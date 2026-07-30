# Positioning: custody protocol versus memory engine

Sovereign Memory Protocol (SMP) and memory engines solve related but different problems.

A memory engine decides how to capture, extract, rank, retrieve, summarize, and deliver context to an AI model. SMP defines how memory evidence and derived state remain attributable, inspectable, portable, correctable, erasable, and independently recoverable across engines and providers.

## Boundary

| Concern | Memory engine | SMP custody protocol |
|---|---|---|
| Evidence capture | May store raw interactions or events | Defines the custody and provenance requirements for preserved evidence |
| Extraction | Produces facts, observations, summaries, or graph nodes | Requires derived state to retain support and lifecycle relationships |
| Retrieval | Selects useful context for a question | Does not prescribe ranking, embeddings, graphs, or query planning |
| Answer synthesis | Instructs or supplies an answer model | Does not prescribe an answer model or answer policy |
| Authority | Often implicit in the application or service credential | Separates actor, runtime, credential, principal, authorization, and acceptance |
| Time | Often models recency or fact-validity windows | Requires reconstructable observed, recorded, effective, accepted, superseded, and reverted lineage where applicable |
| Correction | Updates or supersedes retrieved state | Requires history-preserving correction, conflict, supersession, and invalidation semantics |
| Portability | May expose an API or database export | Requires a verifiable package, checksums, independent restore, and conformance result |
| Erasure | Deletes from the primary store | Requires explicit scope and evidence for projections, logs, traces, exports, and backups |
| Conformance | Usually measured through retrieval or answer benchmarks | Measured through implementation-neutral custody, lifecycle, integrity, authority, and recovery outcomes |

A memory engine may conform to SMP. SMP should not become a retrieval engine.

## Eywa crosswalk

The May 2026 paper *Eywa: Provenance-Grounded Long-Term Memory for AI Agents* is a strong adjacent architecture reference.

Eywa independently supports several design choices that also appear in SMP:

- evidence before belief;
- immutable source evidence separated from derived canonical facts;
- explicit evidence-to-belief provenance;
- revisable and supersedable beliefs;
- deterministic retrieval with no LLM calls in the read path;
- separation of retrieved context from answer-policy instructions;
- an authoritative local store with vector and graph projections treated as rebuildable indexes;
- failure categories that distinguish coverage, grounding, revision, scope, temporal, retrieval, synthesis, and measurement errors.

These are meaningful points of corroboration, not reasons to collapse the projects together.

Eywa is primarily a memory architecture and engine. Its paper evaluates extraction, retrieval, context assembly, answer-model separation, and benchmark quality. SMP covers additional custody and governance boundaries that an engine can implement:

- portable evidence and lifecycle contracts independent of SQLite, PostgreSQL, or a hosted service;
- explicit proposal, acceptance, inference, conflict, authority, and review semantics;
- actor, runtime, credential, principal, and authorization lineage;
- complete effective-time and recorded-time decision history where required;
- deterministic export package and independently verified restore;
- implementation-neutral conformance fixtures and expected outcomes;
- erasure semantics that account for projections, logs, traces, exports, and backups;
- deployment separation across independent trust domains.

Eywa correctly states that provenance proves support by a source, not external truth. SMP should preserve that distinction: custody can prove what was recorded, derived, accepted, or changed and why; it cannot automatically prove that a user's original assertion was factually true in the outside world.

## Conformance must remain implementation-neutral

The protocol repository should publish data fixtures, operations, expected state transitions, expected errors, and verification outcomes.

It should not define conformance as “run this PostgreSQL SQL file.” PostgreSQL-specific runners belong in Sovereign Memory Core. Other implementations should be able to prove the same custody outcomes without adopting the reference database.

Likewise, retrieval benchmarks such as LoCoMo, LongMemEval, or BEAM may demonstrate the quality of a memory engine, but they do not by themselves prove custody conformance. A system can retrieve well while losing provenance, authority, prior state, or provider-exit capability. A custody-conformant store can preserve those properties while using a mediocre retriever.

## Public communication rule

Describe SMP as infrastructure that complements memory engines:

> SMP provides portable custody, provenance, authority, lifecycle, and recovery contracts for AI memory. It does not prescribe how an application extracts or retrieves the memories it holds.

Avoid claiming that SMP outperforms, replaces, or subsumes Eywa or other memory engines. The intended relationship is composability: strong engines should be able to use a strong custody substrate.

## Status

This boundary is the intended architecture. The current public repository still contains both emerging protocol material and the PostgreSQL reference implementation. Repository separation is being prepared through a reviewed ADR and sanitized, fresh-history extraction plan.
