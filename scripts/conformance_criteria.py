#!/usr/bin/env python3
"""Run a conformance suite that requires grants, demonstrations, and coverage.

The normative rules are SMP custody layer section 12, "Criterion shape."
This runner executes those rules on a local fixture. It does not read a
suite-level verdict string, and it does not contact a database.
"""

from __future__ import annotations

import argparse
import copy
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


EXIT_CODE = {"full": 0, "fail": 1, "abort": 2, "partial": 3}
GRANT_REASONS = {"owner-disjunct", "shared-disjunct"}
DENIED_WITHOUT_POLICY = {"identity-unresolved", "request-did-not-reach-policy"}
SPEC_MUTATIONS = {"omit_review_field"}
FIXTURE_MUTATIONS = {
    "table_privilege",
    "identity_resolved",
    "record_visibility",
    "record_owner",
    "hold_scope",
    "drop_scope",
    "host_identifiers_remove",
}
EVALUATED_STATUSES = {"PASS", "FAIL"}


class FixtureConstructionError(Exception):
    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


class UnknownMutation(Exception):
    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


@dataclass
class Record:
    id: str
    scope: str
    owner: str
    visibility: str


@dataclass
class Fixture:
    id: str
    table_privilege: bool
    principals: dict[str, set[str]]
    records: dict[str, Record]
    identities: dict[str, bool]
    host_identifiers: set[str]
    host_grants: dict[str, int]


@dataclass
class Decision:
    visible: bool
    reason: str
    disjunct: str | None = None


@dataclass
class CriterionResult:
    id: str
    kind: str
    status: str
    reason: str
    evidence: bool
    examined: dict[str, Any]
    observed_if_trusted: str | None = None
    zero_row_would_pass: bool | None = None


@dataclass
class DemonstrationResult:
    id: str
    status: str
    reason: str
    observed_status: str
    observed_reason: str


@dataclass
class RunReport:
    suite_id: str
    defined: int
    evaluated: int
    passed: int
    skipped: int
    full_conformance: bool
    exit_class: str
    aborted_reason: str | None
    shape_errors: list[str]
    criteria: list[CriterionResult]
    demonstrations: list[DemonstrationResult]
    execution_order: list[str]
    characterizing_counts: bool
    demonstrations_defined: int = 0
    demonstrations_executed: int = 0
    demonstrations_matched: int = 0


def construct_fixture(spec: dict[str, Any]) -> Fixture:
    """Build a fixture or abort. A rejected binding fails the whole fixture."""
    bindings = spec.get("identity_bindings")
    principals_in = spec.get("principals")
    records_in = spec.get("records")
    if not isinstance(bindings, list) or not bindings:
        raise FixtureConstructionError("identity-bindings-missing")
    if not isinstance(principals_in, list) or not principals_in:
        raise FixtureConstructionError("principals-missing")
    if not isinstance(records_in, list) or not records_in:
        raise FixtureConstructionError("records-missing")
    if not isinstance(spec.get("table_privilege"), bool):
        raise FixtureConstructionError("table-privilege-missing")
    if not isinstance(spec.get("host_identifiers"), list):
        raise FixtureConstructionError("host-identifiers-missing")

    principals: dict[str, set[str]] = {}
    for row in principals_in:
        principal_id = row.get("id")
        scopes = row.get("scopes")
        if not isinstance(principal_id, str) or not principal_id:
            raise FixtureConstructionError("principal-id-missing")
        if not isinstance(scopes, list) or not all(isinstance(item, str) and item for item in scopes):
            raise FixtureConstructionError("principal-scopes-missing")
        principals[principal_id] = set(scopes)

    identities: dict[str, bool] = {}
    for binding in bindings:
        principal = binding.get("principal")
        if not isinstance(principal, str) or not principal:
            raise FixtureConstructionError("required-review-field-omitted")
        review_field = binding.get("review_field")
        if not isinstance(review_field, str) or not review_field.strip():
            raise FixtureConstructionError("required-review-field-omitted")
        if principal not in principals:
            raise FixtureConstructionError("binding-without-principal")
        if not isinstance(binding.get("resolved"), bool):
            raise FixtureConstructionError("identity-resolved-missing")
        identities[principal] = binding["resolved"]

    records: dict[str, Record] = {}
    for row in records_in:
        record_id = row.get("id")
        visibility = row.get("visibility")
        if not isinstance(record_id, str) or not record_id:
            raise FixtureConstructionError("record-id-missing")
        if visibility not in {"private", "shared"}:
            raise FixtureConstructionError("record-visibility-unknown")
        if not isinstance(row.get("scope"), str) or not isinstance(row.get("owner"), str):
            raise FixtureConstructionError("record-fields-missing")
        records[record_id] = Record(record_id, row["scope"], row["owner"], visibility)

    host_grants_in = spec.get("host_grants") or {}
    if not isinstance(host_grants_in, dict):
        raise FixtureConstructionError("host-grants-invalid")
    host_grants = {str(key): int(value) for key, value in host_grants_in.items()}
    return Fixture(
        id=str(spec.get("id") or ""),
        table_privilege=spec["table_privilege"],
        principals=principals,
        records=records,
        identities=identities,
        host_identifiers=set(spec["host_identifiers"]),
        host_grants=host_grants,
    )


