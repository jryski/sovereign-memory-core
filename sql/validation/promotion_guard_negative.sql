-- ============================================================================
-- SOVEREIGN MEMORY :: REVIEW AND PROMOTION GUARD TESTS
-- Target: local Postgres after sql/01_core.sql, sql/04_source_import.sql, and
-- sql/06_promotion_guards.sql. The fixture transaction rolls back.
--
-- Each forbidden promotion path must fail. An approved import remains possible
-- only when an explicit review decision is recorded. Conflicts are left intact.
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

create or replace function pg_temp.expect_rejected(
  p_name text,
  p_statement text,
  p_fragment text,
  p_remediation text
) returns void
language plpgsql
as $fn$
declare
  v_sqlstate text;
  v_message text;
begin
  begin
    execute p_statement;
    insert into promotion_guard_results(check_group, object_name, state, remediation)
    values ('promotion_guard', p_name, 'fail', p_remediation || ' The attempt was accepted.');
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_message = message_text;
    insert into promotion_guard_results(check_group, object_name, state, remediation)
    values (
      'promotion_guard',
      p_name,
      case when position(p_fragment in v_message) > 0 then 'pass' else 'fail' end,
      case
        when position(p_fragment in v_message) > 0 then p_remediation
        else p_remediation || ' Observed ' || v_sqlstate || ': ' || v_message
      end
    );
  end;
end;
$fn$;

