#!/usr/bin/env python3
"""Validate (and optionally apply to a disposable DB) a bounded install profile.

Fails closed with JSON errors. The DSN is read from an environment variable
(--dsn-env, default DATABASE_URL); it is never accepted on argv.

--apply runs SQL only after the DSN is shown to be the disposable lab created
for this invocation. A loopback address, a lab-looking database name, or an
environment flag is not that proof. Refusal performs no database operation.
"""
import argparse, hashlib, hmac, json, os, re, secrets, stat, subprocess, sys, urllib.parse
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
DBNAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
LOOPBACK_HOSTS = frozenset({"localhost", "127.0.0.1", "::1", "0.0.0.0"})
LAB_PROOF_ENV = "E02_LAB_PROOF"


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


def _eq(a, b) -> bool:
    if not isinstance(a, str) or not isinstance(b, str):
        return False
    left, right = a.encode(), b.encode()
    if len(left) != len(right):
        return False
    return hmac.compare_digest(left, right)


def _proc_starttime(pid: int) -> str:
    text = Path(f"/proc/{pid}/stat").read_text()
    end = text.rfind(")")
    if end < 0:
        raise OSError("unreadable proc stat")
    return text[end + 2:].split()[19]


def _proc_cmdline(pid: int) -> list:
    raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    return [part.decode() for part in raw.split(b"\0") if part]


class OsView:
    """Filesystem and process view. This object never opens a database."""

    def __init__(self):
        self.ppid = os.getppid()
        self.script_path = str(Path(__file__).resolve().with_name("validate_install_profile.sh"))

    def read_regular(self, path):
        st = os.lstat(path)
        if not stat.S_ISREG(st.st_mode):
            raise OSError("not a regular file")
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read()

    def realpath(self, path):
        return str(Path(path).resolve())

    def cmdline(self, pid):
        return _proc_cmdline(int(pid))

    def starttime(self, pid):
        return _proc_starttime(int(pid))


def _tcp_class(host: str):
    name = host.strip().strip("[]").lower()
    if name in LOOPBACK_HOSTS or name.startswith("127."):
        return "LAB_TARGET_UNRELATED_LOCAL", "loopback address is not this invocation's lab"
    return "LAB_TARGET_REMOTE", "named or remote host"


def _parse_dsn(dsn):
    """Classify a DSN without resolving it and without opening a socket."""
    if not isinstance(dsn, str) or not dsn or any(ch.isspace() or ch == "\x00" for ch in dsn):
        return None, ("LAB_TARGET_MALFORMED", "unusable dsn")
    if "://" not in dsn:
        return None, ("LAB_TARGET_MALFORMED", "unusable dsn")
    try:
        parts = urllib.parse.urlsplit(dsn)
    except ValueError:
        return None, ("LAB_TARGET_MALFORMED", "unusable dsn")
    if parts.scheme not in {"postgresql", "postgres"}:
        return None, ("LAB_TARGET_MALFORMED", "unusable dsn")
    try:
        query = urllib.parse.parse_qs(parts.query, keep_blank_values=True, strict_parsing=True)
    except ValueError:
        return None, ("LAB_TARGET_MALFORMED", "unusable dsn")
    if "hostaddr" in query:
        values = query.get("hostaddr") or [""]
        return None, _tcp_class(values[0] if values else "")
    if any(key not in {"host", "port"} for key in query) or any(len(values) != 1 for values in query.values()):
        return None, ("LAB_TARGET_MALFORMED", "unusable dsn")
    net_host = parts.hostname
    query_host = query.get("host", [None])[0]
    if net_host and query_host:
        return None, ("LAB_TARGET_MALFORMED", "unusable dsn")
    host = net_host or query_host
    if not host:
        return None, ("LAB_TARGET_MALFORMED", "unusable dsn")
    if not host.startswith("/"):
        return None, _tcp_class(host)
    dbname = parts.path[1:] if parts.path.startswith("/") else parts.path
    if not DBNAME_RE.fullmatch(dbname or ""):
        return None, ("LAB_TARGET_MALFORMED", "unusable dsn")
    port_text = query.get("port", [None])[0]
    if parts.port and port_text:
        return None, ("LAB_TARGET_MALFORMED", "unusable dsn")
    if parts.port and not query_host:
        return None, ("LAB_TARGET_MALFORMED", "unusable dsn")
    port_text = port_text or (str(parts.port) if parts.port else None)
    if not port_text or not port_text.isdigit() or port_text != str(int(port_text)):
        return None, ("LAB_TARGET_MALFORMED", "unusable dsn")
    port = int(port_text)
    if not 1 <= port <= 65535:
        return None, ("LAB_TARGET_MALFORMED", "unusable dsn")
    if parts.password or parts.username != "postgres":
        return None, ("LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab")
    return {"host": host, "port": port, "dbname": dbname}, None


def _parent_is_lab_script(view) -> bool:
    try:
        args = view.cmdline(view.ppid)
    except OSError:
        return False
    script = view.script_path
    for arg in args:
        try:
            if str(Path(arg).resolve()) == script:
                return True
        except OSError:
            continue
    return False


