#!/usr/bin/env python3
"""Git-Umgebung des Zuges und Fallback-Zug im Traeger, fuer jeden Harness.

Der Auftrag vom 20.09.2026: ein Zug ueber den Pi- oder Codex-Harness hatte im Worktree keine git-Identitaet
(docs/AGENTS-TRAEGER.md, "Worktree je Agent") und konnte nicht committen; der Fallback-Zug war nur ueber die
Stellvertreter des Belegt-Pruefers belegt. Hier laeuft alles ueber das Testgeschirr des Traegers mit
Attrappen-Harness: kein echter Modellzug, keine Kosten, nur Wegwerf-Repos.
"""

from __future__ import annotations

import dataclasses
import importlib.util
import json
import os
import socket
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

SHELL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHELL))

import agents_codex as acx  # noqa: E402
import agents_data as ad  # noqa: E402
import agents_pi as ap  # noqa: E402
import agents_traeger as at  # noqa: E402
import agents_worktree as aw  # noqa: E402
from herkunft_fixture import aufbau_herkunft, gebundene_governance, gemessener_mensch  # noqa: E402

_spec = importlib.util.spec_from_file_location("traeger_proben", SHELL / "tests" / "test-wb-agents-traeger.py")
traeger_proben = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(traeger_proben)

MODEL = traeger_proben.MODEL
PERSON = ("Mensch Probe", "mensch@example.invalid")
PI_MODELLE = {"lmgamma": {"context_window": 16384}}

_MESSER = gemessener_mensch(ad)
_GOVERNANCE_CONTEXT = None


def setUpModule():
    global _GOVERNANCE_CONTEXT
    _MESSER.start()
    _GOVERNANCE_CONTEXT = gebundene_governance(ad)
    _GOVERNANCE_CONTEXT.__enter__()


def tearDownModule():
    _GOVERNANCE_CONTEXT.__exit__(None, None, None)
    _MESSER.stop()


def freier_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


class Basis(unittest.TestCase):
    """Das Geschirr des Traegertests, ohne dessen Testfaelle erneut zu sammeln."""

    for _name in ("setUp", "tearDown", "make", "fabrik", "stream", "finish", "ticket", "abgewiesen"):
        locals()[_name] = getattr(traeger_proben.TraegerTest, _name)
    for _name in ("git_welt", "git_welt_mit_pruefer", "reif_mit_commit", "haupt_befreien"):
        locals()[_name] = getattr(traeger_proben.TraegerTest, _name, None) \
            or getattr(traeger_proben.PruefzugHelfer, _name)
    git = staticmethod(traeger_proben.TraegerTest.__dict__["git"].__func__)
    del _name

    def identitaet_setzen(self, projekt: Path) -> None:
        """Die Identitaet des Menschen im Projekt des Traegerhosts; sonst zaehlte die des laufenden Nutzers."""
        self.git(projekt, "config", "user.name", PERSON[0])
        self.git(projekt, "config", "user.email", PERSON[1])

    def paare(self, env: dict[str, str]) -> dict[str, str]:
        return {env["GIT_CONFIG_KEY_%d" % i]: env["GIT_CONFIG_VALUE_%d" % i]
                for i in range(int(env["GIT_CONFIG_COUNT"]))}

    def pi_welt(self, name="gitpi", base_url="http://127.0.0.1:11570", fallback=None):
        projekt, konfig = self.git_welt(name)
        self.identitaet_setzen(projekt)
        konfig = dataclasses.replace(konfig, pi={"node": "/usr/bin/node", "cli": "/opt/pi/cli.js",
                                                 "base_url": base_url, "modelle": dict(PI_MODELLE)})
        self.traeger = self.make(konfig)
        with aufbau_herkunft(ad) as aufbau:
            ad.create_agent_from_draft(self.world, {"id": "lokal", "specialty": "Arbeitet lokal",
                                                   "model": "lmgamma", "effort": "low",
                                                   "tools": ["Read"]}, aufbau)
        if fallback is not None:
            ad.update_agent_profile(self.world, "lokal", {"fallback_model": fallback}, "mensch")
        return projekt, konfig

    def zug_git_umgebung(self, lauf) -> dict[str, str]:
        """Die GIT_*-Umgebung, die der Zug tatsaechlich bekommt: bei Pi und Codex aus ``extra_env``,
        bei Claude aus der Einstellungsdatei."""
        env = {k: v for k, v in dict(lauf.zug.extra_env).items() if k.startswith("GIT_")}
        datei = getattr(lauf.zug, "settings_file", None)
        if datei:
            env.update({k: v for k, v in (json.loads(Path(datei).read_text()).get("env") or {}).items()
                        if k.startswith("GIT_")})
        return env

    def commit_mit(self, baum: Path, env: dict[str, str], datei: str) -> str:
        """Commit im Worktree mit genau der Umgebung des Zuges, in einem fremden HOME ohne Konfiguration."""
        fremdes_home = self.root / "home-ohne-konfiguration"
        fremdes_home.mkdir(exist_ok=True)
        umgebung = {"HOME": str(fremdes_home), "PATH": os.environ.get("PATH", ""), "LANG": "C.UTF-8", **env}
        (baum / datei).write_text("vom Agenten\n")
        for befehl in (["add", datei], ["commit", "-m", "agent change"]):
            subprocess.run(["git", *befehl], cwd=baum, env=umgebung, check=True, capture_output=True)
        return subprocess.run(["git", "log", "-1", "--format=%an <%ae>"], cwd=baum, env=umgebung, check=True,
                              capture_output=True, text=True).stdout.strip()


