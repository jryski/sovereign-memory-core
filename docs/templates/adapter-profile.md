# Adapter profile

Template. Copy once per source family, fill every `FILL`, and keep every
required section. A deleted or emptied required section makes the copy invalid.

This is the declaration form for Draft 0.3 §11
([`smp-custody-layer.md`](../publication/smp-custody-layer.md)). It records how
one source family maps into the source-import contract in
[`docs/07-source-import-cutover.md`](../07-source-import-cutover.md) and
[`docs/09-source-adapters.md`](../09-source-adapters.md).

A filled copy is a profile declaration. It is not a completed adapter, not a
passed probe suite, not SMP conformance, and not a mining-quality result.
Chat-Mine stays research-grade until the gates in
[`docs/00-north-star.md`](../00-north-star.md) are actually tested. No row in
the source adapter matrix is completed by this template.

Do not put private exports, live identifiers, or real personal content in a
filled copy that is committed here.

---

## 0. Identification

- Profile id: `FILL`
- Profile version: `FILL`
- `smp_version` targeted: `FILL` (Draft 0.3 until a later draft is named)
- Source family label: `FILL` (a family name, not a claim that a vendor
  connector is finished)
- `source_type`: `FILL` — one of `ai-export`, `file-wiki`, `notes`,
  `spreadsheet`, `sql`, `memory-store`, `other`
- `adapter_name` / `adapter_version`: `FILL` / `FILL`
- Direction: `FILL` — `import`, `export`, or `both`
- Maturity described: `FILL` — Level 0 manual, Level 1 export parser,
  Level 2 manifest generator, Level 3 reconciliation helper, or Level 4
  cutover assistant, as defined in
  [`docs/09-source-adapters.md`](../09-source-adapters.md). The level describes
  what this profile claims to specify. It is not a production-readiness mark.
- Profile status: `draft`

## 1. Lossiness declaration (required)

This section is required. Do not delete it. Do not replace it with "lossless",
"none", or "n/a" unless the field table below is filled and agrees.

Draft 0.3 requires an adapter profile to state precisely which source fields
do not survive a round trip. A field that does not survive must be named here.
Dropping it without a row is invalid.

Preserving the raw payload does not make a normalization lossless. If a
candidate, timestamp, author, status, attachment, conflict, or review mark is
rewritten, flattened, or omitted from the mapped record, list that as loss
even when the original bytes remain in evidence.

Answer every row. Use `not applicable` only with a reason. A blank cell
invalidates the profile.

| Source field or construct | Survives import into the package? | Survives export / round trip? | If not mapped, where is it preserved? | Loss notes |
|---|---|---|---|---|
| Source identity (system, container, item key) | FILL | FILL | FILL | FILL |
| Timestamps and timezone | FILL | FILL | FILL | FILL |
| Author, actor, or role | FILL | FILL | FILL | FILL |
| Status, deletion, supersession, or review mark | FILL | FILL | FILL | FILL |
| Attachments or related files | FILL | FILL | FILL | FILL |
| Conflict or stale-state markers | FILL | FILL | FILL | FILL |
| Fields with no core column | FILL | FILL | FILL | FILL |
| Anything else this family can emit | FILL | FILL | FILL | FILL |

Consequential loss must be called out in words, not only in the table:

- Identity loss: `FILL` or `none identified`
- Time loss: `FILL` or `none identified`
- Authorship loss: `FILL` or `none identified`
- Conflict or review-state loss: `FILL` or `none identified`

## 2. Source-item identity (required)

State how one source item is identified, and which of those identifiers stay
stable across a second export.

| Field | Rule for this family |
|---|---|
| `source_systems.source_key` | FILL |
| `source_container` (project, folder, table, export member) | FILL |
| `source_item_key` | FILL |
| `source_kind` (`conversation`, `page`, `row`, `note`, `event`, `message`, `file`, `other`) | FILL |
| Uniqueness scope | `(batch_id, source_item_key)` unless FILL says otherwise |

Rules the profile must answer:

- What is copied or hashed into `source_item_key`, and what changes if the
  export is regenerated: `FILL`
