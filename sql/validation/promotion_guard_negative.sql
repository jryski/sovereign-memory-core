-- ============================================================================
-- SOVEREIGN MEMORY :: REVIEW AND PROMOTION GUARD TESTS
-- Target: local Postgres after sql/01_core.sql and sql/04_source_import.sql.
-- Optional sql/05 and sql/06 layers may also be installed. This script does not
-- install schema. The fixture transaction rolls back.
--
-- Five forbidden promotion paths. Each one must fail closed on the existing
-- source-import contract: a promotable zone change is rejected, and staging or
-- freezing a candidate does not create a memory fact or cutover authority.
-- ============================================================================

\set ON_ERROR_STOP on
set search_path to public, extensions;

begin;

create temp table promotion_guard_results (
  check_group text not null,
  object_name text not null,
  state text not null check (state in ('pass', 'fail')),
  remediation text not null
) on commit drop;

with agent as (
  select agent_id
  from trusted_agents
  where agent_id = 'system' and active
), sys as (
  insert into source_systems(source_key, display_name, source_type, adapter_name, adapter_version)
  select 'promotion-guard-fixture', 'Promotion Guard Fixture', 'ai-export', 'fixture-adapter', '0.0.1'
  from agent
  returning id
), batches as (
  insert into source_import_batches(
    source_system_id, batch_key, source_item_count, exported_item_count, created_by, package_checksum
  )
  select sys.id, batch_key, 1, 1, agent.agent_id, 'promotion-guard-fixture-checksum'
  from sys
  cross join agent
  cross join (values
    ('pg-batch-hold'),
    ('pg-batch-exclude'),
    ('pg-batch-evidence'),
    ('pg-batch-package'),
    ('pg-batch-agent')
  ) as b(batch_key)
  returning id, batch_key, created_by
), item_seed as (
  select *
  from (values
    ('pg-batch-hold', 'pg-item-hold', 'pg-hold', 'hold'::source_item_action, 'HOLD'::source_target_zone,
      'needs_review'::source_review_state,
      'Synthetic HOLD candidate. Do not choose a winner.',
      '{"authored_by":"agent","conflict":"unresolved"}'::jsonb),
    ('pg-batch-exclude', 'pg-item-exclude', 'pg-exclude', 'exclude', 'EVIDENCE',
      'rejected',
      'Synthetic EXCLUDE candidate kept for accounting.',
      '{"authored_by":"agent"}'::jsonb),
    ('pg-batch-evidence', 'pg-item-evidence', 'pg-evidence', 'evidence', 'EVIDENCE',
      'unreviewed',
      'Synthetic EVIDENCE candidate preserved as evidence.',
      '{"authored_by":"agent"}'::jsonb),
    ('pg-batch-package', 'pg-item-package', 'pg-package-import', 'import', 'HOUSE',
      'unreviewed',
      'Synthetic structurally valid import candidate.',
      '{"producer_posture":"candidate_only","package_valid":true}'::jsonb),
    ('pg-batch-agent', 'pg-item-agent', 'pg-agent-import', 'import', 'HOUSE',
      'unreviewed',
      'Synthetic agent-authored candidate. Not a human decision.',
      '{"authored_by":"agent","producer":"agent"}'::jsonb)
  ) as s(batch_key, item_key, manifest_key, action, target_zone, review_state, quote_text, metadata)
), items as (
  insert into source_items(
    batch_id, source_item_key, source_container, source_kind, title, payload_hash, payload_size_bytes
  )
  select batches.id, item_seed.item_key, 'fixture/promotion-guard', 'conversation', item_seed.manifest_key,
         encode(digest(item_seed.quote_text, 'sha256'), 'hex'), length(item_seed.quote_text)
  from item_seed
  join batches on batches.batch_key = item_seed.batch_key
  returning id, source_item_key
), manifested as (
  insert into source_manifest(
    source_item_id, manifest_key, action, target_zone, review_state,
    target_table, topic_key, suggested_summary, suggested_content,
    source_locator, source_quote, source_quote_hash, source_quote_hash_algorithm, metadata
  )
  select items.id, item_seed.manifest_key, item_seed.action, item_seed.target_zone, item_seed.review_state,
         case when item_seed.action = 'import' then 'memories' else null end,
         'fixture/promotion-guard', item_seed.quote_text, item_seed.quote_text,
         jsonb_build_object('scheme', 'fixture', 'path', jsonb_build_array('promotion-guard', item_seed.manifest_key)),
         item_seed.quote_text, encode(digest(item_seed.quote_text, 'sha256'), 'hex'), 'sha256', item_seed.metadata
  from item_seed
  join items on items.source_item_key = item_seed.item_key
  returning id
)
select count(*) as promotion_guard_candidates_staged from manifested;

