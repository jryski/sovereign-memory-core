"""Engine-free validation for deterministic Sovereign Memory bundles."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any, NoReturn

try:
    from scripts.sovereignty_bundle import (
        MAX_ARCHIVE_SIZE, ArchiveMember, parse_canonical_json_bytes, validate_ustar,
    )
except ModuleNotFoundError as exc:
    if exc.name != "scripts":
        raise
    from sovereignty_bundle import (
        MAX_ARCHIVE_SIZE, ArchiveMember, parse_canonical_json_bytes, validate_ustar,
    )


_SHA256 = re.compile(r"^[0-9a-f]{64}$")
_COMMIT = re.compile(r"^[0-9a-f]{40}$")
_ENTRY_KEYS = {"bytes", "media_type", "mode", "path", "role", "sha256"}
_TOP_LEVEL_KEYS = {
    "compatibility", "dependencies", "entries", "evidence", "exporter", "format",
    "loss_report_path", "migrations", "profile", "relations", "restore_plan_path",
    "schema_version", "sequence_state_path", "source", "source_snapshot_path", "toolchain",
}
_POINTER_ROLES = {
    "loss_report_path": ("loss-report", "application/json"),
    "restore_plan_path": ("restore-plan", "application/json"),
    "sequence_state_path": ("sequence-state", "application/json"),
    "source_snapshot_path": ("source-snapshot", "application/json"),
}
_MANIFEST_SCHEMA_PATH = Path(__file__).resolve().parent.parent / "release" / "sovereignty-manifest.schema.json"


class BundleValidationError(ValueError):
    """A fail-closed bundle error with a stable machine-readable code."""

    def __init__(self, code: str, message: str):
        self.code = code
        super().__init__(message)


@dataclass(frozen=True)
class BundleValidationResult:
    manifest: dict[str, Any]
    archive_sha256: str
    archive_paths: tuple[str, ...]


def _fail(code: str, message: str) -> NoReturn:
    raise BundleValidationError(code, message)


def _object(value: Any, keys: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        _fail("MANIFEST_STRUCTURE", f"{label} must contain exactly {sorted(keys)!r}")
    return value


def _nonempty_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value:
        _fail("MANIFEST_STRUCTURE", f"{label} must be a nonempty string")
    return value


def _sha256(value: Any, label: str) -> str:
    if not isinstance(value, str) or _SHA256.fullmatch(value) is None:
        _fail("MANIFEST_STRUCTURE", f"{label} must be lowercase SHA-256 hex")
    return value


def _sorted_unique_strings(value: Any, label: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        _fail("MANIFEST_STRUCTURE", f"{label} must be an array of nonempty strings")
    if value != sorted(set(value), key=lambda item: item.encode("utf-8")):
        _fail("MANIFEST_STRUCTURE", f"{label} must be bytewise sorted and unique")
    return value


def _ordered_unique_strings(value: Any, label: str) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        _fail("MANIFEST_STRUCTURE", f"{label} must be an array of nonempty strings")
    if len(set(value)) != len(value):
        _fail("MANIFEST_STRUCTURE", f"{label} must contain unique items")
    return value


def _schema_type_matches(value: Any, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    return False


def _schema_value_key(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _schema_constraint_code(label: str) -> str:
    if label.startswith("manifest.compatibility.postgresql."):
        return "MANIFEST_COMPATIBILITY"
    if label.startswith("manifest.entries[") and label.endswith(".mode"):
        return "ENTRY_METADATA"
    if label.startswith("manifest.entries[") and label.endswith((".media_type", ".role")):
        return "MANIFEST_DEPENDENCY"
    return "MANIFEST_STRUCTURE"


def _validate_schema_node(value: Any, node: dict[str, Any], root: dict[str, Any], label: str) -> None:
    """Validate the small JSON Schema subset used by the release contract."""
    reference = node.get("$ref")
    if reference is not None:
        if not isinstance(reference, str) or not reference.startswith("#/$defs/"):
            _fail("MANIFEST_SCHEMA", f"unsupported schema reference at {label}")
        definition = root.get("$defs", {}).get(reference.removeprefix("#/$defs/"))
        if not isinstance(definition, dict):
            _fail("MANIFEST_SCHEMA", f"unresolved schema reference at {label}")
        _validate_schema_node(value, definition, root, label)
        return

    expected_type = node.get("type")
    if expected_type is not None and not _schema_type_matches(value, expected_type):
        _fail("MANIFEST_STRUCTURE", f"{label} must have JSON Schema type {expected_type}")
    if "const" in node and value != node["const"]:
        _fail(_schema_constraint_code(label), f"{label} does not match its required constant")
    if "enum" in node and value not in node["enum"]:
        _fail(_schema_constraint_code(label), f"{label} is outside its allowed values")

    if isinstance(value, str):
        if len(value) < node.get("minLength", 0):
            _fail("MANIFEST_STRUCTURE", f"{label} is shorter than allowed")
        pattern = node.get("pattern")
        if pattern is not None and re.search(pattern, value) is None:
            _fail("MANIFEST_STRUCTURE", f"{label} does not match its required pattern")
    elif isinstance(value, int) and not isinstance(value, bool):
        if "minimum" in node and value < node["minimum"]:
            _fail("MANIFEST_STRUCTURE", f"{label} is below its minimum")
    elif isinstance(value, list):
        if len(value) < node.get("minItems", 0):
            _fail("MANIFEST_STRUCTURE", f"{label} has too few items")
        if node.get("uniqueItems") and len({_schema_value_key(item) for item in value}) != len(value):
            _fail("MANIFEST_STRUCTURE", f"{label} items must be unique")
        item_schema = node.get("items")
        if isinstance(item_schema, dict):
            for index, item in enumerate(value):
                _validate_schema_node(item, item_schema, root, f"{label}[{index}]")
    elif isinstance(value, dict):
        required = node.get("required", [])
        missing = [key for key in required if key not in value]
        if missing:
            _fail("MANIFEST_STRUCTURE", f"{label} is missing required keys {missing!r}")
        properties = node.get("properties", {})
        if node.get("additionalProperties") is False:
            extras = sorted(set(value) - set(properties))
            if extras:
                _fail("MANIFEST_STRUCTURE", f"{label} has undeclared keys {extras!r}")
        for key, child_schema in properties.items():
            if key in value:
                _validate_schema_node(value[key], child_schema, root, f"{label}.{key}")


def _validate_release_schema(manifest: Any) -> None:
    try:
        with _MANIFEST_SCHEMA_PATH.open("r", encoding="utf-8") as source:
            schema = json.load(source)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        _fail("MANIFEST_SCHEMA", f"release manifest schema is unavailable or invalid: {exc}")
    if not isinstance(schema, dict):
        _fail("MANIFEST_SCHEMA", "release manifest schema root must be an object")
    _validate_schema_node(manifest, schema, schema, "manifest")


def _validate_dependency_graph(dependencies: Any, entry_paths: set[str]) -> None:
    if not isinstance(dependencies, list):
        _fail("MANIFEST_STRUCTURE", "dependencies must be an array")
    paths: list[str] = []
    graph: dict[str, list[str]] = {}
    for index, dependency in enumerate(dependencies):
        item = _object(dependency, {"path", "requires"}, f"dependencies[{index}]")
        path = _nonempty_string(item["path"], f"dependencies[{index}].path")
        requires = _sorted_unique_strings(item["requires"], f"dependencies[{index}].requires")
        if path not in entry_paths or any(required not in entry_paths for required in requires):
            _fail("MANIFEST_DEPENDENCY", "dependency graph contains a path absent from entries")
        if path in requires:
            _fail("MANIFEST_DEPENDENCY", "dependency graph contains a self dependency")
        paths.append(path)
        graph[path] = requires
    if paths != sorted(set(paths), key=lambda item: item.encode("utf-8")):
        _fail("MANIFEST_DEPENDENCY", "dependency nodes must be bytewise sorted and unique")

    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(path: str) -> None:
        if path in visiting:
            _fail("MANIFEST_DEPENDENCY", "dependency graph contains a cycle")
        if path in visited or path not in graph:
            return
        visiting.add(path)
        for required in graph[path]:
            visit(required)
        visiting.remove(path)
        visited.add(path)

    for path in graph:
        visit(path)


def _validate_manifest(manifest: Any, archive_paths: set[str]) -> dict[str, Any]:
    if isinstance(manifest, dict) and isinstance(manifest.get("entries"), list):
        if any(isinstance(entry, dict) and entry.get("path") == "manifest.json" for entry in manifest["entries"]):
            _fail("MANIFEST_RECURSION", "manifest.json must not inventory itself")
    _validate_release_schema(manifest)
    manifest = _object(manifest, _TOP_LEVEL_KEYS, "manifest")
    if manifest["format"] != "sovereign-memory.bundle/1.0":
        _fail("MANIFEST_STRUCTURE", "unsupported bundle format")
    if manifest["schema_version"] != "sovereign-memory.manifest/1.0":
        _fail("MANIFEST_STRUCTURE", "unsupported manifest schema")
    if manifest["profile"] != "full-synthetic-v1":
        _fail("MANIFEST_STRUCTURE", "unsupported bundle profile")

    source = _object(manifest["source"], {"commit", "repository_url"}, "source")
    if not isinstance(source["commit"], str) or _COMMIT.fullmatch(source["commit"]) is None:
        _fail("MANIFEST_STRUCTURE", "source.commit must be lowercase 40-character hex")
    _nonempty_string(source["repository_url"], "source.repository_url")
    exporter = _object(manifest["exporter"], {"version"}, "exporter")
    _nonempty_string(exporter["version"], "exporter.version")

    compatibility = _object(manifest["compatibility"], {"postgresql"}, "compatibility")
    postgres = _object(
        compatibility["postgresql"],
        {"maximum_exclusive_major", "minimum_major"},
        "compatibility.postgresql",
    )
    if postgres != {"maximum_exclusive_major": 17, "minimum_major": 15}:
        _fail("MANIFEST_COMPATIBILITY", "PostgreSQL compatibility must be exactly >=15 <17")

    toolchain = manifest["toolchain"]
    if not isinstance(toolchain, list) or not toolchain:
        _fail("MANIFEST_STRUCTURE", "toolchain must be a nonempty array")
    tool_names: list[str] = []
    for index, raw_tool in enumerate(toolchain):
        tool = _object(raw_tool, {"identity", "name", "version"}, f"toolchain[{index}]")
        tool_names.append(_nonempty_string(tool["name"], f"toolchain[{index}].name"))
        _nonempty_string(tool["identity"], f"toolchain[{index}].identity")
        _nonempty_string(tool["version"], f"toolchain[{index}].version")
    if tool_names != sorted(set(tool_names), key=lambda item: item.encode("utf-8")):
        _fail("MANIFEST_STRUCTURE", "toolchain names must be bytewise sorted and unique")

    entries = manifest["entries"]
    if not isinstance(entries, list) or not entries:
        _fail("MANIFEST_STRUCTURE", "entries must be a nonempty array")
    entry_by_path: dict[str, dict[str, Any]] = {}
    for index, raw_entry in enumerate(entries):
        entry = _object(raw_entry, _ENTRY_KEYS, f"entries[{index}]")
        path = _nonempty_string(entry["path"], f"entries[{index}].path")
        if path == "manifest.json":
            _fail("MANIFEST_RECURSION", "manifest.json must not inventory itself")
        if not isinstance(entry["bytes"], int) or isinstance(entry["bytes"], bool) or entry["bytes"] < 0:
            _fail("MANIFEST_STRUCTURE", "entry bytes must be a non-negative integer")
        if entry["mode"] != "0644":
            _fail("ENTRY_METADATA", f"entry {path!r} mode must be 0644")
        _nonempty_string(entry["role"], f"entries[{index}].role")
        _nonempty_string(entry["media_type"], f"entries[{index}].media_type")
        _sha256(entry["sha256"], f"entries[{index}].sha256")
        entry_by_path[path] = entry
    paths = [entry["path"] for entry in entries]
    if paths != sorted(set(paths), key=lambda item: item.encode("utf-8")):
        _fail("MANIFEST_INVENTORY", "entries must be bytewise sorted and unique")
    if archive_paths != {"manifest.json", *entry_by_path}:
        _fail("MANIFEST_INVENTORY", "archive paths do not equal manifest root plus entries")

    declared_paths: list[str] = []

    for field, expected in _POINTER_ROLES.items():
        path = _nonempty_string(manifest[field], field)
        entry = entry_by_path.get(path)
        if entry is None:
            _fail("MANIFEST_DEPENDENCY", f"{field} does not resolve to an entry")
        if (entry["role"], entry["media_type"]) != expected:
            _fail("ENTRY_METADATA", f"{field} has the wrong role or media type")
        declared_paths.append(path)

    migrations = manifest["migrations"]
    if not isinstance(migrations, list) or not migrations:
        _fail("MANIFEST_STRUCTURE", "migrations must be a nonempty array")
    migration_paths: list[str] = []
    for index, raw_migration in enumerate(migrations):
        migration = _object(raw_migration, {"order", "path", "sha256"}, f"migrations[{index}]")
        if migration["order"] != index + 1:
            _fail("MANIFEST_DEPENDENCY", "migration order must be contiguous and match the array")
        path = _nonempty_string(migration["path"], f"migrations[{index}].path")
        digest = _sha256(migration["sha256"], f"migrations[{index}].sha256")
        entry = entry_by_path.get(path)
        if entry is None or entry["role"] != "migration" or entry["media_type"] != "application/sql":
            _fail("MANIFEST_DEPENDENCY", "migration does not resolve to a migration entry")
        if digest != entry["sha256"]:
            _fail("MANIFEST_DECLARATION_MISMATCH", "migration hash disagrees with its entry")
        migration_paths.append(path)
        declared_paths.append(path)
    if migration_paths != sorted(set(migration_paths), key=lambda item: item.encode("utf-8")):
        _fail("MANIFEST_STRUCTURE", "migrations must be bytewise sorted and unique")

    relations = manifest["relations"]
    if not isinstance(relations, list):
        _fail("MANIFEST_STRUCTURE", "relations must be an array")
    relation_keys: list[tuple[int, str, str]] = []
    relation_names: set[str] = set()
    relation_dependencies: list[tuple[str, list[str]]] = []
    relation_records: list[tuple[str, int, set[str], list[dict[str, Any]]]] = []
    for index, raw_relation in enumerate(relations):
        relation = _object(
            raw_relation,
            {
                "bytes", "columns", "dependencies", "foreign_keys", "path", "primary_key",
                "relation", "restore_order", "row_count", "row_digest_algorithm", "schema", "sha256",
            },
            f"relations[{index}]",
        )
        order = relation["restore_order"]
        if not isinstance(order, int) or isinstance(order, bool) or order < 1:
            _fail("MANIFEST_STRUCTURE", "relation restore_order must be a positive integer")
        schema = _nonempty_string(relation["schema"], f"relations[{index}].schema")
        name = _nonempty_string(relation["relation"], f"relations[{index}].relation")
        path = _nonempty_string(relation["path"], f"relations[{index}].path")
        entry = entry_by_path.get(path)
        if entry is None or entry["role"] != "relation" or entry["media_type"] != "application/x-ndjson":
            _fail("MANIFEST_DEPENDENCY", "relation does not resolve to a relation entry")
        if relation["bytes"] != entry["bytes"] or relation["sha256"] != entry["sha256"]:
            _fail("MANIFEST_DECLARATION_MISMATCH", "relation bytes/hash disagree with its entry")
        if (
            not isinstance(relation["row_count"], int)
            or isinstance(relation["row_count"], bool)
            or relation["row_count"] < 0
            or relation["row_digest_algorithm"] != "sha256-raw-jsonl-v1"
        ):
            _fail("MANIFEST_STRUCTURE", "relation row digest metadata is invalid")
        columns = relation["columns"]
        if not isinstance(columns, list) or not columns:
            _fail("MANIFEST_STRUCTURE", "relation columns must be a nonempty array")
        column_names: list[str] = []
        for column_index, raw_column in enumerate(columns):
            column = _object(raw_column, {"name", "ordinal", "pg_type"}, "relation column")
            if column["ordinal"] != column_index + 1:
                _fail("MANIFEST_DEPENDENCY", "column ordinals must be contiguous and ordered")
            column_names.append(_nonempty_string(column["name"], "column name"))
            _nonempty_string(column["pg_type"], "column PostgreSQL type")
        if len(set(column_names)) != len(column_names):
            _fail("MANIFEST_DEPENDENCY", "relation column names must be unique")
        primary_key = _ordered_unique_strings(relation["primary_key"], "relation primary_key")
        if not primary_key or any(column not in column_names for column in primary_key):
            _fail("MANIFEST_DEPENDENCY", "primary key does not close over relation columns")
        foreign_keys = relation["foreign_keys"]
        if not isinstance(foreign_keys, list):
            _fail("MANIFEST_STRUCTURE", "foreign_keys must be an array")
        checked_foreign_keys: list[dict[str, Any]] = []
        for raw_foreign_key in foreign_keys:
            foreign_key = _object(
                raw_foreign_key,
                {"columns", "deferrable", "referenced_columns", "referenced_relation", "referenced_schema"},
                "foreign key",
            )
            local_columns = _ordered_unique_strings(foreign_key["columns"], "foreign key columns")
            referenced_columns = _ordered_unique_strings(
                foreign_key["referenced_columns"], "foreign key referenced_columns"
            )
            if (
                not local_columns
                or len(local_columns) != len(referenced_columns)
                or any(column not in column_names for column in local_columns)
                or not isinstance(foreign_key["deferrable"], bool)
            ):
                _fail("MANIFEST_DEPENDENCY", "foreign key metadata is structurally incomplete")
            _nonempty_string(foreign_key["referenced_schema"], "referenced schema")
            _nonempty_string(foreign_key["referenced_relation"], "referenced relation")
            checked_foreign_keys.append(foreign_key)
        dependencies = _sorted_unique_strings(relation["dependencies"], f"relations[{index}].dependencies")
        identity = f"{schema}.{name}"
        if identity in relation_names:
            _fail("MANIFEST_STRUCTURE", "relation identities must be unique")
        relation_names.add(identity)
        relation_dependencies.append((identity, dependencies))
        relation_records.append((identity, order, set(column_names), checked_foreign_keys))
        relation_keys.append((order, schema, name))
        declared_paths.append(path)
    if relation_keys != sorted(relation_keys) or len({key[0] for key in relation_keys}) != len(relation_keys):
        _fail("MANIFEST_DEPENDENCY", "relations must have unique ordered restore_order values")
    for identity, dependencies in relation_dependencies:
        if identity in dependencies or any(dependency not in relation_names for dependency in dependencies):
            _fail("MANIFEST_DEPENDENCY", "relation dependency closure is incomplete")
    columns_by_relation = {identity: columns for identity, _, columns, _ in relation_records}
    restore_order_by_relation = {identity: order for identity, order, _, _ in relation_records}
    dependencies_by_relation = dict(relation_dependencies)
    for identity, order, _, foreign_keys in relation_records:
        expected_dependencies: set[str] = set()
        for foreign_key in foreign_keys:
            target = f"{foreign_key['referenced_schema']}.{foreign_key['referenced_relation']}"
            target_columns = columns_by_relation.get(target)
            if target_columns is None or any(
                column not in target_columns for column in foreign_key["referenced_columns"]
            ):
                _fail("MANIFEST_DEPENDENCY", "foreign key target closure is incomplete")
            if not foreign_key["deferrable"] and restore_order_by_relation[target] >= order:
                _fail(
                    "MANIFEST_DEPENDENCY",
                    "non-deferrable foreign key target must precede its dependent relation",
                )
            expected_dependencies.add(target)
        if set(dependencies_by_relation[identity]) != expected_dependencies:
            _fail("MANIFEST_DEPENDENCY", "relation dependencies must exactly match foreign key targets")

    evidence = manifest["evidence"]
    if not isinstance(evidence, list):
        _fail("MANIFEST_STRUCTURE", "evidence must be an array")
    evidence_paths: list[str] = []
    for index, raw_evidence in enumerate(evidence):
        item = _object(raw_evidence, {"locators", "path", "sha256"}, f"evidence[{index}]")
        path = _nonempty_string(item["path"], f"evidence[{index}].path")
        digest = _sha256(item["sha256"], f"evidence[{index}].sha256")
        entry = entry_by_path.get(path)
        if entry is None or entry["role"] != "evidence" or entry["media_type"] != "application/octet-stream":
            _fail("MANIFEST_DEPENDENCY", "evidence does not resolve to an evidence entry")
        if digest != entry["sha256"]:
            _fail("MANIFEST_DECLARATION_MISMATCH", "evidence hash disagrees with its entry")
        if path != f"evidence/sha256/{digest[:2]}/{digest}":
            _fail("MANIFEST_DEPENDENCY", "evidence path is not content addressed by its SHA-256")
        locators = item["locators"]
        if not isinstance(locators, list) or not locators:
            _fail("MANIFEST_STRUCTURE", "evidence locators must be a nonempty array")
        locator_names: list[str] = []
        for raw_locator in locators:
            locator = _object(raw_locator, {"byte_end", "byte_start", "locator"}, "evidence locator")
            locator_name = _nonempty_string(locator["locator"], "evidence locator")
            start = locator["byte_start"]
            end = locator["byte_end"]
            if (
                not isinstance(start, int) or isinstance(start, bool)
                or not isinstance(end, int) or isinstance(end, bool)
                or start < 0 or end <= start or end > entry["bytes"]
            ):
                _fail("MANIFEST_DEPENDENCY", "evidence locator span is outside its payload")
            locator_names.append(locator_name)
        if locator_names != sorted(set(locator_names), key=lambda value: value.encode("utf-8")):
            _fail("MANIFEST_DEPENDENCY", "evidence locators must be bytewise sorted and unique")
        evidence_paths.append(path)
        declared_paths.append(path)
    if evidence_paths != sorted(set(evidence_paths), key=lambda item: item.encode("utf-8")):
        _fail("MANIFEST_STRUCTURE", "evidence must be bytewise sorted and unique")
    if len(declared_paths) != len(entry_by_path) or set(declared_paths) != set(entry_by_path):
        _fail("MANIFEST_DEPENDENCY", "every entry must have exactly one structural declaration")

    _validate_dependency_graph(manifest["dependencies"], set(entry_by_path))
    return manifest


def _member_view(raw: bytes, member: ArchiveMember) -> memoryview:
    return memoryview(raw)[member.data_offset:member.data_offset + member.size]


def validate_bundle(
    raw: bytes,
    *,
    expected_archive_sha256: str | None = None,
    **archive_limits: int,
) -> BundleValidationResult:
    """Validate archive, canonical manifest, closure, inventory, and member hashes.

    Validation is engine-free and performs no extraction, network, or database I/O.
    Member payloads are hashed through bounded memory views rather than copied.
    """
    if expected_archive_sha256 is not None:
        expected_archive_sha256 = _sha256(expected_archive_sha256, "expected archive SHA-256")
    archive_sha256 = hashlib.sha256(raw).hexdigest() if isinstance(raw, bytes) else ""
    if expected_archive_sha256 is not None and archive_sha256 != expected_archive_sha256:
        _fail("ARCHIVE_SHA256_MISMATCH", "archive SHA-256 does not match the external checksum")
    try:
        members = validate_ustar(raw, **archive_limits)
    except (TypeError, ValueError) as exc:
        _fail("ARCHIVE_INVALID", str(exc))

    member_by_path = {member.path: member for member in members}
    manifest_member = member_by_path.get("manifest.json")
    if manifest_member is None:
        _fail("MANIFEST_MISSING", "archive does not contain manifest.json")
    try:
        manifest_raw = bytes(_member_view(raw, manifest_member))
        manifest = parse_canonical_json_bytes(manifest_raw)
    except (TypeError, ValueError) as exc:
        _fail("MANIFEST_CANONICAL", str(exc))
    archive_paths = set(member_by_path)
    manifest = _validate_manifest(manifest, archive_paths)

    for entry in manifest["entries"]:
        member = member_by_path[entry["path"]]
        if member.size != entry["bytes"]:
            _fail("ENTRY_BYTES", f"member {member.path!r} byte count does not match manifest")
        digest = hashlib.sha256(_member_view(raw, member)).hexdigest()
        if digest != entry["sha256"]:
            _fail("MEMBER_SHA256_MISMATCH", f"member {member.path!r} SHA-256 does not match manifest")

    return BundleValidationResult(manifest, archive_sha256, tuple(member.path for member in members))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive")
    parser.add_argument("--expected-sha256")
    parser.add_argument("--max-archive-size", type=int, default=MAX_ARCHIVE_SIZE)
    args = parser.parse_args(argv)
    try:
        if not 0 <= args.max_archive_size <= MAX_ARCHIVE_SIZE:
            _fail(
                "ARCHIVE_INVALID",
                f"max archive size must be between 0 and {MAX_ARCHIVE_SIZE}",
            )
        with open(args.archive, "rb") as source:
            raw = source.read(args.max_archive_size + 1)
        result = validate_bundle(
            raw,
            expected_archive_sha256=args.expected_sha256,
            max_archive_size=args.max_archive_size,
        )
    except BundleValidationError as exc:
        print(json.dumps({"code": exc.code, "message": str(exc)}, sort_keys=True), file=sys.stderr)
        return 1
    print(json.dumps({"archive_sha256": result.archive_sha256, "code": "OK"}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
