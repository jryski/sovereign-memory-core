# Sovereign Memory Core Status

Status date: 2026-07-07

## Current rating

| Dimension | Current | Target | Notes |
|---|---:|---:|---|
| Core schema concept | 9/10 | 10/10 | Strong baseline for memory, wiki, attention index, provenance, supersession, and operating-doc integrity. |
| Repo/deployment alignment | 6/10 | 10/10 | Deployments can evolve beyond repo SQL; drift must be captured without embedding one deployment's inventory in the reusable repo. |
| Source import/cutover readiness | 6/10 | 10/10 | Manifest, readiness, export, and cutover objects need a complete reusable package. |
| Security posture | 8/10 | 10/10 | Security model is honest; next step is least-privilege access hardening beyond broad credential operation. |
| Survivability | 7/10 | 10/10 | Backup/restore guidance exists; needs executable scripts, evidence records, and periodic verification. |
| Personal memory UX/readability | 6/10 | 10/10 | Core has strong data model; browser UI belongs in a separate repo. |
| Governance/review | 7/10 | 10/10 | Proposed/superseded/review concepts exist; needs complete review and promotion workflow. |

## Confirmed current repo contents

The repository currently contains:

- Tier 1 core SQL: `sql/01_core.sql`
- Tier 2 vault SQL: `sql/02_vault.sql`
- Provenance guard SQL: `sql/03_provenance_guards.sql`
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

The repo is a solid baseline blueprint, but the reusable source-import/cutover layer is not yet fully represented as versioned SQL and docs. That layer should be generic enough to support many source types, not just any one user's current migration path.

Deployment-specific inventories should be maintained outside this public/reusable status document.

## 10/10 blockers

1. Source-import/cutover SQL not yet captured in repo.
2. No complete source-import/cutover runbook until `docs/07-source-import-cutover.md`.
3. No automated validation script that runs all readiness checks against a live DB.
4. No repository-stored evidence template for backup/restore rehearsal.
5. Broad credential operation remains the practical trust boundary; least-privilege access hardening is not yet implemented.
6. Drift ledger process is documented here but not yet backed by an executable inventory check.
7. Review queue and promotion workflow need stronger docs and UI support.
8. No formal release tag declaring a known-good schema version.

## Immediate development order

1. Reconcile reusable source-import/cutover objects into repo SQL.
2. Add cutover/readiness validation script or SQL bundle.
3. Add backup/export/restore evidence template.
4. Add least-privilege access hardening design.
5. Update implementation guide to include source import and authoritative cutover.
6. Coordinate with peer reviewers before applying live DB mutations.

## Rule for this phase

Do not make live schema changes casually. Until the source-import/cutover SQL is captured and reviewed, prefer repo docs, issues, and branch work. Live DB changes should be explicit migrations with acceptance tests and review where practical.
