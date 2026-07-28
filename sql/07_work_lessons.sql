-- ============================================================================
-- SOVEREIGN MEMORY :: WORK LESSONS V3
-- Target: PostgreSQL 15+. Idempotent fresh-install and fix-forward contract.
--
-- Agent operating experience is separate from user/world memory. Behavioral
-- rules are proposal-gated, evidence-backed, explicitly accepted, and loaded
-- deterministically. Evidence and authority events are append-only.
-- ============================================================================

create table if not exists work_lessons (
  id              uuid primary key default gen_random_uuid(),
  kind            text not null check (kind in ('worked','failed','prohibition','rule')),
  claim           text not null check (claim ~ '[^[:space:]]'),
  detail          text,
  applies_to      text not null default 'all-agents' check (applies_to='all-agents'),
  learned_on      date not null default current_date,
  status          text not null default 'active' check (status in ('active','superseded')),
  supersedes      uuid references work_lessons(id) on delete restrict,
  authority_state text not null default 'proposed'
                  check (authority_state in ('proposed','accepted','rejected')),
  created_by      text not null check (created_by ~ '[^[:space:]]'),
  accepted_by     text check (accepted_by is null or accepted_by ~ '[^[:space:]]'),
  accepted_at     timestamptz,
  authority_ref   text check (authority_ref is null or authority_ref ~ '[^[:space:]]'),
  created_at      timestamptz not null default now(),
  constraint work_lessons_not_self_supersede check (supersedes is null or supersedes<>id),
  constraint work_lessons_acceptance_shape check (
    (authority_state='accepted' and accepted_by is not null and accepted_at is not null and authority_ref is not null)
    or authority_state<>'accepted'
  )
);

create table if not exists work_lesson_evidence (
  id                uuid primary key default gen_random_uuid(),
  lesson_id         uuid not null references work_lessons(id) on delete restrict,
  evidence_kind     text not null,
  locator           text not null check (locator ~ '[^[:space:]]'),
  source_authority  text not null check (source_authority ~ '[^[:space:]]'),
  integrity_hash    text check (integrity_hash is null or integrity_hash ~ '^[0-9a-f]{64}$'),
  resolution_state  text not null default 'unverified'
                    check (resolution_state in ('unverified','resolvable','invalid')),
  created_by        text not null check (created_by ~ '[^[:space:]]'),
  supersedes        uuid references work_lesson_evidence(id) on delete restrict,
  correction_reason text check (correction_reason is null or correction_reason ~ '[^[:space:]]'),
  created_at        timestamptz not null default now(),
  constraint work_lesson_evidence_not_self_supersede check (supersedes is null or supersedes<>id),
  constraint work_lesson_evidence_correction_shape check (
    (supersedes is null and correction_reason is null)
    or (supersedes is not null and correction_reason is not null)
  )
);

alter table work_lesson_evidence
  drop constraint if exists work_lesson_evidence_evidence_kind_check;
alter table work_lesson_evidence
  add constraint work_lesson_evidence_evidence_kind_check
  check (evidence_kind in (
    'coordination_ref','memory','migration','artifact',
    'public_source','other_durable_locator'
  ));

create table if not exists work_lesson_events (
  id            uuid primary key default gen_random_uuid(),
  lesson_id     uuid not null references work_lessons(id) on delete restrict,
  event_type    text not null check (event_type in (
    'proposed','accepted','rejected','superseded','evidence_added','evidence_corrected'
  )),
  actor         text not null check (actor ~ '[^[:space:]]'),
  authority_ref text check (authority_ref is null or authority_ref ~ '[^[:space:]]'),
  details       jsonb not null default '{}',
  occurred_at   timestamptz not null default now()
);

drop index if exists work_lessons_one_active_successor_uq;
drop index if exists uq_work_lessons_one_active_successor;
drop index if exists work_lessons_one_live_successor_uq;
create unique index work_lessons_one_live_successor_uq
  on work_lessons(supersedes)
  where supersedes is not null
    and status='active'
    and authority_state<>'rejected';

create index if not exists work_lessons_boot_idx
  on work_lessons(kind,learned_on desc,created_at desc,id)
  where status='active' and authority_state='accepted';

create unique index if not exists work_lesson_evidence_root_locator_uq
  on work_lesson_evidence(lesson_id,evidence_kind,locator)
  where supersedes is null;
create unique index if not exists work_lesson_evidence_one_successor_uq
  on work_lesson_evidence(supersedes)
  where supersedes is not null;

comment on table work_lessons is
  'Agent operating experience. Behavioral lessons require explicit acceptance and current resolvable evidence before boot loading.';
