# 09 · Source Adapter Matrix

## Purpose

Sovereign Memory Core should be able to import from many real-world memory and knowledge sources without making any one source the default architecture.

This document defines source adapter expectations for common sources such as AI conversation exports, project folders, file wikis, notes apps, connector-backed memory stores, and prior Sovereign Memory deployments.

Adapters translate source-specific exports into the generic source-import contract described in `docs/07-source-import-cutover.md`.

## Adapter rule

An adapter is not allowed to decide truth.

An adapter may:

- inventory source records;
- export raw payloads;
- compute hashes;
- preserve source metadata;
- suggest classification;
- suggest target records;
- produce a manifest draft.

An adapter must not silently:

- promote stale state to active truth;
- discard conflicts;
- rewrite source timestamps;
- merge records without evidence;
- treat model-generated statements as human decisions;
- move restricted records into HOUSE because parsing was convenient.

## Universal adapter output

Every adapter should produce or feed:

```text
source_system
source_batch
source_item_manifest
source_payload_evidence
classification_suggestions
cutover_probe_candidates
```

At minimum, each source item needs:

```text
source_system:
source_container:
source_item_id_or_path:
source_created_at:
source_updated_at:
source_author_or_actor:
source_kind:
content_type:
payload_hash:
raw_payload_location:
suggested_action: import / hold / exclude / evidence
suggested_target_zone: HOUSE / VAULT / HOLD / EVIDENCE
review_state:
notes:
```

## Source matrix

| Source | Likely export shape | Strengths | Risks | Default handling |
|---|---|---|---|---|
| ChatGPT data export | JSON conversations, project metadata where available, files/attachments depending on export | Rich history, project context, user instructions, decisions | Very large, mixed stale/current state, private data, model hallucinations mixed with user statements | Preserve raw, classify by project/date/topic, HOLD current-state claims unless recently confirmed |
| ChatGPT Projects | Conversation set plus project instructions and files if exported or accessible | Strong project grouping and instruction provenance | Project state may be scattered across chats; export completeness may vary | Treat project as source container; convert durable docs to wiki drafts; facts to proposed memories |
| Claude export or project artifacts | Chat/project exports, local files, artifacts, Claude Desktop context | Often good reasoning trails and artifacts | Model-authored plans can look like decisions; workspace access differs by surface | Preserve artifacts as EVIDENCE unless explicitly durable; classify final decisions separately |
| Gemini exports | Conversation exports or Takeout-style records where available | Useful cross-model perspective and search-backed threads | Export schema may vary; web-derived claims need citations/provenance | Preserve source, extract only durable user-owned facts after review |
| Grok exports | Conversation history where available | Useful external-model contrast | Export completeness and format may vary | Treat as conversation evidence first; promote only reviewed facts |
| MCP memory store | Row-like memory records | Already fact-shaped; likely easy to map | May contain stale or incorrectly promoted facts; IDs/status semantics vary | Manifest every row; preserve source IDs and hashes; review stale/current claims |
| MCP wiki store | Page/document records | Document-shaped; easier wiki migration | May mix instructions, scratch, and durable docs | Preserve pages; classify `_system`/runbook/instructions separately; review authority |
| Markdown file wiki | Files and folders | Portable, human-readable, easy hashes | Weak metadata, unclear status, duplicate facts | Use file path as source ID; import durable pages to wiki; extract memories only after review |
| Notes app export | Markdown, HTML, JSON, or proprietary export | Human-authored notes and decisions | Dates/tags may be lossy; private content mixed with ordinary notes | Preserve raw export; classify by folder/tag/date; HOLD sensitive or ambiguous notes |
| Spreadsheet | CSV/XLSX rows | Structured records, easy counts | Column semantics may be implicit; formulas or formatting can hide meaning | Preserve raw file and row hashes; require column mapping before import |
| SQL database | Tables/views dump | Strong structure and timestamps | Schema semantics may be app-specific; IDs may not be globally meaningful | Preserve dump; map tables to manifest; import only through explicit transformation version |
| Browser bookmarks/history | HTML/JSON/SQLite | Useful source and topic history | Huge volume, low signal, privacy-sensitive | Evidence or derived-index candidate, not memory by default |
| Email export | MBOX/JSON/API rows | Strong provenance and timestamps | Sensitive; high volume; legal/privacy concerns | VAULT or EVIDENCE by default; promote facts only with review |
| Prior Sovereign Memory deployment | SQL/JSON export | Closest semantic match | Schema version drift; authority model may differ | Use provider-exit/restore path; verify hashes and schema version before merge |

