-- ============================================================================
-- SOVEREIGN MEMORY :: WORK LESSONS
-- Target: PostgreSQL 16+.
--
-- Purpose:
--   Record agent operating experience separately from user/world memory.
--   Active prohibitions and rules are exposed through a deterministic boot
--   fragment; worked and failed rows remain evidence but are not instructions.
--
-- Version 1 scope:
--   applies_to is reserved and constrained to all-agents until a typed agent
--   identity and scoped boot contract exist.
-- ============================================================================

create table if not exists work_lessons (
  id           uuid primary key default gen_random_uuid(),

  kind         text not null
               check (kind in ('worked','failed','prohibition','rule')),

  claim        text not null
               check (length(btrim(claim)) > 0),

  detail       text,

  -- Presence is enforceable here. Resolvability remains a deployment acceptance
  -- requirement because evidence may live in another system.
  evidence_ref text not null
               check (length(btrim(evidence_ref)) > 0),

  applies_to   text not null default 'all-agents'
               check (applies_to = 'all-agents'),

  learned_on   date not null default current_date,

  status       text not null default 'active'
               check (status in ('active','superseded')),

  supersedes   uuid references work_lessons(id),

  created_at   timestamptz not null default now()
);

create index if not exists idx_work_lessons_active_kind
  on work_lessons(kind, learned_on desc, created_at desc)
  where status = 'active';

-- One active direct successor per predecessor. A later correction supersedes the
-- current active successor rather than creating competing active branches.
create unique index if not exists uq_work_lessons_one_active_successor
  on work_lessons(supersedes)
  where supersedes is not null and status = 'active';

comment on table work_lessons is
  'Agent operating experience, separate from user/world memory. Active '
  'prohibitions and rules are boot-loaded behavior; worked and failed rows are '
  'supporting evidence. Corrections use supersession rather than in-place edits.';

alter table work_lessons enable row level security;
revoke all on table work_lessons from public;

-- Managed PostgreSQL platforms may define these roles. Revoke them when present
-- without creating a dependency on the platform.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on table work_lessons from anon;
  end if;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on table work_lessons from authenticated;
  end if;
end $$;

create or replace function supersede_lesson(
  p_id uuid,
  p_claim text,
  p_detail text default null,
  p_evidence_ref text default null
) returns uuid
language plpgsql
security definer
set search_path to public
as $$
declare
  v_old work_lessons%rowtype;
  v_new uuid;
begin
  if p_claim is null or btrim(p_claim) = '' then
    raise exception 'supersede_lesson: claim must be non-empty';
  end if;

  if p_evidence_ref is null or btrim(p_evidence_ref) = '' then
    raise exception 'supersede_lesson: evidence_ref must be non-empty';
  end if;

  select *
    into v_old
    from work_lessons
   where id = p_id
     and status = 'active'
   for update;

  if not found then
    raise exception 'supersede_lesson: no active lesson %', p_id;
  end if;

  insert into work_lessons (
    kind,
    claim,
    detail,
    evidence_ref,
    applies_to,
    learned_on,
    status,
    supersedes
  ) values (
    v_old.kind,
    btrim(p_claim),
    p_detail,
    btrim(p_evidence_ref),
    v_old.applies_to,
    current_date,
    'active',
    v_old.id
  )
  returning id into v_new;

  update work_lessons
     set status = 'superseded'
   where id = v_old.id;

  return v_new;
end;
$$;

comment on function supersede_lesson(uuid,text,text,text) is
  'Creates a successor lesson and marks the prior active lesson superseded in '
  'one transaction. Version 1 preserves lesson kind and all-agents scope.';

revoke all on function supersede_lesson(uuid,text,text,text) from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function supersede_lesson(uuid,text,text,text) from anon;
  end if;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function supersede_lesson(uuid,text,text,text) from authenticated;
  end if;
end $$;

-- Portable boot integration seam.
--
-- Deployments should merge this object into their actual session-boot payload.
-- The deterministic ordering prevents rows learned on the same date from
-- appearing in arbitrary order.
create or replace function work_lessons_boot_fragment()
returns jsonb
language sql
stable
security definer
set search_path to public
as $$
  select jsonb_build_object(
    'prohibitions', (
      select coalesce(
        jsonb_agg(claim order by learned_on desc, created_at desc, id),
        '[]'::jsonb
      )
      from work_lessons
      where status = 'active'
        and kind = 'prohibition'
        and applies_to = 'all-agents'
    ),
    'rules', (
      select coalesce(
        jsonb_agg(claim order by learned_on desc, created_at desc, id),
        '[]'::jsonb
      )
      from work_lessons
      where status = 'active'
        and kind = 'rule'
        and applies_to = 'all-agents'
    ),
    'counts', (
      select jsonb_build_object(
        'worked', count(*) filter (where kind = 'worked'),
        'failed', count(*) filter (where kind = 'failed')
      )
      from work_lessons
      where status = 'active'
    )
  );
$$;

comment on function work_lessons_boot_fragment() is
  'Deterministic active work-memory fragment for integration into a deployment '
  'session-boot payload.';

revoke all on function work_lessons_boot_fragment() from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function work_lessons_boot_fragment() from anon;
  end if;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function work_lessons_boot_fragment() from authenticated;
  end if;
end $$;

-- End of work-lessons contract.
