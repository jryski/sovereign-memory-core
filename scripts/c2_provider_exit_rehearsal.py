#!/usr/bin/env python3
"""Execute the v0.3-alpha C2 provider-exit proof on two independent PostgreSQL clusters.

The source is a privacy-safe synthetic deployment built from the exact reviewed
repository migrations.  The bundle contains only deterministic, validator-
supported relation encodings.  The clean target is restored from that bundle,
then checked through constrained service paths plus the C1 perimeter seam.
"""

from __future__ import annotations

import argparse
import datetime as dt
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Any
from urllib.parse import urlparse
from uuid import UUID

from scripts import sovereignty_bundle as bundle
from scripts import validate_sovereignty_bundle as validator


EVIDENCE = b"C2 synthetic provider-exit evidence\n"
EVIDENCE_SHA256 = hashlib.sha256(EVIDENCE).hexdigest()
EVIDENCE_LOCATOR = f"artifact:sha256:{EVIDENCE_SHA256}"
REPOSITORY_URL = "https://github.com/jryski/sovereign-memory-core.git"
MIGRATIONS = (
    "01_core.sql",
    "07_work_lessons.sql",
    "08_attention_events.sql",
    "09_perimeter_refresh.sql",
    "10_security_definer_hardening.sql",
    "11_perimeter_evaluability.sql",
)
_IDENT = re.compile(r"^[a-z_][a-z0-9_]*$")


@dataclass(frozen=True)
class Column:
    name: str
    pg_type: str


@dataclass(frozen=True)
class ForeignKey:
    columns: tuple[str, ...]
    referenced_schema: str
    referenced_relation: str
    referenced_columns: tuple[str, ...]
    deferrable: bool = False


@dataclass(frozen=True)
class Relation:
    schema: str
    name: str
    order: int
    columns: tuple[Column, ...]
    primary_key: tuple[str, ...]
    dependencies: tuple[str, ...] = ()
    foreign_keys: tuple[ForeignKey, ...] = ()

    @property
    def path(self) -> str:
        return f"data/{self.order:03d}-{self.schema}.{self.name}.jsonl"