def decide(fixture: Fixture, principal: str, record_id: str) -> Decision:
    record = fixture.records[record_id]
    if not fixture.identities.get(principal, False):
        return Decision(False, "identity-unresolved")
    if not fixture.table_privilege:
        return Decision(False, "request-did-not-reach-policy")
    holds_scope = record.scope in fixture.principals.get(principal, set())
    if record.owner == principal:
        return Decision(True, "owner-disjunct", "owner")
    if record.visibility == "shared" and holds_scope:
        return Decision(True, "shared-disjunct", "shared")
    if record.visibility == "private" and record.owner != principal and holds_scope:
        return Decision(False, "visibility-disjunct-denied", "visibility")
    if not holds_scope:
        return Decision(False, "scope-denied")
    return Decision(False, "scope-denied")


def _examined(fixture: Fixture, criterion: dict[str, Any], decision: Decision) -> dict[str, Any]:
    record = fixture.records[criterion["object"]]
    return {
        "principal": criterion["subject"],
        "record": criterion["object"],
        "decision_reason": decision.reason,
        "disjunct": decision.disjunct,
        "holds_scope": record.scope in fixture.principals.get(criterion["subject"], set()),
        "visibility": record.visibility,
        "owner": record.owner,
    }


def admit_result(
    status: str,
    reason: str,
    examined: dict[str, Any],
    kind: str,
) -> tuple[str, str, dict[str, Any], bool]:
    if status == "PASS" and not _examined_ok(kind, examined):
        return "FAIL", "pass-without-examined-record", examined, False
    return status, reason, examined, status == "PASS"


def _examined_ok(kind: str, examined: dict[str, Any]) -> bool:
    if not isinstance(examined, dict) or not examined:
        return False
    if kind in {"grant", "denial"}:
        return bool(
            examined.get("principal")
            and examined.get("record")
            and examined.get("decision_reason")
        )
    if kind == "host_filter":
        identifiers = examined.get("identifiers")
        return isinstance(identifiers, list) and bool(identifiers)
    return False


def run_grant(
    fixture: Fixture, criterion: dict[str, Any]
) -> tuple[str, str, dict[str, Any]]:
    decision = decide(fixture, criterion["subject"], criterion["object"])
    examined = _examined(fixture, criterion, decision)
    if decision.visible and decision.reason == criterion["expected_reason"]:
        return "PASS", decision.reason, examined
    if not decision.visible:
        return "FAIL", decision.reason, examined
    return "FAIL", f"wrong-reason:{decision.reason}", examined


