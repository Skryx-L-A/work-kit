#!/usr/bin/env python3
"""Focused local-only probe for process-group and session escape on macOS."""

from __future__ import annotations

import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time


def _sandbox_python() -> Path:
    """Ein Interpreter, den das Seatbelt-Profil laden kann.

    /usr/bin/python3 ist ein Stellvertreter fuer das Python-Framework in Xcode.app; dessen
    Bibliothek liegt ausserhalb der erlaubten Pfade, und die Sandbox verweigert sie
    (Befund 14.09.2026: "dyld: Library not loaded: @executable_path/../Python3").
    Ein Homebrew-Python ist ein echtes Binary und laeuft unter dem Profil.
    """
    exe = Path(sys.executable).resolve()
    if "Xcode.app" in str(exe) or "CommandLineTools" in str(exe):
        for alt in ("/opt/homebrew/bin/python3", "/usr/local/bin/python3"):
            if os.access(alt, os.X_OK):
                return Path(alt).resolve()
    return exe


PYTHON = _sandbox_python()


HELPER_SOURCE = r'''
import ctypes
import json
import os
from pathlib import Path
import sys
import time


def info(role):
    return {
        "role": role,
        "pid": os.getpid(),
        "ppid": os.getppid(),
        "pgid": os.getpgid(0),
        "sid": os.getsid(0),
    }


def write_json(path, value):
    Path(path).write_text(json.dumps(value, sort_keys=True) + "\n")


def wait_for_stop():
    stop = Path(os.environ["PROBE_STOP"])
    deadline = time.monotonic() + 20.0
    while not stop.exists() and time.monotonic() < deadline:
        time.sleep(0.05)


def apply_profile():
    profile = Path(os.environ["PROBE_PROFILE"]).read_bytes()
    libc = ctypes.CDLL(None)
    sandbox_init = libc.sandbox_init
    sandbox_init.argtypes = [ctypes.c_char_p, ctypes.c_uint64, ctypes.POINTER(ctypes.c_char_p)]
    sandbox_init.restype = ctypes.c_int
    error = ctypes.c_char_p()
    if sandbox_init(profile, 0, ctypes.byref(error)) != 0:
        detail = error.value.decode(errors="replace") if error.value else "unknown sandbox_init error"
        raise RuntimeError(detail)


def wait_child(pid, timeout=3.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        waited, status = os.waitpid(pid, os.WNOHANG)
        if waited == pid:
            return os.waitstatus_to_exitcode(status)
        time.sleep(0.03)
    os.kill(pid, 9)
    os.waitpid(pid, 0)
    return None


def fork_exec_wait(argv, env=None):
    pid = os.fork()
    if pid == 0:
        try:
            os.execve(argv[0], argv, env or os.environ.copy())
        except OSError:
            os._exit(127)
    return pid, wait_child(pid)


def child_pgid():
    path = Path(os.environ["PROBE_PGID_STATUS"])
    before = info("pgid-child-before")
    result = {"before": before}
    try:
        os.setpgid(0, 0)
        result["setpgid"] = {"ok": True, "error": None, "errno": None}
    except OSError as exc:
        result["setpgid"] = {
            "ok": False,
            "error": f"{type(exc).__name__}: {exc}",
            "errno": exc.errno,
        }
    result["after"] = info("pgid-child-after")
    write_json(path, result)
    wait_for_stop()


def child_sid():
    path = Path(os.environ["PROBE_SID_STATUS"])
    before = info("sid-child-before")
    result = {"before": before}
    try:
        new_sid = os.setsid()
        result["setsid"] = {"ok": True, "returned": new_sid, "error": None, "errno": None}
    except OSError as exc:
        result["setsid"] = {
            "ok": False,
            "returned": None,
            "error": f"{type(exc).__name__}: {exc}",
            "errno": exc.errno,
        }
    result["after"] = info("sid-child-after")
    write_json(path, result)
    wait_for_stop()


def child_spawn():
    path = Path(os.environ["PROBE_SPAWN_STATUS"])
    write_json(path, info(os.environ["PROBE_SPAWN_ROLE"]))
    wait_for_stop()


def spawn_root():
    root_status = Path(os.environ["PROBE_ROOT_STATUS"])
    children = []
    for role, spawn_kwargs in (("posix-spawn-setpgroup", {"setpgroup": 0}), ("posix-spawn-setsid", {"setsid": True})):
        child_env = os.environ.copy()
        child_env["PROBE_SPAWN_ROLE"] = role
        child_env["PROBE_SPAWN_STATUS"] = str(Path(os.environ["PROBE_WORK"]) / f"{role}.json")
        pid = os.posix_spawn(str(PYTHON), [str(PYTHON), "-S", "helper.py", "spawn-child"], child_env, **spawn_kwargs)
        children.append(pid)
    write_json(root_status, {"root": info("spawn-root"), "children": children})
    wait_for_stop()
    for pid in children:
        os.waitpid(pid, 0)


def compat_root():
    root_status = Path(os.environ["PROBE_ROOT_STATUS"])
    compat_status = Path(os.environ["PROBE_COMPAT_STATUS"])
    apply_profile()
    write_json(root_status, {"root": info("compat-root")})
    result = {}
    try:
        pid = os.posix_spawn("/usr/bin/true", ["/usr/bin/true"], os.environ.copy())
    except OSError as exc:
        result["python_posix_spawn"] = {
            "ok": False,
            "errno": exc.errno,
            "error": f"{type(exc).__name__}: {exc}",
        }
    else:
        result["python_posix_spawn"] = {"ok": True, "returncode": wait_child(pid)}

    shell_pid, shell_returncode = fork_exec_wait(["/bin/sh", "-c", "/usr/bin/true"])
    result["shell_fork_exec"] = {"pid": shell_pid, "returncode": shell_returncode}

    node_script = (
        "const {spawnSync}=require('node:child_process');"
        "const fs=require('node:fs');"
        "const r=spawnSync('/usr/bin/true');"
        "fs.writeFileSync(process.env.PROBE_NODE_STATUS, JSON.stringify({"
        "status:r.status??null,signal:r.signal??null,error:r.error?{"
        "code:r.error.code??null,errno:r.error.errno??null,message:r.error.message}:null}));"
    )
    node_pid, node_returncode = fork_exec_wait(["/opt/homebrew/bin/node", "-e", node_script])
    node_status = Path(os.environ["PROBE_NODE_STATUS"])
    deadline = time.monotonic() + 3.0
    while not node_status.is_file() and time.monotonic() < deadline:
        time.sleep(0.03)
    result["node_runner"] = {
        "pid": node_pid,
        "returncode": node_returncode,
        "spawn_sync": json.loads(node_status.read_text()) if node_status.is_file() else None,
    }
    write_json(compat_status, result)
    wait_for_stop()


def root():
    root_status = Path(os.environ["PROBE_ROOT_STATUS"])
    pgid_pid = os.fork()
    if pgid_pid == 0:
        try:
            child_pgid()
        finally:
            os._exit(0)

    sid_pid = os.fork()
    if sid_pid == 0:
        try:
            child_sid()
        finally:
            os._exit(0)

    write_json(root_status, {"root": info("root"), "children": [pgid_pid, sid_pid]})
    wait_for_stop()
    os.waitpid(pgid_pid, 0)
    os.waitpid(sid_pid, 0)


def main():
    if sys.argv[1] == "root":
        root()
    elif sys.argv[1] == "spawn-root":
        spawn_root()
    elif sys.argv[1] == "spawn-child":
        child_spawn()
    elif sys.argv[1] == "compat-root":
        compat_root()
    else:
        raise SystemExit(f"unknown mode: {sys.argv[1]}")


if __name__ == "__main__":
    main()
'''


