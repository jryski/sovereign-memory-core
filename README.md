# Sovereign Memory Core

A personal, self-hosted memory and knowledge layer for AI assistants, built on plain Postgres
(reference deployment: Supabase). It gives every AI you use one shared, verifiable source of
truth that **you** own, instead of a per-vendor memory silo.

This repository is the **core database/schema and operations package**. Any browser UI
should live in a separate application repository.

## Current status

This repo contains the baseline core schema, vault schema, provenance guards, security model,
agent operating contract, build guide, operations guide, merged source-import/cutover foundation,
authority-gated agent work memory, and an append-only attention-event substrate.

The core includes generic source staging, manifest review, candidate-level provenance,
readiness checks, richer cutover probes, typed work-lesson evidence custody, and exact
character-budget attention presentation. Chat-Mine is a research-grade emitter aligned with
the source-import contract; its current deterministic fixture does not prove mining quality on
real, long-running conversations. Review UI, operator tooling, adapters for real source exports,
and a production attention-ranking law remain future work.

See:

- [`docs/00-north-star.md`](docs/00-north-star.md) for the trustworthy memory transfer doctrine and research boundaries.
- [`docs/roadmap.md`](docs/roadmap.md) for milestones, release targets, and track separation.
- [`docs/project-management.md`](docs/project-management.md) for the GitHub-native operating model.
- [`STATUS.md`](STATUS.md) for current completeness and readiness.
- [`docs/work-memory.md`](docs/work-memory.md) for authority-gated agent operating experience.
- [`docs/attention-layer.md`](docs/attention-layer.md) for the attention-event and presentation contract.
- [`docs/upgrades/work-memory-v2.md`](docs/upgrades/work-memory-v2.md) for live-deployment upgrade sequencing.
- [`docs/publication/smp-custody-layer.md`](docs/publication/smp-custody-layer.md) for the Draft 0.3 SMP custody-layer specification.
- [`docs/publication/smp-conformance-gap-audit.md`](docs/publication/smp-conformance-gap-audit.md) for the Draft 0.3 conformance gap audit.
- [`docs/07-source-import-cutover.md`](docs/07-source-import-cutover.md) for the source import and authoritative cutover plan.
- [`docs/08-readiness-scorecard.md`](docs/08-readiness-scorecard.md) for the 10/10 checklist.
- [`docs/09-source-adapters.md`](docs/09-source-adapters.md) for real-world source adapter patterns.
- [`docs/10-chat-mine-source-import-exporter.md`](docs/10-chat-mine-source-import-exporter.md) for the first internal Chat-Mine producer slice.
- [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md), and [`SUPPORT.md`](SUPPORT.md) for contribution, security, and support expectations.

## Why this exists

1. **Data sovereignty.** Your facts live in a database you control, exportable as plain SQL and
   JSON. Vendor change is a migration, not a hostage negotiation.
2. **Best tool for the job.** Any authorized model or application with a safe Postgres path can read and write
   the same store. Models and apps are clients, not owners.
3. **Verifiable source of truth.** Facts carry provenance. Consequential domains can be guarded
   by the database. Corrections supersede; nothing is silently rewritten.
4. **Operational continuity.** Session boot, attention projections, work lessons, review queues,
   model channels, migration manifests, cutover probes, and provider-exit tests make continuity
   something the system can verify instead of something a prompt merely asks for.

## What you get

| Layer | What it is | SQL |
|---|---|---|
| Tier 1: Shared knowledge base | Memories, wiki pages, baseline attention state, deadlines, doc integrity, agent registry, and coordination channel | `sql/01_core.sql` |
| Tier 2: Private vault (optional) | Locked schemas for identity / health / finance with temporal truth, preserve-then-normalize import, and an audit change log | `sql/02_vault.sql` |
| Provenance guards (optional) | Triggers that reject financial figures lacking a real source | `sql/03_provenance_guards.sql` |
| Source import/cutover foundation | Source registry, import batches, raw evidence, manifest review, readiness checks, and cutover scorecards | `sql/04_source_import.sql` |
| Candidate provenance | Candidate-level source locators, support quotes, and quote hashes for one-item-to-many-candidate imports | `sql/05_candidate_locators.sql` |
| Richer cutover probes | Positive, negative, conflict, stale-state, and evidence-request probe categories | `sql/06_cutover_probe_categories.sql` |
| Agent work memory | Proposed/accepted lesson lifecycle, typed evidence custody, append-only authority events, and deterministic behavioral boot fragment | `sql/07_work_lessons.sql` |
| Attention events and projection | Append-only native observations, linked revisions and assignments, non-destructive topic indexing, and exact character-budget boot presentation | `sql/08_attention_events.sql` |

