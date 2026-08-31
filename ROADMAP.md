# Sovereign Memory Core Roadmap

_Status: implementation planning; not protocol authority_
_Last updated: 2026-08-27_

## Role

Sovereign Memory Core is the PostgreSQL reference implementation of SMP. It should demonstrate and attack portable protocol semantics without defining them through PostgreSQL-specific mechanisms.

## Current release lane

### 1. Close the v0.3-alpha deployment gate

Core-side release evidence is substantially complete:

- perimeter evaluability accepted;
- provider-exit/clean-restore proof accepted for the reference implementation;
- release-closeout PR #82 merged after exact-head adversarial review.

Remaining wider alpha gate:

- live HOUSE issue #59 recovery-anchor and PostgreSQL 17 restore/rollback acceptance.

Core must not claim a live deployment passed merely because the synthetic/reference implementation did.

## Near-term Core work

### 2. Preserve migration and release ordering

- Keep migration `11` as perimeter evaluability.
- Keep downstream topology/search-scope work on migration `12` after rebase onto current main.
- Ensure workflow path filters cover schema-affecting changes so release baselines cannot silently go stale.
- Keep exact-candidate release evidence bound to independently derived ground truth, not merely self-consistent receipts.

### 3. Reconcile protocol authority boundaries

As the private `sovereign-memory-protocol` baseline is established:

- remove language that treats Core as protocol authority;
- maintain crosswalks during transition rather than moving/deleting release-critical material;
- copy/sanitize portable semantics upstream only after reviewed authorization;
- keep PostgreSQL mechanisms in Core or PostgreSQL substrate profiles.

### 4. Reference the emerging Agent Access Integrity Boundary

Protocol issue #9 is defining a forward evidence boundary for legacy systems before agent access. Core may later implement a PostgreSQL substrate profile including:

- protected-surface/catalog inventory;
- canonical snapshot/root mechanics;
- effective read-only/write-path enumeration;
- WAL/logical-decoding/change-continuity evidence;
- continuity receipts for migrations, failover, PITR, and restore;
- agent-access enablement gates and drift/suspension handling.

Do not implement the portable semantics here before the protocol design is accepted.

### 5. Extend effective-perimeter coverage

Operational findings continue to show that authorization and durability surfaces extend beyond ordinary DML/RLS. Future Core/reference work should explicitly account for:

- TRUNCATE/TRIGGER/REFERENCES and sequence privileges;
- inherited roles and `PUBLIC` defaults;
- SECURITY DEFINER call paths;
- external data planes where a policy table is only the authorization anchor and not the data path;
- sanctioned public/API entrypoint registries with exact postconditions.

### 6. Recovery and erasure hardening

After alpha:

- preserve independently reproducible recovery procedures;
- extend erase/retention/non-resurrection evidence;
- keep currentness separate from snapshot reproducibility;
- add deliberately broken recovery controls and stale-restore fixtures.

## Longer-term reference profiles

Core should eventually demonstrate multiple optional profiles without becoming a monolith:

- PostgreSQL custody/provenance profile;
- PostgreSQL agent-access integrity profile;
- export/restore/provider-exit profile;
- approval/actor-assurance reference primitives;
- external-data-plane integration examples.

## Non-goals

Core will not become:

- the normative SMP repository;
- a generic user-context MCP server;
- the Household OS application;
- a model-routing/orchestration platform;
- a deployment authority repository;
- a universal retrieval or RAG engine.

## Gate discipline

A Core `PASS` must identify:

- exact artifact/commit;
- tested PostgreSQL versions;
- evaluated population/surface;
- positive and negative controls;
- unsupported/not-evaluated coverage;
- whether evidence is independently derived or self-reported.
