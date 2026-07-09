# Chat-Mine source-import exporter

This is an internal producer alignment for the source-import contract in
`sql/04_source_import.sql`, `sql/05_candidate_locators.sql`, and
`sql/06_cutover_probe_categories.sql`. It is not a public interchange protocol.

Chat-Mine produces reviewable candidates and source evidence. It does not decide truth,
deduplicate facts, resolve conflicts, run retrieval, or mark a batch ready for cutover.

## Package shape

`scripts/export_chat_mine_package.py` converts the small fixture at
`fixtures/chat_mine/sample_chat_export.json` into a deterministic JSON package. Object
keys, source items, candidates, and probes have stable ordering. JSON payloads use sorted
keys and compact separators before SHA-256 hashing.

The package has these top-level members:

| Member | Purpose |
|---|---|
| `package_format` | Internal Chat-Mine package shape identifier. |
| `hash_algorithm` | Hash algorithm used by this package, currently `sha256`. |
| `source_system` | Producer and source metadata. |
| `batch` | Stable batch key, export watermark, timestamps, and item counts. |
| `source_items` | Raw conversations, payload evidence, and manifest candidates. |
| `cutover_probes` | Optional starter definitions only; no evaluator or run result. |
| `package_checksum` | SHA-256 of canonical package JSON before this member is added. |

The checked-in expected package is executable fixture evidence, not a general-purpose
specification. Regenerate and validate it with:

```bash
python3 scripts/export_chat_mine_package.py \
  fixtures/chat_mine/sample_chat_export.json \
  fixtures/chat_mine/expected_source_import_package.json
bash scripts/validate_chat_mine_export.sh
```

## Core mapping

References between package sections use stable keys. A future loader resolves those keys
to database UUIDs while inserting into the merged core tables.

| Package path | Core destination |
|---|---|
| `source_system.*` | `source_systems`; adapter fields identify Chat-Mine without changing the generic core schema. |
| `batch.*` | `source_import_batches`; `package_checksum` maps to `package_checksum`, while counts and watermark retain export completeness evidence. |
| `source_items[]` fields other than nested arrays and `raw_payload` | `source_items`; `source_item_key` is the stable conversation identifier. |
| `source_items[].payload_evidence[]` | `source_payload_evidence`; each row preserves location, SHA-256, byte count, and evidence metadata. |
| `source_items[].manifest_candidates[]` | `source_manifest`; the enclosing `source_item_key` resolves `source_item_id`. |
| `cutover_probes[]` | `cutover_probes`; `expected_source_item_key`, when present, resolves `expected_source_item_id`. |

`raw_payload` is package-carried evidence used to verify `payload_hash` and
`payload_size_bytes`. A loader must preserve it at `raw_payload_location` or another
durable evidence location before treating the item as staged. It contains only the
source conversation; derived manifest candidates are not folded into the raw evidence
hash.

## Candidate posture

The fixture deliberately emits two candidates from one conversation. Each candidate has
its own:

- `manifest_key`;
- structured `source_locator` with message id, message index, and character range;
- `source_quote`;
- `source_quote_hash`;
- `source_quote_hash_algorithm`.

The Friday deployment statement remains an unreviewed import suggestion. The older
Thursday statement remains a `HOLD` candidate with `needs_review`; the exporter does not
select a winner. Candidate quote hashes and the whole-conversation payload hash are
separate by design. The producer also leaves `source_payload_hash_at_review`,
`reviewed_by`, and `reviewed_at` unset because those fields belong to a later review.

## Validation

`scripts/validate_chat_mine_export.sh` exports twice, compares both outputs byte for byte,
compares output with the checked-in expected package, and independently verifies:

- package, payload, and quote hashes;
- batch counts and raw evidence linkage;
- unique source item and manifest keys;
- candidate locator/quote agreement;
- action and target-zone combinations accepted by `source_manifest`;
- one source item producing multiple candidates;
- active starter probes across all five merged probe categories.

The same command also generates seven temporary corrupted packages and proves the
validator rejects quote-hash, package-checksum, payload-hash, locator, candidate-hash,
manifest-key uniqueness, and probe-category failures with the expected diagnostic.

When `DATABASE_URL` is set, the validator also runs
`sql/validation/load_chat_mine_package.sql`. That rollback-only smoke path loads the
package into `source_systems`, `source_import_batches`, `source_items`,
`source_payload_evidence`, `source_manifest`, and `cutover_probes`, verifies the expected
row counts, payload hashes, manifest uniqueness, one-to-many candidate relationship,
locator/hash posture, five probe categories, and expected `source_readiness` states. It
then rolls back and verifies no fixture rows remain.

Run the complete local/disposable path after applying the core schema:

```bash
export DATABASE_URL="postgres://postgres:postgres@localhost:5432/postgres"
bash scripts/validate_source_import.sh
bash scripts/validate_chat_mine_export.sh
```

**Safety warning:** use only a fresh local or otherwise disposable database. Do not point
this command at production or live Supabase. The smoke path is intentionally
rollback-only, never calls `source_mark_batch_ready`, and does not mark the fixture batch
ready, cut over, or authoritative.
