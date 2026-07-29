import hashlib
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

    def test_validation_is_bounded_and_never_extracts(self):
        members = dict(MEMBERS)
        members["reports/source-snapshot.json"] = b"x" * (8 * 1024 * 1024)
        manifest = valid_manifest()
        source_entry = next(
            entry for entry in manifest["entries"]
            if entry["path"] == "reports/source-snapshot.json"
        )
        source_entry["bytes"] = len(members["reports/source-snapshot.json"])
        source_entry["sha256"] = hashlib.sha256(members["reports/source-snapshot.json"]).hexdigest()
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
