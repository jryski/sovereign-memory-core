# Repository Boundaries

This project is split into three layers. They are related, but they are not the same product and should not evolve as one repository.

The split below is intended ownership. Extraction of protocol text is not finished. This document does not record live deployment acceptance or production readiness.

## 1. Sovereign Memory Protocol

Repository: `jryski/sovereign-memory-protocol`

Purpose: the implementation-neutral normative home.

Belongs there:

- normative custody semantics;
- provenance and evidence concepts;
- authority and lifecycle semantics;
- supersession, retraction, erasure, and conflict rules;
- portable export and import requirements;
- conformance vocabulary and implementation-independent test vectors;
- protocol versioning and compatibility rules.

Must not depend on:

- PostgreSQL, Supabase, or any other hosted runtime;
- HOUSE, Household OS, or any other named deployment;
- a particular agent runtime, model provider, UI, calendar provider, or task system;
- deployment credentials, identifiers, data, or operating evidence.

## 2. Sovereign Memory Core

Repository: `jryski/sovereign-memory-core` (this repository)

Purpose: the PostgreSQL reference runtime and its conformance and adversarial harness.

Emerging protocol drafts may still appear in this tree under `docs/publication/` until they are extracted. That presence is transitional. It does not mean Core owns the protocol. The intended normative home remains the protocol repository. See [`PROGRAM-ROLE.md`](../PROGRAM-ROLE.md) and [`docs/positioning.md`](positioning.md).

Belongs here:

- portable PostgreSQL migrations that implement SMP contracts;
- reference runtime functions and security-perimeter behavior;
- synthetic fixtures;
- conformance and adversarial tests;
- repository-scoped upgrade, replay, export, restore, and portability machinery, exercised with synthetic evidence;
- implementation notes needed to operate or review the reference runtime.

Export and restore in this list mean repository-scoped machinery exercised with synthetic evidence. This document does not claim that export of private data, clean restore of private data, or independent live acceptance has been shown. Those remain open on issue #92.

Must not contain:

- household-specific policy or workflow;
- real household or personal records;
- Google Calendar, Skylight, school, travel, or other provider-specific operating configuration, except generic adapter contracts and fixtures needed to exercise the reference implementation;
- HOUSE agent assignments, project boards, schedules, or live coordination state;
- deployment credentials, project identifiers, or private acceptance evidence.

A defect found in a deployment belongs in Core only when it reproduces as a general defect in the reference runtime or the protocol contract. The public issue or pull request describes the general failure class and uses synthetic evidence.

## 3. HOUSE / Household OS deployment

Repository: a separate deployment repository, not this repository.

Purpose: the HOUSE / Household OS deployment, which consumes a pinned Core revision.

Belongs there:

- HOUSE topology and deployment manifests;
- household-specific policy and authority configuration;
- virtual Kanban and work coordination;
- agent identities, subscriptions, project membership, and handoff rules;
- scheduled agent sync and reconciliation workflows;
- Google Calendar, Skylight, school, travel, email, file, and other household connectors;
- deployment-specific schemas or extensions that are not part of SMP;
- operational runbooks and deployment-local backup and restore procedures;
- links to restricted evidence, without copying that content into public repositories.

The deployment may depend on a pinned Core revision. Core must never depend on HOUSE or Household OS.

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

Read the arrows as "implements or consumes." Dependencies run one way: protocol, then Core, then a deployment. They do not run from the protocol or from Core down into a deployment.

## Promotion rule

Deployment work can reveal reusable improvements. Promotion uses synthetic evidence only:

1. HOUSE-specific behavior stays in the deployment repository.
2. A reusable PostgreSQL implementation improvement is reproduced with synthetic data and proposed to Core.
3. An implementation-neutral semantic requirement is proposed to the protocol repository.
4. Private deployment evidence is not required to understand, test, or merge a public Core or Protocol change.

## Alpha critical-path rule

Repository separation does not expand the SMP/Core alpha gate. Household connectors, Kanban, and agent sync stay in the deployment repository. They become SMP or Core alpha work only when a reproduced defect shows that the protocol or the reference runtime cannot support them safely, and only after that defect is restated with synthetic evidence.
