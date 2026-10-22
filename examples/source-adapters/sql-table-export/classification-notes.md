# Classification notes: SQL table export

Synthetic example only. This CSV-style export of SQL table `demo_memory_rows`
is one source shape. It is not the default import path.

Contract: [`docs/07-source-import-cutover.md`](../../../docs/07-source-import-cutover.md)
and [`docs/09-source-adapters.md`](../../../docs/09-source-adapters.md).

## Source

- Source system: `example-sql-table-export`
- Source type: `sql`
- Raw input: [`sample-input.csv`](sample-input.csv)
- Manifest draft: [`expected-manifest.json`](expected-manifest.json)
- Container: `demo_memory_rows`
- Actors: `person-1`, `agent-1`, `device-demo-1`

The file is a CSV export of a synthetic table, not a live database dump. The
header names the columns and is not a source item. Each data row is one source
item. Column meaning has to be mapped before import:

| Column | Mapping in this draft |
|---|---|
| `row_id` | Source item key. It stays a source id. |
| `created_at`, `updated_at` | Source timestamps. |
| `author` | `source_author`. |
| `source_status` | Source vocabulary only: `active`, `superseded`, `restricted`, `audit`. |
| `sensitivity` | Signal for ordinary versus restricted handling. |
| `topic_key` | Suggested topic key. |
| `body` | Raw statement preserved in the row payload. |

A CSV export drops SQL types, constraints, and indexes. That loss is declared
on the adapter profile.

## Suggested classifications

| Source item | Manifest key | Suggested action | Suggested zone | Review state | Why |
|---|---|---|---|---|---|
| `sql-row-1` | `sql-rollback-checklist` | import | HOUSE | unreviewed | Ordinary rollback fact. `source_status=active` is not approval. |
| `sql-row-2` | `sql-port-8080-stale` | hold | HOLD | needs_review | Stale-state quarantine. `source_status=superseded`. |
| `sql-row-3` | `sql-port-9090-correction` | import | HOUSE | unreviewed | Later port 9090 correction on `device-demo-1`. Still unreviewed. |
| `sql-row-4` | `sql-restricted-pointer` | import | VAULT | needs_review | Restricted pointer for `vault-subject-demo-1`. |
| `sql-row-5` | `sql-listener-audit` | evidence | EVIDENCE | unreviewed | Audit row. Process evidence, not the current listener fact. |

## Stale-state quarantine

`sql-row-2` says the listener is port 8080 and carries
`source_status=superseded`. The draft holds it with
`quarantine_reason=stale_state` and `superseded_by_source_item_key=sql-row-3`.

`sql-row-3` stays an unreviewed HOUSE suggestion. Probe
`example-sql-stale-port` expects `sql-row-2` to stay non-authoritative. Probe
`example-sql-vault-boundary` expects `sql-row-4` to stay out of HOUSE.

## Payload hash and count verification

Algorithm: `sha256` of each raw CSV data line with the trailing newline
excluded. The file checksum covers the header and every row.

Verification counts: source_item_count=5, exported_item_count=5, candidate_count=5, import_count=3, hold_count=1, evidence_count=1, exclude_count=0, rejected_count=0, held_excluded_or_rejected_count=1.

Per-item `payload_hash`, `payload_size_bytes`, and the file checksum live in
[`expected-manifest.json`](expected-manifest.json). Recompute with:

```bash
python3 scripts/validate_source_adapter_examples.py
```

## What this draft does not do

The batch status stays `open`. The draft does not approve records, does not
call `source_mark_batch_ready`, and does not claim a SQL or CSV export is the
default import path. It is not production-ready import tooling.
