"""Local checks for the sanitized agent-operations contract.

These tests do not open a database and do not read a private instruction
corpus. Corpus inputs are synthetic fixtures or files created in a temporary
directory.
"""

from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import check_agent_operations_contract as contract  # noqa: E402


CHECKER = ROOT / "scripts" / "check_agent_operations_contract.py"
SURFACE = ROOT / "docs" / "contracts" / "agent-operations-surface.json"
PASSING_CORPUS = ROOT / "fixtures" / "agent-operations" / "synthetic-current-surface.md"
REMOVED_CORPUS = ROOT / "fixtures" / "agent-operations" / "synthetic-removed-signature.md"


def _run_checker(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CHECKER), *args],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


class AgentOperationsContractTests(unittest.TestCase):
    def test_current_public_signatures_match_the_recorded_surface(self) -> None:
        result = _run_checker([])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("agent-operations-contract/1.0.0", result.stdout)
        self.assertIn("signatures=53", result.stdout)
        self.assertIn("ok", result.stdout)

    def test_removed_signature_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sql_dir = Path(tmp) / "sql"
            shutil.copytree(ROOT / "sql", sql_dir)
            changed = 0
            for path in sql_dir.glob("*.sql"):
                original = path.read_text(encoding="utf-8")
                replacement = original.replace(
                    "function session_boot",
                    "function session_boot_withheld",
                ).replace(
                    "FUNCTION public.session_boot",
                    "FUNCTION public.session_boot_withheld",
                )
                if replacement != original:
                    changed += 1
                    path.write_text(replacement, encoding="utf-8")
            self.assertGreaterEqual(changed, 3)
            result = _run_checker(["--sql-dir", str(sql_dir)])
        self.assertEqual(result.returncode, 1)
        self.assertIn("removed: session_boot(text)", result.stderr)

    def test_changed_result_shape_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sql_dir = Path(tmp) / "sql"
            shutil.copytree(ROOT / "sql", sql_dir)
            target = sql_dir / "10_security_definer_hardening.sql"
            original = target.read_text(encoding="utf-8")
            needle = (
                "CREATE OR REPLACE FUNCTION public.session_boot"
                "(p_viewer text DEFAULT 'shared'::text)\n RETURNS jsonb\n"
            )
            self.assertIn(needle, original)
            target.write_text(
                original.replace(needle, needle.replace("RETURNS jsonb", "RETURNS text"), 1),
                encoding="utf-8",
            )
            result = _run_checker(["--sql-dir", str(sql_dir)])
        self.assertEqual(result.returncode, 1)
        self.assertIn("changed: session_boot(text) result 'jsonb' -> 'text'", result.stderr)

    def test_changed_argument_list_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sql_dir = Path(tmp) / "sql"
            shutil.copytree(ROOT / "sql", sql_dir)
            target = sql_dir / "10_security_definer_hardening.sql"
            original = target.read_text(encoding="utf-8")
            needle = "FUNCTION public.session_boot(p_viewer text DEFAULT 'shared'::text)"
            self.assertIn(needle, original)
            target.write_text(
                original.replace(
                    needle,
                    "FUNCTION public.session_boot(p_viewer uuid DEFAULT 'shared'::text)",
                    1,
                ),
                encoding="utf-8",
            )
            result = _run_checker(["--sql-dir", str(sql_dir)])
        self.assertEqual(result.returncode, 1)
        self.assertIn("changed: session_boot", result.stderr)
        self.assertIn("session_boot(uuid)", result.stderr)
        self.assertNotIn("ok", result.stdout)

    def test_content_digest_mismatch_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            contract_path = Path(tmp) / "03-agent-operations.md"
            contract_path.write_text(
                (ROOT / "docs" / "03-agent-operations.md").read_text(encoding="utf-8")
                + "\nSynthetic digest drift.\n",
                encoding="utf-8",
            )
            result = _run_checker(["--contract", str(contract_path)])
        self.assertEqual(result.returncode, 1)
        self.assertIn("content digest does not match", result.stderr)

    def test_synthetic_current_corpus_passes(self) -> None:
        result = _run_checker(["--corpus", str(PASSING_CORPUS)])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_synthetic_removed_corpus_fails_closed(self) -> None:
        result = _run_checker(["--corpus", str(REMOVED_CORPUS)])
        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "corpus teaches session_boot(), which is not on the recorded public surface",
            result.stderr,
        )
        self.assertIn(
            "corpus teaches supersede_memory(uuid, text, provenance_basis, text, text), "
            "which is not on the recorded public surface",
            result.stderr,
        )
        self.assertNotIn("Synthetic stale instruction", result.stderr)

    def test_drop_removes_signature_in_source_order(self) -> None:
        events = contract.parse_sql_events(
            """
            create function public.widget(p_id uuid) returns uuid language sql as $$ select p_id; $$;
            drop function if exists public.widget(uuid);
            """,
            "snippet.sql",
        )
        surface: dict[str, contract.Signature] = {}
        for kind, payload in events:
            if kind == "drop":
                self.assertIsInstance(payload, str)
                surface.pop(payload, None)
            else:
                self.assertIsInstance(payload, contract.Signature)
                assert isinstance(payload, contract.Signature)
                surface[payload.identity] = payload
        self.assertNotIn("widget(uuid)", surface)

    def test_checker_does_not_name_a_private_corpus(self) -> None:
        text = CHECKER.read_text(encoding="utf-8")
        for banned in (
            "Household_os_private",
            "supabase.co",
            "/home/",
            "BEGIN PRIVATE",
        ):
            self.assertNotIn(banned, text)
        self.assertIn("never fetched", text)
        missing = _run_checker(["--corpus", str(ROOT / "fixtures" / "agent-operations" / "missing.md")])
        self.assertEqual(missing.returncode, 1)
        self.assertIn("missing.md", missing.stderr)
        self.assertNotIn("Household", missing.stderr)

    def test_contract_states_boot_difference_and_deferred_enforcement(self) -> None:
        document = (ROOT / "docs" / "03-agent-operations.md").read_text(encoding="utf-8")
        self.assertIn("Contract version: agent-operations-contract/1.0.0", document)
        self.assertIn("must not assume identical boot signatures across deployments", document)
        self.assertIn("Primary Users", document)
        self.assertIn("Enforcement is deferred", document)
        self.assertIn("pre-DDL probe of live deployment instructions", document)
        self.assertIn("post-migration live compatibility receipt", document)
        self.assertIn("tests/12_hot_summary_profile.sql", document)
        self.assertIn("session_boot` in this tree\nis the copy from main", document)


if __name__ == "__main__":
    unittest.main()
