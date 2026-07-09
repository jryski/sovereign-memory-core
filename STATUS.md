# Sovereign Memory Core Status

Status date: 2026-07-08

## Current rating

| Dimension | Current | Target | Notes |
|---|---:|---:|---|
| Core schema concept | 9/10 | 10/10 | Strong baseline for memory, wiki, attention index, provenance, supersession, and operating-doc integrity. |
| Repo/deployment alignment | 7/10 | 10/10 | The generic source-import/cutover foundation is repo-owned; deployment drift and operational evidence still need periodic verification. |
| Source import/cutover readiness | 8/10 | 10/10 | Foundation, candidate provenance, richer probes, fatal validation, and the first internal producer slice exist; real adapters and operational dry runs remain. |
| Security posture | 8/10 | 10/10 | Security model is honest; next step is least-privilege access hardening beyond broad credential operation. |
| Survivability | 7/10 | 10/10 | Backup/restore guidance exists; needs executable scripts, evidence records, and periodic verification. |
| Personal memory UX/readability | 6/10 | 10/10 | Core has strong data model; browser UI belongs in a separate repo. |
| Governance/review | 7/10 | 10/10 | Proposed/superseded/review concepts exist; needs complete review and promotion workflow. |

## Confirmed current repo contents

The repository currently contains:

- Tier 1 core SQL: `sql/01_core.sql`
- Tier 2 vault SQL: `sql/02_vault.sql`
- Provenance guard SQL: `sql/03_provenance_guards.sql`
- Source-import/cutover foundation: `sql/04_source_import.sql`
- Candidate locators and quote hashes: `sql/05_candidate_locators.sql`
- Richer cutover probe categories: `sql/06_cutover_probe_categories.sql`
- Source-import validation with fatal blocker enforcement and rollback fixtures
- First internal Chat-Mine producer slice with deterministic package validation and a rollback loader smoke path
- Architecture, security, agent operations, implementation, operations, and pattern docs
- A verified baseline claim against vanilla PostgreSQL 16

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

The reusable source-import/cutover foundation is represented as versioned SQL, validation,
and docs. It remains generic across source types. The Chat-Mine package exporter is the first
internal producer aligned with that contract, not a public interchange protocol.

The next gap is operational adoption: real source adapters, review UI, Hermes orchestration,
and dry runs against representative exports. Those layers must preserve the core review and
conflict posture rather than bypassing it.

Deployment-specific inventories should be maintained outside this public/reusable status document.

## 10/10 blockers

1. No real source adapters have completed an end-to-end import and rollback dry run.
2. Review queue and promotion workflow need UI support.
3. Hermes orchestration is not implemented.
4. No repository-stored evidence template for backup/restore rehearsal.
5. Broad credential operation remains the practical trust boundary; least-privilege access hardening is not yet implemented.
6. Drift ledger process is documented here but not yet backed by an executable inventory check.
7. No formal release tag declares a known-good schema version.

## Immediate development order

1. Exercise a real source adapter through export, review, cutover probes, and rollback.
2. Add review UI without bypassing manifest decisions or conflict posture.
3. Add Hermes orchestration only after the manual producer/loader path is proven.
4. Add backup/export/restore evidence template.
5. Add least-privilege access hardening design.
6. Add an executable deployment drift inventory check.
7. Coordinate with peer reviewers before applying live DB mutations.

## Rule for this phase

Do not make live schema changes casually. The source-import/cutover foundation is captured and
validated in the repo, but real deployment work should still use explicit migrations,
acceptance tests, dry-run evidence, and review.
