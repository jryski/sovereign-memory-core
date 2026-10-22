-- ============================================================================
-- SOVEREIGN MEMORY :: SCOPE-BOUND AUTHORITY
-- Target: Postgres 15+ / Supabase. Run after sql/06_cutover_probe_categories.sql.
-- Docs: docs/12-scope-bound-authority.md and docs/04-implementation-guide.md Step 9C.
--
-- Purpose:
--   Store the cutover scope explicitly and record authority for that scope only.
--   A declaration names one principal and one registered scope. Probe results and
--   current-truth reads bind to that same scope. Nothing in this file grants a
--   second scope, and there is no global scope kind to grant by default.
--
-- This contract does not mutate a live database by being present in the repo.
-- Apply it only to a disposable or backed-up database. It adds no SECURITY
-- DEFINER routines, so it stays outside the sql/10 definer inventory.
-- ============================================================================

-- ---- scope registry ----------------------------------------------------------
-- Grammar is <kind>:<identifier>. Kinds are a closed set. There is deliberately
-- no global, all, or wildcard kind: authority that cannot be written cannot be
-- implied.
create table if not exists scope_registry (
  scope_key         text primary key,
  scope_kind        text not null,
  scope_identifier  text not null,
  display_name      text not null,
  active            boolean not null default true,
  created_at        timestamptz not null default now(),
  constraint scope_kind_closed check (
    scope_kind in ('workstream','table','record','domain')
  ),
  constraint scope_identifier_token check (
    scope_identifier ~ '^[a-z0-9][a-z0-9_/-]{0,63}$'
  ),
  constraint scope_identifier_not_universal check (
    scope_identifier not in ('all','global','any')
  ),
  constraint scope_key_composed check (
    scope_key = scope_kind || ':' || scope_identifier
  ),
  constraint scope_no_wildcard check (position('*' in scope_key) = 0),
  constraint scope_display_nonempty check (length(btrim(display_name)) > 0),
  unique (scope_kind, scope_identifier)
);

comment on table scope_registry is
  'Named cutover scopes. Kinds are workstream, table, record, and domain. No global kind exists. Setting active=false does not revoke a recorded declaration.';

-- ---- cutover scope on the batch ---------------------------------------------
alter table source_import_batches
  add column if not exists cutover_scope text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname='source_import_batches_cutover_scope_fkey'
  ) then
    alter table source_import_batches
      add constraint source_import_batches_cutover_scope_fkey
      foreign key (cutover_scope) references scope_registry(scope_key);
  end if;
end $$;

-- One live candidate batch per scope. Rolled-back and abandoned batches keep
-- the historical scope value without blocking a later batch.
create unique index if not exists source_import_batches_one_live_scope
  on source_import_batches (cutover_scope)
  where cutover_scope is not null
    and status in ('open','frozen','ready','cutover');

comment on column source_import_batches.cutover_scope is
  'Explicit scope this batch may become authoritative for. Null until assigned. Never defaults to a global scope.';

-- ---- probe results bind to the batch scope ----------------------------------
alter table cutover_probes
  add column if not exists result_scope text;

alter table cutover_runs
  add column if not exists result_scope text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname='cutover_probes_result_scope_fkey'
  ) then
    alter table cutover_probes
      add constraint cutover_probes_result_scope_fkey
      foreign key (result_scope) references scope_registry(scope_key);
  end if;

  if not exists (
    select 1 from pg_constraint where conname='cutover_runs_result_scope_fkey'
  ) then
    alter table cutover_runs
      add constraint cutover_runs_result_scope_fkey
      foreign key (result_scope) references scope_registry(scope_key);
  end if;
end $$;

comment on column cutover_probes.result_scope is
  'Scope a probe result belongs to. Must match the batch cutover scope. Null results are legacy and do not authorize a scope.';

comment on column cutover_runs.result_scope is
  'Scope recorded on a probe run. Must match the probe result scope. A run bound to one scope cannot satisfy another.';

-- ---- scoped truth -----------------------------------------------------------
-- Current truth is a predicate on one scope, not a corpus-wide flag.
create table if not exists scope_truth_claims (
  id           uuid primary key default gen_random_uuid(),
  scope_key    text not null references scope_registry(scope_key),
  claim_key    text not null,
  truth_state  text not null,
  statement    text not null,
  created_at   timestamptz not null default now(),
  constraint scope_truth_state_known check (
    truth_state in ('current','stale','conflicted','historical')
  ),
  constraint scope_truth_claim_key_nonempty check (length(btrim(claim_key)) > 0),
  constraint scope_truth_statement_nonempty check (length(btrim(statement)) > 0),
  unique (scope_key, claim_key)
);

