# 12 · Scope-bound authority

Authority is declared for one named scope. It is not implied for every scope, and this repository has no scope kind that means "all of them."

This is a repository contract for cutover. Applying `sql/12_scope_bound_authority.sql` belongs on a disposable or backed-up database. Presence of the file is not a live Supabase change and it is not acceptance of a deployment.

## Scope grammar

A scope key is `kind:identifier`.

| Kind | Use |
|---|---|
| `workstream` | One named body of work. |
| `table` | One named table. |
| `record` | One named record. |
| `domain` | One named consequential domain. |

`register_scope` rejects any other kind, including `global`. It also rejects identifier wildcards and the universal tokens `all`, `global`, and `any`. Breadth is several registered scopes, each written down on its own.

Deactivating a scope (`active = false`) does not delete a recorded declaration and does not silently restore one if the scope is registered again. Revocation is `rollback_scope_authority`.

## What is stored

| Object | Role |
|---|---|
| `scope_registry` | The only scopes that can be named. |
| `source_import_batches.cutover_scope` | The one scope a batch may become authoritative for. Null until assigned. |
| `cutover_probes.result_scope` and `cutover_runs.result_scope` | Probe results bound to that same scope. |
| `scope_truth_claims` | Current, stale, conflicted, or historical statements for one scope. |
| `scope_authority_declarations` | The recorded declaration. |

A batch cannot be inserted or updated into `cutover` unless a live declaration already names that batch and that scope. One live declaration per scope. Rolled-back rows stay.

## Declaration

`declare_scope_authority` records:

- the scope;
- the principal, which must match the declaring agent's principal;
- the batch whose `cutover_scope` is that scope;
- an evidence reference;
- a review note;
- the declaring agent.

The batch must already be `ready`, readiness blockers must still be clear, and each critical probe category must have a latest passing run whose `result_scope` is this scope. Unbound runs do not count. Runs bound to another scope cannot be stored on this batch's probes.

The function then sets **this** batch to `cutover`. It does not set any other batch.

`scope_authority_report.authoritative` is false when no live declaration exists. That column means "a declaration is recorded for this scope." It does not mean every older read path consults the scope.

## Current truth and probe results

`scope_visible_current_truth(scope)` returns current claims for that scope only. A null scope returns no rows. Stale, conflicted, and historical claims stay stored and are not returned as current. The same `claim_key` may be stale in one scope and current in another; each read stays on the scope it was given.

`scope_probe_observations(scope)` returns the latest run whose probe and run are both bound to that scope. `scope_cutover_scorecard` counts those in-scope passes only.

## Rollback and review

Until a declaration is recorded, `rollback_scope_before_authority` can move an open, frozen, or ready batch to `rolled_back`. The note is stored on the batch metadata. No authority row is created.

After a declaration, that path refuses. `rollback_scope_authority` is the recorded reversal: the declaration remains with status `rolled_back`, a note, and the acting agent, and the batch returns to `ready`. The acting agent's principal must be the declaration's principal. Rolling one scope back does not change another scope's declaration or its current truth.

Review posture stays in front of the declaration. `source_mark_batch_ready` still refuses unresolved blockers, and the declaration checks those blockers again. A review note is required on the declaration row.

## What this does not claim

This contract does not wire scope into `memories`, session boot, vault reads, or any other path that predates it. Those paths do not start enforcing scopes because this file exists. A later change that adds a scope dimension to an older path has to test that path. Agreement across every read path is still open.

It also does not add declared scope hierarchy or pattern grants. A grant on one scope reaches that scope.

The functions are not `SECURITY DEFINER`. They are outside the `sql/10` definer inventory. Grants for `PUBLIC`, `anon`, and `authenticated` are revoked.

## Validation

`scripts/validate_source_import.sh` applies this file and runs `sql/validation/scope_bound_authority.sql` on a local database. The fixture registers two scopes, proves current and stale truth do not cross, proves probe results do not cross, records two declarations, and rolls one of them back. The fixture transaction rolls back. It does not target a hosted database.
