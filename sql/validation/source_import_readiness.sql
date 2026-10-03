-- ============================================================================
-- SOVEREIGN MEMORY :: SOURCE IMPORT READINESS VALIDATION
-- Target: local Postgres after sql/01_core.sql and sql/04_source_import.sql.
--
-- This script is intentionally read-mostly. The smoke test runs in a transaction
-- and rolls back so it can be used repeatedly on a local validation database.
-- ============================================================================

set search_path to public, extensions;

create temp table if not exists source_import_validation_results (
  check_group text not null,
  object_name text not null,
  state text not null check (state in ('pass','warn','fail')),
  severity text not null default 'required',
  fatal boolean not null default true,
  remediation text not null
) on commit preserve rows;

truncate source_import_validation_results;

-- ---- object inventory --------------------------------------------------------
insert into source_import_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'required_object', object_name, state, 'required', true, remediation
from (
  values
    ('source_systems',              to_regclass('public.source_systems') is not null,              'Run sql/04_source_import.sql'),
    ('source_import_batches',       to_regclass('public.source_import_batches') is not null,       'Run sql/04_source_import.sql'),
    ('source_items',                to_regclass('public.source_items') is not null,                'Run sql/04_source_import.sql'),
    ('source_payload_evidence',     to_regclass('public.source_payload_evidence') is not null,     'Run sql/04_source_import.sql'),
    ('source_manifest',             to_regclass('public.source_manifest') is not null,             'Run sql/04_source_import.sql'),
    ('source_manifest_review_queue',to_regclass('public.source_manifest_review_queue') is not null,'Run sql/04_source_import.sql'),
    ('source_readiness',            to_regclass('public.source_readiness') is not null,            'Run sql/04_source_import.sql'),
    ('cutover_probes',              to_regclass('public.cutover_probes') is not null,              'Run sql/04_source_import.sql'),
    ('cutover_runs',                to_regclass('public.cutover_runs') is not null,                'Run sql/04_source_import.sql'),
    ('cutover_scorecard',           to_regclass('public.cutover_scorecard') is not null,           'Run sql/04_source_import.sql')
) as v(object_name, ok, remediation)
cross join lateral (select case when ok then 'pass' else 'fail' end as state) s;

insert into source_import_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'required_function', function_name, state, 'required', true, remediation
from (
  values
    ('source_freeze_batch',            to_regprocedure('public.source_freeze_batch(uuid,text,jsonb,text)') is not null, 'Run sql/04_source_import.sql'),
    ('source_manifest_payload_drift',  to_regprocedure('public.source_manifest_payload_drift(uuid)') is not null,       'Run sql/04_source_import.sql'),
    ('source_mark_batch_ready',        to_regprocedure('public.source_mark_batch_ready(uuid,text)') is not null,        'Run sql/04_source_import.sql'),
    ('cutover_probe_outcome_matched',  to_regprocedure('public.cutover_probe_outcome_matched(text,text,text,boolean,text,text)') is not null, 'Run sql/06_cutover_probe_categories.sql')
) as v(function_name, ok, remediation)
cross join lateral (select case when ok then 'pass' else 'fail' end as state) s;

insert into source_import_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'required_column',
       'source_manifest.'||column_name,
       case when exists (
         select 1 from information_schema.columns c
         where c.table_schema='public'
           and c.table_name='source_manifest'
           and c.column_name=v.column_name
       ) then 'pass' else 'fail' end,
       'required',
       true,
       'Run sql/05_candidate_locators.sql when candidate locator hardening is expected.' as remediation
from (values
  ('source_locator'),
  ('source_quote'),
  ('source_quote_hash'),
  ('source_quote_hash_algorithm')
) as v(column_name);

insert into source_import_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'required_column',
       'cutover_probes.'||column_name,
       case when exists (
         select 1 from information_schema.columns c
         where c.table_schema='public'
           and c.table_name='cutover_probes'
           and c.column_name=v.column_name
       ) then 'pass' else 'fail' end,
       'required',
       true,
       'Run sql/06_cutover_probe_categories.sql when richer probe hardening is expected.' as remediation
from (values
  ('probe_category'),
  ('expected_behavior'),
  ('expected_evidence_required')
) as v(column_name);

