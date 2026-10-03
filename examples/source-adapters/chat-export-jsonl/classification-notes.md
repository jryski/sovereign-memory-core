# Classification notes: JSONL conversation export

Synthetic example only. This JSONL conversation export is one source shape. It
is not the default import path.

Contract: [`docs/07-source-import-cutover.md`](../../../docs/07-source-import-cutover.md)
and [`docs/09-source-adapters.md`](../../../docs/09-source-adapters.md).

## Source

- Source system: `example-chat-export-jsonl`
- Source type: `ai-export`
- Raw input: [`sample-input.jsonl`](sample-input.jsonl)
- Manifest draft: [`expected-manifest.json`](expected-manifest.json)
- Container: `conv-demo-1`
- Actors: `person-1`, `agent-1`, `device-demo-1`

Each JSONL line is one source item. The line is hashed before normalization.
The trailing newline is not part of the item payload. The whole file has its
own checksum under `verification.raw_input_files`.

## Suggested classifications

| Source item | Manifest key | Suggested action | Suggested zone | Review state | Why |
|---|---|---|---|---|---|
| `chat-record-1` | `chat-rollback-checklist` | import | HOUSE | unreviewed | User-stated durable fact about the rollback checklist. Suggestion for `memories`. |
| `chat-record-2` | `chat-rollback-model-summary` | evidence | EVIDENCE | unreviewed | Assistant summary. Process evidence, not a human decision. |
| `chat-record-3` | `chat-port-8080-stale` | hold | HOLD | needs_review | Stale-state quarantine for the January port 8080 claim. |
| `chat-record-4` | `chat-port-9090-correction` | import | HOUSE | unreviewed | Later correction to port 9090 on `device-demo-1`. Still unreviewed. |
| `chat-record-5` | `chat-restricted-pointer` | import | VAULT | needs_review | Restricted pointer for `vault-subject-demo-1`. |

## Stale-state quarantine

`chat-record-3` says the Example Project listener is port 8080 and calls that
note outdated. The draft holds it. `metadata.quarantine_reason` is
`stale_state`, and `superseded_by_source_item_key` points at `chat-record-4`.

`chat-record-4` is only a proposed HOUSE import. A later timestamp does not
approve it. The stale probe `example-chat-stale-port` asks whether port 8080
is current and expects the January line to stay non-authoritative.

The boundary probe `example-chat-vault-boundary` expects the restricted pointer
to stay out of HOUSE.

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
call `source_mark_batch_ready`, and does not claim this conversation export is
the default import path. It is not production-ready import tooling.
