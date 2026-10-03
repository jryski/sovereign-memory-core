-- ============================================================================
-- SOVEREIGN MEMORY :: SCOPE-BOUND AUTHORITY VALIDATION
-- Target: local Postgres after sql/01_core.sql, sql/04_source_import.sql,
-- sql/05_candidate_locators.sql, sql/06_cutover_probe_categories.sql, and
-- sql/12_scope_bound_authority.sql.
--
-- The smoke fixture uses two synthetic scopes and rolls back. It does not
-- connect to a hosted database.
-- ============================================================================

set search_path to public, extensions;

create temp table if not exists scope_authority_validation_results (
  check_group text not null,
  object_name text not null,
  state text not null check (state in ('pass','warn','fail')),
  severity text not null default 'required',
  fatal boolean not null default true,
  remediation text not null
) on commit preserve rows;

truncate scope_authority_validation_results;

insert into scope_authority_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'required_object', object_name, state, 'required', true, remediation
from (
  values
    ('scope_registry', to_regclass('public.scope_registry') is not null, 'Run sql/12_scope_bound_authority.sql'),
    ('scope_truth_claims', to_regclass('public.scope_truth_claims') is not null, 'Run sql/12_scope_bound_authority.sql'),
    ('scope_authority_declarations', to_regclass('public.scope_authority_declarations') is not null, 'Run sql/12_scope_bound_authority.sql'),
    ('scope_cutover_scorecard', to_regclass('public.scope_cutover_scorecard') is not null, 'Run sql/12_scope_bound_authority.sql'),
    ('scope_authority_report', to_regclass('public.scope_authority_report') is not null, 'Run sql/12_scope_bound_authority.sql')
) as v(object_name, ok, remediation)
cross join lateral (select case when ok then 'pass' else 'fail' end as state) s;

insert into scope_authority_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'required_function', function_name, state, 'required', true, 'Run sql/12_scope_bound_authority.sql'
from (
  values
    ('register_scope', to_regprocedure('public.register_scope(text,text,text)') is not null),
    ('assign_cutover_scope', to_regprocedure('public.assign_cutover_scope(uuid,text,text)') is not null),
    ('declare_scope_authority', to_regprocedure('public.declare_scope_authority(text,text,uuid,text,text,text)') is not null),
    ('rollback_scope_before_authority', to_regprocedure('public.rollback_scope_before_authority(uuid,text,text)') is not null),
    ('rollback_scope_authority', to_regprocedure('public.rollback_scope_authority(uuid,text,text)') is not null),
    ('scope_visible_current_truth', to_regprocedure('public.scope_visible_current_truth(text)') is not null),
    ('scope_probe_observations', to_regprocedure('public.scope_probe_observations(text)') is not null)
) as v(function_name, ok)
cross join lateral (select case when ok then 'pass' else 'fail' end as state) s;

insert into scope_authority_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'required_column',
       table_name || '.' || column_name,
       case when exists (
         select 1 from information_schema.columns c
         where c.table_schema = 'public'
           and c.table_name = v.table_name
           and c.column_name = v.column_name
       ) then 'pass' else 'fail' end,
       'required',
       true,
       'Schema must store cutover scope and bind probe results to it.'
from (values
  ('source_import_batches', 'cutover_scope'),
  ('cutover_probes', 'result_scope'),
  ('cutover_runs', 'result_scope'),
  ('scope_authority_declarations', 'principal'),
  ('scope_authority_declarations', 'scope_key')
) as v(table_name, column_name);

insert into scope_authority_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'function_posture',
       p.proname,
       case
         when p.prosecdef then 'fail'
         when array_to_string(coalesce(p.proconfig, '{}'::text[]), ',') like '%search_path=public%' then 'pass'
         else 'fail'
       end,
       'required',
       true,
       'Scope functions stay invoker and pin search_path. They are not a new definer inventory.'
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'register_scope','assign_cutover_scope','declare_scope_authority',
    'rollback_scope_before_authority','rollback_scope_authority',
    'scope_visible_current_truth','scope_probe_observations'
  );

insert into scope_authority_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'grant_posture',
       'table_or_view_grants',
       case when count(*) = 0 then 'pass' else 'fail' end,
       'required',
       true,
       'Revoke scope table and view privileges from PUBLIC, anon, and authenticated.'
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in (
    'scope_registry','scope_truth_claims','scope_authority_declarations',
    'scope_cutover_scorecard','scope_authority_report'
  )
  and grantee in ('PUBLIC','anon','authenticated');