def run_denial(
    fixture: Fixture, criterion: dict[str, Any]
) -> tuple[str, str, dict[str, Any]]:
    decision = decide(fixture, criterion["subject"], criterion["object"])
    examined = _examined(fixture, criterion, decision)
    if criterion.get("isolates") == "visibility":
        preconditions = (
            examined["visibility"] == "private"
            and examined["owner"] != criterion["subject"]
            and examined["holds_scope"] is True
        )
        if decision.visible:
            return "FAIL", "denial-not-enforced", examined
        if not preconditions:
            return "FAIL", "denial-precondition-not-met", examined
        if decision.reason in DENIED_WITHOUT_POLICY:
            return "FAIL", f"wrong-reason:{decision.reason}", examined
        if decision.reason != criterion["expected_reason"]:
            return "FAIL", f"wrong-reason:{decision.reason}", examined
        return "PASS", decision.reason, examined
    if decision.reason in DENIED_WITHOUT_POLICY:
        return "FAIL", f"wrong-reason:{decision.reason}", examined
    if decision.visible:
        return "FAIL", "denial-not-enforced", examined
    if decision.reason != criterion["expected_reason"]:
        return "FAIL", f"wrong-reason:{decision.reason}", examined
    return "PASS", decision.reason, examined


def run_host_filter(
    fixture: Fixture, criterion: dict[str, Any]
) -> tuple[str, str, dict[str, Any]]:
    """Assert declared identifiers exist before reading grant rows.

    Zero grant rows are a real result only after that assertion. A missing
    identifier is UNSUPPORTED and never an empty PASS.
    """
    required = list(criterion["required_identifiers"])
    missing = [identifier for identifier in required if identifier not in fixture.host_identifiers]
    if missing:
        return (
            "UNSUPPORTED",
            "required-identifier-absent",
            {"missing": missing, "identifiers": []},
        )
    examined = {
        "identifiers": required,
        "grant_counts": {
            identifier: fixture.host_grants.get(identifier, 0) for identifier in required
        },
    }
    return "PASS", "identifiers-present-and-examined", examined


def execute_check(fixture: Fixture, criterion: dict[str, Any]) -> CriterionResult:
    kind = criterion["kind"]
    if kind == "grant":
        status, reason, examined = run_grant(fixture, criterion)
    elif kind == "denial":
        status, reason, examined = run_denial(fixture, criterion)
    elif kind == "host_filter":
        status, reason, examined = run_host_filter(fixture, criterion)
    else:
        status, reason, examined = "FAIL", "unknown-criterion-kind", {}
    decision = None
    if kind in {"grant", "denial"}:
        decision = decide(fixture, criterion["subject"], criterion["object"])
    status, reason, examined, evidence = admit_result(status, reason, examined, kind)
    return CriterionResult(
        id=criterion["id"],
        kind=kind,
        status=status,
        reason=reason,
        evidence=evidence,
        examined=examined,
        zero_row_would_pass=None if decision is None else not decision.visible,
    )


def apply_spec_mutation(spec: dict[str, Any], mutation: dict[str, Any]) -> dict[str, Any]:
    unknown = set(mutation) - SPEC_MUTATIONS
    if unknown:
        raise UnknownMutation(f"unknown-mutation:{sorted(unknown)[0]}")
    mutated = copy.deepcopy(spec)
    if "omit_review_field" in mutation:
        principal = mutation["omit_review_field"]
        for binding in mutated["identity_bindings"]:
            if binding.get("principal") == principal:
                binding.pop("review_field", None)
    return mutated


