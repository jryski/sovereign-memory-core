-- ============================================================================
-- SOVEREIGN MEMORY :: CANDIDATE SOURCE LOCATORS + QUOTE HASHES
-- Target: Postgres 15+ / Supabase. Run after sql/04_source_import.sql.
--
-- Purpose:
--   Harden source_manifest so every import/HOLD candidate can be verified
--   against a candidate-level source locator and quote/span hash.
--
-- Design rule:
--   Whole-item payload preservation is necessary but not sufficient. A large
--   source item, such as a conversation export, can yield many manifest
--   candidates. Each candidate needs its own locator into the source item.
-- ============================================================================

alter table source_manifest
  add column if not exists source_locator jsonb not null default '{}',
  add column if not exists source_quote text,
  add column if not exists source_quote_hash text,
  add column if not exists source_quote_hash_algorithm text not null default 'sha256';

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
end $$;

create index if not exists idx_source_manifest_source_locator_gin
  on source_manifest using gin (source_locator);

create index if not exists idx_source_manifest_quote_hash
  on source_manifest(source_quote_hash)
  where source_quote_hash is not null;

-- Recreate views because locator-aware review_queue inserts columns into the
-- visible review surface; CREATE OR REPLACE VIEW cannot change existing column
-- order/names in-place.
drop view if exists source_readiness;
drop view if exists source_manifest_review_queue;

-- Review queue now exposes candidate-level locator/hash posture.
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

-- Readiness now blocks import/HOLD candidates that cannot be verified against
-- a candidate-level locator plus quote hash.
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
          and (sm.source_locator='{}'::jsonb or sm.source_quote_hash is null)) as candidate_locator_gap
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
         'Import/HOLD candidates must include a source locator and quote hash.'
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

-- End of candidate locator contract.
