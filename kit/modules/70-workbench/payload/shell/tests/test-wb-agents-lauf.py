#!/usr/bin/env python3
"""Isolierte Vertragsproben fuer shell/agents_lauf.py."""

import os
import json
import signal
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHELL))

import agents_lauf as al  # noqa: E402


class DummyLauncher:
    """Verifizierte, ausschliesslich testlokale Startstrecke."""

    def __init__(self):
        self.processes = {}
        self.pause_requests = []
        self.resume_requests = []
        self.terminated = []
        self.mismatched = set()
        self.confirmed_checkpoints = set()
        self.observed_state = "running"
        self.before_pause = None
        self.before_terminate = None

    @staticmethod
    def _identity(pid):
        try:
            output = subprocess.check_output(
                ["ps", "-o", "lstart=", "-p", str(pid)], text=True, stderr=subprocess.DEVNULL
            ).strip()
        except (OSError, subprocess.CalledProcessError):
            return None
        return f"{pid}:{output}"

    def launch(self, spec):
        environment = os.environ.copy()
        environment.update(dict(spec.env))
        process = subprocess.Popen(spec.argv, cwd=spec.cwd, env=environment, start_new_session=True)
        receipt = al.LaunchReceipt(process.pid, os.getpgid(process.pid), self._identity(process.pid))
        self.processes[process.pid] = process
        return receipt

    def verify(self, receipt, spec):
        return (receipt.pid not in self.mismatched and self._identity(receipt.pid) == receipt.identity
                and os.getpgid(receipt.pid) == receipt.process_group_id)

    def observe(self, receipt, spec):
        process = self.processes.get(receipt.pid)
        if process is not None and process.poll() is not None:
            return al.Observation("stopped", True, process.returncode)
        if self._identity(receipt.pid) is None:
            return al.Observation("stopped", True)
        if not self.verify(receipt, spec):
            return al.Observation("unclear", False)
        return al.Observation(self.observed_state, True)

    def request_pause(self, receipt):
        if self.before_pause is not None:
            self.before_pause()
        self.pause_requests.append(receipt)

    def resume(self, receipt):
        self.resume_requests.append(receipt)

    def resolve(self, world, agent, run_id, spec):
        return None

    def confirm_checkpoint(self, receipt, spec, checkpoint_id):
        if checkpoint_id in self.confirmed_checkpoints:
            return al.Observation("paused", True, checkpoint_id=checkpoint_id)
        return al.Observation("running", True)

    def terminate(self, receipt):
        if self.before_terminate is not None:
            self.before_terminate()
        if not self.verify(receipt, None):
            raise RuntimeError("identity mismatch")
        self.terminated.append(receipt)
        os.killpg(receipt.process_group_id, signal.SIGTERM)
        process = self.processes.get(receipt.pid)
        if process is not None:
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(receipt.process_group_id, signal.SIGKILL)
                process.wait(timeout=2)

    def cleanup(self):
        for process in list(self.processes.values()):
            if process.poll() is None:
                try:
                    os.killpg(os.getpgid(process.pid), signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait(timeout=2)


class LaufTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-lauf-")
        self.root = Path(self.tmp.name)
        self.launcher = DummyLauncher()
        self.now = 1.0
        self.controller = al.RunController(
            self.root / "runs.json", launcher=self.launcher, clock=lambda: self.now
        )
        self.spec = al.StartSpec((sys.executable, "-c", "import time; time.sleep(30)"), str(self.root))

    def tearDown(self):
        self.launcher.cleanup()
        self.assertTrue(all(process.poll() is not None for process in self.launcher.processes.values()))
        self.tmp.cleanup()

    def test_stale_remote_controls_cannot_change_new_run(self):
        self.controller.start("world", "agent", "current", self.spec)
        before = (self.root / "runs.json").read_bytes()
        for operation in ("pause", "resume", "stop"):
            with self.subTest(operation=operation), self.assertRaises(al.VeralteteRueckmeldung):
                getattr(self.controller, operation)("world", "agent", expected_run_id="old")
            self.assertEqual((self.root / "runs.json").read_bytes(), before)
        self.assertEqual(self.launcher.terminated, [])
        self.controller.stop("world", "agent", expected_run_id="current")
        self.assertEqual(len(self.launcher.terminated), 1)

    def test_launcher_required_and_start_spec_immutable(self):
        with self.assertRaises(Exception):
            self.spec.argv = ("other",)
        without_launcher = al.RunController(self.root / "without.json")
        with self.assertRaises(al.KeineVerifizierteStartstrecke):
            without_launcher.start("world", "agent", "run-1", self.spec)

    def test_start_persists_tombstone_before_launcher_sideeffect(self):
        register = self.root / "ordered.json"

        class InspectingLauncher(DummyLauncher):
            def launch(inner, spec):
                state = json.loads(register.read_text())
                record = state["runs"]["run-1"]
                self.assertTrue(record["starting"])
                self.assertIsNone(record["receipt"])
                self.assertEqual(state["active"]["[\"world\",\"agent\"]"], "run-1")
                return super().launch(spec)

        self.launcher = InspectingLauncher()
        controller = al.RunController(register, launcher=self.launcher, clock=lambda: self.now)
        controller.start("world", "agent", "run-1", self.spec)

    def test_failed_start_keeps_unclear_tombstone_and_blocks_retry(self):
        register = self.root / "failed.json"

        class FailingLauncher(DummyLauncher):
            def launch(inner, spec):
                raise RuntimeError("launch failed")

        self.launcher = FailingLauncher()
        controller = al.RunController(register, launcher=self.launcher, clock=lambda: self.now)
        with self.assertRaises(al.LaufUngeklaert):
            controller.start("world", "agent", "run-1", self.spec)
        state = json.loads(register.read_text())
        record = state["runs"]["run-1"]
        self.assertEqual((record["starting"], record["observed_state"], record["receipt"]),
                         (False, "unclear", None))
        status = controller.status("world", "agent")
        self.assertEqual((status.run_id, status.observed_state, status.receipt),
                         ("run-1", "unclear", None))
        with self.assertRaises(al.LaufVerweigert):
            controller.start("world", "agent", "run-2", self.spec)

    def test_klaeren_releases_tombstone_only_with_proven_end(self):
        register = self.root / "klaeren.json"
        proofs = []

        class FailingLauncher(DummyLauncher):
            proven = False
            fail = True

            def launch(inner, spec):
                if inner.fail:
                    raise RuntimeError("launch failed")
                return DummyLauncher.launch(inner, spec)

            def beendet_belegt(inner, world, agent, run_id, spec, receipt):
                proofs.append((world, agent, run_id, receipt))
                return inner.proven

        self.launcher = FailingLauncher()
        controller = al.RunController(register, launcher=self.launcher, clock=lambda: self.now)
        self.assertIsNone(controller.klaeren("world", "agent"))
        with self.assertRaises(al.LaufUngeklaert):
            controller.start("world", "agent", "run-1", self.spec)
        self.assertEqual([item["run_id"] for item in controller.ungeklaert()], ["run-1"])
        with self.assertRaises(al.LaufUngeklaert):
            controller.klaeren("world", "agent")
        self.assertEqual(proofs, [("world", "agent", "run-1", None)])
        with self.assertRaises(al.LaufVerweigert):
            controller.start("world", "agent", "run-2", self.spec)
        self.launcher.proven = True
        cleared = controller.klaeren("world", "agent")
        self.assertEqual((cleared.run_id, cleared.observed_state), ("run-1", "stopped"))
        self.assertEqual(json.loads(register.read_text())["runs"]["run-1"]["klaerung"], "belegtes_ende")
        self.assertEqual(controller.ungeklaert(), [])
        self.launcher.fail = False
        handle = controller.start("world", "agent", "run-2", self.spec)
        # Ein lebender eigener Lauf wird uebernommen, nie durch einen Beleg geloest.
        self.assertEqual(controller.klaeren("world", "agent").observed_state, "running")
        self.assertIsNone(self.launcher.processes[handle.receipt.pid].poll())

    def test_invalid_receipt_keeps_unclear_tombstone_and_blocks_retry(self):
        register = self.root / "invalid.json"

        class InvalidLauncher(DummyLauncher):
            def launch(inner, spec):
                return object()

        self.launcher = InvalidLauncher()
        controller = al.RunController(register, launcher=self.launcher, clock=lambda: self.now)
        with self.assertRaises(al.LaufUngeklaert):
            controller.start("world", "agent", "run-1", self.spec)
        state = json.loads(register.read_text())
        record = state["runs"]["run-1"]
        self.assertEqual((record["observed_state"], record["receipt"]), ("unclear", None))
        with self.assertRaises(al.LaufVerweigert):
            controller.start("world", "agent", "run-2", self.spec)

    def test_concurrent_starts_allow_one_active_run(self):
        barrier = threading.Barrier(2)
        results = []

        def start(run_id):
            barrier.wait()
            try:
                results.append(self.controller.start("world", "agent", run_id, self.spec))
            except al.LaufFehler as exc:
                results.append(exc)

        threads = [threading.Thread(target=start, args=(f"run-{index}",)) for index in (1, 2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=5)
        self.assertEqual(sum(isinstance(result, al.RunHandle) for result in results), 1)
        self.assertEqual(sum(isinstance(result, al.LaufVerweigert) for result in results), 1)

    def test_pausing_observation_blocks_replacement_start(self):
        first = self.controller.start("world", "agent", "run-1", self.spec)
        self.launcher.observed_state = "pausing"
        with self.assertRaises(al.LaufVerweigert):
            self.controller.start("world", "agent", "run-2", self.spec)
        current = self.controller.status("world", "agent")
        self.assertEqual((current.run_id, current.observed_state), (first.run_id, "pausing"))

    def test_pause_checkpoint_resume_and_stop_are_separate_states(self):
        handle = self.controller.start("world", "agent", "run-1", self.spec)
        paused = self.controller.pause("world", "agent")
        self.assertEqual((paused.desired_state, paused.observed_state), ("paused", "running"))
        with self.assertRaises(al.LaufVerweigert):
            self.controller.start("world", "agent", "run-2", self.spec)
        with self.assertRaises(al.LaufVerweigert):
            self.controller.checkpoint("run-1", "checkpoint-1")
        self.assertEqual(self.controller.status("world", "agent").observed_state, "running")
        self.launcher.confirmed_checkpoints.add("checkpoint-1")
        checkpointed = self.controller.checkpoint("run-1", "checkpoint-1")
        self.assertEqual((checkpointed.desired_state, checkpointed.observed_state), ("paused", "paused"))
        resumed = self.controller.resume("world", "agent")
        self.assertEqual(resumed.desired_state, "running")
        stopped = self.controller.stop("world", "agent")
        self.assertEqual((stopped.desired_state, stopped.observed_state), ("stopped", "stopped"))
        self.assertEqual(self.launcher.terminated[-1].process_group_id, handle.receipt.process_group_id)
        self.assertIsNotNone(self.launcher.processes[handle.receipt.pid].returncode)

    def test_is_current_follows_register_without_launcher_or_lock(self):
        self.assertFalse(self.controller.is_current("world", "agent", "run-1"))
        handle = self.controller.start("world", "agent", "run-1", self.spec)
        reader = al.RunController(self.root / "runs.json")
        self.assertTrue(reader.is_current("world", "agent", "run-1"))
        self.assertFalse(reader.is_current("world", "agent", "run-2"))
        self.assertFalse(reader.is_current("world", "other", "run-1"))
        self.controller.pause("world", "agent")
        # Pause laesst den laufenden Zug seinen Checkpoint erreichen.
        self.assertTrue(reader.is_current("world", "agent", "run-1"))
        seen = []
        self.launcher.before_terminate = lambda: seen.append(reader.is_current("world", "agent", "run-1"))
        lock = (self.root / "runs.json.lock").open("r+")
        self.addCleanup(lock.close)
        self.controller.stop("world", "agent")
        self.assertEqual(seen, [False])
        import fcntl
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        try:
            self.assertFalse(reader.is_current("world", "agent", "run-1"))
        finally:
            fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        self.assertIsNotNone(self.launcher.processes[handle.receipt.pid].returncode)

    def test_pause_after_natural_turn_end_keeps_lock_without_checkpoint_request(self):
        spec = al.StartSpec((sys.executable, "-c", "pass"), str(self.root))
        handle = self.controller.start("world", "agent", "turn-1", spec)
        self.launcher.processes[handle.receipt.pid].wait(timeout=5)
        paused = self.controller.pause("world", "agent", expected_run_id="turn-1")
        self.assertEqual((paused.run_id, paused.observed_state), ("turn-1", "stopped"))
        self.assertEqual(self.launcher.pause_requests, [])
        self.assertIsNone(self.controller.status("world", "agent"))
        with self.assertRaises(al.LaufVerweigert):
            self.controller.start("world", "agent", "turn-2", spec)
        self.controller.resume("world", "agent")
        self.controller.start("world", "agent", "turn-2", spec)

    def test_checkpoint_requires_matching_launcher_checkpoint_id(self):
        class MismatchingCheckpointLauncher(DummyLauncher):
            def confirm_checkpoint(inner, receipt, spec, checkpoint_id):
                return al.Observation("paused", True, checkpoint_id="other")

        self.launcher = MismatchingCheckpointLauncher()
        controller = al.RunController(self.root / "runs.json", launcher=self.launcher, clock=lambda: self.now)
        controller.start("world", "agent", "run-1", self.spec)
        controller.pause("world", "agent")
        with self.assertRaises(al.LaufVerweigert):
            controller.checkpoint("run-1", "requested")
        state = json.loads((self.root / "runs.json").read_text())
        self.assertEqual(state["runs"]["run-1"]["checkpoint_id"], "other")
        self.assertNotEqual(state["runs"]["run-1"]["checkpoint_id"], "requested")

    def test_report_cannot_store_unconfirmed_checkpoint_id(self):
        handle = self.controller.start("world", "agent", "run-1", self.spec)
        self.controller.report(handle.run_id, al.Observation("running", True, checkpoint_id="forged"))
        state = json.loads((self.root / "runs.json").read_text())
        self.assertIsNone(state["runs"]["run-1"]["checkpoint_id"])

    def test_pause_and_stop_intents_are_persisted_before_sideeffects(self):
        register = self.root / "runs.json"
        seen = []

        def inspect_pause():
            state = json.loads(register.read_text())
            seen.append(("pause", state["controls"]["[\"world\",\"agent\"]"]["desired_state"],
                         state["runs"]["run-1"]["desired_state"]))

        def inspect_stop():
            state = json.loads(register.read_text())
            seen.append(("stop", state["controls"]["[\"world\",\"agent\"]"]["desired_state"],
                         state["runs"]["run-1"]["desired_state"]))

        self.launcher.before_pause = inspect_pause
        self.launcher.before_terminate = inspect_stop
        self.controller.start("world", "agent", "run-1", self.spec)
        self.controller.pause("world", "agent")
        self.controller.stop("world", "agent")
        self.assertEqual(seen, [("pause", "paused", "paused"), ("stop", "stopped", "stopped")])

    def test_stop_without_launcher_persists_gate(self):
        handle = self.controller.start("world", "agent", "run-1", self.spec)
        restarted = al.RunController(self.root / "runs.json")
        with self.assertRaises(al.KeineVerifizierteStartstrecke):
            restarted.stop("world", "agent")
        with self.assertRaises(al.LaufVerweigert):
            self.controller.start("world", "agent", "run-2", self.spec)
        self.assertEqual(self.controller.status("world", "agent").desired_state, "stopped")
        self.assertEqual(handle.run_id, "run-1")

    def test_stale_callback_cannot_overwrite_newer_run(self):
        first = self.controller.start("world", "agent", "run-1", self.spec)
        self.controller.stop("world", "agent")
        self.controller.resume("world", "agent")
        second = self.controller.start("world", "agent", "run-2", self.spec)
        with self.assertRaises(al.VeralteteRueckmeldung):
            self.controller.report(first.run_id, al.Observation("stopped", True, 0))
        current = self.controller.status("world", "agent")
        self.assertEqual(current.run_id, second.run_id)
        self.assertEqual(current.observed_state, "running")

    def test_report_cannot_claim_exit_without_launcher_observation(self):
        handle = self.controller.start("world", "agent", "run-1", self.spec)
        with self.assertRaises(al.LaufVerweigert):
            self.controller.report(handle.run_id, al.Observation("stopped", True, 0))
        current = self.controller.status("world", "agent")
        self.assertEqual(current.observed_state, "running")

    def test_restart_adopts_live_identity_and_crash_is_visible_without_revival(self):
        first = self.controller.start("world", "agent", "run-1", self.spec)
        restarted = al.RunController(self.root / "runs.json", launcher=self.launcher, clock=lambda: self.now)
        adopted = restarted.status("world", "agent")
        self.assertEqual((adopted.run_id, adopted.observed_state), (first.run_id, "running"))
        with self.assertRaises(al.LaufVerweigert):
            restarted.start("world", "agent", "run-2", self.spec)
        os.killpg(first.receipt.process_group_id, signal.SIGKILL)
        self.launcher.processes[first.receipt.pid].wait(timeout=2)
        crashed = restarted.status("world", "agent")
        self.assertEqual(crashed.observed_state, "stopped")
        second = restarted.start("world", "agent", "run-2", self.spec)
        self.assertEqual(second.run_id, "run-2")

    def test_identity_mismatch_stays_unclear_and_blocks_duplicate(self):
        first = self.controller.start("world", "agent", "run-1", self.spec)
        restarted = al.RunController(self.root / "runs.json", launcher=self.launcher)
        self.launcher.mismatched.add(first.receipt.pid)
        unclear = restarted.status("world", "agent")
        self.assertEqual((unclear.observed_state, unclear.receipt.pid), ("unclear", first.receipt.pid))
        with self.assertRaises(al.LaufVerweigert):
            restarted.start("world", "agent", "run-2", self.spec)
        with self.assertRaises(al.LaufUngeklaert):
            restarted.stop("world", "agent")
        self.assertEqual(self.launcher.terminated, [])
        self.assertEqual(restarted.status("world", "agent").desired_state, "stopped")
        self.launcher.mismatched.clear()
        restarted.stop("world", "agent")


if __name__ == "__main__":
    unittest.main(verbosity=2)
