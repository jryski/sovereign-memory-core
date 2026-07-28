-- ============================================================================
-- SOVEREIGN MEMORY :: PERIMETER REFRESH
-- Target: PostgreSQL 15+ / Supabase.
--
-- Run after every optional public-schema layer. PostgreSQL grants EXECUTE on new
-- functions to PUBLIC by default, so the core perimeter closure must be repeated
-- after later SQL packages are installed.
-- ============================================================================

revoke all on all tables in schema public from public;
revoke all on all sequences in schema public from public;
revoke execute on all functions in schema public from public;

do $$
begin
  if exists(select 1 from pg_roles where rolname='anon') then
    execute 'revoke all on all tables in schema public from anon';
    execute 'revoke all on all sequences in schema public from anon';
    execute 'revoke execute on all functions in schema public from anon';
  end if;
  if exists(select 1 from pg_roles where rolname='authenticated') then
    execute 'revoke all on all tables in schema public from authenticated';
    execute 'revoke all on all sequences in schema public from authenticated';
    execute 'revoke execute on all functions in schema public from authenticated';
  end if;
end $$;

alter default privileges in schema public revoke all on tables from public;
alter default privileges in schema public revoke all on sequences from public;
alter default privileges in schema public revoke execute on functions from public;

do $$
begin
  if exists(select 1 from pg_roles where rolname='anon') then
    execute 'alter default privileges in schema public revoke all on tables from anon';
    execute 'alter default privileges in schema public revoke all on sequences from anon';
    execute 'alter default privileges in schema public revoke execute on functions from anon';
  end if;
  if exists(select 1 from pg_roles where rolname='authenticated') then
    execute 'alter default privileges in schema public revoke all on tables from authenticated';
    execute 'alter default privileges in schema public revoke all on sequences from authenticated';
    execute 'alter default privileges in schema public revoke execute on functions from authenticated';
  end if;
end $$;

select assert_perimeter_closed();
