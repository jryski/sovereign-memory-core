#!/usr/bin/env python3
"""Validate the synthetic offline SMP fixture and emit a custody receipt.

The checker reads only the fixture directory. It does not open a database,
contact a source system, or use the network. Functional probes that would
need a restored PostgreSQL instance are checked against the recorded probe
results and the destination-store description.

Success prints one canonical custody receipt on stdout and ``SMP-complete``
on stderr. Failure prints the same receipt shape with result
``verification_failed`` and names the failed checks. This is not a Draft 0.3
conformance claim.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping

try:
    from scripts.sovereignty_bundle import canonical_json_bytes, parse_canonical_json_bytes
except ModuleNotFoundError as exc:
    if exc.name != "scripts":
        raise
    from sovereignty_bundle import canonical_json_bytes, parse_canonical_json_bytes


RECEIPT_VERSION = "smp.custody-receipt.v1"
DEFINITION_VERSION = "smp.canonical-governed-state.v1"
PROBE_SUITE_VERSION = "smp-probe-suite.v1"
TOOL_VERSION = "smp-offline-verifier.v1"
TOOL_SOURCE_COMMIT = "unreleased"
SCOPE_ID = "synthetic-example-scope"
AUTHORITY_EPOCH = "epoch-2026-07-08"
PRINCIPAL = "Primary Users"
RESULT_STATES = (
    "installed",
    "backup_created",
    "custody_verified",
    "verification_failed",
    "verification_skipped",
)
PROVENANCE_BASES = {
    "agent_inference",
    "agent_summary",
    "decision_record",
    "human_direct",
    "imported_artifact",
    "source_document",
    "system_observed",
}
AGENT_BASES = {"agent_inference", "agent_summary"}
HUMAN_AUTHORSHIP = {"human_authored", "human_confirmed"}
PROMOTION_STATES = {
    "conflicted",
    "evidence",
    "excluded",
    "held",
    "historical",
    "promoted",
    "rejected",
    "tombstoned",
}
REQUIRED_PROBE_CATEGORIES = {
    "authority_scope",
    "candidate_separation",
    "conflict",
    "evidence_request",
    "negative",
    "positive",
    "review_boundary",
    "stale_state",
    "tombstone",
}
REQUIRED_EXCLUSIONS = [
    "disposable restore state",
    "embeddings and vector indexes",
    "passwords, tokens, and provider secrets",
    "physical row order",
    "provider-owned operational metadata",
    "ranking scores and hot-index state",
    "rebuildable caches",
    "sequence values",
    "transient sessions and logs",
]
MIGRATION_IDS = [
    "sql/01_core.sql",
    "sql/02_vault.sql",
    "sql/03_provenance_guards.sql",
    "sql/04_source_import.sql",
    "sql/05_candidate_locators.sql",
    "sql/06_cutover_probe_categories.sql",
    "sql/07_work_lessons.sql",
    "sql/08_attention_events.sql",
    "sql/09_perimeter_refresh.sql",
    "sql/10_security_definer_hardening.sql",
    "sql/11_perimeter_evaluability.sql",
]
FORBIDDEN_KEYS = {
    "access_token",
    "api_key",
    "connection_string",
    "database_url",
    "email",
    "password",
    "phone",
}
CANONICAL_DEFINITION: dict[str, Any] = {
    "definition_version": DEFINITION_VERSION,
    "excluded_fields": [
        "cache_token",
        "embedding",
        "hot_index_state",
        "physical_ordinal",
        "ranking_score",
        "sequence_value",
    ],
    "hash_algorithm": "sha256",
    "relations": {
        "authority": {
            "fields": [
                "authority_epoch",
                "principal",
                "probe_run_id",
                "record_id",
                "scope_id",
            ]
        },
        "checkpoints": {
            "fields": [
                "chain_sha256",
                "event",
                "ordinal",
                "payload_sha256",
                "prev_record_id",
                "record_id",
            ]
        },
        "governed_records": {
            "fields": [
                "action",
                "authorship",
                "conflict_group",
                "consequential_domain",
                "content_sha256",
                "evidence_ids",
                "manifest_key",
                "promotion_state",
                "provenance_basis",
                "quote_id",
                "record_id",
                "review_state",
                "source_item_key",
                "supersedes",
                "temporal_state",
                "tombstone",
            ]
        },
        "source_items": {
            "fields": [
                "payload_sha256",
                "payload_size_bytes",
                "record_id",
                "source_item_key",
            ]
        },
    },
}
INVARIANT_CODES = {
    "candidate_promotion_boundaries": {
        "agent_content_promoted",
        "candidate_boundary",
        "excluded_item_promoted",
        "held_item_promoted",
    },
    "checkpoint_chain": {"checkpoint_chain_invalid"},
    "foreign_key_integrity": {"foreign_key_missing", "store_manifest_mismatch"},
    "supersession_acyclicity": {"supersession_cycle"},
    "tombstone_erasure_preservation": {"tombstone_missing", "tombstone_resurrected"},
}
JSON_FILES = {
    "canonical-governed-state.v1.json": "definition",
    "cutover-record.json": "cutover",
    "destination-store.json": "destination",
    "evidence-hashes.json": "evidence",
    "manifest.json": "manifest",
    "package.json": "package",
    "probe-definitions.json": "probes",
    "probe-results.json": "probe_results",
}


@dataclass
class Failure:
    code: str
    message: str
    expected: str | None = None
    observed: str | None = None

    def text(self) -> str:
        parts = [f"{self.code}: {self.message}"]
        if self.expected is not None:
            parts.append(f"expected {self.expected}")
        if self.observed is not None:
            parts.append(f"observed {self.observed}")
        return "; ".join(parts)


@dataclass
class LoadedFixture:
    root: Path
    documents: dict[str, Any]
    file_sha256: dict[str, str]
    backup_bytes: bytes
    failures: list[Failure] = field(default_factory=list)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _fail(failures: list[Failure], code: str, message: str, expected: str | None = None,
          observed: str | None = None) -> None:
    failures.append(Failure(code, message, expected, observed))


def _walk_keys(value: Any, found: set[str]) -> None:
    if isinstance(value, dict):
        found.update(value)
        for child in value.values():
            _walk_keys(child, found)
    elif isinstance(value, list):
        for child in value:
            _walk_keys(child, found)


def _resolve_inside(root: Path, relative: str) -> Path | None:
    if not isinstance(relative, str) or not relative or relative.startswith(("/", "\\")):
        return None
    parts = Path(relative).parts
    if ".." in parts or any(part.startswith("/") for part in parts):
        return None
    path = (root / relative).resolve()
    root_resolved = root.resolve()
    if path != root_resolved and root_resolved not in path.parents:
        return None
    return path


def _load_canonical(path: Path) -> tuple[Any, bytes]:
    raw = path.read_bytes()
    return parse_canonical_json_bytes(raw), raw


def load_fixture(root: Path) -> LoadedFixture:
    documents: dict[str, Any] = {}
    file_sha256: dict[str, str] = {}
    failures: list[Failure] = []
    for name in JSON_FILES:
        path = root / name
        try:
            value, raw = _load_canonical(path)
        except (OSError, ValueError) as exc:
            _fail(failures, "fixture_unreadable", f"{name} is not canonical JSON ({exc.__class__.__name__})")
            continue
        documents[name] = value
        file_sha256[name] = sha256_hex(raw)
    backup_bytes = b""
    destination = documents.get("destination-store.json")
    if isinstance(destination, dict):
        backup = destination.get("backup")
        relative = backup.get("path") if isinstance(backup, dict) else None
        backup_path = _resolve_inside(root, relative) if isinstance(relative, str) else None
        if backup_path is None or not backup_path.is_file():
            _fail(failures, "backup_digest_mismatch", "backup path is not a file inside the fixture")
        else:
            backup_bytes = backup_path.read_bytes()
            file_sha256["backup"] = sha256_hex(backup_bytes)
    loaded = LoadedFixture(root, documents, file_sha256, backup_bytes, failures)
    forbidden: set[str] = set()
    _walk_keys(documents, forbidden)
    overlap = sorted(forbidden & FORBIDDEN_KEYS)
    if overlap:
        _fail(failures, "fixture_unreadable", f"forbidden key(s) {overlap}")
    return loaded


def _rows(destination: Mapping[str, Any], side: str, relation: str) -> list[dict[str, Any]]:
    body = destination.get(side)
    if not isinstance(body, dict):
        return []
    rows = body.get(relation)
    if not isinstance(rows, list):
        return []
    return [row for row in rows if isinstance(row, dict)]


def _project(rows: list[dict[str, Any]], fields: list[str], failures: list[Failure],
             label: str) -> list[dict[str, Any]] | None:
    excluded = set(CANONICAL_DEFINITION["excluded_fields"])
    allowed = set(fields) | excluded
    projected: list[dict[str, Any]] = []
    ok = True
    for row in rows:
        extra = sorted(set(row) - allowed)
        if extra:
            _fail(failures, "undeclared_row_field", f"{label} has undeclared field(s) {extra}")
            ok = False
        missing = [name for name in fields if name not in row]
        if missing:
            _fail(failures, "canonical_field_missing", f"{label} missing {missing}")
            ok = False
            continue
        projected.append({name: row[name] for name in fields})
    if not ok:
        return None
    projected.sort(key=lambda row: row["record_id"] if isinstance(row.get("record_id"), str) else "")
    return projected


def _state_hash(destination: Mapping[str, Any], side: str, failures: list[Failure]) -> str | None:
    state: dict[str, Any] = {}
    for relation, spec in CANONICAL_DEFINITION["relations"].items():
        projected = _project(_rows(destination, side, relation), spec["fields"], failures, f"{side}.{relation}")
        if projected is None:
            return None
        state[relation] = projected
    return sha256_hex(canonical_json_bytes(state))


def _manifest_body_hash(manifest: Mapping[str, Any]) -> str:
    body = {key: value for key, value in manifest.items() if key != "manifest_sha256"}
    return sha256_hex(canonical_json_bytes(body))


def _chain_hash(ordinal: int, prev: str | None, event: str, payload_sha256: str) -> str:
    return sha256_hex(canonical_json_bytes({
        "event": event,
        "ordinal": ordinal,
        "payload_sha256": payload_sha256,
        "prev_record_id": prev,
    }))


def _index(rows: list[dict[str, Any]], key: str) -> dict[str, dict[str, Any]]:
    indexed: dict[str, dict[str, Any]] = {}
    for row in rows:
        value = row.get(key)
        if isinstance(value, str):
            indexed[value] = row
    return indexed


def _check_accounting(fixture: LoadedFixture, failures: list[Failure]) -> None:
    package = fixture.documents["package.json"]
    manifest = fixture.documents["manifest.json"]
    items = package.get("source_items")
    dispositions = manifest.get("dispositions")
    if not isinstance(items, list) or not isinstance(dispositions, list):
        _fail(failures, "source_item_unaccounted", "package or manifest is missing its row arrays")
        return
    item_keys = [item.get("source_item_key") for item in items if isinstance(item, dict)]
    if len(item_keys) != len(set(item_keys)) or any(not isinstance(key, str) for key in item_keys):
        _fail(failures, "source_item_unaccounted", "source item keys are missing or duplicated")
        return
    referenced: list[str] = []
    for row in dispositions:
        if not isinstance(row, dict) or not isinstance(row.get("source_item_key"), str):
            _fail(failures, "source_item_unaccounted", "a disposition has no source item key")
            return
        referenced.append(row["source_item_key"])
    missing = sorted(set(referenced) - set(item_keys))
    extra = sorted(set(item_keys) - set(referenced))
    if missing or extra:
        _fail(
            failures, "source_item_unaccounted",
            "source items and dispositions do not reconcile",
            expected="equal source-item sets",
            observed=f"missing {missing}; unmanifested {extra}",
        )
    batch = package.get("batch") if isinstance(package.get("batch"), dict) else {}
    if batch.get("source_item_count") != len(item_keys) or batch.get("exported_item_count") != len(item_keys):
        _fail(failures, "manifest_count_mismatch", "batch counts do not match packaged source items")
    containers = {
        item.get("source_container") for item in items if isinstance(item, dict)
    }
    actions = [row.get("action") for row in dispositions if isinstance(row, dict)]
    approved = [
        row for row in dispositions
        if isinstance(row, dict) and row.get("action") == "import" and row.get("review_state") == "approved"
    ]
    expected = {
        "approved_imports": len(approved),
        "candidates": len(dispositions),
        "evidence_only_rows": actions.count("evidence"),
        "excluded_rows": actions.count("exclude"),
        "held_rows": actions.count("hold"),
        "source_containers": len(containers),
        "source_items": len(item_keys),
    }
    if manifest.get("reconciliation") != expected:
        _fail(
            failures, "manifest_count_mismatch",
            "reconciliation report does not match the packaged rows",
            expected=str(expected),
            observed=str(manifest.get("reconciliation")),
        )
    recomputed = _manifest_body_hash(manifest)
    if manifest.get("manifest_sha256") != recomputed:
        _fail(
            failures, "manifest_count_mismatch",
            "manifest hash does not match the canonical disposition ledger",
            expected=recomputed,
            observed=str(manifest.get("manifest_sha256")),
        )


def _evidence_index(fixture: LoadedFixture) -> dict[str, dict[str, Any]]:
    evidence = fixture.documents["evidence-hashes.json"]
    entries = evidence.get("entries") if isinstance(evidence, dict) else None
    if not isinstance(entries, list):
        return {}
    return {
        entry["evidence_id"]: entry
        for entry in entries
        if isinstance(entry, dict) and isinstance(entry.get("evidence_id"), str)
    }


def _quotes_by_item(package: Mapping[str, Any]) -> dict[str, dict[str, str]]:
    found: dict[str, dict[str, str]] = {}
    for item in package.get("source_items", []):
        if not isinstance(item, dict):
            continue
        quotes: dict[str, str] = {}
        for quote in item.get("quotes", []):
            if isinstance(quote, dict) and isinstance(quote.get("quote_id"), str) and isinstance(quote.get("text"), str):
                quotes[quote["quote_id"]] = quote["text"]
        if isinstance(item.get("source_item_key"), str):
            found[item["source_item_key"]] = quotes
    return found


def _check_evidence(fixture: LoadedFixture, failures: list[Failure]) -> None:
    package = fixture.documents["package.json"]
    evidence = _evidence_index(fixture)
    if fixture.documents["evidence-hashes.json"].get("algorithm") != "sha256":
        _fail(failures, "consequential_evidence_missing", "evidence ledger algorithm is not sha256")
    items = [item for item in package.get("source_items", []) if isinstance(item, dict)]
    for item in items:
        key = item.get("source_item_key")
        payload = item.get("raw_payload")
        if not isinstance(key, str) or not isinstance(payload, str):
            _fail(failures, "consequential_evidence_missing", "a source item has no raw payload")
            continue
        digest = sha256_hex(payload.encode("utf-8"))
        entry_id = f"ev-payload-{key}"
        entry = evidence.get(entry_id)
        if entry is None or entry.get("sha256") != digest or entry.get("byte_length") != len(payload.encode("utf-8")):
            _fail(
                failures, "consequential_evidence_missing",
                f"{key} raw payload hash is not in the evidence ledger",
                expected=digest, observed=str(None if entry is None else entry.get("sha256")),
            )
        if entry is not None and entry.get("source_item_key") != key:
            _fail(failures, "foreign_key_missing", f"{entry_id} points at the wrong source item")
        for quote in item.get("quotes", []):
            if not isinstance(quote, dict):
                continue
            text = quote.get("text")
            quote_id = quote.get("quote_id")
            if not isinstance(text, str) or not isinstance(quote_id, str) or text not in payload:
                _fail(failures, "foreign_key_missing", f"{key} quote is not contained in the raw payload")
                continue
            quote_digest = sha256_hex(text.encode("utf-8"))
            quote_entry = evidence.get(f"ev-quote-{quote_id}")
            if quote_entry is None or quote_entry.get("sha256") != quote_digest:
                _fail(
                    failures, "consequential_evidence_missing",
                    f"{quote_id} quote hash is not in the evidence ledger",
                    expected=quote_digest,
                    observed=str(None if quote_entry is None else quote_entry.get("sha256")),
                )
    rows = _rows(fixture.documents["destination-store.json"], "restored_rows", "governed_records")
    quotes = _quotes_by_item(package)
    for row in rows:
        if row.get("promotion_state") != "promoted" or row.get("consequential_domain") in (None, ""):
            continue
        evidence_ids = row.get("evidence_ids")
        domain = row.get("consequential_domain")
        authorship = row.get("authorship")
        basis = row.get("provenance_basis")
        if (
            not isinstance(evidence_ids, list) or not evidence_ids
            or any(evidence_id not in evidence for evidence_id in evidence_ids)
            or authorship not in HUMAN_AUTHORSHIP
            or basis in AGENT_BASES
        ):
            _fail(
                failures, "consequential_evidence_missing",
                f"{row.get('record_id')} is a promoted consequential {domain} claim without human evidence",
                expected="human authorship plus evidence-ledger ids",
                observed=f"authorship {authorship}; basis {basis}; evidence {evidence_ids}",
            )


def _check_store_matches_manifest(fixture: LoadedFixture, failures: list[Failure]) -> None:
    manifest = fixture.documents["manifest.json"]
    dispositions = manifest.get("dispositions")
    if not isinstance(dispositions, list):
        return
    fields = CANONICAL_DEFINITION["relations"]["governed_records"]["fields"]
    expected = _project([row for row in dispositions if isinstance(row, dict)], fields, failures, "manifest")
    if expected is None:
        return
    for side in ("source_rows", "restored_rows"):
        projected = _project(
            _rows(fixture.documents["destination-store.json"], side, "governed_records"),
            fields, failures, side,
        )
        if projected is not None and projected != expected:
            _fail(
                failures, "store_manifest_mismatch",
                f"{side} governed records differ from the frozen manifest",
                expected=sha256_hex(canonical_json_bytes(expected)),
                observed=sha256_hex(canonical_json_bytes(projected)),
            )


def _check_required_cases(rows: list[dict[str, Any]], failures: list[Failure]) -> None:
    def missing(code: str, message: str) -> None:
        _fail(failures, code, message)

    groups: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        group = row.get("conflict_group")
        if isinstance(group, str):
            groups.setdefault(group, []).append(row)
    if not any(len(members) >= 2 for members in groups.values()):
        missing("conflict_not_preserved", "no conflict group retains at least two claims")
    for group, members in groups.items():
        if len(members) < 2 or any(member.get("promotion_state") == "promoted" for member in members):
            _fail(
                failures, "conflict_not_preserved",
                f"conflict group {group} was flattened or promoted",
                expected="two or more unpromoted preserved claims",
                observed=str(len(members)),
            )
    stale = [row for row in rows if row.get("temporal_state") == "stale"]
    if not stale:
        missing("stale_claim_not_preserved", "no stale claim is present in the governed row set")
    row_ids = {row.get("record_id") for row in rows}
    for row in stale:
        if row.get("promotion_state") == "promoted" or not any(
            other.get("supersedes") == row.get("record_id") for other in rows
        ):
            _fail(
                failures, "stale_claim_not_preserved",
                f"{row.get('record_id')} is not preserved as a superseded stale claim",
                expected="present, unpromoted, and targeted by supersedes",
                observed=f"promotion {row.get('promotion_state')}",
            )
    if not any(row.get("promotion_state") == "held" for row in rows):
        missing("required_case_missing", "held item is absent")
    if not any(row.get("promotion_state") == "excluded" for row in rows):
        missing("required_case_missing", "excluded item is absent")
    for row in rows:
        if isinstance(row.get("tombstone"), dict) and row.get("promotion_state") != "tombstoned":
            _fail(
                failures, "tombstone_resurrected",
                f"{row.get('record_id')} tombstone was promoted or returned as current",
                expected="tombstoned and erased",
                observed=f"promotion {row.get('promotion_state')}; temporal {row.get('temporal_state')}",
            )
    tombstones = [row for row in rows if row.get("promotion_state") == "tombstoned"]
    if not tombstones:
        missing("tombstone_missing", "tombstone/erasure case is absent")
    for row in tombstones:
        marker = row.get("tombstone")
        if (
            row.get("temporal_state") != "erased"
            or not isinstance(marker, dict)
            or not marker.get("reason")
            or row.get("record_id") not in row_ids
        ):
            _fail(
                failures, "tombstone_resurrected",
                f"{row.get('record_id')} tombstone is not an erased preserved marker",
                expected="temporal_state erased with a tombstone reason",
                observed=f"temporal_state {row.get('temporal_state')}",
            )
        if any(
            other.get("record_id") == row.get("record_id") and other.get("promotion_state") == "promoted"
            for other in rows
        ):
            _fail(failures, "tombstone_resurrected", f"{row.get('record_id')} was promoted again")
    if not any(
        row.get("promotion_state") == "promoted" and row.get("consequential_domain") not in (None, "")
        for row in rows
    ):
        missing("required_case_missing", "promoted consequential claim is absent")
    if not any(row.get("authorship") == "agent_authored" and row.get("promotion_state") != "promoted" for row in rows):
        missing("required_case_missing", "unpromoted agent-authored content is absent")


def _check_promotion(rows: list[dict[str, Any]], failures: list[Failure]) -> None:
    for row in rows:
        record_id = row.get("record_id")
        action = row.get("action")
        promotion = row.get("promotion_state")
        authorship = row.get("authorship")
        basis = row.get("provenance_basis")
        if promotion not in PROMOTION_STATES:
            _fail(failures, "candidate_boundary", f"{record_id} has an unknown promotion state")
        if basis not in PROVENANCE_BASES:
            _fail(failures, "candidate_boundary", f"{record_id} has a provenance basis outside the closed set")
        if action in {"hold", "exclude", "evidence"} and promotion == "promoted":
            code = {
                "hold": "held_item_promoted",
                "exclude": "excluded_item_promoted",
                "evidence": "candidate_boundary",
            }[action]
            _fail(
                failures, code,
                f"{record_id} action {action} was promoted",
                expected="not promoted", observed="promoted",
            )
        if authorship == "agent_authored" and promotion == "promoted":
            _fail(
                failures, "agent_content_promoted",
                f"{record_id} agent-authored content was promoted as authority",
                expected="unpromoted agent authorship", observed="promoted",
            )
        if basis in AGENT_BASES and promotion == "promoted":
            _fail(
                failures, "agent_content_promoted",
                f"{record_id} agent provenance was promoted",
                expected="agent basis remains unpromoted", observed=str(basis),
            )
        if promotion == "promoted" and (
            action != "import"
            or row.get("review_state") != "approved"
            or authorship not in HUMAN_AUTHORSHIP
            or row.get("temporal_state") != "current"
            or row.get("conflict_group") is not None
            or row.get("tombstone") is not None
            or not row.get("evidence_ids")
        ):
            _fail(
                failures, "candidate_boundary",
                f"{record_id} promoted row crosses the candidate boundary",
                expected="approved human import, current, evidenced, without conflict or tombstone",
                observed=f"action {action}; review {row.get('review_state')}; temporal {row.get('temporal_state')}",
            )


def _check_supersession(rows: list[dict[str, Any]], failures: list[Failure]) -> None:
    ids = {row.get("record_id") for row in rows}
    graph: dict[str, str] = {}
    for row in rows:
        target = row.get("supersedes")
        record_id = row.get("record_id")
        if target is None:
            continue
        if not isinstance(record_id, str) or target not in ids or target == record_id:
            _fail(failures, "foreign_key_missing", f"{record_id} supersedes a missing record")
            continue
        graph[record_id] = target
    for start in list(graph):
        seen: set[str] = set()
        cursor: str | None = start
        while isinstance(cursor, str):
            if cursor in seen:
                _fail(
                    failures, "supersession_cycle",
                    "supersession links cycle",
                    expected="acyclic supersedes edges",
                    observed=" -> ".join([*seen, cursor]),
                )
                return
            seen.add(cursor)
            cursor = graph.get(cursor)


def _check_checkpoints(fixture: LoadedFixture, failures: list[Failure]) -> None:
    destination = fixture.documents["destination-store.json"]
    manifest = fixture.documents["manifest.json"]
    cutover = fixture.documents["cutover-record.json"]
    scope = cutover.get("scope_id") if isinstance(cutover, dict) else None
    payloads = {
        "authority_declared": sha256_hex(fixture.file_sha256["cutover-record.json"].encode("ascii")),
        "genesis": sha256_hex(str(scope).encode("utf-8")),
        "manifest_frozen": sha256_hex(str(manifest.get("manifest_sha256")).encode("ascii")),
        "probes_recorded": sha256_hex(fixture.file_sha256["probe-definitions.json"].encode("ascii")),
    }
    for side in ("source_rows", "restored_rows"):
        rows = sorted(
            _rows(destination, side, "checkpoints"),
            key=lambda row: row.get("ordinal") if isinstance(row.get("ordinal"), int) else 0,
        )
        if [row.get("event") for row in rows] != [
            "genesis", "manifest_frozen", "probes_recorded", "authority_declared"
        ]:
            _fail(
                failures, "checkpoint_chain_invalid",
                f"{side} checkpoint events are incomplete",
                expected="genesis, manifest_frozen, probes_recorded, authority_declared",
                observed=str([row.get("event") for row in rows]),
            )
            continue
        previous: str | None = None
        for index, row in enumerate(rows, start=1):
            event = str(row.get("event"))
            expected_payload = payloads[event]
            expected_chain = _chain_hash(index, previous, event, expected_payload)
            if (
                row.get("ordinal") != index
                or row.get("prev_record_id") != previous
                or row.get("payload_sha256") != expected_payload
                or row.get("chain_sha256") != expected_chain
            ):
                _fail(
                    failures, "checkpoint_chain_invalid",
                    f"{side} checkpoint {row.get('record_id')} does not verify",
                    expected=expected_chain,
                    observed=str(row.get("chain_sha256")),
                )
            previous = row.get("record_id") if isinstance(row.get("record_id"), str) else None


def _check_foreign_keys(fixture: LoadedFixture, failures: list[Failure]) -> None:
    package = fixture.documents["package.json"]
    evidence = _evidence_index(fixture)
    quotes = _quotes_by_item(package)
    items = {
        item.get("source_item_key"): item
        for item in package.get("source_items", [])
        if isinstance(item, dict)
    }
    rows = _rows(fixture.documents["destination-store.json"], "restored_rows", "governed_records")
    for row in rows:
        key = row.get("source_item_key")
        quote_id = row.get("quote_id")
        if key not in items or not isinstance(quote_id, str) or quote_id not in quotes.get(key, {}):
            _fail(failures, "foreign_key_missing", f"{row.get('record_id')} source item or quote is missing")
            continue
        text = quotes[key][quote_id]
        digest = sha256_hex(text.encode("utf-8"))
        if row.get("content_sha256") != digest:
            _fail(
                failures, "foreign_key_missing",
                f"{row.get('record_id')} content hash does not match the preserved quote",
                expected=digest, observed=str(row.get("content_sha256")),
            )
        for evidence_id in row.get("evidence_ids") or []:
            if evidence_id not in evidence:
                _fail(failures, "foreign_key_missing", f"{row.get('record_id')} evidence id {evidence_id} is missing")
    source_rows = _rows(fixture.documents["destination-store.json"], "restored_rows", "source_items")
    packaged = {}
    for key, item in items.items():
        payload = item.get("raw_payload")
        if isinstance(key, str) and isinstance(payload, str):
            encoded = payload.encode("utf-8")
            packaged[key] = (sha256_hex(encoded), len(encoded))
    observed = {
        row.get("source_item_key"): (row.get("payload_sha256"), row.get("payload_size_bytes"))
        for row in source_rows
    }
    if observed != packaged:
        _fail(
            failures, "foreign_key_missing",
            "destination source-item rows do not match packaged payload hashes",
            expected=str(len(packaged)), observed=str(len(observed)),
        )


def _evaluate_probe(probe: Mapping[str, Any], rows: list[dict[str, Any]],
                    authority: list[dict[str, Any]]) -> bool:
    check = probe.get("check")
    indexed = _index(rows, "record_id")
    record = indexed.get(probe.get("record_id"))
    if check == "record_promoted_current":
        return bool(record and record.get("promotion_state") == "promoted" and record.get("temporal_state") == "current")
    if check == "record_absent_from_promoted":
        return record is not None and record.get("promotion_state") != "promoted"
    if check == "conflict_preserved":
        members = [row for row in rows if row.get("conflict_group") == probe.get("conflict_group")]
        return len(members) >= 2 and all(row.get("promotion_state") != "promoted" for row in members)
    if check == "record_stale_preserved":
        return bool(
            record and record.get("temporal_state") == "stale" and record.get("promotion_state") != "promoted"
            and any(row.get("supersedes") == record.get("record_id") for row in rows)
        )
    if check in {"agent_not_promoted", "candidate_not_promoted"}:
        return bool(record and record.get("authorship") == "agent_authored" and record.get("promotion_state") != "promoted")
    if check == "held_not_promoted":
        return bool(record and record.get("promotion_state") == "held" and record.get("action") == "hold")
    if check == "authority_recorded":
        return any(
            row.get("scope_id") == probe.get("scope_id")
            and row.get("authority_epoch") == probe.get("authority_epoch")
            and row.get("principal") == PRINCIPAL
            for row in authority
        )
    if check == "tombstone_preserved":
        return bool(
            record and record.get("promotion_state") == "tombstoned"
            and record.get("temporal_state") == "erased"
            and isinstance(record.get("tombstone"), dict)
        )
    return False


def _check_probes(fixture: LoadedFixture, failures: list[Failure]) -> None:
    probes = fixture.documents["probe-definitions.json"]
    results = fixture.documents["probe-results.json"]
    definitions = probes.get("probes") if isinstance(probes, dict) else None
    recorded = results.get("results") if isinstance(results, dict) else None
    if probes.get("probe_suite_version") != PROBE_SUITE_VERSION or results.get("probe_suite_version") != PROBE_SUITE_VERSION:
        _fail(failures, "probe_suite_digest_mismatch", "probe suite version is not the bound version")
    if not isinstance(definitions, list) or not isinstance(recorded, list):
        _fail(failures, "probe_result_contradicts_store", "probe definitions or results are missing")
        return
    categories = {probe.get("probe_category") for probe in definitions if isinstance(probe, dict)}
    missing = sorted(REQUIRED_PROBE_CATEGORIES - {category for category in categories if isinstance(category, str)})
    if missing:
        _fail(failures, "probe_result_contradicts_store", f"probe categories missing: {missing}")
    by_key = {
        probe.get("probe_key"): probe
        for probe in definitions
        if isinstance(probe, dict) and isinstance(probe.get("probe_key"), str)
    }
    result_keys = [row.get("probe_key") for row in recorded if isinstance(row, dict)]
    if sorted(result_keys) != sorted(by_key) or len(result_keys) != len(by_key):
        _fail(failures, "probe_result_contradicts_store", "probe results do not cover the definitions one-for-one")
    rows = _rows(fixture.documents["destination-store.json"], "restored_rows", "governed_records")
    authority = _rows(fixture.documents["destination-store.json"], "restored_rows", "authority")
    execution = fixture.documents["destination-store.json"].get("probe_execution")
    if not isinstance(execution, dict) or execution.get("connects_to_database") is not False:
        _fail(failures, "probe_result_contradicts_store", "probe execution must be recorded and must not connect to a database")
    if results.get("executed_against") != "recorded-restored-instance":
        _fail(failures, "probe_result_contradicts_store", "probe results are not marked as recorded restored-instance results")
    for result in recorded:
        if not isinstance(result, dict):
            continue
        probe = by_key.get(result.get("probe_key"))
        if probe is None:
            continue
        evaluated = _evaluate_probe(probe, rows, authority)
        if result.get("matched") is not True or evaluated is not True:
            code = "critical_probe_failed" if probe.get("severity") == "critical" and result.get("matched") is not True else "probe_result_contradicts_store"
            _fail(
                failures, code,
                f"{probe.get('probe_key')} does not agree with the destination store",
                expected="matched true and store predicate true",
                observed=f"recorded {result.get('matched')}; store {evaluated}",
            )


def _check_authority(fixture: LoadedFixture, failures: list[Failure]) -> None:
    cutover = fixture.documents["cutover-record.json"]
    destination = fixture.documents["destination-store.json"]
    if not isinstance(cutover, dict):
        _fail(failures, "authority_declaration_missing", "cutover record is missing")
        return
    if (
        cutover.get("principal") != PRINCIPAL
        or cutover.get("scope_id") != SCOPE_ID
        or cutover.get("authority_epoch") != AUTHORITY_EPOCH
        or cutover.get("lifecycle", [None])[-1] != "AUTHORITATIVE"
        or not cutover.get("declared_at")
        or not cutover.get("probe_run_id")
    ):
        _fail(
            failures, "authority_declaration_missing",
            "authority declaration is missing principal, scope, epoch, or probe run",
            expected=f"{PRINCIPAL} / {SCOPE_ID} / {AUTHORITY_EPOCH}",
            observed=f"{cutover.get('principal')} / {cutover.get('scope_id')} / {cutover.get('authority_epoch')}",
        )
    for side in ("source_rows", "restored_rows"):
        rows = _rows(destination, side, "authority")
        observed = rows[0] if rows else {}
        matches = (
            len(rows) == 1
            and observed.get("principal") == cutover.get("principal")
            and observed.get("scope_id") == cutover.get("scope_id")
            and observed.get("authority_epoch") == cutover.get("authority_epoch")
            and observed.get("probe_run_id") == cutover.get("probe_run_id")
        )
        if not matches:
            _fail(
                failures, "authority_declaration_missing",
                f"{side} authority row does not match the cutover record",
                expected=str(cutover.get("probe_run_id")),
                observed=str(observed.get("probe_run_id")),
            )
    scope = destination.get("scope")
    scope_matches = (
        isinstance(scope, dict)
        and scope.get("scope_id") == cutover.get("scope_id")
        and scope.get("authority_epoch") == cutover.get("authority_epoch")
    )
    if not scope_matches:
        _fail(failures, "authority_declaration_missing", "destination scope does not match the cutover record")


def _check_identity_and_digests(fixture: LoadedFixture, failures: list[Failure]) -> None:
    destination = fixture.documents["destination-store.json"]
    schema = destination.get("schema")
    schema_ok = (
        isinstance(schema, dict)
        and schema.get("migration_ids") == MIGRATION_IDS
        and schema.get("migration_head") == MIGRATION_IDS[-1]
        and schema.get("profile")
        and schema.get("version")
    )
    if not schema_ok:
        _fail(
            failures, "schema_identity_missing",
            "schema profile, version, or migration identity is incomplete",
            expected=MIGRATION_IDS[-1],
            observed=str(None if not isinstance(schema, dict) else schema.get("migration_head")),
        )
    target = destination.get("restore_target")
    fingerprint = target.get("fingerprint") if isinstance(target, dict) else None
    if (
        not isinstance(target, dict)
        or target.get("engine") != "PostgreSQL"
        or not target.get("engine_version")
        or not isinstance(fingerprint, str)
        or not fingerprint
        or "://" in fingerprint
        or not isinstance(target.get("extensions"), list)
    ):
        _fail(failures, "restore_target_missing", "restore-target fingerprint is missing or not an offline PostgreSQL label")
    if destination.get("exclusions") != REQUIRED_EXCLUSIONS:
        _fail(failures, "exclusion_list_incomplete", "declared exclusions do not match the bound exclusion list")
    backup = destination.get("backup") if isinstance(destination.get("backup"), dict) else {}
    if backup.get("sha256") != fixture.file_sha256.get("backup") or backup.get("size_bytes") != len(fixture.backup_bytes):
        _fail(
            failures, "backup_digest_mismatch",
            "backup digest does not match the fixture backup bytes",
            expected=fixture.file_sha256.get("backup"),
            observed=str(backup.get("sha256")),
        )
    if destination.get("source_package_digest") != fixture.file_sha256.get("package.json"):
        _fail(
            failures, "package_digest_mismatch",
            "source package digest does not match package.json",
            expected=fixture.file_sha256.get("package.json"),
            observed=str(destination.get("source_package_digest")),
        )
    if destination.get("probe_suite_sha256") != fixture.file_sha256.get("probe-definitions.json"):
        _fail(
            failures, "probe_suite_digest_mismatch",
            "probe suite digest does not match probe-definitions.json",
            expected=fixture.file_sha256.get("probe-definitions.json"),
            observed=str(destination.get("probe_suite_sha256")),
        )
    if fixture.documents.get("canonical-governed-state.v1.json") != CANONICAL_DEFINITION:
        _fail(failures, "canonical_definition_mismatch", "canonical governed-state definition is not the bound version")
    source_hash = _state_hash(destination, "source_rows", failures)
    restored_hash = _state_hash(destination, "restored_rows", failures)
    if source_hash is None or restored_hash is None or source_hash != restored_hash:
        _fail(
            failures, "canonical_hash_mismatch",
            "source and restored canonical row-set hashes differ",
            expected=str(source_hash), observed=str(restored_hash),
        )
    if destination.get("claimed_source_sha256") != source_hash or destination.get("claimed_restored_sha256") != restored_hash:
        _fail(
            failures, "canonical_hash_mismatch",
            "claimed canonical hashes do not match the recomputed set hashes",
            expected=str(source_hash),
            observed=str(destination.get("claimed_restored_sha256")),
        )


def verify(fixture: LoadedFixture) -> dict[str, Any]:
    failures = list(fixture.failures)
    required = set(JSON_FILES)
    if required - set(fixture.documents):
        failures.append(Failure("fixture_unreadable", "one or more fixture documents could not be read"))
    else:
        _check_accounting(fixture, failures)
        _check_evidence(fixture, failures)
        _check_store_matches_manifest(fixture, failures)
        _check_foreign_keys(fixture, failures)
        rows = _rows(fixture.documents["destination-store.json"], "restored_rows", "governed_records")
        _check_required_cases(rows, failures)
        _check_promotion(rows, failures)
        _check_supersession(rows, failures)
        _check_checkpoints(fixture, failures)
        _check_probes(fixture, failures)
        _check_authority(fixture, failures)
        _check_identity_and_digests(fixture, failures)
    return _receipt(fixture, _dedupe(failures))


def _dedupe(failures: list[Failure]) -> list[Failure]:
    unique: dict[tuple[str, str], Failure] = {}
    for failure in failures:
        unique[(failure.code, failure.message)] = failure
    return [unique[key] for key in sorted(unique)]


def _counts(rows: list[dict[str, Any]]) -> dict[str, int]:
    def count(state: str) -> int:
        return sum(row.get("promotion_state") == state for row in rows)

    return {
        "candidate": sum(row.get("promotion_state") in {"conflicted", "evidence", "held", "rejected"} for row in rows),
        "conflicted": count("conflicted"),
        "evidence": count("evidence"),
        "excluded": count("excluded"),
        "held": count("held"),
        "historical": count("historical"),
        "promoted": count("promoted"),
        "rejected": count("rejected"),
        "stale": sum(row.get("temporal_state") == "stale" for row in rows),
        "tombstoned": count("tombstoned"),
    }


def _receipt(fixture: LoadedFixture, failures: list[Failure]) -> dict[str, Any]:
    destination = fixture.documents.get("destination-store.json")
    destination = destination if isinstance(destination, dict) else {}
    cutover = fixture.documents.get("cutover-record.json")
    cutover = cutover if isinstance(cutover, dict) else {}
    schema = destination.get("schema") if isinstance(destination.get("schema"), dict) else {}
    target = destination.get("restore_target") if isinstance(destination.get("restore_target"), dict) else {}
    backup = destination.get("backup") if isinstance(destination.get("backup"), dict) else {}
    rows = _rows(destination, "restored_rows", "governed_records")
    source_hash = fixture.file_sha256.get("source-canonical")
    restored_hash = fixture.file_sha256.get("restored-canonical")
    if "destination-store.json" in fixture.documents:
        quiet: list[Failure] = []
        source_hash = _state_hash(destination, "source_rows", quiet) or source_hash or ""
        restored_hash = _state_hash(destination, "restored_rows", quiet) or restored_hash or ""
    by_code: dict[str, list[Failure]] = {}
    for failure in failures:
        by_code.setdefault(failure.code, []).append(failure)
    invariants = []
    for invariant_id in sorted(INVARIANT_CODES):
        matched = [failure for code in INVARIANT_CODES[invariant_id] for failure in by_code.get(code, [])]
        invariants.append({
            "expected": None if not matched else " | ".join(failure.expected or failure.message for failure in matched),
            "id": invariant_id,
            "observed": None if not matched else " | ".join(failure.observed or failure.message for failure in matched),
            "passed": not matched,
        })
    probe_rows = []
    results = fixture.documents.get("probe-results.json")
    definitions = fixture.documents.get("probe-definitions.json")
    if isinstance(results, dict) and isinstance(definitions, dict):
        defined = {
            probe.get("probe_key"): probe
            for probe in definitions.get("probes", [])
            if isinstance(probe, dict)
        }
        for result in results.get("results", []):
            if not isinstance(result, dict):
                continue
            probe = defined.get(result.get("probe_key"), {})
            probe_rows.append({
                "matched": result.get("matched") is True,
                "probe_category": probe.get("probe_category"),
                "probe_key": result.get("probe_key"),
                "severity": probe.get("severity"),
            })
    probe_rows.sort(key=lambda row: row["probe_key"] or "")
    passed = not failures
    receipt = {
        "backup": {
            "format": backup.get("format") or "synthetic-text-backup",
            "sha256": fixture.file_sha256.get("backup", ""),
            "size_bytes": len(fixture.backup_bytes),
        },
        "canonical_view": {
            "counts": _counts(rows),
            "definition_version": DEFINITION_VERSION,
            "restored_sha256": restored_hash or "",
            "source_sha256": source_hash or "",
        },
        "created_at": cutover.get("declared_at") or "2026-07-08T18:30:00Z",
        "exclusions": list(destination.get("exclusions") or REQUIRED_EXCLUSIONS),
        "probe_results": probe_rows,
        "probe_suite": {
            "sha256": fixture.file_sha256.get("probe-definitions.json", ""),
            "version": PROBE_SUITE_VERSION,
        },
        "receipt_version": RECEIPT_VERSION,
        "restore_target": {
            "engine": target.get("engine") or "PostgreSQL",
            "engine_version": target.get("engine_version") or "",
            "extensions": list(target.get("extensions") or []),
            "fingerprint": target.get("fingerprint") or "",
        },
        "result": "custody_verified" if passed else "verification_failed",
        "schema": {
            "migration_head": schema.get("migration_head") or "",
            "profile": schema.get("profile") or "",
            "version": schema.get("version") or "",
        },
        "scope": {
            "authority_epoch": cutover.get("authority_epoch") or destination.get("scope", {}).get("authority_epoch", ""),
            "scope_id": cutover.get("scope_id") or destination.get("scope", {}).get("scope_id", ""),
        },
        "signer": {
            "method": "canonical-sha256",
            "principal": PRINCIPAL,
            "signature": "",
        },
        "skip_or_failure_reason": None if passed else " | ".join(failure.text() for failure in failures),
        "source_package_digest": fixture.file_sha256.get("package.json", ""),
        "structural_invariants": invariants,
        "tool": {"source_commit": TOOL_SOURCE_COMMIT, "version": TOOL_VERSION},
    }
    if receipt["result"] not in RESULT_STATES:
        receipt["result"] = "verification_failed"
    unsigned = copy.deepcopy(receipt)
    receipt["signer"]["signature"] = sha256_hex(canonical_json_bytes(unsigned))
    return receipt


def apply_injection(fixture: LoadedFixture, name: str) -> None:
    destination = fixture.documents["destination-store.json"]

    def governed(side: str) -> list[dict[str, Any]]:
        return destination[side]["governed_records"]

    if name == "non_governed_noise":
        for row in governed("restored_rows"):
            row["ranking_score"] = int(row.get("ranking_score", 0)) + 5
            row["cache_token"] = "synthetic-cache-mutated"
        destination["restored_rows"]["governed_records"].reverse()
        return
    if name == "flatten_conflict":
        for side in ("source_rows", "restored_rows"):
            destination[side]["governed_records"] = [
                row for row in governed(side) if row.get("record_id") != "rec-deploy-thursday"
            ]
        return
    if name == "promote_agent_content":
        for side in ("source_rows", "restored_rows"):
            for row in governed(side):
                if row.get("record_id") == "rec-agent-budget":
                    row["action"] = "import"
                    row["promotion_state"] = "promoted"
                    row["review_state"] = "approved"
                    row["temporal_state"] = "current"
        return
    if name == "drop_authority":
        fixture.documents["cutover-record.json"]["principal"] = ""
        for side in ("source_rows", "restored_rows"):
            destination[side]["authority"] = []
        return
    if name == "unaccounted_source_item":
        fixture.documents["package.json"]["source_items"] = fixture.documents["package.json"]["source_items"][1:]
        return
    if name == "missing_consequential_evidence":
        for side in ("source_rows", "restored_rows"):
            for row in governed(side):
                if row.get("record_id") == "rec-identity-label":
                    row["evidence_ids"] = []
        return
    if name == "break_checkpoint":
        for side in ("source_rows", "restored_rows"):
            for row in destination[side]["checkpoints"]:
                if row.get("event") == "authority_declared":
                    row["chain_sha256"] = "0" * 64
        return
    if name == "resurrect_tombstone":
        for side in ("source_rows", "restored_rows"):
            for row in governed(side):
                if row.get("record_id") == "rec-erased-contact":
                    row["promotion_state"] = "promoted"
                    row["temporal_state"] = "current"
                    row["action"] = "import"
                    row["review_state"] = "approved"
        return
    raise ValueError(f"unknown injection {name}")


QUOTES = {
    "quote-agent-budget": "An example agent infers a synthetic budget of 1000 example units.",
    "quote-checklist-current": "Synthetic rollback checklist version B is the current example.",
    "quote-checklist-old": "Synthetic rollback checklist version A is an older example.",
    "quote-deploy-friday": "Synthetic Example Project has a test deployment proposed for Friday at 14:00 UTC.",
    "quote-deploy-thursday": "A synthetic older note says the test deployment is Thursday.",
    "quote-erased-contact": "A synthetic contact token was recorded and later erased.",
    "quote-excluded-question": "A synthetic one-off question asks about example weather.",
    "quote-held-preference": "A synthetic preference says the example review window is morning.",
    "quote-identity": "The public label for this scope is Primary Users.",
}
ITEMS = [
    ("synthetic-item-agent-budget", "Synthetic agent budget note", ["quote-agent-budget"]),
    ("synthetic-item-checklist", "Synthetic checklist notes", ["quote-checklist-old", "quote-checklist-current"]),
    ("synthetic-item-deployment", "Synthetic deployment notes", ["quote-deploy-thursday", "quote-deploy-friday"]),
    ("synthetic-item-erasure", "Synthetic erasure note", ["quote-erased-contact"]),
    ("synthetic-item-excluded", "Synthetic excluded question", ["quote-excluded-question"]),
    ("synthetic-item-held", "Synthetic held preference", ["quote-held-preference"]),
    ("synthetic-item-identity", "Synthetic public label", ["quote-identity"]),
]


def _disposition(**kwargs: Any) -> dict[str, Any]:
    quote_id = kwargs["quote_id"]
    text = QUOTES[quote_id]
    source_item_key = kwargs["source_item_key"]
    kwargs["content_sha256"] = sha256_hex(text.encode("utf-8"))
    kwargs["evidence_ids"] = sorted([
        f"ev-payload-{source_item_key}",
        f"ev-quote-{quote_id}",
    ])
    return kwargs


def _dispositions() -> list[dict[str, Any]]:
    rows = [
        _disposition(
            action="hold", authorship="agent_authored", conflict_group=None,
            consequential_domain="financial", manifest_key="agent-budget",
            promotion_state="rejected", provenance_basis="agent_inference",
            quote_id="quote-agent-budget", record_id="rec-agent-budget",
            review_state="rejected", source_item_key="synthetic-item-agent-budget",
            supersedes=None, temporal_state="unresolved", tombstone=None,
        ),
        _disposition(
            action="import", authorship="human_authored", conflict_group=None,
            consequential_domain=None, manifest_key="checklist-current",
            promotion_state="promoted", provenance_basis="human_direct",
            quote_id="quote-checklist-current", record_id="rec-checklist-current",
            review_state="approved", source_item_key="synthetic-item-checklist",
            supersedes="rec-checklist-old", temporal_state="current", tombstone=None,
        ),
        _disposition(
            action="import", authorship="human_authored", conflict_group=None,
            consequential_domain=None, manifest_key="checklist-old",
            promotion_state="historical", provenance_basis="human_direct",
            quote_id="quote-checklist-old", record_id="rec-checklist-old",
            review_state="approved", source_item_key="synthetic-item-checklist",
            supersedes=None, temporal_state="stale", tombstone=None,
        ),
        _disposition(
            action="hold", authorship="human_authored", conflict_group="synthetic-deploy-day",
            consequential_domain=None, manifest_key="deploy-friday",
            promotion_state="conflicted", provenance_basis="human_direct",
            quote_id="quote-deploy-friday", record_id="rec-deploy-friday",
            review_state="needs_review", source_item_key="synthetic-item-deployment",
            supersedes=None, temporal_state="conflicted", tombstone=None,
        ),
        _disposition(
            action="hold", authorship="human_authored", conflict_group="synthetic-deploy-day",
            consequential_domain=None, manifest_key="deploy-thursday",
            promotion_state="conflicted", provenance_basis="human_direct",
            quote_id="quote-deploy-thursday", record_id="rec-deploy-thursday",
            review_state="needs_review", source_item_key="synthetic-item-deployment",
            supersedes=None, temporal_state="conflicted", tombstone=None,
        ),
        _disposition(
            action="evidence", authorship="human_authored", conflict_group=None,
            consequential_domain=None, manifest_key="erased-contact",
            promotion_state="tombstoned", provenance_basis="human_direct",
            quote_id="quote-erased-contact", record_id="rec-erased-contact",
            review_state="approved", source_item_key="synthetic-item-erasure",
            supersedes=None, temporal_state="erased",
            tombstone={"erased_at": "2026-07-08T17:00:00Z", "reason": "synthetic_erasure"},
        ),
        _disposition(
            action="exclude", authorship="human_authored", conflict_group=None,
            consequential_domain=None, manifest_key="excluded-question",
            promotion_state="excluded", provenance_basis="human_direct",
            quote_id="quote-excluded-question", record_id="rec-excluded-question",
            review_state="approved", source_item_key="synthetic-item-excluded",
            supersedes=None, temporal_state="unresolved", tombstone=None,
        ),
        _disposition(
            action="hold", authorship="human_authored", conflict_group=None,
            consequential_domain=None, manifest_key="held-preference",
            promotion_state="held", provenance_basis="human_direct",
            quote_id="quote-held-preference", record_id="rec-held-preference",
            review_state="needs_review", source_item_key="synthetic-item-held",
            supersedes=None, temporal_state="unresolved", tombstone=None,
        ),
        _disposition(
            action="import", authorship="human_authored", conflict_group=None,
            consequential_domain="identity", manifest_key="identity-label",
            promotion_state="promoted", provenance_basis="human_direct",
            quote_id="quote-identity", record_id="rec-identity-label",
            review_state="approved", source_item_key="synthetic-item-identity",
            supersedes=None, temporal_state="current", tombstone=None,
        ),
    ]
    return sorted(rows, key=lambda row: row["record_id"])


def _probe_definitions() -> dict[str, Any]:
    probes = [
        {"active": True, "check": "agent_not_promoted", "expected_behavior": "Do not treat the synthetic agent budget inference as human authority.", "probe_category": "evidence_request", "probe_key": "synthetic-evidence-agent-budget", "record_id": "rec-agent-budget", "requires_restored_database": True, "severity": "critical"},
        {"active": True, "authority_epoch": AUTHORITY_EPOCH, "check": "authority_recorded", "expected_behavior": "Record authority for the named synthetic scope and epoch.", "probe_category": "authority_scope", "probe_key": "synthetic-authority-epoch", "requires_restored_database": True, "scope_id": SCOPE_ID, "severity": "critical"},
        {"active": True, "check": "candidate_not_promoted", "expected_behavior": "Keep the agent-authored budget candidate out of promoted memory.", "probe_category": "candidate_separation", "probe_key": "synthetic-candidate-separation", "record_id": "rec-agent-budget", "requires_restored_database": True, "severity": "critical"},
        {"active": True, "check": "conflict_preserved", "conflict_group": "synthetic-deploy-day", "expected_behavior": "Surface Friday and Thursday without choosing a winner.", "probe_category": "conflict", "probe_key": "synthetic-conflict-deploy-day", "requires_restored_database": True, "severity": "critical"},
        {"active": True, "check": "record_absent_from_promoted", "expected_behavior": "Keep the excluded example-weather question out of promoted memory.", "probe_category": "negative", "probe_key": "synthetic-negative-excluded-question", "record_id": "rec-excluded-question", "requires_restored_database": True, "severity": "critical"},
        {"active": True, "check": "record_promoted_current", "expected_behavior": "Recall the promoted public label Primary Users.", "probe_category": "positive", "probe_key": "synthetic-positive-public-label", "record_id": "rec-identity-label", "requires_restored_database": True, "severity": "critical"},
        {"active": True, "check": "held_not_promoted", "expected_behavior": "Leave the morning review-window preference on hold.", "probe_category": "review_boundary", "probe_key": "synthetic-review-held-preference", "record_id": "rec-held-preference", "requires_restored_database": True, "severity": "critical"},
        {"active": True, "check": "record_stale_preserved", "expected_behavior": "Preserve checklist version A as stale and not current.", "probe_category": "stale_state", "probe_key": "synthetic-stale-checklist", "record_id": "rec-checklist-old", "requires_restored_database": True, "severity": "critical"},
        {"active": True, "check": "tombstone_preserved", "expected_behavior": "Preserve the erasure marker and do not resurrect the synthetic contact token.", "probe_category": "tombstone", "probe_key": "synthetic-tombstone-erasure", "record_id": "rec-erased-contact", "requires_restored_database": True, "severity": "critical"},
    ]
    return {"probe_suite_version": PROBE_SUITE_VERSION, "probes": probes}


def _with_noise(rows: list[dict[str, Any]], salt: int) -> list[dict[str, Any]]:
    noisy = []
    for index, row in enumerate(rows):
        copy_row = copy.deepcopy(row)
        copy_row["cache_token"] = f"synthetic-cache-{salt}-{index}"
        copy_row["embedding"] = [index, salt]
        copy_row["hot_index_state"] = "excluded-from-hash"
        copy_row["physical_ordinal"] = salt * 100 + index
        copy_row["ranking_score"] = salt + index
        copy_row["sequence_value"] = 1000 + index
        noisy.append(copy_row)
    noisy.reverse()
    return noisy


def build_good_fixture_files() -> dict[str, bytes]:
    """Return the committed good fixture, including recomputed digests."""
    items = []
    evidence_entries = []
    for key, title, quote_ids in ITEMS:
        payload = "\n".join(QUOTES[quote_id] for quote_id in quote_ids) + "\n"
        encoded = payload.encode("utf-8")
        items.append({
            "content_type": "text/plain",
            "quotes": [{"quote_id": quote_id, "text": QUOTES[quote_id]} for quote_id in quote_ids],
            "raw_payload": payload,
            "source_author": "synthetic-agent" if "agent" in key else PRINCIPAL,
            "source_container": "synthetic-export/notes",
            "source_item_key": key,
            "source_kind": "note",
            "title": title,
        })
        evidence_entries.append({
            "byte_length": len(encoded),
            "evidence_id": f"ev-payload-{key}",
            "kind": "raw_payload",
            "sha256": sha256_hex(encoded),
            "source_item_key": key,
        })
        for quote_id in quote_ids:
            quote_bytes = QUOTES[quote_id].encode("utf-8")
            evidence_entries.append({
                "byte_length": len(quote_bytes),
                "evidence_id": f"ev-quote-{quote_id}",
                "kind": "source_quote",
                "quote_id": quote_id,
                "sha256": sha256_hex(quote_bytes),
                "source_item_key": key,
            })
    items.sort(key=lambda item: item["source_item_key"])
    evidence_entries.sort(key=lambda entry: entry["evidence_id"])
    package = {
        "batch": {
            "batch_key": "synthetic-offline-batch-001",
            "exported_item_count": len(items),
            "source_item_count": len(items),
            "status": "frozen",
        },
        "consequential_domains": ["financial", "identity", "legal", "medical"],
        "hash_algorithm": "sha256",
        "package_format": "smp.offline-verifier-package.v1",
        "scope_id": SCOPE_ID,
        "smp_version": "draft-0.3",
        "source_items": items,
        "source_system": {
            "adapter_name": "synthetic-offline-adapter",
            "adapter_version": "0.1.0",
            "description": "Entirely synthetic package for the offline SMP verifier fixture. It is not a live source.",
            "display_name": "Synthetic Offline Export",
            "source_key": "synthetic-offline-export",
            "source_type": "notes",
        },
    }
    dispositions = _dispositions()
    actions = [row["action"] for row in dispositions]
    manifest_body = {
        "batch_key": "synthetic-offline-batch-001",
        "dispositions": dispositions,
        "frozen_at": "2026-07-08T18:00:00Z",
        "manifest_format": "smp.manifest.v1",
        "reconciliation": {
            "approved_imports": sum(row["action"] == "import" and row["review_state"] == "approved" for row in dispositions),
            "candidates": len(dispositions),
            "evidence_only_rows": actions.count("evidence"),
            "excluded_rows": actions.count("exclude"),
            "held_rows": actions.count("hold"),
            "source_containers": 1,
            "source_items": len(items),
        },
        "scope_id": SCOPE_ID,
    }
    manifest = dict(manifest_body)
    manifest["manifest_sha256"] = sha256_hex(canonical_json_bytes(manifest_body))
    probes = _probe_definitions()
    results = {
        "executed_against": "recorded-restored-instance",
        "probe_run_id": "synthetic-probe-run-001",
        "probe_suite_version": PROBE_SUITE_VERSION,
        "results": [
            {"matched": True, "observed": "store predicate holds for the recorded restored instance", "probe_key": probe["probe_key"]}
            for probe in probes["probes"]
        ],
    }
    cutover = {
        "authority_epoch": AUTHORITY_EPOCH,
        "declaration": "Primary Users declare the synthetic example scope authoritative for epoch-2026-07-08.",
        "declared_at": "2026-07-08T18:30:00Z",
        "lifecycle": [
            "EXPORTED", "PRESERVED", "CLASSIFIED", "FROZEN", "LOADED",
            "PROBED", "REVIEWED", "PARALLEL", "AUTHORITATIVE",
        ],
        "principal": PRINCIPAL,
        "probe_run_id": "synthetic-probe-run-001",
        "probe_suite_version": PROBE_SUITE_VERSION,
        "record_format": "smp.cutover-record.v1",
        "reversible_until_recorded": True,
        "scope_id": SCOPE_ID,
    }
    evidence = {
        "algorithm": "sha256",
        "entries": evidence_entries,
        "evidence_format": "smp.evidence-hashes.v1",
    }
    backup = (
        "Synthetic offline backup for scope synthetic-example-scope.\n"
        "This artifact contains no credentials and no private records.\n"
        "Primary Users\n"
    ).encode("utf-8")
    files = {
        "canonical-governed-state.v1.json": canonical_json_bytes(CANONICAL_DEFINITION),
        "package.json": canonical_json_bytes(package),
        "manifest.json": canonical_json_bytes(manifest),
        "evidence-hashes.json": canonical_json_bytes(evidence),
        "probe-definitions.json": canonical_json_bytes(probes),
        "probe-results.json": canonical_json_bytes(results),
        "cutover-record.json": canonical_json_bytes(cutover),
        "backup/synthetic-scope-backup.txt": backup,
    }
    package_digest = sha256_hex(files["package.json"])
    probe_digest = sha256_hex(files["probe-definitions.json"])
    cutover_digest = sha256_hex(files["cutover-record.json"])
    backup_digest = sha256_hex(backup)
    payloads = {
        "genesis": sha256_hex(SCOPE_ID.encode("utf-8")),
        "manifest_frozen": sha256_hex(manifest["manifest_sha256"].encode("ascii")),
        "probes_recorded": sha256_hex(probe_digest.encode("ascii")),
        "authority_declared": sha256_hex(cutover_digest.encode("ascii")),
    }
    events = ["genesis", "manifest_frozen", "probes_recorded", "authority_declared"]
    checkpoints = []
    previous = None
    for ordinal, event in enumerate(events, start=1):
        record_id = f"ckpt-{ordinal}"
        checkpoints.append({
            "chain_sha256": _chain_hash(ordinal, previous, event, payloads[event]),
            "event": event,
            "ordinal": ordinal,
            "payload_sha256": payloads[event],
            "prev_record_id": previous,
            "record_id": record_id,
        })
        previous = record_id
    source_items = []
    for item in items:
        encoded = item["raw_payload"].encode("utf-8")
        source_items.append({
            "payload_sha256": sha256_hex(encoded),
            "payload_size_bytes": len(encoded),
            "record_id": item["source_item_key"],
            "source_item_key": item["source_item_key"],
        })
    authority = [{
        "authority_epoch": AUTHORITY_EPOCH,
        "principal": PRINCIPAL,
        "probe_run_id": "synthetic-probe-run-001",
        "record_id": "authority-epoch-2026-07-08",
        "scope_id": SCOPE_ID,
    }]
    source_rows = {
        "authority": authority,
        "checkpoints": checkpoints,
        "governed_records": dispositions,
        "source_items": source_items,
    }
    restored_rows = {
        "authority": _with_noise(authority, 2),
        "checkpoints": _with_noise(checkpoints, 3),
        "governed_records": _with_noise(dispositions, 4),
        "source_items": _with_noise(source_items, 5),
    }
    destination_without_claims = {
        "backup": {
            "format": "synthetic-text-backup",
            "path": "backup/synthetic-scope-backup.txt",
            "sha256": backup_digest,
            "size_bytes": len(backup),
        },
        "canonical_definition_version": DEFINITION_VERSION,
        "description_format": "smp.destination-store-description.v1",
        "exclusions": list(REQUIRED_EXCLUSIONS),
        "probe_execution": {"connects_to_database": False, "mode": "recorded-results"},
        "probe_suite_sha256": probe_digest,
        "restore_target": {
            "engine": "PostgreSQL",
            "engine_version": "15",
            "extensions": ["pgcrypto"],
            "fingerprint": "synthetic-empty-postgresql-15",
        },
        "restored_rows": restored_rows,
        "schema": {
            "migration_head": MIGRATION_IDS[-1],
            "migration_ids": list(MIGRATION_IDS),
            "profile": "synthetic-offline-v1",
            "version": "reference-sql-01-through-11",
        },
        "scope": {"authority_epoch": AUTHORITY_EPOCH, "scope_id": SCOPE_ID},
        "source_package_digest": package_digest,
        "source_rows": source_rows,
    }
    quiet: list[Failure] = []
    source_hash = _state_hash(destination_without_claims, "source_rows", quiet)
    restored_hash = _state_hash(destination_without_claims, "restored_rows", quiet)
    if quiet or source_hash != restored_hash:
        raise RuntimeError(f"good fixture canonical hash failed: {quiet}")
    destination = dict(destination_without_claims)
    destination["claimed_restored_sha256"] = restored_hash
    destination["claimed_source_sha256"] = source_hash
    files["destination-store.json"] = canonical_json_bytes(destination)
    return files


def materialize(root: Path) -> None:
    for relative, data in build_good_fixture_files().items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate the synthetic offline SMP fixture.")
    parser.add_argument("fixture", type=Path, help="fixture directory")
    parser.add_argument(
        "--inject",
        choices=sorted([
            "break_checkpoint",
            "drop_authority",
            "flatten_conflict",
            "missing_consequential_evidence",
            "non_governed_noise",
            "promote_agent_content",
            "resurrect_tombstone",
            "unaccounted_source_item",
        ]),
        help="mutate the loaded fixture in memory and expect a specific failure, except non_governed_noise",
    )
    parser.add_argument("--materialize", action="store_true", help="rewrite the good fixture files in place")
    args = parser.parse_args(argv)
    if args.materialize:
        materialize(args.fixture)
        return 0
    fixture = load_fixture(args.fixture)
    if args.inject:
        if "destination-store.json" not in fixture.documents or "package.json" not in fixture.documents:
            print("verification_failed: fixture_unreadable", file=sys.stderr)
            return 1
        apply_injection(fixture, args.inject)
    receipt = verify(fixture)
    sys.stdout.buffer.write(canonical_json_bytes(receipt))
    if receipt["result"] == "custody_verified" and receipt["skip_or_failure_reason"] is None:
        print("SMP-complete", file=sys.stderr)
        return 0
    print(f"verification_failed: {receipt['skip_or_failure_reason']}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
