-- ============================================================================
-- SOVEREIGN MEMORY :: REVIEW AND PROMOTION GUARDS
-- Target: Postgres 15+ / Supabase. Run after sql/04_source_import.sql.
-- Applied by scripts/validate_source_import.sh before the promotion-guard tests.
--
-- This is not a review UI and it does not resolve conflicts. It is the
-- fail-closed side of the source-import promotion paths:
--   * HOLD, EXCLUDE, and EVIDENCE candidates cannot become memory;
--   * a structurally valid package cannot declare cutover authority;
--   * agent-authored content cannot become human authority without explicit review;
--   * an import can become memory only after an explicit review decision.
--
-- Explicit manifest review means review_state='approved', a non-blank
-- reviewed_by, reviewed_at, and a non-blank review_notes decision.
-- Naming target_table is a suggestion, not promotion. Promotion is target_id,
-- a memory row that cites source_manifest_id, or batch status 'cutover'.
-- ============================================================================

create or replace function promotion_guard_candidate_message(p_action source_item_action)
returns text
language sql
immutable
set search_path to public
as $$
  select case p_action
    when 'hold' then 'promotion guard: HOLD candidate cannot be promoted'
    when 'exclude' then 'promotion guard: EXCLUDE candidate cannot be promoted'
    when 'evidence' then 'promotion guard: EVIDENCE candidate cannot normalize into a memory fact'
    else 'promotion guard: import candidate cannot become memory without explicit review'
  end;
$$;

create or replace function source_manifest_explicitly_reviewed(
  p_review_state source_review_state,
  p_reviewed_by text,
  p_reviewed_at timestamptz,
  p_review_notes text
) returns boolean
language sql
immutable
set search_path to public
as $$
  select p_review_state = 'approved'::source_review_state
     and p_reviewed_by is not null
     and length(btrim(p_reviewed_by)) > 0
     and p_reviewed_at is not null
     and p_review_notes is not null
     and length(btrim(p_review_notes)) > 0;
$$;

create or replace function guard_source_manifest_promotion()
returns trigger
language plpgsql
set search_path to public
as $$
declare
  v_memory_target boolean;
begin
  v_memory_target := new.target_id is not null
    or lower(btrim(coalesce(new.target_table, ''))) in (
      'memories', 'wiki_pages', 'public.memories', 'public.wiki_pages'
    );

  if new.action in ('hold', 'exclude', 'evidence') and v_memory_target then
    raise exception using message = promotion_guard_candidate_message(new.action);
  end if;

  if new.action = 'import'
     and new.target_id is not null
     and not source_manifest_explicitly_reviewed(
       new.review_state, new.reviewed_by, new.reviewed_at, new.review_notes
     ) then
    raise exception using message =
      'promotion guard: import candidate cannot become memory without explicit review';
  end if;

  return new;
end;
$$;

create or replace function guard_memory_candidate_promotion()
returns trigger
language plpgsql
set search_path to public
as $$
declare
  v_manifest_id uuid;
  v_manifest source_manifest%rowtype;
  v_matched source_item_action;
  v_claims_human boolean;
  v_receipt boolean;
begin
  v_claims_human :=
    (
      new.source_kind = 'agent'
      and (
        new.metadata->>'basis' = 'human_direct'
        or new.metadata->>'authority' = 'human'
        or new.metadata->>'human_authority' = 'true'
      )
    )
    or (
      new.source_kind = 'human'
      and (
        new.metadata->>'authored_by' = 'agent'
        or new.metadata->>'producer' = 'agent'
      )
    );
  v_receipt := new.metadata->>'explicit_review' = 'true'
    and length(btrim(coalesce(new.metadata->>'reviewed_by', ''))) > 0
    and length(btrim(coalesce(new.metadata->>'reviewed_at', ''))) > 0;

  if nullif(btrim(coalesce(new.metadata->>'source_manifest_id', '')), '') is not null then
    begin
      v_manifest_id := btrim(new.metadata->>'source_manifest_id')::uuid;
    exception when invalid_text_representation then
      raise exception using message =
        'promotion guard: import candidate cannot become memory without explicit review';
    end;

    select * into v_manifest from source_manifest where id = v_manifest_id;
    if not found then
      raise exception using message =
        'promotion guard: import candidate cannot become memory without explicit review';
    end if;

    if v_manifest.action in ('hold', 'exclude', 'evidence') then
      raise exception using message = promotion_guard_candidate_message(v_manifest.action);
    end if;

    if not source_manifest_explicitly_reviewed(
      v_manifest.review_state, v_manifest.reviewed_by, v_manifest.reviewed_at, v_manifest.review_notes
    ) then
      raise exception using message =
        'promotion guard: import candidate cannot become memory without explicit review';
    end if;

    return new;
  end if;

  -- Citation-free copies are still promotion. Match the candidate text itself
  -- so a HOLD, EXCLUDE, EVIDENCE, or unreviewed import cannot be laundered by
  -- omitting source_manifest_id.
  select sm.action into v_matched
  from source_manifest sm
  where (
      (
        nullif(btrim(coalesce(sm.suggested_content, '')), '') is not null
        and sm.suggested_content = new.content
      ) or (
        nullif(btrim(coalesce(sm.suggested_summary, '')), '') is not null
        and sm.suggested_summary = new.content
      )
    )
    and (
      sm.action in ('hold', 'exclude', 'evidence')
      or (
        sm.action = 'import'
        and not source_manifest_explicitly_reviewed(
          sm.review_state, sm.reviewed_by, sm.reviewed_at, sm.review_notes
        )
      )
    )
  order by case sm.action
    when 'evidence' then 0
    when 'exclude' then 1
    when 'hold' then 2
    else 3
  end
  limit 1;

  if v_matched in ('hold', 'exclude', 'evidence') then
    raise exception using message = promotion_guard_candidate_message(v_matched);
  end if;
  if v_matched = 'import' then
    raise exception using message =
      'promotion guard: import candidate cannot become memory without explicit review';
  end if;

  if v_claims_human and not v_receipt then
    raise exception using message =
      'promotion guard: agent-authored content cannot become human authority without explicit review';
  end if;

  return new;
