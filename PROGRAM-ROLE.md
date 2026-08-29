# Program role: Sovereign Memory Core

> **Program:** Sovereign AI OS  
> **Role class:** shared kernel reference implementation  
> **Program context:** [`docs/ecosystem/SOVEREIGN_AI_OS.md`](docs/ecosystem/SOVEREIGN_AI_OS.md)  
> **Implementation status authority:** [`STATUS.md`](STATUS.md)

## Mission

Sovereign Memory Core is the PostgreSQL reference implementation and adversarial proof surface for durable AI memory custody. It demonstrates that provenance, review, temporal truth, conflict preservation, migration, cutover, recovery, and provider exit can be enforced and evaluated independently of any model or application.

## This repository owns

- the reference PostgreSQL custody schema and enforcement functions;
- synthetic fixtures and adversarial tests;
- source preservation, candidate review, promotion, rejection, supersession, and cutover mechanics;
- migration, validation, backup, restore, and provider-exit evidence;
- reference implementation guidance that remains generic across deployments.

## This repository does not own

- household, business, school, product, supplier, customer, calendar, or other deployment-specific tables;
- permanent user or agent connection identity;
- the runtime MCP capability surface;
- agent orchestration, model routing, or integration execution;
- a household or business kanban deployment;
- real user, household, or company data.

## Upstream dependencies

- Sovereign Memory Protocol for implementation-neutral semantics and conformance direction.
- PostgreSQL behavior and documented extension/runtime assumptions.

## Downstream consumers

- personal and household memory deployments;
- Household OS;
- Sovereign Vault and other business deployments;
- Supabase User MCP adapters;
- importers, review applications, and portable storage profiles.

## Planning and work-plane relationship

The Sovereign AI OS planning plane may consume Core-style provenance, review, evidence, correction, and audit patterns. Planning remains a separate organizational capability because work state, assignment, dependencies, leases, events, and external synchronization have a different lifecycle from durable memory custody.

A planning defect that reveals a generic custody or provenance problem may be reproduced here with synthetic fixtures. Deployment-specific task policy must remain in its owning deployment repository.

## Security and transition posture

Core proves database invariants and perimeter behavior. It does not prove that a privileged service-role or database-owner connection represents a specific human or agent. Principal-bound runtime identity is the responsibility of the data-plane access layer, including Supabase User MCP.

The privileged build/control plane and the principal-bound runtime data plane must remain distinct. Do not claim multi-principal isolation from a test performed only through an administrative connection.

## Data boundary

This public repository contains only generic implementation material and synthetic evidence. Never commit credentials, production identifiers, private records, recovery artifacts, raw dumps, or deployment-specific facts.

## Agent handoff rule

Before ending work, promote consequential findings into a test, issue, pull request, status update, decision record, or linked planning-card evidence. Chat output alone is not project state.