def apply_fixture_mutation(fixture: Fixture, mutation: dict[str, Any]) -> None:
    unknown = set(mutation) - FIXTURE_MUTATIONS
    if unknown:
        raise UnknownMutation(f"unknown-mutation:{sorted(unknown)[0]}")
    if "table_privilege" in mutation:
        fixture.table_privilege = bool(mutation["table_privilege"])
    if "identity_resolved" in mutation:
        for principal, resolved in mutation["identity_resolved"].items():
            if principal not in fixture.identities:
                raise KeyError(principal)
            fixture.identities[principal] = bool(resolved)
    if "record_visibility" in mutation:
        for record_id, visibility in mutation["record_visibility"].items():
            fixture.records[record_id].visibility = visibility
    if "record_owner" in mutation:
        for record_id, owner in mutation["record_owner"].items():
            fixture.records[record_id].owner = owner
    if "hold_scope" in mutation:
        change = mutation["hold_scope"]
        fixture.principals[change["principal"]].add(change["scope"])
    if "drop_scope" in mutation:
        change = mutation["drop_scope"]
        fixture.principals[change["principal"]].discard(change["scope"])
    if "host_identifiers_remove" in mutation:
        for identifier in mutation["host_identifiers_remove"]:
            fixture.host_identifiers.discard(identifier)


def _criterion_id(criterion: dict[str, Any], index: int) -> str:
    identifier = criterion.get("id")
    if isinstance(identifier, str) and identifier:
        return identifier
    return f"criterion-{index}"


