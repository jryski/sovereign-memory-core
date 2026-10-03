-- ============================================================================
-- SOVEREIGN MEMORY :: HUMAN APPROVAL VALIDATION
-- Target: disposable Postgres after sql/01_core.sql and sql/13_human_approval_requests.sql.
-- The fixture transaction rolls back. Role shims anon, authenticated, and
-- service_role must already exist.
-- ============================================================================

begin;

do $$
declare
  v_primary_memory uuid;
  v_replay_memory uuid;
  v_expire_memory uuid;
  v_reject_memory uuid;
  v_stale_memory uuid;
  v_mismatch_memory uuid;
  v_active_memory uuid;
  v_unsupported_memory uuid;
  v_service_memory uuid;
  v_primary_request uuid;
  v_replay_request uuid;
  v_expire_request uuid;
  v_reject_request uuid;
  v_stale_request uuid;
  v_mismatch_request uuid;
  v_service_request uuid;
  v_unsupported_request uuid;
  v_primary_version text;
  v_primary_nonce text;
  v_replay_version text;
  v_replay_nonce text;
  v_expire_version text;
  v_expire_nonce text;
  v_reject_version text;
  v_reject_nonce text;
  v_stale_version text;
  v_stale_nonce text;
  v_mismatch_version text;
  v_mismatch_nonce text;
  v_unsupported_version text;
  v_unsupported_nonce text;
  v_receipt uuid;
  v_reject_receipt uuid;
  v_status text;
  v_updated timestamptz;
  v_content text;
  v_audit integer;
  v_receipts integer;
  v_open_sessions integer;
  v_wrong_nonce text;
  v_wrong_version text;
  v_live_version text;
  v_row human_approval.receipts;
  v_session human_approval.sessions;
