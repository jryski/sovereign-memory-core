-- ============================================================================
-- SOVEREIGN MEMORY :: CANDIDATE SOURCE LOCATORS + QUOTE HASHES
-- Target: Postgres 15+ / Supabase. Run after sql/04_source_import.sql.
--
-- Purpose:
--   Harden source_manifest so every import/HOLD candidate can be verified
--   against the span that produced it.
--
-- Span contract (source-type neutral):
--   source_locator is a JSON object. A span is a half-open code-point range
--   [start, end) expressed either as span.unit = codepoint with span.start
--   and span.end, or as character_start and character_end. When both forms
--   are present they are equal. Optional path, scheme, message_id,
--   message_index, turn, turn_start, and turn_end keys are adapter metadata.
--   They do not identify a span by themselves.
--
--   source_quote is an optional excerpt of at most source_quote_max_chars()
--   characters. source_quote_hash is lowercase SHA-256 hex of that span under
--   source_quote_hash_encoding (utf-8). source_content_hash, when present, is
--   lowercase SHA-256 hex of the UTF-8 addressed text: the text the offsets
--   index. It is distinct from source_items.payload_hash, which hashes the
--   preserved container.
--
-- Write-time check:
--   Import and hold rows require a span and a SHA-256 quote hash. A stored
--   quote must match that hash, and the span width must match the quote.
--   When the transaction has created pg_temp.source_span_check_text
--   (addressed_text text) with one row, the trigger also checks the span
--   against that text. The temp table is the caller's verification input.
--   It is dropped at commit and is not a copy of the source body.
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

alter table source_manifest
  add column if not exists source_locator jsonb not null default '{}',
  add column if not exists source_quote text,
  add column if not exists source_quote_hash text,
  add column if not exists source_quote_hash_algorithm text not null default 'sha256',
  add column if not exists source_quote_hash_encoding text not null default 'utf-8',
  add column if not exists source_content_hash text;

create or replace function public.source_quote_max_chars()
returns integer
language sql
immutable
set search_path to 'public'
as $$ select 512 $$;

create or replace function public.source_quote_pg_encoding(p_encoding text)
returns text
language sql
immutable
set search_path to 'public'
as $$
  select case lower(trim(coalesce(p_encoding, 'utf-8')))
    when 'utf-8' then 'UTF8'
    when 'utf8' then 'UTF8'
    when 'latin1' then 'LATIN1'
    when 'iso-8859-1' then 'LATIN1'
    else null
  end
$$;

create or replace function public.source_locator_codepoint_span(p_locator jsonb)
returns integer[]
language plpgsql
immutable
set search_path to 'public'
as $$
declare
  v_span integer[];
  v_char integer[];
  v_start integer;
  v_end integer;
begin
  if p_locator is null or jsonb_typeof(p_locator) <> 'object' then
    return null;
  end if;

  if p_locator ? 'span' then
    if jsonb_typeof(p_locator->'span') <> 'object'
       or coalesce(p_locator->'span'->>'unit', 'codepoint') <> 'codepoint'
       or coalesce(p_locator->'span'->>'start', '') !~ '^[0-9]{1,9}$'
       or coalesce(p_locator->'span'->>'end', '') !~ '^[0-9]{1,9}$' then
      return null;
    end if;
    v_start := (p_locator->'span'->>'start')::integer;
    v_end := (p_locator->'span'->>'end')::integer;
    if v_end <= v_start then
      return null;
    end if;
    v_span := array[v_start, v_end];
  end if;

  if p_locator ? 'character_start' or p_locator ? 'character_end' then
    if coalesce(p_locator->>'character_start', '') !~ '^[0-9]{1,9}$'
       or coalesce(p_locator->>'character_end', '') !~ '^[0-9]{1,9}$' then
      return null;
    end if;
    v_start := (p_locator->>'character_start')::integer;
    v_end := (p_locator->>'character_end')::integer;
    if v_end <= v_start then
      return null;
    end if;
    v_char := array[v_start, v_end];
  end if;

  if v_span is not null and v_char is not null
     and (v_span[1] <> v_char[1] or v_span[2] <> v_char[2]) then
    return null;
  end if;

  return coalesce(v_span, v_char);
end;
$$;

create or replace function public.source_locator_has_span(p_locator jsonb)
returns boolean
language sql
immutable
set search_path to 'public'
as $$
  select public.source_locator_codepoint_span(p_locator) is not null
$$;

create or replace function public.source_quote_digest(
  p_quote text,
  p_algorithm text,
  p_encoding text
) returns text
language plpgsql
immutable
set search_path to 'public'
as $$
declare
  v_encoding text;
