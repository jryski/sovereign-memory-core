-- ============================================================================
-- SOVEREIGN MEMORY :: SOURCE IMPORT + AUTHORITATIVE CUTOVER
-- Target: Postgres 15+ / Supabase. Run after sql/01_core.sql.
--
-- Purpose:
--   Generic contract for importing from prior sources such as AI conversation
--   exports, file wikis, notes exports, row-like memory stores, spreadsheets,
--   SQL tables, or another Sovereign Memory deployment.
--
-- Design rules:
--   1. Preserve raw source evidence before normalization.
--   2. Manifest every source item before import/cutover.
--   3. Separate adapter suggestions from confirmed truth.
--   4. Treat semantic/vector indexes as derived cache, never canon.
--   5. Do not assume any one prior source system.
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---- enums -----------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname='source_batch_status') then
    create type source_batch_status as enum (
      'open',          -- accepting staged source items
      'frozen',        -- hard freeze or watermark recorded
      'ready',         -- readiness checks pass or are waived
      'cutover',       -- target store declared authoritative for this batch
      'rolled_back',   -- planned rollback path used
      'abandoned'      -- no longer part of active migration
    );
  end if;

  if not exists (select 1 from pg_type where typname='source_item_action') then
    create type source_item_action as enum ('import','hold','exclude','evidence');
  end if;

  if not exists (select 1 from pg_type where typname='source_target_zone') then
    create type source_target_zone as enum ('HOUSE','VAULT','HOLD','EVIDENCE');
  end if;

  if not exists (select 1 from pg_type where typname='source_review_state') then
    create type source_review_state as enum (
      'unreviewed',
      'needs_review',
      'approved',
      'waived',
      'rejected'
    );
  end if;

  if not exists (select 1 from pg_type where typname='cutover_probe_severity') then
    create type cutover_probe_severity as enum ('critical','normal','informational');
  end if;
end $$;

-- ---- source registry --------------------------------------------------------
create table if not exists source_systems (
  id              uuid primary key default gen_random_uuid(),
  source_key      text not null unique,
  display_name    text not null,
  source_type     text not null, -- ai-export | file-wiki | notes | spreadsheet | sql | memory-store | other
  adapter_name    text,
  adapter_version text,
  description     text,
  owner           text not null default 'shared', -- optional source-scope label; canonical target rows enforce ownership
  visibility      text not null default 'shared' check (visibility in ('shared','private')),
  active          boolean not null default true,
  metadata        jsonb not null default '{}',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint source_system_shared_not_private check (not (owner='shared' and visibility='private'))
);

create index if not exists idx_source_systems_active on source_systems(active, source_type);

-- ---- import batches / freeze-watermark -------------------------------------
create table if not exists source_import_batches (
  id                    uuid primary key default gen_random_uuid(),
  source_system_id       uuid not null references source_systems(id),
  batch_key              text not null,
  status                 source_batch_status not null default 'open',
  export_started_at      timestamptz,
  export_completed_at    timestamptz,
  frozen_at              timestamptz,
  frozen_by              text references trusted_agents(agent_id),
  freeze_note            text,
  watermark              jsonb not null default '{}', -- counts, max timestamps, source sequence, export hash, etc.
  source_item_count      integer check (source_item_count is null or source_item_count >= 0),
  exported_item_count    integer check (exported_item_count is null or exported_item_count >= 0),
  payload_hash_algorithm text not null default 'sha256',
  package_checksum       text,
  package_location       text,
  created_by             text references trusted_agents(agent_id),
  metadata               jsonb not null default '{}',
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  unique (source_system_id, batch_key)
);

create index if not exists idx_source_import_batches_status on source_import_batches(status, created_at desc);
create index if not exists idx_source_import_batches_source on source_import_batches(source_system_id, created_at desc);

