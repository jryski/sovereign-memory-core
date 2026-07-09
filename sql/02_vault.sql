-- ============================================================================
-- SOVEREIGN MEMORY :: TIER 2 VAULT (optional; run after 01_core.sql)
-- Locked private schemas for identity / health / finance, with:
--   * preserve-then-normalize import (verbatim source + sha256, always)
--   * temporal truth (observed/effective/recorded + status + predecessor chain)
--   * enforced provenance basis + citation on consequential records
--   * an audit change log wired to every domain table
-- Access model: NO grants to anon/authenticated/public on any of these schemas.
-- Only service_role (via PostgREST bypass) and postgres reach this data.
-- ============================================================================

-- ---- schemas ----------------------------------------------------------------
create schema if not exists vault_private;    -- preserved imports + control
create schema if not exists identity_private; -- people, relationships, capabilities
create schema if not exists health_private;   -- per-person health records
create schema if not exists finance_private;  -- accounts, balances, parties
create schema if not exists vault_audit;      -- source links + change log

revoke all on schema vault_private, identity_private, health_private,
              finance_private, vault_audit from public, anon, authenticated;

-- ---- vault_private: preserve-then-normalize ----------------------------------
-- Every import lands VERBATIM here first, with a sha256 of its canonical JSON.
-- Normalized domain rows FK back to their preserved source. Nothing is ever
-- normalized without a preserved original to check against.
create table if not exists vault_private.records (
  id              uuid primary key,
  batch_id        text not null,
  source_project  text not null,
  source_table    text not null,
  source_id       uuid not null,
  record_type     text not null,
  subject_id      text not null,           -- who this is about (stable key)
  custodian       text not null,           -- who is responsible for it
  sensitivity     text not null,           -- e.g. restricted-health / restricted-finance
  workstream      text,
  lifecycle_status text,
  review_state    text,
  source_status   text,
  source_created_at timestamptz,
  source_updated_at timestamptz,
  source_supersedes uuid,
  payload         jsonb not null,          -- the verbatim original
  payload_hash    text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  imported_at     timestamptz not null default now(),
  unique(batch_id, source_project, source_table, source_id)
);

create table if not exists vault_private.import_batches (
  batch_id      text primary key,
  expected_rows integer not null,
  imported_rows integer not null default 0,
  verified_rows integer not null default 0,
  status        text not null default 'prepared',
  created_at    timestamptz not null default now(),
  verified_at   timestamptz
);

create table if not exists vault_private.normalization_queue (
  vault_record_id      uuid primary key references vault_private.records(id),
  proposed_domain      text not null,
  proposed_subject_key text,
  target_table         text,
  normalization_status text not null default 'pending',
  notes                text,
  reviewed_by          text,
  reviewed_at          timestamptz
);

