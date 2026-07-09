\set ON_ERROR_STOP on

begin;

create temp table chat_mine_package_input (
  payload jsonb not null
) on commit drop;

insert into chat_mine_package_input(payload)
values (:'package_json'::jsonb);

create temp table chat_mine_source_system_map on commit drop as
with inserted as (
  insert into source_systems(
    source_key,
    display_name,
    source_type,
    adapter_name,
    adapter_version,
    description,
    owner,
    visibility,
    active,
    metadata
  )
  select
    source->>'source_key',
    source->>'display_name',
    source->>'source_type',
    source->>'adapter_name',
    source->>'adapter_version',
    source->>'description',
    source->>'owner',
    source->>'visibility',
    (source->>'active')::boolean,
    source->'metadata'
  from chat_mine_package_input
  cross join lateral (select payload->'source_system' as source) value
  returning id, source_key
)
select id, source_key from inserted;

create temp table chat_mine_batch_map on commit drop as
with inserted as (
  insert into source_import_batches(
    source_system_id,
    batch_key,
    status,
    export_started_at,
    export_completed_at,
    watermark,
    source_item_count,
    exported_item_count,
    payload_hash_algorithm,
    package_checksum,
    metadata
  )
  select
    source_map.id,
    batch->>'batch_key',
    (batch->>'status')::source_batch_status,
    (batch->>'export_started_at')::timestamptz,
    (batch->>'export_completed_at')::timestamptz,
    batch->'watermark',
    (batch->>'source_item_count')::integer,
    (batch->>'exported_item_count')::integer,
    batch->>'payload_hash_algorithm',
    package.payload->>'package_checksum',
    batch->'metadata'
  from chat_mine_package_input package
  cross join chat_mine_source_system_map source_map
  cross join lateral (select package.payload->'batch' as batch) value
  returning id, batch_key
)
select id, batch_key from inserted;

create temp table chat_mine_source_item_map on commit drop as
with inserted as (
  insert into source_items(
    batch_id,
    source_item_key,
    source_container,
    source_kind,
    source_created_at,
    source_updated_at,
    content_type,
    title,
    payload_hash,
    payload_size_bytes,
    raw_payload_location,
    source_ref,
    metadata
  )
  select
    batch_map.id,
    item->>'source_item_key',
    item->>'source_container',
    item->>'source_kind',
    (item->>'source_created_at')::timestamptz,
    (item->>'source_updated_at')::timestamptz,
    item->>'content_type',
    item->>'title',
    item->>'payload_hash',
    (item->>'payload_size_bytes')::bigint,
    item->>'raw_payload_location',
    item->>'source_ref',
    item->'metadata'
  from chat_mine_package_input package
  cross join chat_mine_batch_map batch_map
  cross join lateral jsonb_array_elements(package.payload->'source_items') item
  returning id, source_item_key
)
select id, source_item_key from inserted;

insert into source_payload_evidence(
  source_item_id,
  evidence_kind,
  location,
  payload_hash,
  hash_algorithm,
  size_bytes,
  content_preview,
  metadata
)
select
  item_map.id,
  evidence->>'evidence_kind',
  evidence->>'location',
  evidence->>'payload_hash',
  evidence->>'hash_algorithm',
  (evidence->>'size_bytes')::bigint,
  evidence->>'content_preview',
  evidence->'metadata'
from chat_mine_package_input package
cross join lateral jsonb_array_elements(package.payload->'source_items') item
join chat_mine_source_item_map item_map
  on item_map.source_item_key=item->>'source_item_key'
cross join lateral jsonb_array_elements(item->'payload_evidence') evidence;

insert into source_manifest(
  source_item_id,
  manifest_key,
  action,
  target_zone,
  review_state,
  target_table,
  topic_key,
  suggested_summary,
  suggested_content,
  transformation_version,
  review_notes,
  metadata,
  source_locator,
  source_quote,
  source_quote_hash,
  source_quote_hash_algorithm
)
select
  item_map.id,
  candidate->>'manifest_key',
  (candidate->>'action')::source_item_action,
  (candidate->>'target_zone')::source_target_zone,
  (candidate->>'review_state')::source_review_state,
  candidate->>'target_table',
  candidate->>'topic_key',
  candidate->>'suggested_summary',
  candidate->>'suggested_content',
  candidate->>'transformation_version',
  candidate->>'review_notes',
  candidate->'metadata',
  coalesce(candidate->'source_locator', '{}'::jsonb),
  candidate->>'source_quote',
  candidate->>'source_quote_hash',
  candidate->>'source_quote_hash_algorithm'
from chat_mine_package_input package
cross join lateral jsonb_array_elements(package.payload->'source_items') item
join chat_mine_source_item_map item_map
  on item_map.source_item_key=item->>'source_item_key'
cross join lateral jsonb_array_elements(item->'manifest_candidates') candidate;

