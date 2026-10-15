# Conformance criterion shape

Operational contract for the criterion-shape rules in [SMP custody layer §12](smp-custody-layer.md#criterion-shape).

The normative statements live in that section. This note describes how the local runner scores a suite, and what an offline verifier fixture has to contain before it can be used as conformance evidence.

## Runner

```bash
bash scripts/validate_conformance_criteria.sh
```

The shell entry point runs `scripts/conformance_criteria.py` on `fixtures/conformance/criterion_shape_suite.json`, then the unit tests under `tests/conformance/`. No database is required.

The reference suite is a synthetic scope-bound access fixture:

- `principal-a` receives private `record-a` through the owner disjunct;
- `principal-b` receives private `record-b` through the owner disjunct;
- `principal-c`, who holds `scope-a`, receives shared `record-shared` through the shared disjunct;
- `principal-b` is denied `record-a` because that principal does not hold `scope-a`;
- `principal-c` is denied private `record-a` even though that principal holds `scope-a`, so only the visibility disjunct explains the denial;
- a host filter named `authenticated` asserts that the identifier is present before it reads grant counts.

Each of those checks has a broken input in `demonstrations`. The run applies the input and requires the named failure reason. The same run builds a fixture with the identity-binding review field removed and requires construction to abort.

A suite-level `verdict` string is ignored. Passage is the aggregate of executed checks.

## Report

Every run prints three coverage numbers and a conformance class:

```text
CRITERIA defined=<n> evaluated=<n> passed=<n> skipped=<n>
DEMONSTRATIONS defined=<n> executed=<n> matched=<n>
COUNTS characterizing=yes|no
CONFORMANCE full|partial|fail|abort
```

| Status | Evaluated | Passed | Meaning |
|---|---|---|---|
| `PASS` | yes | yes | The check ran, matched its reason, and recorded what it examined. |
| `FAIL` | yes | no | The check ran and did not match. |
| `SKIPPED` | no | no | The check did not run. The reason is printed. |
| `UNSUPPORTED` | no | no | A declared host identifier was absent. This is a hard error for a check that expected to evaluate. |
| `NOT_EVIDENCE` | no | no | A grant on the same fixture failed, so the denial result is not evidence. |
| `ABORTED` | no | no | Fixture construction failed. Denial checks were not scored. |
| `UNEVALUATED` | no | no | The suite shape is invalid, so checks were not scored. |

`COUNTS characterizing=yes` only when every grant criterion passed and no host filter returned `UNSUPPORTED` or `FAIL`.

## Exit status

| Exit | Class | When |
|---|---|---|
| 0 | `full` | Defined, evaluated, and passed are equal and non-zero. Every demonstration matched. Nothing was skipped, unsupported, or withheld as non-evidence. |
| 3 | `partial` | Every evaluated criterion passed and every demonstration matched, and at least one criterion is `SKIPPED`. |
| 2 | `abort` | Fixture construction failed. |
| 1 | `fail` | A criterion failed, a host filter was `UNSUPPORTED`, a denial was `NOT_EVIDENCE`, a demonstration mismatched, or the suite shape is invalid. |

Exit 0 is "every defined criterion passed." Exit 3 is "every criterion that was evaluated passed." A partial run is not full conformance.

## Offline verifier fixture

The offline verifier fixture is still a separate gap (conformance audit follow-up 7). When that fixture exists, the same shape applies directly:

- an authorized-receive case on the same fixture as the conflict, stale, held, and excluded cases;
- a case whose host lacks platform-specific roles, extensions, and default-privilege assumptions, with expected outcome `UNSUPPORTED`;
- a broken fixture variant the verifier run executes and must reject for a named reason.

`fixtures/conformance/criterion_shape_suite.json` is the local proof of that shape. It is not an SMP-complete verifier and it does not close the offline fixture.