insert into promotion_guard_results(check_group, object_name, state, remediation)
select 'promotion_guard', function_name, state, 'Run sql/06_promotion_guards.sql'
from (
  values
    ('promotion_guard_candidate_message(source_item_action)',
      to_regprocedure('public.promotion_guard_candidate_message(source_item_action)') is not null),
    ('source_manifest_explicitly_reviewed(source_review_state,text,timestamptz,text)',
      to_regprocedure('public.source_manifest_explicitly_reviewed(source_review_state,text,timestamptz,text)') is not null),
    ('guard_source_manifest_promotion()',
      to_regprocedure('public.guard_source_manifest_promotion()') is not null),
    ('guard_memory_candidate_promotion()',
      to_regprocedure('public.guard_memory_candidate_promotion()') is not null),
    ('guard_source_batch_authority()',
      to_regprocedure('public.guard_source_batch_authority()') is not null)
) as v(function_name, ok)
cross join lateral (select case when ok then 'pass' else 'fail' end as state) s;

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
    ('pg-batch-forbidden'),
    ('pg-batch-package'),
    ('pg-batch-approved'),
    ('pg-batch-agent')
  ) as b(batch_key)
  returning id, batch_key
), item_seed as (
  select *
  from (values
    ('pg-batch-forbidden', 'pg-item-hold', 'pg-hold', 'hold'::source_item_action, 'HOLD'::source_target_zone,
      'needs_review'::source_review_state, null::text,
      'Synthetic HOLD candidate. Do not choose a winner.',
      '{"authored_by":"agent","conflict":"unresolved"}'::jsonb),
    ('pg-batch-forbidden', 'pg-item-exclude', 'pg-exclude', 'exclude', 'EVIDENCE',
      'rejected', null,
      'Synthetic EXCLUDE candidate kept for accounting.',
      '{"authored_by":"agent"}'::jsonb),
    ('pg-batch-forbidden', 'pg-item-evidence', 'pg-evidence', 'evidence', 'EVIDENCE',
      'approved', null,
      'Synthetic EVIDENCE candidate preserved as evidence.',
      '{"authored_by":"agent"}'::jsonb),
    ('pg-batch-package', 'pg-item-package', 'pg-package-import', 'import', 'HOUSE',
      'unreviewed', 'memories',
      'Synthetic structurally valid import candidate.',
      '{"producer_posture":"candidate_only","package_valid":true}'::jsonb),
    ('pg-batch-approved', 'pg-item-approved', 'pg-approved-import', 'import', 'HOUSE',
      'unreviewed', 'memories',
      'Synthetic import candidate awaiting explicit review.',
      '{"producer_posture":"candidate_only"}'::jsonb),
    ('pg-batch-agent', 'pg-item-agent', 'pg-agent-import', 'import', 'HOUSE',
      'unreviewed', 'memories',
      'Synthetic agent-authored candidate. Not a human decision.',
      '{"authored_by":"agent","producer":"agent"}'::jsonb)
  ) as s(batch_key, item_key, manifest_key, action, target_zone, review_state, target_table, quote_text, metadata)
), items as (
  insert into source_items(
    batch_id, source_item_key, source_container, source_kind, title, payload_hash, payload_size_bytes
  )
  select batches.id, item_seed.item_key, 'fixture/promotion-guard', 'conversation', item_seed.manifest_key,
         encode(digest(item_seed.quote_text, 'sha256'), 'hex'), length(item_seed.quote_text)
  from item_seed
  join batches on batches.batch_key = item_seed.batch_key
  returning id, source_item_key, payload_hash
), manifested as (
  insert into source_manifest(
    source_item_id, manifest_key, action, target_zone, review_state, target_table,
    topic_key, suggested_summary, suggested_content, source_locator, source_quote,
    source_quote_hash, source_quote_hash_algorithm, metadata
  )
  select items.id, item_seed.manifest_key, item_seed.action, item_seed.target_zone, item_seed.review_state,
         item_seed.target_table, 'fixture/promotion-guard', item_seed.quote_text, item_seed.quote_text,
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
where batch_key = 'pg-batch-package';

insert into promotion_guard_results(check_group, object_name, state, remediation)
select 'promotion_guard',
       'structurally_valid_package_stays_unauthoritative_after_freeze',
       case when status = 'frozen'::source_batch_status then 'pass' else 'fail' end,
       'Freezing a structurally valid package must not declare cutover authority.'
from source_import_batches
where batch_key = 'pg-batch-package';

select pg_temp.expect_rejected(
  'hold_target_zone_promotion_rejected',
  $sql$
    update source_manifest
       set target_zone = 'HOUSE'
     where manifest_key = 'pg-hold'
  $sql$,
  'source_manifest_action_zone',
  'A HOLD candidate must not be reclassified into a promotable zone.'
);

select pg_temp.expect_rejected(
  'exclude_target_zone_promotion_rejected',
  $sql$
    update source_manifest
       set target_zone = 'HOUSE'
     where manifest_key = 'pg-exclude'
  $sql$,
  'source_manifest_action_zone',
  'An EXCLUDE candidate must not be reclassified into a promotable zone.'
);

select pg_temp.expect_rejected(
  'evidence_target_zone_promotion_rejected',
  $sql$
    update source_manifest
       set target_zone = 'VAULT'
     where manifest_key = 'pg-evidence'
  $sql$,
  'source_manifest_action_zone',
  'An EVIDENCE candidate must not be reclassified into a promotable zone.'
);

select pg_temp.expect_rejected(
  'hold_target_link_rejected',
  $sql$
    update source_manifest
       set target_table = 'memories',
           target_id = gen_random_uuid()
     where manifest_key = 'pg-hold'
  $sql$,
  'promotion guard: HOLD candidate cannot be promoted',
  'A HOLD candidate must not acquire a memory target.'
);

select pg_temp.expect_rejected(
  'exclude_target_link_rejected',
  $sql$
    update source_manifest
       set target_table = 'memories',
           target_id = gen_random_uuid()
     where manifest_key = 'pg-exclude'
  $sql$,
  'promotion guard: EXCLUDE candidate cannot be promoted',
  'An EXCLUDE candidate must not acquire a memory target.'
);

select pg_temp.expect_rejected(
  'evidence_target_link_rejected',
  $sql$
    update source_manifest
       set target_table = 'memories',
           target_id = gen_random_uuid()
     where manifest_key = 'pg-evidence'
  $sql$,
  'promotion guard: EVIDENCE candidate cannot normalize into a memory fact',
  'An EVIDENCE candidate must not acquire a memory target.'
);

select pg_temp.expect_rejected(
  'hold_uncited_copy_rejected',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind)
    select suggested_content, 'shared', 'shared', 'system', 'import'
    from source_manifest
    where manifest_key = 'pg-hold'
  $sql$,
  'promotion guard: HOLD candidate cannot be promoted',
  'Copying HOLD candidate text without a manifest citation must not promote it.'
);

select pg_temp.expect_rejected(
  'exclude_uncited_copy_rejected',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind)
    select suggested_summary, 'shared', 'shared', 'system', 'manual'
    from source_manifest
    where manifest_key = 'pg-exclude'
  $sql$,
  'promotion guard: EXCLUDE candidate cannot be promoted',
  'Copying EXCLUDE candidate text must not turn it into memory.'
);

select pg_temp.expect_rejected(
  'evidence_uncited_copy_rejected',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind)
    select suggested_content, 'shared', 'shared', 'system', 'import'
    from source_manifest
    where manifest_key = 'pg-evidence'
  $sql$,
  'promotion guard: EVIDENCE candidate cannot normalize into a memory fact',
  'Copying EVIDENCE candidate text must not normalize it into a memory fact.'
);

