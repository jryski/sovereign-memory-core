-- ============================================================================
-- SOVEREIGN MEMORY :: HUMAN APPROVAL REQUESTS
-- Target: PostgreSQL 15+. Apply after sql/01_core.sql on a disposable database.
--
-- This is an additive contract. It is not part of the v0.3-alpha C2 migration
-- list and it does not replace public.promote_memory. Objects live in schema
-- human_approval so they stay outside the reviewed public SECURITY DEFINER
-- inventory.
--
-- Proposal is separate from authorization. An agent login may stage a bounded
-- memory promotion. Approval and rejection derive the acting principal and
-- assurance from the current database login plus human_approval.trust_anchors.
-- A client-supplied acting_principal is not an argument and is not consulted.
-- The reference anchor binds login human_approval_reviewer to principal
-- example-user for Primary Users. Deployments replace that anchor; this file
-- does not ship a hosted review UI.
-- ============================================================================

do $$
begin
  if to_regclass('public.memories') is null then
    raise exception 'human_approval: public.memories is required; apply sql/01_core.sql first';
  end if;
  if to_regprocedure('extensions.digest(bytea,text)') is null
     or to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception 'human_approval: pgcrypto in schema extensions is required';
  end if;
end $$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname='human_approval_agent') then
    create role human_approval_agent
      nologin nosuperuser nocreatedb nocreaterole noinherit nobypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname='human_approval_reviewer') then
    create role human_approval_reviewer
      nologin nosuperuser nocreatedb nocreaterole noinherit nobypassrls;
  end if;
end $$;

create schema if not exists human_approval;

comment on schema human_approval is
  'Proposal and authenticated human authorization for authority-bearing mutations. The authorizer is the trusted database login bound in human_approval.trust_anchors, not a client-supplied acting principal. The reference binding is for Primary Users.';

revoke all on schema human_approval from public;
alter default privileges for role postgres in schema human_approval
  revoke execute on functions from public;
alter default privileges for role postgres in schema human_approval
  revoke all on tables from public;

create table if not exists human_approval.operations (
  operation_kind text primary key check (operation_kind ~ '^[a-z][a-z0-9_]{0,63}$'),
  target_schema text not null check (target_schema = 'public'),
  target_table text not null check (target_table ~ '^[a-z][a-z0-9_]{0,63}$'),
  description text not null check (description ~ '[^[:space:]]'),
  active boolean not null default true
);

create table if not exists human_approval.trust_anchors (
  authenticator_role text primary key check (authenticator_role ~ '^[a-z][a-z0-9_]{0,63}$'),
  principal text not null check (principal ~ '[^[:space:]]' and char_length(principal) <= 200),
  assurance_level text not null check (assurance_level ~ '[^[:space:]]' and char_length(assurance_level) <= 200),
  active boolean not null default true
);

create table if not exists human_approval.sessions (
  id uuid primary key default gen_random_uuid(),
  authenticator_role text not null,
  principal text not null,
  assurance_level text not null,
  backend_pid integer not null check (backend_pid > 0),
  backend_start timestamptz not null,
  opened_at timestamptz not null default pg_catalog.clock_timestamp(),
  expires_at timestamptz not null,
  closed_at timestamptz,
  check (expires_at > opened_at),
  check (closed_at is null or closed_at >= opened_at)
);

create unique index if not exists sessions_one_open_backend_uq
  on human_approval.sessions (backend_pid, backend_start)
  where closed_at is null;

