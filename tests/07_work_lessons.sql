-- ============================================================================
-- WORK LESSONS V2 :: ROLLBACK-ONLY CONFORMANCE TEST
-- Run after sql/07_work_lessons.sql.
-- ============================================================================

begin;

do $$
declare
  v_rule uuid;
  v_rule_evidence uuid;
  v_successor uuid;
  v_failed uuid;
  v_rejected uuid;
  v_boot jsonb;
  v_before integer;
begin
  if to_regclass('public.work_lessons') is null
     or to_regclass('public.work_lesson_evidence') is null
     or to_regclass('public.work_lesson_events') is null then
    raise exception 'work-memory tables missing';
  end if;

  if to_regprocedure('public.propose_work_lesson(text,text,text,text,text,text,text,text,text)') is null
     or to_regprocedure('public.accept_work_lesson(uuid,text,text)') is null
     or to_regprocedure('public.work_lessons_boot_fragment()') is null then
    raise exception 'required work-memory functions missing';
  end if;

  -- Whitespace-class validation must reject spaces, tabs, and newlines.
  begin
    perform propose_work_lesson(
      'rule',E' \t\n ','fixture','artifact','artifact:sha256:'||repeat('a',64),
      'fixture-authority','fixture-agent','resolvable',null
    );
    raise exception 'whitespace-only claim was accepted';
  exception when others then
    if sqlerrm not like '%claim must contain non-whitespace%' then raise; end if;
  end;

  -- Direct table writes are denied even to the owner unless a sanctioned function
  -- enables the transaction-local guard.
  begin
    insert into work_lessons(kind,claim,created_by)
    values('rule','direct insert must fail','fixture-agent');
    raise exception 'direct lesson insert unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%direct mutation is not permitted%' then raise; end if;
  end;

  -- Proposed behavioral lesson with unverified evidence is not boot-active.
  v_rule:=propose_work_lesson(
    'rule','fixture accepted rule','fixture detail','artifact',
    'artifact:sha256:'||repeat('b',64),'fixture-authority','fixture-agent','unverified',null
  );

  v_boot:=work_lessons_boot_fragment();
  if (v_boot->'rules') ? 'fixture accepted rule' then
    raise exception 'proposed rule appeared in boot';
  end if;

  begin
    perform accept_work_lesson(v_rule,'fixture-approver','artifact:sha256:'||repeat('c',64));
    raise exception 'acceptance succeeded without resolvable evidence';
  exception when others then
    if sqlerrm not like '%requires current resolvable evidence%' then raise; end if;
  end;

  select id into v_rule_evidence
  from work_lesson_evidence_current where lesson_id=v_rule;

  perform correct_work_lesson_evidence(
    v_rule_evidence,'artifact','artifact:sha256:'||repeat('d',64),
    'fixture-authority','fixture-agent','replace unverified fixture locator',
    'resolvable',repeat('e',64)
  );

  if (select count(*) from work_lesson_evidence where lesson_id=v_rule)<>2 then
    raise exception 'evidence correction did not append a successor';
  end if;
  if (select count(*) from work_lesson_events where lesson_id=v_rule and event_type='evidence_corrected')<>1 then
    raise exception 'evidence correction event missing';
  end if;

  perform accept_work_lesson(v_rule,'fixture-approver','artifact:sha256:'||repeat('f',64));
  v_boot:=work_lessons_boot_fragment();
  if not ((v_boot->'rules') ? 'fixture accepted rule') then
    raise exception 'accepted evidence-backed rule absent from boot';
  end if;

  -- worked/failed history may be accepted but must never become behavioral input.
  v_failed:=propose_work_lesson(
    'failed','fixture supporting failure','fixture','artifact',
    'artifact:sha256:'||repeat('1',64),'fixture-authority','fixture-agent','resolvable',null
  );
  perform accept_work_lesson(v_failed,'fixture-approver','artifact:sha256:'||repeat('2',64));
  v_boot:=work_lessons_boot_fragment();
  if (v_boot->'rules') ? 'fixture supporting failure'
     or (v_boot->'prohibitions') ? 'fixture supporting failure' then
    raise exception 'failed row was injected as behavior';
  end if;

  -- Rejection is preserved but not boot-active.
  v_rejected:=propose_work_lesson(
    'prohibition','fixture rejected prohibition','fixture','artifact',
    'artifact:sha256:'||repeat('3',64),'fixture-authority','fixture-agent','resolvable',null
  );
  perform reject_work_lesson(v_rejected,'fixture-approver','artifact:sha256:'||repeat('4',64));
  v_boot:=work_lessons_boot_fragment();
  if (v_boot->'prohibitions') ? 'fixture rejected prohibition' then
    raise exception 'rejected prohibition appeared in boot';
  end if;

  -- Supersession is proposed first and becomes effective only on acceptance.
  v_successor:=propose_lesson_supersession(
    v_rule,'fixture successor rule','fixture successor','artifact',
    'artifact:sha256:'||repeat('5',64),'fixture-authority','fixture-agent','resolvable',null
  );

  if not exists(select 1 from work_lessons where id=v_rule and status='active') then
    raise exception 'predecessor changed before successor acceptance';
  end if;

  perform accept_work_lesson(v_successor,'fixture-approver','artifact:sha256:'||repeat('6',64));

  if not exists(select 1 from work_lessons where id=v_rule and status='superseded') then
    raise exception 'accepted successor did not supersede predecessor';
  end if;
  if not exists(select 1 from work_lessons where id=v_successor and status='active' and authority_state='accepted' and supersedes=v_rule) then
    raise exception 'successor lineage invalid';
  end if;

  v_boot:=work_lessons_boot_fragment();
  if not ((v_boot->'rules') ? 'fixture successor rule')
     or (v_boot->'rules') ? 'fixture accepted rule' then
    raise exception 'boot did not resolve supersession correctly';
  end if;

  -- Evidence and authority events are immutable and non-truncatable.
  begin
    update work_lesson_evidence set locator=locator where lesson_id=v_successor;
    raise exception 'evidence update unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%append-only%' then raise; end if;
  end;

  begin
    delete from work_lesson_events where lesson_id=v_successor;
    raise exception 'event delete unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%append-only%' then raise; end if;
  end;

  begin
    execute 'truncate table work_lesson_events';
    raise exception 'event truncate unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%TRUNCATE is not permitted%' then raise; end if;
  end;

  -- Runtime roles must not hold routine table mutation privileges.
  if exists(select 1 from pg_roles where rolname='service_role') then
    if has_table_privilege('service_role','public.work_lessons','INSERT')
       or has_table_privilege('service_role','public.work_lesson_evidence','UPDATE')
       or has_table_privilege('service_role','public.work_lesson_events','DELETE')
       or has_table_privilege('service_role','public.work_lesson_events','TRUNCATE') then
      raise exception 'service_role retains routine mutation privilege';
    end if;
  end if;

  if exists(select 1 from pg_roles where rolname='anon')
     and has_table_privilege('anon','public.work_lessons','SELECT') then
    raise exception 'anon has unintended work-memory access';
  end if;

  -- Deterministic order: the accepted successor is the newest fixture rule.
  if (v_boot->'rules'->>0)<>'fixture successor rule' then
    raise exception 'boot ordering is not deterministic newest-first';
  end if;
end $$;

rollback;

-- A successful run reaches this line and leaves no fixtures.
