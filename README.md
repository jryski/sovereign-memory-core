# Sovereign Memory Core

A personal, self-hosted memory and knowledge layer for AI assistants, built on plain Postgres
(reference deployment: Supabase). It gives every AI you use one shared, verifiable source of
truth that **you** own, instead of a per-vendor memory silo.

This repository is the **core database/schema and operations package**. The browser UI lives separately at `jryski/Personal-Wiki-Memory-UI`.

## Current status

This repo contains the baseline core schema, vault schema, provenance guards, security model,
agent operating contract, build guide, and operations guide.

A live deployment may evolve beyond the baseline scripts with source-import, migration,
readiness, and cutover controls. Those controls should be reconciled back into this repo before
that deployment is treated as reproducible from source.

See:

- [`STATUS.md`](STATUS.md) for current completeness and readiness.
- [`docs/07-source-import-cutover.md`](docs/07-source-import-cutover.md) for the source import and authoritative cutover plan.
- [`docs/08-readiness-scorecard.md`](docs/08-readiness-scorecard.md) for the 10/10 checklist.
- [`docs/09-source-adapters.md`](docs/09-source-adapters.md) for real-world source adapter patterns.
- [`docs/10-chat-mine-source-import-exporter.md`](docs/10-chat-mine-source-import-exporter.md) for the first internal Chat-Mine producer slice.

## Why this exists

1. **Data sovereignty.** Your facts live in a database you control, exportable as plain SQL and
   JSON. Vendor change is a migration, not a hostage negotiation.
2. **Best tool for the job.** Any authorized model or application with a safe Postgres path can read and write
   the same store. Models and apps are clients, not owners.
3. **Verifiable source of truth.** Facts carry provenance. Consequential domains can be guarded
   by the database. Corrections supersede; nothing is silently rewritten.
4. **Operational continuity.** Session boot, hot topics, review queues, model channels, migration
   manifests, cutover probes, and provider-exit tests make continuity something the system can
   verify instead of something a prompt merely asks for.

## What you get

| Layer | What it is | SQL |
|---|---|---|
| Tier 1: Shared knowledge base | Memories, wiki pages, attention index, deadlines, doc integrity, agent registry, and coordination channel | `sql/01_core.sql` |
| Tier 2: Private vault (optional) | Locked schemas for identity / health / finance with temporal truth, preserve-then-normalize import, and an audit change log | `sql/02_vault.sql` |
| Provenance guards (optional) | Triggers that reject financial figures lacking a real source | `sql/03_provenance_guards.sql` |
| Source import/cutover controls | Manifest, freeze or watermark controls, export views, readiness checks, and cutover probes for adopting Sovereign Memory as authoritative | pending reconciliation |

## Repo map

```text
README.md                       you are here
STATUS.md                       current readiness and repo/live divergence
sql/01_core.sql                 Tier 1, one idempotent script
sql/02_vault.sql                Tier 2 private schemas + audit trail
sql/03_provenance_guards.sql    financial provenance enforcement
docs/01-architecture.md         concepts, zones, multi-agent model
docs/02-security-model.md       the actual security boundary, and the traps
docs/03-agent-operations.md     operating contract and assistant setup
docs/04-implementation-guide.md build order with acceptance tests
docs/05-operations.md           backups, restore test, provider-exit test, drift checks
docs/06-patterns.md             transferable design patterns
docs/07-source-import-cutover.md source import and authoritative cutover plan
docs/08-readiness-scorecard.md  10/10 readiness checklist
docs/09-source-adapters.md      real-world import source adapter matrix
docs/10-chat-mine-source-import-exporter.md  internal Chat-Mine package exporter
```

## Quick start for a fresh deployment

1. Create a Supabase project or vanilla Postgres database.
2. Run `sql/01_core.sql` after customizing principals and trusted agents.
3. Optionally run `sql/02_vault.sql` and `sql/03_provenance_guards.sql`.
4. Install the operating contract from `docs/03-agent-operations.md`.
5. Run the acceptance tests in `docs/04-implementation-guide.md`.
6. Run the backup and restore rehearsal in `docs/05-operations.md`.

## Import or migration from an existing source

Do not cut over by assumption.

The prior source might be a file wiki, exported chat history, notes app, spreadsheet,
database, vendor export, AI project export, connector-backed memory store, or another memory system. The cutover must be evidence based:

1. Freeze or watermark the old source.
2. Export raw source records or documents.
3. Preserve raw payloads and hashes.
4. Classify each item into import, hold, exclude, or evidence.
5. Import into the appropriate zone: HOUSE, VAULT, HOLD, or EVIDENCE.
6. Run readiness checks.
7. Run cutover probes.
8. Leave the prior source readable until rollback confidence is high.
9. Declare Sovereign Memory authoritative only after the scorecard passes.

See `docs/07-source-import-cutover.md` and `docs/09-source-adapters.md`.

## Non-goals

- Not a RAG framework, not an agent framework, not a product. It is a data layer with rules.
- No browser UI in this repo. UI development belongs in `jryski/Personal-Wiki-Memory-UI`.
- Vector search is optional and treated as regenerable cache, never as the system of record.

## Requirements

- Postgres 15+ (Supabase hosted or any Postgres you run)
- At least one assistant, application, or service that can execute approved SQL/RPCs
- Basic comfort applying SQL migrations and verifying acceptance tests

## Verified baseline

The baseline SQL scripts were applied end to end on vanilla PostgreSQL 16 with shim roles
(`anon`, `authenticated`, `service_role`) and the acceptance tests in
`docs/04-implementation-guide.md` were executed: perimeter assert, second-touch promotion,
session_boot, supersede + audit, delete-guard rejection, channel round trip, vault audit
triggers with zero grant leaks, and the provenance fail/pass/pass triple.

An active production system can contain additional migration/cutover objects not yet fully
reconciled into this repo. `STATUS.md` tracks that type of gap.

## License / provenance

Extracted from a private working system, genericized. Use freely. No warranty; read
`docs/02-security-model.md` before putting anything sensitive in it.
