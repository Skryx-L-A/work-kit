#!/usr/bin/env python3
"""Isolierte Vertragsproben fuer den Welt-Traeger mit Stellvertreter-Laeufen."""

from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import uuid
from pathlib import Path
from unittest import mock

SHELL = Path(__file__).resolve().parents[1]
# Kit: parts of the source repository the kit does not ship (port/strip.txt, regenerate.py).
BIBLIOTHEK = SHELL.parent / "agents" / "bibliothek"
OHNE_BIBLIOTHEK = "kit: the wb-agents library (agents/bibliothek: skills, learning script) is not shipped"
sys.path.insert(0, str(SHELL))

import agents_claude as ac  # noqa: E402
import agents_data as ad  # noqa: E402
import agents_lauf as al  # noqa: E402
import agents_traeger as at  # noqa: E402
import agents_worktree as aw  # noqa: E402
from herkunft_fixture import aufbau_herkunft, gebundene_governance, gemessener_mensch  # noqa: E402

MODEL = "claude-haiku-4-5-20251001"

_MESSER = gemessener_mensch(ad)


def setUpModule():
    global _GOVERNANCE_CONTEXT
    _MESSER.start()
    _GOVERNANCE_CONTEXT = gebundene_governance(ad)
    _GOVERNANCE_CONTEXT.__enter__()


def tearDownModule():
    _GOVERNANCE_CONTEXT.__exit__(None, None, None)
    _MESSER.stop()


class SharedLauncher:
    """Testlokale Startstrecke; Pause wird wie beim Zugharness am Zugende eingeloest."""

    def __init__(self):
        self.processes = {}
        self.fail_launch = False
        self.ended_proven = False

    def launch(self, spec):
        if self.fail_launch:
            raise RuntimeError("systemd-run failed")
        process = subprocess.Popen(spec.argv, cwd=spec.cwd, start_new_session=True)
        self.processes[process.pid] = process
        return al.LaunchReceipt(process.pid, os.getpgid(process.pid), "fake:%d" % process.pid)

    def verify(self, receipt, spec):
        return receipt.pid in self.processes

    def observe(self, receipt, spec):
        process = self.processes.get(receipt.pid)
        if process is None:
            return al.Observation("unclear", False)
        code = process.poll()
        return al.Observation("stopped", True, code) if code is not None else al.Observation("running", True)

    def request_pause(self, receipt):
        if self.processes[receipt.pid].poll() is not None:
            raise RuntimeError("not live")

    def resume(self, receipt):
        pass

    def confirm_checkpoint(self, receipt, spec, checkpoint_id):
        raise RuntimeError("no app checkpoint")

    def terminate(self, receipt):
        process = self.processes[receipt.pid]
        if process.poll() is None:
            os.killpg(receipt.process_group_id, signal.SIGTERM)
            process.wait(timeout=5)

    def beendet_belegt(self, world, agent, run_id, spec, receipt):
        return self.ended_proven

    def cleanup(self):
        for process in self.processes.values():
            if process.poll() is None:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
                process.wait(timeout=5)


class Credential:
    def __init__(self):
        self.available = True

    def status(self):
        return {"kind": "test", "available": self.available, "reason": None if self.available else "abgelaufen"}

    def auth_headers(self):
        return (("Authorization", "Bearer test"),)


class TraegerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-traeger-")
        self.root = Path(self.tmp.name)
        os.chmod(self.root, 0o700)
        # Autostart-Register und Unitordner nie im echten Home.
        self.env = mock.patch.dict(os.environ, {"WB_AGENTS_ZUSTAND": str(self.root / "zustand-autostart"),
                                                "WB_AGENTS_UNIT_DIR": str(self.root / "units")})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.world = self.root / "world"
        ad.create_world(self.world, name="Traegerprobe", main_name="haupt", sender="cli-operator")
        for agent in ("a1", "a2"):
            ad.create_agent(self.world, agent, "mitglied", None, "Probe", None, None, MODEL, None, None, None,
                            "host2", "haupt", "hauptagent")
        self.konfig = at.TraegerKonfig(self.world, self.root / "state", self.root / "agents", "/opt/claude/claude",
                                       "host2", {"kind": "setup-token", "path": "/nonexistent"})
        self.launcher = SharedLauncher()
        self.credential = Credential()
        self.laeufe = {}
        self.outputs = {}
        self.auto = set()
        self.offset = 0.0
        self.timer_calls = []
        self.kontingent = None
        self.proxies = {}
        self.traeger = self.make()

    def tearDown(self):
        self.launcher.cleanup()
        self.tmp.cleanup()

    def make(self, konfig=None):
        return at.WeltTraeger(konfig or self.konfig, zug_fabrik=self.fabrik, observer_fabrik=lambda _t: self.launcher,
                              ausgabe=lambda _t, receipt: self.outputs.get(receipt.pid, b""),
                              anmeldequelle=self.credential, kontingentquelle=self.kontingent,
                              zeitgeber=self.timer_calls.append, clock=lambda: time.time() + self.offset)

    # Stellvertreter fuer ClaudeLauf -------------------------------------------------
    def fabrik(self, traeger, *, agent_id, run_id, zug, workspace, agent_state, extra_read_paths=(), netz=False,
               extra_write_paths=(), git_einbindung=None):
        test = self

        class FakeLauf:
            def __init__(self):
                self.closed = False
                self.release = traeger.orte.state / ("release-" + run_id)
                self.zug = zug
                self.agent_id = agent_id
                self.workspace = workspace
                self.read_paths = tuple(extra_read_paths)
                self.write_paths = tuple(extra_write_paths)
                self.netz = netz
                self.git_einbindung = git_einbindung

            def start(self):
                home = getattr(zug, "config_dir", None) or getattr(zug, "agent_dir", None) or zug.codex_home
                sessions = Path(home) / "projects" / ac.projekt_ordnername(str(workspace))
                sessions.mkdir(parents=True, exist_ok=True)
                transcript = sessions / (zug.session_id + ".jsonl")
                with transcript.open("a") as stream:
                    stream.write(json.dumps({"type": "user", "prompt": zug.prompt}) + "\n")
                code = ("import pathlib, sys, time\np = pathlib.Path(sys.argv[1])\n"
                        "while not p.exists(): time.sleep(0.02)\n")
                spec = al.StartSpec((sys.executable, "-c", code, str(self.release)), str(workspace))
                self.proxy = test.proxies.get(agent_id)
                handle = al.RunController(traeger.orte.runs, launcher=test.launcher).start(
                    traeger.world_id(), agent_id, run_id, spec)
                self.pid = handle.receipt.pid
                test.laeufe[run_id] = self
                if agent_id in test.auto:
                    test.finish(run_id, "auto result")

            def close(self):
                self.closed = True

        return FakeLauf()

    def stream(self, session, complete=True):
        data = (json.dumps({"type": "system", "subtype": "init", "session_id": session}) + "\n"
                + json.dumps({"type": "assistant", "session_id": session,
                              "message": {"content": [{"type": "tool_use", "name": "Bash"}]}}) + "\n")
        if complete:
            data += json.dumps({"type": "result", "subtype": "success", "is_error": False,
                                "terminal_reason": "completed", "result": "done", "session_id": session}) + "\n"
        return data.encode()

    def finish(self, run_id, text=None, complete=True, stream=None, reply=None):
        lauf = self.laeufe[run_id]
        entry = self.traeger._zuege_lesen()["runs"][run_id]
        if text is not None:
            ad.write_result(self.world, entry["ticket_id"], lauf.agent_id, text, None, lauf.agent_id, "mitglied")
        if reply is not None:
            ad.reply_to_delivery(self.world, lauf.agent_id, entry["nachricht_id"], reply,
                                 self.traeger._antwort_id(lauf.agent_id, entry["nachricht_id"]))
        self.outputs[lauf.pid] = stream(lauf.zug.session_id) if stream else self.stream(lauf.zug.session_id, complete)
        lauf.release.write_text("go")
        self.launcher.processes[lauf.pid].wait(timeout=5)

    def ticket(self, ticket_id, agent="a1", goal="Ziel", dependencies=None):
        # Art auftrag: die Definition of Ready verlangt keine Fertig-Liste (tickets3, Satz 45).
        return ad.create_ticket(self.world, "Titel " + ticket_id, goal, "fertig", [agent], "haupt", "hauptagent",
                                dependencies=dependencies, ticket_id=ticket_id, kind="auftrag")

    def delivery_status(self, delivery_id):
        return self.traeger.wecker.status(delivery_id)

    def postfach(self, agent, delivery_id):
        return json.loads((self.world / "agents" / agent / "postfach" / (delivery_id + ".json")).read_text())

    # Vertraege -----------------------------------------------------------------------
    def test_ticket_delivery_starts_exactly_one_run_and_acknowledges_accepted_result(self):
        self.ticket("t1")
        first = self.traeger.einmal()
        self.assertEqual([item["ticket"] for item in first["gestartet"]], ["t1"])
        run_id = first["gestartet"][0]["run"]
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "läuft")
        second = self.make().einmal()
        self.assertEqual(second["gestartet"], [])
        self.assertEqual([item["run"] for item in second["aktiv"]], [run_id])
        self.assertEqual(len(self.launcher.processes), 1)
        self.assertEqual(self.delivery_status(self.traeger._wecker_id("a1", "ticket-2_t1")).status, "unknown")
        self.finish(run_id, "Ergebnis")
        done = self.traeger.einmal()
        self.assertEqual([(item["run"], item["outcome"]) for item in done["beendet"]], [(run_id, "erfolg")])
        self.assertTrue(self.laeufe[run_id].closed)
        status = self.delivery_status(self.traeger._wecker_id("a1", "ticket-2_t1"))
        self.assertEqual((status.status, status.outcome), ("completed", "erfolg"))
        self.assertTrue(self.postfach("a1", "ticket-2_t1")["acknowledged"])
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "zur Abnahme")
        history = (self.world / "tickets" / "t1" / "verlauf.jsonl").read_text()
        self.assertIn('"outcome": "erfolg"', history)
        idle = self.traeger.einmal()
        self.assertEqual((idle["gestartet"], idle["aktiv"]), ([], []))
        self.assertEqual(len(self.launcher.processes), 1)

    def test_missing_result_truncated_output_and_start_errors_are_resolved_without_retry(self):
        self.ticket("t1")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        self.finish(run_id, None)
        self.assertEqual(self.traeger.einmal()["beendet"][0]["outcome"], "ergebnis_fehlt")
        self.ticket("t2", agent="a2")
        run_two = self.traeger.einmal()["gestartet"][0]["run"]
        self.finish(run_two, "halb", complete=False)
        self.assertEqual(self.traeger.einmal()["beendet"][0]["outcome"], "abgeschnitten")
        self.assertEqual(self.traeger.einmal()["gestartet"], [])
        self.assertEqual(len(self.launcher.processes), 2)

    def test_pause_lets_running_turn_finish_and_blocks_next_ticket_until_resume(self):
        self.ticket("t1")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        paused = self.traeger.agent_pausieren("a1", "Pause", absender="haupt")
        self.assertEqual(paused["active_run"], run_id)
        self.assertTrue(al.RunController(self.traeger.orte.runs).is_current(self.traeger.world_id(), "a1", run_id))
        self.assertIsNone(self.launcher.processes[self.laeufe[run_id].pid].poll())
        self.ticket("t2")
        self.finish(run_id, "fertig trotz Pause")
        summary = self.traeger.einmal()
        self.assertEqual(summary["beendet"][0]["outcome"], "erfolg")
        self.assertEqual(summary["gestartet"], [])
        self.assertIn("paused", [item["reason"] for item in summary["wartend"]])
        self.assertEqual(self.traeger.einmal()["gestartet"], [])
        self.traeger.agent_fortsetzen("a1", absender="haupt")
        self.assertEqual([item["ticket"] for item in self.traeger.einmal()["gestartet"]], ["t2"])

    def test_stop_interrupts_never_succeeds_and_resume_continues_same_session(self):
        self.ticket("t1", goal="Codewort amber-1234abcd merken")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        session = self.traeger._zuege_lesen()["runs"][run_id]["session_id"]
        pid = self.laeufe[run_id].pid
        # Eine spaete Erfolgsausgabe liegt schon vor; der Stop gewinnt trotzdem.
        self.outputs[pid] = self.stream(session)
        stopped = self.traeger.agent_stoppen("a1", "Sofortstopp", absender="haupt")
        self.assertEqual((stopped["run"], stopped["observed"]), (run_id, "stopped"))
        self.assertIsNotNone(self.launcher.processes[pid].poll())
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "unterbrochen")
        with self.assertRaises(ad.AgentsError):
            ad.write_result(self.world, "t1", "a1", "zu spaet", None, "a1", "mitglied")
        summary = self.traeger.einmal()
        self.assertEqual(summary["beendet"][0]["outcome"], "gestoppt")
        self.assertTrue(summary["beendet"][0]["handoff"])
        self.assertEqual(self.delivery_status(self.traeger._wecker_id("a1", "ticket-2_t1")).outcome, "gestoppt")
        self.assertEqual(self.traeger.einmal()["gestartet"], [])
        resumed = self.traeger.agent_fortsetzen("a1", absender="haupt")
        self.assertEqual(resumed["reopened"], [{"ticket": "t1", "state": "offen"}])
        started = self.traeger.einmal()["gestartet"]
        self.assertEqual(len(started), 1)
        new_run = started[0]["run"]
        entry = self.traeger._zuege_lesen()["runs"][new_run]
        self.assertTrue(entry["resume"])
        self.assertEqual(entry["session_id"], session)
        self.assertTrue(self.laeufe[new_run].zug.resume)
        restored = (Path(entry["config_dir"]) / "projects" / ac.projekt_ordnername(entry["workspace"])
                    / (session + ".jsonl")).read_text()
        self.assertIn("amber-1234abcd", restored.splitlines()[0])
        self.finish(new_run, "amber-1234abcd")
        self.assertEqual(self.traeger.einmal()["beendet"][0]["outcome"], "erfolg")

    def test_world_pause_and_stop_apply_to_all_agents(self):
        self.ticket("t1", agent="a1")
        self.ticket("t2", agent="a2")
        started = {item["agent"]: item["run"] for item in self.traeger.einmal()["gestartet"]}
        self.assertEqual(set(started), {"a1", "a2"})
        paused = self.traeger.welt_pausieren("Weltpause", absender="haupt")
        self.assertEqual(set(paused["active_runs"]), set(started.values()))
        self.finish(started["a1"], "a1 fertig")
        self.ticket("t3", agent="a1")
        summary = self.traeger.einmal()
        self.assertEqual(summary["gestartet"], [])
        self.assertIn("paused", [item["reason"] for item in summary["wartend"]])
        stopped = self.traeger.welt_stoppen("Weltstopp", absender="haupt")
        self.assertEqual([item["run"] for item in stopped["stopped"]], [started["a2"]])
        self.assertIsNotNone(self.launcher.processes[self.laeufe[started["a2"]].pid].poll())
        summary = self.traeger.einmal()
        self.assertEqual({item["outcome"] for item in summary["beendet"]}, {"gestoppt"})
        self.assertEqual(summary["gestartet"], [])
        self.assertEqual(ad.read_ticket(self.world, "t2")["state"], "unterbrochen")
        resumed = self.traeger.welt_fortsetzen(absender="haupt")
        self.assertEqual(resumed["reopened"], [{"ticket": "t1", "state": "zur Abnahme"},
                                               {"ticket": "t2", "state": "offen"}])
        self.assertEqual({item["ticket"] for item in self.traeger.einmal()["gestartet"]}, {"t2", "t3"})

    def test_missing_model_credential_or_run_binding_never_claims_blindly(self):
        ad.create_agent(self.world, "a3", "mitglied", None, "ohne Claude", None, None, "opus55:xhigh", None, None,
                        None, "host2", "haupt", "hauptagent")
        self.ticket("t3", agent="a3")
        summary = self.traeger.einmal()
        self.assertEqual([item["reason"] for item in summary["wartend"]], ["modell_nicht_aufloesbar"])
        self.credential.available = False
        self.ticket("t1")
        summary = self.traeger.einmal()
        self.assertIn("anmeldung", [item["reason"] for item in summary["wartend"]])
        self.assertEqual(summary["gestartet"], [])
        with self.assertRaises(Exception):
            self.traeger.wecker.status(self.traeger._wecker_id("a1", "ticket-2_t1"))
        self.credential.available = True
        # Absturz zwischen Claim und Zugregister: sichtbar ungeklaert, kein zweiter Start.
        world_id = self.traeger.world_id()
        from agents_wecker import Delivery
        item = self.postfach("a1", "ticket-2_t1")
        claim = self.traeger.wecker.claim(
            Delivery(self.traeger._wecker_id("a1", "ticket-2_t1"), world_id, "a1", "ticket", at._epoch(item["time"], 0.0),
                     at._inhalt("ticket", ticket_id="t1", postfach_id="ticket-2_t1")),
            desired_world_state="running", desired_agent_state="running", active_run=None, progress_marker="t1:0")
        self.assertEqual(claim.status, "claimed")
        summary = self.traeger.einmal()
        self.assertEqual(summary["gestartet"], [])
        self.assertEqual(summary["ungeklaert"][0]["reason"], "claim_ohne_zug")
        self.assertEqual(self.launcher.processes, {})

    def test_laufen_exits_when_idle_and_rejects_second_instance(self):
        self.auto.update({"a1", "a2"})
        self.ticket("t1")
        entered = threading.Event()
        release = threading.Event()
        original = self.traeger.einmal

        def slow_once():
            entered.set()
            release.wait(5)
            return original()

        self.traeger.einmal = slow_once
        result = {}
        thread = threading.Thread(target=lambda: result.update(self.traeger.laufen(frist_s=30, poll_s=0.05)))
        thread.start()
        self.assertTrue(entered.wait(5))
        self.assertEqual(self.make().laufen(frist_s=1), {"status": "laeuft_bereits"})
        release.set()
        thread.join(15)
        self.assertFalse(thread.is_alive())
        self.assertEqual(result["status"], "leerlauf")
        runs = self.traeger._zuege_lesen()["runs"]
        self.assertEqual([entry["outcome"] for entry in runs.values()], ["erfolg"])
        self.assertTrue(self.traeger.orte.exiting.exists())

    def abgewiesen(self, status, resets_at=None):
        def build(session):
            events = [{"type": "system", "subtype": "init", "session_id": session}]
            if status == 429:
                events.append({"type": "rate_limit_event", "session_id": session, "rate_limit_info": {
                    "status": "rejected", "resetsAt": resets_at, "rateLimitType": "five_hour"}})
            events.append({"type": "result", "subtype": "success", "is_error": True, "terminal_reason": "api_error",
                           "api_error_status": status, "result": "limit", "session_id": session})
            return "".join(json.dumps(event) + "\n" for event in events).encode()
        return build

    def budget_runner(self, state):
        class Result:
            def __init__(self, stdout):
                self.stdout = stdout
                self.returncode = 0

        def run(command, **_kwargs):
            if command[0] == "wb-budget":
                return Result(json.dumps(state["budget"]))
            return Result(json.dumps(state.get("kontingent", {"harnesses": {}})))
        return run

    def test_messages_wake_only_addressees_need_a_reply_and_bind_their_chain(self):
        ad.send_message(self.world, "a1", ["a2"], "Wie weit bist du?", None, "m-kanal", "mitglied")
        first = self.traeger.einmal()
        self.assertEqual([(item["agent"], item["art"]) for item in first["gestartet"]], [("a2", "nachricht")])
        run_a2 = first["gestartet"][0]["run"]
        prompt = self.laeufe[run_a2].zug.prompt
        self.assertIn("Wie weit bist du?", prompt)
        self.assertIn("message.reply", prompt)
        self.finish(run_a2, reply="Fast fertig")
        second = self.traeger.einmal()
        self.assertEqual([(item["agent"], item["outcome"]) for item in second["beendet"]], [("a2", "erfolg")])
        self.assertTrue(self.postfach("a2", "m-kanal")["acknowledged"])
        woken = [item for item in second["gestartet"] if item["agent"] == "a1"]
        self.assertEqual(len(woken), 1)
        entry = self.traeger._zuege_lesen()["runs"][woken[0]["run"]]
        self.assertEqual((entry["chain"], entry["art"]), ([self.traeger._wecker_id("a2", "m-kanal")], "rueckmeldung"))
        self.assertIn("No answer is required", self.laeufe[woken[0]["run"]].zug.prompt)
        self.finish(woken[0]["run"])
        read = self.traeger.einmal()
        self.assertEqual([item["outcome"] for item in read["beendet"]], ["erfolg"])
        self.assertEqual(read["gestartet"], [])
        self.assertTrue(self.postfach("a1", self.traeger._antwort_id("a2", "m-kanal"))["acknowledged"])

        ad.send_message(self.world, "mensch", ["a1"], "Ohne Antwort?", None, "m-offen", None)
        run_open = self.traeger.einmal()["gestartet"][0]["run"]
        self.finish(run_open)
        missing = self.traeger.einmal()["beendet"][0]
        self.assertEqual((missing["outcome"], "recovery" in missing["folge"]), ("ergebnis_fehlt", True))
        self.assertFalse(self.postfach("a1", "m-offen")["acknowledged"])

        ad.send_message(self.world, "person-1", ["a2"], "Direkt an dich", None, "m-direkt", None, direct=True)
        run_direct = self.traeger.einmal()["gestartet"]
        self.assertEqual([(item["agent"], item["delivery"]) for item in run_direct],
                         [("a2", self.traeger._wecker_id("a2", "m-direkt"))])
        # Ein Rundruf traegt bei jedem Empfaenger dieselbe Postfachkennung; jeder bekommt seinen Zug.
        self.assertIn("direct chat", self.laeufe[run_direct[0]["run"]].zug.prompt)
        self.finish(run_direct[0]["run"], reply="Gelesen")
        self.assertEqual(self.traeger.einmal()["beendet"][0]["outcome"], "erfolg")
        chat = ad.derived_id("chat", "a2", "person-1")
        self.assertEqual(sorted(item["sender"] for item in ad.read_messages(self.world, direct_chat=chat)), ["a2", "person-1"])
        self.assertEqual(self.traeger._zuege_lesen()["sessions"]["a2"][at.NACHRICHTEN_SITZUNG]["handoff_run"],
                         run_direct[0]["run"])

    def test_answered_question_wakes_the_asking_agent_exactly_once(self):
        import dataclasses
        konfig = dataclasses.replace(self.konfig, modelle={"opus55:xhigh": MODEL})
        traeger = self.make(konfig)
        ad.ask_question(self.world, "Welche Datenbank?", ["A", "B"], "A", None, "frage-1", "haupt", "hauptagent")
        self.assertEqual([item for item in traeger.einmal()["gestartet"] if item["agent"] == "haupt"], [])
        ad.answer_question(self.world, "frage-1", "B, wegen Replikation", "person-1")
        started = [item for item in traeger.einmal()["gestartet"] if item["agent"] == "haupt"]
        self.assertEqual([item["art"] for item in started], ["antwort"])
        self.assertIn("B, wegen Replikation", self.laeufe[started[0]["run"]].zug.prompt)
        self.traeger = traeger
        self.finish(started[0]["run"])
        summary = traeger.einmal()
        self.assertEqual([item["outcome"] for item in summary["beendet"]], ["erfolg"])
        self.assertEqual([item for item in summary["gestartet"] if item["agent"] == "haupt"], [])

    def test_quota_rejection_sleeps_until_next_start_and_resumes_with_same_model(self):
        now = time.time()
        state = {"budget": {"five_hour_pct": 40, "five_hour_resets_at_epoch": now + 3000,
                            "seven_day_pct": 10, "seven_day_resets_at_epoch": now + 6 * 86400}}
        from agents_kontingent import KontingentQuelle
        self.kontingent = KontingentQuelle(runner=self.budget_runner(state), clock=lambda: time.time() + self.offset)
        self.traeger = self.make()
        self.ticket("t1")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        state["budget"]["five_hour_pct"] = 100
        self.finish(run_id, stream=self.abgewiesen(429, resets_at=int(now + 1200)))
        done = self.traeger.einmal()
        verdict = done["beendet"][0]
        self.assertEqual(verdict["outcome"], "kontingent")
        self.assertEqual({item["grund"] for item in verdict["folge"]["sperren"]}, {"fuenf_stunden", "backend"})
        self.assertAlmostEqual(verdict["folge"]["bis"], now + 3000, delta=2)
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "läuft")
        waiting = self.traeger.einmal()
        self.assertEqual((waiting["gestartet"], waiting["wartend"][0]["reason"]), ([], "schlaeft"))
        self.assertAlmostEqual(self.traeger.naechster_weckzeitpunkt(), now + 3000, delta=2)
        self.offset = 3001
        state["budget"]["five_hour_pct"] = 0
        resumed = self.traeger.einmal()["gestartet"]
        self.assertEqual([(item["art"], item["ticket"]) for item in resumed], [("fortsetzen", "t1")])
        entry = self.traeger._zuege_lesen()["runs"][resumed[0]["run"]]
        self.assertEqual((entry["model"], entry["resume"], entry["cause"]), (MODEL, True, "self_timer"))
        self.finish(resumed[0]["run"], "fertig nach Pause")
        self.assertEqual(self.traeger.einmal()["beendet"][0]["outcome"], "erfolg")

    def test_budget_gate_and_credential_expiry_sleep_before_any_claim(self):
        now = time.time()
        state = {"budget": {"five_hour_pct": 10, "five_hour_resets_at_epoch": now + 3000,
                            "seven_day_pct": 100, "seven_day_resets_at_epoch": now + 7200}}
        from agents_kontingent import KontingentQuelle
        self.kontingent = KontingentQuelle(runner=self.budget_runner(state), clock=lambda: time.time() + self.offset)
        self.traeger = self.make()
        self.ticket("t1")
        summary = self.traeger.einmal()
        self.assertEqual((summary["gestartet"], summary["wartend"][0]["reason"]), ([], "kontingent"))
        self.assertAlmostEqual(summary["wartend"][0]["bis"], now + 7200, delta=2)
        with self.assertRaises(Exception):
            self.traeger.wecker.status(self.traeger._wecker_id("a1", "ticket-2_t1"))
        timers = [item for item, _ in self.traeger.wecker.offene(self.traeger.world_id(), "a1")]
        self.assertEqual([(item.cause, json.loads(item.content)["art"]) for item in timers], [("self_timer", "aufwachen")])
        self.traeger.laufen(frist_s=5, poll_s=0.01)
        self.assertAlmostEqual(self.timer_calls[-1], now + 7200, delta=2)
        self.offset = 7201
        state["budget"]["seven_day_pct"] = 0
        self.credential.available = False
        summary = self.traeger.einmal()
        self.assertEqual((summary["gestartet"], summary["wartend"][-1]["reason"]), ([], "anmeldung"))
        self.assertEqual(self.traeger._zuege_lesen()["schlaf"]["a1"]["grund"], "anmeldung")
        self.credential.available = True
        self.offset += at.RECHECK_S + 1
        started = self.traeger.einmal()["gestartet"]
        self.assertEqual([item["ticket"] for item in started], ["t1"])
        self.finish(started[0]["run"], stream=self.abgewiesen(401))
        verdict = self.traeger.einmal()["beendet"][0]
        self.assertEqual((verdict["outcome"], verdict["folge"]["schlaf"]), ("anmeldung", "anmeldung"))

    def test_time_limit_stop_releases_the_binding_so_recovery_can_start(self):
        import dataclasses
        traeger = self.make(dataclasses.replace(self.konfig, zug_frist_s=5.0))
        self.traeger = traeger
        self.ticket("tz")
        first = traeger.einmal()["gestartet"][0]["run"]
        self.offset += 10
        stopping = traeger.einmal()
        self.assertEqual([item["run"] for item in stopping["aktiv"]], [first])
        done = traeger.einmal()["beendet"]
        self.assertEqual([(item["run"], item["outcome"], "recovery" in item.get("folge", {})) for item in done],
                         [(first, "zeitlimit", True)])
        self.assertIn("Zugfrist", traeger._zuege_lesen()["runs"][first]["detail"])
        self.offset += 400
        again = traeger.einmal()
        # Gemessen auf host2: ohne Freigabe endete jede Recovery mit startfehler („neue Starts gesperrt“).
        self.assertEqual([(item["art"], item["agent"]) for item in again["gestartet"]], [("fortsetzen", "a1")])
        second = again["gestartet"][0]["run"]
        self.assertIsNone(traeger._zuege_lesen()["runs"][second]["outcome"])
        ad.set_agent_state(self.world, "a1", "gestoppt", "Mensch stoppt", "mensch", None)
        traeger.runs().stop(traeger.world_id(), "a1")
        traeger._bindung_freigeben(traeger.world_id(), "a1")
        with self.assertRaises(al.LaufFehler):
            traeger.runs().start(traeger.world_id(), "a1", "zug-probe", al.StartSpec((sys.executable, "-c", "pass"), str(self.root)))

    def test_recovery_is_bounded_by_the_wake_up_contract(self):
        self.ticket("t1")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        self.finish(run_id, complete=False)
        self.assertEqual(self.traeger.einmal()["beendet"][0]["outcome"], "abgeschnitten")
        outcomes = []
        for attempt in range(3):
            self.offset += at.RECOVERY_ABSTAND_S + 1
            summary = self.traeger.einmal()
            if not summary["gestartet"]:
                outcomes.append([item["reason"] for item in summary["wartend"]])
                break
            self.finish(summary["gestartet"][0]["run"], complete=False)
            outcomes.append(self.traeger.einmal()["beendet"][0]["outcome"])
        self.assertEqual(outcomes[:2], ["abgeschnitten", "abgeschnitten"])
        self.assertIn("recovery_limit", outcomes[2])
        self.assertEqual(len(self.launcher.processes), 3)

    def test_start_error_tombstone_is_visible_and_only_cleared_with_proven_end(self):
        self.ticket("t1")
        self.launcher.fail_launch = True
        summary = self.traeger.einmal()
        self.assertEqual(summary["gestartet"], [])
        entries = list(self.traeger._zuege_lesen()["runs"].values())
        self.assertEqual([entry["outcome"] for entry in entries], ["startfehler"])
        status = self.traeger.status()
        self.assertEqual([item["agent"] for item in status["ungeklaerte_laeufe"]], ["a1"])
        self.launcher.fail_launch = False
        self.offset += at.RECOVERY_ABSTAND_S + 1
        blocked = self.traeger.einmal()
        self.assertEqual(blocked["gestartet"], [])
        self.assertIn("ungeklaerter_lauf", [item["reason"] for item in blocked["wartend"]])
        with self.assertRaises(al.LaufUngeklaert):
            self.traeger.klaeren("a1")
        self.launcher.ended_proven = True
        self.assertEqual(self.traeger.klaeren("a1")["observed"], "stopped")
        self.assertEqual(self.traeger.status()["ungeklaerte_laeufe"], [])
        started = self.traeger.einmal()["gestartet"]
        self.assertEqual([(item["art"], item["ticket"]) for item in started], [("fortsetzen", "t1")])

    def test_stopped_message_turn_stays_open_until_explicit_resume(self):
        ad.send_message(self.world, "a1", ["a2"], "Bitte antworten", None, "m-stop", "mitglied")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        self.traeger.agent_stoppen("a2", "Sofortstopp", absender="haupt")
        self.assertEqual(self.traeger.einmal()["beendet"][0]["outcome"], "gestoppt")
        self.assertFalse(self.postfach("a2", "m-stop")["acknowledged"])
        self.assertEqual(self.traeger.einmal()["gestartet"], [])
        resumed = self.traeger.agent_fortsetzen("a2", absender="haupt")
        self.assertEqual(resumed["reopened"], [{"nachricht": "m-stop", "state": "offen"}])
        again = self.traeger.einmal()["gestartet"]
        self.assertEqual([(item["agent"], item["art"]) for item in again], [("a2", "nachricht")])
        entry = self.traeger._zuege_lesen()["runs"][again[0]["run"]]
        self.assertTrue(entry["resume"])
        self.finish(again[0]["run"], reply="Jetzt ja")
        self.traeger.einmal()
        self.assertTrue(self.postfach("a2", "m-stop")["acknowledged"])
        self.assertNotEqual(run_id, again[0]["run"])

    def test_broadcast_with_one_message_id_starts_one_turn_per_addressee(self):
        import dataclasses
        traeger = self.make(dataclasses.replace(self.konfig, modelle={"opus55:xhigh": MODEL}))
        ad.send_message(self.world, "haupt", ["alle"], "Rundruf", None, "r-1", "hauptagent")
        started = traeger.einmal()["gestartet"]
        self.assertEqual(sorted((item["agent"], item["art"]) for item in started), [("a1", "nachricht"), ("a2", "nachricht")])
        self.assertEqual(len({item["delivery"] for item in started}), 2)
        self.traeger = traeger
        for item in started:
            self.finish(item["run"], reply="gelesen %s" % item["agent"])
        summary = traeger.einmal()
        self.assertEqual(sorted(item["outcome"] for item in summary["beendet"]), ["erfolg", "erfolg"])
        self.assertTrue(self.postfach("a1", "r-1")["acknowledged"] and self.postfach("a2", "r-1")["acknowledged"])
        self.assertFalse((self.world / "agents" / "haupt" / "postfach" / "r-1.json").exists() and any(
            item["agent"] == "haupt" and item["art"] == "nachricht" for item in summary["gestartet"]))

    @unittest.skipUnless((SHELL / "wb-ticket").exists(), "kit: wb-ticket is not shipped (port/strip.txt)")
    def test_cli_wrappers_wake_only_a_configured_world(self):
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        log = self.root / "calls.log"
        for name in ("systemd-run", "systemctl", "ssh"):
            script = bin_dir / name
            script.write_text("#!/bin/sh\necho \"%s $*\" >> %s\n%s\nexit 0\n" % (
                name, log, 'echo \'{"wecken": "gestartet"}\'' if name == "ssh" else ""))
            script.chmod(0o755)
        env = dict(os.environ, PATH="/usr/bin:/bin")

        def wrapper(tool, *args):
            return subprocess.run([str(SHELL / tool), *map(str, args)], text=True, capture_output=True,
                                  env=env, timeout=60)

        result = wrapper("wb-ticket", "neu", self.world, "--id", "cli-1", "--titel", "T", "--ziel", "Z",
                         "--fertig", "F", "--an", "a1", "--absender", "haupt", "--rolle", "hauptagent",
                         "--json")
        self.assertEqual((result.returncode, result.stderr), (0, ""))
        self.assertFalse(log.exists())
        konfig = dict(self.konfig.as_dict(), maschine="lokal",
                      launcher={"systemd_run": str(bin_dir / "systemd-run"), "systemctl": str(bin_dir / "systemctl")})
        (self.world / "traeger.json").write_text(json.dumps(konfig))
        result = wrapper("wb-ticket", "neu", self.world, "--id", "cli-2", "--titel", "T", "--ziel", "Z",
                         "--fertig", "F", "--an", "a1", "--absender", "haupt", "--rolle", "hauptagent",
                         "--json")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)["id"], "cli-2")
        self.assertIn("wb-agents: Traeger gestartet", result.stderr)
        calls = log.read_text()
        self.assertIn("--unit=%s" % at.traeger_unit(self.konfig), calls)
        self.assertIn("laufen --konfig %s" % (self.world / "traeger.json").resolve(), calls)
        self.assertEqual(wrapper("wb-kanal", "senden", self.world, "--absender", "haupt", "--an", "a1",
                                 "--text", "Hallo", "--json").stderr.strip(), "wb-agents: Traeger gestartet")
        ad.ask_question(self.world, "Frage?", None, None, None, "cli-frage", "haupt", "hauptagent")
        antwort = wrapper("wb-welt", "antwort", self.world, "cli-frage", "--text", "Ja")
        self.assertEqual(antwort.returncode, 2)
        self.assertIn("Herkunftsbeleg fuer Menschenname 'mensch' abgelehnt", antwort.stderr)
        self.assertNotIn("Traeger gestartet", antwort.stderr)
        ad.create_agent(self.world, "tl", "teamleiter", "bau", "Leitet", None, None, MODEL, None, None, None,
                        "host2", "haupt", "hauptagent")
        entwurf = json.dumps({"id": "cli-helfer", "specialty": "Hilft", "tools": ["Read"]})
        result = wrapper("wb-agent", "antrag", self.world, "--entwurf", entwurf, "--absender", "tl", "--rolle",
                         "teamleiter", "--id", "antrag-cli", "--json")
        self.assertEqual(result.returncode, 2)
        self.assertIn("run-gebundenen Controller-Beleg", result.stderr)
        self.assertNotIn("Traeger gestartet", result.stderr)
        ad.request_agent(self.world, json.loads(entwurf), "tl", "teamleiter", "antrag-cli")
        result = wrapper("wb-agent", "antrag-entscheiden", self.world, "antrag-cli", "--ablehnen", "--bemerkung", "nein",
                         "--absender", "haupt", "--rolle", "hauptagent")
        self.assertEqual(result.returncode, 2)
        self.assertIn("run-gebundenen Controller-Beleg", result.stderr)
        self.assertNotIn("Traeger gestartet", result.stderr)
        self.assertEqual(wrapper("wb-agent", "liste", self.world, "--json").stderr, "")
        self.assertEqual(wrapper("wb-kanal", "lesen", self.world, "--json").stderr, "")
        remote = dict(konfig, maschine="fernhost", traeger_modul="/opt/werkbank/shell/agents_traeger.py")
        (self.world / "traeger.json").write_text(json.dumps(remote))
        env["WB_TRAEGER_SSH"] = str(bin_dir / "ssh")
        result = wrapper("wb-ticket", "neu", self.world, "--id", "cli-3", "--titel", "T", "--ziel", "Z",
                         "--fertig", "F", "--an", "a1", "--absender", "haupt", "--rolle", "hauptagent")
        self.assertEqual((result.returncode, result.stderr.strip()), (0, "wb-agents: Traeger gestartet"))
        self.assertIn("ssh -oBatchMode=yes -oConnectTimeout=8 fernhost", log.read_text())
        (self.world / "traeger.json").write_text(json.dumps(dict(konfig, world_root=str(self.root / "andere"))))
        result = wrapper("wb-ticket", "neu", self.world, "--id", "cli-4", "--titel", "T", "--ziel", "Z",
                         "--fertig", "F", "--an", "a1", "--absender", "haupt", "--rolle", "hauptagent")
        self.assertEqual(result.returncode, 0)
        self.assertIn("Traeger nicht geweckt", result.stderr)
        self.assertEqual(ad.read_ticket(self.world, "cli-4")["id"], "cli-4")

    def test_work_from_the_human_reports_back_into_the_human_postbox(self):
        postbox = self.world / "menschen" / "mensch" / "postfach"
        ad.create_ticket(self.world, "Vom Menschen", "Ziel", "fertig", ["a1"], "mensch", None, ticket_id="tm", kind="auftrag")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        self.finish(run_id, "Ergebnis fuer den Menschen")
        done = self.traeger.einmal()["beendet"][0]
        message_id = ad.derived_id("result", "tm")
        self.assertEqual(done["outcome"], "erfolg")
        # Ein Ergebnis an den Menschen ist genau ein markierter Eintrag, ohne zusaetzliche Traegermeldung.
        stored = json.loads((postbox / (message_id + ".json")).read_text())
        self.assertEqual((stored["kind"], stored["sender"], stored["mark"], stored["ticket"], stored["text"]),
                         ("ticket-ergebnis", "a1", "ergebnis", "tm", "Ergebnis fuer den Menschen"))
        channel = [item for item in ad.read_messages(self.world) if item.get("ticket") == "tm"]
        self.assertEqual([(item["id"], item.get("humans"), item.get("mark")) for item in channel],
                         [(message_id, ["mensch"], "ergebnis")])
        self.ticket("th")
        run_haupt = self.traeger.einmal()["gestartet"][0]["run"]
        self.finish(run_haupt, "Ergebnis fuer haupt")
        self.assertEqual(self.traeger.einmal()["beendet"][0]["outcome"], "erfolg")
        self.assertEqual(sorted(path.name for path in postbox.glob("*.json")), [message_id + ".json"])
        self.assertNotIn("mark", [item for item in ad.read_messages(self.world) if item.get("ticket") == "th"][0])

        for delivery, direct in (("mensch-kanal", False), ("mensch-direkt", True)):
            ad.send_message(self.world, "mensch", ["a2"], "Vom Menschen", None, delivery, None, direct=direct)
            started = self.traeger.einmal()["gestartet"]
            self.assertEqual([(item["agent"], item["art"]) for item in started], [("a2", "nachricht")])
            self.assertIn("from mensch", self.laeufe[started[0]["run"]].zug.prompt)
            self.finish(started[0]["run"], reply="Antwort auf " + delivery)
            self.assertEqual(self.traeger.einmal()["beendet"][0]["outcome"], "erfolg")
            reply = json.loads((postbox / (self.traeger._antwort_id("a2", delivery) + ".json")).read_text())
            self.assertEqual((reply["sender"], reply["text"], "mark" in reply), ("a2", "Antwort auf " + delivery, False))
        self.assertEqual(self.traeger.einmal()["gestartet"], [])

    def skill_stream(self, command=None, usage=True):
        def build(session):
            content = [{"type": "tool_use", "name": "Bash", "input": {"command": command or "true"}}]
            result = {"type": "result", "subtype": "success", "is_error": False, "terminal_reason": "completed",
                      "result": "done", "session_id": session, "num_turns": 2, "total_cost_usd": 0.01}
            if usage:
                result["usage"] = {"input_tokens": 40, "output_tokens": 12, "cache_read_input_tokens": 300,
                                   "cache_creation_input_tokens": 20}
            return "\n".join(json.dumps(event) for event in (
                {"type": "system", "subtype": "init", "session_id": session},
                {"type": "assistant", "session_id": session, "message": {"content": content}}, result)).encode() + b"\n"
        return build

    @unittest.skipUnless(BIBLIOTHEK.is_dir(), OHNE_BIBLIOTHEK)
    def test_turn_gets_skills_instructions_effort_and_ends_with_learning_step_and_measurement(self):
        import dataclasses
        import agents_skills as ask
        library = SHELL.parent / "agents" / "bibliothek" / "skills"
        registry = self.root / "models.json"
        registry.write_text(json.dumps({"models": [{"id": "claude-opus-5-5", "maxEffort": "high"}]}))
        konfig = dataclasses.replace(self.konfig, modelle={"opus55:xhigh": "claude-opus-5-5"}, skill_bibliothek=str(library))
        with aufbau_herkunft(ad) as aufbau:
            ad.create_agent_from_draft(self.world, {"id": "s1", "specialty": "Schreibt Ergebnisse",
                                                    "model": "opus55:xhigh", "tools": ["Read"],
                                                    "skills": ["ergebnis-schreiben", "zitat-beleg"]}, aufbau)
        ask.create_skill(self.world, "s1", "notizen", "Eigene Notizen ordnen")
        traeger = self.make(konfig)
        self.traeger = traeger
        ad.create_ticket(self.world, "Mit Skill", "Ziel", "fertig", ["s1"], "haupt", "hauptagent", ticket_id="ts", kind="auftrag")
        run_id = traeger.einmal()["gestartet"][0]["run"]
        lauf, entry = self.laeufe[run_id], traeger._zuege_lesen()["runs"][run_id]
        run_dir = Path(entry["run_dir"])
        self.assertEqual((run_dir.name, run_dir.parent.name), (run_id, "state"))
        self.assertEqual((lauf.zug.effort, entry["denkstufe"]["wirksam"], entry["denkstufe"]["gesenkt"]),
                         ("xhigh", "xhigh", False))
        self.assertEqual(entry["skills"], ["ergebnis-schreiben", "notizen", "zitat-beleg"])
        directory = json.loads((self.world / "agents" / "s1" / "skills.json").read_text())
        paths = {item["name"]: item["pfad"] for item in directory["skills"]}
        scripts = SHELL.parent / "agents" / "bibliothek" / "skripte"
        self.assertEqual(set(lauf.read_paths), {Path(paths["ergebnis-schreiben"]), Path(paths["notizen"]),
                                                Path(paths["zitat-beleg"]), self.world / "agents" / "s1" / "skills.json",
                                                self.world / "agents" / "s1" / "agent.json", library, scripts})
        env = dict(lauf.zug.extra_env)
        # Namen der Sperren (docs/AGENTS-SPERREN.md) plus Zugordner, RPC-Client und Hausliste.
        self.assertEqual((env["WB_WELT"], env["WB_AGENT_ID"], env["WB_AGENT_ZUG"], env["WB_AGENT_TMP"],
                          env["WB_SKILL_BIBLIOTHEK"], env["WB_SKILLS_JSON"]),
                         (str(self.world), "s1", str(run_dir), str(run_dir), str(library),
                          str(self.world / "agents" / "s1" / "skills.json")))
        self.assertEqual(env["WB_AGENT_PROFIL"], str(self.world / "agents" / "s1" / "agent.json"))
        self.assertEqual(env["WB_SKILL_PFADE"].split(os.pathsep), [paths["ergebnis-schreiben"], paths["notizen"]])
        self.assertEqual((env["WB_SKRIPT_PFADE"], env["WB_SKRIPT_BIBLIOTHEK"]), (paths["zitat-beleg"], str(scripts)))
        self.assertEqual(env["WB_AGENT_WORKTREE"], str(lauf.workspace))
        self.assertEqual(env["WB_RPC_CLIENT"], str(run_dir / "rpc" / "agents_rpc_client.py"))
        self.assertTrue(Path(env["WB_RPC_CLIENT"]).is_file() and Path(env["WB_PROFIL_BIN"]).is_file())
        self.assertNotIn("WB_WELT_PROJEKT", env)
        settings = json.loads(Path(lauf.zug.settings_file).read_text())
        commands = {(item["matcher"], hook["command"]) for item in settings["hooks"]["PreToolUse"] for hook in item["hooks"]}
        runtime = traeger.orte.runtime / "hooks"
        self.assertIn(("Bash", 'bash "%s"' % (runtime / "skills-sperre.sh")), commands)
        self.assertIn(("*", 'bash "%s"' % (runtime / "profil-sperre.sh")), commands)
        self.assertTrue((runtime / "lib" / "profil_sperre.py").is_file())
        # An own tool list always carries Bash for the RPC service path (agents_data, 2026-09-15).
        self.assertEqual(lauf.zug.tools, ("Read", "Bash"))
        anweisung = Path(lauf.zug.append_system_prompt_file).read_text()
        for needle in ("# s1 – Anweisungen", "## Dein Gedächtnis", "`%s/SKILL.md`" % paths["ergebnis-schreiben"],
                       "`notizen` (agent", "%s/lernschritt.json" % run_dir, '"art": "nichts"',
                       "Skript `zitat-beleg` (bibliothek", "Datei `%s/zitat-beleg.py`" % paths["zitat-beleg"],
                       "Aufruf `zitat-beleg.py --quelle"):
            self.assertIn(needle, anweisung)
        self.assertNotIn("## Agenten anlegen", anweisung)
        self.assertIn("%s/scripts/ergebnis-schreiben.py --ticket ts" % paths["ergebnis-schreiben"], lauf.zug.prompt)
        self.assertIn(str(run_dir / "rpc" / "agents_rpc_client.py"), anweisung)
        self.assertIn("%s/lernschritt.json" % run_dir, lauf.zug.prompt)

        (run_dir / "lernschritt.json").write_text(json.dumps({"art": "lehre", "text": "Ergebnis per Skill ablegen.",
                                                              "grund": "spart Erklaerung"}))
        command = "%s/scripts/ergebnis-schreiben.py --ticket ts --text fertig" % paths["ergebnis-schreiben"]
        self.finish(run_id, "Ergebnis per Skill", stream=self.skill_stream(command))
        done = traeger.einmal()["beendet"][0]
        self.assertEqual((done["outcome"], done["lernschritt"]), ("erfolg", "angewendet"))
        stored = traeger._zuege_lesen()["runs"][run_id]
        self.assertEqual(stored["skill_aufrufe"], [{"skill": "ergebnis-schreiben", "skript": "ergebnis-schreiben.py"}])
        script_call = self.skill_stream("python3 %s/zitat-beleg.py --quelle q.txt" % paths["zitat-beleg"])("s")
        self.assertEqual(at._skill_aufrufe(script_call, ["zitat-beleg"], traeger._skills_pfade("s1")),
                         [{"skill": "zitat-beleg", "skript": "zitat-beleg.py"}])
        # tickets3: die Messung tritt die Art des Tickets (hier auftrag, siehe Helfer).
        self.assertEqual(stored["messung"], {"ticketart": "auftrag", "gesamt": 372, "vollstaendig": True})
        self.assertIn("Ergebnis per Skill ablegen. Grund: spart Erklaerung",
                      (self.world / "agents" / "s1" / "MEMORY.md").read_text())
        lines = (self.world / "agents" / "s1" / "messungen.jsonl").read_text().splitlines()
        self.assertEqual([(json.loads(line)["lauf"], json.loads(line)["ticketart"]) for line in lines], [(run_id, "auftrag")])
        self.assertEqual(traeger.status()["messungen"]["s1"]["arten"]["auftrag"]["anzahl"], 1)

        ad.create_ticket(self.world, "Ohne Lernschritt", "Ziel", "fertig", ["s1"], "haupt", "hauptagent", ticket_id="tn", kind="auftrag")
        second = traeger.einmal()["gestartet"][0]["run"]
        self.finish(second, "Ergebnis ohne Lehre", stream=self.skill_stream())
        done = traeger.einmal()["beendet"][0]
        self.assertEqual((done["outcome"], done["lernschritt"], done["vermerk"], "folge" in done),
                         ("erfolg", "fehlt", "kein Lernschritt", False))
        self.assertEqual(traeger.einmal()["gestartet"], [])
        self.assertEqual(traeger.status()["messungen"]["s1"]["anzahl"], 2)

        lowered = self.make(dataclasses.replace(konfig, registry=str(registry)))
        effort, befund = lowered.denkstufe(ad.read_agent(self.world, "s1"), "claude-opus-5-5")
        self.assertEqual((effort, befund["gesenkt"], befund["quelle"]), ("high", True, "vorgabe"))
        self.assertEqual(lowered.denkstufe(ad.read_agent(self.world, "a1"), MODEL)[0], "medium")

    @unittest.skipUnless(BIBLIOTHEK.is_dir(), OHNE_BIBLIOTHEK)
    def test_fresh_agent_turn_passes_the_locks_for_rpc_and_learning_script(self):
        """agentslauf Nr. 6: ein ohne Werkzeuge angelegter Agent meldet sein Ergebnis und schreibt den Lernschritt
        durch die echten Sperr-Hooks der Laufzeit; das Modell ist eine Attrappe."""
        import dataclasses
        library = SHELL.parent / "agents" / "bibliothek" / "skills"
        konfig = dataclasses.replace(self.konfig, skill_bibliothek=str(library))
        ad.create_agent(self.world, "frisch", "mitglied", None, "Frisch angelegt", None, None, MODEL, None, None, None,
                        "host2", "haupt", "hauptagent", skills=[at.LERNSKRIPT])
        self.assertEqual(ad.read_agent(self.world, "frisch")["bash"], list(ad.DEFAULT_BASH))
        traeger = self.make(konfig)
        self.traeger = traeger
        self.ticket("tf", agent="frisch")
        run_id = traeger.einmal()["gestartet"][0]["run"]
        lauf, entry = self.laeufe[run_id], traeger._zuege_lesen()["runs"][run_id]
        run_dir = Path(entry["run_dir"])
        blocks = re.findall(r"<<<\n(.*?)\n>>>", lauf.zug.prompt, re.S)
        # Ergebnis, Zwischenstand (Satz 16) und Lernschritt stehen als Markenbefehle im Prompt.
        self.assertEqual(len(blocks), 3, lauf.zug.prompt)
        rpc_command = blocks[0].replace("RESULT", "fertig")
        self.assertIn("ticket.note", blocks[1])
        note_command = blocks[1].replace("PROGRESS", "Stand: Recherche laeuft")
        script = SHELL.parent / "agents" / "bibliothek" / "skripte" / at.LERNSKRIPT / (at.LERNSKRIPT + ".py")
        self.assertEqual(blocks[2], 'python3 %s --art lehre --text "LESSON" --grund "REASON"' % script)
        learn_command = blocks[2].replace("LESSON", "Vorgaben reichen").replace("REASON", "RPC und Skript frei")
        anweisung = Path(lauf.zug.append_system_prompt_file).read_text()
        self.assertIn("3. Schreibe den Lernschritt mit deinem Skript `%s`" % at.LERNSKRIPT, anweisung)
        self.assertIn("Skript `%s` (bibliothek" % at.LERNSKRIPT, anweisung)
        settings = json.loads(Path(lauf.zug.settings_file).read_text())
        hooks = [(item["matcher"], hook["command"]) for item in settings["hooks"]["PreToolUse"] for hook in item["hooks"]]
        env = dict(lauf.zug.extra_env, PATH="/usr/bin:/bin", HOME=os.environ.get("HOME", "/"), LANG="C.UTF-8")

        def pruefen(tool, **fields):
            """Gruende der Hooks aus settings.json, aufgerufen wie Claude Code sie aufruft."""
            payload = json.dumps({"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": fields,
                                  "cwd": str(lauf.workspace), "session_id": "probe"})
            reasons = []
            for matcher, command in hooks:
                if matcher != "*" and tool not in matcher.split("|"):
                    continue
                result = subprocess.run(["/bin/bash", "-c", command], input=payload, text=True, capture_output=True,
                                        env=env, timeout=30)
                for line in result.stdout.splitlines():
                    decision = json.loads(line).get("hookSpecificOutput") or {}
                    if decision.get("permissionDecision") == "deny":
                        reasons.append(decision.get("permissionDecisionReason"))
            return reasons

        self.assertEqual(pruefen("Bash", command=rpc_command), [])
        self.assertEqual(pruefen("Bash", command=note_command), [])
        self.assertEqual(pruefen("Bash", command=learn_command), [])
        self.assertEqual(pruefen("Bash", command="git status"), [])
        self.assertIn("is not in the Bash patterns", " ".join(pruefen("Bash", command="sh ./tool.sh")))
        # Seit 15.09. schreibt auch ein Mitglied im eigenen Arbeitsordner; Web-Werkzeuge bleiben Wahl je Agent.
        self.assertEqual(pruefen("Write", file_path=str(lauf.workspace / "x.txt")), [])
        self.assertIn("tool list", " ".join(pruefen("WebFetch", url="http://beispiel.invalid/")))
        # Attrappe des Modells: das freigegebene Skript laeuft und schreibt den Lernschritt in den Zugordner.
        written = subprocess.run(["/bin/bash", "-c", learn_command], text=True, capture_output=True, env=env, timeout=30)
        self.assertEqual(written.returncode, 0, written.stdout + written.stderr)
        self.assertEqual(json.loads(written.stdout)["datei"], str(run_dir / "lernschritt.json"))
        self.finish(run_id, "fertig")
        done = traeger.einmal()["beendet"][0]
        self.assertEqual((done["outcome"], done["lernschritt"]), ("erfolg", "angewendet"))
        self.assertIn("Vorgaben reichen Grund: RPC und Skript frei",
                      (self.world / "agents" / "frisch" / "MEMORY.md").read_text())

    def test_world_access_turn_gets_network_key_copy_wrappers_and_locks_and_loses_them_at_turn_end(self):
        """Zugaenge einer Welt: Netz, Schluesselkopie im Zugordner, Huellen, Sperre; ohne Zugaenge alles wie bisher."""
        import agents_zugaenge as az
        keys = self.root / "keys"
        keys.mkdir(mode=0o700)
        (keys / "id_probe").write_text("NICHT-ECHT\n")
        (keys / "id_probe").chmod(0o600)
        (keys / "known_hosts").write_text("[127.0.0.1]:2222 ssh-ed25519 AAAAattrappe\n")
        # Ohne Zugaenge: kein Netz, kein Zugangsordner, keine Umgebung in den Einstellungen.
        self.ticket("t0")
        plain = self.traeger.einmal()["gestartet"][0]["run"]
        lauf = self.laeufe[plain]
        self.assertFalse(lauf.netz)
        self.assertFalse((self.traeger.orte.turns / plain / "zugaenge").exists())
        self.assertNotIn("env", json.loads(Path(lauf.zug.settings_file).read_text()))
        self.assertNotIn("## Zugänge", Path(lauf.zug.append_system_prompt_file).read_text())
        self.finish(plain, "fertig")
        self.traeger.einmal()

        az.hinzufuegen(self.world, {"name": "probe", "ziel": "agent@127.0.0.1", "port": 2222,
                                    "schluessel": str(keys / "id_probe"), "known_hosts": str(keys / "known_hosts")},
                       bestaetigt=True, absender="mensch")
        self.ticket("t1")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        lauf, entry = self.laeufe[run_id], self.traeger._zuege_lesen()["runs"][run_id]
        ordner = self.traeger.orte.turns / run_id / "zugaenge"
        self.assertTrue(lauf.netz)
        self.assertEqual((entry["zugaenge"], entry["zugaenge_fehler"]), (["probe"], None))
        self.assertIn(self.world / "zugaenge.json", lauf.read_paths)
        self.assertEqual((ordner / "probe" / "id").read_text(), "NICHT-ECHT\n")
        for name in ("probe/id", "probe/known_hosts", "ssh_config"):
            self.assertEqual((ordner / name).stat().st_mode & 0o777, 0o600, name)
        config = (ordner / "ssh_config").read_text()
        for line in ("Host probe", "HostName 127.0.0.1", "User agent", "Port 2222", 'IdentityFile "%s"' % (ordner / "probe" / "id"),
                     "IdentitiesOnly yes", 'UserKnownHostsFile "%s"' % (ordner / "probe" / "known_hosts"),
                     "StrictHostKeyChecking yes", "ProxyCommand none"):
            self.assertIn(line, config)
        wrapper = (ordner / "ssh").read_text()
        self.assertIn("-F '%s' -- \"$name\" \"$@\"" % (ordner / "ssh_config"), wrapper)
        self.assertEqual((ordner / "ssh").stat().st_mode & 0o777, 0o700)
        settings = json.loads(Path(lauf.zug.settings_file).read_text())
        self.assertEqual(settings["env"], {"PATH": "%s:/usr/local/bin:/usr/bin:/bin" % ordner, "WB_ZUGAENGE": str(ordner)})
        anweisung = Path(lauf.zug.append_system_prompt_file).read_text()
        self.assertIn("- Zugang `probe` (ssh): `ssh probe <befehl>`", anweisung)
        self.assertNotIn("127.0.0.1", anweisung)
        self.assertNotIn(str(keys), anweisung)

        hooks = [(item["matcher"], hook["command"]) for item in settings["hooks"]["PreToolUse"] for hook in item["hooks"]]
        env = dict(lauf.zug.extra_env, HOME=os.environ.get("HOME", "/"), LANG="C.UTF-8", **settings["env"])

        def pruefen(tool, **fields):
            payload = json.dumps({"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": fields,
                                  "cwd": str(lauf.workspace), "session_id": "probe"})
            reasons = []
            for matcher, command in hooks:
                if matcher != "*" and tool not in matcher.split("|"):
                    continue
                result = subprocess.run(["/bin/bash", "-c", command], input=payload, text=True, capture_output=True,
                                        env=env, timeout=30)
                for line in result.stdout.splitlines():
                    decision = json.loads(line).get("hookSpecificOutput") or {}
                    if decision.get("permissionDecision") == "deny":
                        reasons.append(decision.get("permissionDecisionReason"))
            return reasons

        self.assertEqual(pruefen("Bash", command="ssh probe hostname"), [])
        self.assertIn("Bash patterns", " ".join(pruefen("Bash", command="ssh anderer hostname")))  # Kit: English lock texts
        self.assertIn("access folder", " ".join(pruefen("Read", file_path=str(ordner / "probe" / "id"))))
        self.assertIn("access folder", " ".join(pruefen("Bash", command="scp %s probe:/tmp/x" % (ordner / "probe" / "id"))))
        self.assertTrue(pruefen("Bash", command="cat %s" % (ordner / "probe" / "id")))
        self.assertIn("not an ssh option", " ".join(pruefen("Bash", command="ssh probe -oProxyCommand=sh x")))

        # Zugende: die Kopien gehen, auch wenn der Traeger das Laufobjekt nicht mehr kennt.
        self.finish(run_id, "fertig")
        fresh = self.make()
        self.assertEqual(fresh.einmal()["beendet"][0]["outcome"], "erfolg")
        self.assertFalse(ordner.exists())
        # Ein verwaister Zugangsordner (Absturz zwischen Bereitstellung und Registereintrag) geht beim naechsten Durchgang.
        stray = self.traeger.orte.turns / "zug-verwaist" / "zugaenge" / "probe"
        stray.mkdir(parents=True)
        (stray / "id").write_text("x")
        fresh.einmal()
        self.assertFalse(stray.parent.exists())

    def test_world_access_that_cannot_be_provided_starts_the_turn_without_network(self):
        import agents_zugaenge as az
        key = self.root / "id_weg"
        key.write_text("x")
        (self.root / "known_hosts").write_text("x")
        az.hinzufuegen(self.world, {"name": "probe", "ziel": "agent@127.0.0.1", "schluessel": str(key),
                                    "known_hosts": str(self.root / "known_hosts")}, bestaetigt=True,
                       absender="mensch")
        key.unlink()
        self.ticket("t1")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        lauf, entry = self.laeufe[run_id], self.traeger._zuege_lesen()["runs"][run_id]
        self.assertFalse(lauf.netz)
        self.assertEqual(entry["zugaenge"], [])
        self.assertIn("Schluessel fehlt auf dem Traegerhost", entry["zugaenge_fehler"])
        self.assertFalse((self.traeger.orte.turns / run_id / "zugaenge").exists())
        self.assertIn("Die Zugänge der Welt sind in diesem Zug nicht bereit",
                      Path(lauf.zug.append_system_prompt_file).read_text())
        self.assertNotIn("env", json.loads(Path(lauf.zug.settings_file).read_text()))
        self.finish(run_id, "fertig")
        self.traeger.einmal()

    def test_wecken_resets_a_failed_carrier_unit_once_and_starts(self):
        bin_dir = self.root / "bin-failed"
        bin_dir.mkdir()
        log, reset = self.root / "failed-calls.log", self.root / "reset-done"
        (bin_dir / "systemd-run").write_text(
            "#!/bin/sh\necho \"systemd-run $*\" >> %s\n[ -e %s ] && exit 0\n"
            "echo 'Unit was already loaded or has a fragment file.' >&2\nexit 1\n" % (log, reset))
        (bin_dir / "systemctl").write_text(
            "#!/bin/sh\necho \"systemctl $*\" >> %s\n"
            "case \"$2\" in is-active) [ -e %s ] && { echo inactive; exit 3; }; echo failed; exit 3;;\n"
            "reset-failed) touch %s;; esac\nexit 0\n" % (log, reset, reset))
        for name in ("systemd-run", "systemctl"):
            (bin_dir / name).chmod(0o755)
        konfig = dict(self.konfig.as_dict(), systemd={"systemd_run": str(bin_dir / "systemd-run"),
                                                      "systemctl": str(bin_dir / "systemctl")})
        path = self.root / "traeger-failed.json"
        path.write_text(json.dumps(konfig))
        unit = at.traeger_unit(self.konfig)
        self.assertEqual(at.wecken(path, frist_s=5), "gestartet")
        calls = [line.split(" --", 1)[0] if line.startswith("systemd-run") else line
                 for line in log.read_text().splitlines()]
        self.assertEqual(calls, ["systemd-run", "systemctl --user is-active %s" % unit,
                                 "systemctl --user reset-failed %s" % unit, "systemd-run"])
        # Ohne fehlgeschlagene Unit bleibt es beim einen Aufruf; kein reset-failed auf Vorrat.
        log.unlink()
        self.assertEqual(at.wecken(path, frist_s=5), "gestartet")
        self.assertEqual(len(log.read_text().splitlines()), 1)

    def test_codex_model_from_registry_builds_the_call_and_ends_with_anmeldung_without_login(self):
        import dataclasses
        import agents_codex
        import agents_codex_runner
        registry = self.root / "models-codex.json"
        registry.write_text(json.dumps({"models": [
            {"id": "codex-gpt-5-5", "harness": "codex", "modelRef": "gpt-5.5", "efforts": ["low", "medium", "high", "xhigh"],
             "maxEffort": "xhigh", "enabled": True},
            {"id": "codex-alt", "harness": "codex", "modelRef": "gpt-alt", "enabled": False}]}))
        cli = self.root / "codex-bin" / "codex"
        cli.parent.mkdir()
        cli.write_text("#!/bin/sh\nexit 99\n")
        cli.chmod(0o755)
        auth = self.root / "codex-home" / "auth.json"
        konfig = dataclasses.replace(self.konfig, registry=str(registry), codex={"cli": str(cli), "auth": str(auth)})
        traeger = self.make(konfig)
        self.traeger = traeger
        for agent, model in (("cx", "codex-gpt-5-5:high"), ("cy", "codex-gpt-5-5:high"), ("alt", "codex-alt:high")):
            ad.create_agent(self.world, agent, "mitglied", None, "Codex", None, None, model, None, None, None, "host2",
                            "haupt", "hauptagent")
        self.assertEqual([traeger.harness(ad.read_agent(self.world, a)) for a in ("cx", "alt", "a1")],
                         ["codex", "claude", "claude"])
        self.assertEqual(traeger.modell(ad.read_agent(self.world, "cx")), "gpt-5.5")
        self.assertIsNone(traeger.modell(ad.read_agent(self.world, "alt")))

        # Keine Codex-Anmeldung: kein Aufbau, kein Start, Urteil `anmeldung`, der Agent schlaeft bis zur Nachpruefung.
        self.ticket("tc", agent="cx")
        summary = traeger.einmal()
        self.assertEqual((summary["gestartet"], self.laeufe), ([], {}))
        state = traeger._zuege_lesen()
        (entry,) = [e for e in state["runs"].values() if e["agent"] == "cx"]
        self.assertEqual((entry["harness"], entry["outcome"], entry["anmeldung"]["reason"]), ("codex", "anmeldung", "fehlt"))
        self.assertIn("Codex-Anmeldung fehlt; kein Zug gestartet", entry["detail"])
        self.assertFalse(Path(entry["run_dir"]).exists())
        self.assertEqual(state["schlaf"]["cx"]["grund"], "anmeldung")
        self.assertIn('"outcome": "anmeldung"', (self.world / "tickets" / "tc" / "verlauf.jsonl").read_text())
        self.assertEqual(len(self.launcher.processes), 0)

        # Mit Anmeldung baut der Traeger den Zug; der echte Lauf verweigert den Start im Trockenlauf.
        auth.parent.mkdir()
        auth.write_text(json.dumps({"tokens": {"access_token": "nicht-echt"}}))
        self.assertTrue(agents_codex.CodexAnmeldung(auth).status()["available"])
        self.ticket("td", agent="cy")
        run_id = traeger.einmal()["gestartet"][0]["run"]
        zug = self.laeufe[run_id].zug
        self.assertIsInstance(zug, agents_codex.CodexZug)
        self.assertEqual((zug.model, zug.effort, zug.cli, zug.runner), ("gpt-5.5", "high", str(cli), "agents_codex_runner.py"))
        entry = traeger._zuege_lesen()["runs"][run_id]
        self.assertEqual((entry["harness"], entry["denkstufe"]["wirksam"], entry["sperren"]), ("codex", "high", False))
        argv, env = agents_codex_runner.command(zug.as_dict(), "http://127.0.0.1:9/v1")
        self.assertEqual(argv[:2], [str(cli), "exec"])
        for needle in (["--json"], ["--model", "gpt-5.5"], ["--sandbox", "danger-full-access"],
                       ["--config", "model_reasoning_effort=high"], ["--ignore-user-config"],
                       ["-c", 'model_providers.wb-bruecke.base_url="http://127.0.0.1:9/v1"']):
            self.assertTrue(any(argv[i:i + len(needle)] == needle for i in range(len(argv))), needle)
        self.assertTrue(argv[-1].startswith("Read your turn instructions in %s" % zug.append_system_prompt_file))
        self.assertEqual((env["CODEX_HOME"], env["WB_CODEX_KEY"]), (zug.codex_home, "wb-agents-placeholder"))
        self.assertNotIn("nicht-echt", json.dumps([argv, env, zug.as_dict()]))
        turn = self.root / "codex-turn.json"
        turn.write_text(json.dumps(zug.as_dict()))
        if not os.path.exists(agents_codex_runner.MODEL_SOCKET):
            refused = subprocess.run([sys.executable, str(SHELL / "agents_codex_runner.py"), str(turn)],
                                     text=True, capture_output=True, timeout=30)
            self.assertEqual(refused.returncode, 70)
            self.assertIn("nur innerhalb des LinuxLaunchers", refused.stderr)
        with self.assertRaisesRegex(at.TraegerFehler, "Trockenlauf"):
            at._claude_lauf_fabrik(traeger, agent_id="cy", run_id="x", zug=zug, workspace=self.root, agent_state=self.root)
        self.finish(run_id, "Attrappe")

    def test_team_lead_request_wakes_main_agent_whose_decision_reaches_the_team_lead(self):
        import dataclasses
        konfig = dataclasses.replace(self.konfig, modelle={"opus55:xhigh": MODEL})
        traeger = self.make(konfig)
        self.traeger = traeger
        ad.create_agent(self.world, "tl", "teamleiter", "bau", "Leitet", None, None, MODEL, None, None, None,
                        "host2", "haupt", "hauptagent")
        draft = {"id": "helfer", "specialty": "Hilft beim Bauen", "model": "sonnet5:high", "tools": ["Read"]}
        ad.request_agent(self.world, draft, "tl", "teamleiter", "antrag-1")
        started = traeger.einmal()["gestartet"]
        self.assertEqual([(item["agent"], item["art"]) for item in started], [("haupt", "antrag")])
        run_id = started[0]["run"]
        prompt = self.laeufe[run_id].zug.prompt
        self.assertIn("agent.decide", prompt)
        self.assertIn('"request_id": "antrag-1"', prompt)
        self.assertIn("## Agenten anlegen", Path(self.laeufe[run_id].zug.append_system_prompt_file).read_text())
        ad.decide_agent_request(self.world, "antrag-1", True, "passt", "haupt", "hauptagent")
        self.finish(run_id)
        summary = traeger.einmal()
        self.assertEqual([(item["agent"], item["outcome"]) for item in summary["beendet"]], [("haupt", "erfolg")])
        self.assertEqual([(item["agent"], item["art"]) for item in summary["gestartet"]], [("tl", "rueckmeldung")])
        self.assertEqual(ad.read_agent(self.world, "helfer")["team"], "bau")
        self.traeger = traeger
        self.finish(summary["gestartet"][0]["run"])
        read = traeger.einmal()
        self.assertEqual([item["outcome"] for item in read["beendet"]], ["erfolg"])
        self.assertEqual(read["gestartet"], [])
        ad.request_agent(self.world, dict(draft, id="spaet"), "tl", "teamleiter", "antrag-2")
        ad.decide_agent_request(self.world, "antrag-2", False, "nicht noetig", "mensch", None)
        late = traeger.einmal()
        self.assertEqual([item for item in late["gestartet"] if item["agent"] == "haupt"], [])

    def test_einrichten_writes_host_defaults_and_status_names_active_sources(self):
        home = self.root / "home"
        versioned = home / ".local/share/mise/installs/claude/2.1.241/claude"
        versioned.parent.mkdir(parents=True)
        versioned.write_text("#!/bin/sh\n")
        versioned.chmod(0o755)
        (home / ".local/share/mise/installs/claude/latest").symlink_to("2.1.241")
        path = at.einrichten(self.world, self.root / "zustand", self.root / "agentenbereich", home=home,
                             which=lambda name: "/usr/bin/" + name)
        data = json.loads(path.read_text())
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(data["claude_binary"], os.path.realpath(versioned))
        self.assertEqual(data["anmeldung"], {
            "kind": "setup-token", "path": str(home / ".config/werkbank-agents/claude-setup-token"),
            "rueckfall": {"kind": "claude-login-readonly", "path": str(home / ".claude/.credentials.json"),
                          "min_valid_seconds": 900}})
        self.assertEqual(data["kontingent"], {"limits": str(home / ".claude/workbench/limits-latest.json"),
                                              "max_alter_s": 3600})
        self.assertEqual((data["maschine"], data["traeger_modul"], data["backend"]),
                         ("lokal", os.path.realpath(at.__file__), {"kind": "anthropic"}))
        self.assertEqual(data["systemd"], {"systemd_run": "/usr/bin/systemd-run", "systemctl": "/usr/bin/systemctl"})
        self.assertEqual(data["modelle"]["opus55:xhigh"], "claude-opus-5-5")
        bib = BIBLIOTHEK / "skills"  # Kit: no library shipped, then einrichten records none
        self.assertEqual((data["skill_bibliothek"], data["registry"]), (str(bib) if bib.is_dir() else None, None))
        with self.assertRaises(at.TraegerFehler):
            at.einrichten(self.world, self.root / "zustand", self.root / "agentenbereich", home=home)
        self.assertEqual(json.loads(path.read_text()), data)
        at.einrichten(self.world, self.root / "zustand", self.root / "agentenbereich", home=home, ersetzen=True,
                      claude=sys.executable)
        self.assertEqual(json.loads(path.read_text())["claude_binary"], sys.executable)

        konfig = at.TraegerKonfig.laden(path)
        traeger = at.WeltTraeger(konfig, observer_fabrik=lambda _t: self.launcher, zeitgeber=self.timer_calls.append)
        status = traeger.status()
        self.assertEqual((status["anmeldung"]["aktiv"], status["anmeldung"]["rueckfall"],
                          status["anmeldung"]["available"]), ("claude-login-readonly", True, False))
        self.assertEqual((status["kontingentquelle"]["art"], status["kontingentquelle"]["grund"]),
                         ("backend", "limits_fehlen"))
        token = home / ".config/werkbank-agents/claude-setup-token"
        token.parent.mkdir(parents=True, mode=0o700)
        token.write_text("sk-ant-oat01-" + "T" * 40)
        token.chmod(0o600)
        limits = home / ".claude/workbench/limits-latest.json"
        limits.parent.mkdir(parents=True)
        limits.write_text(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "five_hour_pct": 5}))
        status = traeger.status()
        self.assertEqual((status["anmeldung"]["aktiv"], status["anmeldung"]["available"]), ("setup-token", True))
        self.assertEqual(status["kontingentquelle"]["art"], "limits-latest")
        self.assertNotIn("T" * 40, json.dumps(status))
        self.assertEqual(self.make().status()["kontingentquelle"], {"art": "backend", "werkzeuge": []})
        with self.assertRaises(at.TraegerFehler):
            at.TraegerKonfig(self.world, self.root / "s", self.root / "a", "/c", "host2",
                             {"kind": "claude-login-readonly", "path": "/x", "rueckfall": {"kind": "setup-token"}})
        with self.assertRaises(at.TraegerFehler):
            at.TraegerKonfig(self.world, self.root / "s", self.root / "a", "/c", "host2",
                             {"kind": "setup-token", "path": "/x"}, kontingent={"limits": "/l", "fremd": 1})

    def test_konfig_rejects_overlapping_controller_and_agent_paths(self):
        with self.assertRaises(at.TraegerFehler):
            at.TraegerKonfig(self.world, self.root / "agents" / "state", self.root / "agents", "/c", "host2",
                             {"kind": "setup-token", "path": "/x"})
        with self.assertRaises(at.TraegerFehler):
            at.TraegerKonfig(self.root / "agents" / "world", self.root / "state", self.root / "agents", "/c",
                             "host2", {"kind": "setup-token", "path": "/x"})
        path = self.root / "konfig.json"
        path.write_text(json.dumps(self.konfig.as_dict()))
        self.assertEqual(at.TraegerKonfig.laden(path), self.konfig)
        self.assertTrue(at.traeger_unit(self.konfig).startswith("wb-agents-traeger-"))

    def test_project_of_the_world_is_readable_and_its_work_folder_writable(self):
        # der Nutzer, 15.09.2026: jeder Agent sieht das Projekt seiner Welt; geschrieben wird in `work/`.
        projekt = self.root / "projekt"
        world = projekt / ".werkbank" / "agents"
        (projekt / ".werkbank").mkdir(parents=True)
        (projekt / "COMPLIANCE.md").write_text("Regeln\n")
        ad.create_world(world, name="Projektwelt", main_name="haupt", sender="cli-operator")
        ad.create_agent(world, "a1", "mitglied", None, "Probe", None, None, MODEL, None, None, None,
                        "host2", "haupt", "hauptagent")
        konfig = at.TraegerKonfig(world, self.root / "state-p", self.root / "agents-p", "/opt/claude/claude",
                                  "host2", {"kind": "setup-token", "path": "/nonexistent"})
        traeger = self.make(konfig)
        ad.create_ticket(world, "Titel p1", "Ziel", "fertig", ["a1"], "haupt", "hauptagent", ticket_id="p1", kind="auftrag")
        run_id = traeger.einmal()["gestartet"][0]["run"]
        lauf = self.laeufe[run_id]
        arbeit = projekt / "work"
        self.assertTrue(arbeit.is_dir())
        self.assertEqual(arbeit.stat().st_mode & 0o777, 0o700)
        self.assertIn(projekt.resolve(), lauf.read_paths)
        self.assertEqual(lauf.write_paths, (arbeit.resolve(),))
        anweisung = Path(lauf.zug.append_system_prompt_file).read_text()
        self.assertIn("## Projekt", anweisung)
        self.assertIn("`%s`" % projekt.resolve(), anweisung)
        self.assertIn("`%s`" % arbeit.resolve(), anweisung)
        self.assertEqual(os.path.realpath(dict(lauf.zug.extra_env)["WB_WELT_PROJEKT"]), str(projekt.resolve()))
        # Ohne git-Projekt kein Worktree (16.09.2026): Arbeitsverzeichnis bleibt der private Arbeitsordner.
        entry = traeger._zuege_lesen()["runs"][run_id]
        self.assertEqual((entry["worktree"], entry["worktree_fehler"], lauf.git_einbindung),
                         (None, None, None))
        self.assertEqual(lauf.workspace, konfig.agents_dir / "a1" / "work")
        self.assertNotIn("Worktree", anweisung)
        self.assertNotIn("GIT_CONFIG_COUNT", json.dumps(json.loads(Path(lauf.zug.settings_file).read_text())))
        # Eine Welt ausserhalb eines Projekts (wie self.world) bindet nichts davon ein.
        self.ticket("p0")
        plain = self.laeufe[self.traeger.einmal()["gestartet"][0]["run"]]
        self.assertEqual(plain.write_paths, ())
        self.assertNotIn("## Projekt", Path(plain.zug.append_system_prompt_file).read_text())

    @staticmethod
    def git(cwd, *args):
        return subprocess.run(["git", "-c", "user.name=mensch", "-c", "user.email=mensch@example.invalid",
                               "-c", "init.defaultBranch=main", "-c", "core.hooksPath=/dev/null", *args],
                              cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()

    def git_welt(self, name, zweig="main"):
        projekt = self.root / name
        projekt.mkdir()
        self.git(projekt, "init", "-q", "-b", zweig)
        # Kit: the carrier takes the human's git identity from the project (agents_worktree.identitaet);
        # the upstream suite relied on the build machine's global git config for it.
        self.git(projekt, "config", "user.name", "mensch")
        self.git(projekt, "config", "user.email", "mensch@example.invalid")
        (projekt / "README.md").write_text("Projekt\n")
        self.git(projekt, "add", "README.md")
        self.git(projekt, "commit", "-qm", "init")
        world = projekt / ".werkbank" / "agents"
        (projekt / ".werkbank").mkdir()
        ad.create_world(world, name="Gitwelt", main_name="haupt", sender="cli-operator")
        ad.create_agent(world, "a1", "mitglied", None, "Probe", None, None, MODEL, None, None, None,
                        "host2", "haupt", "hauptagent")
        konfig = at.TraegerKonfig(world, self.root / ("state-" + name), self.root / ("agents-" + name),
                                  "/opt/claude/claude", "host2", {"kind": "setup-token", "path": "/nonexistent"})
        self.world, self.traeger = world, self.make(konfig)
        return projekt, konfig

    def test_git_project_turn_works_in_own_worktree_on_agent_branch_and_reuses_it(self):
        # der Nutzer, 16.09.2026: Agenten schreiben ins Projekt, aber in einem eigenen Worktree auf agent/<id>.
        projekt, konfig = self.git_welt("gitprojekt")
        haupt_vorher = self.git(projekt, "rev-parse", "main")
        status_vorher = self.git(projekt, "status", "--porcelain")
        self.ticket("g1")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        lauf, entry = self.laeufe[run_id], self.traeger._zuege_lesen()["runs"][run_id]
        privat = (konfig.agents_dir / "a1" / "work").resolve()
        baum = privat / "a1"
        gitdir = projekt.resolve() / ".git"
        self.assertEqual(self.git(baum, "branch", "--show-current"), "agent/a1")
        self.assertEqual((lauf.workspace, entry["workspace"], entry["worktree"], entry["worktree_fehler"]),
                         (baum, str(baum), str(baum), None))
        self.assertEqual(lauf.write_paths, (projekt.resolve() / "work", konfig.agents_dir / "a1" / "work"))
        self.assertIn(projekt.resolve(), lauf.read_paths)
        einbindung = lauf.git_einbindung
        admin = Path(einbindung["schreiben"][1])
        self.assertEqual((einbindung["gitdir"], admin.parent), (str(gitdir), gitdir / "worktrees"))
        self.assertEqual(einbindung["schreiben"], [str(gitdir / "objects"), str(admin),
                                                   str(gitdir / "refs/heads/agent"),
                                                   str(gitdir / "logs/refs/heads/agent")])
        self.assertLessEqual({str(gitdir / name) for name in ("config", "HEAD", "refs", "logs", "worktrees", "info",
                                                              "objects/pack", "objects/info")},
                             set(einbindung["lesen"]))
        self.assertFalse({str(gitdir / name) for name in ("index", "hooks", "description")} & set(einbindung["lesen"]))
        env = dict(lauf.zug.extra_env)
        self.assertEqual(env["WB_AGENT_WORKTREE"], str(konfig.agents_dir / "a1" / "work"))
        git_env = json.loads(Path(lauf.zug.settings_file).read_text())["env"]
        paare = {git_env["GIT_CONFIG_KEY_%d" % i]: git_env["GIT_CONFIG_VALUE_%d" % i]
                 for i in range(int(git_env["GIT_CONFIG_COUNT"]))}
        self.assertEqual((paare["core.hooksPath"], paare["core.fsmonitor"], paare["core.editor"], paare["gc.auto"]),
                         ("/dev/null", "false", "false", "0"))
        self.assertTrue(paare["user.name"] and paare["user.email"])
        self.assertEqual((git_env["GIT_CONFIG_GLOBAL"], git_env["GIT_CONFIG_NOSYSTEM"]), ("/dev/null", "1"))
        anweisung = Path(lauf.zug.append_system_prompt_file).read_text()
        for teil in ("`%s`" % baum, "`agent/a1`", "git rebase main", "`commit`", "`%s`" % (projekt.resolve() / "work"),
                     "`%s`" % (konfig.agents_dir / "a1" / "work"), "Kein `git push`"):
            self.assertIn(teil, anweisung)
        self.assertNotIn("git merge agent/<mitglied>", anweisung)
        # Der Agent committet in seinem Worktree.
        (baum / "neu.txt").write_text("vom Agenten\n")
        self.git(baum, "add", "neu.txt")
        self.git(baum, "commit", "-qm", "agent change")
        commit = self.git(baum, "rev-parse", "HEAD")
        self.finish(run_id, "fertig")
        self.assertEqual(self.traeger.einmal()["beendet"][0]["outcome"], "erfolg")
        # Zweiter Zug: derselbe Worktree, derselbe Zweig mit dem Commit.
        self.ticket("g2")
        run2 = self.traeger.einmal()["gestartet"][0]["run"]
        entry2 = self.traeger._zuege_lesen()["runs"][run2]
        self.assertEqual((entry2["worktree"], self.laeufe[run2].workspace), (str(baum), baum))
        self.assertEqual(self.git(projekt, "rev-parse", "agent/a1"), commit)
        self.assertEqual(len([z for z in self.git(projekt, "worktree", "list", "--porcelain").splitlines()
                              if z.startswith("worktree ")]), 2)
        self.finish(run2, "fertig")
        self.traeger.einmal()
        # Hauptzweig und Arbeitsbaum des Menschen unveraendert.
        self.assertEqual(self.git(projekt, "rev-parse", "main"), haupt_vorher)
        self.assertEqual(self.git(projekt, "status", "--porcelain"), status_vorher)
        self.assertFalse((projekt / "neu.txt").exists())
        # Ein umgeschriebener Verweis im Worktree wird nicht geglaubt: der Zug laeuft ohne Worktree.
        (baum / ".git").write_text("gitdir: %s\n" % (privat / "fremd"))
        self.ticket("g3")
        run3 = self.traeger.einmal()["gestartet"][0]["run"]
        entry3, lauf3 = self.traeger._zuege_lesen()["runs"][run3], self.laeufe[run3]
        self.assertIsNone(entry3["worktree"])
        self.assertIn("zeigt nicht", entry3["worktree_fehler"])
        self.assertEqual((lauf3.workspace, lauf3.git_einbindung), (konfig.agents_dir / "a1" / "work", None))
        self.assertIn("nicht bereit", Path(lauf3.zug.append_system_prompt_file).read_text())

    def test_git_project_without_main_branch_runs_without_worktree_and_old_session_starts_fresh(self):
        projekt, konfig = self.git_welt("devprojekt", zweig="dev")
        self.ticket("d1", goal="Codewort amber-1234abcd merken")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        entry = self.traeger._zuege_lesen()["runs"][run_id]
        self.assertIn("weder main noch master", entry["worktree_fehler"])
        self.assertEqual(entry["workspace"], str(konfig.agents_dir / "a1" / "work"))
        self.outputs[self.laeufe[run_id].pid] = self.stream(entry["session_id"])
        self.traeger.agent_stoppen("a1", "Sofortstopp", absender="haupt")
        self.assertEqual(self.traeger.einmal()["beendet"][0]["outcome"], "gestoppt")
        # Der Mensch legt main an; die Sitzung hing am alten Arbeitsordner und beginnt im Worktree neu.
        self.git(projekt, "branch", "main")
        self.traeger.agent_fortsetzen("a1", absender="haupt")
        run2 = self.traeger.einmal()["gestartet"][0]["run"]
        entry2 = self.traeger._zuege_lesen()["runs"][run2]
        baum = (konfig.agents_dir / "a1" / "work").resolve() / "a1"
        self.assertEqual((entry2["worktree"], entry2["resume"]), (str(baum), False))
        self.assertNotEqual(entry2["session_id"], entry["session_id"])
        self.finish(run2, "fertig")
        self.assertEqual(self.traeger.einmal()["beendet"][0]["outcome"], "erfolg")

    def test_git_instruction_names_merge_for_team_lead_and_main_agent(self):
        self.git_welt("leitprojekt")
        ad.create_agent(self.world, "lead", "teamleiter", "entwicklung", "Leitet", None, None, MODEL, None, None,
                        None, "host2", "haupt", "hauptagent")
        haupt = self.world / "agents" / "haupt" / "agent.json"
        daten = json.loads(haupt.read_text())
        daten["model_profile"] = dict(daten.get("model_profile") or {}, model=MODEL)
        haupt.write_text(json.dumps(daten))
        for agent in ("lead", "haupt"):
            self.ticket("m-" + agent, agent=agent)
        runs = {item["agent"]: item["run"] for item in self.traeger.einmal()["gestartet"]}
        texte = {agent: Path(self.laeufe[run].zug.append_system_prompt_file).read_text() for agent, run in runs.items()}
        self.assertIn("git merge agent/<mitglied>", texte["lead"])
        self.assertIn("git merge agent/<id>", texte["haupt"])
        self.assertNotIn("git merge agent/<mitglied>", texte["haupt"])

    @unittest.skipUnless((SHELL / "wb-gmx").exists(), "kit: wb-gmx (a personal mailbox tool) is not shipped (port/strip.txt)")
    def test_web_and_mail_accesses_give_network_password_files_and_reading_wrappers(self):
        # 15.09.2026: `web` gibt nur Netz; `mail` legt Passwoerter aus dem Schluesselbund des Traegerhosts und
        # Huellen der lesenden Postfachwerkzeuge in den Zugangsordner. Gesendet wird nichts (Hausliste).
        import agents_zugaenge as az
        runtime = self.traeger.orte.runtime
        self.assertTrue((runtime / "wb-gmx").is_file(), "wb-gmx gehoert zur Laufzeit")
        az.hinzufuegen(self.world, {"name": "netz", "art": "web"}, bestaetigt=True, absender="mensch")
        az.hinzufuegen(self.world, {"name": "post", "art": "mail",
                                    "dienste": [{"werkzeug": "wb-gmx", "konto": "probe@example.net"}]}, bestaetigt=True,
                       absender="mensch")
        with self.assertRaises(az.ZugangFehler):
            az.hinzufuegen(self.world, {"name": "falsch", "art": "web", "ziel": "x@y"}, bestaetigt=True,
                           absender="mensch")
        with self.assertRaises(az.ZugangFehler):
            az.hinzufuegen(self.world, {"name": "falsch", "art": "mail",
                                        "dienste": [{"werkzeug": "wb-mail", "konto": "a@b.de"}]}, bestaetigt=True,
                           absender="mensch")
        self.assertEqual(az.oeffentlich(az.lesen(self.world)),
                         [{"name": "netz", "art": "web"}, {"name": "post", "art": "mail", "werkzeuge": ["wb-gmx"]}])
        abfragen = []

        def geheimnis(dienst, konto, runner=None):
            abfragen.append((dienst, konto))
            return "NICHT-ECHT-" + dienst

        with mock.patch.object(az, "_geheimnis", geheimnis):
            self.ticket("m1")
            run_id = self.traeger.einmal()["gestartet"][0]["run"]
        lauf, entry = self.laeufe[run_id], self.traeger._zuege_lesen()["runs"][run_id]
        ordner = self.traeger.orte.turns / run_id / "zugaenge"
        self.assertTrue(lauf.netz)
        self.assertEqual((entry["zugaenge"], entry["zugaenge_fehler"]), (["netz", "post"], None))
        self.assertEqual(abfragen, [("wb-gmx", "probe@example.net")])
        self.assertTrue((ordner / "netz").is_dir())
        self.assertEqual((ordner / "post" / "wb-gmx.pw").read_text(), "NICHT-ECHT-wb-gmx\n")
        self.assertEqual((ordner / "post" / "wb-gmx.pw").stat().st_mode & 0o777, 0o600)
        self.assertFalse((ordner / "ssh_config").exists())
        self.assertFalse((ordner / "ssh").exists())
        huelle = (ordner / "wb-gmx").read_text()
        self.assertIn("WB_MAIL_GEHEIMNISSE='%s'" % (ordner / "post"), huelle)
        self.assertIn("exec /usr/bin/python3 '%s'" % (runtime / "wb-gmx"), huelle)
        self.assertEqual((ordner / "wb-gmx").stat().st_mode & 0o777, 0o700)
        settings = json.loads(Path(lauf.zug.settings_file).read_text())
        self.assertEqual(settings["env"]["WB_ZUGAENGE"], str(ordner))
        anweisung = Path(lauf.zug.append_system_prompt_file).read_text()
        self.assertIn("- Zugang `netz` (web): Netz fuer WebFetch und WebSearch", anweisung)
        self.assertIn("- Zugang `post` (mail): Postfach nur lesen mit `wb-gmx`", anweisung)
        self.assertNotIn("probe@example.net", anweisung)
        self.assertNotIn("NICHT-ECHT", anweisung)
        self.finish(run_id, "fertig")
        self.traeger.einmal()
        self.assertFalse(ordner.exists(), "Passwortdateien verschwinden mit dem Zugende")
        # Ein Passwort, das der Schluesselbund nicht kennt, macht die Zugaenge des Zuges sichtbar unbereit.
        with mock.patch.object(az, "_geheimnis", mock.Mock(side_effect=az.ZugangFehler("kein Passwort"))):
            self.ticket("m2")
            run_id = self.traeger.einmal()["gestartet"][0]["run"]
        entry = self.traeger._zuege_lesen()["runs"][run_id]
        self.assertEqual(entry["zugaenge"], [])
        self.assertIn("kein Passwort", entry["zugaenge_fehler"])
        self.assertFalse(self.laeufe[run_id].netz)

    def test_mail_freigaben_lesepfad_und_anweisungen(self):
        # 16.09.2026: freigaben.json liegt nur lesend im Zug (Profil-Sperre); wer eine Freigabe email haelt, bekommt
        # „Mail senden“, der Hauptagent immer „Mail-Freigaben weitergeben“. Ein Passwort kommt nie in den Zug.
        import agents_freigaben as af
        self.auto.clear()
        self.ticket("ohne", agent="a2")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        lauf = self.laeufe[run_id]
        self.assertNotIn(self.world / af.DATEI, lauf.read_paths)
        self.assertNotIn("## Mail senden", Path(lauf.zug.append_system_prompt_file).read_text())
        self.finish(run_id, "fertig")
        self.traeger.einmal()
        # Mailkonto aus einer Wegwerf-Hostkonfiguration (AWB_STATE_DIR), nie aus ~/.config.
        zustand = self.root / "zustand"
        zustand.mkdir()
        (zustand / af.KONFIG_DATEI).write_text(json.dumps({"version": 1, "konten": {"beispiel": {
            "domain": "example.org", "smtp_host": "smtp.example.org", "smtp_port": 465, "smtp_modus": "ssl",
            "benutzer": "postfach@example.org", "schluesselbund": "wb-beispiel-smtp", "werkzeug": "wb-beispiel",
            "umfang_quelle": "COMPLIANCE.md, Spalte „Ohne Rückfrage“",
            "ohne_rueckfrage": ["info@example.org", "kontakt@example.org"],
            "nie": {"privat@example.org": "wird nur gelesen."},
            "rundschreiben": {"neuigkeiten@example.org": "sendet nur der Versandweg des Projekts."},
            "hinweise": ["Nachfasstakt: sieben Tage, dann einmal nachfassen."]}}}, ensure_ascii=False))
        umgebung = mock.patch.dict(os.environ, {"AWB_STATE_DIR": str(zustand)})
        umgebung.start()
        self.addCleanup(umgebung.stop)
        af.erteilen(self.world, ["haupt"], "email", "beispiel", ["info@example.org", "kontakt@example.org"],
                    bestaetigt=True, wortlaut="Test", messung=("agent", "Test"), absender="mensch")
        af.weitergeben(self.world, "haupt", "hauptagent", "a1", "email", ["kontakt@example.org"])
        haupt = self.world / "agents" / "haupt" / "agent.json"
        daten = json.loads(haupt.read_text())
        daten["model_profile"] = dict(daten.get("model_profile") or {}, model=MODEL)
        haupt.write_text(json.dumps(daten))
        self.ticket("m-a1", agent="a1")
        self.ticket("m-a2", agent="a2")
        self.ticket("m-haupt", agent="haupt")
        runs = {item["agent"]: item["run"] for item in self.traeger.einmal()["gestartet"]}
        texte = {agent: Path(self.laeufe[run].zug.append_system_prompt_file).read_text() for agent, run in runs.items()}
        for agent in ("a1", "a2", "haupt"):
            self.assertIn(self.world / af.DATEI, self.laeufe[runs[agent]].read_paths)
        self.assertIn("## Mail senden", texte["a1"])
        self.assertIn("Freigabe email (beispiel): kontakt@example.org", texte["a1"])
        self.assertIn("### Konto beispiel (@example.org)", texte["a1"])
        self.assertIn("wb-beispiel senden --von", texte["a1"])
        self.assertIn("als Frage an den Hauptagenten", texte["a1"])
        self.assertIn("Nachfasstakt", texte["a1"])
        self.assertIn("`privat@example.org` sendet nie: wird nur gelesen.", texte["a1"])
        self.assertIn("`neuigkeiten@example.org` sendet nie über `wb-beispiel senden`", texte["a1"])
        self.assertNotIn("## Mail senden", texte["a2"])
        self.assertNotIn("## Mail-Freigaben weitergeben", texte["a1"])
        self.assertIn("## Mail senden", texte["haupt"])
        self.assertIn("## Mail-Freigaben weitergeben", texte["haupt"])
        self.assertIn("freigabe.weitergeben < freigabe.json", texte["haupt"])
        self.assertIn("mit `question.ask` als Frage", texte["haupt"])
        self.assertIn('"adressen": ["info@example.org"]', texte["haupt"])
        self.assertIn("`privat@example.org`, `neuigkeiten@example.org` gibt es nicht", texte["haupt"])
        # Ohne Hostkonfiguration sagt die Anweisung, dass ueber das Konto nichts gesendet wird.
        (zustand / af.KONFIG_DATEI).unlink()
        self.finish(runs["a1"], "fertig")
        self.traeger.einmal()
        self.ticket("m-a1-ohne", agent="a1")
        run_id = next(item["run"] for item in self.traeger.einmal()["gestartet"] if item["agent"] == "a1")
        text = Path(self.laeufe[run_id].zug.append_system_prompt_file).read_text()
        self.assertIn("Konto beispiel: Mailkonto beispiel ist auf diesem Host nicht eingerichtet", text)
        self.assertNotIn("wb-beispiel senden --von", text)

    # Grenzen, Zyklus, WIP und Messart im Durchgang (tickets3) -----------------------------------
    def test_expired_frist_raises_braucht_dich_and_extended_limits_restart_the_ticket(self):
        self.traeger.konfig and None  # Konfig bleibt unberuehrt
        ad.create_ticket(self.world, "Mit alter Frist", "Z", "fertig", ["a1"], "haupt", "hauptagent",
                         limits={"frist": "2020-01-01T00:00:00Z", "runden": 9}, ticket_id="t-alt",
                         kind="auftrag")
        summary = self.traeger.einmal()
        self.assertEqual(summary["gestartet"], [])
        self.assertEqual(summary["grenzen"], ["t-alt"])
        self.assertEqual(ad.read_ticket(self.world, "t-alt")["state"], "braucht dich")
        self.assertIn("uebergangen", summary)
        self.assertIn("wartet auf Antwort", json.dumps(summary["uebergangen"]))
        # Der Hauptagent verlaengert die Frist; das Ticket kehrt zurueck und wird zugestellt.
        ad.set_ticket_limits(self.world, "t-alt", frist="2099-01-01T00:00:00Z", sender="haupt",
                             claimed_role="hauptagent")
        summary = self.traeger.einmal()
        started = [item for item in summary["gestartet"] if item["ticket"] == "t-alt"]
        self.assertEqual(len(started), 1)
        self.finish(started[0]["run"], "Frist gerecht")
        self.assertEqual(ad.read_ticket(self.world, "t-alt")["state"], "zur Abnahme")

    def test_round_limit_counts_zug_events_and_blocks_the_next_turn(self):
        ad.create_ticket(self.world, "Kurz", "Z", "fertig", ["a1"], "haupt", "hauptagent",
                         limits={"runden": 1}, ticket_id="t-kurz", kind="auftrag")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        self.finish(run_id, None)  # der Zug endet ohne Ergebnis; ein Zug-Ereignis steht
        summary = self.traeger.einmal()
        self.assertEqual(summary["grenzen"], ["t-kurz"])
        ticket = ad.read_ticket(self.world, "t-kurz")
        self.assertEqual((ticket["state"], ticket["flag"]["vorher"]), ("braucht dich", "läuft"))
        self.assertIn("Rundenzahl 1 erreicht", ticket["flag"]["reason"])
        # Kein automatischer Zug danach: die Recovery wird uebergangen und quittiert.
        self.traeger.einmal()
        self.assertEqual([item for item in self.traeger.einmal()["gestartet"] if item["ticket"] == "t-kurz"], [])
        ad.set_ticket_limits(self.world, "t-kurz", runden=5, sender="haupt", claimed_role="hauptagent")
        self.assertEqual(ad.read_ticket(self.world, "t-kurz")["state"], "läuft")

    def test_cycle_closure_runs_in_the_pass_and_delivers_the_retro_post(self):
        ad.update_agent_profile(self.world, "haupt", {"model": MODEL}, "mensch")
        ad.set_cycle(self.world, True, tage=1, ziel="Bauen", sender="mensch")
        self.ticket("t-uebrig")
        world_file = self.world / "world.json"
        world = json.loads(world_file.read_text(encoding="utf-8"))
        world["cycles"]["current"]["end"] = "2020-01-01T00:00:00Z"
        world_file.write_text(json.dumps(world), encoding="utf-8")
        summary = self.traeger.einmal()
        self.assertEqual(summary["zyklus"]["uebertragen"], ["t-uebrig"])
        eintrag = json.loads((self.world / "zyklen.jsonl").read_text().splitlines()[-1])
        self.assertEqual((eintrag["id"], eintrag["carried_over"]), ("zyklus-1", 1))
        # Der Hauptagent bekommt den Retro-Posten im selben Durchgang; sein Zug endet ohne Antwortpflicht.
        started = [item for item in summary["gestartet"] if item["agent"] == "haupt"]
        self.assertEqual([item["art"] for item in started], ["zyklus-schluss"])
        self.assertIn("Retro", self.laeufe[started[0]["run"]].zug.prompt)
        self.finish(started[0]["run"])
        done = next(item for item in self.traeger.einmal()["beendet"] if item["art"] == "zyklus-schluss")
        # Ohne Antwortpflicht genuegt der abgeschlossene Zug als Erfolg; der Retro-Posten wird quittiert.
        self.assertEqual(done["outcome"], "erfolg")
        self.assertTrue(self.postfach("haupt", ad.derived_id("zyklus-schluss", "zyklus-1"))["acknowledged"])

    def test_world_without_cycle_and_a_ticket_older_than_limits_stays_untouched(self):
        self.ticket("t-ohne")
        summary = self.traeger.einmal()
        self.assertIsNone(summary["zyklus"])
        self.assertFalse((self.world / "zyklen.jsonl").exists())
        self.assertEqual([item["ticket"] for item in summary["gestartet"]], ["t-ohne"])

    def test_carrier_skips_tickets_that_fail_the_definition_of_ready(self):
        ad.create_ticket(self.world, "Story ohne Liste", "Z", "fertig", ["a1"], "haupt", "hauptagent",
                         ticket_id="t-story", kind="story")
        summary = self.traeger.einmal()
        self.assertEqual(summary["gestartet"], [])
        skipped = [item for item in summary["uebergangen"] if item.get("ticket") == "t-story"]
        self.assertEqual([item["grund"] for item in skipped], ["fehlende Fertig-Liste"])
        self.assertFalse(self.postfach("a1", ad.derived_id("ticket", "t-story"))["acknowledged"])

    def test_carrier_respects_the_wip_limit_of_the_world(self):
        ad.set_wip_limit(self.world, 1, sender="mensch")
        self.ticket("t-ersten")
        self.ticket("t-zweiten", agent="a2")
        first = self.traeger.einmal()["gestartet"]
        self.assertEqual([item["ticket"] for item in first], ["t-ersten"])
        # t-ersten laeuft: die weiche Grenze der Welt (1) ist erreicht, t-zweiten wird uebergangen.
        summary = self.traeger.einmal()
        skipped = [item for item in summary["uebergangen"] if item.get("ticket") == "t-zweiten"]
        self.assertEqual([item["grund"] for item in skipped], ["wip-grenze (1 von 1 laufen)"])
        # Weich: der Mensch weist trotzdem zu.
        ad.claim_ticket(self.world, "t-zweiten", "a2", "a2", "mitglied")
        self.assertEqual(ad.read_ticket(self.world, "t-zweiten")["state"], "läuft")

    def test_measurement_carries_the_ticket_kind(self):
        ad.create_ticket(self.world, "Recherche", "Z", "fertig", ["a1"], "haupt", "hauptagent",
                         ticket_id="t-recherche", kind="recherche")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        self.finish(run_id, "Belegt", stream=self.skill_stream())
        self.traeger.einmal()
        lines = (self.world / "agents" / "a1" / "messungen.jsonl").read_text().splitlines()
        self.assertEqual([json.loads(line)["ticketart"] for line in lines], ["recherche"])
        self.assertEqual(self.traeger.status()["messungen"]["a1"]["arten"]["recherche"]["anzahl"], 1)


class TicketHinweiseTests(TraegerTest):
    """Prompt-Anreicherung und Ticketposten des Traegers (Plan AGENTS-TICKETS-PLAN, Saetze 8 bis 14, 19)."""

    def prompt(self, ticket_id, agent="a1", posten_art="ticket", resume=False):
        world = ad.read_world(self.world)
        agent_obj = ad.read_agent(self.world, agent)
        ticket = ad.read_ticket(self.world, ticket_id)
        posten = at.Posten(at.Delivery("p-" + ticket_id, self.traeger.world_id(), agent, "ticket", 0.0,
                                 at._inhalt("ticket", ticket_id=ticket_id)), posten_art, ticket_id=ticket_id)
        return self.traeger._prompt(world, agent_obj, posten, resume, ticket, None, None)

    def nachricht(self, text, sender="haupt", agent="a1", ticket_id="t-a", message_id=None):
        ad.send_message(self.world, sender, [agent], text, ticket_id, message_id,
                        "hauptagent" if sender == "haupt" else None)

    def erster_lauf(self, ticket_id):
        entry = next(entry for entry in self.traeger._zuege_lesen()["runs"].values()
                     if entry.get("ticket_id") == ticket_id)
        return entry["run_id"]

    def durchgaenge_bis(self, bedingung, versuche=40):
        summary = {}
        for _ in range(versuche):
            summary = self.traeger.einmal()
            if bedingung(summary):
                return summary
            time.sleep(0.05)
        return summary

    def zug_endet(self, ticket_id):
        def hat_zug(summary):
            verlauf = (self.world / "tickets" / ticket_id / "verlauf.jsonl")
            if not verlauf.exists():
                return False
            return any(json.loads(line).get("event") == "zug" for line in verlauf.read_text().splitlines())
        return self.durchgaenge_bis(hat_zug)

    def test_returned_ticket_prompt_carries_remark_and_sender(self):
        self.ticket("t-a", goal="Alles bauen")
        self.traeger.einmal()
        self.finish(self.erster_lauf("t-a"), "Ergebnis A")
        self.traeger.einmal()
        ad.approve_ticket(self.world, "t-a", "haupt", "hauptagent", "Der Test fehlt noch", accept=False)
        self.nachricht("Bitte die Rueckgabe beachten", message_id="m-rueckgabe")
        prompt = self.prompt("t-a")
        self.assertIn("Returned by haupt: Der Test fehlt noch", prompt)
        self.assertIn("From haupt at", prompt)
        self.assertIn("Bitte die Rueckgabe beachten", prompt)
        self.assertNotIn("ältere Nachrichten ausgelassen", prompt)

    def test_prompt_limits_dependencies_and_channel_since_last_turn(self):
        self.ticket("t-basis", agent="a2")
        self.traeger.einmal()
        self.finish(self.erster_lauf("t-basis"), "Basis fertig")
        self.traeger.einmal()
        ad.approve_ticket(self.world, "t-basis", "haupt", "hauptagent", "passt")
        ad.create_ticket(self.world, "Mit Grenzen", "Bauen", "fertig", ["a1"], "haupt", "hauptagent",
                         limits={"frist": "2026-10-01", "runden": 5, "daten": "maschine", "eigene": "wert"},
                         dependencies=["t-basis"], ticket_id="t-a", kind="auftrag")
        self.traeger.einmal()
        self.nachricht("alte Nachricht vor dem letzten Zug", message_id="m-alt")
        time.sleep(1.2)
        self.finish(self.erster_lauf("t-a"), None)
        self.zug_endet("t-a")
        self.nachricht("neue Nachricht nach dem letzten Zug", message_id="m-neu")
        prompt = self.prompt("t-a", resume=True)
        self.assertIn("Depends on t-basis (abgenommen)", prompt)
        self.assertIn("Limit Frist: 2026-10-01", prompt)
        self.assertIn("Limit Rundenzahl: höchstens 5", prompt)
        self.assertIn("Daten bleiben auf der Maschine", prompt)
        self.assertIn("Limit eigene: wert", prompt)
        self.assertIn("neue Nachricht nach dem letzten Zug", prompt)
        self.assertNotIn("alte Nachricht vor dem letzten Zug", prompt)

    def test_prompt_shortens_oldest_messages_at_6000_characters(self):
        self.ticket("t-a")
        self.traeger.einmal()
        self.finish(self.erster_lauf("t-a"), None)
        self.zug_endet("t-a")
        for index in range(30):
            self.nachricht("Nachricht %d %s" % (index, "x" * 400), message_id="m-%d" % index)
        prompt = self.prompt("t-a")
        self.assertIn("ältere Nachrichten ausgelassen", prompt)
        hint = prompt.split(" ältere Nachrichten ausgelassen")[0].rsplit("(", 1)[-1].strip()
        self.assertTrue(hint.isdigit() and int(hint) > 0)
        hinweise = prompt.split("Done when: fertig\n", 1)[1].split("When the goal is met")[0]
        self.assertLessEqual(len(hinweise), 6000)
        self.assertIn("Nachricht 29", prompt)
        self.assertNotIn("Nachricht 0 ", prompt)

    def test_prompt_shows_done_list_dod_last_note_and_older_count(self):
        # tickets2: Fertig-Liste mit Haken, Definition of Done dieser Welt, letzter Zwischenstand mit Zaehler.
        ad.set_definition_of_done(self.world, ["Doku aktualisiert", "Tests gruen"], sender="mensch")
        ad.create_ticket(self.world, "Mit Liste", "Ziel", "fertig", ["a1"], "haupt", "hauptagent",
                         ticket_id="t-a", done_items=["Erster Punkt", "Zweiter Punkt"])
        self.traeger.einmal()
        ad.note_ticket(self.world, "t-a", "a1", "Erster Zug endet mit Bericht", sender="a1",
                       claimed_role="mitglied")
        self.finish(self.erster_lauf("t-a"), None)
        self.zug_endet("t-a")
        ad.claim_ticket(self.world, "t-a", "a1", "a1", "mitglied")
        ad.note_ticket(self.world, "t-a", "a1", "Erster Zwischenstand", sender="a1", claimed_role="mitglied")
        ad.note_ticket(self.world, "t-a", "a1", "Zweiter Zwischenstand", sender="a1", claimed_role="mitglied")
        ad.check_done_item(self.world, "t-a", "a1", 1, sender="a1", claimed_role="mitglied")
        prompt = self.prompt("t-a")
        self.assertIn("Definition of Done dieser Welt (the approver checks it at the end):", prompt)
        self.assertIn("- Doku aktualisiert", prompt)
        self.assertIn("[x] Erster Punkt", prompt)
        self.assertIn("[ ] Zweiter Punkt", prompt)
        self.assertIn("Last progress note:\nZweiter Zwischenstand", prompt)
        self.assertIn("(2 ältere Zwischenstände im Verlauf)", prompt)

    def test_carrier_skips_not_ready_ticket_and_logs_it(self):
        self.ticket("t-a", agent="a1")
        self.ticket("t-b", agent="a2", dependencies=["t-a"])
        summary = self.traeger.einmal()
        self.assertEqual([item["ticket"] for item in summary["gestartet"]], ["t-a"])
        self.assertEqual([item["ticket"] for item in summary["uebergangen"]], ["t-b"])
        self.assertIn(summary["uebergangen"][0]["grund"], ("abhaengigkeit t-a ist offen", "abhaengigkeit t-a ist läuft"))
        delivery = json.loads((self.world / "agents" / "a2" / "postfach" /
                               (ad.derived_id("ticket", "t-b") + ".json")).read_text())
        self.assertFalse(delivery["acknowledged"])
        self.finish(self.erster_lauf("t-a"), "Ergebnis A")
        self.traeger.einmal()
        ad.approve_ticket(self.world, "t-a", "haupt", "hauptagent", "passt")
        summary = self.traeger.einmal()
        self.assertEqual([item["ticket"] for item in summary["gestartet"]], ["t-b"])

    def test_carrier_orders_ticket_items_by_ready_order(self):
        self.ticket("t-niedrig", agent="a1")
        ad.create_ticket(self.world, "Hoch", "Z", "fertig", [], "haupt", "hauptagent", ticket_id="t-hoch")
        ad.triage_accept(self.world, "t-hoch", ["a1"], priority=0, kind="recherche",
                         sender="haupt", claimed_role="hauptagent")
        posten = [item for item in self.traeger._posten(self.traeger.world_id(), "a1") if item.art == "ticket"]
        self.assertEqual([item.ticket_id for item in posten], ["t-hoch", "t-niedrig"])

    def test_carrier_pass_wakes_parked_tickets(self):
        self.ticket("t-a", agent="a1")
        self.traeger.einmal()
        self.finish(self.erster_lauf("t-a"), None)
        self.traeger.einmal()
        ad.claim_ticket(self.world, "t-a", "a1", "a1", "mitglied")
        ad.park_ticket(self.world, "t-a", "a1", "bis spaeter", until="2026-09-18T10:00:00Z",
                       sender="a1", claimed_role="mitglied")
        self.offset = ad._epoch_of("2026-09-18T10:00:00Z") - time.time() + 60
        summary = self.traeger.einmal()
        self.assertEqual(summary["geweckt"], ["t-a"])
        self.assertTrue((self.world / "agents" / "a1" / "postfach" /
                         (ad.derived_id("ticket-wake", "t-a", 1) + ".json")).exists())
        self.assertIn(ad.read_ticket(self.world, "t-a")["state"], ("offen", "läuft"))


class PruefzugHelfer:
    """Gemeinsame Helfer fuer Pruefzug- und Ende-zu-Ende-Proben (tickets2)."""

    def reif_mit_commit(self, ticket_id="t-a"):
        """Bringt das Ticket per Ergebnis und echtem Commit im Worktree von a1 nach `zur Abnahme`."""
        ad.create_ticket(self.world, "Titel " + ticket_id, "Ziel", "fertig", ["a1"], "haupt", "hauptagent",
                         ticket_id=ticket_id, kind="auftrag")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        lauf = self.laeufe[run_id]
        (lauf.workspace / "arbeit.txt").write_text("vom Agenten\n")
        self.git(lauf.workspace, "add", "arbeit.txt")
        self.git(lauf.workspace, "commit", "-qm", "arbeit")
        commit = self.git(lauf.workspace, "rev-parse", "HEAD")
        ad.write_result(self.world, ticket_id, "a1", "fertig mit Commit", commit, "a1", "mitglied")
        self.finish(run_id, None)
        self.traeger.einmal()
        self.haupt_befreien()
        return commit

    def haupt_befreien(self, runden=3):
        """Beendet die Hinweis-Zuege des Hauptagenten (Ergebnis- und Pruefnotiz-Meldungen verlangen keine Antwort)."""
        for _ in range(runden):
            self.traeger.einmal()
            offen = [rid for rid, entry in self.traeger._zuege_lesen()["runs"].items()
                     if entry.get("agent") == "haupt" and entry.get("outcome") is None]
            if not offen:
                return
            for rid in offen:
                self.finish(rid)

    def finish_review(self, run_id, text, verdict):
        lauf = self.laeufe[run_id]
        entry = self.traeger._zuege_lesen()["runs"][run_id]
        ad.review_result(self.world, entry["ticket_id"], lauf.agent_id, text, verdict,
                         lauf.agent_id, "mitglied")
        self.outputs[lauf.pid] = self.stream(lauf.zug.session_id)
        lauf.release.write_text("go")
        self.launcher.processes[lauf.pid].wait(timeout=5)

    def git_welt_mit_pruefer(self, name):
        projekt, konfig = self.git_welt(name)
        ad.create_agent(self.world, "a2", "mitglied", None, "Pruefer", None, None, MODEL, None, None, None,
                        "host2", "haupt", "hauptagent")
        # Der Hauptagent der Welt loest sein Profilmodell auf und kann die Prüfnotiz lesen.
        import dataclasses
        self.traeger = self.make(dataclasses.replace(konfig, modelle={"opus55:xhigh": MODEL}))
        return projekt, konfig


class PruefzugTests(PruefzugHelfer, TraegerTest):
    """Der Pruefzug (tickets2, Plan Saetze 25 und 26): Zustellung, Prompt, Rechte, Pruefnotiz."""

    def test_review_request_starts_a_restricted_review_turn_in_the_assignee_worktree(self):
        projekt, konfig = self.git_welt_mit_pruefer("pruefprojekt")
        ad.set_definition_of_done(self.world, ["Doku aktualisiert"], sender="mensch")
        commit = self.reif_mit_commit()
        baum_a1 = (konfig.agents_dir / "a1" / "work").resolve() / "a1"
        ad.review_ticket(self.world, "t-a", "a2", sender="haupt", claimed_role="hauptagent")
        summary = self.traeger.einmal()
        started = [item for item in summary["gestartet"] if item["agent"] == "a2"]
        self.assertEqual([item["art"] for item in started], ["pruefung"])
        run_id = started[0]["run"]
        lauf, entry = self.laeufe[run_id], self.traeger._zuege_lesen()["runs"][run_id]
        self.assertEqual((entry["art"], entry["session_key"]), ("pruefung", "pruefung:t-a:1"))
        # Der Pruefzug bleibt im privaten Arbeitsordner des Pruefers; GIT_DIR zeigt auf die Revision.
        self.assertEqual(entry["workspace"], str(konfig.agents_dir / "a2" / "work"))
        self.assertEqual(entry["worktree"], str(baum_a1))
        settings_env = json.loads(Path(lauf.zug.settings_file).read_text())["env"]
        self.assertEqual(settings_env["GIT_DIR"],
                         str(aw.verwaltung(projekt.resolve() / ".git", baum_a1)))
        # Ohne Schreibwerkzeuge: die Werkzeugliste des Zuges bietet Write/Edit/Web nie an.
        self.assertEqual(tuple(lauf.zug.tools), at.PRUEF_WERKZEUGE)
        self.assertNotIn("Write", lauf.zug.tools)
        # Die git-Verwaltung des geprüften Worktrees ist nur lesend eingebunden: kein commit moeglich.
        self.assertEqual((lauf.git_einbindung["gitdir"], lauf.git_einbindung["schreiben"]),
                         (str(projekt.resolve() / ".git"), []))
        env = dict(lauf.zug.extra_env)
        self.assertNotIn("WB_ZUGAENGE", env)
        prompt = lauf.zug.prompt
        self.assertIn("git show %s" % commit, prompt)
        self.assertIn("Result under review (revision 1):", prompt)
        self.assertIn("fertig mit Commit", prompt)
        self.assertIn("Definition of Done dieser Welt", prompt)
        self.assertIn("ticket.review_result", prompt)
        self.assertIn('"verdict": "VERDICT"', prompt)
        self.assertIn(str(baum_a1), prompt)
        settings = json.loads(Path(lauf.zug.settings_file).read_text())
        hooks = [(item["matcher"], hook["command"]) for item in settings["hooks"]["PreToolUse"]
                 for hook in item["hooks"]]
        self.assertTrue(any("profil-sperre.sh" in command for _matcher, command in hooks))
        self.finish_review(run_id, "Diff passt zur Analyse", "bestanden")
        done = self.traeger.einmal()["beendet"][0]
        self.assertEqual((done["run"], done["outcome"], done["art"]), (run_id, "erfolg", "pruefung"))
        ticket = ad.read_ticket(self.world, "t-a")
        self.assertEqual((ticket["state"], ticket["review"]["verdict"]), ("zur Abnahme", "bestanden"))
        self.assertTrue(self.postfach("a2", ad.derived_id("ticket-review", "t-a", 1))["acknowledged"])
        # Der Abnehmende sieht die Notiz: Kennung `ticket-reviewed-…`, gelesen als rueckmeldung-Zug.
        reviewed = json.loads((self.world / "agents" / "haupt" / "postfach" /
                               (ad.derived_id("ticket-reviewed", "t-a", 1) + ".json")).read_text())
        self.assertEqual((reviewed["kind"], reviewed["sender"], reviewed["ticket"], reviewed["subject"]),
                         ("kanal", "a2", "t-a", "Antwort"))
        self.assertIn("Diff passt zur Analyse", reviewed["text"])
        self.haupt_befreien()
        notiz = [entry for entry in self.traeger._zuege_lesen()["runs"].values()
                 if entry.get("agent") == "haupt"
                 and entry.get("nachricht_id") == ad.derived_id("ticket-reviewed", "t-a", 1)]
        self.assertEqual([(entry["art"], entry["outcome"]) for entry in notiz], [("rueckmeldung", "erfolg")])
        self.assertFalse('"Zug ohne Bericht' in (self.world / "tickets" / "t-a" / "verlauf.jsonl").read_text())

    def test_review_turn_without_a_note_ends_unsuccessfully_and_gets_the_carrier_note(self):
        self.git_welt_mit_pruefer("pruefohne")
        self.reif_mit_commit()
        ad.review_ticket(self.world, "t-a", "a2", sender="haupt", claimed_role="hauptagent")
        run_id = next(item["run"] for item in self.traeger.einmal()["gestartet"] if item["agent"] == "a2")
        self.finish(run_id, None)
        verdict = self.traeger.einmal()["beendet"][0]
        self.assertEqual((verdict["outcome"], verdict["art"]), ("ergebnis_fehlt", "pruefung"))
        verlauf = (self.world / "tickets" / "t-a" / "verlauf.jsonl").read_text()
        self.assertIn("Zug ohne Bericht (Träger)", verlauf)
        self.assertIn('"ausgang": "ergebnis_fehlt"', verlauf)
        # Die Pruefung wird dem Pruefer erneut zugestellt (Abstand des Wiederholungsvertrags).
        self.offset += at.RECOVERY_ABSTAND_S + 1
        again = [item for item in self.traeger.einmal()["gestartet"] if item["agent"] == "a2"]
        self.assertEqual([(item["agent"], item["art"]) for item in again], [("a2", "pruefung")])
        self.finish_review(again[0]["run"], "jetzt geprueft", "maengel")
        self.assertEqual(self.traeger.einmal()["beendet"][0]["outcome"], "erfolg")
        self.assertEqual(ad.read_ticket(self.world, "t-a")["state"], "zur Abnahme")

    def test_stale_review_post_is_acknowledged_without_a_turn(self):
        self.git_welt_mit_pruefer("pruefstale")
        self.reif_mit_commit()
        ad.review_ticket(self.world, "t-a", "a2", sender="haupt", claimed_role="hauptagent")
        # Die Pruefung wird ohne den Prueferzug beendet; der Posten ist veraltet.
        ad.review_result(self.world, "t-a", "a2", "direkt geprueft", "bestanden",
                         sender="a2", claimed_role="mitglied")
        summary = self.traeger.einmal()
        self.assertEqual([item for item in summary["gestartet"] if item["agent"] == "a2"], [])
        self.assertTrue(self.postfach("a2", ad.derived_id("ticket-review", "t-a", 1))["acknowledged"])

    def test_review_turn_passes_the_locks_for_read_only(self):
        """Rechte-Test: die Profil-Sperre verweigert Schreibzugriffe des Pruefzuges, Lesen und der
        Dienstweg bleiben frei (Plan Satz 26: der Pruefer schreibt nichts)."""
        projekt, konfig = self.git_welt_mit_pruefer("pruefrechte")
        commit = self.reif_mit_commit()
        baum_a1 = (konfig.agents_dir / "a1" / "work").resolve() / "a1"
        ad.review_ticket(self.world, "t-a", "a2", sender="haupt", claimed_role="hauptagent")
        run_id = next(item["run"] for item in self.traeger.einmal()["gestartet"] if item["agent"] == "a2")
        lauf = self.laeufe[run_id]
        env = dict(lauf.zug.extra_env, PATH="/usr/bin:/bin", HOME=os.environ.get("HOME", "/"), LANG="C.UTF-8")
        settings = json.loads(Path(lauf.zug.settings_file).read_text())
        hooks = [(item["matcher"], hook["command"]) for item in settings["hooks"]["PreToolUse"]
                 for hook in item["hooks"]]

        def pruefen(tool, **fields):
            payload = json.dumps({"hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": fields,
                                  "cwd": str(lauf.workspace), "session_id": "probe"})
            reasons = []
            for matcher, command in hooks:
                if matcher != "*" and tool not in matcher.split("|"):
                    continue
                result = subprocess.run(["/bin/bash", "-c", command], input=payload, text=True,
                                        capture_output=True, env=env, timeout=30)
                for line in result.stdout.splitlines():
                    decision = json.loads(line).get("hookSpecificOutput") or {}
                    if decision.get("permissionDecision") == "deny":
                        reasons.append(decision.get("permissionDecisionReason"))
            return reasons

        rpc = dict(lauf.zug.extra_env)["WB_RPC_CLIENT"]
        self.assertEqual(pruefen("Bash", command="git show %s" % commit), [])
        self.assertEqual(pruefen("Bash", command="git diff HEAD~1"), [])
        self.assertEqual(pruefen("Bash", command="git log --oneline -3"), [])
        self.assertEqual(pruefen("Bash",
                                 command="printf '%%s' '{\"ticket_id\": \"t-a\", \"text\": \"n\", "
                                         "\"verdict\": \"maengel\"}' | /usr/bin/python3 %s ticket.review_result" % rpc),
                         [])
        # Schreiben in den geprüften Worktree ist verweigert: kein Schreibwerkzeug, kein Schreibpfad.
        self.assertTrue(pruefen("Write", file_path=str(baum_a1 / "notiz.md")))
        self.assertTrue(pruefen("Bash", command="echo x > %s/notiz.md" % baum_a1))
        # Lesen im Weltordner bleibt frei, Ausfuehren gesperrter Programme verweigert die Hausliste.
        self.assertEqual(pruefen("Read", file_path=str(self.world / "world.json")), [])
        self.assertIn("house list", " ".join(pruefen("Bash", command="git push origin main")))  # Kit: English lock texts
        self.finish_review(run_id, "geprueft", "bestanden")
        self.traeger.einmal()


class EndToEndTicketsTests(PruefzugHelfer, TraegerTest):
    """Ende-zu-Ende ohne Modell: Rueckgabe, Freiwerden, Parken, Triage und Duplikat."""

    def test_full_tickets2_flow_over_the_carrier(self):
        """Fertig-Liste, Zwischenstand, Pruefung, DoD-Bestaetigung ueber den Traeger (Auftrag tickets2)."""
        projekt, konfig = self.git_welt_mit_pruefer("tickets2e2e")
        ad.set_definition_of_done(self.world, ["Doku aktualisiert"], sender="mensch")
        # Ticket mit drei Fertig-Punkten.
        ad.create_ticket(self.world, "Mit Liste", "Ziel", "fertig", ["a1"], "haupt", "hauptagent",
                         ticket_id="t1", done_items=["Punkt A", "Punkt B", "Punkt C"])
        run1 = next(item["run"] for item in self.traeger.einmal()["gestartet"] if item["ticket"] == "t1")
        lauf1 = self.laeufe[run1]
        self.assertIn("[ ] Punkt A", lauf1.zug.prompt)
        self.assertIn("Definition of Done dieser Welt", lauf1.zug.prompt)
        self.assertIn("ticket.note", lauf1.zug.prompt)
        baum = (konfig.agents_dir / "a1" / "work").resolve() / "a1"
        (baum / "arbeit.txt").write_text("vom Agenten\n")
        self.git(baum, "add", "arbeit.txt")
        self.git(baum, "commit", "-qm", "arbeit")
        commit = self.git(baum, "rev-parse", "HEAD")
        # Das Ergebnis scheitert bei zwei Haken; der Zwischenstand wird geschrieben.
        ad.check_done_item(self.world, "t1", "a1", 1, sender="a1", claimed_role="mitglied")
        ad.check_done_item(self.world, "t1", "a1", 2, sender="a1", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError) as caught:
            ad.write_result(self.world, "t1", "a1", "fertig", commit, "a1", "mitglied")
        self.assertIn("Punkt C", str(caught.exception))
        ad.note_ticket(self.world, "t1", "a1", "Recherche steht, Code folgt", sender="a1",
                       claimed_role="mitglied")
        self.finish(run1, None)
        self.traeger.einmal()
        verlauf = (self.world / "tickets" / "t1" / "verlauf.jsonl").read_text()
        self.assertIn('"event": "zug"', verlauf)
        self.assertNotIn("Zug ohne Bericht", verlauf)
        # Dritter Haken, dann Ergebnis mit Commit.
        ad.check_done_item(self.world, "t1", "a1", 3, sender="a1", claimed_role="mitglied")
        ad.write_result(self.world, "t1", "a1", "fertig mit Commit", commit, "a1", "mitglied")
        # Der Hauptagent fordert die Pruefung an; der Pruefzug liest den Diff der Revision des Bearbeiters.
        ad.review_ticket(self.world, "t1", "a2", sender="haupt", claimed_role="hauptagent")
        review_run = next(item["run"] for item in self.traeger.einmal()["gestartet"] if item["agent"] == "a2")
        lauf2 = self.laeufe[review_run]
        self.assertEqual(tuple(lauf2.zug.tools), at.PRUEF_WERKZEUGE)
        settings_env = json.loads(Path(lauf2.zug.settings_file).read_text())["env"]
        self.assertEqual(settings_env["GIT_DIR"],
                         str(aw.verwaltung(projekt.resolve() / ".git", baum)))
        self.assertIn("git show %s" % commit, lauf2.zug.prompt)
        self.assertIn('"verdict": "VERDICT"', lauf2.zug.prompt)
        self.finish_review(review_run, "Diff deckt Punkt B nicht ab", "maengel")
        done = self.traeger.einmal()["beendet"][0]
        self.assertEqual((done["outcome"], done["art"]), ("erfolg", "pruefung"))
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "zur Abnahme")
        # Der Abnehmende sieht die Notiz; sein Hinweis-Zug wird abgeschlossen.
        self.haupt_befreien()
        notiz = [entry for entry in self.traeger._zuege_lesen()["runs"].values()
                 if entry.get("agent") == "haupt"
                 and entry.get("nachricht_id") == ad.derived_id("ticket-reviewed", "t1", 1)]
        self.assertEqual([(entry["art"], entry["outcome"]) for entry in notiz], [("rueckmeldung", "erfolg")])
        # Rueckgabe mit Bemerkung; der naechste Zug sieht Bemerkung und Pruefnotiz.
        ad.approve_ticket(self.world, "t1", "haupt", "hauptagent", "Bitte Punkt B belegen", accept=False)
        run_return = next(item["run"] for item in self.traeger.einmal()["gestartet"] if item["ticket"] == "t1")
        prompt_return = self.laeufe[run_return].zug.prompt
        self.assertIn("Returned by haupt: Bitte Punkt B belegen", prompt_return)
        self.assertIn("Review note by a2 (maengel):", prompt_return)
        self.assertIn("Diff deckt Punkt B nicht ab", prompt_return)
        # Nacharbeit: neue Revision mit Commit im selben Worktree.
        (baum / "nachtrag.txt").write_text("nach\n")
        self.git(baum, "add", "nachtrag.txt")
        self.git(baum, "commit", "-qm", "nachtrag")
        commit2 = self.git(baum, "rev-parse", "HEAD")
        ad.write_result(self.world, "t1", "a1", "Punkt B im Diff nachgetragen", commit2, "a1", "mitglied")
        self.finish(run_return, None)
        self.traeger.einmal()
        # Zweite Pruefung, Urteil bestanden.
        ad.review_ticket(self.world, "t1", "a2", sender="haupt", claimed_role="hauptagent")
        review2 = next(item["run"] for item in self.traeger.einmal()["gestartet"] if item["agent"] == "a2")
        self.assertEqual(self.traeger._zuege_lesen()["runs"][review2]["session_key"], "pruefung:t1:2")
        self.finish_review(review2, "Alle Punkte im Diff belegt", "bestanden")
        self.traeger.einmal()
        self.haupt_befreien()
        notiz2 = [entry for entry in self.traeger._zuege_lesen()["runs"].values()
                  if entry.get("agent") == "haupt"
                  and entry.get("nachricht_id") == ad.derived_id("ticket-reviewed", "t1", 2)]
        self.assertEqual([(entry["art"], entry["outcome"]) for entry in notiz2], [("rueckmeldung", "erfolg")])
        # Abnahme ohne DoD-Bestaetigung scheitert, mit Bestaetigung gelingt.
        with self.assertRaises(ad.AgentsError):
            ad.approve_ticket(self.world, "t1", "haupt", "hauptagent", "passt")
        approved = ad.approve_ticket(self.world, "t1", "haupt", "hauptagent", "passt", dod_checked=True)
        self.assertEqual(approved["state"], "abgenommen")

    def test_full_ticket_flow_over_the_carrier(self):
        self.ticket("t-a", agent="a1")
        self.ticket("t-b", agent="a2", dependencies=["t-a"])
        summary = self.traeger.einmal()
        self.assertEqual([item["ticket"] for item in summary["gestartet"]], ["t-a"])
        self.finish(self.erster_lauf_end("t-a"), "Ergebnis von A")
        self.traeger.einmal()
        self.assertEqual(ad.read_ticket(self.world, "t-a")["state"], "zur Abnahme")
        ad.approve_ticket(self.world, "t-a", "haupt", "hauptagent", "Der Test fehlt", accept=False)
        self.assertEqual(ad.read_ticket(self.world, "t-a")["state"], "zurückgegeben")
        summary = self.traeger.einmal()
        run_return = next(item["run"] for item in summary["gestartet"] if item["ticket"] == "t-a")
        self.assertIn("Returned by haupt: Der Test fehlt", self.laeufe[run_return].zug.prompt)
        self.finish(run_return, "Ergebnis von A neu")
        self.traeger.einmal()
        ad.approve_ticket(self.world, "t-a", "haupt", "hauptagent", "jetzt passt es")
        self.assertEqual(ad.read_ticket(self.world, "t-a")["state"], "abgenommen")
        self.assertEqual(ad.read_ticket(self.world, "t-b")["state"], "offen")
        summary = self.traeger.einmal()
        self.assertEqual([item["ticket"] for item in summary["gestartet"]], ["t-b"])
        self.assertEqual(len(list((self.world / "agents" / "a2" / "postfach").glob("*.json"))), 1)
        ad.park_ticket(self.world, "t-b", "a2", "wartet auf Zeit", until="2026-09-18T09:00:00Z",
                       sender="a2", claimed_role="mitglied")
        self.finish(self.erster_lauf_end("t-b"), None)
        self.offset = ad._epoch_of("2026-09-18T09:00:00Z") - time.time() + 30
        summary = self.traeger.einmal()
        self.assertEqual(summary["geweckt"], ["t-b"])
        run_b = next(item["run"] for item in summary["gestartet"] if item["ticket"] == "t-b")
        self.assertEqual(ad.read_ticket(self.world, "t-b")["state"], "läuft")
        self.finish(run_b, None)
        triage = ad.create_ticket(self.world, "Ohne Adressat", "Z", "F", [], "haupt", "hauptagent")
        self.assertEqual(triage["state"], "triage")
        ad.triage_accept(self.world, triage["id"], ["a1"], priority=2, kind="fehler",
                         sender="haupt", claimed_role="hauptagent")
        duplicate = ad.create_ticket(self.world, "Ohne Adressat nochmal", "Z", "F", [], "haupt", "hauptagent")
        ad.discard_ticket(self.world, duplicate["id"], "duplikat", "gleiches Thema",
                          duplicate_of=triage["id"], sender="haupt", claimed_role="hauptagent")
        verlauf = (self.world / "tickets" / triage["id"] / "verlauf.jsonl").read_text()
        self.assertIn("duplikat-gemeldet", verlauf)
        self.assertIn(duplicate["id"], verlauf)

    def erster_lauf_end(self, ticket_id):
        entry = next(entry for entry in self.traeger._zuege_lesen()["runs"].values()
                     if entry.get("ticket_id") == ticket_id)
        return entry["run_id"]

    def zug_endet(self, ticket_id):
        def hat_zug(summary):
            verlauf = (self.world / "tickets" / ticket_id / "verlauf.jsonl")
            if not verlauf.exists():
                return False
            return any(json.loads(line).get("event") == "zug" for line in verlauf.read_text().splitlines())
        for _ in range(40):
            summary = self.traeger.einmal()
            if hat_zug(summary):
                return summary
            time.sleep(0.05)
        return summary



if __name__ == "__main__":
    unittest.main()
