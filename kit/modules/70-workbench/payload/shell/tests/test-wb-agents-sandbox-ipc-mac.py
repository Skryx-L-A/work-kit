#!/usr/bin/env python3
"""Focused local-only probe for inherited handles, IPC, signals, and exec inheritance."""

from __future__ import annotations

import errno
import json
import os
from pathlib import Path
import select
import signal
import socket
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
DENIAL_ERRNOS = {errno.EPERM, errno.EACCES}


HELPER_SOURCE = r'''
import errno
import json
import os
from pathlib import Path
import select
import signal
import socket
import subprocess
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


def run_controller():
    work = Path(os.environ["PROBE_WORK"])
    socket_path = Path(os.environ["PROBE_CONTROLLER_SOCKET"])
    ready = Path(os.environ["PROBE_CONTROLLER_READY"])
    stop = Path(os.environ["PROBE_CONTROLLER_STOP"])
    status = Path(os.environ["PROBE_CONTROLLER_STATUS"])
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(socket_path))
    server.listen(4)
    server.setblocking(False)
    ready.write_text("ready\n")
    inherited = socket.socket(fileno=int(os.environ["PROBE_CONTROLLER_FD"]))
    inherited.setblocking(False)
    clients = [inherited]
    messages = []
    deadline = time.monotonic() + 8.0
    try:
        while not stop.exists() and time.monotonic() < deadline:
            readable, _, _ = select.select([server, *clients], [], [], 0.1)
            if server in readable:
                client, _ = server.accept()
                client.setblocking(False)
                clients.append(client)
                readable.remove(server)
            for client in readable:
                try:
                    data = client.recv(4096)
                except BlockingIOError:
                    continue
                if not data:
                    clients.remove(client)
                    client.close()
                else:
                    messages.append(data.decode("utf-8", errors="replace").strip())
    finally:
        for client in clients:
            client.close()
        server.close()
        status.write_text(json.dumps({"messages": messages}) + "\n")


def inherited_handles(mode):
    read_fd = int(os.environ["PROBE_READ_FD"])
    write_fd = int(os.environ["PROBE_WRITE_FD"])
    checks = []
    if mode == "baseline":
        checks.append(attempt("inherited_file_read", lambda: assert_bytes(os.read(read_fd, 128), b"protected-read\n")))
        checks.append(attempt("inherited_file_write", lambda: assert_count(os.write(write_fd, b"B"), 1)))
        checks.append(attempt("inherited_socket_send", lambda: send_socket(os.environ["PROBE_SOCKET_FD"], b"baseline-inherited\n")))
        checks.append(attempt("direct_unix_connect", lambda: direct_connect(os.environ["PROBE_CONTROLLER_SOCKET"])))
    elif mode == "sandbox":
        checks.append(attempt("inherited_file_read", lambda: assert_bytes(os.read(read_fd, 128), b"protected-read\n")))
        checks.append(attempt("inherited_file_write", lambda: assert_count(os.write(write_fd, b"S"), 1)))
        checks.append(attempt("inherited_socket_send", lambda: send_socket(os.environ["PROBE_SOCKET_FD"], b"sandbox-inherited\n")))
        checks.append(attempt("direct_unix_connect", lambda: direct_connect(os.environ["PROBE_CONTROLLER_SOCKET"])))
        checks.append(attempt("signal_external_target", lambda: os.kill(int(os.environ["PROBE_SIGNAL_PID"]), signal.SIGUSR1)))
        checks.append(attempt("exec_child", run_exec_child))
    elif mode == "clean-fds":
        checks.append(attempt("closed_file_read", lambda: os.read(read_fd, 1)))
        checks.append(attempt("closed_file_write", lambda: os.write(write_fd, b"C")))
        checks.append(attempt("closed_socket_send", lambda: send_socket(os.environ["PROBE_SOCKET_FD"], b"clean-fds\n")))
    else:
        raise SystemExit(f"unknown handle mode: {mode}")
    print(json.dumps({"checks": checks}, sort_keys=True))


def assert_bytes(actual, wanted):
    if actual != wanted:
        raise ValueError(f"unexpected bytes: {actual!r}")


def assert_count(actual, wanted):
    if actual != wanted:
        raise ValueError(f"unexpected byte count: {actual!r}")


def send_socket(fd_text, payload):
    connection = socket.socket(fileno=int(fd_text))
    try:
        assert_count(connection.send(payload), len(payload))
    finally:
        connection.detach()


def direct_connect(path):
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        connection.connect(path)
    finally:
        connection.close()


def run_exec_child():
    work = Path(os.environ["PROBE_WORK"])
    child = subprocess.Popen(
        [sys.executable, "-S", "helper.py", "exec-leaf"],
        cwd=work,
        env=os.environ.copy(),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
        close_fds=True,
    )
    try:
        stdout, stderr = child.communicate(timeout=4.0)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        child.wait(timeout=2.0)
        raise RuntimeError("exec child timeout")
    if child.returncode != 0:
        raise RuntimeError(f"exec child rc={child.returncode}: {stderr!r}")
    result = json.loads(stdout)
    if not result["own_write"]["ok"]:
        raise RuntimeError(f"exec child own write failed: {result!r}")
    if result["protected_read"]["ok"]:
        raise RuntimeError(f"exec child escaped protected read: {result!r}")
    if result["protected_read"]["errno"] not in {errno.EPERM, errno.EACCES}:
        raise RuntimeError(f"exec child denial was not EPERM/EACCES: {result!r}")


def run_exec_leaf():
    work = Path(os.environ["PROBE_WORK"])
    protected = Path(os.environ["PROBE_PROTECTED"])
    own = work / "exec-leaf-own.txt"
    result = {
        "own_write": attempt("own_write", lambda: own.write_text("exec-leaf\n")),
        "protected_read": attempt("protected_read", lambda: protected.read_text()),
    }
    print(json.dumps(result, sort_keys=True))


def run_signal_target():
    status = Path(os.environ["PROBE_SIGNAL_STATUS"])
    ready = Path(os.environ["PROBE_SIGNAL_READY"])
    stop = Path(os.environ["PROBE_SIGNAL_STOP"])
    received = []

    def on_signal(signum, _frame):
        received.append(signum)
        status.write_text(f"signals={len(received)}\n")

    signal.signal(signal.SIGUSR1, on_signal)
    ready.write_text(str(os.getpid()) + "\n")
    deadline = time.monotonic() + 8.0
    while not stop.exists() and time.monotonic() < deadline:
        time.sleep(0.05)
    status.write_text(f"signals={len(received)}\n")


def main():
    mode = sys.argv[1]
    if mode == "controller":
        run_controller()
    elif mode == "signal-target":
        run_signal_target()
    elif mode in {"baseline", "sandbox", "clean-fds"}:
        inherited_handles(mode)
    elif mode == "exec-leaf":
        run_exec_leaf()
    else:
        raise SystemExit(f"unknown mode: {mode}")


if __name__ == "__main__":
    main()
'''