-- ---- function search_path posture ------------------------------------------
insert into source_import_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'function_posture',
       p.proname,
       case when array_to_string(coalesce(p.proconfig,'{}'::text[]), ',') like '%search_path=public%' then 'pass' else 'fail' end,
       'required',
       true,
       'SECURITY DEFINER functions must pin search_path.'
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('source_freeze_batch','source_manifest_payload_drift','source_mark_batch_ready');

-- ---- grant posture -----------------------------------------------------------
insert into source_import_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'grant_posture',
       'table_or_view_grants',
       case when count(*)=0 then 'pass' else 'fail' end,
       'required',
       true,
       'Revoke table/view privileges from PUBLIC, anon, and authenticated.'
from information_schema.role_table_grants
where table_schema='public'
  and table_name in (
    'source_systems','source_import_batches','source_items','source_payload_evidence',
    'source_manifest','source_manifest_review_queue','source_readiness',
    'cutover_probes','cutover_runs','cutover_scorecard'
  )
  and grantee in ('PUBLIC','anon','authenticated');

insert into source_import_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'grant_posture',
       'function_execute_grants',
       case when count(*)=0 then 'pass' else 'fail' end,
       'required',
       true,
       'Revoke function execute privileges from PUBLIC, anon, and authenticated.'
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f',p.proowner))) acl
where p.proname in (
  'source_freeze_batch',
  'source_manifest_payload_drift',
  'source_mark_batch_ready',
  'cutover_probe_outcome_matched'
)
  and acl.privilege_type='EXECUTE'
  and acl.grantee::regrole::text in ('anon','authenticated','-');

select check_group, object_name, state, severity, remediation
from source_import_validation_results
order by check_group, object_name;

-- ---- smoke test --------------------------------------------------------------
-- This section proves the contract can stage, manifest, review, freeze, score,
-- block premature readiness, enforce locators and richer probes, cover each
-- probe outcome, fail readiness when any critical probe misses, then pass
-- readiness after blockers are resolved. It rolls back all fixture rows.

begin;

create temp table source_import_fixture_results (
  check_group text not null,
  object_name text not null,
  state text not null check (state in ('pass','warn','fail')),
  severity text not null default 'required',
  fatal boolean not null default true,
  remediation text not null
) on commit drop;

