-- ============================================================================
-- ATTENTION EVENTS + PROJECTION V2 :: ROLLBACK-ONLY CONFORMANCE TEST
-- Run after sql/01_core.sql and sql/08_attention_events.sql.
-- ============================================================================

begin;

do $$
declare
  v_agent text;
  v_owner text;
  v_active uuid;
  v_proposed uuid;
  v_import uuid;
  v_created_event uuid;
  v_activation_event uuid;
  v_revision uuid;
  v_replay uuid;
  v_identity text;
  v_count integer;
  v_low jsonb;
  v_high jsonb;
  v_conf jsonb;
  i integer;
begin
  select agent_id,principal into v_agent,v_owner
  from trusted_agents where active and principal<>'shared'
  order by created_at,agent_id limit 1;
  if v_agent is null then raise exception 'test requires one active non-shared trusted agent'; end if;

  if to_regclass('public.attention_events') is null
     or to_regclass('public.attention_event_assignments') is null then
    raise exception 'attention event tables missing';
  end if;

  -- Active native insert creates one source-semantic event and one assignment.
  insert into memories(content,tags,workstream,owner,visibility,source_kind,source_agent,status)
  values('fixture native memory with café emoji 🚀 and escaped "quote"',array['fixture'],
         'fixture/attention-native',v_owner,'shared','agent',v_agent,'active')
  returning id into v_active;

  select id,identity_key into v_created_event,v_identity
  from attention_events where memory_id=v_active and source_event_type='memory_created';
  if v_created_event is null then raise exception 'memory_created event missing'; end if;
  if (select count(*) from attention_events where memory_id=v_active and source_event_type='memory_created')<>1 then
    raise exception 'native insert emitted duplicate creation events';
  end if;
  if (select count(*) from attention_event_assignments where event_id=v_created_event)<>1 then
    raise exception 'native creation assignment missing';
  end if;
  if not exists(select 1 from attention_events where id=v_created_event and owner=v_owner and principal_key=v_owner and visibility='shared') then
    raise exception 'principal/owner/visibility envelope incorrect';
  end if;

  perform record_native_memory_attention(v_active);
  if (select count(*) from attention_events where memory_id=v_active and source_event_type='memory_created')<>1 then
    raise exception 'creation replay duplicated';
  end if;

  -- Proposed insert is silent until actual activation.
  insert into memories(content,tags,workstream,owner,visibility,source_kind,source_agent,status)
  values('fixture proposed memory',array['fixture'],'fixture/attention-proposed',v_owner,'private','agent',v_agent,'proposed')
  returning id into v_proposed;

  if exists(select 1 from attention_events where memory_id=v_proposed) then
    raise exception 'proposed insert emitted an attention event';
  end if;

  if promote_memory(v_proposed,'fixture promotion',v_agent)<>'promoted' then
    raise exception 'promotion failed';
  end if;

  select id,identity_key into v_activation_event,v_identity
  from attention_events where memory_id=v_proposed and source_event_type='memory_activated';
  if v_activation_event is null then raise exception 'memory_activated event missing'; end if;
  if not exists(select 1 from attention_events where id=v_activation_event and owner=v_owner and principal_key=v_owner and visibility='private') then
    raise exception 'activation lost owner/visibility/principal';
  end if;

  perform record_native_memory_activation(v_proposed,v_agent);
  if (select count(*) from attention_events where memory_id=v_proposed and source_event_type='memory_activated')<>1 then
    raise exception 'activation replay duplicated';
  end if;

  -- Changed observation appends a linked revision; replay returns that revision.
  v_revision:=append_attention_event_revision(
    v_activation_event,'2',now(),'memory:'||v_proposed::text,
    'fixture_changed_observation',jsonb_build_object('fixture',true)
  );
  v_replay:=append_attention_event_revision(
    v_activation_event,'2',now(),'memory:'||v_proposed::text,
    'fixture_changed_observation',jsonb_build_object('fixture',true)
  );
  if v_revision<>v_replay then raise exception 'revision replay returned a different event'; end if;
  if (select count(*) from attention_events where identity_key=v_identity)<>2 then
    raise exception 'stable identity does not carry exactly two revisions';
  end if;
  if not exists(select 1 from attention_events where id=v_revision and revision_ordinal=2 and supersedes_event_id=v_activation_event) then
    raise exception 'revision lineage invalid';
  end if;
  if (select count(*) from attention_event_assignments where event_id=v_revision)<>1 then
    raise exception 'revision assignment lineage missing';
  end if;

  -- Imported records remain records, not fabricated native attention events.
  insert into memories(content,tags,workstream,owner,visibility,source_kind,source_agent,status)
  values('fixture imported memory',array['fixture'],'fixture/attention-import',v_owner,'shared','import',v_agent,'active')
  returning id into v_import;
  if exists(select 1 from attention_events where memory_id=v_import) then
    raise exception 'import row emitted a native attention event';
  end if;

  -- Append-only custody.
  begin
    update attention_events set metadata=metadata where id=v_created_event;
    raise exception 'event update unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%append-only%' then raise; end if;
  end;

  begin
    delete from attention_event_assignments where event_id=v_created_event;
    raise exception 'assignment delete unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%append-only%' then raise; end if;
  end;

  begin
    execute 'truncate table attention_events';
    raise exception 'event truncate unexpectedly succeeded';
  exception when others then
    if sqlerrm not like '%TRUNCATE is not permitted%' then raise; end if;
  end;

  -- Add deterministic topics with multibyte and escaped content for budget tests.
  for i in 1..12 loop
    insert into memories(content,tags,workstream,owner,visibility,source_kind,source_agent,status)
    values(
      'fixture topic '||i||' résumé 東京 emoji 🚀 with quoted "text" and backslash \\ plus enough words for boundary truncation',
      array['fixture'],'fixture/budget-'||lpad(i::text,2,'0'),v_owner,'shared','agent',v_agent,'active'
    );
  end loop;

  v_low:=attention_boot_projection_v2(v_owner,2000,80);
  v_high:=attention_boot_projection_v2(v_owner,6000,80);

  if char_length(v_low::text)>(v_low->'coverage'->>'effective_char_budget')::integer
     or char_length(v_high::text)>(v_high->'coverage'->>'effective_char_budget')::integer then
    raise exception 'serialized character budget exceeded';
  end if;
  if (v_low->'coverage'->>'rendered_chars')::integer<>char_length(v_low::text)
     or (v_high->'coverage'->>'rendered_chars')::integer<>char_length(v_high::text) then
    raise exception 'reported serialized character count is not exact';
  end if;
  if jsonb_array_length(v_high->'topics')<jsonb_array_length(v_low->'topics') then
    raise exception 'larger budget reduced represented coverage';
  end if;
  if jsonb_array_length(v_low->'topics')>0 then
    for i in 0..jsonb_array_length(v_low->'topics')-1 loop
      if (v_low->'topics'->i)<>(v_high->'topics'->i) then
        raise exception 'larger budget changed the lower-budget prefix at index %',i;
      end if;
    end loop;
  end if;

  v_conf:=attention_budget_conformance_v2(v_owner,6000,80);
  if not (v_conf->>'pass_reported_exact')::boolean
     or not (v_conf->>'pass_character_budget')::boolean
     or v_conf->>'contract_unit'<>'serialized_characters' then
    raise exception 'character-budget conformance receipt failed';
  end if;
  if not ((v_conf->'does_not_guarantee') ? 'UTF-8 bytes')
     or not ((v_conf->'does_not_guarantee') ? 'model tokens') then
    raise exception 'budget non-guarantees are not explicit';
  end if;

  -- Routine runtime role has read/RPC access only, not event mutation.
  if exists(select 1 from pg_roles where rolname='service_role') then
    if has_table_privilege('service_role','public.attention_events','INSERT')
       or has_table_privilege('service_role','public.attention_events','UPDATE')
       or has_table_privilege('service_role','public.attention_event_assignments','DELETE')
       or has_table_privilege('service_role','public.attention_events','TRUNCATE') then
      raise exception 'service_role retains routine attention-event mutation privilege';
    end if;
  end if;
end $$;

rollback;

-- A successful run reaches this line and leaves no fixtures.
