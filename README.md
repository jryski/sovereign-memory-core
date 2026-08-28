# Sovereign Memory Core

**PostgreSQL reference runtime for Sovereign Memory Protocol semantics.**

> **Current release: `v0.3-alpha`** at commit `c96b9da749b2d95661973485b2a026897329c8cd`.
> The release is intentionally bounded: it carries reviewed PostgreSQL 15/16 conformance/provider-exit evidence plus a separately scoped HOUSE recovery rehearsal. Read the release notes and known limitations before relying on any claim outside that surface.

## What this repository is

Sovereign Memory Core is the **PostgreSQL reference implementation** for a broader Sovereign Memory program.

It implements and attacks concrete mechanisms for:

- provenance and custody;
- lifecycle/supersession;
- authority-adjacent write paths;
- append-only evidence/events;
- perimeter evaluation;
- export/restore/provider-exit evidence;
- implementation conformance and adversarial testing.

It is not a consumer application, not a generic RAG product, and not the normative protocol repository.

## Program relationship

| Layer | Owns | This repo? |
| --- | --- | --- |
| **Sovereign Memory Protocol (SMP)** | Implementation-neutral meaning, assurance, conformance, custody/provenance semantics, claim limits | **No** — separate protocol repository |
| **Sovereign Memory Core** | PostgreSQL reference mechanisms, migrations, perimeter, replay, restore/provider-exit, implementation tests | **Yes** |
| **Capability/data-plane adapters** | Authenticated user/agent access into specific platforms | No |
| **Deployments/applications** | Local identity, policy, topology, UI, credentials, operating evidence | No |

Dependencies run downward. Core implements protocol semantics; it does not define SMP merely because PostgreSQL was the first reference substrate.

## Why this exists

Most AI-memory products optimize recall: extraction, retrieval, ranking, temporal reasoning, context assembly.

Core asks a different question: **custody**.

- What evidence supports this record?
- Is it an observation, derived belief, proposal, or accepted state?
- What superseded it?
- Who or what had authority to change it?
- Can the history be reconstructed independently?
- Can the implementation be exported, restored, verified, corrected, and erased without trusting one provider forever?

Formats can move bytes while losing authority, lineage, and context. Core exists to make one concrete implementation of those properties executable and adversarially testable.

## Relationship to existing/legacy systems

The SMP protocol project is evaluating an informative **Agent Access Integrity Boundary** concept for introducing agents to existing systems of record **in situ** rather than forcing data migration first.

The proposed protocol direction is a forward T0 evidence boundary: observe and commit a protected surface before agent access, then evaluate post-T0 change, attribution, continuity, and authority under explicit assurance limits.

Core may eventually provide a PostgreSQL substrate/reference profile for that concept: catalog/privilege enumeration, canonical snapshot/root construction, transaction/change-log continuity, effective read-only evaluation, restore/failover continuity, and synthetic conformance fixtures.

Those PostgreSQL mechanics belong in the reference/profile layer. They are **not** yet normative SMP requirements, and a T0 root would not prove the pre-T0 data was historically correct or untampered.

## v0.3-alpha verified surface

The release record for `v0.3-alpha` includes:

- work-memory conformance on PostgreSQL 15 and 16;
- C1 perimeter evaluability on PostgreSQL 15 and 16;
- C2 independent clean provider-exit restore on PostgreSQL 16;
- executable schema-drift comparison;
- release manifest/checksum verification;
- immutable baseline reconciliation evidence;
- independent exact-coordinate reviews;
- a HOUSE rollback-safe recovery rehearsal with explicit scope limits.

These are release-evidence claims for the reviewed coordinate. They do not imply every downstream deployment is aligned merely because it uses this code.

### Important recovery/provider-exit limits

- Declared provider-exit support in the alpha remains PostgreSQL 15/16.
- The HOUSE PostgreSQL 17.10 rehearsal preserved a complete logical anchor but exercised a partial household-owned `public` restore in the approved plain-PostgreSQL lab because a hosted extension dependency was unavailable there.
- The HOUSE rehearsal did not reconstruct provider-managed hosted schemas, hosted roles, or hosted-role ACL state.
- Integrity receipts establish the bytes/evidence they name; they do not prove external truth, latestness, or completeness beyond declared coverage.

See the [`v0.3-alpha` release](https://github.com/jryski/sovereign-memory-core/releases/tag/v0.3-alpha) and attached `KNOWN_LIMITATIONS.md`/release evidence.

## Principles

1. **Evidence before belief.** Derived state stays linked to what supports it.
2. **History changes by append.** Corrections and lifecycle changes preserve prior recorded evidence.
3. **Custody is not retrieval.** Indexes, summaries, graphs, caches, and rankings are rebuildable projections.
4. **Authority is multidimensional.** Principal, runtime, credential, client, proposer, reviewer, and authorizer are distinct claims.
5. **Time is multidimensional.** Observed, effective, recorded, verified, anchored, and restored time are not interchangeable.
6. **PASS requires evaluability.** Empty output or zero findings are not proof unless the required population was actually evaluated.
7. **Portability must be proven.** Owning an account/database is not provider exit; an independent restore is evidence.
8. **Deployment policy stays downstream.** Private topology, identities, and local operating rules do not become reusable Core semantics by accident.

## What is not in this repository

- real personal/household/business payloads;
- production project identifiers or credentials;
- private deployment topology or operational receipts;
- a user-facing application;
- a universal memory schema or retrieval engine;
- a normative claim that PostgreSQL mechanisms define SMP.

The public test corpus is synthetic.

## Installing / migration order

Apply migrations only to a disposable or backed-up database first.

```text
sql/01_core.sql
sql/02_vault.sql                       optional
sql/03_provenance_guards.sql           optional
sql/04_source_import.sql               optional
sql/05_candidate_locators.sql          optional
sql/06_cutover_probe_categories.sql    optional
sql/07_work_lessons.sql
sql/08_attention_events.sql
sql/09_perimeter_refresh.sql
sql/10_security_definer_hardening.sql
sql/11_perimeter_evaluability.sql
```

Read [`docs/perimeter.md`](docs/perimeter.md), [`docs/perimeter-evaluability.md`](docs/perimeter-evaluability.md), and the current release notes before applying this to anything important. Do not assume a downstream deployment has the same perimeter or migration state as the reference repository.

## Repository layout

- `sql/` — PostgreSQL schema and fix-forward migrations
- `docs/` — contracts, perimeter/security inventory, lifecycle, upgrade/recovery guidance
- `tests/` — conformance and adversarial harnesses
- `.github/workflows/` — PostgreSQL CI and release-evidence workflows

## Current roadmap

The old memory-only milestone sequence has been superseded by the actual program state. See [`docs/roadmap.md`](docs/roadmap.md).

Near-term Core work should focus on:

- successor hardening after `v0.3-alpha` without widening the alpha claim retroactively;
- alignment with the separate SMP protocol draft and implementation self-description;
- generic substrate-profile/reference work for agent-access integrity and external data planes;
- keeping deployment-specific HOUSE/VAULT behavior out of public reusable Core;
- preserving exact evidence and independent restore/perimeter discipline as features evolve.