create index if not exists idx_scope_truth_claims_scope_state
  on scope_truth_claims(scope_key, truth_state);

comment on table scope_truth_claims is
  'Fixture and contract rows for scoped truth. A stale claim stays in its scope and is not current truth for that scope or any other.';

-- ---- authority declaration --------------------------------------------------
create table if not exists scope_authority_declarations (
  id              uuid primary key default gen_random_uuid(),
  scope_key       text not null references scope_registry(scope_key),
  principal       text not null,
  batch_id        uuid not null references source_import_batches(id),
  evidence_ref    text not null,
  review_note     text not null,
  status          text not null default 'recorded',
  declared_at     timestamptz not null default now(),
  declared_by     text not null references trusted_agents(agent_id),
  rolled_back_at  timestamptz,
  rolled_back_by  text references trusted_agents(agent_id),
  rollback_note   text,
  constraint scope_authority_principal_named check (
    length(btrim(principal)) > 0
    and lower(btrim(principal)) not in ('*','global','all','public','anon','authenticated','any')
  ),
  constraint scope_authority_evidence_named check (length(btrim(evidence_ref)) > 0),
  constraint scope_authority_review_named check (length(btrim(review_note)) > 0),
  constraint scope_authority_status_known check (status in ('recorded','rolled_back')),
  constraint scope_authority_rollback_pair check (
    (status = 'recorded' and rolled_back_at is null and rolled_back_by is null and rollback_note is null)
    or (
      status = 'rolled_back'
      and rolled_back_at is not null
      and rolled_back_by is not null
      and length(btrim(coalesce(rollback_note,''))) > 0
    )
  )
);

-- At most one live declaration per scope. History stays when status changes.
create unique index if not exists scope_authority_one_live_per_scope
  on scope_authority_declarations (scope_key)
  where status = 'recorded';

comment on table scope_authority_declarations is
  'Recorded cutover authority for one principal and one scope. Absence of a row is not authority. Rollback keeps the row.';

-- ---- guards -----------------------------------------------------------------
create or replace function scope_guard_batch_cutover()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  if tg_op = 'INSERT' or new.cutover_scope is distinct from old.cutover_scope then
    if new.cutover_scope is not null
       and not exists (
         select 1 from scope_registry
         where scope_key = new.cutover_scope and active
       ) then
      raise exception 'scope assign: % is not an active registered scope', new.cutover_scope;
    end if;

    if tg_op = 'UPDATE' and exists (
      select 1 from cutover_probes
      where batch_id = new.id
        and result_scope is not null
        and result_scope is distinct from new.cutover_scope
    ) then
      raise exception 'scope assign: bound probes do not match cutover scope %', new.cutover_scope;
    end if;

    if tg_op = 'UPDATE' and exists (
      select 1 from scope_authority_declarations
      where batch_id = new.id and status = 'recorded'
    ) then
      raise exception 'scope assign: cannot retarget a batch with a live authority declaration';
    end if;
  end if;

  if new.status = 'cutover' and (tg_op = 'INSERT' or old.status is distinct from 'cutover') then
    if new.cutover_scope is null then
      raise exception 'scope: cutover requires an explicit scope';
    end if;
    if not exists (
      select 1 from scope_authority_declarations d
      where d.batch_id = new.id
        and d.scope_key = new.cutover_scope
        and d.status = 'recorded'
        and length(btrim(d.principal)) > 0
    ) then
      raise exception 'scope: cutover requires a recorded authority declaration naming this scope';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_source_import_batches_scope_guard on source_import_batches;
create trigger trg_source_import_batches_scope_guard
  before insert or update on source_import_batches
  for each row execute function scope_guard_batch_cutover();

create or replace function scope_guard_probe_binding()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_batch_scope text;
  v_probe_scope text;
