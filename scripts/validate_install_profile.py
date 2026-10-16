#!/usr/bin/env python3
"""Validate (and optionally apply to a disposable DB) a bounded install profile.

Fails closed with JSON errors. The DSN is read from an environment variable
(--dsn-env, default DATABASE_URL); it is never accepted on argv.
"""
import argparse, hashlib, json, os, re, subprocess, sys
from pathlib import Path

SHIM_SQL = """
create schema if not exists extensions;
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
end $$;
-- docs/perimeter.md operator boundary: owner-global default function EXECUTE
-- for PUBLIC must be revoked before 09/10 perimeter asserts can pass.
alter default privileges for role postgres revoke execute on functions from public;
alter default privileges for role pg_database_owner revoke execute on functions from public;
"""
KNOWN_OPTIONAL = frozenset({
    "sql/02_vault.sql",
    "sql/03_provenance_guards.sql",
    "sql/04_source_import.sql",
    "sql/05_candidate_locators.sql",
    "sql/06_cutover_probe_categories.sql",
})
PATH_RE = re.compile(r"^sql/[0-9]{2}_[a-z0-9_]+\.sql$")
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")
IDENT_RE = re.compile(r"^[a-z_][a-z0-9_]*(\.[a-z_][a-z0-9_]*)?$")


def err(errors, code, detail):
    errors.append({"code": code, "detail": detail})


def path_ok(root: Path, p) -> bool:
    if not isinstance(p, str) or not PATH_RE.fullmatch(p):
        return False
    try:
        (root / p).resolve().relative_to(root)
    except ValueError:
        return False
    return True


def check_static(root: Path, prof):
    errors, files = [], []
    if not isinstance(prof, dict):
        err(errors, "PROFILE_INVALID", "profile must be a JSON object")
        return errors, files
    migs = prof.get("migrations")
    if not isinstance(migs, list) or not migs:
        err(errors, "PROFILE_INVALID", "migrations must be a non-empty list")
        return errors, files
    for i, m in enumerate(migs):
        if not isinstance(m, dict):
            err(errors, "PROFILE_INVALID", f"migrations[{i}] must be an object")
        elif not isinstance(m.get("path"), str):
            err(errors, "PROFILE_INVALID", f"migrations[{i}].path must be a string")
        elif not isinstance(m.get("sha256"), str) or not HEX64_RE.fullmatch(m["sha256"]):
            err(errors, "PROFILE_INVALID", f"migrations[{i}].sha256 must be 64 lowercase hex chars (digest pin required)")
        elif not path_ok(root, m["path"]):
            err(errors, "PATH_INVALID", f"migrations[{i}].path {m['path']!r} must match ^sql/[0-9]{{2}}_[a-z0-9_]+\\.sql$ inside root")
    excl = prof.get("excluded_optional", [])
    if not isinstance(excl, list) or not all(isinstance(x, str) for x in excl):
        err(errors, "PROFILE_INVALID", "excluded_optional must be a list of strings")
        excl = []
    excl_errors = []  # reported, but do not block the remaining checks
    for x in excl:
        if x not in KNOWN_OPTIONAL:
            err(excl_errors, "REQUIRED_MIGRATION_EXCLUDED", f"{x} is not in the optional set sql/02-06")
    oc = prof.get("order_constraints", [])
    if not isinstance(oc, list) or not all(isinstance(c, dict) for c in oc):
        err(errors, "PROFILE_INVALID", "order_constraints must be a list of objects")
    else:
        for i, c in enumerate(oc):
            for k in ("first", "last", "after"):
                if k in c and not isinstance(c[k], str):
                    err(errors, "PROFILE_INVALID", f"order_constraints[{i}].{k} must be a string")
            if "after" in c and (not isinstance(c.get("before"), list) or not all(isinstance(b, str) for b in c["before"])):
                err(errors, "PROFILE_INVALID", f"order_constraints[{i}].before must be a list of strings")
    for sect, key in (("dependencies", "extensions"), ("post_checks", "tables")):
        d = prof.get(sect, {})
        vals = d.get(key, []) if isinstance(d, dict) else None
        if not isinstance(vals, list) or not all(isinstance(v, str) and IDENT_RE.fullmatch(v) for v in vals):
            err(errors, "PROFILE_INVALID", f"{sect}.{key} must be a list of plain identifiers")
    if errors:  # structural problems: stop before touching the filesystem
        return errors + excl_errors, files
    errors.extend(excl_errors)

    excluded = set(excl)
    paths = [m["path"] for m in migs]
    if len(set(paths)) != len(paths):
        err(errors, "DUPLICATE_MIGRATION", "migration listed more than once")
    for m in migs:
        p = m["path"]
        fp = root / p
        if p in excluded or p in KNOWN_OPTIONAL:
            err(errors, "OPTIONAL_SILENTLY_INCLUDED", p)
        if not fp.is_file():
            err(errors, "MISSING_DEPENDENCY", p); continue
        try:
            digest = hashlib.sha256(fp.read_bytes()).hexdigest()
        except OSError as e:
            err(errors, "UNREADABLE", f"{p}: {e}"); continue
        if m["sha256"] != digest:
            err(errors, "DIGEST_MISMATCH", p)
        files.append({"path": p, "sha256": digest})
    # every numbered migration on disk (any case) must be listed or be a known optional exclusion
    sqldir = root / "sql"
    disk = sorted(f for f in sqldir.iterdir() if f.is_file() and re.match(r"^[0-9]{2}_.*\.sql$", f.name, re.I)) if sqldir.is_dir() else []
    for fp in disk:
        rel = fp.relative_to(root).as_posix()
        if rel not in paths and not (rel in excluded and rel in KNOWN_OPTIONAL):
            err(errors, "MANIFEST_UNLISTED_MIGRATION", rel)
    for c in oc:
        if "first" in c and paths[:1] != [c["first"]]:
            err(errors, "ORDER_VIOLATION", f"{c['first']} must be first")
        if "last" in c and paths[-1:] != [c["last"]]:
            err(errors, "ORDER_VIOLATION", f"{c['last']} must be last")
        if "after" in c:
            if c["after"] not in paths:
                err(errors, "MISSING_DEPENDENCY", c["after"]); continue
            ai = paths.index(c["after"])
            for b in c["before"]:
                if b not in paths:
                    err(errors, "MISSING_DEPENDENCY", f"{b} (required before {c['after']})")
                elif paths.index(b) > ai:
                    err(errors, "ORDER_VIOLATION", f"{b} must precede {c['after']}")
    return errors, files


