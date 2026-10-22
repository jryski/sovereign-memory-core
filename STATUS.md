# Sovereign Memory Core Status

Status date: 2026-09-25

> **Program note (2026-09-25):** This file tracks repository posture. It does
> not accept a deployment.
>
> Issue #55 is closed historical context for the v0.3-alpha program. The open
> recovery and live-acceptance work is elsewhere: #58 and #52 are still open,
> and umbrella issue #92 is an implementation HOLD. This status refresh is the
> docs reconcile for #91. Parent cutover:
> [WireSpeedComputing/sovereign-ai-os#14](https://github.com/WireSpeedComputing/sovereign-ai-os/issues/14).
> Program map:
> [WireSpeedComputing/sovereign-ai-os#52](https://github.com/WireSpeedComputing/sovereign-ai-os/issues/52).
> Edges on that map stay proposed until an owner validates them.
>
> Tag `v0.3-alpha` points at commit `c96b9da749b2d95661973485b2a026897329c8cd`
> (2026-08-15). `main` has commits after that tag. The tag and
> [`release/v0.3-alpha-known-limitations.md`](release/v0.3-alpha-known-limitations.md)
> are a bounded coordinate and a limitations record. That record proves the
> package/restore mechanism on a representative synthetic source built from the
> exact reviewed migrations. It does not export private production data, and it
> is not independent live acceptance. Live and production export, clean restore
> of private data, and independent live acceptance remain an implementation HOLD
> on #92, with #58 and #52 still open. See
> [`docs/perimeter-evaluability.md`](docs/perimeter-evaluability.md) and the
> [`restore rehearsal template`](docs/templates/restore-rehearsal.md).

## Current rating

| Dimension | Current | Target | Notes |
|---|---:|---:|---|
| Core schema concept | 9/10 | 10/10 | Strong baseline for memory, wiki, attention index, provenance, supersession, and operating-doc integrity. |
| Repo/deployment alignment | 7/10 | 10/10 | The generic source-import/cutover foundation is repo-owned; deployment drift and operational evidence still need periodic verification. |
| Source import/cutover readiness | 8/10 | 10/10 | Foundation, candidate provenance, richer probes, fatal validation, and the first internal producer slice exist; real adapters and operational dry runs remain. |
| Security posture | 8/10 | 10/10 | Security model is honest; next step is least-privilege access hardening beyond broad credential operation. |
| Survivability | 7/10 | 10/10 | Backup/restore guidance and an evidence template exist. The v0.3-alpha known-limitations record proves synthetic package/restore for that rehearsal profile. Live and production export, clean restore of private data, and independent live acceptance remain open and blocked on #92, with #58 and #52 still open. |
| Personal memory UX/readability | 6/10 | 10/10 | Core has strong data model; browser UI belongs in a separate repo. |
| Governance/review | 7/10 | 10/10 | Proposed/superseded/review concepts exist; needs complete review and promotion workflow. |

## Confirmed current repo contents

Checked against `main` on 2026-09-25. Ordered migrations in `sql/`:

- `sql/01_core.sql`
- `sql/02_vault.sql`
- `sql/03_provenance_guards.sql`
- `sql/04_source_import.sql`
- `sql/05_candidate_locators.sql`
- `sql/06_cutover_probe_categories.sql`
- `sql/07_work_lessons.sql`
- `sql/08_attention_events.sql`
- `sql/09_perimeter_refresh.sql`
- `sql/10_security_definer_hardening.sql`
- `sql/11_perimeter_evaluability.sql`

`sql/11_perimeter_evaluability.sql` is the in-repo C1 report seam. Its presence
is a migration, not live acceptance.

`sql/validation/` is not part of that ordered apply list. It holds
`source_import_readiness.sql` and `load_chat_mine_package.sql`.

Also in the repository:

- Source-import validation with fatal blocker enforcement and rollback fixtures
- First internal Chat-Mine producer slice, [`docs/10-chat-mine-source-import-exporter.md`](docs/10-chat-mine-source-import-exporter.md), with deterministic package validation and a rollback loader smoke path. Chat-Mine export is internal producer alignment, not a public interchange protocol.
- Architecture, security, agent operations, implementation, operations, and pattern docs
- Roadmap, ADR, contribution, security, support, issue template, and PR template scaffolding
- [`PROGRAM-ROLE.md`](PROGRAM-ROLE.md) and [`docs/ecosystem/`](docs/ecosystem/)
- Release-path notes under `release/`, including the v0.3-alpha known-limitations record and the exact-release procedure
- Tag `v0.3-alpha` at `c96b9da749b2d95661973485b2a026897329c8cd`
- CI conformance on PostgreSQL 15 and 16, as described in the README

That list is repository contents. It is not a deployment inventory and it is
not an independent live-acceptance receipt. Synthetic package/restore for the
v0.3-alpha rehearsal profile is the known-limitations record named above.

### Source-import current status

- **Merged core foundation.** `sql/04_source_import.sql`, `sql/05_candidate_locators.sql`, and `sql/06_cutover_probe_categories.sql` are repo-owned SQL. Source-import and cutover controls are not pending reconciliation.
- **Internal producer slice.** [`docs/10-chat-mine-source-import-exporter.md`](docs/10-chat-mine-source-import-exporter.md) is the first internal Chat-Mine producer slice. It is internal producer alignment, not a public interchange protocol.
- **Future work.** Review UI, Hermes orchestration, real source adapters, and operational dry runs remain outside this foundation.

### Verified baseline

Work-memory conformance on PostgreSQL 15 and 16 covers the lifecycle, history, authority perimeter, and upgrade checks described in the README. Source-import and cutover validation, on a disposable database, checks required objects, security-definer search paths, grant posture, and fixture rollback. Fatal validation failure behavior raises an exception when a fatal check fails. The same gate covers candidate locators and quote hashes, and all five richer cutover probe categories. Chat-Mine exporter validation checks deterministic package output and, when `DATABASE_URL` is set, a rollback-only load. This baseline is repository validation. It is not independent live acceptance.

## Drift policy

This repository should not carry a detailed inventory of any one private deployment. That information belongs in that deployment's own wiki, issue tracker, or operations log.

The repo should instead provide a repeatable drift ledger template that any deployment can fill in.

### Drift ledger template

```text
deployment_name:
review_date:
reviewed_by:
repo_ref:
database_ref:

object_inventory_method:
  tables_query:
  routines_query:
  grants_query:

repo_objects_missing_from_deployment:
  - object:
    expected_from:
    severity:
    action:

deployment_objects_missing_from_repo:
  - object:
    object_type:
    schema:
    generic_core_candidate: yes/no
    deployment_specific: yes/no
    reason:
    action:

semantic_drift:
  - object_or_doc:
    repo_behavior:
    deployment_behavior:
    risk:
    action:

known_waivers:
  - item:
    reason:
    owner:
    review_by:

result:
  status: aligned / intentional-drift / action-required
  next_action:
```

## Interpretation

The merged core foundation is versioned SQL, validation, and docs:
`sql/04_source_import.sql`, `sql/05_candidate_locators.sql`, and
`sql/06_cutover_probe_categories.sql`. It remains generic across source types.
The internal producer slice is the Chat-Mine package exporter in
[`docs/10-chat-mine-source-import-exporter.md`](docs/10-chat-mine-source-import-exporter.md).
Chat-Mine export is internal producer alignment, not a public interchange protocol.

Future work is operational adoption: real source adapters, review UI, Hermes orchestration,
and dry runs against representative exports. Those layers must preserve the core review and
conflict posture rather than bypassing it. Separately, live and production export,
clean restore of private data, and independent live acceptance stay open and blocked
on #92. The synthetic package/restore rehearsal for v0.3-alpha is already recorded
in `release/v0.3-alpha-known-limitations.md`. This status file does not close #92.

Repository coordination should use `docs/roadmap.md`, `docs/project-management.md`, and
`docs/adr/` so roadmap, issues, PRs, milestones, decisions, and releases remain visible outside
any single chat transcript.

Deployment-specific inventories should be maintained outside this public/reusable status document.

## 10/10 blockers

1. No real source adapters have completed an end-to-end import and rollback dry run.
2. Review queue and promotion workflow need UI support.
3. Hermes orchestration is not implemented.
4. The provider-exit rehearsal template and the C1 perimeter-evaluability migration are in the repository. The v0.3-alpha known-limitations record proves synthetic package/restore for that rehearsal profile. Live and production export, clean restore of private data, and independent live acceptance are an implementation HOLD on #92. Related open issues are #58 and #52. Closed #55 is historical context for the v0.3-alpha program, not a closeout of those issues.
5. Broad credential operation remains the practical trust boundary; least-privilege access hardening is not yet implemented.
6. Drift ledger process is documented here but not yet backed by an executable inventory check.
7. Tag `v0.3-alpha` exists at `c96b9da749b2d95661973485b2a026897329c8cd`. A release tag records a reviewed coordinate and bounded limitations. It does not declare a known-good schema for later commits on `main`, and it does not establish schema readiness or fitness for any deployment.

## Immediate development order

Current work follows the open program in the table below. The 2026-08-13 note that pointed only at #55 is historical.

| Item | State on 2026-09-25 |
|---|---|
| #55 v0.3-alpha completion program | Closed. Historical program context. |
| #58 export, clean restore, and provider-exit conformance | Open. The synthetic v0.3-alpha rehearsal does not close this issue. |
| #52 clean restore verification and custody receipts | Open. |
| #92 recovery and live acceptance | Open. Implementation HOLD. Docs may name the hold. They must not mark the work done. |
| #91 README, status, and roadmap reconcile | Open until an independent reviewer accepts the docs change under D3. |
| [sovereign-ai-os#14](https://github.com/WireSpeedComputing/sovereign-ai-os/issues/14) | Parent cutover of planning onto GitHub. |
| [sovereign-ai-os#52](https://github.com/WireSpeedComputing/sovereign-ai-os/issues/52) | Program map. Proposed edges are not committed dependencies. |

The v0.3-alpha synthetic package/restore rehearsal is recorded in
`release/v0.3-alpha-known-limitations.md`. Live and production export, clean
restore of private data, and independent live acceptance remain open and blocked
on #92. The older product-development order below stays parked. Some of its early
items now exist in the repository as artifacts (the rehearsal template,
`sql/11_perimeter_evaluability.sql`, and tag `v0.3-alpha`). Those artifacts are
not the blocked live acceptance.

1. Exercise a real source adapter through export, review, cutover probes, and rollback.
2. Add review UI without bypassing manifest decisions or conflict posture.
3. Add Hermes orchestration only after the manual producer/loader path is proven.
4. Add backup/export/restore evidence template. The template is now `docs/templates/restore-rehearsal.md`. Using it for live acceptance remains the #92 hold.
5. Add least-privilege access hardening design.
6. Add an executable deployment drift inventory check.
7. Coordinate with peer reviewers before applying live DB mutations.

## Rule for this phase

Do not make live schema changes casually. The source-import/cutover foundation is captured and
validated in the repo, but real deployment work should still use explicit migrations,
acceptance tests, dry-run evidence, and review.
