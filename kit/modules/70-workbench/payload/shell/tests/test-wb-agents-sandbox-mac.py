#!/usr/bin/env python3
"""Small, local-only Seatbelt feasibility probe for macOS agent processes."""

from __future__ import annotations

import json
import errno
import os
from pathlib import Path
import socket
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
import json
import os
from pathlib import Path
import socket
import sys
import time


def attempt(label, operation):
    try:
        operation()
    except BaseException as exc:
        return {
            "label": label,
            "ok": False,
            "error": f"{type(exc).__name__}: {exc}",
            "error_type": type(exc).__name__,
            "errno": getattr(exc, "errno", None),
        }
    return {"label": label, "ok": True, "error": None, "error_type": None, "errno": None}


def probe_process(depth):
    work = Path(os.environ["PROBE_WORK"])
    protected = Path(os.environ["PROBE_PROTECTED"])
    sibling = Path(os.environ["PROBE_SIBLING"])
    escaped = work / "control-link"
    port = int(os.environ["PROBE_PORT"])
    own_file = work / f"own-{depth}.txt"
    sibling_file = sibling / f"escape-{depth}.txt"
    results = []

    results.append(attempt("own_write", lambda: own_file.write_text(f"depth-{depth}\n")))
    results.append(attempt("own_read", lambda: own_file.read_text()))
    results.append(attempt("protected_read", lambda: protected.read_text()))
    results.append(attempt("protected_write", lambda: os.close(os.open(str(protected), os.O_WRONLY))))
    results.append(attempt("sibling_read", lambda: sibling_file.read_text()))
    results.append(attempt("sibling_write", lambda: sibling_file.write_text("escape\n")))
    results.append(attempt("symlink_read", lambda: escaped.read_text()))
    results.append(
        attempt(
            "symlink_write",
            lambda: os.close(os.open(str(escaped), os.O_WRONLY)),
        )
    )
    results.append(
        attempt(
            "loopback_connect",
            lambda: connect_and_close(port),
        )
    )

    if depth < 2:
        child = os.fork()
        if child == 0:
            try:
                probe_process(depth + 1)
            finally:
                os._exit(0)
        os.waitpid(child, 0)

    (work / f"result-{depth}.json").write_text(json.dumps({"depth": depth, "checks": results}) + "\n")


def connect_and_close(port):
    connection = socket.create_connection(("127.0.0.1", port), timeout=1.0)
    connection.close()


def run_server():
    work = Path(os.environ["PROBE_WORK"])
    port_file = Path(os.environ["PROBE_PORT_FILE"])
    status_file = Path(os.environ["PROBE_SERVER_STATUS"])
    stop_file = Path(os.environ["PROBE_SERVER_STOP"])
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    port_file.write_text(str(server.getsockname()[1]) + "\n")
    server.settimeout(0.1)
    accepted = 0
    deadline = time.monotonic() + 8.0
    try:
        while not stop_file.exists() and time.monotonic() < deadline:
            try:
                connection, _ = server.accept()
            except TimeoutError:
                continue
            connection.close()
            accepted += 1
        status_file.write_text(f"connections={accepted}\n")
    finally:
        server.close()


def main():
    mode = sys.argv[1]
    if mode == "server":
        run_server()
    elif mode == "sandbox":
        probe_process(0)
    elif mode == "baseline":
        work = Path(os.environ["PROBE_WORK"])
        protected = Path(os.environ["PROBE_PROTECTED"])
        sibling = Path(os.environ["PROBE_SIBLING"])
        escaped = work / "control-link"
        port = int(os.environ["PROBE_PORT"])
        checks = [
            attempt("own_write", lambda: (work / "baseline.txt").write_text("baseline-ok\n")),
            attempt("own_read", lambda: (work / "baseline.txt").read_text()),
            attempt("protected_read", lambda: protected.read_text()),
            attempt("protected_write", lambda: os.close(os.open(str(protected), os.O_WRONLY))),
            attempt("sibling_read", lambda: (sibling / "escape-0.txt").read_text()),
            attempt("sibling_write", lambda: (sibling / "escape-0.txt").write_text("sibling-control\n")),
            attempt("symlink_read", lambda: escaped.read_text()),
            attempt("symlink_write", lambda: os.close(os.open(str(escaped), os.O_WRONLY))),
            attempt("loopback_connect", lambda: connect_and_close(port)),
        ]
        print(json.dumps({"baseline": checks}, sort_keys=True))
    else:
        raise SystemExit(f"unknown mode: {mode}")


