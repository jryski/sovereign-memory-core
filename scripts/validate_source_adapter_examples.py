#!/usr/bin/env python3
"""Validate synthetic source-adapter examples.

The checker recomputes payload hashes and file checksums from the raw sample
inputs, then checks manifest counts, classification coverage, and stale-state
quarantine. It does not connect to a database and it does not mark a batch ready.
"""

from __future__ import annotations

import copy
import csv
import hashlib
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / "examples" / "source-adapters"
EXAMPLE_DIRS = (
    "chat-export-jsonl",
    "project-container",
    "markdown-wiki",
    "row-memory-store",
    "sql-table-export",
)
DRAFT_FORMAT = "source-adapter.manifest-draft.v1"
DRAFT_NOTE = (
    "Synthetic manifest draft. Suggestions are not approved truth. "
    "This draft does not mark a batch ready for cutover."
)
ZONES = ("HOUSE", "VAULT", "HOLD", "EVIDENCE")
AUTHORS = {"person-1", "agent-1"}
LEGAL_ACTION_ZONE = {
    ("import", "HOUSE"),
    ("import", "VAULT"),
    ("hold", "HOLD"),
    ("exclude", "EVIDENCE"),
    ("evidence", "EVIDENCE"),
}
PROBE_CATEGORIES = {
    "positive",
    "negative",
    "conflict",
    "stale_state",
    "evidence_request",
}
FORBIDDEN_KEYS = {
    "reviewed_by",
    "reviewed_at",
    "source_payload_hash_at_review",
    "package_checksum",
}
COUNT_KEYS = (
    "source_item_count",
    "exported_item_count",
    "candidate_count",
    "import_count",
    "hold_count",
    "evidence_count",
    "exclude_count",
    "rejected_count",
    "held_excluded_or_rejected_count",
)
SAFETY_PATTERNS = (
    re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
    re.compile(r"supabase", re.IGNORECASE),
    re.compile(r"/Users/"),
    re.compile(r"/home/"),
    re.compile(r"AKIA"),
    re.compile(r"sk-"),
    re.compile(r"api_key", re.IGNORECASE),
    re.compile(r"password", re.IGNORECASE),
    re.compile(r"BEGIN [A-Z ]*PRIVATE KEY"),
)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def split_record_lines(data: bytes, label: str, errors: list[str]) -> list[bytes] | None:
    if b"\r" in data:
        errors.append(f"{label}: carriage return is not allowed")
        return None
    if not data.endswith(b"\n"):
        errors.append(f"{label}: file must end with a newline")
        return None
    lines = data.split(b"\n")[:-1]
    if any(line == b"" for line in lines):
        errors.append(f"{label}: empty line is not allowed")
        return None
    return lines


def payload_bytes(example: Path, spec: dict, label: str, errors: list[str]) -> bytes | None:
    relative = spec["file"]
    path = example / relative
    if Path(relative).is_absolute() or ".." in Path(relative).parts:
        errors.append(f"{label}: payload file must stay inside the example")
        return None
    if not path.is_file():
        errors.append(f"{label}: missing payload file {relative}")
        return None
    data = path.read_bytes()
    basis = spec["basis"]
    if basis == "file_bytes":
        return data
    lines = split_record_lines(data, f"{label}:{relative}", errors)
    if lines is None:
        return None
    if basis == "jsonl_line":
        matches = []
        for line in lines:
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                errors.append(f"{label}: invalid JSONL ({exc})")
                return None
            if row.get(spec["match_field"]) == spec["match_value"]:
                matches.append(line)
        if len(matches) != 1:
            errors.append(
                f"{label}: expected one JSONL match for {spec['match_value']}, found {len(matches)}"
            )
            return None
        return matches[0]
    if basis == "csv_row":
        matches = []
        header = next(csv.reader([lines[0].decode("utf-8")]))
        try:
            field_index = header.index(spec["match_field"])
        except ValueError:
            errors.append(f"{label}: CSV header lacks {spec['match_field']}")
            return None
        for line in lines[1:]:
            row = next(csv.reader([line.decode("utf-8")]))
            if row[field_index] == spec["match_value"]:
                matches.append(line)
        if len(matches) != 1:
            errors.append(
                f"{label}: expected one CSV match for {spec['match_value']}, found {len(matches)}"
            )
            return None
        return matches[0]
    errors.append(f"{label}: unknown payload basis {basis}")
    return None