insert into scope_authority_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'grant_posture',
       'function_execute_grants',
       case when count(*) = 0 then 'pass' else 'fail' end,
       'required',
       true,
       'Revoke scope function execute from PUBLIC, anon, and authenticated.'
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
where p.proname in (
  'register_scope','assign_cutover_scope','declare_scope_authority',
  'rollback_scope_before_authority','rollback_scope_authority',
  'scope_visible_current_truth','scope_probe_observations',
  'scope_guard_batch_cutover','scope_guard_probe_binding','scope_guard_declaration'
)
  and acl.privilege_type = 'EXECUTE'
  and acl.grantee::regrole::text in ('anon','authenticated','-');

insert into scope_authority_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'closed_kind',
       'no_global_kind_in_constraint',
       case when pg_get_constraintdef(oid) like '%workstream%table%record%domain%'
             and pg_get_constraintdef(oid) not like '%global%'
            then 'pass' else 'fail' end,
       'required',
       true,
       'scope_kind_closed must list the four named kinds and no global kind.'
from pg_constraint
where conname = 'scope_kind_closed';

insert into scope_authority_validation_results(check_group, object_name, state, severity, fatal, remediation)
select 'closed_kind',
       'scope_kind_closed_present',
       case when count(*) = 1 then 'pass' else 'fail' end,
       'required',
       true,
       'scope_kind_closed must exist so a global kind cannot be added silently.'
from pg_constraint
where conname = 'scope_kind_closed';

select check_group, object_name, state, severity, remediation
from scope_authority_validation_results
order by check_group, object_name;

-- ---- smoke fixture ----------------------------------------------------------
begin;

create temp table scope_authority_fixture_results (
  check_group text not null,
  object_name text not null,
  state text not null check (state in ('pass','fail')),
  severity text not null default 'required',
  fatal boolean not null default true,
  remediation text not null
) on commit drop;

create function pg_temp.prepare_scope_batch(
  p_batch_key text,
  p_scope text,
  p_agent text,
  p_system_id uuid,
  p_bind boolean,
  p_record_runs boolean,
  p_matched boolean,
  p_mark_ready boolean
) returns uuid
language plpgsql
set search_path to public, extensions
as $fn$
declare
  v_batch uuid;
  v_item uuid;
  v_hash text;
  v_quote text := 'fixture quote for ' || p_batch_key;
  v_payload text := '{"fixture":"' || p_batch_key || '"}';
begin
  v_hash := encode(digest(v_payload, 'sha256'), 'hex');

  insert into source_import_batches(
    source_system_id, batch_key, source_item_count, exported_item_count, created_by, cutover_scope
  ) values (
    p_system_id, p_batch_key, 1, 1, p_agent, p_scope
  )
  returning id into v_batch;

  insert into source_items(
    batch_id, source_item_key, source_container, source_kind, title, payload_hash, payload_size_bytes
  ) values (
    v_batch, p_batch_key || '-item', 'fixture/scope', 'note', p_batch_key, v_hash, length(v_payload)
  )
  returning id into v_item;

  insert into source_payload_evidence(
    source_item_id, evidence_kind, location, payload_hash, size_bytes, content_preview
  ) values (
    v_item, 'raw_payload', 'fixture://' || p_batch_key || '.json', v_hash, length(v_payload), p_batch_key
  );

  insert into source_manifest(
    source_item_id, manifest_key, source_locator, source_quote, source_quote_hash,
    source_quote_hash_algorithm, action, target_zone, review_state, target_table,
    topic_key, workstream, suggested_summary, source_payload_hash_at_review,
    reviewed_by, reviewed_at, review_notes
  ) values (
    v_item,
    'candidate:' || p_batch_key,
    jsonb_build_object('scheme','fixture-json','path', jsonb_build_array('fixture', p_batch_key)),
    v_quote,
    encode(digest(v_quote, 'sha256'), 'hex'),
    'sha256',
    'import'::source_item_action,
    'HOUSE'::source_target_zone,
    'approved'::source_review_state,
    'memories',
    'fixture/scope',
    'fixture',
    'Fixture summary ' || p_batch_key,
    v_hash,
    p_agent,
    now(),
    'Fixture review for ' || p_batch_key
  );

  perform source_freeze_batch(v_batch, p_agent, jsonb_build_object('fixture', true, 'count', 1), 'scope fixture');

  insert into cutover_probes(
    batch_id, probe_key, probe_type, probe_category, severity, prompt,
    expected_behavior, expected_evidence_required, result_scope
  )
  select v_batch,
         p_batch_key || '-' || p.probe_category,
         p.probe_type,
         p.probe_category,
         'critical'::cutover_probe_severity,
         p.prompt,
         p.expected_behavior,
         p.expected_evidence_required,
         case when p_bind then p_scope else null end
  from (values
    ('positive', 'project-state', 'What is current in this scope?', 'Return only this scope''s current fixture fact.', false),
    ('negative', 'unknown-avoidance', 'What belongs to the other scope?', 'Do not import the other scope.', false),
    ('conflict', 'conflict', 'Is a conflict flattened?', 'Keep the conflict in this scope.', false),
    ('stale_state', 'stale-avoidance', 'Is the retired fact current?', 'Do not return the retired fact as current.', false),
    ('evidence_request', 'evidence', 'Where is the fixture evidence?', 'Cite this scope''s fixture evidence.', true)
  ) as p(probe_category, probe_type, prompt, expected_behavior, expected_evidence_required);

  if p_record_runs then
    insert into cutover_runs(probe_id, runner_agent, matched, observed_answer, notes, result_scope)
    select cp.id,
           p_agent,
           p_matched,
           case when p_bind then p_scope || '-observation:' || cp.probe_category else 'unbound-observation' end,
           'scope fixture',
           case when p_bind then p_scope else null end
    from cutover_probes cp
    where cp.batch_id = v_batch;
  end if;

  if p_mark_ready then
    perform source_mark_batch_ready(v_batch, p_agent);
  end if;

  return v_batch;
