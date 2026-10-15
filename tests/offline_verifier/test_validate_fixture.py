"""Offline checks for the synthetic SMP verifier fixture."""

from __future__ import annotations

import copy
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.sovereignty_bundle import canonical_json_bytes, parse_canonical_json_bytes
from scripts.validate_smp_offline_fixture import build_good_fixture_files, sha256_hex


FIXTURE = ROOT / "fixtures" / "smp_offline"
VALIDATOR = ROOT / "scripts" / "validate_smp_offline_fixture.py"
FORBIDDEN = re.compile(
    r"https?://|localhost|example-user|example-partner|supabase\.co|@"
    r"|\b\d{3}[-.)]\d{3}[-.]\d{4}\b",
    re.IGNORECASE,
)


def run_validator(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(VALIDATOR), str(FIXTURE), *args],
        check=False,
        capture_output=True,
        text=True,
    )


class OfflineFixtureTests(unittest.TestCase):
    def test_committed_files_match_the_builder(self):
        expected = build_good_fixture_files()
        for relative, data in expected.items():
            self.assertEqual((FIXTURE / relative).read_bytes(), data, relative)
        committed = {
            path.relative_to(FIXTURE).as_posix()
            for path in FIXTURE.rglob("*")
            if path.is_file()
        }
        self.assertEqual(committed, set(expected))

    def test_good_fixture_is_smp_complete(self):
        result = run_validator()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "SMP-complete\n")
        self.assertNotIn("SMP-complete", result.stdout)
        receipt = parse_canonical_json_bytes(result.stdout.encode("utf-8"))
        self.assertEqual(canonical_json_bytes(receipt).decode("utf-8"), result.stdout)
        self.assertEqual(receipt["result"], "custody_verified")
        self.assertIsNone(receipt["skip_or_failure_reason"])
        self.assertEqual(receipt["receipt_version"], "smp.custody-receipt.v1")
        self.assertEqual(receipt["signer"]["principal"], "Primary Users")
        self.assertEqual(receipt["signer"]["method"], "canonical-sha256")
        self.assertEqual(receipt["scope"]["scope_id"], "synthetic-example-scope")
        self.assertEqual(receipt["scope"]["authority_epoch"], "epoch-2026-07-08")
        self.assertEqual(receipt["schema"]["migration_head"], "sql/11_perimeter_evaluability.sql")
        self.assertEqual(receipt["probe_suite"]["version"], "smp-probe-suite.v1")
        self.assertEqual(receipt["restore_target"]["fingerprint"], "synthetic-empty-postgresql-15")
        self.assertEqual(receipt["restore_target"]["engine"], "PostgreSQL")
        for digest in (
            receipt["source_package_digest"],
            receipt["backup"]["sha256"],
            receipt["probe_suite"]["sha256"],
            receipt["canonical_view"]["source_sha256"],
            receipt["canonical_view"]["restored_sha256"],
            receipt["signer"]["signature"],
        ):
            self.assertRegex(digest, r"^[0-9a-f]{64}$")
        self.assertEqual(
            receipt["canonical_view"]["source_sha256"],
            receipt["canonical_view"]["restored_sha256"],
        )
        self.assertEqual(
            receipt["canonical_view"]["definition_version"],
            "smp.canonical-governed-state.v1",
        )
        counts = receipt["canonical_view"]["counts"]
        self.assertGreaterEqual(counts["conflicted"], 2)
        self.assertGreaterEqual(counts["stale"], 1)
        self.assertGreaterEqual(counts["held"], 1)
        self.assertGreaterEqual(counts["excluded"], 1)
        self.assertGreaterEqual(counts["tombstoned"], 1)
        self.assertGreaterEqual(counts["promoted"], 1)
        self.assertTrue(receipt["exclusions"])
        self.assertTrue(all(row["passed"] for row in receipt["structural_invariants"]))
        self.assertEqual(
            {row["id"] for row in receipt["structural_invariants"]},
            {
                "candidate_promotion_boundaries",
                "checkpoint_chain",
                "foreign_key_integrity",
                "supersession_acyclicity",
                "tombstone_erasure_preservation",
            },
        )
        self.assertTrue(receipt["probe_results"])
        self.assertTrue(all(row["matched"] for row in receipt["probe_results"]))
        unsigned = copy.deepcopy(receipt)
        unsigned["signer"]["signature"] = ""
        self.assertEqual(sha256_hex(canonical_json_bytes(unsigned)), receipt["signer"]["signature"])
        self.assertIn("Primary Users", result.stdout)

    def test_non_governed_noise_keeps_the_same_set_hash(self):
        good = run_validator()
        noisy = run_validator("--inject", "non_governed_noise")
        self.assertEqual(noisy.returncode, 0, noisy.stderr)
        self.assertEqual(noisy.stderr, "SMP-complete\n")
        good_receipt = parse_canonical_json_bytes(good.stdout.encode("utf-8"))
        noisy_receipt = parse_canonical_json_bytes(noisy.stdout.encode("utf-8"))
        self.assertEqual(
            good_receipt["canonical_view"]["source_sha256"],
            noisy_receipt["canonical_view"]["restored_sha256"],
        )

    def test_flattened_conflict_is_a_specific_failure(self):
        result = run_validator("--inject", "flatten_conflict")
        self.assertEqual(result.returncode, 1)
        self.assertNotIn("SMP-complete", result.stdout)
        self.assertNotIn("SMP-complete", result.stderr)
        self.assertIn("verification_failed:", result.stderr)
        self.assertIn("conflict_not_preserved", result.stderr)
        receipt = parse_canonical_json_bytes(result.stdout.encode("utf-8"))
        self.assertEqual(receipt["result"], "verification_failed")
        self.assertIn("conflict_not_preserved", receipt["skip_or_failure_reason"])
        conflict = next(row for row in receipt["structural_invariants"] if row["id"] == "foreign_key_integrity")
        self.assertFalse(conflict["passed"])

    def test_promoted_agent_content_is_a_specific_failure(self):
        result = run_validator("--inject", "promote_agent_content")
        self.assertEqual(result.returncode, 1)
        self.assertIn("agent_content_promoted", result.stderr)
        self.assertNotIn("SMP-complete", result.stderr)
        receipt = parse_canonical_json_bytes(result.stdout.encode("utf-8"))
        self.assertEqual(receipt["result"], "verification_failed")
        boundary = next(
            row for row in receipt["structural_invariants"]
            if row["id"] == "candidate_promotion_boundaries"
        )
        self.assertFalse(boundary["passed"])

    def test_resurrected_tombstone_is_a_specific_failure(self):
        result = run_validator("--inject", "resurrect_tombstone")
        self.assertEqual(result.returncode, 1)
        self.assertIn("tombstone_resurrected", result.stderr)
        self.assertNotIn("SMP-complete", result.stderr)

    def test_dropped_authority_is_a_specific_failure(self):
        result = run_validator("--inject", "drop_authority")
        self.assertEqual(result.returncode, 1)
        self.assertIn("authority_declaration_missing", result.stderr)
        self.assertNotIn("SMP-complete", result.stderr)

    def test_fixture_text_is_public_safe(self):
        blob = "\n".join(path.read_text(encoding="utf-8") for path in FIXTURE.rglob("*") if path.is_file())
        self.assertIsNone(FORBIDDEN.search(blob), FORBIDDEN.search(blob).group(0) if FORBIDDEN.search(blob) else None)
        self.assertIn("Primary Users", blob)
        self.assertNotIn("example-user", blob.lower())


if __name__ == "__main__":
    unittest.main()
