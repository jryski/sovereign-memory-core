# Sovereign Memory Protocol (SMP)

## A custody, verification, and cutover layer for AI memory

**Draft 0.3 — internal review. Not cleared for external publication.**

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** in this document are to be interpreted as described in RFC 2119. They are normative only within sections marked **NORMATIVE**. Sections marked **INFORMATIVE** describe intent, strategy, adoption, or examples and impose no conformance requirements.

This draft is a target specification for the SMP custody layer. Implementation coverage is tracked separately in [`docs/publication/smp-conformance-gap-audit.md`](smp-conformance-gap-audit.md). A normative statement in this document should not be treated as implemented unless the conformance audit links it to passing tests or fixtures.

---

## North star

SMP exists to enable **trustworthy memory transfer**.

A principal should be able to move an AI system's memory of them from one system to another and independently verify that nothing was lost, invented, or silently rewritten in transit.

> Formats move bytes. SMP proves memory transfer earned authority.

Long form: anyone should be able to move AI memory from any source to any destination, preserve the evidence behind that memory, account for every source item, review proposed facts before promotion, and know the exact moment a new store became authoritative — without having to trust a vendor, a person, or a model's word.

---

## 1. The problem (INFORMATIVE)

AI memory is fragmenting. Different assistants, agents, applications, vendors, and local tools each hold partial memories about a person, project, team, or workflow. Export and import alone do not make that memory portable in any trustworthy sense.

A raw export answers *what bytes left the source*. It cannot, by itself, prove:

- whether every source item was accounted for;
- whether any memory was lost in migration;
- whether a memory was invented during import;
- whether a source statement was silently rewritten;
- whether assistant speculation was promoted as human fact;
- whether an old fact is stale or superseded;
- whether conflicting memories were preserved or flattened;
- whether consequential claims have evidence;
- whether a destination is actually ready to become authoritative.

SMP is the custody layer between source exports and destination stores. It does not ask the world to agree on one memory record format; it assumes many will exist. Its job is to verify transfer, provenance, readiness, and cutover.

---

## 2. Scope of this document

This document specifies the **publishable core**: custody, verification, and cutover.

It is deliberately narrow. It is not a product specification, not a memory-record wire format, and not a claim that automatic memory mining is solved. Platform features such as multi-principal workspaces, hosted services, delegated authority, local synchronization, and collaboration UX are out of scope here and must be documented separately so the core is not overclaimed by association.

---

## 3. What SMP is and is not (INFORMATIVE)

SMP **is** a custody and cutover layer. It defines how source material is preserved, how evidence is hashed and referenced, how every source item is accounted for, how candidates are staged for review, how provenance is enforced, how conflicts and stale claims are preserved, how verification probes define readiness, how a store becomes authoritative, and how failures roll back safely.

SMP **is not** a wire format, a memory-mining algorithm, a retrieval engine, an LLM evaluator, or an attempt to replace existing or future memory protocols. It wraps, ingests, verifies, and emits profiles for other formats.

SMP does not claim AI can perfectly extract memory from chat histories; does not assume a model's summary is true; does not treat an evidence hash as proof of correctness; does not auto-promote imported data to truth; does not require one global schema; does not erase older facts when newer ones appear; does not silently resolve conflicts; and does not declare a store authoritative by configuration alone.

---

## 4. Core doctrine (INFORMATIVE)

1. **Own the durable data layer, not the application layer.** Memory should not be trapped inside the first assistant that remembered it.
2. **Evidence before belief.** A candidate must point back to preserved source evidence before it can be trusted.
3. **Review before promotion.** Imported or model-generated candidates are proposals, not authoritative facts.
4. **Conflict preservation over false resolution.** Contradictory claims are staged and surfaced, never flattened into a convenient fiction.
5. **Migration without amnesia.** Moving memory preserves source evidence, history, and review state.
6. **Supersession without history rewrite.** Newer claims may supersede older ones; older claims remain preserved as historical evidence.
7. **Models are untrusted producers.** A model may propose candidates, classifications, and mappings. It cannot declare truth by itself.
8. **Validation is mandatory.** Conformance is defined by passing checks and probes, not by prose claims.
9. **Local-first, cloud-optional.** The custody layer supports private local operation and allows cloud deployment where appropriate.
10. **Adapters are replaceable.** Sources and formats change; the custody layer stays stable.

---

## 5. Terminology (NORMATIVE)