with agent as (
  select agent_id from trusted_agents where active order by case when agent_id='system' then 0 else 1 end, agent_id limit 1
), sys as (
  insert into source_systems(source_key, display_name, source_type, adapter_name, adapter_version, created_at)
  values ('fixture-chat-export', 'Fixture Chat Export', 'ai-export', 'fixture-adapter', '0.0.1', now())
  on conflict (source_key) do update set display_name=excluded.display_name
  returning id
), batch as (
  insert into source_import_batches(source_system_id, batch_key, source_item_count, exported_item_count, created_by)
  select sys.id, 'fixture-batch-001', 5, 5, agent.agent_id from sys cross join agent
  returning id, created_by
), items as (
  insert into source_items(batch_id, source_item_key, source_container, source_kind, title, payload_hash, payload_size_bytes)
  select batch.id, x.item_key, x.container, x.kind, x.title, encode(digest(x.payload,'sha256'),'hex'), length(x.payload)
  from batch
  cross join (values
    ('item-house','fixture/project-alpha','conversation','Project alpha decision','{"kind":"conversation","decision":"Use the boring durable schema."}'),
    ('item-vault','fixture/restricted-example','conversation','Restricted example note','{"kind":"conversation","restricted":"review required"}'),
    ('item-hold','fixture/project-alpha','conversation','Maybe stale status','{"kind":"conversation","status":"probably current?"}'),
    ('item-evidence','fixture/channel','message','Peer review note','{"kind":"message","note":"model review"}'),
    ('item-exclude','fixture/project-alpha','conversation','Duplicate throwaway chat','{"kind":"conversation","duplicate":true}')
  ) as x(item_key, container, kind, title, payload)
  returning id, source_item_key, payload_hash
), evidence as (
  insert into source_payload_evidence(source_item_id, evidence_kind, location, payload_hash, size_bytes, content_preview)
  select id, 'raw_payload', 'fixture://'||source_item_key||'.json', payload_hash, 128, source_item_key
  from items
  returning id
), manifest_source as (
  select
    id,
    source_item_key,
    payload_hash,
    case source_item_key
      when 'item-house' then 'decision: Use the boring durable schema.'
      when 'item-vault' then 'restricted: review required'
      when 'item-hold' then 'status: probably current?'
      when 'item-evidence' then 'note: model review'
      when 'item-exclude' then 'duplicate: true'
    end as quote_text,
    jsonb_build_object(
      'scheme','fixture-json',
      'path', jsonb_build_array('fixture', source_item_key),
      'span', jsonb_build_object('kind','synthetic-fixture')
    ) as locator
  from items
), manifest as (
  insert into source_manifest(
    source_item_id,
    manifest_key,
    source_locator,
    source_quote,
    source_quote_hash,
    source_quote_hash_algorithm,
    action,
    target_zone,
    review_state,
    target_table,
    topic_key,
    workstream,
    suggested_summary,
    source_payload_hash_at_review,
    review_notes
  )
  select id,
         'candidate:'||source_item_key,
         locator,
         quote_text,
         encode(digest(quote_text,'sha256'),'hex'),
         'sha256',
         case source_item_key
           when 'item-house' then 'import'::source_item_action
           when 'item-vault' then 'import'::source_item_action
           when 'item-hold' then 'hold'::source_item_action
           when 'item-exclude' then 'exclude'::source_item_action
           else 'evidence'::source_item_action
         end,
         case source_item_key
           when 'item-house' then 'HOUSE'::source_target_zone
           when 'item-vault' then 'VAULT'::source_target_zone
           when 'item-hold' then 'HOLD'::source_target_zone
           else 'EVIDENCE'::source_target_zone
         end,
         case source_item_key
           when 'item-house' then 'approved'::source_review_state
           when 'item-vault' then 'needs_review'::source_review_state
           when 'item-hold' then 'needs_review'::source_review_state
           when 'item-exclude' then 'rejected'::source_review_state
           else 'approved'::source_review_state
         end,
         case source_item_key
           when 'item-house' then 'memories'
           when 'item-vault' then 'vault_private.records'
           else null
         end,
         'fixture/project-alpha',
         'fixture',
         'Fixture summary: '||source_item_key,
         payload_hash,
         'Fixture manifest row'
  from manifest_source
  returning id
), freeze_step as (
  select source_freeze_batch(batch.id, batch.created_by, jsonb_build_object('fixture', true, 'count', 5), 'validation fixture') as result
  from batch
), probes as (
  insert into cutover_probes(
    batch_id,
    probe_key,
    probe_type,
    probe_category,
    severity,
    prompt,
    expect_substring,
    avoid_substring,
    expected_behavior,
    expected_evidence_required
  )
  select batch.id, p.probe_key, p.probe_type, p.probe_category, p.severity::cutover_probe_severity,
         p.prompt, p.expect_substring, p.avoid_substring, p.expected_behavior, p.expected_evidence_required
  from batch cross join freeze_step
  cross join (values
    ('fixture-positive-alpha', 'project-state', 'positive', 'critical', 'What did project alpha decide?', 'boring durable schema', null, 'Return the known project decision.', false),
    ('fixture-negative-unknown', 'unknown-avoidance', 'negative', 'critical', 'What is the launch date for missing project omega?', 'unknown', 'January 1', 'Say unknown or insufficient evidence; do not invent a date.', false),
    ('fixture-conflict-status', 'conflict', 'conflict', 'critical', 'Is the maybe-stale status confirmed?', 'needs review', 'confirmed current', 'Surface the unresolved status instead of flattening it into confirmed truth.', false),
    ('fixture-stale-state', 'stale-avoidance', 'stale_state', 'critical', 'What should happen to stale project state?', 'hold', 'probably current', 'Current disposition stays hold; the superseded note must not outrank it.', false),
    ('fixture-evidence-request', 'evidence', 'evidence_request', 'critical', 'Show evidence for the project alpha decision.', 'fixture source locator', null, 'Return or cite supporting evidence.', true)
  ) as p(probe_key, probe_type, probe_category, severity, prompt, expect_substring, avoid_substring, expected_behavior, expected_evidence_required)
  returning id, probe_category
), runs as (
  insert into cutover_runs(probe_id, runner_agent, matched, observed_answer, evidence_ref, notes)
  select
    cp.id,
    batch.created_by,
    cutover_probe_outcome_matched(
      cp.probe_category,
      cp.expect_substring,
      cp.avoid_substring,
      cp.expected_evidence_required,
      obs.observed_answer,
      obs.evidence_ref
    ),
    obs.observed_answer,
    obs.evidence_ref,
    'validation fixture'
  from probes
  join cutover_probes cp on cp.id = probes.id
  cross join batch
  join (values
    ('positive', 'Use the boring durable schema.', null::text),
    ('negative', 'Unknown: insufficient evidence.', null::text),
    ('conflict', 'This status needs review and should not be treated as confirmed.', null::text),
    ('stale_state', 'Hold stale or uncertain state until reviewed.', null::text),
    ('evidence_request', 'Evidence: fixture source locator supports the decision.', 'fixture://item-house.json')
  ) as obs(probe_category, observed_answer, evidence_ref)
    on obs.probe_category = cp.probe_category
  returning id
)
select count(*) as fixture_rows_created
from manifest;

