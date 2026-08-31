# Sovereign Memory Core Status

Status date: 2026-08-27

## Current release

`v0.3-alpha` is published at exact release commit:

`c96b9da749b2d95661973485b2a026897329c8cd`

The release freezes a bounded reviewed surface. It is not a claim that Core is a complete product or that every downstream deployment is aligned.

### Verified release gates

The release record includes:

- work-memory conformance on PostgreSQL 15 and 16;
- C1 perimeter evaluability on PostgreSQL 15 and 16;
- C2 independent clean provider-exit restore on PostgreSQL 16;
- executable schema-drift comparison;
- release manifest/checksum verification;
- independent exact-coordinate review;
- HOUSE rollback-safe recovery rehearsal with explicit scope limits.

See the [`v0.3-alpha` release](https://github.com/jryski/sovereign-memory-core/releases/tag/v0.3-alpha) and its attached evidence/known limitations.

## Scope limits that remain important

- Provider-exit support declared by the alpha remains PostgreSQL 15/16.
- The HOUSE PostgreSQL 17.10 rehearsal preserved a complete logical anchor but exercised a partial household-owned `public` restore in a plain-PostgreSQL lab because a hosted extension dependency was unavailable.
- Provider-managed hosted schemas/roles/ACLs were not reconstructed by that rehearsal.
- Shared or privileged credentials remain an attribution ceiling; a label is not cryptographic identity proof.
- A reference-runtime PASS does not prove a particular deployment has applied the same migrations, grants, or operational controls.

## Repository role

Core is the **PostgreSQL reference implementation**, not the normative SMP protocol and not a private deployment.

| Plane | Current role |
| --- | --- |
| Sovereign Memory Protocol | Separate private pre-release protocol package; owns implementation-neutral meaning/conformance |
| Sovereign Memory Core | PostgreSQL reference runtime, perimeter, replay, restore/provider-exit, adversarial tests |
| User/data capability adapters | Separate projects such as Supabase User MCP |
| Deployments/applications | Private topology, identity, policy, UI, credentials, recovery/acceptance evidence |

## Current development direction

### 1. Post-alpha hardening

New fixes and capabilities must land as successor evidence. Do not retroactively widen `v0.3-alpha` claims.

### 2. Protocol/Core separation

Protocol concepts duplicated in Core should be cross-linked/extracted after review while preserving historical evidence. PostgreSQL mechanisms stay here; portable meaning stays in the protocol.

### 3. Implementation self-description

Core should eventually emit a machine-readable declaration of:

- protocol/profile version;
- supported PostgreSQL versions;
- representation mappings;
- extensions/deviations;
- evaluated conformance surfaces;
- unsupported coverage.

### 4. Agent Access Integrity Boundary reference work

The SMP protocol project is evaluating an informative in-situ concept for establishing a forward T0 evidence boundary before agents are introduced to existing systems of record.

Core may later provide a PostgreSQL substrate/reference profile for that concept. No normative profile or production enrollment is implied today.

### 5. External data-plane reasoning

Security/containment evidence must eventually represent data and effects that travel outside ordinary table reads/writes, including object/blob Storage and other external capability planes. A relation-only inventory cannot claim complete closure when the authorized bytes/effects are elsewhere.

## Drift policy

This public repository should not carry a detailed inventory of any one private deployment.

Downstream deployments should maintain their own:

- repo/runtime pin;
- migration and object inventory;
- local extensions/deviations;
- perimeter/identity evidence;
- recovery/restore receipts;
- known waivers and review dates.

Generic drift templates and checks belong here only when they are reusable and synthetic/public-safe.

## Current blockers to stronger claims

These are successor-program gaps, not claims that invalidate the existing alpha coordinate:

1. Protocol draft and Core implementation self-description are not yet formally reconciled.
2. User/agent identity remains a downstream mechanism; Core alone cannot distinguish principals behind a shared privileged credential.
3. External data-plane containment/durability semantics need generic reference treatment.
4. Agent-access enrollment/continuity semantics are still an informative protocol proposal, not a frozen profile.
5. Broader PostgreSQL-version/deployment recovery claims require their own exact evidence rather than inheriting the alpha proof.

## Rule for this phase

Preserve evidence, exact coordinates, and claim limits. New work is allowed to improve the reference implementation, but it must not make older releases or downstream deployments appear to have been evaluated for properties they were not actually tested against.
