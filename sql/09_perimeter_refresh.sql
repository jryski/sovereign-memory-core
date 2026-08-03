-- ============================================================================
-- SOVEREIGN MEMORY :: FINAL PERIMETER CLOSURE V5
-- Run after every optional public-schema layer.
--
-- Deployment inputs are read only while this owner-run migration persists an
-- ACL-protected policy snapshot. Runtime assertions never trust session GUCs.
--   sovereign_memory.perimeter_profile = portable (default) | supabase
--   sovereign_memory.perimeter_acl_mode = revoke (default) | fail
--   sovereign_memory.perimeter_allowed_owner_roles = comma-separated roles
--   sovereign_memory.perimeter_allowed_schema_create_roles = comma-separated roles
--   sovereign_memory.perimeter_allowed_function_execute_roles = comma-separated roles
--   sovereign_memory.perimeter_allowed_internal_execute_roles = comma-separated roles
-- ============================================================================

create table if not exists perimeter_acl_policy (
  singleton boolean primary key default true check(singleton),
  profile text not null check(profile in ('portable','supabase')),
  owner_roles text[] not null,
  schema_create_roles text[] not null,
  function_execute_roles text[] not null,
  internal_execute_roles text[] not null,
  updated_at timestamptz not null default now(),
  constraint perimeter_owner_roles_are_named check(not ('public'=any(lower(owner_roles::text)::text[]))),
  constraint perimeter_schema_roles_are_named check(not ('public'=any(lower(schema_create_roles::text)::text[]))),
  constraint perimeter_function_roles_are_named check(not ('public'=any(lower(function_execute_roles::text)::text[]))),
  constraint perimeter_internal_roles_are_named check(not ('public'=any(lower(internal_execute_roles::text)::text[])))
);

create table if not exists perimeter_protected_schema_registry (
  schema_name text primary key check(schema_name<>'' and schema_name=btrim(schema_name))
);

create table if not exists perimeter_authority_function_registry (
  function_identity text primary key check(function_identity<>'' and function_identity=btrim(function_identity)),
  is_internal boolean not null
);

-- These tables are the trust root for the bounded inventory and policy. Validate
-- their non-destructive upgrade shape before reading or writing them, and use
-- the migration identity (never a row in an attacker-writable table) as their
-- trusted owner. Fail mode is observation-only for pre-existing drift.
do $$
declare
  v_mode text:=coalesce(nullif(current_setting('sovereign_memory.perimeter_acl_mode',true),''),'revoke');
  v_table text;
  v_actual text[];
  v_expected text[];
  v_bad text;
  v_acl record;