begin
  if p_quote is null then
    raise exception 'source_quote_digest: quote is null';
  end if;
  if lower(trim(coalesce(p_algorithm, ''))) <> 'sha256' then
    raise exception 'source_quote_digest: unsupported algorithm %', p_algorithm;
  end if;
  v_encoding := public.source_quote_pg_encoding(p_encoding);
  if v_encoding is null then
    raise exception 'source_quote_digest: unsupported encoding %', p_encoding;
  end if;
  return encode(extensions.digest(convert_to(p_quote, v_encoding), 'sha256'), 'hex');
end;
$$;

create or replace function public.source_unique_quote_span(
  p_source text,
  p_quote text
) returns jsonb
language plpgsql
immutable
set search_path to 'public'
as $$
declare
  v_first integer;
begin
  if p_source is null or p_quote is null or char_length(p_quote) = 0 then
    raise exception 'source_unique_quote_span: quote is empty';
  end if;
  if char_length(p_quote) > public.source_quote_max_chars() then
    raise exception 'source_unique_quote_span: quote exceeds % characters', public.source_quote_max_chars();
  end if;

  v_first := position(p_quote in p_source);
  if v_first = 0 then
    raise exception 'source_unique_quote_span: quote not found';
  end if;
  if position(p_quote in substring(p_source from v_first + 1)) > 0 then
    raise exception 'source_unique_quote_span: quote is ambiguous';
  end if;

  return jsonb_build_object(
    'start', v_first - 1,
    'end', v_first - 1 + char_length(p_quote),
    'unit', 'codepoint'
  );
end;
$$;

create or replace function public.source_verify_candidate_span(
  p_source text,
  p_locator jsonb,
  p_quote text,
  p_quote_hash text,
  p_algorithm text,
  p_encoding text,
  p_content_hash text
) returns jsonb
language plpgsql
immutable
set search_path to 'public'
as $$
declare
  v_bounds integer[];
  v_extracted text;
  v_declared text;
  v_utf8 text;
  v_encoding text;
begin
  if p_quote is not null and char_length(p_quote) > public.source_quote_max_chars() then
    return jsonb_build_object('ok', false, 'posture', 'quote_too_long');
  end if;
  if lower(trim(coalesce(p_algorithm, ''))) <> 'sha256' then
    return jsonb_build_object('ok', false, 'posture', 'unsupported_algorithm');
  end if;
  if p_quote_hash is null or p_quote_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'posture', 'hash_mismatch');
  end if;

  v_encoding := coalesce(nullif(trim(p_encoding), ''), 'utf-8');
  if public.source_quote_pg_encoding(v_encoding) is null then
    return jsonb_build_object('ok', false, 'posture', 'unsupported_encoding');
  end if;
  if p_source is null or not public.source_locator_has_span(p_locator) then
    return jsonb_build_object('ok', false, 'posture', 'span_missing');
  end if;

  v_bounds := public.source_locator_codepoint_span(p_locator);
  if v_bounds[2] > char_length(p_source) then
    return jsonb_build_object('ok', false, 'posture', 'offset_drift');
  end if;
  v_extracted := substring(p_source from v_bounds[1] + 1 for v_bounds[2] - v_bounds[1]);

  begin
    v_declared := public.source_quote_digest(v_extracted, 'sha256', v_encoding);
  exception
    when untranslatable_character or character_not_in_repertoire then
      return jsonb_build_object('ok', false, 'posture', 'encoding_drift');
  end;

  if v_declared is distinct from p_quote_hash then
    if lower(trim(v_encoding)) not in ('utf-8', 'utf8') then
      v_utf8 := public.source_quote_digest(v_extracted, 'sha256', 'utf-8');
      if v_utf8 = p_quote_hash then
        return jsonb_build_object('ok', false, 'posture', 'encoding_drift');
      end if;
    end if;
    return jsonb_build_object('ok', false, 'posture', 'offset_drift');
  end if;

  if p_quote is not null and p_quote is distinct from v_extracted then
    return jsonb_build_object('ok', false, 'posture', 'quote_mismatch');
  end if;

  if p_content_hash is not null
     and (
       p_content_hash !~ '^[0-9a-f]{64}$'
       or public.source_quote_digest(p_source, 'sha256', 'utf-8') is distinct from p_content_hash
     ) then
    return jsonb_build_object('ok', false, 'posture', 'source_changed');
  end if;

  return jsonb_build_object('ok', true, 'posture', 'match');
end;
$$;