-- ---- source items and raw-payload evidence ---------------------------------
create table if not exists source_items (
  id                   uuid primary key default gen_random_uuid(),
  batch_id             uuid not null references source_import_batches(id) on delete cascade,
  source_item_key      text not null, -- source row id, path, conversation id, or stable adapter key
  source_container     text,          -- file path, project name, table name, folder, export member
  source_kind          text,          -- conversation | page | row | note | event | message | file | other
  source_created_at    timestamptz,
  source_updated_at    timestamptz,
  source_author        text,
  content_type         text,
  title                text,
  payload_hash         text not null,
  payload_size_bytes   bigint check (payload_size_bytes is null or payload_size_bytes >= 0),
  raw_payload_location text,
  source_ref           text,
  metadata             jsonb not null default '{}',
  created_at           timestamptz not null default now(),
  unique (batch_id, source_item_key)
);

create index if not exists idx_source_items_batch on source_items(batch_id);
create index if not exists idx_source_items_hash on source_items(payload_hash);
create index if not exists idx_source_items_kind on source_items(source_kind);

create table if not exists source_payload_evidence (
  id                  uuid primary key default gen_random_uuid(),
  source_item_id      uuid not null references source_items(id) on delete cascade,
  evidence_kind       text not null check (evidence_kind in ('raw_payload','export_file','attachment','checksum','note')),
  location            text,
  payload_hash        text,
  hash_algorithm      text not null default 'sha256',
  size_bytes          bigint check (size_bytes is null or size_bytes >= 0),
  content_preview     text,
  metadata            jsonb not null default '{}',
  created_at          timestamptz not null default now()
);

create index if not exists idx_source_payload_evidence_item on source_payload_evidence(source_item_id);
create unique index if not exists source_payload_evidence_natural_key
  on source_payload_evidence(source_item_id, evidence_kind, coalesce(location,''), coalesce(payload_hash,''));

-- ---- manifest decisions -----------------------------------------------------
create table if not exists source_manifest (
  id                         uuid primary key default gen_random_uuid(),
  source_item_id              uuid not null references source_items(id) on delete cascade,
  manifest_key                text not null default 'item', -- stable adapter key for one source item -> many candidates
  action                      source_item_action not null default 'hold',
  target_zone                 source_target_zone not null default 'HOLD',
  review_state                source_review_state not null default 'unreviewed',
  target_table                text, -- memories | wiki_pages | vault table | evidence table | external
  target_id                   uuid,
  topic_key                   text,
  workstream                  text,
  suggested_title             text,
  suggested_summary           text,
  suggested_content           text,
  suggestion_confidence       numeric,
  sensitivity                 text,
  preservation_class          text,
  custodian                   text,
  subject_ref                 text,
  lifecycle_status            text,
  exclusion_reason            text,
  transformation_version      text,
  source_payload_hash_at_review text,
  reviewed_by                 text references trusted_agents(agent_id),
  reviewed_at                 timestamptz,
  review_notes                text,
  metadata                    jsonb not null default '{}',
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  unique (source_item_id, manifest_key),
  constraint source_manifest_action_zone check (
    (action='import' and target_zone in ('HOUSE','VAULT')) or
    (action='hold' and target_zone='HOLD') or
    (action='exclude' and target_zone='EVIDENCE') or
    (action='evidence' and target_zone='EVIDENCE')
  ),
  constraint source_manifest_review_required_target check (
    not (review_state='approved' and action='import' and target_table is null)
  )
);

create index if not exists idx_source_manifest_action_review on source_manifest(action, review_state);
create index if not exists idx_source_manifest_item on source_manifest(source_item_id);
create index if not exists idx_source_manifest_zone on source_manifest(target_zone);
create index if not exists idx_source_manifest_topic on source_manifest(topic_key);

-- ---- updated_at maintenance -------------------------------------------------
drop trigger if exists trg_source_systems_updated on source_systems;
create trigger trg_source_systems_updated before update on source_systems
  for each row execute function set_updated_at();

drop trigger if exists trg_source_import_batches_updated on source_import_batches;
create trigger trg_source_import_batches_updated before update on source_import_batches
  for each row execute function set_updated_at();

