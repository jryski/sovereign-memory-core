-- ============================================================================
-- SOVEREIGN MEMORY :: SOURCE IMPORT READINESS VALIDATION
-- Target: local Postgres after sql/01_core.sql and sql/04_source_import.sql.
--
-- This script is intentionally read-mostly. The smoke test runs in a transaction
-- and rolls back so it can be used repeatedly on a local validation database.
-- ============================================================================

set search_path to public, extensions;

-- ---- object inventory --------------------------------------------------------
select 'required_object' as check_group, object_name, state, remediation
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
cross join lateral (select case when ok then 'pass' else 'fail' end as state) s
order by object_name;

-- ---- function search_path posture ------------------------------------------
select 'function_posture' as check_group,
       p.proname as object_name,
       case when array_to_string(coalesce(p.proconfig,'{}'::text[]), ',') like '%search_path=public%' then 'pass' else 'fail' end as state,
       'SECURITY DEFINER functions must pin search_path.' as remediation
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('source_freeze_batch','source_manifest_payload_drift','source_mark_batch_ready')
order by p.proname;

-- ---- grant posture -----------------------------------------------------------
select 'grant_posture' as check_group,
       'table_or_view_grants' as object_name,
       case when count(*)=0 then 'pass' else 'fail' end as state,
       'Revoke table/view privileges from PUBLIC, anon, and authenticated.' as remediation
from information_schema.role_table_grants
where table_schema='public'
  and table_name in (
    'source_systems','source_import_batches','source_items','source_payload_evidence',
    'source_manifest','source_manifest_review_queue','source_readiness',
    'cutover_probes','cutover_runs','cutover_scorecard'
  )
  and grantee in ('PUBLIC','anon','authenticated');

select 'grant_posture' as check_group,
       'function_execute_grants' as object_name,
       case when count(*)=0 then 'pass' else 'fail' end as state,
       'Revoke function execute privileges from PUBLIC, anon, and authenticated.' as remediation
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace and n.nspname='public'
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f',p.proowner))) acl
where p.proname in ('source_freeze_batch','source_manifest_payload_drift','source_mark_batch_ready')
  and acl.privilege_type='EXECUTE'
  and acl.grantee::regrole::text in ('anon','authenticated','-');

-- ---- smoke test --------------------------------------------------------------
-- This section proves the contract can stage, manifest, review, freeze, score,
-- and block readiness. It rolls back all fixture rows.

begin;

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
    ('item-house','chatgpt/project-alpha','conversation','Project alpha decision','{"kind":"conversation","decision":"Use the boring durable schema."}'),
    ('item-vault','chatgpt/project-health','conversation','Sensitive health note','{"kind":"conversation","health":"review required"}'),
    ('item-hold','claude/project-alpha','conversation','Maybe stale status','{"kind":"conversation","status":"probably current?"}'),
    ('item-evidence','model/channel','message','Peer review note','{"kind":"message","note":"model review"}'),
    ('item-exclude','chatgpt/project-alpha','conversation','Duplicate throwaway chat','{"kind":"conversation","duplicate":true}')
  ) as x(item_key, container, kind, title, payload)
  returning id, source_item_key, payload_hash
), evidence as (
  insert into source_payload_evidence(source_item_id, evidence_kind, location, payload_hash, size_bytes, content_preview)
  select id, 'raw_payload', 'fixture://'||source_item_key||'.json', payload_hash, 128, source_item_key
  from items
  returning id
), manifest as (
  insert into source_manifest(source_item_id, action, target_zone, review_state, target_table, topic_key, workstream, suggested_summary, source_payload_hash_at_review, review_notes)
  select id,
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
  from items
  returning id
), freeze_step as (
  select source_freeze_batch(batch.id, batch.created_by, jsonb_build_object('fixture', true, 'count', 5), 'validation fixture') as result
  from batch
), probe as (
  insert into cutover_probes(batch_id, probe_key, probe_type, severity, prompt, expect_substring)
  select batch.id, 'fixture-alpha-decision', 'project-state', 'critical', 'What did project alpha decide?', 'boring durable schema'
  from batch cross join freeze_step
  returning id
), run as (
  insert into cutover_runs(probe_id, runner_agent, matched, observed_answer, notes)
  select probe.id, batch.created_by, true, 'Use the boring durable schema.', 'validation fixture'
  from probe cross join batch
  returning id
)
select 'smoke_test' as check_group,
       check_key as object_name,
       state,
       remediation
from source_readiness
where batch_key='fixture-batch-001'
order by check_key;

select 'smoke_test' as check_group,
       'cutover_scorecard_fixture' as object_name,
       case when probes_defined=1 and probes_run=1 and probes_passed=1 and critical_misses=0 then 'pass' else 'fail' end as state,
       'Cutover scorecard should reflect one passing critical probe.' as remediation
from cutover_scorecard cs
join source_import_batches b on b.id=cs.batch_id
where b.batch_key='fixture-batch-001';

rollback;