def require_keys(label: str, obj: dict, allowed: set[str], required: set[str], errors: list[str]) -> None:
    missing = required - set(obj)
    extra = set(obj) - allowed
    if missing:
        errors.append(f"{label}: missing keys {sorted(missing)}")
    if extra:
        errors.append(f"{label}: unexpected keys {sorted(extra)}")


def forbid_review_keys(label: str, value, errors: list[str]) -> None:
    if isinstance(value, dict):
        found = FORBIDDEN_KEYS.intersection(value)
        if found:
            errors.append(f"{label}: draft contains review-owned keys {sorted(found)}")
        for child in value.values():
            forbid_review_keys(label, child, errors)
    elif isinstance(value, list):
        for child in value:
            forbid_review_keys(label, child, errors)


def collapsed(text: str) -> str:
    return re.sub(r"\s+", " ", text)


def count_sentence(verification: dict) -> str:
    body = ", ".join(f"{key}={verification[key]}" for key in COUNT_KEYS)
    return f"Verification counts: {body}."


def derived_counts(items: list[dict]) -> dict[str, int]:
    actions = [
        candidate["action"]
        for item in items
        for candidate in item["manifest_candidates"]
    ]
    hold_count = actions.count("hold")
    exclude_count = actions.count("exclude")
    rejected_count = 0
    return {
        "candidate_count": len(actions),
        "evidence_count": actions.count("evidence"),
        "exclude_count": exclude_count,
        "exported_item_count": len(items),
        "held_excluded_or_rejected_count": hold_count + exclude_count + rejected_count,
        "hold_count": hold_count,
        "import_count": actions.count("import"),
        "rejected_count": rejected_count,
        "source_item_count": len(items),
    }


def raw_files(example: Path) -> list[Path]:
    return sorted(
        (
            path
            for path in example.rglob("*")
            if path.is_file()
            and path.name not in {"expected-manifest.json", "classification-notes.md"}
        ),
        key=lambda path: path.relative_to(example).as_posix(),
    )


def check_safety(errors: list[str]) -> None:
    for path in sorted(EXAMPLES.rglob("*")):
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT).as_posix()
        for pattern in SAFETY_PATTERNS:
            if pattern.search(text):
                errors.append(f"{relative}: public-safety pattern {pattern.pattern!r} matched")


def check_readme(errors: list[str]) -> None:
    readme = collapsed((EXAMPLES / "README.md").read_text(encoding="utf-8"))
    required = [
        *EXAMPLE_DIRS,
        "not the default import path",
        "synthetic",
        "sha256",
        *ZONES,
        "stale",
        "python3 scripts/validate_source_adapter_examples.py",
    ]
    for phrase in required:
        if phrase not in readme and phrase.lower() not in readme.lower():
            errors.append(f"examples/source-adapters/README.md: missing {phrase!r}")


def check_manifest_coverage(example: Path, draft: dict, errors: list[str]) -> None:
    name = example.name
    items = draft["source_items"]
    zones = {candidate["target_zone"] for item in items for candidate in item["manifest_candidates"]}
    missing_zones = [zone for zone in ZONES if zone not in zones]
    if missing_zones:
        errors.append(f"{name}: manifest omits zones {missing_zones}")

    stale = [
        candidate
        for item in items
        for candidate in item["manifest_candidates"]
        if candidate.get("metadata", {}).get("quarantine_reason") == "stale_state"
        and candidate.get("action") == "hold"
        and candidate.get("target_zone") == "HOLD"
        and candidate.get("review_state") == "needs_review"
    ]
    if not stale:
        errors.append(f"{name}: missing stale-state quarantine candidate")

    probes = [
        probe
        for probe in draft["cutover_probe_candidates"]
        if probe.get("probe_category") == "stale_state"
    ]
    if not probes:
        errors.append(f"{name}: missing stale_state cutover probe candidate")

    if draft["adapter_profile"].get("is_default_import_path") is not False:
        errors.append(f"{name}: adapter profile must set is_default_import_path false")
    description = draft["source_system"].get("description", "")
    if "not the default import path" not in description:
        errors.append(f"{name}: source description must say it is not the default import path")


