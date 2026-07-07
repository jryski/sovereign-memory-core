# Sovereign Memory Core Status

Status date: 2026-07-07

## Current rating

| Dimension | Current | Target | Notes |
|---|---:|---:|---|
| Core schema concept | 9/10 | 10/10 | Strong baseline for memory, wiki, hot index, provenance, supersession, and operating-doc integrity. |
| Production/repo alignment | 6/10 | 10/10 | Live DB has migration and cutover controls that are not yet captured in repo SQL. |
| MCP retirement readiness | 6/10 | 10/10 | Live DB has manifest/readiness/cutover objects; repo now needs a complete migration package and runbook. |
| Security posture | 8/10 | 10/10 | Security model is honest; next step is narrow-role/API hardening beyond shared service-role operation. |
| Survivability | 7/10 | 10/10 | Backup/restore guidance exists; needs executable scripts, evidence records, and periodic verification. |
| Personal memory UX/readability | 6/10 | 10/10 | Core has strong data model; browser UI now belongs in separate repo. |
| Governance/review | 7/10 | 10/10 | Proposed/superseded/review concepts exist; needs complete review and promotion workflow. |

## Confirmed current repo contents

The repository currently contains:

- Tier 1 core SQL: `sql/01_core.sql`
- Tier 2 vault SQL: `sql/02_vault.sql`
- Provenance guard SQL: `sql/03_provenance_guards.sql`
- Architecture, security, agent operations, implementation, operations, and pattern docs
- A verified baseline claim against vanilla PostgreSQL 16

## Confirmed live deployment divergence

The live `personal-memory-wiki` database contains additional objects that are not yet fully represented in the repo baseline:

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

The repo is a solid baseline blueprint, but the live system is the current source for the migration/cutover layer. That layer must be reconciled into versioned SQL and docs before the repo can be treated as complete.

## 10/10 blockers

1. Migration/cutover SQL not yet captured in repo.
2. No complete MCP-retirement runbook until now; `docs/07-mcp-retirement-cutover.md` starts that track.
3. No automated validation script that runs all readiness checks against a live DB.
4. No repository-stored evidence record of latest backup/restore rehearsal.
5. Service-role operation remains the practical trust boundary; narrow-role/API hardening is not yet implemented.
6. Production object drift exists between live DB and repo baseline.
7. Review queue and promotion workflow need stronger docs and UI support.
8. No formal release tag declaring a known-good schema version.

## Immediate development order

1. Reconcile live migration/cutover objects into repo SQL.
2. Add cutover/readiness validation script or SQL bundle.
3. Add backup/export/restore evidence template.
4. Add API/narrow-role hardening design.
5. Update implementation guide to include MCP retirement and Supabase-authoritative cutover.
6. Coordinate with Warden/Claude via `model_channel` before applying live DB mutations.

## Rule for this phase

Do not make live schema changes casually. Until the migration/cutover SQL is captured and reviewed, prefer repo docs, issues, and branch work. Live DB changes should be explicit migrations with acceptance tests and Warden review where practical.