select pg_temp.expect_rejected(
  'hold_memory_insert_rejected',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
    select 'Synthetic HOLD candidate. Do not choose a winner.',
           'shared', 'shared', 'system', 'import',
           jsonb_build_object('source_manifest_id', id::text)
    from source_manifest
    where manifest_key = 'pg-hold'
  $sql$,
  'promotion guard: HOLD candidate cannot be promoted',
  'A HOLD candidate must not normalize into memories.'
);

select pg_temp.expect_rejected(
  'exclude_memory_insert_rejected',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
    select 'Synthetic EXCLUDE candidate kept for accounting.',
           'shared', 'shared', 'system', 'import',
           jsonb_build_object('source_manifest_id', id::text)
    from source_manifest
    where manifest_key = 'pg-exclude'
  $sql$,
  'promotion guard: EXCLUDE candidate cannot be promoted',
  'An EXCLUDE candidate must not become memory.'
);

select pg_temp.expect_rejected(
  'evidence_memory_insert_rejected',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
    select 'Synthetic EVIDENCE candidate preserved as evidence.',
           'shared', 'shared', 'system', 'import',
           jsonb_build_object('source_manifest_id', id::text)
    from source_manifest
    where manifest_key = 'pg-evidence'
  $sql$,
  'promotion guard: EVIDENCE candidate cannot normalize into a memory fact',
  'An EVIDENCE candidate must not normalize into a memory fact.'
);

update source_manifest
   set review_state = 'approved'
 where manifest_key = 'pg-hold';

select pg_temp.expect_rejected(
  'hold_approval_does_not_promote',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
    select suggested_content, 'shared', 'shared', 'system', 'import',
           jsonb_build_object('source_manifest_id', id::text)
    from source_manifest
    where manifest_key = 'pg-hold'
  $sql$,
  'promotion guard: HOLD candidate cannot be promoted',
  'Approving a HOLD candidate must not promote it into memory.'
);

select pg_temp.expect_rejected(
  'evidence_approval_does_not_normalize',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind, status, metadata)
    select suggested_content, 'shared', 'shared', 'system', 'import', 'active',
           jsonb_build_object('source_manifest_id', id::text, 'basis', 'human_direct')
    from source_manifest
    where manifest_key = 'pg-evidence'
  $sql$,
  'promotion guard: EVIDENCE candidate cannot normalize into a memory fact',
  'An approved EVIDENCE disposition must remain evidence, not a memory fact.'
);

select pg_temp.expect_rejected(
  'hold_blocks_authority_declaration',
  $sql$
    update source_import_batches
       set status = 'cutover'
     where batch_key = 'pg-batch-forbidden'
  $sql$,
  'promotion guard: HOLD candidate cannot be promoted',
  'An open HOLD candidate must block an authority declaration.'
);

select pg_temp.expect_rejected(
  'structurally_valid_package_cutover_rejected',
  $sql$
    update source_import_batches
       set status = 'cutover'
     where batch_key = 'pg-batch-package'
  $sql$,
  'promotion guard: structurally valid package cannot become authoritative without explicit review',
  'A structurally valid unreviewed package must not become authoritative.'
);

select pg_temp.expect_rejected(
  'unreviewed_import_uncited_copy_rejected',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind)
    select suggested_content, 'shared', 'shared', 'system', 'import'
    from source_manifest
    where manifest_key = 'pg-package-import'
  $sql$,
  'promotion guard: import candidate cannot become memory without explicit review',
  'A structurally valid import must not become memory by copying its text.'
);

select pg_temp.expect_rejected(
  'unreviewed_import_memory_rejected',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
    select suggested_content, 'shared', 'shared', 'system', 'import',
           jsonb_build_object('source_manifest_id', id::text)
    from source_manifest
    where manifest_key = 'pg-package-import'
  $sql$,
  'promotion guard: import candidate cannot become memory without explicit review',
  'Structural validity must not promote an unreviewed import.'
);

select pg_temp.expect_rejected(
  'unreviewed_import_target_rejected',
  $sql$
    update source_manifest
       set target_id = gen_random_uuid()
     where manifest_key = 'pg-approved-import'
  $sql$,
  'promotion guard: import candidate cannot become memory without explicit review',
  'An import target_id requires an explicit review decision.'
);

update source_manifest
   set review_state = 'approved'
 where manifest_key = 'pg-approved-import';

