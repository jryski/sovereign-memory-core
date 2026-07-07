# 07 · MCP Memory/Wiki Retirement and Supabase Cutover

## Purpose

Retire unreliable `mcp_memory` and `mcp_wiki` paths without losing history, laundering stale state into active truth, or declaring Supabase authoritative before evidence supports it.

This document is the operational cutover plan for moving from legacy MCP-backed memory/wiki behavior to Sovereign Memory Core as the durable source of truth.

## Non-negotiable principles

1. **No blind import.** Every source row receives a manifest entry.
2. **Preserve before transform.** Raw source payloads are exported and hashable before normalization.
3. **Classify explicitly.** Every row becomes `import`, `hold`, `exclude`, or `evidence`.
4. **Separate zones.** HOUSE, VAULT, HOLD, and EVIDENCE are different destinations with different authority.
5. **Old state is not current truth.** Historical current-state claims require review before promotion.
6. **No silent overwrite.** Corrections supersede. Imported conflicts are surfaced.
7. **Cutover by tests, not vibes.** Readiness checks and recall probes must pass before the old system is demoted.
8. **Rollback remains possible.** Legacy sources stay readable until Supabase has passed a confidence window.

## Target architecture after cutover

```text
legacy mcp_memory / mcp_wiki
        ↓ export + manifest + hashes
Sovereign Memory Core
├── HOUSE: general household memory and wiki content
├── VAULT: restricted identity/health/finance/legal records
├── HOLD: rows requiring human review or deferred classification
├── EVIDENCE: channel messages, notebooks, integrity records, migration artifacts
└── REVIEW: proposed/stale/conflicting rows surfaced for promotion/rejection
```

## Phase 0: Inventory

### Goal

Know what exists before deciding what to import.

### Required inventory

- source system name
- source table or collection
- source row count
- source ID field
- source timestamps
- content fields
- metadata fields
- status fields
- deletion/supersession semantics
- attachment or file references
- known reliability problems

### Output

Create or update a migration inventory note containing:

```text
source_system:
source_table:
row_count:
id_semantics:
timestamp_semantics:
content_fields:
metadata_fields:
known_risks:
export_method:
```

## Phase 1: Freeze or watermark

### Goal

Prevent the old source from changing invisibly during export.

### Options

1. Hard freeze: stop writes to legacy MCP paths.
2. Watermark: record max updated timestamp / sequence / content hash before export.
3. Dual-write window: allow writes only if captured into both legacy and Supabase.

### Live DB support

The live deployment already contains a `migration_freeze_control` table with:

- `is_frozen`
- `batch_id`
- `frozen_at`
- `frozen_by`
- `watermark`
- `note`

It also contains freeze functions:

- `activate_migration_freeze_v1`
- `release_migration_freeze_v1`
- `enforce_migration_freeze_v1`

These must be reconciled into repo SQL before a repeatable release.

## Phase 2: Export raw source rows

### Goal

Export data in a format that can be verified outside any vendor or MCP server.

### Rules

- Prefer JSONL for row exports.
- Include every source field needed to reconstruct or audit the original.
- Compute a stable `payload_hash` per row.
- Store export metadata: source, batch, timestamp, tool, row count, hash algorithm.
- Do not normalize while exporting.

### Required export evidence

```text
batch_id:
source_system:
source_row_count:
exported_row_count:
export_file:
export_file_sha256:
payload_hash_algorithm:
exported_at:
exported_by:
```

## Phase 3: Build migration manifest

### Goal

Every source row receives an explicit decision.

The live DB has `migration_manifest_v1`. The repo must capture this schema in versioned SQL.

### Minimum manifest fields

- batch ID
- source project/system
- source table
- source ID
- target table
- target ID
- action: `import`, `hold`, `exclude`, `evidence`
- exclusion reason
- payload hash
- target zone: HOUSE, VAULT, HOLD, EVIDENCE
- preservation class
- custodian
- subject ID
- lifecycle status
- review state
- topic key
- source timestamps
- source agent/kind/ref
- confidence
- workstream
- sensitivity
- processing profile
- transformation version
- review notes
- reviewer and review timestamp

## Phase 4: Classify rows

### HOUSE

