# 05 · Operations: survive vendor change, your own mistakes, and time

The design goal: losing the Supabase account is an afternoon of restore work, not a loss.

## 1. Migrations belong OUTSIDE the vendor

The hosted `supabase_migrations.schema_migrations` table is the only schema history a
default Supabase project has. It lives inside the thing whose loss you are insuring
against. Rules:

- Every migration's SQL is mirrored to a git repo (local + one remote you control) in
  the same session it is applied. Convention, enforced by habit and by the drift check.
- Monthly drift check: compare the version list and a checksum of the full concatenation.

Export/verify query (produces one text blob with per-migration headers, plus an md5 you
compare against your repo file):

```sql
with m as (
  select version, coalesce(name,'') as name,
         array_to_string(statements, E'\n') as sql
  from supabase_migrations.schema_migrations
)
select md5(string_agg('-- >>> MIGRATION ' || version || ' ' || name || E' <<<\n'
           || sql || E'\n', E'\n' order by version)) as full_md5,
       count(*) as n,
       string_agg(version, E'\n' order by version) as manifest
from m;
```

Keep `MANIFEST.txt` (version list) next to `all_migrations.sql` in the repo. Drift =
manifest mismatch or md5 mismatch; resolve immediately, in whichever direction is true.

## 2. Independent backups

Weekly `pg_dump` of the project to storage you control (NAS, external drive, second
cloud). Both formats:

```bash
# custom format: full-fidelity restore
pg_dump "$DB_URL" -Fc -f backup_$(date +%F).dump
# schema-only SQL: human-readable, diffable
pg_dump "$DB_URL" --schema-only -f schema_$(date +%F).sql
sha256sum backup_$(date +%F).dump > backup_$(date +%F).dump.sha256
```

`$DB_URL` is the project's direct Postgres connection string (Dashboard → Database →
connection string). Retention: 8 weekly + 6 monthly. Never let the checksum file drift
from the dump.

Quarterly human-readable data export (the "understandable outside any provider" test):
wiki_pages as markdown files, memories as JSONL, vault records as JSONL with hashes.
An assistant can script this in one session; keep the script in the repo.

## 3. Restore rehearsal = provider-exit test

A backup that has never been restored is a hypothesis. Once after setup, then annually
or after any schema overhaul:

```bash
docker run -d --name exit-test -e POSTGRES_PASSWORD=x -p 55432:5432 postgres:16
pg_restore -d "postgresql://postgres:x@localhost:55432/postgres" --no-owner backup_YYYY-MM-DD.dump
```

Pass criteria on the scratch database:
1. Row counts per table match the source at dump time.
2. `select session_boot('alex');` executes (proves the function surface is vanilla-
   Postgres portable).
3. Any payload-hash joins (vault `source_link` vs recomputed sha256) return zero
   mismatches.
4. Expected failures are ONLY: missing extensions you can `create extension` (pgvector
   if used), and grants referencing Supabase roles (anon/authenticated/service_role),
   which are minutes to shim. Anything else that fails is real coupling; fix it in the
   schema, not the runbook.

Record results in a wiki page (`infrastructure/provider-exit-test`) with date and
findings. That page is your proof the sovereignty claim is real.

## 4. Rollback expectations

- Data: supersede chains + preserved vault sources make content rollback a query, not a
  restore. Nothing is hard-deleted without an audit row.
- Schema: migrations are forward-only. Do not write retroactive down-migrations
  (busywork). Rule instead: destructive DDL requires a fresh pre-dump, which the weekly
  cadence makes nearly free.

## 5. Tooling gotchas (paid for in blood; read before letting an agent operate)

These are behaviors of the Supabase MCP tools and large-payload transfer observed in
production. Encode them into any agent that operates this system:

1. **`execute_sql` multi-statement batches return only the LAST statement's result.**
   Verify several things at once with UNION ALL, or one statement per call.
2. **`apply_migration` is atomic and can fail opaquely.** A PL/pgSQL parse error rolls
   the whole migration back, sometimes surfacing only a generic tool error. After any
   migration, verify its objects exist; never trust "success" alone. Pre-test tricky
   function bodies as `do $$ ... $$` blocks.
3. **Same-statement snapshot visibility will gaslight your tests.** A statement's SELECT
   cannot see rows written by its own CTEs or by triggers it fired. Acceptance checks go
   in a SEPARATE statement from the writes they verify.
4. **Supabase auto-grants on new public objects.** Every object-creating migration ends
   with the revoke block + `assert_perimeter_closed()`. No exceptions. (docs/02)
5. **Large payload relay corrupts silently.** Moving big blobs (schema exports, base64)
   through chat/tool pipes truncates without error past roughly 2-4k characters per
   chunk, and model transcription of long opaque strings is unreliable. Working pattern:
   chunk to ~2,000 chars, transfer via stdin to a small script (not inline heredocs in
   model-typed commands), and verify EVERY chunk and the final file against md5/byte
   counts computed by Postgres (`md5()`, `length(convert_to(...,'UTF8'))`). A checksum
   mismatch means redo the chunk, never "close enough."
6. **Long-running MCP servers die mid-task.** Before any multi-step transfer, write a
   RESUME file recording per-chunk checksums and completion state, so any session (or a
   different model) can finish mechanically. Assume interruption; make everything
   resumable and idempotent.
7. **GENERATED ALWAYS identity columns reject helpful models.** Agents love to supply
   `seq`/`id` values on insert. The error is the constraint working; teach agents to
   omit identity columns rather than "fixing" the error by weakening the column.

## 6. Weekly ops ritual (10 minutes, via any assistant)

Ask: "Boot. Report anything overdue, anything in proposed_for_review, hot-list topics
that look stale, and open channel items older than a week. Then run the migration drift
check." That single prompt keeps the store trustworthy. Monthly, add: "verify latest
backup checksum and confirm the repo migration manifest matches the database."
