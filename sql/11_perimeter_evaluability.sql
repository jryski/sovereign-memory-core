-- ============================================================================
-- SOVEREIGN MEMORY :: PERIMETER EVALUABILITY REPORT V1
-- Issue #58 C1 fix-forward migration. Run after 10_security_definer_hardening.sql.
--
-- Adds one sanctioned report seam that separates "clean" from "not evaluable".
-- The previous assertion body is retained as a private violation primitive;
-- public.assert_perimeter_closed() becomes a fail-closed wrapper over the report.
-- ============================================================================

begin;

-- Preserve the reviewed v10 assertion body exactly once as the internal
-- violation primitive. Reapplication is idempotent. Refuse to wrap a pre-v10
-- function whose SECURITY DEFINER search path has not crossed the hardening
-- boundary.
do $$
declare
  v_oid oid;
  v_path text;
begin
  v_oid := to_regprocedure('public.perimeter_assert_violations_v1()');
  if v_oid is null then
    v_oid := to_regprocedure('public.assert_perimeter_closed()');
    if v_oid is null then
      raise exception 'PERIMETER C1 FAIL: public.assert_perimeter_closed() is missing; apply migrations through 10 first';
    end if;

    select cfg into v_path
    from pg_proc p
    left join lateral (
      select x cfg from unnest(p.proconfig) x where x like 'search_path=%'
    ) s on true
    where p.oid=v_oid;

    if v_path is distinct from 'search_path=pg_catalog, pg_temp'
       or not (select prosecdef from pg_proc where oid=v_oid) then
      raise exception 'PERIMETER C1 FAIL: assertion has not crossed the v10 SECURITY DEFINER hardening boundary (path=%)',coalesce(v_path,'<missing>');
    end if;

    alter function public.assert_perimeter_closed()
      rename to perimeter_assert_violations_v1;
  end if;

  v_oid := to_regprocedure('public.perimeter_assert_violations_v1()');
  select cfg into v_path
  from pg_proc p
  left join lateral (
    select x cfg from unnest(p.proconfig) x where x like 'search_path=%'
  ) s on true
  where p.oid=v_oid;

  if v_oid is null
     or v_path is distinct from 'search_path=pg_catalog, pg_temp'
     or not (select prosecdef from pg_proc where oid=v_oid) then
    raise exception 'PERIMETER C1 FAIL: internal assertion primitive is missing or not v10-hardened';
  end if;
end $$;

create or replace function public.perimeter_report()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_gaps jsonb := '[]'::jsonb;
  v_findings jsonb := '[]'::jsonb;
  v_acl_findings jsonb := '[]'::jsonb;
  v_required_tables text[] := array[
    'work_lessons',
    'work_lesson_evidence',
    'work_lesson_events',
    'attention_events',
    'attention_event_assignments'
  ];
  v_required_authority_functions text[] := array[
    'public.perimeter_acl_violations()',
    'public.perimeter_policy_roles(text)',
    'public.perimeter_protected_schemas()',
    'public.perimeter_authority_functions()',
    'public.perimeter_assert_violations_v1()'
  ];
  v_missing text[];
  v_policy_count integer := 0;
  v_registered_schemas integer := 0;
  v_resolved_schemas integer := 0;
  v_registered_functions integer := 0;
  v_resolved_functions integer := 0;
  v_profile text;
  v_role_names text[] := array[]::text[];
  v_assertion_error text;
  v_assertion_oid oid;
  v_assertion_source text;
  v_count integer;
