-- Attention v3 rollback-only conformance, including runtime-role attacks.
begin;

create temporary table attention_test_ids(kind text primary key,id uuid);

insert into attention_test_ids(kind,id)
select 'legacy_without_event',m.id
from public.memories m
where m.status='active' and m.source_kind in ('agent','human','manual')
  and not exists(select 1 from public.attention_events e where e.memory_id=m.id)
order by m.created_at,m.id limit 1;

do $$
begin
  if not exists(select 1 from attention_test_ids where kind='legacy_without_event') then
    raise exception 'workflow must seed a pre-attention active memory';
  end if;
end $$;

select set_config('app.test_legacy_id',(select id::text from attention_test_ids where kind='legacy_without_event'),true);
select set_config('app.test_event_count',(select count(*)::text from public.attention_events),true);

set local role service_role;

do $$
declare v uuid;
begin
  v:=public.record_native_memory_attention(current_setting('app.test_legacy_id')::uuid);
  if v is not null then raise exception 'runtime fabricated memory_created'; end if;
  v:=public.record_native_memory_activation(current_setting('app.test_legacy_id')::uuid,'forged');
  if v is not null then raise exception 'runtime fabricated memory_activated'; end if;
  if has_function_privilege('service_role','public.capture_memory_attention_after_insert()','EXECUTE')
     or has_function_privilege('service_role','public.capture_memory_activation_after_update()','EXECUTE') then
    raise exception 'service_role can execute trigger-only writer';
  end if;
  begin
    insert into public.attention_events(
      source_system,source_namespace,source_event_type,identity_key,revision_key,
      occurred_at,source_evidence_ref,observation_method
    ) values('x','x','x',repeat('a',64),repeat('b',64),now(),'x','x');
    raise exception 'direct event insert unexpectedly succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;

do $$
declare
  v_created_memory uuid;
  v_created attention_events%rowtype;
  v_proposed_memory uuid;
  v_activated attention_events%rowtype;
  v_revision uuid;
  v_revision_replay uuid;
  v_revision_row attention_events%rowtype;
  v_payload jsonb;
begin
  if (select count(*) from attention_events)<>current_setting('app.test_event_count')::integer then
    raise exception 'runtime replay changed event count';
  end if;

  insert into memories(content,workstream,owner,visibility,source_agent,source_kind,status)
  values(
    'attention creation fixture','conformance','example-user','private',
    'example-user-chatgpt','agent','active'
  ) returning id into v_created_memory;
  insert into attention_test_ids values('created_memory',v_created_memory);

  select * into v_created from attention_events
  where memory_id=v_created_memory and source_event_type='memory_created';
  if not found then raise exception 'native insert trigger did not create event'; end if;
  if v_created.contract_version<>'attention-event/0.3'
     or v_created.source_revision<>'native-revision:1'
     or v_created.revision_key<>attention_hash_parts(v_created.identity_key,v_created.source_revision)
     or v_created.owner<>'example-user' or v_created.visibility<>'private'
     or v_created.observation_method<>'native_insert_trigger' then
    raise exception 'creation envelope or independent key recomputation failed';
  end if;

  insert into memories(content,workstream,owner,visibility,source_agent,source_kind,status)
  values(
    'attention activation fixture','conformance','example-partner','private',
    'example-partner-chatgpt','agent','proposed'
  ) returning id into v_proposed_memory;
  if exists(select 1 from attention_events where memory_id=v_proposed_memory) then
    raise exception 'proposed insert emitted an event';
  end if;
  perform promote_memory(v_proposed_memory,'conformance','ci-promoter');
  select * into v_activated from attention_events
  where memory_id=v_proposed_memory and source_event_type='memory_activated';
  if not found then raise exception 'actual proposed-to-active transition emitted no activation'; end if;
  if v_activated.source_revision<>'native-revision:1'
     or v_activated.revision_key<>attention_hash_parts(v_activated.identity_key,v_activated.source_revision)
     or v_activated.owner<>'example-partner' or v_activated.visibility<>'private'
     or v_activated.observation_method<>'native_status_transition' then
    raise exception 'activation envelope or independent key recomputation failed';
  end if;
  if record_native_memory_activation(v_proposed_memory,'forged')<>v_activated.id then
    raise exception 'activation replay failed to return existing row';
  end if;

  perform set_config('app.actor_agent','current-observer',true);
  perform set_config('app.credential_ref','asserted:test-credential',true);
  perform set_config('app.runtime_ref','runtime:test',true);
  v_revision:=append_attention_event_revision(
    v_created.id,'observed-revision:2',clock_timestamp(),
    'other:test:revision-2','conformance-observation','{"fixture":true}'::jsonb
  );
  select * into v_revision_row from attention_events where id=v_revision;
  if v_revision_row.actor_key<>'current-observer'
     or v_revision_row.credential_ref<>'asserted:test-credential'
     or v_revision_row.runtime_ref<>'runtime:test' then
    raise exception 'revision copied stale observer attribution';
  end if;
  if v_revision_row.revision_key<>attention_hash_parts(v_revision_row.identity_key,v_revision_row.source_revision) then
    raise exception 'revision key cannot be recomputed from persisted fields';
  end if;
  v_revision_replay:=append_attention_event_revision(
    v_created.id,'observed-revision:2',clock_timestamp(),
    'other:test:revision-2','conformance-observation','{"fixture":true}'::jsonb
  );
  if v_revision_replay<>v_revision then raise exception 'same revision replay did not return winner'; end if;

  if attention_fixed_point_chars(8)<>9
     or attention_fixed_point_chars(9)<>11
     or attention_fixed_point_chars(97)<>99
     or attention_fixed_point_chars(98)<>101
     or attention_fixed_point_chars(997)<>1001
     or attention_fixed_point_chars(9996)<>10001 then
    raise exception 'decimal width-boundary fixed-point test failed';
  end if;

  v_payload:=attention_set_rendered_chars(jsonb_build_object(
    'topics',jsonb_build_array(jsonb_build_object(
      'summary',E'漢字 😀 quote " slash \\ tab\t newline\n'
    )),
    'coverage',jsonb_build_object('rendered_chars',0)
  ));
  if (v_payload#>>'{coverage,rendered_chars}')::integer<>char_length(v_payload::text) then
    raise exception 'multibyte/escaped fixed point failed';
  end if;
  if (attention_budget_conformance_v2('example-user',512,80)->>'pass_reported_exact')::boolean is not true
     or (attention_budget_conformance_v2('example-user',512,80)->>'pass_character_budget')::boolean is not true then
    raise exception 'tight serialized-character budget failed';
  end if;
end $$;

select public.assert_perimeter_closed();
rollback;

select 'attention v3 rollback-only conformance passed' as result;
