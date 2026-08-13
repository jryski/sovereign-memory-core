# Repository Boundaries

This project is intentionally split into three layers. They are related, but they are not the same product and should not evolve in the same repository.

## 1. Sovereign Memory Protocol

Repository: `jryski/sovereign-memory-protocol`

Purpose: the implementation-neutral contract.

Belongs there:

- normative custody semantics;
- provenance and evidence concepts;
- authority and lifecycle semantics;
- supersession, retraction, erasure, and conflict rules;
- portable export/import requirements;
- conformance vocabulary and implementation-independent test vectors;
- protocol versioning and compatibility rules.

Must not depend on:

- PostgreSQL or Supabase;
- HOUSE or any other named deployment;
- a particular agent runtime, model provider, UI, calendar provider, or task system;
- deployment credentials, identifiers, data, or operating evidence.

## 2. Sovereign Memory Core

Repository: `jryski/sovereign-memory-core`

Purpose: the PostgreSQL reference implementation of SMP and its adversarial/conformance harness.

Belongs here:

- portable PostgreSQL migrations implementing SMP contracts;
- reference runtime functions and security perimeter behavior;
- synthetic fixtures;
- conformance and adversarial tests;
- upgrade, replay, export/restore, and portability machinery;
- implementation notes necessary to operate or review the reference runtime.

Must not contain:

- household-specific policy or workflow;
- real household or personal records;
- Google Calendar, Skylight, school, travel, or other provider-specific operating configuration except generic adapter contracts/fixtures needed to exercise the reference implementation;
- HOUSE agent assignments, project boards, schedules, or live coordination state;
- deployment credentials, project identifiers, or private acceptance evidence.

A defect found in a deployment belongs in Core only when it reproduces as a general defect in the reference implementation or protocol contract. The public issue/PR should describe the general failure class and use synthetic evidence.

## 3. HOUSE / Household OS deployment

Repository: separate deployment repository, not this repository.

Purpose: the Ryski household deployment and the household operating layer built on released SMP/Core capabilities.

Belongs there:

- HOUSE topology and deployment manifests;
- household-specific policy and authority configuration;
- virtual Kanban/work coordination;
- agent identities, subscriptions, project membership, and handoff rules;
- scheduled agent sync/reconciliation workflows;
- Google Calendar, Skylight, school, travel, email, file, and other household connectors;
- deployment-specific schemas or extensions that are not part of SMP;
- operational runbooks, acceptance receipts, backup/restore procedures, and sanitized architecture diagrams;
- links to restricted/private evidence without copying sensitive content into public repositories.

The deployment may depend on a released or pinned Core version. Core must never depend on HOUSE.

## Dependency direction

```text
Sovereign Memory Protocol
        ^
        |
Sovereign Memory Core
        ^
        |
HOUSE / Household OS deployment
        ^
        |
Agents, UIs, calendars, task boards, connectors
```

Read the arrows as "implements or consumes." Dependencies do not run downward from protocol or Core into a deployment.

## Promotion rule

Deployment work can reveal reusable improvements. Promotion happens only after classification:

1. HOUSE-specific behavior remains in the deployment repository.
2. A reusable PostgreSQL implementation improvement is reproduced with synthetic data and proposed to Core.
3. A genuinely implementation-neutral semantic requirement is proposed to the Protocol repository.
4. No private deployment evidence is required to understand, test, or merge a public Core or Protocol change.

## Alpha critical-path rule

Repository separation is architectural hygiene, not permission to expand the current alpha scope. Existing release-critical Core defects remain blockers. Household OS features, provider connectors, Kanban UX, and agent-sync implementation proceed in the deployment repository without becoming SMP alpha requirements unless a reproduced load-bearing defect demonstrates that the protocol or reference runtime cannot support them safely.