select source_freeze_batch(
  id,
  created_by,
  jsonb_build_object('fixture', true, 'structurally_valid', true),
  'promotion guard fixture freeze'
)
from source_import_batches
where batch_key in ('pg-batch-package', 'pg-batch-agent');

do $$
declare
  v_rejected boolean := false;
  v_message text;
begin
  begin
    update source_manifest
       set target_zone = 'HOUSE'
     where manifest_key = 'pg-hold';
  exception when others then
    get stacked diagnostics v_message = message_text;
    v_rejected := position('source_manifest_action_zone' in v_message) > 0;
  end;

  insert into promotion_guard_results(check_group, object_name, state, remediation)
  select 'promotion_guard',
         'hold_candidate_cannot_promote',
         case
           when v_rejected
            and sm.action = 'hold'
            and sm.target_zone = 'HOLD'
            and sm.target_id is null
            and sm.target_table is null
            and not exists (
              select 1 from memories m
              where m.content = sm.suggested_content
                 or m.metadata->>'source_manifest_id' = sm.id::text
            )
           then 'pass' else 'fail'
         end,
         'A HOLD candidate must not be reclassified into a promotable zone or become a memory.'
  from source_manifest sm
  where sm.manifest_key = 'pg-hold';
end $$;

do $$
declare
  v_rejected boolean := false;
  v_message text;
begin
  begin
    update source_manifest
       set target_zone = 'HOUSE'
     where manifest_key = 'pg-exclude';
  exception when others then
    get stacked diagnostics v_message = message_text;
    v_rejected := position('source_manifest_action_zone' in v_message) > 0;
  end;

  insert into promotion_guard_results(check_group, object_name, state, remediation)
  select 'promotion_guard',
         'exclude_candidate_cannot_promote',
         case
           when v_rejected
            and sm.action = 'exclude'
            and sm.target_zone = 'EVIDENCE'
            and sm.target_id is null
            and sm.target_table is null
            and not exists (
              select 1 from memories m
              where m.content = sm.suggested_content
                 or m.metadata->>'source_manifest_id' = sm.id::text
            )
           then 'pass' else 'fail'
         end,
         'An EXCLUDE candidate must not be reclassified into a promotable zone or become memory.'
  from source_manifest sm
  where sm.manifest_key = 'pg-exclude';
end $$;

do $$
declare
  v_rejected boolean := false;
  v_message text;
begin
  begin
    update source_manifest
       set target_zone = 'VAULT'
     where manifest_key = 'pg-evidence';
  exception when others then
    get stacked diagnostics v_message = message_text;
    v_rejected := position('source_manifest_action_zone' in v_message) > 0;
  end;

  update source_manifest
     set review_state = 'approved'
   where manifest_key = 'pg-evidence';

  insert into promotion_guard_results(check_group, object_name, state, remediation)
  select 'promotion_guard',
         'evidence_candidate_cannot_normalize_into_memory_fact',
         case
           when v_rejected
            and sm.action = 'evidence'
            and sm.target_zone = 'EVIDENCE'
            and sm.review_state = 'approved'
            and sm.target_id is null
            and sm.target_table is null
            and not exists (
              select 1 from memories m
              where m.content = sm.suggested_content
                 or m.metadata->>'source_manifest_id' = sm.id::text
            )
           then 'pass' else 'fail'
         end,
         'Approving an EVIDENCE candidate must keep it evidence and must not create a memory fact.'
  from source_manifest sm
  where sm.manifest_key = 'pg-evidence';
