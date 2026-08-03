import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import tracemalloc
import unittest
from unittest import mock

from scripts import sovereignty_bundle as bundle
from scripts import validate_sovereignty_bundle as validator


MEMBERS = {
    "data/001-public.memory.jsonl": b'{"pk":["1"],"row":{"id":"1"}}\n',
    "evidence/sha256/b7/b781ca4e3efcbf31178927825de855f45b7e52f0d652af03cfb236785de2fe48": b"synthetic evidence\n",
    "migrations/01_core.sql": b"SELECT 1;\n",
    "reports/loss-report.json": b'{"loss_summary":{"unclassified":0,"unsupported":0}}\n',
    "reports/source-snapshot.json": b'{"source":"fixture"}\n',
    "restore/plan.json": b'{"steps":[]}\n',
    "state/sequences.json": b'{"sequences":[]}\n',
}


def _entry(path, role, media_type):
    raw = MEMBERS[path]
    return {
        "bytes": len(raw),
        "media_type": media_type,
        "mode": "0644",
        "path": path,
        "role": role,
        "sha256": hashlib.sha256(raw).hexdigest(),
    }


def valid_manifest():
    entries = [
        _entry("data/001-public.memory.jsonl", "relation", "application/x-ndjson"),
        _entry(
            "evidence/sha256/b7/b781ca4e3efcbf31178927825de855f45b7e52f0d652af03cfb236785de2fe48",
            "evidence",
            "application/octet-stream",
        ),
        _entry("migrations/01_core.sql", "migration", "application/sql"),
        _entry("reports/loss-report.json", "loss-report", "application/json"),
        _entry("reports/source-snapshot.json", "source-snapshot", "application/json"),
        _entry("restore/plan.json", "restore-plan", "application/json"),
        _entry("state/sequences.json", "sequence-state", "application/json"),
    ]
    return {
        "compatibility": {"postgresql": {"maximum_exclusive_major": 17, "minimum_major": 15}},
        "dependencies": [
            {"path": "data/001-public.memory.jsonl", "requires": ["migrations/01_core.sql"]},
        ],
        "entries": entries,
        "evidence": [{
            "locators": [{
                "byte_end": 9,
                "byte_start": 0,
                "locator": "artifact:sha256:b781ca4e3efcbf31178927825de855f45b7e52f0d652af03cfb236785de2fe48",
            }],
            "path": entries[1]["path"],
            "sha256": entries[1]["sha256"],
        }],
        "exporter": {"version": "1.0.0"},
        "format": "sovereign-memory.bundle/1.0",
        "loss_report_path": "reports/loss-report.json",
        "migrations": [
            {"order": 1, "path": "migrations/01_core.sql", "sha256": entries[2]["sha256"]},
        ],
        "profile": "full-synthetic-v1",
        "relations": [
            {
                "bytes": entries[0]["bytes"],
                "columns": [{"name": "id", "ordinal": 1, "pg_type": "bigint"}],
                "dependencies": [],
                "foreign_keys": [],
                "path": "data/001-public.memory.jsonl",
                "primary_key": ["id"],
                "relation": "memory",
                "restore_order": 1,
                "row_count": 1,
                "row_digest_algorithm": "sha256-raw-jsonl-v1",
                "schema": "public",
                "sha256": entries[0]["sha256"],
            },
        ],
        "restore_plan_path": "restore/plan.json",
        "schema_version": "sovereign-memory.manifest/1.0",
        "sequence_state_path": "state/sequences.json",
        "source": {
            "commit": "0123456789abcdef0123456789abcdef01234567",
            "repository_url": "https://github.com/jryski/sovereign-memory-core.git",
        },
        "source_snapshot_path": "reports/source-snapshot.json",
        "toolchain": [{"identity": "sha256:" + "a" * 64, "name": "python", "version": "3.11"}],
    }


def bundle_bytes(manifest=None, members=None):
    manifest = valid_manifest() if manifest is None else manifest
    members = MEMBERS if members is None else members
    return bundle.write_ustar(
        [("manifest.json", bundle.canonical_json_bytes(manifest)), *members.items()]
    )


def replace_member(manifest, members, path, payload):
    members[path] = payload
    digest = hashlib.sha256(payload).hexdigest()
    entry = next(entry for entry in manifest["entries"] if entry["path"] == path)
    entry["bytes"] = len(payload)
    entry["sha256"] = digest
    for relation in manifest["relations"]:
        if relation["path"] == path:
            relation["bytes"] = len(payload)
            relation["sha256"] = digest
    for migration in manifest["migrations"]:
        if migration["path"] == path:
            migration["sha256"] = digest


def add_relation(manifest, members, *, name, order, columns, primary_key, dependencies, foreign_keys):
    path = f"data/100-public.{name}.jsonl"
    payload = b""
    members[path] = payload
    entry = {
        "bytes": len(payload),
        "media_type": "application/x-ndjson",
        "mode": "0644",
        "path": path,
        "role": "relation",
        "sha256": hashlib.sha256(payload).hexdigest(),
    }
    manifest["entries"].append(entry)
    manifest["entries"].sort(key=lambda item: item["path"].encode("utf-8"))
    manifest["relations"].append({
        "bytes": entry["bytes"],
        "columns": [
            {"name": column, "ordinal": index, "pg_type": "bigint"}
            for index, column in enumerate(columns, start=1)
        ],
        "dependencies": dependencies,
        "foreign_keys": foreign_keys,
        "path": path,
        "primary_key": primary_key,
        "relation": name,
        "restore_order": order,
        "row_count": 0,
        "row_digest_algorithm": "sha256-raw-jsonl-v1",
        "schema": "public",
        "sha256": entry["sha256"],
    })
    manifest["relations"].sort(key=lambda relation: relation["restore_order"])


def add_migration_chain(manifest, members, count):
    original_path = manifest["migrations"][0]["path"]
    members.pop(original_path)
    manifest["entries"] = [
        entry for entry in manifest["entries"] if entry["path"] != original_path
    ]
    digest = hashlib.sha256(b"").hexdigest()
    paths = [f"migrations/{index:04d}.sql" for index in range(count)]
    for path in paths:
        members[path] = b""
        manifest["entries"].append({
            "bytes": 0,
            "media_type": "application/sql",
            "mode": "0644",
            "path": path,
            "role": "migration",
            "sha256": digest,
        })
    manifest["entries"].sort(key=lambda item: item["path"].encode("utf-8"))
    manifest["migrations"] = [
        {"order": index, "path": path, "sha256": digest}
        for index, path in enumerate(paths, start=1)
    ]
    manifest["dependencies"] = [
        {"path": path, "requires": [] if index == count - 1 else [paths[index + 1]]}
        for index, path in enumerate(paths)
    ]
    return paths


