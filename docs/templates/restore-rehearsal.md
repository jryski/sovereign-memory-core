# Restore rehearsal / provider-exit conformance record

Template. Copy per rehearsal, fill DURING the run, retain as evidence.

Addresses STATUS blocker: *no repository-stored evidence template for
backup/restore rehearsal*. Structure only. Filled records belong in the
deployment's own notebook, never here.

---

## 0. Which rehearsal is this?

A single rehearsal cannot answer both questions below. Roles restored onto a
target CREATE the platform role model there, after which role-bound policies
apply cleanly and any check that filters on those roles evaluates normally.
The coupling under test is then masked by the backup being CORRECT.

    [ ] CONTINUITY   platform roles supplied.
                     "Can this system be stood up elsewhere?"
                     Expected: clean pass.

    [ ] SOVEREIGNTY  platform roles withheld.
                     "What does the schema assume about its platform?"
                     Expected: refusal or loud failure.
                     A PASS HERE IS A FINDING, NOT A SUCCESS.

Run both. Record which one this is; several criteria below apply to only one.

## 1. Identification

- Date / operator / target identifier
- Rehearsal type (above)
- Perimeter checker contract version, as reported by the perimeter report.
  **A criterion 6 result is not interpretable without it.** This contract has
  changed before; a bare pass or fail carries no meaning on its own.
- Source and target engine versions. **A dump cannot restore into an older
  major version.** Version-matched targets are mandatory.

## 2. Predictions — WRITE BEFORE EXECUTING

Backfilled predictions prove nothing. Commit this section before the restore
runs, as a separate revision.

- Expected object and row counts
- Expected required extensions, schemas, roles, publications
- Expected failures, IN ORDER
- Expected duration

## 3. Source artifact

- Artifact identifiers and integrity digests, verified BEFORE restore
- Which components are present (roles / schema / data are typically separate;
  a default dump may carry neither roles nor data)

## 4. Pre-flight

- [ ] Target initialised clean; emptiness asserted, not assumed
- [ ] Declared requirements checked against the target
- [ ] For a SOVEREIGNTY rehearsal: platform roles confirmed ABSENT

## 5. Restore

Record exact commands. Note:

- Whether triggers were disabled during load. Provenance and custody triggers
  will otherwise fire per restored row and may abort the load or MUTATE data
  during it.
- Whether errors halted on first failure or collected. Collecting yields a
  full coupling census; halting yields only the first cause.

## 6. Criteria

| # | Criterion | Predicted | Observed | Result |
|---|---|---|---|---|
| 1 | Schema applies without error | | | |
| 2 | Object and row counts match source | | | |
| 3 | Session entry point executes and returns a payload | | | |
| 4 | Only acceptable failures | | | |
| 5 | POSITIVE CONTROL: a known record is VISIBLE and READABLE to an entitled principal | | | |
| 6 | Perimeter REPORT evaluates honestly. Gate on the report, never on the violation primitive | | | |
| 7 | PAIRED DENIAL: a private record owned by another principal is NOT visible to a reader WHO HOLDS THE SCOPE | | | |

### Why 5, 6 and 7 exist

**Criteria 1-4 are all confirmations.** A restore producing a database where
nothing is visible to anyone satisfies every one of them. A denial-only suite
cannot distinguish "correctly restricted" from "entitled to nothing".

**Criterion 6 is not a precaution, and WHICH FUNCTION YOU CALL decides whether
it works.**

Gate on `perimeter_report()`. NEVER on `perimeter_assert()`.

`perimeter_assert()` is violation-only by contract: on a target lacking
the platform roles its filters match nothing, so it returns zero rows, and
zero rows reads as clean. That is the exact fail-open this criterion exists
to catch, so a rehearsal that gates on `perimeter_assert()` records a PASS
precisely where it should refuse.

`perimeter_report()` declares its own evaluability. Read BOTH halves, and
read them differently depending on which rehearsal you are running:

    CONTINUITY   (platform roles supplied)
      PASS   evaluation_status = 'evaluated' AND violation_count = 0
      VOID   anything else

    SOVEREIGNTY  (platform roles withheld)
      PASS   evaluation_status <> 'evaluated' AND violation_count IS NULL
             the report correctly refuses, having nothing it can check
      VOID   evaluation_status = 'evaluated', or a non-NULL violation_count
             the checker is claiming an answer it cannot have

`violation_count` is NULL rather than 0 when nothing could be checked. That
is the only value that fails closed: `NULL = 0` evaluates to NULL, so a caller
gating on it refuses instead of proceeding. Returning 0 would hand a clean
answer to exactly the target that could not produce one. Do not coalesce it.

**Criterion 7 exists because 5 is not sufficient.** A positive control can be
genuine and still exercise only ONE DISJUNCT of a two-disjunct predicate. If
an access predicate is `owner OR shared` and every record is shared, the
owner branch has never been evaluated and criterion 5 passes identically
against a build where it is broken. Both clauses of 7 are load-bearing:

- private AND owned by another  -> only visibility can deny it
- reader HOLDS the scope        -> scope cannot be the reason for denial

Drop either and the denial passes for the wrong reason.

**Verify as a constrained principal, not as the owner.** A superuser or table
owner bypasses row-level security and sees everything, so a restore verified
that way proves almost nothing about the access model.

## 7. Findings

State each finding with the measurement behind it.

**Counts taken from a cascading failure are LOWER BOUNDS.** When early
failures prevent objects from existing, later checks against those objects
fail for the earlier reason and are never reached. A census taken mid-cascade
measures what survived long enough to be tested, not what is there. Re-run
with the cascade cleared before treating any count as characterising a
dependency surface.

## 8. Actions

Real coupling is fixed in the schema, not documented around in the runbook.

- [ ] Schema change required
- [ ] Runbook change required
- [ ] Declared-requirements manifest change required

## 9. Outcome

- Result, duration, next rehearsal due
- For a SOVEREIGNTY rehearsal, the strongest possible outcome is a
  ZERO-MUTATION REFUSAL: requirements enumerated, unmet ones listed, target
  left unchanged. Failing loudly after partially mutating the target is a
  weaker result and should be recorded as interim.