begin
  -- C1 is the final enforcement seam. If a predecessor migration is replayed
  -- out of order and rewrites assert_perimeter_closed(), the report must expose
  -- that wiring drift instead of continuing to look clean. This is deliberately
  -- checked through pg_catalog so the detector does not depend on the seam it
  -- is validating.
  v_assertion_oid := to_regprocedure('public.assert_perimeter_closed()');
  if v_assertion_oid is null then
    v_gaps := v_gaps || jsonb_build_array(jsonb_build_object(
      'kind','assertion_seam_unwired',
      'reason','public.assert_perimeter_closed() is missing'
    ));
  else
    select p.prosrc into v_assertion_source from pg_proc p where p.oid=v_assertion_oid;
    if position('public.perimeter_report()' in coalesce(v_assertion_source,''))=0 then
      v_gaps := v_gaps || jsonb_build_array(jsonb_build_object(
        'kind','assertion_seam_unwired',
        'reason','public.assert_perimeter_closed() does not route through public.perimeter_report()'
      ));
    end if;
  end if;

  -- These routines are mandatory inputs to the evaluator itself. A restored
  -- target that is missing one is unsupported, not an implementation error and
  -- never a clean result.
  select coalesce(array_agg(f order by f),array[]::text[])
    into v_missing
  from unnest(v_required_authority_functions) f
  where to_regprocedure(f) is null;

  if cardinality(v_missing)>0 then
    v_gaps := v_gaps || jsonb_build_array(jsonb_build_object(
      'kind','missing_authority_functions',
      'count',cardinality(v_missing),
      'items',to_jsonb(v_missing)
    ));
  end if;

  -- First establish that the three durable perimeter control tables themselves
  -- exist. Do not query a missing table and turn "cannot evaluate" into an
  -- implementation exception.
  select coalesce(array_agg(x order by x),array[]::text[])
    into v_missing
  from unnest(array[
    'perimeter_acl_policy',
    'perimeter_protected_schema_registry',
    'perimeter_authority_function_registry'
  ]) x
  where to_regclass(format('public.%I',x)) is null;

  if cardinality(v_missing)>0 then
    v_gaps := v_gaps || jsonb_build_array(jsonb_build_object(
      'kind','missing_control_tables','count',cardinality(v_missing),'items',to_jsonb(v_missing)
    ));
    return jsonb_build_object(
      'contract_version','perimeter-report/1',
      'evaluation_status','unsupported',
      'perimeter_state','unknown',
      'coverage',jsonb_build_object(
        'complete',false,
        'required_authority_functions',cardinality(v_required_authority_functions),
        'authority_functions_required_resolved',cardinality(v_required_authority_functions)-cardinality(coalesce(v_missing,array[]::text[])),
        'gap_count',jsonb_array_length(v_gaps),
        'gaps',v_gaps
      ),
      'violation_count',null,
      'findings','[]'::jsonb,
      'violation_detail_rpc','public.perimeter_acl_violations()',
      'assertion_rpc','public.assert_perimeter_closed()'
    );
  end if;

  select count(*),max(profile)
    into v_policy_count,v_profile
  from public.perimeter_acl_policy
  where singleton;

  if v_policy_count<>1 then
    v_gaps := v_gaps || jsonb_build_array(jsonb_build_object(
      'kind','perimeter_policy_singleton','expected',1,'observed',v_policy_count
    ));
  else
    select array(
      select distinct role_name
      from unnest(
        owner_roles ||
        schema_create_roles ||
        function_execute_roles ||
        internal_execute_roles
      ) role_name
      where role_name is not null and role_name<>''
      order by role_name
    )
    into v_role_names
    from public.perimeter_acl_policy
    where singleton;

    select coalesce(array_agg(role_name order by role_name),array[]::text[])
      into v_missing
    from unnest(v_role_names) role_name
    where not exists(select 1 from pg_roles r where r.rolname=role_name);

    if cardinality(v_missing)>0 then
      v_gaps := v_gaps || jsonb_build_array(jsonb_build_object(
        'kind','missing_policy_roles','count',cardinality(v_missing),'items',to_jsonb(v_missing)
      ));
    end if;
  end if;

  select count(*) into v_registered_schemas
  from public.perimeter_protected_schema_registry;

  select count(*) into v_resolved_schemas
  from public.perimeter_protected_schema_registry r
  join pg_namespace n on n.nspname=r.schema_name;

  if v_registered_schemas=0
     or not exists(
       select 1 from public.perimeter_protected_schema_registry
       where schema_name='public'
     )
     or v_resolved_schemas<>v_registered_schemas then
    select coalesce(array_agg(r.schema_name order by r.schema_name),array[]::text[])
      into v_missing
    from public.perimeter_protected_schema_registry r
    left join pg_namespace n on n.nspname=r.schema_name
    where n.oid is null;

    v_gaps := v_gaps || jsonb_build_array(jsonb_build_object(
      'kind','protected_schema_population',
      'registered',v_registered_schemas,
      'resolved',v_resolved_schemas,
      'public_registered',exists(
        select 1 from public.perimeter_protected_schema_registry where schema_name='public'
      ),
      'missing_items',to_jsonb(v_missing)
    ));
  end if;

  select count(*) into v_registered_functions
  from public.perimeter_authority_function_registry;

  select count(*) into v_resolved_functions
  from public.perimeter_authority_function_registry r
  where to_regprocedure(r.function_identity) is not null;

  if v_registered_functions=0 or v_resolved_functions<>v_registered_functions then
    select coalesce(array_agg(r.function_identity order by r.function_identity),array[]::text[])
      into v_missing
    from public.perimeter_authority_function_registry r
    where to_regprocedure(r.function_identity) is null;

    v_gaps := v_gaps || jsonb_build_array(jsonb_build_object(
      'kind','authority_function_population',
      'registered',v_registered_functions,
      'resolved',v_resolved_functions,
      'missing_items',to_jsonb(v_missing)
    ));
  end if;

  select coalesce(array_agg(t order by t),array[]::text[])
    into v_missing
  from unnest(v_required_tables) t
  where to_regclass(format('public.%I',t)) is null;

  if cardinality(v_missing)>0 then
    v_gaps := v_gaps || jsonb_build_array(jsonb_build_object(
      'kind','missing_protected_tables','count',cardinality(v_missing),'items',to_jsonb(v_missing)
    ));
  end if;

  if jsonb_array_length(v_gaps)>0 then
    return jsonb_build_object(
      'contract_version','perimeter-report/1',
      'evaluation_status','unsupported',
      'perimeter_state','unknown',
      'coverage',jsonb_build_object(
        'complete',false,
        'profile',v_profile,
        'policy_rows',v_policy_count,
        'required_policy_roles',cardinality(v_role_names),
        'required_authority_functions',cardinality(v_required_authority_functions),
        'authority_functions_required_resolved',cardinality(v_required_authority_functions)-(
          select count(*) from unnest(v_required_authority_functions) f where to_regprocedure(f) is null
        ),
        'protected_schemas_registered',v_registered_schemas,
        'protected_schemas_resolved',v_resolved_schemas,
        'authority_functions_registered',v_registered_functions,
        'authority_functions_resolved',v_resolved_functions,
        'required_protected_tables',cardinality(v_required_tables),
        'gap_count',jsonb_array_length(v_gaps),
        'gaps',v_gaps
      ),
      'violation_count',null,
      'findings','[]'::jsonb,
      'violation_detail_rpc','public.perimeter_acl_violations()',
      'assertion_rpc','public.assert_perimeter_closed()'
    );
  end if;

  -- Preserve the structured ACL detail already exposed by the perimeter
  -- implementation. Other assertion categories remain visible through the
  -- bounded assertion finding below rather than being silently converted into
  -- a zero-row "clean" result.
  select coalesce(jsonb_agg(jsonb_build_object(
           'kind','acl',
           'boundary',boundary,
           'object_identity',object_identity,
           'grantee',grantee,
           'privilege_type',privilege_type,
           'privilege_source',privilege_source
         ) order by boundary,object_identity,grantee,privilege_type,privilege_source),'[]'::jsonb)
    into v_acl_findings
  from public.perimeter_acl_violations();

  v_findings := v_acl_findings;

  begin
    perform public.perimeter_assert_violations_v1();
  exception
    when sqlstate 'P0001' then
      get stacked diagnostics v_assertion_error = message_text;
      if v_assertion_error not like 'PERIMETER FAIL:%' then
        raise;
      end if;

      -- The v10 primitive intentionally wraps ACL findings in a category-level
      -- assertion message. Do not count that message a second time when the
      -- same category is already represented by structured ACL rows.
      if jsonb_array_length(v_acl_findings)>0
         and (
           v_assertion_error like 'PERIMETER FAIL: owner-global default ACLs:%'
           or v_assertion_error like 'PERIMETER FAIL: unexpected effective ACL grantees:%'
         ) then
        null;
      else
        v_findings := v_findings || jsonb_build_array(jsonb_build_object(
          'kind','assertion',
          'message',v_assertion_error
        ));
      end if;
  end;

  v_count := jsonb_array_length(v_findings);

  return jsonb_build_object(
    'contract_version','perimeter-report/1',
    'evaluation_status','evaluated',
    'perimeter_state',case when v_count=0 then 'clean' else 'not_clean' end,
    'coverage',jsonb_build_object(
      'complete',true,
      'profile',v_profile,
      'policy_rows',v_policy_count,
      'required_policy_roles',cardinality(v_role_names),
      'required_authority_functions',cardinality(v_required_authority_functions),
      'authority_functions_required_resolved',cardinality(v_required_authority_functions),
      'protected_schemas_registered',v_registered_schemas,
      'protected_schemas_resolved',v_resolved_schemas,
      'authority_functions_registered',v_registered_functions,
      'authority_functions_resolved',v_resolved_functions,
      'required_protected_tables',cardinality(v_required_tables),
      'gap_count',0,
      'gaps','[]'::jsonb
    ),
    'violation_count',v_count,
    'findings',v_findings,
    'violation_detail_rpc','public.perimeter_acl_violations()',
    'assertion_rpc','public.assert_perimeter_closed()'
  );