def check_notes(example: Path, draft: dict, errors: list[str]) -> None:
    notes_path = example / "classification-notes.md"
    if not notes_path.is_file():
        errors.append(f"{example.name}: missing classification-notes.md")
        return
    notes = collapsed(notes_path.read_text(encoding="utf-8"))
    required = [
        "not the default import path",
        "sha256",
        "Stale-state quarantine",
        *ZONES,
        count_sentence(draft["verification"]),
    ]
    for phrase in required:
        if phrase not in notes:
            errors.append(f"{example.name}/classification-notes.md: missing {phrase!r}")
    for item in draft["source_items"]:
        if item["source_item_key"] not in notes:
            errors.append(
                f"{example.name}/classification-notes.md: missing source item {item['source_item_key']}"
            )
        for candidate in item["manifest_candidates"]:
            if candidate["manifest_key"] not in notes:
                errors.append(
                    f"{example.name}/classification-notes.md: missing manifest key {candidate['manifest_key']}"
                )
    for probe in draft["cutover_probe_candidates"]:
        if probe["probe_key"] not in notes:
            errors.append(
                f"{example.name}/classification-notes.md: missing probe {probe['probe_key']}"
            )


def check_items(example: Path, draft: dict, errors: list[str]) -> None:
    name = example.name
    items = draft["source_items"]
    keys = [item["source_item_key"] for item in items]
    if len(keys) != len(set(keys)):
        errors.append(f"{name}: duplicate source item keys")
    manifest_keys = [
        candidate["manifest_key"]
        for item in items
        for candidate in item["manifest_candidates"]
    ]
    if len(manifest_keys) != len(set(manifest_keys)):
        errors.append(f"{name}: duplicate manifest keys")

    profile_id = draft["adapter_profile"]["profile_id"]
    item_keys = set(keys)
    for item in items:
        label = f"{name}:{item.get('source_item_key', '?')}"
        require_keys(
            label,
            item,
            {
                "content_type",
                "manifest_candidates",
                "metadata",
                "payload",
                "payload_evidence",
                "payload_hash",
                "payload_size_bytes",
                "raw_payload_location",
                "source_author",
                "source_container",
                "source_created_at",
                "source_item_key",
                "source_kind",
                "source_ref",
                "source_updated_at",
                "title",
            },
            {
                "content_type",
                "manifest_candidates",
                "metadata",
                "payload",
                "payload_evidence",
                "payload_hash",
                "payload_size_bytes",
                "raw_payload_location",
                "source_author",
                "source_container",
                "source_created_at",
                "source_item_key",
                "source_kind",
                "source_ref",
                "source_updated_at",
                "title",
            },
            errors,
        )
        if item.get("source_author") not in AUTHORS:
            errors.append(f"{label}: source_author must be a synthetic actor")
        if item.get("source_ref") != item.get("source_item_key"):
            errors.append(f"{label}: source_ref must stay equal to the source item key")
        if item.get("metadata") != {"timestamp_source": item.get("metadata", {}).get("timestamp_source")}:
            errors.append(f"{label}: unexpected item metadata")
        if item.get("metadata", {}).get("timestamp_source") not in {"source_field", "export_watermark"}:
            errors.append(f"{label}: timestamp_source is missing")

        spec = item.get("payload", {})
        require_keys(
            f"{label}:payload",
            spec,
            {"basis", "file", "match_field", "match_value"},
            {"basis", "file"},
            errors,
        )
        if spec.get("basis") == "file_bytes" and ("match_field" in spec or "match_value" in spec):
            errors.append(f"{label}: file payloads do not use a match field")
        if spec.get("basis") in {"jsonl_line", "csv_row"} and (
            "match_field" not in spec or "match_value" not in spec
        ):
            errors.append(f"{label}: row payloads require match_field and match_value")
        if spec.get("match_value") not in (None, item.get("source_item_key")):
            errors.append(f"{label}: match_value must equal the source item key")

        raw = payload_bytes(example, spec, label, errors) if "file" in spec and "basis" in spec else None
        if raw is not None:
            digest = sha256_hex(raw)
            if item.get("payload_hash") != digest:
                errors.append(f"{label}: payload_hash does not match raw bytes")
            if item.get("payload_size_bytes") != len(raw):
                errors.append(f"{label}: payload_size_bytes does not match raw bytes")
            text = raw.decode("utf-8")
        else:
            text = ""

        expected_location = spec.get("file")
        if spec.get("basis") in {"jsonl_line", "csv_row"}:
            expected_location = f"{spec.get('file')}#{item.get('source_item_key')}"
        if item.get("raw_payload_location") != expected_location:
            errors.append(f"{label}: raw_payload_location does not match the payload basis")

        evidence = item.get("payload_evidence")
        if not isinstance(evidence, list) or len(evidence) != 1:
            errors.append(f"{label}: expected one raw payload evidence row")
        elif raw is not None:
            row = evidence[0]
            require_keys(
                f"{label}:evidence",
                row,
                {
                    "evidence_kind",
                    "hash_algorithm",
                    "location",
                    "metadata",
                    "payload_hash",
                    "size_bytes",
                },
                {
                    "evidence_kind",
                    "hash_algorithm",
                    "location",
                    "metadata",
                    "payload_hash",
                    "size_bytes",
                },
                errors,
            )
            if row.get("evidence_kind") != "raw_payload" or row.get("hash_algorithm") != "sha256":
                errors.append(f"{label}: payload evidence must be sha256 raw_payload")
            if row.get("location") != item.get("raw_payload_location"):
                errors.append(f"{label}: payload evidence location drifted")
            if row.get("payload_hash") != item.get("payload_hash") or row.get("size_bytes") != len(raw):
                errors.append(f"{label}: payload evidence hash or size drifted")
            if row.get("metadata") != {"encoding": "utf-8"}:
                errors.append(f"{label}: payload evidence encoding metadata drifted")

        for candidate in item.get("manifest_candidates", []):
            check_candidate(
                f"{label}:{candidate.get('manifest_key', '?')}",
                candidate,
                text,
                profile_id,
                item_keys,
                errors,
            )


