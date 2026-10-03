-- Declared consequential-domain conformance. All fixture writes roll back.
-- Requires 01_core.sql, 03_provenance_guards.sql, 08_attention_events.sql
-- (for promote_memory), and 12_consequential_domains.sql.
--
-- Negative checks name the error text. A bare rejection can come from the
-- financial figure guard or from a broken review path and prove nothing
-- about this migration.
begin;

do $$
declare
  v_domain text;
  v_ws text;
  v_id uuid;
  v_agent uuid;
  v_human uuid;
  v_successor uuid;
  v_result text;
  v_status knowledge_status;
  v_kind source_kind;
  v_stored text;
  v_checks integer := 0;
  v_sourced jsonb := '{"basis":"source_document","source_citation":"synthetic-record-001"}'::jsonb;
begin
  if to_regprocedure('public.promote_memory(uuid,text,text)') is null then
    raise exception 'legitimate-path check requires public.promote_memory(uuid,text,text)';
  end if;
  if (select count(*) from consequential_domains
      where domain in ('financial','legal','medical','identity')
        and citation_required
        and allowed_basis @> array['human_direct','decision_record','imported_artifact','source_document']::text[]) <> 4 then
    raise exception 'financial, legal, medical, and identity baselines are not declared';
  end if;
  v_checks := v_checks + 1;

  if not has_table_privilege('service_role', 'public.consequential_domains', 'SELECT')
     or not has_table_privilege('service_role', 'public.consequential_domain_bindings', 'SELECT')
     or not has_function_privilege('service_role', 'public.enforce_consequential_domain()', 'EXECUTE') then
    raise exception 'service_role cannot evaluate declared domains while writing';
  end if;
  if has_table_privilege('service_role', 'public.consequential_domains', 'INSERT')
     or has_table_privilege('service_role', 'public.consequential_domains', 'UPDATE')
     or has_table_privilege('service_role', 'public.consequential_domains', 'DELETE')
     or has_table_privilege('service_role', 'public.consequential_domain_bindings', 'INSERT')
     or has_table_privilege('service_role', 'public.consequential_domain_bindings', 'UPDATE')
     or has_table_privilege('service_role', 'public.consequential_domain_bindings', 'DELETE') then
    raise exception 'service_role can edit consequential domain declarations';
  end if;
  if has_function_privilege('anon', 'public.enforce_consequential_domain()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.enforce_consequential_domain()', 'EXECUTE') then
    raise exception 'anon or authenticated can execute the domain guard';
  end if;
  v_checks := v_checks + 1;

  -- Additional domains are inserts. The baseline is not a closed enum.
  insert into consequential_domains(domain, allowed_basis, citation_required, rationale)
  values ('safety',
          array['human_direct','decision_record','imported_artifact','source_document'],
          true,
          'Synthetic additional domain declared for the conformance fixture.');
  v_checks := v_checks + 1;

  begin
    insert into consequential_domains(domain, allowed_basis, citation_required, rationale)
    values ('widened', array['agent_summary'], true, 'Synthetic widened basis that must fail.');
    raise exception 'agent basis was accepted into a declared domain';
  exception when check_violation then
    v_checks := v_checks + 1;
  end;

  -- Inverse control. Unclassified writes still succeed, including the existing
  -- financial-figure paths. If every insert failed, the negative sections
  -- below would go green without proving this guard.
  insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status)
  values ('Synthetic ordinary note about a lunch preference.',
          'synthetic-ordinary', 'example-user', 'private', 'example-user-claude', 'agent', 'proposed')
  returning id into v_id;
  if v_id is null then
    raise exception 'ordinary agent proposal was rejected';
  end if;
  v_result := promote_memory(v_id, 'synthetic ordinary review', 'example-user');
  if v_result <> 'promoted' then
    raise exception 'ordinary agent proposal was not promoted: %', v_result;
  end if;
  select status, source_kind, consequential_domain
    into v_status, v_kind, v_stored
  from memories where id = v_id;
  if v_status <> 'active' or v_kind <> 'agent' or v_stored is not null then
    raise exception 'ordinary promotion changed review or classification: % % %', v_status, v_kind, v_stored;
  end if;
  v_checks := v_checks + 1;

  insert into memories(content, owner, visibility, source_agent, source_kind, confidence, metadata)
  values ('Ballpark is around $5k', 'shared', 'shared', 'system', 'agent', 0.5,
          '{"financial_unverified":true}'::jsonb);
  v_checks := v_checks + 1;

  begin
    insert into memories(content, owner, visibility, source_agent, source_kind)
    values ('Quote came in at $4,200', 'shared', 'shared', 'system', 'human');
    raise exception 'unsourced financial figure was accepted';
  exception when raise_exception then
    if sqlerrm = 'unsourced financial figure was accepted' then
      raise;
    end if;
    if position('FINANCIAL PROVENANCE REQUIRED' in sqlerrm) = 0 then
      raise exception 'unsourced financial figure rejected for the wrong reason: %', sqlerrm;
    end if;
  end;
  v_checks := v_checks + 1;

  insert into memories(content, owner, visibility, source_agent, source_kind, metadata)
  values ('Quote came in at $4,200', 'shared', 'shared', 'system', 'human',
          '{"basis":"source_document","source_citation":"synthetic-quote-001"}'::jsonb);
  v_checks := v_checks + 1;

  -- Unsourced declared facts. Content has no monetary figure, so the financial
  -- figure guard would accept these. The domain guard must be the one that refuses.
  foreach v_domain in array array['financial','legal','medical','identity','safety'] loop
    v_ws := 'synthetic-' || v_domain;
    insert into consequential_domain_bindings(relation_name, workstream, domain)
    values ('memories', v_ws, v_domain);
    begin
      insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status, metadata)
      values ('Synthetic ' || v_domain || ' claim with no measured quantity.',
              v_ws, 'example-user', 'private', 'example-user-claude', 'human', 'active', '{}'::jsonb);
      raise exception 'unsourced % fact was accepted', v_domain;
    exception when raise_exception then
      if sqlerrm = format('unsourced %s fact was accepted', v_domain) then
        raise;
      end if;
      if position('unsourced consequential fact' in sqlerrm) = 0
         or position(v_domain in sqlerrm) = 0 then
        raise exception 'unsourced % fact rejected for the wrong reason: %', v_domain, sqlerrm;
      end if;
    end;

    begin
      insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status, metadata)
      values ('Synthetic ' || v_domain || ' claim citing a placeholder.',
              v_ws, 'example-user', 'private', 'example-user-claude', 'manual', 'proposed',
              '{"basis":"human_direct","source_citation":"source"}'::jsonb);
      raise exception 'placeholder citation for % was accepted', v_domain;
    exception when raise_exception then
      if sqlerrm = format('placeholder citation for %s was accepted', v_domain) then
        raise;
      end if;
      if position('unsourced consequential fact' in sqlerrm) = 0
         or position('source_citation' in sqlerrm) = 0 then
        raise exception 'placeholder citation for % rejected for the wrong reason: %', v_domain, sqlerrm;
      end if;
    end;
    v_checks := v_checks + 1;
  end loop;

  begin
    insert into memories(content, workstream, owner, visibility, source_agent, source_kind, confidence, metadata)
    values ('Ballpark is around $5k', 'synthetic-financial', 'example-user', 'private',
            'example-user-claude', 'human', 0.5, '{"financial_unverified":true}'::jsonb);
    raise exception 'financial_unverified bypassed a declared financial domain';
  exception when raise_exception then
    if sqlerrm = 'financial_unverified bypassed a declared financial domain' then
      raise;
    end if;
    if position('unsourced consequential fact' in sqlerrm) = 0
       or position('financial' in sqlerrm) = 0 then
      raise exception 'declared unverified financial row rejected for the wrong reason: %', sqlerrm;
    end if;
  end;
  v_checks := v_checks + 1;

  insert into consequential_domain_bindings(relation_name, workstream, domain)
  values ('wiki_pages', 'synthetic-legal', 'legal');
  begin
    insert into wiki_pages(path, title, content, workstream, owner, visibility, source_agent, source_kind, status, frontmatter)
    values ('synthetic/consequential-legal-unsourced', 'Synthetic legal page',
            'Synthetic legal clause with no measured quantity.',
            'synthetic-legal', 'shared', 'shared', 'system', 'human', 'active', '{}'::jsonb);
    raise exception 'unsourced legal wiki page was accepted';
  exception when raise_exception then
    if sqlerrm = 'unsourced legal wiki page was accepted' then
      raise;
    end if;
    if position('unsourced consequential fact' in sqlerrm) = 0
       or position('wiki_pages' in sqlerrm) = 0 then
      raise exception 'unsourced legal wiki page rejected for the wrong reason: %', sqlerrm;
    end if;
  end;
  v_checks := v_checks + 1;

  -- Agent-authored declared facts, including proposed rows and remember().
  foreach v_domain in array array['financial','legal','medical','identity'] loop
    v_ws := 'synthetic-' || v_domain;
    begin
      insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status, metadata)
      values ('Synthetic sourced ' || v_domain || ' claim.',
              v_ws, 'example-user', 'private', 'example-user-claude', 'agent', 'proposed', v_sourced);
      raise exception 'agent-authored proposed % fact was accepted', v_domain;
    exception when raise_exception then
      if sqlerrm = format('agent-authored proposed %s fact was accepted', v_domain) then
        raise;
      end if;
      if position('agent-authored consequential fact' in sqlerrm) = 0
         or position(v_domain in sqlerrm) = 0 then
        raise exception 'agent-authored % fact rejected for the wrong reason: %', v_domain, sqlerrm;
      end if;
    end;
    v_checks := v_checks + 1;
  end loop;

  begin
    perform remember(
      'Synthetic sourced medical claim from the agent write path.',
      'synthetic-medical',
      null,
      'example-user-claude',
      'example-user'
    );
    raise exception 'remember() wrote a declared medical fact';
  exception when raise_exception then
    if sqlerrm = 'remember() wrote a declared medical fact' then
      raise;
    end if;
    if position('agent-authored consequential fact' in sqlerrm) = 0
       or position('medical' in sqlerrm) = 0 then
      raise exception 'remember() rejected a medical fact for the wrong reason: %', sqlerrm;
    end if;
  end;
  v_checks := v_checks + 1;

  begin
    insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status, metadata)
    values ('Synthetic sourced medical claim entered as active.',
            'synthetic-medical', 'example-user', 'private', 'example-user-claude', 'agent', 'active',
            v_sourced);
    raise exception 'agent-authored active medical fact was accepted';
  exception when raise_exception then
    if sqlerrm = 'agent-authored active medical fact was accepted' then
      raise;
    end if;
    if position('agent-authored consequential fact' in sqlerrm) = 0 then
      raise exception 'active agent medical fact rejected for the wrong reason: %', sqlerrm;
    end if;
  end;
  v_checks := v_checks + 1;

  begin
    insert into wiki_pages(path, title, content, workstream, owner, visibility, source_agent, source_kind, status, frontmatter)
    values ('synthetic/consequential-legal-agent', 'Synthetic legal page',
            'Synthetic sourced legal clause.',
            'synthetic-legal', 'shared', 'shared', 'system', 'agent', 'proposed', v_sourced);
    raise exception 'agent-authored legal wiki page was accepted';
  exception when raise_exception then
    if sqlerrm = 'agent-authored legal wiki page was accepted' then
      raise;
    end if;
    if position('agent-authored consequential fact' in sqlerrm) = 0
       or position('wiki_pages' in sqlerrm) = 0 then
      raise exception 'agent legal wiki page rejected for the wrong reason: %', sqlerrm;
    end if;
  end;
  v_checks := v_checks + 1;

  -- Legitimate review path. promote_memory leaves source_kind unchanged.
  -- A guard keyed on "agent and status is not proposed" fails this section.
  insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status, metadata)
  values ('Synthetic medical claim recorded from a source document.',
          'synthetic-medical', 'example-user', 'private', 'example-user-claude', 'human', 'proposed', v_sourced)
  returning id into v_human;
  select consequential_domain into v_stored from memories where id = v_human;
  if v_stored <> 'medical' then
    raise exception 'human medical proposal was not classified as medical';
  end if;
  v_result := promote_memory(v_human, 'synthetic human review', 'example-user');
  if v_result <> 'promoted' then
    raise exception 'human medical proposal was not promoted: %', v_result;
  end if;
  select status, source_kind, consequential_domain, metadata->>'source_citation'
    into v_status, v_kind, v_stored, v_result
  from memories where id = v_human;
  if v_status <> 'active' or v_kind <> 'human' or v_stored <> 'medical' or v_result <> 'synthetic-record-001' then
    raise exception 'human promotion did not keep review and provenance: % % % %', v_status, v_kind, v_stored, v_result;
  end if;
  v_checks := v_checks + 1;

  insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status, metadata)
  values ('Quoted fee is $12 on the synthetic invoice.',
          'synthetic-financial', 'shared', 'shared', 'system', 'manual', 'active',
          '{"basis":"imported_artifact","source_citation":"synthetic-invoice-001"}'::jsonb)
  returning id into v_id;
  if not exists (
    select 1 from memories
    where id = v_id and status = 'active' and consequential_domain = 'financial' and source_kind = 'manual'
  ) then
    raise exception 'sourced manual financial row was not stored';
  end if;
  v_checks := v_checks + 1;

  insert into wiki_pages(path, title, content, workstream, owner, visibility, source_agent, source_kind, status, frontmatter)
  values ('synthetic/consequential-legal-human', 'Synthetic legal page',
          'Synthetic legal clause recorded from a source document.',
          'synthetic-legal', 'shared', 'shared', 'system', 'human', 'active', v_sourced)
  returning id into v_id;
  if not exists (
    select 1 from wiki_pages
    where id = v_id and consequential_domain = 'legal' and source_kind = 'human' and status = 'active'
  ) then
    raise exception 'sourced human legal wiki page was not stored';
  end if;
  v_checks := v_checks + 1;

  -- Late binding must not let an already proposed agent row become active,
  -- and must not block a human proposal in that same workstream.
  insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status, metadata)
  values ('Synthetic identity claim waiting unbound.',
          'synthetic-late', 'example-user', 'private', 'example-user-claude', 'agent', 'proposed', v_sourced)
  returning id into v_agent;
  insert into consequential_domain_bindings(relation_name, workstream, domain)
  values ('memories', 'synthetic-late', 'identity');
  begin
    v_result := promote_memory(v_agent, 'synthetic late review', 'example-user');
    raise exception 'agent identity proposal was promoted after binding: %', v_result;
  exception when raise_exception then
    if position('agent identity proposal was promoted after binding' in sqlerrm) > 0 then
      raise;
    end if;
    if position('agent-authored consequential fact' in sqlerrm) = 0
       or position('identity' in sqlerrm) = 0 then
      raise exception 'late-bound agent promotion rejected for the wrong reason: %', sqlerrm;
    end if;
  end;
  if not exists (
    select 1 from memories where id = v_agent and status = 'proposed' and source_kind = 'agent'
  ) then
    raise exception 'rejected agent promotion did not leave the proposal in review';
  end if;
  begin
    update memories
    set status = 'active', source_kind = 'human'
    where id = v_agent and status = 'proposed';
    raise exception 'agent identity row was relabeled human and activated';
  exception when raise_exception then
    if sqlerrm = 'agent identity row was relabeled human and activated' then
      raise;
    end if;
    if position('agent-authored consequential fact' in sqlerrm) = 0 then
      raise exception 'agent relabel rejected for the wrong reason: %', sqlerrm;
    end if;
  end;
  insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status, metadata)
  values ('Synthetic identity claim recorded by a person.',
          'synthetic-late', 'example-user', 'private', 'example-user-claude', 'human', 'proposed', v_sourced)
  returning id into v_human;
  v_result := promote_memory(v_human, 'synthetic late human review', 'example-user');
  if v_result <> 'promoted' then
    raise exception 'human identity proposal was blocked by the agent rejection: %', v_result;
  end if;
  v_checks := v_checks + 1;

  -- Direct service-role writes still reach the guard, and human promotion
  -- through the definer function still works for that role.
  execute 'grant select, insert, update on memories, wiki_pages to service_role';
  execute 'set local role service_role';
  insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status)
  values ('Synthetic ordinary service-role proposal.',
          'synthetic-ordinary-role', 'example-user', 'private', 'example-user-claude', 'manual', 'proposed')
  returning id into v_id;
  v_result := promote_memory(v_id, 'synthetic service-role review', 'example-user');
  if v_result <> 'promoted' then
    raise exception 'service_role could not promote an ordinary proposal: %', v_result;
  end if;
  begin
    insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status, metadata)
    values ('Synthetic sourced identity claim from service_role.',
            'synthetic-identity', 'example-user', 'private', 'example-user-claude', 'agent', 'proposed', v_sourced);
    raise exception 'service_role agent identity write was accepted';
  exception when raise_exception then
    if sqlerrm = 'service_role agent identity write was accepted' then
      raise;
    end if;
    if position('agent-authored consequential fact' in sqlerrm) = 0 then
      raise exception 'service_role agent write rejected for the wrong reason: %', sqlerrm;
    end if;
  end;
  execute 'reset role';
  v_checks := v_checks + 1;

  -- Corrections. supersede_memory stamps source_kind=agent and must not create
  -- an active consequential successor. A human-authored successor still can.
  select id into v_human
  from memories
  where consequential_domain = 'medical' and source_kind = 'human' and status = 'active'
  order by created_at desc
  limit 1;
  begin
    perform supersede_memory(v_human, 'Synthetic corrected medical claim.', 'example-user-claude');
    raise exception 'supersede_memory wrote an agent medical successor';
  exception when raise_exception then
    if sqlerrm = 'supersede_memory wrote an agent medical successor' then
      raise;
    end if;
    if position('agent-authored consequential fact' in sqlerrm) = 0 then
      raise exception 'supersede_memory rejected for the wrong reason: %', sqlerrm;
    end if;
  end;
  if not exists (select 1 from memories where id = v_human and status = 'active') then
    raise exception 'failed supersede_memory changed the predecessor';
  end if;
  insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status, supersedes, metadata)
  values ('Synthetic corrected medical claim recorded by a person.',
          'synthetic-medical', 'example-user', 'private', 'example-user-claude', 'human', 'active', v_human, v_sourced)
  returning id into v_successor;
  if not exists (
    select 1 from memories
    where id = v_successor and consequential_domain = 'medical' and source_kind = 'human' and supersedes = v_human
  ) then
    raise exception 'human medical successor did not inherit classification';
  end if;
  update memories set status = 'superseded' where id = v_human and status = 'active';
  if not exists (select 1 from memories where id = v_human and status = 'superseded') then
    raise exception 'human predecessor could not be marked superseded';
  end if;
  v_checks := v_checks + 1;

  -- Row declaration, conflict, and the no-clear ratchet.
  insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status,
                       consequential_domain, metadata)
  values ('Synthetic row-declared medical claim.',
          'synthetic-unbound', 'example-user', 'private', 'example-user-claude', 'human', 'active',
          'medical', v_sourced)
  returning id into v_id;
  begin
    update memories set consequential_domain = null where id = v_id;
    raise exception 'declared domain was cleared';
  exception when raise_exception then
    if sqlerrm = 'declared domain was cleared' then
      raise;
    end if;
    if position('not editable once set' in sqlerrm) = 0 then
      raise exception 'domain clear rejected for the wrong reason: %', sqlerrm;
    end if;
  end;
  begin
    update memories set metadata = metadata - 'source_citation' where id = v_id;
    raise exception 'citation was removed from a declared row';
  exception when raise_exception then
    if sqlerrm = 'citation was removed from a declared row' then
      raise;
    end if;
    if position('unsourced consequential fact' in sqlerrm) = 0 then
      raise exception 'citation removal rejected for the wrong reason: %', sqlerrm;
    end if;
  end;
  v_checks := v_checks + 1;

  begin
    insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status,
                         consequential_domain, metadata)
    values ('Synthetic conflicting domain claim.',
            'synthetic-medical', 'example-user', 'private', 'example-user-claude', 'human', 'active',
            'legal', v_sourced);
    raise exception 'domain conflict was accepted';
  exception when raise_exception then
    if sqlerrm = 'domain conflict was accepted' then
      raise;
    end if;
    if position('consequential domain conflict' in sqlerrm) = 0 then
      raise exception 'domain conflict rejected for the wrong reason: %', sqlerrm;
    end if;
  end;
  v_checks := v_checks + 1;

  begin
    insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status,
                         consequential_domain, metadata)
    values ('Synthetic undeclared domain claim.',
            'synthetic-unbound-missing', 'example-user', 'private', 'example-user-claude', 'human', 'active',
            'not_declared', v_sourced);
    raise exception 'undeclared domain was accepted';
  exception when raise_exception then
    if sqlerrm = 'undeclared domain was accepted' then
      raise;
    end if;
    if position('not declared in consequential_domains' in sqlerrm) = 0 then
      raise exception 'undeclared domain rejected for the wrong reason: %', sqlerrm;
    end if;
  end;
  v_checks := v_checks + 1;

  -- Limit: prose is not classified. This sentence is medical in meaning and
  -- financial in nothing the figure guard matches, and no domain was declared.
  insert into memories(content, workstream, owner, visibility, source_agent, source_kind, status)
  values ('Synthetic clinic note with a positive screening and no declaration.',
          'synthetic-unclassified', 'example-user', 'private', 'example-user-claude', 'agent', 'active')
  returning id into v_id;
  if not exists (
    select 1 from memories where id = v_id and consequential_domain is null and status = 'active' and source_kind = 'agent'
  ) then
    raise exception 'unclassified prose was treated as a declared domain';
  end if;
  v_checks := v_checks + 1;

  if v_checks < 20 then
    raise exception 'consequential domain conformance ended early at % checks', v_checks;
  end if;
  raise notice 'consequential-domain conformance passed (% checks)', v_checks;
end $$;

rollback;
