-- Run after the previous PR head's v2 SQL.
create table public.upgrade_expectations(
  event_count integer not null,
  assignment_count integer not null,
  event_snapshot text not null,
  assignment_snapshot text not null,
  legacy_without_event uuid not null
);

-- This must be a separate statement. A data-modifying CTE and its main SELECT
-- share one command snapshot, so trigger side effects would not be included in
-- the baseline receipt captured by that same statement.
insert into public.memories(
  content,workstream,owner,visibility,source_agent,source_kind,status
) values(
  'v2 generated event fixture','upgrade','example-user','private',
  'example-user-chatgpt','agent','active'
);

insert into public.upgrade_expectations
select
  (select count(*) from public.attention_events),
  (select count(*) from public.attention_event_assignments),
  encode(extensions.digest(coalesce((
    select string_agg(concat_ws('|',id::text,contract_version,source_event_type,identity_key,
      revision_key,coalesce(source_revision,''),revision_ordinal::text,
      coalesce(supersedes_event_id::text,''),memory_id::text,occurred_at::text,recorded_at::text,
      source_evidence_ref,observation_method,metadata::text),E'\n' order by id)
    from public.attention_events
  ),''),'sha256'),'hex'),
  encode(extensions.digest(coalesce((
    select string_agg(concat_ws('|',id::text,event_id::text,assignment_kind,assignment_key,
      coalesce(confidence::text,''),assigned_by,coalesce(assignment_model_version,''),
      coalesce(supersedes::text,''),assigned_at::text),E'\n' order by id)
    from public.attention_event_assignments
  ),''),'sha256'),'hex'),
  (select id from public.memories
   where content='pre-attention upgrade fixture'
   order by created_at,id limit 1);
