# Installer and productization roadmap

> Claim your memory core in minutes.

This roadmap describes a future installer experience built on the merged core schema,
source-import controls, deterministic producer fixture, rollback loader proof, and SMP
conformance work. The commands, services, and screens below are product direction, not
functionality currently shipped by this repository.

The installer should hide database assembly without hiding evidence, review, authority, or
validation. It should make a self-controlled memory core approachable while keeping every
consequential step inspectable, reversible, and independently verifiable.

## Product thesis

The installer should feel like claiming a durable home for AI memory, not manually applying SQL.
The user chooses where data lives, brings in a source, reviews what was found, and leaves with
proof that the governed memory state can be backed up, restored into a clean compatible system,
and verified without reaching back to the original provider.

The product promise is:

- local-first by default and cloud optional;
- evidence-preserving imports;
- validation-backed setup;
- review before promotion;
- no silent conflict resolution;
- candidates remain outside authoritative memory until reviewed;
- every completed install creates a backup and offers a clean restore verification;
- verification produces a scoped custody receipt that states exactly what was proven and excluded.

A custody receipt proves restoration and custody for a declared scope. It does not prove that every
memory is true, that every candidate should be promoted, that two AI models will answer identically,
or that arbitrary database engines are interchangeable.

## First-run journey

1. Choose where memory lives.
2. Install the schema.
3. Run structural and security validation.
4. Import a synthetic demo or supported export.
5. Generate an internal source-import package.
6. Run a rollback-only loader dry-run.
7. Review candidates or leave them explicitly unpromoted.
8. Show the readiness scorecard.
9. Create a checksummed backup.
10. Restore the backup into an empty compatible target.
11. Compare canonical governed state and run conformance probes against the restored target.
12. Issue a custody receipt or record why custody verification was skipped or failed.

## Completion states

The installer must not collapse all outcomes into a single success banner.

| State | Meaning |
|---|---|
| **Installed** | The selected schema and services were installed and base validation completed. |
| **Backup created** | A portable, checksummed backup artifact and manifest were produced. |
| **Custody verified** | The backup restored into an empty compatible target using no source-system reach-back, canonical governed state matched, structural invariants passed, and the versioned probe suite passed. |

Custody verification should be default-on but skippable for constrained hosts. A skipped or failed
verification leaves the installation usable but visibly degraded. The reason must be recorded in
the receipt/report, and verification must be re-runnable after installation.

Suggested command:

```bash
smc verify-exit
```

## Installation personas

### Guided Supabase or cloud install

For a user who wants managed Postgres without operating a local database. A guided flow verifies
the target, applies versioned schema changes through a controlled administrative connection,
runs acceptance checks, and removes or avoids retaining elevated credentials. The resulting backup
must be restorable into a declared compatible PostgreSQL target without requiring the original
Supabase project.

### Local Docker install

For a user who wants a self-contained deployment on a workstation, home server, or private host.
One command should start pinned services, initialize durable storage, run health checks, and open
the review flow. Data and backups must live in explicit host-managed locations rather than
disappearing with a container. A separate disposable PostgreSQL container should serve as the
initial clean restore target.

### Power-user CLI install

For operators who already manage Postgres and want scriptable, non-interactive control. The CLI
should expose plans, machine-readable results, explicit target selection, and idempotent
validation without assuming a particular cloud provider.

## Minimum lovable installer

The minimum lovable installer is a complete, safe first-use loop rather than a large feature
surface. It should:

- explain where data will be stored before making changes;
- check prerequisites, connectivity, disk space, and backup destination;
- show the schema plan and require confirmation for a non-local target;
- install and validate the core;
- offer a synthetic demo or one supported export adapter;
- preserve raw evidence and generate deterministic candidates;
- run the loader in rollback-only mode before any committed load;
- keep candidate results structurally separate from promoted results;
- require review for promotion and hold consequential or conflicting claims;
- present readiness blockers in plain language;
- create a checksummed backup and manifest;
- restore into an empty compatible target using only the backup and public tooling;
- verify canonical governed state, structural invariants, erasure/tombstone behavior, and the conformance probe suite;
- issue a signed or locally authenticated canonical JSON custody receipt;
- support a safe skip path that records a degraded completion state and can be rerun later.

Success means a new user can complete the journey without understanding internal table order,
while an operator can still inspect every command, validation result, exclusion, and artifact.

## CLI command surface

The proposed `smc` command surface is intentionally small:

| Command | Purpose |
|---|---|
| `smc doctor` | Check runtime, database, disk, credentials, versions, extensions, and backup destination without changing state. |
| `smc install` | Plan and install the selected schema profile, then report exactly what changed. |
| `smc validate` | Run schema, grant, source-import, and readiness validation with machine-readable and human-readable output. |
| `smc import` | Read a supported export or synthetic demo and generate an internal source-import package. |
| `smc load --dry-run` | Load a package inside a rollback-only transaction and report invariant or readiness failures. |
| `smc review` | Open or serve the candidate review workflow without auto-promoting contested claims. |
| `smc backup` | Create a portable backup with SHA-256 checksums, manifest, scope, and declared exclusions. |
| `smc verify-exit` | Restore the backup into an empty compatible target, compare canonical state, run invariants and probes, and emit a custody receipt. |
| `smc receipt verify` | Verify receipt structure, signatures, hashes, probe-suite identity, and referenced artifacts offline. |

Shared command behavior should include `--help`, `--json`, `--non-interactive`, and an explicit
target profile. Mutating commands should display the target and a plan first. The CLI must refuse
ambiguous destinations and must never infer that conflicting candidates are equivalent.

The package generated by `smc import` is internal producer alignment with the core contract. It
is not a public interchange protocol.

## Clean restore verification

The first supported proof should remain deliberately narrow:

```text
Supabase or PostgreSQL source
    -> portable PostgreSQL backup
    -> empty compatible PostgreSQL target
    -> canonical governed-state comparison
    -> structural invariants
    -> restored-instance conformance probes
    -> custody receipt
```

The restore must be clean-room capable: verification may use the backup artifact, its manifest,
the versioned verifier/probe suite, and public installation tooling, but must not query the source
system or depend on its credentials.

Verification is layered:

1. **Canonical row-set hashes** over declared governed state.
2. **Structural invariants**, including foreign-key integrity, supersession acyclicity, checkpoint-chain verification, and tombstone/erasure preservation.
3. **Functional probes** run against the restored instance, including positive, negative, conflict, stale-state, evidence-request, authority, and review-boundary behavior.

Byte-for-byte equality is not required and would create false failures from harmless differences
such as physical row order, sequence state, cache data, and database statistics.

## Canonical governed state

The initial canonical view should cover, where present:

- stable record identity and content hashes;
- scope and authority epoch;
- review and promotion state;
- provenance and source-evidence references;
- effective, observed, and supersession relationships;
- conflict and hold state;
- tombstones and erasure markers;
- principal, actor, and trusted-agent registry state;
- checkpoint-log heads and verification material;
- source package, manifest, and cutover evidence needed to explain authority.

The receipt must explicitly declare exclusions. Expected exclusions include:

- embeddings and vector indexes;
- hot-index or ranking scores;
- caches and other rebuildable derived data;
- transient sessions and logs not declared durable;
- passwords, OAuth tokens, API keys, and provider secrets;
- provider-owned operational metadata that cannot be exported safely.

## Candidate and demo boundary

Demo and imported candidate records may be useful for preview or recall, but they must not silently
join authoritative result sets.

- Candidate results are returned through a structurally separate field or query path.
- Promoted and candidate records are not merged by default.
- A derivation that relies on an unreviewed candidate cannot be promoted until the cited source is reviewed.
- Demo data lives in a separately named, wholesale-droppable scope.
- The custody receipt reports candidate, promoted, held, rejected, and excluded counts separately.

A warning label alone is insufficient because labels can disappear when data enters model context.
The boundary must exist in the data and retrieval contract.

## Portability lint

Before restore, the verifier should inventory dependencies that can block a vanilla PostgreSQL
restore, including:

- `auth.uid()` or other provider-specific identity functions in RLS;
- Supabase-specific roles and grants;
- required extensions such as `pgcrypto`, `pg_net`, or `vault`;
- PostgREST-coupled RPC assumptions;
- extension versions and schema placement;
- unsupported secrets or provider-managed objects.

The verifier may install documented compatibility shims for declared portable dependencies, or it
must fail with a precise report. It must never silently skip a failed function, trigger, RLS policy,
or extension and still claim custody verified.

## Custody receipt

The receipt contract is defined in [`12-custody-receipt.md`](12-custody-receipt.md). At minimum,
it binds:

- tool version and source commit;
- schema and migration versions;
- probe-suite version and hash;
- source package digest;
- backup SHA-256;
- restore-target engine fingerprint;
- canonical-view definition and both hashes;
- structural invariant results;
- functional probe results;
- scope, authority epoch, exclusions, skip/failure reason, and signer.

The receipt should itself be preservable as SMP evidence and anchored in the checkpoint log. An
external transparency service such as Sigstore may be added later; it is not required for the first
local proof.