create or replace function public.source_verify_stored_candidate(
  p_manifest_id uuid,
  p_source text
) returns jsonb
language sql
stable
set search_path to 'public'
as $$
  select public.source_verify_candidate_span(
    p_source,
    sm.source_locator,
    sm.source_quote,
    sm.source_quote_hash,
    sm.source_quote_hash_algorithm,
    sm.source_quote_hash_encoding,
    sm.source_content_hash
  )
  from public.source_manifest sm
  where sm.id = p_manifest_id
$$;

create or replace function public.guard_source_manifest_span()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_bounds integer[];
  v_count integer;
  v_source text;
  v_result jsonb;
begin
  if new.action in ('import', 'hold') then
    if not public.source_locator_has_span(new.source_locator)
       or new.source_quote_hash is null
       or new.source_quote_hash !~ '^[0-9a-f]{64}$' then
      raise exception 'source_manifest_span: candidate locator gap';
    end if;
  end if;

  if new.source_quote is not null then
    if char_length(new.source_quote) > public.source_quote_max_chars() then
      raise exception 'source_manifest_span: source quote exceeds % characters',
        public.source_quote_max_chars();
    end if;
    if public.source_quote_digest(
         new.source_quote,
         new.source_quote_hash_algorithm,
         new.source_quote_hash_encoding
       ) is distinct from new.source_quote_hash then
      raise exception 'source_manifest_span: candidate quote hash mismatch';
    end if;
    v_bounds := public.source_locator_codepoint_span(new.source_locator);
    if v_bounds is not null
       and (v_bounds[2] - v_bounds[1]) <> char_length(new.source_quote) then
      raise exception 'source_manifest_span: span width does not match source quote';
    end if;
  end if;

  if new.action in ('import', 'hold')
     and to_regclass('pg_temp.source_span_check_text') is not null then
    select count(*), min(addressed_text)
      into v_count, v_source
    from pg_temp.source_span_check_text;
    if v_count > 1 then
      raise exception 'source_manifest_span: source_span_check_text must contain one row';
    end if;
    if v_count = 1 and v_source is not null then
      v_result := public.source_verify_candidate_span(
        v_source,
        new.source_locator,
        new.source_quote,
        new.source_quote_hash,
        new.source_quote_hash_algorithm,
        new.source_quote_hash_encoding,
        new.source_content_hash
      );
      if coalesce((v_result->>'ok')::boolean, false) is distinct from true then
        raise exception 'source_manifest_span: %', coalesce(v_result->>'posture', 'unverified');
      end if;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.source_quote_max_chars() from public;
