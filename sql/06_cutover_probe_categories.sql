-- ============================================================================
-- SOVEREIGN MEMORY :: RICHER CUTOVER PROBE CATEGORIES
-- Target: Postgres 15+ / Supabase. Run after sql/04_source_import.sql.
-- Docs: docs/04-implementation-guide.md Step 9B.
--
-- Purpose:
--   Harden cutover verification beyond positive retrieval checks.
--
-- Design rule:
--   Retrieval success alone is not proof of readiness. Cutover probes must also
--   verify refusal/unknown behavior, conflict surfacing, stale-state avoidance,
--   and evidence-request behavior.
-- ============================================================================

alter table cutover_probes
  add column if not exists probe_category text not null default 'positive',
  add column if not exists expected_behavior text,
  add column if not exists expected_evidence_required boolean not null default false;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname='cutover_probe_category_known'
  ) then
    alter table cutover_probes
      add constraint cutover_probe_category_known
      check (probe_category in ('positive','negative','conflict','stale_state','evidence_request'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname='cutover_probe_expected_behavior_nonempty'
  ) then
    alter table cutover_probes
      add constraint cutover_probe_expected_behavior_nonempty
      check (expected_behavior is null or length(trim(expected_behavior)) > 0);
  end if;
end $$;

create index if not exists idx_cutover_probes_category
  on cutover_probes(batch_id, probe_category, severity, active);

-- Recreate scorecard so critical readiness is not hidden behind aggregate pass
-- percentage. A single active critical miss remains visible as a blocker signal.
drop view if exists cutover_scorecard;

create view cutover_scorecard with (security_invoker=true) as
  with latest as (
    select distinct on (cr.probe_id)
      cr.probe_id, cr.run_at, cr.matched, cr.top_distance
    from cutover_runs cr
    order by cr.probe_id, cr.run_at desc
  )
  select
    cp.batch_id,
    count(cp.id) filter (where cp.active) as probes_defined,
    count(cp.id) filter (where cp.active and cp.probe_category='positive') as positive_probes,
    count(cp.id) filter (where cp.active and cp.probe_category='negative') as negative_probes,
    count(cp.id) filter (where cp.active and cp.probe_category='conflict') as conflict_probes,
    count(cp.id) filter (where cp.active and cp.probe_category='stale_state') as stale_state_probes,
    count(cp.id) filter (where cp.active and cp.probe_category='evidence_request') as evidence_request_probes,
    count(l.probe_id) as probes_run,
    count(l.probe_id) filter (where l.matched) as probes_passed,
    count(l.probe_id) filter (where not l.matched and cp.severity='critical') as critical_misses,
    count(l.probe_id) filter (where not l.matched and cp.severity='normal') as normal_misses,
    count(cp.id) filter (where cp.active and cp.severity='critical' and l.probe_id is null) as critical_not_run,
    case when count(cp.id) filter (where cp.active and cp.severity='critical') = 0 then true
         else count(cp.id) filter (where cp.active and cp.severity='critical')
              = count(l.probe_id) filter (where cp.active and cp.severity='critical' and l.matched)
    end as critical_all_pass,
    case when count(cp.id) filter (where cp.active) = 0 then 0
         else round((count(l.probe_id) filter (where l.matched))::numeric
                    / nullif(count(cp.id) filter (where cp.active),0) * 100, 2) end as pass_pct,
    avg(l.top_distance) filter (where l.top_distance is not null) as avg_hit_distance,
    max(l.run_at) as latest_run_at
  from cutover_probes cp
  left join latest l on l.probe_id=cp.id
  where cp.active
  group by cp.batch_id;

-- Extend source_readiness with a cutover probe category gate. This remains
-- generic: it checks probe coverage, not a specific retrieval engine.
drop view if exists source_readiness;

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
          and (sm.source_locator='{}'::jsonb or sm.source_quote_hash is null)) as candidate_locator_gap,
      (select count(distinct cp.probe_category) from cutover_probes cp
        where cp.batch_id=b.batch_id and cp.active) as active_probe_categories,
      (select bool_or(coalesce(cs.critical_all_pass,false)) from cutover_scorecard cs
        where cs.batch_id=b.batch_id) as critical_all_pass
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
  from batches b join counts c using (batch_id)
  union all
  select b.batch_id, b.source_key, b.batch_key, 'cutover_probe_category_coverage',
         case when c.active_probe_categories >= 5 then 'pass' else 'fail' end,
         'blocker',
         'Define active positive, negative, conflict, stale_state, and evidence_request probes before cutover.'
  from batches b join counts c using (batch_id)
  union all
  select b.batch_id, b.source_key, b.batch_key, 'critical_cutover_probes_all_pass',
         case when coalesce(c.critical_all_pass,false) then 'pass' else 'fail' end,
         'blocker',
         'Run every active critical cutover probe and resolve all critical misses before cutover.'
  from batches b join counts c using (batch_id);

revoke all on cutover_scorecard from public;
revoke all on source_readiness from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname='anon') then
    revoke all on cutover_scorecard from anon;
    revoke all on source_readiness from anon;
  end if;

  if exists (select 1 from pg_roles where rolname='authenticated') then
    revoke all on cutover_scorecard from authenticated;
    revoke all on source_readiness from authenticated;
  end if;
end $$;

-- End of richer cutover probe category contract.
