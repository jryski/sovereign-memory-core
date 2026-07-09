#!/usr/bin/env python3
"""Exercise rollback-only SQL loader failures against local PostgreSQL."""

from __future__ import annotations

import argparse
import copy
import json
import os
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


Package = dict[str, Any]
Mutation = Callable[[Package], None]
LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1"}


def candidate(package: Package, index: int = 0) -> dict[str, Any]:
    return package["source_items"][0]["manifest_candidates"][index]


def duplicate_manifest_key(package: Package) -> None:
    candidate(package, 1)["manifest_key"] = candidate(package, 0)["manifest_key"]


def remove_probe_category(package: Package) -> None:
    package["cutover_probes"] = [
        probe
        for probe in package["cutover_probes"]
        if probe["probe_category"] != "negative"
    ]


def psql(
    database_url: str,
    *arguments: str,
    input_text: str | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["psql", database_url, "-v", "ON_ERROR_STOP=1", *arguments],
        capture_output=True,
        check=False,
        input=input_text,
        text=True,
    )


def assert_fixture_absent(database_url: str, source_key: str, case_name: str) -> None:
    result = psql(
        database_url,
        "-v",
        f"source_key={source_key}",
        "-Atq",
        input_text="select count(*) from source_systems where source_key=:'source_key';",
    )
    if result.returncode != 0:
        raise AssertionError(f"{case_name}: cleanup query failed: {result.stderr.strip()}")
    if result.stdout.strip() != "0":
        raise AssertionError(
            f"{case_name}: failed transaction left fixture source rows"
        )


def run_case(
    database_url: str,
    loader: Path,
    baseline: Package,
    name: str,
    mutate: Mutation,
    expected_error: str,
) -> None:
    package = copy.deepcopy(baseline)
    mutate(package)
    package_json = json.dumps(package, ensure_ascii=True, separators=(",", ":"), sort_keys=True)
    result = psql(
        database_url,
        "-v",
        f"package_json={package_json}",
        "-f",
        str(loader),
    )
    output = result.stdout + result.stderr
    if result.returncode == 0:
        raise AssertionError(f"{name}: corrupted package unexpectedly loaded")
    if expected_error not in output:
        raise AssertionError(
            f"{name}: expected {expected_error!r}, received {output.strip()!r}"
        )
    assert_fixture_absent(
        database_url, baseline["source_system"]["source_key"], name
    )
    print(f"PASS: {name} rejected and rolled back ({expected_error})")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("loader", type=Path)
    args = parser.parse_args()

    database_url = os.environ.get("DATABASE_URL")
    if not database_url:
        raise SystemExit("DATABASE_URL is required")
    hostname = urlparse(database_url).hostname
    if hostname not in LOCAL_HOSTS:
        raise SystemExit(
            "negative loader tests require localhost/127.0.0.1/::1; "
            "refusing non-local DATABASE_URL"
        )

    baseline = json.loads(args.package.read_text(encoding="utf-8"))
    cases: list[tuple[str, Mutation, str]] = [
        (
            "corrupted payload evidence hash",
            lambda package: package["source_items"][0]["payload_evidence"][0].__setitem__(
                "payload_hash", "0" * 64
            ),
            "Chat-Mine loader smoke hash mismatch",
        ),
        (
            "corrupted candidate quote hash",
            lambda package: candidate(package).__setitem__(
                "source_quote_hash", "0" * 64
            ),
            "candidate quote hash mismatch",
        ),
        (
            "missing import/HOLD source locator",
            lambda package: candidate(package).pop("source_locator"),
            "candidate locator gap",
        ),
        (
            "duplicate manifest key",
            duplicate_manifest_key,
            "duplicate key value violates unique constraint",
        ),
        (
            "missing cutover probe category",
            remove_probe_category,
            "expected five active probe categories",
        ),
    ]

    for name, mutate, expected_error in cases:
        run_case(
            database_url,
            args.loader,
            baseline,
            name,
            mutate,
            expected_error,
        )

    print(f"PASS: {len(cases)} negative SQL loader corruption case(s)")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1) from None
