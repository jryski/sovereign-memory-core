-- ============================================================================
-- SOVEREIGN MEMORY :: CANDIDATE SPAN CONTRACT VALIDATION
-- Target: local Postgres after sql/05_candidate_locators.sql and
-- sql/06_cutover_probe_categories.sql.
--
-- Proves one synthetic source item can yield two candidates with distinct
-- locators and manifest keys. The import candidate stores a short quote. The
-- hold candidate stores a locator and hash only. Addressed text is placed in
-- pg_temp.source_span_check_text for the write-time check and is not written
-- to source_items or source_manifest. The transaction rolls back.
-- ============================================================================

set search_path to public, extensions;

begin;

create temp table source_span_check_text (
  addressed_text text not null
) on commit drop;

do $$
declare
  v_agent text;
  v_system_id uuid;
  v_batch_id uuid;
  v_item_id uuid;
  v_import_id uuid;
  v_hold_id uuid;
  v_source text := U&'SYNTHETIC-SPAN-A: keep the boring schema. SYNTHETIC-SPAN-B: status is caf\00E9-hold.';
  v_quote_a text := 'keep the boring schema';
  v_quote_b text := U&'status is caf\00E9-hold';
  v_span_a jsonb;
  v_span_b jsonb;
  v_locator_a jsonb;
  v_locator_b jsonb;
  v_shifted jsonb;
  v_hash_a text;
  v_hash_b text;
  v_content_hash text;
  v_result jsonb;
  v_seen boolean;
  v_state text;
  v_candidates integer;
  v_items integer;
  v_keys integer;
  v_locators integer;