RELATIONS = (
    Relation(
        "public", "memories", 10,
        (
            Column("id", "uuid"), Column("content", "text"),
            Column("workstream", "text"), Column("owner", "text"),
            Column("visibility", "text"), Column("source_agent", "text"),
            Column("source_ref", "text"), Column("hot_touched", "boolean"),
            Column("created_at", "timestamptz"), Column("updated_at", "timestamptz"),
        ),
        ("id",),
    ),
    Relation(
        "public", "memory_hot_index", 20,
        (
            Column("id", "uuid"), Column("memory_id", "uuid"),
            Column("topic_key", "text"), Column("owner", "text"),
            Column("visibility", "text"), Column("summary", "text"),
            Column("workstream", "text"), Column("touch_count", "integer"),
            Column("last_touched", "timestamptz"), Column("created_at", "timestamptz"),
        ),
        ("id",),
        ("public.memories",),
        (ForeignKey(("memory_id",), "public", "memories", ("id",)),),
    ),
    Relation(
        "public", "work_lessons", 30,
        (
            Column("id", "uuid"), Column("kind", "text"), Column("claim", "text"),
            Column("detail", "text"), Column("applies_to", "text"),
            Column("learned_on", "date"), Column("status", "text"),
            Column("supersedes", "uuid"), Column("authority_state", "text"),
            Column("created_by", "text"), Column("accepted_by", "text"),
            Column("accepted_at", "timestamptz"), Column("authority_ref", "text"),
            Column("created_at", "timestamptz"),
        ),
        ("id",),
    ),
    Relation(
        "public", "work_lesson_evidence", 40,
        (
            Column("id", "uuid"), Column("lesson_id", "uuid"),
            Column("evidence_kind", "text"), Column("locator", "text"),
            Column("source_authority", "text"), Column("integrity_hash", "text"),
            Column("resolution_state", "text"), Column("created_by", "text"),
            Column("supersedes", "uuid"), Column("correction_reason", "text"),
            Column("created_at", "timestamptz"),
        ),
        ("id",),
        ("public.work_lessons",),
        (ForeignKey(("lesson_id",), "public", "work_lessons", ("id",)),),
    ),
    Relation(
        "public", "work_lesson_events", 50,
        (
            Column("id", "uuid"), Column("lesson_id", "uuid"),
            Column("event_type", "text"), Column("actor", "text"),
            Column("authority_ref", "text"), Column("details", "jsonb"),
            Column("occurred_at", "timestamptz"),
        ),
        ("id",),
        ("public.work_lessons",),
        (ForeignKey(("lesson_id",), "public", "work_lessons", ("id",)),),
    ),
    Relation(
        "public", "attention_events", 60,
        (
            Column("id", "uuid"), Column("contract_version", "text"),
            Column("source_system", "text"), Column("source_namespace", "text"),
            Column("source_event_type", "text"), Column("source_native_event_id", "text"),
            Column("identity_key", "text"), Column("revision_key", "text"),
            Column("source_revision", "text"), Column("revision_ordinal", "integer"),
            Column("supersedes_event_id", "uuid"), Column("memory_id", "uuid"),
            Column("principal_key", "text"), Column("owner", "text"),
            Column("visibility", "text"), Column("actor_key", "text"),
            Column("credential_ref", "text"), Column("runtime_ref", "text"),
            Column("workstream_as_of", "text"), Column("topic_key_as_of", "text"),
            Column("occurred_at", "timestamptz"), Column("recorded_at", "timestamptz"),
            Column("source_evidence_ref", "text"), Column("observation_method", "text"),
            Column("historical_import", "boolean"), Column("metadata", "jsonb"),
        ),
        ("id",),
        ("public.memories",),
        # The actual table also has a non-deferrable self-FK on supersedes_event_id.
        # The v1 bundle dependency profile rejects non-deferrable cyclic FK metadata,
        # so self-lineage is intentionally restored by revision ordinal and verified
        # explicitly instead of being misdeclared in the manifest.
        (ForeignKey(("memory_id",), "public", "memories", ("id",)),),
    ),
)


def _safe_identifier(value: str) -> str:
    if _IDENT.fullmatch(value) is None:
        raise ValueError(f"unsafe SQL identifier: {value!r}")
    return value


