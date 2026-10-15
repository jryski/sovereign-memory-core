# Classification notes: Markdown wiki

Synthetic example only. This Markdown file wiki is one source shape. It is not
the default import path.

Contract: [`docs/07-source-import-cutover.md`](../../../docs/07-source-import-cutover.md)
and [`docs/09-source-adapters.md`](../../../docs/09-source-adapters.md).

## Source

- Source system: `example-markdown-wiki`
- Source type: `file-wiki`
- Raw input: [`sample-input/`](sample-input/operations/demo-rollback.md)
- Manifest draft: [`expected-manifest.json`](expected-manifest.json)
- Container: `markdown-wiki`
- Actors: `person-1`, `agent-1`, `device-demo-1`

The file path is the source item key. These pages have no native timestamps, so
each item uses the export watermark `2026-07-08T16:00:00Z` and records
`timestamp_source=export_watermark`. That timestamp is the export time, not a
claim about when the prose was authored. Stale status comes from the page text.

| Path | Page |
|---|---|
| `sample-input/operations/demo-rollback.md` | Current rollback checklist page. |
| `sample-input/operations/demo-port-history.md` | Superseded port history. |
| `sample-input/scratch/session-notebook.md` | Scratch notebook. |
| `sample-input/restricted/demo-subject-pointer.md` | Restricted subject pointer. |

## Suggested classifications

| Source item | Manifest key | Suggested action | Suggested zone | Review state | Why |
|---|---|---|---|---|---|
| `operations/demo-rollback.md` | `wiki-demo-rollback` | import | HOUSE | unreviewed | Durable operating page. Suggestion for `wiki_pages`. |
| `operations/demo-port-history.md` | `wiki-port-8080-stale` | hold | HOLD | needs_review | Stale-state quarantine. The page says it is superseded. |
| `scratch/session-notebook.md` | `wiki-session-notebook` | evidence | EVIDENCE | unreviewed | Model-authored scratch. Process evidence. |
| `restricted/demo-subject-pointer.md` | `wiki-restricted-pointer` | import | VAULT | needs_review | Restricted pointer for `vault-subject-demo-1`. |

## Stale-state quarantine

`operations/demo-port-history.md` is marked superseded and states that the
listener is port 8080. The draft holds it with `quarantine_reason=stale_state`.
This export has no replacement page, so the draft leaves the successor
unresolved instead of inventing one.

Probe `example-wiki-stale-port` expects that page to stay non-authoritative.
Probe `example-wiki-vault-boundary` expects
`restricted/demo-subject-pointer.md` to stay out of HOUSE.

## Payload hash and count verification

Algorithm: `sha256` of each raw Markdown file, trailing newline included.

Verification counts: source_item_count=4, exported_item_count=4, candidate_count=4, import_count=2, hold_count=1, evidence_count=1, exclude_count=0, rejected_count=0, held_excluded_or_rejected_count=1.

Per-file checksums and per-item payload hashes live in
[`expected-manifest.json`](expected-manifest.json). Recompute with:

```bash
python3 scripts/validate_source_adapter_examples.py
```

## What this draft does not do

The batch status stays `open`. The draft does not approve records, does not
call `source_mark_batch_ready`, and does not claim a file wiki is the default
import path. It is not production-ready import tooling.
