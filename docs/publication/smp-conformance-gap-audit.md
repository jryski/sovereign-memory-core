# SMP Draft 0.3 Conformance Gap Audit

## Status

Draft audit for internal review.

This document maps the normative requirements in [`smp-custody-layer.md`](smp-custody-layer.md) to the current implementation and test posture of this repository.

It is intentionally conservative. A requirement is marked **covered** only when the current repository appears to include a direct structural check, validation script, fixture, or negative test for that requirement. Requirements that are architecturally intended but not yet backed by a direct probe are marked **gap** or **partial**.

## Coverage states

| State | Meaning |
|---|---|
| Covered | Existing SQL, fixtures, validation, or negative tests appear to directly exercise the requirement. |
| Partial | Existing work covers part of the requirement, but the requirement is broader than current tests. |
| Gap | Requirement is not currently proven by the repo. |
| Future profile | Requirement belongs to future adapter/profile/product work, not the current foundation. |
| Needs decision | Requirement needs scope, wording, or implementation decision before testing. |

## Current tested foundation

The merged foundation is known to include:

- source-import foundation;
- source systems, import batches, source items, payload evidence, and manifest review;
- candidate-level source locators and quote hashes;
- richer cutover probe categories;
- deterministic Chat-Mine package fixture;
- rollback-only loader proof;
- negative package mutation tests;
- negative SQL corruption tests;
- non-local database refusal;
- current tracked-file public-readiness scrub.

This foundation strongly covers custody rails. It does **not** yet cover the entire Draft 0.3 normative surface.

## Requirement matrix