end;
$$;

create or replace function guard_source_batch_authority()
returns trigger
language plpgsql
set search_path to public
as $$
declare
  v_action source_item_action;
begin
  if new.status is distinct from 'cutover'::source_batch_status then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.status = 'cutover'::source_batch_status then
    return new;
  end if;

  select sm.action into v_action
  from source_manifest sm
  join source_items si on si.id = sm.source_item_id
  where si.batch_id = new.id
    and sm.action in ('hold', 'exclude', 'evidence')
    and (
      sm.target_id is not null
      or lower(btrim(coalesce(sm.target_table, ''))) in (
        'memories', 'wiki_pages', 'public.memories', 'public.wiki_pages'
      )
    )
  order by case sm.action when 'evidence' then 0 when 'exclude' then 1 else 2 end
  limit 1;

  if v_action is not null then
    raise exception using message = promotion_guard_candidate_message(v_action);
  end if;

  if exists (
    select 1
    from source_manifest sm
    join source_items si on si.id = sm.source_item_id
    where si.batch_id = new.id
      and sm.action = 'hold'
      and sm.review_state not in ('waived'::source_review_state, 'rejected'::source_review_state)
  ) then
    raise exception using message = promotion_guard_candidate_message('hold');
  end if;

  if exists (
    select 1
    from source_manifest sm
    join source_items si on si.id = sm.source_item_id
    where si.batch_id = new.id
      and sm.action = 'import'
      and not source_manifest_explicitly_reviewed(
        sm.review_state, sm.reviewed_by, sm.reviewed_at, sm.review_notes
      )
  ) then
    raise exception using message =
      'promotion guard: structurally valid package cannot become authoritative without explicit review';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_source_manifest_promotion on source_manifest;
create trigger trg_guard_source_manifest_promotion
  before insert or update on source_manifest
  for each row execute function guard_source_manifest_promotion();

drop trigger if exists trg_guard_memory_candidate_promotion on memories;
create trigger trg_guard_memory_candidate_promotion
  before insert or update on memories
  for each row execute function guard_memory_candidate_promotion();

drop trigger if exists trg_guard_source_batch_authority on source_import_batches;
create trigger trg_guard_source_batch_authority
  before insert or update of status on source_import_batches
  for each row execute function guard_source_batch_authority();

revoke all on function promotion_guard_candidate_message(source_item_action) from public;
revoke all on function source_manifest_explicitly_reviewed(source_review_state, text, timestamptz, text) from public;
revoke all on function guard_source_manifest_promotion() from public;
revoke all on function guard_memory_candidate_promotion() from public;
revoke all on function guard_source_batch_authority() from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on function promotion_guard_candidate_message(source_item_action) from anon;
    revoke all on function source_manifest_explicitly_reviewed(source_review_state, text, timestamptz, text) from anon;
    revoke all on function guard_source_manifest_promotion() from anon;
    revoke all on function guard_memory_candidate_promotion() from anon;
    revoke all on function guard_source_batch_authority() from anon;
  end if;

  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on function promotion_guard_candidate_message(source_item_action) from authenticated;
    revoke all on function source_manifest_explicitly_reviewed(source_review_state, text, timestamptz, text) from authenticated;
    revoke all on function guard_source_manifest_promotion() from authenticated;
    revoke all on function guard_memory_candidate_promotion() from authenticated;
    revoke all on function guard_source_batch_authority() from authenticated;
  end if;
end $$;

-- End of review and promotion guards.