def wait_for_file(path: Path, process: subprocess.Popen[str], timeout: float = 3.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.is_file() and path.read_text().strip():
            return
        if process.poll() is not None:
            stdout, stderr = process.communicate(timeout=0.5)
            raise RuntimeError(
                f"process exited before readiness: rc={process.returncode}, "
                f"stdout={stdout!r}, stderr={stderr!r}"
            )
        time.sleep(0.03)
    raise TimeoutError(f"readiness timeout: {path}")


def process_group_exists(pgid: int) -> bool:
    try:
        os.killpg(pgid, 0)
    except ProcessLookupError:
        return False
    return True


def sbpl_literal(path: Path) -> str:
    value = str(path)
    if "\\" in value or '"' in value:
        raise ValueError(f"unsupported SBPL path: {value!r}")
    return value


def write_profile(path: Path, work: Path) -> None:
    work = work.resolve()
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
                f'(allow file-read* (subpath "{sbpl_literal(Path("/opt/homebrew"))}"))',
                f'(allow file-map-executable (subpath "{sbpl_literal(Path("/opt/homebrew"))}"))',
                f'(allow file-read* (subpath "{sbpl_literal(work)}"))',
                f'(allow file-write-data file-write-create file-write-unlink (subpath "{sbpl_literal(work)}"))',
                "",
            ]
        )
    )


def run_helper(mode: str, env: dict[str, str], *, pass_fds: tuple[int, ...] = ()) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(PYTHON), "-S", "helper.py", mode],
        cwd=env["PROBE_WORK"],
        env=env,
        text=True,
        capture_output=True,
        timeout=8.0,
        check=False,
        pass_fds=pass_fds,
    )


def parse_checks(result: subprocess.CompletedProcess[str]) -> dict[str, dict]:
    if result.returncode != 0:
        raise AssertionError(f"helper failed: rc={result.returncode}, stdout={result.stdout!r}, stderr={result.stderr!r}")
    payload = json.loads(result.stdout)
    return {check["label"]: check for check in payload["checks"]}


