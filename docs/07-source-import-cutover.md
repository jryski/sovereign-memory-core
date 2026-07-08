# 07 · Source Import and Authoritative Cutover

## Purpose

Provide a general, repeatable process for importing memory/wiki/knowledge data from any prior source into Sovereign Memory Core without losing history, laundering stale state into active truth, or declaring the new store authoritative before evidence supports it.

This document is intentionally source-agnostic. A prior source might be:

- a file-based wiki;
- an MCP memory or wiki store;
- exported chat history;
- Markdown folders;
- a notes app;
- a database table;
- a spreadsheet;
- a vendor-native memory export;
- another Sovereign Memory deployment.

The same cutover discipline applies regardless of source.

## Non-negotiable principles

1. **No blind import.** Every source row or document receives a manifest entry.
2. **Preserve before transform.** Raw source payloads are exported and hashable before normalization.
3. **Classify explicitly.** Every item becomes `import`, `hold`, `exclude`, or `evidence`.
4. **Separate zones.** HOUSE, VAULT, HOLD, and EVIDENCE are different destinations with different authority.
5. **Old state is not automatically current truth.** Historical current-state claims require review before promotion.
6. **No silent overwrite.** Corrections supersede. Imported conflicts are surfaced.
7. **Cutover by tests, not vibes.** Readiness checks and recall probes must pass before the new store is declared authoritative.
8. **Rollback remains possible.** Prior sources remain readable until the new store has passed a confidence window.
9. **Bulk data must not transit model context.** Stage large exports server-side or as files, then verify transfer with row counts and checksums.

## Target architecture after cutover

```text
prior source(s)
        ↓ export + manifest + hashes
Sovereign Memory Core
├── HOUSE: general household, personal, project, and shared memory/wiki content
├── VAULT: restricted identity/health/finance/legal records
├── HOLD: records requiring human review or deferred classification
├── EVIDENCE: process records, channel messages, notebooks, integrity records, migration artifacts
└── REVIEW: proposed/stale/conflicting records surfaced for promotion/rejection
```

## Phase 0: Define source scope

### Goal

Know what is being imported before deciding how to import it.

### Required inventory

For each source:

- source system name;
- source table, collection, folder, or export file;
- source row/document count;
- source ID semantics;
- timestamp semantics;
- content fields;
- metadata fields;
- status/deletion/supersession semantics;
- attachment or file references;
- known reliability problems;
- export method;
- whether the source should remain readable after cutover.

### Output

Create an inventory note:

```text
source_system:
source_container:
row_or_document_count:
id_semantics:
timestamp_semantics:
content_fields:
metadata_fields:
status_semantics:
known_risks:
export_method:
post_cutover_role:
```

## Phase 1: Freeze or watermark

### Goal

Prevent the prior source from changing invisibly during export.

### Options

1. **Hard freeze:** stop writes to the source.
2. **Watermark:** record max updated timestamp, sequence, row count, and/or content hash before export.
3. **Dual-write window:** allow writes only if captured into both old and new stores.
4. **Read-only source:** if the source is already static, record its export hash and timestamp.

### Schema support

A mature deployment should include a freeze/watermark control record with:

- `is_frozen` or freeze state;
- batch ID;
- frozen/watermarked timestamp;
- actor;
- source counts;
- source high-water marks;
- notes.

## Phase 2: Export raw source data

### Goal

Export data in a format that can be verified outside the original system.

### Rules

- Prefer JSONL for row-like data and Markdown/files for document-like data.
- Include every source field needed to reconstruct or audit the original.
- Compute a stable `payload_hash` per item.
- Store export metadata: source, batch, timestamp, tool, row count, hash algorithm.
- Do not normalize while exporting.
- Do not rely on semantic search output as an export. Export the source records.
- Do not relay bulk source data through model context, chat transcripts, or tool stdin when a server-side export or file transfer is available.
- Verify exports and transfers by item count plus checksum before import.

### Required export evidence

```text
batch_id:
source_system:
source_item_count:
exported_item_count:
export_location:
export_sha256:
payload_hash_algorithm:
exported_at:
exported_by:
transfer_method:
transfer_verified_by:
notes:
```

## Phase 3: Build migration manifest

### Goal

Every source item receives an explicit decision.

A complete manifest should support:

- batch ID;
- source system/project;
- source table/folder/export;
- source ID/path;
- target table;
- target ID;
- action: `import`, `hold`, `exclude`, `evidence`;
- exclusion reason;
- payload hash;
- target zone: HOUSE, VAULT, HOLD, EVIDENCE;
- preservation class;
- custodian;
- subject ID;
- lifecycle status;
- review state;
- topic key;
- source timestamps;
- source kind/agent/ref where applicable;
- confidence;
- workstream;
- sensitivity;
- processing profile;
- transformation version;
- review notes;
- reviewer and review timestamp.