do $$
declare
  v_batch_id uuid;
  v_agent text;
begin
  select b.id, b.created_by
    into v_batch_id, v_agent
  from source_import_batches b
  where b.batch_key='fixture-batch-001';

  begin
    perform source_mark_batch_ready(v_batch_id, v_agent);
    insert into source_import_fixture_results(check_group, object_name, state, severity, fatal, remediation)
    values ('smoke_test', 'source_mark_batch_ready_blocks_unresolved', 'fail', 'required', true,
            'source_mark_batch_ready should reject batches with unresolved readiness blockers.');
  exception
    when others then
      insert into source_import_fixture_results(check_group, object_name, state, severity, fatal, remediation)
      values (
        'smoke_test',
        'source_mark_batch_ready_blocks_unresolved',
        case when sqlerrm like 'source_mark_batch_ready:%blocker%' then 'pass' else 'fail' end,
        'required',
        true,
        'source_mark_batch_ready should reject batches with unresolved readiness blockers.'
      );
  end;
end $$;

update source_manifest sm
set review_state = case
      when sm.action='hold' then 'waived'::source_review_state
      when sm.review_state='needs_review' then 'approved'::source_review_state
      else sm.review_state
    end,
    reviewed_by = b.created_by,
    reviewed_at = now()
from source_items si
join source_import_batches b on b.id=si.batch_id
where sm.source_item_id=si.id
  and b.batch_key='fixture-batch-001'
  and sm.review_state in ('needs_review','unreviewed');

insert into source_import_fixture_results(check_group, object_name, state, severity, fatal, remediation)
select 'smoke_test',
       check_key,
       state,
       severity,
       severity='blocker',
       remediation
from source_readiness
where batch_key='fixture-batch-001';

insert into source_import_fixture_results(check_group, object_name, state, severity, fatal, remediation)
select 'smoke_test',
       'candidate_locator_fixture',
       case when count(*) filter (
          where action in ('import','hold')
            and source_locator <> '{}'::jsonb
            and source_quote_hash is not null
       ) = 3 then 'pass' else 'fail' end,
       'required',
       true,
       'Import/HOLD fixture candidates should carry source locators and quote hashes.'
from source_manifest sm
join source_items si on si.id=sm.source_item_id
join source_import_batches b on b.id=si.batch_id
where b.batch_key='fixture-batch-001';

insert into source_import_fixture_results(check_group, object_name, state, severity, fatal, remediation)
select 'smoke_test',
       'probe_category_fixture',
       case when count(distinct probe_category)=5 then 'pass' else 'fail' end,
       'required',
       true,
       'Fixture should define all five cutover probe categories.'
from cutover_probes cp
join source_import_batches b on b.id=cp.batch_id
where b.batch_key='fixture-batch-001';

insert into source_import_fixture_results(check_group, object_name, state, severity, fatal, remediation)
select 'smoke_test',
       'cutover_scorecard_fixture',
       case when probes_defined=5
              and positive_probes=1
              and negative_probes=1
              and conflict_probes=1
              and stale_state_probes=1
              and evidence_request_probes=1
              and probes_run=5
              and probes_passed=5
              and critical_misses=0
              and critical_not_run=0
              and critical_all_pass
         then 'pass' else 'fail' end,
       'required',
       true,
       'Cutover scorecard should reflect five passing critical probe categories.' as remediation
