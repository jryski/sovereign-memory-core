# Attention Layer

## Status

**Correctness and event-custody contracts defined; production ranking model intentionally open.**

This document describes a portable attention substrate and presentation contract. It does not prescribe a final decay law, a fixed topic count, or a vendor-specific implementation.

The reference schema is in [`sql/08_attention_events.sql`](../sql/08_attention_events.sql), with rollback-only checks in [`tests/08_attention_events.sql`](../tests/08_attention_events.sql).

## Purpose

The attention layer helps an agent orient at the start of a session by estimating which workstreams, questions, and artifacts are likely to matter now.

It is **orientation, not authority**.

Attention may be inferred, recomputed, reordered, and replaced. Canonical facts, consequential decisions, permissions, and provenance remain governed by their own custody and authority rules.

## Correctness requirements

A compliant implementation should satisfy these properties before scoring quality is considered:

1. Every eligible candidate can participate in ranking; a first observation must not be trapped in an invisible staging state.
2. Presentation limits do not delete evidence or low-ranked state.
3. Invalid, retired, or superseded references are not served as current orientation.
4. Health metrics measure actual coverage, invalid links, and omissions.
5. Source-semantic observations are preserved; scores and classifications are derived.
6. Resource budgets are explicit and independently testable.
7. Increasing a budget does not remove prior representation or reduce prior detail.
8. Compression and omission are visible, with a retrieval path for the full projection.
9. Multi-user projections filter by principal/owner and visibility rather than treating visibility alone as orientation scope.

## Append-only source-semantic events

A stored touch count and last-touched timestamp cannot reconstruct whether activity was massed into one burst, spread over months, or revived after dormancy. Those histories can produce the same counters but imply different future relevance.

The durable substrate therefore preserves non-content event envelopes. Ranking, clustering, and prominence remain replaceable views over those events.

Do not fabricate historical events or missing timestamps. Imports retain their source meaning and stay distinguishable from native live observations.

### Stable identity and observed revision

An event has two distinct keys:

1. **Stable identity** identifies the source-native event or transition.
2. **Revision key** identifies one observed revision of that stable identity.

The reference contract uses SHA-256 over canonical length-delimited parts. Ambiguous string concatenation is not permitted.

For a source with a native identifier, stable identity is derived from:

`contract_version, source_system, source_namespace, source_event_type, source_native_event_id`

A revision key is derived from:

`identity_key, source_revision`

When no source revision exists, an adapter must use a declared evidence/envelope digest scheme. It must not silently merge unrelated records across exports.

Replaying the same revision returns the existing event. A changed observation appends a successor with the same stable identity, the next revision ordinal, and `supersedes_event_id`. It never overwrites the prior envelope.

### Native memory events

The portable reference distinguishes:

- `memory_created` — an eligible memory was inserted active;
- `memory_activated` — an eligible memory transitioned from proposed to active.

Promotion is not another creation event. A trigger on the actual status transition captures activation even when more than one sanctioned workflow can perform the update.

Imports and ingest rows do not become native attention events. No synthetic production seed is required; the first organic native write is the preferred production proof.

## Assignments are separate linked records

Project, workstream, and topic classifications are mutable interpretations. They belong in append-only assignment rows linked to the event, not as mutable truth flags on the event itself.

A changed classification appends a successor assignment. Reclassifying an event does not rewrite the source event.

Likewise, utilization, dismissal, presentation, citation, and confirmation should be later linked events rather than booleans such as `was_utilized` added to the original row.

## Grains

The design distinguishes three grains:

- **Project or workstream:** durable resumption identity.
- **Topic or question:** mutable orientation projection that may split, merge, or be renamed.
- **Artifact, claim, decision, or action:** evidence and execution grain.

A ranker can orient an agent. It cannot replace preserved resumable state such as pause rationale, decision lineage, verified artifacts, blockers, next actions, acceptance gates, failed paths, and custody evidence.

## Presentation under finite context

A finite context budget is a resource constraint, not a fixed topic-count rule.

The reference projection contract is denominated in **serialized PostgreSQL characters**:

`char_length(payload::text) <= effective_char_budget`

The reported rendered count must equal the actual serialized character length. This does **not** guarantee a UTF-8 byte ceiling or a model-token ceiling. Consumers that require token limits must apply their own tokenizer or safety margin.

A compliant projection should:

- retain deterministic ranked order;
- emit complete semantic objects rather than partial JSON fragments;
- admit the longest stable prefix that fits the declared character budget;
- shorten summaries only at word boundaries;
- preserve every lower-budget object and its detail when the budget increases;
- report total, represented, and omitted counts;
- expose a retrieval handle for the complete ranked source.

The budget unit and compression policy must be visible and configurable. Low-ranked evidence remains stored even when omitted from one boot payload.

## Multi-user orientation

Owner and visibility answer different questions:

- **Owner/principal:** whose orientation the item belongs to.
- **Visibility:** who may see it.

A shared row may be visible to multiple principals while still requiring explicit ordering or projection semantics. Multi-user deployments must test each viewer independently and prove that foreign private rows do not appear.

A shared runtime credential may be an acceptable audited guardrail for a small trusted household. It is not proof of human authority and should not be copied into a product or broader multi-user service without distinct principals and credentials.

## Candidate scoring models

Existing scoring models may be useful benchmarks, not doctrine. Frequency, recency, power-law, spacing-sensitive, graph, semantic, personalized, and hybrid models should remain replaceable.

A production law should be selected only after comparison against observed behavior at the intended grain and timescale. Derived weights must not be written back as canonical event facts.

## Retirement and supersession

Silence is not retirement.

A dormant topic or project must not be retired merely because it has not been accessed recently. Retirement is a deliberate lifecycle action with authority and evidence.

Likewise, `superseded` should not be overloaded to mean replaced, deliberately retired, and merely deferred. Deployments should distinguish those states well enough that ranking cleanup does not destroy valid history.

## Minimum conformance checks

A deployment should prove that:

1. an active native insert produces exactly one `memory_created` event;
2. a proposed insert produces no native event;
3. proposed-to-active produces exactly one `memory_activated` event;
4. replay of the same source revision does not duplicate;
5. a changed observation appends a linked revision under the same stable identity;
6. event and assignment update, delete, and truncate are denied;
7. imports and ingest rows do not fabricate native events;
8. assignments remain linked and append-preserving across revisions;
9. owner, visibility, and principal fields survive capture in multi-user stores;
10. the serialized-character budget is exact, including escaped and multibyte content;
11. larger budgets produce monotonic representation;
12. rollback-only tests leave no fixtures.

## Standing constraints

- Never fabricate historical attention events or missing access timestamps.
- Never lock a production ranking law without observed data for the intended behavior and timescale.
- Never bulk-promote or retire memories, topics, or projects from inferred signal alone.
- Never bake derived ranking policy into immutable evidence.
- Never convert vendor-exported messages into generic access or utilization events.
- Never let ranking substitute for canonical project state, authority, or custody.