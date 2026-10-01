#!/usr/bin/env python3
"""Isolierte Vertragsproben fuer shell/agents_wecker.py."""

import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHELL))

import agents_wecker as aw  # noqa: E402


class WeckerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-wecker-")
        self.root = Path(self.tmp.name)
        self.now = [1000.0]
        self.controller = aw.WeckerController(
            self.root / "wecker.json", clock=lambda: self.now[0]
        )

    def tearDown(self):
        self.tmp.cleanup()

    def delivery(self, delivery_id, cause="fresh_message", due_at=None, content="wake"):
        return aw.Delivery(
            delivery_id, "world", "agent", cause,
            self.now[0] if due_at is None else due_at, content,
        )

    def context(self, *, world="running", agent="running", active=None, marker="m0"):
        return {
            "desired_world_state": world,
            "desired_agent_state": agent,
            "active_run": active,
            "progress_marker": marker,
        }

    def claim(self, delivery, **changes):
        context = self.context(**changes)
        return self.controller.claim(delivery, **context)

    def test_due_pause_stop_and_active_run_precedence(self):
        future = self.delivery("timer-future", "self_timer", due_at=2000.0)
        self.assertEqual(self.claim(future).reason, "not_due")

        immediate = self.delivery("message-future", "fresh_message", due_at=2000.0)
        immediate_claim = self.claim(immediate)
        self.assertEqual(immediate_claim.status, "claimed")

        paused = self.delivery("paused")
        self.assertEqual(self.claim(paused, agent="paused").reason, "paused")
        stopped = self.delivery("stopped")
        self.assertEqual(self.claim(stopped, world="stopped").reason, "stopped")
        active = self.delivery("active")
        self.assertEqual(self.claim(active, active="run-1").reason, "active_run")

        # Ohne Steuerungsgrund sperrt der noch offene Claim derselben Bindung.
        self.assertEqual(self.claim(self.delivery("in-flight")).reason, "claim_in_flight")
        self.controller.resolve(immediate.delivery_id, immediate_claim.claim_id, run_id="run-0",
                                progress_marker="m0", outcome="sent")

        timer = self.delivery("timer-1", "self_timer")
        first = self.claim(timer)
        self.assertEqual(first.status, "claimed")
        self.controller.resolve(timer.delivery_id, first.claim_id, run_id="run-1",
                                progress_marker="m0", outcome="sent")
        second_timer = self.delivery("timer-2", "self_timer")
        self.now[0] += 899
        self.assertEqual(self.claim(second_timer).reason, "self_timer_spacing")
        self.now[0] += 1
        self.assertEqual(self.claim(second_timer).status, "claimed")

    def test_offene_lists_pending_and_claimed_without_claiming(self):
        self.assertEqual(self.controller.offene(), [])
        timer = self.delivery("timer", "self_timer", due_at=1500.0)
        self.assertEqual(self.claim(timer).reason, "not_due")
        message = self.delivery("message")
        claim = self.claim(message)
        other = aw.Delivery("elsewhere", "world-2", "agent", "fresh_message", self.now[0], "x")
        self.controller.claim(other, **self.context(agent="paused"))
        listed = [(item.delivery_id, status.status) for item, status in self.controller.offene("world")]
        self.assertEqual(listed, [("message", "unknown"), ("timer", "pending")])
        self.assertEqual([item.delivery_id for item, _ in self.controller.offene(agent="agent")],
                         ["elsewhere", "message", "timer"])
        self.controller.resolve("message", claim.claim_id, run_id="run", progress_marker="m0", outcome="ok")
        self.assertEqual([item.delivery_id for item, _ in self.controller.offene("world")], ["timer"])
        self.now[0] = 1600.0
        self.assertEqual([item.delivery_id for item, _ in self.controller.offene("world")], ["timer"])
        self.assertEqual(self.controller.status("timer").status, "pending")

    def test_concurrent_claim_has_one_winner(self):
        delivery = self.delivery("concurrent")
        barrier = threading.Barrier(2)
        results = []

        def worker():
            barrier.wait()
            results.append(self.claim(delivery))

        threads = [threading.Thread(target=worker) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=5)
        self.assertEqual(sum(result.status == "claimed" for result in results), 1)
        self.assertEqual(sum(result.status == "unknown" for result in results), 1)

    def test_duplicate_delivery_is_idempotent_and_conflict_rejected(self):
        delivery = self.delivery("same")
        first = self.claim(delivery)
        duplicate = self.claim(delivery)
        self.assertEqual((duplicate.status, duplicate.claim_id), ("unknown", first.claim_id))
        with self.assertRaises(aw.WeckerKonflikt):
            self.claim(self.delivery("same", content="different"))
        self.controller.resolve(delivery.delivery_id, first.claim_id, run_id="run-1",
                                progress_marker="m1", outcome="sent")
        done = self.claim(delivery)
        self.assertEqual((done.status, done.claim_id), ("completed", first.claim_id))
        with self.assertRaises(aw.WeckerKonflikt):
            self.controller.resolve(delivery.delivery_id, first.claim_id, run_id="run-1",
                                    progress_marker="m2", outcome="sent")

    def test_unresolved_claim_blocks_other_delivery_same_binding(self):
        first = self.claim(self.delivery("binding-1"))
        self.assertEqual(first.status, "claimed")
        second = self.claim(self.delivery("binding-2"))
        self.assertEqual((second.status, second.reason), ("pending", "claim_in_flight"))

        self.controller.resolve("binding-1", first.claim_id, run_id="run-1",
                                progress_marker="m0", outcome="sent")
        after_resolution = self.claim(self.delivery("binding-2"))
        self.assertEqual(after_resolution.status, "claimed")

    def test_restart_keeps_claim_unknown_until_explicit_resolution(self):
        delivery = self.delivery("restart")
        first = self.claim(delivery)
        restarted = aw.WeckerController(self.root / "wecker.json", clock=lambda: self.now[0])
        self.assertEqual(restarted.status(delivery.delivery_id).status, "unknown")
        self.assertEqual(restarted.claim(delivery, **self.context()).status, "unknown")
        resolved = restarted.resolve(delivery.delivery_id, first.claim_id, run_id="run-7",
                                     progress_marker="m1", outcome="recovered")
        self.assertEqual(resolved.status, "completed")

    def test_recovery_limit_resets_only_after_marker_progress(self):
        def recovery(delivery_id):
            return self.delivery(delivery_id, "recovery")

        first = self.claim(recovery("recovery-1"))
        self.controller.resolve("recovery-1", first.claim_id, run_id="run-1",
                                progress_marker="m0", outcome="no_progress")
        self.now[0] += 300
        second = self.claim(recovery("recovery-2"))
        self.assertEqual(second.status, "claimed")
        self.controller.resolve("recovery-2", second.claim_id, run_id="run-2",
                                progress_marker="m0", outcome="no_progress")
        self.now[0] += 300
        blocked = self.claim(recovery("recovery-3"), marker=None)
        self.assertEqual(blocked.reason, "recovery_limit")
        state = json.loads((self.root / "wecker.json").read_text())
        self.assertEqual(state["progress"]["[\"world\",\"agent\"]"]["marker"], "m0")

        recovery_after_progress = self.claim(recovery("recovery-4"), marker="m1")
        self.assertEqual(recovery_after_progress.status, "claimed")
        self.controller.resolve("recovery-4", recovery_after_progress.claim_id, run_id="run-4",
                                progress_marker=None, outcome="no_progress")
        state = json.loads((self.root / "wecker.json").read_text())
        self.assertEqual(state["progress"]["[\"world\",\"agent\"]"]["marker"], "m1")
        self.assertEqual(state["progress"]["[\"world\",\"agent\"]"]["recovery_attempts"], 1)

    def test_cycle_and_hop_limit_are_visible_blocked(self):
        cycle = aw.Delivery("cycle-a", "world", "agent", "ticket", 1000.0, "x",
                            caused_by="cycle-b", chain=("cycle-b", "cycle-a"))
        self.assertEqual(self.claim(cycle).reason, "cycle")
        long_chain = aw.Delivery("hop-20", "world", "agent", "ticket", 1000.0, "x",
                                 chain=tuple(f"hop-{i}" for i in range(20)))
        self.assertEqual(self.claim(long_chain).reason, "chain_limit")
        self.assertEqual(self.controller.status("cycle-a").status, "blocked")

    def test_invalid_times_clock_and_immutable_delivery_rejected(self):
        with self.assertRaises(ValueError):
            self.delivery("nan", due_at=float("nan"))
        with self.assertRaises(ValueError):
            self.delivery("inf", due_at=float("inf"))
        delivery = self.delivery("clock")
        self.now[0] = float("nan")
        with self.assertRaises(ValueError):
            self.claim(delivery)
        with self.assertRaises(Exception):
            delivery.content = "changed"


if __name__ == "__main__":
    unittest.main(verbosity=2)