begin
  if v_mode not in ('revoke','fail') then
    raise exception 'PERIMETER FAIL: unknown sovereign_memory.perimeter_acl_mode %',v_mode;
  end if;

  for v_table,v_expected in values
    ('perimeter_acl_policy',array[
      'singleton:boolean:true','profile:text:true','owner_roles:text[]:true',
      'schema_create_roles:text[]:true','function_execute_roles:text[]:true',
      'internal_execute_roles:text[]:true','updated_at:timestamp with time zone:true']),
    ('perimeter_protected_schema_registry',array['schema_name:text:true']),
    ('perimeter_authority_function_registry',array[
      'function_identity:text:true','is_internal:boolean:true'])
  loop
    select array_agg(a.attname||':'||format_type(a.atttypid,a.atttypmod)||':'||a.attnotnull order by a.attnum)
      into v_actual
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
    where n.nspname='public' and c.relname=v_table
      and c.relkind='r' and c.relpersistence='p';
    if v_actual is distinct from v_expected then
      raise exception 'PERIMETER FAIL: durable control-table shape mismatch for public.%: expected %, found %; manual non-destructive repair required',
        v_table,v_expected,v_actual;
    end if;
    if exists(
      select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname=v_table
        and (c.relrowsecurity or c.relforcerowsecurity)
    ) or exists(
      select 1 from pg_attribute a
      where a.attrelid=format('public.%I',v_table)::regclass and a.attnum>0
        and not a.attisdropped and (a.attgenerated<>'' or a.attidentity<>'')
    ) or exists(
      select 1 from pg_trigger t
      where t.tgrelid=format('public.%I',v_table)::regclass and not t.tgisinternal
    ) or exists(
      select 1 from pg_rewrite r
      where r.ev_class=format('public.%I',v_table)::regclass and r.rulename<>'_RETURN'
    ) then
      raise exception 'PERIMETER FAIL: durable control-table shape mismatch for public.%: unexpected RLS, trigger, or rule; manual non-destructive repair required',v_table;
    end if;
  end loop;

  if not exists(select 1 from pg_constraint where conrelid='public.perimeter_acl_policy'::regclass and contype='p' and pg_get_constraintdef(oid)='PRIMARY KEY (singleton)')
     or not exists(select 1 from pg_constraint where conrelid='public.perimeter_acl_policy'::regclass and contype='c' and conname='perimeter_acl_policy_singleton_check' and pg_get_constraintdef(oid)='CHECK (singleton)')
     or not exists(select 1 from pg_constraint where conrelid='public.perimeter_acl_policy'::regclass and contype='c' and conname='perimeter_acl_policy_profile_check' and pg_get_constraintdef(oid) like 'CHECK ((profile = ANY (%portable%supabase%)))')
     or exists(
       select 1 from (values
         ('perimeter_owner_roles_are_named','owner_roles'),
         ('perimeter_schema_roles_are_named','schema_create_roles'),
         ('perimeter_function_roles_are_named','function_execute_roles'),
         ('perimeter_internal_roles_are_named','internal_execute_roles')
       ) e(conname,column_name)
       where not exists(
         select 1 from pg_constraint c
         where c.conrelid='public.perimeter_acl_policy'::regclass and c.contype='c'
           and c.conname=e.conname
           and pg_get_constraintdef(c.oid) like '%NOT%public%ANY%lower%'||e.column_name||'%'
       )
     )
     or (select pg_get_expr(d.adbin,d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid=d.adrelid and a.attnum=d.adnum where d.adrelid='public.perimeter_acl_policy'::regclass and a.attname='singleton') is distinct from 'true'
     or (select pg_get_expr(d.adbin,d.adrelid) from pg_attrdef d join pg_attribute a on a.attrelid=d.adrelid and a.attnum=d.adnum where d.adrelid='public.perimeter_acl_policy'::regclass and a.attname='updated_at') is distinct from 'now()'
     or (select count(*) from pg_constraint where conrelid='public.perimeter_acl_policy'::regclass and contype in ('p','u','c','f','x'))<>7
     or (select count(*) from pg_constraint where conrelid='public.perimeter_protected_schema_registry'::regclass and contype in ('p','u','c','f','x'))<>2
     or (select count(*) from pg_constraint where conrelid='public.perimeter_authority_function_registry'::regclass and contype in ('p','u','c','f','x'))<>2
     or not exists(select 1 from pg_constraint where conrelid='public.perimeter_protected_schema_registry'::regclass and contype='p' and pg_get_constraintdef(oid)='PRIMARY KEY (schema_name)')
     or not exists(select 1 from pg_constraint where conrelid='public.perimeter_protected_schema_registry'::regclass and contype='c' and pg_get_constraintdef(oid) like '%schema_name%<>%btrim%')
     or not exists(select 1 from pg_constraint where conrelid='public.perimeter_authority_function_registry'::regclass and contype='p' and pg_get_constraintdef(oid)='PRIMARY KEY (function_identity)')
     or not exists(select 1 from pg_constraint where conrelid='public.perimeter_authority_function_registry'::regclass and contype='c' and pg_get_constraintdef(oid) like '%function_identity%<>%btrim%') then
    raise exception 'PERIMETER FAIL: durable control-table constraint mismatch; manual non-destructive repair required';
  end if;

  -- Ownership and ACL evidence are aggregated after optional remediation so fail
  -- mode reports all drift in one operator-action error.

  if v_mode='revoke' then
    for v_table in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public'
        and c.relname=any(array['perimeter_acl_policy','perimeter_protected_schema_registry','perimeter_authority_function_registry'])
        and c.relowner<>current_user::regrole
    loop
      execute format('alter table public.%I owner to %I',v_table,current_user);
    end loop;
    for v_acl in
      select c.relname,a.grantee,case when a.grantee=0 then 'PUBLIC' else r.rolname end grantee_name
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
      left join pg_roles r on r.oid=a.grantee
      where n.nspname='public'
        and c.relname=any(array['perimeter_acl_policy','perimeter_protected_schema_registry','perimeter_authority_function_registry'])
        and a.grantee<>c.relowner
    loop
      execute format('revoke all on table public.%I from %s',v_acl.relname,
        case when v_acl.grantee=0 then 'PUBLIC' else format('%I',v_acl.grantee_name) end);
    end loop;
    for v_acl in
      select c.relname,att.attname,a.privilege_type,a.grantee,
             case when a.grantee=0 then 'PUBLIC' else r.rolname end grantee_name
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      join pg_attribute att on att.attrelid=c.oid and att.attnum>0 and not att.attisdropped and att.attacl is not null
      cross join lateral aclexplode(att.attacl) a left join pg_roles r on r.oid=a.grantee
      where n.nspname='public'
        and c.relname=any(array['perimeter_acl_policy','perimeter_protected_schema_registry','perimeter_authority_function_registry'])
        and a.grantee<>c.relowner
    loop
      execute format('revoke %s (%I) on table public.%I from %s',v_acl.privilege_type,v_acl.attname,v_acl.relname,
        case when v_acl.grantee=0 then 'PUBLIC' else format('%I',v_acl.grantee_name) end);
    end loop;
  end if;

  with control_tables as (
    select c.oid,c.relname,c.relowner,r.rolname owner_name
    from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_roles r on r.oid=c.relowner
    where n.nspname='public'
      and c.relname=any(array['perimeter_acl_policy','perimeter_protected_schema_registry','perimeter_authority_function_registry'])
  ), table_acl as (
    select c.oid,c.relname,c.relowner,a.grantee,a.privilege_type
    from control_tables c
    cross join lateral aclexplode(coalesce(
      (select relacl from pg_class where oid=c.oid),acldefault('r',c.relowner))) a
  ), column_acl as (
    select c.oid,c.relname,c.relowner,att.attname,a.grantee,a.privilege_type
    from control_tables c
    join pg_attribute att on att.attrelid=c.oid and att.attnum>0
      and not att.attisdropped and att.attacl is not null
    cross join lateral aclexplode(att.attacl) a
  ), violations as (
    select relname,owner_name grantee,'OWNER'::text privilege,'owner'::text source
    from control_tables where relowner<>current_user::regrole
    union all
    select a.relname,'PUBLIC',a.privilege_type,'PUBLIC'
    from table_acl a where a.grantee=0
    union all
    select distinct a.relname,r.rolname,a.privilege_type,
           case when r.oid=a.grantee then 'direct' else 'inherited' end
    from table_acl a
    join pg_roles r on a.grantee<>0 and pg_has_role(r.oid,a.grantee,'USAGE')
    where a.grantee<>a.relowner and r.oid<>a.relowner
      and not (r.rolname like 'pg\_%' escape '\' and not r.rolcanlogin)
    union all
    select a.relname,'PUBLIC',a.privilege_type||'('||a.attname||')','PUBLIC'
    from column_acl a where a.grantee=0
    union all
    select distinct a.relname,r.rolname,a.privilege_type||'('||a.attname||')',
           case when r.oid=a.grantee then 'direct' else 'inherited' end
    from column_acl a
    join pg_roles r on a.grantee<>0 and pg_has_role(r.oid,a.grantee,'USAGE')
    where a.grantee<>a.relowner and r.oid<>a.relowner
      and not (r.rolname like 'pg\_%' escape '\' and not r.rolcanlogin)
  )
  select string_agg(format('%s grantee=%s privilege=%s source=%s',relname,grantee,privilege,source),', '
                    order by relname,grantee,privilege,source)
    into v_bad from violations;
  if v_bad is not null then
    raise exception 'PERIMETER FAIL: durable control-table ownership/effective ACLs require operator action: %',v_bad;
  end if;
end $$;

do $$
declare
  v_profile text:=coalesce(nullif(current_setting('sovereign_memory.perimeter_profile',true),''),'portable');
  v_owner text[];
  v_schema text[];
  v_function text[];
  v_internal text[];
  r text;
begin
  if v_profile not in ('portable','supabase') then
    raise exception 'PERIMETER FAIL: unknown sovereign_memory.perimeter_profile %',v_profile;
  end if;
  select coalesce(array_agg(distinct btrim(x) order by btrim(x)) filter(where btrim(x)<>'' and lower(btrim(x))<>'public'),array[]::text[])
    into v_owner from regexp_split_to_table(coalesce(current_setting('sovereign_memory.perimeter_allowed_owner_roles',true),''),',') x;
  select coalesce(array_agg(distinct btrim(x) order by btrim(x)) filter(where btrim(x)<>'' and lower(btrim(x))<>'public'),array[]::text[])
    into v_schema from regexp_split_to_table(coalesce(current_setting('sovereign_memory.perimeter_allowed_schema_create_roles',true),''),',') x;
  select coalesce(array_agg(distinct btrim(x) order by btrim(x)) filter(where btrim(x)<>'' and lower(btrim(x))<>'public'),array[]::text[])
    into v_function from regexp_split_to_table(coalesce(current_setting('sovereign_memory.perimeter_allowed_function_execute_roles',true),''),',') x;
  select coalesce(array_agg(distinct btrim(x) order by btrim(x)) filter(where btrim(x)<>'' and lower(btrim(x))<>'public'),array[]::text[])
    into v_internal from regexp_split_to_table(coalesce(current_setting('sovereign_memory.perimeter_allowed_internal_execute_roles',true),''),',') x;
  if v_profile='supabase' then v_function:=v_function||array['service_role']; end if;
  v_owner:=v_owner||array[current_user,'pg_database_owner'];

  insert into perimeter_acl_policy(singleton,profile,owner_roles,schema_create_roles,function_execute_roles,internal_execute_roles)
  values(true,v_profile,
    array(select distinct x from unnest(v_owner) x where x<>''),
    array(select distinct x from unnest(v_schema) x where x<>''),
    array(select distinct x from unnest(v_function) x where x<>''),
    array(select distinct x from unnest(v_internal) x where x<>''))
  on conflict(singleton) do update set
    profile=excluded.profile,owner_roles=excluded.owner_roles,
    schema_create_roles=excluded.schema_create_roles,
    function_execute_roles=excluded.function_execute_roles,
    internal_execute_roles=excluded.internal_execute_roles,updated_at=now();

  insert into perimeter_protected_schema_registry(schema_name)
  select schema_name from unnest(array['public','extensions']) schema_name
  where to_regnamespace(schema_name) is not null
  on conflict do nothing;

  delete from perimeter_authority_function_registry where function_identity in (
    'public.perimeter_setting_roles(text)','public.perimeter_policy_roles(text)',
    'public.perimeter_protected_schemas()','public.perimeter_authority_functions()',
    'public.perimeter_acl_violations()','public.assert_perimeter_closed()',
    'public.promote_memory(uuid,text)'
  );

  insert into perimeter_authority_function_registry(function_identity,is_internal) values
    ('public.current_doc_hash(text)',false),
    ('public.verify_doc_integrity(text)',false),
    ('public.bless_doc(text,text)',false),
    ('public.hot_touch(text,uuid,text,text)',false),
    ('public.remember(text,text,text,text,text,text,text[],text,timestamp with time zone)',false),
    ('public.supersede_memory(uuid,text,text,text,text[],timestamp with time zone)',false),
    ('public.supersede_wiki(text,text,text,text,jsonb)',false),
    ('public.channel_send(text,text,text,text,text,timestamp with time zone,boolean,bigint)',false),
    ('public.channel_complete(bigint,text)',false),
    ('public.session_boot(text)',false),
    ('public.propose_work_lesson(text,text,text,text,text,text,text,text,text)',false),
    ('public.append_work_lesson_evidence(uuid,text,text,text,text,text,text)',false),
    ('public.correct_work_lesson_evidence(uuid,text,text,text,text,text,text,text)',false),
    ('public.propose_lesson_supersession(uuid,text,text,text,text,text,text,text,text)',false),
    ('public.accept_work_lesson(uuid,text,text)',false),
    ('public.reject_work_lesson(uuid,text,text)',false),
    ('public.work_lessons_boot_fragment()',false),
    ('public.record_native_memory_attention(uuid)',false),
    ('public.record_native_memory_activation(uuid,text)',false),
    ('public.append_attention_event_revision(uuid,text,timestamp with time zone,text,text,jsonb)',false),
    ('public.promote_memory(uuid,text,text)',false),
    ('public.attention_boot_projection_v2(text,integer,integer)',false),
    ('public.attention_budget_conformance_v2(text,integer,integer)',false),
    ('public.capture_memory_attention_after_insert()',true),
    ('public.capture_memory_activation_after_update()',true),
    ('public.attention_fixed_point_chars(integer)',true),
    ('public.attention_set_rendered_chars(jsonb)',true),
    ('public.remediate_perimeter_acl()',true)
  on conflict(function_identity) do update set is_internal=excluded.is_internal;

end $$;

create or replace function perimeter_setting_roles(p_setting text)
returns text[]
language sql stable set search_path=pg_catalog as $$
select case p_setting
  when 'sovereign_memory.perimeter_allowed_owner_roles' then owner_roles
  when 'sovereign_memory.perimeter_allowed_schema_create_roles' then schema_create_roles
  when 'sovereign_memory.perimeter_allowed_function_execute_roles' then function_execute_roles
  when 'sovereign_memory.perimeter_allowed_internal_execute_roles' then internal_execute_roles
  else array[]::text[]
end
from public.perimeter_acl_policy where singleton;
$$;

create or replace function perimeter_policy_roles(p_kind text)
returns text[]
language plpgsql stable set search_path=pg_catalog,public as $$
declare v_roles text[];
begin
  select case p_kind
    when 'owner' then owner_roles
    when 'schema_create' then schema_create_roles
    when 'function_execute' then function_execute_roles
    when 'internal_execute' then internal_execute_roles
    else null
  end into v_roles from perimeter_acl_policy where singleton;
  if v_roles is null then
    raise exception 'PERIMETER FAIL: unknown perimeter policy kind %',p_kind;
  end if;
  return v_roles;
end;
$$;

create or replace function perimeter_protected_schemas()
returns table(schema_oid oid,schema_name text)
language sql stable set search_path=pg_catalog,public as $$
select n.oid,n.nspname
from perimeter_protected_schema_registry r
join pg_namespace n on n.nspname=r.schema_name;
$$;

create or replace function perimeter_authority_functions()
returns table(function_oid oid,function_identity text,is_internal boolean)
language sql stable set search_path=pg_catalog,public as $$
select p.oid,format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),r.is_internal
from perimeter_authority_function_registry r
join pg_proc p on p.oid=to_regprocedure(r.function_identity)
join pg_namespace n on n.oid=p.pronamespace;
$$;

create or replace function perimeter_acl_violations()
returns table(boundary text,object_identity text,grantee text,privilege_type text,privilege_source text)
language sql stable set search_path=pg_catalog,public as $$
with policy as (
  select perimeter_policy_roles('owner') owners,
         perimeter_policy_roles('schema_create') schema_creators,
         perimeter_policy_roles('function_execute') function_executors,
         perimeter_policy_roles('internal_execute') internal_executors
), protected_schemas as (
  select s.*,n.nspowner from perimeter_protected_schemas() s join pg_namespace n on n.oid=s.schema_oid
), schema_acl as (
  select s.schema_oid,a.grantee from protected_schemas s
  cross join lateral aclexplode(coalesce((select nspacl from pg_namespace where oid=s.schema_oid),acldefault('n',s.nspowner))) a
  where a.privilege_type='CREATE'
), schema_public as (
  select 'schema'::text,s.schema_name,'PUBLIC'::text,'CREATE'::text,'PUBLIC'::text
  from protected_schemas s
  where exists(select 1 from schema_acl a where a.schema_oid=s.schema_oid and a.grantee=0)
    and not ('PUBLIC'=any(((select schema_creators from policy))::text[]))
), schema_roles as (
  -- Derive each finding from the non-PUBLIC ACL fact that supplies it. Do not
  -- collapse simultaneous direct and membership-chain sources by asking only
  -- whether the role has the effective privilege.
  select distinct 'schema'::text,s.schema_name,r.rolname,'CREATE'::text,
         case when r.oid=a.grantee then 'direct' else 'inherited' end::text
  from protected_schemas s
  join schema_acl a on a.schema_oid=s.schema_oid and a.grantee<>0
  join pg_roles r on pg_has_role(r.oid,a.grantee,'USAGE')
  where r.oid<>s.nspowner and not (r.rolname=any(((select owners from policy))::text[]))
    and not (r.rolname=any(((select schema_creators from policy))::text[]))
), authority_functions as (
  select f.*,p.proowner,p.proacl from perimeter_authority_functions() f join pg_proc p on p.oid=f.function_oid
), function_acl as (
  select f.function_oid,a.grantee from authority_functions f
  cross join lateral aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) a
  where a.privilege_type='EXECUTE'
), function_public as (
  select case when f.is_internal then 'internal_function' else 'authority_function' end,
         f.function_identity,'PUBLIC'::text,'EXECUTE'::text,'PUBLIC'::text
  from authority_functions f
  where exists(select 1 from function_acl a where a.function_oid=f.function_oid and a.grantee=0)
    and not ('PUBLIC'=any((case when f.is_internal then (select internal_executors from policy) else (select function_executors from policy) end)::text[]))
), function_roles as (
  select distinct case when f.is_internal then 'internal_function' else 'authority_function' end,
         f.function_identity,r.rolname,'EXECUTE'::text,
         case when r.oid=a.grantee then 'direct' else 'inherited' end::text
  from authority_functions f
  join function_acl a on a.function_oid=f.function_oid and a.grantee<>0
  join pg_roles r on pg_has_role(r.oid,a.grantee,'USAGE')
  where r.oid<>f.proowner and not (r.rolname=any(((select owners from policy))::text[]))
    and not (r.rolname=any((case when f.is_internal then (select internal_executors from policy) else (select function_executors from policy) end)::text[]))
), default_targets as (
  select s.schema_oid,s.schema_name,r.oid nspowner,r.rolname owner_name,x.objtype,x.boundary,x.privilege
  from protected_schemas s cross join policy p
  cross join lateral unnest(p.owners) owner_name
  join pg_roles r on r.rolname=owner_name
  cross join (values('r'::"char",'default_table'::text,'ALL'::text),('S'::"char",'default_sequence','ALL'),('f'::"char",'default_function','EXECUTE')) x(objtype,boundary,privilege)
), default_entries as (
  -- PostgreSQL's built-in function default grants EXECUTE to PUBLIC even when
  -- no pg_default_acl row exists. Treat both that baseline and explicit catalog
  -- rows as owner-global policy; neither may be repaired schema-locally.
  select t.*,a.grantee,a.privilege_type,'global'::text default_scope
  from default_targets t
  cross join lateral aclexplode(coalesce(
    (select d.defaclacl from pg_default_acl d where d.defaclrole=t.nspowner and d.defaclnamespace=0 and d.defaclobjtype=t.objtype),
    acldefault(t.objtype,t.nspowner))) a
  union all
  select t.*,a.grantee,a.privilege_type,'schema'::text
  from default_targets t
  join pg_default_acl d on d.defaclrole=t.nspowner and d.defaclnamespace=t.schema_oid and d.defaclobjtype=t.objtype
  cross join lateral aclexplode(d.defaclacl) a
), default_public as (
  select case when d.default_scope='global' then 'global_'||d.boundary else d.boundary end,
         d.owner_name||' '||d.default_scope||' for '||d.schema_name,'PUBLIC'::text,d.privilege_type,'PUBLIC'::text
  from default_entries d where d.grantee=0
), default_roles as (
  select case when d.default_scope='global' then 'global_'||d.boundary else d.boundary end,
         d.owner_name||' '||d.default_scope||' for '||d.schema_name,r.rolname,d.privilege_type,'direct'::text
  from default_entries d join pg_roles r on r.oid=d.grantee where d.grantee<>d.nspowner
)
select * from schema_public
union all select * from schema_roles
union all select * from function_public
union all select * from function_roles
union all select * from default_public
union all select * from default_roles;
$$;

create or replace function remediate_perimeter_acl()
returns text
language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_mode text:=coalesce(nullif(current_setting('sovereign_memory.perimeter_acl_mode',true),''),'revoke');
  v_object record;v_acl record;v_allowed text[];v_owner text[]:=perimeter_policy_roles('owner');v_revoked integer:=0;
begin
  if v_mode not in ('revoke','fail') then raise exception 'PERIMETER FAIL: unknown sovereign_memory.perimeter_acl_mode %',v_mode; end if;
  if v_mode='fail' then return 'perimeter ACL policy is fail-only'; end if;

  -- The SECURITY DEFINER owner is the trusted control-table owner. Never derive
  -- a repair target from the durable policy row, which is precisely the object
  -- under review. Ownership drift must be handled by the owner-run migration,
  -- which validates shape/ACLs and refreshes the policy before calling here.
  for v_object in
    select c.relname,c.relowner from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relname=any(array['perimeter_acl_policy','perimeter_protected_schema_registry','perimeter_authority_function_registry'])
  loop
    if v_object.relowner<>current_user::regrole then
      raise exception 'PERIMETER FAIL: unsafe durable control-table owner for public.%: rerun the owner migration',v_object.relname;
    end if;
    for v_acl in
      select a.grantee,case when a.grantee=0 then 'PUBLIC' else r.rolname end grantee_name
      from pg_class c cross join lateral aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
      left join pg_roles r on r.oid=a.grantee
      where c.oid=format('public.%I',v_object.relname)::regclass and a.grantee<>c.relowner
    loop
      execute format('revoke all on table public.%I from %s',v_object.relname,
        case when v_acl.grantee=0 then 'PUBLIC' else format('%I',v_acl.grantee_name) end);
      v_revoked:=v_revoked+1;
    end loop;
    for v_acl in
      select att.attname,a.privilege_type,a.grantee,
             case when a.grantee=0 then 'PUBLIC' else r.rolname end grantee_name
      from pg_attribute att cross join lateral aclexplode(att.attacl) a
      left join pg_roles r on r.oid=a.grantee
      where att.attrelid=format('public.%I',v_object.relname)::regclass
        and att.attnum>0 and not att.attisdropped and att.attacl is not null
        and a.grantee<>v_object.relowner
    loop
      execute format('revoke %s (%I) on table public.%I from %s',v_acl.privilege_type,v_acl.attname,v_object.relname,
        case when v_acl.grantee=0 then 'PUBLIC' else format('%I',v_acl.grantee_name) end);
      v_revoked:=v_revoked+1;
    end loop;
  end loop;

  for v_object in select s.schema_oid,s.schema_name,n.nspowner from perimeter_protected_schemas() s join pg_namespace n on n.oid=s.schema_oid loop
    v_allowed:=perimeter_policy_roles('schema_create');
    for v_acl in
      select a.grantee,case when a.grantee=0 then 'PUBLIC' else r.rolname end grantee_name
      from aclexplode(coalesce((select nspacl from pg_namespace where oid=v_object.schema_oid),acldefault('n',v_object.nspowner))) a
      left join pg_roles r on r.oid=a.grantee
      where a.privilege_type='CREATE' and a.grantee<>v_object.nspowner
        and not (coalesce(r.rolname,'PUBLIC')=any(v_owner)) and not (coalesce(r.rolname,'PUBLIC')=any(v_allowed))
    loop
      execute format('revoke create on schema %I from %s',v_object.schema_name,case when v_acl.grantee=0 then 'PUBLIC' else format('%I',v_acl.grantee_name) end);
      v_revoked:=v_revoked+1;
    end loop;
  end loop;

  for v_object in select f.function_oid,f.function_identity,f.is_internal,p.proowner,p.proacl from perimeter_authority_functions() f join pg_proc p on p.oid=f.function_oid loop
    v_allowed:=case when v_object.is_internal then perimeter_policy_roles('internal_execute') else perimeter_policy_roles('function_execute') end;
    for v_acl in
      select a.grantee,case when a.grantee=0 then 'PUBLIC' else r.rolname end grantee_name
      from aclexplode(coalesce(v_object.proacl,acldefault('f',v_object.proowner))) a left join pg_roles r on r.oid=a.grantee
      where a.privilege_type='EXECUTE' and a.grantee<>v_object.proowner
        and not (coalesce(r.rolname,'PUBLIC')=any(v_owner)) and not (coalesce(r.rolname,'PUBLIC')=any(v_allowed))
    loop
      execute format('revoke execute on function %s from %s',v_object.function_identity,case when v_acl.grantee=0 then 'PUBLIC' else format('%I',v_acl.grantee_name) end);
      v_revoked:=v_revoked+1;
    end loop;
  end loop;

  -- Owner-global defaults apply to every schema owned by that role. This
  -- repository cannot safely mutate them; only schema-scoped defaults for an
  -- explicitly registered schema are remediated below.
  for v_object in
    select s.schema_name,r.oid nspowner,r.rolname owner_name,x.objtype,x.object_kind
    from perimeter_protected_schemas() s
    cross join lateral unnest(perimeter_policy_roles('owner')) owner_name
    join pg_roles r on r.rolname=owner_name
    cross join (values('r'::"char",'tables'::text),('S'::"char",'sequences'),('f'::"char",'functions')) x(objtype,object_kind)
  loop
    for v_acl in
      select a.grantee,case when a.grantee=0 then 'PUBLIC' else r.rolname end grantee_name
      from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a
      left join pg_roles r on r.oid=a.grantee
      where d.defaclrole=v_object.nspowner
        and d.defaclnamespace=(select oid from pg_namespace where nspname=v_object.schema_name)
        and d.defaclobjtype=v_object.objtype and a.grantee<>v_object.nspowner
    loop
      execute format('alter default privileges for role %I in schema %I revoke all on %s from %s',
        v_object.owner_name,v_object.schema_name,v_object.object_kind,
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
  v_bad text;v_item text;v_owner text[]:=perimeter_policy_roles('owner');
  v_tables text[]:=array['work_lessons','work_lesson_evidence','work_lesson_events','attention_events','attention_event_assignments'];
begin
  with control_tables as (
    select c.oid,c.relname,c.relowner,r.rolname owner_name
    from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_roles r on r.oid=c.relowner
    where n.nspname='public'
      and c.relname=any(array['perimeter_acl_policy','perimeter_protected_schema_registry','perimeter_authority_function_registry'])
  ), table_acl as (
    select c.oid,c.relname,c.relowner,a.grantee,a.privilege_type
    from control_tables c
    cross join lateral aclexplode(coalesce(
      (select relacl from pg_class where oid=c.oid),acldefault('r',c.relowner))) a
  ), column_acl as (
    select c.oid,c.relname,c.relowner,att.attname,a.grantee,a.privilege_type
    from control_tables c
    join pg_attribute att on att.attrelid=c.oid and att.attnum>0
      and not att.attisdropped and att.attacl is not null
    cross join lateral aclexplode(att.attacl) a
  ), violations as (
    select 'public.'||relname object_identity,owner_name grantee,
           'OWNER'::text privilege_type,'owner'::text privilege_source
    from control_tables where relowner<>current_user::regrole
    union all
    select 'public.'||a.relname,'PUBLIC',a.privilege_type,'PUBLIC'
    from table_acl a where a.grantee=0
    union all
    select distinct 'public.'||a.relname,r.rolname,a.privilege_type,
           case when r.oid=a.grantee then 'direct' else 'inherited' end
    from table_acl a
    join pg_roles r on a.grantee<>0 and pg_has_role(r.oid,a.grantee,'USAGE')
    where a.grantee<>a.relowner and r.oid<>a.relowner
      and not (r.rolname like 'pg\_%' escape '\' and not r.rolcanlogin)
    union all
    select 'public.'||a.relname,'PUBLIC',
           a.privilege_type||'('||a.attname||')','PUBLIC'
    from column_acl a where a.grantee=0
    union all
    select distinct 'public.'||a.relname,r.rolname,
           a.privilege_type||'('||a.attname||')',
           case when r.oid=a.grantee then 'direct' else 'inherited' end
    from column_acl a
    join pg_roles r on a.grantee<>0 and pg_has_role(r.oid,a.grantee,'USAGE')
    where a.grantee<>a.relowner and r.oid<>a.relowner
      and not (r.rolname like 'pg\_%' escape '\' and not r.rolcanlogin)
  )
  select string_agg(format('durable_control_table %s %s %s via %s',grantee,privilege_type,object_identity,privilege_source),', ' order by object_identity,grantee,privilege_type,privilege_source)
    into v_bad from violations;
  if v_bad is not null then
    raise exception 'PERIMETER FAIL: durable control-table ownership/effective ACL drift: %',v_bad;
  end if;

  select string_agg(format('%s %s %s %s via %s',boundary,grantee,privilege_type,object_identity,privilege_source),', ' order by boundary,object_identity,grantee)
    into v_bad from perimeter_acl_violations() where boundary like 'global_default_%';
  if v_bad is not null then
    raise exception 'PERIMETER FAIL: owner-global default ACLs: operator action required (global grants cannot be negated schema-locally): %',v_bad;
  end if;

  select string_agg(format('%s %s %s %s via %s',boundary,grantee,privilege_type,object_identity,privilege_source),', ' order by boundary,object_identity,grantee)
    into v_bad from perimeter_acl_violations() where boundary not like 'global_default_%';
  if v_bad is not null then raise exception 'PERIMETER FAIL: unexpected effective ACL grantees: %',v_bad; end if;

  select string_agg(format('%s owner=%s',s.schema_name,r.rolname),', ' order by s.schema_name) into v_bad
  from perimeter_protected_schemas() s join pg_namespace n on n.oid=s.schema_oid join pg_roles r on r.oid=n.nspowner
  where not (r.rolname=any(v_owner));
  if v_bad is not null then raise exception 'PERIMETER FAIL: unexpected protected-schema owner: %',v_bad; end if;

  select string_agg(c.relname,', ' order by c.relname) into v_bad from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname=any(v_tables) and(not c.relrowsecurity or not c.relforcerowsecurity);
  if v_bad is not null then raise exception 'PERIMETER FAIL: protected tables lack RLS/FORCE RLS: %',v_bad; end if;

  select string_agg(c.relname||' owner='||r.rolname,', ' order by c.relname) into v_bad
  from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_roles r on r.oid=c.relowner
  where n.nspname='public' and c.relname=any(v_tables) and not (r.rolname=any(v_owner));
  if v_bad is not null then raise exception 'PERIMETER FAIL: unexpected protected-table owner: %',v_bad; end if;

  select string_agg(f.function_identity||' owner='||r.rolname,', ' order by f.function_identity) into v_bad
  from perimeter_authority_functions() f join pg_proc p on p.oid=f.function_oid join pg_roles r on r.oid=p.proowner
  where not (r.rolname=any(v_owner));
  if v_bad is not null then raise exception 'PERIMETER FAIL: unexpected authority-function owner: %',v_bad; end if;

  with authority_paths as (
    select f.function_identity,
           replace(trim(both '"' from btrim(path_item)),'""','"') schema_name
    from perimeter_authority_functions() f
    join pg_proc p on p.oid=f.function_oid
    cross join lateral unnest(p.proconfig) setting
    cross join lateral regexp_split_to_table(
      substring(setting from char_length('search_path=')+1),E'\\s*,\\s*') path_item
    where setting like 'search_path=%'
  )
  select string_agg(function_identity||' path_schema='||schema_name,', '
                    order by function_identity,schema_name)
    into v_bad
  from authority_paths p
  where p.schema_name<>''
    and lower(p.schema_name)<>'information_schema'
    and lower(p.schema_name) not like 'pg\_%' escape '\'
    and p.schema_name<>'$user'
    and (to_regnamespace(p.schema_name) is null or not exists(
      select 1 from perimeter_protected_schema_registry r
      where r.schema_name=p.schema_name
    ));
  if v_bad is not null then
    raise exception 'PERIMETER FAIL: registered authority-function search-path schema is missing or not explicitly protected: %',v_bad;
  end if;

  select string_agg(grantee||':'||table_name||':'||privilege_type,', ' order by grantee,table_name,privilege_type) into v_bad
  from information_schema.role_table_grants where table_schema='public' and table_name=any(v_tables)
    and grantee<>all(v_owner) and grantee<>'service_role';
  if v_bad is not null then raise exception 'PERIMETER FAIL: stale protected-table grantees: %',v_bad; end if;

  if exists(select 1 from pg_roles where rolname='service_role') then
    foreach v_item in array v_tables loop
      if has_table_privilege('service_role',format('public.%I',v_item),'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
        raise exception 'PERIMETER FAIL: service_role has direct mutation on %',v_item;
      end if;
    end loop;
    if exists(select 1 from pg_roles where rolname='pg_write_all_data') and pg_has_role('service_role','pg_write_all_data','MEMBER') then
      raise exception 'PERIMETER FAIL: service_role inherits pg_write_all_data';
    end if;
  end if;

  select string_agg(f.function_identity,', ' order by f.function_identity) into v_bad
  from perimeter_authority_functions() f join pg_proc p on p.oid=f.function_oid
  where p.prosecdef and(p.proconfig is null or not exists(select 1 from unnest(p.proconfig) x where x like 'search_path=%')
    or exists(select 1 from unnest(p.proconfig) x where x like 'search_path=%' and(x ilike '%pg_temp%' or x ilike '%$user%')));
  if v_bad is not null then raise exception 'PERIMETER FAIL: unsafe or missing function search_path: %',v_bad; end if;

  return 'perimeter OK: bounded schema/function/default ACLs, owners, RLS/FORCE, runtime mutation, inheritance, PUBLIC and SECURITY DEFINER search paths verified';
end;
$$;

do $$
declare v_mode text:=coalesce(nullif(current_setting('sovereign_memory.perimeter_acl_mode',true),''),'revoke');r text;
begin
  if v_mode not in ('revoke','fail') then raise exception 'PERIMETER FAIL: unknown sovereign_memory.perimeter_acl_mode %',v_mode; end if;
  if v_mode='revoke' then
    revoke all on perimeter_acl_policy from public;
    revoke all on perimeter_protected_schema_registry from public;
    revoke all on perimeter_authority_function_registry from public;
    foreach r in array array['anon','authenticated','service_role'] loop
      if exists(select 1 from pg_roles where rolname=r) then
        execute format('revoke all on perimeter_acl_policy,perimeter_protected_schema_registry,perimeter_authority_function_registry from %I',r);
      end if;
    end loop;
    revoke all on function perimeter_setting_roles(text) from public;
    revoke all on function perimeter_policy_roles(text) from public;
    revoke all on function perimeter_protected_schemas() from public;
    revoke all on function perimeter_authority_functions() from public;
    revoke all on function perimeter_acl_violations() from public;
    revoke all on function remediate_perimeter_acl() from public;
    revoke all on function assert_perimeter_closed() from public;
    perform remediate_perimeter_acl();
  end if;
end $$;

do $$
declare v_mode text:=coalesce(nullif(current_setting('sovereign_memory.perimeter_acl_mode',true),''),'revoke');
begin
  if v_mode='revoke' and exists(select 1 from pg_roles where rolname='service_role') then
    if (select profile='supabase' from perimeter_acl_policy where singleton) then
      grant execute on function assert_perimeter_closed() to service_role;
    else
      revoke execute on function assert_perimeter_closed() from service_role;
    end if;
  end if;
end $$;

select assert_perimeter_closed();
