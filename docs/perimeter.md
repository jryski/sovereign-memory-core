# Perimeter policy

Operator reference for migration `09_perimeter_refresh.sql`. Extracted from the
README, which should stay readable by someone deciding whether this project is
relevant to them. This document assumes you have already decided and are
deploying.

## What the audit covers

Migration `09` audits every **effective** role, not only familiar platform role
names. It classifies:

- direct grants;
- privilege inherited through role membership chains;
- privilege derived from `PUBLIC`;
- owner-scoped table, sequence, and function defaults that would affect objects
  created in future.

Enumerating all roles rather than a known list is deliberate: an allowlist entry
is a conscious waiver, not a blind spot in the audit.

## Registry scoping

The protected-schema and authority-function registries bound remediation to
Sovereign Memory surfaces. Unrelated schemas, functions, and owner or schema
defaults are not silently absorbed.

Every non-system schema appearing in an explicitly registered authority
function's fixed `search_path` must itself be present in the protected-schema
registry, or the assertion fails closed *before* any remediation runs.

## Profiles

The default `portable` profile permits no non-owner schema creation and no
non-owner function execution.

Deployments using this repository's Supabase grants must persist the scoped
profile before applying the package:

```sql
alter database your_database
  set sovereign_memory.perimeter_profile = 'supabase';
```

The `supabase` profile permits `service_role` only on non-internal authority
functions. It never waives trigger-only or internal writers, and it never
permits schema `CREATE`.

## Allowlists

Other deployments declare comma-separated effective-principal allowlists:

- `sovereign_memory.perimeter_allowed_owner_roles`
- `sovereign_memory.perimeter_allowed_schema_create_roles`
- `sovereign_memory.perimeter_allowed_function_execute_roles`
- `sovereign_memory.perimeter_allowed_internal_execute_roles`

The owner-run migration snapshots these inputs into an ACL-protected durable
policy row. **Runtime assertions read that row, not caller-controlled custom
GUCs.** A caller cannot widen its own perimeter by setting a session variable.

## ACL mode

`sovereign_memory.perimeter_acl_mode` defaults to `revoke`: direct grants
outside policy are revoked, and the effective audit then fails if authority
still remains after revocation.

Set it to `fail` for audit-only deployment gates where you want the check to
report without mutating grants.

## Owner-global default privileges

Owner-global default privileges are a **separate operator boundary**, because
they apply in every schema where that owner creates objects, including schemas
this project knows nothing about.

Migration `09` reports these as `global_default_*` violations in both modes and
**never revokes them.** Operators must establish the intended global baseline
for each allowed owner themselves, for example:

```sql
alter default privileges for role your_owner
  revoke execute on functions from public;
```

A schema-scoped default can add privileges but cannot negate a global grant.
`revoke` mode therefore repairs only schema-scoped defaults in explicitly
registered protected schemas. Unrelated owners' global defaults are never read
or mutated by this migration.

## Conformance coverage

CI exercises the perimeter on PostgreSQL 15 and 16:

- portable-profile fresh apply, and exact reapply;
- arbitrary direct, inherited, and `PUBLIC` stale-grantee drift;
- owner-scoped default ACL drift and future-object inheritance;
- runtime GUC spoof attempts;
- unrelated SECURITY DEFINER negative fixtures;
- omitted, misordered, untrusted, checker-self-shadow, and privileged-write
  temporary-object shadow probes;
- deliberate drift followed by remediation;
- final perimeter closure.

## Related

- [`security-definer-inventory.md`](security-definer-inventory.md) — the exact
  reviewed SECURITY DEFINER surface that migration `10` recreates.
