#!/usr/bin/env python3
"""Isolierte Proben: Rechte durch den Hauptagenten, Fallback-Modell im Traeger, Modellliste und Maschine je Welt.

der Nutzer, 16.09.2026: „Der Hauptagent darf entscheiden, wer welche Berechtigung bekommt, und ich beim Erstellen.“
„Fallback-Modell machen.“ „Myproject-Agenten sollen alle auf host2 laufen.“ Keine echten Modellzuege: der Traeger
laeuft mit den Stellvertretern aus test-wb-agents-traeger.py, eine 429 ist eine Stream-Attrappe.
"""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import time
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHELL))

import agents_controller as actl  # noqa: E402
import agents_data as ad  # noqa: E402
import agents_modellwahl as amw  # noqa: E402
from herkunft_fixture import gemessener_mensch  # noqa: E402


_MENSCH_PATCH = None


def setUpModule():
    global _MENSCH_PATCH
    _MENSCH_PATCH = gemessener_mensch(ad)
    _MENSCH_PATCH.start()


def tearDownModule():
    _MENSCH_PATCH.stop()

_spec = importlib.util.spec_from_file_location("traeger_proben", Path(__file__).resolve().parent / "test-wb-agents-traeger.py")
traeger_proben = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(traeger_proben)
at = traeger_proben.at
MODEL = traeger_proben.MODEL

REGISTRY = {"models": [
    {"id": "claude-opus-5", "alias": "opus5", "harness": "claude", "modelRef": "claude-opus-5", "enabled": True,
     "machines": ["mac", "host2"]},
    {"id": "claude-sonnet-5", "alias": "sonnet5", "harness": "claude", "modelRef": "claude-sonnet-5", "enabled": True,
     "machines": ["mac", "host2"]},
    {"id": "claude-haiku-4-5", "alias": "haiku45", "harness": "claude", "modelRef": "claude-haiku-4-5",
     "enabled": True, "machines": ["mac", "host2"]},
    {"id": "claude-fable-5-1", "alias": "fable51", "harness": "claude", "modelRef": "claude-fable-5-1",
     "enabled": True, "machines": ["mac", "host2"]},
    {"id": "lmgamma-27b", "alias": "lmgamma", "harness": "pi", "enabled": True, "machines": ["mac"]},
    {"id": "codex-gpt-5-5", "harness": "codex", "modelRef": "gpt-5.5", "enabled": True},
]}


def zugaenge(world: Path, *eintraege: dict) -> None:
    (world / "zugaenge.json").write_text(json.dumps({"zugaenge": list(eintraege)}), encoding="utf-8")


def traeger_json(world: Path, **werte) -> None:
    daten = {"version": 1, "execution_host": "host2", "maschine": "lokal",
             "modelle": dict(at.MODELLE_VORGABE, **{"fable": "claude-fable-5-1"}), "pi": None, "codex": None,
             "registry": None}
    daten.update(werte)
    (world / "traeger.json").write_text(json.dumps(daten), encoding="utf-8")