class GitUmgebungTests(Basis):
    """Jeder Zug committet im Worktree unter der Identitaet des Menschen, gleich welcher Harness."""

    def test_pi_turn_gets_the_git_environment_and_commits_as_the_human(self):
        projekt, konfig = self.pi_welt()
        self.traeger._lokal_frei_pruefer = lambda _url: True
        global_vorher = subprocess.run(["git", "config", "--global", "--list"], capture_output=True, text=True)
        config_vorher = (projekt / ".git" / "config").read_bytes()
        self.ticket("g1", agent="lokal")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        lauf, entry = self.laeufe[run_id], self.traeger._zuege_lesen()["runs"][run_id]
        baum = (konfig.agents_dir / "lokal" / "work").resolve() / "lokal"
        self.assertIsInstance(lauf.zug, ap.PiZug)
        self.assertEqual((entry["harness"], entry["worktree"], lauf.workspace), ("pi", str(baum), baum))
        env = self.zug_git_umgebung(lauf)
        paare = self.paare(env)
        self.assertEqual((paare["user.name"], paare["user.email"]), PERSON)
        self.assertEqual((env["GIT_CONFIG_GLOBAL"], env["GIT_CONFIG_NOSYSTEM"]), ("/dev/null", "1"))
        self.assertEqual((paare["core.hooksPath"], paare["commit.gpgSign"], paare["core.editor"]),
                         ("/dev/null", "false", "false"))
        # Der Runner reicht genau diese Namen an Pi weiter.
        import agents_pi_runner as apr
        _argv, kindumgebung = apr.command(lauf.zug.as_dict(), "http://127.0.0.1:9/v1")
        self.assertEqual({k: v for k, v in kindumgebung.items() if k.startswith("GIT_")}, env)
        # Der Commit im Worktree traegt die Identitaet des Menschen, nie die Agentenkennung.
        self.assertEqual(self.commit_mit(baum, env, "pi.txt"), "%s <%s>" % PERSON)
        self.finish(run_id, "fertig")
        self.traeger.einmal()
        # Weder die globale noch die Projektkonfiguration hat sich geaendert.
        global_nachher = subprocess.run(["git", "config", "--global", "--list"], capture_output=True, text=True)
        self.assertEqual((global_vorher.returncode, global_vorher.stdout),
                         (global_nachher.returncode, global_nachher.stdout))
        self.assertEqual((projekt / ".git" / "config").read_bytes(), config_vorher)

    def test_codex_turn_gets_the_same_git_environment(self):
        projekt, konfig = self.git_welt("gitcodex")
        self.identitaet_setzen(projekt)
        registry = self.root / "models-codex.json"
        registry.write_text(json.dumps({"models": [{"id": "codex-gpt-5-5", "harness": "codex", "modelRef": "gpt-5.5",
                                                    "efforts": ["low", "medium", "high"], "enabled": True}]}))
        cli = self.root / "codex-bin" / "codex"
        cli.parent.mkdir(exist_ok=True)
        cli.write_text("#!/bin/sh\nexit 99\n")
        cli.chmod(0o755)
        auth = self.root / "codex-home" / "auth.json"
        auth.parent.mkdir(exist_ok=True)
        auth.write_text(json.dumps({"tokens": {"access_token": "nicht-echt"}}))
        self.traeger = self.make(dataclasses.replace(konfig, registry=str(registry),
                                                     codex={"cli": str(cli), "auth": str(auth)}))
        with aufbau_herkunft(ad) as aufbau:
            ad.create_agent_from_draft(self.world, {"id": "cx", "specialty": "Codex",
                                                   "model": "codex-gpt-5-5:high", "tools": ["Read"]}, aufbau)
        self.ticket("c1", agent="cx")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        lauf, entry = self.laeufe[run_id], self.traeger._zuege_lesen()["runs"][run_id]
        baum = (konfig.agents_dir / "cx" / "work").resolve() / "cx"
        self.assertIsInstance(lauf.zug, acx.CodexZug)
        self.assertEqual((entry["harness"], entry["worktree"]), ("codex", str(baum)))
        env = self.zug_git_umgebung(lauf)
        self.assertEqual(self.paare(env)["user.email"], PERSON[1])
        import agents_codex_runner as acxr
        _argv, kindumgebung = acxr.command(lauf.zug.as_dict(), "http://127.0.0.1:9/v1")
        self.assertEqual({k: v for k, v in kindumgebung.items() if k.startswith("GIT_")}, env)
        self.assertEqual(self.commit_mit(baum, env, "codex.txt"), "%s <%s>" % PERSON)

    def test_review_turn_of_a_pi_agent_reads_the_revision_and_gets_no_identity(self):
        projekt, konfig = self.git_welt_mit_pruefer("gitpruef")
        self.identitaet_setzen(projekt)
        self.traeger = self.make(dataclasses.replace(self.traeger.konfig,
                                                     pi={"node": "/usr/bin/node", "cli": "/opt/pi/cli.js",
                                                         "base_url": "http://127.0.0.1:11570",
                                                         "modelle": dict(PI_MODELLE)}))
        self.traeger._lokal_frei_pruefer = lambda _url: True
        ad.update_agent_profile(self.world, "a2", {"model": "lmgamma"}, "mensch")
        self.reif_mit_commit()
        baum_a1 = (konfig.agents_dir / "a1" / "work").resolve() / "a1"
        ad.review_ticket(self.world, "t-a", "a2", sender="haupt", claimed_role="hauptagent")
        started = [item for item in self.traeger.einmal()["gestartet"] if item["agent"] == "a2"]
        self.assertEqual([item["art"] for item in started], ["pruefung"])
        lauf = self.laeufe[started[0]["run"]]
        self.assertIsInstance(lauf.zug, ap.PiZug)
        env = self.zug_git_umgebung(lauf)
        # Nur die geprüfte Revision, keine Identitaet: ein Pruefzug committet nicht.
        self.assertEqual(env, {"GIT_DIR": str(aw.verwaltung(projekt.resolve() / ".git", baum_a1))})
        self.assertEqual(lauf.git_einbindung["schreiben"], [])

    def test_a_carrier_host_without_git_identity_runs_without_a_worktree(self):
        projekt, konfig = self.pi_welt("gitlos")
        self.traeger._lokal_frei_pruefer = lambda _url: True
        self.git(projekt, "config", "--unset", "user.name")
        leer = self.root / "leeres-home"
        leer.mkdir()
        umgebung = {"HOME": str(leer), "PATH": os.environ.get("PATH", ""), "GIT_CONFIG_NOSYSTEM": "1"}
        with mock.patch.object(aw, "_umgebung", return_value=umgebung):
            self.ticket("g2", agent="lokal")
            run_id = self.traeger.einmal()["gestartet"][0]["run"]
        lauf, entry = self.laeufe[run_id], self.traeger._zuege_lesen()["runs"][run_id]
        self.assertIsNone(entry["worktree"])
        self.assertIn("keine brauchbare git-Identitaet", entry["worktree_fehler"])
        self.assertEqual(lauf.workspace, konfig.agents_dir / "lokal" / "work")
        self.assertEqual(self.zug_git_umgebung(lauf), {})
        self.assertIsNone(lauf.git_einbindung)

    def test_a_stale_lock_of_a_broken_turn_does_not_block_the_next_turn(self):
        projekt, konfig = self.pi_welt("gitsperre")
        self.traeger._lokal_frei_pruefer = lambda _url: True
        self.ticket("g3", agent="lokal")
        erster = self.traeger.einmal()["gestartet"][0]["run"]
        baum = (konfig.agents_dir / "lokal" / "work").resolve() / "lokal"
        admin = aw.verwaltung(projekt.resolve() / ".git", baum)
        # Der Zug wird mitten in `git add` gestoppt und laesst seine Sperrdatei liegen.
        (admin / "index.lock").write_text("")
        self.traeger.agent_stoppen("lokal", "Sofortstopp", absender="haupt")
        self.assertEqual(self.traeger.einmal()["beendet"][0]["outcome"], "gestoppt")
        self.traeger.agent_fortsetzen("lokal", absender="haupt")
        zweiter = self.traeger.einmal()["gestartet"][0]["run"]
        entry = self.traeger._zuege_lesen()["runs"][zweiter]
        self.assertEqual(entry["worktree_geraeumt"], [str(admin / "index.lock")])
        self.assertFalse((admin / "index.lock").exists())
        self.assertEqual(self.commit_mit(baum, self.zug_git_umgebung(self.laeufe[zweiter]), "nach-sperre.txt"),
                         "%s <%s>" % PERSON)
        self.assertNotEqual(erster, zweiter)


