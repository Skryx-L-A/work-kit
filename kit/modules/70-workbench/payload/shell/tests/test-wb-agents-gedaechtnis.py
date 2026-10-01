#!/usr/bin/env python3
"""Gedaechtnis mit Obergrenze und Brain je Agent (Entscheidung vom 16.09.2026, docs/AGENTS-PLAN.md Abschnitt 16).

Alles laeuft in einem Wegwerf-Kbase mit Attrappen-Remote (nacktes git-Repository im Testordner); das echte
``~/work/brain`` wird weder gelesen noch beschrieben.
"""

from __future__ import annotations

import importlib.util
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

SHELL = Path(__file__).resolve().parents[1]
REPO = SHELL.parent
sys.path.insert(0, str(SHELL))
sys.path.insert(0, str(REPO / "hooks" / "lib"))

import agents_brain as ab  # noqa: E402
import agents_claude as ac  # noqa: E402
import agents_controller as actl  # noqa: E402
import agents_data as ad  # noqa: E402
import agents_gedaechtnis as ag  # noqa: E402
import agents_lauf as al  # noqa: E402
import agents_skills as sk  # noqa: E402
import agents_traeger as at  # noqa: E402
import profil_sperre as ps  # noqa: E402
from herkunft_fixture import aufbau_herkunft, gemessener_mensch  # noqa: E402

_spec = importlib.util.spec_from_file_location("traeger_hilfen", Path(__file__).with_name("test-wb-agents-traeger.py"))
traeger_hilfen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(traeger_hilfen)

ULID_RE = re.compile(r"^[0-9A-HJKMNP-TV-Z]{26}$")
LEHRE = "- 2026-09-15: %s Lehre mit etwas Hergang, damit die Zeile Laenge hat. Grund: Beleg aus Zug %d."
MODEL = "claude-haiku-4-5-20251001"

_MESSER = gemessener_mensch(ad)


def setUpModule():
    _MESSER.start()


def tearDownModule():
    _MESSER.stop()


def git(cwd, *args, check=True):
    result = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True,
                            env={k: v for k, v in os.environ.items() if not k.startswith("GIT_")})
    if check and result.returncode != 0:
        raise AssertionError("git %s: %s" % (" ".join(args), result.stderr))
    return result.stdout.strip()


def memory_mit(n, laenge=40):
    lessons = [LEHRE % ("x" * laenge, i) for i in range(1, n + 1)]
    return "# a1 – Gedächtnis\n\n## Lehren\n\n" + "\n".join(lessons) + "\n", lessons