comment on table work_lesson_evidence is
  'Append-only typed evidence custody. coordination_ref is generic; deployment mappings remain outside the public protocol.';
comment on table work_lesson_events is
  'Append-only authority and evidence-custody event trail.';
comment on index work_lessons_one_live_successor_uq is
  'At most one non-rejected live successor may occupy a predecessor slot; rejected proposals remain readable history.';

alter table work_lessons enable row level security;
alter table work_lessons force row level security;
alter table work_lesson_evidence enable row level security;
alter table work_lesson_evidence force row level security;
alter table work_lesson_events enable row level security;
alter table work_lesson_events force row level security;

revoke all on work_lessons,work_lesson_evidence,work_lesson_events from public;

do $$
begin
  if exists(select 1 from pg_roles where rolname='service_role') then
    drop policy if exists work_lessons_service_select on work_lessons;
    create policy work_lessons_service_select on work_lessons for select to service_role using(true);
    drop policy if exists work_lesson_evidence_service_select on work_lesson_evidence;
    create policy work_lesson_evidence_service_select on work_lesson_evidence for select to service_role using(true);
    drop policy if exists work_lesson_events_service_select on work_lesson_events;
    create policy work_lesson_events_service_select on work_lesson_events for select to service_role using(true);
  end if;
end $$;

create or replace function is_canonical_work_lesson_locator(p_kind text,p_locator text)
returns boolean
language sql immutable set search_path=public as $$
select case p_kind
  when 'coordination_ref' then p_locator ~ '^coordination:[a-z][a-z0-9+.-]*:[^[:space:]]+$'
  when 'memory' then p_locator ~ '^memory:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  when 'migration' then p_locator ~ '^migration:[a-z0-9][a-z0-9_]*$'
  when 'artifact' then p_locator ~ '^artifact:sha256:[0-9a-f]{64}$'
  when 'public_source' then p_locator ~ '^public_source:https://[^[:space:]]+$'
  when 'other_durable_locator' then p_locator ~ '^other:[a-z][a-z0-9+.-]*:[^[:space:]]+$'
  else false
end;
$$;

create or replace view work_lesson_evidence_current with (security_invoker=true) as
select e.*
from work_lesson_evidence e
where not exists(select 1 from work_lesson_evidence successor where successor.supersedes=e.id);

create or replace function guard_work_lessons_write_path()
returns trigger language plpgsql set search_path=public as $$
begin
  if coalesce(current_setting('app.work_lessons_write',true),'')<>'on' then
    raise exception 'work_lessons: direct mutation is not permitted; use sanctioned functions';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function guard_work_lesson_custody_write_path()
returns trigger language plpgsql set search_path=public as $$
begin
  if tg_op='INSERT' then
    if coalesce(current_setting('app.work_lesson_custody_write',true),'')<>'on' then
      raise exception '%: direct insert is not permitted; use sanctioned functions',tg_table_name;
    end if;
    return new;
  end if;
  raise exception '% is append-only; % is not permitted',tg_table_name,tg_op;
end;
$$;

create or replace function guard_work_lesson_truncate()
returns trigger language plpgsql set search_path=public as $$
begin
  raise exception '%: TRUNCATE is not permitted',tg_table_name;
end;
$$;

drop trigger if exists trg_work_lessons_write_path on work_lessons;
create trigger trg_work_lessons_write_path
before insert or update or delete on work_lessons
for each row execute function guard_work_lessons_write_path();
drop trigger if exists trg_work_lessons_no_truncate on work_lessons;
create trigger trg_work_lessons_no_truncate
before truncate on work_lessons
for each statement execute function guard_work_lesson_truncate();

drop trigger if exists trg_work_lesson_evidence_custody on work_lesson_evidence;
create trigger trg_work_lesson_evidence_custody
before insert or update or delete on work_lesson_evidence
for each row execute function guard_work_lesson_custody_write_path();
drop trigger if exists trg_work_lesson_evidence_no_truncate on work_lesson_evidence;
create trigger trg_work_lesson_evidence_no_truncate
before truncate on work_lesson_evidence
for each statement execute function guard_work_lesson_truncate();

drop trigger if exists trg_work_lesson_events_custody on work_lesson_events;
create trigger trg_work_lesson_events_custody
before insert or update or delete on work_lesson_events
for each row execute function guard_work_lesson_custody_write_path();
drop trigger if exists trg_work_lesson_events_no_truncate on work_lesson_events;
create trigger trg_work_lesson_events_no_truncate
before truncate on work_lesson_events
for each statement execute function guard_work_lesson_truncate();

