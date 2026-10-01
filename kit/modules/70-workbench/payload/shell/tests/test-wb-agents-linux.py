#!/usr/bin/env python3
"""Focused integration tests for the Linux Agents execution boundary."""

from __future__ import annotations

import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHELL))

import agents_lauf as al  # noqa: E402
import agents_linux as linux  # noqa: E402


PROBE = r'''import json
import os
import pwd
import socket
import subprocess
import sys
import time
from pathlib import Path

work = Path(sys.argv[1])
read_root = Path(sys.argv[2])
outside = Path(sys.argv[3])
controller = Path(sys.argv[4])
port = int(sys.argv[5])

def readable(path):
    try:
        path.read_bytes()
        return True
    except OSError:
        return False

def writable(path):
    try:
        path.write_text("escaped", encoding="utf-8")
        return True
    except OSError:
        return False

def connectable(host, target_port):
    sock = socket.socket()
    sock.settimeout(0.4)
    try:
        sock.connect((host, target_port))
        return True
    except OSError:
        return False
    finally:
        sock.close()

child = subprocess.Popen(
    [sys.executable, "-c", "import time; time.sleep(120)"],
    start_new_session=True,
)
payload = {
    "input": (read_root / "input.txt").read_text(encoding="utf-8"),
    "own_write": True,
    "outside_read": readable(outside / "protected.txt"),
    "outside_write": writable(outside / "agent-created.txt"),
    "symlink_read": readable(work / "escape" / "protected.txt"),
    "symlink_write": writable(work / "escape" / "agent-created.txt"),
    "host_loopback": connectable("127.0.0.1", port),
    "external_network": connectable("1.1.1.1", 53),
    "host_home_visible": Path(pwd.getpwuid(os.getuid()).pw_dir).exists(),
    "host_cgroup_visible": Path("/sys/fs/cgroup").exists(),
    "host_dbus_visible": Path(f"/run/user/{os.getuid()}/bus").exists(),
    "docker_socket_visible": Path("/var/run/docker.sock").exists(),
    "controller_visible": controller.exists(),
    "marker": os.environ.get("AGENT_TEST_MARKER"),
    "ssh_env": os.environ.get("SSH_AUTH_SOCK"),
    "dbus_env": os.environ.get("DBUS_SESSION_BUS_ADDRESS"),
    "home": os.environ.get("HOME"),
    "child_pid": child.pid,
    "root_pid": os.getpid(),
    "root_pgid": os.getpgrp(),
    "child_pgid": os.getpgid(child.pid),
    "child_sid": os.getsid(child.pid),
}
(work / "probe.json").write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
while True:
    time.sleep(1)
'''

SHORT_PROBE = r'''import sys
import time
from pathlib import Path
Path(sys.argv[1]).write_text("one", encoding="utf-8")
time.sleep(0.8)
raise SystemExit(7)
'''