def wait_for_file(path: Path, process: subprocess.Popen[str], timeout: float = 4.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.is_file() and path.read_text().strip():
            return
        if process.poll() is not None:
            stdout, stderr = process.communicate(timeout=0.5)
            raise RuntimeError(
                f"sandbox exited before readiness: rc={process.returncode}, "
                f"stdout={stdout!r}, stderr={stderr!r}"
            )
        time.sleep(0.03)
    raise TimeoutError(f"readiness timeout: {path}")


def process_info(pid: int) -> dict[str, str] | None:
    result = subprocess.run(
        ["/bin/ps", "-p", str(pid), "-o", "pid=,ppid=,pgid=,sess=,state="],
        text=True,
        capture_output=True,
        timeout=2.0,
        check=False,
    )
    line = result.stdout.strip()
    if not line:
        return None
    fields = line.split()
    if len(fields) != 5:
        raise AssertionError(f"unexpected ps output for owned pid {pid}: {result.stdout!r}")
    return dict(zip(("pid", "ppid", "pgid", "sid", "state"), fields))


def wait_absent(pid: int, timeout: float = 4.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process_info(pid) is None:
            return
        time.sleep(0.05)
    raise AssertionError(f"owned process remained after termination: pid={pid}, info={process_info(pid)!r}")


def group_matches(pid: int, pgid: int) -> bool:
    current = process_info(pid)
    return current is not None and int(current["pgid"]) == pgid


def terminate_owned_group(pid: int, pgid: int) -> None:
    if not group_matches(pid, pgid):
        return
    os.killpg(pgid, signal.SIGTERM)
    try:
        wait_absent(pid, timeout=2.0)
    except AssertionError:
        if group_matches(pid, pgid):
            os.killpg(pgid, signal.SIGKILL)
        wait_absent(pid, timeout=2.0)


def sbpl_literal(path: Path) -> str:
    value = str(path)
    if "\\" in value or '"' in value:
        raise ValueError(f"unsupported path for SBPL literal: {value!r}")
    return value


def write_profile(path: Path, work: Path, deny_session_syscalls: bool = False, deny_posix_spawn: bool = False) -> None:
    work = work.resolve()
    ancestor_rules = [
        f'(allow file-read-metadata file-test-existence (literal "{sbpl_literal(ancestor)}"))'
        for ancestor in work.parents
        if ancestor != Path("/")
    ]
    session_syscall_denials = [
        "(deny syscall-unix (syscall-number SYS_setpgid))",
        "(deny syscall-unix (syscall-number SYS_setsid))",
    ] if deny_session_syscalls else []
    posix_spawn_denial = [
        "(deny syscall-unix (syscall-number SYS_posix_spawn))",
    ] if deny_posix_spawn else []
    path.write_text(
        "\n".join(
            [
                "(version 1)",
                '(import "system.sb")',
                "(deny default)",
                "(allow process-fork process-exec)",
                *session_syscall_denials,
                *posix_spawn_denial,
                f'(allow file-read-metadata (literal "{sbpl_literal(Path("/opt"))}"))',
                *ancestor_rules,
                f'(allow file-read* (subpath "{sbpl_literal(Path("/opt/homebrew"))}"))',
                f'(allow file-map-executable (subpath "{sbpl_literal(Path("/opt/homebrew"))}"))',
                f'(allow file-read* (subpath "{sbpl_literal(work)}"))',
                f'(allow file-write-data file-write-create file-write-unlink (subpath "{sbpl_literal(work)}"))',
                "",
            ]
        )
    )


def main() -> int:
    if sys.platform != "darwin":
        print("SKIP: macOS-only process-group/session probe", file=sys.stderr)
        return 0
    sandbox_exec = Path("/usr/bin/sandbox-exec")
    if not sandbox_exec.is_file():
        print("ERROR: /usr/bin/sandbox-exec missing", file=sys.stderr)
        return 2
    deny_session_syscalls = "--deny-session-syscalls" in sys.argv[1:]
    probe_posix_spawn = "--probe-posix-spawn" in sys.argv[1:]
    probe_posix_spawn_filter = "--probe-posix-spawn-filter" in sys.argv[1:]

    with tempfile.TemporaryDirectory(prefix="wbss-", dir="/tmp") as root_name:
        root = Path(root_name)
        work = root / "work-root"
        work.mkdir()
        helper = work / "helper.py"
        helper.write_text(HELPER_SOURCE)
        profile = root / "probe.sb"
        write_profile(
            profile,
            work,
            deny_session_syscalls=deny_session_syscalls,
            deny_posix_spawn=probe_posix_spawn_filter,
        )
        stop = work / "stop"
        root_status = work / "root-status.json"
        pgid_status = work / "pgid-status.json"
        sid_status = work / "sid-status.json"
        compat_status = work / "compat-status.json"
        node_status = work / "node-status.json"
        env = {
            "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
            "HOME": str(root),
            "TMPDIR": str(root),
            "PYTHONNOUSERSITE": "1",
            "LC_ALL": "C",
            "PROBE_STOP": str(stop),
            "PROBE_WORK": str(work),
            "PROBE_ROOT_STATUS": str(root_status),
            "PROBE_PGID_STATUS": str(pgid_status),
            "PROBE_SID_STATUS": str(sid_status),
            "PROBE_COMPAT_STATUS": str(compat_status),
            "PROBE_NODE_STATUS": str(node_status),
            "PROBE_PROFILE": str(profile),
        }
        sandbox = None
        child_records: list[tuple[int, int]] = []
        try:
            command = [str(PYTHON), "-S", "helper.py", "compat-root"] if probe_posix_spawn_filter else [
                str(sandbox_exec),
                "-f",
                str(profile),
                str(PYTHON),
                "-S",
                "helper.py",
                "spawn-root" if probe_posix_spawn else "root",
            ]
            sandbox = subprocess.Popen(
                command,
                cwd=work,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True,
                close_fds=True,
            )
            wait_for_file(root_status, sandbox)
            if probe_posix_spawn_filter:
                wait_for_file(compat_status, sandbox)
                compat = json.loads(compat_status.read_text())
                python_spawn = compat["python_posix_spawn"]
                if python_spawn["ok"] or python_spawn["errno"] != 1:
                    raise AssertionError(f"os.posix_spawn was not denied with EPERM: {compat!r}")
                shell = compat["shell_fork_exec"]
                if shell["returncode"] != 0:
                    raise AssertionError(f"fork/exec shell control failed: {compat!r}")
                node = compat["node_runner"]
                if node["returncode"] != 0 or node["spawn_sync"] is None:
                    raise AssertionError(f"Node compatibility runner failed: {compat!r}")
                node_spawn = node["spawn_sync"]
                if node_spawn.get("error", {}).get("code") != "EPERM":
                    raise AssertionError(f"Node spawnSync was not denied with EPERM: {compat!r}")
                print("PASS: syscall-unix denied Python os.posix_spawn with EPERM")
                print("PASS: fork/exec /bin/sh -c /usr/bin/true remained usable")
                print("PASS: Node child_process.spawnSync failed with EPERM")
                print(json.dumps({"policy": "deny-SYS_posix_spawn", "python": python_spawn, "shell": shell, "node": node}, sort_keys=True))
                stop.write_text("stop\n")
                sandbox.wait(timeout=3.0)
                if sandbox.returncode != 0:
                    raise AssertionError(f"compatibility root did not stop cleanly: rc={sandbox.returncode}")
                return 0
            if probe_posix_spawn:
                spawn_pgroup_status = work / "posix-spawn-setpgroup.json"
                spawn_sid_status = work / "posix-spawn-setsid.json"
                wait_for_file(spawn_pgroup_status, sandbox)
                wait_for_file(spawn_sid_status, sandbox)
                root_record = json.loads(root_status.read_text())
                spawn_pgroup = json.loads(spawn_pgroup_status.read_text())
                spawn_sid = json.loads(spawn_sid_status.read_text())
                parent = root_record["root"]
                child_records = [
                    (int(spawn_pgroup["pid"]), int(spawn_pgroup["pgid"])),
                    (int(spawn_sid["pid"]), int(spawn_sid["pgid"])),
                ]
                if int(parent["pid"]) != sandbox.pid:
                    raise AssertionError(f"sandbox pid mismatch: {parent!r}, popen={sandbox.pid}")
                if root_record["children"] != [spawn_pgroup["pid"], spawn_sid["pid"]]:
                    raise AssertionError(f"spawn child list mismatch: {root_record!r}")
                if int(spawn_pgroup["pgid"]) == int(parent["pgid"]):
                    raise AssertionError(f"setpgroup=0 did not create a separate group: {spawn_pgroup!r}")
                if int(spawn_sid["pgid"]) == int(parent["pgid"]) or int(spawn_sid["sid"]) == int(parent["sid"]):
                    raise AssertionError(f"setsid=True did not create a separate session/group: {spawn_sid!r}")
                root_pgid = int(parent["pgid"])
                os.killpg(root_pgid, signal.SIGTERM)
                sandbox.wait(timeout=3.0)
                survivors = {pid: process_info(pid) for pid, _ in child_records}
                if any(value is None for value in survivors.values()):
                    raise AssertionError(f"posix_spawn child did not escape root group: {survivors!r}")
                for pid, pgid in child_records:
                    terminate_owned_group(pid, pgid)
                    wait_absent(pid)
                print("PASS: posix_spawn setpgroup=0 created an escaped process group")
                print("PASS: posix_spawn setsid=True created an escaped session/process group")
                print("PASS: root-group stop left both spawn children alive")
                print("PASS: exact recorded posix_spawn child PGIDs terminated both survivors")
                print(json.dumps({"root": parent, "setpgroup": spawn_pgroup, "setsid": spawn_sid, "root_group_stop": "children-survived", "cleanup": "exact-child-pgids"}, sort_keys=True))
                return 0
            wait_for_file(pgid_status, sandbox)
            wait_for_file(sid_status, sandbox)
            root_record = json.loads(root_status.read_text())
            pgid_record = json.loads(pgid_status.read_text())
            sid_record = json.loads(sid_status.read_text())
            parent = root_record["root"]
            pgid_child = pgid_record["after"]
            sid_child = sid_record["after"]
            if int(parent["pid"]) != sandbox.pid:
                raise AssertionError(f"sandbox pid mismatch: {parent!r}, popen={sandbox.pid}")
            if int(parent["pgid"]) != int(parent["pid"]) or int(parent["sid"]) != int(parent["pid"]):
                raise AssertionError(f"sandbox root was not own session leader: {parent!r}")
            if deny_session_syscalls:
                if pgid_record["setpgid"]["ok"] or pgid_record["setpgid"]["errno"] != 1:
                    raise AssertionError(f"setpgid was not denied with EPERM: {pgid_record!r}")
                if sid_record["setsid"]["ok"] or sid_record["setsid"]["errno"] != 1:
                    raise AssertionError(f"setsid was not denied with EPERM: {sid_record!r}")
                if pgid_child["pgid"] != pgid_record["before"]["pgid"] or pgid_child["sid"] != pgid_record["before"]["sid"]:
                    raise AssertionError(f"denied setpgid still changed identity: {pgid_record!r}")
                if sid_child["pgid"] != sid_record["before"]["pgid"] or sid_child["sid"] != sid_record["before"]["sid"]:
                    raise AssertionError(f"denied setsid still changed identity: {sid_record!r}")
            else:
                if not pgid_record["setpgid"]["ok"]:
                    raise AssertionError(f"setpgid failed: {pgid_record!r}")
                if not sid_record["setsid"]["ok"]:
                    raise AssertionError(f"setsid failed: {sid_record!r}")
                if int(pgid_record["before"]["pgid"]) != int(parent["pgid"]):
                    raise AssertionError(f"setpgid child did not start in root group: {pgid_record!r}")
                if int(pgid_child["pgid"]) != int(pgid_child["pid"]) or int(pgid_child["sid"]) != int(parent["sid"]):
                    raise AssertionError(f"setpgid child did not leave root group only: {pgid_record!r}")
                if int(sid_record["before"]["sid"]) != int(parent["sid"]):
                    raise AssertionError(f"setsid child did not start in root session: {sid_record!r}")
                if int(sid_child["sid"]) != int(sid_child["pid"]) or int(sid_child["pgid"]) != int(sid_child["pid"]):
                    raise AssertionError(f"setsid child did not create its own session/group: {sid_record!r}")
            child_records = [(int(pgid_child["pid"]), int(pgid_child["pgid"])), (int(sid_child["pid"]), int(sid_child["pgid"]))]

            root_pgid = int(parent["pgid"])
            os.killpg(root_pgid, signal.SIGTERM)
            sandbox.wait(timeout=3.0)
            if sandbox.returncode == 0:
                raise AssertionError("root process-group termination unexpectedly returned success")
            if deny_session_syscalls:
                for pid, _ in child_records:
                    wait_absent(pid)
                print("PASS: syscall-unix denied setpgid and setsid with EPERM")
                print("PASS: denied calls left children in the original process group/session")
                print("PASS: original group termination ended both children")
                print(json.dumps({"root": parent, "setpgid": pgid_record, "setsid": sid_record, "root_group_stop": "children-ended", "policy": "deny-session-syscalls"}, sort_keys=True))
                return 0
            survivors = {pid: process_info(pid) for pid, _ in child_records}
            if any(value is None for value in survivors.values()):
                raise AssertionError(f"escaped child did not survive root-group stop: {survivors!r}")

            for pid, pgid in child_records:
                terminate_owned_group(pid, pgid)
            for pid, _ in child_records:
                wait_absent(pid)

            print("PASS: sandbox root and children exposed PID/PGID/SID records")
            print("PASS: setpgid(0, 0) and setsid() left the original process group/session")
            print("PASS: stopping the original group left both escaped child groups alive")
            print("PASS: exact recorded child PGIDs terminated both owned survivors")
            print(json.dumps({"root": parent, "setpgid": pgid_record, "setsid": sid_record, "root_group_stop": "children-survived", "cleanup": "exact-child-pgids"}, sort_keys=True))
        finally:
            stop.write_text("stop\n")
            if sandbox is not None and sandbox.poll() is None:
                if group_matches(sandbox.pid, sandbox.pid):
                    os.killpg(sandbox.pid, signal.SIGKILL)
                sandbox.wait(timeout=3.0)
            for pid, pgid in child_records:
                if process_info(pid) is not None:
                    terminate_owned_group(pid, pgid)
        for pid, _ in child_records:
            if process_info(pid) is not None:
                raise AssertionError(f"owned child remained after cleanup: pid={pid}, info={process_info(pid)!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
