#!/usr/bin/env python3
"""Isolierte Vertragsproben fuer shell/agents_rechte.py."""

import fcntl
import json
import sys
import tempfile
import threading
import unittest
from dataclasses import replace
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHELL))

import agents_rechte as ar  # noqa: E402


class Auth:
    def __init__(self, allowed=True):
        self.allowed = allowed
        self.calls = []

    def authorize(self, operation, grant):
        self.calls.append((operation, grant))
        return ar.ControllerReceipt("human-1", "evidence-1") if self.allowed else None


class RechteTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-rechte-")
        self.root = Path(self.tmp.name)
        self.project = self.root / "project"
        self.project.mkdir()
        self.results = self.project / "agent-results"
        self.results.mkdir()
        self.memory = self.project / "agent-memory"
        self.memory.mkdir()
        self.foreign = self.root / "foreign"
        self.foreign.mkdir()
        self.control = self.root / "control"
        self.control.mkdir()
        self.auth = Auth()
        self.now_value = 100.0
        self.controller = ar.RightsController(
            self.root / "rights.json",
            protected_scopes=(str(self.control),),
            human_authenticator=self.auth,
            clock=lambda: self.now_value,
            effect_resolver=lambda action, target, scope: ("publish", "deploy")
            if action == "push" else (),
        )
        self.context = ar.RunContext(
            "world-a", "agent-a", "worker", "run-a",
            write_scopes=(str(self.project),),
            result_scopes=(str(self.results),),
            memory_scopes=(str(self.memory),),
            protected_scopes=(str(self.control),),
        )

    def tearDown(self):
        self.tmp.cleanup()

    def issue(self, action, target, scope, start=0, end=200, context=None, **kwargs):
        return self.controller.issue(context or self.context, action, target, scope,
                                     valid_from=start, valid_until=end, **kwargs)

    def test_context_is_immutable_and_bound_to_world_agent_role_run(self):
        with self.assertRaises(Exception):
            self.context.run_id = "other"
        target = str(self.project / "a.txt")
        self.issue("write", target, str(self.project))
        wrong = ar.RunContext("world-a", "agent-a", "worker", "run-b",
                              write_scopes=(str(self.project),))
        self.assertFalse(self.controller.check(wrong, "write", target, str(self.project)).allowed)
        foreign = ar.RunContext("world-b", "agent-a", "worker", "run-a",
                                write_scopes=(str(self.project),))
        self.assertFalse(self.controller.check(foreign, "write", target, str(self.project)).allowed)

    def test_default_has_no_human_authority_and_consumer_cannot_issue(self):
        controller = ar.RightsController(self.root / "no-auth.json")
        with self.assertRaises(ar.KeineControllerAutorisierung):
            controller.issue(self.context, "write", str(self.project / "a"), str(self.project),
                             valid_from=0, valid_until=2)
        consumer = self.controller.consumer(self.context)
        self.assertFalse(hasattr(consumer, "issue"))
        self.assertTrue(callable(consumer.check))
        self.assertTrue(callable(consumer.reserve))
        self.assertTrue(callable(consumer.report))

    def test_auth_receipt_is_stored_and_interval_must_be_finite(self):
        target = str(self.project / "audited.txt")
        grant = self.issue("write", target, str(self.project))
        self.assertEqual((grant.human_actor, grant.human_evidence), ("human-1", "evidence-1"))
        receipt_input = self.auth.calls[-1][1]
        self.assertEqual((receipt_input.action_type, receipt_input.target, receipt_input.scope),
                         (grant.action_type, grant.target, grant.scope))
        self.assertEqual((receipt_input.run_id, receipt_input.valid_from, receipt_input.valid_until),
                         (grant.run_id, grant.valid_from, grant.valid_until))
        state = json.loads((self.root / "rights.json").read_text())
        saved = state["grants"][grant.grant_id]
        self.assertEqual(saved["human_actor"], "human-1")
        self.assertEqual(saved["human_evidence"], "evidence-1")
        for invalid in (float("nan"), float("inf"), float("-inf")):
            with self.assertRaises(ValueError):
                self.issue("write", str(self.project / ("bad-%s" % abs(hash(invalid)))),
                            str(self.project), start=invalid)
        with self.assertRaises(ValueError):
            self.issue("write", str(self.project / "bad-end"), str(self.project), end=float("nan"))
        permanent = self.issue("write", str(self.project / "permanent"), str(self.project), end=None)
        self.assertIsNone(permanent.valid_until)
        self.assertIsNone(json.loads((self.root / "rights.json").read_text())["grants"]
                          [permanent.grant_id]["valid_until"])

    def test_expired_and_revoked_grants(self):
        target = str(self.project / "a.txt")
        expired = self.issue("write", target, str(self.project), end=100)
        self.assertFalse(self.controller.check(self.context, "write", target, str(self.project)).allowed)
        self.issue("write", target, str(self.project))
        active = self.controller.check(self.context, "write", target, str(self.project))
        self.assertTrue(active.allowed)
        self.controller.revoke(active_grant_id := self._active_grant_id(target), context=self.context)
        self.assertNotEqual(expired.grant_id, active_grant_id)
        self.assertFalse(self.controller.check(self.context, "write", target, str(self.project)).allowed)
        state = json.loads((self.root / "rights.json").read_text())
        revoked = state["grants"][active_grant_id]
        self.assertEqual(revoked["revoked_actor"], "human-1")
        self.assertEqual(revoked["revoked_evidence"], "evidence-1")

    def test_clock_is_read_under_register_lock(self):
        target = str(self.project / "lock-time.txt")
        self.issue("write", target, str(self.project))
        clock_called = threading.Event()
        original_clock = self.controller._clock

        def clock():
            clock_called.set()
            return original_clock()

        self.controller._clock = clock
        lock = self.controller.lock_path.open("r+")
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        result = []

        def reserve():
            try:
                result.append(self.controller.reserve(self.context, "write", target,
                                                      str(self.project), operation_id="lock-time"))
            except ar.RechteFehler as exc:
                result.append(exc)

        thread = threading.Thread(target=reserve)
        thread.start()
        self.assertFalse(clock_called.wait(0.2))
        self.now_value = 201.0
        fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        lock.close()
        thread.join(timeout=5)
        self.assertEqual(len(result), 1)
        self.assertIsInstance(result[0], ar.AktionVerweigert)

    def _active_grant_id(self, target):
        state = json.loads((self.root / "rights.json").read_text())
        target = str(Path(target).resolve())
        return next(gid for gid, grant in state["grants"].items()
                    if grant["target"] == target and grant["status"] == "active"
                    and grant["valid_until"] > 100)

    def test_atomic_one_time_reservation_under_concurrency(self):
        target = str(self.project / "a.txt")
        self.issue("write", target, str(self.project))
        barrier = threading.Barrier(2)
        results = []

        def reserve():
            barrier.wait()
            try:
                results.append(self.controller.reserve(self.context, "write", target, str(self.project),
                                                       operation_id="concurrent-%s" % threading.get_ident()))
            except ar.RechteFehler as exc:
                results.append(exc)

        threads = [threading.Thread(target=reserve) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=5)
        self.assertEqual(sum(isinstance(item, ar.Reservation) for item in results), 1)
        self.assertEqual(sum(isinstance(item, ar.AktionVerweigert) for item in results), 1)

    def test_unknown_result_consumes_grant_and_denies_retry(self):
        target = str(self.project / "a.txt")
        self.issue("write", target, str(self.project))
        consumer = self.controller.consumer(self.context)
        reservation = consumer.reserve("write", target, str(self.project), operation_id="unknown-op")
        with self.assertRaises(ar.UnbekanntesErgebnis):
            consumer.report(reservation, "unknown")
        self.issue("write", target, str(self.project))
        with self.assertRaises(ar.AktionVerweigert):
            consumer.reserve("write", target, str(self.project), operation_id="unknown-op")

    def test_reusable_permanent_grant_allows_distinct_operations_until_revoke(self):
        target = str(self.project / "durable.txt")
        grant = self.issue("write", target, str(self.project), end=None, reusable=True)
        consumer = self.controller.consumer(self.context)
        first = consumer.reserve("write", target, str(self.project), operation_id="durable-one")
        consumer.report(first, "success")
        second = consumer.reserve("write", target, str(self.project), operation_id="durable-two")
        consumer.report(second, "success")
        with self.assertRaises(ar.AktionVerweigert):
            consumer.reserve("write", target, str(self.project), operation_id="durable-one")
        self.controller.revoke(grant.grant_id, context=self.context)
        self.assertFalse(consumer.check("write", target, str(self.project)).allowed)
        with self.assertRaises(ar.AktionVerweigert):
            consumer.reserve("write", target, str(self.project), operation_id="durable-three")

    def test_unknown_result_blocks_retry_even_for_reusable_grant(self):
        target = str(self.project / "durable-unknown.txt")
        self.issue("write", target, str(self.project), end=None, reusable=True)
        consumer = self.controller.consumer(self.context)
        reservation = consumer.reserve("write", target, str(self.project), operation_id="durable-unknown")
        with self.assertRaises(ar.UnbekanntesErgebnis):
            consumer.report(reservation, "unknown")
        with self.assertRaises(ar.AktionVerweigert):
            consumer.reserve("write", target, str(self.project), operation_id="durable-unknown")
        retry = consumer.reserve("write", target, str(self.project), operation_id="durable-retry")
        consumer.report(retry, "success")

    def test_run_bound_and_agent_bound_grants_across_resume(self):
        run_target = str(self.project / "run-bound.txt")
        self.issue("write", run_target, str(self.project))
        resumed = ar.RunContext("world-a", "agent-a", "worker", "run-b",
                                write_scopes=(str(self.project),))
        self.assertFalse(self.controller.check(resumed, "write", run_target,
                                               str(self.project)).allowed)
        agent_target = str(self.project / "agent-bound.txt")
        self.issue("write", agent_target, str(self.project), bind_run=False)
        self.assertTrue(self.controller.check(resumed, "write", agent_target,
                                              str(self.project)).allowed)
        other_world = ar.RunContext("world-b", "agent-a", "worker", "run-b",
                                    write_scopes=(str(self.project),))
        self.assertFalse(self.controller.check(other_world, "write", agent_target,
                                               str(self.project)).allowed)
        other_agent = ar.RunContext("world-a", "agent-b", "worker", "run-b",
                                    write_scopes=(str(self.project),))
        self.assertFalse(self.controller.check(other_agent, "write", agent_target,
                                               str(self.project)).allowed)

    def test_path_traversal_symlink_and_sibling_prefix_are_denied(self):
        outside = self.foreign / "secret.txt"
        outside.write_text("x")
        scope = str(self.project)
        traversal = str(self.project / "sub" / ".." / "escape.txt")
        self.issue("write", str(self.project / "safe.txt"), scope)
        self.assertFalse(self.controller.check(self.context, "write", traversal, scope).allowed)
        link = self.project / "link.txt"
        try:
            link.symlink_to(outside)
        except OSError as exc:
            self.skipTest(f"Symlink nicht verfuegbar: {exc}")
        self.assertFalse(self.controller.check(self.context, "write", str(link), scope).allowed)
        sibling = str(self.project) + "-sibling/file.txt"
        self.assertFalse(self.controller.check(self.context, "write", sibling, scope).allowed)

    def test_result_and_memory_scopes_are_separate_from_project_write_scope(self):
        result = str(self.results / "result.json")
        memory = str(self.memory / "note.md")
        self.issue("result_write", result, str(self.results))
        self.issue("memory_write", memory, str(self.memory))
        self.assertTrue(self.controller.check(self.context, "result_write", result, str(self.results)).allowed)
        self.assertTrue(self.controller.check(self.context, "memory_write", memory, str(self.memory)).allowed)
        self.assertFalse(self.controller.check(self.context, "write", result, str(self.results)).allowed)

    def test_protected_control_path_and_foreign_world_are_denied(self):
        target = str(self.control / "grant.json")
        with self.assertRaises(ar.RechteFehler):
            self.issue("write", target, str(self.project))
        self.issue("write", str(self.project / "own.txt"), str(self.project))
        foreign = ar.RunContext("world-b", "agent-b", "worker", "run-b",
                                write_scopes=(str(self.project),))
        self.assertFalse(self.controller.check(foreign, "write", str(self.project / "own.txt"),
                                                str(self.project)).allowed)

    def test_push_requires_push_publish_and_deploy_grants(self):
        target = str(self.project / "repo")
        scope = str(self.project)
        self.issue("push", target, scope)
        self.issue("publish", target, scope)
        self.assertFalse(self.controller.check(self.context, "push", target, scope).allowed)
        self.issue("deploy", target, scope)
        reservation = self.controller.reserve(self.context, "push", target, scope, operation_id="push-op")
        self.assertEqual(len(reservation.grant_ids), 3)

    def test_report_checks_every_authoritative_reservation_field(self):
        target = str(self.project / "report-binding.txt")
        self.issue("write", target, str(self.project))
        consumer = self.controller.consumer(self.context)
        reservation = consumer.reserve("write", target, str(self.project), operation_id="report-op")
        mutations = {
            "action_type": "memory_write",
            "target": str(self.project / "other.txt"),
            "scope": str(self.memory),
            "operation_id": "forged-op",
        }
        for field, value in mutations.items():
            forged = replace(reservation, **{field: value})
            with self.assertRaises(ar.AktionVerweigert):
                consumer.report(forged, "success")
        consumer.report(reservation, "success")


if __name__ == "__main__":
    unittest.main(verbosity=2)
