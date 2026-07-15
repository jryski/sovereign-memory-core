# Custody receipt and clean restore verification

## Status

Design contract for the future local operator and installer flow. This document does not claim
that receipt generation, clean restore automation, or offline verification is currently shipped.

## Decision

A completed Sovereign Memory installation should be able to prove that its governed memory state
can leave the original provider, restore into an empty compatible PostgreSQL target, preserve its
custody and authority semantics, and pass the same versioned conformance probes used by the active
system.

The resulting artifact is a **custody receipt**.

Use `custody verified` for the narrow completion claim. Keep `data sovereignty` as the broader
project philosophy. A restore test does not prove ongoing key custody, universal deletion rights,
truth of every memory, equivalent model behavior, or portability to arbitrary database engines.

## Completion states

Verification reports one of three primary states:

1. **Installed** — schema and base validation completed.
2. **Backup created** — a checksummed portable backup and manifest exist.
3. **Custody verified** — an empty compatible target was restored without source reach-back, the
   canonical governed state matched, structural invariants passed, and restored-instance probes
   passed.

The verification gate is default-on but skippable. A skip must be explicit, record a reason, and
leave the installation in a visibly degraded state. Verification must be repeatable through a
post-install command such as `smc verify-exit`.

## Threat model

The receipt is designed to catch failures that a successful `pg_dump` alone cannot detect:

- incomplete or corrupt backup artifacts;
- hidden dependence on the source provider or its credentials;
- missing functions, triggers, grants, RLS policies, or extensions after restore;
- broken provenance, supersession, checkpoint, or review relationships;
- resurrection of tombstoned or erased records;
- silent mixing of candidates with authoritative memory;
- a restored system that contains the right rows but behaves incorrectly;
- a verifier that silently ignores provider-specific incompatibilities.

The receipt does not establish the truth of content. It establishes custody, restoration, and
behavioral preservation for the declared scope.

## Clean-room requirement

Verification must be possible using only:

- the backup artifact;
- the artifact manifest and checksums;
- the declared schema/migration bundle;
- the versioned verifier and conformance probe suite;
- documented public tooling and compatibility shims.

The verifier must not query the source system, use source credentials, or rely on a live source
service during comparison. A restore that needs the original provider to explain or complete itself
has not proven provider exit.

## Layered verification

A valid custody verification includes all three layers.

### Layer 1: canonical governed-state comparison

Export a deterministic representation from both source and restored targets, sort it using declared
stable keys, normalize permitted representation differences, and compute a cryptographic set/hash.

The canonical state should cover, where present:

- stable record identifiers;
- content and evidence hashes;
- scope and authority epoch;
- review, promotion, hold, rejection, and exclusion states;
- provenance and source-evidence references;
- observed, effective, and supersession relationships;
- conflict and stale-state representation;
- tombstones and erasure markers;
- principal, actor, and trusted-agent registry state;
- checkpoint-log heads and verification material;
- source package, manifest, and cutover evidence required to explain authority.

Exact database byte equality is not required. Physical row order, sequence values, statistics,
cache content, and other non-governed differences may legitimately vary.

### Layer 2: structural invariants

Run deterministic checks including:

- foreign-key and referential integrity;
- uniqueness and manifest-accounting requirements;
- supersession acyclicity;
- checkpoint-chain verification;
- tombstone/erasure preservation;
- no prohibited promotion of HOLD, EXCLUDE, EVIDENCE, demo, or unreviewed agent-authored material;
- grant, role, trigger, function, and RLS posture required by the declared profile;
- declared extension and function availability.

### Layer 3: functional conformance probes

Run the versioned SMP probe suite against the restored target, not merely against exported files.
The initial categories should include:

- positive retrieval;
- negative/unknown handling;
- conflict surfacing;
- stale-state avoidance;
- evidence-request behavior;
- review and promotion boundaries;
- authority scope and epoch;
- candidate/promoted result separation;
- erased/tombstoned record non-resurrection.

The receipt binds the probe-suite version and hash so a future verifier can determine exactly which
behavioral contract was tested.

## Declared exclusions

The receipt must include the exclusion list used by the canonical comparison. Expected exclusions
include:

- embeddings and vector indexes;
- ranking scores and hot-index state;
- rebuildable caches;
- transient sessions and logs not declared durable;
- passwords, OAuth tokens, API keys, and provider secrets;
- provider-owned operational metadata that cannot be exported safely;
- temporary restore containers and disposable test state.