## Chat conversation sources

AI chat exports are high-value but high-risk.

They often contain:

- user facts;
- project decisions;
- model interpretations;
- outdated plans;
- abandoned ideas;
- copied source material;
- personal or sensitive records;
- assistant mistakes;
- repeated summaries.

### Conversation import rule

Do not import a conversation as one giant memory.

Recommended classification:

| Conversation element | Default target |
|---|---|
| User-stated durable fact | proposed memory or active memory if recent and unambiguous |
| Model summary | EVIDENCE or proposed, not active by default |
| Explicit user decision | memory or wiki decision record with source reference |
| Long project plan | wiki draft or project page |
| Outdated implementation status | HOLD or proposed with stale-state note |
| Health/finance/legal/identity content | VAULT or HOLD |
| Tool output / connector result | EVIDENCE with provenance |
| Source quote or citation | EVIDENCE, linked to durable record only if rights and context allow |

## Project container sources

Project-based systems, such as ChatGPT Projects or Claude Projects, should map the project itself as a source container.

Recommended source container fields:

```text
project_name:
project_id_or_slug:
exported_at:
conversation_count:
file_count:
instruction_hash:
source_platform:
```

Import order:

1. preserve project-level instructions and files;
2. inventory conversations;
3. classify project pages or decisions;
4. extract durable memories;
5. create cutover probes from important user expectations;
6. leave ambiguous state in HOLD.

## Connector-backed memory sources

Connector-backed stores such as MCP memory or wiki sources are useful because they already have memory-shaped or page-shaped data.

They still need review because a memory store may already contain:

- over-promoted model inference;
- stale state;
- duplicate facts;
- missing provenance;
- source-specific status values;
- row IDs that should not become canonical IDs.

Adapter rule:

```text
source row id stays source row id
Sovereign Memory target id is new unless performing a verified same-system restore
```

## Cutover probe candidates by source

Adapters should propose probes based on high-value expected recall.

Examples:

- “What is the current architecture of this project?”
- “What decision replaced the old plan?”
- “Which source proves this fact?”
- “What should not be treated as current anymore?”
- “What restricted record must not appear in HOUSE?”
- “What project instructions are currently authoritative?”

## Bulk transfer rule

Do not relay bulk exports through model context, chat messages, or tool stdin when a file or server-side transfer is possible.

Required verification:

- source item count;
- exported item count;
- file size;
- file checksum;
- payload hash algorithm;
- import count;
- rejected/held/excluded count.

## Adapter maturity levels

### Level 0: Manual

Human or assistant manually inventories and imports selected records.

### Level 1: Export parser

Adapter reads source export and produces raw payload evidence plus item counts.

### Level 2: Manifest generator

Adapter produces a manifest draft with suggested action and target zone.

### Level 3: Reconciliation helper

Adapter detects duplicates, conflicts, stale state, and likely target records.

### Level 4: Cutover assistant

Adapter proposes cutover probes and readiness checks, but still requires owner approval.

No adapter should bypass review for high-impact or sensitive records.

## Minimum viable adapters

To prove the core import contract is real, the repo should eventually include examples for at least:

1. JSONL conversation export;
2. Markdown file wiki;
3. row-like memory store;
4. SQL table export.

These examples should be small, synthetic, and non-private.
