# Roadmap

## North star

Sovereign Memory Core exists to make AI memory custody and transfer
independently verifiable.

Short form:

> Chain of custody for AI memory.

The project should not compete to become the universal memory format or the
best retrieval engine. It should provide a reference runtime and executable
evidence for custody, provenance, authority, lifecycle, verification,
portability, and recovery semantics that other systems can compose with.

## Current phase

`v0.3-alpha` is published.

The alpha established a reviewed PostgreSQL reference runtime with fail-closed
perimeter evaluability, lifecycle/provenance tests, provider-exit evidence,
schema-drift checks, release receipts, and a separately exercised deployment
recovery procedure.

The project is now in a **post-alpha hardening and separation phase**. The next
work is not "finish the alpha." It is to reduce ambiguity, separate protocol
semantics from implementation and deployment concerns, improve operator
experience, and expand evidence only where new measurements justify broader
claims.

## Work streams

### 1. Protocol / specification separation

Goal: make implementation-neutral semantics readable and testable without
requiring PostgreSQL-specific knowledge.

- identify normative custody semantics currently embedded in Core docs/tests;
- keep PostgreSQL implementation details in Core;
- use positive neutrality tests where practical, not only identifier denylists;
- preserve history while material is copied/reconciled across repository
  boundaries;
- do not let downstream deployments redefine protocol semantics locally.

### 2. Core runtime hardening

Goal: make the PostgreSQL reference runtime safer and easier to evaluate.

- continue adversarial perimeter and migration testing;
- reduce broad/shared credential assumptions;
- strengthen verifiable principal/runtime attribution where feasible;
- keep release evidence bound to exact candidate coordinates;
- improve schema and deployment drift detection without turning approximate
  checks into stronger claims than they support.

### 3. Provider exit and recovery

Goal: broaden portability evidence deliberately.

- keep PostgreSQL 15/16 as the declared v0.3-alpha provider-exit range;
- add new PostgreSQL major versions only after independent version-matched proof;
- evolve bundle profiles where current representation constraints are too
  narrow;
- distinguish database portability from hosted-product reconstruction;
- keep recovery-anchor and rollback rehearsals part of deployment acceptance.

### 4. Source adapters and review flows

Goal: connect real source systems without weakening custody semantics.

- define adapter profiles and lossiness declarations;
- exercise import/review/cutover/rollback flows on representative data;
- keep proposals distinct from human acceptance;
- preserve conflict and supersession semantics;
- measure source-understanding quality instead of inferring it from deterministic
  packaging success.

### 5. Operator ergonomics

Goal: make the safe path obvious to humans.

Potential work includes:

- a doctor/preflight command;
- safer migration/install wrappers;
- clearer recovery and rollback tooling;
- executable drift inventory;
- clearer release/evidence inspection;
- local disposable-environment helpers.

Operator convenience must not bypass recovery, validation, authority, or
perimeter checks.

### 6. Documentation and adoption

Goal: make the project understandable without requiring issue archaeology.

- keep README and STATUS aligned with released evidence;
- maintain explicit "proved / not proved" boundaries;
- move stale historical plans out of current guidance rather than leaving them
  mixed with active instructions;
- document repository boundaries and contribution paths;
- keep terminology and protocol naming decisions deliberate and durable.

## Release philosophy

Future releases should be evidence-driven, not calendar-driven.

A release may broaden a claim only when the corresponding executable evidence
exists. A deployment-specific success does not silently broaden Core support,
and a Core test does not silently certify every downstream deployment.

Each release should answer four questions clearly:

1. What exact behavior is claimed?
2. On which runtime/provider/version surface was it measured?
3. What evidence can an independent reviewer reproduce?
4. What remains explicitly outside the claim?

## What is deliberately not on this roadmap

This repository is not the roadmap for:

- a household UI or household operating system;
- a business SaaS product;
- private deployment configuration;
- a generic vector database or RAG engine;
- a universal agent orchestrator;
- hosted-provider control-plane reconstruction.

Those systems may consume Core, but their product roadmaps belong downstream.

## Current release references

- [`README.md`](../README.md) — human-oriented project entry point
- [`STATUS.md`](../STATUS.md) — current implementation/release state
- [`release/v0.3-alpha-known-limitations.md`](../release/v0.3-alpha-known-limitations.md) — exact alpha claim boundaries
- [`docs/project-management.md`](project-management.md) — issue/PR/ADR operating model
