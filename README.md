# Sovereign Memory Core

**A portable PostgreSQL reference runtime for AI memory that remains auditable, recoverable, and under the data owner's control.**

> **Status: alpha.** The core data model, lifecycle, provenance, replay, and security perimeter have substantial automated coverage. Live deployment acceptance and independent export/restore proof are still being completed.

## Why this exists

AI assistants increasingly remember preferences, decisions, relationships, project history, and prior work. Most memory products focus on **recall**: extracting useful facts and retrieving them for a model.

Recall is important, but it is not the whole problem.

A durable memory system should also be able to answer:

- What was the original evidence?
- Is this an observed statement, a derived belief, a proposal, or an accepted record?
- Who or what changed it, through which runtime and authority path?
- What did this record supersede, and what superseded it?
- Can the current state and its history be independently reconstructed?
- Can the data be exported, restored, verified, corrected, or erased without trusting one vendor forever?
- Can a different model, application, retrieval engine, or database consume the same custody record?

**Sovereign Memory Protocol (SMP)** is the emerging implementation-neutral contract for those custody questions. **Sovereign Memory Core** is the PostgreSQL reference runtime where those contracts are being implemented and adversarially tested.

This repository is not a consumer application and it is not a complete memory product. It is the reference machinery for preserving evidence, provenance, lifecycle, authority boundaries, and reconstructable history.

## The three project layers

| Layer | Responsibility | This repository? |
|---|---|---|
| **SMP protocol** | Implementation-neutral custody, provenance, lifecycle, verification, supersession, erasure, portability, and conformance rules | Partly documented here while the dedicated specification repository is prepared |
| **Sovereignty runtime / core** | PostgreSQL reference implementation, migrations, perimeter enforcement, replay, tests, export/restore tooling | **Yes** |
| **Deployment** | A particular person's, household's, or organization's private policies, credentials, adapters, data, and operating evidence | **No** |

The dependency direction is one-way: deployments consume a released runtime; runtimes implement the protocol; the protocol must not depend on PostgreSQL, Supabase, a household deployment, or a particular user interface.

## How this differs from a memory engine

Memory engines such as Eywa, Mem0, Zep/Graphiti, Supermemory, Hindsight, and similar systems focus on some combination of extraction, retrieval, ranking, temporal reasoning, graph structure, and answer-time context assembly.

SMP is complementary. It does not prescribe which retriever, embedding model, graph, vector store, answer model, or user interface should be used.

A memory engine asks:

> What should be remembered, and what context should be retrieved for this question?

SMP asks:

> What evidence and state are being held, under whose authority, with what lineage, and can they be moved, verified, corrected, erased, and restored independently?

A memory engine can implement SMP custody contracts. SMP should not become a competing retrieval engine.

See [`docs/positioning.md`](docs/positioning.md) for the architecture boundary and an Eywa crosswalk.

## Core principles

1. **Evidence before belief.** Derived state must remain linked to the evidence that supports it.
2. **Preserve history.** Correct, supersede, reconcile, or invalidate; do not silently rewrite the past.
3. **Separate custody from retrieval.** Search indexes, summaries, graphs, and hot-memory projections are rebuildable views, not independent truth.
4. **Authority must be explicit.** Runtime identity, principal, credential path, and review authority are separate dimensions, even when current infrastructure cannot prove all of them cryptographically.
5. **Time is part of state.** Observed, recorded, effective, accepted, superseded, and reverted times must not be collapsed into one timestamp.
6. **Portability must be proven.** Owning an account or hosted database is not sovereignty; independent export, restore, verification, and provider exit are required.
7. **Protect the data and its meaning.** Content, provenance, chain of custody, state history, and interpretive context are the protected asset.

## What works today

The current runtime and test suite cover:

- evidence-backed, proposal-gated work lessons;
- readable rejected successors that do not block a replacement proposal;
- generic public evidence locators without private deployment references;
- creation and activation events emitted only by their real source transitions;
- existence-only runtime replay that cannot fabricate missing history;
- revision keys derived from the exact persisted source revision;
- append-only generated events, evidence, and authority records;
- current observer attribution on appended revisions, with shared-runtime limitations stated honestly;
- one winner under concurrent identical replay;
- bounded fixed-point context-budget accounting;
- effective stale-grantee detection across direct, inherited, membership-chain, and `PUBLIC` authority;
- explicit SECURITY DEFINER inventory and temporary-object shadowing defenses;
- fresh install, reapply, upgrade, concurrency, drift, remediation, and adversarial testing on PostgreSQL 15 and 16.

## What remains incomplete

The following are active alpha gates or known limitations:

- independent live HOUSE deployment acceptance of the merged runtime;
- export into a deterministic package and clean restoration outside the originating hosted project;
- executable drift inventory, release manifest, checksums, and tagged alpha release;
- proof-grade distinction between a human principal and agents sharing one privileged credential path;
- broader deployment profiles and user-facing installation tooling;
- end-to-end erasure proof across projections, logs, traces, exports, and backups;
- the attention/work-memory layer remains an early reference implementation, not a universal ranking policy.

## What is deliberately not in this repository

- personal, household, health, or financial records;
- live project identifiers, credentials, secrets, or private operational evidence;
- a polished consumer user interface;
- a generic RAG or vector-retrieval product;
- a mandated model, embedding system, graph engine, or hosted provider;
- private deployment configuration.