## Repo map

```text
README.md                       you are here
STATUS.md                       current readiness and repo/live divergence
sql/01_core.sql                 Tier 1 baseline core
sql/02_vault.sql                Tier 2 private schemas + audit trail
sql/03_provenance_guards.sql    financial provenance enforcement
sql/04_source_import.sql        source-import and cutover foundation
sql/05_candidate_locators.sql   candidate locators and quote hashes
sql/06_cutover_probe_categories.sql  richer cutover probe categories
sql/07_work_lessons.sql         authority-gated work-memory contract
sql/08_attention_events.sql     attention events, revisions, and boot projection
tests/07_work_lessons.sql       rollback-only work-memory conformance
tests/08_attention_events.sql   rollback-only attention conformance
docs/00-north-star.md           trustworthy memory transfer doctrine
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
docs/work-memory.md             agent operating-experience contract
docs/attention-layer.md         attention substrate and presentation contract
docs/upgrades/work-memory-v2.md reviewed live-upgrade sequence
docs/publication/smp-custody-layer.md        Draft 0.3 custody-layer specification
docs/publication/smp-conformance-gap-audit.md Draft 0.3 conformance gap audit
docs/roadmap.md                 milestones, release targets, and tracks
docs/project-management.md      GitHub-native roadmap, labels, issues, and ADR model
.github/workflows/work-memory-conformance.yml PostgreSQL 15/16 CI gate
CONTRIBUTING.md                 contribution and validation expectations
SECURITY.md                     sensitive-reporting and live-state safety
SUPPORT.md                      early-alpha support expectations
```

## Quick start for a fresh deployment

1. Create a Supabase project or vanilla Postgres database.
2. Run `sql/01_core.sql` after customizing principals and trusted agents.
3. Optionally run `sql/02_vault.sql` and `sql/03_provenance_guards.sql`.
4. Run `sql/04_source_import.sql` through `sql/06_cutover_probe_categories.sql` when source migration is required.
5. Run `sql/07_work_lessons.sql` and `sql/08_attention_events.sql` for work memory and attention v2.
6. Install the operating contract from `docs/03-agent-operations.md`.
7. Run the acceptance tests in `docs/04-implementation-guide.md` plus `tests/07_work_lessons.sql` and `tests/08_attention_events.sql`.
8. Run the backup and restore rehearsal in `docs/05-operations.md`.

For an existing deployment, read `docs/upgrades/work-memory-v2.md` first. The v2 SQL files describe the fresh-install target and are not blind production migrations.

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
- No browser UI in this repo. UI development belongs in a separate application repository.
- Vector search is optional and treated as regenerable cache, never as the system of record.
- The attention event schema does not select a final ranking or decay law.
- A shared runtime credential is not cryptographic proof of human authority.

## Requirements

- Postgres 15+ (Supabase hosted or any Postgres you run)
- At least one assistant, application, or service that can execute approved SQL/RPCs
- Basic comfort applying SQL migrations and verifying acceptance tests

## Verification

The work-memory workflow runs the fresh-install core, SQL 07, SQL 08, and both rollback-only conformance suites against PostgreSQL 15 and 16. It also verifies the external perimeter and checks that no synthetic fixtures remain.

Live deployments still require deployment-specific catalog, grant, viewer-isolation, backup, and restore checks. Passing portable CI is necessary but not proof that a particular production upgrade was applied correctly.

## License / provenance

Published as a generic reference implementation. Use freely. No warranty; read
`docs/02-security-model.md` before putting anything sensitive in it.
