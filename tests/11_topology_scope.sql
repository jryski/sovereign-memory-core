-- Issue #72 topology/scope acceptance. All fixtures and configuration edits roll back.
begin;

-- Default boot is fail closed but local read-only recovery remains available.
do $$
declare v_boot jsonb;
begin
  v_boot:=public.session_boot('example-user');
  if v_boot#>>'{topology,schema}' is distinct from 'sovereign-memory/topology-profile'
     or v_boot#>>'{topology,version}' is distinct from '1'
     or (v_boot#>>'{topology,read_only_local_available}')::boolean is not true
     or v_boot#>>'{topology,state}' is distinct from 'not_configured'
     or v_boot#>>'{topology,visible_known_stores,0,configuration_state}' is distinct from 'not_configured'
     or v_boot#>>'{topology,visible_known_stores,0,coverage_state}' is distinct from 'not_applicable' then
    raise exception 'session boot lacks the fail-closed topology/profile contract: %',v_boot->'topology';
  end if;
  if v_boot#>>'{topology,attestation,status}' is distinct from 'unknown' then
    raise exception 'missing observed contract metadata did not attest unknown';
  end if;
end $$;

-- Synthetic deployment-neutral stores: one shared peer and one private peer.
update public.store_topology_profile
set topology_state='configured',updated_at=now()
where singleton;
update public.known_memory_stores set store_profile='reference' where relationship='local';
insert into public.known_memory_stores(store_id,store_profile,relationship,search_scope,owner,visibility)
values
  ('peer-store','reference','peer','default','shared','shared'),
  ('private-peer','reference','peer','private-scope','example-partner','private');

do $$
declare v_user jsonb;v_partner jsonb;
begin
  v_user:=public.topology_profile_boot('example-user');
  v_partner:=public.topology_profile_boot('example-partner');
  if v_user::text like '%private-peer%' or v_user::text like '%private-scope%' then
    raise exception 'public topology exposed non-shared metadata';
  end if;
  if v_partner::text like '%private-peer%' or v_partner::text like '%private-scope%' then
    raise exception 'caller-selected logical viewer broadened public topology';
  end if;
  if v_user#>>'{coverage,total_visible}' is distinct from '2'
     or v_user#>>'{visible_known_stores,0,configuration_state}' is distinct from 'configured'
     or v_user#>>'{visible_known_stores,0,coverage_state}' is distinct from 'not_queried'
     or v_user#>>'{visible_known_stores,1,configuration_state}' is distinct from 'configured'
     or v_user#>>'{visible_known_stores,1,coverage_state}' is distinct from 'not_queried' then
    raise exception 'configured topology coverage is not deterministic: %',v_user;
  end if;
end $$;

-- Deterministic classification through the public, client-reported receipt seam.
do $$
declare v jsonb;
begin
  v:=public.search_coverage_receipt('example-user','{"schema_version":"1","attempts":[{"store_id":"local-store","scope":"default","status":"queried","hit_count":1}]}');
  if v->>'classification'<>'local_hit' or v->>'coverage_source'<>'client-reported'
     or v->>'authority'<>'client-reported-coverage-not-search-authority' then
    raise exception 'local hit classification failed: %',v;
  end if;

  v:=public.search_coverage_receipt('example-user','{"schema_version":"1","attempts":[{"store_id":"local-store","scope":"default","status":"queried","hit_count":0},{"store_id":"peer-store","scope":"default","status":"queried","hit_count":2}]}');
  if v->>'classification'<>'remote_hit' or (v->>'coverage_complete')::boolean is not true then
    raise exception 'remote hit classification failed: %',v;
  end if;

  v:=public.search_coverage_receipt('example-user','{"schema_version":"1","attempts":[{"store_id":"local-store","scope":"default","status":"queried","hit_count":0}]}');
  if v->>'classification'<>'partial_miss' or (v->>'coverage_complete')::boolean is not false
     or (v->>'global_absence_supported')::boolean is not false
     or (v->>'advertised_unqueried_stores')::integer<>1 then
    raise exception 'single-store miss was broadened beyond reported coverage: %',v;
  end if;

  v:=public.search_coverage_receipt('example-user','{"schema_version":"1","attempts":[{"store_id":"local-store","scope":"default","status":"queried","hit_count":0},{"store_id":"peer-store","scope":"default","status":"queried","hit_count":0}]}');
  if v->>'classification'<>'complete_miss' or (v->>'coverage_complete')::boolean is not true
     or (v->>'global_absence_supported')::boolean is not true then
    raise exception 'complete miss classification failed: %',v;
  end if;

  v:=public.search_coverage_receipt('example-user','{"schema_version":"1","attempts":[{"store_id":"local-store","scope":"default","status":"queried","hit_count":0},{"store_id":"peer-store","scope":"default","status":"unreachable","hit_count":0}]}');
  if v->>'classification'<>'unreachable_peer' or (v->>'coverage_complete')::boolean is not false then
    raise exception 'unreachable peer classification failed: %',v;
  end if;

  update public.store_topology_profile set topology_state='unknown' where singleton;
  v:=public.search_coverage_receipt('example-user','{"schema_version":"1","attempts":[{"store_id":"local-store","scope":"default","status":"queried","hit_count":0}]}');
  if v->>'classification'<>'unknown_topology' then
    raise exception 'unknown topology classification failed: %',v;
  end if;
  update public.store_topology_profile set topology_state='configured' where singleton;
end $$;

-- A configured profile without its canonical local store is unknown topology,
-- never complete coverage or support for a global absence claim.
do $$
declare v_boot jsonb;v_receipt jsonb;
begin
  delete from public.known_memory_stores where relationship='local';
  v_boot:=public.topology_profile_boot('example-user');
  v_receipt:=public.search_coverage_receipt(
    'example-user','{"schema_version":"1","attempts":[]}'::jsonb);
  if v_boot->>'state'<>'unknown'
     or v_boot#>>'{local_store,store_id}'<>'unknown'
     or v_receipt->>'classification'<>'unknown_topology'
     or (v_receipt->>'coverage_complete')::boolean is not false
     or (v_receipt->>'global_absence_supported')::boolean is not false then
    raise exception 'missing local store did not fail closed: boot %, receipt %',v_boot,v_receipt;
  end if;
  insert into public.known_memory_stores(
    store_id,store_profile,relationship,search_scope,owner,visibility)
  values('local-store','reference','local','default','shared','shared');
end $$;

-- Loss of the singleton profile row must still return a versioned, deterministic
-- unknown topology object so read-only boot never degrades to JSON null.
do $$
declare v_boot jsonb;v_receipt jsonb;
begin
  delete from public.store_topology_profile where singleton;
  v_boot:=public.session_boot('example-user');
  v_receipt:=public.search_coverage_receipt(
    'example-user','{"schema_version":"1","attempts":[]}'::jsonb);
  if v_boot#>>'{topology,schema}'<>'sovereign-memory/topology-profile'
     or v_boot#>>'{topology,version}'<>'1'
     or v_boot#>>'{topology,state}'<>'unknown'
     or (v_boot#>>'{topology,read_only_local_available}')::boolean is not true
     or v_receipt->>'classification'<>'unknown_topology'
     or (v_receipt->>'coverage_complete')::boolean is not false
     or (v_receipt->>'global_absence_supported')::boolean is not false then
    raise exception 'missing topology profile row did not fail closed: boot %, receipt %',
      v_boot->'topology',v_receipt;
  end if;
  insert into public.store_topology_profile(singleton,topology_state)
  values(true,'configured');
end $$;

-- Exact shape/types/statuses, identities, counts, duplicates, and input bound.
do $$
declare r record;v_many jsonb;
begin
  begin
    perform public.search_coverage_receipt('example-user','[]'::jsonb);
    raise exception 'unversioned receipt array was accepted';
  exception when others then
    if sqlerrm='unversioned receipt array was accepted' then raise; end if;
    if sqlerrm<>'search coverage receipt must be a JSON object' then
      raise exception 'wrong receipt-envelope error: %',sqlerrm;
    end if;
  end;
  begin
    perform public.search_coverage_receipt('example-user','{"schema_version":"2","attempts":[]}'::jsonb);
    raise exception 'unsupported receipt schema version was accepted';
  exception when others then
    if sqlerrm='unsupported receipt schema version was accepted' then raise; end if;
    if sqlerrm<>'unsupported search coverage schema_version' then
      raise exception 'wrong schema-version error: %',sqlerrm;
    end if;
  end;

  for r in select * from (values
    ('{}'::jsonb,'search coverage attempts must be a JSON array'),
    ('[1]'::jsonb,'search coverage attempt 1 must be an object'),
    ('[{"store_id":"local-store","scope":"default","status":"queried","hit_count":0,"extra":true}]'::jsonb,'search coverage attempt 1 must contain exactly'),
    ('[{"store_id":1,"scope":"default","status":"queried","hit_count":0}]'::jsonb,'search coverage attempt 1 has invalid JSON types'),
    ('[{"store_id":"local-store","scope":"default","status":"skipped","hit_count":0}]'::jsonb,'search coverage attempt 1 has invalid status'),
    ('[{"store_id":"local-store","scope":"default","status":"queried","hit_count":0},{"store_id":"local-store","scope":"default","status":"queried","hit_count":0}]'::jsonb,'search coverage attempt 2 duplicates store_id'),
    ('[{"store_id":"missing-store","scope":"default","status":"queried","hit_count":0}]'::jsonb,'search coverage attempt 1 has unknown visible store_id'),
    ('[{"store_id":"private-peer","scope":"private-scope","status":"queried","hit_count":0}]'::jsonb,'search coverage attempt 1 has unknown visible store_id'),
    ('[{"store_id":"local-store","scope":"wrong","status":"queried","hit_count":0}]'::jsonb,'search coverage attempt 1 scope does not match visible store'),
    ('[{"store_id":"local-store","scope":"default","status":"queried","hit_count":-1}]'::jsonb,'search coverage attempt 1 hit_count must be an integer'),
    ('[{"store_id":"local-store","scope":"default","status":"queried","hit_count":1.5}]'::jsonb,'search coverage attempt 1 hit_count must be an integer'),
    ('[{"store_id":"local-store","scope":"default","status":"queried","hit_count":1000001}]'::jsonb,'search coverage attempt 1 hit_count exceeds maximum 1000000'),
    ('[{"store_id":"local-store","scope":"default","status":"unreachable","hit_count":1}]'::jsonb,'search coverage attempt 1 unreachable hit_count must be zero')
  ) x(payload,expected)
  loop
    begin
      perform public.search_coverage_receipt('example-user',jsonb_build_object('schema_version','1','attempts',r.payload));
    exception when others then
      if sqlerrm like r.expected||'%' then continue; end if;
      raise exception 'wrong validation error for %: expected %, got %',r.payload,r.expected,sqlerrm;
    end;
    raise exception 'invalid coverage payload was accepted: %',r.payload;
  end loop;

  select jsonb_agg(jsonb_build_object('store_id','local-store','scope','default','status','queried','hit_count',0))
  into v_many from generate_series(1,33);
  begin
    perform public.search_coverage_receipt('example-user',jsonb_build_object('schema_version','1','attempts',v_many));
  exception when others then
    if sqlerrm='search coverage attempts exceed maximum 32' then return; end if;
    raise exception 'wrong excessive-attempt error: %',sqlerrm;
  end;
  raise exception 'more than 32 coverage attempts were accepted';
end $$;

-- Canonical identifiers and output are independent of attempt order.
do $$
declare v jsonb;
begin
  begin
    perform public.search_coverage_receipt('example-user',
      '{"schema_version":"1","attempts":[{"store_id":"LOCAL-store","scope":"default","status":"queried","hit_count":0}]}'::jsonb);
    raise exception 'noncanonical identifier was accepted';
  exception when others then
    if sqlerrm='noncanonical identifier was accepted' then raise; end if;
    if sqlerrm not like 'search coverage attempt % has noncanonical identity/scope' then
      raise exception 'wrong canonical-identifier error: %',sqlerrm;
    end if;
  end;

  v:=public.search_coverage_receipt('example-user',
    '{"schema_version":"1","attempts":[{"store_id":"peer-store","scope":"default","status":"queried","hit_count":0},{"store_id":"local-store","scope":"default","status":"queried","hit_count":0}]}'::jsonb);
  if v#>>'{attempts,0,store_id}'<>'local-store' or v#>>'{attempts,1,store_id}'<>'peer-store' then
    raise exception 'coverage receipt did not canonicalize attempt ordering: %',v->'attempts';
  end if;
end $$;

-- Local identity has one durable source of truth. Disabled configuration is
-- distinct from unknown/not-configured and has not-applicable search coverage.
do $$
declare v jsonb;
begin
  if exists(select 1 from information_schema.columns
            where table_schema='public' and table_name='store_topology_profile'
              and column_name in ('local_store_id','local_store_profile')) then
    raise exception 'topology profile duplicates canonical local-store identity';
  end if;
  update public.known_memory_stores set enabled=false where store_id='peer-store';
  v:=public.topology_profile_boot('example-user');
  if v#>>'{visible_known_stores,1,configuration_state}'<>'disabled'
     or v#>>'{visible_known_stores,1,coverage_state}'<>'not_applicable' then
    raise exception 'disabled configuration/coverage states were conflated: %',v->'visible_known_stores';
  end if;
  update public.known_memory_stores set enabled=true where store_id='peer-store';
end $$;

-- Contract/version/digest attestation is fail closed and never disables local read-only boot.
do $$
declare v jsonb;v_digest text;
begin
  select contract_digest into v_digest from public.store_topology_profile where singleton;
  update public.store_topology_profile
  set observed_contract_version=contract_version,observed_contract_digest=contract_digest
  where singleton;
  v:=public.topology_profile_boot('example-user');
  if v#>>'{attestation,status}'<>'match' then raise exception 'attestation match failed'; end if;
  update public.store_topology_profile set observed_contract_digest=repeat('0',64) where singleton;
  v:=public.topology_profile_boot('example-user');
  if v#>>'{attestation,status}'<>'mismatch'
     or (v->>'read_only_local_available')::boolean is not true then
    raise exception 'attestation mismatch did not fail closed with recovery: %',v;
  end if;
  update public.store_topology_profile set observed_contract_digest=null where singleton;
  v:=public.topology_profile_boot('example-user');
  if v#>>'{attestation,status}'<>'unknown'
     or v#>>'{attestation,contract_digest}' is distinct from v_digest then
    raise exception 'attestation unknown/digest contract failed: %',v;
  end if;
end $$;

-- Viewer-filtered inbox metadata is stale/blocking aware and bounded to 25.
create temporary table issue72_inbox_baseline(total integer not null);
insert into issue72_inbox_baseline
select count(*)::integer from public.household_channel
where status='open' and to_principal in ('example-user','shared');
insert into public.household_channel(from_agent,to_principal,kind,subject,due_at,created_at)
select 'example-user-chatgpt','example-user','task','scope-task-'||g,null,
       now()-interval '8 days'-g*interval '1 minute'
from generate_series(1,30) g;
insert into public.household_channel(from_agent,to_principal,kind,subject,created_at)
values('example-partner-chatgpt','example-partner','task','private-other-principal-task',now()-interval '30 days');

do $$
declare v jsonb;v_expected integer;
begin
  select total+30 into v_expected from issue72_inbox_baseline;
  v:=public.session_boot('example-user');
  if (v#>>'{channel_inbox_coverage,total_visible}')::integer<>v_expected
     or (v#>>'{channel_inbox_coverage,represented}')::integer<>least(v_expected,25)
     or (v#>>'{channel_inbox_coverage,omitted}')::integer<>greatest(v_expected-25,0)
     or v#>>'{channel_inbox_coverage,status}'<>(case when v_expected<=25 then 'complete' else 'bounded' end)
     or jsonb_array_length(v->'channel_inbox')<>least(v_expected,25)
     or v::text like '%private-other-principal-task%' then
    raise exception 'viewer-filtered bounded inbox coverage failed: %',v->'channel_inbox_coverage';
  end if;
  if not exists(select 1 from jsonb_array_elements(v->'channel_inbox') item
                where item->>'subject' like 'scope-task-%'
                  and item ? 'created_at' and item ? 'age_seconds'
                  and item ? 'blocking' and item ? 'stale'
                  and jsonb_typeof(item->'age_seconds')='number'
                  and (item->>'age_seconds')::bigint>=691200
                  and (item->>'blocking')::boolean
                  and (item->>'stale')::boolean) then
    raise exception 'inbox lacks represented stale/blocking age metadata: %',v->'channel_inbox';
  end if;
end $$;

-- New authority seams are hardened, registered, PUBLIC-closed, service-usable
-- only under the configured perimeter profile, and resistant to temp shadowing.
do $$
declare v_bad text;
begin
  if not exists(select 1 from public.perimeter_authority_function_registry
                where function_identity='public.topology_profile_boot(text)' and not is_internal)
     or not exists(select 1 from public.perimeter_authority_function_registry
                where function_identity='public.search_coverage_receipt(text,jsonb)' and not is_internal) then
    raise exception 'topology authority seams are absent from perimeter registry';
  end if;
  select string_agg(p.oid::regprocedure::text,',') into v_bad
  from pg_proc p where p.oid in (
    'public.topology_profile_boot(text)'::regprocedure,
    'public.search_coverage_receipt(text,jsonb)'::regprocedure,
    'public.session_boot(text)'::regprocedure
  ) and (not p.prosecdef or p.proconfig is distinct from array['search_path=pg_catalog, pg_temp']
         or has_function_privilege('public',p.oid,'EXECUTE'));
  if v_bad is not null then raise exception 'new public seam perimeter mismatch: %',v_bad; end if;
  if exists(select 1 from pg_class c where c.oid in (
       'public.store_topology_profile'::regclass,'public.known_memory_stores'::regclass)
       and (not c.relrowsecurity or not c.relforcerowsecurity)) then
    raise exception 'topology metadata tables lack RLS/FORCE RLS';
  end if;
end $$;

-- Probe temporary names through the intended runtime role when that role is in
-- the durable profile; portable deployments intentionally have no grant.
do $$
begin
  if 'service_role'=any(((select function_execute_roles from public.perimeter_acl_policy where singleton))::text[])
     and (not has_function_privilege('service_role','public.topology_profile_boot(text)','EXECUTE')
          or not has_function_privilege('service_role','public.search_coverage_receipt(text,jsonb)','EXECUTE')) then
    raise exception 'intended service_role lacks new public seam grants';
  end if;
end $$;

set local role service_role;
create temporary table store_topology_profile(singleton boolean,topology_state text,local_store_id text);
insert into store_topology_profile values(true,'configured','attacker-shadow');
create temporary table known_memory_stores(store_id text,visibility text,owner text);
insert into known_memory_stores values('attacker-peer','shared','shared');
do $$
declare v jsonb;
begin
  if has_function_privilege(current_user,'public.topology_profile_boot(text)','EXECUTE') then
    v:=public.topology_profile_boot('example-user');
    if v#>>'{local_store,store_id}'='attacker-shadow' or v::text like '%attacker-peer%' then
      raise exception 'topology seam resolved caller temporary relations';
    end if;
  end if;
end $$;
reset role;

select public.assert_perimeter_closed();
rollback;
select 'topology/scope contract conformance passed' as result;
