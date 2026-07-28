-- Work-lessons v3 rollback-only conformance. Safe on non-empty databases.
begin;

set local role service_role;

do $$
begin
  begin
    insert into public.work_lessons(kind,claim,created_by)
    values('worked','direct runtime insert must fail','runtime');
    raise exception 'direct work_lessons insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

do $$
declare
  v_root uuid;
  v_rejected uuid;
  v_replacement uuid;
  v_rule uuid;
  v_evidence uuid;
  v_boot jsonb;
begin
  v_root:=public.propose_work_lesson(
    'worked','conformance root worked lesson','fixture',
    'coordination_ref','coordination:test:root','test-suite','ci',
    'resolvable',null
  );
  perform public.accept_work_lesson(v_root,'ci','coordination:test:accept-root');

  v_rejected:=public.propose_lesson_supersession(
    v_root,'rejected successor','fixture',
    'coordination_ref','coordination:test:rejected','test-suite','ci',
    'resolvable',null
  );
  perform public.reject_work_lesson(v_rejected,'ci','coordination:test:reject');

  v_replacement:=public.propose_lesson_supersession(
    v_root,'replacement successor','fixture',
    'coordination_ref','coordination:test:replacement','test-suite','ci',
    'resolvable',null
  );
  if not exists(select 1 from public.work_lessons where id=v_rejected and authority_state='rejected') then
    raise exception 'rejected history is not readable';
  end if;
  if not exists(select 1 from public.work_lessons where id=v_replacement and authority_state='proposed') then
    raise exception 'replacement successor was blocked';
  end if;

  v_rule:=public.propose_work_lesson(
    'rule','conformance accepted rule','fixture',
    'coordination_ref','coordination:test:rule-unverified','test-suite','ci',
    'unverified',null
  );
  begin
    perform public.accept_work_lesson(v_rule,'ci','coordination:test:premature-accept');
    raise exception 'behavioral rule accepted without resolvable evidence';
  exception when raise_exception then
    if sqlerrm='behavioral rule accepted without resolvable evidence' then raise; end if;
  end;

  select id into v_evidence
  from public.work_lesson_evidence_current
  where lesson_id=v_rule
  order by created_at,id limit 1;
  perform public.correct_work_lesson_evidence(
    v_evidence,'coordination_ref','coordination:test:rule-resolved',
    'test-suite','ci','resolved in conformance','resolvable',null
  );
  perform public.accept_work_lesson(v_rule,'ci','coordination:test:accept-rule');

  v_boot:=public.work_lessons_boot_fragment();
  if not (v_boot->'rules' ? 'conformance accepted rule') then
    raise exception 'accepted evidenced rule absent from boot';
  end if;

  begin
    update public.work_lesson_evidence set locator='coordination:test:tamper' where lesson_id=v_rule;
    raise exception 'direct evidence update unexpectedly succeeded';
  exception when insufficient_privilege then null;
           when raise_exception then
             if sqlerrm='direct evidence update unexpectedly succeeded' then raise; end if;
  end;
  begin
    delete from public.work_lesson_events where lesson_id=v_rule;
    raise exception 'direct authority-event delete unexpectedly succeeded';
  exception when insufficient_privilege then null;
           when raise_exception then
             if sqlerrm='direct authority-event delete unexpectedly succeeded' then raise; end if;
  end;
end $$;

reset role;
select public.assert_perimeter_closed();
rollback;

select 'work-lessons v3 rollback-only conformance passed' as result;