begin
  if public.source_locator_has_span('{"turn_start":1,"turn_end":2,"message_id":"example"}'::jsonb) then
    raise exception 'turn or message metadata was treated as a span';
  end if;
  if public.source_locator_has_span('{"character_start":0,"character_end":2,"span":{"unit":"codepoint","start":1,"end":3}}'::jsonb) then
    raise exception 'disagreeing span forms were accepted';
  end if;

  select agent_id into v_agent
  from trusted_agents
  where active and agent_id='system';
  if v_agent is null then
    raise exception 'candidate span fixture: system agent missing';
  end if;

  v_span_a := public.source_unique_quote_span(v_source, v_quote_a);
  v_span_b := public.source_unique_quote_span(v_source, v_quote_b);
  if (v_span_a->>'end')::integer + 1 > char_length(v_source) then
    raise exception 'fixture span has no room to demonstrate an in-range shift';
  end if;

  v_hash_a := public.source_quote_digest(v_quote_a, 'sha256', 'utf-8');
  v_hash_b := public.source_quote_digest(v_quote_b, 'sha256', 'utf-8');
  v_content_hash := public.source_quote_digest(v_source, 'sha256', 'utf-8');
  v_locator_a := jsonb_build_object(
    'scheme', 'fixture-text',
    'path', jsonb_build_array('synthetic', 'span-a'),
    'turn_start', 1,
    'turn_end', 1,
    'character_start', (v_span_a->>'start')::integer,
    'character_end', (v_span_a->>'end')::integer,
    'span', v_span_a
  );
  v_locator_b := jsonb_build_object(
    'scheme', 'fixture-text',
    'path', jsonb_build_array('synthetic', 'span-b'),
    'character_start', (v_span_b->>'start')::integer,
    'character_end', (v_span_b->>'end')::integer,
    'span', v_span_b
  );
  if v_locator_a = v_locator_b then
    raise exception 'fixture locators must differ before insert';
  end if;

  insert into source_span_check_text(addressed_text) values (v_source);

  insert into source_systems(source_key, display_name, source_type, adapter_name, adapter_version)
  values ('fixture-span-contract', 'Fixture Span Contract', 'other', 'fixture-adapter', '0.0.1')
  returning id into v_system_id;

  insert into source_import_batches(
    source_system_id, batch_key, source_item_count, exported_item_count, created_by
  ) values (
    v_system_id, 'fixture-span-batch', 1, 1, v_agent
  ) returning id into v_batch_id;

  insert into source_items(
    batch_id, source_item_key, source_container, source_kind, title,
    payload_hash, payload_size_bytes
  ) values (
    v_batch_id,
    'item-many-candidates',
    'fixture/synthetic-span',
    'note',
    'Synthetic span fixture',
    v_content_hash,
    octet_length(convert_to(v_source, 'UTF8'))
  ) returning id into v_item_id;

  insert into source_payload_evidence(
    source_item_id, evidence_kind, location, payload_hash, hash_algorithm, size_bytes, content_preview
  ) values (
    v_item_id, 'checksum', 'fixture://synthetic-span', v_content_hash, 'sha256',
    octet_length(convert_to(v_source, 'UTF8')), 'synthetic span fixture'
  );

  insert into source_manifest(
    source_item_id, manifest_key, source_locator, source_quote, source_quote_hash,
    source_quote_hash_algorithm, source_quote_hash_encoding, source_content_hash,
    action, target_zone, review_state, target_table, topic_key, suggested_summary
  ) values (
    v_item_id, 'span:alpha', v_locator_a, v_quote_a, v_hash_a,
    'sha256', 'utf-8', v_content_hash,
    'import', 'HOUSE', 'approved', 'memories', 'fixture/synthetic-span', 'Synthetic import span'
  ) returning id into v_import_id;

  insert into source_manifest(
    source_item_id, manifest_key, source_locator, source_quote, source_quote_hash,
    source_quote_hash_algorithm, source_quote_hash_encoding, source_content_hash,
    action, target_zone, review_state, topic_key, suggested_summary
  ) values (
    v_item_id, 'span:beta', v_locator_b, null, v_hash_b,
    'sha256', 'utf-8', v_content_hash,
    'hold', 'HOLD', 'unreviewed', 'fixture/synthetic-span', 'Synthetic hold span'
  ) returning id into v_hold_id;

  select count(*), count(distinct source_item_id), count(distinct manifest_key), count(distinct source_locator)
    into v_candidates, v_items, v_keys, v_locators
  from source_manifest
  where source_item_id = v_item_id;

  if v_candidates <> 2 or v_items <> 1 or v_keys <> 2 or v_locators <> 2 then
    raise exception 'expected one source item with two distinct candidates, got candidates % items % keys % locators %',
      v_candidates, v_items, v_keys, v_locators;
  end if;

  if not exists (
    select 1 from source_manifest
    where id = v_import_id
      and action = 'import'
      and source_quote = v_quote_a
      and char_length(source_quote) <= public.source_quote_max_chars()
      and public.source_locator_has_span(source_locator)
  ) then
    raise exception 'import candidate lost its short quote or span';
  end if;

  if not exists (
    select 1 from source_manifest
    where id = v_hold_id
      and action = 'hold'
      and source_quote is null
      and source_quote_hash = v_hash_b
      and public.source_locator_has_span(source_locator)
  ) then
    raise exception 'hold candidate should keep a locator and hash without a stored quote';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'source_manifest_review_queue'
      and column_name = 'source_quote'
  ) then
    raise exception 'review queue exposes source_quote';
  end if;

  if not exists (
    select 1 from source_manifest_review_queue
    where manifest_key = 'span:beta'
      and source_quote_stored is false
      and source_quote_hash = v_hash_b
  ) then
    raise exception 'hold candidate is missing from the locator review queue';
  end if;

  v_result := public.source_verify_stored_candidate(v_import_id, v_source);
  if v_result is null or v_result->>'posture' is distinct from 'match' or (v_result->>'ok')::boolean is distinct from true then
    raise exception 'import candidate verify failed: %', v_result;
  end if;

  v_result := public.source_verify_stored_candidate(v_hold_id, v_source);
  if v_result is null or v_result->>'posture' is distinct from 'match' or (v_result->>'ok')::boolean is distinct from true then
    raise exception 'hold candidate verify failed: %', v_result;
  end if;

  select state into v_state
  from source_readiness
  where batch_id = v_batch_id
    and check_key = 'candidate_locators_and_quote_hashes';
  if v_state is distinct from 'pass' then
    raise exception 'candidate locator readiness is %', v_state;
  end if;

  v_result := public.source_verify_candidate_span(
    v_source, v_locator_b, v_quote_b, v_hash_b, 'sha256', 'latin1', v_content_hash
  );
  if v_result->>'posture' is distinct from 'encoding_drift' then
    raise exception 'encoding drift posture was %', v_result;
  end if;

  v_result := public.source_verify_stored_candidate(v_import_id, v_source || ' tail');
  if v_result->>'posture' is distinct from 'source_changed' then
    raise exception 'addressed-text change posture was %', v_result;
  end if;

  v_shifted := jsonb_build_object(
    'scheme', 'fixture-text',
    'path', jsonb_build_array('synthetic', 'span-shifted'),
    'character_start', (v_span_a->>'start')::integer + 1,
    'character_end', (v_span_a->>'end')::integer + 1,
    'span', jsonb_build_object(
      'unit', 'codepoint',
      'start', (v_span_a->>'start')::integer + 1,
      'end', (v_span_a->>'end')::integer + 1
    )
  );
  v_result := public.source_verify_candidate_span(
    v_source, v_shifted, v_quote_a, v_hash_a, 'sha256', 'utf-8', v_content_hash
  );
  if v_result->>'posture' is distinct from 'offset_drift' then
    raise exception 'shifted span posture was %', v_result;
  end if;

  v_seen := false;
  begin
    insert into source_manifest(
      source_item_id, manifest_key, source_locator, source_quote, source_quote_hash,
      source_quote_hash_algorithm, source_quote_hash_encoding, source_content_hash,
      action, target_zone, review_state, target_table, topic_key, suggested_summary
    ) values (
      v_item_id, 'span:shifted', v_shifted, v_quote_a, v_hash_a,
      'sha256', 'utf-8', v_content_hash,
      'import', 'HOUSE', 'unreviewed', 'memories', 'fixture/synthetic-span', 'Shifted span'
    );
  exception when others then
    if sqlerrm like '%offset_drift%' then
      v_seen := true;
    else
      raise;
    end if;
  end;
  if not v_seen then
    raise exception 'shifted span was inserted';
  end if;

  v_seen := false;
  begin
    insert into source_manifest(
      source_item_id, manifest_key, source_locator, source_quote, source_quote_hash,
      source_quote_hash_algorithm, source_quote_hash_encoding, source_content_hash,
      action, target_zone, review_state, target_table, topic_key, suggested_summary
    ) values (
      v_item_id, 'span:bad-hash', v_locator_a, v_quote_a, repeat('0', 64),
      'sha256', 'utf-8', v_content_hash,
      'import', 'HOUSE', 'unreviewed', 'memories', 'fixture/synthetic-span', 'Bad hash'
    );
  exception when others then
    if sqlerrm like '%candidate quote hash mismatch%' then
      v_seen := true;
    else
      raise;
    end if;
  end;
  if not v_seen then
    raise exception 'quote hash mismatch was inserted';
  end if;

  v_seen := false;
  begin
    insert into source_manifest(
      source_item_id, manifest_key, source_locator, source_quote_hash,
      source_quote_hash_algorithm, source_quote_hash_encoding, source_content_hash,
      action, target_zone, review_state, target_table, topic_key, suggested_summary
    ) values (
      v_item_id, 'span:gap', '{}'::jsonb, v_hash_a,
      'sha256', 'utf-8', v_content_hash,
      'import', 'HOUSE', 'unreviewed', 'memories', 'fixture/synthetic-span', 'Missing span'
    );
  exception when others then
    if sqlerrm like '%candidate locator gap%' then
      v_seen := true;
    else
      raise;
    end if;
  end;
  if not v_seen then
    raise exception 'missing span was inserted';
  end if;

  v_seen := false;
  begin
    insert into source_manifest(
      source_item_id, manifest_key, source_locator, source_quote, source_quote_hash,
      source_quote_hash_algorithm, source_quote_hash_encoding,
      action, target_zone, review_state, target_table, topic_key, suggested_summary
    ) values (
      v_item_id, 'span:overlong',
      jsonb_build_object(
        'scheme', 'fixture-text',
        'character_start', 0,
        'character_end', 513,
        'span', jsonb_build_object('unit', 'codepoint', 'start', 0, 'end', 513)
      ),
      repeat('x', 513),
      public.source_quote_digest(repeat('x', 513), 'sha256', 'utf-8'),
      'sha256', 'utf-8',
      'import', 'HOUSE', 'unreviewed', 'memories', 'fixture/synthetic-span', 'Overlong quote'
    );
  exception when others then
    if sqlerrm like '%exceeds%characters%' then
      v_seen := true;
    else
      raise;
    end if;
  end;
  if not v_seen then
    raise exception 'overlong quote was inserted';
  end if;

  v_seen := false;
  begin
    perform public.source_unique_quote_span('ab SYNTHETIC ab', 'ab');
  exception when others then
    if sqlerrm like '%quote is ambiguous%' then
      v_seen := true;
    else
      raise;
    end if;
  end;
  if not v_seen then
    raise exception 'ambiguous quote was accepted';
  end if;

  v_seen := false;
  begin
    perform public.source_unique_quote_span(v_source, 'missing-token');
  exception when others then
    if sqlerrm like '%quote not found%' then
      v_seen := true;
    else
      raise;
    end if;
  end;
  if not v_seen then
    raise exception 'missing quote was accepted';
  end if;

  if (select count(*) from source_manifest where source_item_id = v_item_id) <> 2 then
    raise exception 'rejected candidates were stored';
  end if;

  raise notice 'candidate span contract passed';
end $$;

rollback;

do $$
begin
  if exists (select 1 from source_systems where source_key = 'fixture-span-contract') then
    raise exception 'candidate span fixture leaked source rows';
  end if;
end $$;
