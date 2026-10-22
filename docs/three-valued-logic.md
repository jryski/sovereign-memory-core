# Three-valued logic fail-closed verification

Guidance and a disposable local proof for
[issue #74](https://github.com/jryski/sovereign-memory-core/issues/74).

SQL `NULL` is not false. A check can be written correctly and still report
success because the thing reading it treats unknown as pass. This page records
that hazard and the five verification-gate requirements suggested in the issue.
It is not an SMP Draft 0.3 conformance claim, and it is not a row in
[`smp-conformance-gap-audit.md`](publication/smp-conformance-gap-audit.md).
It does not inspect a live database.

## The three layers

### 1. Assertions that pass without asserting

A missing JSON key, a comparison against `NULL`, and `NOT NULL` are all
`NULL`, not false. `bool_and` skips `NULL` and returns true when any remaining
value is true. `count(*) FILTER (WHERE NOT pass)` skips `NULL` and counts zero
failures. An empty `bool_and` is `NULL`, and `NULL IS NOT FALSE` is true, so a
suite that never ran can also look green.

Corrected forms:

```sql
bool_and(coalesce(pass, false))
count(*) filter (where pass is not true)
```

Treat an empty aggregate as failure too: `coalesce(bool_and(...), false)`.

### 2. Security predicates that return NULL

```sql
select p_row_owner = p_principal_id or p_row_visibility = 'shared';
```

With a `NULL` owner and private visibility this is `NULL`, not false. A
`WHERE` clause hides the bug, because both `NULL` and false drop the row. The
next caller can still write:

```sql
if not owner_or_shared(...) then
  raise exception 'denied';
end if;
```

`NOT NULL` is `NULL`, and `IF NULL` does not enter the branch, so the guard
never runs.

The predicate has to be total: every input, including `NULL`, returns true or
false. `COALESCE(..., false)` after an explicit comparison does that. Declaring
the function `STRICT` puts the hole back, because `STRICT` returns `NULL`
without running the body whenever any argument is `NULL`.

### 3. CHECK constraints pass on NULL

A `CHECK` is satisfied when its expression is true **or** unknown. So:

```sql
check ((binding_status <> 'active') or (review_status = 'approved'))
```

accepts `binding_status = 'active'` with a `NULL` review status
(`false OR NULL` is `NULL`). It also accepts `inactive` with a `NULL` review
status (`true OR NULL` is true). The constraint text can look like dual control
and still not require a review value.

`NOT NULL` on every column that invariant reads is what rejects the row. A
conformance check that only asks whether the `CHECK` exists still passes on
the nullable table. Verify the pairing.

A `CHECK` that names `NULL` as permitted (`is null or ...`) evaluates to true
on purpose. That is a different shape from an expression that becomes unknown.
It is not evidence that a dual-control invariant holds when the column is
missing. Do not point this matrix at every `CHECK` in `sql/` and read a hit
as a defect: several constraints in this repository allow `NULL` by name.

## NORMATIVE — verification-gate requirements

The key words **MUST**, **MUST NOT**, and **SHOULD** are used as in RFC 2119.
They apply to SQL verification gates and to the runners that read those gates.
They are the suggested protocol requirements from issue #74. They are not yet
requirements of SMP Draft 0.3.

1. Security predicates **MUST** be total functions — always boolean, never
   `NULL` — and **MUST NOT** be declared `STRICT`.
2. Every `CHECK` constraint expressing an invariant **MUST** be paired with
   `NOT NULL` on every column it reads. Conformance verifies the pairing, not
   the constraint alone.
3. Test aggregates **MUST** treat `NULL` as failure: `coalesce(pass, false)`
   and `IS NOT TRUE`, never bare `NOT`.
4. Test runners **MUST** treat an absent or blank result as failure, not as
   absence of failure.
5. A verification suite **SHOULD** be run against a known-broken implementation
   and required to fail. A suite that has never failed is not evidence that
   the system is correct.

Requirements 4 and 5 are about the consumer of the gate. State the expected
discrimination count before running. Capture the checker's own status. A
pipeline that keeps a later filter's exit status can hide a failing checker.
Do not accept a run that prints a pass marker without a verdict the corrected
gate produced.

## What the local matrix proves

`tests/12_three_valued_fail_closed.sql` rolls back. It records eight cases
where the naive consumer passes and the corrected consumer rejects:

| Case | Naive consumer | Corrected consumer |
|---|---|---|
| `l1_bool_and_ignores_null` | `bool_and` over `{true, NULL, true}` is true | `coalesce(pass, false)` aggregate is false |
| `l1_filter_not_ignores_null` | `FILTER (WHERE NOT pass)` counts 0 | `IS NOT TRUE` counts 1 |
| `l1_not_null_skips_guard` | `IF NOT` on a `NULL` comparison does not fire | `IS NOT TRUE` fires |
| `l1_empty_aggregate_is_not_false` | empty `bool_and IS NOT FALSE` is true | empty corrected aggregate is false |
| `l2_not_predicate_skips_guard` | `IF NOT` on the nullable predicate does not fire | total predicate is false, so the failure guard fires |
| `l2_strict_reintroduces_null` | `STRICT` returns `NULL` and the denial does not fire | the same body without `STRICT` returns false and the denial fires |
| `l3_check_accepts_null` | active plus `NULL` review satisfies `CHECK` | the same insert hits `NOT NULL` |
| `l3_presence_is_not_pairing` | "the CHECK exists" is true on the nullable table | the pairing query reports that table's nullable columns |

The same script asserts the `WHERE` trap: the `NULL` owner row is returned by
neither the positive nor the negated nullable predicate, and the total
predicate returns false for that row. It also checks a small totality matrix
for the predicate, including `NULL` principal and `NULL` visibility.

`scripts/check_three_valued_fail_closed.sh` states the eight-case verdict
before it calls `psql`. It refuses a non-local host, requires that exact
verdict as the only result line, rejects a blank `select null::boolean`, and
rejects `tests/fixtures/three_valued_known_broken.sql`. That fixture exits 0
and prints `true|0`. Leaving it green is the point: the checker must not treat
that exit status as evidence.

## How to run

Use a disposable local database. The matrix creates schema `smc_tvl` inside a
transaction and rolls it back.

```bash
DATABASE_URL="postgres://postgres:postgres@127.0.0.1:5432/postgres" \
  bash scripts/check_three_valued_fail_closed.sh
```

Expected final line:

```text
three_valued_fail_closed: checker pass
```

The script does not print `DATABASE_URL`. Hosts other than `localhost`,
`127.0.0.1`, and `::1` are refused. PostgreSQL 15 and 16 run this checker in
[`.github/workflows/three-valued-fail-closed.yml`](../.github/workflows/three-valued-fail-closed.yml).

## What this does not prove

- No live or hosted database was read or changed.
- The matrix does not certify the checks already shipped under `sql/`.
- A green checker run is evidence about these eight cases and about this
  runner. It is not evidence about any other gate.
- Passing this matrix does not establish SMP conformance, provider exit, or
  live acceptance.