def check_candidate(
    label: str,
    candidate: dict,
    payload_text: str,
    profile_id: str,
    item_keys: set[str],
    errors: list[str],
) -> None:
    require_keys(
        label,
        candidate,
        {
            "action",
            "custodian",
            "lifecycle_status",
            "manifest_key",
            "metadata",
            "preservation_class",
            "review_notes",
            "review_state",
            "sensitivity",
            "source_quote",
            "source_quote_hash",
            "source_quote_hash_algorithm",
            "subject_ref",
            "suggested_content",
            "suggested_summary",
            "target_table",
            "target_zone",
            "topic_key",
            "transformation_version",
            "workstream",
        },
        {
            "action",
            "lifecycle_status",
            "manifest_key",
            "metadata",
            "preservation_class",
            "review_notes",
            "review_state",
            "sensitivity",
            "source_quote",
            "source_quote_hash",
            "source_quote_hash_algorithm",
            "suggested_content",
            "suggested_summary",
            "target_zone",
            "topic_key",
            "transformation_version",
            "workstream",
        },
        errors,
    )
    action = candidate.get("action")
    zone = candidate.get("target_zone")
    if (action, zone) not in LEGAL_ACTION_ZONE:
        errors.append(f"{label}: action/zone pair {action}/{zone} is not in the source manifest check")
    if candidate.get("transformation_version") != profile_id:
        errors.append(f"{label}: transformation_version must match the adapter profile")
    if candidate.get("workstream") != "example-project":
        errors.append(f"{label}: workstream drifted from the synthetic example")
    if candidate.get("source_quote_hash_algorithm") != "sha256":
        errors.append(f"{label}: quote hash algorithm must be sha256")
    quote = candidate.get("source_quote", "")
    if payload_text and payload_text.count(quote) != 1:
        errors.append(f"{label}: source quote must occur once in the raw payload")
    if quote and candidate.get("source_quote_hash") != sha256_hex(quote.encode("utf-8")):
        errors.append(f"{label}: source_quote_hash does not match the quote bytes")
    if candidate.get("suggested_content") != quote:
        errors.append(f"{label}: suggested_content must preserve the source quote")

    expected = {
        ("import", "HOUSE"): ("unreviewed", "proposed", "durable", "ordinary", True, False),
        ("import", "VAULT"): ("needs_review", "proposed", "restricted", "restricted", False, True),
        ("hold", "HOLD"): ("needs_review", "stale", "quarantine", "ordinary", False, False),
        ("evidence", "EVIDENCE"): ("unreviewed", "evidence", "process", "ordinary", False, False),
    }.get((action, zone))
    if expected is None:
        return
    review_state, lifecycle, preservation, sensitivity, wants_table, wants_subject = expected
    if candidate.get("review_state") != review_state:
        errors.append(f"{label}: review_state must stay {review_state}")
    if candidate.get("lifecycle_status") != lifecycle:
        errors.append(f"{label}: lifecycle_status must stay {lifecycle}")
    if candidate.get("preservation_class") != preservation:
        errors.append(f"{label}: preservation_class must stay {preservation}")
    if candidate.get("sensitivity") != sensitivity:
        errors.append(f"{label}: sensitivity must stay {sensitivity}")
    if wants_table:
        if candidate.get("target_table") not in {"memories", "wiki_pages"}:
            errors.append(f"{label}: HOUSE import needs target_table memories or wiki_pages")
    elif "target_table" in candidate:
        errors.append(f"{label}: target_table belongs only on a HOUSE import suggestion")
    if wants_subject:
        if candidate.get("custodian") != "person-1" or candidate.get("subject_ref") != "vault-subject-demo-1":
            errors.append(f"{label}: VAULT suggestion needs the synthetic custodian and subject")
    elif "custodian" in candidate or "subject_ref" in candidate:
        errors.append(f"{label}: custodian and subject_ref belong only on a VAULT suggestion")

    metadata = candidate.get("metadata", {})
    allowed_metadata = {"producer_posture", "quarantine_reason", "superseded_by_source_item_key"}
    if set(metadata) - allowed_metadata:
        errors.append(f"{label}: unexpected candidate metadata {sorted(set(metadata) - allowed_metadata)}")
    if action == "hold":
        if metadata.get("quarantine_reason") != "stale_state":
            errors.append(f"{label}: HOLD candidate must record stale_state quarantine")
        if metadata.get("producer_posture") != "stale_state_quarantine":
            errors.append(f"{label}: HOLD candidate posture must be stale_state_quarantine")
        successor = metadata.get("superseded_by_source_item_key")
        if successor is not None and successor not in item_keys:
            errors.append(f"{label}: successor {successor} is not a source item in this draft")
    elif "quarantine_reason" in metadata or "superseded_by_source_item_key" in metadata:
        errors.append(f"{label}: quarantine metadata belongs on the HOLD candidate")


