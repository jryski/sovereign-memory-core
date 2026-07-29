# Sovereign Memory Core

Portable PostgreSQL contracts for provenance-preserving personal and household AI memory.

This repository contains protocol SQL, neutral documentation, synthetic fixtures, and conformance tests. It must not contain live deployment identifiers, private record counts, operational channel references, credentials, or production evidence.

## Apply order

```text
sql/01_core.sql
sql/02_vault_tier2.sql          # optional
sql/03_document_ingest.sql      # optional
sql/04_migration_foundation.sql # optional
sql/05_candidate_locators.sql   # optional
sql/06_cutover_probe_categories.sql # optional
sql/07_work_lessons.sql
sql/08_attention_events.sql
sql/09_perimeter_refresh.sql
sql/10_security_definer_hardening.sql
```

`07`, `08`, and `09` are re-runnable legacy fix-forward migrations and must be
reapplied, if needed, before `10`. `09` closes schema creation, table grants,
function execution, default privileges, RLS/FORCE RLS, owner, and trigger-only
boundaries. `10` is a re-runnable, one-way hardening boundary and must run last:
after it has been applied, reapply `10` only, not `07`–`09`, because those
historical definitions intentionally predate the explicit-`pg_temp` contract.
`10` recreates the exact reviewed SECURITY DEFINER and authority-adjacent helper
inventory with protected names qualified and `pg_temp` explicit last. See
[`docs/security-definer-inventory.md`](docs/security-definer-inventory.md).

## Perimeter policy inputs

`09` audits every effective role, not only familiar platform role names. It
classifies direct, inherited membership-chain, and `PUBLIC`-derived `CREATE`
and `EXECUTE` authority, plus owner-scoped table, sequence, and function
defaults that would affect future objects. Its protected-schema and authority-
function registries bound remediation to sovereign-memory surfaces; unrelated
schemas, functions, and owner/schema defaults are not silently absorbed. Every
non-system schema in an explicitly registered authority function's fixed
`search_path` must itself be present in the protected-schema registry; otherwise
the assertion fails closed before remediation. The built-in inventory explicitly
registers both `public` and the repository's `extensions` dependency when present.
Durable control-table table and column ACL findings identify direct grants,
membership-chain inheritance, and `PUBLIC` pseudo-grants as distinct sources. The
default `portable` profile permits no non-owner schema creation or function
execution. Deployments using the repository's Supabase grants must explicitly
persist the scoped profile before applying the package:

```sql
alter database your_database
  set sovereign_memory.perimeter_profile = 'supabase';
```

The `supabase` profile permits `service_role` only on non-internal authority
functions. It never waives trigger-only/internal writers or schema `CREATE`.
Other deployments can declare comma-separated effective-principal allowlists
with `sovereign_memory.perimeter_allowed_owner_roles`,
`sovereign_memory.perimeter_allowed_schema_create_roles`,
`sovereign_memory.perimeter_allowed_function_execute_roles`, and
`sovereign_memory.perimeter_allowed_internal_execute_roles`.

The owner-run migration snapshots these inputs into an ACL-protected durable
policy row. Runtime assertions read that row, not caller-controlled custom GUCs.

`sovereign_memory.perimeter_acl_mode` is `revoke` by default: direct grants
outside policy are revoked and the effective audit then fails if authority
still remains. Set it to `fail` for audit-only deployment gates. An allowlist
entry is a deliberate platform waiver; the audit still enumerates all roles,
so it is not an assertion blind spot.

Owner-global default privileges are a separate operator boundary because they
apply in every schema where that owner creates objects. Migration `09` reports
these as `global_default_*` violations in both modes and never revokes them.
Before applying, operators must establish the intended global baseline for each
allowed owner (PostgreSQL grants `PUBLIC` function execution by default), for
example:

```sql
alter default privileges for role your_owner
  revoke execute on functions from public;
```

A schema-scoped default can add privileges but cannot negate a global grant;
`revoke` mode therefore repairs only schema-scoped defaults in explicitly
registered protected schemas. Unrelated owners' global defaults are not read or
mutated by this repository migration.

## Current contracts

- Work lessons are proposal-gated and evidence-backed.
- Rejected successor proposals remain readable but do not block replacement successors.
- Public evidence locators use generic protocol kinds such as `coordination_ref`; deployment mappings remain private.
- Native creation and activation events are emitted only by their actual source-transition triggers.
- Runtime replay APIs are existence-only and never synthesize missing history.
- Revision keys hash the exact persisted `source_revision`.
- Appended revisions capture the current observer context and label shared-runtime attribution honestly.
- Concurrent identical revision replay returns one winning event.
- Context budgets are serialized PostgreSQL characters, with a proven decimal fixed point for the self-reported count.
- Generated events, evidence, and authority records are append-only.

See:

- [`docs/work-memory.md`](docs/work-memory.md)
- [`docs/attention-layer.md`](docs/attention-layer.md)
- [`docs/upgrades/work-memory-v2.md`](docs/upgrades/work-memory-v2.md)

## Conformance

GitHub Actions tests PostgreSQL 15 and 16 for:

- fresh install on a non-empty database;
- runtime-role adversarial paths;
- reject-then-replace lifecycle;
- independent revision-key recomputation;
- fixed-point boundaries at 9/10, 99/100, 999/1000, and 9999/10000;
- multibyte, escaped, and tight-budget payloads;
- migration reapplication;
- deliberate drift followed by remediation;
- arbitrary direct, inherited, and `PUBLIC` stale-grantee drift;
- owner-scoped default ACL drift and future-object inheritance;
- runtime GUC spoof attempts and unrelated SECURITY DEFINER negative fixtures;
- portable-profile fresh apply and exact reapply;
- executable upgrade from the previous PR head;
- concurrent identical revision replay;
- final perimeter closure.
- exact SECURITY DEFINER inventory and omitted, misordered, untrusted, checker-self-shadow, and privileged-write temp-shadow probes.

The public test corpus is synthetic.
