"""The criterion-shape runner must execute grants, broken inputs, and coverage."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SUITE_PATH = REPO_ROOT / "fixtures" / "conformance" / "criterion_shape_suite.json"
SCRIPT_PATH = REPO_ROOT / "scripts" / "conformance_criteria.py"
SHELL_PATH = REPO_ROOT / "scripts" / "validate_conformance_criteria.sh"

sys.path.insert(0, str(REPO_ROOT))

from scripts.conformance_criteria import (  # noqa: E402
    EXIT_CODE,
    admit_result,
    construct_fixture,
    execute_check,
    render,
    run_suite,
)


def load_suite() -> dict:
    return json.loads(SUITE_PATH.read_text(encoding="utf-8"))


def criterion(suite: dict, identifier: str) -> dict:
    return next(item for item in suite["criteria"] if item["id"] == identifier)


class CriterionShapeTests(unittest.TestCase):
    def test_reference_suite_reports_full_conformance(self) -> None:
        report = run_suite(load_suite())
        self.assertEqual(report.exit_class, "full")
        self.assertTrue(report.full_conformance)
        self.assertGreaterEqual(report.defined, 6)
        self.assertEqual(report.defined, report.evaluated)
        self.assertEqual(report.evaluated, report.passed)
        self.assertEqual(report.skipped, 0)
        self.assertEqual(report.demonstrations_defined, report.demonstrations_executed)
        self.assertEqual(report.demonstrations_executed, report.demonstrations_matched)
        self.assertTrue(report.characterizing_counts)
        kinds = {item.kind for item in report.criteria}
        self.assertIn("grant", kinds)
        self.assertIn("denial", kinds)
        self.assertTrue(all(item.evidence for item in report.criteria))
        text = render(report)
        self.assertIn(
            f"CRITERIA defined={report.defined} evaluated={report.evaluated} passed={report.passed}",
            text,
        )
        self.assertIn("CONFORMANCE full", text)
        self.assertNotIn("SUITE_RESULT", text)

    def test_reference_execution_order_runs_grants_before_denials(self) -> None:
        suite = load_suite()
        suite["criteria"].reverse()
        report = run_suite(suite)
        grant_at = max(
            report.execution_order.index(item.id)
            for item in report.criteria
            if item.kind == "grant"
        )
        denial_at = min(
            report.execution_order.index(item.id)
            for item in report.criteria
            if item.kind == "denial"
        )
        self.assertLess(grant_at, denial_at)
        self.assertLess(report.execution_order.index("H1"), denial_at)
        self.assertEqual(report.exit_class, "full")

    def test_reference_executes_broken_inputs_for_the_right_reason(self) -> None:
        report = run_suite(load_suite())
        by_id = {item.id: item for item in report.demonstrations}
        self.assertEqual(by_id["demo-partial-fixture"].status, "MATCH")
        self.assertEqual(by_id["demo-partial-fixture"].observed_status, "ABORT")
        self.assertEqual(
            by_id["demo-partial-fixture"].observed_reason,
            "required-review-field-omitted",
        )
        self.assertEqual(by_id["demo-h1-absent"].observed_status, "UNSUPPORTED")
        self.assertEqual(by_id["demo-d1-identity"].observed_reason, "wrong-reason:identity-unresolved")
        self.assertEqual(by_id["demo-d1-privilege"].observed_reason, "wrong-reason:request-did-not-reach-policy")
        self.assertEqual(by_id["demo-d2-missing-scope"].observed_reason, "denial-precondition-not-met")
        self.assertEqual(by_id["demo-g1-owner"].observed_reason, "visibility-disjunct-denied")
        self.assertTrue(all(item.status == "MATCH" for item in report.demonstrations))
        self.assertGreater(len(report.demonstrations), len(report.criteria))

    def test_cli_exits_zero_and_prints_coverage_numbers(self) -> None:
        result = subprocess.run(
            [sys.executable, str(SCRIPT_PATH), str(SUITE_PATH)],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        coverage = next(line for line in result.stdout.splitlines() if line.startswith("CRITERIA "))
        parts = dict(item.split("=", 1) for item in coverage.split()[1:])
        self.assertEqual(parts["defined"], parts["evaluated"])
        self.assertEqual(parts["evaluated"], parts["passed"])
        self.assertIn("CONFORMANCE full", result.stdout)

    def test_cli_abort_and_partial_use_distinct_exit_statuses(self) -> None:
        aborted = load_suite()
        aborted["fixture"]["identity_bindings"][0].pop("review_field")
        partial = load_suite()
        partial["criteria"].append(
            {
                "id": "S1",
                "kind": "host_filter",
                "fixture_id": "scope-bound-access",
                "required_identifiers": ["authenticated"],
                "skip": "optional-platform-role-not-in-this-profile",
            }
        )
        abort_result = _run_cli(aborted)
        partial_result = _run_cli(partial)
        self.assertEqual(abort_result.returncode, EXIT_CODE["abort"])
        self.assertEqual(partial_result.returncode, EXIT_CODE["partial"])
        self.assertNotEqual(abort_result.returncode, partial_result.returncode)
        self.assertNotEqual(abort_result.returncode, 0)
        self.assertNotEqual(partial_result.returncode, 0)
        self.assertIn("CONFORMANCE abort", abort_result.stdout)
        self.assertIn("CONFORMANCE partial", partial_result.stdout)
        self.assertNotIn("D1 PASS", abort_result.stdout)
        self.assertIn("S1 SKIPPED", partial_result.stdout)
        self.assertNotIn("CONFORMANCE full", partial_result.stdout)

    def test_failed_grants_are_not_denial_evidence(self) -> None:
        suite = load_suite()
        for binding in suite["fixture"]["identity_bindings"]:
            binding["resolved"] = False
        report = run_suite(suite)
        self.assertEqual(report.exit_class, "fail")
        self.assertFalse(report.full_conformance)
        self.assertFalse(report.characterizing_counts)
        denials = [item for item in report.criteria if item.kind == "denial"]
        self.assertGreaterEqual(len(denials), 2)
        for denial in denials:
            self.assertEqual(denial.status, "NOT_EVIDENCE")
            self.assertEqual(denial.reason, "positive-controls-failed")
            self.assertFalse(denial.evidence)
            self.assertTrue(denial.zero_row_would_pass)
            self.assertNotEqual(denial.status, "PASS")
        self.assertLess(report.passed, report.defined)
        self.assertNotEqual(report.evaluated, report.defined)
        text = render(report)
        self.assertIn("zero_row_would_pass=yes", text)
        self.assertNotIn("CONFORMANCE full", text)

    def test_privilege_gap_is_not_denial_evidence(self) -> None:
        suite = load_suite()
        suite["fixture"]["table_privilege"] = False
        report = run_suite(suite)
        grants = [item for item in report.criteria if item.kind == "grant"]
        self.assertTrue(all(item.status == "FAIL" for item in grants))
        self.assertTrue(
            all(item.reason == "request-did-not-reach-policy" for item in grants)
        )
        denials = [item for item in report.criteria if item.kind == "denial"]
        self.assertTrue(all(item.status == "NOT_EVIDENCE" for item in denials))
        self.assertFalse(report.full_conformance)

    def test_partial_fixture_aborts_before_denials(self) -> None:
        suite = load_suite()
        suite["fixture"]["identity_bindings"][0].pop("review_field")
        report = run_suite(suite)
        self.assertEqual(report.exit_class, "abort")
        self.assertEqual(report.aborted_reason, "required-review-field-omitted")
        self.assertEqual(report.evaluated, 0)
        self.assertEqual(report.passed, 0)
        self.assertEqual(report.execution_order, [])
        self.assertEqual(report.demonstrations, [])
        self.assertTrue(report.criteria)
        self.assertTrue(all(item.status == "ABORTED" for item in report.criteria))
        self.assertNotIn("PASS", [item.status for item in report.criteria])

    def test_missing_demonstration_fails_the_suite(self) -> None:
        suite = load_suite()
        suite["demonstrations"] = [
            demo for demo in suite["demonstrations"] if demo.get("check_id") != "D1"
        ]
        report = run_suite(suite)
        self.assertEqual(report.exit_class, "fail")
        self.assertFalse(report.full_conformance)
        self.assertEqual(report.evaluated, 0)
        self.assertEqual(report.passed, 0)
        self.assertTrue(
            any("D1: no demonstration is executed" in error for error in report.shape_errors)
        )
        self.assertTrue(all(item.status == "UNEVALUATED" for item in report.criteria))

    def test_unpaired_denial_fails_the_suite(self) -> None:
        suite = load_suite()
        criterion(suite, "D1").pop("pairs_with")
        report = run_suite(suite)
        self.assertEqual(report.exit_class, "fail")
        self.assertEqual(report.passed, 0)
        self.assertTrue(
            any("D1: denial is not paired with a grant" in error for error in report.shape_errors)
        )

    def test_wrong_reason_fails_the_run(self) -> None:
        suite = load_suite()
        demo = next(item for item in suite["demonstrations"] if item["id"] == "demo-g1-privilege")
        demo["expected_reason"] = "identity-unresolved"
        report = run_suite(suite)
        observed = next(item for item in report.demonstrations if item.id == "demo-g1-privilege")
        self.assertEqual(observed.status, "FAIL")
        self.assertEqual(observed.reason, "wrong-reason")
        self.assertEqual(observed.observed_reason, "request-did-not-reach-policy")
        self.assertEqual(report.exit_class, "fail")
        self.assertFalse(report.full_conformance)

    def test_demonstration_that_still_passes_fails_the_run(self) -> None:
        suite = load_suite()
        suite["demonstrations"].append(
            {
                "id": "demo-g1-noop",
                "check_id": "G1",
                "mutation": {},
                "expected_status": "FAIL",
                "expected_reason": "request-did-not-reach-policy",
            }
        )
        report = run_suite(suite)
        observed = next(item for item in report.demonstrations if item.id == "demo-g1-noop")
        self.assertEqual(observed.status, "FAIL")
        self.assertEqual(observed.reason, "check-did-not-fail")
        self.assertEqual(observed.observed_status, "PASS")
        self.assertEqual(report.exit_class, "fail")

    def test_absent_host_identifier_is_unsupported_not_pass(self) -> None:
        suite = load_suite()
        suite["fixture"]["host_identifiers"].remove("authenticated")
        report = run_suite(suite)
        host = next(item for item in report.criteria if item.id == "H1")
        self.assertEqual(host.status, "UNSUPPORTED")
        self.assertEqual(host.reason, "required-identifier-absent")
        self.assertNotEqual(host.status, "PASS")
        self.assertFalse(host.evidence)
        self.assertEqual(report.exit_class, "fail")
        self.assertEqual(report.defined, 6)
        self.assertEqual(report.evaluated, 5)
        self.assertEqual(report.passed, 5)
        self.assertFalse(report.characterizing_counts)
        text = render(report)
        self.assertIn("H1 UNSUPPORTED required-identifier-absent", text)
        self.assertNotIn("H1 PASS", text)

    def test_present_identifier_with_zero_grants_passes(self) -> None:
        suite = load_suite()
        fixture = construct_fixture(suite["fixture"])
        fixture.host_grants["authenticated"] = 0
        result = execute_check(fixture, criterion(suite, "H1"))
        self.assertEqual(result.status, "PASS")
        self.assertEqual(result.examined["identifiers"], ["authenticated"])
        self.assertEqual(result.examined["grant_counts"]["authenticated"], 0)
        self.assertTrue(result.evidence)

    def test_skip_is_reported_and_blocks_full_conformance(self) -> None:
        suite = load_suite()
        suite["criteria"].append(
            {
                "id": "S1",
                "kind": "host_filter",
                "fixture_id": "scope-bound-access",
                "required_identifiers": ["authenticated"],
                "skip": "optional-platform-role-not-in-this-profile",
            }
        )
        report = run_suite(suite)
        skipped = next(item for item in report.criteria if item.id == "S1")
        self.assertEqual(skipped.status, "SKIPPED")
        self.assertEqual(report.exit_class, "partial")
        self.assertFalse(report.full_conformance)
        self.assertEqual(report.defined, 7)
        self.assertEqual(report.evaluated, 6)
        self.assertEqual(report.passed, 6)
        self.assertEqual(report.skipped, 1)
        self.assertIn("S1 SKIPPED optional-platform-role-not-in-this-profile", render(report))

    def test_hardcoded_verdict_cannot_force_a_pass(self) -> None:
        suite = load_suite()
        suite["verdict"] = "SUITE_RESULT: PASS"
        for binding in suite["fixture"]["identity_bindings"]:
            binding["resolved"] = False
        report = run_suite(suite)
        self.assertNotEqual(report.exit_class, "full")
        self.assertFalse(any(item.status == "PASS" and item.kind == "denial" for item in report.criteria))
        self.assertNotIn("SUITE_RESULT: PASS", render(report))

    def test_pass_without_examined_record_is_not_pass(self) -> None:
        status, reason, _examined, evidence = admit_result("PASS", "owner-disjunct", {}, "grant")
        self.assertEqual(status, "FAIL")
        self.assertEqual(reason, "pass-without-examined-record")
        self.assertFalse(evidence)

    def test_isolating_denial_fails_when_scope_precondition_is_absent(self) -> None:
        suite = load_suite()
        fixture = construct_fixture(suite["fixture"])
        fixture.principals["principal-c"].discard("scope-a")
        result = execute_check(fixture, criterion(suite, "D2"))
        self.assertEqual(result.status, "FAIL")
        self.assertEqual(result.reason, "denial-precondition-not-met")
        self.assertNotEqual(result.status, "PASS")

    def test_characterizing_counts_require_passing_grants(self) -> None:
        healthy = run_suite(load_suite())
        self.assertTrue(healthy.characterizing_counts)
        broken = load_suite()
        for binding in broken["fixture"]["identity_bindings"]:
            binding["resolved"] = False
        self.assertFalse(run_suite(broken).characterizing_counts)

    def test_spec_states_criterion_shape_requirements(self) -> None:
        spec = (REPO_ROOT / "docs" / "publication" / "smp-custody-layer.md").read_text(
            encoding="utf-8"
        )
        audit = (REPO_ROOT / "docs" / "publication" / "smp-conformance-gap-audit.md").read_text(
            encoding="utf-8"
        )
        for phrase in (
            "Paired grant.",
            "Grants gate denials.",
            "Fixture construction.",
            "Demonstrated failure.",
            "Failure reason.",
            "Host-specific identifiers.",
            "Skips.",
            "Coverage.",
            "Disjunctive predicates.",
            "Examined record.",
            "Characterizing counts.",
            "conformance-criteria-shape.md",
        ):
            self.assertIn(phrase, spec)
        for row in ("SH1", "SH2", "SH3", "SH4", "SH5", "SH6", "SH7", "SH8", "SH9", "SH10"):
            self.assertIn(f"| {row} |", audit)

    def test_validator_shell_syntax(self) -> None:
        self.assertTrue(os.access(SHELL_PATH, os.X_OK))
        subprocess.run(["bash", "-n", str(SHELL_PATH)], check=True)


def _run_cli(suite: dict) -> subprocess.CompletedProcess[str]:
    with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8") as handle:
        json.dump(suite, handle)
        handle.flush()
        return subprocess.run(
            [sys.executable, str(SCRIPT_PATH), handle.name],
            capture_output=True,
            check=False,
            text=True,
        )


if __name__ == "__main__":
    unittest.main()