def check_verification(example: Path, draft: dict, errors: list[str]) -> None:
    name = example.name
    verification = draft["verification"]
    require_keys(
        f"{name}:verification",
        verification,
        set(COUNT_KEYS) | {"payload_hash_algorithm", "raw_input_files"},
        set(COUNT_KEYS) | {"payload_hash_algorithm", "raw_input_files"},
        errors,
    )
    expected_counts = derived_counts(draft["source_items"])
    for key, value in expected_counts.items():
        if verification.get(key) != value:
            errors.append(f"{name}: verification {key} is {verification.get(key)}, expected {value}")
    if verification.get("payload_hash_algorithm") != "sha256":
        errors.append(f"{name}: verification hash algorithm must be sha256")
    if draft["batch"].get("source_item_count") != expected_counts["source_item_count"]:
        errors.append(f"{name}: batch source_item_count drifted")
    if draft["batch"].get("exported_item_count") != expected_counts["exported_item_count"]:
        errors.append(f"{name}: batch exported_item_count drifted")
    if draft["batch"]["watermark"].get("source_item_count") != expected_counts["source_item_count"]:
        errors.append(f"{name}: watermark source_item_count drifted")
    max_updated = max(item["source_updated_at"] for item in draft["source_items"])
    if draft["batch"]["watermark"].get("max_updated_at") != max_updated:
        errors.append(f"{name}: watermark max_updated_at drifted")

    files = raw_files(example)
    listed = verification.get("raw_input_files", [])
    listed_paths = [row.get("path") for row in listed]
    actual_paths = [path.relative_to(example).as_posix() for path in files]
    if listed_paths != actual_paths:
        errors.append(f"{name}: raw_input_files does not match the sample files")
    for path, row in zip(files, listed):
        data = path.read_bytes()
        if row.get("sha256") != sha256_hex(data) or row.get("size_bytes") != len(data):
            errors.append(f"{name}: checksum drifted for {row.get('path')}")

    by_file: dict[str, list[dict]] = {}
    for item in draft["source_items"]:
        by_file.setdefault(item["payload"]["file"], []).append(item)
    if sorted(by_file) != actual_paths:
        errors.append(f"{name}: a raw file has no source item, or an item names a missing file")
    for relative, group in by_file.items():
        basis = {item["payload"]["basis"] for item in group}
        if len(basis) != 1:
            errors.append(f"{name}:{relative}: mixed payload bases")
            continue
        kind = next(iter(basis))
        data = (example / relative).read_bytes()
        if kind == "file_bytes":
            if len(group) != 1:
                errors.append(f"{name}:{relative}: a file payload must be one source item")
            continue
        lines = split_record_lines(data, f"{name}:{relative}", errors)
        if lines is None:
            continue
        if kind == "csv_row":
            lines = lines[1:]
        if len(lines) != len(group):
            errors.append(
                f"{name}:{relative}: raw record count {len(lines)} != source item count {len(group)}"
            )