insert into cutover_probes(
  batch_id,
  probe_key,
  probe_type,
  probe_category,
  severity,
  prompt,
  expect_topic_key,
  expected_source_item_id,
  expected_behavior,
  expected_evidence_required,
  active,
  metadata
)
select
  batch_map.id,
  probe->>'probe_key',
  probe->>'probe_type',
  probe->>'probe_category',
  (probe->>'severity')::cutover_probe_severity,
  probe->>'prompt',
  probe->>'expect_topic_key',
  item_map.id,
  probe->>'expected_behavior',
  (probe->>'expected_evidence_required')::boolean,
  coalesce((probe->>'active')::boolean, true),
  coalesce(probe->'metadata', '{}'::jsonb)
from chat_mine_package_input package
cross join chat_mine_batch_map batch_map
cross join lateral jsonb_array_elements(package.payload->'cutover_probes') probe
left join chat_mine_source_item_map item_map
  on item_map.source_item_key=probe->>'expected_source_item_key';

do $$
declare
  source_system_count integer;
  batch_count integer;
  item_count integer;
  evidence_count integer;
  candidate_count integer;
  probe_count integer;
  payload_hash_mismatches integer;
  evidence_hash_mismatches integer;
  candidate_quote_hash_mismatches integer;
  duplicate_manifest_keys integer;
  candidate_locator_gaps integer;
  active_probe_categories integer;
  package_probe_count integer;
  readiness_states jsonb;