- Which apparent identifiers are not stable (titles, ordinal positions,
  display names) and must not be used as `source_item_key`: `FILL`
- Source row id stays the source row id: `FILL` — yes, and where it is stored
- A Sovereign Memory target id is new unless this profile is a verified
  same-system restore: `FILL` — confirm, or describe the restore exception
- How a container is distinguished from an item: `FILL`

## 3. Raw preservation requirements (required)

Invariant I1: an item is not normalized or trusted until its raw source payload
is preserved and content-hashed. Derived records point back by locator and
hash.

| Requirement | Declaration |
|---|---|
| Bytes that count as the raw payload | FILL |
| `raw_payload_location` | FILL |
| `evidence_kind` values used (`raw_payload`, `export_file`, `attachment`, `checksum`, `note`) | FILL |
| Attachments: inside the payload, separate evidence rows, or both | FILL |
| Bytes excluded from "raw", and why | FILL |
| When normalization is allowed | Only after the raw payload and its hash are stored. FILL any extra gate. |

Derived manifest candidates are not folded into the raw payload hash. A quote
hash covers the quoted span only. State any exception: `FILL` or `no exception`.

Any exclusion from the raw payload is also a lossiness row in §1.

## 4. Hash computation (required)

A hash proves custody of bytes, not truth, currentness, or endorsement. See
[ADR-0002](../adr/0002-evidence-hashes-prove-custody-not-truth.md).

| Hash | Algorithm | Bytes covered | Canonicalization | Stored beside the digest |
|---|---|---|---|---|
| `payload_hash` | FILL (default `sha256`) | FILL | FILL — encoding, key order, whitespace, newlines, Unicode | `payload_hash_algorithm` |
| `package_checksum` | FILL | FILL — which members, and that the checksum member itself is excluded | FILL | `hash_algorithm` on the package |
| `source_quote_hash` | FILL (default `sha256`) | The quote or span only, not the whole item | FILL | `source_quote_hash_algorithm` |

Mismatch behavior: `FILL` — the package is rejected or held; it is not repaired
by rewriting the source.

`source_quote_hash` and `payload_hash` stay separate. Say so if this family
does not emit quotes: `FILL`.

## 5. Candidate generation and import behavior (required)

An emitter may suggest candidates. It does not decide truth, resolve
conflicts, or mark a batch ready for cutover. A structurally valid package
does not promote anything.

| Behavior | Declaration |
|---|---|
| What generates candidates | FILL — deterministic parser, human, or untrusted model-assisted emitter |
| One source item to many candidates | FILL — `manifest_key` rule |
| Locator for each source-text candidate | FILL — `source_locator` shape (path, message id, range, byte offset) |
| Default `action` when uncertain | `hold` unless FILL justifies another default |
| Default `review_state` when uncertain | `unreviewed` or `needs_review` |
| Bulk transfer path | File or server-side transfer. Not model context, chat, or tool stdin. FILL the path used. |

`action` and `target_zone` must stay inside the core pairing:

| `action` | Allowed `target_zone` | Meaning |
|---|---|---|
| `import` | `HOUSE` or `VAULT` | Appears suitable for later promotion, still subject to review |
| `hold` | `HOLD` | Must not be promoted yet |
| `exclude` | `EVIDENCE` | Must not become memory; disposition is kept for accounting |
| `evidence` | `EVIDENCE` | Preserved as evidence; must not be normalized into a memory fact |

Suggested title, summary, content, and confidence are suggestions. State the
suggestion fields this family fills: `FILL`.

## 6. Provenance mapping (required)

Every imported record needs a provenance basis from the Draft 0.3 closed set,
and human-authored, human-confirmed, and agent-authored content stay
distinguishable. Agent-authored content is not mapped onto human authority.

| Source signal | Provenance basis | Authorship class |
|---|---|---|
| FILL | `human_direct` | human-authored |
| FILL | `decision_record` | FILL |
| FILL | `imported_artifact` | FILL |
| FILL | `source_document` | FILL |
| FILL | `agent_summary` | agent-authored |
| FILL | `agent_inference` | agent-authored |
| FILL | `system_observed` | FILL |
| Unknown or mixed | Do not guess `human_direct`. Use `hold`. | FILL |