revoke all on function public.source_quote_pg_encoding(text) from public;
revoke all on function public.source_locator_codepoint_span(jsonb) from public;
revoke all on function public.source_locator_has_span(jsonb) from public;
revoke all on function public.source_quote_digest(text, text, text) from public;
revoke all on function public.source_unique_quote_span(text, text) from public;
revoke all on function public.source_verify_candidate_span(text, jsonb, text, text, text, text, text) from public;
revoke all on function public.source_verify_stored_candidate(uuid, text) from public;
revoke all on function public.guard_source_manifest_span() from public;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname='source_manifest_locator_object'
  ) then
    alter table source_manifest
      add constraint source_manifest_locator_object
      check (jsonb_typeof(source_locator)='object');
  end if;

  if not exists (
    select 1 from pg_constraint where conname='source_manifest_quote_hash_algorithm_nonempty'
  ) then
    alter table source_manifest
      add constraint source_manifest_quote_hash_algorithm_nonempty
      check (length(trim(source_quote_hash_algorithm)) > 0);
  end if;

  if not exists (
    select 1 from pg_constraint where conname='source_manifest_quote_length'
  ) then
    alter table source_manifest
      add constraint source_manifest_quote_length
      check (source_quote is null or char_length(source_quote) <= public.source_quote_max_chars());
  end if;

  if not exists (
    select 1 from pg_constraint where conname='source_manifest_quote_hash_encoding_utf8'
  ) then
    alter table source_manifest
      add constraint source_manifest_quote_hash_encoding_utf8
      check (lower(trim(source_quote_hash_encoding)) in ('utf-8', 'utf8'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname='source_manifest_quote_hash_sha256'
  ) then
    alter table source_manifest
      add constraint source_manifest_quote_hash_sha256
      check (
        source_quote_hash is null
        or lower(source_quote_hash_algorithm) <> 'sha256'
        or source_quote_hash ~ '^[0-9a-f]{64}$'
      );
  end if;

  if not exists (
    select 1 from pg_constraint where conname='source_manifest_content_hash_sha256'
  ) then
    alter table source_manifest
      add constraint source_manifest_content_hash_sha256
      check (
        source_content_hash is null
        or (
          lower(source_quote_hash_algorithm) = 'sha256'
          and source_content_hash ~ '^[0-9a-f]{64}$'
        )
      );
  end if;

  if exists (select 1 from pg_roles where rolname='anon') then
    revoke all on function public.source_quote_max_chars() from anon;
    revoke all on function public.source_quote_pg_encoding(text) from anon;
    revoke all on function public.source_locator_codepoint_span(jsonb) from anon;
    revoke all on function public.source_locator_has_span(jsonb) from anon;
    revoke all on function public.source_quote_digest(text, text, text) from anon;
    revoke all on function public.source_unique_quote_span(text, text) from anon;
    revoke all on function public.source_verify_candidate_span(text, jsonb, text, text, text, text, text) from anon;
    revoke all on function public.source_verify_stored_candidate(uuid, text) from anon;
    revoke all on function public.guard_source_manifest_span() from anon;
  end if;

  if exists (select 1 from pg_roles where rolname='authenticated') then
    revoke all on function public.source_quote_max_chars() from authenticated;
    revoke all on function public.source_quote_pg_encoding(text) from authenticated;
    revoke all on function public.source_locator_codepoint_span(jsonb) from authenticated;
    revoke all on function public.source_locator_has_span(jsonb) from authenticated;
    revoke all on function public.source_quote_digest(text, text, text) from authenticated;
    revoke all on function public.source_unique_quote_span(text, text) from authenticated;
    revoke all on function public.source_verify_candidate_span(text, jsonb, text, text, text, text, text) from authenticated;
    revoke all on function public.source_verify_stored_candidate(uuid, text) from authenticated;
    revoke all on function public.guard_source_manifest_span() from authenticated;
  end if;
end $$;

create index if not exists idx_source_manifest_source_locator_gin
  on source_manifest using gin (source_locator);

create index if not exists idx_source_manifest_quote_hash
  on source_manifest(source_quote_hash)
  where source_quote_hash is not null;

drop trigger if exists trg_source_manifest_span on source_manifest;
create trigger trg_source_manifest_span
  before insert or update on source_manifest
  for each row execute function public.guard_source_manifest_span();

-- Recreate views because locator-aware review_queue inserts columns into the
-- visible review surface; CREATE OR REPLACE VIEW cannot change existing column
-- order/names in-place.
drop view if exists source_readiness;
drop view if exists source_manifest_review_queue;

-- Review queue exposes locator/hash posture and omits the optional quote text.
create view source_manifest_review_queue with (security_invoker=true) as
  select
    sib.id as batch_id,
    ss.source_key,
    sib.batch_key,
    si.id as source_item_id,
    si.source_item_key,
    sm.id as source_manifest_id,
    sm.manifest_key,
    sm.source_locator,
    sm.source_quote_hash,
    sm.source_quote_hash_algorithm,
    sm.source_quote_hash_encoding,
    (sm.source_quote is not null) as source_quote_stored,
    sm.source_content_hash,
    si.source_container,
    si.title,
    sm.action,
    sm.target_zone,
    sm.review_state,
    sm.suggestion_confidence,
    sm.sensitivity,
    sm.review_notes,
    si.created_at as staged_at
  from source_manifest sm
  join source_items si on si.id = sm.source_item_id
  join source_import_batches sib on sib.id = si.batch_id
  join source_systems ss on ss.id = sib.source_system_id
  where sm.review_state in ('unreviewed','needs_review')
     or (sm.action='hold' and sm.review_state not in ('waived','rejected'))
  order by si.created_at asc, sm.manifest_key asc;

-- Readiness blocks import/HOLD candidates that lack a span or quote hash.
create view source_readiness with (security_invoker=true) as
  with batches as (
    select b.id as batch_id, ss.source_key, b.batch_key, b.status,
           b.source_item_count, b.exported_item_count
    from source_import_batches b
    join source_systems ss on ss.id=b.source_system_id
  ), counts as (
    select b.batch_id,
      (select count(*) from source_items si where si.batch_id=b.batch_id) as staged_items,
      (select count(*) from source_items si
        where si.batch_id=b.batch_id
          and not exists (select 1 from source_manifest sm where sm.source_item_id=si.id)) as unmanifested_items,
      (select count(*) from source_manifest sm join source_items si on si.id=sm.source_item_id
        where si.batch_id=b.batch_id and sm.review_state in ('unreviewed','needs_review')) as review_pending,
      (select count(*) from source_manifest sm join source_items si on si.id=sm.source_item_id
        where si.batch_id=b.batch_id and sm.action='hold' and sm.review_state not in ('waived','rejected')) as unwaived_hold,
      (select count(*) from source_manifest_payload_drift(b.batch_id)) as payload_drift,
      (select count(*) from source_manifest sm join source_items si on si.id=sm.source_item_id
        where si.batch_id=b.batch_id and sm.action='import' and sm.review_state='approved' and sm.target_table is null) as approved_import_without_target,
      (select count(*) from source_manifest sm join source_items si on si.id=sm.source_item_id
        where si.batch_id=b.batch_id
          and sm.action in ('import','hold')
          and sm.review_state not in ('rejected')
          and (
            not public.source_locator_has_span(sm.source_locator)
            or sm.source_quote_hash is null
            or length(trim(sm.source_quote_hash)) = 0
          )) as candidate_locator_gap
    from batches b
  )
  select batch_id, source_key, batch_key, 'batch_frozen' as check_key,
         case when status in ('frozen','ready','cutover') then 'pass' else 'fail' end as state,
         'blocker' as severity,
         'Freeze or watermark the source before declaring readiness.' as remediation
  from batches
  union all
  select b.batch_id, b.source_key, b.batch_key, 'expected_counts_match',
         case when b.source_item_count is null or b.exported_item_count is null then 'warn'
              when b.source_item_count = b.exported_item_count and b.exported_item_count = c.staged_items then 'pass'
              else 'fail' end,
         case when b.source_item_count is null or b.exported_item_count is null then 'warning' else 'blocker' end,
         'Record expected source/export counts and stage every exported item.'
  from batches b join counts c using (batch_id)
  union all
  select b.batch_id, b.source_key, b.batch_key, 'no_unmanifested_items',
         case when c.unmanifested_items=0 then 'pass' else 'fail' end,
         'blocker',
         'Create at least one manifest row for every staged source item, even if the item is excluded.'
  from batches b join counts c using (batch_id)
  union all
  select b.batch_id, b.source_key, b.batch_key, 'review_queue_clear_or_waived',
         case when c.review_pending=0 then 'pass' else 'fail' end,
         'blocker',
         'Review or waive all unreviewed/needs-review manifest rows.'
  from batches b join counts c using (batch_id)
  union all
  select b.batch_id, b.source_key, b.batch_key, 'hold_rows_waived',
         case when c.unwaived_hold=0 then 'pass' else 'fail' end,
         'blocker',
         'HOLD rows must be explicitly waived or resolved before cutover.'
  from batches b join counts c using (batch_id)
  union all
  select b.batch_id, b.source_key, b.batch_key, 'no_payload_drift_after_review',
         case when c.payload_drift=0 then 'pass' else 'fail' end,
         'blocker',
         'Re-review manifest rows whose source payload hash changed.'
  from batches b join counts c using (batch_id)
  union all
  select b.batch_id, b.source_key, b.batch_key, 'approved_imports_have_targets',
         case when c.approved_import_without_target=0 then 'pass' else 'fail' end,
         'blocker',
         'Approved imports must name their target table before cutover.'
  from batches b join counts c using (batch_id)
  union all
  select b.batch_id, b.source_key, b.batch_key, 'candidate_locators_and_quote_hashes',
         case when c.candidate_locator_gap=0 then 'pass' else 'fail' end,
         'blocker',
         'Import/HOLD candidates must include a source span and quote hash.'
  from batches b join counts c using (batch_id);

revoke all on source_manifest_review_queue from public;
revoke all on source_readiness from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname='anon') then
    revoke all on source_manifest_review_queue from anon;
    revoke all on source_readiness from anon;
  end if;

  if exists (select 1 from pg_roles where rolname='authenticated') then
    revoke all on source_manifest_review_queue from authenticated;
    revoke all on source_readiness from authenticated;
  end if;
end $$;

comment on column source_manifest.source_locator is
  'JSON object. Span is a half-open code-point range in span or character_start/character_end. Optional path, scheme, message, and turn keys are adapter metadata.';
comment on column source_manifest.source_quote is
  'Optional excerpt of at most source_quote_max_chars() characters. Omit when a locator and hash are enough.';
comment on column source_manifest.source_quote_hash is
  'Lowercase SHA-256 hex of the located span under source_quote_hash_encoding.';
comment on column source_manifest.source_quote_hash_encoding is
  'Encoding used for source_quote_hash. Stored rows use utf-8.';
comment on column source_manifest.source_content_hash is
  'Optional lowercase SHA-256 hex of the UTF-8 addressed text. Distinct from source_items.payload_hash.';

-- End of candidate locator contract.
