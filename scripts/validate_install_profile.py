#!/usr/bin/env python3
"""Validate (and optionally apply to a disposable DB) a bounded install profile.

Fails closed with JSON errors. The DSN is read from an environment variable
(--dsn-env, default DATABASE_URL); it is never accepted on argv.

--apply runs SQL only after the DSN is shown to be the disposable lab created
for this invocation. A loopback address, a lab-looking database name, an
environment flag, an inherited PG* variable, or a URL fragment is not that
proof. Fragments and other syntax this checker does not validate are rejected:
libpq reads them even when url parsing does not. A decoded host that contains
whitespace, '=', quotes, a backslash, or a '.' or '..' segment is rejected
before any database gateway. Client tools run with every PG* variable removed.
The connection string is built from the lab directory recorded for this
invocation, with each value quoted, and not from the decoded host text. The
original DSN is not passed through. The parent-process check is a same-user
guard only: it accepts bash with this script as argv[1], and it does not stop
a different local user or a rewritten script. Refusal performs no database operation and writes no
success receipt. A session probe that does not match this lab's nonce and
data directory stops before the role and privilege preamble.
"""
import argparse, hashlib, hmac, json, os, re, stat, subprocess, sys, urllib.parse
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
SOCKET_DIR_RE = re.compile(r"^/(?:[A-Za-z0-9._-]+)(?:/[A-Za-z0-9._-]+)*$")
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


def _proc_exe(pid: int) -> str:
    target = os.readlink(f"/proc/{int(pid)}/exe")
    suffix = " (deleted)"
    if target.endswith(suffix):
        target = target[:-len(suffix)]
    return target


def _exe_is_postgres(exe: str) -> bool:
    return bool(exe) and Path(exe).name == "postgres"


def _socket_bound(socket_dir, port, pid) -> bool:
    """True when .s.PGSQL.<port> is this user's real socket and that postmaster holds it."""
    directory = Path(socket_dir)
    sock = directory / f".s.PGSQL.{int(port)}"
    try:
        dir_stat = os.lstat(directory)
        sock_stat = os.lstat(sock)
    except OSError:
        return False
    if stat.S_ISLNK(dir_stat.st_mode) or not stat.S_ISDIR(dir_stat.st_mode):
        return False
    if stat.S_ISLNK(sock_stat.st_mode) or not stat.S_ISSOCK(sock_stat.st_mode):
        return False
    if sock_stat.st_uid != os.getuid() or dir_stat.st_uid != os.getuid():
        return False
    if directory.resolve() != Path(socket_dir).resolve():
        return False
    kernel_inode = None
    try:
        with open("/proc/net/unix", encoding="utf-8") as handle:
            next(handle, None)
            for line in handle:
                fields = line.split()
                if len(fields) >= 8 and fields[-1] == str(sock) and fields[6].isdigit():
                    kernel_inode = fields[6]
                    break
    except OSError:
        return False
    if kernel_inode is None:
        return False
    needle = f"socket:[{kernel_inode}]"
    try:
        for entry in Path(f"/proc/{int(pid)}/fd").iterdir():
            try:
                if os.readlink(entry) == needle:
                    return True
            except OSError:
                continue
    except OSError:
        return False
    return False


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

    def exe(self, pid):
        return _proc_exe(int(pid))

    def socket_bound(self, socket_dir, port, pid):
        return _socket_bound(socket_dir, int(port), int(pid))


def _tcp_class(host: str):
    name = host.strip().strip("[]").lower()
    if name in LOOPBACK_HOSTS or name.startswith("127."):
        return "LAB_TARGET_UNRELATED_LOCAL", "loopback address is not this invocation's lab"
    return "LAB_TARGET_REMOTE", "named or remote host"


def _plain_socket_dir(host) -> bool:
    """Absolute lab directory. No conninfo metacharacters and no dot segments.

    This is a character allowlist, not a conninfo parser. Percent-decoding
    happens before this check, so encoded whitespace or '..' cannot hide.
    """
    if not isinstance(host, str) or not SOCKET_DIR_RE.fullmatch(host):
        return False
    return all(part not in {".", ".."} for part in host.split("/"))


def _quote_conninfo(value: str) -> str:
    """Single-quote a value. '\\' and \"'\" are escaped the way libpq reads them."""
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"