class WeltProbe(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-profilrechte-")
        self.base = Path(self.tmp.name)
        self.world = self.base / "world"
        ad.create_world(self.world, name="Rechte", main_name="main", sender="cli-operator")
        ad.create_agent(self.world, "lead", "teamleiter", "recht", "Leitet", None, None, None, None, None, None,
                        "lokal", "main", "hauptagent")
        ad.create_agent(self.world, "member", "mitglied", "recht", "Recherchiert", None, None, None, None, None,
                        None, "lokal", "main", "hauptagent")
        self.controllers = []

    def tearDown(self):
        for controller in self.controllers:
            controller.close()
            controller.join()
        self.tmp.cleanup()

    def client(self, agent_id: str, role: str):
        controller = actl.AgentController(self.world, "run-1", lambda binding: True, 1.0, 5.0)
        self.controllers.append(controller)
        return controller.bind_agent(agent_id, role)

    def history(self, agent_id: str) -> list[dict]:
        return json.loads((self.world / "agents" / agent_id / "history.json").read_text())["entries"]


class RechteProben(WeltProbe):
    def test_main_agent_sets_rights_of_a_member_through_the_service_path(self):
        zugaenge(self.world, {"name": "netz", "art": "web"}, {"name": "host2", "art": "ssh"})
        main = self.client("main", "hauptagent")
        data = main.request("agent.rechte", {"agent_id": "member", "tools": ["Read", "Grep", "Write"],
                                             "bash": ["pytest *", "ssh host2 *"], "skills": ["texte-schreiben"],
                                             "web": True})
        agent = ad.read_agent(self.world, "member")
        self.assertEqual(agent["tools"], ["Read", "Grep", "Write", "WebFetch", "WebSearch", "Bash"])
        # Die Dienstwegmuster bleiben immer; eigene Muster stehen davor.
        self.assertEqual(agent["bash"], ["pytest *", "ssh host2 *"] + list(ad.DEFAULT_BASH))
        self.assertEqual(agent["skills"], ["texte-schreiben"])
        entry = self.history("member")[-1]
        self.assertEqual((entry["event"], entry["actor"]["id"], entry["actor"]["kind"]), ("rechte", "main", "agent"))
        self.assertEqual(sorted(entry["changes"]), ["bash", "skills", "tools"])
        self.assertIn("nächsten Zug", entry["note"])
        # Die Anweisungsdatei endet mit den neuen Grenzen.
        instructions = (self.world / "agents" / "member" / "AGENTS.md").read_text()
        self.assertEqual(instructions.count(ad.INSTRUCTIONS_LIMITS_MARK), 1)
        self.assertIn("`pytest *`", instructions)
        self.assertIn("WebFetch", instructions)
        # Der Mensch erfaehrt es als markiertes Ergebnis mit den Rechten.
        messages = [m for m in ad.read_messages(self.world) if m.get("id") == data["meldung"]]
        self.assertEqual(len(messages), 1)
        self.assertEqual(messages[0].get("mark"), "ergebnis")
        self.assertIn("Rechte von member", messages[0]["text"])
        self.assertIn("`pytest *`", messages[0]["text"])
        # Wiederholung ohne Aenderung: kein Verlaufseintrag, keine Meldung.
        again = main.request("agent.rechte", {"agent_id": "member", "tools": ["Read", "Grep", "Write"], "web": True})
        self.assertIsNone(again["meldung"])
        self.assertEqual(len([e for e in self.history("member") if e["event"] == "rechte"]), 1)
        # web false nimmt beide Web-Werkzeuge; ein Bash-Muster, das dem Dienstweg gleicht, wird nicht doppelt.
        main.request("agent.rechte", {"agent_id": "member", "web": False, "bash": ["git status"]})
        agent = ad.read_agent(self.world, "member")
        self.assertNotIn("WebFetch", agent["tools"])
        self.assertEqual(agent["bash"], list(ad.DEFAULT_BASH))

    def test_team_leader_member_and_main_agent_on_itself_are_refused(self):
        lead = self.client("lead", "teamleiter")
        with self.assertRaisesRegex(actl.ControllerError, "darf diese Mutation nicht ausfuehren"):
            lead.request("agent.rechte", {"agent_id": "member", "skills": ["x"]})
        with self.assertRaisesRegex(ad.AgentsError, "darf diese Mutation nicht ausfuehren"):
            ad.set_agent_rights(self.world, "member", {"skills": ["x"]}, "member", "mitglied")
        main = self.client("main", "hauptagent")
        with self.assertRaisesRegex(actl.ControllerError, "eigenen Rechte"):
            main.request("agent.rechte", {"agent_id": "main", "skills": ["x"]})
        with self.assertRaisesRegex(actl.ControllerError, "Werkzeug nicht erlaubt"):
            main.request("agent.rechte", {"agent_id": "member", "tools": ["Read", "mcp__x__y"]})
        with self.assertRaisesRegex(actl.ControllerError, "gesperrt"):
            main.request("agent.rechte", {"agent_id": "member", "bash": ["git push *"]})
        with self.assertRaisesRegex(actl.ControllerError, "Payloadfeld hat falschen Typ: web"):
            main.request("agent.rechte", {"agent_id": "member", "web": "ja"})
        self.assertEqual([e for e in self.history("member") if e["event"] == "rechte"], [])

    def test_web_and_ssh_need_the_accesses_of_the_world(self):
        main = self.client("main", "hauptagent")
        with self.assertRaisesRegex(actl.ControllerError, "Zugang der Art web"):
            main.request("agent.rechte", {"agent_id": "member", "web": True})
        with self.assertRaisesRegex(actl.ControllerError, "Zugang der Art web"):
            main.request("agent.rechte", {"agent_id": "member", "tools": ["Read", "WebSearch"]})
        with self.assertRaisesRegex(actl.ControllerError, "ssh-Zugang"):
            main.request("agent.rechte", {"agent_id": "member", "bash": ["ssh host2 *"]})
        zugaenge(self.world, {"name": "host2", "art": "ssh"})
        with self.assertRaisesRegex(actl.ControllerError, "keinen eingerichteten ssh-Zugang"):
            main.request("agent.rechte", {"agent_id": "member", "bash": ["ssh fremd *"]})
        with self.assertRaisesRegex(actl.ControllerError, "Zugang der Art web"):
            main.request("agent.rechte", {"agent_id": "member", "web": True})
        main.request("agent.rechte", {"agent_id": "member", "bash": ["ssh host2 *", "scp *host2:*"]})
        self.assertIn("scp *host2:*", ad.read_agent(self.world, "member")["bash"])
        # Der Mensch ist an dieselbe Grenze gebunden.
        with self.assertRaisesRegex(ad.AgentsError, "Zugang der Art web"):
            ad.set_agent_rights(self.world, "member", {"web": True}, "mensch")

    def test_agent_marked_cli_cannot_claim_human_rights_but_measured_human_can(self):
        zugaenge(self.world, {"name": "netz", "art": "web"})
        run = subprocess.run([str(SHELL / "wb-agent"), "rechte", str(self.world), "member", "--werkzeuge", "Read,grep",
                              "--bash", "pytest *", "--skills", "texte-schreiben,recherche", "--web"],
                             text=True, capture_output=True, timeout=30)
        self.assertEqual(run.returncode, 2)
        self.assertIn("Agenten-Marker", run.stderr)
        ad.set_agent_rights(self.world, "member", {"tools": ["Read", "grep"], "bash": ["pytest *"],
                                                    "skills": ["texte-schreiben", "recherche"], "web": True},
                            "mensch")
        entry = self.history("member")[-1]
        self.assertEqual((entry["event"], entry["actor"]["id"], entry["actor"]["kind"]), ("rechte", "mensch", "external"))
        agent = ad.set_agent_rights(self.world, "member", {"bash": [], "skills": [], "web": False}, "mensch")
        self.assertEqual((agent["bash"], agent["skills"], agent["tools"]), (list(ad.DEFAULT_BASH), [], ["Read", "Grep", "Bash"]))
        refused = subprocess.run([str(SHELL / "wb-agent"), "rechte", str(self.world), "member", "--skills", "x",
                                  "--absender", "lead"], text=True, capture_output=True, timeout=30)
        self.assertNotEqual(refused.returncode, 0)
        self.assertIn("darf diese Mutation nicht ausfuehren", refused.stderr + refused.stdout)

    def test_main_agent_draft_keeps_tools_bash_and_skills_and_lands_on_the_carrier_host(self):
        traeger_json(self.world)
        main = self.client("main", "hauptagent")
        draft = {"id": "recherche", "stage": "mitglied", "team": "recht", "specialty": "Sucht Urteile.",
                 "model": "sonnet5:high", "tools": ["read", "Grep"], "bash": ["pytest *"], "skills": "texte-schreiben"}
        created = main.request("agent.create", {"draft": draft})
        self.assertEqual(created["tools"], ["Read", "Grep", "Bash"])
        self.assertEqual(created["bash"], ["pytest *"] + list(ad.DEFAULT_BASH))
        self.assertEqual(created["skills"], ["texte-schreiben"])
        self.assertEqual(created["machine"], "host2")
        text = next(m["text"] for m in ad.read_messages(self.world) if m.get("id") == created["meldung"])
        self.assertIn("Maschine host2", text)
        self.assertIn("Werkzeuge Read, Grep, Bash", text)
        self.assertIn("`pytest *`", text)
        self.assertIn("Skills texte-schreiben", text)
        # Das Beispiel der Anweisung (ohne Werkzeuge) wird angelegt: die Werkzeuge der Stufe kommen dazu.
        bare = main.request("agent.create", {"draft": {"id": "knapp", "stage": "mitglied", "team": "recht",
                                                       "specialty": "Ein Satz", "model": "sonnet5:high"}})
        self.assertEqual(bare["tools"][:4], list(ad.DEFAULT_TOOLS["mitglied"])[:4])
        self.assertEqual(bare["machine"], "host2")
        # Eine ausdrueckliche Maschine bleibt; ohne traeger.json bleibt es bei lokal.
        explicit = main.request("agent.create", {"draft": {"id": "mac", "stage": "mitglied", "team": "recht",
                                                           "specialty": "Ein Satz", "machine": "mac"}})
        self.assertEqual(explicit["machine"], "mac")
        (self.world / "traeger.json").unlink()
        self.assertEqual(ad.world_machine_default(self.world), "lokal")
        self.assertEqual(ad.preview_agent_draft(self.world, {"id": "x", "specialty": "y"})["draft"]["machine"], "lokal")


class ModelllisteProben(WeltProbe):
    def test_world_with_carrier_lists_only_claude_models_without_fable(self):
        registry = self.base / "models.json"
        registry.write_text(json.dumps(REGISTRY), encoding="utf-8")
        traeger_json(self.world, registry=str(registry))
        view = subprocess.run([str(SHELL / "wb-welt"), "ansicht", str(self.world), "--json"], text=True,
                              capture_output=True, timeout=30)
        self.assertEqual(view.returncode, 0, view.stderr)
        data = json.loads(view.stdout)
        self.assertEqual(data["maschine_vorgabe"], "host2")
        modelle = data["modelle"]
        self.assertEqual({item["harness"] for item in modelle}, {"claude"})
        self.assertFalse([item for item in modelle if "fable" in item["id"]])
        self.assertIn({"id": "sonnet5:high", "harness": "claude", "verfuegbar": True}, modelle)
        self.assertIn({"id": "haiku", "harness": "claude", "verfuegbar": True}, modelle)
        self.assertEqual(sorted(item["id"] for item in modelle), sorted(at.MODELLE_VORGABE))
        self.assertTrue(all(set(item) <= {"id", "harness", "verfuegbar", "grund"} for item in modelle))
        # Eine Registry ohne Sonnet: nicht verfuegbar mit Grund.
        registry.write_text(json.dumps({"models": [m for m in REGISTRY["models"] if m["id"] != "claude-sonnet-5"]}))
        eintrag = next(item for item in amw.welt_modelle(self.world) if item["id"] == "sonnet5:low")
        self.assertEqual(eintrag, {"id": "sonnet5:low", "harness": "claude", "verfuegbar": False,
                                   "grund": "nicht_in_registry"})

    def test_pi_and_codex_rows_and_world_without_carrier(self):
        registry = self.base / "models.json"
        registry.write_text(json.dumps(REGISTRY), encoding="utf-8")
        traeger_json(self.world, registry=str(registry), execution_host="mac",
                     pi={"node": "/usr/bin/node", "cli": "/opt/pi/cli.js", "base_url": "http://127.0.0.1:11570",
                         "modelle": {"lmgamma": {}}},
                     codex={"cli": "/opt/codex", "auth": "/nonexistent/auth.json"})
        modelle = amw.welt_modelle(self.world)
        self.assertIn({"id": "lmgamma", "harness": "pi", "verfuegbar": True}, modelle)
        self.assertIn({"id": "codex-gpt-5-5", "harness": "codex", "verfuegbar": False, "grund": "codex_nur_trockenlauf"},
                      modelle)
        (self.world / "traeger.json").unlink()
        data = ad.world_snapshot(self.world)
        self.assertNotIn("modelle", data)
        self.assertEqual(data["maschine_vorgabe"], "lokal")


class FallbackProben(unittest.TestCase):
    """Die Stellvertreter des Traegertests, ohne dessen Testfaelle erneut zu sammeln."""

    for _name in ("setUp", "tearDown", "make", "fabrik", "stream", "finish", "ticket", "abgewiesen", "budget_runner"):
        locals()[_name] = getattr(traeger_proben.TraegerTest, _name)

    PI = {"node": "/usr/bin/node", "cli": "/opt/pi/cli.js", "base_url": "http://127.0.0.1:11570",
          "modelle": {"lmgamma": {"context_window": 16384}}}

    def mit_pi(self, frei=True):
        import dataclasses
        self.frei = frei
        self.konfig = dataclasses.replace(self.konfig, pi=dict(self.PI))
        self.traeger = at.WeltTraeger(self.konfig, zug_fabrik=self.fabrik, observer_fabrik=lambda _t: self.launcher,
                                      ausgabe=lambda _t, receipt: self.outputs.get(receipt.pid, b""),
                                      anmeldequelle=self.credential, kontingentquelle=self.kontingent,
                                      zeitgeber=self.timer_calls.append, clock=lambda: time.time() + self.offset,
                                      lokal_frei=lambda _url: self.frei)

    def fallback(self, agent, modell):
        ad.update_agent_profile(self.world, agent, {"fallback_model": modell}, "mensch")

    def entry(self, run_id):
        return self.traeger._zuege_lesen()["runs"][run_id]

    def test_quota_rejection_switches_to_a_fallback_outside_the_subscription(self):
        self.mit_pi()
        self.fallback("a1", "lmgamma")
        self.ticket("t1")
        first = self.traeger.einmal()["gestartet"][0]["run"]
        self.assertEqual(self.entry(first)["modellwahl"], {"profil": MODEL, "modell": MODEL, "harness": "claude",
                                                           "fallback": False, "grund": None})
        self.finish(first, stream=self.abgewiesen(429, resets_at=int(time.time() + 3600)))
        done = self.traeger.einmal()
        verdict = done["beendet"][0]
        self.assertEqual((verdict["outcome"], verdict["folge"].get("fallback")), ("kontingent", True))
        self.assertNotIn("a1", self.traeger._zuege_lesen()["schlaf"])
        # Die Recovery ist sofort faellig: derselbe Durchgang startet den Fallback.
        started = done["gestartet"]
        self.assertEqual([(item["art"], item["ticket"]) for item in started], [("fortsetzen", "t1")])
        entry = self.entry(started[0]["run"])
        self.assertEqual((entry["harness"], entry["model"], entry["resume"]), ("pi", "lmgamma", False))
        self.assertEqual(entry["modellwahl"], {"profil": MODEL, "modell": "lmgamma", "harness": "pi", "fallback": True,
                                               "grund": "kontingent"})
        status = self.traeger.status()
        self.assertEqual(status["agenten"]["a1"]["modellwahl"]["grund"], "kontingent")
        self.assertEqual(status["fallback_vorgemerkt"]["a1"]["grund"], "kontingent")
        self.finish(started[0]["run"], "mit Fallback fertig")
        done = self.traeger.einmal()
        # Die Stream-Attrappe ist eine Claude-Ausgabe; das Urteil ueber den Pi-Zug ist hier nicht Gegenstand.
        self.assertEqual(done["beendet"][0]["run"], started[0]["run"])
        status = self.traeger.status()
        self.assertEqual(status["letzte_zuege"][-1]["modellwahl"]["modell"], "lmgamma")
        self.assertEqual(status["agenten"]["a1"]["letzter"]["modellwahl"]["fallback"], True)
        # Solange das Abo vorgemerkt ist, faehrt auch ein neues Ticket den Fallback.
        self.ticket("t2")
        second = self.traeger.einmal()["gestartet"][0]["run"]
        self.assertEqual(self.entry(second)["modellwahl"]["modell"], "lmgamma")

    def test_fallback_in_the_same_subscription_waits_and_status_names_the_reason(self):
        self.fallback("a1", "claude-sonnet-5")
        self.ticket("t1")
        first = self.traeger.einmal()["gestartet"][0]["run"]
        resets = time.time() + 1800
        self.finish(first, stream=self.abgewiesen(429, resets_at=int(resets)))
        verdict = self.traeger.einmal()["beendet"][0]
        self.assertEqual(verdict["outcome"], "kontingent")
        self.assertEqual(verdict["folge"]["fallback"], {"modell": "claude-sonnet-5", "grund": "gleiches_abo"})
        waiting = self.traeger.einmal()
        self.assertEqual((waiting["gestartet"], waiting["wartend"][0]["reason"]), ([], "schlaeft"))
        stand = self.traeger.status()["agenten"]["a1"]
        self.assertEqual(stand["fallback"], {"modell": "claude-sonnet-5", "grund": "gleiches_abo"})
        self.assertEqual(self.traeger._zuege_lesen()["schlaf"]["a1"]["grund"], "kontingent")

    def test_budget_gate_uses_a_fallback_outside_the_subscription_and_waits_without_one(self):
        now = time.time()
        state = {"budget": {"five_hour_pct": 100, "five_hour_resets_at_epoch": now + 3000,
                            "seven_day_pct": 10, "seven_day_resets_at_epoch": now + 6 * 86400}}
        from agents_kontingent import KontingentQuelle
        self.kontingent = KontingentQuelle(runner=self.budget_runner(state), clock=lambda: time.time() + self.offset)
        self.mit_pi()
        self.fallback("a1", "lmgamma")
        self.fallback("a2", "claude-sonnet-5")
        self.ticket("t1")
        self.ticket("t2", agent="a2")
        summary = self.traeger.einmal()
        self.assertEqual([item["agent"] for item in summary["gestartet"]], ["a1"])
        self.assertEqual(self.entry(summary["gestartet"][0]["run"])["modellwahl"]["grund"], "kontingent")
        wait = next(item for item in summary["wartend"] if item["agent"] == "a2")
        self.assertEqual((wait["reason"], wait["fallback"]["grund"]), ("kontingent", "gleiches_abo"))
        self.assertEqual(self.traeger._zuege_lesen()["schlaf"]["a2"]["quelle"]["fallback"]["grund"], "gleiches_abo")

    def test_busy_local_model_and_start_error_use_the_fallback_once(self):
        self.mit_pi(frei=False)
        ad.update_agent_profile(self.world, "a1", {"model": "lmgamma", "effort": "medium"}, "mensch")
        self.ticket("t1")
        summary = self.traeger.einmal()
        self.assertEqual((summary["gestartet"], summary["wartend"][0]["reason"]), ([], "belegt"))
        self.assertEqual(summary["wartend"][0]["fallback"]["grund"], "kein_fallback")
        self.fallback("a1", "claude-sonnet-5")
        self.offset += at.BELEGT_ABSTAND_S + 1
        started = self.traeger.einmal()["gestartet"]
        self.assertEqual(len(started), 1)
        self.assertEqual(self.entry(started[0]["run"])["modellwahl"],
                         {"profil": "lmgamma", "modell": "claude-sonnet-5", "harness": "claude", "fallback": True,
                          "grund": "belegt"})
        self.finish(started[0]["run"], "fertig")
        self.traeger.einmal()
        # Startfehler: der naechste Zug faehrt einmal den Fallback, danach wieder das Profilmodell.
        # Der Harness scheitert vor dem Start (wie der Codex-Trockenlauf in _claude_lauf_fabrik); ein Launcherfehler
        # nach dem Start bleibt dagegen ungeklaert, bis sein Ende belegt ist (test_start_error_tombstone_...).
        self.frei = True
        echte_fabrik = self.traeger._zug_fabrik

        def scheitert(*args, **kwargs):
            self.traeger._zug_fabrik = echte_fabrik
            raise at.TraegerFehler("Harness startet nicht")
        self.traeger._zug_fabrik = scheitert
        self.ticket("t2")
        failed = self.traeger.einmal()
        runs = self.traeger._zuege_lesen()["runs"]
        broken = next(entry for entry in runs.values() if entry.get("ticket_id") == "t2" and entry.get("outcome"))
        self.assertEqual((broken["outcome"], broken["folge"].get("fallback")), ("startfehler", True))
        self.assertEqual(broken["modellwahl"]["fallback"], False)
        retry = failed["gestartet"] or self.traeger.einmal()["gestartet"]
        self.assertEqual([item["art"] for item in retry], ["fortsetzen"])
        self.assertEqual(self.entry(retry[0]["run"])["modellwahl"]["grund"], "startfehler")
        self.assertNotIn("a1", self.traeger._zuege_lesen()["fallback"])
        self.finish(retry[0]["run"], "fertig mit Fallback")
        self.traeger.einmal()
        self.ticket("t3")
        normal = self.traeger.einmal()["gestartet"][0]["run"]
        self.assertEqual(self.entry(normal)["modellwahl"]["fallback"], False)

    def test_fable_is_never_model_or_fallback(self):
        with self.assertRaisesRegex(ad.AgentsError, "Fable"):
            ad.update_agent_profile(self.world, "a1", {"fallback_model": "claude-fable-5-1"}, "mensch")
        # Auch ein von Hand geschriebenes Profil faehrt nie Fable.
        path = self.world / "agents" / "a1" / "agent.json"
        agent = json.loads(path.read_text())
        agent["model_profile"]["fallback_model"] = "claude-fable-5-1"
        path.write_text(json.dumps(agent))
        self.assertEqual(self.traeger.fallback_agent(agent), (None, "fallback_fable_verboten"))
        self.ticket("t1")
        first = self.traeger.einmal()["gestartet"][0]["run"]
        self.finish(first, stream=self.abgewiesen(429, resets_at=int(time.time() + 900)))
        verdict = self.traeger.einmal()["beendet"][0]
        self.assertEqual(verdict["folge"]["fallback"], {"modell": None, "grund": "fallback_fable_verboten"})
        agent["model_profile"]["model"] = "claude-fable-5-1"
        agent["model_profile"]["fallback_model"] = None
        (self.world / "agents" / "a2" / "agent.json").write_text(json.dumps(dict(agent, id="a2", name="a2")))
        self.ticket("t2", agent="a2")
        summary = self.traeger.einmal()
        self.assertEqual([item["reason"] for item in summary["wartend"] if item["agent"] == "a2"], ["fable_verboten"])
        self.assertFalse([run for run in self.traeger._zuege_lesen()["runs"].values()
                          if "fable" in str(run.get("model"))])
        self.assertFalse([item for item in amw.modelle({"modelle": {"fable": "claude-fable-5-1"}}) if item])


if __name__ == "__main__":
    unittest.main()