from cutover_scorecard cs
join source_import_batches b on b.id=cs.batch_id
where b.batch_key='fixture-batch-001';

-- Category outcomes are generic string/evidence contracts. They do not call a
-- retrieval engine. Each category has a passing observation and a failing one.
insert into source_import_fixture_results(check_group, object_name, state, severity, fatal, remediation)
select 'smoke_test',
       v.object_name,
       case when cutover_probe_outcome_matched(
              v.probe_category,
              v.expect_substring,
              v.avoid_substring,
              v.expected_evidence_required,
              v.observed_answer,
              v.evidence_ref
            ) = v.expected_match then 'pass' else 'fail' end,
       'required',
       true,
       v.remediation
from (values
  ('outcome_positive_recall', 'positive', 'boring durable schema', null::text, false,
    'Use the boring durable schema.', null::text, true,
    'Positive probes match when the expected recall is present.'),
  ('outcome_positive_missing_recall', 'positive', 'boring durable schema', null::text, false,
    'No project decision was found.', null::text, false,
    'Positive probes miss when the expected recall is absent.'),
  ('outcome_positive_unnamed_recall', 'positive', null::text, null::text, false,
    'Use the boring durable schema.', null::text, false,
    'Positive probes fail closed when no expected recall is named.'),
  ('outcome_negative_refuses', 'negative', 'unknown', 'January 1', false,
    'Unknown: insufficient evidence.', null::text, true,
    'Negative probes match when the answer refuses and does not invent the forbidden fact.'),
  ('outcome_negative_invents', 'negative', 'unknown', 'January 1', false,
    'The launch date is January 1.', null::text, false,
    'Negative probes miss when the answer invents the forbidden fact.'),
  ('outcome_negative_over_answers', 'negative', 'unknown', 'January 1', false,
    'Unknown, but the launch date is January 1.', null::text, false,
    'Negative probes miss when a refusal still includes the forbidden over-answer.'),
  ('outcome_conflict_visible', 'conflict', 'needs review', 'confirmed current', false,
    'This status needs review and both accounts stay visible.', null::text, true,
    'Conflict probes match when the tension stays visible.'),
  ('outcome_conflict_flattened', 'conflict', 'needs review', 'confirmed current', false,
    'The status is confirmed current.', null::text, false,
    'Conflict probes miss when the tension is flattened.'),
  ('outcome_stale_current_fact', 'stale_state', 'hold', 'probably current', false,
    'Hold stale or uncertain state until reviewed.', null::text, true,
    'Stale-state probes match when the current fact is present and the superseded fact is absent.'),
  ('outcome_stale_superseded_outranks', 'stale_state', 'hold', 'probably current', false,
    'The stale note is probably current.', null::text, false,
    'Stale-state probes miss when the superseded fact is returned in place of the current fact.'),
  ('outcome_stale_superseded_still_present', 'stale_state', 'hold', 'probably current', false,
    'Hold the item, but it is probably current.', null::text, false,
    'Stale-state probes miss when the superseded fact remains beside the current fact.'),
  ('outcome_stale_unnamed_superseded', 'stale_state', 'hold', null::text, false,
    'Hold stale or uncertain state until reviewed.', null::text, false,
    'Stale-state probes fail closed when the superseded fact is not named.'),
  ('outcome_evidence_cited', 'evidence_request', 'fixture source locator', null::text, true,
    'Evidence: fixture source locator supports the decision.', null::text, true,
    'Evidence-request probes match when the answer cites supporting evidence.'),
  ('outcome_evidence_returned', 'evidence_request', 'fixture source locator', null::text, true,
    'See the attached support.', 'fixture://item-house.json', true,
    'Evidence-request probes match when supporting evidence is returned by reference.'),
  ('outcome_evidence_missing', 'evidence_request', 'fixture source locator', null::text, true,
    'The decision stands without a citation.', null::text, false,
    'Evidence-request probes miss when no evidence is returned or cited.'),
  ('outcome_evidence_not_required_fails_closed', 'evidence_request', 'fixture source locator', null::text, false,
    'Evidence: fixture source locator supports the decision.', 'fixture://item-house.json', false,
    'Evidence-request probes fail closed unless evidence is required.')
) as v(
  object_name,
  probe_category,
  expect_substring,
  avoid_substring,
  expected_evidence_required,
  observed_answer,
  evidence_ref,
  expected_match,
  remediation
);