def _canonical_port(port_text):
    """Return an integer port, or None. Never raises. ASCII digits only."""
    if not isinstance(port_text, str) or not port_text.isascii() or not port_text.isdigit():
        return None
    try:
        value = int(port_text)
    except ValueError:
        return None
    if str(value) != port_text or not 1 <= value <= 65535:
        return None
    return value


def _parse_dsn(dsn):
    """Classify a DSN without resolving it and without opening a socket.

    A fragment is rejected even when the part before '#' would match a lab.
    libpq parses that fragment as extra connection parameters. A host is
    rejected when its decoded text is not a plain absolute directory. The
    caller connects with pinned_conninfo of the lab directory, not this string.
    """
    malformed = ("LAB_TARGET_MALFORMED", "unusable dsn")
    if not isinstance(dsn, str) or not dsn or any(ch.isspace() or ch == "\x00" for ch in dsn):
        return None, malformed
    if "://" not in dsn or "#" in dsn or "%23" in dsn.lower():
        return None, malformed
    try:
        parts = urllib.parse.urlsplit(dsn)
        query = urllib.parse.parse_qs(parts.query, keep_blank_values=True, strict_parsing=True)
        authority_port = parts.port
        net_host = parts.hostname
        username = parts.username
        password = parts.password
    except ValueError:
        return None, malformed
    if parts.fragment or parts.scheme not in {"postgresql", "postgres"}:
        return None, malformed
    if "hostaddr" in query:
        values = query.get("hostaddr") or [""]
        return None, _tcp_class(values[0] if values else "")
    if any(key not in {"host", "port"} for key in query) or any(len(values) != 1 for values in query.values()):
        return None, malformed
    query_host = query.get("host", [None])[0]
    if net_host and query_host:
        return None, malformed
    host = net_host or query_host
    if not host:
        return None, malformed
    if not host.startswith("/"):
        return None, _tcp_class(host)
    if not _plain_socket_dir(host):
        return None, malformed
    dbname = parts.path[1:] if parts.path.startswith("/") else parts.path
    if not DBNAME_RE.fullmatch(dbname or ""):
        return None, malformed
    port_text = query.get("port", [None])[0]
    if authority_port and port_text:
        return None, malformed
    if authority_port and not query_host:
        return None, malformed
    if port_text is None and authority_port is not None:
        port_text = str(authority_port)
    port = _canonical_port(port_text)
    if port is None:
        return None, malformed
    if password or username != "postgres":
        return None, ("LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab")
    return {"host": host, "port": port, "dbname": dbname}, None


def _resolves_to(arg, script) -> bool:
    try:
        return str(Path(arg).resolve()) == script
    except OSError:
        return False


def _parent_is_lab_script(view) -> bool:
    """Same-user guard only.

    The parent executable must be bash, argv[0] must be bash, and argv[1]
    must be this lab script. Later arguments do not count, so
    bash -c '<driver>' <script> is not this invocation. This check does not
    constrain any other user, and it does not stop someone who can rewrite
    the script itself.
    """
    try:
        args = view.cmdline(view.ppid)
        exe = view.exe(view.ppid)
    except OSError:
        return False
    if not exe or len(args) < 2:
        return False
    if Path(exe).name != "bash" or Path(args[0]).name != "bash":
        return False
    return _resolves_to(args[1], view.script_path)


def _proof_matches_postmaster(proof, view):
    """Return an error pair, or None when the proof describes that live postmaster."""
    try:
        data_dir = view.realpath(proof["data_dir"])
        socket_dir = view.realpath(proof["socket_dir"])
        pid_text = view.read_regular(str(Path(data_dir) / "postmaster.pid"))
        nonce = view.read_regular(str(Path(data_dir) / "e02_invocation")).strip()
        cmdline = view.cmdline(proof["postmaster_pid"])
        exe = view.exe(proof["postmaster_pid"])
        socket_ok = view.socket_bound(socket_dir, proof["port"], proof["postmaster_pid"])
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
    if f"e02.invocation={nonce}" not in cmdline or not _exe_is_postgres(exe) or not socket_ok:
        return "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab"
    return None