Basis values are only: `human_direct`, `decision_record`, `imported_artifact`,
`source_document`, `agent_summary`, `agent_inference`, `system_observed`.

Consequential domains include financial, legal, medical, and identity claims.
A consequential fact that is agent-authored or lacks a required citation is
rejected at write time by the store, not waived in this profile. How this
family labels those claims so the store can reject them: `FILL`.

## 7. Timestamp mapping (required)

Source clocks are preserved. They are not rewritten to import time. One source
timestamp is not copied into every SMP time field unless this table says that
is the source's only clock.

| SMP field | Source clock used | Timezone | If the source clock is missing |
|---|---|---|---|
| `source_created_at` | FILL | FILL | FILL |
| `source_updated_at` | FILL | FILL | FILL |
| `observed_at` (when it happened) | FILL | FILL | FILL |
| `recorded_at` (when the store learned it) | FILL | FILL | FILL |
| `effective_from` / `effective_to` | FILL | FILL | FILL |
| `export_started_at` / `export_completed_at` / `frozen_at` | FILL | FILL | FILL |
| `reviewed_at` | Left unset by the emitter | — | Review sets it later |

Name any source clock that has no SMP field and point at its lossiness or
unsupported-field row: `FILL`.

## 8. Conflict representation (required)

Contradictory claims stay visible. The adapter does not pick a winner and does
not flatten them into one current fact.

| Question | Declaration |
|---|---|
| How conflicts are detected, or explicitly not detected | FILL |
| How each side is stored | Separate candidates or records. FILL the keying rule. |
| Marks this profile may apply | Only among `stale`, `superseded`, `conflicted`, `historical`. FILL which ones. |
| `record_status` values used | `proposed`, `current`, `superseded`, `retracted`, `entered_in_error`. FILL which ones. |
| Predecessor or supersession link | FILL |
| Earlier record preserved when a later source contradicts it | FILL — yes, and where |

If this family cannot detect conflicts, say so in §1 and do not claim a
conflict probe can pass for that family until detection exists.

## 9. Review-state mapping (required)

Two different fields are required. Do not collapse them.

- Disposition `action`: `import`, `hold`, `exclude`, `evidence` (Draft 0.3 §8).
- `review_state`: `unreviewed`, `needs_review`, `approved`, `waived`,
  `rejected`.

| Source status | `action` | `review_state` | `target_zone` | Notes |
|---|---|---|---|---|
| FILL | FILL | FILL | FILL | FILL |
| No source status | `hold` | `unreviewed` | `HOLD` | Default. Replace only with a reason. |

Promotion to authoritative memory requires an explicit review decision by the
principal or an authorized delegate. No import path promotes automatically.

The emitter leaves `reviewed_by`, `reviewed_at`, and
`source_payload_hash_at_review` unset. Confirm: `FILL`.

`hold` is not promoted. `exclude` does not become memory. `evidence` is not
normalized into a memory fact.

## 10. Unsupported-field preservation (required)

A field the core schema does not model is still source material. It is
preserved, or it is listed as loss in §1. It is not dropped on the way into
the package.

| Unsupported field or family | Preservation location | Re-emitted on export? |
|---|---|---|
| FILL | `source_items.metadata`, `source_payload_evidence`, raw payload, or FILL | FILL |
| Unknown fields not named at profile-write time | FILL — declared bucket, or listed as loss | FILL |

## 11. Round-trip and export behavior (required)

The conversion layer has two directions:

```text
external format -> SMP custody package
reviewed SMP store -> external export profile
```

| Direction | What this profile actually does |
|---|---|
| Import into an SMP custody package | FILL |
| Export from a reviewed SMP store | FILL — or `not offered` |

`not offered` is an explicit limitation. It still needs the table below.
Silence is not "not offered".

### Round-trip limitations (required)

These rows are required. They must agree with §1 and §10. A profile that says
export is supported and leaves this subsection blank is invalid.

