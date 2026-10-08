# ADR-0008: Promoted-record mutation audit

## Status

Accepted as policy. Structural enforcement is deferred. This decision does not close CNF4, A2, or I5.1.

## Context

Draft 0.3 says a store must make in-place mutation of a promoted record either structurally impossible or content-hash audited, so a silent post-promotion edit cannot pass undetected. The same draft says corrections append and history is not silently rewritten, and that an agent must not promote its own source-of-record change without review. Where a store cannot represent proposed versus authoritative, an in-place agent edit must be content-hash audited.

This repository can already tell a candidate from a current row:

- `memories.status` and `wiki_pages.status` are `proposed`, `active`, or `superseded`.
- `promote_memory` moves a `proposed` memory to `active` and stamps promotion metadata.
- `work_lessons.authority_state` is `proposed`, `accepted`, or `rejected`.
- `supersede_memory` and `supersede_wiki` insert a successor and mark the previous row `superseded`.
- `audit_log` records memory and wiki status changes, memory `due_status` changes, and overridden hard deletes. It does not record content changes.
- `verify_doc_integrity` compares the active wiki page at a path with `doc_integrity`. Its states are `match`, `mismatch`, and `no-blessing`.

What this tree does not do: reject an in-place rewrite of a promoted memory's content, source, or provenance; store a content-hash receipt for a memory; or sign anything. `remember()` and the `knowledge_status` default still insert `active`, so the common write path does not stage a candidate. `bless_doc` overwrites the single wiki receipt in place.

Ordered migrations on `main` stop at slot 11. Slot 12 is an unmerged draft for a different contract. A downstream design that adds promotion guards, an authority hash, and a receipt table in a much later slot is not part of this tree and is not imported here.

## Decision

Promoted records are **both** append-only in their authority-bearing fields **and** content-hash audited. The scope is the decision. Full-table append-only is rejected.

### Candidates may be edited

A candidate is a row still under review:

- a memory or wiki page with `status = proposed`;
- a work lesson with `authority_state = proposed`.

Editing a candidate is review work. The policy does not freeze it.

### Promoted authority-bearing fields are not a scratch pad

A promoted record is the current authority:

- a memory or wiki page with `status = active`, including a row inserted already active and a row moved to active by `promote_memory`;
- a work lesson with `status = active` and `authority_state = accepted`.

These authority-bearing fields must not be silently rewritten in place:

- memories: `content`, `source_kind`, `source_agent`, `source_ref`, `supersedes`, and provenance keys inside `metadata` (`basis`, `source_citation`, `financial_unverified`);
- wiki pages: `content`, `path`, `source_kind`, `source_agent`, `source_ref`, and provenance keys inside `frontmatter`;
- accepted work lessons: `claim` and `kind`, together with the evidence locators already governed by the lesson evidence path.

A citation swap is the same class of tamper as a content rewrite. The record can stay plausible while its basis changes.

### Operational fields stay mutable

On a promoted memory, these fields are operational and may change without becoming a new authority record: `due_date`, `due_status`, `hot_touched`, `tags`, `workstream`, `owner`, `visibility`, `confidence`, and metadata that is not provenance (`promoted_at`, `promote_note`, `promoted_by`). Marking a deadline done does not rewrite what was promoted.

### Corrections use supersession

The sanctioned correction is the existing supersession path: `supersede_memory`, `supersede_wiki`, or the work-lesson supersession proposal. The previous row stays, with its previous authority-bearing bytes, and is marked superseded. A rule that forbids every change, including that path, would fossilize a wrong record. That is why full-table append-only is rejected. The allowed status change on a promoted row is the transition to `superseded`, which `audit_log` already records as a status change.

### Three integrity states

When a checker reports on a promoted record, absence of a receipt is its own state:

| State | Meaning |
|---|---|
| `match` | A receipt exists and the current authority hash equals it. |
| `mismatch` | A receipt exists and the authority-bearing bytes differ from it. |
| `unaudited` | No receipt exists. Nothing is claimed. |

`unaudited` is not `match` and not `mismatch`. Folding a missing receipt into `match` would call an unchecked corpus verified. Folding it into `mismatch` would report tamper where no receipt was ever taken.

For wiki paths, `verify_doc_integrity` already uses this shape under different absence wording: `no-blessing` means no receipt. `no-blessing` is not `match` and not `mismatch`. Memories have no receipt relation. Every memory is `unaudited`, including a memory whose content was rewritten after promotion. That classification detects the lack of evidence. It does not detect the rewrite.

### A hash is not a signature

A matching hash shows that the stored receipt and the current bytes agree. It does not authenticate Primary Users, an agent, or a delegate, and it does not prove the bytes are true. `bless_doc` updates `doc_integrity` in place, so a role that can bless can make a rewritten page `match` again. ADR-0002 still holds: hashes prove custody of bytes, not truth. Signing is not part of this decision.

### What is deferred

This change adds no migration and no enforcement trigger. Deferred, and not claimed:

- a trigger that rejects in-place updates of authority-bearing fields on promoted memories, wiki pages, and accepted work lessons;
- an append-only promotion receipt and a memory authority hash covering content, source, and provenance keys;
- a memory verifier that can return `mismatch` after a silent edit that got past a guard;
- signing, and any actor assurance stronger than a caller-supplied label;
- a wiki promotion receipt beyond the existing single-row blessing (`wiki_pages` has no `promote_wiki`);
- changing `remember()` or the `active` default so ordinary writes start as candidates;
- treating git history as the A2 control for spec pages or schema files.

Slot 12 stays reserved for the unmerged topology draft. No later synthetic slot is added, because the missing piece would be a new promotion and receipt system rather than a check this schema can already express.

The disposable test in `tests/promoted_record_silent_edit.sh` loads a throwaway local database. It is not applied to any deployment.

## Consequences

- Reviewers and agents have a written difference between a candidate edit and a promoted-record edit.
- A silent content edit of a blessed active wiki page is reported as `mismatch`. A path with no blessing stays `no-blessing`.
- A silent content edit of a promoted memory is reported as `unaudited`, and the test fails if that absence is reported as `match` or `mismatch`.
- A candidate memory edit and a candidate wiki edit remain allowed. Supersession remains the correction path and keeps the previous bytes. An operational `due_status` update remains allowed.
- Provenance triggers are unchanged. The disposable check fails if an unsourced financial figure is accepted.
- CNF4 stays Gap. A2 stays Gap. I5.1 stays Partial. The wiki mismatch covers only blessed active page content, and memory rewrites are still stored.

## Related

- Issue #47
- [ADR-0002](0002-evidence-hashes-prove-custody-not-truth.md)
- [ADR-0004](0004-review-before-promotion.md)
- [ADR-0006](0006-protected-durable-writes-default-to-proposed.md)
- [docs/publication/smp-custody-layer.md](../publication/smp-custody-layer.md)
- [docs/publication/smp-conformance-gap-audit.md](../publication/smp-conformance-gap-audit.md)
