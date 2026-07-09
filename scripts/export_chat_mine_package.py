#!/usr/bin/env python3
"""Export an internal Chat-Mine fixture into the core source-import package shape."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


PACKAGE_FORMAT = "chat-mine.source-import-package.v1"
HASH_ALGORITHM = "sha256"
ADAPTER_NAME = "chat-mine"
ADAPTER_VERSION = "0.1.0"


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=True, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")


def sha256_hex(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def locate_quote(conversation: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    message_id = candidate["message_id"]
    matches = [
        (index, message)
        for index, message in enumerate(conversation["messages"])
        if message["message_id"] == message_id
    ]
    if len(matches) != 1:
        raise ValueError(
            f"candidate {candidate['manifest_key']!r} must reference one message"
        )

    message_index, message = matches[0]
    quote = candidate["source_quote"]
    start = message["content"].find(quote)
    if start < 0 or message["content"].find(quote, start + 1) >= 0:
        raise ValueError(
            f"candidate {candidate['manifest_key']!r} quote must occur once"
        )

    return {
        "message_id": message_id,
        "message_index": message_index,
        "character_start": start,
        "character_end": start + len(quote),
    }


def export_candidate(
    conversation: dict[str, Any],
    candidate: dict[str, Any],
) -> dict[str, Any]:
    output = {
        key: value
        for key, value in candidate.items()
        if key not in {"message_id"}
    }
    output["source_locator"] = locate_quote(conversation, candidate)
    output["source_quote_hash"] = sha256_hex(
        candidate["source_quote"].encode("utf-8")
    )
    output["source_quote_hash_algorithm"] = HASH_ALGORITHM
    return output


def export_source_item(conversation: dict[str, Any]) -> dict[str, Any]:
    raw_payload = {
        key: value
        for key, value in conversation.items()
        if key != "manifest_candidates"
    }
    payload = canonical_bytes(raw_payload)
    payload_hash = sha256_hex(payload)
    source_item_key = conversation["conversation_id"]
    location = f"chat-mine://conversations/{source_item_key}"

    return {
        "source_item_key": source_item_key,
        "source_container": "chat-mine/conversations",
        "source_kind": "conversation",
        "source_created_at": conversation.get("created_at"),
        "source_updated_at": conversation.get("updated_at"),
        "content_type": "application/json",
        "title": conversation.get("title"),
        "payload_hash": payload_hash,
        "payload_size_bytes": len(payload),
        "raw_payload_location": location,
        "source_ref": source_item_key,
        "metadata": {
            "participant_roles": sorted(set(conversation.get("participants", []))),
            "message_count": len(conversation["messages"]),
        },
        "raw_payload": raw_payload,
        "payload_evidence": [
            {
                "evidence_kind": "raw_payload",
                "location": location,
                "payload_hash": payload_hash,
                "hash_algorithm": HASH_ALGORITHM,
                "size_bytes": len(payload),
                "content_preview": conversation.get("title"),
                "metadata": {"encoding": "utf-8", "canonical_json": True},
            }
        ],
        "manifest_candidates": [
            export_candidate(conversation, candidate)
            for candidate in sorted(
                conversation["manifest_candidates"],
                key=lambda row: row["manifest_key"],
            )
        ],
    }


def build_package(export: dict[str, Any]) -> dict[str, Any]:
    source_items = [
        export_source_item(conversation)
        for conversation in sorted(
            export["conversations"], key=lambda row: row["conversation_id"]
        )
    ]
    source_system = {
        **export["source_system"],
        "adapter_name": ADAPTER_NAME,
        "adapter_version": ADAPTER_VERSION,
        "active": True,
        "metadata": {"package_format": PACKAGE_FORMAT},
    }
    batch = {
        **export["batch"],
        "status": "open",
        "source_item_count": len(export["conversations"]),
        "exported_item_count": len(source_items),
        "payload_hash_algorithm": HASH_ALGORITHM,
        "metadata": {"producer": ADAPTER_NAME},
    }
    package = {
        "package_format": PACKAGE_FORMAT,
        "hash_algorithm": HASH_ALGORITHM,
        "source_system": source_system,
        "batch": batch,
        "source_items": source_items,
        "cutover_probes": sorted(
            export.get("cutover_probes", []), key=lambda row: row["probe_key"]
        ),
    }
    package["package_checksum"] = sha256_hex(canonical_bytes(package))
    return package


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    source = json.loads(args.input.read_text(encoding="utf-8"))
    package = build_package(source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(package, ensure_ascii=True, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
