-- Blocking-review regressions for issue #56. All fixtures roll back.
begin;

create role smc_unrelated_grantee nologin;
create schema smc_unrelated authorization current_user;
create function smc_unrelated.unrelated_writer()
returns void language sql security definer set search_path=smc_unrelated
as $$ select null::void $$;
grant execute on function smc_unrelated.unrelated_writer() to smc_unrelated_grantee;
alter default privileges in schema smc_unrelated
  grant execute on functions to smc_unrelated_grantee;

-- Repository perimeter inventory must not absorb unrelated SECURITY DEFINER
-- functions, their search paths, or their owner-scoped defaults.
select public.assert_perimeter_closed();
select public.remediate_perimeter_acl();
do $$
begin
  if not has_function_privilege('smc_unrelated_grantee',
       'smc_unrelated.unrelated_writer()','EXECUTE') then
    raise exception 'perimeter remediation touched an unrelated SECURITY DEFINER function';
  end if;
  if not exists(
    select 1
    from pg_default_acl d
    join pg_namespace n on n.oid=d.defaclnamespace
    cross join lateral aclexplode(d.defaclacl) a
    join pg_roles r on r.oid=a.grantee
    where n.nspname='smc_unrelated' and d.defaclobjtype='f'
      and r.rolname='smc_unrelated_grantee' and a.privilege_type='EXECUTE'
  ) then
    raise exception 'perimeter remediation touched unrelated owner defaults';
  end if;
end $$;

-- A registered authority function closes over every non-system schema in its
-- fixed search path. The schema must be explicitly registered before its CREATE
-- ACL can be repaired; unrelated SECURITY DEFINER paths remain out of scope.
create role smc_registered_path_stale nologin;
create schema smc_registered_path authorization current_user;
create function smc_registered_path.registered_path_writer()
returns void language sql security definer
set search_path=pg_catalog,smc_registered_path
as $$ select null::void $$;
insert into public.perimeter_authority_function_registry(function_identity,is_internal)
values('smc_registered_path.registered_path_writer()',false);
grant create on schema smc_registered_path to smc_registered_path_stale;
grant create on schema smc_unrelated to smc_registered_path_stale;
do $$
begin
  begin
    perform public.assert_perimeter_closed();
  exception when others then
    if sqlstate='P0001' and sqlerrm like '%registered authority-function search-path schema%'
       and sqlerrm like '%smc_registered_path%' then return; end if;
    raise exception 'unregistered authority path failure lacked schema evidence: %',sqlerrm;
  end;
  raise exception 'perimeter accepted an unregistered authority-function path schema';
end $$;
insert into public.perimeter_protected_schema_registry(schema_name)
values('smc_registered_path');
do $$
begin
  begin
    perform public.assert_perimeter_closed();
  exception when others then
    if sqlstate='P0001' and sqlerrm like '%unexpected effective ACL grantees%'
       and sqlerrm like '%smc_registered_path_stale%'
       and sqlerrm like '%smc_registered_path%' then return; end if;
    raise exception 'registered authority path ACL failure lacked exact evidence: %',sqlerrm;
  end;
  raise exception 'perimeter accepted CREATE on a registered authority path schema';
end $$;
select public.remediate_perimeter_acl();
select public.assert_perimeter_closed();
do $$
begin
  if has_schema_privilege('smc_registered_path_stale','smc_registered_path','CREATE') then
    raise exception 'registered authority path CREATE survived remediation';
  end if;
  if not has_schema_privilege('smc_registered_path_stale','smc_unrelated','CREATE') then
    raise exception 'registered authority path remediation touched an unrelated schema';
  end if;
end $$;

create role smc_secondary_stale nologin;
create schema smc_secondary authorization current_user;
insert into public.perimeter_protected_schema_registry(schema_name)
values('smc_secondary');
create function smc_secondary.registered_writer()
returns void language sql security definer set search_path=smc_secondary
as $$ select null::void $$;
insert into public.perimeter_authority_function_registry(function_identity,is_internal)
values('smc_secondary.registered_writer()',false);
grant create on schema smc_secondary to smc_secondary_stale;
grant execute on function smc_secondary.registered_writer() to smc_secondary_stale;
alter default privileges in schema smc_secondary
  grant execute on functions to smc_secondary_stale;
alter default privileges in schema smc_secondary
  grant select on tables to smc_secondary_stale;
alter default privileges in schema smc_secondary
  grant usage on sequences to smc_secondary_stale;

-- A second explicitly protected schema is fully audited, including defaults.
do $$
begin
  begin
    perform public.assert_perimeter_closed();
  exception when others then
    if sqlstate='P0001' and sqlerrm like '%smc_secondary_stale%'
       and sqlerrm like '%default_function%' then return; end if;
    raise exception 'secondary-schema failure lacked default ACL evidence: %',sqlerrm;
  end;
  raise exception 'perimeter accepted drift in a registered protected schema';
