# Sovereign Memory Core

A personal, self-hosted memory and knowledge layer for AI assistants, built on plain Postgres
(reference deployment: Supabase). It gives every AI you use one shared, verifiable source of
truth that **you** own, instead of a per-vendor memory silo.

This repository is the **core database/schema and operations package**. Any browser UI
should live in a separate application repository.

## Current status

This repo contains the baseline core schema, vault schema, provenance guards, security model,
agent operating contract, build guide, operations guide, and the merged source-import/cutover
foundation.

The core now includes generic source staging, manifest review, candidate-level provenance,
readiness checks, and richer cutover probes. Chat-Mine is a research-grade emitter aligned with
that contract; its current deterministic fixture does not prove mining quality on real,
long-running conversations. Review UI, operator tooling, adapters for real source exports, and
operational dry runs remain future work.

See:

- [`docs/00-north-star.md`](docs/00-north-star.md) for the trustworthy memory transfer doctrine and research boundaries.
- [`docs/roadmap.md`](docs/roadmap.md) for milestones, release targets, and track separation.
- [`docs/project-management.md`](docs/project-management.md) for the GitHub-native operating model.
- [`STATUS.md`](STATUS.md) for current completeness and readiness.
- [`docs/publication/smp-custody-layer.md`](docs/publication/smp-custody-layer.md) for the Draft 0.3 SMP custody-layer specification.
- [`docs/publication/smp-conformance-gap-audit.md`](docs/publication/smp-conformance-gap-audit.md) for the Draft 0.3 conformance gap audit.
- [`docs/07-source-import-cutover.md`](docs/07-source-import-cutover.md) for the source import and authoritative cutover plan.
- [`docs/08-readiness-scorecard.md`](docs/08-readiness-scorecard.md) for the 10/10 checklist.
- [`docs/09-source-adapters.md`](docs/09-source-adapters.md) for real-world source adapter patterns.
- [`docs/10-chat-mine-source-import-exporter.md`](docs/10-chat-mine-source-import-exporter.md) for the first internal Chat-Mine producer slice.
- [`docs/11-installer-roadmap.md`](docs/11-installer-roadmap.md) for the future local/cloud installer and custody verification gate.
- [`docs/12-custody-receipt.md`](docs/12-custody-receipt.md) for the clean restore, layered verification, and custody receipt contract.
- [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md), and [`SUPPORT.md`](SUPPORT.md) for contribution, security, and support expectations.

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
| Source import/cutover foundation | Source registry, import batches, raw evidence, manifest review, readiness checks, and cutover scorecards | `sql/04_source_import.sql` |
| Candidate provenance | Candidate-level source locators, support quotes, and quote hashes for one-item-to-many-candidate imports | `sql/05_candidate_locators.sql` |
| Richer cutover probes | Positive, negative, conflict, stale-state, and evidence-request probe categories | `sql/06_cutover_probe_categories.sql` |

## Repo map

```text
README.md                       you are here
STATUS.md                       current readiness and repo/live divergence
sql/01_core.sql                 Tier 1, one idempotent script
sql/02_vault.sql                Tier 2 private schemas + audit trail
sql/03_provenance_guards.sql    financial provenance enforcement
sql/04_source_import.sql        source-import and cutover foundation
sql/05_candidate_locators.sql   candidate locators and quote hashes
sql/06_cutover_probe_categories.sql  richer cutover probe categories
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
docs/11-installer-roadmap.md    installer and productization roadmap
docs/12-custody-receipt.md      clean restore and custody receipt contract
docs/publication/smp-custody-layer.md        Draft 0.3 custody-layer specification
docs/publication/smp-conformance-gap-audit.md Draft 0.3 conformance gap audit
docs/roadmap.md                 milestones, release targets, and tracks
docs/project-management.md      GitHub-native roadmap, labels, issues, and ADR model
docs/adr/                       architecture decision records
CONTRIBUTING.md                 contribution and validation expectations
SECURITY.md                     sensitive-reporting and live-state safety
SUPPORT.md                      early-alpha support expectations
.github/ISSUE_TEMPLATE/         issue templates
.github/pull_request_template.md pull request checklist
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
- No browser UI in this repo. UI development belongs in a separate application repository.
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

The source-import/cutover suite also verifies required objects, security-definer search paths,
grant posture, fixture rollback, and fatal readiness blockers. Candidate locator/quote-hash
coverage and all five richer cutover probe categories are included in that gate. The first
internal Chat-Mine producer slice additionally validates deterministic package output,
one-source-item-to-many-candidate mapping, candidate quote hashes, and a rollback-only load into
the merged core schema.

## License / provenance

Published as a generic reference implementation. Use freely. No warranty; read
`docs/02-security-model.md` before putting anything sensitive in it.