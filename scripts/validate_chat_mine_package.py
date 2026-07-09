#!/usr/bin/env python3
"""Validate deterministic Chat-Mine package output against the core contract."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any


PACKAGE_FORMAT = "chat-mine.source-import-package.v1"
PROBE_CATEGORIES = {
    "positive",
    "negative",
    "conflict",
    "stale_state",
    "evidence_request",
}
ACTION_ZONES = {
    "import": {"HOUSE", "VAULT"},
    "hold": {"HOLD"},
    "exclude": {"EVIDENCE"},
    "evidence": {"EVIDENCE"},
}


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=True, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


def sha256_hex(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def validate_candidate(
    candidate: dict[str, Any],
    messages: list[dict[str, Any]],
) -> None:
    key = candidate["manifest_key"]
    action = candidate["action"]
    require(
        candidate["target_zone"] in ACTION_ZONES.get(action, set()),
        f"{key}: action/target_zone does not satisfy source_manifest",
    )
    require(
        "source_payload_hash_at_review" not in candidate,
        f"{key}: producer must not claim an unperformed review",
    )
    locator = candidate.get("source_locator")
    if action in {"import", "hold"}:
        require(
            isinstance(locator, dict) and bool(locator),
            f"{key}: import/HOLD candidate requires source_locator",
        )
        require(
            bool(candidate.get("source_quote_hash")),
            f"{key}: import/HOLD candidate requires source_quote_hash",
        )
    require(isinstance(locator, dict) and bool(locator), f"{key}: source_locator is required")
    message = messages[locator["message_index"]]
    require(message["message_id"] == locator["message_id"], f"{key}: locator mismatch")
    quote = message["content"][
        locator["character_start"] : locator["character_end"]
    ]
    require(quote == candidate["source_quote"], f"{key}: quote locator mismatch")
    require(
        candidate["source_quote_hash_algorithm"] == "sha256",
        f"{key}: unsupported quote hash algorithm",
    )
    require(
        sha256_hex(quote.encode("utf-8")) == candidate.get("source_quote_hash"),
        f"{key}: quote hash mismatch",
    )


def validate_package(package: dict[str, Any]) -> None:
    require(package["package_format"] == PACKAGE_FORMAT, "unknown package format")
    require(package["hash_algorithm"] == "sha256", "unsupported package hash")

    checksum = package.pop("package_checksum")
    require(
        sha256_hex(canonical_bytes(package)) == checksum,
        "package checksum mismatch",
    )
    package["package_checksum"] = checksum

    source_items = package["source_items"]
    batch = package["batch"]
    require(
        batch["source_item_count"] == batch["exported_item_count"] == len(source_items),
        "batch counts do not match source items",
    )
    require(len(source_items) > 0, "package must contain source items")

    item_keys: set[str] = set()
    demonstrates_one_to_many = False
    for item in source_items:
        item_key = item["source_item_key"]
        require(item_key not in item_keys, f"duplicate source_item_key: {item_key}")
        item_keys.add(item_key)

        payload = canonical_bytes(item["raw_payload"])
        require(
            sha256_hex(payload) == item["payload_hash"],
            f"{item_key}: payload hash mismatch",
        )
        require(len(payload) == item["payload_size_bytes"], f"{item_key}: payload size")
        evidence = item["payload_evidence"]
        require(len(evidence) > 0, f"{item_key}: missing payload evidence")
        require(
            any(row.get("payload_hash") == item["payload_hash"] for row in evidence),
            f"{item_key}: evidence does not preserve the raw payload hash",
        )

        candidates = item["manifest_candidates"]
        demonstrates_one_to_many = demonstrates_one_to_many or len(candidates) > 1
        manifest_keys: set[str] = set()
        for candidate in candidates:
            key = candidate["manifest_key"]
            require(key not in manifest_keys, f"{item_key}: duplicate manifest_key {key}")
            manifest_keys.add(key)
            validate_candidate(candidate, item["raw_payload"]["messages"])

    require(
        demonstrates_one_to_many,
        "fixture must demonstrate one source item producing multiple candidates",
    )

    probes = package["cutover_probes"]
    probe_keys = [probe["probe_key"] for probe in probes]
    require(len(probe_keys) == len(set(probe_keys)), "duplicate probe_key")
    categories = {probe["probe_category"] for probe in probes if probe.get("active", True)}
    require(categories == PROBE_CATEGORIES, "active probes must cover all five categories")
    require(
        all(
            probe.get("expected_source_item_key") in item_keys
            for probe in probes
            if probe.get("expected_source_item_key")
        ),
        "probe references an unknown source item",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    args = parser.parse_args()

    try:
        package = json.loads(args.package.read_text(encoding="utf-8"))
        validate_package(package)
    except (IndexError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1) from None
    print(
        f"PASS: {len(package['source_items'])} source item(s), "
        f"{sum(len(item['manifest_candidates']) for item in package['source_items'])} "
        f"manifest candidate(s), {len(package['cutover_probes'])} cutover probe(s)"
    )


if __name__ == "__main__":
    main()
