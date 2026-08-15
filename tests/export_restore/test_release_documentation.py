from __future__ import annotations

from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]


class ReleaseDocumentationContractTests(unittest.TestCase):
    def test_house_rehearsal_and_fingerprint_claim_boundaries_are_explicit(self) -> None:
        limitations = " ".join(
            (
                REPO_ROOT / "release" / "v0.3-alpha-known-limitations.md"
            ).read_text(encoding="utf-8").lower().split()
        )
        procedure = " ".join(
            (
                REPO_ROOT / "release" / "v0.3-alpha-release-procedure.md"
            ).read_text(encoding="utf-8").lower().split()
        )

        required_house_paragraph = (
            "the house rehearsal retained a complete recovery anchor, but exercised a "
            "partial public-schema restore because `supabase_vault` 0.3.1 was unavailable. "
            "hosted-role acl reconstruction was excluded, so house #59 is not a second c1 "
            "perimeter re-arm proof. house pg17.10 is a deployment-specific, version-matched "
            "recovery procedure; it does not expand postgresql 15/16 provider-exit support."
        )
        self.assertIn(required_house_paragraph, limitations)

        required_fingerprint_paragraph = (
            "optional source-before/after fingerprint binding remains a deferred residual. "
            "the release evidence checks that the recorded before and after fingerprints are "
            "nonempty and equal, but does not bind those values to an independently captured "
            "source fingerprint. that additional binding is not implemented in v0.3-alpha."
        )
        self.assertIn(required_fingerprint_paragraph, limitations)

        required_sql_procedure = (
            "schema fingerprint baselines must be regenerated whenever `sql/**` changes. "
            "treat a sql change without a regenerated, reviewed baseline as a new candidate "
            "whose schema-drift evidence is not current."
        )
        self.assertIn(required_sql_procedure, procedure)

    def test_export_restore_workflow_runs_for_every_sql_change(self) -> None:
        workflow = (
            REPO_ROOT / ".github" / "workflows" / "export-restore-validation.yml"
        ).read_text(encoding="utf-8").splitlines()

        def event_paths(event: str) -> set[str]:
            event_header = f"  {event}:"
            event_start = workflow.index(event_header) + 1
            event_end = next(
                (
                    index
                    for index, line in enumerate(workflow[event_start:], event_start)
                    if line.startswith("  ") and not line.startswith("    ")
                ),
                len(workflow),
            )
            paths_header = "    paths:"
            paths_start = workflow.index(paths_header, event_start, event_end) + 1
            paths: set[str] = set()
            for line in workflow[paths_start:event_end]:
                if line.startswith("    ") and not line.startswith("      "):
                    break
                if not line.startswith("      - "):
                    continue
                paths.add(line.removeprefix("      - ").strip('"'))
            return paths

        for event in ("pull_request", "push"):
            with self.subTest(event=event):
                self.assertIn("sql/**", event_paths(event))


if __name__ == "__main__":
    unittest.main()
