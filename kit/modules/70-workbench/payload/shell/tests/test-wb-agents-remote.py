"""Gezielte Grenzen des SSH-Controllers; keine Verbindung zur Live-Umgebung."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import agents_remote as ar


class RemoteTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.ledger = Path(self.temp.name) / "ledger.json"
        self.calls = []
        def action(agent, run):
            self.calls.append((agent, run))
            return {"run": run}
        self.handlers = {op: action for op in ar.OPERATIONS}
        self.dispatcher = ar.RemoteDispatcher("host", "world", self.ledger, self.handlers)
        self.request = ar.make_request("host", "world", "request", "start", "agent", "run")

    def test_replayed_response_after_dispatcher_restart_does_not_start_twice(self):
        first = self.dispatcher.dispatch(self.request)
        restarted = ar.RemoteDispatcher("host", "world", self.ledger, self.handlers)
        self.assertEqual(first, restarted.dispatch(self.request))
        self.assertEqual(self.calls, [("agent", "run")])

    def test_crashed_handler_retains_claim_even_after_restart(self):
        def crashes(agent, run):
            self.calls.append((agent, run))
            raise RuntimeError("lost acknowledgement")
        self.dispatcher.handlers["start"] = crashes
        with self.assertRaises(RuntimeError):
            self.dispatcher.dispatch(self.request)
        restarted = ar.RemoteDispatcher("host", "world", self.ledger, self.handlers)
        self.assertEqual(restarted.dispatch(self.request)["state"], "unknown")
        self.assertEqual(len(self.calls), 1)

    def test_foreign_host_world_extra_fields_and_changed_replay_are_denied(self):
        for alteration in ({"host": "foreign"}, {"world": "foreign"}, {"argv": ["sh"]}):
            with self.subTest(alteration=alteration), self.assertRaises(ar.RemoteError):
                self.dispatcher.dispatch({**self.request, **alteration})
        self.assertEqual(self.calls, [])
        self.dispatcher.dispatch(self.request)
        with self.assertRaises(ar.RemoteError):
            self.dispatcher.dispatch({**self.request, "run": "second"})
        self.assertEqual(len(self.calls), 1)

    def test_controls_require_expected_run_identity(self):
        for op in ("start", "stop", "pause", "resume"):
            with self.subTest(op=op), self.assertRaises(ar.RemoteError):
                ar.make_request("host", "world", "request", op, "agent")

    def test_wrong_ssh_response_binding_is_unknown_and_command_is_fixed(self):
        binding = ar.HostBinding("host", "world", "test-host", "/opt/agents/endpoint.py", "/opt/agents/config.json")
        def fake(argv, **kwargs):
            self.assertIn("-oStrictHostKeyChecking=yes", argv)
            self.assertIn("-oForwardAgent=no", argv)
            self.assertIn("-oClearAllForwardings=yes", argv)
            self.assertNotIn("run", argv[-1])
            request = json.loads(kwargs["input"])
            request["host"] = "foreign"
            kwargs["stdout"].write(ar.encode({"request": request, "state": "done", "result": {}}))
            return type("Result", (), {"returncode": 0})()
        with patch.object(ar.subprocess, "run", fake), self.assertRaises(ar.OutcomeUnknown):
            ar.SSHTransport(binding).call("request", "start", "agent", "run")

    def test_shell_option_injection_and_path_newlines_rejected(self):
        for target in ("-oProxyCommand=evil", "host;echo evil", "host\nother"):
            with self.assertRaises(ar.RemoteError):
                ar.HostBinding("host", "world", target, "/endpoint", "/config")

    def test_dedicated_user_is_fixed_in_remote_command(self):
        binding = ar.HostBinding("host", "world", "root@test-host", "/endpoint", "/config", "werkbank-agents")
        def fake(argv, **kwargs):
            self.assertTrue(argv[-1].startswith("/usr/sbin/runuser -u werkbank-agents -- /usr/bin/python3 -I "))
            kwargs["stdout"].write(ar.encode({"request": json.loads(kwargs["input"]),
                                             "state": "done", "result": "ok"}))
            return type("Result", (), {"returncode": 0})()
        with patch.object(ar.subprocess, "run", fake):
            self.assertEqual(ar.SSHTransport(binding).call("request", "status", "agent"), "ok")
        with self.assertRaises(ar.RemoteError):
            ar.HostBinding("host", "world", "root@test-host", "/endpoint", "/config", "root")


if __name__ == "__main__":
    unittest.main()