drop trigger if exists trg_source_manifest_updated on source_manifest;
create trigger trg_source_manifest_updated before update on source_manifest
  for each row execute function set_updated_at();

-- ---- helper functions --------------------------------------------------------
create or replace function source_freeze_batch(
  p_batch_id uuid,
  p_agent text,
  p_watermark jsonb default '{}'::jsonb,
  p_note text default null
) returns text
language plpgsql security definer set search_path to 'public'
as $$
begin
  if not exists (select 1 from trusted_agents where agent_id=p_agent and active) then
    raise exception 'source_freeze_batch: unknown/inactive agent %', p_agent;
  end if;

  update source_import_batches
     set status='frozen', frozen_at=now(), frozen_by=p_agent,
         watermark=coalesce(p_watermark,'{}'::jsonb), freeze_note=p_note
   where id=p_batch_id and status in ('open','frozen');

  if not found then
    raise exception 'source_freeze_batch: batch % not found or not freezable', p_batch_id;
  end if;

  return 'frozen';
end; $$;

create or replace function source_manifest_payload_drift(p_batch_id uuid)
returns table(source_manifest_id uuid, source_item_id uuid, source_item_key text, manifest_key text, reviewed_hash text, current_hash text, review_state source_review_state)
language sql stable security definer set search_path to 'public'
as $$
  select sm.id, si.id, si.source_item_key, sm.manifest_key, sm.source_payload_hash_at_review, si.payload_hash, sm.review_state
  from source_manifest sm
  join source_items si on si.id = sm.source_item_id
  where si.batch_id = p_batch_id
    and sm.source_payload_hash_at_review is not null
    and sm.source_payload_hash_at_review <> si.payload_hash;
$$;

create or replace function source_mark_batch_ready(p_batch_id uuid, p_agent text)
returns text
language plpgsql security definer set search_path to 'public'
as $$
declare v_blockers int;
begin
  if not exists (select 1 from trusted_agents where agent_id=p_agent and active) then
    raise exception 'source_mark_batch_ready: unknown/inactive agent %', p_agent;
  end if;

  select count(*) into v_blockers
  from source_readiness
  where batch_id=p_batch_id and severity='blocker' and state='fail';

  if v_blockers > 0 then
    raise exception 'source_mark_batch_ready: batch % has % blocker(s)', p_batch_id, v_blockers;
  end if;

  update source_import_batches set status='ready' where id=p_batch_id and status in ('frozen','ready');
  if not found then
    raise exception 'source_mark_batch_ready: batch % not found or not frozen', p_batch_id;
  end if;

  return 'ready';
end; $$;

-- ---- readiness and review views --------------------------------------------
create or replace view source_manifest_review_queue with (security_invoker=true) as
  select
    sib.id as batch_id,
    ss.source_key,
    sib.batch_key,
    si.id as source_item_id,
    si.source_item_key,
    sm.id as source_manifest_id,
    sm.manifest_key,
    si.source_container,
    si.title,
    sm.action,
    sm.target_zone,
    sm.review_state,
    sm.suggestion_confidence,
    sm.sensitivity,
    sm.review_notes,
    si.created_at as staged_at
  from source_manifest sm
  join source_items si on si.id = sm.source_item_id
  join source_import_batches sib on sib.id = si.batch_id
  join source_systems ss on ss.id = sib.source_system_id
  where sm.review_state in ('unreviewed','needs_review')
     or (sm.action='hold' and sm.review_state not in ('waived','rejected'))
  order by si.created_at asc, sm.manifest_key asc;