create table if not exists human_approval.requests (
  id uuid primary key default gen_random_uuid(),
  contract_version text not null default 'human-approval-request/0.1'
    check (contract_version = 'human-approval-request/0.1'),
  operation_kind text not null references human_approval.operations(operation_kind),
  target_schema text not null check (target_schema = 'public'),
  target_table text not null,
  target_id uuid not null,
  expected_version text not null check (expected_version ~ '^[0-9a-f]{64}$'),
  expected_state jsonb not null,
  proposed_transition jsonb not null,
  proposer_session_user text not null check (proposer_session_user ~ '[^[:space:]]'),
  proposer_label text,
  reason text not null check (reason ~ '[^[:space:]]'),
  evidence jsonb not null,
  decision_nonce text not null unique check (decision_nonce ~ '^[0-9a-f]{64}$'),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  expires_at timestamptz not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  resolved_at timestamptz,
  receipt_id uuid unique,
  check (
    (status = 'pending' and resolved_at is null and receipt_id is null)
    or (status in ('approved','rejected') and resolved_at is not null and receipt_id is not null)
  )
);

create index if not exists requests_pending_idx
  on human_approval.requests (expires_at, created_at)
  where status = 'pending';

create table if not exists human_approval.receipts (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references human_approval.requests(id),
  decision text not null check (decision in ('approved','rejected')),
  operation_kind text not null,
  proposer_session_user text not null,
  proposer_label text,
  authorizer_principal text not null check (authorizer_principal ~ '[^[:space:]]'),
  authorizer_assurance text not null check (authorizer_assurance ~ '[^[:space:]]'),
  authorizer_role text not null check (authorizer_role ~ '[^[:space:]]'),
  evidence jsonb not null,
  proposal_reason text not null,
  decision_reason text not null check (decision_reason ~ '[^[:space:]]'),
  prior_state jsonb not null,
  resulting_state jsonb not null,
  decision_nonce text not null unique check (decision_nonce ~ '^[0-9a-f]{64}$'),
  decided_at timestamptz not null default pg_catalog.clock_timestamp()
);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'requests_receipt_id_fkey'
      and conrelid = 'human_approval.requests'::regclass
  ) then
    alter table human_approval.requests
      add constraint requests_receipt_id_fkey
      foreign key (receipt_id) references human_approval.receipts(id) deferrable initially deferred;
  end if;
end $$;

comment on table human_approval.operations is
  'Reusable authority-bearing operation envelope. memory_promotion is the first executable kind.';
comment on table human_approval.trust_anchors is
  'Operator-administered map from an authenticated database login to a principal and assurance level.';
comment on table human_approval.sessions is
  'Open human session bound to this backend. Principal and assurance are stamped from the trust anchor, not from the client.';
comment on table human_approval.requests is
  'Bounded proposal. Staging does not perform the authority-bearing transition.';
comment on table human_approval.receipts is
  'Append-only decision receipt. Authorizer, assurance, proposal, evidence, reasons, prior state, resulting state, and timestamp commit with the decision.';

alter table human_approval.operations enable row level security;
alter table human_approval.operations force row level security;
alter table human_approval.trust_anchors enable row level security;
alter table human_approval.trust_anchors force row level security;
alter table human_approval.sessions enable row level security;
alter table human_approval.sessions force row level security;
alter table human_approval.requests enable row level security;
alter table human_approval.requests force row level security;
alter table human_approval.receipts enable row level security;
alter table human_approval.receipts force row level security;

revoke all on human_approval.operations, human_approval.trust_anchors,
  human_approval.sessions, human_approval.requests, human_approval.receipts
  from public;

