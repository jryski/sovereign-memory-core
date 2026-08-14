#!/usr/bin/env python3
"""Build v0.3-alpha candidate release assets from an exact Git commit.

This command does not tag, publish, merge, or declare a release. It creates a
source archive, release manifest and checksums that are cryptographically bound
to the exact candidate commit and to the provider-exit evidence produced in the
same workflow run.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

CONTRACT = "sovereign-memory-release-manifest/1"
REPOSITORY = "https://github.com/jryski/sovereign-memory-core"
SHA40 = re.compile(r"^[0-9a-f]{40}$")


@dataclass(frozen=True)
class Artifact:
    path: str
    role: str
    sha256: str
    bytes: int

    def as_dict(self) -> dict[str, object]:
        return {
            "path": self.path,
            "role": self.role,
            "sha256": self.sha256,
            "bytes": self.bytes,
        }


def _canonical_json(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def _sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _read_json(path: Path) -> dict[str, object]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return value


def _git(root: Path, *args: str, input_bytes: bytes | None = None) -> bytes:
    proc = subprocess.run(
        ["git", *args],
        cwd=root,
        input=input_bytes,
        stdin=subprocess.PIPE if input_bytes is not None else subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode:
        stderr = proc.stderr.decode("utf-8", errors="replace")[-4000:]
        raise RuntimeError(f"git {' '.join(args)} failed ({proc.returncode}): {stderr}")
    return proc.stdout


def _artifact(path: Path, relative: str, role: str) -> Artifact:
    raw = path.read_bytes()
    return Artifact(relative, role, _sha256(raw), len(raw))


def _build_source_archive(root: Path, version: str, commit: str, output: Path) -> Artifact:
    prefix = f"sovereign-memory-core-{version}/"
    tar_raw = _git(root, "archive", "--format=tar", f"--prefix={prefix}", commit)
    embedded = _git(root, "get-tar-commit-id", input_bytes=tar_raw).decode("ascii", errors="strict").strip()
    if embedded != commit:
        raise RuntimeError(f"git archive embedded commit {embedded!r}, expected {commit}")

    buffer = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=buffer, compresslevel=9, mtime=0) as gz:
        gz.write(tar_raw)
    output.write_bytes(buffer.getvalue())
    return _artifact(output, output.name, "source-archive")


def build(args: argparse.Namespace) -> int:
    root = args.repo_root.resolve()
    proof = args.proof_dir.resolve()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)

    if SHA40.fullmatch(args.commit) is None or SHA40.fullmatch(args.tree) is None:
        raise ValueError("--commit and --tree must be exact lowercase 40-character SHAs")
    actual_commit = _git(root, "rev-parse", "HEAD").decode().strip()
    actual_tree = _git(root, "rev-parse", "HEAD^{tree}").decode().strip()
    if actual_commit != args.commit or actual_tree != args.tree:
        raise RuntimeError(
            f"checkout coordinate mismatch: commit {actual_commit}/{args.commit}, tree {actual_tree}/{args.tree}"
        )

    provider_receipt_path = proof / "receipt.json"
    provider_bundle_path = proof / "sovereign-memory-c2.bundle.tar"
    provider_archive_checksum_path = proof / "archive.sha256"
    drift_path = proof / "schema-drift-comparison.json"
    for required in (provider_receipt_path, provider_bundle_path, provider_archive_checksum_path, drift_path):
        if not required.is_file():
            raise FileNotFoundError(f"required release evidence is missing: {required}")

    provider = _read_json(provider_receipt_path)
    drift = _read_json(drift_path)
    if provider.get("contract") != "c2-provider-exit-receipt/1":
        raise ValueError("unexpected provider-exit receipt contract")
    if provider.get("exact_commit") != args.commit:
        raise ValueError("provider-exit receipt is not bound to the release candidate commit")
    if drift.get("contract") != "schema-drift-inventory/1" or drift.get("comparison_status") != "clean":
        raise ValueError("schema drift comparison is missing or not clean")

    archive_checksum = provider_archive_checksum_path.read_text(encoding="utf-8").strip().split()[0]
    if archive_checksum != _sha256(provider_bundle_path.read_bytes()):
        raise ValueError("provider bundle checksum file does not match provider bundle")
    provider_bundle_sha = str((provider.get("bundle") or {}).get("archive_sha256", ""))
    if provider_bundle_sha != archive_checksum:
        raise ValueError("provider receipt archive checksum does not match provider bundle")

    known_source = root / "release" / "v0.3-alpha-known-limitations.md"
    if not known_source.is_file():
        raise FileNotFoundError("release/v0.3-alpha-known-limitations.md is missing")
    known_output = output / "KNOWN_LIMITATIONS.md"
    shutil.copyfile(known_source, known_output)

    source_archive = output / f"sovereign-memory-core-{args.version}.tar.gz"
    source_artifact = _build_source_archive(root, args.version, args.commit, source_archive)

    provider_receipt_output = output / "PROVIDER_EXIT_RECEIPT.json"
    shutil.copyfile(provider_receipt_path, provider_receipt_output)
    provider_bundle_output = output / "PROVIDER_EXIT_FIXTURE.bundle.tar"
    shutil.copyfile(provider_bundle_path, provider_bundle_output)
    drift_output = output / "SCHEMA_DRIFT_RECEIPT.json"
    shutil.copyfile(drift_path, drift_output)

    evidence_artifacts = [
        source_artifact,
        _artifact(known_output, known_output.name, "known-limitations"),
        _artifact(provider_receipt_output, provider_receipt_output.name, "provider-exit-receipt"),
        _artifact(provider_bundle_output, provider_bundle_output.name, "provider-exit-fixture"),
        _artifact(drift_output, drift_output.name, "schema-drift-receipt"),
    ]

    perimeter = ((provider.get("verification") or {}).get("perimeter_report") or {})
    exact_assertion = str((provider.get("verification") or {}).get("assert_perimeter_closed", ""))
    if not (
        perimeter.get("contract_version") == "perimeter-report/1"
        and perimeter.get("evaluation_status") == "evaluated"
        and perimeter.get("perimeter_state") == "clean"
        and perimeter.get("violation_count") == 0
        and exact_assertion == "perimeter OK: perimeter-report/1 evaluated clean with zero findings"
    ):
        raise ValueError("provider-exit receipt does not contain a clean exact C1 perimeter result")

    manifest = {
        "contract": CONTRACT,
        "version": args.version,
        "repository": REPOSITORY,
        "release_candidate": {
            "commit": args.commit,
            "tree": args.tree,
        },
        "artifacts": [artifact.as_dict() for artifact in sorted(evidence_artifacts, key=lambda a: a.path)],
        "evidence": {
            "provider_exit": {
                "contract": provider.get("contract"),
                "archive_sha256": provider_bundle_sha,
                "manifest_sha256": (provider.get("bundle") or {}).get("manifest_sha256"),
                "source_unchanged": (provider.get("source") or {}).get("unchanged"),
                "destination_clean_before_restore": (provider.get("destination") or {}).get("clean_before_restore"),
                "positive_control_readable": (provider.get("verification") or {}).get("positive_control_readable"),
                "paired_private_denial": (provider.get("verification") or {}).get("paired_private_denial"),
            },
            "schema_drift": drift,
            "perimeter": {
                "contract_version": perimeter.get("contract_version"),
                "evaluation_status": perimeter.get("evaluation_status"),
                "perimeter_state": perimeter.get("perimeter_state"),
                "violation_count": perimeter.get("violation_count"),
                "assertion_result": exact_assertion,
            },
        },
        "tag_requirement": {
            "required": True,
            "candidate_tag": args.version,
            "must_resolve_to_exact_release_commit": True,
            "created_by_this_builder": False,
        },
        "release_authorization": {
            "owner_authorization_required": True,
            "performed_by_this_builder": False,
        },
    }
    manifest_path = output / "RELEASE_MANIFEST.json"
    manifest_path.write_bytes(_canonical_json(manifest))

    checksum_artifacts = [*evidence_artifacts, _artifact(manifest_path, manifest_path.name, "release-manifest")]
    checksum_lines = [f"{artifact.sha256}  {artifact.path}" for artifact in sorted(checksum_artifacts, key=lambda a: a.path)]
    checksums_path = output / "CHECKSUMS.sha256"
    checksums_path.write_text("\n".join(checksum_lines) + "\n", encoding="utf-8")

    summary = {
        "code": "RELEASE_CANDIDATE_BUILT",
        "version": args.version,
        "commit": args.commit,
        "tree": args.tree,
        "manifest_sha256": _sha256(manifest_path.read_bytes()),
        "checksums_sha256": _sha256(checksums_path.read_bytes()),
        "source_archive_sha256": source_artifact.sha256,
    }
    print(json.dumps(summary, sort_keys=True))
    return 0


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="v0.3-alpha")
    parser.add_argument("--commit", required=True)
    parser.add_argument("--tree", required=True)
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--proof-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    return parser


def main() -> int:
    try:
        return build(_parser().parse_args())
    except (OSError, UnicodeError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(json.dumps({"code": "RELEASE_CANDIDATE_ERROR", "error": str(exc)}, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