def wait_until(predicate, timeout=8.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    return None


@unittest.skipUnless(sys.platform == "linux", "Linux-only integration test")
class LinuxLauncherTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.systemctl = os.environ.get("WB_TEST_SYSTEMCTL") or shutil.which("systemctl")
        cls.systemd_run = os.environ.get("WB_TEST_SYSTEMD_RUN") or shutil.which("systemd-run")
        cls.bwrap = os.environ.get("WB_TEST_BWRAP") or shutil.which("bwrap")
        if not all((cls.systemctl, cls.systemd_run, cls.bwrap)):
            raise unittest.SkipTest("systemctl, systemd-run oder bwrap fehlt")
        check = subprocess.run(
            [cls.systemctl, "--user", "show", "--property=Version", "--value"],
            text=True, capture_output=True,
        )
        if check.returncode != 0 or not check.stdout.strip():
            raise unittest.SkipTest("systemd --user ist nicht erreichbar")

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="wb-agents-linux-", dir="/tmp")
        self.root = Path(self.tmp.name)
        self.work = self.root / "work"
        self.read_root = self.root / "read"
        self.outside = self.root / "outside"
        self.controller_root = self.root / "controller"
        self.state = self.root / "launcher-state"
        for path in (self.work, self.read_root, self.outside, self.controller_root, self.state):
            path.mkdir(mode=0o700)
        (self.read_root / "input.txt").write_text("allowed", encoding="utf-8")
        (self.read_root / "probe.py").write_text(PROBE, encoding="utf-8")
        (self.read_root / "short_probe.py").write_text(SHORT_PROBE, encoding="utf-8")
        (self.outside / "protected.txt").write_text("protected", encoding="utf-8")
        (self.work / "escape").symlink_to(self.outside, target_is_directory=True)
        self.register = self.controller_root / "runs.json"
        self.unit_prefix = f"wb-agents-linux-test-{uuid.uuid4().hex[:12]}-"
        self.launchers = []
        self.receipts = []
        self.neighbor = None

    def tearDown(self):
        for launcher, receipt in reversed(self.receipts):
            try:
                observation = launcher.observe(receipt, self._long_spec(1))
                if observation.state in {"running", "paused"}:
                    launcher.terminate(receipt)
            except Exception:
                pass
        if self.neighbor is not None and self.neighbor.poll() is None:
            os.kill(self.neighbor.pid, signal.SIGTERM)
            self.neighbor.wait(timeout=3)
        remaining = []
        for launcher in self.launchers:
            for record_path in launcher.state_dir.glob("*.json"):
                try:
                    unit = json.loads(record_path.read_text(encoding="utf-8"))["unit"]
                    shown = launcher._show(unit)
                    if shown.get("LoadState") == "loaded":
                        if shown.get("FreezerState") == "frozen":
                            subprocess.run([self.systemctl, "--user", "thaw", unit], timeout=5)
                        subprocess.run([self.systemctl, "--user", "stop", unit], timeout=5)
                        subprocess.run([self.systemctl, "--user", "reset-failed", unit], timeout=5)
                    if launcher._cgroup_pids(json.loads(record_path.read_text())["control_group"]):
                        remaining.append(unit)
                except (KeyError, OSError, ValueError):
                    pass
        self.assertEqual(remaining, [], f"test cgroups still populated: {remaining}")
        self.tmp.cleanup()

    def _launcher(self):
        launcher = linux.LinuxLauncher(
            self.state,
            read_paths=(self.read_root,),
            write_paths=(self.work,),
            allowed_env_names=("AGENT_TEST_MARKER",),
            unit_prefix=self.unit_prefix,
            stop_timeout=1.0,
            systemctl=self.systemctl,
            systemd_run=self.systemd_run,
            bwrap=self.bwrap,
        )
        self.launchers.append(launcher)
        return launcher

    def _long_spec(self, port):
        return al.StartSpec(
            (
                "/usr/bin/python3", str(self.read_root / "probe.py"), str(self.work),
                str(self.read_root), str(self.outside), str(self.register), str(port),
            ),
            str(self.work),
            (("AGENT_TEST_MARKER", "present"),),
        )

    def test_scope_validation_fails_closed(self):
        with self.assertRaises(ValueError):
            linux.LinuxLauncher(
                self.state, unit_prefix="wb-agents-linux-" + "a" * 72 + "-",
                systemctl=self.systemctl, systemd_run=self.systemd_run, bwrap=self.bwrap,
            )
        with self.assertRaises(ValueError):
            linux.LinuxLauncher(
                self.state, read_paths=(Path.home(),), systemctl=self.systemctl,
                systemd_run=self.systemd_run, bwrap=self.bwrap,
            )
        with self.assertRaises(ValueError):
            linux.LinuxLauncher(
                self.state, write_paths=(self.state,), systemctl=self.systemctl,
                systemd_run=self.systemd_run, bwrap=self.bwrap,
            )
        launcher = self._launcher()
        bad = al.StartSpec(("/usr/bin/true",), str(self.work), (("SSH_AUTH_SOCK", "x"),))
        with self.assertRaises(ValueError):
            launcher.launch(bad)

    def test_failed_receipt_verification_cleans_its_unit(self):
        class RejectingLauncher(linux.LinuxLauncher):
            def verify(self, receipt, spec):
                return False

        launcher = RejectingLauncher(
            self.state,
            read_paths=(self.read_root,),
            write_paths=(self.work,),
            unit_prefix=self.unit_prefix,
            stop_timeout=1.0,
            systemctl=self.systemctl,
            systemd_run=self.systemd_run,
            bwrap=self.bwrap,
        )
        self.launchers.append(launcher)
        spec = al.StartSpec(("/usr/bin/sleep", "120"), str(self.work))
        with self.assertRaises(linux.LinuxIdentitaetUnklar):
            launcher.launch(spec)
        records = list(self.state.glob("*.json"))
        self.assertEqual(len(records), 1)
        record = json.loads(records[0].read_text(encoding="utf-8"))
        self.assertEqual(record["phase"], "stopped")
        self.assertTrue(record["cleanup_verified"])
        self.assertEqual(launcher._show(record["unit"]).get("LoadState"), "not-found")

    def test_isolation_identity_pause_restart_and_cgroup_stop(self):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        port = listener.getsockname()[1]
        self.neighbor = subprocess.Popen(["/usr/bin/sleep", "120"], start_new_session=True)
        neighbor_pid = self.neighbor.pid

        launcher = self._launcher()
        controller = al.RunController(self.register, launcher=launcher)
        spec = self._long_spec(port)
        handle = controller.start("world", "agent", "run-1", spec)
        self.receipts.append((launcher, handle.receipt))
        payload_path = self.work / "probe.json"
        self.assertIsNotNone(wait_until(payload_path.exists), "sandbox probe produced no output")
        payload = json.loads(payload_path.read_text(encoding="utf-8"))
        self.assertEqual(payload["input"], "allowed")
        self.assertEqual(payload["marker"], "present")
        self.assertEqual(payload["home"], "/home/agent")
        for field in (
            "outside_read", "outside_write", "symlink_read", "symlink_write", "host_loopback",
            "external_network", "host_home_visible", "host_cgroup_visible", "host_dbus_visible",
            "docker_socket_visible", "controller_visible",
        ):
            self.assertFalse(payload[field], field)
        self.assertIsNone(payload["ssh_env"])
        self.assertIsNone(payload["dbus_env"])
        self.assertNotEqual(payload["root_pgid"], payload["child_pgid"])
        self.assertEqual(payload["child_pgid"], payload["child_sid"])

        identity = launcher.receipt_details(handle.receipt)
        properties = launcher._show(identity["unit"])
        self.assertEqual(properties["InvocationID"], identity["invocation_id"])
        self.assertEqual(int(properties["MainPID"]), handle.receipt.pid)
        self.assertEqual(properties["KillMode"], "control-group")
        self.assertEqual(properties["Restart"], "no")
        self.assertEqual(properties["Delegate"], "no")
        self.assertEqual(os.readlink(f"/proc/{handle.receipt.pid}/exe"), str(Path(self.bwrap).resolve()))
        cgroup_pids = launcher._cgroup_pids(identity["control_group"])
        self.assertIn(handle.receipt.pid, cgroup_pids)
        self.assertGreaterEqual(len(cgroup_pids), 3)

        forged = dict(identity)
        forged["invocation_id"] = "0" * 32
        fake = al.LaunchReceipt(
            handle.receipt.pid, handle.receipt.process_group_id,
            json.dumps(forged, sort_keys=True, separators=(",", ":")),
        )
        self.assertFalse(launcher.verify(fake, spec))

        restarted_launcher = self._launcher()
        restarted = al.RunController(self.register, launcher=restarted_launcher)
        adopted = restarted.status("world", "agent")
        self.assertEqual((adopted.run_id, adopted.receipt.identity), ("run-1", handle.receipt.identity))
        with self.assertRaises(linux.CheckpointNichtUnterstuetzt):
            restarted_launcher.request_pause(handle.receipt)
        self.assertEqual(restarted.status("world", "agent").observed_state, "running")
        restarted_launcher.freeze(handle.receipt)
        self.assertIsNotNone(wait_until(lambda: restarted.status("world", "agent").observed_state == "paused"))
        with self.assertRaises(linux.CheckpointNichtUnterstuetzt):
            restarted_launcher.confirm_checkpoint(handle.receipt, spec, "not-a-real-checkpoint")
        restarted_launcher.thaw(handle.receipt)
        self.assertIsNotNone(wait_until(lambda: restarted.status("world", "agent").observed_state == "running"))
        restarted_launcher.freeze(handle.receipt)
        self.assertIsNotNone(wait_until(lambda: restarted.status("world", "agent").observed_state == "paused"))

        stopped = restarted.stop("world", "agent")
        self.assertEqual(stopped.observed_state, "stopped")
        self.assertEqual(restarted_launcher._cgroup_pids(identity["control_group"]), ())
        self.assertEqual(restarted_launcher._show(identity["unit"]).get("LoadState"), "not-found")
        self.assertIsNone(self.neighbor.poll(), "neighbor process was killed with sandbox cgroup")
        self.assertEqual(self.neighbor.pid, neighbor_pid)
        listener.close()

        after_restart = self._launcher()
        self.assertIsNone(al.RunController(self.register, launcher=after_restart).status("world", "agent"))
        self.assertFalse(after_restart.verify(fake, spec))

    def test_agent_worktree_commits_on_its_branch_while_project_and_git_admin_stay_read_only(self):
        # Worktree je Agent (16.09.2026): .git als tmpfs mit den gemessenen Teilen (agents_worktree).
        import agents_worktree as aw

        projekt = self.read_root / "projekt"
        projekt.mkdir()
        ident = ["-c", "user.name=mensch", "-c", "user.email=m@example.invalid"]
        for args in (["init", "-q", "-b", "main"], ["commit", "-q", "--allow-empty", "-m", "init"]):
            subprocess.run(["git", *ident, *args], cwd=projekt, check=True)
        (projekt / "README.md").write_text("mensch\n", encoding="utf-8")
        baum = aw.bereitstellen(projekt, self.work, "a1")
        andere = aw.bereitstellen(projekt, self.outside, "a2")
        haupt = subprocess.run(["git", "rev-parse", "main"], cwd=projekt, capture_output=True, text=True).stdout
        code = r"""import json, os, subprocess, sys
baum, projekt, andere, ziel = sys.argv[1:5]
env = dict(os.environ, **json.loads(sys.argv[5]))
def git(*args):
    r = subprocess.run(["git", *args], cwd=baum, env=env, capture_output=True, text=True)
    return [r.returncode, (r.stdout + r.stderr).strip()[-300:]]
def schreiben(pfad):
    try:
        open(pfad, "w").write("x")
        return True
    except OSError:
        return False
open(os.path.join(baum, "neu.txt"), "w").write("vom agenten")
ergebnis = {"add": git("add", "neu.txt"), "commit": git("commit", "-q", "-m", "agent"),
            "rebase": git("rebase", "main"), "cherry": os.path.exists(os.path.join(projekt, ".git/worktrees/a1/CHERRY_PICK_HEAD")),
            "main": git("update-ref", "refs/heads/main", "HEAD"), "fremd": git("checkout", "agent/a2"),
            "readme": schreiben(os.path.join(projekt, "README.md")),
            "config": schreiben(os.path.join(projekt, ".git/config")),
            "commondir": schreiben(os.path.join(projekt, ".git/commondir")),
            "andere_head": schreiben(os.path.join(projekt, ".git/worktrees/a2/HEAD")),
            "alternates": schreiben(os.path.join(projekt, ".git/objects/info/alternates"))}
open(ziel, "w").write(json.dumps(ergebnis))
"""
        (self.read_root / "git_probe.py").write_text(code, encoding="utf-8")
        launcher = linux.LinuxLauncher(
            self.state, read_paths=(self.read_root,), write_paths=(self.work,), unit_prefix=self.unit_prefix,
            stop_timeout=1.0, systemctl=self.systemctl, systemd_run=self.systemd_run, bwrap=self.bwrap,
            git_einbindung=baum.einbindung())
        self.launchers.append(launcher)
        env = json.dumps(baum.git_umgebung("a1"))
        spec = al.StartSpec(("/usr/bin/python3", str(self.read_root / "git_probe.py"), str(baum.pfad), str(projekt),
                             str(andere.pfad), str(self.work / "git.json"), env), str(baum.pfad))
        command = launcher._bwrap_command(spec)
        tmpfs = command.index(str(projekt / ".git"))
        self.assertEqual(command[tmpfs - 1], "--tmpfs")
        self.assertLess(command.index(str(projekt / ".git/objects")), command.index(str(projekt / ".git/objects/pack")))
        receipt = launcher.launch(spec)
        self.receipts.append((launcher, receipt))
        self.assertIsNotNone(wait_until(lambda: launcher.observe(receipt, spec).state == "stopped", 60))
        result = json.loads((self.work / "git.json").read_text())
        self.assertEqual((result["add"][0], result["commit"][0], result["rebase"][0]), (0, 0, 0), result)
        self.assertFalse(result["cherry"], result)
        self.assertNotEqual(result["main"][0], 0, result)
        self.assertNotEqual(result["fremd"][0], 0, result)
        self.assertEqual([result[k] for k in ("readme", "config", "commondir", "andere_head", "alternates")],
                         [False, False, True, False, False], result)
        self.assertFalse((projekt / ".git/commondir").exists(), "tmpfs-Datei erreichte den Host")
        self.assertEqual(subprocess.run(["git", "rev-parse", "main"], cwd=projekt, capture_output=True,
                                        text=True).stdout, haupt)
        log = subprocess.run(["git", "log", "--format=%s", "agent/a1"], cwd=projekt, capture_output=True, text=True)
        self.assertEqual(log.stdout.split("\n")[0], "agent")
        self.assertEqual((projekt / "README.md").read_text(encoding="utf-8"), "mensch\n")
        # Ein Plan ausserhalb des Repos oder ohne Projekt unter den Lesepfaden wird abgewiesen.
        falsch = dict(baum.einbindung(), schreiben=[str(self.outside)])
        with self.assertRaises(ValueError):
            linux.LinuxLauncher(self.state, read_paths=(self.read_root,), unit_prefix=self.unit_prefix,
                                systemctl=self.systemctl, systemd_run=self.systemd_run, bwrap=self.bwrap,
                                git_einbindung=falsch)
        ohne_projekt = linux.LinuxLauncher(self.state, write_paths=(self.work,), unit_prefix=self.unit_prefix,
                                           systemctl=self.systemctl, systemd_run=self.systemd_run, bwrap=self.bwrap,
                                           git_einbindung=baum.einbindung())
        with self.assertRaises(ValueError):
            ohne_projekt.launch(spec)

    def test_brain_kbase_read_only_with_hidden_secret_folders_and_search_wrapper(self):
        """Brain im Zug (16.09.2026): Kbase nur lesbar, 90-secrets und .secrets-sync als leeres tmpfs, brain search."""
        kbase = self.root / "kbase"
        for rel, text in (("20-projects/p/box.md", "---\ntitle: box\n---\n\nHostco Box im Brain.\n"),
                          ("90-secrets/key.md", "Hostco Box geheim\n"), (".secrets-sync/key", "geheim\n")):
            (kbase / rel).parent.mkdir(parents=True, exist_ok=True)
            (kbase / rel).write_text(text, encoding="utf-8")
        code = r"""import json, os, subprocess, sys
kbase, shell, ziel = sys.argv[1:4]
def lesen(pfad):
    try:
        return open(pfad).read()
    except OSError:
        return None
def schreiben(pfad):
    try:
        open(pfad, "w").write("x")
        return True
    except OSError:
        return False
suche = subprocess.run(["/usr/bin/python3", os.path.join(shell, "agents_brain.py"), "search", "Hostco Box",
                        "--json"], env={"WB_BRAIN_KBASE": kbase, "PATH": "/usr/bin:/bin", "HOME": "/tmp"},
                       capture_output=True, text=True)
ergebnis = {"note": lesen(os.path.join(kbase, "20-projects/p/box.md")),
            "geheim": lesen(os.path.join(kbase, "90-secrets/key.md")),
            "geheim_liste": sorted(os.listdir(os.path.join(kbase, "90-secrets"))),
            "sync_liste": sorted(os.listdir(os.path.join(kbase, ".secrets-sync"))),
            "schreiben": schreiben(os.path.join(kbase, "20-projects/p/neu.md")),
            "geheim_schreiben": schreiben(os.path.join(kbase, "90-secrets/neu.md")),
            "suche": [suche.returncode, json.loads(suche.stdout)["hits"] if suche.returncode == 0 else suche.stderr]}
open(ziel, "w").write(json.dumps(ergebnis))
"""
        (self.read_root / "brain_probe.py").write_text(code, encoding="utf-8")
        verdeckt = (kbase / "90-secrets", kbase / ".secrets-sync")
        launcher = linux.LinuxLauncher(
            self.state, read_paths=(self.read_root, kbase, SHELL), write_paths=(self.work,),
            unit_prefix=self.unit_prefix, stop_timeout=1.0, systemctl=self.systemctl, systemd_run=self.systemd_run,
            bwrap=self.bwrap, verdeckt=verdeckt)
        self.launchers.append(launcher)
        spec = al.StartSpec(("/usr/bin/python3", str(self.read_root / "brain_probe.py"), str(kbase), str(SHELL),
                             str(self.work / "brain.json")), str(self.work))
        command = launcher._bwrap_command(spec)
        for path in verdeckt:
            self.assertEqual(command[command.index(str(path)) - 1], "--tmpfs")
            self.assertGreater(command.index(str(path)), command.index(str(kbase)))
        receipt = launcher.launch(spec)
        self.receipts.append((launcher, receipt))
        self.assertIsNotNone(wait_until(lambda: launcher.observe(receipt, spec).state == "stopped", 60))
        result = json.loads((self.work / "brain.json").read_text())
        self.assertEqual(result["note"], "---\ntitle: box\n---\n\nHostco Box im Brain.\n")
        self.assertEqual((result["geheim"], result["geheim_liste"], result["sync_liste"]), (None, [], []))
        self.assertEqual((result["schreiben"], result["geheim_schreiben"]), (False, True), result)
        self.assertEqual(result["suche"][0], 0, result)
        self.assertEqual([hit["rel"] for hit in result["suche"][1]], ["20-projects/p/box.md"])
        self.assertEqual((kbase / "90-secrets/key.md").read_text(), "Hostco Box geheim\n")
        self.assertFalse((kbase / "90-secrets/neu.md").exists(), "tmpfs-Datei erreichte den Host")
        # Verdeckt nur innerhalb eines Nur-Lese-Pfads; ein Symlink an seiner Stelle bricht den Start ab.
        with self.assertRaises(ValueError):
            linux.LinuxLauncher(self.state, read_paths=(self.read_root,), write_paths=(self.work,),
                                unit_prefix=self.unit_prefix, systemctl=self.systemctl, systemd_run=self.systemd_run,
                                bwrap=self.bwrap, verdeckt=verdeckt)
        (kbase / ".secrets-sync/key").unlink()
        (kbase / ".secrets-sync").rmdir()
        (kbase / ".secrets-sync").symlink_to(self.outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            launcher._bwrap_command(spec)

    def test_natural_exit_is_recorded_without_restart(self):
        launcher = self._launcher()
        register = self.controller_root / "short-runs.json"
        controller = al.RunController(register, launcher=launcher)
        spec = al.StartSpec(
            ("/usr/bin/python3", str(self.read_root / "short_probe.py"), str(self.work / "short.txt")),
            str(self.work),
        )
        handle = controller.start("world", "short-agent", "short-run", spec)
        self.receipts.append((launcher, handle.receipt))

        stopped = wait_until(
            lambda: (value if (value := controller.status("world", "short-agent")) and value.observed_state == "stopped" else None),
            timeout=6,
        )
        self.assertIsNotNone(stopped)
        self.assertEqual(stopped.receipt.identity, handle.receipt.identity)
        self.assertEqual(stopped.observed_state, "stopped")
        self.assertEqual(stopped.receipt.pid, handle.receipt.pid)
        self.assertEqual((self.work / "short.txt").read_text(encoding="utf-8"), "one")
        time.sleep(0.2)
        restarted = self._launcher()
        self.assertIsNone(al.RunController(register, launcher=restarted).status("world", "short-agent"))
        details = restarted.receipt_details(handle.receipt)
        self.assertEqual(restarted._show(details["unit"]).get("LoadState"), "not-found")

    def test_beendet_belegt_only_without_active_unit_for_spec(self):
        launcher = self._launcher()
        spec = al.StartSpec(("/usr/bin/sleep", "120"), str(self.work))
        self.assertTrue(launcher.beendet_belegt("w", "a", "r", spec))
        receipt = launcher.launch(spec)
        self.receipts.append((launcher, receipt))
        self.assertFalse(launcher.beendet_belegt("w", "a", "r", spec))
        self.assertFalse(launcher.beendet_belegt("w", "a", "r", spec, receipt))
        other = al.StartSpec(("/usr/bin/sleep", "121"), str(self.work))
        self.assertTrue(launcher.beendet_belegt("w", "a", "r", other))
        launcher.terminate(receipt)
        self.assertTrue(launcher.beendet_belegt("w", "a", "r", spec, receipt))

        failing = self.root / "failing-systemd-run"
        failing.write_text("#!/bin/sh\necho 'Failed to start transient service unit' >&2\nexit 1\n")
        failing.chmod(0o700)
        broken = linux.LinuxLauncher(
            self.state, read_paths=(self.read_root,), write_paths=(self.work,), unit_prefix=self.unit_prefix,
            stop_timeout=1.0, systemctl=self.systemctl, systemd_run=str(failing), bwrap=self.bwrap)
        self.launchers.append(broken)
        failed_spec = al.StartSpec(("/usr/bin/sleep", "122"), str(self.work))
        with self.assertRaises(linux.LinuxLauncherFehler):
            broken.launch(failed_spec)
        self.assertTrue(launcher.beendet_belegt("w", "a", "r", failed_spec))

    def test_output_capture_uses_controller_files_outside_the_sandbox(self):
        output = self.controller_root / "output"
        output.mkdir(mode=0o700)
        with self.assertRaises(ValueError):
            linux.LinuxLauncher(self.state, write_paths=(self.work,), output_dir=self.work,
                                systemctl=self.systemctl, systemd_run=self.systemd_run, bwrap=self.bwrap)
        launcher = linux.LinuxLauncher(
            self.state, read_paths=(self.read_root,), write_paths=(self.work,), output_dir=output,
            unit_prefix=self.unit_prefix, stop_timeout=1.0,
            systemctl=self.systemctl, systemd_run=self.systemd_run, bwrap=self.bwrap)
        self.launchers.append(launcher)
        code = ("import os, pathlib, sys; print('stream-line', flush=True); "
                "print('diagnostic', file=sys.stderr, flush=True); "
                "pathlib.Path('seen.txt').write_text(str(pathlib.Path(%r).exists()))" % str(output))
        spec = al.StartSpec(("/usr/bin/python3", "-c", code), str(self.work))
        receipt = launcher.launch(spec)
        self.receipts.append((launcher, receipt))
        self.assertIsNotNone(wait_until(lambda: launcher.observe(receipt, spec).state == "stopped"))
        stdout, stderr = launcher.output_paths(receipt)
        self.assertEqual(stdout.parent, output)
        self.assertEqual(stdout.read_text(), "stream-line\n")
        self.assertEqual(stderr.read_text(), "diagnostic\n")
        self.assertEqual(stdout.stat().st_mode & 0o077, 0)
        self.assertEqual((self.work / "seen.txt").read_text(), "False")
        self.assertEqual(launcher.observe(receipt, spec).exit_code, 0)
        plain = self._launcher()
        with self.assertRaises(linux.LinuxLauncherFehler):
            plain.output_paths(receipt)

    def test_world_access_turn_reaches_a_local_sshd_only_through_its_wrappers(self):
        """Zugang einer Welt gegen einen eigenen sshd auf 127.0.0.1 mit Wegwerfschluesseln; ohne Zugang kein Netz."""
        import agents_data as ad
        import agents_zugaenge as az
        tools = {name: shutil.which(name, path="/usr/bin:/usr/sbin") for name in ("sshd", "ssh-keygen")}
        if not all(tools.values()) or not Path("/usr/bin/ssh").is_file():
            self.skipTest("sshd, ssh-keygen oder ssh fehlt")
        sshd_dir = self.controller_root / "sshd"
        sshd_dir.mkdir(mode=0o700)
        for name in ("host", "client"):
            subprocess.run([tools["ssh-keygen"], "-q", "-t", "ed25519", "-N", "", "-C", "wb-test", "-f",
                            str(sshd_dir / name)], check=True, timeout=30)
        (sshd_dir / "authorized_keys").write_text((sshd_dir / "client.pub").read_text())
        (sshd_dir / "authorized_keys").chmod(0o600)
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
        account = __import__("pwd").getpwuid(os.getuid()).pw_name
        (sshd_dir / "sshd_config").write_text("\n".join([
            "Port %d" % port, "ListenAddress 127.0.0.1", "HostKey %s" % (sshd_dir / "host"),
            "AuthorizedKeysFile %s" % (sshd_dir / "authorized_keys"), "PasswordAuthentication no",
            "KbdInteractiveAuthentication no", "UsePAM no", "StrictModes no", "PidFile %s" % (sshd_dir / "pid"),
            "AllowUsers %s" % account, "Subsystem sftp internal-sftp", ""]))
        log = (sshd_dir / "log").open("w")
        self.sshd = subprocess.Popen([tools["sshd"], "-D", "-e", "-f", str(sshd_dir / "sshd_config")],
                                     stdout=subprocess.DEVNULL, stderr=log)
        self.addCleanup(lambda: (self.sshd.terminate(), self.sshd.wait(timeout=5), log.close()))

        def listening():
            with socket.socket() as sock:
                sock.settimeout(0.2)
                return sock.connect_ex(("127.0.0.1", port)) == 0
        self.assertIsNotNone(wait_until(listening, 10), (sshd_dir / "log").read_text())
        host_key = (sshd_dir / "host.pub").read_text().split()
        (sshd_dir / "known_hosts").write_text("[127.0.0.1]:%d %s %s\n" % (port, host_key[0], host_key[1]))

        world = self.controller_root / "world"
        ad.create_world(world, name="Zugangsprobe", main_name="main")
        az.hinzufuegen(world, {"name": "probe", "ziel": "%s@127.0.0.1" % account, "port": port,
                               "schluessel": str(sshd_dir / "client"), "known_hosts": str(sshd_dir / "known_hosts")},
                       bestaetigt=True)
        turn = self.root / "turns" / "zug-1"
        turn.mkdir(mode=0o700, parents=True)
        zugang = az.bereitstellen(world, turn)
        self.assertEqual(zugang.namen, ("probe",))
        (self.work / "a.txt").write_text("hin", encoding="utf-8")
        remote_target = self.outside / "kopie.txt"
        code = r'''import json, pathlib, subprocess, sys
ordner, work, remote = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
def run(*argv):
    done = subprocess.run([str(a) for a in argv], capture_output=True, text=True, timeout=60)
    return [done.returncode, done.stdout.strip(), done.stderr.strip()[-300:]]
def writable(path):
    try:
        path.write_text("x")
        return True
    except OSError:
        return False
result = {
    "ssh": run(ordner / "ssh", "probe", "echo", "REMOTE-OK"),
    "unknown": run(ordner / "ssh", "anderer", "echo", "x"),
    "injection": run(ordner / "ssh", "probe", "-oProxyCommand=touch %s/injected" % work, "true"),
    "scp": run(ordner / "scp", work / "a.txt", "probe:" + remote),
    "rsync": run(ordner / "rsync", "-a", work / "a.txt", "probe:" + remote + ".rsync"),
    "direct_without_config": run("/usr/bin/ssh", "-oBatchMode=yes", "probe", "true"),
    "key_writable": writable(ordner / "probe" / "id"),
    "resolv_readable": pathlib.Path("/etc/resolv.conf").exists(),
}
(work / "zugang.json").write_text(json.dumps(result))
'''
        (self.read_root / "zugang_probe.py").write_text(code, encoding="utf-8")
        spec = al.StartSpec(("/usr/bin/python3", str(self.read_root / "zugang_probe.py"), str(zugang.ordner),
                             str(self.work), str(remote_target)), str(self.work))

        def launch(network):
            launcher = linux.LinuxLauncher(
                self.state, read_paths=(self.read_root, turn), write_paths=(self.work,), unit_prefix=self.unit_prefix,
                stop_timeout=1.0, systemctl=self.systemctl, systemd_run=self.systemd_run, bwrap=self.bwrap,
                network=network)
            self.launchers.append(launcher)
            self.assertIn("--share-net" if network else "--unshare-net", launcher._bwrap_command(spec))
            receipt = launcher.launch(spec)
            self.receipts.append((launcher, receipt))
            self.assertIsNotNone(wait_until(lambda: launcher.observe(receipt, spec).state == "stopped", 90))
            return json.loads((self.work / "zugang.json").read_text())

        result = launch(True)
        self.assertEqual(result["ssh"][:2], [0, "REMOTE-OK"], result)
        self.assertEqual(result["unknown"][0], 2, result)
        self.assertNotEqual(result["injection"][0], 0, result)
        self.assertFalse((self.work / "injected").exists(), "ssh-Option nach dem Namen lief lokal")
        self.assertEqual(result["scp"][0], 0, result)
        self.assertEqual(remote_target.read_text(), "hin")
        if Path("/usr/bin/rsync").is_file():
            self.assertEqual(result["rsync"][0], 0, result)
            self.assertEqual(Path(str(remote_target) + ".rsync").read_text(), "hin")
        self.assertNotEqual(result["direct_without_config"][0], 0, result)
        self.assertFalse(result["key_writable"])
        self.assertTrue(result["resolv_readable"])

        (self.work / "zugang.json").unlink()
        remote_target.unlink()
        closed = launch(False)
        self.assertNotEqual(closed["ssh"][0], 0, closed)
        self.assertFalse(remote_target.exists())
        self.assertTrue(az.aufraeumen(turn))
        self.assertFalse(zugang.ordner.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
