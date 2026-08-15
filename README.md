# Sovereign Memory Core

**A PostgreSQL reference runtime for AI memory custody you can audit, move, restore, and verify.**

> **Current release: [`v0.3-alpha`](../../releases/tag/v0.3-alpha).**
> This is an alpha reference implementation, not a finished consumer product.
> Read [What the alpha proves](#what-the-alpha-proves) and
> [What it does not prove](#what-it-does-not-prove) before relying on it.

## In one minute

Most AI memory systems focus on **recall**: extracting useful facts and finding
relevant context later.

Sovereign Memory focuses on **custody**:

- What evidence supports a memory?
- Is a record an observation, a derived belief, a proposal, or a human-accepted decision?
- Who or what changed it, through which authority path?
- What did it supersede, and what superseded it?
- Can history be reconstructed independently?
- Can the system be exported, restored, checked, corrected, and erased without trusting one provider forever?

This repository is the PostgreSQL implementation of those ideas. It contains
migrations, security/perimeter controls, lifecycle and provenance behavior,
portable export/restore tooling, and adversarial/conformance tests.

It does **not** contain a chat UI, personal data, production credentials, or a
complete retrieval/ranking product.

## Why this exists

A data export is not automatically a continuity export.

In real multi-year AI account exports we examined, conversation text could be
returned while important organizational relationships, such as which project a
conversation belonged to, were not reconstructable from the export. You can get
your words back without getting the structure that made them useful.

Sovereign Memory treats that as a custody problem rather than a retrieval
problem: important state should carry enough provenance, lifecycle, authority,
and portability information to be independently understood later.

## Repository boundary

There are separate concerns, and this repository intentionally handles only one
of them.

| Surface | Responsibility | Here? |
|---|---|---|
| **Protocol / specification** | Implementation-neutral custody semantics, lifecycle, provenance, authority, portability, conformance | **No**. This repo implements them; the specification surface is separate. |
| **Sovereign Memory Core** | PostgreSQL reference runtime, migrations, perimeter enforcement, replay, tests, export/restore contracts | **Yes** |
| **Deployment / product** | A household, organization, UI, connectors, policies, credentials, operating evidence | **No** |
| **Private data** | Personal, household, health, financial, business, or other live records | **Never** |

Dependencies should run one way: deployments consume a runtime; runtimes
implement the protocol; the protocol must not depend on PostgreSQL, Supabase, a
particular model, or a particular UI.

## What the alpha proves

The published `v0.3-alpha` release freezes an exact reviewed commit and ships
checksummed release artifacts, including provider-exit and schema-drift receipts.
The release gate established these repository-level properties:

- **PostgreSQL 15 and 16 conformance coverage** for the reference runtime.
- **Fail-closed perimeter evaluability**: clean, violated, and unevaluable states
  are distinct; an unevaluable perimeter cannot masquerade as clean.
- **Lifecycle and history behavior**: evidence-gated proposals, append-oriented
  history, supersession, replay, and concurrency controls.
- **Authority-perimeter checks** across direct grants, role inheritance,
  membership chains, `PUBLIC`, RLS/FORCE RLS, ownership, defaults, and reviewed
  `SECURITY DEFINER` surfaces.
- **Provider exit on a representative synthetic deployment**: package creation,
  clean independent PostgreSQL 16 restore, structural comparison, positive and
  denial controls, and source-unchanged verification.
- **Release integrity receipts**: manifest, checksums, schema-drift evidence, and
  exact-coordinate review.
- **A separate HOUSE recovery rehearsal** demonstrated that a real deployment
  could retain a complete logical recovery anchor and restore its household-owned
  public schema into an isolated PostgreSQL 17.10 target without changing the
  live source.

These are **measured claims**, not a general promise that every deployment is
safe. A deployment only has controls that it actually installed, configured,
and verified.

## What it does not prove

The alpha deliberately does **not** claim more than the evidence supports.

- It is **not a consumer application** and has no polished end-user UI.
- It is **not a retrieval engine**. Ranking, embeddings, graph search, context
  assembly, and memory extraction can be supplied by other systems.
- Declared provider-exit support is currently **PostgreSQL 15 and 16**. The
  HOUSE PostgreSQL 17.10 exercise was a deployment-specific recovery procedure;
  it does not expand that support range.
- Database restore does **not** recreate a hosted provider's auth service,
  object storage, realtime system, edge functions, scheduler, billing,
  observability, networking, dashboard, hosted roles, or hosted-role ACL state.
- The HOUSE rehearsal did not reconstruct `supabase_vault` or hosted-role ACLs
  on its plain PostgreSQL restore target.
- Recorded actor attribution is not cryptographic non-repudiation when multiple
  actors share a credential path.
- Perimeter findings are fail-closed but not guaranteed to enumerate every
  simultaneous defect in one pass; fix reported findings and rerun.
- SHA-256 checksums prove integrity of the measured bytes, not authorship.
- End-to-end physical erasure from every backup, cache, trace, artifact, or
  third-party copy is not proven.

The complete release limitations are in
[`release/v0.3-alpha-known-limitations.md`](release/v0.3-alpha-known-limitations.md).

## How this relates to memory engines

Memory engines such as extraction, vector, graph, or temporal-reasoning systems
answer questions like:

> What should be remembered, and what context is relevant now?

Sovereign Memory asks:

> What is being held, under whose authority, with what evidence and history, and
> can it be moved and independently verified later?

Those concerns compose. A retrieval system can use Sovereign Memory as a custody
substrate. Core should not grow into a generic RAG engine just because both
systems store "memory."

See [`docs/positioning.md`](docs/positioning.md).

## Core principles

1. **Evidence before belief.** Derived state stays linked to supporting evidence.
2. **Preserve history.** Corrections supersede prior records rather than silently rewriting them.
3. **Custody is not retrieval.** Summaries, indexes, graphs, and hot projections are rebuildable views.
4. **Authority is explicit.** Runtime identity, principal, credential path, and review authority are separate concepts.
5. **Time is state.** Observed, recorded, effective, accepted, superseded, and reverted are different moments.
6. **Portability must be demonstrated.** Account ownership is not enough; export, restore, and verification matter.
7. **Protect meaning as well as bytes.** Provenance, lifecycle, relationships, and chain of custody are part of the asset.

## Who should start where?

| If you are... | Start with... |
|---|---|
| Evaluating the idea | This README, then [`docs/positioning.md`](docs/positioning.md) |
| Reviewing security | [`docs/perimeter.md`](docs/perimeter.md) and [`docs/security-definer-inventory.md`](docs/security-definer-inventory.md) |
| Reviewing provider exit | [`release/v0.3-alpha-known-limitations.md`](release/v0.3-alpha-known-limitations.md) and [`docs/templates/restore-rehearsal.md`](docs/templates/restore-rehearsal.md) |
| Building against the runtime | [`docs/work-memory.md`](docs/work-memory.md), then `sql/` and `tests/` |
| Contributing | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Looking for a chat UI or turnkey personal assistant | This is not that repository |

## Trying it safely

Do not point an alpha migration set at an important database as your first test.
Use a disposable PostgreSQL instance or a database with a verified recovery
anchor.

Apply migrations in numeric order:

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

Important ordering rules:

- `07` through `09` are re-runnable fix-forward migrations. Reapply them before `10`.
- `10` is the `SECURITY DEFINER` hardening boundary. Do not reapply `07` through `09` after crossing it.
- `11` is the perimeter evaluability/report boundary. If `10` is deliberately reapplied, reapply `11` immediately afterward before treating the perimeter as evaluated.

Before using the runtime beyond a disposable test, read
[`docs/perimeter.md`](docs/perimeter.md) and
[`docs/perimeter-evaluability.md`](docs/perimeter-evaluability.md).

## Repository layout

- `sql/` — schema and fix-forward migrations
- `tests/` — conformance, adversarial, export/restore, and regression tests
- `scripts/` — package, restore, schema-drift, and release tooling
- `fixtures/` — synthetic fixtures only
- `docs/` — architecture and operating contracts
- `release/` — release procedure and known limitations
- `.github/workflows/` — CI for supported release surfaces

## Public-repository safety rule

This repository must remain reusable and safe to inspect publicly.

Do not commit real personal/household/business records, credentials, provider
project identifiers, private hostnames, private operating receipts, or copied
production data. Public fixtures must be synthetic.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`SECURITY.md`](SECURITY.md).

## Release and status

- Latest published release: [`v0.3-alpha`](../../releases/tag/v0.3-alpha)
- Current development status: [`STATUS.md`](STATUS.md)
- Known alpha limitations: [`release/v0.3-alpha-known-limitations.md`](release/v0.3-alpha-known-limitations.md)
- Security reporting: [`SECURITY.md`](SECURITY.md)

## Further reading

- [`docs/positioning.md`](docs/positioning.md) — custody versus retrieval
- [`docs/perimeter.md`](docs/perimeter.md) — permission profiles and policy inputs
- [`docs/perimeter-evaluability.md`](docs/perimeter-evaluability.md) — clean, violated, and unsupported states
- [`docs/security-definer-inventory.md`](docs/security-definer-inventory.md) — authority-adjacent function inventory
- [`docs/work-memory.md`](docs/work-memory.md) — work-memory lifecycle
- [`docs/attention-layer.md`](docs/attention-layer.md) — reference attention model
- [`docs/templates/restore-rehearsal.md`](docs/templates/restore-rehearsal.md) — recovery/provider-exit evidence template
