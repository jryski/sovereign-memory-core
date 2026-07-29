-- ============================================================================
-- SOVEREIGN MEMORY :: FINAL PERIMETER CLOSURE V4
-- Run after every optional public-schema layer.
--
-- Deployment policy is explicit:
--   sovereign_memory.perimeter_profile = portable (default) | supabase
--   sovereign_memory.perimeter_acl_mode = revoke (default) | fail
--   sovereign_memory.perimeter_allowed_owner_roles = comma-separated roles
--   sovereign_memory.perimeter_allowed_schema_create_roles = comma-separated roles
--   sovereign_memory.perimeter_allowed_function_execute_roles = comma-separated roles
--   sovereign_memory.perimeter_allowed_internal_execute_roles = comma-separated roles
-- A profile is a declared platform waiver, not a reason to skip grantee discovery.
-- Every effective role is still enumerated, including membership and PUBLIC.
-- ============================================================================

do $$
declare
  v_mode text:=coalesce(nullif(current_setting('sovereign_memory.perimeter_acl_mode',true),''),'revoke');
begin
  if v_mode not in ('revoke','fail') then
    raise exception 'PERIMETER FAIL: unknown sovereign_memory.perimeter_acl_mode %',v_mode;
  end if;
  if v_mode='revoke' then
    revoke create on schema public from public;
    if exists(select 1 from pg_namespace where nspname='extensions') then
      revoke create on schema extensions from public;
    end if;
    revoke all on all tables in schema public from public;
    revoke all on all sequences in schema public from public;
    revoke execute on all functions in schema public from public;
    alter default privileges in schema public revoke all on tables from public;
    alter default privileges in schema public revoke all on sequences from public;
    alter default privileges in schema public revoke execute on functions from public;
  end if;
end $$;

create or replace function perimeter_setting_roles(p_setting text)
returns text[]
language sql stable set search_path=pg_catalog as $$
select coalesce(
  array_agg(distinct btrim(value) order by btrim(value))
    filter(where lower(btrim(value))<>'public' and btrim(value)<>''),
  array[]::text[]
)
from regexp_split_to_table(coalesce(current_setting(p_setting,true),''),',') value;
$$;

create or replace function perimeter_policy_roles(p_kind text)
returns text[]
language plpgsql stable set search_path=pg_catalog as $$
declare
  v_profile text:=coalesce(nullif(current_setting('sovereign_memory.perimeter_profile',true),''),'portable');
  v_roles text[]:=array[]::text[];
begin
  if v_profile not in ('portable','supabase') then
    raise exception 'PERIMETER FAIL: unknown sovereign_memory.perimeter_profile %',v_profile;
  end if;

  case p_kind
    when 'owner' then
      v_roles:=array[current_user,'pg_database_owner']
        ||public.perimeter_setting_roles('sovereign_memory.perimeter_allowed_owner_roles');
    when 'schema_create' then
      v_roles:=public.perimeter_setting_roles('sovereign_memory.perimeter_allowed_schema_create_roles');
    when 'function_execute' then
      if v_profile='supabase' then v_roles:=array['service_role']; end if;
      v_roles:=v_roles||public.perimeter_setting_roles('sovereign_memory.perimeter_allowed_function_execute_roles');
    when 'internal_execute' then
      v_roles:=public.perimeter_setting_roles('sovereign_memory.perimeter_allowed_internal_execute_roles');
    else
      raise exception 'PERIMETER FAIL: unknown perimeter policy kind %',p_kind;
  end case;

  return array(select distinct x from unnest(v_roles) x where x is not null and x<>'');
end;
$$;

create or replace function perimeter_protected_schemas()
returns table(schema_oid oid,schema_name text)
language sql stable set search_path=pg_catalog as $$
with configured_paths as (
  select regexp_split_to_table(substr(setting,13),',') path_item
  from pg_proc p
  cross join lateral unnest(p.proconfig) setting
  where p.prosecdef and setting like 'search_path=%'
), names as (
  select btrim(path_item,E' \t\n\r"') schema_name
  from configured_paths
)
select distinct n.oid,n.nspname
from names x join pg_namespace n on n.nspname=x.schema_name
where x.schema_name not in ('','$user');
$$;

