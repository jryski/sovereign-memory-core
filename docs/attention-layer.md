# Attention Layer

## Status

**Correctness contract defined; production ranking model intentionally open.**

This document describes a portable attention-layer design. It does not prescribe a final decay law, fixed topic count, or vendor-specific implementation.

## Purpose

The attention layer helps an agent orient at the start of a session by estimating which workstreams, questions, and artifacts are likely to matter now.

It is **orientation, not authority**.

Attention may be inferred, recomputed, reordered, and replaced. Canonical facts, consequential decisions, permissions, and provenance remain governed by their own custody and authority rules.

This separation permits aggressive automatic attention inference without allowing salience to become truth.

## Correctness requirements

A compliant attention implementation should satisfy these properties before scoring quality is considered:

1. **Every valid candidate can participate in ranking.** A first observation must not be trapped in an invisible staging state.
2. **Presentation limits do not delete evidence.** A UI or boot budget may compress output, but storage must not discard low-ranked topics merely because they are not displayed.
3. **Invalid or inactive references are not served.** Ranked projections must join the canonical record and enforce its current eligibility state.
4. **Health metrics express actual failure modes.** Metrics should measure candidate coverage, invalid links, and output coverage rather than merely whether a helper function was called.
5. **Ranking state is derived when possible.** Irreversible counters or destructive tier transitions should not replace source events that future models may need.
6. **Resource budgets are explicit.** A caller may declare a finite character or token budget, but should not silently impose a fixed worldview such as “only the top N topics exist.”
7. **Compression is visible.** Boot output should report total candidates, represented candidates, omitted candidates, compression state, and a retrieval handle for the full ranked projection.

## Why append-only events matter

A stored touch count and last-touched timestamp cannot reconstruct whether repeated activity was:

- massed into one burst;
- distributed across several sessions;
- separated by months;
- revived after a long dormancy.

Those histories can produce the same counter values but imply different future relevance.

The durable substrate should therefore preserve source-semantic events. Ranking, clustering, and prominence should be derived views over those events.

Do not fabricate historical events or missing timestamps. Imported history should retain the source event's native meaning and remain distinguishable from live native attention observations.

## Grains

The current converged design position distinguishes three grains:

- **Project or workstream:** durable resumption identity.
- **Topic or question:** mutable orientation projection that may split, merge, or be renamed.
- **Artifact, claim, decision, or action:** evidence and execution grain.

A topic identifier may be recorded as an `as_of` classification for audit, but should not be treated as an immutable canonical partition. Reclassification must not rewrite the underlying event.

A ranker can orient an agent. It cannot replace preserved resumable state such as:

- pause rationale and resume conditions;
- decision and correction lineage;
- last verified artifacts and configuration;
- open blockers and next actions;
- acceptance gates;
- known failed paths;
- custody and restore evidence.

## Candidate scoring models

Existing models may be useful benchmarks, not doctrine.

For example, power-law activation models demonstrate why spacing history matters, but no evidence reviewed for this design establishes a production decay law for irregular multi-year project work.

A production model should be selected only after comparison against observed behavior at the intended grain and timescale.

The event substrate should permit side-by-side evaluation of:

- frequency and recency models;
- power-law candidates;
- spacing-sensitive models;
- graph-based propagation;
- semantic relevance models;
- personalized learned ranking;
- hybrid or future models.

The scoring implementation should be replaceable without rewriting event history.

## Write-path requirement

Attention capture should add near-zero ceremony to normal work.

A user or agent should not be required to mint a precise topic key, look up a prior slug, and invoke a separate attention function for every interaction.

Normal work may emit low-assurance attention evidence automatically. Background processors may propose classifications and links, provided that:

- the source event is preserved;
- inference is clearly marked as derived;
- factual authority is not granted by attention inference;
- correction and reclassification remain possible;
- processors are replaceable;
- the durable event data remains portable.

## Event-model constraints

A portable event contract should preserve enough information to support future interpretations, including:

- immutable event identity;
- source system and source-native event type;
- source-native object identifiers;
- occurrence and recording times;
- actor, principal, credential, and runtime when known;
- session or interaction grouping when known;
- source evidence locator and integrity metadata;
- assurance and custody state;
- optional non-authoritative classification-as-of links;
- later linked events for presentation, utilization, dismissal, citation, correction, or confirmation.

Do not mutate an event row later to set `was_utilized=true`. Utilization is a later event linked to the original presentation or retrieval event.

Do not store derived policy or scoring weights as canonical facts in the immutable event. Preserve observed source features and explicit human priority as evidence; compute replaceable scores separately.

## Retirement and supersession

Silence is not retirement.

A dormant topic or project must not be retired merely because it has not been accessed recently. Retirement is a deliberate lifecycle action with authority and evidence.

Likewise, `superseded` should not be overloaded to mean all of:

- replaced by a newer record;
- deliberately retired;
- deferred or awaiting re-proposal.

Deployments should model those states distinctly enough that ranking and resumption do not destroy valid history.

## Presentation under finite context

A finite context budget is a resource constraint, not a fixed topic-count rule.

A useful boot projection may:

- allocate more summary detail to more prominent work;
- represent less prominent work compactly when the label still carries orientation value;
- aggregate the unrepresented tail when individual labels would become noise;
- report coverage and compression explicitly;
- expose a retrieval path for the complete ranked projection.

The budget and compression policy should be visible and configurable. Low-ranked evidence remains stored even when it is not represented in one boot payload.

## Standing constraints

- Never fabricate historical attention events or missing access timestamps.
- Never lock a production ranking law without observed data for the intended behavior and timescale.
- Never bulk-promote or retire memories, topics, or projects from inferred signal alone.
- Never bake derived ranking policy into immutable evidence.
- Never convert vendor-exported messages into generic access or utilization events.
- Never let ranking substitute for canonical project state, authority, or custody.
