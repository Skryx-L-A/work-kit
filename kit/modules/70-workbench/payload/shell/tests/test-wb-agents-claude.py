#!/usr/bin/env python3
"""Isolierte Vertragsproben fuer den Claude-Code-Adapter der Agents."""

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

import agents_claude as ac  # noqa: E402
import agents_claude_runner as runner  # noqa: E402

TOKEN = "sk-ant-oat01-" + "T" * 40
SESSION = str(uuid.UUID(int=7))


def event(**values):
    values.setdefault("session_id", SESSION)
    return json.dumps(values).encode() + b"\n"


def completed_stream(**result):
    fields = {"type": "result", "subtype": "success", "is_error": False, "terminal_reason": "completed",
              "result": "OK", "num_turns": 2}
    fields.update(result)
    return (event(type="system", subtype="init")
            + event(type="assistant", message={"content": [{"type": "tool_use", "name": "Bash"}]})
            + event(type="user", message={"content": [{"type": "tool_result"}]})
            + event(**fields))


class TokenSourceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-claude-")
        self.root = Path(self.tmp.name)
        os.chmod(self.root, 0o700)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, data, mode=0o600):
        path = self.root / name
        path.write_text(data)
        os.chmod(path, mode)
        return path

    def assert_no_token(self, exc):
        self.assertNotIn(TOKEN, str(exc))
        self.assertNotIn("T" * 20, str(exc))

    def test_setup_token_file_requires_private_regular_file_and_format(self):
        source = ac.SetupTokenDatei(self.write("token", TOKEN + "\n"))
        self.assertEqual(source.auth_headers(), (("Authorization", "Bearer " + TOKEN),))
        self.assertEqual(source.status()["available"], True)
        os.chmod(source.path, 0o640)
        with self.assertRaises(ac.AnmeldungNichtVerfuegbar) as caught:
            source.auth_headers()
        self.assert_no_token(caught.exception)
        link = self.root / "link"
        link.symlink_to(self.write("target", TOKEN))
        with self.assertRaises(ac.AnmeldungNichtVerfuegbar):
            ac.SetupTokenDatei(link).auth_headers()
        with self.assertRaises(ac.AnmeldungNichtVerfuegbar) as caught:
            ac.SetupTokenDatei(self.write("bad", TOKEN + " trailing")).auth_headers()
        self.assert_no_token(caught.exception)
        self.assertNotIn(TOKEN, json.dumps(ac.SetupTokenDatei(self.write("bad2", "x" + TOKEN)).status()))
        with self.assertRaises(ac.ClaudeAdapterFehler):
            ac.SetupTokenDatei("relative/token")

    def test_readonly_login_never_writes_and_refuses_expiring_token(self):
        now = 1_800_000_000.0
        credentials = {"claudeAiOauth": {"accessToken": TOKEN, "refreshToken": "R" * 40,
                                         "expiresAt": int((now + 3600) * 1000),
                                         "scopes": ["user:inference", "user:profile"]}}
        path = self.write("credentials.json", json.dumps(credentials))
        before = (path.read_bytes(), path.stat().st_mtime_ns)
        source = ac.ClaudeAnmeldungNurLesen(path, min_valid_seconds=600, clock=lambda: now)
        self.assertEqual(source.auth_headers(), (("Authorization", "Bearer " + TOKEN),))
        status = source.status()
        self.assertEqual((status["available"], status["kind"]), (True, "claude-login-readonly"))
        self.assertNotIn(TOKEN, json.dumps(status))
        expiring = ac.ClaudeAnmeldungNurLesen(path, min_valid_seconds=3601, clock=lambda: now)
        with self.assertRaises(ac.AnmeldungNichtVerfuegbar) as caught:
            expiring.auth_headers()
        self.assert_no_token(caught.exception)
        self.assertFalse(expiring.status()["available"])
        self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), before)
        credentials["claudeAiOauth"]["scopes"] = ["user:profile"]
        with self.assertRaises(ac.AnmeldungNichtVerfuegbar):
            ac.ClaudeAnmeldungNurLesen(self.write("noscope.json", json.dumps(credentials)),
                                       clock=lambda: now).auth_headers()
        with self.assertRaises(ac.AnmeldungNichtVerfuegbar) as caught:
            ac.ClaudeAnmeldungNurLesen(self.write("broken.json", '{"claudeAiOauth": "' + TOKEN),
                                       clock=lambda: now).auth_headers()
        self.assert_no_token(caught.exception)
        self.assertIsNone(caught.exception.__cause__)

    def test_setup_token_falls_back_only_while_its_file_is_missing(self):
        now = 1_800_000_000.0
        other = "sk-ant-oat01-" + "L" * 40
        credentials = {"claudeAiOauth": {"accessToken": other, "expiresAt": int((now + 3600) * 1000),
                                         "scopes": ["user:inference"]}}
        fallback = ac.ClaudeAnmeldungNurLesen(self.write("credentials.json", json.dumps(credentials)),
                                              clock=lambda: now)
        token_path = self.root / "setup-token"
        source = ac.AnmeldungMitRueckfall(ac.SetupTokenDatei(token_path), fallback)
        self.assertEqual(source.auth_headers(), (("Authorization", "Bearer " + other),))
        status = source.status()
        self.assertEqual((status["available"], status["aktiv"], status["rueckfall"]),
                         (True, "claude-login-readonly", True))
        self.write("setup-token", TOKEN + "\n")
        self.assertEqual(source.auth_headers(), (("Authorization", "Bearer " + TOKEN),))
        self.assertEqual((source.status()["aktiv"], source.status()["rueckfall"]), ("setup-token", False))
        # Eine vorhandene, aber ungueltige Tokendatei ist ein sichtbarer Fehler, kein Rueckfall.
        os.chmod(token_path, 0o644)
        with self.assertRaises(ac.AnmeldungNichtVerfuegbar) as caught:
            source.auth_headers()
        self.assert_no_token(caught.exception)
        status = source.status()
        self.assertEqual((status["available"], status["aktiv"]), (False, "setup-token"))
        for value in (TOKEN, other):
            self.assertNotIn(value, json.dumps(status))
        token_path.unlink()
        token_path.symlink_to(self.root / "credentials.json")
        self.assertEqual(source.status()["aktiv"], "setup-token")
        self.assertFalse(source.status()["available"])