end;
$fn$;

do $body$
declare
  v_system uuid;
  v_alpha uuid;
  v_beta uuid;
  v_gamma uuid;
  v_delta uuid;
  v_alpha_decl uuid;
  v_beta_decl uuid;
  v_ok boolean;
  v_detail text;
  v_count integer;
  v_text text;
begin
  insert into trusted_agents(agent_id, principal, display_name, model, surface)
  values
    ('fixture-scope-alpha', 'example-user', 'Fixture Scope Alpha', 'fixture', 'validation'),
    ('fixture-scope-beta', 'example-partner', 'Fixture Scope Beta', 'fixture', 'validation');

  insert into source_systems(source_key, display_name, source_type, adapter_name, adapter_version)
  values ('fixture-scope-authority', 'Fixture Scope Authority', 'other', 'fixture-adapter', '0.0.1')
  returning id into v_system;

  begin
    perform register_scope('global', 'all', 'Fixture global');
    v_ok := false;
    v_detail := 'register_scope accepted a global kind';
  exception when others then
    v_ok := sqlerrm like 'scope registry:%';
    v_detail := sqlerrm;
  end;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values ('scope_grammar', 'reject_global_kind', case when v_ok then 'pass' else 'fail' end, v_detail);

  begin
    perform register_scope('workstream', '*', 'Fixture wildcard');
    v_ok := false;
    v_detail := 'register_scope accepted a wildcard identifier';
  exception when others then
    v_ok := sqlerrm like 'scope registry:%';
    v_detail := sqlerrm;
  end;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values ('scope_grammar', 'reject_wildcard_identifier', case when v_ok then 'pass' else 'fail' end, v_detail);

  begin
    perform register_scope('workstream', 'all', 'Fixture all');
    v_ok := false;
    v_detail := 'register_scope accepted the universal identifier all';
  exception when others then
    v_ok := sqlerrm like 'scope registry:%';
    v_detail := sqlerrm;
  end;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values ('scope_grammar', 'reject_universal_identifier', case when v_ok then 'pass' else 'fail' end, v_detail);

  perform register_scope('workstream', 'alpha', 'Fixture scope alpha');
  perform register_scope('workstream', 'beta', 'Fixture scope beta');
  perform register_scope('workstream', 'gamma', 'Fixture scope gamma');
  perform register_scope('workstream', 'delta', 'Fixture scope delta');
  perform register_scope('workstream', 'epsilon', 'Fixture scope epsilon');

  select count(*) into v_count
  from scope_registry
  where scope_kind in ('global','all') or scope_key like '%*%' or scope_identifier in ('all','global','any');
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'scope_grammar',
    'registry_has_no_universal_scope',
    case when v_count = 0 then 'pass' else 'fail' end,
    'Registered scopes must stay explicit. Found ' || v_count || ' universal row(s).'
  );

  select authoritative into v_ok
  from scope_authority_report
  where scope_key = 'workstream:epsilon';
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'authority_default',
    'unmentioned_scope_is_not_authoritative',
    case when v_ok is false then 'pass' else 'fail' end,
    'A registered scope with no declaration must report authoritative=false.'
  );

  insert into scope_truth_claims(scope_key, claim_key, truth_state, statement)
  values
    ('workstream:alpha', 'alpha-current', 'current', 'alpha keeps the current fixture fact'),
    ('workstream:alpha', 'alpha-retired', 'stale', 'alpha retired fixture fact'),
    ('workstream:alpha', 'fixture-label', 'stale', 'alpha retired shared label'),
    ('workstream:beta', 'beta-current', 'current', 'beta keeps the current fixture fact'),
    ('workstream:beta', 'beta-retired', 'stale', 'beta retired fixture fact'),
    ('workstream:beta', 'fixture-label', 'current', 'beta current shared label');

  select count(*) into v_count from scope_visible_current_truth(null);
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'truth_isolation',
    'null_scope_returns_nothing',
    case when v_count = 0 then 'pass' else 'fail' end,
    'A missing scope must not return every current claim.'
  );

  select count(*) into v_count
  from scope_visible_current_truth('workstream:alpha');
  select string_agg(statement, ' | ' order by claim_key) into v_text
  from scope_visible_current_truth('workstream:alpha');
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'truth_isolation',
    'alpha_current_excludes_stale_and_beta',
    case when v_count = 1 and v_text = 'alpha keeps the current fixture fact' then 'pass' else 'fail' end,
    'Alpha current truth was: ' || coalesce(v_text, '<none>')
  );

  select count(*) into v_count
  from scope_visible_current_truth('workstream:beta');
  select string_agg(statement, ' | ' order by claim_key) into v_text
  from scope_visible_current_truth('workstream:beta');
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'truth_isolation',
    'beta_current_excludes_stale_and_alpha',
    case
      when v_count = 2
       and v_text = 'beta keeps the current fixture fact | beta current shared label'
      then 'pass' else 'fail'
    end,
    'Beta current truth was: ' || coalesce(v_text, '<none>')
  );

  select count(*) into v_count
  from scope_visible_current_truth('workstream:alpha') a
  join scope_visible_current_truth('workstream:beta') b on b.statement = a.statement or b.claim_key = a.claim_key;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'truth_isolation',
    'shared_claim_key_does_not_cross_scopes',
    case when v_count = 0 then 'pass' else 'fail' end,
    'The same claim key is stale in alpha and current in beta. Current reads must not meet.'
  );

  v_alpha := pg_temp.prepare_scope_batch(
    'fixture-scope-alpha', 'workstream:alpha', 'fixture-scope-alpha', v_system,
    true, true, true, true
  );
  v_beta := pg_temp.prepare_scope_batch(
    'fixture-scope-beta', 'workstream:beta', 'fixture-scope-beta', v_system,
    true, false, false, false
  );

  select probes_passed_in_scope into v_count
  from scope_cutover_scorecard
  where scope_key = 'workstream:alpha';
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'probe_binding',
    'alpha_scorecard_counts_only_alpha',
    case when v_count = 5 then 'pass' else 'fail' end,
    'Alpha in-scope passes: ' || coalesce(v_count::text, '<none>')
  );

  select probes_defined::text || '/' || probes_passed_in_scope::text into v_text
  from scope_cutover_scorecard
  where scope_key = 'workstream:beta';
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'probe_binding',
    'beta_has_no_passed_runs_yet',
    case when v_text = '5/0' then 'pass' else 'fail' end,
    'Beta scorecard defined/passed was ' || coalesce(v_text, '<none>') || '. Alpha passes must not count.'
  );

  select count(*) into v_count
  from scope_probe_observations('workstream:beta') o
  where o.observed_answer like 'workstream:alpha%';
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'probe_binding',
    'beta_observations_exclude_alpha',
    case when v_count = 0 then 'pass' else 'fail' end,
    'Alpha observations must not be readable as beta probe results.'
  );

  begin
    insert into cutover_runs(probe_id, runner_agent, matched, observed_answer, notes, result_scope)
    select cp.id, 'fixture-scope-beta', true, 'workstream:alpha-observation:leaked', 'cross scope', 'workstream:alpha'
    from cutover_probes cp
    where cp.batch_id = v_beta
    limit 1;
    v_ok := false;
    v_detail := 'a beta probe accepted an alpha result scope';
  exception when others then
    v_ok := sqlerrm like 'scope probe result:%';
    v_detail := sqlerrm;
  end;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values ('probe_binding', 'reject_cross_scope_probe_run', case when v_ok then 'pass' else 'fail' end, v_detail);

  begin
    insert into cutover_probes(
      batch_id, probe_key, probe_type, probe_category, severity, prompt, result_scope
    ) values (
      v_alpha, 'fixture-scope-alpha-foreign', 'other', 'positive', 'normal'::cutover_probe_severity,
      'Foreign scope probe', 'workstream:beta'
    );
    v_ok := false;
    v_detail := 'an alpha batch accepted a beta probe scope';
  exception when others then
    v_ok := sqlerrm like 'scope probe:%';
    v_detail := sqlerrm;
  end;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values ('probe_binding', 'reject_cross_scope_probe', case when v_ok then 'pass' else 'fail' end, v_detail);

  insert into cutover_runs(probe_id, runner_agent, matched, observed_answer, notes, result_scope)
  select cp.id, 'fixture-scope-beta', true, 'workstream:beta-observation:' || cp.probe_category, 'scope fixture', 'workstream:beta'
  from cutover_probes cp
  where cp.batch_id = v_beta;
  perform source_mark_batch_ready(v_beta, 'fixture-scope-beta');

  v_gamma := pg_temp.prepare_scope_batch(
    'fixture-scope-gamma', 'workstream:gamma', 'fixture-scope-alpha', v_system,
    true, true, true, true
  );
  v_delta := pg_temp.prepare_scope_batch(
    'fixture-scope-delta', 'workstream:delta', 'fixture-scope-alpha', v_system,
    false, true, true, true
  );

  begin
    perform declare_scope_authority(
      'workstream:delta', 'example-user', v_delta, 'fixture-scope-alpha',
      'fixture://scope-authority/delta', 'Delta review must not pass on unbound probes.'
    );
    v_ok := false;
    v_detail := 'unbound passing probes authorized a scope';
  exception when others then
    v_ok := sqlerrm like 'scope authority: scope workstream:delta is missing %';
    v_detail := sqlerrm;
  end;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values ('probe_binding', 'unbound_passes_do_not_authorize', case when v_ok then 'pass' else 'fail' end, v_detail);

  begin
    update source_import_batches set status = 'cutover' where id = v_delta;
    v_ok := false;
    v_detail := 'batch entered cutover without a declaration';
  exception when others then
    v_ok := sqlerrm like 'scope: cutover requires a recorded authority declaration%';
    v_detail := sqlerrm;
  end;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values ('cutover_guard', 'cutover_without_declaration_rejected', case when v_ok then 'pass' else 'fail' end, v_detail);

  if rollback_scope_before_authority(v_gamma, 'fixture-scope-alpha', 'Gamma stays reversible before declaration.') <> 'rolled_back' then
    insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
    values ('rollback', 'before_authority_returns_rolled_back', 'fail', 'rollback_scope_before_authority did not return rolled_back');
  else
    insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
    values ('rollback', 'before_authority_returns_rolled_back', 'pass', 'Gamma rolled back before any declaration.');
  end if;

  select status into v_text from source_import_batches where id = v_gamma;
  select count(*) into v_count
  from scope_authority_declarations
  where scope_key = 'workstream:gamma';
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'rollback',
    'before_authority_records_no_declaration',
    case when v_text = 'rolled_back' and v_count = 0 then 'pass' else 'fail' end,
    'Gamma status=' || coalesce(v_text, '<none>') || ' declarations=' || v_count
  );

  begin
    perform declare_scope_authority(
      'workstream:alpha', 'example-partner', v_alpha, 'fixture-scope-alpha',
      'fixture://scope-authority/alpha', 'Wrong principal.'
    );
    v_ok := false;
    v_detail := 'example-partner was recorded for the alpha agent';
  exception when others then
    v_ok := sqlerrm like 'scope authority: principal % does not match%';
    v_detail := sqlerrm;
  end;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values ('authority_declaration', 'reject_other_principal', case when v_ok then 'pass' else 'fail' end, v_detail);

  begin
    perform declare_scope_authority(
      'workstream:beta', 'example-user', v_alpha, 'fixture-scope-alpha',
      'fixture://scope-authority/beta', 'Wrong batch.'
    );
    v_ok := false;
    v_detail := 'alpha batch declared beta';
  exception when others then
    v_ok := sqlerrm like 'scope authority: batch scope % does not match declared scope %';
    v_detail := sqlerrm;
  end;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values ('authority_declaration', 'reject_cross_scope_batch', case when v_ok then 'pass' else 'fail' end, v_detail);

  begin
    perform declare_scope_authority(
      'workstream:alpha', 'global', v_alpha, 'fixture-scope-alpha',
      'fixture://scope-authority/alpha', 'Global principal.'
    );
    v_ok := false;
    v_detail := 'global principal was accepted';
  exception when others then
    v_ok := sqlerrm like 'scope authority: principal must be named%';
    v_detail := sqlerrm;
  end;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values ('authority_declaration', 'reject_global_principal', case when v_ok then 'pass' else 'fail' end, v_detail);

  v_alpha_decl := declare_scope_authority(
    'workstream:alpha', 'example-user', v_alpha, 'fixture-scope-alpha',
    'fixture://scope-authority/alpha', 'Alpha review note for the fixture scope.'
  );
  v_beta_decl := declare_scope_authority(
    'workstream:beta', 'example-partner', v_beta, 'fixture-scope-beta',
    'fixture://scope-authority/beta', 'Beta review note for the fixture scope.'
  );

  select count(*) into v_count
  from scope_authority_declarations
  where id = v_alpha_decl
    and scope_key = 'workstream:alpha'
    and principal = 'example-user'
    and batch_id = v_alpha
    and evidence_ref = 'fixture://scope-authority/alpha'
    and status = 'recorded';
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'authority_declaration',
    'alpha_declaration_names_principal_and_scope',
    case when v_count = 1 then 'pass' else 'fail' end,
    'Alpha declaration must store the named principal and scope.'
  );

  select count(*) into v_count
  from scope_authority_declarations
  where id = v_beta_decl
    and scope_key = 'workstream:beta'
    and principal = 'example-partner'
    and batch_id = v_beta
    and status = 'recorded';
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'authority_declaration',
    'beta_declaration_names_principal_and_scope',
    case when v_count = 1 then 'pass' else 'fail' end,
    'Beta declaration must store its own principal and scope.'
  );

  select status into v_text from source_import_batches where id = v_alpha;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'authority_declaration',
    'alpha_batch_is_cutover',
    case when v_text = 'cutover' then 'pass' else 'fail' end,
    'Alpha batch status=' || coalesce(v_text, '<none>')
  );

  select status into v_text from source_import_batches where id = v_beta;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'authority_declaration',
    'beta_batch_is_cutover',
    case when v_text = 'cutover' then 'pass' else 'fail' end,
    'Beta batch status=' || coalesce(v_text, '<none>')
  );

  select status into v_text from source_import_batches where id = v_delta;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'authority_declaration',
    'delta_remains_ready',
    case when v_text = 'ready' then 'pass' else 'fail' end,
    'Declaring alpha and beta must not move the unbound delta batch. Status=' || coalesce(v_text, '<none>')
  );

  select count(*) filter (where authoritative) into v_count
  from scope_authority_report
  where scope_key in ('workstream:alpha','workstream:beta','workstream:gamma','workstream:delta','workstream:epsilon');
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'authority_declaration',
    'only_declared_scopes_are_authoritative',
    case when v_count = 2 then 'pass' else 'fail' end,
    'Authoritative fixture scopes: ' || v_count
  );

  begin
    perform declare_scope_authority(
      'workstream:alpha', 'example-user', v_alpha, 'fixture-scope-alpha',
      'fixture://scope-authority/alpha-again', 'Second declaration.'
    );
    v_ok := false;
    v_detail := 'a second declaration call was accepted';
  exception when others then
    v_ok := sqlerrm like 'scope authority:%';
    v_detail := sqlerrm;
  end;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values ('authority_declaration', 'reject_second_declaration_call', case when v_ok then 'pass' else 'fail' end, v_detail);

  begin
    insert into scope_authority_declarations(
      scope_key, principal, batch_id, evidence_ref, review_note, declared_by
    ) values (
      'workstream:alpha', 'example-user', v_alpha, 'fixture://scope-authority/alpha-again',
      'Second declaration.', 'fixture-scope-alpha'
    );
    v_ok := false;
    v_detail := 'a second live row was inserted';
  exception when others then
    v_ok := sqlerrm like '%scope_authority_one_live_per_scope%';
    v_detail := sqlerrm;
  end;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values ('authority_declaration', 'reject_second_live_row', case when v_ok then 'pass' else 'fail' end, v_detail);

  begin
    perform rollback_scope_before_authority(v_alpha, 'fixture-scope-alpha', 'Too late.');
    v_ok := false;
    v_detail := 'pre-authority rollback succeeded after declaration';
  exception when others then
    v_ok := sqlerrm like 'scope rollback: batch % already has recorded authority%';
    v_detail := sqlerrm;
  end;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values ('rollback', 'before_authority_blocked_after_declaration', case when v_ok then 'pass' else 'fail' end, v_detail);

  begin
    perform rollback_scope_authority(v_alpha_decl, 'fixture-scope-beta', 'Beta must not roll alpha back.');
    v_ok := false;
    v_detail := 'beta rolled back alpha';
  exception when others then
    v_ok := sqlerrm like 'scope rollback: agent principal % cannot roll back declaration%';
    v_detail := sqlerrm;
  end;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values ('rollback', 'other_principal_cannot_roll_back', case when v_ok then 'pass' else 'fail' end, v_detail);

  if rollback_scope_authority(v_alpha_decl, 'fixture-scope-alpha', 'Recorded rollback of alpha only.') <> 'workstream:alpha' then
    insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
    values ('rollback', 'recorded_rollback_returns_scope', 'fail', 'rollback_scope_authority did not return the alpha scope');
  else
    insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
    values ('rollback', 'recorded_rollback_returns_scope', 'pass', 'Alpha rollback returned workstream:alpha.');
  end if;

  select status into v_text
  from scope_authority_declarations
  where id = v_alpha_decl;
  select authoritative into v_ok
  from scope_authority_report
  where scope_key = 'workstream:alpha';
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'rollback',
    'alpha_rollback_keeps_row_and_clears_authority',
    case when v_text = 'rolled_back' and v_ok is false then 'pass' else 'fail' end,
    'Alpha declaration status=' || coalesce(v_text, '<none>')
  );

  select b.status, r.authoritative
    into v_text, v_ok
  from source_import_batches b
  join scope_authority_report r on r.scope_key = b.cutover_scope
  where b.id = v_beta;
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'rollback',
    'beta_authority_survives_alpha_rollback',
    case when v_text = 'cutover' and v_ok is true then 'pass' else 'fail' end,
    'Beta status=' || coalesce(v_text, '<none>')
  );

  select string_agg(statement, ' | ' order by claim_key) into v_text
  from scope_visible_current_truth('workstream:alpha');
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'truth_isolation',
    'alpha_truth_unchanged_after_rollback',
    case when v_text = 'alpha keeps the current fixture fact' then 'pass' else 'fail' end,
    'Rollback must not import beta truth or revive alpha stale truth. Saw: ' || coalesce(v_text, '<none>')
  );

  select count(*) into v_count
  from scope_visible_current_truth('workstream:beta')
  where statement like '%retired%' or statement like 'alpha %';
  insert into scope_authority_fixture_results(check_group, object_name, state, remediation)
  values (
    'truth_isolation',
    'beta_current_still_excludes_stale_and_alpha',
    case when v_count = 0 then 'pass' else 'fail' end,
    'Beta current truth picked up stale or alpha text.'
  );
end;
$body$;

select check_group, object_name, state, remediation
from scope_authority_fixture_results
order by check_group, object_name;

do $$
declare
  fail_count integer;
begin
  select count(*) into fail_count
  from scope_authority_fixture_results
  where fatal and state = 'fail';
  if fail_count > 0 then
    raise exception 'scope authority fixture validation failed: % failing check(s)', fail_count;
  end if;
end $$;

rollback;

do $$
declare
  fail_count integer;
begin
  select count(*) into fail_count
  from scope_authority_validation_results
  where fatal and state = 'fail';
  if fail_count > 0 then
    raise exception 'scope authority validation failed: % failing check(s)', fail_count;
  end if;
end $$;