begin
  if tg_table_name = 'cutover_probes' then
    if new.result_scope is null then
      return new;
    end if;
    select cutover_scope into v_batch_scope
    from source_import_batches
    where id = new.batch_id;
    if v_batch_scope is distinct from new.result_scope then
      raise exception 'scope probe: result_scope % does not match batch cutover scope %',
        new.result_scope, v_batch_scope;
    end if;
    return new;
  end if;

  if new.result_scope is null then
    return new;
  end if;

  select result_scope into v_probe_scope
  from cutover_probes
  where id = new.probe_id;
  if v_probe_scope is distinct from new.result_scope then
    raise exception 'scope probe result: result_scope % does not match probe scope %',
      new.result_scope, v_probe_scope;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_cutover_probes_scope_guard on cutover_probes;
create trigger trg_cutover_probes_scope_guard
  before insert or update on cutover_probes
  for each row execute function scope_guard_probe_binding();

drop trigger if exists trg_cutover_runs_scope_guard on cutover_runs;
create trigger trg_cutover_runs_scope_guard
  before insert or update on cutover_runs
  for each row execute function scope_guard_probe_binding();

create or replace function scope_guard_declaration()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_batch_scope text;
begin
  if new.principal is null
     or length(btrim(new.principal)) = 0
     or lower(btrim(new.principal)) in ('*','global','all','public','anon','authenticated','any') then
    raise exception 'scope authority: declaration must name a principal and a scope';
  end if;

  select cutover_scope into v_batch_scope
  from source_import_batches
  where id = new.batch_id;
  if v_batch_scope is distinct from new.scope_key then
    raise exception 'scope authority: declaration scope % does not match batch cutover scope %',
      new.scope_key, v_batch_scope;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_scope_authority_declarations_guard on scope_authority_declarations;
create trigger trg_scope_authority_declarations_guard
  before insert or update on scope_authority_declarations
  for each row execute function scope_guard_declaration();

-- ---- registration and assignment --------------------------------------------
create or replace function register_scope(
  p_kind text,
  p_identifier text,
  p_display_name text
) returns text
language plpgsql
set search_path to 'public'
as $$
declare
  v_key text;
begin
  if p_kind is null or p_kind not in ('workstream','table','record','domain') then
    raise exception 'scope registry: kind % is not allowed; authority is never global by default', p_kind;
  end if;
  if p_identifier is null
     or p_identifier !~ '^[a-z0-9][a-z0-9_/-]{0,63}$'
     or p_identifier in ('all','global','any')
     or position('*' in p_identifier) > 0 then
    raise exception 'scope registry: identifier % is not a single named scope', p_identifier;
  end if;
  if p_display_name is null or length(btrim(p_display_name)) = 0 then
    raise exception 'scope registry: display name is required for %:%', p_kind, p_identifier;
  end if;

  v_key := p_kind || ':' || p_identifier;

  if exists (select 1 from scope_registry where scope_key = v_key and not active) then
    raise exception 'scope registry: scope % is inactive; registering again does not restore it', v_key;
  end if;

  insert into scope_registry(scope_key, scope_kind, scope_identifier, display_name)
  values (v_key, p_kind, p_identifier, btrim(p_display_name))
  on conflict (scope_key) do nothing;

  return v_key;
end;
$$;

create or replace function assign_cutover_scope(
  p_batch_id uuid,
  p_scope text,
  p_agent text
) returns text
language plpgsql
set search_path to 'public'
as $$
declare
  v_status source_batch_status;
begin
  if not exists (select 1 from trusted_agents where agent_id = p_agent and active) then
    raise exception 'scope assign: unknown/inactive agent %', p_agent;
  end if;
  if not exists (select 1 from scope_registry where scope_key = p_scope and active) then
    raise exception 'scope assign: % is not an active registered scope', p_scope;
  end if;

  select status into v_status
  from source_import_batches
  where id = p_batch_id;
  if v_status is null then
    raise exception 'scope assign: batch % not found', p_batch_id;
  end if;
  if v_status not in ('open','frozen','ready') then
    raise exception 'scope assign: batch % cannot take a scope from status %', p_batch_id, v_status;
  end if;

  update source_import_batches
     set cutover_scope = p_scope
   where id = p_batch_id;

  return p_scope;
end;
$$;

