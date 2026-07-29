-- Stale-grantee perimeter conformance. Role and ACL fixtures roll back together.
begin;
select set_config('sovereign_memory.perimeter_profile','supabase',true);
select set_config('sovereign_memory.perimeter_acl_mode','revoke',true);

create temporary table perimeter_history_snapshot as
select
  (select count(*) from public.work_lesson_events) lesson_event_count,
  (select count(*) from public.attention_events) attention_event_count,
  (select count(*) from public.attention_event_assignments) assignment_count,
  (select md5(coalesce(string_agg(row_to_json(x)::text,E'\n' order by x.id),''))
     from public.work_lesson_events x) lesson_event_hash,
  (select md5(coalesce(string_agg(row_to_json(x)::text,E'\n' order by x.id),''))
     from public.attention_events x) attention_event_hash,
  (select md5(coalesce(string_agg(row_to_json(x)::text,E'\n' order by x.id),''))
     from public.attention_event_assignments x) assignment_hash;

-- Regression: scalar policy arrays must reach the array form of ANY rather
-- than PostgreSQL's subquery form (which coerced the literal PUBLIC to text[]).
do $$
begin
  perform count(*) from public.perimeter_acl_violations();
exception when invalid_text_representation then
  raise exception 'perimeter ACL policy array dispatch regressed: %',sqlerrm;
end $$;

do $$
begin
  perform set_config('sovereign_memory.perimeter_allowed_schema_create_roles','PUBLIC',true);
  if 'PUBLIC'=any(public.perimeter_setting_roles(
       'sovereign_memory.perimeter_allowed_schema_create_roles')) then
    raise exception 'PUBLIC pseudo-grantee entered an explicit role allowlist';
  end if;
  perform set_config('sovereign_memory.perimeter_allowed_schema_create_roles','',true);
end $$;

create role smc_stale_direct nologin;
grant create on schema public to smc_stale_direct;
grant execute on function public.capture_memory_attention_after_insert() to smc_stale_direct;

do $$
begin
  begin
    perform public.assert_perimeter_closed();
  exception when others then
    if sqlstate='P0001'
       and sqlerrm like 'PERIMETER FAIL: unexpected effective ACL grantees:%'
       and sqlerrm like '%smc_stale_direct%'
       and sqlerrm like '%public%'
       and sqlerrm like '%capture_memory_attention_after_insert%'
       and sqlerrm like '%direct%' then return; end if;
    raise exception 'direct stale-grantee failure lacked evidence: %',sqlerrm;
  end;
  raise exception 'perimeter accepted arbitrary direct grantee';
end $$;

-- Fail mode reports only and leaves the stale grant in place.
select set_config('sovereign_memory.perimeter_acl_mode','fail',true);
do $$
declare v_result text;
begin
  v_result:=public.remediate_perimeter_acl();
  if v_result<>'perimeter ACL policy is fail-only' then
    raise exception 'unexpected fail-only remediation result: %',v_result;
  end if;
  if not has_schema_privilege('smc_stale_direct','public','CREATE') then
    raise exception 'fail-only policy revoked a direct stale grant';
  end if;
  begin
    perform public.assert_perimeter_closed();
  exception when others then
    if sqlstate='P0001'
       and sqlerrm like 'PERIMETER FAIL: unexpected effective ACL grantees:%'
       and sqlerrm like '%smc_stale_direct%' then return; end if;
    raise exception 'fail-only assertion lacked exact stale-grantee evidence: %',sqlerrm;
  end;
  raise exception 'fail-only policy accepted retained stale authority';
end $$;
select set_config('sovereign_memory.perimeter_acl_mode','revoke',true);
select public.remediate_perimeter_acl();
select public.assert_perimeter_closed();

create role smc_stale_parent nologin;
create role smc_stale_middle nologin;
create role smc_stale_leaf nologin;
grant smc_stale_parent to smc_stale_middle;
grant smc_stale_middle to smc_stale_leaf;
grant create on schema public to smc_stale_parent;
grant execute on function public.capture_memory_attention_after_insert() to smc_stale_parent;

