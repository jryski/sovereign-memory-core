-- C1 perimeter evaluability contract.
-- Runs only on disposable CI databases. Everything is rolled back.

begin;

do $$
declare
  r jsonb;
begin
  r := public.perimeter_report();

  if r->>'contract_version'<>'perimeter-report/1' then
    raise exception 'unexpected perimeter report contract: %',r;
  end if;
  if r->>'evaluation_status'<>'evaluated'
     or r->>'perimeter_state'<>'clean'
     or (r->>'violation_count')::integer<>0 then
    raise exception 'clean fixture did not report evaluated/clean/zero: %',r;
  end if;
  if coalesce((r->'coverage'->>'complete')::boolean,false) is not true
     or (r->'coverage'->>'gap_count')::integer<>0 then
    raise exception 'clean fixture coverage is incomplete: %',r;
  end if;
end $$;

select public.assert_perimeter_closed();

-- Deliberate privilege drift must remain fully evaluable and report not-clean,
-- with nonzero findings and structured ACL detail.
create role smc_c1_unexpected_grantee nologin;
grant create on schema public to smc_c1_unexpected_grantee;

do $$
declare
  r jsonb;
begin
  r := public.perimeter_report();

  if r->>'evaluation_status'<>'evaluated'
     or r->>'perimeter_state'<>'not_clean'
     or coalesce((r->>'violation_count')::integer,0)<1 then
    raise exception 'deliberate violation was not reported as evaluated/not-clean: %',r;
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(r->'findings') f
    where f->>'kind'='acl'
      and f->>'boundary'='schema'
      and f->>'grantee'='smc_c1_unexpected_grantee'
      and f->>'privilege_type'='CREATE'
  ) then
    raise exception 'structured ACL finding was lost: %',r;
  end if;

  begin
    perform public.assert_perimeter_closed();
  exception
    when sqlstate 'P0001' then
      if sqlerrm like 'PERIMETER FAIL:%' then
        return;
      end if;
      raise;
  end;

  raise exception 'assertion gate accepted deliberate privilege drift';
end $$;

revoke create on schema public from smc_c1_unexpected_grantee;
drop role smc_c1_unexpected_grantee;

-- A required role named by the persisted perimeter policy but absent from the
-- target makes the evaluation population incomplete. This is the provider-exit
-- case that must never collapse to violation_count=0.
update public.perimeter_acl_policy
set function_execute_roles =
  array_append(function_execute_roles,'smc_c1_intentionally_missing_role')
where singleton;

do $$
declare
  r jsonb;
begin
  r := public.perimeter_report();

  if r->>'evaluation_status'<>'unsupported'
     or r->>'perimeter_state'<>'unknown'
     or r->>'violation_count' is not null
     or r->'violation_count'<>'null'::jsonb then
    raise exception 'unevaluable fixture did not fail closed with NULL violation count: %',r;
  end if;

  if coalesce((r->'coverage'->>'complete')::boolean,true) is not false
     or (r->'coverage'->>'gap_count')::integer<1 then
    raise exception 'unevaluable fixture did not expose incomplete coverage: %',r;
  end if;

  if not exists(
    select 1
    from jsonb_array_elements(r->'coverage'->'gaps') g
    where g->>'kind'='missing_policy_roles'
      and (g->'items') ? 'smc_c1_intentionally_missing_role'
  ) then
    raise exception 'missing-role coverage gap was not reported: %',r;
  end if;

  if jsonb_array_length(r->'findings')<>0 then
    raise exception 'UNSUPPORTED was fabricated into a violation finding: %',r;
  end if;

  begin
    perform public.assert_perimeter_closed();
  exception
    when sqlstate 'P0001' then
      if sqlerrm like 'PERIMETER UNSUPPORTED:%' then
        return;
      end if;
      raise;
  end;

  raise exception 'assertion gate treated an unevaluable target as clean';
end $$;

rollback;
