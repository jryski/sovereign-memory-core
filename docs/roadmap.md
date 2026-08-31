# Sovereign Memory Core Roadmap

_Status: reference-runtime planning document; protocol meaning lives upstream in SMP_

## North star

Sovereign Memory Core is the PostgreSQL reference runtime for proving that provenance, custody, authority boundaries, change history, and provider-exit/recovery claims can be made executable rather than aspirational.

Short form:

> **A PostgreSQL reference implementation you can audit, move, restore, and prove.**

The protocol should remain substrate-neutral. Core exists to implement and attack one concrete substrate.

## Current release boundary

`v0.3-alpha` is published at commit `c96b9da749b2d95661973485b2a026897329c8cd`.

The alpha freezes a bounded reviewed surface rather than claiming product completeness. It includes PostgreSQL 15/16 conformance/perimeter/provider-exit evidence and a separately scoped HOUSE recovery rehearsal with known hosted-extension/role limitations.

Future work must not silently widen what `v0.3-alpha` meant. New claims belong to successor coordinates and new evidence.

## Track A — Post-alpha reference-runtime hardening

- preserve exact migration/reapply ordering and perimeter evaluability;
- close successor findings without rewriting release history;
- keep release evidence bound to independently derived ground truth;
- expand catalog/perimeter coverage only with explicit positive and broken controls;
- preserve recovery/provider-exit claim limits by version/profile.

## Track B — Protocol / implementation separation

The SMP protocol now has its own repository and review lineage. Core should remove or clearly label material that is normative in meaning but currently duplicated here.

Rules:

- protocol defines meaning and conformance semantics;
- Core defines PostgreSQL mechanisms and reference tests;
- deployments define local policy/topology/identity;
- copy/cross-link before any post-alpha deduplication; do not delete useful history just to make the tree tidy;
- implementation self-description should declare protocol/profile version, mappings, extensions, unsupported requirements, and known deviations.

## Track C — Agent Access Integrity Boundary reference profile

The protocol project is evaluating an informative in-situ profile for establishing a forward T0 evidence boundary before agents are granted access to existing systems of record.

Core's possible role is a **PostgreSQL substrate/reference profile**, not protocol ownership.

Candidate reference work, only after the protocol design is sufficiently frozen:

- protected-surface manifest and canonical serialization rules;
- catalog/role/write-path enumeration for effective read-only claims;
- transaction/change-log continuity and gap evidence;
- baseline/chunk/Merkle commitment reference implementation;
- shared-credential attribution limits;
- continuity receipts for migrations, bulk jobs, failover, PITR, restore, and replica relationships;
- `ACCESS_ENABLED`, drift/UNKNOWN/suspension fixtures;
- evidence-plane independence declarations;
- synthetic adversarial fixtures proving omitted surface, capture gaps, restore discontinuity, and indirect write paths fail closed.

Do not add PostgreSQL-specific requirements to the portable protocol simply because Core implements them first.

## Track D — External data planes

Recent user-context/Storage work proved that a policy relation and the data path can be different things. Core/conformance reasoning should generalize beyond "tables are the universe."

Reference work should be able to describe:

- relational rows;
- object/blob bytes authorized by relation policy;
- file/content-addressed artifacts;
- queues/events and other external effect paths;
- read and durability edges separately.

A closure result that ignores an authorized external data plane must be `INCOMPLETE`, not PASS.

## Track E — Neutrality and interoperability

- align Core with protocol fixtures without making Core's schema normative;
- provide exact implementation self-description;
- run protocol vectors through at least one non-PostgreSQL implementation/stub alongside Core;
- keep generic profile fixtures synthetic and public-safe;
- treat downstream differences as mappings/extensions/limitations unless they violate protocol semantics.

## Track F — Operator and deployment tooling

Useful future Core tooling may include:

- install/doctor/version checks;
- migration ordering and drift inventory;
- export/restore evidence runners;
- perimeter report collection;
- implementation self-description export;
- reference protected-surface enrollment/reconciliation tooling for PostgreSQL.

Deployment-specific credentials, production data, user interfaces, and operating receipts remain downstream.

## Release strategy

Successor releases should be defined by evidence gates rather than a feature-count ladder.

Every release candidate should state:

- exact commit/tree;
- supported PostgreSQL versions/profiles;
- defined/evaluated/passed conformance dimensions;
- release evidence and independent review coordinates;
- known limitations and unsupported coverage;
- provider-exit/recovery claim scope;
- whether any new protocol draft dependency is normative, experimental, or unsupported.

## Standing rules

- **Protocol meaning flows down; deployment policy does not flow up.**
- **PASS says what was evaluated.**
- **A checksum is not truth.**
- **A valid restore is not automatically current.**
- **A user/agent label is not identity proof.**
- **A relation-only security model is incomplete when bytes/effects travel through another plane.**
- **History is preserved; successor work does not rewrite what earlier releases claimed.**