create or replace view source_readiness with (security_invoker=true) as
  with batches as (
    select b.id as batch_id, ss.source_key, b.batch_key, b.status,
           b.source_item_count, b.exported_item_count
    from source_import_batches b
    join source_systems ss on ss.id=b.source_system_id
  ), counts as (
    select b.batch_id,
      (select count(*) from source_items si where si.batch_id=b.batch_id) as staged_items,
      (select count(*) from source_items si
        where si.batch_id=b.batch_id
          and not exists (select 1 from source_manifest sm where sm.source_item_id=si.id)) as unmanifested_items,
      (select count(*) from source_manifest sm join source_items si on si.id=sm.source_item_id
        where si.batch_id=b.batch_id and sm.review_state in ('unreviewed','needs_review')) as review_pending,
      (select count(*) from source_manifest sm join source_items si on si.id=sm.source_item_id
        where si.batch_id=b.batch_id and sm.action='hold' and sm.review_state not in ('waived','rejected')) as unwaived_hold,
      (select count(*) from source_manifest_payload_drift(b.batch_id)) as payload_drift,
      (select count(*) from source_manifest sm join source_items si on si.id=sm.source_item_id
        where si.batch_id=b.batch_id and sm.action='import' and sm.review_state='approved' and sm.target_table is null) as approved_import_without_target
    from batches b
  )
  select batch_id, source_key, batch_key, 'batch_frozen' as check_key,
         case when status in ('frozen','ready','cutover') then 'pass' else 'fail' end as state,
         'blocker' as severity,
         'Freeze or watermark the source before declaring readiness.' as remediation
  from batches
  union all
  select b.batch_id, b.source_key, b.batch_key, 'expected_counts_match',
         case when b.source_item_count is null or b.exported_item_count is null then 'warn'
              when b.source_item_count = b.exported_item_count and b.exported_item_count = c.staged_items then 'pass'
              else 'fail' end,
         case when b.source_item_count is null or b.exported_item_count is null then 'warning' else 'blocker' end,
         'Record expected source/export counts and stage every exported item.'
  from batches b join counts c using (batch_id)
  union all
  select b.batch_id, b.source_key, b.batch_key, 'no_unmanifested_items',
         case when c.unmanifested_items=0 then 'pass' else 'fail' end,
         'blocker',
         'Create at least one manifest row for every staged source item, even if the item is excluded.'
  from batches b join counts c using (batch_id)
  union all
  select b.batch_id, b.source_key, b.batch_key, 'review_queue_clear_or_waived',
         case when c.review_pending=0 then 'pass' else 'fail' end,
         'blocker',
         'Review or waive all unreviewed/needs-review manifest rows.'
  from batches b join counts c using (batch_id)
  union all
  select b.batch_id, b.source_key, b.batch_key, 'hold_rows_waived',
         case when c.unwaived_hold=0 then 'pass' else 'fail' end,
         'blocker',
         'HOLD rows must be explicitly waived or resolved before cutover.'
  from batches b join counts c using (batch_id)
  union all
  select b.batch_id, b.source_key, b.batch_key, 'no_payload_drift_after_review',
         case when c.payload_drift=0 then 'pass' else 'fail' end,
         'blocker',
         'Re-review manifest rows whose source payload hash changed.'
  from batches b join counts c using (batch_id)
  union all
  select b.batch_id, b.source_key, b.batch_key, 'approved_imports_have_targets',
         case when c.approved_import_without_target=0 then 'pass' else 'fail' end,
         'blocker',
         'Approved imports must name their target table before cutover.'
  from batches b join counts c using (batch_id);

-- ---- cutover probes ----------------------------------------------------------
create table if not exists cutover_probes (
  id                uuid primary key default gen_random_uuid(),
  batch_id          uuid references source_import_batches(id) on delete cascade,
  probe_key         text not null,
  probe_type        text not null, -- fact | project-state | stale-avoidance | provenance | sensitive-boundary | evidence | other
  severity          cutover_probe_severity not null default 'normal',
  prompt            text not null,
  expect_topic_key  text,
  expect_substring  text,
  avoid_substring   text,
  expected_source_item_id uuid references source_items(id),
  active            boolean not null default true,
  metadata          jsonb not null default '{}',
  created_at        timestamptz not null default now(),
  unique (batch_id, probe_key)
);

create index if not exists idx_cutover_probes_batch on cutover_probes(batch_id, active, severity);