end;
$function$;

create or replace function public.assert_perimeter_closed()
returns text
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_report jsonb;
  v_count integer;
begin
  v_report := public.perimeter_report();

  if v_report->>'evaluation_status' <> 'evaluated' then
    raise exception 'PERIMETER UNSUPPORTED: required evaluation population is incomplete: %',
      v_report->'coverage'->'gaps';
  end if;

  v_count := (v_report->>'violation_count')::integer;
  if v_count<>0 then
    raise exception 'PERIMETER FAIL: report found % finding(s): %',
      v_count,v_report->'findings';
  end if;

  return 'perimeter OK: perimeter-report/1 evaluated clean with zero findings';
end;
$function$;

-- Register the new surfaces before using the old assertion primitive, because
-- the primitive audits the complete authority-function perimeter.
insert into public.perimeter_authority_function_registry(function_identity,is_internal)
values
  ('public.perimeter_assert_violations_v1()',true),
  ('public.perimeter_report()',false),
  ('public.assert_perimeter_closed()',false)
on conflict(function_identity) do update set is_internal=excluded.is_internal;

-- Default function EXECUTE includes PUBLIC. Make the public seam obey the same
-- persisted allowlist as the rest of the perimeter. The internal primitive is
-- owner-only.
revoke all on function public.perimeter_assert_violations_v1() from public;
revoke all on function public.perimeter_report() from public;
revoke all on function public.assert_perimeter_closed() from public;