def _proof_matches_postmaster(proof, view):
    """Return an error pair, or None when the proof describes that live postmaster."""
    try:
        data_dir = view.realpath(proof["data_dir"])
        socket_dir = view.realpath(proof["socket_dir"])
        pid_text = view.read_regular(str(Path(data_dir) / "postmaster.pid"))
        nonce = view.read_regular(str(Path(data_dir) / "e02_invocation")).strip()
        cmdline = view.cmdline(proof["postmaster_pid"])
    except (OSError, KeyError, TypeError, ValueError):
        return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    lines = pid_text.splitlines()
    if len(lines) < 6:
        return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    try:
        if int(lines[0]) != int(proof["postmaster_pid"]):
            return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
        if int(lines[3]) != int(proof["port"]):
            return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    except (TypeError, ValueError):
        return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    if view.realpath(lines[1]) != data_dir or view.realpath(lines[4]) != socket_dir:
        return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    if lines[5] != "" or str(lines[2]) != str(proof["postmaster_start"]):
        return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    if not _eq(nonce, str(proof.get("nonce", ""))):
        return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    if Path(data_dir).parent != Path(socket_dir):
        return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    expected = {
        "-D": data_dir,
        "-k": socket_dir,
        "-p": str(int(proof["port"])),
    }
    seen = {}
    for index, arg in enumerate(cmdline[:-1]):
        if arg in expected:
            try:
                seen[arg] = view.realpath(cmdline[index + 1]) if arg in {"-D", "-k"} else cmdline[index + 1]
            except OSError:
                return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    if seen != expected or "listen_addresses=" not in cmdline:
        return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    if not cmdline or not cmdline[0].endswith("/postgres"):
        return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    return None


def assess_apply_target(dsn, proof_path, view):
    """Return (code, detail) or (None, None). Never opens a database connection.

    Caller-supplied flags are ignored. Only a unix-socket DSN whose live
    postmaster is the lab process created by this invocation's lab script matches.
    """
    parsed, failure = _parse_dsn(dsn)
    if failure:
        return failure
    if not proof_path:
        return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    try:
        proof_real = view.realpath(proof_path)
        proof = json.loads(view.read_regular(proof_path))
        socket_dir = view.realpath(proof["socket_dir"])
        if proof_real != str(Path(socket_dir) / "invocation.json"):
            return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
        if view.realpath(parsed["host"]) != socket_dir or int(parsed["port"]) != int(proof["port"]):
            return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
        databases = proof["databases"]
        if not isinstance(databases, list) or parsed["dbname"] not in databases:
            return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
        if any(not isinstance(name, str) or not DBNAME_RE.fullmatch(name) for name in databases):
            return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
        return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    postmaster = _proof_matches_postmaster(proof, view)
    if postmaster:
        return postmaster
    try:
        same_creator = (
            int(view.ppid) == int(proof["creator_pid"])
            and _eq(view.starttime(view.ppid), str(proof["creator_starttime"]))
            and _parent_is_lab_script(view)
        )
    except (OSError, KeyError, TypeError, ValueError):
        same_creator = False
    if not same_creator:
        return "LAB_TARGET_STALE", "lab process does not match this invocation"
    return None, None


def _write_private(path: Path, text: str):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)


def write_invocation_proof(proof_path, data_dir, socket_dir, port, database, creator_pid):
    """Record the lab this process's parent just created. Does not connect."""
    if os.getppid() != int(creator_pid):
        raise SystemExit(1)
    data = Path(data_dir).resolve()
    socket = Path(socket_dir).resolve()
    if data.parent != socket or not DBNAME_RE.fullmatch(database):
        raise SystemExit(1)
    lines = (data / "postmaster.pid").read_text().splitlines()
    if len(lines) < 6 or lines[5] != "":
        raise SystemExit(1)
    if Path(lines[1]).resolve() != data or Path(lines[4]).resolve() != socket or int(lines[3]) != int(port):
        raise SystemExit(1)
    cmdline = _proc_cmdline(int(lines[0]))
    if "listen_addresses=" not in cmdline or not cmdline[0].endswith("/postgres"):
        raise SystemExit(1)
    nonce = secrets.token_hex(32)
    _write_private(data / "e02_invocation", nonce + "\n")
    proof = {
        "nonce": nonce,
        "creator_pid": int(creator_pid),
        "creator_starttime": _proc_starttime(int(creator_pid)),
        "data_dir": str(data),
        "socket_dir": str(socket),
        "port": int(port),
        "postmaster_pid": int(lines[0]),
        "postmaster_start": str(lines[2]),
        "databases": [database],
    }
    destination = Path(proof_path)
    if destination.resolve().parent != socket or destination.name != "invocation.json":
        raise SystemExit(1)
    _write_private(destination, json.dumps(proof) + "\n")


def psql(dsn, args, stdin=None):
    return subprocess.run(["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", dsn, *args],
                          input=stdin, capture_output=True, text=True)


def apply(root, prof, dsn, errors, proof_path=None, view=None, gateway=None):
    applied = []
    code, detail = assess_apply_target(dsn, proof_path, view or OsView())
    if code:
        err(errors, code, detail)
        return applied
    gateway = gateway or psql
    r = gateway(dsn, [], SHIM_SQL)
    if r.returncode:
        err(errors, "LAB_SHIM_FAILED", r.stderr.strip()[-500:]); return applied
    for m in prof["migrations"]:
        r = gateway(dsn, ["-1", "-f", str(root / m["path"])])
        if r.returncode:
            err(errors, "APPLY_FAILED", f"{m['path']}: {r.stderr.strip()[-500:]}"); return applied
        applied.append(m["path"])
    for ext in prof.get("dependencies", {}).get("extensions", []):
        r = gateway(dsn, ["-tA", "-v", f"v={ext}"], "select 1 from pg_extension where extname = :'v';\n")
        if r.stdout.strip() != "1":
            err(errors, "EXTENSION_MISSING", ext)
    for t in prof.get("post_checks", {}).get("tables", []):
        r = gateway(dsn, ["-tA", "-v", f"v={t}"], "select to_regclass(:'v') is not null;\n")
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
            out["applied"] = apply(root, prof, dsn, errors, os.environ.get(LAB_PROOF_ENV))
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
