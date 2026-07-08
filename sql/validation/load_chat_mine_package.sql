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
  candidate->'source_locator',
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
  item_count integer;
  evidence_count integer;
  candidate_count integer;
  probe_count integer;
begin
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

  if item_count <> 1 or evidence_count <> 1 or candidate_count <> 2 or probe_count <> 5 then
    raise exception
      'Chat-Mine loader smoke mismatch: items %, evidence %, candidates %, probes %',
      item_count, evidence_count, candidate_count, probe_count;
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
end $$;

select
  (select count(*) from chat_mine_source_item_map) as source_items_loaded,
  (select count(*) from source_payload_evidence evidence
    join chat_mine_source_item_map item_map on item_map.id=evidence.source_item_id) as evidence_loaded,
  (select count(*) from source_manifest manifest
    join chat_mine_source_item_map item_map on item_map.id=manifest.source_item_id) as candidates_loaded,
  (select count(*) from cutover_probes probe
    join chat_mine_batch_map batch_map on batch_map.id=probe.batch_id) as probes_loaded;

rollback;