-- ---- declaration ------------------------------------------------------------
-- Ready means review blockers are already clear. Declaration checks them again,
-- then requires each critical probe category to have a latest passing run whose
-- result_scope is this scope. Unbound runs do not count. The batch moves to
-- cutover only after the row exists, and only this batch moves.
create or replace function declare_scope_authority(
  p_scope text,
  p_principal text,
  p_batch_id uuid,
  p_agent text,
  p_evidence_ref text,
  p_review_note text
) returns uuid
language plpgsql
set search_path to 'public'
as $$
declare
  v_agent_principal text;
  v_batch_scope text;
  v_status source_batch_status;
  v_blockers integer;
  v_missing integer;
  v_id uuid;
begin
  select principal into v_agent_principal
  from trusted_agents
  where agent_id = p_agent and active;
  if v_agent_principal is null then
    raise exception 'scope authority: unknown/inactive agent %', p_agent;
  end if;

  if p_principal is null
     or length(btrim(p_principal)) = 0
     or lower(btrim(p_principal)) in ('*','global','all','public','anon','authenticated','any') then
    raise exception 'scope authority: principal must be named and must not be global';
  end if;
  if btrim(p_principal) is distinct from v_agent_principal then
    raise exception 'scope authority: principal % does not match declaring agent principal %',
      p_principal, v_agent_principal;
  end if;
  if p_evidence_ref is null or length(btrim(p_evidence_ref)) = 0 then
    raise exception 'scope authority: evidence reference is required';
  end if;
  if p_review_note is null or length(btrim(p_review_note)) = 0 then
    raise exception 'scope authority: review note is required';
  end if;
  if not exists (select 1 from scope_registry where scope_key = p_scope and active) then
    raise exception 'scope authority: scope % is not an active registered scope', p_scope;
  end if;

  select cutover_scope, status into v_batch_scope, v_status
  from source_import_batches
  where id = p_batch_id;
  if v_status is null then
    raise exception 'scope authority: batch % not found', p_batch_id;
  end if;
  if v_batch_scope is distinct from p_scope then
    raise exception 'scope authority: batch scope % does not match declared scope %',
      v_batch_scope, p_scope;
  end if;
  if v_status <> 'ready' then
    raise exception 'scope authority: batch % must be ready before authority is declared (status %)',
      p_batch_id, v_status;
  end if;

  select count(*) into v_blockers
  from source_readiness
  where batch_id = p_batch_id and severity = 'blocker' and state = 'fail';
  if v_blockers > 0 then
    raise exception 'scope authority: batch % still has % readiness blocker(s)', p_batch_id, v_blockers;
  end if;

  with needed(category) as (
    values ('positive'),('negative'),('conflict'),('stale_state'),('evidence_request')
  ), latest as (
    select distinct on (cr.probe_id)
      cr.probe_id, cr.matched, cr.result_scope
    from cutover_runs cr
    order by cr.probe_id, cr.run_at desc
  )
  select count(*) into v_missing
  from needed n
  where not exists (
    select 1
    from cutover_probes cp
    join latest l on l.probe_id = cp.id
    where cp.batch_id = p_batch_id
      and cp.active
      and cp.severity = 'critical'
      and cp.probe_category = n.category
      and cp.result_scope = p_scope
      and l.matched
      and l.result_scope = p_scope
  );
  if v_missing > 0 then
    raise exception 'scope authority: scope % is missing % critical probe category binding(s)',
      p_scope, v_missing;
  end if;

  if exists (
    select 1 from scope_authority_declarations
    where scope_key = p_scope and status = 'recorded'
  ) then
    raise exception 'scope authority: scope % already has a live declaration', p_scope;
  end if;

  insert into scope_authority_declarations(
    scope_key, principal, batch_id, evidence_ref, review_note, status, declared_by
  ) values (
    p_scope, btrim(p_principal), p_batch_id, btrim(p_evidence_ref), btrim(p_review_note),
    'recorded', p_agent
  )
  returning id into v_id;

  update source_import_batches
     set status = 'cutover'
   where id = p_batch_id and status = 'ready' and cutover_scope = p_scope;
  if not found then
    raise exception 'scope authority: batch % could not enter cutover for %', p_batch_id, p_scope;
  end if;

  return v_id;
end;
$$;

-- Reversible until a declaration is recorded. After that, use
-- rollback_scope_authority, which keeps the declaration row.
create or replace function rollback_scope_before_authority(
  p_batch_id uuid,
  p_agent text,
  p_note text
) returns text
language plpgsql
set search_path to 'public'
as $$
declare
  v_status source_batch_status;
  v_scope text;