The public test corpus is synthetic.

## Repository contents

- `sql/` — portable PostgreSQL schema and fix-forward migrations
- `docs/` — contracts, security inventory, lifecycle, attention, and upgrade guidance
- `tests/` — conformance and adversarial test harnesses
- `.github/workflows/` — PostgreSQL 15/16 CI

## Quick start

Review the migrations and apply them in order to a disposable or backed-up PostgreSQL database first.

```text
sql/01_core.sql
sql/02_vault_tier2.sql              # optional
sql/03_document_ingest.sql          # optional
sql/04_migration_foundation.sql     # optional
sql/05_candidate_locators.sql       # optional
sql/06_cutover_probe_categories.sql # optional
sql/07_work_lessons.sql
sql/08_attention_events.sql
sql/09_perimeter_refresh.sql
sql/10_security_definer_hardening.sql
```

`07`, `08`, and `09` are re-runnable legacy fix-forward migrations and must be reapplied, if needed, before `10`. `09` closes schema creation, table grants, function execution, default privileges, RLS/FORCE RLS, owner, and trigger-only boundaries.

`10` is a re-runnable, one-way hardening boundary and must run last. After it has been applied, reapply `10` only—not `07` through `09`—because those historical definitions intentionally predate the explicit-`pg_temp` contract. `10` recreates the exact reviewed SECURITY DEFINER and authority-adjacent helper inventory with protected names qualified and `pg_temp` explicit last.

See [`docs/security-definer-inventory.md`](docs/security-definer-inventory.md).

## Perimeter policy inputs

Migration `09` audits every effective role, not only familiar platform role names. It classifies direct, inherited membership-chain, and `PUBLIC`-derived `CREATE` and `EXECUTE` authority, plus owner-scoped table, sequence, and function defaults that would affect future objects.

Its protected-schema and authority-function registries bound remediation to Sovereign Memory surfaces; unrelated schemas, functions, and owner/schema defaults are not silently absorbed. Every non-system schema in an explicitly registered authority function's fixed `search_path` must itself be present in the protected-schema registry, or the assertion fails closed before remediation.

The default `portable` profile permits no non-owner schema creation or function execution. Deployments using the repository's Supabase grants must explicitly persist the scoped profile before applying the package:

```sql
alter database your_database
  set sovereign_memory.perimeter_profile = 'supabase';
```

The `supabase` profile permits `service_role` only on non-internal authority functions. It never waives trigger-only/internal writers or schema `CREATE`.

Other deployments can declare comma-separated effective-principal allowlists with:

- `sovereign_memory.perimeter_allowed_owner_roles`
- `sovereign_memory.perimeter_allowed_schema_create_roles`
- `sovereign_memory.perimeter_allowed_function_execute_roles`
- `sovereign_memory.perimeter_allowed_internal_execute_roles`

The owner-run migration snapshots these inputs into an ACL-protected durable policy row. Runtime assertions read that row, not caller-controlled custom GUCs.

`sovereign_memory.perimeter_acl_mode` is `revoke` by default: direct grants outside policy are revoked and the effective audit then fails if authority still remains. Set it to `fail` for audit-only deployment gates. An allowlist entry is a deliberate platform waiver; the audit still enumerates all roles, so it is not an assertion blind spot.

Owner-global default privileges are a separate operator boundary because they apply in every schema where that owner creates objects. Migration `09` reports these as `global_default_*` violations in both modes and never revokes them. Operators must establish the intended global baseline for each allowed owner, for example:

```sql
alter default privileges for role your_owner
  revoke execute on functions from public;
```

A schema-scoped default can add privileges but cannot negate a global grant. `revoke` mode therefore repairs only schema-scoped defaults in explicitly registered protected schemas. Unrelated owners' global defaults are not read or mutated by this repository migration.

## Conformance coverage

GitHub Actions tests PostgreSQL 15 and 16 for:

- fresh installation on a non-empty database;
- runtime-role adversarial paths;
- reject-then-replace lifecycle;
- independent revision-key recomputation;
- fixed-point boundaries at 9/10, 99/100, 999/1000, and 9999/10000;
- multibyte, escaped, and tight-budget payloads;
- migration reapplication;
- deliberate drift followed by remediation;
- arbitrary direct, inherited, and `PUBLIC` stale-grantee drift;
- owner-scoped default ACL drift and future-object inheritance;
- runtime GUC spoof attempts and unrelated SECURITY DEFINER negative fixtures;
- portable-profile fresh apply and exact reapply;
- executable upgrade from the previous reviewed head;
- concurrent identical revision replay;
- final perimeter closure;
- exact SECURITY DEFINER inventory;
- omitted, misordered, untrusted, checker-self-shadow, and privileged-write temp-shadow probes.

## Further reading

- [`docs/work-memory.md`](docs/work-memory.md)
- [`docs/attention-layer.md`](docs/attention-layer.md)
- [`docs/security-definer-inventory.md`](docs/security-definer-inventory.md)
- [`docs/upgrades/work-memory-v2.md`](docs/upgrades/work-memory-v2.md)
- [`docs/positioning.md`](docs/positioning.md)
