#!/usr/bin/env python3
"""Prove malformed Chat-Mine packages fail for the intended invariant."""

from __future__ import annotations

import argparse
import copy
import json
import subprocess
import sys
import tempfile
from collections.abc import Callable
from pathlib import Path
from typing import Any

from validate_chat_mine_package import canonical_bytes, sha256_hex


Package = dict[str, Any]
Mutation = Callable[[Package], None]


def refresh_checksum(package: Package) -> None:
    package.pop("package_checksum", None)
    package["package_checksum"] = sha256_hex(canonical_bytes(package))


def candidate(package: Package, index: int = 0) -> dict[str, Any]:
    return package["source_items"][0]["manifest_candidates"][index]


def remove_probe_category(package: Package) -> None:
    package["cutover_probes"] = [
        probe
        for probe in package["cutover_probes"]
        if probe["probe_category"] != "negative"
    ]


def duplicate_manifest_key(package: Package) -> None:
    candidate(package, 1)["manifest_key"] = candidate(package, 0)["manifest_key"]


def run_case(
    validator: Path,
    baseline: Package,
    name: str,
    mutate: Mutation,
    expected_error: str,
    *,
    recompute_checksum: bool = True,
) -> None:
    package = copy.deepcopy(baseline)
    mutate(package)
    if recompute_checksum:
        refresh_checksum(package)

    with tempfile.NamedTemporaryFile("w", suffix=".json", encoding="utf-8") as handle:
        json.dump(package, handle, ensure_ascii=True, sort_keys=True)
        handle.flush()
        result = subprocess.run(
            [sys.executable, str(validator), handle.name],
            capture_output=True,
            check=False,
            text=True,
        )

    output = result.stdout + result.stderr
    if result.returncode == 0:
        raise AssertionError(f"{name}: malformed package unexpectedly passed")
    if expected_error not in output:
        raise AssertionError(
            f"{name}: expected {expected_error!r}, received {output.strip()!r}"
        )
    print(f"PASS: {name} rejected ({expected_error})")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    args = parser.parse_args()

    baseline = json.loads(args.package.read_text(encoding="utf-8"))
    validator = Path(__file__).with_name("validate_chat_mine_package.py")
    cases: list[tuple[str, Mutation, str, bool]] = [
        (
            "candidate quote hash mismatch",
            lambda package: candidate(package).__setitem__("source_quote_hash", "0" * 64),
            "quote hash mismatch",
            True,
        ),
        (
            "package checksum mismatch",
            lambda package: package["batch"].__setitem__("batch_key", "tampered-batch"),
            "package checksum mismatch",
            False,
        ),
        (
            "payload hash mismatch",
            lambda package: package["source_items"][0].__setitem__(
                "payload_hash", "0" * 64
            ),
            "payload hash mismatch",
            True,
        ),
        (
            "missing source locator",
            lambda package: candidate(package).pop("source_locator"),
            "import/HOLD candidate requires source_locator",
            True,
        ),
        (
            "missing source quote hash",
            lambda package: candidate(package).pop("source_quote_hash"),
            "import/HOLD candidate requires source_quote_hash",
            True,
        ),
        (
            "duplicate manifest key",
            duplicate_manifest_key,
            "duplicate manifest_key",
            True,
        ),
        (
            "missing probe category",
            remove_probe_category,
            "active probes must cover all five categories",
            True,
        ),
    ]

    for name, mutate, expected_error, recompute_checksum in cases:
        run_case(
            validator,
            baseline,
            name,
            mutate,
            expected_error,
            recompute_checksum=recompute_checksum,
        )

    print(f"PASS: {len(cases)} negative package mutation case(s)")


if __name__ == "__main__":
    main()