end $$;
select public.remediate_perimeter_acl();
select public.assert_perimeter_closed();

do $$
begin
  if has_schema_privilege('smc_secondary_stale','smc_secondary','CREATE')
     or has_function_privilege('smc_secondary_stale',
          'smc_secondary.registered_writer()','EXECUTE') then
    raise exception 'secondary-schema current ACL drift survived remediation';
  end if;
end $$;
create function smc_secondary.future_writer()
returns void language sql security definer set search_path=smc_secondary
as $$ select null::void $$;
create table smc_secondary.future_table(id bigint);
create sequence smc_secondary.future_sequence;
do $$
begin
  if has_function_privilege('smc_secondary_stale',
       'smc_secondary.future_writer()','EXECUTE')
     or has_table_privilege('smc_secondary_stale',
       'smc_secondary.future_table','SELECT')
     or has_sequence_privilege('smc_secondary_stale',
       'smc_secondary.future_sequence','USAGE') then
    raise exception 'remediated owner defaults leaked authority to a future object';
  end if;
end $$;

-- ACL evidence is source-preserving. A leaf with its own grant and authority
-- inherited from a granted parent produces both rows, while one PUBLIC ACL
-- produces exactly one pseudo-grantee row and never fans out across roles.
create role smc_acl_source_parent nologin;
create role smc_acl_source_leaf nologin;
grant smc_acl_source_parent to smc_acl_source_leaf;
create schema smc_acl_source authorization current_user;
insert into public.perimeter_protected_schema_registry(schema_name)
values('smc_acl_source');
create function smc_acl_source.registered_writer()
returns void language sql security definer
set search_path=pg_catalog,smc_acl_source
as $$ select null::void $$;
insert into public.perimeter_authority_function_registry(function_identity,is_internal)
values('smc_acl_source.registered_writer()',false);
grant create on schema smc_acl_source to smc_acl_source_parent,smc_acl_source_leaf;
grant create on schema smc_acl_source to public;
grant execute on function smc_acl_source.registered_writer()
  to smc_acl_source_parent,smc_acl_source_leaf;
grant execute on function smc_acl_source.registered_writer() to public;
do $$
begin
  if (select count(*) from public.perimeter_acl_violations()
      where boundary='schema' and object_identity='smc_acl_source'
        and grantee='smc_acl_source_leaf' and privilege_type='CREATE'
        and privilege_source='direct')<>1
     or (select count(*) from public.perimeter_acl_violations()
         where boundary='schema' and object_identity='smc_acl_source'
           and grantee='smc_acl_source_leaf' and privilege_type='CREATE'
           and privilege_source='inherited')<>1 then
    raise exception 'schema ACL evidence did not preserve simultaneous direct and inherited sources';
  end if;
  if (select count(*) from public.perimeter_acl_violations()
      where boundary='authority_function'
        and object_identity='smc_acl_source.registered_writer()'
        and grantee='smc_acl_source_leaf' and privilege_type='EXECUTE'
        and privilege_source='direct')<>1
     or (select count(*) from public.perimeter_acl_violations()
         where boundary='authority_function'
           and object_identity='smc_acl_source.registered_writer()'
           and grantee='smc_acl_source_leaf' and privilege_type='EXECUTE'
           and privilege_source='inherited')<>1 then
    raise exception 'function ACL evidence did not preserve simultaneous direct and inherited sources';
  end if;
  if (select count(*) from public.perimeter_acl_violations()
      where boundary='schema' and object_identity='smc_acl_source'
        and grantee='PUBLIC' and privilege_type='CREATE'
        and privilege_source='PUBLIC')<>1
     or exists(select 1 from public.perimeter_acl_violations()
         where boundary='schema' and object_identity='smc_acl_source'
           and grantee<>'PUBLIC' and privilege_source='PUBLIC') then
    raise exception 'one schema PUBLIC ACL did not produce exactly one pseudo-grantee source';
  end if;
  if (select count(*) from public.perimeter_acl_violations()
      where boundary='authority_function'
        and object_identity='smc_acl_source.registered_writer()'
        and grantee='PUBLIC' and privilege_type='EXECUTE'
        and privilege_source='PUBLIC')<>1
     or exists(select 1 from public.perimeter_acl_violations()
         where boundary='authority_function'
           and object_identity='smc_acl_source.registered_writer()'
           and grantee<>'PUBLIC' and privilege_source='PUBLIC') then
    raise exception 'one function PUBLIC ACL did not produce exactly one pseudo-grantee source';
  end if;