| Limitation class | Fields | What a later reader cannot recover |
|---|---|---|
| Byte-for-byte round trip | FILL | FILL |
| Round trip with a declared transformation | FILL — name the transformation | FILL |
| Does not round-trip | FILL — must match §1 | FILL |
| Preserved in SMP, not re-emitted | FILL — must match §10 | FILL |
| SMP-only; the external format cannot represent it | FILL | FILL |
| Ordering or canonicalization the export will not restore | FILL | FILL |

State whether export emits preserved payloads, re-derives candidates, or both:
`FILL`. Re-derived candidates are new proposals. They are not proof that the
original candidates survived.

## 12. Required probes (required)

A profile names the probes that must pass before anyone relies on it. Naming
a probe is not a pass. This template records no probe results.

Draft 0.3 I4 requires all five categories. Stored `probe_category` values are
`positive`, `negative`, `conflict`, `stale_state`, and `evidence_request`.

Each category needs at least one named probe, or the exact marker
`probe not yet defined — cutover claim forbidden`.

| Probe id | `probe_category` | Severity (`critical`, `normal`, `informational`) | Expected behavior | If it fails |
|---|---|---|---|---|
| FILL | `positive` | FILL | Required facts are present | FILL |
| FILL | `negative` | FILL | Excluded and invented content are absent | FILL |
| FILL | `conflict` | FILL | Contradictions are surfaced, not flattened | FILL |
| FILL | `stale_state` | FILL | Superseded claims are not returned as current | FILL |
| FILL | `evidence_request` | FILL | Insufficient evidence is reported as such | FILL |

Custody probes this profile also requires before a cutover claim:

| Check | Required? | Pass condition |
|---|---|---|
| Source-item reconciliation | yes | Zero unexplained source items. Counts separated for containers, items, candidates, imports, holds, excludes, and evidence-only rows. |
| Payload hash match | yes | Stored `payload_hash` matches the preserved bytes under the §4 rules. |
| Quote hash match | FILL | Source-text candidates carry `source_quote` and `source_quote_hash`, and the hash matches. |
| Non-promotion | yes | `hold`, `exclude`, and `evidence` do not become memory. |
| Authorship | yes | Agent-authored content is not stored as human authority. |
| Declared loss still finds its preservation location | yes | Every §1 field that is not mapped is still at the location §1 or §10 names. |

Critical probes must all pass before cutover. A profile with any
`probe not yet defined — cutover claim forbidden` row cannot support a cutover
claim.

Known-answer mining, topic-shift, alias, and currentness gates for
conversational emitters are research work. They are not checked off here, and
this template does not treat Chat-Mine mining quality as solved.

## 13. Accounting outputs

The profile's emitter produces or feeds the universal adapter outputs:

```text
source_system
source_batch
source_item_manifest
source_payload_evidence
classification_suggestions
cutover_probe_candidates
```

Minimum per source item: `source_system`, `source_container`,
`source_item_key`, `source_created_at`, `source_updated_at`, `source_author`,
`source_kind`, `content_type`, `payload_hash`, `raw_payload_location`,
suggested `action`, suggested `target_zone`, `review_state`, and notes.

State any minimum field this family cannot supply, and the §1 row that records
that gap: `FILL` or `all supplied`.

## 14. Non-claims (required)

Leave these checked on every copy, including a filled one:

- [x] This profile does not claim that any real adapter is complete.
- [x] This profile does not claim that Chat-Mine mining quality is solved.
- [x] This profile does not claim production readiness.
- [x] This profile does not claim SMP conformance.
- [x] The lossiness section is present and filled, or this copy is still a blank template.
- [x] Round-trip limitations are explicit, including `not offered` where export does not exist.
- [x] No live store was mutated to produce this profile.

## Related

- [Draft 0.3 §11](../publication/smp-custody-layer.md)
- [Conformance gap audit](../publication/smp-conformance-gap-audit.md) — C1, C2, and C3 stay future profile work until filled profiles and round-trip fixtures exist
- [Source adapter matrix](../09-source-adapters.md)
- [Source import and cutover](../07-source-import-cutover.md)
- [ADR-0005](../adr/0005-adapter-profiles-over-format-competition.md)
- [ADR-0002](../adr/0002-evidence-hashes-prove-custody-not-truth.md)
- [ADR-0004](../adr/0004-review-before-promotion.md)
