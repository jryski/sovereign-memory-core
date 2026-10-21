#!/usr/bin/env python3
"""Throwaway local-cluster checks for inherited PG*, socket swap, and argv spoof.

The stand-in listens on 127.0.0.1 or its own unix socket. Nothing here dials
a remote or hosted database. The older 20/20 runner does not cover these cases.
"""
import importlib.util, os, shutil, subprocess, sys, textwrap, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PY = ROOT / "scripts" / "validate_install_profile.py"
SH = ROOT / "scripts" / "validate_install_profile.sh"
spec = importlib.util.spec_from_file_location("validate_install_profile", PY)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

PGBIN = sorted(Path("/usr/lib/postgresql").glob("*/bin"))[-1]
PG_NAMES = [
    "PGHOSTADDR", "PGSERVICE", "PGSERVICEFILE", "PGHOST", "PGPORT",
    "PGDATABASE", "PGUSER", "PGPASSFILE", "PGPASSWORD", "PGSSLMODE",
    "PGSSLCERT", "PGSSLKEY", "PGSSLROOTCERT", "PGSSLCRL", "PGOPTIONS",
    "PGTARGETSESSIONATTRS", "PGAPPNAME", "PGREQUIREAUTH", "PGCHANNELBINDING",
    "PGCONNECT_TIMEOUT", "PGREALM", "PGKRBSRVNAME",
]


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=False, text=True, **kwargs)