class Grundlage(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-gedaechtnis-")
        self.root = Path(self.tmp.name).resolve()
        os.chmod(self.root, 0o700)
        self.env = mock.patch.dict(os.environ, {"WB_AGENTS_ZUSTAND": str(self.root / "zustand-autostart"),
                                                "WB_AGENTS_UNIT_DIR": str(self.root / "units"),
                                                "WB_BRAIN_KBASE": ""})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.world = self.root / "myproject" / ".werkbank" / "agents"
        with aufbau_herkunft(ad) as aufbau:
            ad.create_world(self.world, name="Gedaechtnisprobe", main_name="haupt", sender=aufbau)
            for agent in ("a1", "a2"):
                ad.create_agent_from_draft(self.world, {"id": agent, "stage": "mitglied", "specialty": "Probe",
                                                        "tools": ["Bash", "Read", "Grep", "Glob"],
                                                        "model": MODEL}, aufbau)
        self.kbase = self.root / "kbase"
        self.remote = self.root / "remote.git"
        self._kbase_anlegen()

    def tearDown(self):
        self.tmp.cleanup()

    def controller_beenden(self, controller, client):
        """Dienstfaden ueber sein eigenes Gegenstueck beenden, dann erst den Controller.

        ``AgentController`` startet je Bindung einen Faden ohne ``daemon``-Flag, und
        ``close()`` schliesst den Serversocket aus dem Hauptfaden heraus. Steht der Dienstfaden
        in diesem Moment im ``poll`` auf derselben Dateinummer, weckt ihn das nicht mehr: die
        Nummer wird gleich darauf von einer Pipe eines ``git``-Unterprozesses belegt, und der
        Faden wartet bis zum Sitzungszeitlimit (300 s). Der Interpreter haengt dann nach dem
        letzten Test in ``threading._shutdown``. Wird stattdessen das Klientenende geschlossen,
        liest der Dienstfaden ein EOF, beendet sich und schliesst seinen Socket selbst.
        """
        client.close()
        controller.join(10.0)
        controller.close()

    def _kbase_anlegen(self):
        v = self.kbase
        (v / "20-projects" / "myproject").mkdir(parents=True)
        (v / "10-global").mkdir()
        (v / "90-secrets").mkdir()
        (v / "20-projects" / "myproject" / "hostco-box.md").write_text(
            "---\ntitle: hostco-box\ntype: note\n---\n\nAcme Box bei Hostco in Falkenstein, CX23.\n")
        (v / "10-global" / "regeln.md").write_text("---\ntitle: Regeln\ntype: note\n---\n\nAllgemeine Regeln.\n")
        (v / "90-secrets" / "hostco.md").write_text("Hostco Box Zugang geheim\n")
        (v / ".gitignore").write_text("90-secrets/\n")
        git(self.root, "init", "-q", "--bare", "-b", "main", str(self.remote))
        git(v, "init", "-q", "-b", "main")
        git(v, "config", "user.name", "Mensch Test")
        git(v, "config", "user.email", "mensch@example.invalid")
        git(v, "add", "-A")
        git(v, "commit", "-q", "-m", "start")
        git(v, "remote", "add", "origin", str(self.remote))
        git(v, "push", "-q", "-u", "origin", "main")

    def lehren_pfad(self, agent="a1"):
        return self.kbase / "20-projects" / "myproject" / "agenten" / agent / "lehren.md"

    def memory(self, agent="a1"):
        return (self.world / "agents" / agent / "MEMORY.md").read_text(encoding="utf-8")

    def write_memory(self, text, agent="a1"):
        (self.world / "agents" / agent / "MEMORY.md").write_text(text, encoding="utf-8")

    def run_dir(self, name, step):
        folder = self.root / "zuege" / name
        folder.mkdir(parents=True)
        (folder / sk.LEARN_FILE).write_text(json.dumps(step), encoding="utf-8")
        return folder

    def remote_log(self):
        return git(self.remote, "log", "--format=%an|%s", "main").splitlines()


class GrenzeUndArchiv(Grundlage):
    def test_obergrenze_gemessen_unter_dem_kopf_und_lehre_ueber_der_grenze_markiert(self):
        self.assertEqual(ag.messen(ag.vorlage("a1")), {"zeichen": 0, "zeilen": 0, "ueber_grenze": False})
        self.assertIn(ag.KOPF_SATZ, self.memory())
        kopf = "# a1 – Gedächtnis\n\n%s\n\n" % ag.KOPF_SATZ
        self.assertFalse(ag.messen(kopf + "x" * 2000 + "\n")["ueber_grenze"])
        self.assertTrue(ag.messen(kopf + "x" * 2001 + "\n")["ueber_grenze"])
        self.assertFalse(ag.messen(kopf + "\n".join("- %d" % i for i in range(15)) + "\n")["ueber_grenze"])
        self.assertTrue(ag.messen(kopf + "\n".join("- %d" % i for i in range(16)) + "\n")["ueber_grenze"])
        text, _ = memory_mit(14)
        self.write_memory(text)
        self.assertEqual(ag.messen(text)["zeilen"], 15)
        result = sk.lernschritt_anwenden(self.world, "a1", self.run_dir("z1", {
            "art": "lehre", "text": "Eine Lehre zu viel.", "grund": "Probe"}), date="2026-09-16")
        # Die Lehre geht nicht verloren; die Grenze erzwingt der Traeger mit dem Posten "Gedaechtnis kuerzen".
        self.assertEqual((result["status"], result.get("ueber_grenze")), ("angewendet", True))
        self.assertTrue(self.memory().startswith("# a1 – Gedächtnis\n\n%s\n\n## Lehren\n" % ag.KOPF_SATZ))
        self.assertIsNotNone(ag.ueber_grenze(self.world, "a1"))
        # Die alte Notbremse in Bytes gilt weiter.
        self.write_memory("# a1\n\n" + "x" * sk.MEMORY_LIMIT)
        voll = sk.lernschritt_anwenden(self.world, "a1", self.run_dir("z2", {"art": "lehre", "text": "N.", "grund": "g"}))
        self.assertEqual(voll["status"], "abgewiesen")

    def test_archiv_verschiebt_zeilen_ins_brain_und_kuerzt_das_gedaechtnis(self):
        text, lessons = memory_mit(10, 200)
        self.write_memory(text)
        self.assertTrue(ag.messen(text)["ueber_grenze"])
        step = {"art": "archiv", "zeilen": list(range(2, 10)), "neu": ["Regel in einem Satz."], "grund": "Grenze"}
        result = sk.lernschritt_anwenden(self.world, "a1", self.run_dir("zug-archiv", step), date="2026-09-16",
                                         brain=self.kbase)
        self.assertEqual(result["status"], "angewendet", result)
        self.assertEqual((result["verschoben"], result["ueber_grenze"]), (8, False))
        self.assertEqual(result["brain"]["rel"], "20-projects/myproject/agenten/a1/lehren.md")
        self.assertEqual(result["brain"]["sync"]["status"], "gepusht")
        memory = self.memory()
        self.assertTrue(memory.startswith("# a1 – Gedächtnis\n\n%s\n" % ag.KOPF_SATZ))
        for lesson in lessons[:8]:
            self.assertNotIn(lesson, memory)
        for lesson in lessons[8:]:
            self.assertIn(lesson, memory)
        self.assertIn("- Regel in einem Satz.", memory)
        self.assertFalse(ag.messen(memory)["ueber_grenze"])
        archive = self.lehren_pfad().read_text(encoding="utf-8")
        positions = [archive.index(lesson) for lesson in lessons[:8]]
        self.assertEqual(positions, sorted(positions), "Lehren bleiben chronologisch")
        self.assertIn("## Archiviert 2026-09-16", archive)
        self.assertIn("<!-- wb-zug: zug-archiv -->", archive)
        self.assertEqual(self.remote_log()[0], "Mensch Test|agents: archive memory of Gedaechtnisprobe/a1 into "
                                               "20-projects/myproject/agenten/a1/lehren.md")
        # Derselbe Zug ein zweites Mal: nichts doppelt.
        again = sk.lernschritt_anwenden(self.world, "a1", self.root / "zuege" / "zug-archiv", brain=self.kbase)
        self.assertEqual(again["status"], "angewendet")
        self.assertEqual(self.lehren_pfad().read_text(encoding="utf-8"), archive)
        self.assertEqual(len(self.remote_log()), 2)

    def test_archiv_ohne_brain_oder_mit_falscher_zeile_aendert_nichts(self):
        text, _ = memory_mit(16)
        self.write_memory(text)
        ohne = sk.lernschritt_anwenden(self.world, "a1", self.run_dir("z1", {"art": "archiv", "zeilen": [2],
                                                                             "grund": "g"}))
        self.assertEqual(ohne["status"], "abgewiesen")
        ueberschrift = sk.lernschritt_anwenden(self.world, "a1", self.run_dir("z2", {"art": "archiv", "zeilen": [1],
                                                                                     "grund": "g"}), brain=self.kbase)
        self.assertEqual(ueberschrift["status"], "abgewiesen")
        self.assertIn("Ueberschriften", ueberschrift["fehler"])
        git(self.kbase, "config", "--unset", "user.email")
        with mock.patch.dict(os.environ, {"GIT_CONFIG_GLOBAL": str(self.root / "keine-gitconfig"),
                                          "HOME": str(self.root)}):
            ohne_identitaet = sk.lernschritt_anwenden(self.world, "a1", self.run_dir("z3", {
                "art": "archiv", "zeilen": [2, 3], "grund": "g"}), brain=self.kbase)
        self.assertEqual(ohne_identitaet["status"], "abgewiesen")
        self.assertIn("Identitaet", ohne_identitaet["fehler"])
        self.assertEqual(self.memory(), text)
        self.assertFalse(self.lehren_pfad().exists())
        ungueltig = sk.lernschritt_anwenden(self.world, "a1", self.run_dir("z4", {"art": "archiv", "zeilen": []}))
        self.assertEqual(ungueltig["status"], "ungueltig")

    def test_bestand_behaelt_die_letzten_fuenf_lehren_und_meldet_die_groesse(self):
        text, lessons = memory_mit(9, 400)
        self.write_memory(text)
        (self.world / "traeger.json").write_text(json.dumps({"brain": {"kbase": str(self.kbase)}}))
        env = dict(os.environ, PATH="%s:%s" % (Path(sys.executable).parent, os.environ.get("PATH", "")))
        out = subprocess.run(["sh", str(SHELL / "wb-welt"), "gedaechtnis", str(self.world), "a1", "--archivieren",
                              "--json"], capture_output=True, text=True, env=env, timeout=120)
        self.assertEqual(out.returncode, 0, out.stderr)
        report = json.loads(out.stdout)[0]
        self.assertEqual((report["agent"], report["verschoben"]), ("a1", 4))
        self.assertEqual(report["vorher"]["zeilen"], 10)
        self.assertEqual(report["nachher"]["zeilen"], 6)
        self.assertEqual(report["gedaechtnis"]["brain_pfad"], str(self.kbase / "20-projects/myproject/agenten/a1"))
        self.assertEqual(report["brain"]["sync"]["status"], "gepusht")
        self.assertEqual(ag.lehren(self.memory()), lessons[4:])
        archive = self.lehren_pfad().read_text(encoding="utf-8")
        self.assertTrue(all(lesson in archive for lesson in lessons[:4]))
        history = json.loads((self.world / "agents" / "a1" / "history.json").read_text())["entries"]
        self.assertEqual(history[-1]["event"], "gedaechtnis-archiv")
        ansicht = subprocess.run(["sh", str(SHELL / "wb-welt"), "gedaechtnis", str(self.world)], capture_output=True,
                                 text=True, env=env, timeout=60)
        self.assertIn("a1: %d Zeichen, 6 Zeilen (Grenze 2000/15)" % report["nachher"]["zeichen"], ansicht.stdout)

    def test_ansicht_liefert_groesse_grenze_und_brain_pfad(self):
        (self.world / "traeger.json").write_text(json.dumps({"brain": {"kbase": str(self.kbase)}}))
        text, _ = memory_mit(3)
        self.write_memory(text)
        snapshot = ad.world_snapshot(self.world)
        agent = next(item for item in snapshot["agents"] if item["id"] == "a1")
        self.assertEqual(agent["gedaechtnis"], {"zeichen": ag.messen(text)["zeichen"], "zeilen": 4,
                                                "grenze": {"zeichen": 2000, "zeilen": 15}, "ueber_grenze": False,
                                                "brain_bereich": "20-projects/myproject/agenten/a1",
                                                "brain_pfad": str(self.kbase / "20-projects/myproject/agenten/a1")})


class NotizUndSuche(Grundlage):
    def client(self, agent="a1", role="mitglied", kbase="standard"):
        controller = actl.AgentController(self.world, "zug-probe", lambda _binding: True,
                                          brain_kbase=self.kbase if kbase == "standard" else kbase)
        client = controller.bind_agent(agent, role)
        self.addCleanup(self.controller_beenden, controller, client)
        return client

    def test_notiz_schreibt_nur_im_eigenen_ordner_und_ausbruch_wird_abgewiesen(self):
        client = self.client()
        result = client.request("brain.notiz", {"titel": "../../../10-global/boese", "text": "Hergang der Klaerung."})
        self.assertEqual(result["rel"], "20-projects/myproject/agenten/a1/10-global-boese.md")
        self.assertEqual(result["status"], "angelegt")
        self.assertEqual(sorted(p.name for p in (self.kbase / "10-global").iterdir()), ["regeln.md"])
        for payload, needle in (
                ({"titel": "x", "text": "y", "bereich": "projekt"}, "nur der Hauptagent"),
                ({"titel": "x", "text": "y", "pfad": "10-global/x.md"}, "Unbekannte Payloadfelder"),
                ({"titel": "Schluessel", "text": "token sk-ant-api03-abcdefghijk"}, "Zugangsschluessel"),
                ({"titel": "lehren", "text": "y"}, "lehren.md"),
                ({"titel": "../../../10-global/boese", "text": "noch einmal"}, "existiert")):
            with self.assertRaises(actl.ControllerError) as caught:
                client.request("brain.notiz", payload)
            self.assertIn(needle, str(caught.exception))
        # Ein Symlink im Bereich eines anderen Agenten fuehrt nicht hinaus.
        agenten = self.kbase / "20-projects" / "myproject" / "agenten"
        (agenten / "a2").symlink_to(self.kbase / "10-global", target_is_directory=True)
        with self.assertRaises(actl.ControllerError) as caught:
            self.client("a2").request("brain.notiz", {"titel": "Ausbruch", "text": "y"})
        self.assertIn("Symlink", str(caught.exception))
        self.assertFalse((self.kbase / "10-global" / "ausbruch.md").exists())
        (agenten / "a2").unlink()
        with self.assertRaises(actl.ControllerError) as caught:
            self.client(kbase=None).request("brain.notiz", {"titel": "x", "text": "y"})
        self.assertIn("Kein Brain-Kbase", str(caught.exception))
        # Der Hauptagent schreibt zusaetzlich in das Projekt, ebenfalls nur ueber den Dienstweg.
        haupt = self.client("haupt", "hauptagent").request("brain.notiz", {
            "titel": "Entscheidung Postfach", "text": "Postfach bleibt lesend.", "bereich": "projekt"})
        self.assertEqual(haupt["rel"], "20-projects/myproject/entscheidung-postfach.md")
        self.assertEqual(git(self.kbase, "status", "--porcelain"), "")

    def test_thema_haengt_datierte_eintraege_an_und_frontmatter_ist_gueltig(self):
        client = self.client()
        first = client.request("brain.notiz", {"titel": "Zugang geprueft", "text": "Erster Befund.\nZweite Zeile.",
                                               "thema": "Hostco Box"})
        second = client.request("brain.notiz", {"titel": "Neustart", "text": "Zweiter Befund.", "thema": "Hostco Box",
                                                "anhaengen": True})
        self.assertEqual((first["status"], second["status"]), ("angelegt", "angehaengt"))
        self.assertEqual(first["rel"], "20-projects/myproject/agenten/a1/hostco-box.md")
        text = (self.kbase / first["rel"]).read_text(encoding="utf-8")
        fm = ab.frontmatter_lesen(text)
        self.assertIsNotNone(fm)
        block = text.split("---\n")[1].splitlines()
        self.assertEqual(len(block), len({line.split(":", 1)[0] for line in block}), "keine doppelten Schluessel")
        self.assertRegex(fm["id"], ULID_RE)
        self.assertEqual((fm["schema"], fm["type"], fm["class"], fm["branch"]),
                         ("4", "note", "knowledge", "20-projects/myproject"))
        self.assertEqual(json.loads(fm["title"]), "Hostco Box")
        self.assertEqual(fm["permalink"], "main/20-projects/myproject/agenten/a1/hostco-box")
        self.assertEqual(fm["tags"], "[agenten, welt-gedaechtnisprobe, agent-a1]")
        self.assertRegex(fm["created"], r"^\d{4}-\d{2}-\d{2}$")
        self.assertRegex(fm["stand"], r"^\d{4}-\d{2}$")
        self.assertIn("Für künftige Sessions:", text)
        self.assertLess(text.index("Zugang geprueft"), text.index("Neustart"))
        self.assertRegex(text, r"## \d{4}-\d{2}-\d{2}: Neustart")
        self.assertEqual(ab.frontmatter_lesen(text)["id"], fm["id"], "Anhaengen behaelt die Identitaet")

    def test_commit_und_push_mit_attrappen_remote_nie_force(self):
        client = self.client()
        first = client.request("brain.notiz", {"titel": "Erste Notiz", "text": "Inhalt."})
        self.assertEqual(first["sync"], {"status": "gepusht", "weg": "git pull --rebase"})
        self.assertEqual(self.remote_log()[0], "Mensch Test|agents: note 20-projects/myproject/agenten/a1/erste-notiz.md "
                                               "from Gedaechtnisprobe/a1")
        self.assertEqual(first["commit"], git(self.remote, "rev-parse", "main"))
        # Der Upstream ist weiter (andere Maschine): pull --rebase holt ihn, dann push.
        klon = self.root / "klon"
        git(self.root, "clone", "-q", str(self.remote), str(klon))
        git(klon, "config", "user.name", "Andere Maschine")
        git(klon, "config", "user.email", "andere@example.invalid")
        (klon / "10-global" / "fremd.md").write_text("fremd\n")
        git(klon, "add", "-A")
        git(klon, "commit", "-q", "-m", "fremd")
        git(klon, "push", "-q")
        second = client.request("brain.notiz", {"titel": "Zweite Notiz", "text": "Inhalt."})
        self.assertEqual(second["sync"]["status"], "gepusht")
        self.assertEqual([line.split("|")[1] for line in self.remote_log()[:3]],
                         ["agents: note 20-projects/myproject/agenten/a1/zweite-notiz.md from Gedaechtnisprobe/a1",
                          "fremd", "agents: note 20-projects/myproject/agenten/a1/erste-notiz.md from Gedaechtnisprobe/a1"])
        # Fremde, nicht committete Aenderung im Kbase: nur der eigene Pfad wird committet, der Abgleich bleibt aus.
        (self.kbase / "10-global" / "regeln.md").write_text("vom Menschen geaendert\n")
        third = client.request("brain.notiz", {"titel": "Dritte Notiz", "text": "Inhalt."})
        self.assertEqual(third["sync"]["status"], "lokal")
        self.assertIn("pull --rebase", third["sync"]["grund"])
        self.assertEqual(git(self.kbase, "status", "--porcelain"), "M 10-global/regeln.md")
        self.assertIn("dritte-notiz.md", git(self.kbase, "log", "-1", "--name-only", "--format="))
        git(self.kbase, "checkout", "--", "10-global/regeln.md")
        # Remote weg: der Commit bleibt lokal, der Status nennt es; danach holt die naechste Notiz alles nach.
        self.remote.rename(self.root / "remote-weg.git")
        fourth = client.request("brain.notiz", {"titel": "Vierte Notiz", "text": "Inhalt."})
        self.assertEqual(fourth["sync"]["status"], "lokal")
        self.assertIn("fetch", fourth["sync"]["grund"])
        (self.root / "remote-weg.git").rename(self.remote)
        fifth = client.request("brain.notiz", {"titel": "Fuenfte Notiz", "text": "Inhalt."})
        self.assertEqual(fifth["sync"]["status"], "gepusht")
        self.assertEqual(git(self.kbase, "rev-parse", "HEAD"), git(self.remote, "rev-parse", "main"))
        # Merge-Commit in der eigenen Historie: fetch und merge --ff-only statt rebase.
        git(self.kbase, "checkout", "-q", "-b", "seite")
        (self.kbase / "10-global" / "seite.md").write_text("seite\n")
        git(self.kbase, "add", "-A")
        git(self.kbase, "commit", "-q", "-m", "seite")
        git(self.kbase, "checkout", "-q", "main")
        git(self.kbase, "merge", "-q", "--no-ff", "-m", "merge seite", "seite")
        sixth = client.request("brain.notiz", {"titel": "Sechste Notiz", "text": "Inhalt."})
        self.assertEqual(sixth["sync"], {"status": "gepusht", "weg": "git fetch && git merge --ff-only"})
        self.assertEqual(git(self.kbase, "rev-parse", "HEAD"), git(self.remote, "rev-parse", "main"))
        self.assertEqual(git(self.remote, "rev-list", "--merges", "--count", "main"), "1")

    def test_suche_liefert_treffer_aus_dem_wegwerf_kbase_ohne_geheimordner(self):
        client = self.client()
        client.request("brain.notiz", {"titel": "Hostco Neustart", "text": "Box neu gestartet, Dienst lief wieder."})
        alles = client.request("brain.suche", {"frage": "Hostco Box", "k": 5, "bereich": "alles"})
        rels = [hit["rel"] for hit in alles["treffer"]]
        self.assertIn("20-projects/myproject/hostco-box.md", rels)
        self.assertIn("20-projects/myproject/agenten/a1/hostco-neustart.md", rels)
        self.assertFalse(any(rel.startswith("90-secrets") for rel in rels))
        self.assertEqual(alles["quelle"], "stichwort")
        eigen = client.request("brain.suche", {"frage": "Hostco", "bereich": "eigen"})
        self.assertEqual([hit["rel"] for hit in eigen["treffer"]], ["20-projects/myproject/agenten/a1/hostco-neustart.md"])
        self.assertEqual(eigen["pfad"], "20-projects/myproject/agenten/a1")
        welt = client.request("brain.suche", {"frage": "Regeln Hostco", "bereich": "welt"})
        self.assertTrue(welt["treffer"] and all(hit["rel"].startswith("20-projects/myproject/") for hit in welt["treffer"]))
        with self.assertRaises(actl.ControllerError):
            client.request("brain.suche", {"frage": "x", "k": True})
        with self.assertRaises(actl.ControllerError):
            client.request("brain.suche", {"frage": "x", "bereich": "90-secrets"})
        # Mit dem Werkzeug des Kbases: seine Treffer, ein Geheimordner-Treffer faellt heraus.
        tool = self.kbase / ab.WERKZEUG_REL
        tool.parent.mkdir(parents=True)
        tool.write_text("#!%s\nimport json\nprint(json.dumps({'fallback': True, 'hits': [\n"
                        " {'rel': '90-secrets/hostco.md', 'title': 'geheim', 'score': 1.0, 'snippet': 'x'},\n"
                        " {'rel': '20-projects/myproject/hostco-box.md', 'title': 'hostco-box', 'score': 0.9,"
                        " 'snippet': 'Box', 'match': 'text'}]}))\n" % sys.executable)
        tool.chmod(0o755)
        werkzeug = ab.suche(self.kbase, self.world, "a1", "Hostco", 5, "alles")
        self.assertEqual(werkzeug["quelle"], "brain search (ohne Einbettungen)")
        self.assertEqual([hit["rel"] for hit in werkzeug["treffer"]], ["20-projects/myproject/hostco-box.md"])

    def test_huelle_im_zug_nur_search_mit_pfad_und_rueckfall(self):
        runtime = self.root / "runtime"
        (runtime / at.BRAIN_BIN).mkdir(parents=True)
        for name in ("agents_brain.py", "agents_data.py", "atomar_schreiben.py"):
            (runtime / name).write_bytes((SHELL / name).read_bytes())
        huelle = runtime / at.BRAIN_BIN / "brain"
        huelle.write_text(ab.HUELLE)
        env = {"WB_BRAIN_KBASE": str(self.kbase), "PATH": "/usr/bin:/bin", "HOME": str(self.root)}
        out = subprocess.run([sys.executable, str(huelle), "search", "Hostco Box", "-k", "3"], capture_output=True,
                             text=True, env=env, timeout=60)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("20-projects/myproject/hostco-box.md", out.stdout)
        self.assertIn("Stichwortsuche", out.stdout)
        self.assertNotIn("90-secrets", out.stdout)
        pfad = subprocess.run([sys.executable, str(huelle), "search", "Regeln", "--pfad", "10-global", "--json"],
                              capture_output=True, text=True, env=env, timeout=60)
        self.assertEqual([hit["rel"] for hit in json.loads(pfad.stdout)["hits"]], ["10-global/regeln.md"])
        for args in (["ingest", "x"], ["search", "x", "--pfad", "90-secrets"], ["search", "x", "--pfad", "/etc"]):
            result = subprocess.run([sys.executable, str(huelle), *args], capture_output=True, text=True, env=env,
                                    timeout=60)
            self.assertEqual(result.returncode, 2, args)
        self.assertEqual(ab.huelle(["--kbase", "/", "search", "x"], out=io.StringIO()), 2)

    def test_einbindung_bindet_kbase_python_installation_und_versionslink(self):
        pythons = self.root / "uv-python"
        (pythons / "cpython-3.13.14-linux").mkdir(parents=True)
        (pythons / "cpython-3.13-linux").symlink_to(pythons / "cpython-3.13.14-linux", target_is_directory=True)
        venv = self.kbase / "_meta/tools/braincli/.venv"
        (venv / "bin").mkdir(parents=True)
        (venv / "bin" / "brain").write_text("#!/bin/sh\n")
        (venv / "pyvenv.cfg").write_text("home = %s\nversion_info = 3.13\n" % (pythons / "cpython-3.13-linux" / "bin"))
        info = ab.einbindung(self.kbase)
        self.assertEqual(info["lese_pfade"], (self.kbase, pythons, pythons / "cpython-3.13.14-linux"))
        self.assertEqual(info["verdeckt"], (self.kbase / "90-secrets", self.kbase / ".secrets-sync"))
        self.assertEqual(info["werkzeug"], venv / "bin" / "brain")
        (venv / "pyvenv.cfg").write_text("home = %s\n" % (pythons / "cpython-3.13.14-linux" / "bin"))
        self.assertEqual(ab.einbindung(self.kbase)["lese_pfade"], (self.kbase, pythons / "cpython-3.13.14-linux"))
        self.assertIsNone(ab.einbindung(self.root / "fehlt"))

    def test_sperre_kbase_lesen_geheimordner_und_brain_befehle(self):
        work = self.root / "arbeit"
        work.mkdir()
        (self.kbase / ".secrets-sync").mkdir()
        env = {"WB_AGENT_ID": "a1", "WB_WELT": str(self.world),
               "WB_AGENT_PROFIL": str(self.world / "agents" / "a1" / "agent.json"), "WB_AGENT_TMP": str(work),
               "WB_BRAIN_KBASE": str(self.kbase), "WB_PROFIL_BIN": str(SHELL / "wb-profil")}

        def entscheiden(tool, felder):
            with mock.patch.dict(os.environ, env):
                return ps.entscheiden({"tool_name": tool, "tool_input": felder, "cwd": str(work)})

        self.assertIsNone(entscheiden("Read", {"file_path": str(self.kbase / "20-projects/myproject/hostco-box.md")}))
        self.assertIsNone(entscheiden("Grep", {"pattern": "Hostco", "path": str(self.kbase / "20-projects")}))
        self.assertIn("Geheimordner", entscheiden("Read", {"file_path": str(self.kbase / "90-secrets/hostco.md")}))
        self.assertIn("Geheimordner", entscheiden("Glob", {"pattern": str(self.kbase / ".secrets-sync/*")}))
        self.assertIsNone(entscheiden("Bash", {"command": 'brain search "Hostco Box" -k 5'}))
        self.assertIsNone(entscheiden("Bash", {"command": "brain search Box --pfad %s" % (
            self.kbase / "20-projects/myproject/agenten/a1")}))
        self.assertIn("brain search", entscheiden("Bash", {"command": "brain ingest %s/n.md --write" % work}))
        self.assertIn("brain search", entscheiden("Bash", {"command": "brain gardener run"}))
        self.assertIn("in the brain", entscheiden("Bash", {"command": "echo x > %s" % (self.kbase / "20-projects/x.md")}))


class TraegerPosten(Grundlage):
    def setUp(self):
        super().setUp()
        self.launcher = traeger_hilfen.SharedLauncher()
        self.addCleanup(self.launcher.cleanup)
        self.laeufe = {}
        self.outputs = {}
        self.konfig = at.TraegerKonfig(self.world, self.root / "state", self.root / "agents", "/opt/claude/claude",
                                       "host2", {"kind": "setup-token", "path": "/nonexistent"},
                                       brain={"kbase": str(self.kbase)})
        self.traeger = at.WeltTraeger(self.konfig, zug_fabrik=self.fabrik, observer_fabrik=lambda _t: self.launcher,
                                      ausgabe=lambda _t, receipt: self.outputs.get(receipt.pid, b""),
                                      anmeldequelle=traeger_hilfen.Credential(), kontingentquelle=None,
                                      zeitgeber=lambda _when: None, clock=time.time)

    def fabrik(self, traeger, *, agent_id, run_id, zug, workspace, agent_state, extra_read_paths=(), netz=False,
               extra_write_paths=(), git_einbindung=None, verdeckt=(), brain_kbase=None):
        test = self

        class FakeLauf:
            def start(self):
                self.zug, self.agent_id = zug, agent_id
                self.read_paths, self.verdeckt, self.brain_kbase = tuple(extra_read_paths), tuple(verdeckt), brain_kbase
                self.release = traeger.orte.state / ("release-" + run_id)
                sessions = Path(zug.config_dir) / "projects" / ac.projekt_ordnername(str(workspace))
                sessions.mkdir(parents=True, exist_ok=True)
                code = ("import pathlib, sys, time\np = pathlib.Path(sys.argv[1])\n"
                        "while not p.exists(): time.sleep(0.02)\n")
                spec = al.StartSpec((sys.executable, "-c", code, str(self.release)), str(workspace))
                handle = al.RunController(traeger.orte.runs, launcher=test.launcher).start(
                    traeger.world_id(), agent_id, run_id, spec)
                self.pid = handle.receipt.pid
                test.laeufe[run_id] = self

            def close(self):
                pass

        return FakeLauf()

    def finish(self, run_id, text=None):
        lauf = self.laeufe[run_id]
        session = lauf.zug.session_id
        if text is not None:
            entry = self.traeger._zuege_lesen()["runs"][run_id]
            ad.write_result(self.world, entry["ticket_id"], lauf.agent_id, text, None, lauf.agent_id, "mitglied")
        self.outputs[lauf.pid] = "\n".join(json.dumps(event) for event in (
            {"type": "system", "subtype": "init", "session_id": session},
            {"type": "result", "subtype": "success", "is_error": False, "terminal_reason": "completed",
             "result": "done", "session_id": session})).encode() + b"\n"
        lauf.release.write_text("go")
        self.launcher.processes[lauf.pid].wait(timeout=5)

    def test_posten_gedaechtnis_kuerzen_kommt_vor_jedem_anderen_posten(self):
        text, lessons = memory_mit(16)
        self.write_memory(text)
        ad.create_ticket(self.world, "Ticket a1", "Ziel", "fertig", ["a1"], "haupt", "hauptagent", ticket_id="t1", kind="auftrag")
        ad.create_ticket(self.world, "Ticket a2", "Ziel", "fertig", ["a2"], "haupt", "hauptagent", ticket_id="t2", kind="auftrag")
        first = self.traeger.einmal()["gestartet"]
        self.assertEqual(sorted((item["agent"], item["art"]) for item in first),
                         [("a1", "gedaechtnis"), ("a2", "ticket")])
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "offen")
        run_id = next(item["run"] for item in first if item["agent"] == "a1")
        lauf = self.laeufe[run_id]
        entry = self.traeger._zuege_lesen()["runs"][run_id]
        self.assertEqual(entry["session_key"], at.GEDAECHTNIS_SITZUNG)
        self.assertIn("over its limit", lauf.zug.prompt)
        self.assertIn("1: ## Lehren", lauf.zug.prompt)
        self.assertIn('"art": "archiv"', lauf.zug.prompt)
        anweisung = Path(lauf.zug.append_system_prompt_file).read_text(encoding="utf-8")
        eigen = self.kbase / "20-projects/myproject/agenten/a1"
        self.assertIn('brain search \\"<Thema des Tickets>\\" -k 5 --pfad %s' % eigen, json.dumps(anweisung))
        self.assertIn("brain.suche", anweisung)
        self.assertIn("brain.notiz", anweisung)
        self.assertIn('"art": "archiv"', anweisung)
        self.assertIn("über der Grenze", anweisung)
        self.assertIn(self.kbase, lauf.read_paths)
        self.assertEqual(lauf.verdeckt, (self.kbase / "90-secrets", self.kbase / ".secrets-sync"))
        self.assertEqual(lauf.brain_kbase, self.kbase)
        settings = json.loads(Path(lauf.zug.settings_file).read_text())
        self.assertEqual(settings["env"]["WB_BRAIN_KBASE"], str(self.kbase))
        self.assertTrue(settings["env"]["PATH"].startswith(str(self.traeger.orte.runtime / at.BRAIN_BIN) + ":"))
        self.assertEqual((self.traeger.orte.runtime / at.BRAIN_BIN / "brain").stat().st_mode & 0o777, 0o700)
        self.assertTrue((self.traeger.orte.runtime / "agents_brain.py").is_file())
        # Solange der Kuerzungszug laeuft, startet fuer a1 nichts anderes.
        self.assertEqual(self.traeger.einmal()["gestartet"], [])
        run_dir = Path(entry["run_dir"])
        (run_dir / sk.LEARN_FILE).write_text(json.dumps({"art": "archiv", "zeilen": list(range(2, 16)),
                                                         "neu": ["Kurz: Regel fuer jeden Zug."], "grund": "Grenze"}))
        self.finish(run_id)
        durchgang = self.traeger.einmal()
        done = next(item for item in durchgang["beendet"] if item["agent"] == "a1")
        self.assertEqual((done["art"], done["outcome"], done["lernschritt"]), ("gedaechtnis", "erfolg", "angewendet"))
        self.assertFalse(ag.messen(self.memory())["ueber_grenze"])
        self.assertTrue(all(lesson in self.lehren_pfad().read_text(encoding="utf-8") for lesson in lessons[:14]))
        stored = self.traeger._zuege_lesen()["runs"][run_id]["lernschritt"]
        self.assertEqual(stored["brain"]["sync"]["status"], "gepusht")
        # Im selben Durchgang ist der Weg frei: das Ticket startet.
        self.assertEqual([(item["agent"], item["art"], item["ticket"]) for item in durchgang["gestartet"]],
                         [("a1", "ticket", "t1")])

    def test_kuerzungszug_ohne_archiv_haelt_die_anderen_posten_zurueck(self):
        text, _ = memory_mit(16)
        self.write_memory(text)
        ad.create_ticket(self.world, "Ticket a1", "Ziel", "fertig", ["a1"], "haupt", "hauptagent", ticket_id="t1", kind="auftrag")
        run_id = self.traeger.einmal()["gestartet"][0]["run"]
        self.finish(run_id)
        done = self.traeger.einmal()["beendet"][0]
        self.assertEqual((done["art"], done["outcome"], done["lernschritt"]), ("gedaechtnis", "ergebnis_fehlt", "fehlt"))
        self.assertIn("recovery", done["folge"])
        self.assertEqual(self.traeger.einmal()["gestartet"], [])
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "offen")
        stand = self.traeger.zug_stand()["a1"]
        self.assertTrue(stand["zustellung_offen"])
        self.assertEqual(stand["letzter"]["art"], "gedaechtnis")
        # Kuerzt der Mensch selbst, ist der Weg frei.
        ad.write_memory(self.world, "a1", ag.vorlage("a1"), None, "mensch", None)
        self.assertEqual([item["ticket"] for item in self.traeger.einmal()["gestartet"]], ["t1"])

    def test_konfig_brain_aus_traeger_json_und_abschaltbar(self):
        data = dict(self.konfig.as_dict())
        self.assertEqual(data["brain"], {"kbase": str(self.kbase)})
        path = self.root / "traeger.json"
        path.write_text(json.dumps(data))
        self.assertEqual(at.TraegerKonfig.laden(path).brain, {"kbase": str(self.kbase)})
        data["brain"] = None
        path.write_text(json.dumps(data))
        self.assertIsNone(at.TraegerKonfig.laden(path).brain)
        data.pop("brain")
        path.write_text(json.dumps(data))
        with mock.patch.object(Path, "home", return_value=self.root / "ohne-home"):
            self.assertIsNone(at.TraegerKonfig.laden(path).brain)
        with self.assertRaises(at.TraegerFehler):
            at.TraegerKonfig(self.world, self.root / "s2", self.root / "a2", "/opt/claude/claude", "host2",
                             {"kind": "setup-token", "path": "/x"}, brain={"kbase": "relativ"})


if __name__ == "__main__":
    unittest.main()
