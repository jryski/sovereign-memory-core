# Sovereign Memory Core

A personal, self-hosted memory and knowledge layer for AI assistants, built on plain Postgres
(reference deployment: Supabase). It gives every AI you use (Claude, ChatGPT, local models)
one shared, verifiable source of truth that **you** own, instead of a per-vendor memory silo.

This repository is the **core database/schema and operations package**. The browser UI now lives separately at `jryski/Personal-Wiki-Memory-UI`.

## Current status

This repo contains the baseline core schema, vault schema, provenance guards, security model,
agent operating contract, build guide, and operations guide.

The live `personal-memory-wiki` deployment has already evolved beyond the baseline scripts and now includes migration/cutover controls used to retire unreliable `mcp_memory` and `mcp_wiki` paths. Those controls are being reconciled back into this repo before Supabase becomes the authoritative memory path.

See:

- [`STATUS.md`](STATUS.md) for current completeness and readiness.
- [`docs/07-mcp-retirement-cutover.md`](docs/07-mcp-retirement-cutover.md) for the migration-off-MCP plan.
- [`docs/08-readiness-scorecard.md`](docs/08-readiness-scorecard.md) for the 10/10 checklist.

## Why this exists

1. **Data sovereignty.** Your facts live in a database you control, exportable as plain SQL and
   JSON. Vendor change is a migration, not a hostage negotiation.
2. **Best tool for the job.** Any authorized model with a safe Postgres path can read and write
   the same store. Claude, ChatGPT, local models, and future agents are clients, not owners.
3. **Verifiable source of truth.** Facts carry provenance. Consequential domains can be guarded
   by the database. Corrections supersede; nothing is silently rewritten.
4. **Operational continuity.** Session boot, hot topics, review queues, model channels, migration
   manifests, cutover probes, and provider-exit tests make continuity something the system can
   verify instead of something a prompt merely asks for.

## What you get

| Layer | What it is | SQL |
|---|---|---|
| Tier 1: Shared knowledge base | Memories, wiki pages, attention (hot) index, deadlines, doc integrity, agent registry, cross-assistant task channel | `sql/01_core.sql` |
| Tier 2: Private vault (optional) | Locked schemas for identity / health / finance with temporal truth, preserve-then-normalize import, and an audit change log | `sql/02_vault.sql` |
| Provenance guards (optional) | Triggers that reject financial figures lacking a real source | `sql/03_provenance_guards.sql` |
| Migration/cutover controls | Manifest, freeze controls, export views, readiness checks, and cutover probes for retiring older memory systems | pending reconciliation |

## Repo map

```text
README.md                     you are here
STATUS.md                     current readiness and repo/live divergence
sql/01_core.sql               Tier 1, one idempotent script
sql/02_vault.sql              Tier 2 private schemas + audit trail
sql/03_provenance_guards.sql  financial provenance enforcement
docs/01-architecture.md       concepts, zones, multi-agent model
docs/02-security-model.md     the actual security boundary, and the traps
docs/03-agent-operations.md   the operating contract + Claude/ChatGPT setup, paste-ready
docs/04-implementation-guide.md  build order with acceptance tests (agent-executable)
docs/05-operations.md         backups, restore test, provider-exit test, drift checks
docs/06-patterns.md           transferable design patterns
docs/07-mcp-retirement-cutover.md  migration-off-MCP plan
docs/08-readiness-scorecard.md     10/10 readiness checklist
```

## Quick start for a fresh deployment

1. Create a Supabase project or vanilla Postgres database.
2. Run `sql/01_core.sql` after customizing principals and trusted agents.
3. Optionally run `sql/02_vault.sql` and `sql/03_provenance_guards.sql`.
4. Install the operating contract from `docs/03-agent-operations.md`.
5. Run the acceptance tests in `docs/04-implementation-guide.md`.
6. Run the backup and restore rehearsal in `docs/05-operations.md`.

## Migration from `mcp_memory` / `mcp_wiki`

Do not cut over by vibes.

The cutover must be evidence based:

1. Freeze or watermark the old source.
2. Export raw source rows.
3. Preserve raw payloads and hashes.
4. Classify each row into import, hold, exclude, or evidence.
5. Import into HOUSE, VAULT, or evidence zones.
6. Run readiness checks.
7. Run cutover probes.
8. Leave old MCP systems read-only until rollback confidence is high.
9. Declare Supabase authoritative only after the scorecard passes.

See `docs/07-mcp-retirement-cutover.md`.

## Non-goals

- Not a RAG framework, not an agent framework, not a product. It is a data layer with rules.
- No browser UI in this repo. UI development belongs in `jryski/Personal-Wiki-Memory-UI`.
- Vector search is optional and treated as regenerable cache, never as the system of record.

## Requirements

- Postgres 15+ (Supabase hosted or any Postgres you run)
- At least one AI assistant or service that can execute approved SQL/RPCs
- Basic comfort applying SQL migrations and verifying acceptance tests

## Verified baseline

The baseline SQL scripts were applied end to end on vanilla PostgreSQL 16 with shim roles
(`anon`, `authenticated`, `service_role`) and the acceptance tests in
`docs/04-implementation-guide.md` were executed: perimeter assert, second-touch promotion,
session_boot, supersede + audit, delete-guard rejection, channel round trip, vault audit
triggers with zero grant leaks, and the provenance fail/pass/pass triple.

The active production system contains additional migration/cutover objects not yet fully
reconciled into this repo. `STATUS.md` tracks that gap.

## License / provenance

Extracted from a private working system, genericized. Use freely. No warranty; read
`docs/02-security-model.md` before putting anything sensitive in it.