def validate_shape(suite: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    fixture = suite.get("fixture")
    fixture_id = fixture.get("id") if isinstance(fixture, dict) else None
    if not isinstance(fixture_id, str) or not fixture_id:
        errors.append("suite fixture is missing an id")
    criteria = suite.get("criteria")
    if not isinstance(criteria, list) or not criteria:
        errors.append("suite defines no criteria")
        criteria = [] if not isinstance(criteria, list) else criteria
    demonstrations = suite.get("demonstrations")
    if not isinstance(demonstrations, list):
        errors.append("suite defines no demonstrations")
        demonstrations = []

    by_id: dict[str, dict[str, Any]] = {}
    for index, criterion in enumerate(criteria):
        if not isinstance(criterion, dict):
            errors.append(f"criterion {index} is not an object")
            continue
        identifier = _criterion_id(criterion, index)
        if identifier in by_id:
            errors.append(f"{identifier}: duplicate criterion id")
        by_id[identifier] = criterion
        kind = criterion.get("kind")
        if kind not in {"grant", "denial", "host_filter"}:
            errors.append(f"{identifier}: unknown criterion kind")
        if criterion.get("fixture_id") != fixture_id:
            errors.append(f"{identifier}: criterion fixture does not match the suite fixture")
        if "skip" in criterion and (
            not isinstance(criterion.get("skip"), str) or not criterion.get("skip", "").strip()
        ):
            errors.append(f"{identifier}: skip requires a reason")
        if kind == "grant" and criterion.get("expected_reason") not in GRANT_REASONS:
            errors.append(f"{identifier}: grant must expect an entitled receive reason")
        if kind == "denial" and not isinstance(criterion.get("expected_reason"), str):
            errors.append(f"{identifier}: denial must name an expected reason")
        if kind == "host_filter":
            required = criterion.get("required_identifiers")
            if (
                not isinstance(required, list)
                or not required
                or not all(isinstance(item, str) and item for item in required)
            ):
                errors.append(f"{identifier}: host filter must declare required identifiers")

    demos_for: dict[str, list[dict[str, Any]]] = {}
    seen_demo_ids: set[str] = set()
    construction_demos = 0
    for index, demo in enumerate(demonstrations):
        if not isinstance(demo, dict):
            errors.append(f"demonstration {index} is not an object")
            continue
        demo_id = demo.get("id")
        if not isinstance(demo_id, str) or not demo_id:
            errors.append(f"demonstration {index} is missing an id")
            demo_id = f"demonstration-{index}"
        if demo_id in seen_demo_ids:
            errors.append(f"{demo_id}: duplicate demonstration id")
        seen_demo_ids.add(demo_id)
        if demo.get("expected_status") not in {"FAIL", "UNSUPPORTED", "ABORT"}:
            errors.append(f"{demo_id}: demonstration must expect FAIL, UNSUPPORTED, or ABORT")
        if not isinstance(demo.get("expected_reason"), str) or not demo.get("expected_reason"):
            errors.append(f"{demo_id}: demonstration must name an expected reason")
        if not isinstance(demo.get("mutation"), dict):
            errors.append(f"{demo_id}: demonstration mutation must be an object")
        if demo.get("kind") == "fixture_construction":
            construction_demos += 1
            if demo.get("expected_status") != "ABORT":
                errors.append(f"{demo_id}: fixture construction demonstration must expect ABORT")
            continue
        check_id = demo.get("check_id")
        if check_id not in by_id:
            errors.append(f"{demo_id}: demonstration does not name a criterion")
            continue
        demos_for.setdefault(str(check_id), []).append(demo)

    if construction_demos == 0:
        errors.append("suite does not execute a fixture-construction failure")

    for identifier, criterion in by_id.items():
        if criterion.get("kind") == "denial":
            pair = by_id.get(str(criterion.get("pairs_with")))
            if (
                pair is None
                or pair.get("kind") != "grant"
                or pair.get("fixture_id") != criterion.get("fixture_id")
            ):
                errors.append(
                    f"{identifier}: denial is not paired with a grant on the same fixture"
                )
            elif pair.get("skip"):
                errors.append(f"{identifier}: denial is paired with a grant that does not run")
            if criterion.get("isolates") == "visibility" and pair is not None:
                if pair.get("subject") != criterion.get("subject"):
                    errors.append(
                        f"{identifier}: isolating denial must pair with the same principal's grant"
                    )
                if pair.get("expected_reason") != "shared-disjunct":
                    errors.append(
                        f"{identifier}: isolating denial must pair with a shared-disjunct grant"
                    )
        if criterion.get("skip"):
            continue
        if identifier not in demos_for:
            errors.append(f"{identifier}: no demonstration is executed for this check")
    return errors


def _ordered_criteria(criteria: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grants = [item for item in criteria if item.get("kind") == "grant"]
    middle = [item for item in criteria if item.get("kind") not in {"grant", "denial"}]
    denials = [item for item in criteria if item.get("kind") == "denial"]
    return grants + middle + denials


def _grants_passed(
    results: list[CriterionResult],
    criteria_by_id: dict[str, dict[str, Any]],
    fixture_id: str,
) -> bool:
    grant_results = [
        result
        for result in results
        if result.kind == "grant" and criteria_by_id[result.id].get("fixture_id") == fixture_id
    ]
    return bool(grant_results) and all(result.status == "PASS" for result in grant_results)


def _finish(report: RunReport) -> RunReport:
    report.evaluated = sum(result.status in EVALUATED_STATUSES for result in report.criteria)
    report.passed = sum(result.status == "PASS" for result in report.criteria)
    report.skipped = sum(result.status == "SKIPPED" for result in report.criteria)
    report.demonstrations_matched = sum(
        result.status == "MATCH" for result in report.demonstrations
    )
    report.demonstrations_executed = len(report.demonstrations)
    return report


def _characterizing(criteria: list[CriterionResult]) -> bool:
    grants = [result for result in criteria if result.kind == "grant"]
    if not grants or any(result.status != "PASS" for result in grants):
        return False
    host_filters = [result for result in criteria if result.kind == "host_filter"]
    return not any(result.status in {"UNSUPPORTED", "FAIL"} for result in host_filters)


def _classify(report: RunReport) -> str:
    if report.aborted_reason:
        return "abort"
    if report.shape_errors:
        return "fail"
    if any(result.status in {"FAIL", "UNSUPPORTED", "NOT_EVIDENCE"} for result in report.criteria):
        return "fail"
    if any(result.status != "MATCH" for result in report.demonstrations):
        return "fail"
    if report.demonstrations_defined != len(report.demonstrations):
        return "fail"
    if any(result.status == "SKIPPED" for result in report.criteria):
        return "partial"
    if report.defined > 0 and report.defined == report.evaluated == report.passed:
        grants = [result for result in report.criteria if result.kind == "grant"]
        if grants and not report.characterizing_counts:
            return "fail"
        return "full"
    return "fail"


def _unscored(criteria: list[dict[str, Any]], status: str, reason: str) -> list[CriterionResult]:
    results: list[CriterionResult] = []
    for index, criterion in enumerate(criteria):
        if not isinstance(criterion, dict):
            continue
        results.append(
            CriterionResult(
                id=_criterion_id(criterion, index),
                kind=str(criterion.get("kind") or "unknown"),
                status=status,
                reason=reason,
                evidence=False,
                examined={},
            )
        )
    return results


def _score_demonstration(
    demo: dict[str, Any],
    fixture_spec: dict[str, Any],
    fixture: Fixture,
    criteria_by_id: dict[str, dict[str, Any]],
) -> DemonstrationResult:
    demo_id = str(demo["id"])
    expected_status = str(demo["expected_status"])
    expected_reason = str(demo["expected_reason"])
    mutation = demo["mutation"]
    try:
        if demo.get("kind") == "fixture_construction":
            try:
                construct_fixture(apply_spec_mutation(fixture_spec, mutation))
            except FixtureConstructionError as exc:
                observed_status, observed_reason = "ABORT", exc.reason
            else:
                observed_status, observed_reason = "CONSTRUCTED", "fixture-constructed"
        else:
            mutated = copy.deepcopy(fixture)
            apply_fixture_mutation(mutated, mutation)
            observed = execute_check(mutated, criteria_by_id[demo["check_id"]])
            observed_status, observed_reason = observed.status, observed.reason
    except UnknownMutation as exc:
        observed_status, observed_reason = "ERROR", exc.reason
    except Exception as exc:
        observed_status, observed_reason = "ERROR", type(exc).__name__

    if observed_status == expected_status and observed_reason == expected_reason:
        status, reason = "MATCH", "matched"
    elif observed_status == "PASS":
        status, reason = "FAIL", "check-did-not-fail"
    elif observed_status == expected_status:
        status, reason = "FAIL", "wrong-reason"
    else:
        status, reason = "FAIL", "demonstration-mismatch"
    return DemonstrationResult(demo_id, status, reason, observed_status, observed_reason)


def run_suite(suite: dict[str, Any]) -> RunReport:
    """Execute one suite. The suite object is copied and is not mutated."""
    suite = copy.deepcopy(suite)
    # A literal verdict cannot satisfy the suite. Scoring ignores it.
    suite.pop("verdict", None)
    suite_id = str(suite.get("suite_id") or "unspecified")
    raw_criteria = suite.get("criteria")
    criteria = [item for item in raw_criteria if isinstance(item, dict)] if isinstance(raw_criteria, list) else []
    demonstrations = suite.get("demonstrations")
    if not isinstance(demonstrations, list):
        demonstrations = []
    shape_errors = validate_shape(suite)
    report = RunReport(
        suite_id=suite_id,
        defined=len(criteria),
        evaluated=0,
        passed=0,
        skipped=0,
        full_conformance=False,
        exit_class="fail",
        aborted_reason=None,
        shape_errors=shape_errors,
        criteria=[],
        demonstrations=[],
        execution_order=[],
        characterizing_counts=False,
        demonstrations_defined=len(demonstrations),
    )
    if shape_errors:
        report.criteria = _unscored(criteria, "UNEVALUATED", "suite-shape-invalid")
        return _finish(report)

    try:
        fixture = construct_fixture(suite["fixture"])
    except FixtureConstructionError as exc:
        report.aborted_reason = exc.reason
        report.criteria = _unscored(criteria, "ABORTED", exc.reason)
        report.exit_class = "abort"
        return _finish(report)
    except Exception:
        report.aborted_reason = "fixture-construction-failed"
        report.criteria = _unscored(criteria, "ABORTED", "fixture-construction-failed")
        report.exit_class = "abort"
        return _finish(report)

    criteria_by_id = {criterion["id"]: criterion for criterion in criteria}
    ordered = _ordered_criteria(criteria)
    for criterion in ordered:
        report.execution_order.append(criterion["id"])
        if criterion.get("skip"):
            report.criteria.append(
                CriterionResult(
                    id=criterion["id"],
                    kind=criterion["kind"],
                    status="SKIPPED",
                    reason=str(criterion["skip"]),
                    evidence=False,
                    examined={},
                )
            )
            continue
        if criterion["kind"] == "denial" and not _grants_passed(
            report.criteria, criteria_by_id, criterion["fixture_id"]
        ):
            trusted = execute_check(fixture, criterion)
            report.criteria.append(
                CriterionResult(
                    id=criterion["id"],
                    kind="denial",
                    status="NOT_EVIDENCE",
                    reason="positive-controls-failed",
                    evidence=False,
                    examined=trusted.examined,
                    observed_if_trusted=f"{trusted.status}:{trusted.reason}",
                    zero_row_would_pass=trusted.zero_row_would_pass,
                )
            )
            continue
        report.criteria.append(execute_check(fixture, criterion))

    for demo in demonstrations:
        report.demonstrations.append(
            _score_demonstration(demo, suite["fixture"], fixture, criteria_by_id)
        )
    report.characterizing_counts = _characterizing(report.criteria)
    report.exit_class = "pending"
    report = _finish(report)
    report.exit_class = _classify(report)
    report.full_conformance = report.exit_class == "full"
    return report


def _format_examined(examined: dict[str, Any]) -> str:
    if not examined:
        return "examined="
    parts: list[str] = []
    for key in ("principal", "record", "decision_reason", "identifiers"):
        if key not in examined:
            continue
        value = examined[key]
        if isinstance(value, list):
            value = ",".join(str(item) for item in value)
        parts.append(f"{key}:{value}")
    grant_counts = examined.get("grant_counts")
    if isinstance(grant_counts, dict) and grant_counts:
        rendered = ",".join(f"{key}={grant_counts[key]}" for key in grant_counts)
        parts.append(f"grant_counts:{rendered}")
    if not parts:
        parts.append("present")
    return "examined=" + ",".join(parts)


def render(report: RunReport) -> str:
    lines = [
        f"SUITE {report.suite_id}",
        (
            f"CRITERIA defined={report.defined} evaluated={report.evaluated} "
            f"passed={report.passed} skipped={report.skipped}"
        ),
        (
            f"DEMONSTRATIONS defined={report.demonstrations_defined} "
            f"executed={report.demonstrations_executed} matched={report.demonstrations_matched}"
        ),
        f"COUNTS characterizing={'yes' if report.characterizing_counts else 'no'}",
        f"CONFORMANCE {report.exit_class}",
    ]
    if report.aborted_reason:
        lines.append(f"ABORTED {report.aborted_reason}")
    for error in report.shape_errors:
        lines.append(f"SHAPE {error}")
    for criterion in report.criteria:
        line = (
            f"{criterion.id} {criterion.status} {criterion.reason} "
            f"{_format_examined(criterion.examined)}"
        )
        if criterion.status == "NOT_EVIDENCE":
            zero_row = "yes" if criterion.zero_row_would_pass else "no"
            line += (
                f" observed_if_trusted={criterion.observed_if_trusted} "
                f"zero_row_would_pass={zero_row}"
            )
        lines.append(line)
    for demo in report.demonstrations:
        lines.append(
            f"{demo.id} {demo.status} {demo.observed_status} {demo.observed_reason}"
        )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("suite", type=Path)
    args = parser.parse_args(argv)
    try:
        suite = json.loads(args.suite.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"suite could not be read: {type(exc).__name__}", file=sys.stderr)
        return EXIT_CODE["fail"]
    if not isinstance(suite, dict):
        print("suite must be a JSON object", file=sys.stderr)
        return EXIT_CODE["fail"]
    report = run_suite(suite)
    sys.stdout.write(render(report))
    return EXIT_CODE[report.exit_class]


if __name__ == "__main__":
    raise SystemExit(main())