def start_cluster(directory, port, listen, nonce=None):
    data = directory / "data"
    directory.mkdir(parents=True, exist_ok=True)
    init = run([str(PGBIN / "initdb"), "-D", str(data), "-U", "postgres", "-A", "trust"],
               stdout=subprocess.DEVNULL)
    if init.returncode != 0:
        raise RuntimeError(f"initdb failed for {directory}")
    options = f"-p {port} -k {directory} -c listen_addresses={listen} -c log_connections=on -c log_statement=all"
    if nonce:
        options += f" -c e02.invocation={nonce}"
    started = run(
        [str(PGBIN / "pg_ctl"), "-D", str(data), "-o", options, "-l", str(directory / "log"), "-w", "start"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    if started.returncode != 0:
        log = (directory / "log").read_text(errors="replace") if (directory / "log").exists() else ""
        raise RuntimeError(f"pg_ctl failed for {directory}\n{log}")


def stop_cluster(directory):
    data = directory / "data"
    if data.exists():
        run([str(PGBIN / "pg_ctl"), "-D", str(data), "-m", "immediate", "stop"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def marks(path):
    text = path.read_text(errors="replace") if path.exists() else ""
    return text.count("connection received"), text.count("statement:")


def foreign_roles(socket_dir, port):
    proc = run([
        str(PGBIN / "psql"), "-X", "-tA", "-h", str(socket_dir), "-p", str(port),
        "-U", "postgres", "-d", "postgres", "-c",
        "select count(*) from pg_roles where rolname in ('anon','authenticated','service_role')",
    ], capture_output=True, env=mod.client_env())
    return proc.stdout.strip()


def main():
    work = Path("/tmp/e02-boundary")
    if work.exists():
        shutil.rmtree(work, ignore_errors=True)
    work.mkdir()
    clusters = []
    results = []
    fake_proc = None
    try:
        standin = work / "standin"
        port = 55481
        start_cluster(standin, port, "127.0.0.1")
        clusters.append(standin)

        def runner(label, extra):
            env = os.environ.copy()
            for name in PG_NAMES:
                env.pop(name, None)
            env.update(extra)
            env["OUT_DIR"] = str(work / label)
            env["KEEP_OUT"] = "1"
            env["LAB_PORT"] = str(port)
            return run(["bash", str(SH)], env=env, capture_output=True)

        before = marks(standin / "log")
        inherited = {name: "synthetic-value" for name in PG_NAMES}
        inherited.update({
            "PGHOSTADDR": "127.0.0.1", "PGPORT": str(port), "PGHOST": "127.0.0.1",
            "PGUSER": "postgres", "PGDATABASE": "postgres",
        })
        proc = runner("pghostaddr", inherited)
        delta = tuple(a - b for a, b in zip(marks(standin / "log"), before))
        roles = foreign_roles(standin, port)
        ok = proc.returncode == 0 and delta == (0, 0) and roles == "0"
        results.append(("b1-pghostaddr-and-other-pg", "scrubbed" if ok else "failed", sum(delta), ok, proc.returncode))
        if not ok:
            (work / "pghostaddr.err").write_text(proc.stdout[-4000:] + "\n" + proc.stderr[-4000:])
        before = marks(standin / "log")

        service = work / "services.conf"
        service.write_text(f"[labsvc]\nhostaddr=127.0.0.1\nport={port}\nuser=postgres\ndbname=postgres\n")
        svc = {name: "synthetic-value" for name in PG_NAMES}
        svc.update({"PGSERVICE": "labsvc", "PGSERVICEFILE": str(service), "PGHOSTADDR": "127.0.0.1", "PGPORT": str(port)})
        proc = runner("pgservice", svc)
        delta = tuple(a - b for a, b in zip(marks(standin / "log"), before))
        roles = foreign_roles(standin, port)
        ok = proc.returncode == 0 and delta == (0, 0) and roles == "0"
        results.append(("b1-pgservice", "scrubbed" if ok else "failed", sum(delta), ok, proc.returncode))
        if not ok:
            (work / "pgservice.err").write_text(proc.stdout[-4000:] + "\n" + proc.stderr[-4000:])

        lab = work / "lab-socket"
        nonce = "ab" * 32
        lab_port = 55483
        other = work / "standin-unix"
        start_cluster(other, 55484, "''")
        clusters.append(other)
        start_cluster(lab, lab_port, "''", nonce=nonce)
        clusters.append(lab)
        writer = run([sys.executable, "-c", textwrap.dedent(f"""
            import importlib.util, os
            spec = importlib.util.spec_from_file_location("vip", {str(PY)!r})
            gate = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(gate)
            gate.write_invocation_proof({str(lab / "invocation.json")!r}, {str(lab / "data")!r}, {str(lab)!r}, {lab_port}, "postgres", os.getppid(), {nonce!r})
        """)])
        sock = lab / f".s.PGSQL.{lab_port}"
        if sock.exists() or sock.is_symlink():
            sock.unlink()
        sock.symlink_to(other / ".s.PGSQL.55484")
        before_other = marks(other / "log")
        code = None
        if writer.returncode == 0:
            dsn = f"postgresql://postgres@/postgres?host={lab}&port={lab_port}"
            code, _detail = mod.assess_apply_target(dsn, str(lab / "invocation.json"), mod.OsView())
        delta_ops = sum(a - b for a, b in zip(marks(other / "log"), before_other))
        ok = writer.returncode == 0 and code == "LAB_TARGET_UNRELATED_LOCAL" and delta_ops == 0
        results.append(("m1-socket-symlink", code or "proof-rejected", delta_ops, ok, writer.returncode))

        spoof = work / "lab-spoof"
        spoof_nonce = "cd" * 32
        start_cluster(spoof, 55485, "''", nonce=spoof_nonce)
        clusters.append(spoof)
        before_spoof = marks(spoof / "log")
        receipt = work / "spoof-receipt.json"
        driver = textwrap.dedent(f"""
            import importlib.util, os, sys
            spec = importlib.util.spec_from_file_location("vip", {str(PY)!r})
            gate = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(gate)
            gate.write_invocation_proof({str(spoof / "invocation.json")!r}, {str(spoof / "data")!r}, {str(spoof)!r}, 55485, "postgres", os.getppid(), {spoof_nonce!r})
            os.environ["E02_LAB_PROOF"] = {str(spoof / "invocation.json")!r}
            os.environ["DATABASE_URL"] = "postgresql://postgres@/postgres?host={spoof}&port=55485"
            sys.argv = [{str(PY)!r}, "--root", {str(ROOT)!r}, "--apply", "--receipt", {str(receipt)!r}]
            raise SystemExit(gate.main())
        """)
        proc = run(["bash", "-c", "python3 - <<'PY'\n" + driver + "\nPY\n", str(SH)], capture_output=True)
        delta_ops = sum(a - b for a, b in zip(marks(spoof / "log"), before_spoof))
        refused = proc.returncode == 1 and "LAB_TARGET_STALE" in proc.stdout and not receipt.exists()
        ok = refused and delta_ops == 0
        results.append(("m2-argv-spoof", "LAB_TARGET_STALE" if refused else "failed", delta_ops, ok, proc.returncode))
        if not ok:
            (work / "spoof.err").write_text(proc.stdout[-4000:] + "\n" + proc.stderr[-4000:])

        foreign = work / "fake-foreign"
        fake_port = 55486
        fake_nonce = "ef" * 32
        start_cluster(foreign, fake_port, "''")
        clusters.append(foreign)
        fake_lab = work / "fake-lab"
        fake_data = (fake_lab / "data").resolve()
        fake_socket = fake_lab.resolve()
        fake_data.mkdir(parents=True)
        fake_proc = subprocess.Popen([
            sys.executable, "-c",
            "import os,sys,time; os.execv(sys.executable, sys.argv[1:])",
            "/fake/bin/postgres", "-c", "import time; time.sleep(60)",
            "-D", str(fake_data), "-k", str(fake_socket), "-p", str(fake_port),
            "-c", "listen_addresses=", "-c", f"e02.invocation={fake_nonce}",
        ])
        deadline = time.time() + 5
        while time.time() < deadline:
            try:
                cmd = Path(f"/proc/{fake_proc.pid}/cmdline").read_bytes().split(b"\0")
            except OSError:
                cmd = []
            if cmd and cmd[0] == b"/fake/bin/postgres":
                break
            time.sleep(0.05)
        exe = os.readlink(f"/proc/{fake_proc.pid}/exe")
        (fake_data / "postmaster.pid").write_text(
            f"{fake_proc.pid}\n{fake_data}\n1\n{fake_port}\n{fake_socket}\n\n"
        )
        sock = fake_socket / f".s.PGSQL.{fake_port}"
        if sock.exists() or sock.is_symlink():
            sock.unlink()
        sock.symlink_to(foreign / f".s.PGSQL.{fake_port}")
        before_foreign = marks(foreign / "log")
        writer = run([sys.executable, "-c", textwrap.dedent(f"""
            import importlib.util, os
            spec = importlib.util.spec_from_file_location("vip", {str(PY)!r})
            gate = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(gate)
            gate.write_invocation_proof({str(fake_socket / "invocation.json")!r}, {str(fake_data)!r}, {str(fake_socket)!r}, {fake_port}, "postgres", os.getppid(), {fake_nonce!r})
        """)])
        proof = {
            "nonce": fake_nonce,
            "creator_pid": os.getpid(),
            "creator_starttime": "1",
            "data_dir": str(fake_data),
            "socket_dir": str(fake_socket),
            "port": fake_port,
            "postmaster_pid": fake_proc.pid,
            "postmaster_start": "1",
            "databases": ["postgres"],
        }
        (fake_data / "e02_invocation").write_text(fake_nonce + "\n")
        (fake_socket / "invocation.json").write_text(__import__("json").dumps(proof))
        dsn = f"postgresql://postgres@/postgres?host={fake_socket}&port={fake_port}"
        code, _detail = mod.assess_apply_target(dsn, str(fake_socket / "invocation.json"), mod.OsView())
        delta_ops = sum(a - b for a, b in zip(marks(foreign / "log"), before_foreign))
        ok = (
            Path(exe).name != "postgres"
            and writer.returncode != 0
            and code == "LAB_TARGET_UNRELATED_LOCAL"
            and delta_ops == 0
        )
        results.append(("m1-fake-exe", code or "rejected", delta_ops, ok, writer.returncode))
    finally:
        if fake_proc is not None and fake_proc.poll() is None:
            fake_proc.kill()
            fake_proc.wait(timeout=5)
        alive = []
        for directory in clusters:
            pid_file = directory / "data" / "postmaster.pid"
            pid = pid_file.read_text().splitlines()[0] if pid_file.exists() else ""
            stop_cluster(directory)
            if pid:
                try:
                    os.kill(int(pid), 0)
                    alive.append(pid)
                except OSError:
                    pass
            shutil.rmtree(directory, ignore_errors=True)
        print("BOUNDARY_SUMMARY")
        failed = 0
        for name, code, ops, ok, rc in results:
            print(f"{name} code={code} database_operations={ops} ok={ok} rc={rc}")
            failed += not ok
        left = sum(path.exists() for path in clusters)
        shutil.rmtree(work, ignore_errors=True)
        print(f"clusters_alive={len(alive)} directories_left={left} work_left={int(work.exists())}")
        return 1 if failed or alive or work.exists() else 0


if __name__ == "__main__":
    sys.exit(main())