-- ---- identity_private ----------------------------------------------------------
create table if not exists identity_private.person (
  id             uuid primary key default gen_random_uuid(),
  stable_key     text not null unique,     -- e.g. 'example-user'
  legal_name     text not null,
  preferred_name text,
  date_of_birth  date,
  deceased_at    timestamptz,
  status         text not null default 'active' check (status in ('active','deceased','inactive')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create table if not exists identity_private.family_group (
  id          uuid primary key default gen_random_uuid(),
  stable_key  text not null unique,
  display_name text not null,
  created_at  timestamptz not null default now()
);

create table if not exists identity_private.family_member (
  id              uuid primary key default gen_random_uuid(),
  family_group_id uuid not null references identity_private.family_group(id),
  person_id       uuid not null references identity_private.person(id),
  role            text not null check (role in ('adult','child','dependent','caregiver','other')),
  valid_from      date not null default current_date,
  valid_to        date,
  created_at      timestamptz not null default now(),
  check (valid_to is null or valid_to >= valid_from),
  unique(family_group_id, person_id, valid_from)
);

create table if not exists identity_private.relation (
  id              uuid primary key default gen_random_uuid(),
  from_person_id  uuid not null references identity_private.person(id),
  to_person_id    uuid not null references identity_private.person(id),
  relation_type   text not null,
  authority_basis text,                    -- what document/decision grants this
  valid_from      date not null default current_date,
  valid_to        date,
  created_at      timestamptz not null default now(),
  check (from_person_id <> to_person_id),
  check (valid_to is null or valid_to >= valid_from),
  unique(from_person_id, to_person_id, relation_type, valid_from)
);

-- Capability-based access: explicit, scoped, dated, reviewable. Access is a
-- ROW here, never an implication of role or group membership.
create table if not exists identity_private.capability_assignment (
  id                uuid primary key default gen_random_uuid(),
  principal_kind    text not null,         -- 'person' | 'agent'
  principal_key     text not null,         -- 'example-user' | 'example-user-claude'
  domain_name       text not null,         -- 'health' | 'finance' | ...
  capability_name   text not null,         -- 'read' | 'write' | 'approve'
  subject_person_id uuid references identity_private.person(id),  -- scope, null = all
  valid_from        timestamptz not null default now(),
  valid_to          timestamptz,
  assigned_by       text not null,
  reason            text,
  created_at        timestamptz not null default now(),
  check (valid_to is null or valid_to >= valid_from)
);

-- ---- health_private: temporal truth ------------------------------------------
create table if not exists health_private.patient (
  id         uuid primary key default gen_random_uuid(),
  person_id  uuid not null unique references identity_private.person(id),
  status     text not null default 'active',
  created_at timestamptz not null default now()
);

create table if not exists health_private.record (
  id                   uuid primary key default gen_random_uuid(),
  patient_id           uuid not null references health_private.patient(id),
  record_type          text not null,
  recorded_at          timestamptz not null default now(),   -- when WE learned it
  observed_at          timestamptz,                          -- when it happened
  effective_from       timestamptz not null default now(),   -- truth window start
  effective_to         timestamptz,                          -- truth window end
  record_status        text not null default 'current'
    check (record_status in ('proposed','current','superseded','retracted','entered_in_error')),
  predecessor_id       uuid references health_private.record(id),
  data                 jsonb not null default '{}',
  provenance_record_id uuid references vault_private.records(id),
  provenance_basis     text not null default 'imported_artifact'
    check (provenance_basis in ('human_direct','decision_record','imported_artifact','source_document')),
  citation             text,
  confidence           numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  check (effective_to is null or effective_to >= effective_from),
  -- facts need sources: citation required unless the human said it directly
  check (provenance_basis='human_direct' or nullif(citation,'') is not null)
);

-- ---- finance_private ------------------------------------------------------------
create table if not exists finance_private.account (
  id            uuid primary key default gen_random_uuid(),
  stable_key    text not null unique,
  institution   text not null,
  account_label text not null,
  account_type  text not null,
  last_four     text,
  opened_at     date,
  closed_at     date,
  status        text not null default 'active',
  created_at    timestamptz not null default now()
);

create table if not exists finance_private.party_link (
  id         uuid primary key default gen_random_uuid(),
  account_id uuid not null references finance_private.account(id),
  person_id  uuid not null references identity_private.person(id),
  role_name  text not null,               -- owner | joint | authorized-user | ...
  valid_from date not null default current_date,
  valid_to   date,
  created_at timestamptz not null default now()
);

create table if not exists finance_private.balance_snapshot (
  id                   uuid primary key default gen_random_uuid(),
  account_id           uuid not null references finance_private.account(id),
  amount               numeric not null,
  currency             text not null default 'USD',
  observed_at          timestamptz not null,
  recorded_at          timestamptz not null default now(),
  predecessor_id       uuid references finance_private.balance_snapshot(id),
  provenance_record_id uuid references vault_private.records(id),
  provenance_basis     text not null
    check (provenance_basis in ('human_direct','decision_record','imported_artifact','source_document')),
  citation             text,
  confidence           numeric
);

create table if not exists finance_private.beneficiary_link (
  id            uuid primary key default gen_random_uuid(),
  account_id    uuid references finance_private.account(id),
  person_id     uuid not null references identity_private.person(id),
  role_name     text not null,
  share_percent numeric,
  valid_from    date not null default current_date,
  valid_to      date,
  recorded_at   timestamptz not null default now()
);

-- ---- vault_audit ------------------------------------------------------------------
create table if not exists vault_audit.source_link (
  id              uuid primary key default gen_random_uuid(),
  vault_record_id uuid not null unique references vault_private.records(id),
  source_project  text not null,
  source_table    text not null,
  source_id       uuid not null,
  payload_hash    text not null,
  linked_at       timestamptz not null default now()
);

create table if not exists vault_audit.change_log (
  id             uuid primary key default gen_random_uuid(),
  occurred_at    timestamptz not null default now(),
  principal_key  text not null,
  action_name    text not null,
  domain_name    text not null,
  object_table   text not null,
  object_id      uuid,
  source_link_id uuid references vault_audit.source_link(id),
  details        jsonb not null default '{}'
);

-- Trigger: log every insert/update/delete on domain tables. KEYS ONLY in
-- details, never payload duplication (the audit row must not become a second
-- copy of sensitive data).
create or replace function vault_audit.log_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare v_row jsonb; v_id uuid;
begin
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  begin v_id := (v_row->>'id')::uuid; exception when others then v_id := null; end;
  insert into vault_audit.change_log(principal_key, action_name, domain_name, object_table, object_id, details)
  values (current_user, lower(tg_op), tg_table_schema,
          tg_table_schema || '.' || tg_table_name, v_id,
          jsonb_build_object('columns',
            (select coalesce(jsonb_agg(k.key order by k.key),'[]'::jsonb)
             from jsonb_object_keys(v_row) as k(key))));
  if tg_op = 'DELETE' then return old; else return new; end if;
end $$;
revoke execute on function vault_audit.log_change() from public, anon, authenticated;

do $$
declare t record;
begin
  for t in
    select n.nspname, c.relname
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where c.relkind = 'r'
      and n.nspname in ('health_private','identity_private','finance_private','vault_private')
  loop
    execute format('drop trigger if exists vault_change_log_v1 on %I.%I', t.nspname, t.relname);
    execute format('create trigger vault_change_log_v1 after insert or update or delete on %I.%I
                    for each row execute function vault_audit.log_change()', t.nspname, t.relname);
  end loop;
end $$;

-- ---- lock everything -----------------------------------------------------------
revoke all on all tables    in schema vault_private, identity_private, health_private,
                                      finance_private, vault_audit from public, anon, authenticated;
revoke all on all sequences in schema vault_private, identity_private, health_private,
                                      finance_private, vault_audit from public, anon, authenticated;