Use HOUSE for general household/shared memory:

- projects
- preferences
- technical environment
- ordinary wiki docs
- open loops
- non-restricted decisions
- durable profile facts

### VAULT

Use VAULT for restricted or person-centered records:

- health
- finance
- identity
- legal authority
- beneficiaries
- sensitive family records

### HOLD

Use HOLD when:

- the row is stale current-state history;
- ownership/custodian is unclear;
- row contains mixed HOUSE/VAULT content;
- provenance is insufficient;
- conflict exists;
- human review is required.

### EVIDENCE

Use EVIDENCE for records that preserve process and auditability but should not become user memory:

- model_channel messages
- model_notebook notes
- migration manifests
- cutover probes
- doc integrity records
- raw operational evidence

## Phase 5: Import and preserve

### HOUSE import

Import active/durable facts into `memories` and durable docs into `wiki_pages` only after classification.

Rules:

- keep source provenance;
- preserve source timestamps where supported;
- do not promote stale state blindly;
- use `proposed` for historical state needing review;
- use `supersedes` for replacement/corrections;
- call or reconstruct hot-topic state only after payload correctness is verified.

### VAULT import

VAULT imports must preserve first:

1. insert raw payload into `vault_private.records`;
2. compute and store payload hash;
3. link normalized domain rows to preserved source;
4. create audit/source links;
5. normalize only after subject/custodian classification is reviewed.

## Phase 6: Readiness checks

The live DB contains `migration_readiness_v1`, which checks for classes of migration failure such as:

- unmanifested memories;
- unmanifested wiki pages;
- changed memory payloads;
- changed wiki payloads;
- expected HOUSE export count;
- expected EVIDENCE export count;
- null HOUSE payloads;
- null EVIDENCE payloads.

Before cutover, every readiness row must pass or be explicitly waived with a reason.

## Phase 7: Cutover probes

### Purpose

A migrated memory system is only successful if real recall works.

The live DB contains:

- `cutover_probe`
- `cutover_run`
- `cutover_scorecard`

A probe should represent a query or user expectation the new system must satisfy.

### Probe types

- exact-known fact
- project state retrieval
- correction retrieval
- stale-state avoidance
- sensitive-domain boundary
- model-channel retrieval
- hot-topic boot recall
- deadline recall

### Pass conditions

A cutover run passes only when:

- critical probes pass;
- stale/incorrect sources are avoided;
- expected topic or substring is found;
- old MCP output is not materially better than Supabase output;
- misses are reviewed and either fixed or accepted.

## Phase 8: Parallel run

Run legacy MCP and Supabase in parallel for a bounded period.

Recommended gates:

- no unmanifested source rows;
- readiness checks pass;
- critical cutover probes pass;
- no failed embeddings or pending hot-touch backlog;
- review queue is understood;
- backup and restore evidence exists;
- Warden/ATLAS review complete;
- Jesse explicitly approves cutover.

## Phase 9: Declare Supabase authoritative

Only after gates pass:

1. mark legacy MCP paths read-only if possible;
2. update assistant instructions to prefer Supabase;
3. keep fallback retrieval path documented but non-authoritative;
4. log cutover date, batch, evidence, and rollback window;
5. create a post-cutover review task one week later.

## Phase 10: Rollback and fallback

Rollback is not a failure if it is planned.

Keep:

- raw source exports;
- manifest;
- payload hashes;
- legacy MCP read path;
- cutover probe history;
- backup/restore evidence.

Rollback triggers:

- critical recall misses;
- integrity mismatch not explained;
- unexpected sensitive data exposure;
- manifest/readiness drift;
- failed backup/restore;
- repeated model confusion about authoritative store.

## Repo work required

To make this repeatable, the repo still needs:

1. SQL migration for migration manifest, freeze control, export views, readiness view, cutover probes.
2. A validation SQL bundle that produces a pass/fail cutover report.
3. Export scripts or documented commands for MCP source extraction.
4. Import/reconciliation examples.
5. A cutover evidence template.
6. A release tag after repo/live parity is restored.

## Current warning

The live production system contains migration/cutover objects not yet captured in this repository. Until they are reconciled, the repo is a strong baseline but not a complete reproduction of the active migration system.