select pg_temp.expect_rejected(
  'approved_state_without_reviewer_rejected',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
    select suggested_content, 'shared', 'shared', 'system', 'import',
           jsonb_build_object('source_manifest_id', id::text)
    from source_manifest
    where manifest_key = 'pg-approved-import'
  $sql$,
  'promotion guard: import candidate cannot become memory without explicit review',
  'review_state=approved alone is not an explicit review decision.'
);

update source_manifest
   set reviewed_by = 'system',
       reviewed_at = now()
 where manifest_key = 'pg-approved-import';

select pg_temp.expect_rejected(
  'review_without_decision_note_rejected',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
    select suggested_content, 'shared', 'shared', 'system', 'import',
           jsonb_build_object('source_manifest_id', id::text)
    from source_manifest
    where manifest_key = 'pg-approved-import'
  $sql$,
  'promotion guard: import candidate cannot become memory without explicit review',
  'A reviewer stamp without a review decision must not promote an import.'
);

select pg_temp.expect_rejected(
  'agent_human_basis_without_review_rejected',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
    values (
      'Agent summary presented as a human decision.',
      'shared', 'shared', 'example-user-claude', 'agent',
      '{"basis":"human_direct","authority":"human"}'::jsonb
    )
  $sql$,
  'promotion guard: agent-authored content cannot become human authority without explicit review',
  'Agent-authored content must not claim human authority without explicit review.'
);

select pg_temp.expect_rejected(
  'agent_labeled_human_without_review_rejected',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
    values (
      'Agent text stored as a human decision.',
      'shared', 'shared', 'example-user-claude', 'human',
      '{"authored_by":"agent","basis":"human_direct"}'::jsonb
    )
  $sql$,
  'promotion guard: agent-authored content cannot become human authority without explicit review',
  'Relabeling agent-authored content as human requires explicit review.'
);

select pg_temp.expect_rejected(
  'memory_receipt_cannot_bypass_unreviewed_agent_candidate',
  $sql$
    insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
    select suggested_content, 'shared', 'shared', 'example-user-claude', 'human',
           jsonb_build_object(
             'source_manifest_id', id::text,
             'authored_by', 'agent',
             'basis', 'human_direct',
             'explicit_review', 'true',
             'reviewed_by', 'example-user',
             'reviewed_at', '2026-07-08T00:00:00Z'
           )
    from source_manifest
    where manifest_key = 'pg-agent-import'
  $sql$,
  'promotion guard: import candidate cannot become memory without explicit review',
  'A memory-local receipt must not bypass review of an agent-authored candidate.'
);

insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
values (
  'Ordinary agent proposal that does not claim human authority.',
  'shared', 'shared', 'example-user-claude', 'agent', '{}'::jsonb
);

insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
values (
  'Synthetic human note with no agent authorship claim.',
  'shared', 'shared', 'system', 'human', '{"basis":"human_direct"}'::jsonb
);

select remember(
  'Promotion guard control: agent proposal that does not claim human authority.',
  'fixture',
  'fixture/promotion-guard-control',
  'system',
  'shared'
);

insert into promotion_guard_results(check_group, object_name, state, remediation)
select 'promotion_guard',
       'agent_proposal_without_human_claim_allowed',
       case when count(*) = 2 then 'pass' else 'fail' end,
       'Agent-authored rows that do not claim human authority must still be writable.'
from memories
where content in (
  'Ordinary agent proposal that does not claim human authority.',
  'Promotion guard control: agent proposal that does not claim human authority.'
)
  and source_kind = 'agent';

insert into promotion_guard_results(check_group, object_name, state, remediation)
select 'promotion_guard',
       'human_note_without_agent_authorship_allowed',
       case when count(*) = 1 then 'pass' else 'fail' end,
       'A human note that does not claim agent authorship must still be writable.'
from memories
where content = 'Synthetic human note with no agent authorship claim.'
  and source_kind = 'human';

update source_manifest
   set review_notes = 'Explicit review decision for the fixture import.'
 where manifest_key = 'pg-approved-import';

insert into memories(content, owner, visibility, source_agent, source_kind, status, metadata)
select suggested_content, 'shared', 'shared', 'system', 'import', 'active',
       jsonb_build_object('source_manifest_id', id::text)
from source_manifest
where manifest_key = 'pg-approved-import';

update source_manifest sm
   set target_id = m.id
  from memories m
 where sm.manifest_key = 'pg-approved-import'
   and m.metadata->>'source_manifest_id' = sm.id::text;

update source_import_batches
   set status = 'cutover'
 where batch_key = 'pg-batch-approved';

insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
values (
  'Agent text accepted as human authority after explicit review.',
  'shared', 'shared', 'example-user-claude', 'human',
  jsonb_build_object(
    'authored_by', 'agent',
    'basis', 'human_direct',
    'explicit_review', 'true',
    'reviewed_by', 'example-user',
    'reviewed_at', '2026-07-08T00:00:00Z'
  )
);

update source_manifest
   set review_state = 'approved',
       reviewed_by = 'system',
       reviewed_at = now(),
       review_notes = 'Explicit review decision recorded for the agent-authored candidate.'
 where manifest_key = 'pg-agent-import';

insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
select suggested_content, 'shared', 'shared', 'example-user-claude', 'human',
       jsonb_build_object(
         'source_manifest_id', id::text,
         'authored_by', 'agent',
         'basis', 'human_direct'
       )
from source_manifest
where manifest_key = 'pg-agent-import';

insert into promotion_guard_results(check_group, object_name, state, remediation)
select 'promotion_guard',
       'explicit_review_import_promotes',
       case when count(*) = 1 then 'pass' else 'fail' end,
       'An import promotes only after review_state, reviewer, time, and decision note are all present.'
from memories m
join source_manifest sm on sm.id::text = m.metadata->>'source_manifest_id'
where sm.manifest_key = 'pg-approved-import'
  and m.source_kind = 'import'
  and m.status = 'active'
  and sm.target_id = m.id
  and source_manifest_explicitly_reviewed(sm.review_state, sm.reviewed_by, sm.reviewed_at, sm.review_notes);

insert into promotion_guard_results(check_group, object_name, state, remediation)
select 'promotion_guard',
       'explicit_review_allows_authority_declaration',
       case when status = 'cutover'::source_batch_status then 'pass' else 'fail' end,
       'Cutover authority remains available after an explicit review decision.'
from source_import_batches
where batch_key = 'pg-batch-approved';

insert into promotion_guard_results(check_group, object_name, state, remediation)
select 'promotion_guard',
       'agent_explicit_review_can_record_human_authority',
       case when count(*) = 2 then 'pass' else 'fail' end,
       'Agent-authored content can be recorded as human authority only with explicit review, and authorship stays visible.'
from memories
where metadata->>'authored_by' = 'agent'
  and source_kind = 'human'
  and (
    content = 'Agent text accepted as human authority after explicit review.'
    or content = 'Synthetic agent-authored candidate. Not a human decision.'
  );

insert into promotion_guard_results(check_group, object_name, state, remediation)
select 'promotion_guard',
       'package_batch_remains_frozen',
       case when status = 'frozen'::source_batch_status then 'pass' else 'fail' end,
       'A rejected cutover attempt must leave the structurally valid package unauthoritative.'
from source_import_batches
where batch_key = 'pg-batch-package';

insert into promotion_guard_results(check_group, object_name, state, remediation)
select 'promotion_guard',
       'forbidden_candidates_have_no_memory',
       case when count(*) = 0 then 'pass' else 'fail' end,
       'HOLD, EXCLUDE, and EVIDENCE candidates must not be referenced by memories.'
from memories m
join source_manifest sm on sm.id::text = m.metadata->>'source_manifest_id'
where sm.manifest_key in ('pg-hold', 'pg-exclude', 'pg-evidence');

insert into promotion_guard_results(check_group, object_name, state, remediation)
select 'promotion_guard',
       'hold_conflict_not_silently_resolved',
       case when action = 'hold'::source_item_action
              and target_zone = 'HOLD'::source_target_zone
              and target_id is null
              and target_table is null
              and suggested_content = 'Synthetic HOLD candidate. Do not choose a winner.'
              and metadata->>'conflict' = 'unresolved'
            then 'pass' else 'fail' end,
       'A HOLD conflict must remain a HOLD conflict when another candidate is reviewed.'
from source_manifest
where manifest_key = 'pg-hold';

insert into promotion_guard_results(check_group, object_name, state, remediation)
select 'promotion_guard',
       'exclude_and_evidence_not_relinked',
       case when count(*) = 2 then 'pass' else 'fail' end,
       'EXCLUDE and EVIDENCE rows must keep a null memory target.'
from source_manifest
where manifest_key in ('pg-exclude', 'pg-evidence')
  and target_id is null
  and target_table is null
  and action in ('exclude'::source_item_action, 'evidence'::source_item_action);

select object_name, state, remediation
from promotion_guard_results
order by object_name;

do $$
declare
  fail_count integer;
begin
  select count(*) into fail_count
  from promotion_guard_results
  where state is distinct from 'pass';

  if fail_count > 0 then
    raise exception 'promotion guard validation failed: % failing check(s)', fail_count;
  end if;
end $$;

rollback;