end $$;

do $$
declare
  v_rejected boolean := false;
  v_message text;
  v_batch uuid;
  v_agent text;
begin
  select id, created_by into v_batch, v_agent
  from source_import_batches
  where batch_key = 'pg-batch-package';

  begin
    perform source_mark_batch_ready(v_batch, v_agent);
  exception when others then
    get stacked diagnostics v_message = message_text;
    v_rejected := position('source_mark_batch_ready:' in v_message) > 0
      and position('blocker' in v_message) > 0;
  end;

  insert into promotion_guard_results(check_group, object_name, state, remediation)
  select 'promotion_guard',
         'structurally_valid_package_cannot_cause_authority',
         case
           when v_rejected
            and b.status = 'frozen'
            and sm.review_state = 'unreviewed'
            and sm.reviewed_by is null
            and sm.reviewed_at is null
            and sm.target_id is null
            and sm.source_locator <> '{}'::jsonb
            and sm.source_quote_hash is not null
            and not exists (
              select 1 from memories m
              where m.content = sm.suggested_content
                 or m.metadata->>'source_manifest_id' = sm.id::text
            )
           then 'pass' else 'fail'
         end,
         'A structurally valid unreviewed package must stay frozen and must not become memory or cutover authority.'
  from source_import_batches b
  join source_items si on si.batch_id = b.id
  join source_manifest sm on sm.source_item_id = si.id
  where b.batch_key = 'pg-batch-package'
    and sm.manifest_key = 'pg-package-import';
end $$;

do $$
declare
  v_rejected boolean := false;
  v_message text;
  v_batch uuid;
  v_agent text;
begin
  select id, created_by into v_batch, v_agent
  from source_import_batches
  where batch_key = 'pg-batch-agent';

  begin
    perform source_mark_batch_ready(v_batch, v_agent);
  exception when others then
    get stacked diagnostics v_message = message_text;
    v_rejected := position('source_mark_batch_ready:' in v_message) > 0
      and position('blocker' in v_message) > 0;
  end;

  insert into promotion_guard_results(check_group, object_name, state, remediation)
  select 'promotion_guard',
         'agent_authored_content_cannot_become_human_authority_without_explicit_review',
         case
           when v_rejected
            and b.status = 'frozen'
            and sm.review_state = 'unreviewed'
            and sm.reviewed_by is null
            and sm.reviewed_at is null
            and sm.metadata->>'authored_by' = 'agent'
            and sm.target_id is null
            and not exists (
              select 1 from memories m
              where m.content = sm.suggested_content
                 or m.metadata->>'source_manifest_id' = sm.id::text
                 or (m.source_kind = 'human' and m.metadata->>'authored_by' = 'agent')
            )
           then 'pass' else 'fail'
         end,
         'Agent-authored content must stay unreviewed and must not become a human-authority memory without explicit review.'
  from source_import_batches b
  join source_items si on si.batch_id = b.id
  join source_manifest sm on sm.source_item_id = si.id
  where b.batch_key = 'pg-batch-agent'
    and sm.manifest_key = 'pg-agent-import';
end $$;

select object_name, state, remediation
from promotion_guard_results
order by object_name;

do $$
declare
  fail_count integer;
  check_count integer;
begin
  select count(*) into check_count from promotion_guard_results;
  select count(*) into fail_count
  from promotion_guard_results
  where state is distinct from 'pass';

  if check_count <> 5 or fail_count > 0 then
    raise exception
      'promotion guard validation failed: % check(s), % failing',
      check_count, fail_count;
  end if;
end $$;

rollback;
