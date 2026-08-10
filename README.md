# Sovereign Memory Core

**A PostgreSQL runtime for AI memory you can audit, move, and prove.**

> **Status: alpha.** Tested on PostgreSQL 15 and 16 in CI on every pull request.
> No live deployment has completed independent acceptance. Read
> [What's not done](#whats-not-done)
> before relying on it for anything that matters.

## The problem, concretely

We examined multi-year ChatGPT and Claude exports from real accounts.

Both returned the conversations. **Neither returned which project a
conversation belonged to.** One returned the project definitions, names,
instructions, attached documents, with no link from any conversation to any of
them.

You get your words back. You do not get your organization of them. That is a
portability gap even when a compliance export exists.

This is not an accusation of bad faith. Export formats are built for compliance,
not continuity. But it means "you can export your data" and "you can leave" are
different claims, and only one of them is usually true.

## What this is

Most memory products optimize **recall**: extract useful facts, retrieve them
for a model. That is a real problem, and specialists solve it better than this
project does.

This project asks a different question, **custody**:

- What was the original evidence, and is this record an observation, a derived
  belief, a proposal, or something a human actually accepted?
- Who changed it, through which runtime and authority path?
- What did it supersede, and what superseded it?
- Can the history be reconstructed independently?
- Can it be exported, restored, verified, corrected, and erased without trusting
  one vendor forever?

**Sovereign Memory Protocol (SMP)** is the implementation-neutral contract for
those questions. **Sovereign Memory Core**, this repository, is the PostgreSQL
reference implementation where those contracts get built and attacked.

It is not a consumer application and not a complete memory product.

## Relationship to memory engines

Engines such as Eywa, Mem0, Zep/Graphiti, Supermemory, and Hindsight handle
extraction, retrieval, ranking, temporal reasoning, and context assembly.

They ask: *what should be remembered, and what context answers this question?*

SMP asks: *what is being held, under whose authority, with what lineage, and can
it be moved, verified, corrected, erased, and restored independently?*

These compose. A memory engine can implement SMP custody contracts. SMP should
not become a retrieval engine. Architecture boundary and an Eywa crosswalk:
[`docs/positioning.md`](docs/positioning.md).

## The three layers

| Layer | Responsibility | In this repo? |
|---|---|---|
| **SMP protocol** | Implementation-neutral custody, provenance, lifecycle, verification, supersession, erasure, portability, conformance | Partly, while the specification repository is prepared |
| **Runtime / core** | PostgreSQL reference implementation, migrations, perimeter enforcement, replay, tests, and export/restore contracts | **Yes** |
| **Deployment** | A particular person's or organization's policies, credentials, adapters, data, and operating evidence | **No** |

Dependencies run one way. Deployments consume a released runtime; runtimes
implement the protocol; the protocol must not depend on PostgreSQL, on a hosted
provider, or on any particular interface.

## Principles

1. **Evidence before belief.** Derived state stays linked to what supports it.
2. **Lock custody facts and preserve history.** Accepted custody-semantic fields
   are write-once in ordinary operation. Corrections append superseding records;
   authorized erasure is explicit, scoped, and auditable.
3. **Custody is not retrieval.** Indexes, summaries, graphs, and hot-memory
   projections are rebuildable views, not independent truth.
4. **Authority is explicit.** Runtime identity, principal, credential path, and
   review authority are separate dimensions, even where current infrastructure
   cannot prove all of them cryptographically.
5. **Time is state.** Observed, recorded, effective, accepted, superseded, and
   reverted are not one timestamp.
6. **Portability must be proven.** Owning the account or the database is not
   sovereignty. Independent export, restore, and verification are.
7. **Protect the data and its meaning.** Content, provenance, chain of custody,
   state history, and interpretive context are the asset.

## Who this is for

| You are | Start here |
|---|---|
| Deciding whether custody matters for your system | [`docs/positioning.md`](docs/positioning.md) |
| Building a memory engine, want a custody substrate | [`docs/positioning.md`](docs/positioning.md), then `sql/` |
| Running it yourself | [Installing](#installing), then [`docs/perimeter.md`](docs/perimeter.md) |
| Reviewing security | [`docs/security-definer-inventory.md`](docs/security-definer-inventory.md) |
| Looking for a chat UI, or a RAG product | This is not it |

## What works

Verified by the [conformance workflow](.github/workflows/work-memory-conformance.yml)
in five jobs across PostgreSQL 15 and 16 on every pull request. See
[recent runs](https://github.com/jryski/sovereign-memory-core/actions/workflows/work-memory-conformance.yml).

- **Lifecycle** — proposals gated on evidence; a rejected record does not block
  its replacement; exactly one winner under concurrent identical replay.
- **History** — append-only events, evidence, and authority records; replay that
  cannot fabricate missing history; revision keys derived from the exact stored
  source revision rather than recomputed guesses.
- **Authority perimeter** — detects privilege granted directly, through role
  inheritance, through membership chains, or via `PUBLIC`; explicit
  SECURITY DEFINER inventory; temporary-object shadowing defenses including a
  probe for the perimeter checker shadowing itself.
- **Upgrade safety** — fresh install on a non-empty database, exact reapply,
  upgrade from the previous reviewed head, and deliberate drift followed by
  remediation.

**These are repository properties, proven by CI.** Whether any particular
deployment has them depends on which migrations that deployment has applied.
The two claims are not the same and this README does not conflate them.

## What's not done

- No live deployment has completed independent acceptance.
- **Export to a portable package and clean restore outside the originating host
  is not yet proven.** This is the central sovereignty claim and it is open.
- No end-to-end erasure proof across projections, logs, traces, exports, and
  backups.
- **A shared database credential cannot cryptographically distinguish a human
  principal from an agent acting under it.** Today this is an audit trail, not
  identity-backed proof. It is a known limitation, not an oversight.
- The attention and work-memory layer is an early reference implementation, not
  a ranking policy anyone should adopt.
- No tagged release, checksums, installer, or deployment profiles beyond the
  reference ones.

## Not in this repository

Personal, household, health, or financial records. Live project identifiers,
credentials, secrets, or private operating evidence. A polished user interface.
A generic RAG or vector-retrieval product. Any mandated model, embedding system,
graph engine, or hosted provider. Private deployment configuration.

The public test corpus is synthetic.

## Installing

There is no one-command install yet. Apply the migrations in order to a
**disposable or backed-up** PostgreSQL database first.

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
sql/11_topology_scope.sql
```

Two ordering rules that will bite you otherwise:

- `07` through `09` are re-runnable fix-forward migrations. If you need to
  reapply them, do it **before** `10`.
- `10` is a one-way hardening boundary for the historical package. Once applied,
  reapply only `10`, never `07` through `09`, because those historical
  definitions deliberately predate the explicit-`pg_temp` contract that `10`
  establishes.
- `11` runs after `10` and is independently re-runnable. It adds the versioned
  topology/search-scope contract without weakening local read-only boot.

`09` closes schema creation, table grants, function execution, default
privileges, RLS and FORCE RLS, ownership, and trigger-only boundaries. `10`
recreates the reviewed SECURITY DEFINER and authority-adjacent helper inventory
with protected names schema-qualified and `pg_temp` listed last.

`11` exposes deployment-neutral, viewer-filtered topology evidence and validated
client-reported search-coverage receipts. It contains no routing endpoints or
credentials. See [`docs/topology-and-search-scope.md`](docs/topology-and-search-scope.md).

Permission profiles, allowlists, and perimeter policy inputs live in
[`docs/perimeter.md`](docs/perimeter.md). Read it before applying to anything
you care about.

## Repository layout

- `sql/` — portable schema and fix-forward migrations
- `docs/` — contracts, security inventory, lifecycle, upgrade guidance
- `tests/` — conformance and adversarial harnesses
- `.github/workflows/` — PostgreSQL 15 and 16 CI

## Further reading

- [`docs/positioning.md`](docs/positioning.md) — custody versus retrieval, Eywa crosswalk
- [`docs/perimeter.md`](docs/perimeter.md) — permission profiles and policy inputs
- [`docs/security-definer-inventory.md`](docs/security-definer-inventory.md)
- [`docs/work-memory.md`](docs/work-memory.md)
- [`docs/attention-layer.md`](docs/attention-layer.md)
- [`docs/upgrades/work-memory-v2.md`](docs/upgrades/work-memory-v2.md)
