-- ============================================================================
-- WORK LESSONS :: ROLLBACK-ONLY CONFORMANCE TEST
-- Run after sql/07_work_lessons.sql.
-- ============================================================================

begin;

do $$
declare
  v_old uuid;
  v_new uuid;
  v_boot jsonb;
begin
  -- Presence and catalog checks.
  if to_regclass('public.work_lessons') is null then
    raise exception 'work_lessons table missing';
  end if;

  if to_regprocedure('public.supersede_lesson(uuid,text,text,text)') is null then
    raise exception 'supersede_lesson function missing';
  end if;

  if to_regprocedure('public.work_lessons_boot_fragment()') is null then
    raise exception 'work_lessons_boot_fragment function missing';
  end if;

  -- Blank evidence must fail.
  begin
    insert into work_lessons(kind,claim,evidence_ref)
    values ('rule','blank evidence must fail','   ');

    raise exception 'blank evidence was accepted';
  exception
    when check_violation or not_null_violation then
      null;
  end;

  -- Unsupported v1 scope must fail.
  begin
    insert into work_lessons(kind,claim,evidence_ref,applies_to)
    values ('rule','unsupported scope must fail','fixture:scope','agent-a');

    raise exception 'unsupported applies_to was accepted';
  exception
    when check_violation then
      null;
  end;

  -- Seed an old rule and a second active rule with explicit timestamps so boot
  -- ordering can be checked deterministically.
  insert into work_lessons(
    kind,claim,detail,evidence_ref,created_at
  ) values (
    'rule',
    'older active rule',
    'fixture',
    'fixture:older-rule',
    '2026-01-01T00:00:00Z'
  ) returning id into v_old;

  insert into work_lessons(
    kind,claim,detail,evidence_ref,created_at
  ) values (
    'rule',
    'newer active rule',
    'fixture',
    'fixture:newer-rule',
    '2026-01-02T00:00:00Z'
  );

  insert into work_lessons(kind,claim,detail,evidence_ref)
  values ('failed','supporting failure','fixture','fixture:failed');

  -- Supersession must preserve kind/scope, create lineage, and deactivate the
  -- predecessor in the same transaction.
  v_new := supersede_lesson(
    v_old,
    'successor active rule',
    'fixture successor',
    'fixture:successor'
  );

  if not exists (
    select 1 from work_lessons
    where id = v_old and status = 'superseded'
  ) then
    raise exception 'predecessor was not superseded';
  end if;

  if not exists (
    select 1 from work_lessons
    where id = v_new
      and status = 'active'
      and supersedes = v_old
      and kind = 'rule'
      and applies_to = 'all-agents'
  ) then
    raise exception 'successor lineage or inherited fields invalid';
  end if;

  -- A second active direct successor must fail.
  begin
    insert into work_lessons(
      kind,claim,evidence_ref,applies_to,supersedes
    ) values (
      'rule','competing successor','fixture:competing','all-agents',v_old
    );

    raise exception 'competing active successor was accepted';
  exception
    when unique_violation then
      null;
  end;

  v_boot := work_lessons_boot_fragment();

  if jsonb_typeof(v_boot->'rules') <> 'array' then
    raise exception 'boot rules is not an array';
  end if;

  if jsonb_typeof(v_boot->'prohibitions') <> 'array' then
    raise exception 'boot prohibitions is not an array';
  end if;

  if (v_boot->'rules'->>0) <> 'successor active rule' then
    raise exception 'boot ordering is not deterministic/newest-first';
  end if;

  if (v_boot->'counts'->>'failed')::integer < 1 then
    raise exception 'failed evidence count missing';
  end if;

  if (v_boot->'rules')::text like '%supporting failure%' then
    raise exception 'failed evidence was injected as behavior';
  end if;

  -- Effective managed-role checks when those roles exist.
  if exists (select 1 from pg_roles where rolname='anon')
     and has_table_privilege('anon','public.work_lessons','SELECT') then
    raise exception 'anon has unintended SELECT on work_lessons';
  end if;

  if exists (select 1 from pg_roles where rolname='authenticated')
     and has_function_privilege(
       'authenticated',
       'public.supersede_lesson(uuid,text,text,text)',
       'EXECUTE'
     ) then
    raise exception 'authenticated has unintended EXECUTE on supersede_lesson';
  end if;
end $$;

rollback;

-- End of rollback-only conformance test.