**Principal** — the human, team, or authority root whose memory is moved, reviewed, or governed. The principal is the root of truth; only the principal or a delegate the principal has authorized **MAY** declare authority.

**Source** — any system containing memory-relevant material, including assistant memory exports, chat exports, notes, agent stores, vendor formats, knowledge bases, application databases, and API-derived records.

**Store** — a destination system implementing SMP custody semantics. A store **MAY** be local, hosted, personal, team-based, or enterprise-operated.

**Package** — a structured import bundle containing source material, evidence references, manifest, candidates, hashes, and the metadata required for validation. A package **MUST** declare the `smp_version` it targets.

**Emitter** — software that produces a package from a source. An emitter **MAY** be deterministic, model-assisted, or model-driven. Its output is untrusted until verified and reviewed.

**Candidate** — a proposed memory, disposition, classification, or derived record. A candidate is not authoritative merely because it exists in a package.

**Manifest** — the disposition ledger for source items and candidates.

**Evidence** — preserved source material plus the hashes and locators that allow later verification.

**Probe** — a repeatable check whose pass/fail result is recorded, used to determine whether a package, store, import, or cutover satisfies custody requirements.

**Verifier** — an actor independent of the emitter that runs probes and evaluates results. Verification by a party that also produced the package does not, by itself, satisfy the custody test in [§13](#13-the-custody-test-normative).

**Scope** — the explicitly named subset of memory a cutover covers, such as one principal's shared personal memory or one workstream. Authority is always declared *for a scope*, never globally by default. Migrations **MAY** proceed scope by scope.

**Cutover** — the recorded transition where a store becomes authoritative for a scope.

---

## 6. The Five Invariants (NORMATIVE)

### I1 — Evidence

An item **MUST NOT** be normalized or trusted unless its raw source payload is preserved and content-hashed first. A derived record **MUST** reference its evidence by locator and hash. A claim that cannot be re-checked against preserved source material **MUST NOT** be counted as a migrated fact; it **MAY** be retained as a note or orphaned assertion, marked as such.

### I2 — Accounting

Every source item **MUST** receive at least one explicit disposition: `import`, `hold`, `exclude`, or `evidence`. A single source item **MAY** yield multiple candidate records. The manifest **MUST** be frozen and hashed before load, and reconciliation **MUST** reach zero unexplained source items. The reconciliation report **MUST** count, separately: source containers, source items, candidates, approved imports, held rows, excluded rows, and evidence-only rows.

### I3 — Provenance

Every imported record **MUST** carry a provenance basis drawn from a closed set — at minimum `human_direct`, `decision_record`, `imported_artifact`, `source_document`, `agent_summary`, `agent_inference`, and `system_observed` — and **MUST** preserve the distinction between human-authored, human-confirmed, and agent-authored content. Agent-authored content **MUST NOT** be silently promoted to human authority.

A deployment **MUST** declare its **consequential domains**. At minimum, consequential domains include financial, legal, medical, and identity claims. Deployments **MAY** declare additional consequential domains. A consequential fact whose basis is agent-authored, or which lacks a required citation, **MUST** be rejected at write time rather than flagged for later review. Enforcement is a property of the store, not of operator discipline.

### I4 — Verification

Authority is earned by passing probes, never declared by configuration or by a model's assessment. A store becomes *candidate-authoritative* for a scope only after the required probe suite passes. A probe suite **MUST** include all five categories:

- **positive** — required facts are present and recalled;
- **negative** — excluded content and invented content are absent;
- **conflict** — contradictory claims are surfaced, not flattened;
- **stale-state** — superseded claims are not returned as current truth;
- **evidence-request** — the store correctly answers "insufficient evidence" when it should.

Probes designated *critical* for a scope **MUST** all pass before cutover. Conformance to this specification is the passing of its probe suite; a normative claim unbacked by a passing probe is void.

### I5 — Supersession

Corrections **MUST** append; history **MUST NOT** be silently rewritten. When a later source contradicts an earlier one, the earlier record **MUST** be preserved and **MAY** be marked stale, superseded, conflicted, or historical. Cutover **MUST** remain reversible until the authority declaration is recorded, and that declaration **MUST** itself be a recorded, evidenced event.

---

## 7. Lifecycle (NORMATIVE)

```text
EXPORTED -> PRESERVED -> CLASSIFIED -> FROZEN -> LOADED
         -> PROBED -> REVIEWED -> PARALLEL -> AUTHORITATIVE
```

Each transition **MUST** record a durable artifact. A transition without its artifact **MUST NOT** be considered to have occurred. Failure at any gate **MUST** return the system to a prior safe state, and no gate **MAY** be skipped.

| Transition into | Required recorded artifact |
|---|---|
| PRESERVED | Raw payloads stored; per-payload content hashes |
| CLASSIFIED | Manifest dispositions for every source item |
| FROZEN | Manifest hash watermark that freezes the disposition ledger |
| LOADED | Load result and rollback proof |
| PROBED | Probe run identifier and per-probe pass/fail results |
| REVIEWED | Per-approved-candidate reviewer identity, review time, and payload-hash-at-review |
| PARALLEL | Source-vs-store comparison record while the source remains readable |
| AUTHORITATIVE | Authority declaration row naming the scope, probe run, and principal |

---

## 8. Candidate review states (NORMATIVE)

A candidate is distinct from authoritative memory and **MUST** carry one state:

- **import** — appears suitable for promotion, subject to validation and review;
- **hold** — **MUST NOT** be promoted yet;
- **exclude** — **MUST NOT** become memory, but the disposition is recorded for accounting;
- **evidence** — preserved as evidence and **MUST NOT** be normalized into a memory fact.

Promotion of a candidate to authoritative memory **MUST** require an explicit review decision by the principal or an authorized delegate. No import path **MAY** promote a candidate to authority automatically.

---

## 9. Evidence and hashing (NORMATIVE)

Evidence fields **SHOULD** include: source payload hash, package checksum, source item key, source locator, source quote, source quote hash, hash algorithm identifier, candidate manifest key, source system identifier, import batch identifier, and observed timestamps where available.

A candidate that asserts specific source text **MUST** carry a source quote and a hash of that quote so span drift across encodings is detectable. A source quote hash proves that a candidate refers to specific preserved text. It proves **custody, not correctness**.

---

## 10. Emitter trust model (NORMATIVE + INFORMATIVE)

**NORMATIVE:** Emitters are untrusted. A store **MUST** treat emitter output as proposed input to review and verification, and a structurally valid package **MUST NOT** by that fact alone cause any candidate to be promoted.

**INFORMATIVE:** Common emitter failures include over-broad summaries; stale facts presented as current; assistant suggestions presented as user facts; one-off questions treated as durable preferences; ignored topic shifts; missed project aliases; flattened conflicts; lost temporal context; and sensitive facts routed incorrectly.

### Chat-Mine as an emitter (INFORMATIVE)

Chat-Mine is a research-grade emitter that mines conversational sources for reviewable, evidence-backed candidates. Its deterministic package/export path is implemented and CI-verified; the mining quality problem is unsolved research. A naive `chunk -> model -> candidate` pipeline is expected to fail on complex histories, which need whole-conversation mapping, topic-shift detection, one-off filtering, alias resolution, temporal-currentness classification, suggestion-vs-confirmed-fact distinction, cross-conversation conflict detection, and known-answer evaluation fixtures.

Until those gates exist and pass, Chat-Mine candidates should default to review-first or HOLD posture. Chat-Mine is not the SMP north star; SMP remains valuable if Chat-Mine is weak or replaced.

---

## 11. Conversion and adapter profiles (NORMATIVE + INFORMATIVE)

SMP supports a conversion layer so ecosystems need not abandon their own formats. It operates in two directions:

```text
external format -> SMP custody package
reviewed SMP store -> external export profile
```

**INFORMATIVE:** The strategic position is to avoid competing with every format: verify them, wrap them, convert them, and prove their migrations. Format wars are decided by adoption, not merit; a custody layer that wraps many formats does not need to win one.

**NORMATIVE:** An adapter profile **MUST** specify: how source items are identified; how raw payloads are preserved; how source payload hashes are computed; how candidates are generated or imported; how provenance fields map; how timestamps map; how conflicts are represented; how review states map; how unsupported fields are preserved; how round-trip/export behaves; and which validation probes **MUST** pass.

An adapter profile **MUST** declare its **lossiness**: precisely which source fields do not survive a round trip. A profile that cannot round-trip a field **MUST** say so rather than silently drop it.

Candidate source families include vendor AI memory exports, assistant chat exports, open memory-interchange formats, MCP-based memory tools, notes and project-management exports, collaboration systems, local agent stores, and personal knowledge bases. None of these are canonical; all are sources.

---

## 12. Conformance (NORMATIVE)

Conformance is demonstrated by passing a defined probe suite, never by branding. A system **MUST NOT** claim conformance merely because it stores fields named "provenance" or "memory."

- **Emitter-conformant** — produces packages satisfying I1 and I2. This says nothing about whether its candidates are true or useful.
- **Store-conformant** — enforces I1, I3, and I5 on ingest, including write-time rejection of unsourced consequential facts. A store **MUST** make in-place mutation of a promoted record either structurally impossible or content-hash audited, so silent post-promotion edits cannot occur undetected.
- **Cutover-conformant** — executes the full [§7](#7-lifecycle-normative) lifecycle and records probe results, review decisions, and the cutover declaration.

---

## 13. The custody test (NORMATIVE)

A migration is **SMP-complete** for a scope when a third party — given only the package, the destination store, the manifest, the evidence hashes, the probe definitions, the probe results, and the cutover record — can independently confirm:

- every source item was accounted for, with zero unexplained items;
- every consequential imported fact traces to preserved evidence;
- conflicts and stale claims were preserved, not silently flattened;
- agent-generated content was not silently promoted as human authority;
- the store passed the required probes;
- the authority declaration is recorded for the named scope.

This verification **MUST** be possible offline, without cooperation from the source system or the emitter. If confirmation requires trusting a person's word, a vendor's promise, or a model's summary, the migration is not SMP-complete.

---

## 14. Agents operating the system (NORMATIVE)

The custody doctrine applies to the agents that operate an SMP project, not only to the memories they move. An agent **MAY** propose durable changes to a store's source-of-record, such as schema, operating documents, or spec pages, but **MUST NOT** promote them to authoritative state without an explicit review decision by the principal or an authorized delegate. Where a store cannot structurally represent proposed-vs-authoritative for such records, in-place changes by an agent **MUST** be content-hash audited.

> Agents may propose truth; approved workflows promote it.

This is not a separate policy. It is SMP applied to its own operators.

---

## 15. Multi-user and platform expansion (INFORMATIVE)

The custody core supports a larger platform, documented separately. At the custody layer, multi-user authority should be modeled as federation between per-principal authority scopes exchanging verified packages or signed messages, rather than as implicit shared tenancy. A hosted implementation may place multiple principals in one physical deployment, but authority, evidence access, review rights, and cutover must remain scoped per principal.

Future platform scope may include workspaces, roles, delegated authority, team memory, private zones, shared review queues, agent-to-agent state channels, model handoffs, proposal/approval workflows, audit logs, hosted deployment, local-first sync, and enterprise policy controls. None are required to define the publishable core.

---

## 16. Adoption path (INFORMATIVE)

1. **Reference implementation** — a working repo demonstrating the custody model on Postgres with validation scripts and fixtures.
2. **Conformance fixtures** — synthetic fixtures for evidence preservation, manifest accounting, conflicts, stale facts, HOLD posture, rollback loading, and negative validation.
3. **Adapter profiles** — first profiles chosen for practical value and low ambiguity.
4. **Local alpha** — installer, doctor command, validation runner, review workflow, and backup/export proof for technical early adopters.
5. **Public requirements draft** — a doctrine/requirements document that explains the custody layer without overclaiming the platform.
6. **External review** — developers, protocol people, privacy people, memory implementers.
7. **Standards exploration** — only after IP review and running-code maturity.

### Publication prerequisites

Before public positioning, the project should confirm: tracked files are scrubbed of private identifiers; historical commit caveats are documented or resolved; license posture is clear; IP and employment-agreement questions are reviewed; normative claims are tracked in a conformance audit; README and status docs align with this north star; conformance fixtures exist; no model-heavy feature is represented as solved before evaluation; Chat-Mine is framed as research; and adapter profiles are described as profiles, not universal truth.

---

## 17. What success looks like (INFORMATIVE)

SMP succeeds if users can move memory without losing provenance; stores reject unsourced consequential facts; migrations fail safely; conflicts are preserved for review; stale facts do not silently become current; other formats are ingested through adapter profiles; third parties can verify completeness; conformance is shown by probes; and the custody layer stays useful as memory formats change.

---

## Summary

SMP is chain of custody for AI memory. It need not be the only memory format, need not solve all memory extraction, and need not have every vendor adopt its internal schema. Its value is narrower and stronger:

> Preserve the evidence. Account for every item. Stage candidates. Review before promotion. Verify by probes. Declare cutover only when the new store has earned authority.