class FallbackZugTests(Basis):
    """Der Zug ueber den Fallback: echter Belegt-Pruefer, Denkstufe, Worktree, nie Fable."""

    def test_default_busy_check_uses_a_real_loopback_connection(self):
        with socket.socket() as server:
            server.bind(("127.0.0.1", 0))
            server.listen(1)
            port = int(server.getsockname()[1])
            self.assertTrue(at._lokal_erreichbar("http://127.0.0.1:%d" % port))
        self.assertFalse(at._lokal_erreichbar("http://127.0.0.1:%d" % port, timeout=1.0))

    def test_busy_local_server_falls_back_over_the_default_checker_and_keeps_the_worktree(self):
        server = socket.socket()
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        port = int(server.getsockname()[1])
        self.addCleanup(server.close)
        projekt, konfig = self.pi_welt("gitfallback", base_url="http://127.0.0.1:%d" % port, fallback=MODEL)
        # Kein Stellvertreter: der Traeger prueft den Port selbst (agents_traeger._lokal_erreichbar).
        self.assertIs(self.traeger._lokal_frei_pruefer, at._lokal_erreichbar)
        self.ticket("f1", agent="lokal")
        erster = self.traeger.einmal()["gestartet"][0]["run"]
        self.assertEqual(self.traeger._zuege_lesen()["runs"][erster]["modellwahl"],
                         {"profil": "lmgamma", "modell": "lmgamma", "harness": "pi", "fallback": False, "grund": None})
        self.finish(erster, "fertig")
        self.traeger.einmal()
        # Der lokale Server ist weg: derselbe Agent faehrt den Fallback in der Cloud, im selben Worktree.
        server.close()
        self.ticket("f2", agent="lokal")
        zweiter = self.traeger.einmal()["gestartet"][0]["run"]
        lauf, entry = self.laeufe[zweiter], self.traeger._zuege_lesen()["runs"][zweiter]
        self.assertEqual(entry["modellwahl"], {"profil": "lmgamma", "modell": MODEL, "harness": "claude",
                                               "fallback": True, "grund": "belegt"})
        baum = (konfig.agents_dir / "lokal" / "work").resolve() / "lokal"
        self.assertEqual((entry["harness"], entry["worktree"], lauf.workspace), ("claude", str(baum), baum))
        self.assertEqual(self.paare(self.zug_git_umgebung(lauf))["user.name"], PERSON[0])
        self.assertEqual(self.traeger.status()["agenten"]["lokal"]["modellwahl"]["grund"], "belegt")
        self.assertEqual(self.commit_mit(baum, self.zug_git_umgebung(lauf), "fallback.txt"), "%s <%s>" % PERSON)

    def test_the_fallback_carries_its_own_thinking_level_into_the_turn(self):
        ad.update_agent_profile(self.world, "a1", {"model": MODEL, "effort": "low",
                                                   "fallback_model": "claude-sonnet-5",
                                                   "fallback_effort": "high"}, "mensch")
        # Der Harness scheitert vor dem Start; ein Launcherfehler nach dem Start bliebe dagegen ungeklaert.
        echte_fabrik = self.traeger._zug_fabrik

        def scheitert(*args, **kwargs):
            self.traeger._zug_fabrik = echte_fabrik
            raise at.TraegerFehler("Harness startet nicht")
        self.traeger._zug_fabrik = scheitert
        self.ticket("t1")
        erste = self.traeger.einmal()
        (kaputt,) = [e for e in self.traeger._zuege_lesen()["runs"].values() if e["outcome"] == "startfehler"]
        self.assertEqual((kaputt["agent"], kaputt["modellwahl"]["fallback"]), ("a1", False))
        run_id = (erste["gestartet"] or self.traeger.einmal()["gestartet"])[0]["run"]
        lauf, entry = self.laeufe[run_id], self.traeger._zuege_lesen()["runs"][run_id]
        self.assertEqual((entry["model"], entry["modellwahl"]["grund"]), ("claude-sonnet-5", "startfehler"))
        self.assertEqual(entry["denkstufe"]["angefragt"], "high")
        self.assertEqual(lauf.zug.effort, entry["denkstufe"]["wirksam"])
        self.assertIsNotNone(lauf.zug.effort)

    def test_fable_is_never_chosen_as_a_fallback(self):
        pfad = self.world / "agents" / "a1" / "agent.json"
        daten = json.loads(pfad.read_text())
        # Die Datenschicht weist Fable schon beim Anlegen ab; hier steht es trotzdem im Profil.
        daten["model_profile"] = dict(daten["model_profile"], fallback_model="claude-fable-5-1")
        pfad.write_text(json.dumps(daten))
        agent = ad.read_agent(self.world, "a1")
        self.assertEqual(self.traeger.fallback_agent(agent), (None, "fallback_fable_verboten"))
        self.ticket("t1")
        erster = self.traeger.einmal()["gestartet"][0]["run"]
        self.finish(erster, stream=self.abgewiesen(429, resets_at=int(self.traeger._now() + 3600)))
        beendet = self.traeger.einmal()["beendet"][0]
        self.assertEqual((beendet["outcome"], beendet["folge"]["fallback"]["grund"]),
                         ("kontingent", "fallback_fable_verboten"))
        weiter = self.traeger.einmal()
        self.assertEqual(weiter["gestartet"], [])
        self.assertEqual(self.traeger._zuege_lesen()["schlaf"]["a1"]["grund"], "kontingent")
        for entry in self.traeger._zuege_lesen()["runs"].values():
            self.assertNotIn("fable", str(entry["model"]).lower())


if __name__ == "__main__":
    unittest.main()
