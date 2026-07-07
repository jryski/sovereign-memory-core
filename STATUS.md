# Sovereign Memory Core Status

Status date: 2026-07-07

## Current rating

| Dimension | Current | Target | Notes |
|---|---:|---:|---|
| Core schema concept | 9/10 | 10/10 | Strong baseline for memory, wiki, hot index, provenance, supersession, and operating-doc integrity. |
| Production/repo alignment | 6/10 | 10/10 | Live deployments can contain source-import and cutover controls that are not yet captured in repo SQL. |
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

## Confirmed live deployment divergence pattern

A live deployment may include additional objects that are not yet represented in the reusable repo baseline. In the current reference deployment, examples include:

### Public tables/views

- `migration_manifest_v1`
- `migration_manifest_review_queue`
- `migration_readiness_v1`
- `migration_export_house_v1`
- `migration_export_hold_v1`
- `migration_export_evidence_v1`
- `migration_freeze_control`
- `cutover_probe`
- `cutover_run`
- `cutover_scorecard`
- `model_channel`
- `model_notebook`
- `review_queue`
- `skill_registry`
- `failed_embeds`
- `cookbook_recipes`

### Public functions

- `activate_migration_freeze_v1`
- `release_migration_freeze_v1`
- `enforce_migration_freeze_v1`
- `export_house_chunk_v1`
- `export_evidence_chunk_v1`
- `promote_memory`
- `reject_memory`
- `correct_memory`
- `match_memories`
- `match_wiki`
- `embed_pending`

### Vault additions

- `vault_private.api_version`
- `vault_internal.resolve_subject`

## Interpretation

The repo is a solid baseline blueprint, but the reusable source-import/cutover layer is not yet fully represented as versioned SQL and docs. That layer should be generic enough to support many source types, not just any one user's current migration path.

## 10/10 blockers

1. Source-import/cutover SQL not yet captured in repo.
2. No complete source-import/cutover runbook until `docs/07-source-import-cutover.md`.
3. No automated validation script that runs all readiness checks against a live DB.
4. No repository-stored evidence record of latest backup/restore rehearsal.
5. Broad credential operation remains the practical trust boundary; least-privilege access hardening is not yet implemented.
6. Production object drift can exist between live DB and repo baseline.
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