begin
  if not exists (select 1 from trusted_agents where agent_id = p_agent and active) then
    raise exception 'scope rollback: unknown/inactive agent %', p_agent;
  end if;
  if p_note is null or length(btrim(p_note)) = 0 then
    raise exception 'scope rollback: a rollback note is required';
  end if;

  select status, cutover_scope into v_status, v_scope
  from source_import_batches
  where id = p_batch_id;
  if v_status is null then
    raise exception 'scope rollback: batch % not found', p_batch_id;
  end if;
  if v_status = 'cutover' or exists (
    select 1 from scope_authority_declarations
    where batch_id = p_batch_id and status = 'recorded'
  ) then
    raise exception 'scope rollback: batch % already has recorded authority; use rollback_scope_authority', p_batch_id;
  end if;
  if v_status not in ('open','frozen','ready') then
    raise exception 'scope rollback: batch % is not reversible from status %', p_batch_id, v_status;
  end if;

  update source_import_batches
     set status = 'rolled_back',
         metadata = metadata || jsonb_build_object(
           'scope_rollback_before_authority', jsonb_build_object(
             'agent', p_agent,
             'scope', v_scope,
             'note', btrim(p_note)
           )
         )
   where id = p_batch_id;

  return 'rolled_back';
end;
$$;

create or replace function rollback_scope_authority(
  p_declaration_id uuid,
  p_agent text,
  p_note text
) returns text
language plpgsql
set search_path to 'public'
as $$
declare
  v_scope text;
  v_batch_id uuid;
  v_principal text;
  v_agent_principal text;
begin
  select principal into v_agent_principal
  from trusted_agents
  where agent_id = p_agent and active;
  if v_agent_principal is null then
    raise exception 'scope rollback: unknown/inactive agent %', p_agent;
  end if;
  if p_note is null or length(btrim(p_note)) = 0 then
    raise exception 'scope rollback: a rollback note is required';
  end if;

  select scope_key, batch_id, principal
    into v_scope, v_batch_id, v_principal
  from scope_authority_declarations
  where id = p_declaration_id and status = 'recorded';
  if v_scope is null then
    raise exception 'scope rollback: live declaration % not found', p_declaration_id;
  end if;
  if v_agent_principal is distinct from v_principal then
    raise exception 'scope rollback: agent principal % cannot roll back declaration for %',
      v_agent_principal, v_principal;
  end if;

  update scope_authority_declarations
     set status = 'rolled_back',
         rolled_back_at = now(),
         rolled_back_by = p_agent,
         rollback_note = btrim(p_note)
   where id = p_declaration_id and status = 'recorded';
  if not found then
    raise exception 'scope rollback: live declaration % not found', p_declaration_id;
  end if;

  update source_import_batches
     set status = 'ready'
   where id = v_batch_id and status = 'cutover' and cutover_scope = v_scope;
  if not found then
    raise exception 'scope rollback: batch for scope % was not in cutover', v_scope;
  end if;

  return v_scope;
end;
$$;

-- ---- reads ------------------------------------------------------------------
-- Both reads require a scope. A null scope returns no rows rather than every row.
create or replace function scope_visible_current_truth(p_scope text)
returns table(claim_key text, statement text)
language sql
stable
set search_path to 'public'
as $$
  select claim_key, statement
  from scope_truth_claims
  where p_scope is not null
    and scope_key = p_scope
    and truth_state = 'current'
  order by claim_key;
$$;

create or replace function scope_probe_observations(p_scope text)
returns table(probe_key text, matched boolean, observed_answer text)
language sql
stable
set search_path to 'public'
as $$
  select cp.probe_key, l.matched, l.observed_answer
  from cutover_probes cp
  join lateral (
    select cr.matched, cr.observed_answer, cr.result_scope
    from cutover_runs cr
    where cr.probe_id = cp.id
    order by cr.run_at desc, cr.id desc
    limit 1
  ) l on true
  where p_scope is not null
    and cp.result_scope = p_scope
    and l.result_scope = p_scope
  order by cp.probe_key;
$$;

