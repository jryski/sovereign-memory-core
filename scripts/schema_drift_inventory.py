#!/usr/bin/env python3
"""Capture and compare a deterministic PostgreSQL schema drift inventory.

This is a release-evidence seam, not a semantic SQL equivalence engine.  It uses
pg_dump's schema view (including ACL/RLS/function/trigger/extension DDL), removes
only dump comments and psql's randomized restrict markers, and compares the
remaining bytes exactly.  Source and restored target should therefore be
captured with the same pg_dump major version.

Credentials are read from a named environment variable containing a PostgreSQL
URL and are translated into libpq environment variables.  The DSN/password is
never placed on the subprocess command line.
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import parse_qsl, unquote, urlsplit

CONTRACT = "schema-drift-inventory/1"
SHA40 = re.compile(r"^[0-9a-f]{40}$")


def _canonical_json(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _libpq_env(dsn: str) -> dict[str, str]:
    parsed = urlsplit(dsn)
    if parsed.scheme not in {"postgres", "postgresql"}:
        raise ValueError("DSN must be a postgres:// or postgresql:// URL")
    if not parsed.hostname:
        raise ValueError("DSN must include a hostname")

    env = os.environ.copy()
    for key in (
        "PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGPASSWORD", "PGSSLMODE",
        "PGOPTIONS", "PGSERVICE", "PGSERVICEFILE", "PGPASSFILE",
    ):
        env.pop(key, None)

    env["PGHOST"] = parsed.hostname
    if parsed.port is not None:
        env["PGPORT"] = str(parsed.port)
    env["PGDATABASE"] = unquote(parsed.path.lstrip("/")) or "postgres"
    if parsed.username is not None:
        env["PGUSER"] = unquote(parsed.username)
    if parsed.password is not None:
        env["PGPASSWORD"] = unquote(parsed.password)

    query = dict(parse_qsl(parsed.query, keep_blank_values=True))
    if "sslmode" in query:
        env["PGSSLMODE"] = query["sslmode"]
    if "options" in query:
        env["PGOPTIONS"] = query["options"]
    return env


def _run(command: list[str], *, env: dict[str, str]) -> bytes:
    proc = subprocess.run(
        command,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode:
        stderr = proc.stderr.decode("utf-8", errors="replace")[-4000:]
        raise RuntimeError(f"{command[0]} failed ({proc.returncode}): {stderr}")
    return proc.stdout


def _normalize_dump(raw: bytes) -> bytes:
    text = raw.decode("utf-8", errors="strict")
    lines: list[str] = []
    blank = False
    for original in text.splitlines():
        line = original.rstrip()
        stripped = line.strip()
        # Dump comments are not executable database shape and include version
        # headers/trailers. Object COMMENT statements are omitted by --no-comments.
        if stripped.startswith("--"):
            continue
        # PostgreSQL 17+ psql safety markers carry a per-dump randomized key.
        # They protect script execution but are not catalog state.
        if stripped.startswith("\\restrict ") or stripped.startswith("\\unrestrict "):
            continue
        if not stripped:
            if lines and not blank:
                lines.append("")
            blank = True
            continue
        lines.append(line)
        blank = False
    while lines and lines[-1] == "":
        lines.pop()
    return ("\n".join(lines) + "\n").encode("utf-8")


def _capture(dsn_env: str, sql_output: Path, receipt_output: Path) -> int:
    dsn = os.environ.get(dsn_env)
    if not dsn:
        raise ValueError(f"environment variable {dsn_env!r} is empty or missing")
    env = _libpq_env(dsn)

    server_version_num = _run(
        ["psql", "-X", "-A", "-t", "-q", "-v", "ON_ERROR_STOP=1", "-c", "show server_version_num;"],
        env=env,
    ).decode("utf-8", errors="strict").strip()
    pg_dump_version = _run(["pg_dump", "--version"], env=env).decode("utf-8", errors="strict").strip()
    raw = _run(
        [
            "pg_dump",
            "--schema-only",
            "--no-owner",
            "--no-comments",
            "--quote-all-identifiers",
        ],
        env=env,
    )
    normalized = _normalize_dump(raw)
    digest = hashlib.sha256(normalized).hexdigest()

    sql_output.parent.mkdir(parents=True, exist_ok=True)
    receipt_output.parent.mkdir(parents=True, exist_ok=True)
    sql_output.write_bytes(normalized)
    receipt = {
        "contract": CONTRACT,
        "capture_status": "captured",
        "pg_dump_version": pg_dump_version,
        "server_version_num": server_version_num,
        "schema_bytes": len(normalized),
        "schema_lines": normalized.count(b"\n"),
        "schema_sha256": digest,
    }
    receipt_output.write_text(_canonical_json(receipt) + "\n", encoding="utf-8")
    print(_canonical_json(receipt))
    return 0


def _compare(
    expected: Path,
    actual: Path,
    receipt_output: Path,
    diff_output: Path | None,
    exact_commit: str,
    exact_tree: str,
) -> int:
    if SHA40.fullmatch(exact_commit) is None or SHA40.fullmatch(exact_tree) is None:
        raise ValueError("--exact-commit and --exact-tree must be exact lowercase 40-character SHAs")

    expected_raw = expected.read_bytes()
    actual_raw = actual.read_bytes()
    expected_sha = hashlib.sha256(expected_raw).hexdigest()
    actual_sha = hashlib.sha256(actual_raw).hexdigest()
    clean = expected_raw == actual_raw

    diff_lines: list[str] = []
    if not clean:
        diff_lines = list(
            difflib.unified_diff(
                expected_raw.decode("utf-8", errors="strict").splitlines(),
                actual_raw.decode("utf-8", errors="strict").splitlines(),
                fromfile=str(expected),
                tofile=str(actual),
                lineterm="",
            )
        )
        if diff_output is not None:
            diff_output.parent.mkdir(parents=True, exist_ok=True)
            diff_output.write_text("\n".join(diff_lines) + "\n", encoding="utf-8")

    receipt = {
        "contract": CONTRACT,
        "comparison_status": "clean" if clean else "drift",
        "exact_commit": exact_commit,
        "exact_tree": exact_tree,
        "expected_sha256": expected_sha,
        "actual_sha256": actual_sha,
        "expected_bytes": len(expected_raw),
        "actual_bytes": len(actual_raw),
        "diff_line_count": len(diff_lines),
    }
    receipt_output.parent.mkdir(parents=True, exist_ok=True)
    receipt_output.write_text(_canonical_json(receipt) + "\n", encoding="utf-8")
    print(_canonical_json(receipt))
    return 0 if clean else 3


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    capture = sub.add_parser("capture", help="capture normalized schema inventory")
    capture.add_argument("--dsn-env", required=True, help="environment variable containing PostgreSQL URL")
    capture.add_argument("--sql-output", required=True, type=Path)
    capture.add_argument("--receipt-output", required=True, type=Path)

    compare = sub.add_parser("compare", help="fail closed if two captured inventories differ")
    compare.add_argument("--expected", required=True, type=Path)
    compare.add_argument("--actual", required=True, type=Path)
    compare.add_argument("--receipt-output", required=True, type=Path)
    compare.add_argument("--diff-output", type=Path)
    compare.add_argument("--exact-commit", required=True)
    compare.add_argument("--exact-tree", required=True)
    return parser


def main() -> int:
    args = _parser().parse_args()
    try:
        if args.command == "capture":
            return _capture(args.dsn_env, args.sql_output, args.receipt_output)
        return _compare(
            args.expected,
            args.actual,
            args.receipt_output,
            args.diff_output,
            args.exact_commit,
            args.exact_tree,
        )
    except (OSError, UnicodeError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(_canonical_json({"code": "SCHEMA_DRIFT_INVENTORY_ERROR", "error": str(exc)}), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
