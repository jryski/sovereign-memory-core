from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import check_normative_coverage as coverage  # noqa: E402


SPEC = """\
The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** in this document are to be interpreted as described in RFC 2119.

A package **MUST** declare the version.
"""

MAP = """\
# Example

## Keyword map

| Anchor | Keyword | Audit ID |
|---|---|---|
| A package **MUST** declare the version | MUST | T1 |
"""

AUDIT = """\
# Example

## Requirement matrix

| ID | Draft 0.3 requirement | Current posture | Notes / follow-up |
|---|---|---|---|
| T1 | Package declares a version. | Gap | Example only. |
"""


class NormativeCoverageTests(unittest.TestCase):
    def test_repository_keyword_map_matches_the_audit(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(REPO_ROOT / "scripts" / "check_normative_coverage.py")],
            cwd=REPO_ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn(coverage.NO_CONFORMANCE_CLAIM, completed.stdout)
        self.assertIn("52 RFC 2119 keywords mapped", completed.stdout)
        self.assertNotIn("full Draft 0.3 conformance", completed.stdout.lower())

    def test_i44_remains_a_gap(self) -> None:
        audit = (
            REPO_ROOT / "docs" / "publication" / "smp-conformance-gap-audit.md"
        ).read_text(encoding="utf-8")
        row = next(line for line in audit.splitlines() if line.startswith("| I4.4 |"))
        cells = [cell.strip() for cell in row.strip().strip("|").split("|")]
        self.assertEqual(cells[2], "Gap")
        self.assertIn("does not claim", audit)

    def test_boilerplate_is_ignored_and_declared_keyword_maps(self) -> None:
        report = coverage.evaluate(SPEC, MAP, AUDIT)
        self.assertEqual(report.problems, ())
        self.assertEqual(report.keyword_count, 1)

    def test_unmapped_bold_keyword_fails(self) -> None:
        spec = SPEC + "\nA later rule **MUST NOT** be forgotten.\n"
        report = coverage.evaluate(spec, MAP, AUDIT)
        self.assertTrue(any(item.startswith("unmapped keyword MUST NOT") for item in report.problems))

    def test_unbolded_keyword_fails(self) -> None:
        spec = SPEC + "\nA package MUST stay bold.\n"
        report = coverage.evaluate(spec, MAP, AUDIT)
        self.assertTrue(any(item.startswith("unbolded keyword MUST") for item in report.problems))

    def test_missing_audit_id_fails(self) -> None:
        audit = AUDIT.replace("| T1 |", "| T9 |")
        report = coverage.evaluate(SPEC, MAP, audit)
        self.assertTrue(
            any("mapped audit ID T1" in item and "missing" in item for item in report.problems)
        )

    def test_should_not_outside_boilerplate_must_be_mapped(self) -> None:
        spec = SPEC + "\nA profile **SHOULD NOT** hide lossiness.\n"
        report = coverage.evaluate(spec, MAP, AUDIT)
        self.assertTrue(any("unmapped keyword SHOULD NOT" in item for item in report.problems))

    def test_unknown_anchor_fails(self) -> None:
        mapped = MAP + "| This anchor is not in the spec **MAY** wander | MAY | T1 |\n"
        report = coverage.evaluate(SPEC, mapped, AUDIT)
        self.assertTrue(any("was not found in the spec" in item for item in report.problems))


if __name__ == "__main__":
    unittest.main()