create or replace function perimeter_authority_functions()
returns table(function_oid oid,function_identity text,is_internal boolean)
language sql stable set search_path=pg_catalog as $$
with targets as (
  select p.oid,
         p.prosecdef,
         exists(select 1 from pg_trigger t where not t.tgisinternal and t.tgfoid=p.oid) is_trigger,
         format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)) identity
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where p.prosecdef
     or exists(select 1 from pg_trigger t where not t.tgisinternal and t.tgfoid=p.oid)
     or (n.nspname='public' and p.proname in (
       'attention_fixed_point_chars','attention_set_rendered_chars','remediate_perimeter_acl'
     ))
)
select oid,identity,
       is_trigger or identity in (
         'public.attention_fixed_point_chars(integer)',
         'public.attention_set_rendered_chars(jsonb)',
         'public.remediate_perimeter_acl()'
       )
from targets;
$$;

create or replace function perimeter_acl_violations()
returns table(
  boundary text,
  object_identity text,
  grantee text,
  privilege_type text,
  privilege_source text
)
language sql stable set search_path=pg_catalog,public as $$
with policy as (
  select perimeter_policy_roles('owner') owners,
         perimeter_policy_roles('schema_create') schema_creators,
         perimeter_policy_roles('function_execute') function_executors,
         perimeter_policy_roles('internal_execute') internal_executors
), protected_schemas as (
  select s.*,n.nspowner
  from perimeter_protected_schemas() s join pg_namespace n on n.oid=s.schema_oid
), schema_acl as (
  select s.schema_oid,a.grantee
  from protected_schemas s
  cross join lateral aclexplode(coalesce((select nspacl from pg_namespace where oid=s.schema_oid),acldefault('n',s.nspowner))) a
  where a.privilege_type='CREATE'
), schema_public as (
  select 'schema'::text,s.schema_name,'PUBLIC'::text,'CREATE'::text,'PUBLIC'::text
  from protected_schemas s
  where exists(select 1 from schema_acl a where a.schema_oid=s.schema_oid and a.grantee=0)
    and not ('PUBLIC'=any(((select schema_creators from policy))::text[]))
), schema_roles as (
  select 'schema'::text,s.schema_name,r.rolname,'CREATE'::text,
         case
           when exists(select 1 from schema_acl a where a.schema_oid=s.schema_oid and a.grantee=r.oid) then 'direct'
           when exists(select 1 from schema_acl a where a.schema_oid=s.schema_oid and a.grantee=0) then 'PUBLIC'
           else 'inherited'
         end::text
  from protected_schemas s
  join pg_roles r on has_schema_privilege(r.oid,s.schema_oid,'CREATE')
  where r.oid<>s.nspowner
    and not (r.rolname=any(((select owners from policy))::text[]))
    and not (r.rolname=any(((select schema_creators from policy))::text[]))
), authority_functions as (
  select f.*,p.proowner,p.proacl
  from perimeter_authority_functions() f join pg_proc p on p.oid=f.function_oid
), function_acl as (
  select f.function_oid,a.grantee
  from authority_functions f
  cross join lateral aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) a
  where a.privilege_type='EXECUTE'
), function_public as (
  select case when f.is_internal then 'internal_function' else 'authority_function' end,
         f.function_identity,'PUBLIC'::text,'EXECUTE'::text,'PUBLIC'::text
  from authority_functions f
  where exists(select 1 from function_acl a where a.function_oid=f.function_oid and a.grantee=0)
    and not ('PUBLIC'=any((case when f.is_internal then
      (select internal_executors from policy) else (select function_executors from policy) end)::text[]))
), function_roles as (
  select case when f.is_internal then 'internal_function' else 'authority_function' end,
         f.function_identity,r.rolname,'EXECUTE'::text,
         case
           when exists(select 1 from function_acl a where a.function_oid=f.function_oid and a.grantee=r.oid) then 'direct'
           when exists(select 1 from function_acl a where a.function_oid=f.function_oid and a.grantee=0) then 'PUBLIC'
           else 'inherited'
         end::text
  from authority_functions f
  join pg_roles r on has_function_privilege(r.oid,f.function_oid,'EXECUTE')
  where r.oid<>f.proowner
    and not (r.rolname=any(((select owners from policy))::text[]))
    and not (r.rolname=any((case when f.is_internal then
      (select internal_executors from policy) else (select function_executors from policy) end)::text[]))
)
select * from schema_public
union all select * from schema_roles
union all select * from function_public
union all select * from function_roles;
$$;

