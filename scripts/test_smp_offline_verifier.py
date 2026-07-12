#!/usr/bin/env python3
"""Exercise specific offline-verifier failure reasons."""

from __future__ import annotations

import copy
import json
import tempfile
from pathlib import Path
from typing import Any, Callable

from verify_smp_offline import verify

ROOT = Path(__file__).parents[1]
FIXTURE = ROOT / "fixtures" / "smp_offline" / "complete"


def write_fixture(root: Path, files: dict[str, Any]) -> None:
    for name, value in files.items():
        (root / name).write_text(json.dumps(value), encoding="utf-8")


def main() -> None:
    baseline = {p.name: json.loads(p.read_text()) for p in FIXTURE.glob("*.json")}
    cases: list[tuple[str, str, Callable[[dict[str, Any]], None]]] = [
        ("unexplained item", "accounting: source items are missing or unexplained",
         lambda f: f["manifest.json"]["entries"].pop()),
        ("agent authority laundering", "launders agent content as human authority",
         lambda f: f["package.json"]["destination_records"][0].update(
             provenance_basis="agent_summary", authority="human")),
        ("failed critical probe", "critical probe positive-current did not pass",
         lambda f: f["probe-results.json"]["results"][0].update(status="fail")),
        ("missing scope", "authority: cutover scope is missing",
         lambda f: f["cutover.json"].update(scope="")),
    ]
    for name, expected, mutate in cases:
        files = copy.deepcopy(baseline)
        mutate(files)
        files["commitments.json"]["artifacts"] = {}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_fixture(root, files)
            failures = verify(root)
        if not any(expected in failure for failure in failures):
            raise AssertionError(f"{name}: expected {expected!r}, got {failures!r}")
        print(f"PASS: {name} rejected")
    print(f"PASS: {len(cases)} offline verifier negative case(s)")


if __name__ == "__main__":
    main()
