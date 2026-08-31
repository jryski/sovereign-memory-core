# Sovereign Memory Core

**The PostgreSQL reference runtime for Sovereign Memory Protocol (SMP).**

Sovereign Memory Core is where implementation-neutral SMP semantics are exercised as concrete PostgreSQL behavior: migrations, authority/perimeter enforcement, replay, adversarial tests, export/restore, and provider-exit evidence.

It is **not** the protocol, a consumer application, a generic RAG product, or a deployment repository.

## Program role

The wider Sovereign Memory program is deliberately split into separate authority planes:

1. **Sovereign Memory Protocol** — implementation-neutral meaning, custody/provenance semantics, assurance, conformance, and profiles.
2. **Sovereign Memory Core** — this repository: one PostgreSQL reference implementation and adversarial proving ground.
3. **Data-plane capability and deployment/application layers** — user-context MCP, Household OS, Hermes runtimes, and downstream implementations that consume protocol/runtime behavior without redefining it.

Dependencies flow downward. A PostgreSQL mechanism demonstrated here must not silently become a universal protocol requirement.

## Current status

**Alpha release closeout is substantially complete in Core, but the wider alpha acceptance is not complete.**

- C1 perimeter evaluability passed independent exact-head adversarial review.
- C2 provider-exit / clean-restore evidence passed for the synthetic/reference implementation.
- PR #82, the v0.3-alpha release-closeout package, merged after independent exact-head review of the release-evidence binding and fabrication-resistance path.
- Live HOUSE issue #59 remains open and P0. The real PostgreSQL 17 household deployment still requires its own recovery-anchor/restore acceptance before the wider alpha claim can be treated as complete.
- No Core result should be read as proof that a particular deployment has applied the same migrations, perimeter, recovery controls, or acceptance evidence.

See [ROADMAP.md](ROADMAP.md) for the current sequencing and [docs/WIKI.md](docs/WIKI.md) for the repository orientation page.

## What this repository proves

Core is designed to make the following classes of claims executable rather than aspirational:

- **Lifecycle and lineage** — proposal, evidence, acceptance, supersession, replay, and append-only history.
- **Authority perimeter** — direct grants, inherited roles, `PUBLIC`, SECURITY DEFINER inventory, search-path hardening, and evaluability of the perimeter itself.
- **Upgrade/reapply safety** — migration ordering, reapply behavior, and deliberate-drift remediation.
- **Provider exit** — deterministic export bundle, clean restore into an independent PostgreSQL cluster, reciprocal positive/negative controls, source-unchanged verification, schema-drift comparison, and release evidence bound to exact candidate coordinates.
- **Claim limits** — unsupported, not-evaluated, incomplete, unknown, and clean results are distinct states.

Passing CI proves repository behavior at the tested coordinate. It does not certify downstream deployments.

## Relationship to SMP

The protocol repository owns the portable semantics. Core owns PostgreSQL mechanisms.

Examples:

| Protocol concern | Core mechanism examples |
| --- | --- |
| custody / provenance | immutable evidence and event tables, lineage constraints |
| authority / assurance | ACLs, RLS, SECURITY DEFINER inventory, actor/runtime fields |
| evaluability | `perimeter_report()` and fail-closed assertions |
| portability / provider exit | export bundle, validator, clean restore rehearsal |
| continuity / recovery | migration ledger, restore checks, rollback-safe acceptance harnesses |

If a requirement only makes sense because PostgreSQL exists, it belongs here or in a PostgreSQL profile — not in the protocol core.

## Relationship to current adjacent work

- **Supabase User MCP** is building the authenticated user/agent data-plane capability that preserves user context into PostgREST/RLS. It is not part of Core.
- **Household OS** is a deployment/application layer and public synthetic reference architecture. It does not define SMP semantics.
- **Household OS Private** contains deployment-specific planning/evidence and must remain a separate trust/visibility surface.
- **Model Radar** owns model/provider/workload qualification evidence, not memory authority.
- **Hermes** owns agent/runtime orchestration, workers, and recovery behavior, not protocol authority.

The new protocol proposal for an **Agent Access Integrity Boundary** is also intentionally separate from this repository. Core may later provide a PostgreSQL substrate profile/reference implementation for it, but the portable concept is being designed in `sovereign-memory-protocol` first.

## What this is not

Core does not decide:

- what a model should remember;
- how retrieval/ranking/semantic search should work;
- what UI a deployment should expose;
- who a real deployment's principals are;
- which provider, identity service, or runtime must be used;
- whether a source statement is true.

Memory engines and applications can compose with SMP/Core rather than being replaced by them.

## Current limitations

- HOUSE #59 remains a separate live-deployment gate.
- PostgreSQL 15/16 Core evidence does not automatically establish PostgreSQL 17 deployment acceptance.
- Shared/native privileged credentials still limit cryptographic actor attribution in some operational paths.
- Erasure across every projection/log/export/backup surface is not yet a complete end-to-end release claim.
- Agent-access enrollment/in-situ legacy-system protection is a protocol design lane, not an implemented Core feature yet.
- A valid restore can reproduce a snapshot without proving latestness or non-resurrection; recovery/currentness remain separate claims.

## Installing the reference migrations

Apply migrations in order to a **disposable or independently recoverable** PostgreSQL database first.

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

- `07` through `09` are re-runnable fix-forward migrations. Reapply them before crossing `10`.
- `10` is the SECURITY DEFINER hardening boundary.
- `11` is the perimeter-evaluability/report boundary and must remain after `10`.
- A downstream topology/search-scope migration has separately been assigned slot `12`; do not reuse migration numbers across active branches.

Read [docs/perimeter.md](docs/perimeter.md) and [docs/perimeter-evaluability.md](docs/perimeter-evaluability.md) before applying to anything important.

## Repository layout

- `sql/` — PostgreSQL reference migrations and fix-forward changes
- `docs/` — runtime contracts, security inventories, evidence/runbook guidance
- `tests/` — conformance and adversarial harnesses
- `release/` — release evidence, limitations, and exact-candidate artifacts
- `.github/workflows/` — executable CI / provider-exit / perimeter proof

## Documentation

- [docs/WIKI.md](docs/WIKI.md) — role and program orientation
- [ROADMAP.md](ROADMAP.md) — current Core work and dependency order
- [docs/positioning.md](docs/positioning.md) — custody versus retrieval
- [docs/perimeter.md](docs/perimeter.md) — permission profiles and policy inputs
- [docs/perimeter-evaluability.md](docs/perimeter-evaluability.md) — evaluated vs unsupported perimeter states
- [docs/templates/restore-rehearsal.md](docs/templates/restore-rehearsal.md) — provider-exit evidence record
- [docs/security-definer-inventory.md](docs/security-definer-inventory.md)
- [docs/work-memory.md](docs/work-memory.md)
- [docs/attention-layer.md](docs/attention-layer.md)

## Public/private boundary

This public repository must not contain real household/business payloads, live project identifiers, credentials, private topology, recovery artifacts, or deployment security posture. Public defects should be reproduced with synthetic evidence.
