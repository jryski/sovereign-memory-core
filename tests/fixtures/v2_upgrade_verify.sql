do $$
declare e public.upgrade_expectations%rowtype;v uuid;
begin
  select * into e from public.upgrade_expectations;
  if (select count(*) from public.attention_events)<>e.event_count then
    raise exception 'upgrade changed existing event count';
  end if;
  if (select count(*) from public.attention_event_assignments)<>e.assignment_count then
    raise exception 'upgrade changed existing assignment count';
  end if;
  if encode(extensions.digest(coalesce((
    select string_agg(concat_ws('|',id::text,contract_version,source_event_type,identity_key,
      revision_key,coalesce(source_revision,''),revision_ordinal::text,
      coalesce(supersedes_event_id::text,''),memory_id::text,occurred_at::text,recorded_at::text,
      source_evidence_ref,observation_method,metadata::text),E'\n' order by id)
    from public.attention_events
  ),''),'sha256'),'hex')<>e.event_snapshot then
    raise exception 'upgrade rewrote an existing event';
  end if;
  if encode(extensions.digest(coalesce((
    select string_agg(concat_ws('|',id::text,event_id::text,assignment_kind,assignment_key,
      coalesce(confidence::text,''),assigned_by,coalesce(assignment_model_version,''),
      coalesce(supersedes::text,''),assigned_at::text),E'\n' order by id)
    from public.attention_event_assignments
  ),''),'sha256'),'hex')<>e.assignment_snapshot then
    raise exception 'upgrade rewrote an existing assignment';
  end if;
  v:=public.record_native_memory_attention(e.legacy_without_event);
  if v is not null then raise exception 'upgrade replay fabricated missing history'; end if;
end $$;

select public.assert_perimeter_closed();
select 'executable v2-to-v3 upgrade preserved legacy rows' as result;
