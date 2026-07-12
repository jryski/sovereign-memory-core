#!/usr/bin/env python3
"""Verify the synthetic SMP custody fixture without a source system or emitter."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

PROVENANCE = {
    "human_direct", "decision_record", "imported_artifact", "source_document",
    "agent_summary", "agent_inference", "system_observed",
}
DISPOSITIONS = {"import", "hold", "exclude", "evidence"}
PROBE_CATEGORIES = {"positive", "negative", "conflict", "stale_state", "evidence_request"}


def load(root: Path, name: str) -> Any:
    return json.loads((root / name).read_text(encoding="utf-8"))


def verify(root: Path) -> list[str]:
    failures: list[str] = []

    def check(condition: bool, message: str) -> None:
        if not condition:
            failures.append(message)

    try:
        commitments = load(root, "commitments.json")
        for name, expected in commitments["artifacts"].items():
            path = root / name
            check(path.is_file(), f"commitment: missing artifact {name}")
            if path.is_file():
                actual = hashlib.sha256(path.read_bytes()).hexdigest()
                check(actual == expected, f"commitment: hash mismatch for {name}")

        package = load(root, "package.json")
        manifest = load(root, "manifest.json")
        probes = load(root, "probes.json")
        results = load(root, "probe-results.json")
        cutover = load(root, "cutover.json")
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        return [f"structure: {error}"]

    check(package.get("smp_version") == "0.3", "package: smp_version must be 0.3")
    check(package.get("profile") == "plain-directory-json-v1", "package: unexpected profile")
    items = {row["id"]: row for row in package.get("source_items", [])}
    entries = manifest.get("entries", [])
    dispositions: dict[str, list[str]] = {}
    for entry in entries:
        item_id = entry.get("source_item_id")
        dispositions.setdefault(item_id, []).append(entry.get("disposition"))
        check(entry.get("disposition") in DISPOSITIONS, f"manifest: invalid disposition for {item_id}")
        check(item_id in items, f"manifest: unknown source item {item_id}")
    check(set(dispositions) == set(items), "accounting: source items are missing or unexplained")
    for item_id, values in dispositions.items():
        check(len(values) == 1, f"accounting: {item_id} must have exactly one disposition")
    check(manifest.get("frozen") is True, "manifest: ledger is not frozen")
    check({v[0] for v in dispositions.values()} >= {"import", "hold", "exclude"},
          "fixture: import, hold, and exclude dispositions are required")

    records = package.get("destination_records", [])
    evidence = {row["id"]: row for row in package.get("evidence", [])}
    for evidence_id, row in evidence.items():
        payload = row.get("payload")
        check(isinstance(payload, str), f"evidence: {evidence_id} payload is missing")
        if isinstance(payload, str):
            check(hashlib.sha256(payload.encode("utf-8")).hexdigest() == row.get("sha256"),
                  f"evidence: {evidence_id} hash mismatch")
        check(row.get("source_item_id") in items,
              f"evidence: {evidence_id} references an unknown source item")
    imported_ids = {e["source_item_id"] for e in entries if e.get("disposition") == "import"}
    for record in records:
        rid = record.get("id", "unknown")
        basis = record.get("provenance_basis")
        check(basis in PROVENANCE, f"provenance: {rid} has invalid basis")
        check(record.get("source_item_id") in imported_ids, f"promotion: {rid} is not backed by an import disposition")
        evidence_id = record.get("evidence_id")
        check(evidence_id in evidence, f"evidence: {rid} has no preserved evidence")
        if evidence_id in evidence:
            check(evidence[evidence_id].get("source_item_id") == record.get("source_item_id"),
                  f"evidence: {rid} trace points to a different source item")
        if record.get("consequential"):
            check(bool(evidence_id), f"consequential: {rid} lacks evidence")
            check(basis not in {"agent_summary", "agent_inference"},
                  f"consequential: {rid} is agent-authored")
        check(record.get("authority") != "human" or basis in {"human_direct", "decision_record"},
              f"provenance: {rid} launders agent content as human authority")

    states = {r.get("state") for r in records}
    check("conflicted" in states, "preservation: conflict is not represented")
    check("stale" in states, "preservation: stale claim is not represented")
    check(all(r.get("preserved") is True for r in records if r.get("state") in {"conflicted", "stale"}),
          "preservation: conflict/stale history must be preserved")

    definitions = {p["id"]: p for p in probes.get("probes", [])}
    result_map = {r["probe_id"]: r for r in results.get("results", [])}
    categories = {p.get("category") for p in definitions.values() if p.get("active", True)}
    check(categories == PROBE_CATEGORIES, "probes: all five categories are required")
    check(set(result_map) == set(definitions), "probes: definitions and results do not reconcile")
    for probe_id, probe in definitions.items():
        if probe.get("critical"):
            check(result_map.get(probe_id, {}).get("status") == "pass",
                  f"probes: critical probe {probe_id} did not pass")

    scope = cutover.get("scope")
    check(bool(scope), "authority: cutover scope is missing")
    check(cutover.get("authority_declared_by") == package.get("principal_id"),
          "authority: declaration is not by the principal")
    check(cutover.get("probe_run_id") == results.get("run_id"),
          "authority: cutover does not reference the verified probe run")
    check(cutover.get("status") == "authoritative", "authority: cutover is not authoritative")
    return failures


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("fixture", type=Path)
    args = parser.parse_args()
    failures = verify(args.fixture)
    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        raise SystemExit(1)
    print("SMP-COMPLETE: offline custody verification passed")


if __name__ == "__main__":
    main()
