# 04 · Implementation guide (agent-executable)

This is a build order with acceptance tests. A capable AI agent with a Supabase MCP
connector can execute it end to end; a human with the SQL editor can too. Do the steps
in order; each has a verifiable DONE condition. Do not proceed past a failed test.

Conventions for the executing agent:
- Use `apply_migration` (not `execute_sql`) for DDL so every change lands in
  `supabase_migrations.schema_migrations` with a name.
- After EVERY migration, run `select assert_perimeter_closed();` (exists after step 2).
- `execute_sql` returns only the LAST statement's result of a multi-statement batch;
  verify multiple things in one call with UNION ALL.
- `apply_migration` is atomic and can roll back silently on PL/pgSQL parse errors
  without surfacing the failing line. If a migration "succeeded" but its objects are
  missing, it did not succeed: test function bodies as plain `do $$ ... $$` blocks
  first, then wrap in `create or replace function`.

## Step 0: Project
Create a Supabase project (free tier fine). Record the project ref. Connect your MCP.
- DONE: `select 1;` returns via the connector.

## Step 1: Customize the script
In `sql/01_core.sql`, replace principals `alex`/`sam` in: the `trusted_agents` seed,
and every `check (... in ('alex','sam','shared'))` (memories, wiki_pages,
memory_hot_index, memory_hot_staging, household_channel). Single person? Use one name;
keep 'shared'.
- DONE: `grep -c "CUSTOMIZE"` locations all edited (5 check constraints + seed block).

## Step 2: Apply Tier 1
Apply `01_core.sql` as one migration named `core_v1`.
- DONE (all in one execute_sql):
```sql
select 'perimeter' as t, assert_perimeter_closed() as v
union all select 'agents', count(*)::text from trusted_agents
union all select 'instructions', count(*)::text from wiki_pages
  where path='_system/ai-instructions' and status='active'
union all select 'integrity', state from verify_doc_integrity('_system/ai-instructions');
```
Expect: perimeter OK / agents >= 3 / instructions 1 / integrity match.

## Step 3: Functional smoke test
```sql
select remember('Test fact: the build works.','system','system/build-smoke',
                'system','shared', p_summary=>'build smoke test');
select session_boot('alex');   -- your principal
```
- DONE: session_boot returns the topic staged or hot; health.memories_visible >= 1.
- Second call of remember with the same topic_key should return and `hot_touch` should
  report promotion; verify: `select topic_key from memory_hot_index;` contains
  system/build-smoke after two touches.

## Step 4: Supersede + delete-guard test
```sql
-- capture id
select id from memories where topic_key is null and content like 'Test fact%';
select supersede_memory('<id>','Test fact corrected.','system');
delete from memories where content like 'Test fact%';  -- MUST FAIL
```
- DONE: supersede returns a new uuid; the delete raises
  'hard delete blocked'; `select count(*) from audit_log;` >= 1 (status_change row).

## Step 5: Install the real operating contract
Paste the customized contract from docs/03 section A via `supersede_wiki`, then
`bless_doc`.
- DONE: `verify_doc_integrity('_system/ai-instructions')` state='match'.

## Step 6: Wire the assistants
Per docs/03 B and C: connector + bootstrap for each person's Claude and/or ChatGPT.
- DONE: in a FRESH conversation, ask "boot and tell me what you see." The assistant
  runs session_boot unprompted (because the bootstrap says so), reports hot topics and
  integrity=match, and identifies its own source_agent correctly.

## Step 7 (optional): Tier 2 vault
Apply `02_vault.sql` as migration `vault_v1`. Seed your people:
```sql
insert into identity_private.person(stable_key, legal_name) values
  ('alex','<full name>'), ('sam','<full name>') on conflict do nothing;
insert into health_private.patient(person_id)
  select id from identity_private.person on conflict do nothing;
```
- DONE:
```sql
select 'schemas' as t, count(*)::text from information_schema.schemata
  where schema_name in ('vault_private','identity_private','health_private','finance_private','vault_audit')
union all select 'grants_leak', count(*)::text from information_schema.role_table_grants
  where table_schema like '%_private' and grantee in ('anon','authenticated','PUBLIC')
union all select 'audit_triggers', count(*)::text from pg_trigger
  where tgname='vault_change_log_v1' and not tgisinternal;
```
Expect: schemas 5 / grants_leak 0 / audit_triggers >= 12.
- Audit acceptance: insert then delete a throwaway `identity_private.family_group`
  row (two separate statements; same-statement CTE counts will lie to you due to
  snapshot visibility). `vault_audit.change_log` must show one insert and one delete.

