-- SECURITY DEFINER inventory and pg_temp-shadow conformance for issue #57.
-- All adversarial roles, grants, temporary objects, and row fixtures roll back.
begin;

-- Dedicated exact inventory: every SECURITY DEFINER function installed by the
-- work-memory package must be reviewed, not sampled.
do $$
declare
  v_expected text[]:=array[
    'public.accept_work_lesson(uuid,text,text)',
    'public.append_attention_event_revision(uuid,text,timestamp with time zone,text,text,jsonb)',
    'public.append_work_lesson_evidence(uuid,text,text,text,text,text,text)',
    'public.assert_perimeter_closed()',
    'public.attention_boot_projection_v2(text,integer,integer)',
    'public.attention_budget_conformance_v2(text,integer,integer)',
    'public.bless_doc(text,text)',
    'public.capture_memory_activation_after_update()',
    'public.capture_memory_attention_after_insert()',
    'public.channel_complete(bigint,text)',
    'public.channel_send(text,text,text,text,text,timestamp with time zone,boolean,bigint)',
    'public.correct_work_lesson_evidence(uuid,text,text,text,text,text,text,text)',
    'public.current_doc_hash(text)',
    'public.hot_touch(text,uuid,text,text)',
    'public.promote_memory(uuid,text,text)',
    'public.propose_lesson_supersession(uuid,text,text,text,text,text,text,text,text)',
    'public.propose_work_lesson(text,text,text,text,text,text,text,text,text)',
    'public.record_native_memory_activation(uuid,text)',
    'public.record_native_memory_attention(uuid)',
    'public.reject_work_lesson(uuid,text,text)',
    'public.remediate_perimeter_acl()',
    'public.remember(text,text,text,text,text,text,text[],text,timestamp with time zone)',
    'public.search_coverage_receipt(text,jsonb)',
    'public.session_boot(text)',
    'public.supersede_memory(uuid,text,text,text,text[],timestamp with time zone)',
    'public.supersede_wiki(text,text,text,text,jsonb)',
    'public.topology_profile_boot(text)',
    'public.verify_doc_integrity(text)',
    'public.work_lessons_boot_fragment()'
  ];
  v_actual text[];
  v_bad text;
begin
  select array_agg(format('%I.%I(%s)',n.nspname,p.proname,
           regexp_replace(oidvectortypes(p.proargtypes),', ', ',', 'g'))
           order by format('%I.%I(%s)',n.nspname,p.proname,
             regexp_replace(oidvectortypes(p.proargtypes),', ', ',', 'g')))
    into v_actual
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where p.prosecdef and n.nspname='public';
  if v_actual is distinct from v_expected then
    raise exception 'SECURITY DEFINER inventory mismatch: expected %, found %',v_expected,v_actual;
  end if;

  select string_agg(format('%I.%I(%s) path=%s',n.nspname,p.proname,
           pg_get_function_identity_arguments(p.oid),coalesce(array_to_string(p.proconfig,','),'<missing>')),
           E'\n' order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid))
    into v_bad
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where p.prosecdef and n.nspname='public'
    and p.proconfig is distinct from array['search_path=pg_catalog, pg_temp'];
  if v_bad is not null then
    raise exception 'SECURITY DEFINER functions are not fully-qualified/search_path empty: %',v_bad;
  end if;

  if to_regprocedure('public.promote_memory(uuid,text)') is not null
     or exists(
       select 1 from public.perimeter_authority_function_registry
       where function_identity='public.promote_memory(uuid,text)'
     ) then
    raise exception 'actorless/defaulted promotion path or stale perimeter entry remains';
  end if;

  if pg_get_functiondef('public.hot_touch(text,uuid,text,text)'::regprocedure)
       not like '%insert into public.memory_hot_index as mhi%'
     or pg_get_functiondef('public.hot_touch(text,uuid,text,text)'::regprocedure)
       not like '%touch_count=mhi.touch_count+1%' then
    raise exception 'hot_touch conflict update lacks an explicitly bound qualified target alias';
  end if;
end $$;