## Local Docker stack

The planned local profile contains the fewest services needed for a complete first-run loop:

| Service | Responsibility |
|---|---|
| Postgres | Durable system of record, constraints, review state, and readiness views. |
| API or service layer | Narrow application access to approved database operations. |
| Review UI | Candidate inspection, evidence display, decisions, and readiness status. |
| Worker or import runner | Deterministic export parsing, package generation, controlled loading, and portability lint. |
| Backup/verifier runner | Backup creation, clean restore into a disposable target, canonical comparison, probes, and receipt generation. |

Images and dependencies should be version-pinned. The stack should use named volumes or explicit
host paths, health checks, least-privilege service roles, and a separate disposable profile for
loader and restore tests. Secrets belong in local secret storage or environment files excluded
from version control.

## Setup wizard UX

The setup wizard should be a thin presentation over the same plans and validations used by the
CLI:

1. **Claim your memory.** Set expectations: custody, portability, evidence, and review.
2. **Choose storage.** Select local Docker, guided cloud, or an existing PostgreSQL target.
3. **Check the target.** Run `smc doctor` and explain blockers before any mutation.
4. **Install and validate.** Show progress by schema stage and retain the validation report.
5. **Import the first source.** Choose synthetic demo data or a supported export.
6. **Preview the dry-run.** Show package integrity, proposed rows, holds, conflicts, and rollback.
7. **Review candidates.** Require explicit decisions and preserve source evidence.
8. **Read the scorecard.** Separate passing checks, warnings, and blockers.
9. **Create the backup.** Show artifact location, size, SHA-256, and declared scope.
10. **Verify custody.** Restore into an empty compatible target, run comparisons and probes, and show exclusions.
11. **Issue the receipt.** Present `installed`, `backup created`, or `custody verified` honestly.
12. **Connect assistants later.** Keep assistant integration outside the critical install path.

The wizard should never replace an actionable error with a generic failure screen. Each failed
gate should name the invariant, preserve diagnostic output, and offer a safe retry.

## Milestones

| Milestone | Scope | Status and exit condition |
|---|---|---|
| M0 | Core schema and source-import foundation | Complete: versioned schema, provenance, review, readiness, and probe foundations are merged. |
| M1 | Deterministic producer and rollback loader proof | Complete: a synthetic package and rollback-only loader path prove the internal producer contract. |
| M2 | Negative package and SQL validation hardening | Complete foundation: malformed packages and corrupted SQL paths fail for the intended invariants while positive paths remain green. |
| M3 | Public-readiness and governance baseline | Active: tracked examples remain synthetic/public-safe and durable-write/license decisions are resolved. |
| M4 | CLI skeleton and `smc doctor` | Planned: establish packaging, target profiles, diagnostics, structured output, and no-mutation checks. |
| M5 | Minimum local installer and custody gate | Planned: local Docker setup, backup creation, clean restore verification, portability lint, versioned probes, and custody receipt. |
| M6 | Review UI v0 | Planned: inspect evidence, decide candidates, preserve holds/conflicts, and display readiness blockers. |
| M7 | Representative real-export adapter fixture | Planned: add a sanitized fixture and deterministic adapter without vendor coupling in the core schema. |
| M8 | Advanced provider-exit and migration UX | Planned: provider-to-provider workflows, broader adapter profiles, larger-scale restore operations, and optional external receipt anchoring. |
| M9 | Guided Supabase install | Planned: deliver a safe managed-cloud path with explicit target confirmation, least-privilege posture, validation, and no retained elevated secret. |

Only backup, clean compatible restore, layered verification, and the custody receipt move into the
minimum installer. Cross-engine migration, universal adapters, and polished provider-to-provider
migration remain later work.

## Early non-goals

The early installer deliberately excludes:

- UI polish beyond the review and verification flow;
- Hermes orchestration;
- a retrieval engine beyond conformance probes;
- an LLM evaluator;
- a plugin marketplace;
- a public interchange protocol;
- automatic truth deduplication or conflict resolution;
- arbitrary cross-database-engine restoration;
- a claim of universal or permanent sovereignty.

These exclusions keep the first product surface focused on custody, evidence, review, validation,
restoration, and reversibility.

## Adoption narrative

**Take your AI memory with you.**

**A backup is a promise. A verified restore is evidence.**

**Your AI memories should belong to you, not whichever app remembered them first.**

That promise is credible only when installation ends with a validated schema, reviewable import,
readiness result, portable backup, clean restore proof, and an auditable custody receipt.