# Classification notes: project container

Synthetic example only. This AI project container is one source shape. It is
not the default import path.

Contract: [`docs/07-source-import-cutover.md`](../../../docs/07-source-import-cutover.md)
and [`docs/09-source-adapters.md`](../../../docs/09-source-adapters.md).

## Source

- Source system: `example-project-container`
- Source type: `ai-export`
- Raw input: [`sample-input/`](sample-input/project.json)
- Manifest draft: [`expected-manifest.json`](expected-manifest.json)
- Container: `example-project` (`project_id_or_slug`)
- Actors: `person-1`, `agent-1`, `device-demo-1`

The project is the source container. Import order in the adapter notes is:
preserve instructions and files, inventory conversations, then suggest zones.
Ambiguous or stale state stays in HOLD.

| File | Role |
|---|---|
| `sample-input/project.json` | Container inventory. `conversation_count` 2, `file_count` 2. |
| `sample-input/instructions.md` | Current instruction set. |
| `sample-input/files/restricted-subject-pointer.md` | Restricted subject file. |
| `sample-input/conversations/older-status.json` | January status conversation. |
| `sample-input/conversations/current-status.json` | Later status conversation. |

Markdown files in this sample have no native timestamps. Those items record
`timestamp_source=export_watermark` and use the container export time
`2026-07-08T16:00:00Z`. Conversation files use the timestamps inside the JSON.

The instruction payload hash is the hash of `instructions.md`. The container
file does not duplicate that hash as a second authority.

## Suggested classifications

| Source item | Manifest key | Suggested action | Suggested zone | Review state | Why |
|---|---|---|---|---|---|
| `project-container-metadata` | `project-container-inventory` | evidence | EVIDENCE | unreviewed | Export inventory, not user memory. |
| `project-instructions` | `project-instructions-current` | import | HOUSE | unreviewed | Current instructions as a `wiki_pages` draft. |
| `restricted-subject-pointer` | `restricted-subject-pointer` | import | VAULT | needs_review | Restricted file for `vault-subject-demo-1`. |
| `conv-older-status` | `older-status-port-8080` | hold | HOLD | needs_review | Stale-state quarantine for the January cutover claim. |
| `conv-current-status` | `current-status-port-9090` | import | HOUSE | unreviewed | User decision in the later conversation. |
| `conv-current-status` | `current-status-model-summary` | evidence | EVIDENCE | unreviewed | Assistant summary in the same file. |

`conv-current-status` is one source item with two candidates. The user decision
and the model summary do not share a zone.

## Stale-state quarantine

`conv-older-status` says the January cutover is complete and the listener is
port 8080. The draft holds that candidate. `quarantine_reason` is
`stale_state`, and `superseded_by_source_item_key` points at
`conv-current-status`.

The later user decision remains an unreviewed HOUSE suggestion. The assistant
summary in that file stays EVIDENCE, so the model does not confirm the decision.

Probe `example-project-stale-cutover` expects the January conversation to stay
non-authoritative. Probe `example-project-vault-boundary` expects the
restricted file to stay out of HOUSE.

## Payload hash and count verification

Algorithm: `sha256` of each raw file, trailing newline included.

Verification counts: source_item_count=5, exported_item_count=5, candidate_count=6, import_count=3, hold_count=1, evidence_count=2, exclude_count=0, rejected_count=0, held_excluded_or_rejected_count=1.

Per-file checksums and per-item payload hashes live in
[`expected-manifest.json`](expected-manifest.json). Recompute with:

```bash
python3 scripts/validate_source_adapter_examples.py
```

## What this draft does not do

The batch status stays `open`. The draft does not approve records, does not
call `source_mark_batch_ready`, and does not claim a project container is the
default import path. It is not production-ready import tooling.
