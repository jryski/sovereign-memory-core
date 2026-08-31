# Sovereign Memory Core — Orientation

_Status: informative repository orientation_

## What this repository owns

Sovereign Memory Core owns the PostgreSQL reference implementation of Sovereign Memory Protocol semantics.

It is the place to ask:

- can the portable semantic be enforced in PostgreSQL?
- can the enforcement be independently evaluated?
- can the state be exported, restored, and verified outside the originating environment?
- can a deliberately broken perimeter or recovery path be detected rather than reported clean?

It is not the place to define universal SMP meaning merely because a PostgreSQL implementation exists first.

## Program map

```text
Sovereign Memory Protocol
        ↓
Sovereign Memory Core (this repo)
        ↓
user-context capability / deployments / applications
        ├── Supabase User MCP
        ├── Household OS
        ├── downstream business implementations
        └── runtime/orchestration layers such as Hermes
```

Separate evidence planes such as Model Radar may inform decisions without becoming data authority.

## Key boundaries

### Protocol vs Core

- Protocol defines portable semantics and conformance claims.
- Core implements those semantics using PostgreSQL migrations, ACL/RLS, triggers/functions, catalogs, and restore tooling.
- PostgreSQL-specific mechanisms belong here or in a PostgreSQL profile.

### Core vs deployment

Core does not contain real household/business data, credentials, project refs, private topology, or deployment receipts.

A deployment may extend Core and remain conformant. Schema identity is not the same as protocol conformance.

### Core vs data-plane MCP

Supabase User MCP owns authenticated user/agent data-plane access and the fixed tool/capability surface. Core does not become an MCP control plane.

### Core vs application

Household OS and other applications own UI, workflow, provider integration, local policy, and deployment-specific principal decisions.

## Current major evidence

- C1 perimeter evaluability: accepted.
- C2 provider-exit / clean restore: accepted for the synthetic/reference implementation.
- PR #82 release-closeout: merged after exact-head adversarial review.
- HOUSE #59: still an open deployment-specific P0 gate and not replaced by Core CI.

## Agent Access Integrity Boundary

The protocol repository is exploring a profile for existing systems that are about to receive novel agentic access.

Core's future role, if that concept is accepted, is to demonstrate the PostgreSQL substrate mechanics — not to define the portable concept. Likely PostgreSQL concerns include catalogs, effective privileges, canonical snapshot/root construction, WAL/LSN continuity, transaction attribution, continuity events, and restore handling.

## Review discipline

A clean PostgreSQL result is only meaningful when the evaluated population is known.

Examples of invalid shortcuts:

- no findings because a helper/table was missing;
- RLS clean while TRUNCATE or SECURITY DEFINER bypass remains reachable;
- source and target receipts agree because the same producer fabricated both;
- restore succeeded but readable positive controls were never exercised;
- a deployment is assumed accepted because the reference CI passed.

## Start here

- [README](../README.md)
- [Roadmap](../ROADMAP.md)
- [Positioning](positioning.md)
- [Perimeter](perimeter.md)
- [Perimeter evaluability](perimeter-evaluability.md)
- [Security-definer inventory](security-definer-inventory.md)
- [Restore rehearsal template](templates/restore-rehearsal.md)
