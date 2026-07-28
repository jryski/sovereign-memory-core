# Upgrade Guide: Work Memory and Attention V2

## Scope

This guide separates **fresh-install contracts** from **live-deployment upgrades**.

- `sql/07_work_lessons.sql` defines the desired work-memory v2 state for a fresh installation.
- `sql/08_attention_events.sql` defines the desired attention-event and projection v2 state after the core schema.
- `sql/09_perimeter_refresh.sql` re-closes PostgreSQL default privileges after optional public-schema layers.
- Existing deployments must not blindly replay these files over live tables.

The upgrade must preserve history, avoid synthetic observations, and maintain a usable boot path throughout the transition.

## Preflight

Before any mutation:

1. Take a database snapshot or logical export.
2. Prove that the backup can be restored into an isolated database.
3. Inventory table definitions, constraints, triggers, grants, policies, and function source.
4. Record row counts and integrity checks for lessons, evidence, authority events, memories, attention events, assignments, and hot references.
5. Identify every runtime principal and credential that can execute SQL or RPCs.
6. Run a read-only boot projection for each real viewer.
7. Prepare rollback-only acceptance tests against the actual deployment, not only the portable schema.

## Work-memory upgrade sequence

### 1. Add custody structures without changing boot behavior

Add:

- authority state and acceptance metadata to lesson rows;
- typed `work_lesson_evidence` rows;
- append-only `work_lesson_events` rows;
- correction lineage for evidence;
- terminal/current evidence view.

Backfill existing evidence strings as **legacy or unverified evidence**. Do not label a locator resolvable merely because it is non-empty.

### 2. Establish sanctioned functions

Install and behaviorally test:

- proposal;
- evidence append;
- evidence correction;
- acceptance;
- rejection;
- proposed supersession;
- deterministic boot fragment.

Tests must exercise positive and negative behavior inside rollback-only transactions.

### 3. Close routine mutation paths

Only after sanctioned functions work:

- revoke direct insert, update, delete, and truncate from routine runtime roles;
- add lesson write-path guards;
- add append-only evidence and event guards;
- enable RLS with explicit policies when the deployment uses RLS;
- verify that enabling RLS does not accidentally block sanctioned SECURITY DEFINER paths.

A shared service credential is an audited guardrail, not proof of human approval.

### 4. Normalize evidence by appending corrections

For each vague, false, or noncanonical locator:

1. Find the real durable handle.
2. Append a corrected evidence successor.
3. Append an evidence-correction event.
4. Mark the new row resolvable only after a reviewer can retrieve it.
5. Leave the original row intact.

Do not invent a locator to satisfy a non-null constraint. If no truthful durable handle exists, preserve the evidence as invalid or unverified and keep the behavioral lesson blocked.

### 5. Enable the resolvable-evidence boot gate

Before changing boot:

- list every accepted active rule and prohibition;
- prove each has at least one current resolvable evidence row;
- compare expected versus actual boot counts.

Then switch boot loading to require:

- active status;
- accepted authority state;
- supported scope;
- current resolvable evidence for rules and prohibitions.

Worked and failed rows remain historical evidence and are not injected.

## Attention upgrade sequence

### 1. Preserve existing state; do not fabricate history

Create event and assignment tables empty unless real native events have already been captured by a trustworthy source.

Do not translate historical imports, chat exports, or existing touch counters into generic attention events. A counter is not a reconstructable event history.

### 2. Install append-only event custody

Add:

- stable identity key;
- revision key;
- revision ordinal;
- event supersession linkage;
- assignment supersession linkage;
- append-only guards;
- deterministic length-delimited hashing;
- bounded revision append API.

If an earlier schema made `identity_key` unique, remove that uniqueness before permitting multiple revisions. Keep `revision_key` unique.

### 3. Capture native creation and activation separately

Install capture for:

- active native insert → `memory_created`;
- proposed-to-active transition → `memory_activated`.

Promotion must be observed at the actual status transition. A promotion is not a second creation event.

Exclude import and ingest rows. Test idempotent replay before the first production event.

Prefer the first organic native write as the production proof. Do not add a synthetic seed merely to make the ledger non-empty.

### 4. Remove destructive presentation behavior

Inventory old hot-index and staging rows before changing the write path.

Replace:

- two-touch visibility gates;
- fixed row caps;
- destructive eviction;
- stale-pointer bumps;

with a non-destructive upsert where every eligible first touch can participate in ranking. Limit and compress only in presentation.

Do not silently delete invalid hot links. Classify each as:

- repoint to a proven active successor;
- preserve pending review;
- retire the attention link while preserving canonical history.

### 5. Install the exact character projection

The portable v2 projection uses serialized PostgreSQL characters:

`char_length(payload::text) <= effective_char_budget`

Before replacing boot, test:

- exact rendered count;
- escaped text;
- multibyte text;
- deterministic ordering;
- lower-budget prefix preservation;
- owner/visibility filtering for every real viewer;
- explicit omission counts and retrieval handle.

This contract does not guarantee UTF-8 bytes or model tokens.

### 6. Refresh the public perimeter

PostgreSQL grants EXECUTE on newly created functions to PUBLIC unless defaults have already been changed for the creating role. After the final optional layer:

1. run `sql/09_perimeter_refresh.sql` or an equivalent reviewed closure;
2. rerun the perimeter assertion;
3. verify the intended runtime RPC grants still exist;
4. verify anonymous, ordinary authenticated, and PUBLIC roles hold no unintended table, sequence, or function privileges.

Do not treat the perimeter closure in the baseline core as sufficient for functions created later.

## Acceptance gates

An upgrade is not complete until independent checks show:

- no routine direct DML on authority-bearing or append-only tables;
- proposed lessons absent from boot;
- evidence-blocked behavioral lessons absent from boot;
- accepted, evidence-backed lessons present in deterministic order;
- evidence corrections and authority decisions append custody records;
- active native inserts emit exactly one creation event;
- proposed inserts emit none;
- activation emits exactly one activation event;
- replay is idempotent;
- changed observations append revisions rather than collide or overwrite;
- imports emit no fabricated native events;
- every viewer's projection respects owner and visibility;
- character budgets are exact and monotonic;
- invalid attention links are measured and deliberately resolved;
- the post-layer perimeter assertion passes;
- rollback-only tests leave no fixtures.

## Rollback posture

Schema changes that add append-only custody are normally fix-forward. Rollback should be reserved for defects that make current records unusable, expose data, or corrupt lineage.

Keep the prior boot function available until the replacement passes comparison. Do not delete old tables or columns in the same change that establishes the new contract. Removal belongs in a later, separately reviewed migration after restore confidence and consumer migration are proven.