def assert_positive_control(checks: dict[str, dict]) -> None:
    for label, check in checks.items():
        if not check["ok"]:
            raise AssertionError(f"outside-sandbox control failed for {label}: {check!r}")


def assert_denial(check: dict, label: str) -> None:
    if check["ok"] or check["errno"] not in DENIAL_ERRNOS:
        raise AssertionError(f"{label} was not an EPERM/EACCES denial: {check!r}")


def stop_process(process: subprocess.Popen[str], stop_file: Path | None = None) -> None:
    if process.poll() is None and stop_file is not None:
        stop_file.write_text("stop\n")
    if process.poll() is None:
        try:
            process.wait(timeout=2.0)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2.0)
    if process.poll() is None:
        raise AssertionError(f"owned process did not terminate: pid={process.pid}")


def main() -> int:
    if sys.platform != "darwin":
        print("SKIP: macOS-only inherited-handle/IPC probe", file=sys.stderr)
        return 0
    sandbox_exec = Path("/usr/bin/sandbox-exec")
    if not sandbox_exec.is_file():
        print("ERROR: /usr/bin/sandbox-exec missing", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory(prefix="wbsi-", dir="/tmp") as root_name:
        root = Path(root_name)
        work = root / "work-root"
        protected_dir = root / "outside-control"
        work.mkdir()
        protected_dir.mkdir()
        protected_read = protected_dir / "read.txt"
        protected_write = protected_dir / "write.txt"
        protected_read.write_text("protected-read\n")
        protected_write.write_text("")
        helper = work / "helper.py"
        helper.write_text(HELPER_SOURCE)
        profile = root / "probe.sb"
        write_profile(profile, work)

        controller_socket = work / "controller.sock"
        controller_ready = work / "controller-ready"
        controller_stop = work / "controller-stop"
        controller_status = work / "controller-status.json"
        signal_ready = work / "signal-ready"
        signal_stop = work / "signal-stop"
        signal_status = work / "signal-status"

        read_fd = os.open(protected_read, os.O_RDONLY)
        write_fd = os.open(protected_write, os.O_WRONLY)
        socket_client = None
        controller = None
        signal_target = None
        sandbox = None
        socket_controller_fd = None
        try:
            os.set_inheritable(read_fd, True)
            os.set_inheritable(write_fd, True)
            socket_controller_fd, socket_client = socket.socketpair(socket.AF_UNIX, socket.SOCK_STREAM)
            socket_controller_fd.set_inheritable(True)
            socket_client.set_inheritable(True)

            env = {
                "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
                "HOME": str(root),
                "TMPDIR": str(root),
                "PYTHONNOUSERSITE": "1",
                "LC_ALL": "C",
                "PROBE_WORK": str(work),
                "PROBE_PROTECTED": str(protected_read),
                "PROBE_READ_FD": str(read_fd),
                "PROBE_WRITE_FD": str(write_fd),
                "PROBE_SOCKET_FD": str(socket_client.fileno()),
                "PROBE_CONTROLLER_FD": str(socket_controller_fd.fileno()),
                "PROBE_CONTROLLER_SOCKET": str(controller_socket),
                "PROBE_CONTROLLER_READY": str(controller_ready),
                "PROBE_CONTROLLER_STOP": str(controller_stop),
                "PROBE_CONTROLLER_STATUS": str(controller_status),
                "PROBE_SIGNAL_READY": str(signal_ready),
                "PROBE_SIGNAL_STOP": str(signal_stop),
                "PROBE_SIGNAL_STATUS": str(signal_status),
            }

            controller = subprocess.Popen(
                [str(PYTHON), "-S", "helper.py", "controller"],
                cwd=work,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True,
                pass_fds=(socket_controller_fd.fileno(),),
            )
            wait_for_file(controller_ready, controller)

            signal_target = subprocess.Popen(
                [str(PYTHON), "-S", "helper.py", "signal-target"],
                cwd=work,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True,
            )
            wait_for_file(signal_ready, signal_target)

            # Positive controls happen before entering the sandbox.
            socket_client.sendall(b"host-control\n")
            baseline = parse_checks(run_helper("baseline", env, pass_fds=(read_fd, write_fd, socket_client.fileno())))
            assert_positive_control(baseline)
            os.lseek(read_fd, 0, os.SEEK_SET)
            os.kill(int(signal_ready.read_text()), signal.SIGUSR1)
            wait_for_file(signal_status, signal_target)
            if signal_status.read_text().strip() != "signals=1":
                raise AssertionError(f"signal positive control failed: {signal_status.read_text()!r}")

            sandbox = subprocess.Popen(
                [str(sandbox_exec), "-f", str(profile), str(PYTHON), "-S", "helper.py", "sandbox"],
                cwd=work,
                env={**env, "PROBE_SIGNAL_PID": signal_ready.read_text().strip()},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True,
                pass_fds=(read_fd, write_fd, socket_client.fileno()),
            )
            try:
                sandbox_stdout, sandbox_stderr = sandbox.communicate(timeout=12.0)
            except subprocess.TimeoutExpired:
                os.killpg(sandbox.pid, signal.SIGKILL)
                sandbox_stdout, sandbox_stderr = sandbox.communicate(timeout=2.0)
                raise AssertionError(f"sandbox process group timed out: stdout={sandbox_stdout!r}, stderr={sandbox_stderr!r}")
            if sandbox.returncode != 0:
                raise AssertionError(f"sandbox failed: rc={sandbox.returncode}, stdout={sandbox_stdout!r}, stderr={sandbox_stderr!r}")
            if process_group_exists(sandbox.pid):
                os.killpg(sandbox.pid, signal.SIGKILL)
                sandbox.wait(timeout=2.0)
                raise AssertionError("sandbox process group remained after completion")
            sandbox_checks = parse_checks(subprocess.CompletedProcess([], 0, sandbox_stdout, sandbox_stderr))
            if not all(sandbox_checks[label]["ok"] for label in ("inherited_file_read", "inherited_file_write", "inherited_socket_send", "exec_child")):
                raise AssertionError(f"inherited handle or exec pass-through unexpectedly failed: {sandbox_checks!r}")
            assert_denial(sandbox_checks["direct_unix_connect"], "direct Unix socket connect")
            signal_check = sandbox_checks["signal_external_target"]
            if not signal_check["ok"]:
                assert_denial(signal_check, "signal to external target")

            signal_count_after = signal_status.read_text().strip()
            if signal_check["ok"] and signal_count_after != "signals=2":
                raise AssertionError(f"signal pass-through reported success without target signal: {signal_count_after!r}")
            if not signal_check["ok"] and signal_count_after != "signals=1":
                raise AssertionError(f"denied signal changed target state: {signal_count_after!r}")

            clean_env = {**env, "PROBE_SIGNAL_PID": signal_ready.read_text().strip()}
            clean = parse_checks(
                subprocess.run(
                    [str(sandbox_exec), "-f", str(profile), str(PYTHON), "-S", "helper.py", "clean-fds"],
                    cwd=work,
                    env=clean_env,
                    text=True,
                    capture_output=True,
                    timeout=8.0,
                    check=False,
                    close_fds=True,
                )
            )
            for label in ("closed_file_read", "closed_file_write", "closed_socket_send"):
                if clean[label]["ok"] or clean[label]["errno"] != errno.EBADF:
                    raise AssertionError(f"close_fds counterprobe leaked {label}: {clean[label]!r}")

            print("PASS: outside-sandbox file/socket/signal controls succeeded")
            print("PASS: pre-opened file and Unix socket descriptors remained usable in sandbox")
            print("PASS: direct Unix socket connect denied; exec child inherited sandbox restrictions")
            print(f"PASS: signal result={signal_check['error'] or 'allowed'}; close_fds counterprobe returned EBADF")
            print(json.dumps({"sandbox": sandbox_checks, "clean_fds": clean, "signal_status": signal_count_after}, sort_keys=True))
        finally:
            if socket_client is not None:
                socket_client.close()
            if socket_controller_fd is not None:
                socket_controller_fd.close()
            stop_process(controller, controller_stop) if controller is not None else None
            stop_process(signal_target, signal_stop) if signal_target is not None else None
            if sandbox is not None and sandbox.poll() is None:
                os.killpg(sandbox.pid, signal.SIGKILL)
                sandbox.wait(timeout=2.0)
            os.close(read_fd)
            os.close(write_fd)

        if not controller_status.is_file():
            raise AssertionError("controller produced no status")
        messages = json.loads(controller_status.read_text())["messages"]
        if messages != ["host-control", "baseline-inherited", "sandbox-inherited"]:
            raise AssertionError(f"unexpected controller messages: {messages!r}")
        if protected_write.read_text() != "BS":
            raise AssertionError(f"inherited write descriptor result mismatch: {protected_write.read_text()!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