-- One critical miss at a time. The other four stay passing, so pass_pct stays
-- at 80. Readiness must still fail, and the miss remains in run history.
do $$
declare
  v_batch_id uuid;
  v_agent text;
  v_probe_id uuid;
  v_category text;
  v_expect text;
  v_avoid text;
  v_evidence_required boolean;
  v_observed text;
  v_evidence_ref text;
  v_matched boolean;
  v_pass_pct numeric;
  v_critical_all_pass boolean;
  v_critical_misses bigint;
  v_probes_passed bigint;
  v_ready_state text;
  v_blocker_count bigint;
  v_failed_history bigint;
  v_memories_before bigint;
  v_wiki_before bigint;
  v_step integer := 0;
begin
  select count(*) into v_memories_before from memories;
  select count(*) into v_wiki_before from wiki_pages;

  select b.id, b.created_by
    into v_batch_id, v_agent
  from source_import_batches b
  where b.batch_key = 'fixture-batch-001';

  for v_category, v_observed, v_evidence_ref in
    select category, observed_answer, evidence_ref
    from (values
      ('positive', 'No recalled project decision.', null::text),
      ('negative', 'The launch date is January 1.', null::text),
      ('conflict', 'The status is confirmed current.', null::text),
      ('stale_state', 'The stale note is probably current.', null::text),
      ('evidence_request', 'The decision stands without a citation.', null::text)
    ) as misses(category, observed_answer, evidence_ref)
  loop
    v_step := v_step + 1;

    select cp.id, cp.expect_substring, cp.avoid_substring, cp.expected_evidence_required
      into v_probe_id, v_expect, v_avoid, v_evidence_required
    from cutover_probes cp
    where cp.batch_id = v_batch_id
      and cp.probe_category = v_category
      and cp.active
      and cp.severity = 'critical';

    v_matched := cutover_probe_outcome_matched(
      v_category, v_expect, v_avoid, v_evidence_required, v_observed, v_evidence_ref
    );

    insert into source_import_fixture_results(check_group, object_name, state, severity, fatal, remediation)
    values (
      'smoke_test',
      'outcome_recorded_miss_' || v_category,
      case when v_matched then 'fail' else 'pass' end,
      'required',
      true,
      'The recorded ' || v_category || ' miss must fail that category outcome.'
    );

    insert into cutover_runs(probe_id, run_at, runner_agent, matched, observed_answer, evidence_ref, notes)
    values (
      v_probe_id,
      now() + (v_step * interval '1 minute'),
      v_agent,
      v_matched,
      v_observed,
      v_evidence_ref,
      'synthetic critical miss'
    );

    select cs.pass_pct, cs.critical_all_pass, cs.critical_misses, cs.probes_passed
      into v_pass_pct, v_critical_all_pass, v_critical_misses, v_probes_passed
    from cutover_scorecard cs
    where cs.batch_id = v_batch_id;

    select sr.state
      into v_ready_state
    from source_readiness sr
    where sr.batch_id = v_batch_id
      and sr.check_key = 'critical_cutover_probes_all_pass';

    select count(*)
      into v_blocker_count
    from source_readiness sr
    where sr.batch_id = v_batch_id
      and sr.severity = 'blocker'
      and sr.state = 'fail';

    insert into source_import_fixture_results(check_group, object_name, state, severity, fatal, remediation)
    values (
      'smoke_test',
      'critical_miss_visible_' || v_category,
      case
        when v_probes_passed = 4
         and v_critical_misses = 1
         and v_critical_all_pass = false
         and v_pass_pct = 80
         and v_ready_state = 'fail'
         and v_blocker_count = 1
        then 'pass' else 'fail'
      end,
      'required',
      true,
      'One critical ' || v_category || ' miss must fail readiness while pass_pct stays 80.'
    );

    begin
      perform source_mark_batch_ready(v_batch_id, v_agent);
      insert into source_import_fixture_results(check_group, object_name, state, severity, fatal, remediation)
      values (
        'smoke_test',
        'critical_miss_blocks_ready_' || v_category,
        'fail',
        'required',
        true,
        'source_mark_batch_ready must reject a batch with a critical probe miss.'
      );
    exception
      when others then
        insert into source_import_fixture_results(check_group, object_name, state, severity, fatal, remediation)
        values (
          'smoke_test',
          'critical_miss_blocks_ready_' || v_category,
          case when sqlerrm like 'source_mark_batch_ready:%blocker%' then 'pass' else 'fail' end,
          'required',
          true,
          'source_mark_batch_ready must reject a batch with a critical probe miss.'
        );
    end;

    insert into cutover_runs(probe_id, run_at, runner_agent, matched, observed_answer, evidence_ref, notes)
    select
      cr.probe_id,
      now() + (v_step * interval '1 minute') + interval '30 seconds',
      cr.runner_agent,
      cutover_probe_outcome_matched(
        cp.probe_category,
        cp.expect_substring,
        cp.avoid_substring,
        cp.expected_evidence_required,
        cr.observed_answer,
        cr.evidence_ref
      ),
      cr.observed_answer,
      cr.evidence_ref,
      'later passing run; earlier miss remains history'
    from cutover_runs cr
    join cutover_probes cp on cp.id = cr.probe_id
    where cr.probe_id = v_probe_id
      and cr.notes = 'validation fixture'
    order by cr.run_at asc
    limit 1;
  end loop;

  select cs.pass_pct, cs.critical_all_pass, cs.critical_misses, cs.probes_passed
    into v_pass_pct, v_critical_all_pass, v_critical_misses, v_probes_passed
  from cutover_scorecard cs
  where cs.batch_id = v_batch_id;

  select count(*)
    into v_failed_history
  from cutover_runs cr
  join cutover_probes cp on cp.id = cr.probe_id
  where cp.batch_id = v_batch_id
    and cr.matched = false
    and cr.notes = 'synthetic critical miss';

  insert into source_import_fixture_results(check_group, object_name, state, severity, fatal, remediation)
  values (
    'smoke_test',
    'critical_miss_history_retained',
    case
      when v_failed_history = 5
       and v_probes_passed = 5
       and v_critical_misses = 0
       and v_critical_all_pass
       and v_pass_pct = 100
      then 'pass' else 'fail'
    end,
    'required',
    true,
    'Critical misses remain run history. The latest passing runs restore all-pass readiness.'
  );

  insert into source_import_fixture_results(check_group, object_name, state, severity, fatal, remediation)
  values (
    'smoke_test',
    'probe_results_are_run_history',
    case
      when (select count(*) from memories) = v_memories_before
       and (select count(*) from wiki_pages) = v_wiki_before
      then 'pass' else 'fail'
    end,
    'required',
    true,
    'Probe outcome checks must not write canonical memories or wiki pages.'
  );
end $$;

insert into source_import_fixture_results(check_group, object_name, state, severity, fatal, remediation)
select 'smoke_test',
       'source_mark_batch_ready_after_resolution',
       case when source_mark_batch_ready(b.id, b.created_by)='ready' then 'pass' else 'fail' end,
       'required',
       true,
       'source_mark_batch_ready should mark the batch ready after blockers are resolved.'
from source_import_batches b
where b.batch_key='fixture-batch-001';

select check_group, object_name, state, severity, remediation
from source_import_fixture_results
order by check_group, object_name;

do $$
declare
  fail_count integer;
begin
  select count(*) into fail_count
  from source_import_fixture_results
  where fatal and state='fail';

  if fail_count > 0 then
    raise exception 'source import fixture validation failed: % failing check(s)', fail_count;
  end if;
end $$;

rollback;

-- ---- fatal assertion ---------------------------------------------------------
do $$
declare
  fail_count integer;
begin
  select count(*) into fail_count
  from source_import_validation_results
  where fatal and state='fail';

  if fail_count > 0 then
    raise exception 'source import validation failed: % failing check(s)', fail_count;
  end if;
end $$;