end $$;
select public.remediate_perimeter_acl();
select public.assert_perimeter_closed();

-- Runtime callers cannot turn custom GUCs into assertion allowlists.
grant create on schema public to service_role;
grant execute on function public.capture_memory_attention_after_insert() to service_role;
set local role service_role;
select set_config('sovereign_memory.perimeter_allowed_schema_create_roles','service_role',true);
select set_config('sovereign_memory.perimeter_allowed_internal_execute_roles','service_role',true);
do $$
begin
  begin
    perform public.assert_perimeter_closed();
  exception when others then
    if sqlstate='P0001' and sqlerrm like '%service_role%' then return; end if;
    raise exception 'spoof-resistant assertion lacked service_role evidence: %',sqlerrm;
  end;
  raise exception 'service_role spoofed perimeter policy with session GUCs';
end $$;
reset role;
select public.remediate_perimeter_acl();
select public.assert_perimeter_closed();

-- The durable policy source itself is not writable by the runtime caller.
set local role service_role;
do $$
begin
  begin
    update public.perimeter_acl_policy set schema_create_roles=array['service_role'];
  exception when insufficient_privilege then return; end;
  raise exception 'service_role could rewrite durable perimeter policy';
end $$;
reset role;

-- All three durable control tables are owner and effective-ACL boundaries.
-- Fail mode preserves drift; revoke mode establishes the migration owner and
-- removes arbitrary direct grants, including grants inherited by another role.
create role smc_policy_attacker nologin;
create role smc_policy_parent nologin;
create role smc_policy_leaf nologin;
grant smc_policy_parent to smc_policy_leaf;
alter table public.perimeter_acl_policy owner to smc_policy_attacker;
grant update on public.perimeter_acl_policy,
  public.perimeter_protected_schema_registry to smc_policy_parent;
grant update(function_identity) on public.perimeter_authority_function_registry
  to smc_policy_parent;
select set_config('sovereign_memory.perimeter_acl_mode','fail',true);
do $$
begin
  if public.remediate_perimeter_acl()<>'perimeter ACL policy is fail-only' then
    raise exception 'unexpected fail-only policy-table remediation result';
  end if;
  if (select r.rolname from pg_class c join pg_roles r on r.oid=c.relowner
      where c.oid='public.perimeter_acl_policy'::regclass)<>'smc_policy_attacker'
     or not has_column_privilege('smc_policy_leaf',
          'public.perimeter_authority_function_registry','function_identity','UPDATE') then
    raise exception 'fail-only mode changed durable-table owner or inherited ACL drift';
  end if;
  begin
    perform public.assert_perimeter_closed();
  exception when others then
    if sqlstate='P0001' and sqlerrm like '%durable_control_table%'
       and sqlerrm like '%smc_policy_attacker%'
       and sqlerrm like '%smc_policy_parent%UPDATE%via direct%'
       and sqlerrm like '%smc_policy_leaf%UPDATE%via inherited%' then return; end if;
    raise exception 'durable-table failure lacked owner/effective-ACL evidence: %',sqlerrm;
  end;
  raise exception 'perimeter accepted attacker-owned durable policy state';
end $$;
select set_config('sovereign_memory.perimeter_acl_mode','revoke',true);
-- Standalone remediation refuses to trust an attacker-owned policy table; only
-- the owner-run migration may establish ownership before refreshing the row.
do $$
begin
  begin
    perform public.remediate_perimeter_acl();
  exception when others then
    if sqlstate='P0001' and sqlerrm like '%unsafe durable control-table owner%' then return; end if;
    raise exception 'unsafe standalone owner repair lacked evidence: %',sqlerrm;
  end;
  raise exception 'standalone remediation trusted an attacker-owned policy table';
end $$;
alter table public.perimeter_acl_policy owner to current_user;
select public.remediate_perimeter_acl();
select public.assert_perimeter_closed();
do $$
begin
  if exists(
    select 1 from pg_class c join pg_roles r on r.oid=c.relowner
    where c.oid=any(array[
      'public.perimeter_acl_policy'::regclass,
      'public.perimeter_protected_schema_registry'::regclass,
      'public.perimeter_authority_function_registry'::regclass])
      and r.rolname<>current_user
  ) or has_table_privilege('smc_policy_leaf',
       'public.perimeter_acl_policy','UPDATE')
     or has_table_privilege('smc_policy_leaf',
       'public.perimeter_protected_schema_registry','UPDATE')
     or has_table_privilege('smc_policy_leaf',
       'public.perimeter_authority_function_registry','UPDATE') then
    raise exception 'revoke mode did not close durable control-table ownership/ACLs';
  end if;
