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
       and sqlerrm like '%smc_policy_leaf%' then return; end if;
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
       and sqlerrm like '%smc_policy_leaf%'
       and sqlerrm like '%UPDATE(function_identity)%' then return; end if;
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