do $$
begin
  begin
    perform public.assert_perimeter_closed();
  exception when others then
    if sqlstate='P0001'
       and sqlerrm like 'PERIMETER FAIL: unexpected effective ACL grantees:%'
       and sqlerrm like '%smc_stale_leaf%'
       and sqlerrm like '%inherited%' then return; end if;
    raise exception 'membership-chain failure lacked leaf/inherited evidence: %',sqlerrm;
  end;
  raise exception 'perimeter accepted inherited membership-chain authority';
end $$;
select public.remediate_perimeter_acl();
select public.assert_perimeter_closed();

grant create on schema public to public;
grant execute on function public.capture_memory_attention_after_insert() to public;

do $$
begin
  begin
    perform public.assert_perimeter_closed();
  exception when others then
    if sqlstate='P0001'
       and sqlerrm like 'PERIMETER FAIL: unexpected effective ACL grantees:%'
       and sqlerrm like '%PUBLIC%'
       and sqlerrm like '%CREATE%'
       and sqlerrm like '%EXECUTE%' then return; end if;
    raise exception 'PUBLIC-derived failure lacked privilege evidence: %',sqlerrm;
  end;
  raise exception 'perimeter accepted PUBLIC authority';
end $$;
select public.remediate_perimeter_acl();
select public.assert_perimeter_closed();

-- The named Supabase profile explicitly permits its runtime role on public
-- authority RPCs, but never waives trigger-only/internal EXECUTE.
do $$
begin
  if not has_function_privilege('service_role',
       'public.append_attention_event_revision(uuid,text,timestamp with time zone,text,text,jsonb)','EXECUTE') then
    raise exception 'supabase profile fixture lacks required runtime RPC grant';
  end if;
  if exists(select 1 from public.perimeter_acl_violations() where grantee='service_role') then
    raise exception 'declared supabase runtime role was treated as an assertion blind spot or violation';
  end if;
end $$;

-- Custom deployment allowlists are explicit effective-principal inputs.
create role smc_declared_runtime nologin;
select set_config('sovereign_memory.perimeter_allowed_schema_create_roles','smc_declared_runtime',true);
select set_config('sovereign_memory.perimeter_allowed_function_execute_roles','smc_declared_runtime',true);
grant create on schema public to smc_declared_runtime;
grant execute on function public.append_attention_event_revision(uuid,text,timestamptz,text,text,jsonb) to smc_declared_runtime;
select public.assert_perimeter_closed();
revoke create on schema public from smc_declared_runtime;
revoke execute on function public.append_attention_event_revision(uuid,text,timestamptz,text,text,jsonb) from smc_declared_runtime;

-- ACL-only remediation must not rewrite append-only historical rows.
do $$
declare before_row perimeter_history_snapshot%rowtype;
begin
  select * into before_row from perimeter_history_snapshot;
  if (select count(*) from public.work_lesson_events)<>before_row.lesson_event_count
     or (select count(*) from public.attention_events)<>before_row.attention_event_count
     or (select count(*) from public.attention_event_assignments)<>before_row.assignment_count
     or (select md5(coalesce(string_agg(row_to_json(x)::text,E'\n' order by x.id),'')) from public.work_lesson_events x)<>before_row.lesson_event_hash
     or (select md5(coalesce(string_agg(row_to_json(x)::text,E'\n' order by x.id),'')) from public.attention_events x)<>before_row.attention_event_hash
     or (select md5(coalesce(string_agg(row_to_json(x)::text,E'\n' order by x.id),'')) from public.attention_event_assignments x)<>before_row.assignment_hash then
    raise exception 'ACL remediation changed historical event or assignment rows';
  end if;
end $$;

rollback;
select 'stale-grantee perimeter conformance passed' as result;