def check_probes(example_name: str, draft: dict, errors: list[str]) -> None:
    probes = draft["cutover_probe_candidates"]
    if not isinstance(probes, list) or not probes:
        errors.append(f"{example_name}: missing cutover probe candidates")
        return
    item_keys = {item["source_item_key"] for item in draft["source_items"]}
    probe_keys = [probe.get("probe_key") for probe in probes]
    if len(probe_keys) != len(set(probe_keys)):
        errors.append(f"{example_name}: duplicate probe keys")
    for probe in probes:
        label = f"{example_name}:{probe.get('probe_key', '?')}"
        require_keys(
            label,
            probe,
            {
                "expected_behavior",
                "expected_source_item_key",
                "probe_category",
                "probe_key",
                "probe_type",
                "prompt",
                "severity",
            },
            {
                "expected_behavior",
                "expected_source_item_key",
                "probe_category",
                "probe_key",
                "probe_type",
                "prompt",
                "severity",
            },
            errors,
        )
        if probe.get("probe_category") not in PROBE_CATEGORIES:
            errors.append(f"{label}: probe category is outside the cutover set")
        if probe.get("severity") != "critical":
            errors.append(f"{label}: example probes stay critical")
        if probe.get("expected_source_item_key") not in item_keys:
            errors.append(f"{label}: probe source item is not in this draft")


