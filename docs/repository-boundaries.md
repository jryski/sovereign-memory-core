# Repository Boundaries

Ownership runs across the protocol, Core, the public Household OS reference, and the private HOUSE deployment. They are related, but they are not the same product and should not evolve as one repository.

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
- Household OS, a private HOUSE deployment, or any other named domain reference or deployment;
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
- public Household OS schemas, connector contracts, planning behavior, or virtual Kanban;
- HOUSE topology, agent identities, schedules, credentials, or live coordination state;
- deployment credentials, project identifiers, or private acceptance evidence.

A defect found in public Household OS or in a private HOUSE deployment belongs in Core only when it reproduces as a general defect in the reference runtime or the protocol contract. The public issue or pull request describes the general failure class and uses synthetic evidence.

## 3. Household OS and private HOUSE

Public Household OS and the private HOUSE deployment are different layers. Sovereign AI OS routes classify Household-OS as generic-upstream. HOUSE consumes that public reference. Neither layer is this repository.

### 3a. Household OS

Repository: `jryski/Household-OS`

Purpose: the public household-domain reference. It is generic-upstream of a private HOUSE deployment and consumes a pinned Core revision.

Belongs there:

- household-domain schemas and contracts;
- synthetic fixtures;
- connector contracts, including observation and reconciliation contracts;
- planning behavior, including virtual Kanban and work coordination;
- generic household policy examples that name no live deployment.

Public Household OS forbids real topology, identities, and credentials. It must not contain:

- real topology or deployment manifests;
- agent identities, subscriptions, or live project membership;
- credentials, project identifiers, or private acceptance evidence;
- operational runbooks for a named deployment;
- links to restricted evidence;
- real household or personal records.

Household OS may depend on a pinned Core revision. Core must never depend on Household OS. Household OS must never depend on a private HOUSE deployment.

### 3b. Private HOUSE deployment

Repository: a separate private deployment repository, not this repository and not `jryski/Household-OS`.

Purpose: the private HOUSE deployment. It consumes public Household OS and a pinned Core revision.

Belongs there:

- HOUSE topology and deployment manifests;
- household-specific authority configuration for this deployment;
- agent identities, subscriptions, project membership, and handoff rules;
- credentials and project identifiers;
- scheduled agent sync and live reconciliation workflows;
- live connector configuration for calendar, school, travel, email, file, and other household providers;
- deployment-specific schemas or extensions that are not part of SMP or of the public household-domain reference;
- operational runbooks and deployment-local backup and restore procedures;
- links to restricted evidence, without copying that content into public repositories.

The private deployment may depend on public Household OS. Public Household OS must never depend on HOUSE. Core must never depend on HOUSE or on Household OS.

## Dependency direction

```text
Sovereign Memory Protocol
        ^
        |
Sovereign Memory Core
        ^
        |
Household OS
        ^
        |
private HOUSE deployment
        ^
        |
Agents, UIs, calendars, task boards, connectors
```

Read the arrows as "implements or consumes." The household chain is Core ← Household OS ← HOUSE. Dependencies run one way: protocol, then Core, then public Household OS, then a private HOUSE deployment. They do not run from the protocol, from Core, or from public Household OS down into HOUSE.

## Promotion rule

Domain-reference and deployment work can reveal reusable improvements. Promotion uses synthetic evidence only:

1. Private HOUSE behavior stays in the private deployment repository.
2. A reusable household-domain schema, contract, synthetic fixture, connector contract, or planning and virtual Kanban behavior is proposed to public Household OS, without real topology, identities, or credentials.
3. A reusable PostgreSQL implementation improvement is reproduced with synthetic data and proposed to Core.
4. An implementation-neutral semantic requirement is proposed to the protocol repository.
5. Private deployment evidence is not required to understand, test, or merge a public Household OS, Core, or Protocol change.

## Alpha critical-path rule

Repository separation does not expand the SMP/Core alpha gate. Public Household OS planning, virtual Kanban, and connector contracts stay in the public reference. Private HOUSE agent sync stays in the private deployment. They become SMP or Core alpha work only when a reproduced defect shows that the protocol or the reference runtime cannot support them safely, and only after that defect is restated with synthetic evidence.
