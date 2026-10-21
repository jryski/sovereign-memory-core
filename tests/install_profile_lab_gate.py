#!/usr/bin/env python3
"""Refusal tests for the disposable-lab apply boundary.

Synthetic DSNs and an in-process gateway only. These tests must not open a
database connection. The older 20/20 lab runner does not cover inherited PG*
variables, socket identity, argv spoofing, URL fragments, or malformed ports.
tests/install_profile_lab_boundary.py covers the cluster cases.
"""
import contextlib, importlib.util, io, json, os, subprocess, sys, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "validate_install_profile.py"
spec = importlib.util.spec_from_file_location("validate_install_profile", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

REPORT = []


class Result:
    def __init__(self, code, out="", err=""):
        self.returncode = code
        self.stdout = out
        self.stderr = err


class Gateway:
    def __init__(self, results=None):
        self.operations = 0
        self.calls = []
        self.results = list(results or [])

    def __call__(self, dsn, args, stdin=None):
        self.operations += 1
        self.calls.append((dsn, tuple(args), stdin))
        if self.results:
            return self.results.pop(0)
        raise AssertionError("database operation")


class FakeView:
    def __init__(self):
        self.files = {}
        self.symlinks = set()
        self.cmds = {}
        self.starts = {}
        self.exes = {}
        self.ppid = 10
        self.script_path = "/invocation/validate_install_profile.sh"
        self.socket_ok = False
        self.database_operations = 0

    def read_regular(self, path):
        if path in self.symlinks:
            raise OSError("symlink")
        if path not in self.files:
            raise OSError("missing")
        return self.files[path]

    def realpath(self, path):
        return str(path)

    def cmdline(self, pid):
        if int(pid) not in self.cmds:
            raise OSError("no process")
        return list(self.cmds[int(pid)])

    def starttime(self, pid):
        if int(pid) not in self.starts:
            raise OSError("no process")
        return self.starts[int(pid)]

    def exe(self, pid):
        if int(pid) not in self.exes:
            raise OSError("no process")
        return self.exes[int(pid)]

    def socket_bound(self, socket_dir, port, pid):
        return bool(self.socket_ok)


def live_lab(database="e02_pos", creator_start="100"):
    socket = "/invocation/lab"
    data = socket + "/data"
    view = FakeView()
    nonce = "ab" * 32
    view.starts[10] = creator_start
    view.cmds[10] = ["bash", view.script_path]
    view.exes[10] = "/usr/bin/bash"
    view.exes[50] = "/usr/lib/postgresql/16/bin/postgres"
    view.socket_ok = True
    view.cmds[50] = [
        "/usr/lib/postgresql/16/bin/postgres",
        "-D", data, "-p", "55432", "-k", socket, "-c", "listen_addresses=",
        "-c", f"e02.invocation={nonce}",
    ]
    view.files[data + "/postmaster.pid"] = "\n".join([
        "50", data, "1700000000", "55432", socket, "", "1 2",
    ]) + "\n"
    view.files[data + "/e02_invocation"] = "ab" * 32 + "\n"
    proof = {
        "nonce": "ab" * 32,
        "creator_pid": 10,
        "creator_starttime": "100",
        "data_dir": data,
        "socket_dir": socket,
        "port": 55432,
        "postmaster_pid": 50,
        "postmaster_start": "1700000000",
        "databases": [database],
    }
    view.files[socket + "/invocation.json"] = json.dumps(proof)
    dsn = f"postgresql://postgres@/{database}?host={socket}&port=55432"
    return view, dsn, socket + "/invocation.json"


def note(name, code, operations, ok):
    REPORT.append({"name": name, "code": code, "database_operations": operations, "ok": ok})


class LabGateTests(unittest.TestCase):
    def check(self, name, dsn, code, view=None, proof=None, flag=False):
        gateway = Gateway()
        if flag:
            os.environ["E02_LAB_OK"] = "1"
        else:
            os.environ.pop("E02_LAB_OK", None)
        errors = []
        try:
            mod.apply(ROOT, {"migrations": []}, dsn, errors, proof, view or FakeView(), gateway)
        finally:
            os.environ.pop("E02_LAB_OK", None)
        self.assertEqual(gateway.operations, 0, name)
        self.assertTrue(errors, name)
        self.assertEqual(errors[0]["code"], code, errors)
        if dsn:
            self.assertNotIn(dsn, errors[0]["detail"])
        note(name, errors[0]["code"], gateway.operations, True)

    def test_remote(self):
        self.check("remote", "postgresql://postgres@db.example.invalid:5432/app", "LAB_TARGET_REMOTE")

    def test_remote_ignores_caller_flag(self):
        self.check("remote-flag", "postgresql://postgres@db.example.invalid:5432/app", "LAB_TARGET_REMOTE", flag=True)

    def test_malformed_keyword_form(self):
        self.check("malformed-keyword", "host=127.0.0.1 dbname=e02_pos", "LAB_TARGET_MALFORMED")

    def test_malformed_empty(self):
        self.check("malformed-empty", "", "LAB_TARGET_MALFORMED")

    def test_malformed_no_host(self):
        self.check("malformed-no-host", "postgresql://postgres@/e02_pos", "LAB_TARGET_MALFORMED")

    def test_loopback_with_lab_looking_name(self):
        self.check(
            "loopback-lab-name",
            "postgresql://postgres@127.0.0.1:5432/e02_pos",
            "LAB_TARGET_UNRELATED_LOCAL",
            flag=True,
        )

    def test_localhost_name(self):
        self.check("localhost", "postgresql://postgres@localhost:5432/e02_pos", "LAB_TARGET_UNRELATED_LOCAL")

    def test_ipv6_loopback(self):
        self.check("ipv6-loopback", "postgresql://postgres@[::1]:5432/e02_pos", "LAB_TARGET_UNRELATED_LOCAL")

    def test_hostaddr_does_not_bypass(self):
        self.check(
            "hostaddr",
            "postgresql://postgres@/e02_pos?host=/invocation/lab&port=55432&hostaddr=127.0.0.1",
            "LAB_TARGET_UNRELATED_LOCAL",
        )

    def test_unix_socket_without_proof(self):
        self.check(
            "unix-no-proof",
            "postgresql://postgres@/e02_pos?host=/var/run/postgresql&port=5432",
            "LAB_TARGET_UNRELATED_LOCAL",
            flag=True,
        )

    def test_proof_for_other_socket(self):
        view, _dsn, proof = live_lab()
        self.check(
            "other-socket",
            "postgresql://postgres@/e02_pos?host=/var/run/postgresql&port=5432",
            "LAB_TARGET_UNRELATED_LOCAL",
            view=view,
            proof=proof,
        )

    def test_allow_flag_file_is_not_proof(self):
        view = FakeView()
        view.files["/tmp/flag.json"] = '{"allow": true}'
        self.check(
            "flag-file",
            "postgresql://postgres@/e02_pos?host=/tmp&port=5432",
            "LAB_TARGET_UNRELATED_LOCAL",
            view=view,
            proof="/tmp/flag.json",
            flag=True,
        )

    def test_stale_creator(self):
        view, dsn, proof = live_lab()
        view.starts[10] = "999"
        self.check("stale-lab", dsn, "LAB_TARGET_STALE", view=view, proof=proof)

    def test_stale_parent_is_not_lab_script(self):
        view, dsn, proof = live_lab()
        view.cmds[10] = ["bash"]
        self.check("stale-parent", dsn, "LAB_TARGET_STALE", view=view, proof=proof)

    def test_argv_spoof_does_not_match_invocation(self):
        view, dsn, proof = live_lab()
        view.cmds[10] = ["bash", "-c", "driver", view.script_path]
        view.exes[10] = "/usr/bin/bash"
        self.check("m2-argv-spoof", dsn, "LAB_TARGET_STALE", view=view, proof=proof)

    def test_symlink_socket_is_not_the_lab(self):
        view, dsn, proof = live_lab()
        view.socket_ok = False
        self.check("m1-socket-not-held", dsn, "LAB_TARGET_UNRELATED_LOCAL", view=view, proof=proof)

    def test_fake_postgres_exe_is_rejected(self):
        view, dsn, proof = live_lab()
        view.exes[50] = "/usr/bin/python3"
        view.cmds[50][0] = "/fake/bin/postgres"
        self.check("m1-fake-exe", dsn, "LAB_TARGET_UNRELATED_LOCAL", view=view, proof=proof)

    def test_session_mismatch_stops_before_shim(self):
        view, dsn, proof = live_lab()
        gateway = Gateway([Result(0, out="other|/somewhere/data\n")])
        errors = []
        mod.apply(ROOT, {"migrations": []}, dsn, errors, proof, view, gateway)
        self.assertEqual(gateway.operations, 1)
        self.assertEqual(errors[0]["code"], "LAB_SESSION_MISMATCH")
        self.assertTrue(all(call[2] is None or "create schema" not in (call[2] or "") for call in gateway.calls))
        note("session-mismatch", errors[0]["code"], gateway.operations, True)

    def test_gate_opens_only_for_matching_invocation(self):
        view, dsn, proof = live_lab()
        nonce = "ab" * 32
        gateway = Gateway([
            Result(0, out=f"{nonce}|/invocation/lab/data\n"),
            Result(1, err="stopped"),
        ])
        errors = []
        mod.apply(ROOT, {"migrations": []}, dsn, errors, proof, view, gateway)
        self.assertEqual(gateway.operations, 2)
        self.assertIn("current_setting", gateway.calls[0][2])
        self.assertEqual(gateway.calls[0][0], mod.pinned_conninfo("/invocation/lab", 55432, "e02_pos"))
        self.assertNotIn("postgresql://", gateway.calls[0][0])
        self.assertNotIn("#", gateway.calls[0][0])
        self.assertEqual(errors[0]["code"], "LAB_SHIM_FAILED")
        note("matching-invocation-opens-gateway", "LAB_SHIM_FAILED", gateway.operations, True)

    def test_fragment_cannot_add_hostaddr_to_a_matching_lab(self):
        view, _dsn, proof = live_lab()
        dsn = (
            "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab"
            "#&hostaddr=203.0.113.10&host=/invocation/lab"
        )
        self.check("fragment-hostaddr", dsn, "LAB_TARGET_MALFORMED", view=view, proof=proof)

    def test_encoded_hash_cannot_smuggle_parameters(self):
        view, _dsn, proof = live_lab()
        dsn = "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab%23&hostaddr=203.0.113.10"
        self.check("encoded-fragment", dsn, "LAB_TARGET_MALFORMED", view=view, proof=proof)

    def test_bad_authority_port_is_malformed_without_connecting(self):
        self.check(
            "authority-port",
            "postgresql://postgres@:bad/e02_pos?host=/invocation/lab",
            "LAB_TARGET_MALFORMED",
        )

    def test_superscript_query_port_is_malformed_without_connecting(self):
        self.check(
            "superscript-port",
            "postgresql://postgres@/e02_pos?host=/invocation/lab&port=\u00b2",
            "LAB_TARGET_MALFORMED",
        )

    def test_main_writes_a_receipt_only_when_ok(self):
        """Production main() decides the receipt. This does not reimplement that condition."""
        with tempfile.TemporaryDirectory() as tmp:
            fail_receipt = Path(tmp) / "fail.json"
            ok_receipt = Path(tmp) / "ok.json"
            calls = []
            original = mod.subprocess.run

            def trap(*_args, **_kwargs):
                calls.append(1)
                raise AssertionError("database operation")

            mod.subprocess.run = trap
            argv = sys.argv
            saved = {key: os.environ.get(key) for key in ("DATABASE_URL", "E02_LAB_PROOF", "PGHOSTADDR")}
            try:
                os.environ["DATABASE_URL"] = "postgresql://postgres@:bad/e02_pos?host=/invocation/lab"
                os.environ["PGHOSTADDR"] = "203.0.113.10"
                os.environ.pop("E02_LAB_PROOF", None)
                sys.argv = [str(SCRIPT), "--root", str(ROOT), "--apply", "--receipt", str(fail_receipt)]
                stdout = io.StringIO()
                with contextlib.redirect_stdout(stdout):
                    rc = mod.main()
                self.assertEqual(rc, 1)
                self.assertFalse(fail_receipt.exists())
                body = json.loads(stdout.getvalue())
                self.assertEqual(body["errors"][0]["code"], "LAB_TARGET_MALFORMED")
                self.assertNotIn("Traceback", stdout.getvalue())
                note("main-bad-port-no-receipt", body["errors"][0]["code"], len(calls), True)

                os.environ.pop("DATABASE_URL", None)
                os.environ.pop("PGHOSTADDR", None)
                sys.argv = [str(SCRIPT), "--root", str(ROOT), "--receipt", str(ok_receipt)]
                stdout = io.StringIO()
                with contextlib.redirect_stdout(stdout):
                    rc = mod.main()
                printed = json.loads(stdout.getvalue())
                self.assertEqual(rc, 0)
                self.assertTrue(ok_receipt.is_file())
                self.assertEqual(json.loads(ok_receipt.read_text()), printed)
                self.assertTrue(printed["ok"])
                note("main-static-receipt", "ok", len(calls), True)
            finally:
                mod.subprocess.run = original
                sys.argv = argv
                for key, value in saved.items():
                    if value is None:
                        os.environ.pop(key, None)
                    else:
                        os.environ[key] = value
        self.assertEqual(calls, [])

    def test_each_pg_variable_is_removed_from_the_client_environment(self):
        names = [
            "PGHOSTADDR", "PGSERVICE", "PGSERVICEFILE", "PGHOST", "PGPORT",
            "PGDATABASE", "PGUSER", "PGPASSFILE", "PGPASSWORD", "PGSSLMODE",
            "PGSSLCERT", "PGSSLKEY", "PGSSLROOTCERT", "PGSSLCRL", "PGOPTIONS",
            "PGTARGETSESSIONATTRS", "PGAPPNAME", "PGREQUIREAUTH", "PGCHANNELBINDING",
            "PGCONNECT_TIMEOUT", "PGREALM", "PGKRBSRVNAME", "PGPASSFILE",
        ]
        captured = {}

        def fake_run(cmd, **kwargs):
            captured["cmd"] = cmd
            captured["env"] = kwargs.get("env") or {}
            return Result(0, out="")

        original = mod.subprocess.run
        mod.subprocess.run = fake_run
        try:
            for name in names:
                os.environ[name] = "synthetic-value"
                mod.psql("host=/invocation/lab port=55432 dbname=postgres user=postgres hostaddr=''", ["-c", "select 1"])
                self.assertTrue(captured["env"], name)
                self.assertFalse(any(key.startswith("PG") for key in captured["env"]), name)
                self.assertNotIn(name, captured["env"], name)
                note(f"pg-scrub-{name}", "scrubbed", 0, True)
                del os.environ[name]
        finally:
            mod.subprocess.run = original
            for name in names:
                os.environ.pop(name, None)

    def test_encoded_host_is_refused_before_the_gateway(self):
        """A collapsing realpath must not turn the decoded host into a conninfo keyword."""
        vectors = [
            ("encoded-space-host", "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab/junk%20host=203.0.113.10%20application_name=x/.."),
            ("encoded-tab-host", "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab/junk%09x/.."),
            ("encoded-newline-host", "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab/junk%0ax/.."),
            ("encoded-quote-host", "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab/junk%27x"),
            ("encoded-backslash-host", "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab/junk%5cx"),
            ("encoded-equals-host", "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab/junk%3dhostaddr"),
        ]
        for name, dsn in vectors:
            view, _dsn, proof = live_lab()
            view.realpath = lambda path: str(Path(path).resolve())
            self.check(name, dsn, "LAB_TARGET_MALFORMED", view=view, proof=proof)
        safe = mod.pinned_conninfo("/invocation/lab", 55432, "e02_pos")
        self.assertNotIn("203.0.113.10", safe)
        parsed = _pq_parse(safe)
        self.assertEqual(parsed.get("host"), "/invocation/lab")
        self.assertFalse(parsed.get("hostaddr"))
        injected = _pq_parse(
            "host=/invocation/lab/junk host=203.0.113.10 application_name=x/.. "
            "port=55432 dbname=e02_pos user=postgres hostaddr=''"
        )
        self.assertEqual(injected.get("host"), "203.0.113.10")

    def test_boundary_unexpected_exception_still_cleans_up(self):
        env = os.environ.copy()
        env["E02_BOUNDARY_RAISE"] = "1"
        proc = subprocess.run(
            [sys.executable, str(ROOT / "tests" / "install_profile_lab_boundary.py")],
            env=env, text=True, capture_output=True, check=False,
        )
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn("unexpected=RuntimeError", proc.stdout)
        self.assertIn("work_left=0", proc.stdout)
        self.assertIn("clusters_alive=0", proc.stdout)
        self.assertFalse(Path("/tmp/e02-boundary").exists())
        note("boundary-unexpected", "RuntimeError", 0, True)

    def test_shell_scrubs_libpq_env_before_setup_and_cleanup(self):
        text = (ROOT / "scripts" / "validate_install_profile.sh").read_text()
        for line in text.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if any(tool in stripped for tool in ("$PGBIN/createdb", "$PGBIN/dropdb", "$PGBIN/psql")):
                self.assertIn("client ", stripped, stripped)
        self.assertIn("scrub_libpq", _bash_function("cleanup", text))

        names = [
            "PGHOSTADDR", "PGSERVICE", "PGSERVICEFILE", "PGHOST", "PGPORT",
            "PGDATABASE", "PGUSER", "PGPASSFILE", "PGPASSWORD", "PGSSLMODE",
            "PGSSLCERT", "PGSSLKEY", "PGSSLROOTCERT", "PGSSLCRL", "PGOPTIONS",
            "PGTARGETSESSIONATTRS", "PGAPPNAME", "PGREQUIREAUTH", "PGCHANNELBINDING",
            "PGCONNECT_TIMEOUT", "PGREALM", "PGKRBSRVNAME",
        ]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bindir = root / "bin"
            bindir.mkdir()
            log = root / "calls.log"
            recorder = root / "record.py"
            recorder.write_text(
                "import json, os, sys\n"
                "seen = {k: os.environ[k] for k in os.environ if k.startswith('PG')}\n"
                f"open({str(log)!r}, 'a').write(json.dumps({{'tool': sys.argv[1], 'pg': seen}}) + '\\n')\n"
            )
            for tool in ("createdb", "dropdb", "psql", "pg_ctl"):
                path = bindir / tool
                path.write_text(f"#!/bin/sh\nexec python3 {recorder} {tool}\n")
                path.chmod(0o755)
            functions = "\n".join(_bash_function(name, text) for name in ("scrub_libpq", "client", "cleanup"))
            lab = root / "lab"
            (lab / "data").mkdir(parents=True)
            (lab / "data" / "postmaster.pid").write_text("999999\n")
            exports = "\n".join(f"export {name}=synthetic-value" for name in names)
            script = "\n".join([
                "set -euo pipefail",
                exports,
                functions,
                f"PGBIN={bindir}",
                f"LAB={lab}",
                "OUT_TMP=",
                "KEEP_OUT=0",
                f"OUT={root / 'out'}",
                'mkdir -p "$OUT"',
                'client "$PGBIN/createdb" -h /invocation/lab -p 1 -U postgres e02_pos',
                'client "$PGBIN/dropdb" -h /invocation/lab -p 1 -U postgres --if-exists e02_pos',
                'client "$PGBIN/psql" -X -tA -h /invocation/lab -p 1 -U postgres -d postgres -c select',
                "cleanup",
            ])
            proc = subprocess.run(["bash", "-c", script], text=True, capture_output=True, check=False)
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
            rows = [json.loads(line) for line in log.read_text().splitlines()]
            tools = [row["tool"] for row in rows]
            self.assertEqual(tools, ["createdb", "dropdb", "psql", "pg_ctl"])
            for row in rows:
                self.assertEqual(row["pg"], {}, row["tool"])
                note(f"shell-scrub-{row['tool']}", "scrubbed", 0, True)

    def test_cli_refusals_do_not_invoke_psql_or_write_receipt(self):
        cases = [
            ("cli-remote", "postgresql://postgres@db.example.invalid:5432/app", "LAB_TARGET_REMOTE", None),
            ("cli-malformed", "host=localhost dbname=e02_pos", "LAB_TARGET_MALFORMED", None),
            ("cli-loopback-lab-name", "postgresql://postgres@127.0.0.1:5432/e02_pos", "LAB_TARGET_UNRELATED_LOCAL", None),
            ("cli-unix-unrelated", "postgresql://postgres@/e02_pos?host=/var/run/postgresql&port=5432", "LAB_TARGET_UNRELATED_LOCAL", None),
            ("cli-fragment-hostaddr", "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab#&hostaddr=203.0.113.10&host=/invocation/lab", "LAB_TARGET_MALFORMED", None),
            ("cli-authority-port", "postgresql://postgres@:bad/e02_pos?host=/invocation/lab", "LAB_TARGET_MALFORMED", None),
            ("cli-superscript-port", "postgresql://postgres@/e02_pos?host=/invocation/lab&port=\u00b2", "LAB_TARGET_MALFORMED", None),
            ("cli-encoded-space-host", "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab/junk%20host=203.0.113.10%20application_name=x/..", "LAB_TARGET_MALFORMED", None),
            ("cli-encoded-tab-host", "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab/junk%09x/..", "LAB_TARGET_MALFORMED", None),
            ("cli-encoded-newline-host", "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab/junk%0ax/..", "LAB_TARGET_MALFORMED", None),
            ("cli-encoded-quote-host", "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab/junk%27x", "LAB_TARGET_MALFORMED", None),
            ("cli-encoded-backslash-host", "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab/junk%5cx", "LAB_TARGET_MALFORMED", None),
            ("cli-encoded-equals-host", "postgresql://postgres@/e02_pos?port=55432&host=/invocation/lab/junk%3dhostaddr", "LAB_TARGET_MALFORMED", None),
        ]
        with tempfile.TemporaryDirectory() as tmp:
            stub_dir = Path(tmp) / "bin"
            stub_dir.mkdir()
            stub = stub_dir / "psql"
            stub.write_text("#!/bin/sh\nprintf '%s\\n' called >> \"$E02_STUB_LOG\"\nexit 0\n")
            stub.chmod(0o755)
            for name, dsn, code, proof in cases:
                log = Path(tmp) / (name + ".log")
                receipt = Path(tmp) / (name + ".receipt")
                env = os.environ.copy()
                env["PATH"] = str(stub_dir) + os.pathsep + env.get("PATH", "")
                env["DATABASE_URL"] = dsn
                env["E02_LAB_OK"] = "1"
                env["E02_STUB_LOG"] = str(log)
                env["PGHOSTADDR"] = "203.0.113.10"
                env["PGSERVICE"] = "labsvc"
                env["PGSERVICEFILE"] = str(Path(tmp) / "services.conf")
                env.pop("E02_LAB_PROOF", None)
                if proof:
                    env["E02_LAB_PROOF"] = proof
                proc = subprocess.run(
                    [sys.executable, str(SCRIPT), "--root", str(ROOT), "--apply", "--receipt", str(receipt)],
                    env=env, text=True, capture_output=True, check=False,
                )
                self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
                self.assertNotIn("Traceback", proc.stderr)
                body = json.loads(proc.stdout)
                self.assertFalse(body["ok"])
                self.assertEqual(body["errors"][0]["code"], code, body)
                self.assertFalse(receipt.exists(), name)
                operations = len(log.read_text().splitlines()) if log.exists() else 0
                self.assertEqual(operations, 0, name)
                note(name, code, operations, True)


def _pq_parse(conninfo):
    """Read keyword values with PQconninfoParse. This does not connect."""
    import ctypes, glob
    library = next(iter(glob.glob("/usr/lib/*/libpq.so.5") + glob.glob("/usr/lib/libpq.so.5")), None)
    if library is None:
        raise AssertionError("libpq is not available for a no-connection parse")

    class Option(ctypes.Structure):
        _fields_ = [
            ("keyword", ctypes.c_char_p), ("envvar", ctypes.c_char_p),
            ("compiled", ctypes.c_char_p), ("val", ctypes.c_char_p),
            ("label", ctypes.c_char_p), ("dispchar", ctypes.c_char_p),
            ("dispsize", ctypes.c_int),
        ]

    lib = ctypes.CDLL(library)
    lib.PQconninfoParse.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p)]
    lib.PQconninfoParse.restype = ctypes.POINTER(Option)
    lib.PQconninfoFree.argtypes = [ctypes.POINTER(Option)]
    error = ctypes.c_char_p()
    options = lib.PQconninfoParse(conninfo.encode(), ctypes.byref(error))
    if error.value:
        message = error.value.decode()
        lib.PQfreemem(error)
        raise AssertionError(message)
    found = {}
    index = 0
    while options[index].keyword:
        if options[index].val:
            found[options[index].keyword.decode()] = options[index].val.decode()
        index += 1
    lib.PQconninfoFree(options)
    return found


def _bash_function(name, text):
    lines = text.splitlines()
    start = next(index for index, line in enumerate(lines) if line.startswith(name + "()"))
    if lines[start].count("{") == lines[start].count("}") and lines[start].rstrip().endswith("}"):
        return lines[start]
    body = [lines[start]]
    for line in lines[start + 1:]:
        body.append(line)
        if line == "}":
            return "\n".join(body)
    raise AssertionError(f"unclosed function {name}")


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    print("LAB_GATE_SUMMARY")
    for row in REPORT:
        print(f"{row['name']} code={row['code']} database_operations={row['database_operations']} ok={row['ok']}")
    ran = {row["name"] for row in REPORT}
    print(f"recorded={len(REPORT)} failed_tests={len(result.failures) + len(result.errors)}")
    sys.exit(0 if result.wasSuccessful() else 1)