create or replace function remediate_perimeter_acl()
returns text
language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_mode text:=coalesce(nullif(current_setting('sovereign_memory.perimeter_acl_mode',true),''),'revoke');
  v_object record;
  v_acl record;
  v_allowed text[];
  v_owner text[]:=perimeter_policy_roles('owner');
  v_revoked integer:=0;
begin
  if v_mode not in ('revoke','fail') then
    raise exception 'PERIMETER FAIL: unknown sovereign_memory.perimeter_acl_mode %',v_mode;
  end if;
  if v_mode='fail' then return 'perimeter ACL policy is fail-only'; end if;

  for v_object in
    select s.schema_oid,s.schema_name,n.nspowner
    from perimeter_protected_schemas() s join pg_namespace n on n.oid=s.schema_oid
  loop
    v_allowed:=perimeter_policy_roles('schema_create');
    for v_acl in
      select a.grantee,case when a.grantee=0 then 'PUBLIC' else r.rolname end grantee_name
      from aclexplode(coalesce((select nspacl from pg_namespace where oid=v_object.schema_oid),acldefault('n',v_object.nspowner))) a
      left join pg_roles r on r.oid=a.grantee
      where a.privilege_type='CREATE'
        and a.grantee<>v_object.nspowner
        and not (coalesce(r.rolname,'PUBLIC')=any(v_owner))
        and not (coalesce(r.rolname,'PUBLIC')=any(v_allowed))
    loop
      execute format('revoke create on schema %I from %s',v_object.schema_name,
        case when v_acl.grantee=0 then 'PUBLIC' else format('%I',v_acl.grantee_name) end);
      v_revoked:=v_revoked+1;
    end loop;
  end loop;

  for v_object in
    select f.function_oid,f.function_identity,f.is_internal,p.proowner,p.proacl
    from perimeter_authority_functions() f join pg_proc p on p.oid=f.function_oid
  loop
    v_allowed:=case when v_object.is_internal then perimeter_policy_roles('internal_execute')
                    else perimeter_policy_roles('function_execute') end;
    for v_acl in
      select a.grantee,case when a.grantee=0 then 'PUBLIC' else r.rolname end grantee_name
      from aclexplode(coalesce(v_object.proacl,acldefault('f',v_object.proowner))) a
      left join pg_roles r on r.oid=a.grantee
      where a.privilege_type='EXECUTE'
        and a.grantee<>v_object.proowner
        and not (coalesce(r.rolname,'PUBLIC')=any(v_owner))
        and not (coalesce(r.rolname,'PUBLIC')=any(v_allowed))
    loop
      execute format('revoke execute on function %s from %s',v_object.function_identity,
        case when v_acl.grantee=0 then 'PUBLIC' else format('%I',v_acl.grantee_name) end);
      v_revoked:=v_revoked+1;
    end loop;
  end loop;

  return format('perimeter ACL remediation revoked %s direct grant(s)',v_revoked);
end;
$$;

create or replace function assert_perimeter_closed()
returns text
language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_bad text;
  v_item text;
  v_owner text[]:=perimeter_policy_roles('owner');
  v_tables text[]:=array[
    'work_lessons','work_lesson_evidence','work_lesson_events',
    'attention_events','attention_event_assignments'
  ];
