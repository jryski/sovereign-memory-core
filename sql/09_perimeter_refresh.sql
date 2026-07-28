-- ============================================================================
-- SOVEREIGN MEMORY :: FINAL PERIMETER CLOSURE V3
-- Run after every optional public-schema layer.
-- ============================================================================

revoke create on schema public from public;
do $$ begin
  if exists(select 1 from pg_namespace where nspname='extensions') then
    revoke create on schema extensions from public;
  end if;
end $$;

revoke all on all tables in schema public from public;
revoke all on all sequences in schema public from public;
revoke execute on all functions in schema public from public;

do $$
declare r text;
begin
  foreach r in array array['anon','authenticated'] loop
    if exists(select 1 from pg_roles where rolname=r) then
      execute format('revoke create on schema public from %I',r);
      if exists(select 1 from pg_namespace where nspname='extensions') then
        execute format('revoke create on schema extensions from %I',r);
      end if;
      execute format('revoke all on all tables in schema public from %I',r);
      execute format('revoke all on all sequences in schema public from %I',r);
      execute format('revoke execute on all functions in schema public from %I',r);
    end if;
  end loop;
  if exists(select 1 from pg_roles where rolname='service_role') then
    revoke create on schema public from service_role;
    if exists(select 1 from pg_namespace where nspname='extensions') then
      revoke create on schema extensions from service_role;
    end if;
    revoke all on function capture_memory_attention_after_insert() from service_role;
    revoke all on function capture_memory_activation_after_update() from service_role;
    revoke all on function attention_fixed_point_chars(integer) from service_role;
    revoke all on function attention_set_rendered_chars(jsonb) from service_role;
  end if;
end $$;

alter default privileges in schema public revoke all on tables from public;
alter default privileges in schema public revoke all on sequences from public;
alter default privileges in schema public revoke execute on functions from public;
do $$
declare r text;
begin
  foreach r in array array['anon','authenticated'] loop
    if exists(select 1 from pg_roles where rolname=r) then
      execute format('alter default privileges in schema public revoke all on tables from %I',r);
      execute format('alter default privileges in schema public revoke all on sequences from %I',r);
      execute format('alter default privileges in schema public revoke execute on functions from %I',r);
    end if;
  end loop;
end $$;

create or replace function assert_perimeter_closed()
returns text
language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_role text;
  v_item text;
  v_bad text;
  v_owner text;
  v_tables text[]:=array[
    'work_lessons','work_lesson_evidence','work_lesson_events',
    'attention_events','attention_event_assignments'
  ];
  v_trigger_functions text[]:=array[
    'capture_memory_attention_after_insert()',
    'capture_memory_activation_after_update()',
    'guard_attention_append_only()',
    'validate_attention_event_revision_lineage()',
    'guard_work_lessons_write_path()',
    'guard_work_lesson_custody_write_path()'
  ];
  v_checked_functions text[]:=array[
    'record_native_memory_attention(uuid)',
    'record_native_memory_activation(uuid,text)',
    'capture_memory_attention_after_insert()',
    'capture_memory_activation_after_update()',
    'append_attention_event_revision(uuid,text,timestamp with time zone,text,text,jsonb)',
    'attention_boot_projection_v2(text,integer,integer)',
    'attention_set_rendered_chars(jsonb)',
    'propose_work_lesson(text,text,text,text,text,text,text,text,text)',
    'accept_work_lesson(uuid,text,text)',
    'reject_work_lesson(uuid,text,text)',
    'assert_perimeter_closed()'
  ];