class ManifestValidationTests(unittest.TestCase):
    def test_accepts_golden_canonical_manifest_and_inventory(self):
        manifest_raw = bundle.canonical_json_bytes(valid_manifest())
        self.assertEqual(len(manifest_raw), 3012)
        self.assertEqual(
            hashlib.sha256(manifest_raw).hexdigest(),
            "26910a8c6952da583b56fe7145f9067b005a3b51be3c6afb31a5740a50eb5f86",
        )
        self.assertTrue(manifest_raw.endswith(b"\n"))
        raw = bundle_bytes()
        result = validator.validate_bundle(raw)

        self.assertEqual(result.manifest, valid_manifest())
        self.assertEqual(result.archive_sha256, hashlib.sha256(raw).hexdigest())
        self.assertEqual(result.archive_paths, tuple(sorted(["manifest.json", *MEMBERS])))

    def test_payload_byte_tamper_has_stable_code_before_extraction(self):
        raw = bundle_bytes()
        payload = next(
            member for member in bundle.validate_ustar(raw)
            if member.path == "data/001-public.memory.jsonl"
        )
        mutated = bytearray(raw)
        mutated[payload.data_offset] ^= 1

        with self.assertRaises(validator.BundleValidationError) as caught:
            validator.validate_bundle(bytes(mutated))
        self.assertEqual(caught.exception.code, "MEMBER_SHA256_MISMATCH")

    def test_declared_json_member_must_be_canonical(self):
        manifest = valid_manifest()
        members = dict(MEMBERS)
        replace_member(manifest, members, "state/sequences.json", b'{ "sequences":[]}\n')

        self.assert_code("MEMBER_JSON_INVALID", bundle_bytes(manifest, members))

    def test_declared_json_member_content_limit_accepts_boundary_and_cannot_be_broadened(self):
        limit = validator.MAX_CANONICAL_JSON_MEMBER_SIZE
        self.assertEqual(limit, 1 << 20)
        accepted = b'"' + (b"x" * (limit - 3)) + b'"\n'
        manifest = valid_manifest()
        members = dict(MEMBERS)
        replace_member(manifest, members, "reports/source-snapshot.json", accepted)
        accepted_raw = bundle_bytes(manifest, members)
        validator.validate_bundle(accepted_raw)
        self.assert_code("MEMBER_JSON_LIMIT", accepted_raw, max_json_member_size=limit - 1)

        rejected = b'"' + (b"x" * (limit - 2)) + b'"\n'
        replace_member(manifest, members, "reports/source-snapshot.json", rejected)
        raw = bundle_bytes(manifest, members)
        self.assert_code("MEMBER_JSON_LIMIT", raw)
        self.assert_code("MEMBER_JSON_LIMIT", raw, max_json_member_size=limit + 1)

    def test_relation_jsonl_row_count_must_match_actual_lines(self):
        manifest = valid_manifest()
        members = dict(MEMBERS)
        manifest["relations"][0]["row_count"] = 2

        self.assert_code("RELATION_JSONL_INVALID", bundle_bytes(manifest, members))

    def test_relation_jsonl_row_limit_accepts_boundary_and_cannot_be_broadened(self):
        limit = validator.MAX_CANONICAL_JSONL_ROW_SIZE
        self.assertEqual(limit, 1 << 20)
        prefix = b'{"pk":["1"],"row":{"id":"1","payload":"'
        suffix = b'"}}\n'
        relation = valid_manifest()["relations"][0]
        relation["columns"].append({"name": "payload", "ordinal": 2, "pg_type": "text"})

        accepted = prefix + (b"x" * (limit - len(prefix) - len(suffix))) + suffix
        manifest = valid_manifest()
        manifest["relations"][0] = relation
        members = dict(MEMBERS)
        replace_member(manifest, members, relation["path"], accepted)
        accepted_raw = bundle_bytes(manifest, members)
        validator.validate_bundle(accepted_raw)
        self.assert_code("RELATION_JSONL_LIMIT", accepted_raw, max_jsonl_row_size=limit - 1)

        rejected = prefix + (b"x" * (limit + 1 - len(prefix) - len(suffix))) + suffix
        replace_member(manifest, members, relation["path"], rejected)
        raw = bundle_bytes(manifest, members)
        self.assert_code("RELATION_JSONL_LIMIT", raw)
        self.assert_code("RELATION_JSONL_LIMIT", raw, max_jsonl_row_size=limit + 1)

    def test_content_limit_arguments_require_nonnegative_integers(self):
        raw = bundle_bytes()
        for name in ("max_json_member_size", "max_jsonl_row_size"):
            for value in (-1, True, 1.5):
                with self.subTest(name=name, value=value):
                    self.assert_code("ARCHIVE_INVALID", raw, **{name: value})

    def test_content_limits_preserve_checksum_tamper_precedence(self):
        manifest = valid_manifest()
        members = dict(MEMBERS)
        json_path = "reports/source-snapshot.json"
        json_payload = b'"' + (b"x" * validator.MAX_CANONICAL_JSON_MEMBER_SIZE) + b'"\n'
        replace_member(manifest, members, json_path, json_payload)
        members[json_path] = b"!" + members[json_path][1:]
        self.assert_code("MEMBER_SHA256_MISMATCH", bundle_bytes(manifest, members))

        manifest = valid_manifest()
        members = dict(MEMBERS)
        replace_member(manifest, members, json_path, json_payload)
        json_entry = next(entry for entry in manifest["entries"] if entry["path"] == json_path)
        json_entry["bytes"] -= 1
        self.assert_code("ENTRY_BYTES", bundle_bytes(manifest, members))

        manifest = valid_manifest()
        members = dict(MEMBERS)
        relation = manifest["relations"][0]
        relation["columns"].append({"name": "payload", "ordinal": 2, "pg_type": "text"})
        relation_path = relation["path"]
        row_payload = (
            b'{"pk":["1"],"row":{"id":"1","payload":"'
            + (b"x" * validator.MAX_CANONICAL_JSONL_ROW_SIZE)
            + b'"}}\n'
        )
        replace_member(manifest, members, relation_path, row_payload)
        members[relation_path] = b"!" + members[relation_path][1:]
        self.assert_code("MEMBER_SHA256_MISMATCH", bundle_bytes(manifest, members))

        manifest = valid_manifest()
        members = dict(MEMBERS)
        relation = manifest["relations"][0]
        relation["columns"].append({"name": "payload", "ordinal": 2, "pg_type": "text"})
        replace_member(manifest, members, relation_path, row_payload)
        relation["bytes"] -= 1
        relation_entry = next(entry for entry in manifest["entries"] if entry["path"] == relation_path)
        relation_entry["bytes"] -= 1
        self.assert_code("ENTRY_BYTES", bundle_bytes(manifest, members))

    def test_relation_jsonl_rejects_noncanonical_framing_envelope_columns_and_pk(self):
        cases = (
            (b"", 1),
            (b'\n', 1),
            (b'{ "pk":["1"],"row":{"id":"1"}}\n', 1),
            (b'{"pk":["1"],"row":{"id":"1"}}', 1),
            (b'{"pk":["1"]}\n', 1),
            (b'{"pk":["1"],"row":{"extra":"1","id":"1"}}\n', 1),
            (b'{"pk":["2"],"row":{"id":"1"}}\n', 1),
            (b'{"pk":["1"],"row":{"id":"1"}}\n', 0),
        )
        for payload, row_count in cases:
            manifest = valid_manifest()
            members = dict(MEMBERS)
            replace_member(manifest, members, "data/001-public.memory.jsonl", payload)
            manifest["relations"][0]["row_count"] = row_count
            with self.subTest(payload=payload, row_count=row_count):
                self.assert_code("RELATION_JSONL_INVALID", bundle_bytes(manifest, members))

    def test_relation_jsonl_framing_checks_have_distinct_stable_messages(self):
        cases = (
            (b'{"pk":["1"],"row":{"id":"1"}}', 1, "relation JSONL row lacks an LF terminator"),
            (
                b'{"pk":["1"],"row":{"id":"1"}}\n',
                0,
                "relation JSONL byte/count invariant is invalid",
            ),
        )
        for payload, row_count, message in cases:
            manifest = valid_manifest()
            members = dict(MEMBERS)
            replace_member(manifest, members, "data/001-public.memory.jsonl", payload)
            manifest["relations"][0]["row_count"] = row_count
            with self.subTest(message=message), self.assertRaises(validator.BundleValidationError) as caught:
                validator.validate_bundle(bundle_bytes(manifest, members))
            self.assertEqual(caught.exception.code, "RELATION_JSONL_INVALID")
            self.assertEqual(str(caught.exception), message)

    def test_relation_jsonl_composite_pk_uses_declared_semantic_order(self):
        manifest = valid_manifest()
        members = dict(MEMBERS)
        relation = manifest["relations"][0]
        relation["columns"] = [
            {"name": "z_id", "ordinal": 1, "pg_type": "bigint"},
            {"name": "a_id", "ordinal": 2, "pg_type": "bigint"},
        ]
        relation["primary_key"] = ["z_id", "a_id"]
        payload = b'{"pk":["2","1"],"row":{"a_id":"1","z_id":"2"}}\n'
        replace_member(manifest, members, relation["path"], payload)

        validator.validate_bundle(bundle_bytes(manifest, members))

        bad_payload = b'{"pk":["1","2"],"row":{"a_id":"1","z_id":"2"}}\n'
        replace_member(manifest, members, relation["path"], bad_payload)
        self.assert_code("RELATION_JSONL_INVALID", bundle_bytes(manifest, members))

    def test_relation_jsonl_requires_strict_semantic_composite_pk_order(self):
        manifest = valid_manifest()
        relation = manifest["relations"][0]
        relation["columns"] = [
            {"name": "major", "ordinal": 1, "pg_type": "numeric"},
            {"name": "minor", "ordinal": 2, "pg_type": "text"},
            {"name": "stamp", "ordinal": 3, "pg_type": "timestamptz"},
        ]
        relation["primary_key"] = ["major", "minor", "stamp"]
        rows = [
            {"pk": ["-2.5", "astral 😀", "2025-01-01T00:00:00.000000Z"], "row": {
                "major": "-2.5", "minor": "astral 😀", "stamp": "2025-01-01T00:00:00.000000Z",
            }},
            {"pk": ["2", "a", "2024-12-31T23:59:59.999999Z"], "row": {
                "major": "2", "minor": "a", "stamp": "2024-12-31T23:59:59.999999Z",
            }},
            {"pk": ["10", "a", "2025-01-01T00:00:00.000000Z"], "row": {
                "major": "10", "minor": "a", "stamp": "2025-01-01T00:00:00.000000Z",
            }},
        ]
        members = dict(MEMBERS)
        payload = bundle.canonical_jsonl_bytes(rows)
        replace_member(manifest, members, relation["path"], payload)
        relation["row_count"] = len(rows)
        validator.validate_bundle(bundle_bytes(manifest, members))

        for hostile_rows in (list(reversed(rows)), [rows[0], rows[0]]):
            hostile_manifest = valid_manifest()
            hostile_relation = hostile_manifest["relations"][0]
            hostile_relation["columns"] = relation["columns"]
            hostile_relation["primary_key"] = relation["primary_key"]
            hostile_members = dict(MEMBERS)
            hostile_payload = bundle.canonical_jsonl_bytes(hostile_rows)
            replace_member(hostile_manifest, hostile_members, hostile_relation["path"], hostile_payload)
            hostile_relation["row_count"] = len(hostile_rows)
            with self.subTest(keys=[row["pk"] for row in hostile_rows]):
                self.assert_code(
                    "RELATION_PK_ORDER",
                    bundle_bytes(hostile_manifest, hostile_members),
                )

    def test_relation_jsonl_validates_every_declared_postgresql_encoding(self):
        valid_cases = (
            ("text", "snowman ☃"),
            ("varchar", "varchar"),
            ("character varying", ""),
            ("char", "fixed "),
            ("character", "fixed "),
            ("bpchar", "fixed "),
            ("uuid", "12345678-1234-5678-9234-567812345678"),
            ("timestamptz", "2025-01-02T01:04:05.006000Z"),
            ("timestamp with time zone", "2025-01-02T01:04:05.006000Z"),
            ("timestamp", "2025-01-02T03:04:05.006000"),
            ("timestamp without time zone", "2025-01-02T03:04:05.006000"),
            ("date", "2025-01-02"),
            ("time", "03:04:05.006000"),
            ("time without time zone", "03:04:05.006000"),
            ("smallint", "-32768"),
            ("int2", "32767"),
            ("integer", "2147483647"),
            ("int4", "-2147483648"),
            ("bigint", "-9223372036854775808"),
            ("int8", "9223372036854775807"),
            ("numeric", "-12345678901234567890.0000001"),
            ("decimal", "0"),
            ("boolean", False),
            ("bool", True),
            ("text[]", ["a", None, "☃"]),
            ("bytea", {"$bytea": "AP8="}),
            ("json", {"nested": [None, True, {"$bytea": "ordinary JSON"}]}),
            ("jsonb", ["an", {"unwrapped": "canonical value"}]),
        )
        for pg_type, value in valid_cases:
            manifest = valid_manifest()
            relation = manifest["relations"][0]
            relation["columns"].append({"name": "value", "ordinal": 2, "pg_type": pg_type})
            members = dict(MEMBERS)
            payload = bundle.canonical_jsonl_bytes([
                {"pk": ["1"], "row": {"id": "1", "value": value}},
            ])
            replace_member(manifest, members, relation["path"], payload)
            with self.subTest(pg_type=pg_type, value=value):
                validator.validate_bundle(bundle_bytes(manifest, members))

        manifest = valid_manifest()
        relation = manifest["relations"][0]
        relation["columns"].append({"name": "nullable", "ordinal": 2, "pg_type": "uuid"})
        members = dict(MEMBERS)
        replace_member(
            manifest,
            members,
            relation["path"],
            b'{"pk":["1"],"row":{"id":"1","nullable":null}}\n',
        )
        validator.validate_bundle(bundle_bytes(manifest, members))

    def test_relation_jsonl_rejects_malformed_or_unsupported_postgresql_encodings(self):
        invalid_cases = (
            ("text", 1),
            ("varchar", False),
            ("bpchar", ["x"]),
            ("uuid", "12345678-1234-5678-9234-56781234567A"),
            ("timestamptz", "2025-01-02T01:04:05Z"),
            ("timestamp", "2025-01-02T01:04:05.000000Z"),
            ("date", "2025-1-2"),
            ("time", "03:04:05"),
            ("smallint", "32768"),
            ("integer", "01"),
            ("bigint", "9223372036854775808"),
            ("numeric", "1.2300"),
            ("numeric", "-0"),
            ("boolean", 1),
            ("bool", "false"),
            ("text[]", ["ok", 1]),
            ("bytea", {"$bytea": "not base64"}),
            ("bytea", {"$bytea": "AP8=", "extra": True}),
        )
        for pg_type, value in invalid_cases:
            manifest = valid_manifest()
            relation = manifest["relations"][0]
            relation["columns"].append({"name": "value", "ordinal": 2, "pg_type": pg_type})
            members = dict(MEMBERS)
            payload = bundle.canonical_jsonl_bytes([
                {"pk": ["1"], "row": {"id": "1", "value": value}},
            ])
            replace_member(manifest, members, relation["path"], payload)
            with self.subTest(pg_type=pg_type, value=value):
                self.assert_code("RELATION_VALUE_INVALID", bundle_bytes(manifest, members))

        for unsupported_type in ("inet", "public.not_an_enum", "public.custom_domain"):
            unsupported = valid_manifest()
            unsupported["relations"][0]["columns"][0]["pg_type"] = unsupported_type
            with self.subTest(unsupported_type=unsupported_type):
                self.assert_code("RELATION_VALUE_INVALID", bundle_bytes(unsupported))

        for value in ("1" * 131_073, "0." + "1" * 16_384):
            manifest = valid_manifest()
            relation = manifest["relations"][0]
            relation["columns"].append({"name": "value", "ordinal": 2, "pg_type": "numeric"})
            members = dict(MEMBERS)
            replace_member(
                manifest,
                members,
                relation["path"],
                bundle.canonical_jsonl_bytes([
                    {"pk": ["1"], "row": {"id": "1", "value": value}},
                ]),
            )
            with self.subTest(numeric_length=len(value)):
                self.assert_code("RELATION_VALUE_INVALID", bundle_bytes(manifest, members))

        null_pk = valid_manifest()
        members = dict(MEMBERS)
        replace_member(
            null_pk,
            members,
            null_pk["relations"][0]["path"],
            b'{"pk":[null],"row":{"id":null}}\n',
        )
        self.assert_code("RELATION_VALUE_INVALID", bundle_bytes(null_pk, members))

    def test_relation_value_validation_precedes_pk_equality_and_order(self):
        manifest = valid_manifest()
        members = dict(MEMBERS)
        replace_member(
            manifest,
            members,
            manifest["relations"][0]["path"],
            b'{"pk":["not-an-integer"],"row":{"id":"not-an-integer"}}\n',
        )
        self.assert_code("RELATION_VALUE_INVALID", bundle_bytes(manifest, members))

    def test_enum_declaration_order_cannot_be_inferred_offline(self):
        manifest = valid_manifest()
        relation = manifest["relations"][0]
        relation["columns"][0]["pg_type"] = "public.mood"
        members = dict(MEMBERS)
        rows = [
            {"pk": ["z"], "row": {"id": "z"}},
            {"pk": ["a"], "row": {"id": "a"}},
        ]
        replace_member(manifest, members, relation["path"], bundle.canonical_jsonl_bytes(rows))
        relation["row_count"] = 2

        self.assert_code("RELATION_VALUE_INVALID", bundle_bytes(manifest, members))

    def test_bpchar_pk_ignores_trailing_ascii_spaces(self):
        manifest = valid_manifest()
        relation = manifest["relations"][0]
        relation["columns"][0]["pg_type"] = "bpchar"
        members = dict(MEMBERS)
        rows = [
            {"pk": ["a"], "row": {"id": "a"}},
            {"pk": ["a "], "row": {"id": "a "}},
        ]
        replace_member(manifest, members, relation["path"], bundle.canonical_jsonl_bytes(rows))
        relation["row_count"] = 2

        self.assert_code("RELATION_PK_ORDER", bundle_bytes(manifest, members))

    def test_supported_pk_types_use_postgresql_c_semantic_order(self):
        cases = (
            ("text", ["a", "é"]),
            ("varchar", ["2", "a"]),
            ("uuid", [
                "00000000-0000-0000-0000-000000000002",
                "00000000-0000-0000-0000-000000000010",
            ]),
            ("timestamptz", [
                "2024-12-31T23:59:59.999999Z",
                "2025-01-01T00:00:00.000000Z",
            ]),
            ("timestamp", [
                "2024-12-31T23:59:59.999999",
                "2025-01-01T00:00:00.000000",
            ]),
            ("date", ["2024-12-31", "2025-01-01"]),
            ("time", ["00:00:00.000001", "23:59:59.999999"]),
            ("bigint", ["2", "10"]),
            ("numeric", ["2", "10"]),
            ("boolean", [False, True]),
            ("bytea", [{"$bytea": "AA8="}, {"$bytea": "AQA="}]),
        )
        for pg_type, values in cases:
            manifest = valid_manifest()
            relation = manifest["relations"][0]
            relation["columns"][0]["pg_type"] = pg_type
            relation["row_count"] = len(values)
            members = dict(MEMBERS)
            rows = [
                {"pk": [value], "row": {"id": value}}
                for value in values
            ]
            replace_member(
                manifest,
                members,
                relation["path"],
                bundle.canonical_jsonl_bytes(rows),
            )
            with self.subTest(pg_type=pg_type):
                validator.validate_bundle(bundle_bytes(manifest, members))

    def test_pk_types_without_proven_pg_comparator_fail_closed(self):
        cases = (
            ("json", [{"a": 1}, [None]]),
            ("jsonb", [None, "a"]),
            ("text[]", [["a", None], ["a", "z"]]),
        )
        for pg_type, values in cases:
            manifest = valid_manifest()
            relation = manifest["relations"][0]
            relation["columns"][0]["pg_type"] = pg_type
            relation["row_count"] = len(values)
            members = dict(MEMBERS)
            rows = [
                {"pk": [value], "row": {"id": value}}
                for value in values
            ]
            replace_member(
                manifest,
                members,
                relation["path"],
                bundle.canonical_jsonl_bytes(rows),
            )
            with self.subTest(pg_type=pg_type, values=values):
                self.assert_code("RELATION_PK_TYPE_UNSUPPORTED", bundle_bytes(manifest, members))

    def assert_code(self, expected, raw, **kwargs):
        with self.assertRaises(validator.BundleValidationError) as caught:
            validator.validate_bundle(raw, **kwargs)
        self.assertEqual(caught.exception.code, expected)

    def test_manifest_is_a_nonrecursive_canonical_json_root(self):
        manifest = valid_manifest()
        manifest["entries"].append({
            "bytes": 1,
            "media_type": "application/json",
            "mode": "0644",
            "path": "manifest.json",
            "role": "manifest",
            "sha256": "0" * 64,
        })
        self.assert_code("MANIFEST_RECURSION", bundle_bytes(manifest))

        pretty = json.dumps(valid_manifest(), indent=2, ensure_ascii=False).encode() + b"\n"
        noncanonical = bundle.write_ustar([("manifest.json", pretty), *MEMBERS.items()])
        self.assert_code("MANIFEST_CANONICAL", noncanonical)

        sensitive = bundle.write_ustar([
            ("manifest.json", b'{"private-field":1,"private-field":2}\n'),
            *MEMBERS.items(),
        ])
        with self.assertRaises(validator.BundleValidationError) as caught:
            validator.validate_bundle(sensitive)
        self.assertEqual(caught.exception.code, "MANIFEST_CANONICAL")
        self.assertEqual(str(caught.exception), "manifest.json is not canonical JSON")
        self.assertNotIn("private-field", str(caught.exception))

        limit = validator.MAX_CANONICAL_JSON_MEMBER_SIZE
        boundary_manifest = b'"' + (b"x" * (limit - 3)) + b'"\n'
        boundary = bundle.write_ustar([("manifest.json", boundary_manifest), *MEMBERS.items()])
        self.assert_code("MANIFEST_STRUCTURE", boundary)
        self.assert_code("MANIFEST_JSON_LIMIT", boundary, max_json_member_size=limit - 1)

        oversized_manifest = b'"' + (b"x" * (limit - 2)) + b'"\n'
        oversized = bundle.write_ustar([("manifest.json", oversized_manifest), *MEMBERS.items()])
        self.assert_code("MANIFEST_JSON_LIMIT", oversized)
        self.assert_code("MANIFEST_JSON_LIMIT", oversized, max_json_member_size=limit + 1)

    def test_archive_inventory_is_exact_sorted_and_unique(self):
        missing = valid_manifest()
        missing["entries"].pop(0)
        self.assert_code("MANIFEST_INVENTORY", bundle_bytes(missing))

        unsorted = valid_manifest()
        unsorted["entries"].reverse()
        self.assert_code("MANIFEST_INVENTORY", bundle_bytes(unsorted))

        extra_members = dict(MEMBERS)
        extra_members["unexpected.txt"] = b"surprise"
        self.assert_code("MANIFEST_INVENTORY", bundle_bytes(members=extra_members))

    def test_entry_metadata_bytes_and_hash_are_exact(self):
        cases = (
            ("ENTRY_METADATA", "mode", "0600"),
            ("ENTRY_BYTES", "bytes", 29),
            ("MEMBER_SHA256_MISMATCH", "sha256", "0" * 64),
        )
        for code, field, value in cases:
            manifest = valid_manifest()
            entry_index = 0 if field == "mode" else -1
            manifest["entries"][entry_index][field] = value
            with self.subTest(field=field):
                self.assert_code(code, bundle_bytes(manifest))

    def test_all_entry_roles_and_media_types_are_structurally_declared(self):
        manifest = valid_manifest()
        content = b"orphan"
        manifest["entries"].insert(3, {
            "bytes": len(content),
            "media_type": "text/plain",
            "mode": "0644",
            "path": "orphan.txt",
            "role": "other",
            "sha256": hashlib.sha256(content).hexdigest(),
        })
        members = dict(MEMBERS)
        members["orphan.txt"] = content
        self.assert_code("MANIFEST_DEPENDENCY", bundle_bytes(manifest, members))

    def test_dependency_and_compatibility_closure_fail_closed(self):
        dangling = valid_manifest()
        dangling["dependencies"][0]["requires"] = ["absent.sql"]
        self.assert_code("MANIFEST_DEPENDENCY", bundle_bytes(dangling))

        cycle = valid_manifest()
        cycle["dependencies"] = [
            {"path": "data/001-public.memory.jsonl", "requires": ["migrations/01_core.sql"]},
            {"path": "migrations/01_core.sql", "requires": ["data/001-public.memory.jsonl"]},
        ]
        self.assert_code("MANIFEST_DEPENDENCY", bundle_bytes(cycle))

        unsupported = valid_manifest()
        unsupported["compatibility"]["postgresql"]["maximum_exclusive_major"] = 18
        self.assert_code("MANIFEST_COMPATIBILITY", bundle_bytes(unsupported))

    def test_dependency_chain_beyond_python_recursion_limit_is_accepted(self):
        manifest = valid_manifest()
        members = dict(MEMBERS)
        paths = add_migration_chain(manifest, members, 1400)

        result = validator.validate_bundle(bundle_bytes(manifest, members))

        self.assertEqual(len(result.manifest["dependencies"]), 1400)
        self.assertEqual(result.manifest["dependencies"][-1]["path"], paths[-1])

    def test_dependency_cycle_beyond_python_recursion_limit_has_stable_code(self):
        manifest = valid_manifest()
        members = dict(MEMBERS)
        paths = add_migration_chain(manifest, members, 1400)
        manifest["dependencies"][-1]["requires"] = [paths[0]]

        self.assert_code("MANIFEST_DEPENDENCY", bundle_bytes(manifest, members))

    def test_relation_and_evidence_structural_closure_fail_closed(self):
        bad_primary_key = valid_manifest()
        bad_primary_key["relations"][0]["primary_key"] = ["absent"]
        self.assert_code("MANIFEST_DEPENDENCY", bundle_bytes(bad_primary_key))

        bad_span = valid_manifest()
        bad_span["evidence"][0]["locators"][0]["byte_end"] = 20
        self.assert_code("MANIFEST_DEPENDENCY", bundle_bytes(bad_span))

        bad_migration_order = valid_manifest()
        bad_migration_order["migrations"][0]["order"] = 2
        self.assert_code("MANIFEST_DEPENDENCY", bundle_bytes(bad_migration_order))

        duplicate_relation = valid_manifest()
        second_relation = dict(duplicate_relation["relations"][0])
        second_relation["relation"] = "memory_copy"
        second_relation["restore_order"] = 2
        duplicate_relation["relations"].append(second_relation)
        self.assert_code("MANIFEST_DEPENDENCY", bundle_bytes(duplicate_relation))

    def test_relation_restore_order_rejects_child_before_nondeferrable_parent(self):
        manifest = valid_manifest()
        members = dict(MEMBERS)
        manifest["relations"][0]["restore_order"] = 2
        add_relation(
            manifest,
            members,
            name="child",
            order=1,
            columns=["id", "memory_id"],
            primary_key=["id"],
            dependencies=["public.memory"],
            foreign_keys=[{
                "columns": ["memory_id"],
                "deferrable": False,
                "referenced_columns": ["id"],
                "referenced_relation": "memory",
                "referenced_schema": "public",
            }],
        )

        self.assert_code("MANIFEST_DEPENDENCY", bundle_bytes(manifest, members))

    def test_relation_restore_order_accepts_backward_acyclic_deferrable_edge(self):
        manifest = valid_manifest()
        members = dict(MEMBERS)
        manifest["relations"][0]["restore_order"] = 2
        add_relation(
            manifest,
            members,
            name="child",
            order=1,
            columns=["id", "memory_id"],
            primary_key=["id"],
            dependencies=["public.memory"],
            foreign_keys=[{
                "columns": ["memory_id"],
                "deferrable": True,
                "referenced_columns": ["id"],
                "referenced_relation": "memory",
                "referenced_schema": "public",
            }],
        )

        result = validator.validate_bundle(bundle_bytes(manifest, members))
        self.assertEqual(
            [relation["restore_order"] for relation in result.manifest["relations"]],
            [1, 2],
        )

    def test_relation_restore_order_accepts_deferrable_self_reference(self):
        manifest = valid_manifest()
        members = dict(MEMBERS)
        relation = manifest["relations"][0]
        relation["columns"].append({"name": "parent_id", "ordinal": 2, "pg_type": "bigint"})
        relation["dependencies"] = ["public.memory"]
        relation["foreign_keys"] = [{
            "columns": ["parent_id"],
            "deferrable": True,
            "referenced_columns": ["id"],
            "referenced_relation": "memory",
            "referenced_schema": "public",
        }]
        replace_member(
            manifest,
            members,
            relation["path"],
            b'{"pk":["1"],"row":{"id":"1","parent_id":null}}\n',
        )

        result = validator.validate_bundle(bundle_bytes(manifest, members))

        self.assertEqual(result.manifest["relations"][0]["dependencies"], ["public.memory"])

    def test_relation_restore_order_rejects_nondeferrable_self_reference_as_cycle(self):
        manifest = valid_manifest()
        relation = manifest["relations"][0]
        relation["columns"].append({"name": "parent_id", "ordinal": 2, "pg_type": "bigint"})
        relation["dependencies"] = ["public.memory"]
        relation["foreign_keys"] = [{
            "columns": ["parent_id"],
            "deferrable": False,
            "referenced_columns": ["id"],
            "referenced_relation": "memory",
            "referenced_schema": "public",
        }]

        with self.assertRaises(validator.BundleValidationError) as caught:
            validator.validate_bundle(bundle_bytes(manifest))

        self.assertEqual(caught.exception.code, "MANIFEST_DEPENDENCY")
        self.assertIn("cycle", str(caught.exception))

    def test_relation_dependencies_reject_spurious_self_reference_without_self_fk(self):
        manifest = valid_manifest()
        manifest["relations"][0]["dependencies"] = ["public.memory"]

        self.assert_code("MANIFEST_DEPENDENCY", bundle_bytes(manifest))

    def test_relation_restore_order_accepts_all_deferrable_cycle(self):
        manifest = valid_manifest()
        members = dict(MEMBERS)
        parent = manifest["relations"][0]
        parent["columns"].append({"name": "child_id", "ordinal": 2, "pg_type": "bigint"})
        parent["dependencies"] = ["public.child"]
        parent["foreign_keys"] = [{
            "columns": ["child_id"],
            "deferrable": True,
            "referenced_columns": ["id"],
            "referenced_relation": "child",
            "referenced_schema": "public",
        }]
        replace_member(
            manifest,
            members,
            parent["path"],
            b'{"pk":["1"],"row":{"child_id":null,"id":"1"}}\n',
        )
        add_relation(
            manifest,
            members,
            name="child",
            order=2,
            columns=["id", "memory_id"],
            primary_key=["id"],
            dependencies=["public.memory"],
            foreign_keys=[{
                "columns": ["memory_id"],
                "deferrable": True,
                "referenced_columns": ["id"],
                "referenced_relation": "memory",
                "referenced_schema": "public",
            }],
        )

        result = validator.validate_bundle(bundle_bytes(manifest, members))
        self.assertEqual(len(result.manifest["relations"]), 2)

    def test_relation_restore_order_rejects_mixed_deferrability_cycle(self):
        manifest = valid_manifest()
        members = dict(MEMBERS)
        parent = manifest["relations"][0]
        parent["columns"].append({"name": "child_id", "ordinal": 2, "pg_type": "bigint"})
        parent["dependencies"] = ["public.child"]
        parent["foreign_keys"] = [{
            "columns": ["child_id"],
            "deferrable": True,
            "referenced_columns": ["id"],
            "referenced_relation": "child",
            "referenced_schema": "public",
        }]
        add_relation(
            manifest,
            members,
            name="child",
            order=2,
            columns=["id", "memory_id"],
            primary_key=["id"],
            dependencies=["public.memory"],
            foreign_keys=[{
                "columns": ["memory_id"],
                "deferrable": False,
                "referenced_columns": ["id"],
                "referenced_relation": "memory",
                "referenced_schema": "public",
            }],
        )

        self.assert_code("MANIFEST_DEPENDENCY", bundle_bytes(manifest, members))

    def test_relation_restore_order_rejects_nondeferrable_cycle(self):
        manifest = valid_manifest()
        members = dict(MEMBERS)
        parent = manifest["relations"][0]
        parent["columns"].append({"name": "child_id", "ordinal": 2, "pg_type": "bigint"})
        parent["dependencies"] = ["public.child"]
        parent["foreign_keys"] = [{
            "columns": ["child_id"],
            "deferrable": False,
            "referenced_columns": ["id"],
            "referenced_relation": "child",
            "referenced_schema": "public",
        }]
        add_relation(
            manifest,
            members,
            name="child",
            order=2,
            columns=["id", "memory_id"],
            primary_key=["id"],
            dependencies=["public.memory"],
            foreign_keys=[{
                "columns": ["memory_id"],
                "deferrable": False,
                "referenced_columns": ["id"],
                "referenced_relation": "memory",
                "referenced_schema": "public",
            }],
        )

        self.assert_code("MANIFEST_DEPENDENCY", bundle_bytes(manifest, members))

    def test_composite_key_column_order_is_semantic_not_bytewise(self):
        manifest = valid_manifest()
        members = dict(MEMBERS)
        parent = manifest["relations"][0]
        parent["columns"] = [
            {"name": "z_id", "ordinal": 1, "pg_type": "bigint"},
            {"name": "a_id", "ordinal": 2, "pg_type": "bigint"},
        ]
        parent["primary_key"] = ["z_id", "a_id"]
        replace_member(
            manifest,
            members,
            parent["path"],
            b'{"pk":["2","1"],"row":{"a_id":"1","z_id":"2"}}\n',
        )
        add_relation(
            manifest,
            members,
            name="child",
            order=2,
            columns=["id", "z_parent", "a_parent"],
            primary_key=["z_parent", "a_parent"],
            dependencies=["public.memory"],
            foreign_keys=[{
                "columns": ["z_parent", "a_parent"],
                "deferrable": False,
                "referenced_columns": ["z_id", "a_id"],
                "referenced_relation": "memory",
                "referenced_schema": "public",
            }],
        )

        result = validator.validate_bundle(bundle_bytes(manifest, members))
        child = result.manifest["relations"][1]
        self.assertEqual(child["primary_key"], ["z_parent", "a_parent"])
        self.assertEqual(child["foreign_keys"][0]["columns"], ["z_parent", "a_parent"])
        self.assertEqual(child["foreign_keys"][0]["referenced_columns"], ["z_id", "a_id"])

    def test_manifest_entry_and_external_archive_checksum_tamper_have_stable_codes(self):
        manifest = valid_manifest()
        manifest["entries"][0]["sha256"] = "f" * 64
        self.assert_code("MANIFEST_DECLARATION_MISMATCH", bundle_bytes(manifest))

        raw = bundle_bytes()
        self.assert_code("ARCHIVE_SHA256_MISMATCH", raw, expected_archive_sha256="0" * 64)

    def test_release_schema_is_the_production_shape_contract(self):
        schema = json.loads(validator._MANIFEST_SCHEMA_PATH.read_text(encoding="utf-8"))
        relation_required = set(schema["$defs"]["relation"]["required"])
        self.assertEqual(
            relation_required,
            {
                "bytes", "columns", "dependencies", "foreign_keys", "path", "primary_key",
                "relation", "restore_order", "row_count", "row_digest_algorithm", "schema", "sha256",
            },
        )

        schema["required"].append("schema_probe")
        with tempfile.TemporaryDirectory() as directory:
            schema_path = Path(directory) / "manifest.schema.json"
            schema_path.write_text(json.dumps(schema), encoding="utf-8")
            with mock.patch.object(validator, "_MANIFEST_SCHEMA_PATH", schema_path):
                self.assert_code("MANIFEST_STRUCTURE", bundle_bytes())

    def test_release_schema_io_and_parse_errors_are_stable_and_redacted(self):
        private_path = Path("/private/host/schema.json")
        for failure in (
            FileNotFoundError(f"missing: {private_path}"),
            PermissionError(f"denied: {private_path}"),
            UnicodeDecodeError("utf-8", b"x", 0, 1, f"private: {private_path}"),
            json.JSONDecodeError(f"private: {private_path}", "x", 0),
        ):
            with self.subTest(failure=type(failure).__name__), mock.patch.object(
                Path, "open", side_effect=failure
            ):
                with self.assertRaises(validator.BundleValidationError) as caught:
                    validator._validate_release_schema(valid_manifest())
                self.assertEqual(caught.exception.code, "MANIFEST_SCHEMA")
                self.assertEqual(str(caught.exception), "release manifest schema is unavailable or invalid")
                self.assertNotIn(str(private_path), str(caught.exception))

        with mock.patch.object(validator.json, "load", side_effect=RecursionError("parser depth")):
            with self.assertRaises(validator.BundleValidationError) as caught:
                validator._validate_release_schema(valid_manifest())
        self.assertEqual(caught.exception.code, "MANIFEST_SCHEMA")
        self.assertEqual(str(caught.exception), "release manifest schema is unavailable or invalid")

        schema_failures = (
            (None, None),
            ({"$ref": "private-sensitive-reference"}, "private-sensitive-label"),
            ({"$defs": {}, "$ref": "#/$defs/private-sensitive-reference"}, "private-sensitive-label"),
        )
        for schema, label in schema_failures:
            with self.subTest(schema=schema):
                with self.assertRaises(validator.BundleValidationError) as caught:
                    if schema is None:
                        with mock.patch.object(validator.json, "load", return_value=[]):
                            validator._validate_release_schema(valid_manifest())
                    else:
                        assert label is not None
                        validator._validate_schema_node({}, schema, schema, label)
                self.assertEqual(caught.exception.code, "MANIFEST_SCHEMA")
                self.assertEqual(
                    str(caught.exception),
                    "release manifest schema is unavailable or invalid",
                )
                self.assertNotIn("private-sensitive", str(caught.exception))

    def test_deep_manifest_and_json_member_have_stable_codes(self):
        deep = (b"[" * 2000) + b"0" + (b"]" * 2000) + b"\n"
        raw = bundle.write_ustar([("manifest.json", deep), *MEMBERS.items()])
        self.assert_code("MANIFEST_CANONICAL", raw)

        manifest = valid_manifest()
        members = dict(MEMBERS)
        replace_member(manifest, members, "state/sequences.json", deep)
        self.assert_code("MEMBER_JSON_INVALID", bundle_bytes(manifest, members))

    def test_content_limits_bound_large_valid_json_and_single_jsonl_row_memory(self):
        cases = []

        manifest = valid_manifest()
        members = dict(MEMBERS)
        json_payload = b'"' + (b"x" * (8 * 1024 * 1024)) + b'"\n'
        replace_member(manifest, members, "reports/source-snapshot.json", json_payload)
        cases.append(("MEMBER_JSON_LIMIT", bundle_bytes(manifest, members)))

        manifest = valid_manifest()
        members = dict(MEMBERS)
        relation = manifest["relations"][0]
        relation["columns"].append({"name": "payload", "ordinal": 2, "pg_type": "text"})
        row_payload = (
            b'{"pk":["1"],"row":{"id":"1","payload":"'
            + (b"x" * (8 * 1024 * 1024))
            + b'"}}\n'
        )
        replace_member(manifest, members, relation["path"], row_payload)
        cases.append(("RELATION_JSONL_LIMIT", bundle_bytes(manifest, members)))

        for code, raw in cases:
            tracemalloc.start()
            try:
                with self.subTest(code=code):
                    self.assert_code(code, raw)
                _, peak = tracemalloc.get_traced_memory()
            finally:
                tracemalloc.stop()
            self.assertLess(peak, len(raw) // 4)

    def test_validation_is_bounded_and_never_extracts(self):
        members = dict(MEMBERS)
        manifest = valid_manifest()
        replace_member(
            manifest,
            members,
            "migrations/01_core.sql",
            b"x" * (8 * 1024 * 1024),
        )
        raw = bundle_bytes(manifest, members)

        tracemalloc.start()
        try:
            with (
                mock.patch("tarfile.TarFile.extract", side_effect=AssertionError("extracted")),
                mock.patch("tarfile.TarFile.extractall", side_effect=AssertionError("extracted")),
            ):
                validator.validate_bundle(raw)
            _, peak = tracemalloc.get_traced_memory()
        finally:
            tracemalloc.stop()
        self.assertLess(peak, len(raw) // 4)
        self.assert_code("ARCHIVE_INVALID", raw, max_path_bytes=10)

    def test_cli_reads_at_most_archive_limit_plus_one_before_rejecting_oversize(self):
        class ReadProbe(io.BytesIO):
            def __init__(self, raw):
                super().__init__(raw)
                self.read_sizes = []

            def read(self, size=None):
                self.read_sizes.append(size)
                if size is None or size < 0 or size > 1025:
                    raise AssertionError("archive input was read without a strict bound")
                return super().read(size)

        source = ReadProbe(b"x" * 1025)
        source.close = mock.Mock()
        stderr = io.StringIO()
        with (
            mock.patch("builtins.open", return_value=source),
            mock.patch.object(sys, "stderr", stderr),
        ):
            status = validator.main(["oversized.tar", "--max-archive-size", "1024"])

        self.assertEqual(status, 1)
        self.assertEqual(source.read_sizes, [1025])
        source.close.assert_called_once_with()
        self.assertEqual(json.loads(stderr.getvalue())["code"], "ARCHIVE_INVALID")

    def test_cli_unreadable_archive_has_stable_machine_readable_io_error(self):
        class UnreadableProbe(io.BytesIO):
            def read(self, size=None):
                raise PermissionError("sensitive host detail")

        source = UnreadableProbe(b"private")
        source.close = mock.Mock(return_value=None)
        stderr = io.StringIO()
        with (
            mock.patch("builtins.open", return_value=source),
            mock.patch.object(sys, "stderr", stderr),
        ):
            status = validator.main(["private-host-path.tar"])

        self.assertEqual(status, 1)
        self.assertEqual(
            json.loads(stderr.getvalue()),
            {"code": "ARCHIVE_IO", "message": "archive could not be read"},
        )
        source.close.assert_called_once_with()

    def test_cli_memory_exhaustion_has_stable_redacted_machine_error(self):
        source = io.BytesIO(bundle_bytes())
        source.close = mock.Mock(return_value=None)
        stderr = io.StringIO()
        with (
            mock.patch("builtins.open", return_value=source),
            mock.patch.object(validator, "validate_bundle", side_effect=MemoryError("private host detail")),
            mock.patch.object(validator.json, "dumps", side_effect=MemoryError("no allocation headroom")),
            mock.patch.object(sys, "stderr", stderr),
        ):
            status = validator.main(["private-host-path.tar"])

        self.assertEqual(status, 1)
        self.assertEqual(
            json.loads(stderr.getvalue()),
            {"code": "VALIDATION_RESOURCE_LIMIT", "message": "bundle validation exceeded resource limits"},
        )
        self.assertNotIn("private", stderr.getvalue())
        self.assertNotIn("Traceback", stderr.getvalue())
        source.close.assert_called_once_with()

    def test_cli_unexpected_validation_error_has_stable_redacted_machine_error(self):
        source = io.BytesIO(bundle_bytes())
        source.close = mock.Mock(return_value=None)
        stderr = io.StringIO()
        with (
            mock.patch("builtins.open", return_value=source),
            mock.patch.object(validator, "validate_bundle", side_effect=RuntimeError("private host detail")),
            mock.patch.object(validator.json, "dumps", side_effect=MemoryError("no allocation headroom")),
            mock.patch.object(sys, "stderr", stderr),
        ):
            status = validator.main(["private-host-path.tar"])

        self.assertEqual(status, 1)
        self.assertEqual(
            json.loads(stderr.getvalue()),
            {"code": "VALIDATION_INTERNAL", "message": "bundle validation failed unexpectedly"},
        )
        self.assertNotIn("private", stderr.getvalue())
        self.assertNotIn("Traceback", stderr.getvalue())
        source.close.assert_called_once_with()

    def test_direct_cli_missing_archive_has_stable_machine_readable_io_error(self):
        script = Path(validator.__file__)
        with tempfile.TemporaryDirectory() as directory:
            missing_path = Path(directory) / "private-host-path.tar"
            result = subprocess.run(
                [sys.executable, str(script), str(missing_path)],
                check=False, capture_output=True, text=True,
            )

        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")
        self.assertEqual(
            json.loads(result.stderr),
            {"code": "ARCHIVE_IO", "message": "archive could not be read"},
        )
        self.assertNotIn(str(missing_path), result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_direct_cli_has_machine_readable_golden_and_tamper_results(self):
        raw = bundle_bytes()
        member = next(
            item for item in bundle.validate_ustar(raw)
            if item.path == "data/001-public.memory.jsonl"
        )
        tampered = bytearray(raw)
        tampered[member.data_offset] ^= 1
        script = Path(validator.__file__)
        with tempfile.TemporaryDirectory() as directory:
            golden_path = Path(directory) / "golden.tar"
            tampered_path = Path(directory) / "tampered.tar"
            golden_path.write_bytes(raw)
            tampered_path.write_bytes(tampered)
            golden = subprocess.run(
                [sys.executable, str(script), str(golden_path)],
                check=False, capture_output=True, text=True,
            )
            rejected = subprocess.run(
                [sys.executable, str(script), str(tampered_path)],
                check=False, capture_output=True, text=True,
            )

        self.assertEqual(golden.returncode, 0, golden.stderr)
        self.assertEqual(json.loads(golden.stdout)["code"], "OK")
        self.assertEqual(rejected.returncode, 1, rejected.stdout)
        self.assertEqual(json.loads(rejected.stderr)["code"], "MEMBER_SHA256_MISMATCH")


if __name__ == "__main__":
    unittest.main()