begin
  select string_agg(format('%s %s %s via %s',grantee,privilege_type,object_identity,privilege_source),', '
                    order by boundary,object_identity,grantee)
  into v_bad from perimeter_acl_violations();
  if v_bad is not null then
    raise exception 'PERIMETER FAIL: unexpected effective ACL grantees: %',v_bad;
  end if;

  select string_agg(format('%s owner=%s',s.schema_name,r.rolname),', ' order by s.schema_name)
  into v_bad
  from perimeter_protected_schemas() s
  join pg_namespace n on n.oid=s.schema_oid join pg_roles r on r.oid=n.nspowner
  where not (r.rolname=any(v_owner));
  if v_bad is not null then raise exception 'PERIMETER FAIL: unexpected protected-schema owner: %',v_bad; end if;

  select string_agg(c.relname,', ' order by c.relname) into v_bad
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname=any(v_tables)
    and(not c.relrowsecurity or not c.relforcerowsecurity);
  if v_bad is not null then
    raise exception 'PERIMETER FAIL: protected tables lack RLS/FORCE RLS: %',v_bad;
  end if;

  select string_agg(c.relname||' owner='||r.rolname,', ' order by c.relname) into v_bad
  from pg_class c
  join pg_namespace n on n.oid=c.relnamespace join pg_roles r on r.oid=c.relowner
  where n.nspname='public' and c.relname=any(v_tables) and not (r.rolname=any(v_owner));
  if v_bad is not null then raise exception 'PERIMETER FAIL: unexpected protected-table owner: %',v_bad; end if;

  select string_agg(f.function_identity||' owner='||r.rolname,', ' order by f.function_identity) into v_bad
  from perimeter_authority_functions() f
  join pg_proc p on p.oid=f.function_oid join pg_roles r on r.oid=p.proowner
  where not (r.rolname=any(v_owner));
  if v_bad is not null then raise exception 'PERIMETER FAIL: unexpected authority-function owner: %',v_bad; end if;

  select string_agg(grantee||':'||table_name||':'||privilege_type,', '
                    order by grantee,table_name,privilege_type) into v_bad
  from information_schema.role_table_grants
  where table_schema='public' and table_name=any(v_tables)
    and grantee<>all(v_owner) and grantee<>'service_role';
  if v_bad is not null then raise exception 'PERIMETER FAIL: stale protected-table grantees: %',v_bad; end if;

  if exists(select 1 from pg_roles where rolname='service_role') then
    foreach v_item in array v_tables loop
      if has_table_privilege('service_role',format('public.%I',v_item),
        'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
        raise exception 'PERIMETER FAIL: service_role has direct mutation on %',v_item;
      end if;
    end loop;
    if exists(select 1 from pg_roles where rolname='pg_write_all_data')
       and pg_has_role('service_role','pg_write_all_data','MEMBER') then
      raise exception 'PERIMETER FAIL: service_role inherits pg_write_all_data';
    end if;
  end if;

  select string_agg(f.function_identity,', ' order by f.function_identity) into v_bad
  from perimeter_authority_functions() f join pg_proc p on p.oid=f.function_oid
  where p.prosecdef and(
    p.proconfig is null
    or not exists(select 1 from unnest(p.proconfig) x where x like 'search_path=%')
    or exists(select 1 from unnest(p.proconfig) x
              where x like 'search_path=%' and(x ilike '%pg_temp%' or x ilike '%$user%'))
  );
  if v_bad is not null then raise exception 'PERIMETER FAIL: unsafe or missing function search_path: %',v_bad; end if;

  return 'perimeter OK: effective schema/function ACLs, owners, RLS/FORCE, runtime mutation, inheritance, PUBLIC and SECURITY DEFINER search paths verified';
end;
$$;

revoke all on function perimeter_setting_roles(text) from public;
revoke all on function perimeter_policy_roles(text) from public;
revoke all on function perimeter_protected_schemas() from public;
revoke all on function perimeter_authority_functions() from public;
revoke all on function perimeter_acl_violations() from public;
revoke all on function remediate_perimeter_acl() from public;
revoke all on function assert_perimeter_closed() from public;

select remediate_perimeter_acl();

do $$
begin
  if exists(select 1 from pg_roles where rolname='service_role')
     and coalesce(nullif(current_setting('sovereign_memory.perimeter_profile',true),''),'portable')='supabase' then
    grant execute on function assert_perimeter_closed() to service_role;
  end if;
end $$;

select assert_perimeter_closed();