def check_example(example: Path, draft: dict | None = None) -> list[str]:
    errors: list[str] = []
    manifest_path = example / "expected-manifest.json"
    if draft is None:
        if not manifest_path.is_file():
            return [f"{example.name}: missing expected-manifest.json"]
        draft = json.loads(manifest_path.read_text(encoding="utf-8"))
    name = example.name
    forbid_review_keys(name, draft, errors)
    require_keys(
        name,
        draft,
        {
            "adapter_profile",
            "batch",
            "cutover_probe_candidates",
            "draft_format",
            "draft_note",
            "hash_algorithm",
            "source_items",
            "source_system",
            "verification",
        },
        {
            "adapter_profile",
            "batch",
            "cutover_probe_candidates",
            "draft_format",
            "draft_note",
            "hash_algorithm",
            "source_items",
            "source_system",
            "verification",
        },
        errors,
    )
    if draft.get("draft_format") != DRAFT_FORMAT:
        errors.append(f"{name}: draft_format must be {DRAFT_FORMAT}")
    if draft.get("draft_note") != DRAFT_NOTE:
        errors.append(f"{name}: draft_note drifted")
    if draft.get("hash_algorithm") != "sha256":
        errors.append(f"{name}: hash_algorithm must be sha256")

    system = draft.get("source_system", {})
    require_keys(
        f"{name}:source_system",
        system,
        {
            "adapter_name",
            "adapter_version",
            "description",
            "display_name",
            "owner",
            "source_key",
            "source_type",
            "visibility",
        },
        {
            "adapter_name",
            "adapter_version",
            "description",
            "display_name",
            "owner",
            "source_key",
            "source_type",
            "visibility",
        },
        errors,
    )
    if system.get("owner") != "shared" or system.get("visibility") != "shared":
        errors.append(f"{name}: example source system stays shared")
    if system.get("adapter_version") != "example-v1":
        errors.append(f"{name}: adapter_version must stay example-v1")

    profile = draft.get("adapter_profile", {})
    require_keys(
        f"{name}:adapter_profile",
        profile,
        {
            "evidence_posture",
            "is_default_import_path",
            "lossiness",
            "mapping",
            "profile_id",
            "source_identity",
            "unsupported",
        },
        {
            "evidence_posture",
            "is_default_import_path",
            "lossiness",
            "mapping",
            "profile_id",
            "source_identity",
            "unsupported",
        },
        errors,
    )
    if profile.get("unsupported") != [
        "approval",
        "deduplication",
        "conflict resolution",
        "authoritative cutover",
    ]:
        errors.append(f"{name}: adapter profile must declare the unsupported authority steps")

    batch = draft.get("batch", {})
    require_keys(
        f"{name}:batch",
        batch,
        {
            "batch_key",
            "export_completed_at",
            "export_started_at",
            "exported_by",
            "exported_item_count",
            "metadata",
            "payload_hash_algorithm",
            "source_item_count",
            "status",
            "watermark",
        },
        {
            "batch_key",
            "export_completed_at",
            "export_started_at",
            "exported_by",
            "exported_item_count",
            "metadata",
            "payload_hash_algorithm",
            "source_item_count",
            "status",
            "watermark",
        },
        errors,
    )
    if batch.get("status") != "open":
        errors.append(f"{name}: batch status must stay open")
    if batch.get("payload_hash_algorithm") != "sha256":
        errors.append(f"{name}: batch hash algorithm must be sha256")
    if batch.get("exported_by") != "agent-1":
        errors.append(f"{name}: exported_by must be the synthetic actor agent-1")
    if batch.get("metadata") != {
        "producer": "example-source-adapter-draft",
        "ready_for_cutover": False,
    }:
        errors.append(f"{name}: batch must stay an unready draft")
    if not str(batch.get("batch_key", "")).startswith(str(system.get("source_key", ""))):
        errors.append(f"{name}: batch_key must start with the source key")

    if "source_items" in draft and "verification" in draft and "adapter_profile" in draft:
        check_items(example, draft, errors)
        check_verification(example, draft, errors)
        check_probes(name, draft, errors)
        check_manifest_coverage(example, draft, errors)
        if draft is not None and (example / "classification-notes.md").is_file():
            check_notes(example, draft, errors)
    return errors


def self_test(errors: list[str]) -> None:
    example = EXAMPLES / "chat-export-jsonl"
    original = json.loads((example / "expected-manifest.json").read_text(encoding="utf-8"))

    mutated = copy.deepcopy(original)
    mutated["source_items"][0]["payload_hash"] = "0" * 64
    if not any("payload_hash" in error for error in check_example(example, mutated)):
        errors.append("self-test: corrupted payload hash was accepted")

    mutated = copy.deepcopy(original)
    mutated["source_items"][0]["manifest_candidates"][0]["target_zone"] = "HOLD"
    if not any("action/zone" in error for error in check_example(example, mutated)):
        errors.append("self-test: illegal action/zone pair was accepted")

    mutated = copy.deepcopy(original)
    mutated["adapter_profile"]["is_default_import_path"] = True
    if not any("is_default_import_path" in error for error in check_example(example, mutated)):
        errors.append("self-test: default import path claim was accepted")

    mutated = copy.deepcopy(original)
    mutated["source_items"][0]["manifest_candidates"][0]["review_state"] = "approved"
    if not any("review_state" in error for error in check_example(example, mutated)):
        errors.append("self-test: approved review state was accepted")


def main() -> int:
    errors: list[str] = []
    children = sorted(path.name for path in EXAMPLES.iterdir())
    expected_children = sorted([*EXAMPLE_DIRS, "README.md"])
    if children != expected_children:
        errors.append(
            f"examples/source-adapters children {children} != {expected_children}"
        )
    check_readme(errors)
    check_safety(errors)
    for name in EXAMPLE_DIRS:
        errors.extend(check_example(EXAMPLES / name))
    if not errors:
        self_test(errors)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(f"validated {len(EXAMPLE_DIRS)} synthetic source-adapter examples")
    return 0


if __name__ == "__main__":
    sys.exit(main())