## Phase 4: Classify records

### HOUSE

Use HOUSE for general personal/household/shared memory:

- projects;
- preferences;
- technical environment;
- ordinary wiki docs;
- open loops;
- non-restricted decisions;
- durable profile facts;
- reusable operating knowledge.

### VAULT

Use VAULT for restricted or person-centered records:

- health;
- finance;
- identity;
- legal authority;
- beneficiaries;
- sensitive family records;
- other records whose existence or content requires stricter handling.

### HOLD

Use HOLD when:

- the record is stale current-state history;
- ownership/custodian is unclear;
- content mixes HOUSE and VAULT concerns;
- provenance is insufficient;
- conflict exists;
- target status is uncertain;
- human review is required.

### EVIDENCE

Use EVIDENCE for records that preserve process and auditability but should not automatically become user memory:

- model-to-model messages;
- notebooks or scratchpads;
- migration manifests;
- cutover probes;
- integrity records;
- raw operational evidence;
- import logs;
- historical exports.

## Phase 5: Import and preserve

### HOUSE import

Import active/durable facts into `memories` and durable docs into `wiki_pages` only after classification.

Rules:

- keep source provenance;
- preserve source timestamps where supported;
- do not promote stale state blindly;
- use `proposed` for historical state needing review;
- use `supersedes` for replacement/corrections;
- reconstruct hot-topic state only after payload correctness is verified;
- do not duplicate source rows already represented in the target.

### VAULT import

VAULT imports must preserve first:

1. insert raw payload into preserved-source storage;
2. compute and store payload hash;
3. link normalized domain rows to preserved source;
4. create audit/source links;
5. normalize only after subject/custodian classification is reviewed.

## Phase 6: Readiness checks

Before cutover, readiness checks should verify:

- no unmanifested source items;
- no changed source payloads after manifest review;
- expected import/export counts match;
- no null payloads in export views;
- all HOLD records are intentionally held;
- review queue is understood;
- critical records have source/provenance;
- backup and restore evidence exists;
- no unreviewed high-risk records were promoted.

Every readiness row must pass or be explicitly waived with a reason.

## Phase 7: Cutover probes

### Purpose

A migrated memory system is only successful if real recall works.

A probe should represent a query or expectation the new system must satisfy.

### Probe types

- exact-known fact;
- project state retrieval;
- correction retrieval;
- stale-state avoidance;
- sensitive-domain boundary;
- model-channel or evidence retrieval;
- hot-topic boot recall;
- deadline recall;
- source/provenance retrieval.

### Pass conditions

A cutover run passes only when:

- critical probes pass;
- stale/incorrect sources are avoided;
- expected topic, ID, or content is found;
- retrieval is traceable to the target store;
- misses are reviewed and either fixed or accepted.

Do not compare only convenience. Compare correctness, provenance, and freshness.

## Phase 8: Parallel run

Run the prior source and Sovereign Memory Core in parallel for a bounded period when the source is still available.

Recommended gates:

- no unmanifested source items;
- readiness checks pass;
- critical cutover probes pass;
- no unexplained derived-index backlog or pending attention backlog;
- review queue is understood;
- backup and restore evidence exists;
- cross-model review complete where applicable;
- owner explicitly approves authoritative cutover.

## Phase 9: Declare Sovereign Memory authoritative

Only after gates pass:

1. mark prior source read-only if possible;
2. update assistant instructions to prefer Sovereign Memory Core;
3. keep fallback retrieval path documented but non-authoritative;
4. log cutover date, batch, evidence, and rollback window;
5. create a post-cutover review task.

## Phase 10: Rollback and fallback

Rollback is not a failure if it is planned.

Keep:

- raw source exports;
- manifest;
- payload hashes;
- prior source read path where feasible;
- cutover probe history;
- backup/restore evidence.

Rollback triggers:

- critical recall misses;
- integrity mismatch not explained;
- unexpected sensitive data exposure;
- manifest/readiness drift;
- failed backup/restore;
- repeated agent confusion about authoritative store.

## Repo work required

To make this repeatable, the repo needs:

1. SQL migration for manifest, freeze/watermark control, export views, readiness view, and cutover probes.
2. A validation SQL bundle that produces a pass/fail cutover report.
3. Export/import examples for at least two different source types, such as JSONL rows and Markdown files.
4. A cutover evidence template.
5. A release tag after repo/live parity is restored.

## Current warning

The live production system may contain migration/cutover objects not yet captured in this repository. Until they are reconciled, the repo is a strong baseline but not a complete reproduction of that active deployment.