create table if not exists cutover_runs (
  id              uuid primary key default gen_random_uuid(),
  probe_id        uuid not null references cutover_probes(id) on delete cascade,
  run_at          timestamptz not null default now(),
  runner_agent    text references trusted_agents(agent_id),
  matched         boolean not null default false,
  top_distance    numeric,
  observed_answer text,
  evidence_ref    text,
  notes           text,
  metadata        jsonb not null default '{}'
);

create index if not exists idx_cutover_runs_probe_latest on cutover_runs(probe_id, run_at desc);

create or replace view cutover_scorecard with (security_invoker=true) as
  with latest as (
    select distinct on (cr.probe_id)
      cr.probe_id, cr.run_at, cr.matched, cr.top_distance
    from cutover_runs cr
    order by cr.probe_id, cr.run_at desc
  )
  select
    cp.batch_id,
    count(cp.id) filter (where cp.active) as probes_defined,
    count(l.probe_id) as probes_run,
    count(l.probe_id) filter (where l.matched) as probes_passed,
    count(l.probe_id) filter (where not l.matched and cp.severity='critical') as critical_misses,
    count(l.probe_id) filter (where not l.matched and cp.severity='normal') as normal_misses,
    case when count(cp.id) filter (where cp.active) = 0 then 0
         else round((count(l.probe_id) filter (where l.matched))::numeric
                    / nullif(count(cp.id) filter (where cp.active),0) * 100, 2) end as pass_pct,
    avg(l.top_distance) filter (where l.top_distance is not null) as avg_hit_distance,
    max(l.run_at) as latest_run_at
  from cutover_probes cp
  left join latest l on l.probe_id=cp.id
  where cp.active
  group by cp.batch_id;

-- ---- grant perimeter ---------------------------------------------------------
revoke all on source_systems from public;
revoke all on source_import_batches from public;
revoke all on source_items from public;
revoke all on source_payload_evidence from public;
revoke all on source_manifest from public;
revoke all on cutover_probes from public;
revoke all on cutover_runs from public;
revoke all on source_manifest_review_queue from public;
revoke all on source_readiness from public;
revoke all on cutover_scorecard from public;

revoke execute on function source_freeze_batch(uuid,text,jsonb,text) from public;
revoke execute on function source_manifest_payload_drift(uuid) from public;
revoke execute on function source_mark_batch_ready(uuid,text) from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname='anon') then
    revoke all on source_systems from anon;
    revoke all on source_import_batches from anon;
    revoke all on source_items from anon;
    revoke all on source_payload_evidence from anon;
    revoke all on source_manifest from anon;
    revoke all on cutover_probes from anon;
    revoke all on cutover_runs from anon;
    revoke all on source_manifest_review_queue from anon;
    revoke all on source_readiness from anon;
    revoke all on cutover_scorecard from anon;

    revoke execute on function source_freeze_batch(uuid,text,jsonb,text) from anon;
    revoke execute on function source_manifest_payload_drift(uuid) from anon;
    revoke execute on function source_mark_batch_ready(uuid,text) from anon;
  end if;

  if exists (select 1 from pg_roles where rolname='authenticated') then
    revoke all on source_systems from authenticated;
    revoke all on source_import_batches from authenticated;
    revoke all on source_items from authenticated;
    revoke all on source_payload_evidence from authenticated;
    revoke all on source_manifest from authenticated;
    revoke all on cutover_probes from authenticated;
    revoke all on cutover_runs from authenticated;
    revoke all on source_manifest_review_queue from authenticated;
    revoke all on source_readiness from authenticated;
    revoke all on cutover_scorecard from authenticated;

    revoke execute on function source_freeze_batch(uuid,text,jsonb,text) from authenticated;
    revoke execute on function source_manifest_payload_drift(uuid) from authenticated;
    revoke execute on function source_mark_batch_ready(uuid,text) from authenticated;
  end if;
end $$;

-- End of source import contract.