An exclusion may be valid without being harmless. The receipt records exclusions so the claim is
auditable rather than implied.

## Candidate and demo separation

Candidate records are untrusted proposed context, not authoritative memory.

Required behavior:

- candidate and promoted results use separate fields, views, or query paths;
- default authoritative retrieval excludes candidates;
- candidate-derived material cannot be promoted until the cited source is reviewed;
- demo data uses a separately named, wholesale-droppable scope;
- the receipt reports candidate, promoted, held, rejected, excluded, and tombstoned counts
  independently;
- probe cases verify that restored retrieval preserves this boundary.

A UI badge or prompt warning is not sufficient because labels may be lost when records are placed
into model context.

## Portability lint

Before restore, inspect the backup and migration bundle for provider-specific dependencies.

At minimum, report:

- use of `auth.uid()` or other provider-specific identity functions in RLS;
- Supabase-specific roles and grants;
- required extension names, versions, and schema placement;
- `pgcrypto`, `pg_net`, `vault`, or other non-core dependencies;
- PostgREST-coupled functions or assumptions;
- provider-managed secrets or objects that are not present in the backup;
- unsupported ownership or security-definer posture.

The verifier may install documented compatibility roles or shims when the selected profile permits
it. Otherwise it must stop with a precise incompatibility report. It must never omit a failed
function, trigger, RLS policy, grant, or extension and still claim custody verified.

## Receipt format

The receipt should be canonical JSON suitable for hashing, signing, offline verification, and
storage as an SMP evidence record.

Minimum fields:

```json
{
  "receipt_version": "...",
  "result": "installed|backup_created|custody_verified|verification_failed|verification_skipped",
  "skip_or_failure_reason": null,
  "created_at": "...",
  "tool": {
    "version": "...",
    "source_commit": "..."
  },
  "schema": {
    "profile": "...",
    "version": "...",
    "migration_head": "..."
  },
  "probe_suite": {
    "version": "...",
    "sha256": "..."
  },
  "source_package_digest": "...",
  "backup": {
    "format": "...",
    "sha256": "...",
    "size_bytes": 0
  },
  "restore_target": {
    "engine": "PostgreSQL",
    "engine_version": "...",
    "extensions": []
  },
  "scope": {
    "scope_id": "...",
    "authority_epoch": "..."
  },
  "canonical_view": {
    "definition_version": "...",
    "source_sha256": "...",
    "restored_sha256": "...",
    "counts": {}
  },
  "structural_invariants": [],
  "probe_results": [],
  "exclusions": [],
  "signer": {
    "principal": "...",
    "method": "...",
    "signature": "..."
  }
}
```

SHA-256 is the minimum backup and receipt digest algorithm. MD5 is not acceptable for the custody
claim.

The first implementation may use a locally controlled signing key. External transparency or
Sigstore integration is optional later work and must not block local custody proof.

## Evidence anchoring

After successful generation, store the receipt itself as an SMP evidence record and anchor its hash
in the checkpoint log. This dogfoods the protocol: the custody proof receives the same provenance
and tamper-evidence treatment as other consequential evidence.

The offline verifier must also work when that database is unavailable. The receipt, backup,
manifest, canonical-view definition, and probe bundle must remain independently inspectable.

## Failure behavior

The verifier fails closed for the custody claim. It may leave the installed system running, but it
must not emit `custody_verified` when any required layer fails.

Failure output should identify:

- the failed layer;
- the exact invariant or probe;
- expected and observed values;
- whether the source installation remains intact;
- whether the disposable restore was retained for diagnosis or destroyed;
- a safe retry command.

## Relationship to conformance and issue #48

The offline SMP-complete verifier fixture and the installer custody verification should share one
versioned probe suite and canonical-view definition. The project should not maintain separate
notions of conformance for migration packages, restored systems, and Steward Pack validation when a
single reusable verifier can serve all three.

Issue #48 is the natural implementation home for the first public-safe synthetic fixture and
offline verifier. The installer consumes that verifier rather than inventing another proof format.

## Deferred work

The first custody receipt does not require:

- arbitrary cross-engine restoration;
- universal provider-to-provider migration UX;
- automatic migration of secrets or external accounts;
- identical model responses after restore;
- universal adapter coverage;
- external signing/transparency infrastructure;
- a global or permanent sovereignty claim.

These may be added as separate profiles or later milestones without weakening the initial narrow
claim.