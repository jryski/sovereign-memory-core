from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import types
import unittest
from unittest import mock

from scripts import build_release_candidate
from scripts import schema_drift_inventory


class ReleaseCandidateEvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        (self.repo / "release").mkdir()
        self.schema = b"CREATE TABLE public.fixture (id bigint);\n"
        self.schema_sha = hashlib.sha256(self.schema).hexdigest()
        (self.repo / "release" / "v0.3-alpha-known-limitations.md").write_text(
            "# Known limitations\n", encoding="utf-8"
        )
        (self.repo / "release" / "v0.3-alpha-schema-fingerprint.json").write_text(
            json.dumps(
                {
                    "contract": "release-schema-fingerprint/1",
                    "schema_bytes": len(self.schema),
                    "schema_sha256": self.schema_sha,
                    "source": "test exact-commit schema baseline",
                },
                sort_keys=True,
                separators=(",", ":"),
            )
            + "\n",
            encoding="utf-8",
        )
        self._git("init")
        self._git("config", "user.email", "release-test@example.invalid")
        self._git("config", "user.name", "Release Test")
        self._git("add", ".")
        self._git("commit", "-m", "fixture")
        self.commit = self._git("rev-parse", "HEAD")
        self.tree = self._git("rev-parse", "HEAD^{tree}")
        self.proof = self.root / "proof"
        self.proof.mkdir()
        self.output = self.root / "output"
        self._write_valid_proof()

    def _git(self, *args: str) -> str:
        proc = subprocess.run(
            ["git", *args], cwd=self.repo, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, check=True,
        )
        return proc.stdout.strip()

    def _write_json(self, path: Path, value: object) -> None:
        path.write_text(
            json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )

    def _write_valid_proof(self) -> None:
        bundle = b"fixture"
        bundle_sha = hashlib.sha256(bundle).hexdigest()
        (self.proof / "sovereign-memory-c2.bundle.tar").write_bytes(bundle)
        (self.proof / "archive.sha256").write_text(bundle_sha + "  sovereign-memory-c2.bundle.tar\n", encoding="utf-8")
        fingerprint = hashlib.sha256(b"nonempty source fingerprint").hexdigest()
        self._write_json(
            self.proof / "receipt.json",
            {
                "contract": "c2-provider-exit-receipt/1",
                "exact_commit": self.commit,
                "source": {
                    "unchanged": True,
                    "before_fingerprint": fingerprint,
                    "after_fingerprint": fingerprint,
                    "system_identifier": "source-system",
                },
                "destination": {
                    "clean_before_restore": True,
                    "preflight_public_table_count": 0,
                    "system_identifier": "destination-system",
                },
                "bundle": {
                    "archive_sha256": bundle_sha,
                    "manifest_sha256": hashlib.sha256(b"manifest").hexdigest(),
                    "byte_deterministic_repeat_export": True,
                },
                "verification": {
                    "positive_control_readable": True,
                    "paired_private_denial": True,
                    "reciprocal_positive_readable": True,
                    "reciprocal_private_denial": True,
                    "attention_revision_lineage": True,
                    "service_role_direct_memories_select": False,
                    "perimeter_report": {
                        "contract_version": "perimeter-report/1",
                        "evaluation_status": "evaluated",
                        "perimeter_state": "clean",
                        "violation_count": 0,
                    },
                    "assert_perimeter_closed": "perimeter OK: perimeter-report/1 evaluated clean with zero findings",
                },
            },
        )
        self._write_json(
            self.proof / "schema-drift-comparison.json",
            {
                "contract": "schema-drift-inventory/1",
                "comparison_status": "clean",
                "exact_commit": self.commit,
                "exact_tree": self.tree,
                "expected_sha256": self.schema_sha,
                "actual_sha256": self.schema_sha,
                "expected_bytes": len(self.schema),
                "actual_bytes": len(self.schema),
                "diff_line_count": 0,
            },
        )

    def _args(self, suffix: str) -> argparse.Namespace:
        return argparse.Namespace(
            version="v0.3-alpha",
            commit=self.commit,
            tree=self.tree,
            repo_root=self.repo,
            proof_dir=self.proof,
            output_dir=self.output / suffix,
        )

    def _fake_bundle_result(self) -> object:
        return types.SimpleNamespace(manifest={"source": {"commit": self.commit}})

    def test_valid_receipts_reach_release_builder(self) -> None:
        with mock.patch.object(
            build_release_candidate, "validate_bundle", return_value=self._fake_bundle_result()
        ):
            self.assertEqual(build_release_candidate.build(self._args("valid")), 0)

    def test_self_consistent_fabricated_drift_must_match_commit_baseline(self) -> None:
        value = json.loads((self.proof / "schema-drift-comparison.json").read_text(encoding="utf-8"))
        fabricated = hashlib.sha256(b"fabricated but nonempty").hexdigest()
        value["expected_sha256"] = fabricated
        value["actual_sha256"] = fabricated
        value["expected_bytes"] = 23
        value["actual_bytes"] = 23
        self._write_json(self.proof / "schema-drift-comparison.json", value)
        with self.assertRaisesRegex(ValueError, "exact-commit release baseline"):
            build_release_candidate.build(self._args("fabricated-drift"))

    def test_both_empty_drift_sides_are_rejected(self) -> None:
        value = json.loads((self.proof / "schema-drift-comparison.json").read_text(encoding="utf-8"))
        empty = hashlib.sha256(b"").hexdigest()
        value["expected_sha256"] = empty
        value["actual_sha256"] = empty
        value["expected_bytes"] = 0
        value["actual_bytes"] = 0
        self._write_json(self.proof / "schema-drift-comparison.json", value)
        with self.assertRaisesRegex(ValueError, "internally inconsistent or empty"):
            build_release_candidate.build(self._args("empty-drift"))

    def test_zero_length_compare_receipt_is_rejected_end_to_end(self) -> None:
        expected = self.root / "expected.sql"
        actual = self.root / "actual.sql"
        expected.write_bytes(b"")
        actual.write_bytes(b"")
        receipt = self.proof / "schema-drift-comparison.json"
        self.assertEqual(
            schema_drift_inventory._compare(expected, actual, receipt, None, self.commit, self.tree),
            0,
        )
        with self.assertRaisesRegex(ValueError, "internally inconsistent or empty"):
            build_release_candidate.build(self._args("zero-capture"))

    def test_both_empty_source_fingerprints_are_rejected(self) -> None:
        value = json.loads((self.proof / "receipt.json").read_text(encoding="utf-8"))
        empty = hashlib.sha256(b"").hexdigest()
        value["source"]["before_fingerprint"] = empty
        value["source"]["after_fingerprint"] = empty
        self._write_json(self.proof / "receipt.json", value)
        with self.assertRaisesRegex(ValueError, "nonempty source fingerprint stability"):
            build_release_candidate.build(self._args("empty-source"))

    def test_builder_rejects_invalid_bundle_even_when_checksum_matches(self) -> None:
        with self.assertRaisesRegex(ValueError, "provider bundle validation failed"):
            build_release_candidate.build(self._args("invalid-bundle"))


if __name__ == "__main__":
    unittest.main()
