# 01 · Architecture

## The one-paragraph version

One Postgres database is the system of record for a household's (or small team's) knowledge.
Multiple AI assistants, owned by different people and made by different vendors, read and
write it through the same service-role connection. The database, not the assistants, enforces
the rules: who wrote what, what counts as a sourced fact, how corrections happen, and what
stays private. Everything is exportable, restorable, and verifiable by checksum.

## Concepts

### Principals and agents
- A **principal** is a human ('example-user', 'example-partner') or the collective ('shared').
- An **agent** is one assistant surface serving one principal ('example-user-claude', 'example-partner-chatgpt'),
  registered in `trusted_agents`. Every write is stamped with its agent. An unregistered
  or retired agent cannot write at all (FK + active check in `remember()` and friends).

### Two dimensions on every fact
- `owner` = who the fact is **about** (example-user | example-partner | shared).
  Joint or team context is `shared`.
- `visibility` = who may **see** it (shared by default | private).
- Visibility rule: a row is visible to viewer V when `visibility='shared' OR owner=V`.
- Constraint: a `shared`-owned row can never be `private` (a secret must belong to someone).

Examples:

| Fact | owner | visibility |
|---|---|---|
| Shared project decision | shared | shared |
| Example User's working note | example-user | shared |
| Example Partner's reading list | example-partner | shared |
| Example User's private draft | example-user | private |

### The three storage shapes (Tier 1)
1. **memories** — atomic facts. Append-mostly. Carry provenance columns, optional
   `due_date` (deadline mechanism), and a `supersedes` chain for corrections.
2. **wiki_pages** — durable documents at a path (`projects/example-project`,
   `_system/ai-instructions`). One `active` row per path (partial unique index);
   edits supersede. Page metadata lives in `frontmatter` jsonb.
3. **memory_hot_index** — the attention layer. A capped (15 per owner) list of "hot"
   topics with a recency-decayed score: `touch_count / (1 + age_days)`. This is what
   makes a fresh session feel oriented without loading everything.

### The second-touch gate
Not everything mentioned once deserves attention. `hot_touch()` implements a gate:
- 1st sighting of a topic_key → staged in `memory_hot_staging` only.
- 2nd sighting → promoted into the hot index (evicting the lowest-scoring topic if full).
- 3rd+ → bumps touch_count and freshness.
This single mechanism filters noise better than any prompt instruction ever did.

### session_boot()
The assistant's first call on any substantive task. Returns, filtered to the viewer:
hot topics, upcoming/overdue deadlines, the cross-assistant channel inbox, operating-doc
integrity state, and health counters. One call, one JSON blob, instant orientation.

### Corrections: supersede, never delete
`supersede_memory()` / `supersede_wiki()` create the replacement row, link it via
`supersedes`, flip the old row to `superseded`, and (for memories) atomically retarget
the hot-index pointer. Hard DELETE is blocked by trigger unless an admin sets
`app.allow_delete='on'` inside a transaction, and even then it is audit-logged.
History is never rewritten; it accumulates.

### Deadlines
A memory with `due_date` + `due_status='pending'` is a tracked deadline. The
`deadlines_upcoming` view surfaces anything due within 14 days or overdue, and
`session_boot()` includes it, so every session opens with "here's what's due."

### The cross-assistant channel
`household_channel` is an inbox between principals' assistants: task / todo / reminder /
note rows addressed to a principal (or 'shared'). Each assistant sees its open items at
boot and closes them with `channel_complete(seq)`. This is how "have your assistant tell
my assistant" becomes literal.

### Operating-doc integrity
The behavior contract for the assistants is itself a wiki page
(`_system/ai-instructions`). `doc_integrity` stores a blessed sha256 of it.
`session_boot()` reports `match | mismatch | no-blessing`. On mismatch the assistant
**warns and asks the human to confirm or re-bless**; it never locks anyone out. This
catches both corruption and prompt-injection-driven rewrites of the contract.

## Tier 2: the private vault (optional)

Separate locked schemas (`identity_private`, `health_private`, `finance_private`,
`vault_private`, `vault_audit`) for data that should never ride in the general
knowledge tables. Three load-bearing ideas:

1. **Preserve-then-normalize.** Anything imported lands verbatim in
   `vault_private.records` with a sha256 of its canonical JSON, before any normalization.
   Normalized rows FK back to the preserved source. Every claim is re-checkable against
   the original, forever.
2. **Temporal truth.** Domain records carry `observed_at` (when it happened),
   `recorded_at` (when we learned it), `effective_from/to` (the window it was true),
   `record_status` (proposed/current/superseded/retracted/entered_in_error), and a
   `predecessor_id` chain. Corrections create history instead of overwriting it.
3. **Principal-before-org access.** `capability_assignment` grants are explicit rows:
   principal x domain x capability x subject x validity window x who assigned x why.
   Access is never an implication of a role name.

`vault_audit.change_log` triggers fire on every domain-table write, logging principal,
action, table, id, and column KEYS only (never payload, so the audit trail is not a
second copy of the sensitive data).

## Multi-agent topology (what "best tool for the job" looks like)

```
             ┌─────────────────────────────────────────────┐
             │                POSTGRES (yours)             │
             │  Tier 1: memories / wiki / hot / channel    │
             │  Tier 2: identity / health / finance vault  │
             │  Rules: triggers, checks, perimeter, audit  │
             └────────▲──────────▲──────────▲──────────────┘
                      │          │          │  service-role connector(s)
               Example User's Claude  Example User's GPT  Example Partner's Claude   ... any future model
```

- Every assistant boots from the same state and writes under its own agent_id.
- Model-to-model async coordination happens through tables (`household_channel`
  between principals; add a `model_channel` table with the same shape if you want
  peer AI-to-AI messaging: from_agent, to_agent, re_seq, subject, body).
- Personal connectors (health APIs, calendars, email) stay attached to each person's
  assistant. Only the resulting durable rows live together in the store.

## What is deliberately NOT here

- No embeddings requirement. Vector search is a nice-to-have cache; the hot index +
  workstream/tags/text queries carry a personal-scale corpus fine. If you add pgvector,
  treat embeddings as regenerable, never as canon.
- No app server, no Edge Functions, no queue. The assistants call SQL functions.
  Add moving parts only when a concrete need arrives.
- No cross-vendor schema mirroring. If you run a second store (say, a business one),
  share PATTERNS and contracts, not tables. Feature parity between different use cases
  is a treadmill; see docs/06.