create or replace view scope_cutover_scorecard with (security_invoker=true) as
with latest as (
  select distinct on (cr.probe_id)
    cr.probe_id, cr.matched, cr.result_scope as run_scope
  from cutover_runs cr
  order by cr.probe_id, cr.run_at desc, cr.id desc
)
select
  cp.result_scope as scope_key,
  cp.batch_id,
  count(*) filter (where cp.active) as probes_defined,
  count(*) filter (
    where cp.active and l.matched and l.run_scope = cp.result_scope
  ) as probes_passed_in_scope,
  count(*) filter (
    where cp.active and cp.severity = 'critical'
      and l.matched and l.run_scope = cp.result_scope
  ) as critical_passed_in_scope
from cutover_probes cp
left join latest l on l.probe_id = cp.id
where cp.result_scope is not null
group by cp.result_scope, cp.batch_id;

comment on view scope_cutover_scorecard is
  'Probe pass counts for one scope. Runs bound to another scope are not in the join.';

create or replace view scope_authority_report with (security_invoker=true) as
select
  r.scope_key,
  r.scope_kind,
  r.scope_identifier,
  r.active as scope_active,
  d.id as declaration_id,
  d.principal,
  d.batch_id,
  d.evidence_ref,
  d.declared_at,
  d.declared_by,
  coalesce(d.status = 'recorded', false) as authoritative
from scope_registry r
left join scope_authority_declarations d
  on d.scope_key = r.scope_key
 and d.status = 'recorded';

comment on view scope_authority_report is
  'Per-scope authority. authoritative is false when no live declaration exists. It does not mean every pre-existing read path enforces the scope.';

-- ---- grant perimeter --------------------------------------------------------
revoke all on scope_registry from public;
revoke all on scope_truth_claims from public;
revoke all on scope_authority_declarations from public;
revoke all on scope_cutover_scorecard from public;
revoke all on scope_authority_report from public;

revoke execute on function register_scope(text,text,text) from public;
revoke execute on function assign_cutover_scope(uuid,text,text) from public;
revoke execute on function declare_scope_authority(text,text,uuid,text,text,text) from public;
revoke execute on function rollback_scope_before_authority(uuid,text,text) from public;
revoke execute on function rollback_scope_authority(uuid,text,text) from public;
revoke execute on function scope_visible_current_truth(text) from public;
revoke execute on function scope_probe_observations(text) from public;
revoke execute on function scope_guard_batch_cutover() from public;
revoke execute on function scope_guard_probe_binding() from public;
revoke execute on function scope_guard_declaration() from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname='anon') then
    revoke all on scope_registry from anon;
    revoke all on scope_truth_claims from anon;
    revoke all on scope_authority_declarations from anon;
    revoke all on scope_cutover_scorecard from anon;
    revoke all on scope_authority_report from anon;
    revoke execute on function register_scope(text,text,text) from anon;
    revoke execute on function assign_cutover_scope(uuid,text,text) from anon;
    revoke execute on function declare_scope_authority(text,text,uuid,text,text,text) from anon;
    revoke execute on function rollback_scope_before_authority(uuid,text,text) from anon;
    revoke execute on function rollback_scope_authority(uuid,text,text) from anon;
    revoke execute on function scope_visible_current_truth(text) from anon;
    revoke execute on function scope_probe_observations(text) from anon;
    revoke execute on function scope_guard_batch_cutover() from anon;
    revoke execute on function scope_guard_probe_binding() from anon;
    revoke execute on function scope_guard_declaration() from anon;
  end if;

  if exists (select 1 from pg_roles where rolname='authenticated') then
    revoke all on scope_registry from authenticated;
    revoke all on scope_truth_claims from authenticated;
    revoke all on scope_authority_declarations from authenticated;
    revoke all on scope_cutover_scorecard from authenticated;
    revoke all on scope_authority_report from authenticated;
    revoke execute on function register_scope(text,text,text) from authenticated;
    revoke execute on function assign_cutover_scope(uuid,text,text) from authenticated;
    revoke execute on function declare_scope_authority(text,text,uuid,text,text,text) from authenticated;
    revoke execute on function rollback_scope_before_authority(uuid,text,text) from authenticated;
    revoke execute on function rollback_scope_authority(uuid,text,text) from authenticated;
    revoke execute on function scope_visible_current_truth(text) from authenticated;
    revoke execute on function scope_probe_observations(text) from authenticated;
    revoke execute on function scope_guard_batch_cutover() from authenticated;
    revoke execute on function scope_guard_probe_binding() from authenticated;
    revoke execute on function scope_guard_declaration() from authenticated;
  end if;
end $$;

-- End of scope-bound authority contract.
