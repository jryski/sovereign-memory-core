# Perimeter evaluability contract

`public.perimeter_report()` is the sanctioned v1 seam for deciding whether the
Sovereign Memory perimeter can be evaluated on the current PostgreSQL target.

The report separates three states that must not be collapsed:

| `evaluation_status` | `perimeter_state` | `violation_count` | Meaning |
|---|---|---:|---|
| `evaluated` | `clean` | `0` | Required evaluation population exists and no perimeter finding was detected. |
| `evaluated` | `not_clean` | `> 0` | Required population exists and one or more findings were detected. |
| `unsupported` | `unknown` | `null` | Required roles or protected surfaces are missing, so a clean/not-clean answer cannot be made. |

The contract version is `perimeter-report/1`.

## Why `null` matters

An unevaluable target does not have zero violations. It has no defensible
violation count. `violation_count = null` is deliberate so a caller that tests
for `= 0` refuses instead of accidentally certifying an environment that could
not be inspected.

`UNSUPPORTED` is report state, not a synthetic violation. The `findings` array
therefore remains empty in that state. The `coverage.gaps` array records why
evaluation was unavailable.

## Enforcement

Use the report as the evidence seam:

```sql
select public.perimeter_report();
```

`public.assert_perimeter_closed()` is the matching fail-closed enforcement
wrapper. It succeeds only when the report is `evaluated`, `clean`, and has zero
findings. It raises `PERIMETER UNSUPPORTED` when required evaluation population
is missing and `PERIMETER FAIL` when the evaluated perimeter is not clean.

The pre-C1 assertion body is retained only as the internal
`public.perimeter_assert_violations_v1()` primitive so existing detailed checks
are preserved. It is not an operator API and is not granted to runtime roles.

## Coverage population

The report refuses to evaluate if any of these prerequisites are incomplete:

- the three durable perimeter control tables;
- exactly one persisted perimeter policy row;
- every role named by the persisted perimeter policy;
- a non-empty protected-schema registry including `public`, with every
  registered schema resolvable;
- a non-empty authority-function registry, with every registered function
  resolvable;
- the protected work/attention tables checked by the perimeter assertion.

A missing hosted-provider role is therefore an `unsupported` result, not an
empty finding set.

## Findings

When evaluation is possible, structured ACL findings from
`public.perimeter_acl_violations()` remain available in the report. Other
perimeter categories enforced by the existing assertion are surfaced as a
bounded assertion finding rather than being converted into a false zero.

For deeper ACL inspection:

```sql
select * from public.perimeter_acl_violations();
```

## Restore rehearsal

Provider-exit evidence must use
[`templates/restore-rehearsal.md`](templates/restore-rehearsal.md). A continuity
rehearsal with its required roles present should evaluate normally. A
sovereignty rehearsal that intentionally withholds required platform roles
should record `unsupported` with `violation_count = null`.

Neither result alone establishes provider exit. The complete release gate also
requires the independent export, clean restore, conformance, source-unchanged,
destination-disposable, manifest, and HOUSE acceptance evidence tracked by the
v0.3-alpha completion program.