| ID | Draft 0.3 requirement | Current posture | Notes / follow-up |
|---|---|---|---|
| T1 | Package MUST declare `smp_version`. | Gap | Add package schema field and validation if not already present. |
| T2 | Principal or authorized delegate MAY declare authority. | Partial | Current cutover concepts exist, but authorization/delegation model is not fully specified or tested. |
| T3 | Scope names the subset of memory a cutover covers. | Partial | Cutover machinery exists; explicit scope model and scope-by-scope migration should be checked. |
| I1.1 | Raw source payload preserved before normalization/trust. | Covered | Source payload evidence and hashes are core to `sql/04_source_import.sql` and validation. |
| I1.2 | Derived record references evidence by locator and hash. | Covered | Candidate locator and quote-hash work covers import/HOLD posture. |
| I1.3 | Claims without preserved source are not counted as migrated facts. | Partial | HOLD/evidence posture exists; explicit orphaned assertion handling should be tested. |
| I2.1 | Every source item receives disposition: import/hold/exclude/evidence. | Covered | Source manifest review and readiness checks cover disposition posture. |
| I2.2 | One source item MAY yield multiple candidate records. | Covered | Chat-Mine fixture validates one-source-item-to-many-candidate mapping. |
| I2.3 | Manifest frozen and hashed before load. | Partial | Manifest freezing exists in the doctrine/foundation; confirm direct hash-freeze checks. |
| I2.4 | Reconciliation reaches zero unexplained source items. | Covered | Readiness checks and loader smoke verify reconciliation for fixture paths. |
| I2.5 | Reconciliation report separately counts containers, items, candidates, imports, holds, excludes, evidence-only rows. | Partial | Existing scorecards count some categories; full listed report should be audited and extended. |
| I3.1 | Imported record carries provenance basis from a closed set. | Partial | Core/vault provenance basis exists, but Draft 0.3's expanded closed set may exceed implementation. |
| I3.2 | Human-authored, human-confirmed, and agent-authored content remain distinguishable. | Partial | Basis labels exist conceptually; human-confirmed vs human-authored may need explicit schema/test. |
| I3.3 | Agent-authored content MUST NOT be silently promoted to human authority. | Partial | Doctrine and review posture exist; add explicit negative test for agent-authored promotion. |
| I3.4 | Deployment declares consequential domains. | Gap | Current provenance guards appear domain-specific; no general domain declaration mechanism yet. |
| I3.5 | Unsourced or agent-authored consequential facts rejected at write time. | Partial | Existing provenance guards cover financial-style facts; general legal/medical/identity domain enforcement is not complete. |
| I4.1 | Store becomes candidate-authoritative only after required probe suite passes. | Partial | Probe suite and scorecards exist; candidate-authoritative state model should be verified. |
| I4.2 | Probe suite includes positive, negative, conflict, stale-state, evidence-request categories. | Covered | `sql/06_cutover_probe_categories.sql` introduced these categories and validation coverage. |
| I4.3 | Critical probes all pass before cutover. | Partial | Critical probe tracking exists; direct cutover-blocking behavior should be tested. |
| I4.4 | Normative claims are backed by passing probes. | Gap | This audit starts the mapping; not all claims are covered. |
| I5.1 | Corrections append; history is not silently rewritten. | Partial | Supersession doctrine and core audit patterns exist; source-import promoted-record mutation rules need direct tests. |
| I5.2 | Earlier contradictory record preserved and may be marked stale/superseded/conflicted/historical. | Partial | Conflict/stale probes exist; explicit record preservation under contradiction needs fixture coverage. |
| I5.3 | Cutover remains reversible until authority declaration recorded. | Gap | Needs explicit cutover-state model and rollback/reversibility test. |
| I5.4 | Authority declaration is recorded and evidenced. | Partial | Cutover concepts exist; declaration evidence fields should be audited. |
| L1 | Each lifecycle transition records a durable artifact. | Partial | Early lifecycle artifacts exist; REVIEWED/PARALLEL/AUTHORITATIVE artifacts not fully implemented. |
| L2 | Failure at any gate returns to prior safe state. | Partial | Rollback-only loader proof covers load path; all lifecycle gates need broader tests. |
| L3 | No lifecycle gate may be skipped. | Gap | Needs state-transition guard/probe. |
| R1 | Candidate MUST carry one review state. | Covered | Manifest dispositions cover import/hold/exclude/evidence. |
| R2 | HOLD candidates MUST NOT be promoted. | Partial | HOLD posture exists; add direct promotion-blocking negative test. |
| R3 | EXCLUDE candidates MUST NOT become memory. | Partial | Exclusion accounting exists; add direct negative promotion test. |
| R4 | EVIDENCE candidates MUST NOT normalize into memory fact. | Partial | Evidence posture exists; add direct negative promotion test. |
| R5 | Promotion requires explicit review decision by principal/delegate. | Gap | Review UI/workflow is future work; current loader is dry-run/rollback only. |
| R6 | No import path may auto-promote to authority. | Covered | Current loader proof does not mark batch ready/cutover/authoritative. Add regression test if not already explicit. |
| H1 | Evidence fields SHOULD include payload hash, package checksum, source key, locator, quote, quote hash, algorithm, manifest key, source system, batch, timestamps. | Partial | Many fields exist; full SHOULD list needs schema inventory. |
| H2 | Source-text candidates MUST carry source quote and quote hash. | Covered | Candidate quote hashes are validated; mutation tests cover hash mismatches. |
| H3 | Quote hash proves custody, not correctness. | Informative/doctrine | No test required beyond docs clarity. |
| E1 | Store treats emitter output as proposed input. | Partial | Source manifest/review posture exists; direct store-level guard is future review workflow. |
| E2 | Structurally valid package alone MUST NOT promote candidate. | Covered | Loader dry-run never marks authoritative; negative tests protect validation but not truth promotion. |
| C1 | Adapter profile maps source item identity, raw preservation, hashes, candidates, provenance, timestamps, conflicts, review states, unsupported fields, round-trip/export, probes. | Future profile | Create adapter profile template. |
| C2 | Adapter profile declares lossiness. | Future profile | Add required section to adapter profile template. |
| C3 | Non-round-tripped fields must be declared, not silently dropped. | Future profile | Needs round-trip fixture/profile tests. |
| CNF1 | System MUST NOT claim conformance merely by storing provenance/memory fields. | Documentation | Enforce by project docs/release policy; no runtime test needed. |
| CNF2 | Emitter-conformant means packages satisfy I1+I2 only. | Partial | Current Chat-Mine package validates much of I1/I2; `smp_version` and full reconciliation report remain gaps. |
| CNF3 | Store-conformant enforces I1, I3, I5 on ingest. | Partial | I1 mostly covered; I3/I5 general enforcement gaps remain. |
| CNF4 | Promoted-record in-place mutation structurally impossible or content-hash audited. | Gap | A prior review identified silent content-update risk in deployment-style wiki pages; repo needs source-import/store audit decision. |
| CNF5 | Cutover-conformant executes full lifecycle and records probe results, review decisions, cutover declaration. | Gap | Full lifecycle beyond dry-run/readiness not complete. |
| CT1 | Third-party verification can confirm all source items accounted for. | Covered | Fixture/readiness validation covers current source-import package paths. |
| CT2 | Third-party verification can confirm consequential imported facts trace to evidence. | Partial | Evidence tracing exists; consequential-domain enforcement is partial. |
| CT3 | Third-party verification can confirm conflicts/stale claims preserved. | Partial | Probe categories exist; fixture coverage should be expanded. |
| CT4 | Third-party verification can confirm agent-generated content not promoted as human authority. | Gap | Needs explicit attribution/provenance fixture and negative test. |
| CT5 | Verification possible offline without source/emitter cooperation. | Partial | Package/evidence/rollback fixtures move in this direction; full offline verifier not complete. |
| A1 | Agents may propose durable source-of-record changes but not promote without review. | Gap | Policy issue exists; repo docs and/or protected-path proposal posture needed. |
| A2 | In-place source-of-record changes by an agent are content-hash audited when proposed/authoritative split is unavailable. | Gap | Possible phase-2 trigger; not implemented. |

