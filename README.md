# Sovereign Memory

A personal, self-hosted memory and knowledge layer for AI assistants, built on plain Postgres
(reference deployment: Supabase). It gives every AI you use (Claude, ChatGPT, local models)
one shared, verifiable source of truth that **you** own, instead of a per-vendor memory silo.

Built and battle-tested as a working household system. This repo is the blueprint: schema,
security model, agent operating instructions, and a build guide a capable AI agent can execute
end to end.

## Why this exists

1. **Data sovereignty.** Your facts live in a database you control, exportable as plain SQL and
   JSON. Vendor change is a migration, not a hostage negotiation.
2. **Best tool for the job.** Any model with a Postgres path (Supabase MCP connector, direct
   SQL, REST) reads and writes the same store. Claude and ChatGPT literally coordinate through
   a table.
3. **Verifiable source of truth.** Facts carry provenance. Consequential domains (money) are
   enforced by the database: a financial figure without a source citation is rejected at write
   time, no matter which model wrote it. Corrections supersede; nothing is silently rewritten.

## What you get

| Layer | What it is | SQL |
|---|---|---|
| Tier 1: Shared knowledge base | Memories, wiki pages, attention (hot) index, deadlines, doc integrity, agent registry, cross-assistant task channel | `sql/01_core.sql` |
| Tier 2: Private vault (optional) | Locked schemas for identity / health / finance with temporal truth, preserve-then-normalize import, and an audit change log | `sql/02_vault.sql` |
| Provenance guards (optional) | Triggers that reject financial figures lacking a real source | `sql/03_provenance_guards.sql` |

## Repo map

```
README.md                     you are here
sql/01_core.sql               Tier 1, one idempotent script
sql/02_vault.sql              Tier 2 private schemas + audit trail
sql/03_provenance_guards.sql  financial provenance enforcement
docs/01-architecture.md       concepts, zones, multi-agent model
docs/02-security-model.md     the actual security boundary, and the traps
docs/03-agent-operations.md   the operating contract + Claude/ChatGPT setup, paste-ready
docs/04-implementation-guide.md  build order with acceptance tests (agent-executable)
docs/05-operations.md         backups, restore test, provider-exit test, drift checks
docs/06-patterns.md           the transferable design patterns and why they matter
```

## Quick start (10 minutes)

1. Create a Supabase project (free tier is fine to start).
2. Run `sql/01_core.sql` in the SQL editor (or via MCP `apply_migration`). It is idempotent.
3. Edit the two principals in `trusted_agents` and the `owner` check constraints to your names
   (see docs/04, step 2).
4. Connect the Supabase MCP connector to your Claude and/or ChatGPT with the service-role key.
5. Paste the operating contract from docs/03 into your assistant's custom instructions.
6. Ask your assistant: "run session_boot and tell me what you see." If it reports hot topics,
   integrity state, and health counts, you are live.

Full build with verification steps: `docs/04-implementation-guide.md`.

## Non-goals

- Not a RAG framework, not an agent framework, not a product. It is a data layer with rules.
- No UI. The assistants are the UI. Resist building dashboards until you actually need one.
- Vector search is optional and treated as regenerable cache, never as the system of record.

## Requirements

- Postgres 15+ (Supabase hosted or any Postgres you run)
- At least one AI assistant that can execute SQL against it (Supabase MCP connector for
  Claude Desktop/ChatGPT, or any tool-calling path to Postgres)
- Basic comfort running SQL once during setup

## Verified

All three SQL scripts were applied end to end on vanilla PostgreSQL 16 (with three shim
roles: anon, authenticated, service_role) and the acceptance tests in
docs/04-implementation-guide.md were executed: perimeter assert, second-touch promotion,
session_boot, supersede + audit, delete-guard rejection, channel round trip, vault audit
triggers with zero grant leaks, and the provenance fail/pass/pass triple. Running on
vanilla Postgres is itself the provider-exit proof: nothing here requires Supabase.

## License / provenance

Extracted from a private working system, genericized. Use freely. No warranty; read
docs/02-security-model.md before putting anything sensitive in it.