def assess_apply_target(dsn, proof_path, view):
    """Return (code, detail) or (None, None). Never opens a database connection.

    Caller-supplied flags are ignored. Only a unix-socket DSN whose live
    postmaster is the lab process created by this invocation's lab script matches.
    The parent check is a same-user guard, not a barrier against other users.
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


def write_invocation_proof(proof_path, data_dir, socket_dir, port, database, creator_pid, nonce):
    """Record the lab this process's parent just created. Does not connect."""
    if os.getppid() != int(creator_pid):
        raise SystemExit(1)
    if not isinstance(nonce, str) or len(nonce) != 64 or any(ch not in "0123456789abcdef" for ch in nonce):
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
    postmaster_pid = int(lines[0])
    cmdline = _proc_cmdline(postmaster_pid)
    if "listen_addresses=" not in cmdline or f"e02.invocation={nonce}" not in cmdline:
        raise SystemExit(1)
    if not _exe_is_postgres(_proc_exe(postmaster_pid)):
        raise SystemExit(1)
    if not _socket_bound(socket, port, postmaster_pid):
        raise SystemExit(1)
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


def client_env(base=None):
    """Environment for libpq clients: every PG* variable removed."""
    source = os.environ if base is None else base
    return {key: value for key, value in source.items() if not key.startswith("PG")}


def pinned_conninfo(socket_dir, port, dbname) -> str:
    """Conninfo for the lab directory created for this invocation.

    socket_dir is that directory's real path, not the decoded DSN host.
    Values are single-quoted so a metacharacter cannot add another keyword.
    """
    if not _plain_socket_dir(socket_dir) or not DBNAME_RE.fullmatch(dbname or ""):
        raise ValueError("unusable conninfo")
    number = _canonical_port(str(port))
    if number is None:
        raise ValueError("unusable conninfo")
    return (
        f"host={_quote_conninfo(socket_dir)} port={number} "
        f"dbname={_quote_conninfo(dbname)} user='postgres' hostaddr=''"
    )


def psql(dsn, args, stdin=None):
    return subprocess.run(
        ["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", dsn, *args],
        input=stdin, capture_output=True, text=True, env=client_env(),
    )


def _session_matches(stdout, nonce, data_dir) -> bool:
    return _eq(stdout.strip(), f"{nonce}|{data_dir}")


def apply(root, prof, dsn, errors, proof_path=None, view=None, gateway=None):
    applied = []
    view = view or OsView()
    code, detail = assess_apply_target(dsn, proof_path, view)
    if code:
        err(errors, code, detail)
        return applied
    parsed, failure = _parse_dsn(dsn)
    if failure:
        err(errors, failure[0], failure[1])
        return applied
    try:
        proof = json.loads(view.read_regular(proof_path))
        nonce = str(proof["nonce"])
        data_dir = view.realpath(proof["data_dir"])
        socket_dir = view.realpath(proof["socket_dir"])
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
        err(errors, "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab")
        return applied
    if not _plain_socket_dir(socket_dir) or socket_dir != view.realpath(parsed["host"]):
        err(errors, "LAB_TARGET_UNRELATED_LOCAL", "not this invocation's lab")
        return applied
    gateway = gateway or psql
    conn = pinned_conninfo(socket_dir, parsed["port"], parsed["dbname"])
    probe = (
        "select current_setting('e02.invocation', true) || '|' || "
        "current_setting('data_directory');\n"
    )
    checked = gateway(conn, ["-tA"], probe)
    if checked.returncode or not _session_matches(checked.stdout, nonce, data_dir):
        err(errors, "LAB_SESSION_MISMATCH", "session is not this invocation's lab")
        return applied
    r = gateway(conn, [], SHIM_SQL)
    if r.returncode:
        err(errors, "LAB_SHIM_FAILED", r.stderr.strip()[-500:]); return applied
    for m in prof["migrations"]:
        r = gateway(conn, ["-1", "-f", str(root / m["path"])])
        if r.returncode:
            err(errors, "APPLY_FAILED", f"{m['path']}: {r.stderr.strip()[-500:]}"); return applied
        applied.append(m["path"])
    for ext in prof.get("dependencies", {}).get("extensions", []):
        r = gateway(conn, ["-tA", "-v", f"v={ext}"], "select 1 from pg_extension where extname = :'v';\n")
        if r.stdout.strip() != "1":
            err(errors, "EXTENSION_MISSING", ext)
    for t in prof.get("post_checks", {}).get("tables", []):
        r = gateway(conn, ["-tA", "-v", f"v={t}"], "select to_regclass(:'v') is not null;\n")
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