def _run_psql(dsn: str, sql: str | bytes, *, tuples: bool = False) -> str:
    cmd = ["psql", dsn, "-X", "-v", "ON_ERROR_STOP=1", "-q"]
    if tuples:
        cmd.extend(["-A", "-t"])
    proc = subprocess.run(
        cmd,
        input=sql.encode("utf-8") if isinstance(sql, str) else sql,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if proc.returncode:
        stderr = proc.stderr.decode("utf-8", errors="replace")[-4000:]
        raise RuntimeError(f"psql failed ({proc.returncode}): {stderr}")
    return proc.stdout.decode("utf-8", errors="strict").strip()


def _scalar(dsn: str, sql: str) -> str:
    return _run_psql(dsn, sql, tuples=True).strip()


def _json_query(dsn: str, sql: str) -> Any:
    raw = _scalar(dsn, sql)
    if not raw:
        raise RuntimeError("query returned no JSON")
    return json.loads(raw)


def _database_name(dsn: str) -> str:
    name = urlparse(dsn).path.lstrip("/") or "postgres"
    return _safe_identifier(name)


def _bootstrap_cluster(dsn: str) -> dict[str, str]:
    db = _database_name(dsn)
    _run_psql(
        dsn,
        f"""
        create schema if not exists extensions;
        do $$ begin
          if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
          if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
          if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
        end $$;
        alter database {db} set sovereign_memory.perimeter_profile='supabase';
        alter default privileges for role postgres revoke execute on functions from public;
        alter default privileges for role pg_database_owner revoke execute on functions from public;
        """,
    )
    return {
        "server_version": _scalar(dsn, "show server_version;"),
        "system_identifier": _scalar(dsn, "select system_identifier::text from pg_control_system();"),
        "database": db,
    }


def _apply_repo_migrations(dsn: str, root: Path) -> list[dict[str, Any]]:
    receipts: list[dict[str, Any]] = []
    for order, name in enumerate(MIGRATIONS, start=1):
        raw = (root / "sql" / name).read_bytes()
        _run_psql(dsn, raw)
        receipts.append({
            "order": order,
            "path": f"migrations/{name}",
            "sha256": hashlib.sha256(raw).hexdigest(),
            "bytes": len(raw),
        })
    return receipts


def _seed_source(dsn: str) -> None:
    _run_psql(
        dsn,
        f"""
        do $$
        declare
          v_user uuid;
          v_partner uuid;
          v_event uuid;
          v_lesson uuid;
        begin
          insert into public.memories(content,workstream,owner,visibility,source_agent,source_ref)
          values(
            'C2 USER PRIVATE POSITIVE',null,'example-user','private','example-user-chatgpt','{EVIDENCE_LOCATOR}'
          ) returning id into v_user;
          perform public.hot_touch('c2/user-private',v_user,'C2 USER PRIVATE POSITIVE',null);
          perform public.hot_touch('c2/user-private',v_user,'C2 USER PRIVATE POSITIVE',null);

          insert into public.memories(content,workstream,owner,visibility,source_agent,source_ref)
          values(
            'C2 PARTNER PRIVATE SECRET',null,'example-partner','private','example-partner-chatgpt','{EVIDENCE_LOCATOR}'
          ) returning id into v_partner;
          perform public.hot_touch('c2/partner-private',v_partner,'C2 PARTNER PRIVATE SECRET',null);
          perform public.hot_touch('c2/partner-private',v_partner,'C2 PARTNER PRIVATE SECRET',null);

          select id into v_event
          from public.attention_events
          where memory_id=v_user and source_event_type='memory_created' and revision_ordinal=1;
          perform set_config('app.actor_agent','c2-independent-observer',true);
          perform set_config('app.credential_ref','asserted:c2-fixture',true);
          perform set_config('app.runtime_ref','runtime:c2-provider-exit',true);
          perform public.append_attention_event_revision(
            v_event,'observed-revision:2',clock_timestamp(),'{EVIDENCE_LOCATOR}',
            'c2-provider-exit-observation','{{"fixture":true}}'::jsonb
          );

          v_lesson:=public.propose_work_lesson(
            'rule','C2 ACCEPTED RESTORED RULE','synthetic provider-exit fixture',
            'artifact','{EVIDENCE_LOCATOR}','c2-fixture','c2-fixture','resolvable','{EVIDENCE_SHA256}'
          );
          perform public.accept_work_lesson(v_lesson,'c2-owner','coordination:c2:acceptance');
        end $$;
        """,
    )


def _encode_value(pg_type: str, value: Any) -> Any:
    if value is None:
        return None
    if pg_type == "uuid":
        return bundle.encode_pg_scalar(pg_type, UUID(value))
    if pg_type == "timestamptz":
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
        return bundle.encode_pg_scalar(pg_type, parsed)
    if pg_type == "date":
        return bundle.encode_pg_scalar(pg_type, dt.date.fromisoformat(value))
    if pg_type in {"integer", "int4", "bigint", "int8"}:
        return bundle.encode_pg_scalar(pg_type, int(value))
    if pg_type in {"boolean", "bool"}:
        if not isinstance(value, bool):
            raise TypeError(f"expected JSON boolean for {pg_type}")
        return bundle.encode_pg_scalar(pg_type, value)
    if pg_type in {"json", "jsonb"}:
        return bundle.encode_pg_scalar(pg_type, bundle.PgJsonValue(value))
    if pg_type == "text":
        return bundle.encode_pg_scalar(pg_type, str(value))
    raise TypeError(f"unsupported C2 fixture type: {pg_type}")


def _relation_payload(dsn: str, relation: Relation) -> tuple[bytes, list[dict[str, Any]]]:
    schema = _safe_identifier(relation.schema)
    table = _safe_identifier(relation.name)
    names = [_safe_identifier(column.name) for column in relation.columns]
    select_list = ",".join(names)
    pk_order = ",".join(_safe_identifier(name) for name in relation.primary_key)
    raw_rows = _json_query(
        dsn,
        f"select coalesce(json_agg(row_to_json(q) order by {pk_order}),'[]'::json)::text "
        f"from (select {select_list} from {schema}.{table}) q;",
    )
    rows: list[dict[str, Any]] = []
    for raw in raw_rows:
        encoded = {
            column.name: _encode_value(column.pg_type, raw.get(column.name))
            for column in relation.columns
        }
        rows.append({"pk": [encoded[name] for name in relation.primary_key], "row": encoded})
    # json_agg ordering above is by the source PG comparator. The bundle validator
    # independently confirms strict canonical PK ordering for the declared types.
    return bundle.canonical_jsonl_bytes(rows), rows


def _migration_owned_invariants(dsn: str) -> dict[str, Any]:
    return {
        "trusted_agents": _json_query(
            dsn,
            "select coalesce(json_agg(row_to_json(q) order by agent_id),'[]'::json)::text "
            "from (select agent_id,principal,model,surface,active from public.trusted_agents) q;",
        ),
        "instruction_hash": _scalar(
            dsn,
            "select coalesce(public.current_doc_hash('_system/ai-instructions'),'');",
        ),
        "memory_default_violations": int(_scalar(
            dsn,
            "select count(*) from public.memories where source_kind<>'manual' or status<>'active' "
            "or tags<>'{}'::text[] or metadata<>'{}'::jsonb or due_date is not null "
            "or due_status is not null or confidence is not null or supersedes is not null;",
        )),
        "hot_staging_rows": int(_scalar(dsn, "select count(*) from public.memory_hot_staging;")),
        "attention_assignment_rows": int(_scalar(dsn, "select count(*) from public.attention_event_assignments;")),
    }


def _entry(path: str, role: str, media_type: str, raw: bytes) -> dict[str, Any]:
    return {
        "bytes": len(raw), "media_type": media_type, "mode": "0644",
        "path": path, "role": role, "sha256": hashlib.sha256(raw).hexdigest(),
    }


def _build_bundle(dsn: str, root: Path, commit: str) -> tuple[bytes, dict[str, Any], dict[str, Any]]:
    if re.fullmatch(r"[0-9a-f]{40}", commit) is None:
        raise ValueError("commit must be an exact lowercase 40-character SHA")

    relation_payloads: dict[str, bytes] = {}
    relation_rows: dict[str, list[dict[str, Any]]] = {}
    relation_manifests: list[dict[str, Any]] = []
    for relation in RELATIONS:
        raw, rows = _relation_payload(dsn, relation)
        relation_payloads[relation.path] = raw
        relation_rows[relation.path] = rows
        relation_manifests.append({
            "bytes": len(raw),
            "columns": [
                {"name": column.name, "ordinal": index, "pg_type": column.pg_type}
                for index, column in enumerate(relation.columns, start=1)
            ],
            "dependencies": sorted(relation.dependencies),
            "foreign_keys": [
                {
                    "columns": list(fk.columns), "deferrable": fk.deferrable,
                    "referenced_columns": list(fk.referenced_columns),
                    "referenced_relation": fk.referenced_relation,
                    "referenced_schema": fk.referenced_schema,
                }
                for fk in relation.foreign_keys
            ],
            "path": relation.path,
            "primary_key": list(relation.primary_key),
            "relation": relation.name,
            "restore_order": relation.order,
            "row_count": len(rows),
            "row_digest_algorithm": "sha256-raw-jsonl-v1",
            "schema": relation.schema,
            "sha256": hashlib.sha256(raw).hexdigest(),
        })

    migration_payloads: dict[str, bytes] = {}
    migrations: list[dict[str, Any]] = []
    for order, name in enumerate(MIGRATIONS, start=1):
        path = f"migrations/{name}"
        raw = (root / "sql" / name).read_bytes()
        migration_payloads[path] = raw
        migrations.append({"order": order, "path": path, "sha256": hashlib.sha256(raw).hexdigest()})

    invariants = _migration_owned_invariants(dsn)
    source_snapshot = {
        "commit": commit,
        "fixture": "c2-provider-exit/full-synthetic-v1",
        "migration_owned_invariants": invariants,
        "relations": [
            {"path": item["path"], "row_count": item["row_count"], "sha256": item["sha256"]}
            for item in relation_manifests
        ],
    }
    source_snapshot_raw = bundle.canonical_json_bytes(source_snapshot)
    loss_report = {
        "loss_summary": {"unclassified": 0, "unsupported": 0},
        "selected_fixture_scope": [f"{r.schema}.{r.name}" for r in RELATIONS],
        "migration_default_invariants": {
            "public.memories.source_kind": "manual",
            "public.memories.status": "active",
            "public.memories.tags": [],
            "public.memories.metadata": {},
            "public.memories.due_date": None,
            "public.memories.due_status": None,
            "public.memories.confidence": None,
            "public.memories.supersedes": None,
        },
        "known_profile_constraints": [
            "manifest v1 cannot declare non-deferrable cyclic self-FKs; attention self-lineage is restored by ordinal and verified after load",
            "enum-valued memory columns are migration-default invariants in this synthetic profile rather than relation payload fields",
        ],
    }
    loss_report_raw = bundle.canonical_json_bytes(loss_report)
    restore_plan = {
        "migration_order": [f"migrations/{name}" for name in MIGRATIONS],
        "relation_order": [r.path for r in RELATIONS],
        "source_mutation": "none",
        "target_trigger_handling": ["disable USER triggers on public.memories during relation load", "re-enable before verification"],
        "verification": [
            "bundle hashes", "relation byte equality", "migration-owned defaults",
            "positive-control readability", "paired private denial", "attention revision lineage",
            "accepted work lesson and evidence", "perimeter-report/1", "exact public assertion result",
        ],
    }
    restore_plan_raw = bundle.canonical_json_bytes(restore_plan)
    sequence_state_raw = bundle.canonical_json_bytes({"sequences": []})

    evidence_path = f"evidence/sha256/{EVIDENCE_SHA256[:2]}/{EVIDENCE_SHA256}"
    payloads: dict[str, tuple[str, str, bytes]] = {}
    for path, raw in relation_payloads.items():
        payloads[path] = ("relation", "application/x-ndjson", raw)
    for path, raw in migration_payloads.items():
        payloads[path] = ("migration", "application/sql", raw)
    payloads[evidence_path] = ("evidence", "application/octet-stream", EVIDENCE)
    payloads["reports/loss-report.json"] = ("loss-report", "application/json", loss_report_raw)
    payloads["reports/source-snapshot.json"] = ("source-snapshot", "application/json", source_snapshot_raw)
    payloads["restore/plan.json"] = ("restore-plan", "application/json", restore_plan_raw)
    payloads["state/sequences.json"] = ("sequence-state", "application/json", sequence_state_raw)

    entries = [
        _entry(path, role, media_type, raw)
        for path, (role, media_type, raw) in sorted(payloads.items())
    ]
    dependencies: list[dict[str, Any]] = []
    migration_paths = [f"migrations/{name}" for name in MIGRATIONS]
    for index, path in enumerate(migration_paths):
        dependencies.append({"path": path, "requires": [] if index == 0 else [migration_paths[index - 1]]})
    final_migration = migration_paths[-1]
    for relation in RELATIONS:
        dependencies.append({"path": relation.path, "requires": [final_migration]})
    dependencies.sort(key=lambda item: item["path"].encode("utf-8"))

    python_version = f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"
    psql_version = subprocess.run(["psql", "--version"], stdout=subprocess.PIPE, check=True).stdout.decode().strip()
    toolchain = []
    for name, version in sorted((("postgresql-client", psql_version), ("python", python_version))):
        identity = "sha256:" + hashlib.sha256(f"{name}:{version}".encode()).hexdigest()
        toolchain.append({"identity": identity, "name": name, "version": version})

    manifest = {
        "compatibility": {"postgresql": {"maximum_exclusive_major": 17, "minimum_major": 15}},
        "dependencies": dependencies,
        "entries": entries,
        "evidence": [{
            "locators": [{"byte_end": len(EVIDENCE), "byte_start": 0, "locator": EVIDENCE_LOCATOR}],
            "path": evidence_path,
            "sha256": EVIDENCE_SHA256,
        }],
        "exporter": {"version": "c2-provider-exit/1"},
        "format": "sovereign-memory.bundle/1.0",
        "loss_report_path": "reports/loss-report.json",
        "migrations": migrations,
        "profile": "full-synthetic-v1",
        "relations": relation_manifests,
        "restore_plan_path": "restore/plan.json",
        "schema_version": "sovereign-memory.manifest/1.0",
        "sequence_state_path": "state/sequences.json",
        "source": {"commit": commit, "repository_url": REPOSITORY_URL},
        "source_snapshot_path": "reports/source-snapshot.json",
        "toolchain": toolchain,
    }
    manifest_raw = bundle.canonical_json_bytes(manifest)
    archive = bundle.write_ustar([("manifest.json", manifest_raw), *[(path, data[2]) for path, data in payloads.items()]])
    validator.validate_bundle(archive, expected_archive_sha256=hashlib.sha256(archive).hexdigest())
    return archive, manifest, source_snapshot


def _member_bytes(raw: bytes) -> dict[str, bytes]:
    return {
        member.path: bytes(memoryview(raw)[member.data_offset:member.data_offset + member.size])
        for member in bundle.validate_ustar(raw)
    }


def _restore_relation_sql(relation: Relation, rows: list[dict[str, Any]]) -> str:
    ordered = rows
    if relation.name == "attention_events":
        ordered = sorted(rows, key=lambda item: (item["row"]["revision_ordinal"], item["row"]["id"]))
    row_objects = [item["row"] for item in ordered]
    raw_json = json.dumps(row_objects, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    delimiter = "$c2json$"
    if delimiter in raw_json:
        raise ValueError("unexpected restore delimiter collision")
    columns = ",".join(_safe_identifier(column.name) for column in relation.columns)
    return (
        f"insert into {relation.schema}.{relation.name} ({columns}) "
        f"select {columns} from jsonb_populate_recordset(null::{relation.schema}.{relation.name},"
        f"{delimiter}{raw_json}{delimiter}::jsonb);\n"
    )


def _restore_bundle(dsn: str, raw: bytes, root: Path) -> None:
    result = validator.validate_bundle(raw, expected_archive_sha256=hashlib.sha256(raw).hexdigest())
    members = _member_bytes(raw)
    for migration in result.manifest["migrations"]:
        _run_psql(dsn, members[migration["path"]])

    rows_by_path: dict[str, list[dict[str, Any]]] = {}
    for relation in result.manifest["relations"]:
        lines = members[relation["path"]].splitlines(keepends=True)
        rows_by_path[relation["path"]] = [bundle.parse_canonical_json_bytes(line) for line in lines]

    sql = [
        "begin;",
        "select set_config('app.work_lessons_write','on',true);",
        "select set_config('app.work_lesson_custody_write','on',true);",
        "alter table public.memories disable trigger user;",
    ]
    for relation in RELATIONS:
        sql.append(_restore_relation_sql(relation, rows_by_path[relation.path]))
        if relation.name == "memories":
            sql.append("alter table public.memories enable trigger user;")
    sql.append("commit;")
    _run_psql(dsn, "\n".join(sql))


def _relation_receipts(dsn: str) -> list[dict[str, Any]]:
    receipts = []
    for relation in RELATIONS:
        raw, rows = _relation_payload(dsn, relation)
        receipts.append({"path": relation.path, "row_count": len(rows), "sha256": hashlib.sha256(raw).hexdigest()})
    return receipts


def _source_fingerprint(dsn: str) -> dict[str, Any]:
    payload = {
        "relations": _relation_receipts(dsn),
        "migration_owned_invariants": _migration_owned_invariants(dsn),
    }
    return {
        "sha256": hashlib.sha256(bundle.canonical_json_bytes(payload)).hexdigest(),
        "payload": payload,
    }


def _verify_target(dsn: str, manifest: dict[str, Any]) -> dict[str, Any]:
    expected = {item["path"]: (item["row_count"], item["sha256"]) for item in manifest["relations"]}
    actual = _relation_receipts(dsn)
    for item in actual:
        if expected[item["path"]] != (item["row_count"], item["sha256"]):
            raise RuntimeError(f"restored relation mismatch: {item['path']}")

    invariants = _migration_owned_invariants(dsn)
    if invariants["memory_default_violations"] != 0 or invariants["hot_staging_rows"] != 0:
        raise RuntimeError(f"migration-default invariant failed: {invariants}")
    if invariants["attention_assignment_rows"] != 0:
        raise RuntimeError("fixture unexpectedly restored attention assignments")

    user_projection = _json_query(
        dsn,
        "set role service_role; select public.attention_boot_projection_v2('example-user',4096,240)::text;",
    )
    partner_projection = _json_query(
        dsn,
        "set role service_role; select public.attention_boot_projection_v2('example-partner',4096,240)::text;",
    )
    user_text = json.dumps(user_projection, sort_keys=True)
    partner_text = json.dumps(partner_projection, sort_keys=True)
    positive_control = "C2 USER PRIVATE POSITIVE" in user_text
    paired_denial = "C2 PARTNER PRIVATE SECRET" not in user_text
    reciprocal_positive = "C2 PARTNER PRIVATE SECRET" in partner_text
    reciprocal_denial = "C2 USER PRIVATE POSITIVE" not in partner_text
    if not all((positive_control, paired_denial, reciprocal_positive, reciprocal_denial)):
        raise RuntimeError("positive-control/paired-denial visibility proof failed")

    direct_memory_select = _scalar(
        dsn,
        "select has_table_privilege('service_role','public.memories','SELECT')::text;",
    )
    if direct_memory_select != "false":
        raise RuntimeError("service_role unexpectedly gained direct memories SELECT")

    work_fragment = _json_query(
        dsn,
        "set role service_role; select public.work_lessons_boot_fragment()::text;",
    )
    if "C2 ACCEPTED RESTORED RULE" not in json.dumps(work_fragment, sort_keys=True):
        raise RuntimeError("accepted work lesson did not survive restore")
    evidence_ok = _scalar(
        dsn,
        "set role service_role; select (count(*)=1)::text from public.work_lesson_evidence "
        f"where locator='{EVIDENCE_LOCATOR}' and integrity_hash='{EVIDENCE_SHA256}' and resolution_state='resolvable';",
    )
    if evidence_ok != "true":
        raise RuntimeError("work-lesson evidence custody did not survive restore")

    attention_ok = _scalar(
        dsn,
        "set role service_role; with user_line as ("
        "select * from public.attention_events where owner='example-user' and source_event_type='memory_created'"
        ") select (count(*)=2 and min(revision_ordinal)=1 and max(revision_ordinal)=2 "
        "and count(*) filter(where revision_ordinal=2 and supersedes_event_id is not null "
        f"and source_evidence_ref='{EVIDENCE_LOCATOR}' and credential_ref='asserted:c2-fixture')=1)::text from user_line;",
    )
    if attention_ok != "true":
        raise RuntimeError("attention revision/provenance lineage did not survive restore")

    perimeter = _json_query(dsn, "set role service_role; select public.perimeter_report()::text;")
    if not (
        perimeter.get("contract_version") == "perimeter-report/1"
        and perimeter.get("evaluation_status") == "evaluated"
        and perimeter.get("perimeter_state") == "clean"
        and perimeter.get("violation_count") == 0
    ):
        raise RuntimeError(f"restored target perimeter is not evaluated/clean: {perimeter}")
    assertion = _scalar(dsn, "set role service_role; select public.assert_perimeter_closed();")
    expected_assertion = "perimeter OK: perimeter-report/1 evaluated clean with zero findings"
    if assertion != expected_assertion:
        raise RuntimeError(f"unexpected public assertion result: {assertion!r}")

    return {
        "relations": actual,
        "migration_owned_invariants": invariants,
        "positive_control_readable": positive_control,
        "paired_private_denial": paired_denial,
        "reciprocal_positive_readable": reciprocal_positive,
        "reciprocal_private_denial": reciprocal_denial,
        "service_role_direct_memories_select": False,
        "work_lesson_boot_fragment": work_fragment,
        "attention_revision_lineage": True,
        "perimeter_report": perimeter,
        "assert_perimeter_closed": assertion,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dsn", required=True)
    parser.add_argument("--target-dsn", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)

    target_preflight_tables = int(_scalar(
        args.target_dsn,
        "select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace "
        "where n.nspname='public' and c.relkind in ('r','p');",
    ))
    if target_preflight_tables != 0:
        raise RuntimeError("destination was not clean before rehearsal")

    source_cluster = _bootstrap_cluster(args.source_dsn)
    target_cluster = _bootstrap_cluster(args.target_dsn)
    if source_cluster["system_identifier"] == target_cluster["system_identifier"]:
        raise RuntimeError("source and destination are not independent PostgreSQL clusters")

    source_migrations = _apply_repo_migrations(args.source_dsn, root)
    _seed_source(args.source_dsn)

    source_before = _source_fingerprint(args.source_dsn)
    archive_one, manifest, source_snapshot = _build_bundle(args.source_dsn, root, args.commit)
    archive_two, manifest_two, source_snapshot_two = _build_bundle(args.source_dsn, root, args.commit)
    if archive_one != archive_two or manifest != manifest_two or source_snapshot != source_snapshot_two:
        raise RuntimeError("same-source export was not byte deterministic")
    archive_sha = hashlib.sha256(archive_one).hexdigest()
    manifest_sha = hashlib.sha256(bundle.canonical_json_bytes(manifest)).hexdigest()

    (output / "sovereign-memory-c2.bundle.tar").write_bytes(archive_one)
    (output / "archive.sha256").write_text(f"{archive_sha}  sovereign-memory-c2.bundle.tar\n", encoding="utf-8")

    _restore_bundle(args.target_dsn, archive_one, root)
    target_verification = _verify_target(args.target_dsn, manifest)
    source_after = _source_fingerprint(args.source_dsn)
    if source_after != source_before:
        raise RuntimeError("source changed during export/restore rehearsal")

    receipt = {
        "contract": "c2-provider-exit-receipt/1",
        "repository": REPOSITORY_URL,
        "exact_commit": args.commit,
        "source": {
            **source_cluster,
            "fixture": "privacy-safe full-synthetic-v1",
            "migrations": source_migrations,
            "before_fingerprint": source_before["sha256"],
            "after_fingerprint": source_after["sha256"],
            "unchanged": True,
        },
        "destination": {
            **target_cluster,
            "preflight_public_table_count": target_preflight_tables,
            "clean_before_restore": True,
            "disposable_container_required": True,
        },
        "bundle": {
            "archive_sha256": archive_sha,
            "manifest_sha256": manifest_sha,
            "byte_deterministic_repeat_export": True,
            "profile": manifest["profile"],
            "format": manifest["format"],
            "schema_version": manifest["schema_version"],
            "source_snapshot": source_snapshot,
        },
        "verification": target_verification,
        "commands": [
            "bootstrap independent source and destination clusters",
            "apply exact repository migrations 01,07,08,09,10,11 to source",
            "seed privacy-safe fixture through native/sanctioned write paths",
            "export same source twice and require byte-identical bundle",
            "validate bundle and external archive checksum",
            "apply bundle migrations to initially empty destination",
            "restore declared relations with memory USER triggers disabled only during load",
            "re-enable triggers and compare restored relation bytes/hashes",
            "run positive control, paired denial, work/evidence, attention lineage and C1 perimeter checks",
            "re-fingerprint source and require exact equality",
        ],
    }
    (output / "receipt.json").write_text(
        json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps({
        "code": "C2_PROVIDER_EXIT_PASS",
        "archive_sha256": archive_sha,
        "manifest_sha256": manifest_sha,
        "source_system_identifier": source_cluster["system_identifier"],
        "destination_system_identifier": target_cluster["system_identifier"],
        "source_fingerprint": source_before["sha256"],
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