if __name__ == "__main__":
    main()
'''


def run_helper(mode: str, env: dict[str, str], *, timeout: float = 8.0) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(PYTHON), "-S", "helper.py", mode],
        cwd=env["PROBE_WORK"],
        env=env,
        text=True,
        capture_output=True,
        timeout=timeout,
        check=False,
    )


def wait_for_file(path: Path, process: subprocess.Popen[str], timeout: float = 3.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.is_file() and path.read_text().strip():
            return
        if process.poll() is not None:
            raise RuntimeError(f"dummy server exited before readiness: rc={process.returncode}")
        time.sleep(0.03)
    raise TimeoutError(f"dummy server readiness timeout: {path}")


def process_group_exists(pgid: int) -> bool:
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    return True


def sbpl_literal(path: Path) -> str:
    value = str(path)
    if "\\" in value or '"' in value:
        raise ValueError(f"unsupported path for SBPL literal: {value!r}")
    return value


def write_profile(path: Path, work: Path) -> None:
    runtime = sbpl_literal(Path("/opt/homebrew"))
    work = work.resolve()
    work_literal = sbpl_literal(work)
    ancestor_rules = [
        f'(allow file-read-metadata file-test-existence (literal "{sbpl_literal(ancestor)}"))'
        for ancestor in work.parents
        if ancestor != Path("/")
    ]
    path.write_text(
        "\n".join(
            [
                "(version 1)",
                '(import "system.sb")',
                "(deny default)",
                "(allow process-fork process-exec)",
                f'(allow file-read-metadata (literal "{sbpl_literal(Path("/opt"))}"))',
                *ancestor_rules,
                f'(allow file-read* (subpath "{runtime}"))',
                f'(allow file-map-executable (subpath "{runtime}"))',
                f'(allow file-read* (subpath "{work_literal}"))',
                f'(allow file-write-data file-write-create file-write-unlink (subpath "{work_literal}"))',
                "",
            ]
        )
    )


def check_results(work: Path) -> dict:
    expected = {
        "own_write": True,
        "own_read": True,
        "protected_read": False,
        "protected_write": False,
        "sibling_read": False,
        "sibling_write": False,
        "symlink_read": False,
        "symlink_write": False,
        "loopback_connect": False,
    }
    observed = {}
    for depth in range(3):
        result_path = work / f"result-{depth}.json"
        if not result_path.is_file():
            raise AssertionError(f"missing descendant result: {result_path}")
        payload = json.loads(result_path.read_text())
        checks = {item["label"]: item for item in payload["checks"]}
        if payload["depth"] != depth or set(checks) != set(expected):
            raise AssertionError(f"unexpected result shape at depth {depth}: {payload!r}")
        observed[str(depth)] = {
            label: {"ok": checks[label]["ok"], "error": checks[label]["error"]}
            for label in expected
        }
        for label, wanted in expected.items():
            if checks[label]["ok"] != wanted:
                raise AssertionError(
                    f"depth {depth} {label}: wanted ok={wanted}, got {checks[label]!r}"
                )
            if not wanted and checks[label]["errno"] not in {errno.EPERM, errno.EACCES}:
                raise AssertionError(
                    f"depth {depth} {label}: denial was not EPERM/EACCES: {checks[label]!r}"
                )
    return observed


def main() -> int:
    if sys.platform != "darwin":
        print("SKIP: macOS-only Seatbelt probe", file=sys.stderr)
        return 0
    if not Path("/usr/bin/sandbox-exec").is_file():
        print("ERROR: /usr/bin/sandbox-exec missing", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory(prefix="wb-agents-sandbox-") as root_name:
        root = Path(root_name)
        work = root / "work-root"
        sibling = root / "work-root-sibling"
        protected_dir = root / "outside-control"
        work.mkdir()
        sibling.mkdir()
        protected_dir.mkdir()
        protected = protected_dir / "control.txt"
        protected.write_text("protected-control\n")
        for depth in range(3):
            (sibling / f"escape-{depth}.txt").write_text("sibling-control\n")
        (work / "control-link").symlink_to(protected)
        helper = work / "helper.py"
        helper.write_text(HELPER_SOURCE)
        profile = root / "probe.sb"
        write_profile(profile, work)
        port_file = work / "server-port.txt"
        server_status = work / "server-status.txt"
        server_stop = work / "server-stop"

        env = {
            "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
            "HOME": str(root),
            "TMPDIR": str(root),
            "PYTHONNOUSERSITE": "1",
            "LC_ALL": "C",
            "PROBE_WORK": str(work),
            "PROBE_PROTECTED": str(protected),
            "PROBE_SIBLING": str(sibling),
            "PROBE_PORT_FILE": str(port_file),
            "PROBE_SERVER_STATUS": str(server_status),
            "PROBE_SERVER_STOP": str(server_stop),
        }

        server = subprocess.Popen(
            [str(PYTHON), "-S", "helper.py", "server"],
            cwd=work,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            wait_for_file(port_file, server)
            env["PROBE_PORT"] = port_file.read_text().strip()
            baseline = run_helper("baseline", env)
            if baseline.returncode != 0:
                raise AssertionError(
                    f"outside-sandbox control failed: rc={baseline.returncode}, "
                    f"stdout={baseline.stdout!r}, stderr={baseline.stderr!r}"
                )
            baseline_payload = json.loads(baseline.stdout)
            baseline_checks = baseline_payload["baseline"]
            if any(not check["ok"] for check in baseline_checks):
                raise AssertionError(f"outside-sandbox control denied an operation: {baseline_payload!r}")

            sandbox = subprocess.Popen(
                ["/usr/bin/sandbox-exec", "-f", str(profile), str(PYTHON), "-S", "helper.py", "sandbox"],
                cwd=work,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True,
            )
            try:
                sandbox_stdout, sandbox_stderr = sandbox.communicate(timeout=12.0)
            except subprocess.TimeoutExpired:
                os.killpg(sandbox.pid, signal.SIGKILL)
                sandbox_stdout, sandbox_stderr = sandbox.communicate(timeout=2.0)
                raise AssertionError(
                    f"sandbox command timed out and its process group was killed: "
                    f"stdout={sandbox_stdout!r}, stderr={sandbox_stderr!r}"
                )
            if sandbox.returncode != 0:
                raise AssertionError(
                    f"sandbox command failed: rc={sandbox.returncode}, "
                    f"stdout={sandbox_stdout!r}, stderr={sandbox_stderr!r}"
                )
            if process_group_exists(sandbox.pid):
                os.killpg(sandbox.pid, signal.SIGKILL)
                sandbox.wait(timeout=2.0)
                raise AssertionError("sandbox process group remained after command completion")
            observed = check_results(work)
        finally:
            if server.poll() is None:
                server_stop.write_text("stop\n")
            if server.poll() is None and not server_status.is_file():
                try:
                    server.wait(timeout=2.0)
                except subprocess.TimeoutExpired:
                    pass
            if server.poll() is None:
                server.terminate()
            try:
                server.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=2.0)
            if server.poll() is None:
                raise AssertionError("dummy server did not terminate")

        if not server_status.is_file():
            server_output, server_error = server.communicate(timeout=0.5)
            raise AssertionError(
                f"dummy server produced no status: rc={server.returncode}, "
                f"stdout={server_output!r}, stderr={server_error!r}"
            )
        if server_status.read_text().strip() != "connections=1":
            raise AssertionError(f"dummy server observed unexpected traffic: {server_status.read_text()!r}")

        print("PASS: outside-sandbox control used all fixture paths and loopback successfully")
        print("PASS: Seatbelt denied protected, sibling-prefix, symlink, and loopback operations")
        print("PASS: same restrictions observed in root, child, and grandchild")
        print(json.dumps({"depths": observed, "server": server_status.read_text().strip()}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
