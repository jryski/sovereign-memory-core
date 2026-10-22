# Synthetic source-adapter examples

These fixtures show how different source shapes can feed the same source-import
contract. They are synthetic drafts for review. They are not a production
importer, they do not connect to a live database, and they do not mark any
batch ready for cutover.

No example in this directory is the default import path. A conversation export,
a project container, a file wiki, a row store, and a table export are peer
shapes. The Chat-Mine package under [`fixtures/chat_mine/`](../../fixtures/chat_mine/sample_chat_export.json)
is a separate research-grade producer alignment. It is also not the default
import path. See [`docs/10-chat-mine-source-import-exporter.md`](../../docs/10-chat-mine-source-import-exporter.md).

Contract references:

- [`docs/07-source-import-cutover.md`](../../docs/07-source-import-cutover.md)
- [`docs/09-source-adapters.md`](../../docs/09-source-adapters.md)
- [`docs/adr/0005-adapter-profiles-over-format-competition.md`](../../docs/adr/0005-adapter-profiles-over-format-competition.md)
- `sql/04_source_import.sql` action and zone pairs

## Examples

| Directory | Source shape | Raw input |
|---|---|---|
| [`chat-export-jsonl/`](chat-export-jsonl/) | AI conversation export, JSONL | `sample-input.jsonl` |
| [`project-container/`](project-container/) | AI project container: instructions, files, conversations | `sample-input/` |
| [`markdown-wiki/`](markdown-wiki/) | Markdown file wiki | `sample-input/` |
| [`row-memory-store/`](row-memory-store/) | Row-like memory store | `sample-input.jsonl` |
| [`sql-table-export/`](sql-table-export/) | CSV-style export of SQL table `demo_memory_rows` | `sample-input.csv` |

Each directory contains:

- raw sample input;
- `expected-manifest.json`, the manifest draft and payload hash/count expectations;
- `classification-notes.md`, the classification rationale.

The repeated Example Project scenario is intentional. The same synthetic facts
cross five shapes so the contract stays source-agnostic.

## Classifications

Every example includes all four zones:

| Zone | Role in these drafts |
|---|---|
| HOUSE | Ordinary operating fact or durable wiki page. `action=import`, `review_state=unreviewed`. |
| VAULT | Restricted subject pointer for `vault-subject-demo-1`. `action=import`, `review_state=needs_review`. |
| HOLD | Stale-state quarantine for an outdated current-state claim. `action=hold`, `review_state=needs_review`. |
| EVIDENCE | Model summary, scratch note, audit row, or export inventory. `action=evidence`. |

Those pairs match the `source_manifest` check in `sql/04_source_import.sql`.
Nothing in these drafts is `approved`. A later correction stays a suggestion.
Stale history stays in HOLD.

Actors are synthetic: `person-1`, `agent-1`, `device-demo-1`, and
`vault-subject-demo-1`. There are no live HOUSE or VAULT records here.

## Manifest field mapping

`docs/09-source-adapters.md` names the universal adapter fields. The drafts use
the core column names so a future loader can map them without treating any
example as a second schema.

| Universal field | Draft field |
|---|---|
| `source_system` | `source_system` |
| `source_container` | `source_items[].source_container` |
| `source_item_id_or_path` | `source_item_key` |
| `source_author_or_actor` | `source_author` |
| `payload_hash` | `payload_hash` |
| `raw_payload_location` | `raw_payload_location` |
| `suggested_action` | `action` |
| `suggested_target_zone` | `target_zone` |
| `notes` | `review_notes` |

`action` and `target_zone` are suggestions while `review_state` is `unreviewed`
or `needs_review`.

## Payload hash and count verification

Hash algorithm: `sha256`.

| Basis | What is hashed |
|---|---|
| `jsonl_line` | The raw JSONL line, trailing newline excluded. |
| `csv_row` | The raw CSV data line, trailing newline excluded. The header is not an item. |
| `file_bytes` | The entire file, trailing newline included. |

`verification.raw_input_files` is the SHA-256 and byte count of each complete
raw file. `verification` also records source, exported, import, hold, evidence,
exclude, and rejected counts. `batch.status` stays `open`.
`batch.metadata.ready_for_cutover` is false.

Recompute the drafts:

```bash
python3 scripts/validate_source_adapter_examples.py
```

The validator checks hashes, counts, zone coverage, stale-state quarantine,
the action/zone pairs, and that the drafts do not claim a default import path
or an approved review.
