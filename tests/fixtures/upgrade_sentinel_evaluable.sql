-- Preserved upgrade sentinels stay in the perimeter registries. Slot 11
-- evaluability reports an unresolved protected schema or authority function
-- as an unsupported population, so the preserved names have to resolve
-- before that migration's post-install assert. The registry rows themselves
-- are not rewritten.
--
-- The function identity is the unqualified smc_upgrade_sentinel(). Evaluability
-- resolves it with search_path pg_catalog, pg_temp, so the function lives in
-- pg_catalog. The schema sentinel is a normal namespace.
create schema if not exists smc_upgrade_sentinel;
revoke all on schema smc_upgrade_sentinel from public;

create or replace function pg_catalog.smc_upgrade_sentinel()
returns void
language sql
as 'select null';

revoke all on function pg_catalog.smc_upgrade_sentinel() from public;

do $$
declare r text;
begin
  foreach r in array array['anon','authenticated','service_role'] loop
    if exists(select 1 from pg_roles where rolname=r) then
      execute format('revoke all on schema smc_upgrade_sentinel from %I',r);
      execute format('revoke all on function pg_catalog.smc_upgrade_sentinel() from %I',r);
    end if;
  end loop;
end $$;