do $$
declare
  r text;
  v_profile text;
begin
  foreach r in array array['anon','authenticated','service_role'] loop
    if exists(select 1 from pg_roles where rolname=r) then
      execute format('revoke all on function public.perimeter_assert_violations_v1() from %I',r);
      execute format('revoke all on function public.perimeter_report() from %I',r);
      execute format('revoke all on function public.assert_perimeter_closed() from %I',r);
    end if;
  end loop;

  select profile into v_profile
  from public.perimeter_acl_policy
  where singleton;

  if v_profile='supabase' and exists(select 1 from pg_roles where rolname='service_role') then
    grant execute on function public.perimeter_report() to service_role;
    grant execute on function public.assert_perimeter_closed() to service_role;
  end if;
end $$;

-- The report itself is now part of the inspected perimeter. A clean installation
-- must be able to evaluate it and return zero findings.
do $$
declare
  v_report jsonb;
begin
  v_report := public.perimeter_report();
  if v_report->>'evaluation_status'<>'evaluated'
     or v_report->>'perimeter_state'<>'clean'
     or (v_report->>'violation_count')::integer<>0 then
    raise exception 'PERIMETER C1 FAIL: post-install report is not evaluated/clean: %',v_report;
  end if;
  if public.assert_perimeter_closed()<>'perimeter OK: perimeter-report/1 evaluated clean with zero findings' then
    raise exception 'PERIMETER C1 FAIL: assertion seam returned an unexpected success string';
  end if;
end $$;

commit;