end $$;

-- A column-only grant is not visible through has_table_privilege(). It must be
-- audited effectively through membership and revoked at its direct source.
grant update(function_identity) on public.perimeter_authority_function_registry
  to smc_policy_parent;
do $$
begin
  begin
    perform public.assert_perimeter_closed();
  exception when others then
    if sqlstate='P0001' and sqlerrm like '%durable_control_table%'
       and sqlerrm like '%smc_policy_parent%UPDATE(function_identity)%via direct%'
       and sqlerrm like '%smc_policy_leaf%UPDATE(function_identity)%via inherited%' then return; end if;
    raise exception 'column-ACL failure lacked inherited column evidence: %',sqlerrm;
  end;
  raise exception 'perimeter accepted inherited column-only control-table authority';
end $$;
select public.remediate_perimeter_acl();
select public.assert_perimeter_closed();
do $$
begin
  if has_column_privilege('smc_policy_leaf',
       'public.perimeter_authority_function_registry','function_identity','UPDATE') then
    raise exception 'column-only control-table authority survived remediation';
  end if;
end $$;

-- PUBLIC table and column ACLs are reported once as explicit pseudo-grantee
-- evidence, rather than being ambiguously attributed to every effective role.
grant select on public.perimeter_acl_policy to public;
grant update(function_identity) on public.perimeter_authority_function_registry to public;
do $$
begin
  begin
    perform public.assert_perimeter_closed();
  exception when others then
    if sqlstate='P0001'
       and sqlerrm like '%durable_control_table PUBLIC SELECT public.perimeter_acl_policy via PUBLIC%'
       and sqlerrm like '%durable_control_table PUBLIC UPDATE(function_identity) public.perimeter_authority_function_registry via PUBLIC%' then return; end if;
    raise exception 'PUBLIC control-table failure lacked exact table/column evidence: %',sqlerrm;
  end;
  raise exception 'perimeter accepted PUBLIC control-table authority';
end $$;
select public.remediate_perimeter_acl();
select public.assert_perimeter_closed();

-- Global defaults are owner-wide and therefore outside schema-local repair.
-- Both policy modes must preserve and report them for explicit operator action.
alter default privileges for role current_user grant select on tables to smc_secondary_stale;
select set_config('sovereign_memory.perimeter_acl_mode','fail',true);
select public.remediate_perimeter_acl();
do $$
begin
  begin
    perform public.assert_perimeter_closed();
  exception when others then
    if sqlstate='P0001' and sqlerrm like '%global_default_table%'
       and sqlerrm like '%operator action required%'
       and sqlerrm like '%smc_secondary_stale%' then return; end if;
    raise exception 'global-default fail-mode evidence was not actionable: %',sqlerrm;
  end;
  raise exception 'fail mode accepted an owner-global default grant';
end $$;
select set_config('sovereign_memory.perimeter_acl_mode','revoke',true);
select public.remediate_perimeter_acl();
do $$
begin
  if not exists(
    select 1 from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a
    where d.defaclrole=current_user::regrole and d.defaclnamespace=0
      and d.defaclobjtype='r' and a.grantee='smc_secondary_stale'::regrole
      and a.privilege_type='SELECT'
  ) then
    raise exception 'revoke mode silently changed an owner-global default';
  end if;
  begin
    perform public.assert_perimeter_closed();
  exception when others then
    if sqlstate='P0001' and sqlerrm like '%global_default_table%'
       and sqlerrm like '%operator action required%' then return; end if;
    raise exception 'global-default revoke-mode evidence was not actionable: %',sqlerrm;
  end;
  raise exception 'revoke mode accepted an owner-global default grant';
end $$;
alter default privileges for role current_user revoke select on tables from smc_secondary_stale;

-- Defaults owned by an unrelated role are not part of this repository boundary.
create role smc_unrelated_default_owner nologin;
alter default privileges for role smc_unrelated_default_owner
  grant select on tables to smc_unrelated_grantee;
select set_config('sovereign_memory.perimeter_acl_mode','fail',true);
select public.remediate_perimeter_acl();
select set_config('sovereign_memory.perimeter_acl_mode','revoke',true);
select public.remediate_perimeter_acl();
do $$
begin
  if not exists(
    select 1 from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a
    where d.defaclrole='smc_unrelated_default_owner'::regrole
      and d.defaclnamespace=0 and d.defaclobjtype='r'
      and a.grantee='smc_unrelated_grantee'::regrole
      and a.privilege_type='SELECT'
  ) then
    raise exception 'perimeter policy changed an unrelated global default';
  end if;
end $$;
select public.assert_perimeter_closed();

rollback;
select 'blocking-review perimeter regressions passed' as result;
