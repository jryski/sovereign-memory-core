# Classification notes: row memory store

Synthetic example only. This row-like memory store is one source shape. It is
not the default import path.

Contract: [`docs/07-source-import-cutover.md`](../../../docs/07-source-import-cutover.md)
and [`docs/09-source-adapters.md`](../../../docs/09-source-adapters.md).

## Source

- Source system: `example-row-memory-store`
- Source type: `memory-store`
- Raw input: [`sample-input.jsonl`](sample-input.jsonl)
- Manifest draft: [`expected-manifest.json`](expected-manifest.json)
- Container: `example-memory-rows`
- Actors: `person-1`, `agent-1`, `device-demo-1`

Each JSONL row is one source item. `row_id` stays the source item key. It does
not become a canonical target id. `source_status` values (`active`,
`superseded`, `restricted`, `audit`) are source vocabulary. They are not
approval, lifecycle, or zone.

## Suggested classifications

| Source item | Manifest key | Suggested action | Suggested zone | Review state | Why |
|---|---|---|---|---|---|
| `row-1` | `row-rollback-checklist` | import | HOUSE | unreviewed | Ordinary rollback fact. `source_status=active` is not approval. |
| `row-2` | `row-port-8080-stale` | hold | HOLD | needs_review | Stale-state quarantine. `source_status=superseded`. |
| `row-3` | `row-restricted-pointer` | import | VAULT | needs_review | Restricted pointer for `vault-subject-demo-1`. |
| `row-4` | `row-listener-audit` | evidence | EVIDENCE | unreviewed | Audit row. Process evidence, not the current listener fact. |
| `row-5` | `row-port-9090-correction` | import | HOUSE | unreviewed | Later port 9090 correction on `device-demo-1`. Still unreviewed. |

## Stale-state quarantine

`row-2` says the listener is port 8080, carries `source_status=superseded`, and
points at `row-5`. The draft holds it with `quarantine_reason=stale_state` and
`superseded_by_source_item_key=row-5`.

`row-5` stays an unreviewed HOUSE suggestion even though the source row says
`active`. Probe `example-row-stale-port` expects `row-2` to stay
non-authoritative. Probe `example-row-vault-boundary` expects `row-3` to stay
out of HOUSE.

## Payload hash and count verification

Algorithm: `sha256` of each raw JSONL line with the trailing newline excluded.

Verification counts: source_item_count=5, exported_item_count=5, candidate_count=5, import_count=3, hold_count=1, evidence_count=1, exclude_count=0, rejected_count=0, held_excluded_or_rejected_count=1.

Per-item `payload_hash`, `payload_size_bytes`, and the file checksum live in
[`expected-manifest.json`](expected-manifest.json). Recompute with:

```bash
python3 scripts/validate_source_adapter_examples.py
```

## What this draft does not do

The batch status stays `open`. The draft does not approve records, does not
call `source_mark_batch_ready`, and does not claim a row store is the default
import path. It is not production-ready import tooling.