## Step 8 (optional): Provenance guards
Apply `03_provenance_guards.sql` as migration `provenance_guards_v1`.
- DONE, all three behaviors:
```sql
-- 1) unsourced money MUST FAIL:
insert into memories(content,owner,source_agent) values ('Quote came in at $4,200','shared','system');
-- 2) sourced money MUST SUCCEED:
insert into memories(content,owner,source_agent,metadata)
values ('Quote came in at $4,200','shared','system',
        '{"basis":"source_document","source_citation":"contractor-quote-2026-07-01.pdf"}');
-- 3) honest estimate MUST SUCCEED:
insert into memories(content,owner,source_agent,confidence,metadata)
values ('Ballpark is around $5k','shared','system',0.5,'{"financial_unverified":true}');
```
Then perimeter: `select assert_perimeter_closed();`

## Step 9: Source import and authoritative cutover foundation
Apply `04_source_import.sql` as migration `source_import_v1`.

This step installs the generic source-import contract used by adapters and future tools.
It should not be customized for a single prior source system.

For disposable local validation, run the bundled helper from a fresh local database:

```bash
DATABASE_URL="postgres://postgres:postgres@localhost:5432/postgres" \
  bash scripts/validate_source_import.sh
```

The helper creates local compatibility shims (`extensions`, `anon`, `authenticated`,
`service_role`), applies `01_core.sql`, applies `04_source_import.sql`, and runs the
rollback validation bundle. Use it for local review only; production/Supabase deployments
should still apply DDL through migrations.

- DONE, object/perimeter checks:
```sql
select 'perimeter' as t, assert_perimeter_closed() as v
union all select 'source_systems', count(*)::text from information_schema.tables
  where table_schema='public' and table_name='source_systems'
union all select 'source_readiness', count(*)::text from information_schema.views
  where table_schema='public' and table_name='source_readiness'
union all select 'cutover_scorecard', count(*)::text from information_schema.views
  where table_schema='public' and table_name='cutover_scorecard';
```
Expect: perimeter OK / source_systems 1 / source_readiness 1 / cutover_scorecard 1.

- DONE, validation bundle:
```sql
\i sql/validation/source_import_readiness.sql
```
Expected behavior:
- required objects pass;
- function posture passes;
- grant posture passes;
- fixture smoke test returns readiness rows;
- fixture scorecard shows one passing critical probe;
- fixture rows are rolled back.

## Step 10: Source-control your migrations (not optional)
Hosted `supabase_migrations.schema_migrations` is NOT source control; if the project
dies, your schema dies with it. Set up per docs/05 section 1: export every migration to
a git repo now, and adopt the rule that every future `apply_migration` gets its SQL
mirrored to the repo in the same session.
- DONE: repo contains all rows of
  `select version, name from supabase_migrations.schema_migrations order by version;`
  and the concatenation md5 matches the file (docs/05 has the exact query).

## Step 11: First backup + restore rehearsal
Per docs/05 sections 2-3: take a pg_dump, restore it into a scratch vanilla Postgres,
run the exit-test checks.
- DONE: restore succeeds; row counts match; session_boot() runs on vanilla Postgres.

## Build order summary

| Step | Deliverable | Gate |
|---|---|---|
| 0-2 | Tier 1 live, perimeter closed | assert + integrity match |
| 3-4 | Write path, hot gate, supersede, delete-guard proven | smoke tests pass |
| 5-6 | Contract installed, assistants booting | fresh-session boot test |
| 7 | Vault (if needed) | zero grant leaks, audit firing |
| 8 | Money guards (if needed) | fail/pass/pass triple |
| 9 | Source import/cutover foundation | validation bundle passes |
| 10-11 | Survivability | repo checksum + restore rehearsal |

Stop building after step 11. Use it before adding higher-level automation.
