# Sovereign Memory Core

**A PostgreSQL runtime for AI memory you can audit, move, and prove.**

> **Status: alpha.** Tested on PostgreSQL 15 and 16 in CI on every pull request.
> The v0.3-alpha provider-exit rehearsal proves package and restore on a
> representative synthetic source. See
> [`release/v0.3-alpha-known-limitations.md`](release/v0.3-alpha-known-limitations.md).
> No live deployment has completed independent acceptance. Read
> [What's not done](#whats-not-done)
> before relying on it for anything that matters.
> Current program pointers, including the open recovery hold, are in
> [`STATUS.md`](STATUS.md).

## Orientation: purpose, place and first test

A short map for people and AI assistants arriving here first. Each row links
the source that supports it.

| Question | Answer |
| --- | --- |
| What is this? | The PostgreSQL reference implementation for custody: evidence, history, an authority perimeter and export/restore ([what this is](#what-this-is)). It is not a consumer application or a retrieval engine. |
| Where does it fit? | The durable evidence and history foundation in the [Sovereign AI OS program map](https://github.com/WireSpeedComputing/sovereign-ai-os) ([component routes](https://github.com/WireSpeedComputing/sovereign-ai-os/blob/main/ROUTES.md), [program role](PROGRAM-ROLE.md)). It implements protocol semantics; deployments consume it ([the three layers](#the-three-layers)). It does not require User MCP, Household OS or Sovereign Vault. No install order across components is implied. |
| What is supported today? | Alpha. Tag `v0.3-alpha` (`c96b9da749b2d95661973485b2a026897329c8cd`) is the reviewed coordinate; later `main` commits are outside it. Provider-exit restore is declared for PostgreSQL 15 and 16 only ([known limitations](release/v0.3-alpha-known-limitations.md), [release](https://github.com/jryski/sovereign-memory-core/releases/tag/v0.3-alpha)). |
| First test | The [history and restore guide](docs/history-restore-guide.md) gives the exact setup, the pinned recipe and its checksum, expected allowed and denied results, the receipt fields and owned-resource cleanup for `v0.3-alpha`. It uses PowerShell 7, Git and Docker with Linux containers; a pass prints `PASS: synthetic C2 rehearsal and bundle validation.` A database-free check is `python -m unittest discover -s tests/export_restore -p 'test_*.py' -v` ([export-restore-validation.yml](.github/workflows/export-restore-validation.yml)). There is no one-command installer ([installing](#installing)). |
| Evidence | [Workflow runs](https://github.com/jryski/sovereign-memory-core/actions) on PostgreSQL 15 and 16; the [v0.3-alpha release](https://github.com/jryski/sovereign-memory-core/releases/tag/v0.3-alpha) publishes `CHECKSUMS.sha256` with its receipts. |
| Source status | Merged source: `main`, of which only the `v0.3-alpha` coordinate was reviewed for restore. Tested review branches: open draft pull requests, each for its stated exact head only. Operating observations: the synthetic receipt in the [guide](docs/history-restore-guide.md#reference-receipt). Future direction: [roadmap](docs/roadmap.md). |
| Limitations | No live deployment has independent acceptance; restore evidence is synthetic; attribution is assertion-grade; checksums are not signatures ([what's not done](#whats-not-done)). |
| Contribute | [CONTRIBUTING.md](CONTRIBUTING.md), [SUPPORT.md](SUPPORT.md), DCO sign-off ([DCO.md](DCO.md)). |
| License and security | Apache-2.0 ([LICENSE](LICENSE), [NOTICE](NOTICE)). Report vulnerabilities through this repository's own private form, with an email fallback ([SECURITY.md](SECURITY.md)). |
| Related components | [Sovereign Memory Protocol](https://github.com/jryski/sovereign-memory-protocol) (intended long-term home of normative text), [Supabase User MCP](https://github.com/jryski/Supabase_user_MCP), [Household OS](https://github.com/jryski/Household-OS), and [Sovereign Vault](https://github.com/WireSpeedComputing/Sovereign-Vault), an independent business platform that records Core as design lineage ([LINEAGE.md](https://github.com/WireSpeedComputing/Sovereign-Vault/blob/main/LINEAGE.md)). |

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
| **SMP protocol** | Implementation-neutral custody, provenance, lifecycle, verification, supersession, erasure, portability, conformance | Partly, and transitional. Emerging normative text still lives in this tree under [`docs/publication/`](docs/publication/), including [`smp-custody-layer.md`](docs/publication/smp-custody-layer.md). The intended long-term home is the protocol repository. This repository's primary role is the PostgreSQL reference runtime. |
| **Runtime / core** | PostgreSQL reference implementation, migrations, perimeter enforcement, replay, tests, and export/restore contracts | **Yes** |
| **Deployment** | A particular person's or organization's policies, credentials, adapters, data, and operating evidence | **No** |

Dependencies run one way. Deployments consume a released runtime; runtimes
implement the protocol; the protocol must not depend on PostgreSQL, on a hosted
provider, or on any particular interface.

That separation is the intended architecture. It is not the current file
layout. This public repository still contains both emerging protocol material
and the PostgreSQL reference implementation, as
[`docs/positioning.md`](docs/positioning.md) records. Repository separation is
being prepared. Until then, normative protocol text in
[`docs/publication/smp-custody-layer.md`](docs/publication/smp-custody-layer.md)
remains in this tree.

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
- **Live and production export, and clean restore of private data, remain open.**
  Issue #92 is an implementation HOLD for that work. Related open issues are
  #58 and #52. This is separate from the v0.3-alpha synthetic rehearsal:
  [`release/v0.3-alpha-known-limitations.md`](release/v0.3-alpha-known-limitations.md)
  records that the package/restore mechanism was proven on a representative
  synthetic source built from the exact reviewed migrations.
  [`.github/workflows/c2-provider-exit.yml`](.github/workflows/c2-provider-exit.yml)
  runs that rehearsal on independent clusters. Synthetic mechanism proof is not
  live acceptance.
- No end-to-end erasure proof across projections, logs, traces, exports, and
  backups.
- **A shared database credential cannot cryptographically distinguish a human
  principal from an agent acting under it.** Today this is an audit trail, not
  identity-backed proof. It is a known limitation, not an oversight.
- The attention and work-memory layer is an early reference implementation, not
  a ranking policy anyone should adopt.
- Tag `v0.3-alpha` (commit `c96b9da749b2d95661973485b2a026897329c8cd`) is a
  reviewed coordinate. Its limitations record is
  [`release/v0.3-alpha-known-limitations.md`](release/v0.3-alpha-known-limitations.md).
  Later commits on `main` sit outside that tag. For that tag, synthetic
  package/restore is the rehearsal named above. Live and production export,
  clean restore of private data, and independent live acceptance stay open on
  #92. There is still no one-command installer or deployment profiles beyond
  the reference ones. Checksums, where a release record has them, show
  integrity. Signed authorship is still absent.

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
sql/11_perimeter_evaluability.sql
```

Three ordering rules that will bite you otherwise:

- `07` through `09` are re-runnable fix-forward migrations. If you need to
  reapply them, do it **before** `10`.
- `10` is the SECURITY DEFINER hardening boundary. Do not reapply `07` through
  `09` after crossing it.
- `11` is the perimeter-evaluability/report boundary and must remain **last**.
  It is itself re-runnable. If an operator deliberately reapplies `10`, reapply
  `11` immediately afterward before treating the perimeter as evaluated.

`sql/validation/` is not in the ordered list. It holds
`source_import_readiness.sql` and `load_chat_mine_package.sql`. Those are
validation helpers. Applying `01` through `11` does not run them.

`09` closes schema creation, table grants, function execution, default
privileges, RLS and FORCE RLS, ownership, and trigger-only boundaries. `10`
recreates the reviewed SECURITY DEFINER and authority-adjacent helper inventory
with protected names schema-qualified and `pg_temp` listed last. `11` preserves
that reviewed assertion body as an internal violation primitive, adds the
versioned `public.perimeter_report()` evaluability seam, and makes
`public.assert_perimeter_closed()` fail closed when required evaluation
population is unavailable.

Permission profiles, allowlists, and perimeter policy inputs live in
[`docs/perimeter.md`](docs/perimeter.md). The report-state contract is in
[`docs/perimeter-evaluability.md`](docs/perimeter-evaluability.md). Read both
before applying to anything you care about.

## Repository layout

- `sql/` — portable schema and fix-forward migrations
- `docs/` — contracts, security inventory, lifecycle, upgrade guidance
- `tests/` — conformance and adversarial harnesses
- `.github/workflows/` — PostgreSQL 15 and 16 CI

## Further reading

- [`STATUS.md`](STATUS.md) — repository posture, open program pointers, and the recovery hold
- [`PROGRAM-ROLE.md`](PROGRAM-ROLE.md) — one-way protocol, core, and deployment boundaries
- [`docs/roadmap.md`](docs/roadmap.md) — older milestone vocabulary, read with STATUS
- [`docs/positioning.md`](docs/positioning.md) — custody versus retrieval, Eywa crosswalk
- [`docs/perimeter.md`](docs/perimeter.md) — permission profiles and policy inputs
- [`docs/perimeter-evaluability.md`](docs/perimeter-evaluability.md) — evaluated, not-clean, and unsupported perimeter states
- [`docs/templates/restore-rehearsal.md`](docs/templates/restore-rehearsal.md) — provider-exit evidence record
- [`docs/security-definer-inventory.md`](docs/security-definer-inventory.md)
- [`docs/work-memory.md`](docs/work-memory.md)
- [`docs/attention-layer.md`](docs/attention-layer.md)
- [`docs/upgrades/work-memory-v2.md`](docs/upgrades/work-memory-v2.md)

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) and
[NOTICE](NOTICE). Contributions are accepted under the Developer Certificate of
Origin. See [DCO.md](DCO.md).
