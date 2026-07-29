# Executable upgrade: work memory and attention v2 to v3

## Safety posture

This is a fix-forward upgrade.

- Do not rewrite existing event, assignment, lesson, evidence, or authority-event rows.
- Do not backfill missing native events through replay.
- Apply the portable SQL in order: `07`, `08`, then `09`.
- Run `09` last after every optional layer.
- Reapply the same files once to prove idempotency.
- Execute tests in a transaction or disposable database.

## What changes

### Native event production

Runtime-callable creation and activation functions become existence-only lookups. Trigger functions write new native events directly from the actual source transition.

### Revision keys

New producers hash the exact persisted `source_revision`. Existing immutable rows retain their historical contract and keys.

### Revision attribution and concurrency

New revisions use current runtime observer context and assertion-grade labeling when stronger credentials are unavailable. Per-identity advisory locking makes concurrent identical replay return one winner.

### Rejected successors

The live-successor uniqueness predicate excludes rejected proposals. Rejected history remains readable while a replacement successor can be proposed.

### Context accounting

The projection replaces assumed multi-pass stabilization with a bounded fixed-point calculation and assertion.

### Public locator kinds

Deployment-specific coordination-store names are replaced by the generic `coordination_ref` protocol kind. Deployment mappings remain outside the public package.

### Perimeter

The final migration revokes schema creation and stale grants, enforces RLS/FORCE RLS on protected tables, verifies owners and SECURITY DEFINER search paths, and denies runtime execution of trigger-only writers.

## Required receipts

An upgrade is accepted only with:

- before/after row counts and immutable snapshots for protected historical rows;
- runtime-role fabrication denial;
- actual insert and actual activation capture;
- independent revision-key recomputation;
- current observer attribution;
- reject-then-replace success;
- fixed-point boundary tests;
- reapply and drift-remediation tests;
- concurrent replay test;
- final perimeter assertion;
- zero persistent live fixtures.