begin
  select jsonb_array_length(payload->'cutover_probes')
  into package_probe_count
  from chat_mine_package_input;

  select count(*) into source_system_count from chat_mine_source_system_map;
  select count(*) into batch_count from chat_mine_batch_map;
  select count(*) into item_count from chat_mine_source_item_map;
  select count(*) into evidence_count
  from source_payload_evidence evidence
  join chat_mine_source_item_map item_map on item_map.id=evidence.source_item_id;
  select count(*) into candidate_count
  from source_manifest manifest
  join chat_mine_source_item_map item_map on item_map.id=manifest.source_item_id;
  select count(*) into probe_count
  from cutover_probes probe
  join chat_mine_batch_map batch_map on batch_map.id=probe.batch_id;

  if source_system_count <> 1 or batch_count <> 1 or item_count <> 1
     or evidence_count <> 1 or candidate_count <> 2
     or probe_count <> package_probe_count then
    raise exception
      'Chat-Mine loader smoke mismatch: systems %, batches %, items %, evidence %, candidates %, probes %',
      source_system_count, batch_count, item_count, evidence_count, candidate_count, probe_count;
  end if;

  if exists (
    select 1
    from source_import_batches batch
    join chat_mine_batch_map batch_map on batch_map.id=batch.id
    cross join chat_mine_package_input package
    where batch.source_item_count <> (package.payload#>>'{batch,source_item_count}')::integer
       or batch.exported_item_count <> (package.payload#>>'{batch,exported_item_count}')::integer
  ) then
    raise exception 'Chat-Mine loader smoke batch counts do not match the package';
  end if;

  select count(*) into payload_hash_mismatches
  from chat_mine_package_input package
  cross join lateral jsonb_array_elements(package.payload->'source_items') item
  join chat_mine_source_item_map item_map
    on item_map.source_item_key=item->>'source_item_key'
  join source_items loaded on loaded.id=item_map.id
  where loaded.payload_hash <> item->>'payload_hash';

  select count(*) into evidence_hash_mismatches
  from source_payload_evidence evidence
  join chat_mine_source_item_map item_map on item_map.id=evidence.source_item_id
  join source_items item on item.id=item_map.id
  where evidence.payload_hash is distinct from item.payload_hash
     or evidence.hash_algorithm <> 'sha256';

  if payload_hash_mismatches <> 0 or evidence_hash_mismatches <> 0 then
    raise exception
      'Chat-Mine loader smoke hash mismatch: payload %, evidence %',
      payload_hash_mismatches, evidence_hash_mismatches;
  end if;

  select count(*) into candidate_quote_hash_mismatches
  from source_manifest manifest
  join chat_mine_source_item_map item_map on item_map.id=manifest.source_item_id
  where manifest.source_quote is not null
    and (
      manifest.source_quote_hash_algorithm <> 'sha256'
      or manifest.source_quote_hash is distinct from
         encode(extensions.digest(manifest.source_quote, 'sha256'), 'hex')
    );

  if candidate_quote_hash_mismatches <> 0 then
    raise exception
      'Chat-Mine loader smoke found % candidate quote hash mismatch(es)',
      candidate_quote_hash_mismatches;
  end if;

  if not exists (
    select 1
    from source_manifest manifest
    join chat_mine_source_item_map item_map on item_map.id=manifest.source_item_id
    group by manifest.source_item_id
    having count(*) > 1
  ) then
    raise exception 'Chat-Mine loader smoke did not preserve one-to-many candidates';
  end if;

  select count(*) into duplicate_manifest_keys
  from (
    select manifest.source_item_id, manifest.manifest_key
    from source_manifest manifest
    join chat_mine_source_item_map item_map on item_map.id=manifest.source_item_id
    group by manifest.source_item_id, manifest.manifest_key
    having count(*) > 1
  ) duplicates;

  if duplicate_manifest_keys <> 0 then
    raise exception 'Chat-Mine loader smoke found duplicate manifest keys';
  end if;

  select count(*) into candidate_locator_gaps
  from source_manifest manifest
  join chat_mine_source_item_map item_map on item_map.id=manifest.source_item_id
  where manifest.action in ('import','hold')
    and (
      manifest.source_locator='{}'::jsonb
      or manifest.source_quote_hash is null
      or length(trim(manifest.source_quote_hash))=0
    );

  if candidate_locator_gaps <> 0 then
    raise exception
      'Chat-Mine loader smoke found % import/HOLD candidate locator gap(s)',
      candidate_locator_gaps;
  end if;

  select count(distinct probe.probe_category)
  into active_probe_categories
  from cutover_probes probe
  join chat_mine_batch_map batch_map on batch_map.id=probe.batch_id
  where probe.active;

  if package_probe_count > 0 and active_probe_categories <> 5 then
    raise exception
      'Chat-Mine loader smoke expected five active probe categories, found %',
      active_probe_categories;
  end if;

  select jsonb_object_agg(readiness.check_key, readiness.state)
  into readiness_states
  from source_readiness readiness
  join chat_mine_batch_map batch_map on batch_map.id=readiness.batch_id;

  if readiness_states is distinct from jsonb_build_object(
    'batch_frozen', 'fail',
    'expected_counts_match', 'pass',
    'no_unmanifested_items', 'pass',
    'review_queue_clear_or_waived', 'fail',
    'hold_rows_waived', 'fail',
    'no_payload_drift_after_review', 'pass',
    'approved_imports_have_targets', 'pass',
    'candidate_locators_and_quote_hashes', 'pass',
    'cutover_probe_category_coverage', 'pass',
    'critical_cutover_probes_all_pass', 'fail'
  ) then
    raise exception
      'Chat-Mine loader smoke readiness mismatch: %',
      readiness_states;
  end if;
end $$;

select
  (select count(*) from chat_mine_source_system_map) as source_systems_loaded,
  (select count(*) from chat_mine_batch_map) as batches_loaded,
  (select count(*) from chat_mine_source_item_map) as source_items_loaded,
  (select count(*) from source_payload_evidence evidence
    join chat_mine_source_item_map item_map on item_map.id=evidence.source_item_id) as evidence_loaded,
  (select count(*) from source_manifest manifest
    join chat_mine_source_item_map item_map on item_map.id=manifest.source_item_id) as candidates_loaded,
  (select count(*) from cutover_probes probe
    join chat_mine_batch_map batch_map on batch_map.id=probe.batch_id) as probes_loaded;

rollback;

create temp table chat_mine_cleanup_input (
  payload jsonb not null
);

insert into chat_mine_cleanup_input(payload)
values (:'package_json'::jsonb);

do $$
declare
  remaining_rows integer;
begin
  select
    (select count(*)
     from source_systems source
     cross join chat_mine_cleanup_input package
     where source.source_key=package.payload#>>'{source_system,source_key}')
    +
    (select count(*)
     from source_import_batches batch
     join source_systems source on source.id=batch.source_system_id
     cross join chat_mine_cleanup_input package
     where source.source_key=package.payload#>>'{source_system,source_key}')
    +
    (select count(*)
     from source_items item
     join source_import_batches batch on batch.id=item.batch_id
     join source_systems source on source.id=batch.source_system_id
     cross join chat_mine_cleanup_input package
     where source.source_key=package.payload#>>'{source_system,source_key}')
    +
    (select count(*)
     from source_payload_evidence evidence
     join source_items item on item.id=evidence.source_item_id
     join source_import_batches batch on batch.id=item.batch_id
     join source_systems source on source.id=batch.source_system_id
     cross join chat_mine_cleanup_input package
     where source.source_key=package.payload#>>'{source_system,source_key}')
    +
    (select count(*)
     from source_manifest manifest
     join source_items item on item.id=manifest.source_item_id
     join source_import_batches batch on batch.id=item.batch_id
     join source_systems source on source.id=batch.source_system_id
     cross join chat_mine_cleanup_input package
     where source.source_key=package.payload#>>'{source_system,source_key}')
    +
    (select count(*)
     from cutover_probes probe
     join source_import_batches batch on batch.id=probe.batch_id
     join source_systems source on source.id=batch.source_system_id
     cross join chat_mine_cleanup_input package
     where source.source_key=package.payload#>>'{source_system,source_key}')
  into remaining_rows;

  if remaining_rows <> 0 then
    raise exception
      'Chat-Mine loader smoke rollback left % fixture row(s)',
      remaining_rows;
  end if;
end $$;

drop table chat_mine_cleanup_input;

select 'pass' as rollback_cleanup, 0 as fixture_rows_remaining;
