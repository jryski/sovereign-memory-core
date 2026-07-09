# North star: trustworthy memory transfer

> Anyone can move an AI's memory of them from any system to any other, prove nothing
> was lost, invented, or silently rewritten in transit, and know the exact moment the
> new home became the truth.

The short form is **trustworthy memory transfer**.

Sovereign Memory Core exists to make custody, provenance, review, and cutover durable
across applications and model providers. The project owns the durable data layer and its
rules. Applications, adapters, models, and miners remain replaceable clients.

## Doctrine

1. **Own the durable data layer, not the application layer.** Memory remains portable
   when storage, evidence, review state, and history are independent of any client.
2. **Evidence before belief.** Preserve raw source material and its provenance before
   deriving candidates from it.
3. **Review before promotion.** Producers propose; an approved workflow decides what
   becomes durable truth.
4. **Preserve conflict instead of manufacturing agreement.** Contradictory claims stay
   visible until a reviewer resolves or explicitly waives them.
5. **Migrate without amnesia.** Counts, evidence, holds, exclusions, and rollback paths
   are part of a migration, not optional cleanup.
6. **Operate local-first and cloud-optional.** A technical user must be able to run and
   exit the system without depending on one hosted provider.
7. **Keep adapters replaceable.** Source-specific parsing belongs at the edge; the core
   custody model remains source-neutral.
8. **Treat models and miners as untrusted producers.** Their output is a candidate with
   evidence, never self-authenticating truth.
9. **Make validation mandatory.** A gate must fail when an invariant fails. A successful
   process exit alone is not proof.

## Product tracks

The project has five related tracks with different responsibilities:

| Track | Responsibility | Trust posture |
|---|---|---|
| Core custody layer | Durable records, provenance, supersession, audit, source staging, readiness, and cutover state. | Database constraints and validation define the boundary. |
| Source import and adapters | Preserve exports and translate source records into reviewable packages and candidates. | Replaceable producers; source-specific logic does not define core truth. |
| Review and promotion | Inspect evidence, preserve holds and conflicts, approve candidates, and declare readiness. | Explicit decisions are required before promotion. |
| Installer and operator experience | Install, diagnose, validate, back up, restore, and prove provider exit. | Friendly workflows must expose rather than bypass safety gates. |
| Research producers | Explore conversation mapping, extraction, entity resolution, and temporal reasoning. | Research-grade until representative evaluations prove quality. |

The near-term alpha is the custody and operator path: a technical user can install the
core locally, validate it, dry-run a synthetic import, review candidates, and prove
backup or export. It is not a claim that conversational memory mining is solved.

## What evidence proves

Payload and quote hashes prove that checked bytes are attached to a candidate and have
not changed since the hash was calculated. Locators make the supporting span
inspectable. Counts and checksums make omission or package drift detectable.

Those mechanisms do **not** prove that:

- a statement is true;
- a statement reflects the user's belief rather than an assistant suggestion;
- a statement is still current;
- two names refer to the same project or entity;
- a source omitted no relevant context;
- a candidate belongs in durable memory.

Evidence supports review. It does not replace judgment.

## Chat-Mine posture

Chat-Mine is an emitter and research track, not the north star.

The current Chat-Mine slice proves:

- deterministic package generation from a synthetic fixture;
- one source item producing multiple manifest candidates;
- candidate-level locators, quotes, and hashes;
- rejection of corrupted package states with clear diagnostics;
- rollback-only loading into the source-import schema;
- rejection of corrupted loaded state;
- preservation of holds and conflicts without silent resolution.

It does not prove high-quality mining of real, long-running AI conversations. In
particular, a naive `chunk -> model -> memory candidate` pipeline is expected to confuse
or lose important context around:

- project aliases and entity identity;
- topic changes within a conversation;
- one-off questions versus durable facts;
- assistant suggestions versus user-confirmed facts;
- temporal currentness and stale claims;
- supersession and conflicts across conversations;
- differences between local open-source and frontier model capability;
- token, GPU, cost, and privacy constraints.

Chat-Mine should remain described as research-grade until representative known-answer
evaluations establish otherwise.

## Research gates for conversational adapters

Before treating real chat, social, notes, or other conversational adapters as reliable
emitters, the project should define and test:

1. Deterministic preservation of source metadata and explicit project tags.
2. Whole-conversation maps before candidate extraction.
3. Topic segmentation and topic-shift detection.
4. Separation of durable facts from one-off questions and transient instructions.
5. Project and entity alias resolution across conversations.
6. Temporal posture, supersession, and currentness risk.
7. Conflict detection without automatic truth selection.
8. Known-answer evaluation fixtures with omission and invention checks.
9. Frontier-model versus local/open-source model quality, cost, and privacy tradeoffs.
10. Prior-art research before introducing novel mining architecture.

Passing these gates would support a scoped quality claim for a tested adapter and
fixture set. It would not convert a producer into a trusted source of truth.

## Cutover definition

A new memory home becomes authoritative only when its documented scorecard passes and
an approved operator performs the cutover. Package generation, successful loading, or a
model's confidence cannot declare authority.

Until that moment:

- the prior source remains readable;
- unresolved candidates remain reviewable;
- holds and conflicts remain visible;
- rollback remains possible;
- the new store is staged, not authoritative.

This exact boundary is what turns data movement into trustworthy memory transfer.