create or replace function human_approval.memory_version(
  p_status text, p_updated_at timestamptz, p_content text
) returns text
language sql immutable
set search_path to 'pg_catalog', 'pg_temp'
as $$
  select encode(extensions.digest(convert_to(
    coalesce(p_status,'') || '|' ||
    coalesce(to_char(p_updated_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'), '') || '|' ||
    coalesce(p_content,''),
    'UTF8'), 'sha256'), 'hex');
$$;

create or replace function human_approval.current_trusted_session()
returns human_approval.sessions
language plpgsql stable security definer
set search_path to 'pg_catalog', 'pg_temp'
as $$
declare
  v_row human_approval.sessions;
  v_backend_start timestamptz;
begin
  select a.backend_start into v_backend_start
  from pg_catalog.pg_stat_activity a
  where a.pid = pg_catalog.pg_backend_pid();
  if v_backend_start is null then
    return null;
  end if;
  select s.* into v_row
  from human_approval.sessions s
  join human_approval.trust_anchors t
    on t.authenticator_role = s.authenticator_role
   and t.active
   and t.principal = s.principal
   and t.assurance_level = s.assurance_level
  where s.authenticator_role = session_user::text
    and s.backend_pid = pg_catalog.pg_backend_pid()
    and s.backend_start = v_backend_start
    and s.closed_at is null
    and s.expires_at > pg_catalog.clock_timestamp()
  order by s.opened_at desc
  limit 1;
  if not found then
    return null;
  end if;
  return v_row;
end;
$$;

create or replace function human_approval.guard_registry_write()
returns trigger
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $$
begin
  if coalesce(current_setting('human_approval.registry_write', true), '') <> 'on' then
    raise exception 'human_approval: registry mutation is not permitted';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function human_approval.guard_session_write()
returns trigger
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $$
declare
  v_principal text;
  v_assurance text;
  v_backend_start timestamptz;
begin
  if tg_op = 'DELETE' then
    raise exception 'human_approval: session delete is not permitted';
  end if;
  if coalesce(current_setting('human_approval.write', true), '') <> 'on' then
    raise exception 'human_approval: direct session mutation is not permitted';
  end if;
  if tg_op = 'UPDATE' then
    if new.authenticator_role is distinct from old.authenticator_role
       or new.principal is distinct from old.principal
       or new.assurance_level is distinct from old.assurance_level
       or new.backend_pid is distinct from old.backend_pid
       or new.backend_start is distinct from old.backend_start
       or new.opened_at is distinct from old.opened_at
       or new.expires_at is distinct from old.expires_at
       or new.id is distinct from old.id then
      raise exception 'human_approval: session identity is immutable';
    end if;
    return new;
  end if;
  select t.principal, t.assurance_level into v_principal, v_assurance
  from human_approval.trust_anchors t
  where t.authenticator_role = session_user::text
    and t.active;
  if not found then
    raise exception 'human_approval: current login is not a trusted human authenticator';
  end if;
  select a.backend_start into v_backend_start
  from pg_catalog.pg_stat_activity a
  where a.pid = pg_catalog.pg_backend_pid();
  if v_backend_start is null then
    raise exception 'human_approval: backend identity is unavailable';
  end if;
  new.authenticator_role := session_user::text;
  new.principal := v_principal;
  new.assurance_level := v_assurance;
  new.backend_pid := pg_catalog.pg_backend_pid();
  new.backend_start := v_backend_start;
  new.opened_at := pg_catalog.clock_timestamp();
  new.expires_at := pg_catalog.clock_timestamp() + interval '15 minutes';
  new.closed_at := null;
  return new;
end;
$$;

create or replace function human_approval.guard_request_write()
returns trigger
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'human_approval: request delete is not permitted';
  end if;
  if coalesce(current_setting('human_approval.write', true), '') <> 'on' then
    raise exception 'human_approval: direct request mutation is not permitted';
  end if;
  if tg_op = 'INSERT' then
    new.proposer_session_user := session_user::text;
    new.status := 'pending';
    new.resolved_at := null;
    new.receipt_id := null;
    new.created_at := pg_catalog.clock_timestamp();
    new.contract_version := 'human-approval-request/0.1';
    return new;
  end if;
  if old.status <> 'pending' or new.status not in ('approved','rejected') then
    raise exception 'human_approval: already resolved';
  end if;
  if new.operation_kind is distinct from old.operation_kind
     or new.target_schema is distinct from old.target_schema
     or new.target_table is distinct from old.target_table
     or new.target_id is distinct from old.target_id
     or new.expected_version is distinct from old.expected_version
     or new.expected_state is distinct from old.expected_state
     or new.proposed_transition is distinct from old.proposed_transition
     or new.proposer_session_user is distinct from old.proposer_session_user
     or new.proposer_label is distinct from old.proposer_label
     or new.reason is distinct from old.reason
     or new.evidence is distinct from old.evidence
     or new.decision_nonce is distinct from old.decision_nonce
     or new.contract_version is distinct from old.contract_version
     or new.created_at is distinct from old.created_at
     or new.expires_at is distinct from old.expires_at
     or new.id is distinct from old.id then
    raise exception 'human_approval: proposal fields are immutable';
  end if;
  if new.receipt_id is null or new.resolved_at is null then
    raise exception 'human_approval: resolution requires a receipt';
  end if;
  return new;
end;
$$;

create or replace function human_approval.guard_receipt_write()
returns trigger
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $$
declare
  v_session human_approval.sessions;
  v_request human_approval.requests;
begin
  if tg_op <> 'INSERT' then
    raise exception 'human_approval: receipts are append-only';
  end if;
  if coalesce(current_setting('human_approval.write', true), '') <> 'on' then
    raise exception 'human_approval: direct receipt mutation is not permitted';
  end if;
  v_session := human_approval.current_trusted_session();
  if v_session.id is null then
    raise exception 'human_approval: trusted human session required';
  end if;
  select * into v_request from human_approval.requests where id = new.request_id;
  if not found then
    raise exception 'human_approval: missing request';
  end if;
  if new.decision not in ('approved','rejected') then
    raise exception 'human_approval: unsupported operation';
  end if;
  if new.decision_reason is null or new.decision_reason !~ '[^[:space:]]' then
    raise exception 'human_approval: decision reason must contain non-whitespace';
  end if;
  if new.prior_state is null or jsonb_typeof(new.prior_state) <> 'object'
     or new.resulting_state is null or jsonb_typeof(new.resulting_state) <> 'object' then
    raise exception 'human_approval: receipt state binding is required';
  end if;
  new.operation_kind := v_request.operation_kind;
  new.proposer_session_user := v_request.proposer_session_user;
  new.proposer_label := v_request.proposer_label;
  new.authorizer_principal := v_session.principal;
  new.authorizer_assurance := v_session.assurance_level;
  new.authorizer_role := v_session.authenticator_role;
  new.evidence := v_request.evidence;
  new.proposal_reason := v_request.reason;
  new.decision_nonce := v_request.decision_nonce;
  new.decided_at := pg_catalog.clock_timestamp();
  return new;
end;
$$;

create or replace function human_approval.guard_truncate()
returns trigger
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $$
begin
  raise exception 'human_approval: truncate is not permitted';
end;
$$;

drop trigger if exists trg_operations_registry on human_approval.operations;
create trigger trg_operations_registry
before insert or update or delete on human_approval.operations
for each row execute function human_approval.guard_registry_write();
drop trigger if exists trg_operations_truncate on human_approval.operations;
create trigger trg_operations_truncate
before truncate on human_approval.operations
for each statement execute function human_approval.guard_truncate();

drop trigger if exists trg_trust_anchors_registry on human_approval.trust_anchors;
create trigger trg_trust_anchors_registry
before insert or update or delete on human_approval.trust_anchors
for each row execute function human_approval.guard_registry_write();
drop trigger if exists trg_trust_anchors_truncate on human_approval.trust_anchors;
create trigger trg_trust_anchors_truncate
before truncate on human_approval.trust_anchors
for each statement execute function human_approval.guard_truncate();

drop trigger if exists trg_sessions_write on human_approval.sessions;
create trigger trg_sessions_write
before insert or update or delete on human_approval.sessions
for each row execute function human_approval.guard_session_write();
drop trigger if exists trg_sessions_truncate on human_approval.sessions;
create trigger trg_sessions_truncate
before truncate on human_approval.sessions
for each statement execute function human_approval.guard_truncate();

drop trigger if exists trg_requests_write on human_approval.requests;
create trigger trg_requests_write
before insert or update or delete on human_approval.requests
for each row execute function human_approval.guard_request_write();
drop trigger if exists trg_requests_truncate on human_approval.requests;
create trigger trg_requests_truncate
before truncate on human_approval.requests
for each statement execute function human_approval.guard_truncate();

drop trigger if exists trg_receipts_write on human_approval.receipts;
create trigger trg_receipts_write
before insert or update or delete on human_approval.receipts
for each row execute function human_approval.guard_receipt_write();
drop trigger if exists trg_receipts_truncate on human_approval.receipts;
create trigger trg_receipts_truncate
before truncate on human_approval.receipts
for each statement execute function human_approval.guard_truncate();

create or replace function human_approval.request_memory_promotion(
  p_memory_id uuid,
  p_reason text,
  p_evidence jsonb,
  p_expires_at timestamptz default null,
  p_proposer_label text default null
) returns uuid
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $$
declare
  v_memory public.memories;
  v_expires timestamptz;
  v_version text;
  v_id uuid;
  v_nonce text;
begin
  if p_memory_id is null then
    raise exception 'human_approval: memory is required';
  end if;
  if p_reason is null or p_reason !~ '[^[:space:]]' or char_length(p_reason) > 4000 then
    raise exception 'human_approval: reason must contain non-whitespace';
  end if;
  if p_proposer_label is not null
     and (p_proposer_label !~ '[^[:space:]]' or char_length(p_proposer_label) > 200) then
    raise exception 'human_approval: proposer label is not a usable claim';
  end if;
  if p_evidence is null or jsonb_typeof(p_evidence) <> 'array'
     or jsonb_array_length(p_evidence) < 1 or jsonb_array_length(p_evidence) > 20 then
    raise exception 'human_approval: evidence must be a non-empty array';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_evidence) as e(item)
    where jsonb_typeof(e.item) <> 'object'
       or coalesce(e.item->>'ref','') !~ '[^[:space:]]'
       or char_length(e.item->>'ref') > 500
  ) then
    raise exception 'human_approval: evidence ref is required';
  end if;
  if not exists (
    select 1 from human_approval.operations
    where operation_kind = 'memory_promotion' and active
  ) then
    raise exception 'human_approval: unsupported operation';
  end if;
  v_expires := coalesce(p_expires_at, pg_catalog.clock_timestamp() + interval '24 hours');
  if v_expires <= pg_catalog.clock_timestamp()
     or v_expires > pg_catalog.clock_timestamp() + interval '7 days' then
    raise exception 'human_approval: expiry must be in the future and within 7 days';
  end if;
  select * into v_memory from public.memories where id = p_memory_id for share;
  if not found then
    raise exception 'human_approval: missing target';
  end if;
  if v_memory.status::text <> 'proposed' then
    raise exception 'human_approval: memory is not proposed';
  end if;
  v_version := human_approval.memory_version(v_memory.status::text, v_memory.updated_at, v_memory.content);
  v_nonce := encode(extensions.gen_random_bytes(32), 'hex');
  perform set_config('human_approval.write', 'on', true);
  insert into human_approval.requests(
    operation_kind, target_schema, target_table, target_id,
    expected_version, expected_state, proposed_transition,
    proposer_session_user, proposer_label, reason, evidence,
    decision_nonce, expires_at
  ) values (
    'memory_promotion', 'public', 'memories', v_memory.id,
    v_version,
    jsonb_build_object(
      'status', v_memory.status::text,
      'updated_at', v_memory.updated_at,
      'version', v_version
    ),
    jsonb_build_object('from_status','proposed','to_status','active'),
    'client-supplied-proposer',
    p_proposer_label,
    p_reason,
    p_evidence,
    v_nonce,
    v_expires
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function human_approval.pending_human_approval_requests(
  p_operation_kind text default null
) returns table (
  request_id uuid,
  operation_kind text,
  target_schema text,
  target_table text,
  target_id uuid,
  expected_version text,
  expected_state jsonb,
  proposed_transition jsonb,
  proposer_session_user text,
  proposer_label text,
  reason text,
  evidence jsonb,
  decision_nonce text,
  expires_at timestamptz,
  created_at timestamptz
)
language sql stable security definer
set search_path to 'pg_catalog', 'pg_temp'
as $$
  select r.id, r.operation_kind, r.target_schema, r.target_table, r.target_id,
         r.expected_version, r.expected_state, r.proposed_transition,
         r.proposer_session_user, r.proposer_label, r.reason, r.evidence,
         r.decision_nonce, r.expires_at, r.created_at
  from human_approval.requests r
  where r.status = 'pending'
    and r.expires_at > pg_catalog.clock_timestamp()
    and (p_operation_kind is null or r.operation_kind = p_operation_kind)
  order by r.created_at, r.id;
$$;

create or replace function human_approval.open_human_approval_session()
returns uuid
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $$
declare
  v_backend_start timestamptz;
  v_id uuid;
begin
  select a.backend_start into v_backend_start
  from pg_catalog.pg_stat_activity a
  where a.pid = pg_catalog.pg_backend_pid();
  if v_backend_start is null then
    raise exception 'human_approval: backend identity is unavailable';
  end if;
  perform set_config('human_approval.write', 'on', true);
  update human_approval.sessions
  set closed_at = pg_catalog.clock_timestamp()
  where backend_pid = pg_catalog.pg_backend_pid()
    and backend_start = v_backend_start
    and closed_at is null;
  insert into human_approval.sessions(
    authenticator_role, principal, assurance_level, backend_pid, backend_start, expires_at
  ) values (
    'client-supplied-role',
    'client-supplied-principal',
    'client-supplied-assurance',
    1,
    pg_catalog.clock_timestamp(),
    pg_catalog.clock_timestamp() + interval '7 days'
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function human_approval.decide_request(
  p_request_id uuid,
  p_expected_version text,
  p_decision_nonce text,
  p_decision_reason text,
  p_decision text
) returns uuid
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $$
declare
  v_session human_approval.sessions;
  v_request human_approval.requests;
  v_memory public.memories;
  v_live_version text;
  v_new_status text;
  v_new_updated_at timestamptz;
  v_new_content text;
  v_new_version text;
  v_prior jsonb;
  v_resulting jsonb;
  v_receipt_id uuid;
  v_decided_at timestamptz;
begin
  if p_decision not in ('approved','rejected') then
    raise exception 'human_approval: unsupported operation';
  end if;
  if p_decision_reason is null or p_decision_reason !~ '[^[:space:]]'
     or char_length(p_decision_reason) > 4000 then
    raise exception 'human_approval: decision reason must contain non-whitespace';
  end if;
  if p_expected_version is null or p_expected_version !~ '^[0-9a-f]{64}$' then
    raise exception 'human_approval: expected version must be a sha256 hex digest';
  end if;
  if p_decision_nonce is null or p_decision_nonce !~ '^[0-9a-f]{64}$' then
    raise exception 'human_approval: decision nonce must be a sha256 hex digest';
  end if;
  v_session := human_approval.current_trusted_session();
  if v_session.id is null then
    raise exception 'human_approval: trusted human session required';
  end if;
  select * into v_request
  from human_approval.requests
  where id = p_request_id
  for update;
  if not found then
    raise exception 'human_approval: missing request';
  end if;
  if v_request.status <> 'pending' then
    raise exception 'human_approval: already resolved';
  end if;
  if v_request.expires_at <= pg_catalog.clock_timestamp() then
    raise exception 'human_approval: expired';
  end if;
  if p_decision_nonce <> v_request.decision_nonce then
    if exists (
      select 1 from human_approval.receipts where decision_nonce = p_decision_nonce
    ) then
      raise exception 'human_approval: replay';
    end if;
    raise exception 'human_approval: decision nonce mismatch';
  end if;
  if p_expected_version <> v_request.expected_version then
    raise exception 'human_approval: version mismatch';
  end if;
  if v_request.operation_kind <> 'memory_promotion'
     or v_request.target_schema <> 'public'
     or v_request.target_table <> 'memories' then
    raise exception 'human_approval: unsupported operation';
  end if;
  select * into v_memory
  from public.memories
  where id = v_request.target_id
  for update;
  if not found then
    raise exception 'human_approval: missing target';
  end if;
  v_live_version := human_approval.memory_version(
    v_memory.status::text, v_memory.updated_at, v_memory.content
  );
  if v_live_version <> v_request.expected_version or v_memory.status::text <> 'proposed' then
    raise exception 'human_approval: stale target';
  end if;
  v_prior := jsonb_build_object(
    'schema','public',
    'table','memories',
    'id', v_memory.id,
    'status', v_memory.status::text,
    'version', v_live_version,
    'target_mutated', false
  );
  v_receipt_id := gen_random_uuid();
  if p_decision = 'approved' then
    update public.memories
    set status = 'active'::public.knowledge_status,
        metadata = metadata || jsonb_build_object(
          'promoted_at', pg_catalog.clock_timestamp(),
          'promote_note', v_request.reason,
          'promoted_by', v_session.principal,
          'promotion_assurance', v_session.assurance_level,
          'promotion_request_id', v_request.id,
          'promotion_receipt_id', v_receipt_id
        )
    where id = v_memory.id
      and status = 'proposed'::public.knowledge_status
      and human_approval.memory_version(status::text, updated_at, content) = v_request.expected_version
    returning status::text, updated_at, content
    into v_new_status, v_new_updated_at, v_new_content;
    if not found then
      raise exception 'human_approval: stale target';
    end if;
    v_new_version := human_approval.memory_version(v_new_status, v_new_updated_at, v_new_content);
    v_resulting := jsonb_build_object(
      'schema','public',
      'table','memories',
      'id', v_memory.id,
      'status', v_new_status,
      'version', v_new_version,
      'target_mutated', true
    );
  else
    v_resulting := v_prior;
  end if;
  perform set_config('human_approval.write', 'on', true);
  insert into human_approval.receipts(
    id, request_id, decision, operation_kind,
    proposer_session_user, proposer_label,
    authorizer_principal, authorizer_assurance, authorizer_role,
    evidence, proposal_reason, decision_reason,
    prior_state, resulting_state, decision_nonce
  ) values (
    v_receipt_id,
    v_request.id,
    p_decision,
    'client-supplied-operation',
    'client-supplied-proposer',
    'client-supplied-label',
    'client-supplied-principal',
    'client-supplied-assurance',
    'client-supplied-role',
    '[]'::jsonb,
    'client-supplied-proposal-reason',
    p_decision_reason,
    v_prior,
    v_resulting,
    repeat('0', 64)
  ) returning decided_at into v_decided_at;
  update human_approval.requests
  set status = p_decision,
      resolved_at = v_decided_at,
      receipt_id = v_receipt_id
  where id = v_request.id
    and status = 'pending';
  if not found then
    raise exception 'human_approval: already resolved';
  end if;
  return v_receipt_id;
end;
$$;

comment on function human_approval.decide_request(uuid,text,text,text,text) is
  'Internal single-use decision. Identity fields written by the caller are replaced from the trusted session and the locked proposal. public is on the search path last-but-one so the core memory audit trigger can resolve its unqualified audit target; pg_temp stays last.';

create or replace function human_approval.approve_human_approval_request(
  p_request_id uuid,
  p_expected_version text,
  p_decision_nonce text,
  p_decision_reason text
) returns uuid
language sql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $$
  select human_approval.decide_request(
    p_request_id, p_expected_version, p_decision_nonce, p_decision_reason, 'approved'
  );
$$;

create or replace function human_approval.reject_human_approval_request(
  p_request_id uuid,
  p_expected_version text,
  p_decision_nonce text,
  p_decision_reason text
) returns uuid
language sql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $$
  select human_approval.decide_request(
    p_request_id, p_expected_version, p_decision_nonce, p_decision_reason, 'rejected'
  );
$$;

do $$
begin
  perform set_config('human_approval.registry_write', 'on', true);
  insert into human_approval.operations(operation_kind, target_schema, target_table, description)
  values (
    'memory_promotion', 'public', 'memories',
    'Promote a proposed memory to active and bind a human approval receipt'
  )
  on conflict (operation_kind) do update
    set target_schema = excluded.target_schema,
        target_table = excluded.target_table,
        description = excluded.description,
        active = true;
  insert into human_approval.trust_anchors(authenticator_role, principal, assurance_level, active)
  values (
    'human_approval_reviewer', 'example-user', 'deployment-authenticated-human', true
  )
  on conflict (authenticator_role) do update
    set principal = excluded.principal,
        assurance_level = excluded.assurance_level,
        active = excluded.active;
end $$;

do $$
declare
  r record;
  role_name text;
begin
  revoke all on schema human_approval from public;
  revoke all on all tables in schema human_approval from public;
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'human_approval'
  loop
    execute format('revoke all on function %s from public', r.sig);
    foreach role_name in array array[
      'anon','authenticated','service_role','human_approval_agent','human_approval_reviewer'
    ] loop
      if exists (select 1 from pg_roles where rolname = role_name) then
        execute format('revoke all on function %s from %I', r.sig, role_name);
        execute format(
          'revoke all on human_approval.operations, human_approval.trust_anchors, human_approval.sessions, human_approval.requests, human_approval.receipts from %I',
          role_name
        );
      end if;
    end loop;
  end loop;
  grant usage on schema human_approval to human_approval_agent, human_approval_reviewer;
  grant execute on function human_approval.request_memory_promotion(uuid,text,jsonb,timestamptz,text)
    to human_approval_agent;
  grant execute on function human_approval.pending_human_approval_requests(text)
    to human_approval_agent, human_approval_reviewer;
  grant execute on function human_approval.open_human_approval_session()
    to human_approval_reviewer;
  grant execute on function human_approval.approve_human_approval_request(uuid,text,text,text)
    to human_approval_reviewer;
  grant execute on function human_approval.reject_human_approval_request(uuid,text,text,text)
    to human_approval_reviewer;
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant usage on schema human_approval to service_role;
    grant execute on function human_approval.request_memory_promotion(uuid,text,jsonb,timestamptz,text)
      to service_role;
    grant execute on function human_approval.pending_human_approval_requests(text)
      to service_role;
  end if;
end $$;

comment on function human_approval.request_memory_promotion(uuid,text,jsonb,timestamptz,text) is
  'Stage a memory promotion. The caller login is recorded as the proposer. The memory status is not changed.';
comment on function human_approval.open_human_approval_session() is
  'Bind this backend to the trust anchor for the current database login. No principal argument is accepted.';
comment on function human_approval.approve_human_approval_request(uuid,text,text,text) is
  'Approve one pending request. The authorizer and assurance come from the open trusted session.';
comment on function human_approval.reject_human_approval_request(uuid,text,text,text) is
  'Reject one pending request. The rejection receipt records the session authorizer, assurance, proposal, and reason. The target is not mutated.';
comment on function human_approval.pending_human_approval_requests(text) is
  'List unexpired pending proposals for review. This does not authorize a decision.';

do $$
begin
  if to_regprocedure('public.assert_perimeter_closed()') is not null then
    perform public.assert_perimeter_closed();
  end if;
end $$;