create or replace function propose_work_lesson(
  p_kind text,p_claim text,p_detail text,p_evidence_kind text,p_evidence_locator text,
  p_source_authority text,p_created_by text,p_resolution_state text default 'unverified',
  p_integrity_hash text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if p_kind not in ('worked','failed','prohibition','rule') then raise exception 'invalid kind'; end if;
  if p_claim is null or p_claim !~ '[^[:space:]]' then raise exception 'claim must contain non-whitespace'; end if;
  if p_created_by is null or p_created_by !~ '[^[:space:]]'
     or p_source_authority is null or p_source_authority !~ '[^[:space:]]' then
    raise exception 'creator and source authority must contain non-whitespace';
  end if;
  if p_resolution_state not in ('unverified','resolvable','invalid') then raise exception 'invalid resolution state'; end if;
  if not is_canonical_work_lesson_locator(p_evidence_kind,p_evidence_locator) then
    raise exception 'evidence locator must be canonical';
  end if;
  perform set_config('app.work_lessons_write','on',true);
  perform set_config('app.work_lesson_custody_write','on',true);
  insert into work_lessons(kind,claim,detail,authority_state,created_by)
  values(p_kind,p_claim,p_detail,'proposed',p_created_by) returning id into v_id;
  insert into work_lesson_evidence(lesson_id,evidence_kind,locator,source_authority,integrity_hash,resolution_state,created_by)
  values(v_id,p_evidence_kind,p_evidence_locator,p_source_authority,p_integrity_hash,p_resolution_state,p_created_by);
  insert into work_lesson_events(lesson_id,event_type,actor,details)
  values(v_id,'proposed',p_created_by,jsonb_build_object('evidence_kind',p_evidence_kind,'locator',p_evidence_locator));
  return v_id;
end;
$$;

create or replace function append_work_lesson_evidence(
  p_lesson_id uuid,p_evidence_kind text,p_locator text,p_source_authority text,p_actor text,
  p_resolution_state text default 'unverified',p_integrity_hash text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if p_actor is null or p_actor !~ '[^[:space:]]'
     or p_source_authority is null or p_source_authority !~ '[^[:space:]]' then
    raise exception 'actor and source authority must contain non-whitespace';
  end if;
  if p_resolution_state not in ('unverified','resolvable','invalid') then raise exception 'invalid resolution state'; end if;
  if not is_canonical_work_lesson_locator(p_evidence_kind,p_locator) then raise exception 'evidence locator must be canonical'; end if;
  perform 1 from work_lessons where id=p_lesson_id;
  if not found then raise exception 'lesson not found'; end if;
  if exists(select 1 from work_lesson_evidence_current where lesson_id=p_lesson_id and evidence_kind=p_evidence_kind and locator=p_locator) then
    raise exception 'current evidence already exists';
  end if;
  perform set_config('app.work_lesson_custody_write','on',true);
  insert into work_lesson_evidence(lesson_id,evidence_kind,locator,source_authority,integrity_hash,resolution_state,created_by)
  values(p_lesson_id,p_evidence_kind,p_locator,p_source_authority,p_integrity_hash,p_resolution_state,p_actor)
  returning id into v_id;
  insert into work_lesson_events(lesson_id,event_type,actor,details)
  values(p_lesson_id,'evidence_added',p_actor,jsonb_build_object('evidence_id',v_id,'locator',p_locator,'resolution_state',p_resolution_state));
  return v_id;
end;
$$;

create or replace function correct_work_lesson_evidence(
  p_evidence_id uuid,p_evidence_kind text,p_locator text,p_source_authority text,p_actor text,
  p_correction_reason text,p_resolution_state text default 'unverified',p_integrity_hash text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_old work_lesson_evidence%rowtype;v_new uuid;
begin
  if p_actor is null or p_actor !~ '[^[:space:]]'
     or p_source_authority is null or p_source_authority !~ '[^[:space:]]'
     or p_correction_reason is null or p_correction_reason !~ '[^[:space:]]' then
    raise exception 'actor, source authority and correction reason must contain non-whitespace';
  end if;
  if p_resolution_state not in ('unverified','resolvable','invalid') then raise exception 'invalid resolution state'; end if;
  if not is_canonical_work_lesson_locator(p_evidence_kind,p_locator) then raise exception 'evidence locator must be canonical'; end if;
  select * into v_old from work_lesson_evidence where id=p_evidence_id for update;
  if not found then raise exception 'evidence not found'; end if;
  if exists(select 1 from work_lesson_evidence where supersedes=v_old.id) then raise exception 'evidence is not current'; end if;
  perform set_config('app.work_lesson_custody_write','on',true);
  insert into work_lesson_evidence(
    lesson_id,evidence_kind,locator,source_authority,integrity_hash,resolution_state,created_by,supersedes,correction_reason
  ) values(
    v_old.lesson_id,p_evidence_kind,p_locator,p_source_authority,p_integrity_hash,p_resolution_state,p_actor,v_old.id,p_correction_reason
  ) returning id into v_new;
  insert into work_lesson_events(lesson_id,event_type,actor,details)
  values(v_old.lesson_id,'evidence_corrected',p_actor,jsonb_build_object('old_evidence_id',v_old.id,'new_evidence_id',v_new,'locator',p_locator,'reason',p_correction_reason));
  return v_new;
end;
$$;

create or replace function propose_lesson_supersession(
  p_predecessor_id uuid,p_claim text,p_detail text,p_evidence_kind text,p_evidence_locator text,
  p_source_authority text,p_created_by text,p_resolution_state text default 'unverified',
  p_integrity_hash text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_old work_lessons%rowtype;v_new uuid;
begin
  select * into v_old from work_lessons
  where id=p_predecessor_id and status='active' and authority_state='accepted' for update;
  if not found then raise exception 'no active accepted predecessor'; end if;
  if p_claim is null or p_claim !~ '[^[:space:]]' then raise exception 'claim must contain non-whitespace'; end if;
  if p_created_by is null or p_created_by !~ '[^[:space:]]'
     or p_source_authority is null or p_source_authority !~ '[^[:space:]]' then
    raise exception 'creator and source authority must contain non-whitespace';
  end if;
  if p_resolution_state not in ('unverified','resolvable','invalid') then raise exception 'invalid resolution state'; end if;
  if not is_canonical_work_lesson_locator(p_evidence_kind,p_evidence_locator) then raise exception 'evidence locator must be canonical'; end if;
  perform set_config('app.work_lessons_write','on',true);
  perform set_config('app.work_lesson_custody_write','on',true);
  insert into work_lessons(kind,claim,detail,applies_to,status,supersedes,authority_state,created_by)
  values(v_old.kind,p_claim,p_detail,v_old.applies_to,'active',v_old.id,'proposed',p_created_by)
  returning id into v_new;
  insert into work_lesson_evidence(lesson_id,evidence_kind,locator,source_authority,integrity_hash,resolution_state,created_by)
  values(v_new,p_evidence_kind,p_evidence_locator,p_source_authority,p_integrity_hash,p_resolution_state,p_created_by);
  insert into work_lesson_events(lesson_id,event_type,actor,details)
  values(v_new,'proposed',p_created_by,jsonb_build_object('supersedes',v_old.id,'locator',p_evidence_locator));
  return v_new;
end;
$$;

create or replace function accept_work_lesson(p_id uuid,p_accepted_by text,p_authority_ref text)
returns uuid
language plpgsql security definer set search_path=public as $$
declare v_row work_lessons%rowtype;
begin
  if p_accepted_by is null or p_accepted_by !~ '[^[:space:]]'
     or p_authority_ref is null or p_authority_ref !~ '[^[:space:]]' then
    raise exception 'acceptor and authority reference must contain non-whitespace';
  end if;
  select * into v_row from work_lessons
  where id=p_id and status='active' and authority_state='proposed' for update;
  if not found then raise exception 'no active proposed lesson'; end if;
  if v_row.kind in ('rule','prohibition') and not exists(
    select 1 from work_lesson_evidence_current where lesson_id=v_row.id and resolution_state='resolvable'
  ) then raise exception 'behavioral lesson requires current resolvable evidence'; end if;
  perform set_config('app.work_lessons_write','on',true);
  perform set_config('app.work_lesson_custody_write','on',true);
  if v_row.supersedes is not null then
    update work_lessons set status='superseded'
    where id=v_row.supersedes and status='active' and authority_state='accepted';
    if not found then raise exception 'predecessor is not active and accepted'; end if;
    insert into work_lesson_events(lesson_id,event_type,actor,authority_ref,details)
    values(v_row.supersedes,'superseded',p_accepted_by,p_authority_ref,jsonb_build_object('successor',v_row.id));
  end if;
  update work_lessons
  set authority_state='accepted',accepted_by=p_accepted_by,accepted_at=now(),authority_ref=p_authority_ref
  where id=v_row.id;
  insert into work_lesson_events(lesson_id,event_type,actor,authority_ref)
  values(v_row.id,'accepted',p_accepted_by,p_authority_ref);
  return v_row.id;
end;
$$;

create or replace function reject_work_lesson(p_id uuid,p_actor text,p_authority_ref text)
returns uuid
language plpgsql security definer set search_path=public as $$
begin
  if p_actor is null or p_actor !~ '[^[:space:]]'
     or p_authority_ref is null or p_authority_ref !~ '[^[:space:]]' then
    raise exception 'actor and authority reference must contain non-whitespace';
  end if;
  perform set_config('app.work_lessons_write','on',true);
  perform set_config('app.work_lesson_custody_write','on',true);
  update work_lessons set authority_state='rejected'
  where id=p_id and status='active' and authority_state='proposed';
  if not found then raise exception 'no active proposed lesson'; end if;
  insert into work_lesson_events(lesson_id,event_type,actor,authority_ref)
  values(p_id,'rejected',p_actor,p_authority_ref);
  return p_id;
end;
$$;

create or replace function work_lessons_boot_fragment()
returns jsonb
language sql stable security definer set search_path=public as $$
with bootable as (
  select wl.* from work_lessons wl
  where wl.status='active' and wl.authority_state='accepted' and wl.applies_to='all-agents'
    and (
      wl.kind not in ('rule','prohibition')
      or exists(
        select 1 from work_lesson_evidence_current e
        where e.lesson_id=wl.id and e.resolution_state='resolvable'
      )
    )
)
select jsonb_build_object(
  'prohibitions',(select coalesce(jsonb_agg(claim order by learned_on desc,created_at desc,id),'[]'::jsonb) from bootable where kind='prohibition'),
  'rules',(select coalesce(jsonb_agg(claim order by learned_on desc,created_at desc,id),'[]'::jsonb) from bootable where kind='rule'),
  'counts',jsonb_build_object(
    'worked',(select count(*) from work_lessons where status='active' and authority_state='accepted' and kind='worked'),
    'failed',(select count(*) from work_lessons where status='active' and authority_state='accepted' and kind='failed'),
    'proposed',(select count(*) from work_lessons where status='active' and authority_state='proposed'),
    'evidence_blocked',(select count(*) from work_lessons wl where wl.status='active' and wl.authority_state='accepted' and wl.kind in ('rule','prohibition') and not exists(select 1 from work_lesson_evidence_current e where e.lesson_id=wl.id and e.resolution_state='resolvable'))
  )
);
$$;

revoke all on function is_canonical_work_lesson_locator(text,text) from public;
revoke all on function propose_work_lesson(text,text,text,text,text,text,text,text,text) from public;
revoke all on function append_work_lesson_evidence(uuid,text,text,text,text,text,text) from public;
revoke all on function correct_work_lesson_evidence(uuid,text,text,text,text,text,text,text) from public;
revoke all on function propose_lesson_supersession(uuid,text,text,text,text,text,text,text,text) from public;
revoke all on function accept_work_lesson(uuid,text,text) from public;
revoke all on function reject_work_lesson(uuid,text,text) from public;
revoke all on function work_lessons_boot_fragment() from public;

do $$
declare r text;f text;
begin
  foreach r in array array['anon','authenticated'] loop
    if exists(select 1 from pg_roles where rolname=r) then
      execute format('revoke all on work_lessons,work_lesson_evidence,work_lesson_events from %I',r);
      foreach f in array array[
        'is_canonical_work_lesson_locator(text,text)',
        'propose_work_lesson(text,text,text,text,text,text,text,text,text)',
        'append_work_lesson_evidence(uuid,text,text,text,text,text,text)',
        'correct_work_lesson_evidence(uuid,text,text,text,text,text,text,text)',
        'propose_lesson_supersession(uuid,text,text,text,text,text,text,text,text)',
        'accept_work_lesson(uuid,text,text)','reject_work_lesson(uuid,text,text)',
        'work_lessons_boot_fragment()'
      ] loop execute format('revoke all on function %s from %I',f,r); end loop;
    end if;
  end loop;
  if exists(select 1 from pg_roles where rolname='service_role') then
    revoke all on work_lessons,work_lesson_evidence,work_lesson_events from service_role;
    grant select on work_lessons,work_lesson_evidence,work_lesson_events to service_role;
    grant select on work_lesson_evidence_current to service_role;
    foreach f in array array[
      'is_canonical_work_lesson_locator(text,text)',
      'propose_work_lesson(text,text,text,text,text,text,text,text,text)',
      'append_work_lesson_evidence(uuid,text,text,text,text,text,text)',
      'correct_work_lesson_evidence(uuid,text,text,text,text,text,text,text)',
      'propose_lesson_supersession(uuid,text,text,text,text,text,text,text,text)',
      'accept_work_lesson(uuid,text,text)','reject_work_lesson(uuid,text,text)',
      'work_lessons_boot_fragment()'
    ] loop execute format('grant execute on function %s to service_role',f); end loop;
  end if;
end $$;