begin
  select r.rolname into v_owner
  from pg_namespace n join pg_roles r on r.oid=n.nspowner
  where n.nspname='public';
  if v_owner not in ('postgres','pg_database_owner') then
    raise exception 'PERIMETER FAIL: unexpected public schema owner %',v_owner;
  end if;

  if exists(
    select 1
    from pg_namespace n
    cross join lateral aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a
    where n.nspname in ('public','extensions')
      and a.grantee=0 and a.privilege_type='CREATE'
  ) then raise exception 'PERIMETER FAIL: PUBLIC can CREATE in a SECURITY DEFINER search-path schema'; end if;

  foreach v_role in array array['anon','authenticated','service_role'] loop
    if exists(select 1 from pg_roles where rolname=v_role) then
      if has_schema_privilege(v_role,'public','CREATE') then
        raise exception 'PERIMETER FAIL: % can CREATE in public',v_role;
      end if;
      if exists(select 1 from pg_namespace where nspname='extensions')
         and has_schema_privilege(v_role,'extensions','CREATE') then
        raise exception 'PERIMETER FAIL: % can CREATE in extensions',v_role;
      end if;
    end if;
  end loop;

  select string_agg(c.relname,', ' order by c.relname) into v_bad
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relname=any(v_tables)
    and(not c.relrowsecurity or not c.relforcerowsecurity);
  if v_bad is not null then
    raise exception 'PERIMETER FAIL: protected tables lack RLS/FORCE RLS: %',v_bad;
  end if;

  select string_agg(c.relname||' owner='||r.rolname,', ' order by c.relname) into v_bad
  from pg_class c
  join pg_namespace n on n.oid=c.relnamespace
  join pg_roles r on r.oid=c.relowner
  where n.nspname='public' and c.relname=any(v_tables) and r.rolname<>'postgres';
  if v_bad is not null then
    raise exception 'PERIMETER FAIL: unexpected protected-table owner: %',v_bad;
  end if;

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

  select string_agg(grantee||':'||table_name||':'||privilege_type,', '
                    order by grantee,table_name,privilege_type) into v_bad
  from information_schema.role_table_grants
  where table_schema='public' and table_name=any(v_tables)
    and grantee not in ('postgres','service_role');
  if v_bad is not null then
    raise exception 'PERIMETER FAIL: stale protected-table grantees: %',v_bad;
  end if;

  foreach v_item in array v_trigger_functions loop
    if exists(
      select 1 from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
      where p.oid=('public.'||v_item)::regprocedure
        and a.grantee=0 and a.privilege_type='EXECUTE'
    ) then raise exception 'PERIMETER FAIL: PUBLIC can execute trigger-only function %',v_item; end if;
    foreach v_role in array array['anon','authenticated','service_role'] loop
      if exists(select 1 from pg_roles where rolname=v_role)
         and has_function_privilege(v_role,'public.'||v_item,'EXECUTE') then
        raise exception 'PERIMETER FAIL: % can execute trigger-only function %',v_role,v_item;
      end if;
    end loop;
  end loop;

  select string_agg(p.oid::regprocedure::text,', ' order by p.oid::regprocedure::text) into v_bad
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_roles r on r.oid=p.proowner
  where n.nspname='public' and p.oid::regprocedure::text=any(v_checked_functions)
    and r.rolname<>'postgres';
  if v_bad is not null then
    raise exception 'PERIMETER FAIL: unexpected function owner: %',v_bad;
  end if;

  select string_agg(p.oid::regprocedure::text,', ' order by p.oid::regprocedure::text) into v_bad
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.oid::regprocedure::text=any(v_checked_functions)
    and(
      p.proconfig is null
      or not exists(select 1 from unnest(p.proconfig) x where x like 'search_path=%')
      or exists(select 1 from unnest(p.proconfig) x
                where x like 'search_path=%' and(x ilike '%pg_temp%' or x ilike '%$user%'))
    );
  if v_bad is not null then
    raise exception 'PERIMETER FAIL: unsafe or missing function search_path: %',v_bad;
  end if;

  return 'perimeter OK: schema creation, owners, stale grants, RLS/FORCE, runtime mutation, role inheritance, trigger execution and SECURITY DEFINER search paths verified';
end;
$$;

revoke all on function assert_perimeter_closed() from public;
do $$ begin
  if exists(select 1 from pg_roles where rolname='service_role') then
    grant execute on function assert_perimeter_closed() to service_role;
  end if;
end $$;

select assert_perimeter_closed();
