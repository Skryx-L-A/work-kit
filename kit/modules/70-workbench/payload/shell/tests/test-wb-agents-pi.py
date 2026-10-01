#!/usr/bin/env python3
"""Isolierte Vertragsproben fuer den Pi-Adapter (shell/agents_pi.py, shell/agents_pi_runner.py)."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path
from unittest import mock

SHELL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHELL))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import agents_data as ad  # noqa: E402
import agents_model_proxy as amp  # noqa: E402
import agents_pi as ap  # noqa: E402
import agents_pi_runner as runner  # noqa: E402
import agents_skills as ask  # noqa: E402
from herkunft_fixture import aufbau_herkunft, gemessener_mensch  # noqa: E402


_MENSCH_PATCH = None


def setUpModule():
    global _MENSCH_PATCH
    _MENSCH_PATCH = gemessener_mensch(ad)
    _MENSCH_PATCH.start()


def tearDownModule():
    _MENSCH_PATCH.stop()

SESSION = str(uuid.UUID(int=11))
USAGE = {"input": 120, "output": 9, "cacheRead": 0, "cacheWrite": 0, "reasoning": 0, "totalTokens": 129}


def pi_stream(stop="stop", session=SESSION, end=True, text="fertig"):
    """Ereignisfolge wie gemessen an Pi 0.83.0 (results/20260914-pi/json-fixture.json)."""
    assistant_tool = {"role": "assistant", "stopReason": "toolUse", "usage": USAGE, "timestamp": 1757860355001,
                      "content": [{"type": "toolCall", "name": "bash"}]}
    assistant_end = {"role": "assistant", "stopReason": stop, "usage": USAGE, "timestamp": 1757860356002,
                     "content": [{"type": "text", "text": text}], "errorMessage": "429 Too Many Requests" if stop == "error" else None}
    events = [{"type": "session", "version": 3, "id": session, "timestamp": "2026-09-14T14:32:35Z", "cwd": "/w"},
              {"type": "agent_start"}, {"type": "turn_start"},
              {"type": "message_end", "message": {"role": "user", "content": [{"type": "text", "text": "Auftrag"}]}},
              {"type": "message_end", "message": assistant_tool},
              {"type": "tool_execution_start", "toolName": "bash", "args": {"command": "/skills/x/scripts/run.sh"}},
              {"type": "tool_execution_end", "toolName": "bash", "isError": False},
              {"type": "turn_end", "message": assistant_tool}, {"type": "turn_start"},
              {"type": "message_end", "message": assistant_end}, {"type": "turn_end", "message": assistant_end}]
    if end:
        events += [{"type": "agent_end", "messages": [{"role": "user"}, assistant_tool, {"role": "toolResult"}, assistant_end]},
                   {"type": "agent_settled"}]
    return ("\n".join(json.dumps(e) for e in events) + "\n").encode()


class PiAdapterTest(unittest.TestCase):
    def zug(self, **changes):
        values = dict(node="/usr/bin/node", cli="/opt/pi/lib/node_modules/pi/dist/cli.js", model="qwen2.5:7b",
                      prompt="Hallo", session_id=SESSION, session_dir="/work/state/pi-sitzungen",
                      agent_dir="/work/state/zug-1/pi-agent")
        values.update(changes)
        return ap.PiZug(**values)

    def test_befund_follows_the_measured_event_stream(self):
        done = ap.pi_befund(pi_stream(), SESSION)
        self.assertEqual((done.status, done.result_text, done.num_turns, done.tool_uses, done.session_id),
                         ("completed", "fertig", 2, ("bash",), SESSION))
        self.assertEqual(ap.pi_befund(pi_stream(end=False)).status, "truncated")
        self.assertEqual(ap.pi_befund(pi_stream()[:-5]).status, "truncated")
        self.assertEqual(ap.pi_befund(pi_stream(), str(uuid.UUID(int=12))).status, "unclear")
        error = ap.pi_befund(pi_stream(stop="error"))
        self.assertEqual((error.status, error.api_error_status), ("harness_error", 429))
        self.assertEqual(ap.pi_befund(pi_stream(stop="aborted")).status, "harness_error")
        self.assertEqual(ap.pi_befund(b"").status, "empty")
        self.assertEqual(ap.pi_befund(b'{"type": "agent_start"}\n').status, "unclear")
        extra = pi_stream() + b'{"type": "turn_start"}\n'
        self.assertEqual(ap.pi_befund(extra).status, "unclear")
        measured = ask.measure_turn(pi_stream(), "pi")
        self.assertEqual((measured["tokens"]["input"], measured["tokens"]["output"], measured["tokens"]["gesamt"]),
                         (240, 18, 258))

    def test_zug_validation_tools_and_runner_command(self):
        zug = self.zug(tools=("bash", "read"), thinking="off", append_system_prompt_file="/turns/z/ANWEISUNG.md",
                       extra_env=(("WB_AGENT_ID", "p1"), ("WB_RPC_CLIENT", "/state/z/rpc/agents_rpc_client.py")))
        self.assertEqual(zug.lese_pfade(), (Path("/opt/pi/lib/node_modules/pi"), Path("/usr/bin")))
        config = zug.as_dict()
        self.assertEqual(set(config), runner.KEYS)
        argv, env = runner.command(config, "http://127.0.0.1:4711/v1")
        models = json.loads(env.pop("_WB_MODELS_JSON"))
        provider = models["providers"]["wb-lokal"]
        self.assertEqual((provider["baseUrl"], provider["api"], provider["apiKey"], provider["models"][0]["id"]),
                         ("http://127.0.0.1:4711/v1", "openai-completions", "wb-agents-placeholder", "qwen2.5:7b"))
        for flag, value in (("--provider", "wb-lokal"), ("--model", "qwen2.5:7b"), ("--session-id", SESSION),
                            ("--tools", "bash,read"), ("--thinking", "off"),
                            ("--append-system-prompt", "/turns/z/ANWEISUNG.md")):
            self.assertEqual(argv[argv.index(flag) + 1], value)
        for flag in ("--print", "--offline", "--no-extensions", "--no-skills", "--no-context-files", "--no-approve"):
            self.assertIn(flag, argv)
        self.assertEqual(argv[-1], "Hallo")
        self.assertEqual((env["PI_CODING_AGENT_DIR"], env["WB_AGENT_ID"], env["PI_OFFLINE"]),
                         ("/work/state/zug-1/pi-agent", "p1", "1"))
        self.assertNotIn("OLLAMA_HOST", env)
        self.assertEqual(ap.pi_werkzeuge(["Bash", "Read", "WebFetch", "Glob"]), ("bash", "read", "find"))
        self.assertEqual(ap.pi_werkzeuge([]), ("bash",))
        for bad in (dict(tools=("python",)), dict(model="bad model"), dict(api="anthropic-messages"),
                    dict(extra_env=(("PATH", "/tmp"),)), dict(cli="relativ/cli.js"), dict(thinking="ultra")):
            with self.subTest(bad=bad), self.assertRaises(Exception):
                self.zug(**bad)

    def test_local_backend_uses_chat_completions_and_never_leaves_the_host(self):
        backend = amp.BackendConfig("lokal", "qwen2.5:7b", "openai-completions", "local", "http://127.0.0.1:11570",
                                    "host2", "host2", (("Authorization", "Bearer wb-agents-lokal"),), True)
        self.assertEqual(amp.ROUTES[backend.protocol], "/v1/chat/completions")
        with self.assertRaises(amp.ModelProxyError):
            amp.BackendConfig("lokal", "qwen2.5:7b", "openai-completions", "local", "http://10.0.0.5:11570",
                              "host2", "host2", (), True)
        with self.assertRaises(amp.ModelProxyError):
            amp.BackendConfig("lokal", "qwen2.5:7b", "openai-completions", "local", "http://127.0.0.1:11570",
                              "hostco", "hostco", (), True)


class PiTraegerTest(unittest.TestCase):
    def setUp(self):
        import importlib.util  # unter Python 3.9 ist importlib.util nicht implizit geladen
        spec = importlib.util.spec_from_file_location("traeger_tests", Path(__file__).with_name("test-wb-agents-traeger.py"))
        self.helpers = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.helpers)

    def test_pi_agent_turn_is_local_without_subscription_gate_and_ends_with_measurement(self):
        base = self.helpers.TraegerTest("test_konfig_rejects_overlapping_controller_and_agent_paths")
        base.setUp()
        self.addCleanup(base.tearDown)
        import dataclasses
        import agents_traeger as at
        konfig = dataclasses.replace(base.konfig, pi={
            "node": "/usr/bin/node", "cli": "/opt/pi/lib/node_modules/pi/dist/cli.js",
            "base_url": "http://127.0.0.1:11570", "api": "openai-completions",
            "modelle": {"qwen2.5:7b": {"context_window": 16384}}})
        base.credential.available = False  # Abo-Anmeldung fehlt: ein lokaler Agent startet trotzdem
        traeger = base.make(konfig)
        # Kein lokaler Modellserver in der Probe: der Belegt-Pruefer des Traegers meldet ihn frei (16.09.2026).
        traeger._lokal_frei_pruefer = lambda _base_url: True
        base.traeger = traeger
        with aufbau_herkunft(ad) as aufbau:
            ad.create_agent_from_draft(base.world, {"id": "lokal", "specialty": "Arbeitet lokal",
                                                    "model": "qwen2.5:7b", "effort": "low",
                                                    "tools": ["Read"]}, aufbau)
            ad.create_ticket(base.world, "Lokal", "Ziel", "fertig", ["lokal"], aufbau, None,
                             ticket_id="tl", kind="auftrag")
        started = traeger.einmal()["gestartet"]
        self.assertEqual([item["agent"] for item in started], ["lokal"])
        run_id = started[0]["run"]
        lauf = base.laeufe[run_id]
        self.assertIsInstance(lauf.zug, ap.PiZug)
        # An own tool list always carries Bash for the service path (agents_data, 2026-09-15).
        self.assertEqual((lauf.zug.model, lauf.zug.tools, lauf.zug.context_window), ("qwen2.5:7b", ("read", "bash"), 16384))
        entry = traeger._zuege_lesen()["runs"][run_id]
        self.assertEqual((entry["harness"], entry["sperren"], entry["resume"]), ("pi", False, False))
        self.assertFalse((traeger.orte.turns / run_id / "settings.json").exists())
        backend = konfig.backend_fuer("qwen2.5:7b", "pi")
        self.assertEqual((backend.kind, backend.local_only, backend.protocol), ("local", True, "openai-completions"))
        ad.write_result(base.world, "tl", "lokal", "lokal erledigt", None, "lokal", "mitglied")
        base.outputs[lauf.pid] = pi_stream(session=lauf.zug.session_id)
        lauf.release.write_text("go")
        base.launcher.processes[lauf.pid].wait(timeout=5)
        done = traeger.einmal()["beendet"][0]
        self.assertEqual((done["outcome"], done["handoff"], done["lernschritt"]), ("erfolg", False, "fehlt"))
        stored = traeger._zuege_lesen()
        self.assertEqual(stored["runs"][run_id]["messung"]["gesamt"], 258)
        self.assertEqual(stored["sessions"]["lokal"]["tl"]["session_id"], lauf.zug.session_id)


if __name__ == "__main__":
    unittest.main()