begin
  if to_regnamespace('human_approval') is null then
    raise exception 'human approval validation: apply sql/13_human_approval_requests.sql first';
  end if;
  if (select count(*) from pg_roles where rolname in ('anon','authenticated','service_role')) <> 3 then
    raise exception 'human approval validation: anon, authenticated, and service_role shims are required';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'human_approval'
      and (
        'acting_principal' = any (coalesce(p.proargnames, '{}'::text[]))
        or 'p_acting_principal' = any (coalesce(p.proargnames, '{}'::text[]))
        or p.prosrc ilike '%acting_principal%'
      )
  ) then
    raise exception 'human approval validation: a function accepts or reads acting_principal';
  end if;

  if (select pronargdefaults from pg_proc
      where oid = 'human_approval.approve_human_approval_request(uuid,text,text,text)'::regprocedure) <> 0
     or (select pronargdefaults from pg_proc
      where oid = 'human_approval.reject_human_approval_request(uuid,text,text,text)'::regprocedure) <> 0 then
    raise exception 'human approval validation: decision functions must not default their arguments';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'human_approval'
      and not exists (
        select 1 from unnest(p.proconfig) as cfg
        where cfg like 'search_path=%'
          and right(btrim(regexp_replace(cfg, '^search_path=', '')), 7) = 'pg_temp'
      )
  ) then
    raise exception 'human approval validation: search_path must keep pg_temp last';
  end if;

  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'human_approval'
      and c.relkind = 'r'
      and (not c.relrowsecurity or not c.relforcerowsecurity)
  ) then
    raise exception 'human approval validation: approval tables must force row level security';
  end if;

  if has_function_privilege('human_approval_agent', 'human_approval.approve_human_approval_request(uuid,text,text,text)', 'execute')
     or has_function_privilege('human_approval_agent', 'human_approval.reject_human_approval_request(uuid,text,text,text)', 'execute')
     or has_function_privilege('human_approval_agent', 'human_approval.open_human_approval_session()', 'execute')
     or has_function_privilege('human_approval_agent', 'human_approval.decide_request(uuid,text,text,text,text)', 'execute')
     or has_function_privilege('service_role', 'human_approval.approve_human_approval_request(uuid,text,text,text)', 'execute')
     or has_function_privilege('service_role', 'human_approval.reject_human_approval_request(uuid,text,text,text)', 'execute')
     or has_function_privilege('service_role', 'human_approval.open_human_approval_session()', 'execute')
     or has_function_privilege('human_approval_reviewer', 'human_approval.decide_request(uuid,text,text,text,text)', 'execute')
     or not has_function_privilege('human_approval_agent', 'human_approval.request_memory_promotion(uuid,text,jsonb,timestamp with time zone,text)', 'execute')
     or not has_function_privilege('service_role', 'human_approval.request_memory_promotion(uuid,text,jsonb,timestamp with time zone,text)', 'execute')
     or not has_function_privilege('human_approval_reviewer', 'human_approval.approve_human_approval_request(uuid,text,text,text)', 'execute')
     or not has_function_privilege('human_approval_reviewer', 'human_approval.reject_human_approval_request(uuid,text,text,text)', 'execute')
     or not has_function_privilege('human_approval_reviewer', 'human_approval.open_human_approval_session()', 'execute') then
    raise exception 'human approval validation: execute grants do not match the proposal/authorization split';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'human_approval'
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where acl.privilege_type = 'EXECUTE'
      and acl.grantee::regrole::text in ('anon','authenticated','-')
  ) then
    raise exception 'human approval validation: public, anon, or authenticated can execute approval functions';
  end if;

  if exists (
    select 1
    from information_schema.role_table_grants
    where table_schema = 'human_approval'
      and grantee in ('PUBLIC','anon','authenticated','service_role','human_approval_agent','human_approval_reviewer')
  ) or exists (
    select 1
    from (values
      ('human_approval_agent'), ('human_approval_reviewer'), ('service_role'), ('anon'), ('authenticated')
    ) as roles(role_name)
    cross join (values
      ('human_approval.requests'), ('human_approval.receipts'), ('human_approval.sessions'),
      ('human_approval.trust_anchors'), ('human_approval.operations'), ('public.memories')
    ) as rels(relname)
    cross join (values ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE')) as privs(priv)
    where has_table_privilege(role_name, relname, priv)
  ) then
    raise exception 'human approval validation: a runtime role can mutate approval tables or memories directly';
  end if;

  insert into public.memories(content, workstream, owner, visibility, source_agent, source_kind, status)
  values
    ('human-approval-fixture: primary', 'fixture', 'example-user', 'shared', 'example-user-claude', 'agent', 'proposed'),
    ('human-approval-fixture: replay', 'fixture', 'example-user', 'shared', 'example-user-claude', 'agent', 'proposed'),
    ('human-approval-fixture: expire', 'fixture', 'example-user', 'shared', 'example-user-claude', 'agent', 'proposed'),
    ('human-approval-fixture: reject', 'fixture', 'example-user', 'shared', 'example-user-claude', 'agent', 'proposed'),
    ('human-approval-fixture: stale', 'fixture', 'example-user', 'shared', 'example-user-claude', 'agent', 'proposed'),
    ('human-approval-fixture: mismatch', 'fixture', 'example-user', 'shared', 'example-user-claude', 'agent', 'proposed'),
    ('human-approval-fixture: active', 'fixture', 'example-user', 'shared', 'example-user-claude', 'agent', 'active'),
    ('human-approval-fixture: unsupported', 'fixture', 'example-user', 'shared', 'example-user-claude', 'agent', 'proposed'),
    ('human-approval-fixture: service', 'fixture', 'example-user', 'shared', 'example-user-claude', 'agent', 'proposed');
  select id into v_primary_memory from public.memories where content = 'human-approval-fixture: primary';
  select id into v_replay_memory from public.memories where content = 'human-approval-fixture: replay';
  select id into v_expire_memory from public.memories where content = 'human-approval-fixture: expire';
  select id into v_reject_memory from public.memories where content = 'human-approval-fixture: reject';
  select id into v_stale_memory from public.memories where content = 'human-approval-fixture: stale';
  select id into v_mismatch_memory from public.memories where content = 'human-approval-fixture: mismatch';
  select id into v_active_memory from public.memories where content = 'human-approval-fixture: active';
  select id into v_unsupported_memory from public.memories where content = 'human-approval-fixture: unsupported';
  select id into v_service_memory from public.memories where content = 'human-approval-fixture: service';

  execute 'set session authorization human_approval_agent';
  begin
    update public.memories set status = 'active' where id = v_primary_memory;
    raise exception 'human approval validation: direct agent execution mutated a memory';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform human_approval.approve_human_approval_request(
      '00000000-0000-0000-0000-000000000000'::uuid, repeat('ab', 32), repeat('cd', 32), 'agent attempt');
    raise exception 'human approval validation: direct agent execution approved a request';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform human_approval.reject_human_approval_request(
      '00000000-0000-0000-0000-000000000000'::uuid, repeat('ab', 32), repeat('cd', 32), 'agent attempt');
    raise exception 'human approval validation: direct agent execution rejected a request';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform human_approval.open_human_approval_session();
    raise exception 'human approval validation: agent opened a human session';
  exception when insufficient_privilege then
    null;
  end;
  begin
    -- The authenticated superuser can still change session authorization.
    -- SET ROLE follows the current login, so an agent who is not a member of
    -- the reviewer role cannot assume it.
    execute 'set role human_approval_reviewer';
    raise exception 'human approval validation: agent assumed the reviewer login';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform set_config('human_approval.write', 'on', true);
    perform set_config('app.acting_principal', 'example-user', true);
    insert into human_approval.trust_anchors(authenticator_role, principal, assurance_level)
    values ('human_approval_agent', 'example-user', 'forged');
    raise exception 'human approval validation: agent inserted a trust anchor';
  exception when insufficient_privilege then
    null;
  end;

  v_primary_request := human_approval.request_memory_promotion(
    v_primary_memory, 'proposal reason', '[{"ref":"fixture:primary"}]'::jsonb,
    pg_catalog.clock_timestamp() + interval '2 hours', 'forged-human');
  v_replay_request := human_approval.request_memory_promotion(
    v_replay_memory, 'proposal reason', '[{"ref":"fixture:replay"}]'::jsonb,
    pg_catalog.clock_timestamp() + interval '2 hours', null);
  v_expire_request := human_approval.request_memory_promotion(
    v_expire_memory, 'proposal reason', '[{"ref":"fixture:expire"}]'::jsonb,
    pg_catalog.clock_timestamp() + interval '300 milliseconds', null);
  v_reject_request := human_approval.request_memory_promotion(
    v_reject_memory, 'proposal reason', '[{"ref":"fixture:reject"}]'::jsonb,
    pg_catalog.clock_timestamp() + interval '2 hours', 'forged-human');
  v_stale_request := human_approval.request_memory_promotion(
    v_stale_memory, 'proposal reason', '[{"ref":"fixture:stale"}]'::jsonb,
    pg_catalog.clock_timestamp() + interval '2 hours', null);
  v_mismatch_request := human_approval.request_memory_promotion(
    v_mismatch_memory, 'proposal reason', '[{"ref":"fixture:mismatch"}]'::jsonb,
    pg_catalog.clock_timestamp() + interval '2 hours', null);
  begin
    perform human_approval.request_memory_promotion(
      v_active_memory, 'proposal reason', '[{"ref":"fixture:active"}]'::jsonb,
      pg_catalog.clock_timestamp() + interval '1 hour', null);
    raise exception 'human approval validation: active memory was staged';
  exception when others then
    if sqlerrm <> 'human_approval: memory is not proposed' then
      raise exception 'human approval validation: active memory stage: %', sqlerrm;
    end if;
  end;
  if not exists (
    select 1 from human_approval.pending_human_approval_requests('memory_promotion')
    where request_id = v_primary_request
  ) then
    raise exception 'human approval validation: staged request is not pending';
  end if;
  execute 'reset session authorization';

  if (select status::text from public.memories where id = v_primary_memory) <> 'proposed'
     or exists (select 1 from human_approval.receipts)
     or exists (select 1 from human_approval.requests where target_id = v_active_memory) then
    raise exception 'human approval validation: staging left execution residue';
  end if;

  select expected_version, decision_nonce into v_primary_version, v_primary_nonce
  from human_approval.requests where id = v_primary_request;
  select expected_version, decision_nonce into v_replay_version, v_replay_nonce
  from human_approval.requests where id = v_replay_request;
  select expected_version, decision_nonce into v_expire_version, v_expire_nonce
  from human_approval.requests where id = v_expire_request;
  select expected_version, decision_nonce into v_reject_version, v_reject_nonce
  from human_approval.requests where id = v_reject_request;
  select expected_version, decision_nonce into v_stale_version, v_stale_nonce
  from human_approval.requests where id = v_stale_request;
  select expected_version, decision_nonce into v_mismatch_version, v_mismatch_nonce
  from human_approval.requests where id = v_mismatch_request;
  if (select proposer_session_user from human_approval.requests where id = v_primary_request) <> 'human_approval_agent'
     or (select proposer_label from human_approval.requests where id = v_primary_request) <> 'forged-human'
     or (select contract_version from human_approval.requests where id = v_primary_request) <> 'human-approval-request/0.1' then
    raise exception 'human approval validation: proposer was not bound to the agent login';
  end if;

  execute 'set session authorization service_role';
  begin
    perform human_approval.approve_human_approval_request(
      v_primary_request, v_primary_version, v_primary_nonce, 'service attempt');
    raise exception 'human approval validation: service_role approved a request';
  exception when insufficient_privilege then
    null;
  end;
  v_service_request := human_approval.request_memory_promotion(
    v_service_memory, 'service proposal', '[{"ref":"fixture:service"}]'::jsonb,
    pg_catalog.clock_timestamp() + interval '1 hour', 'example-user');
  execute 'reset session authorization';
  if (select proposer_session_user from human_approval.requests where id = v_service_request) <> 'service_role'
     or (select status::text from public.memories where id = v_service_memory) <> 'proposed' then
    raise exception 'human approval validation: service_role staging executed or mis-attributed the proposal';
  end if;

  perform set_config('app.acting_principal', 'example-user', true);
  begin
    perform human_approval.open_human_approval_session();
    raise exception 'human approval validation: unbound login opened a session';
  exception when others then
    if sqlerrm <> 'human_approval: current login is not a trusted human authenticator' then
      raise exception 'human approval validation: unbound open: %', sqlerrm;
    end if;
  end;
  begin
    perform human_approval.approve_human_approval_request(
      v_primary_request, v_primary_version, v_primary_nonce, 'forged principal');
    raise exception 'human approval validation: caller-supplied principal approved a request';
  exception when others then
    if sqlerrm <> 'human_approval: trusted human session required' then
      raise exception 'human approval validation: forged principal: %', sqlerrm;
    end if;
  end;
  if exists (select 1 from human_approval.sessions)
     or exists (select 1 from human_approval.receipts)
     or (select status::text from public.memories where id = v_primary_memory) <> 'proposed' then
    raise exception 'human approval validation: unauthorized principal left residue';
  end if;

  execute 'set session authorization human_approval_reviewer';
  begin
    perform human_approval.approve_human_approval_request(
      v_primary_request, v_primary_version, v_primary_nonce, 'no session yet');
    raise exception 'human approval validation: approval without a session succeeded';
  exception when others then
    if sqlerrm <> 'human_approval: trusted human session required' then
      raise exception 'human approval validation: missing session: %', sqlerrm;
    end if;
  end;
  perform human_approval.open_human_approval_session();
  perform human_approval.open_human_approval_session();
  execute 'reset session authorization';

  select count(*) into v_open_sessions
  from human_approval.sessions
  where closed_at is null and backend_pid = pg_backend_pid();
  if v_open_sessions <> 1 then
    raise exception 'human approval validation: expected one open session, found %', v_open_sessions;
  end if;
  select * into v_session
  from human_approval.sessions
  where closed_at is null and backend_pid = pg_backend_pid();
  if v_session.principal <> 'example-user'
     or v_session.assurance_level <> 'deployment-authenticated-human'
     or v_session.authenticator_role <> 'human_approval_reviewer'
     or v_session.principal = 'client-supplied-principal'
     or v_session.expires_at - v_session.opened_at < interval '14 minutes'
     or v_session.expires_at - v_session.opened_at > interval '16 minutes' then
    raise exception 'human approval validation: session was not derived from the trust anchor';
  end if;

  execute 'set session authorization human_approval_reviewer';
  begin
    perform human_approval.approve_human_approval_request(
      v_primary_request, v_primary_version, v_primary_nonce, 'atomic probe');
    raise exception 'rollback atomic probe';
  exception when others then
    if sqlerrm <> 'rollback atomic probe' then
      raise exception 'human approval validation: atomic probe: %', sqlerrm;
    end if;
  end;
  execute 'reset session authorization';
  if (select status::text from public.memories where id = v_primary_memory) <> 'proposed'
     or exists (select 1 from human_approval.receipts)
     or (select status from human_approval.requests where id = v_primary_request) <> 'pending'
     or exists (
       select 1 from public.audit_log
       where row_id = v_primary_memory and action = 'status_change'
     ) then
    raise exception 'human approval validation: rolled-back approval left residue';
  end if;

  perform set_config('app.acting_principal', 'forged-principal', true);
  execute 'set session authorization human_approval_reviewer';
  v_receipt := human_approval.approve_human_approval_request(
    v_primary_request, v_primary_version, v_primary_nonce, 'human approval reason');
  begin
    perform human_approval.approve_human_approval_request(
      v_primary_request, v_primary_version, v_primary_nonce, 'second approval');
    raise exception 'human approval validation: double approval succeeded';
  exception when others then
    if sqlerrm <> 'human_approval: already resolved' then
      raise exception 'human approval validation: double approval: %', sqlerrm;
    end if;
  end;
  begin
    perform human_approval.approve_human_approval_request(
      v_replay_request, v_replay_version, v_primary_nonce, 'replayed nonce');
    raise exception 'human approval validation: replay succeeded';
  exception when others then
    if sqlerrm <> 'human_approval: replay' then
      raise exception 'human approval validation: replay: %', sqlerrm;
    end if;
  end;
  v_wrong_version := repeat('c', 64);
  if v_wrong_version = v_mismatch_version then
    v_wrong_version := repeat('d', 64);
  end if;
  begin
    perform human_approval.approve_human_approval_request(
      v_mismatch_request, v_wrong_version, v_mismatch_nonce, 'wrong version');
    raise exception 'human approval validation: version mismatch succeeded';
  exception when others then
    if sqlerrm <> 'human_approval: version mismatch' then
      raise exception 'human approval validation: version mismatch: %', sqlerrm;
    end if;
  end;
  v_wrong_nonce := repeat('a', 64);
  if v_wrong_nonce in (v_reject_nonce, v_primary_nonce) then
    v_wrong_nonce := repeat('b', 64);
  end if;
  begin
    perform human_approval.reject_human_approval_request(
      v_reject_request, v_reject_version, v_wrong_nonce, 'wrong nonce');
    raise exception 'human approval validation: nonce mismatch succeeded';
  exception when others then
    if sqlerrm <> 'human_approval: decision nonce mismatch' then
      raise exception 'human approval validation: nonce mismatch: %', sqlerrm;
    end if;
  end;
  execute 'reset session authorization';

  select * into v_row from human_approval.receipts where id = v_receipt;
  select human_approval.memory_version(status::text, updated_at, content) into v_live_version
  from public.memories where id = v_primary_memory;
  if v_row.decision <> 'approved'
     or v_row.authorizer_principal <> 'example-user'
     or v_row.authorizer_assurance <> 'deployment-authenticated-human'
     or v_row.authorizer_role <> 'human_approval_reviewer'
     or v_row.proposer_session_user <> 'human_approval_agent'
     or v_row.proposer_label <> 'forged-human'
     or v_row.proposal_reason <> 'proposal reason'
     or v_row.decision_reason <> 'human approval reason'
     or v_row.evidence <> '[{"ref":"fixture:primary"}]'::jsonb
     or v_row.prior_state->>'status' <> 'proposed'
     or v_row.prior_state->>'version' <> v_primary_version
     or v_row.prior_state->>'target_mutated' <> 'false'
     or v_row.resulting_state->>'status' <> 'active'
     or v_row.resulting_state->>'version' <> v_live_version
     or v_row.resulting_state->>'target_mutated' <> 'true'
     or v_row.decision_nonce <> v_primary_nonce
     or v_row.decided_at is null
     or v_row.authorizer_principal = 'client-supplied-principal'
     or v_row.authorizer_principal = 'forged-principal'
     or (select resolved_at from human_approval.requests where id = v_primary_request) <> v_row.decided_at
     or (select receipt_id from human_approval.requests where id = v_primary_request) <> v_receipt
     or (select metadata->>'promoted_by' from public.memories where id = v_primary_memory) <> 'example-user'
     or (select metadata->>'promotion_assurance' from public.memories where id = v_primary_memory) <> 'deployment-authenticated-human'
     or (select metadata->>'promotion_receipt_id' from public.memories where id = v_primary_memory) <> v_receipt::text
     or (select count(*) from human_approval.receipts where request_id = v_primary_request) <> 1
     or (select status::text from public.memories where id = v_replay_memory) <> 'proposed'
     or (select status from human_approval.requests where id = v_replay_request) <> 'pending'
     or (select status from human_approval.requests where id = v_mismatch_request) <> 'pending'
     or (select status::text from public.memories where id = v_mismatch_memory) <> 'proposed' then
    raise exception 'human approval validation: approval receipt was not bound atomically to the session authorizer';
  end if;

  select updated_at, content into v_updated, v_content
  from public.memories where id = v_mismatch_memory;
  if v_updated is null then
    raise exception 'human approval validation: mismatch fixture disappeared';
  end if;

  update public.memories
  set content = content || ' edited'
  where id = v_stale_memory;
  select updated_at, content, status::text into v_updated, v_content, v_status
  from public.memories where id = v_stale_memory;
  execute 'set session authorization human_approval_reviewer';
  begin
    perform human_approval.approve_human_approval_request(
      v_stale_request, v_stale_version, v_stale_nonce, 'stale approval');
    raise exception 'human approval validation: stale target succeeded';
  exception when others then
    if sqlerrm <> 'human_approval: stale target' then
      raise exception 'human approval validation: stale target: %', sqlerrm;
    end if;
  end;
  execute 'reset session authorization';
  if (select status::text from public.memories where id = v_stale_memory) <> 'proposed'
     or (select content from public.memories where id = v_stale_memory) <> v_content
     or (select updated_at from public.memories where id = v_stale_memory) <> v_updated
     or (select status from human_approval.requests where id = v_stale_request) <> 'pending'
     or exists (select 1 from human_approval.receipts where request_id = v_stale_request) then
    raise exception 'human approval validation: stale target left residue';
  end if;

  perform pg_catalog.pg_sleep(0.5);
  execute 'set session authorization human_approval_reviewer';
  begin
    perform human_approval.approve_human_approval_request(
      v_expire_request, v_expire_version, v_expire_nonce, 'expired approval');
    raise exception 'human approval validation: expired approval succeeded';
  exception when others then
    if sqlerrm <> 'human_approval: expired' then
      raise exception 'human approval validation: expired approval: %', sqlerrm;
    end if;
  end;
  begin
    perform human_approval.reject_human_approval_request(
      v_expire_request, v_expire_version, v_expire_nonce, 'expired rejection');
    raise exception 'human approval validation: expired rejection succeeded';
  exception when others then
    if sqlerrm <> 'human_approval: expired' then
      raise exception 'human approval validation: expired rejection: %', sqlerrm;
    end if;
  end;
  v_reject_receipt := human_approval.reject_human_approval_request(
    v_reject_request, v_reject_version, v_reject_nonce, 'synthetic rejection reason');
  begin
    perform human_approval.reject_human_approval_request(
      v_reject_request, v_reject_version, v_reject_nonce, 'second rejection');
    raise exception 'human approval validation: double rejection succeeded';
  exception when others then
    if sqlerrm <> 'human_approval: already resolved' then
      raise exception 'human approval validation: double rejection: %', sqlerrm;
    end if;
  end;
  begin
    perform human_approval.approve_human_approval_request(
      '11111111-1111-1111-1111-111111111111'::uuid, repeat('ab', 32), repeat('cd', 32), 'missing');
    raise exception 'human approval validation: missing request succeeded';
  exception when others then
    if sqlerrm <> 'human_approval: missing request' then
      raise exception 'human approval validation: missing request: %', sqlerrm;
    end if;
  end;
  execute 'reset session authorization';

  select * into v_row from human_approval.receipts where id = v_reject_receipt;
  if v_row.decision <> 'rejected'
     or v_row.authorizer_principal <> 'example-user'
     or v_row.authorizer_assurance <> 'deployment-authenticated-human'
     or v_row.authorizer_role <> 'human_approval_reviewer'
     or v_row.proposer_session_user <> 'human_approval_agent'
     or v_row.decision_reason <> 'synthetic rejection reason'
     or v_row.proposal_reason <> 'proposal reason'
     or v_row.evidence <> '[{"ref":"fixture:reject"}]'::jsonb
     or v_row.prior_state <> v_row.resulting_state
     or v_row.resulting_state->>'status' <> 'proposed'
     or v_row.resulting_state->>'target_mutated' <> 'false'
     or v_row.decided_at is null
     or (select status::text from public.memories where id = v_reject_memory) <> 'proposed'
     or (select status from human_approval.requests where id = v_reject_request) <> 'rejected'
     or (select count(*) from human_approval.receipts where request_id = v_reject_request) <> 1 then
    raise exception 'human approval validation: rejection was not durably attributed';
  end if;
  if (select status from human_approval.requests where id = v_expire_request) <> 'pending'
     or (select status::text from public.memories where id = v_expire_memory) <> 'proposed'
     or exists (select 1 from human_approval.receipts where request_id = v_expire_request)
     or exists (
       select 1 from human_approval.pending_human_approval_requests(null)
       where request_id in (v_expire_request, v_primary_request, v_reject_request)
     ) then
    raise exception 'human approval validation: expiry or pending visibility is wrong';
  end if;

  perform set_config('human_approval.registry_write', 'on', true);
  insert into human_approval.operations(operation_kind, target_schema, target_table, description)
  values ('memory_supersession', 'public', 'memories', 'unimplemented envelope slot');
  v_unsupported_version := repeat('e', 64);
  v_unsupported_nonce := encode(extensions.gen_random_bytes(32), 'hex');
  perform set_config('human_approval.write', 'on', true);
  insert into human_approval.requests(
    operation_kind, target_schema, target_table, target_id, expected_version,
    expected_state, proposed_transition, proposer_session_user, reason, evidence,
    decision_nonce, expires_at
  ) values (
    'memory_supersession', 'public', 'memories', v_unsupported_memory,
    v_unsupported_version, '{"status":"proposed"}'::jsonb,
    '{"from_status":"proposed","to_status":"superseded"}'::jsonb,
    'client-supplied-proposer', 'unsupported proposal', '[{"ref":"fixture:unsupported"}]'::jsonb,
    v_unsupported_nonce, pg_catalog.clock_timestamp() + interval '1 hour'
  ) returning id into v_unsupported_request;
  if (select proposer_session_user from human_approval.requests where id = v_unsupported_request) <> session_user::text then
    raise exception 'human approval validation: direct proposal insert kept a client proposer';
  end if;
  execute 'set session authorization human_approval_reviewer';
  begin
    perform human_approval.approve_human_approval_request(
      v_unsupported_request, v_unsupported_version, v_unsupported_nonce, 'unsupported');
    raise exception 'human approval validation: unsupported operation succeeded';
  exception when others then
    if sqlerrm <> 'human_approval: unsupported operation' then
      raise exception 'human approval validation: unsupported operation: %', sqlerrm;
    end if;
  end;
  execute 'reset session authorization';
  if (select status::text from public.memories where id = v_unsupported_memory) <> 'proposed'
     or exists (select 1 from human_approval.receipts where request_id = v_unsupported_request) then
    raise exception 'human approval validation: unsupported operation left residue';
  end if;

  select count(*) into v_audit
  from public.audit_log
  where row_id = v_primary_memory and action = 'status_change';
  select count(*) into v_receipts from human_approval.receipts;
  if v_audit <> 1 or v_receipts <> 2 then
    raise exception 'human approval validation: expected one promotion audit row and two receipts, found audit % receipts %', v_audit, v_receipts;
  end if;

  begin
    update human_approval.receipts set decision_reason = 'rewritten';
    raise exception 'human approval validation: receipt update succeeded';
  exception when others then
    if sqlerrm <> 'human_approval: receipts are append-only' then
      raise exception 'human approval validation: receipt update: %', sqlerrm;
    end if;
  end;
  begin
    truncate human_approval.sessions;
    raise exception 'human approval validation: session truncate succeeded';
  exception when others then
    if sqlerrm <> 'human_approval: truncate is not permitted' then
      raise exception 'human approval validation: session truncate: %', sqlerrm;
    end if;
  end;
end $$;

rollback;