-- The checker validates omitted, misordered, and untrusted retained paths. Each
-- deliberate catalog drift is restored before the next adversarial case.
do $$
declare v_case text;v_sql text;
begin
  foreach v_case in array array['omitted','misordered','untrusted'] loop
    v_sql:=case v_case
      when 'omitted' then 'alter function public.current_doc_hash(text) reset search_path'
      when 'misordered' then 'alter function public.current_doc_hash(text) set search_path=pg_temp,pg_catalog'
      else 'alter function public.current_doc_hash(text) set search_path=pg_catalog,attacker_schema,pg_temp'
    end;
    execute v_sql;
    begin
      perform public.assert_perimeter_closed();
    exception when others then
      if sqlstate='P0001'
         and sqlerrm like (case when v_case='untrusted'
           then 'PERIMETER FAIL: registered authority-function search-path schema is missing or not explicitly protected:%'
           else 'PERIMETER FAIL: unsafe or missing function search_path:%'
         end)
         and sqlerrm like '%public.current_doc_hash%' then
        execute 'alter function public.current_doc_hash(text) set search_path=pg_catalog,pg_temp';
        continue;
      end if;
      raise exception 'path case % lacked exact failure evidence: %',v_case,sqlerrm;
    end;
    raise exception 'perimeter accepted % SECURITY DEFINER search_path',v_case;
  end loop;
end $$;

-- The perimeter checker must not read caller-controlled temporary policy and
-- registry tables and falsely allow a real CREATE grant on public.
grant create on schema public to service_role;
set local role service_role;
create temporary table perimeter_acl_policy (
  singleton boolean,profile text,owner_roles text[],schema_create_roles text[],
  function_execute_roles text[],internal_execute_roles text[],updated_at timestamptz
);
insert into perimeter_acl_policy values(
  true,'supabase',array[current_user],array['service_role'],array['service_role'],array[]::text[],now()
);
create temporary table perimeter_protected_schema_registry(schema_name text);
insert into perimeter_protected_schema_registry values('public');
create temporary table perimeter_authority_function_registry(function_identity text,is_internal boolean);
do $$
begin
  begin
    perform public.assert_perimeter_closed();
  exception when others then
    if sqlstate='P0001' and sqlerrm like '%unexpected effective ACL grantees:%'
       and sqlerrm like '%service_role%' and sqlerrm like '%CREATE%' then return; end if;
    raise exception 'checker temp-shadow attempt failed without real drift evidence: %',sqlerrm;
  end;
  raise exception 'temp-shadowed checker falsely passed real public-schema CREATE drift';
end $$;
reset role;
revoke create on schema public from service_role;

-- The highest-priority write path must update the durable public objects, not
-- same-named temporary relations supplied by its runtime caller.
do $$
declare v_id uuid;
begin
  insert into public.memories(content,workstream,owner,visibility,source_agent,source_kind,status)
  values('pg_temp hot_touch durable sentinel',null,'example-user','private','example-user-chatgpt','import','active')
  returning id into v_id;
  perform set_config('smc.temp_shadow_memory_id',v_id::text,true);
end $$;
set local role service_role;
create temporary table memories (
  id uuid primary key,content text,owner text,visibility text,workstream text,
  source_agent text,source_kind text,status text,hot_touched boolean default false
);
create temporary table memory_hot_index (
  memory_id uuid,topic_key text,owner text,visibility text,summary text,workstream text,
  touch_count integer,last_touched timestamptz,unique(owner,topic_key)
);
create temporary table memory_hot_staging(owner text,topic_key text);
insert into memories(id,content,owner,visibility,source_agent,source_kind,status)
values(current_setting('smc.temp_shadow_memory_id')::uuid,'attacker shadow','example-user','private','example-user-chatgpt','import','active');
select public.hot_touch('security/temp-shadow',current_setting('smc.temp_shadow_memory_id')::uuid,'durable target',null);
reset role;
do $$
begin
  if not exists(
    select 1 from public.memories
    where id=current_setting('smc.temp_shadow_memory_id')::uuid and hot_touched
  ) or not exists(
    select 1 from public.memory_hot_index
    where memory_id=current_setting('smc.temp_shadow_memory_id')::uuid
      and topic_key='security/temp-shadow'
  ) then
    raise exception 'hot_touch was redirected to caller temporary relations';
  end if;
end $$;

rollback;
select 'SECURITY DEFINER inventory and pg_temp-shadow conformance passed' as result;