def psql(dsn, args, stdin=None):
    return subprocess.run(["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", dsn, *args],
                          input=stdin, capture_output=True, text=True)


def apply(root, prof, dsn, errors):
    applied = []
    r = psql(dsn, [], SHIM_SQL)
    if r.returncode:
        err(errors, "LAB_SHIM_FAILED", r.stderr.strip()[-500:]); return applied
    for m in prof["migrations"]:
        r = psql(dsn, ["-1", "-f", str(root / m["path"])])
        if r.returncode:
            err(errors, "APPLY_FAILED", f"{m['path']}: {r.stderr.strip()[-500:]}"); return applied
        applied.append(m["path"])
    for ext in prof.get("dependencies", {}).get("extensions", []):
        r = psql(dsn, ["-tA", "-v", f"v={ext}"], "select 1 from pg_extension where extname = :'v';\n")
        if r.stdout.strip() != "1":
            err(errors, "EXTENSION_MISSING", ext)
    for t in prof.get("post_checks", {}).get("tables", []):
        r = psql(dsn, ["-tA", "-v", f"v={t}"], "select to_regclass(:'v') is not null;\n")
        if r.stdout.strip() != "t":
            err(errors, "POSTCHECK_FAILED", t)
    return applied


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--profile", default="fixtures/install_profiles/minimal_portable.json")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--dsn-env", default="DATABASE_URL")
    ap.add_argument("--receipt")
    a = ap.parse_args()
    root = Path(a.root).resolve()
    out = {"ok": False, "profile": a.profile, "errors": []}
    try:
        prof = json.loads((root / a.profile).read_text())
    except Exception as e:
        out["errors"].append({"code": "PROFILE_INVALID", "detail": str(e)})
        print(json.dumps(out, indent=2)); return 1
    out["profile_id"] = prof.get("profile_id") if isinstance(prof, dict) else None
    try:
        errors, files = check_static(root, prof)
    except Exception as e:  # fail closed: never a traceback
        out["errors"] = [{"code": "PROFILE_INVALID", "detail": f"{type(e).__name__}: {e}"}]
        print(json.dumps(out, indent=2)); return 1
    out["files"] = files
    if not errors and a.apply:
        dsn = os.environ.get(a.dsn_env)
        if not dsn:
            err(errors, "DSN_MISSING", f"env {a.dsn_env} not set")
        else:
            out["applied"] = apply(root, prof, dsn, errors)
    out["errors"] = errors
    out["mode"] = "apply" if a.apply else "static"
    out["ok"] = not errors
    text = json.dumps(out, indent=2)
    print(text)
    if a.receipt and out["ok"]:  # never write a success receipt on failure
        Path(a.receipt).write_text(text + "\n")
    return 0 if out["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