## Immediate follow-up issues recommended

1. **Create adapter profile template**
   - Add required lossiness declaration.
   - Define source-item identity, preservation, hashes, provenance mapping, timestamp mapping, conflict mapping, review-state mapping, unsupported-field preservation, round-trip/export behavior, and probe requirements.

2. **Audit Draft 0.3 SHOULD/MUST coverage automatically**
   - Add a script or checklist that extracts normative keywords and maps them to this audit.
   - Prevent future specs from adding silent untracked MUSTs.

3. **Generalize consequential-domain enforcement**
   - Move beyond domain-specific guards into a declared consequential-domain model.
   - Add negative tests for unsourced or agent-authored consequential facts.

4. **Define scope-bound authority model**
   - Store cutover scope explicitly.
   - Add tests for scope-by-scope authority.

5. **Add review/promotion guard tests**
   - HOLD/EXCLUDE/EVIDENCE must not promote.
   - Agent-authored content must not become human authority.
   - Structurally valid package must not cause authority.

6. **Add promoted-record mutation audit policy**
   - Decide whether promoted records are append-only, content-hash audited, or both.
   - Add negative tests for silent post-promotion edit.

7. **Define offline verifier fixture**
   - Given only package, manifest, evidence hashes, probe definitions/results, and cutover record, verify SMP-complete for a small scope.

## Practical alpha interpretation

Draft 0.3 is ahead of the current implementation, but in a useful way. It should be treated as the target custody specification, while this audit prevents overclaiming.

The current repo can credibly claim:

- source-import custody foundation;
- deterministic package rails;
- candidate locators and quote hashes;
- readiness/probe categories;
- rollback loader proof;
- negative package and SQL validation.

It should not yet claim:

- full SMP Draft 0.3 conformance;
- production-grade review workflow;
- generalized consequential-domain enforcement;
- complete adapter-profile support;
- offline third-party verifier;
- solved Chat-Mine mining quality.