class StreamTests(unittest.TestCase):
    def verdict(self, data, exit_code=0, stop=False, ticket=None, before=0):
        return ac.zug_urteil(ac.stream_befund(data, SESSION), exit_code, stop_requested=stop, ticket=ticket,
                             agent_id="claude", result_revision_before=before)

    def ticket(self, revision=1, agent="claude"):
        return {"state": "zur Abnahme", "assignee": agent, "result_revision": revision, "result": {"agent": agent}}

    def test_completed_stream_needs_new_ticket_result(self):
        befund = ac.stream_befund(completed_stream(), SESSION)
        self.assertEqual((befund.status, befund.tool_uses, befund.num_turns), ("completed", ("Bash",), 2))
        self.assertEqual(self.verdict(completed_stream(), ticket=self.ticket()).status, "erfolg")
        self.assertEqual(self.verdict(completed_stream(), ticket=self.ticket(revision=1), before=1).status,
                         "ergebnis_fehlt")
        self.assertEqual(self.verdict(completed_stream(), ticket=None).status, "ergebnis_fehlt")
        self.assertEqual(self.verdict(completed_stream(), ticket=self.ticket(agent="other")).status, "ergebnis_fehlt")

    def test_truncated_missing_and_unclear_outputs_are_distinct(self):
        stream = completed_stream()
        self.assertEqual(ac.stream_befund(stream[:-5], SESSION).status, "truncated")
        self.assertEqual(self.verdict(stream[:-5], ticket=self.ticket()).status, "abgeschnitten")
        without_result = stream[:stream.rfind(b'{"type": "result"')]
        self.assertEqual(ac.stream_befund(without_result, SESSION).detail, "Stream endet ohne result-Ereignis")
        self.assertEqual(self.verdict(b"", ticket=self.ticket()).status, "abgeschnitten")
        cases = {
            "Ereignisse nach dem result-Ereignis": stream + event(type="assistant"),
            "mehrere result-Ereignisse": stream + event(type="result", subtype="success", is_error=False,
                                                        terminal_reason="completed"),
            "unlesbare Zeile 1": b"garbage\n" + stream,
            "Sitzungskennung fehlt oder wechselt": stream.replace(SESSION.encode(), str(uuid.UUID(int=8)).encode(), 1),
            "Ausgabe beginnt nicht mit system/init": event(type="assistant") + stream,
        }
        for detail, data in cases.items():
            with self.subTest(detail=detail):
                befund = ac.stream_befund(data, SESSION)
                self.assertEqual((befund.status, befund.detail), ("unclear", detail))
                self.assertEqual(self.verdict(data, ticket=self.ticket()).status, "unklar")
        self.assertEqual(ac.stream_befund(stream, str(uuid.UUID(int=9))).detail, "Sitzungskennung passt nicht zum Zug")
        self.assertEqual(self.verdict(stream, exit_code=None, ticket=self.ticket()).status, "unklar")
        self.assertEqual(self.verdict(stream, exit_code=1, ticket=self.ticket()).status, "unklar")

    def test_harness_error_and_stop_never_succeed(self):
        failed = completed_stream(subtype="error_during_execution", is_error=True, terminal_reason="api_error")
        self.assertEqual(self.verdict(failed, exit_code=1, ticket=self.ticket()).status, "harness_fehler")
        self.assertEqual(self.verdict(completed_stream(), stop=True, ticket=self.ticket()).status, "gestoppt")
        self.assertEqual(self.verdict(b"", exit_code=None, stop=True).status, "gestoppt")

    def test_quota_and_credential_rejections_are_own_verdicts(self):
        limited = (event(type="system", subtype="init")
                   + event(type="rate_limit_event", rate_limit_info={"status": "rejected", "resetsAt": 1800000000,
                                                                     "rateLimitType": "five_hour", "isUsingOverage": False})
                   + event(type="system", subtype="api_retry")
                   + event(type="result", subtype="success", is_error=True, terminal_reason="api_error",
                           api_error_status=429, result="You've hit your session limit"))
        befund = ac.stream_befund(limited, SESSION)
        self.assertEqual((befund.status, befund.api_error_status), ("harness_error", 429))
        self.assertEqual(befund.rate_limit, {"status": "rejected", "resetsAt": 1800000000, "rateLimitType": "five_hour"})
        self.assertEqual(self.verdict(limited, exit_code=1, ticket=self.ticket()).status, "kontingent")
        self.assertEqual(self.verdict(limited, exit_code=1, stop=True).status, "gestoppt")
        expired = completed_stream(subtype="success", is_error=True, terminal_reason="api_error", api_error_status=401)
        self.assertEqual(self.verdict(expired, exit_code=1).status, "anmeldung")
        cut = completed_stream()[:-5]
        self.assertEqual(ac.zug_urteil(ac.stream_befund(cut, SESSION), None, stop_requested=False, ticket=None,
                                       agent_id="claude", result_revision_before=0,
                                       proxy_counts={"429": 1}).status, "kontingent")
        self.assertEqual(ac.zug_urteil(ac.stream_befund(b"", SESSION), None, stop_requested=False, ticket=None,
                                       agent_id="claude", result_revision_before=0,
                                       proxy_counts={"controller_auth_unavailable": 2}).status, "anmeldung")
        # Ein ueberstandener 429 mitten im Zug aendert ein abgeschlossenes Ergebnis nicht.
        self.assertEqual(ac.zug_urteil(ac.stream_befund(completed_stream(), SESSION), 0, stop_requested=False,
                                       ticket=self.ticket(), agent_id="claude", result_revision_before=0,
                                       proxy_counts={"429": 1, "200": 2}).status, "erfolg")
        self.assertEqual(ac.zug_urteil(ac.stream_befund(completed_stream(), SESSION), 0, stop_requested=False,
                                       ticket=None, agent_id="claude", result_revision_before=0,
                                       ergebnis_belegt=False).status, "ergebnis_fehlt")
        self.assertEqual(ac.zug_urteil(ac.stream_befund(completed_stream(), SESSION), 0, stop_requested=False,
                                       ticket=None, agent_id="claude", result_revision_before=0,
                                       ergebnis_belegt=True).status, "erfolg")

    def test_oversized_output_reads_as_truncated(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out"
            path.write_bytes(completed_stream())
            self.assertEqual(ac.stream_befund(ac.ausgabe_lesen(path), SESSION).status, "completed")
            # Auch ein Schnitt genau hinter einem Zeilenende darf nicht wie eine vollstaendige Ausgabe aussehen.
            cut = completed_stream().rfind(b"\n", 0, len(completed_stream()) - 1) + 1
            for limit in (len(completed_stream()) - 1, cut):
                self.assertEqual(ac.stream_befund(ac.ausgabe_lesen(path, max_bytes=limit), SESSION).status,
                                 "truncated")
            self.assertEqual(ac.ausgabe_lesen(Path(tmp) / "missing"), b"")


class ZugTests(unittest.TestCase):
    def zug(self, **changes):
        values = dict(claude_binary="/opt/claude/claude", model="claude-haiku-4-5-20251001", prompt="Hallo",
                      session_id=SESSION, config_dir="/work/state/claude-config")
        values.update(changes)
        return ac.ClaudeZug(**values)

    def test_zug_validation(self):
        self.assertEqual(self.zug().as_dict()["tools"], ["Bash"])
        # WebFetch/WebSearch sind seit 15.09. zugelassen; ein MCP-Werkzeug bleibt draussen.
        for changes in ({"tools": ("Bash", "mcp__x__y")}, {"session_id": "not-a-uuid"}, {"prompt": " "},
                        {"claude_binary": "claude"}, {"model": "bad model"},
                        {"extra_env": (("ANTHROPIC_API_KEY", "x"),)}, {"config_dir": "state"}):
            with self.subTest(changes=changes), self.assertRaises(ac.ClaudeAdapterFehler):
                self.zug(**changes)

    def test_runner_command_uses_placeholder_minimal_env_and_resume(self):
        config = self.zug(append_system_prompt="Regeln").as_dict()
        with mock.patch.dict(os.environ, {"ANTHROPIC_API_KEY": "host-secret", "SSH_AUTH_SOCK": "/run/ssh",
                                          "HOME": "/home/agent"}):
            argv, env = runner.command(config)
        self.assertEqual(env["CLAUDE_CODE_OAUTH_TOKEN"], ac.PLACEHOLDER_TOKEN)
        self.assertNotIn("ANTHROPIC_API_KEY", env)
        self.assertNotIn("SSH_AUTH_SOCK", env)
        self.assertNotIn("host-secret", json.dumps([argv, env]))
        self.assertIn("--dangerously-skip-permissions", argv)
        self.assertEqual(argv[argv.index("--session-id") + 1], SESSION)
        self.assertNotIn("--resume", argv)
        self.assertEqual(argv[argv.index("--tools") + 1], "Bash")
        self.assertEqual(argv[argv.index("--setting-sources") + 1], "")
        self.assertEqual(argv[argv.index("--append-system-prompt") + 1], "Regeln")
        argv, _ = runner.command(self.zug(resume=True).as_dict())
        self.assertEqual(argv[argv.index("--resume") + 1], SESSION)
        self.assertNotIn("--session-id", argv)
        self.assertNotIn("--effort", argv)
        zug = self.zug(effort="xhigh", append_system_prompt_file="/turns/zug-1/ANWEISUNG.md",
                       extra_env=(("WB_AGENT_ID", "a1"), ("WB_RPC_CLIENT", "/rt/agents_rpc_client.py")))
        argv, env = runner.command(zug.as_dict())
        self.assertEqual(argv[argv.index("--effort") + 1], "xhigh")
        self.assertEqual(argv[argv.index("--append-system-prompt-file") + 1], "/turns/zug-1/ANWEISUNG.md")
        self.assertEqual((env["WB_AGENT_ID"], env["WB_RPC_CLIENT"]), ("a1", "/rt/agents_rpc_client.py"))
        for bad in (dict(effort="ultra"), dict(append_system_prompt_file="relativ.md"),
                    dict(extra_env=(("PATH", "/tmp"),)), dict(extra_env=(("CLAUDE_CODE_OAUTH_TOKEN", "x"),))):
            with self.subTest(bad=bad), self.assertRaises(ac.ClaudeAdapterFehler):
                self.zug(**bad)
        self.assertEqual(set(config), runner.KEYS)
        self.assertEqual(runner.ALLOWED_TOOLS, ac.ALLOWED_TOOLS)
        self.assertEqual(runner.PLACEHOLDER_TOKEN, ac.PLACEHOLDER_TOKEN)

    def test_start_spec_and_turn_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            turn_dir = Path(tmp) / "turn"
            turn_dir.mkdir(mode=0o700)
            path = ac.zug_schreiben(self.zug(), turn_dir)
            self.assertEqual(json.loads(path.read_text())["session_id"], SESSION)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            spec = ac.start_spec(Path("/rt"), path, Path(tmp))
            self.assertEqual(spec.argv, ("/usr/bin/python3", "-I", "/rt/" + ac.RUNNER, str(path)))
            os.chmod(turn_dir, 0o755)
            with self.assertRaises(ac.ClaudeAdapterFehler):
                ac.zug_schreiben(self.zug(), turn_dir)


class UebergabeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-claude-handoff-")
        self.root = Path(self.tmp.name)
        self.cwd = "/srv/werkbank/agent-1/work"
        self.config = self.root / "config"
        self.store = self.root / "store"
        self.store.mkdir(mode=0o700)
        self.session_dir = self.config / "projects" / ac.projekt_ordnername(self.cwd)
        self.session_dir.mkdir(parents=True, mode=0o700)
        self.transcript = self.session_dir / (SESSION + ".jsonl")
        self.transcript.write_bytes(b'{"type":"user","text":"codeword"}\n{"type":"assistant","partial')

    def tearDown(self):
        self.tmp.cleanup()

    def save(self, **changes):
        values = dict(world="welt-1", agent="agent-1", run_id="run-1", clock=lambda: 5.0)
        values.update(changes)
        return ac.uebergabe_sichern(self.config, SESSION, self.cwd, self.store, **values)

    def test_roundtrip_trims_partial_line_and_restores_into_fresh_config(self):
        self.assertEqual(ac.projekt_ordnername("/home/a/.wb-x/work"), "-home-a--wb-x-work")
        handoff = self.save()
        self.assertEqual(handoff.bytes, len(b'{"type":"user","text":"codeword"}\n'))
        fresh = self.root / "fresh"
        restored = ac.uebergabe_wiederherstellen(self.store, "run-1", fresh, world="welt-1", agent="agent-1",
                                                 cwd=self.cwd)
        self.assertEqual(restored.session_id, SESSION)
        target = fresh / "projects" / ac.projekt_ordnername(self.cwd) / (SESSION + ".jsonl")
        self.assertEqual(target.read_bytes(), b'{"type":"user","text":"codeword"}\n')
        with self.assertRaises(ac.ClaudeAdapterFehler):
            ac.uebergabe_wiederherstellen(self.store, "run-1", fresh, world="welt-1", agent="agent-1", cwd=self.cwd)

    def test_restore_rejects_tampering_foreign_binding_and_symlinks(self):
        self.save()
        for changes in ({"world": "welt-2"}, {"agent": "agent-2"}, {"cwd": "/other"}):
            values = dict(world="welt-1", agent="agent-1", cwd=self.cwd)
            values.update(changes)
            with self.subTest(changes=changes), self.assertRaises(ac.ClaudeAdapterFehler):
                ac.uebergabe_wiederherstellen(self.store, "run-1", self.root / "x", **values)
        stored = self.store / "run-1" / "transcript.jsonl"
        stored.write_bytes(stored.read_bytes().replace(b"codeword", b"codeworm"))
        with self.assertRaises(ac.ClaudeAdapterFehler):
            ac.uebergabe_wiederherstellen(self.store, "run-1", self.root / "y", world="welt-1", agent="agent-1",
                                          cwd=self.cwd)
        self.transcript.unlink()
        outside = self.root / "outside.jsonl"
        outside.write_text("{}\n")
        self.transcript.symlink_to(outside)
        with self.assertRaises(ac.ClaudeAdapterFehler):
            self.save(run_id="run-2")
        with self.assertRaises(ac.ClaudeAdapterFehler):
            self.save(run_id="../escape")


if __name__ == "__main__":
    unittest.main()
