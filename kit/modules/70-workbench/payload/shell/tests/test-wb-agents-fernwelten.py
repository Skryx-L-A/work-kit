#!/usr/bin/env python3
"""Isolierte Vertragsproben fuer Fernwelten: agents_weltauftrag.py (Auftraege ueber ssh) und wb-welt umziehen.

Keine echte Maschine: eine ssh-Attrappe fuehrt den entfernten Befehl lokal in einem eigenen Home aus
(``FERN_HOME``), dessen Laufzeit ``~/.local/share/werkbank-agents/laufzeit/shell`` auf dieses ``shell/``
zeigt. systemd-run und systemctl sind dort Attrappen, die ihren Aufruf protokollieren; das Claude-Binary
ist eine leere ausfuehrbare Datei. rsync ist echt und kopiert ueber die Attrappe in das zweite Home.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHELL))

import agents_data as ad  # noqa: E402
from herkunft_fixture import aufbau_herkunft, gemessener_mensch  # noqa: E402


_MENSCH_PATCH = None


def setUpModule():
    global _MENSCH_PATCH
    _MENSCH_PATCH = gemessener_mensch(ad)
    _MENSCH_PATCH.start()


def tearDownModule():
    _MENSCH_PATCH.stop()

SSH_ATTRAPPE = r'''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
i = 0
while i < len(args) and args[i].startswith("-"):
    i += 2 if args[i] in ("-o", "-p", "-l", "-i", "-F") else 1
host, befehl = args[i], args[i + 1:]
home = os.environ["FERN_HOME"]
with open(os.environ["FERN_LOG"], "a") as log:
    log.write(json.dumps({"host": host, "befehl": " ".join(befehl), "optionen": args[:i]}) + "\n")
if os.path.exists(os.path.join(home, ".nicht-erreichbar")):
    sys.stderr.write("ssh: connect to host %s port 22: Connection refused\n" % host)
    sys.exit(255)
os.chdir(home)
env = dict(os.environ, HOME=home, PATH=os.path.join(home, "bin") + ":/usr/bin:/bin")
os.execvpe("/bin/sh", ["/bin/sh", "-c", " ".join(befehl)], env)
'''


class Fernmaschine:
    """Ein Wegwerf-Home als „host2": Laufzeit, systemd- und Claude-Attrappen."""

    def __init__(self, base: Path):
        self.home = base / "host2-home"
        self.log = base / "ssh.log"
        self.ssh = base / "ssh"
        self.ssh.write_text(SSH_ATTRAPPE)
        self.ssh.chmod(0o755)
        laufzeit = self.home / ".local/share/werkbank-agents/laufzeit"
        laufzeit.mkdir(parents=True)
        (laufzeit / "shell").symlink_to(SHELL)
        claude = self.home / ".local/share/mise/installs/claude/latest/claude"
        claude.parent.mkdir(parents=True)
        claude.write_text("#!/bin/sh\nexit 0\n")
        claude.chmod(0o755)
        bindir = self.home / "bin"
        bindir.mkdir()
        (bindir / "systemd-run").write_text("#!/bin/sh\necho \"$*\" >> \"$HOME/systemd-run.log\"\nexit 0\n")
        (bindir / "systemctl").write_text("#!/bin/sh\necho inactive\nexit 3\n")
        for f in bindir.iterdir():
            f.chmod(0o755)
        self.env = dict(os.environ, FERN_HOME=str(self.home), FERN_LOG=str(self.log), TMPDIR=str(base / "tmp"))
        (base / "tmp").mkdir()

    def auftrag(self, job: dict, *, host: str = "host2") -> tuple[int, dict]:
        done = subprocess.run([str(self.ssh), "-oBatchMode=yes", host,
                               "python3 .local/share/werkbank-agents/laufzeit/shell/agents_weltauftrag.py json"],
                              input=json.dumps(job), text=True, capture_output=True, env=self.env, timeout=60)
        try:
            return done.returncode, json.loads(done.stdout)
        except ValueError:
            return done.returncode, {"roh": done.stdout, "err": done.stderr}


class WeltauftragTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-fernwelten-")
        self.base = Path(self.tmp.name).resolve()
        self.fern = Fernmaschine(self.base)
        self.projekt = self.fern.home / "AI" / "myproject"
        self.projekt.mkdir(parents=True)

    def tearDown(self):
        self.tmp.cleanup()

    def test_anlegen_richtet_traeger_ein_und_lesen_finden_sehen_die_welt(self):
        code, neu = self.fern.auftrag({"befehl": "anlegen", "art": "projekt", "projekt": "~/AI/myproject", "einrichten": True})
        self.assertEqual(code, 0, neu)
        ablage = self.projekt / ".werkbank" / "agents"
        self.assertEqual((neu["pfad"], neu["projekt"], neu["name"], neu["vorhanden"]), (str(ablage), str(self.projekt), "myproject", False))
        self.assertTrue(neu["traeger"]["eingerichtet"], neu["traeger"])
        konfig = json.loads((ablage / "traeger.json").read_text())
        self.assertEqual((konfig["maschine"], konfig["world_root"]), ("lokal", str(ablage)))
        self.assertTrue(konfig["state_dir"].startswith(str(self.fern.home / ".wba/")), konfig["state_dir"])
        # Der Modell-Socket liegt im Zugordner (agents_claude_lauf.py); der Agentenbereich muss so kurz
        # sein, dass eine Kennung von 20 Zeichen unter 107 Byte bleibt (host2, 15.09.2026: path too long).
        # Gemessen relativ zum Home, weil das Wegwerf-HOME unter $TMPDIR selbst schon lang ist.
        relativ = len(konfig["agents_dir"]) - len(str(self.fern.home))
        self.assertGreaterEqual(107 - (len("/home/<user>") + relativ) - len("/") - 20 - len("/state/zug-") - 20 - len("/model.sock"), 0, konfig["agents_dir"])
        self.assertIn("kennung_hoechstens", neu["traeger"])
        register = json.loads((self.fern.home / ".local/state/werkbank-agents/welten.json").read_text())
        self.assertEqual([w["konfig"] for w in register["welten"]], [str(ablage / "traeger.json")])
        code, noch = self.fern.auftrag({"befehl": "anlegen", "art": "projekt", "projekt": "~/AI/myproject", "einrichten": True})
        self.assertEqual((code, noch["vorhanden"], noch["traeger"]["eingerichtet"]), (0, True, True))

        code, gelesen = self.fern.auftrag({"befehl": "lesen", "welt": str(ablage), "grenze": 50})
        self.assertEqual(code, 0, gelesen)
        self.assertEqual((gelesen["ansicht"]["world"]["name"], gelesen["ansicht"]["agents"], gelesen["traeger"]),
                         ("myproject", [], {"eingerichtet": True, "laeuft": False, "maschine": "lokal"}))
        self.assertIsNotNone(gelesen["skills"])
        code, funde = self.fern.auftrag({"befehl": "finden", "wurzeln": ["~/AI"], "projekte": [], "global": "~/.claude/workbench/agents"})
        self.assertEqual(code, 0, funde)
        self.assertEqual([(w["path"], w["kind"], w["name"]) for w in funde["welten"]], [(str(ablage), "project", "myproject")])
        self.assertEqual(funde["home"], str(self.fern.home))

    def test_ausfuehren_schreibt_mit_datei_weckt_den_traeger_und_raeumt_auf(self):
        code, neu = self.fern.auftrag({"befehl": "anlegen", "art": "projekt", "projekt": "~/AI/myproject", "einrichten": True})
        ablage = neu["pfad"]
        ad.create_agent(Path(ablage), "myproject", "hauptagent", None, "Hauptagent", None, None, "sonnet5:high", None,
                        None, None, "host2", "cli-operator", None, bootstrap=True)
        code, gesendet = self.fern.auftrag({"befehl": "ausfuehren", "skript": "agents_data.py", "welt": ablage, "wecken": True,
                                            "argv": ["kanal", "senden", ablage, "--absender=cli-operator", "--an=myproject",
                                                     "--text=Hallo -h 'mit' \"Quoten\"", "--direkt", "--json"]})
        self.assertEqual((code, gesendet["code"], gesendet["wecken"]), (0, 0, "gestartet"), gesendet)
        self.assertIn("wb-agents-traeger-", (self.fern.home / "systemd-run.log").read_text())
        nachricht = json.loads(gesendet["out"])
        self.assertEqual(nachricht["text"], "Hallo -h 'mit' \"Quoten\"")

        gross = "Dateiuebergabe " + "x" * 200_000
        entwurf = json.dumps({"title": "Dateiuebergabe", "goal": gross, "done_criterion": "Geprueft",
                              "recipients": ["myproject"], "done_items": ["Geprueft"],
                              "limits": {"runden": 1}})
        code, gemerkt = self.fern.auftrag({"befehl": "ausfuehren", "skript": "agents_data.py", "welt": ablage,
                                           "argv": ["ticket", "bereit", ablage,
                                                    {"datei": entwurf, "vor": "--entwurf-datei="},
                                                    "--json"]})
        self.assertEqual((code, gemerkt["code"]), (0, 0), gemerkt)
        self.assertNotIn("wecken", gemerkt)
        self.assertEqual(json.loads(gemerkt["out"])["entwurf"]["goal"], gross)
        self.assertEqual(list((self.base / "tmp").iterdir()), [])

        code, fehler = self.fern.auftrag({"befehl": "ausfuehren", "skript": "agents_data.py", "welt": ablage, "wecken": True,
                                          "argv": ["kanal", "senden", ablage, "--absender=cli-operator",
                                                   "--an=niemand", "--text=x", "--json"]})
        self.assertEqual(code, 0)
        self.assertNotEqual(fehler["code"], 0)
        self.assertNotIn("wecken", fehler)
        self.assertEqual(len((self.fern.home / "systemd-run.log").read_text().splitlines()), 1)

    def test_abgelehnte_auftraege_nennen_den_grund(self):
        code, a = self.fern.auftrag({"befehl": "anlegen", "art": "projekt", "projekt": "~/AI/fehlt"})
        self.assertEqual(code, 1)
        self.assertIn("gibt es auf", a["fehler"])
        code, b = self.fern.auftrag({"befehl": "ausfuehren", "skript": "agents_traeger.py", "welt": "/x", "argv": ["status"]})
        self.assertEqual((code, "nicht erlaubt" in b["fehler"]), (1, True))
        code, c = self.fern.auftrag({"befehl": "loeschen"})
        self.assertEqual(code, 2)
        code, d = self.fern.auftrag({"befehl": "hallo"})
        self.assertEqual((code, d["home"]), (0, str(self.fern.home)))
        (self.fern.home / ".nicht-erreichbar").write_text("")
        code, e = self.fern.auftrag({"befehl": "hallo"})
        self.assertEqual(code, 255)


class UmzugTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-umzug-")
        self.base = Path(self.tmp.name).resolve()
        self.fern = Fernmaschine(self.base)
        (self.fern.home / "AI" / "myproject").mkdir(parents=True)
        self.mac = self.base / "mac-home"
        self.ablage = self.mac / "AI" / "myproject" / ".werkbank" / "agents"
        ad.create_world(self.ablage, "myproject", with_main_agent=False)
        ad.create_agent(self.ablage, "myproject", "hauptagent", None, "Hauptagent", None, None, "sonnet5:high", None,
                        None, None, "host2", "cli-operator", None, bootstrap=True)
        ad.send_message(self.ablage, "mensch", ["myproject"], "Hallo", None, None, None, direct=True)
        self.register = self.mac / ".config/agent-workbench/welten-fern.json"
        self.env = dict(self.fern.env, HOME=str(self.mac), WB_FERN_SSH=str(self.fern.ssh), AWB_STATE_DIR=str(self.register.parent))

    def tearDown(self):
        self.tmp.cleanup()

    def umziehen(self, *extra: str, welt: Path | None = None) -> tuple[int, dict]:
        done = subprocess.run([str(SHELL / "wb-welt"), "umziehen", str(welt or self.ablage), "host2", "--json", *extra],
                              text=True, capture_output=True, env=self.env, timeout=120)
        try:
            return done.returncode, json.loads(done.stdout)
        except ValueError:
            return done.returncode, {"roh": done.stdout, "err": done.stderr}

    def test_trocken_prueft_beide_seiten_und_schreibt_nichts(self):
        code, plan = self.umziehen("--trocken")
        self.assertEqual(code, 0, plan)
        ziel = self.fern.home / "AI/myproject/.werkbank/agents"
        self.assertEqual((plan["trocken"], plan["nach"], plan["rel"]), (True, str(ziel), "AI/myproject/.werkbank/agents"))
        self.assertTrue(plan["umbenannt"].startswith(str(self.ablage) + ".umgezogen-"))
        self.assertTrue((self.ablage / "world.json").is_file())
        self.assertFalse((self.fern.home / "AI/myproject/.werkbank").exists())
        self.assertFalse(self.register.exists())

    def test_umzug_kopiert_prueft_benennt_um_traegt_ein_und_richtet_ein(self):
        (self.ablage / "traeger.json").write_text('{"version": 1, "maschine": "lokal", "world_root": "%s"}' % self.ablage)
        code, erg = self.umziehen()
        self.assertEqual(code, 0, erg)
        ziel = self.fern.home / "AI/myproject/.werkbank/agents"
        self.assertFalse(self.ablage.exists())
        self.assertTrue(Path(erg["umbenannt"]).is_dir())
        self.assertTrue((Path(erg["umbenannt"]) / "world.json").is_file())
        self.assertEqual(ad.world_snapshot(ziel, 50)["world"]["name"], "myproject")
        self.assertEqual([c["id"] for c in ad.world_snapshot(ziel, 50)["direct_chats"]],
                         [c["id"] for c in ad.world_snapshot(Path(erg["umbenannt"]), 50)["direct_chats"]])
        konfig = json.loads((ziel / "traeger.json").read_text())
        self.assertEqual(konfig["world_root"], str(ziel))
        self.assertTrue(erg["traeger"]["eingerichtet"], erg["traeger"])
        self.assertEqual(json.loads(self.register.read_text())["welten"],
                         [{"maschine": "host2", "pfad": str(ziel), "projekt": str(self.fern.home / "AI/myproject")}])
        self.assertEqual(ad.find_worlds([str(self.mac / "AI")], [], None), [])
        self.assertIn("world.json", erg["alte_pfade"])

        # Ein zweiter Umzug derselben Welt: das Ziel steht, und hier gibt es keine Welt mehr.
        ad.create_world(self.ablage, "myproject", with_main_agent=False)
        code, zweit = self.umziehen()
        self.assertEqual(code, 2)
        self.assertIn("gibt es", zweit["fehler"])
        self.assertTrue((self.ablage / "world.json").is_file())

    def test_ablehnungen_vor_dem_kopieren(self):
        with aufbau_herkunft(ad) as aufbau:
            tid = ad.create_ticket(self.ablage, "Laeuft", "Z", "F", ["myproject"], aufbau, None)["id"]
        ad.claim_ticket(self.ablage, tid, "myproject", None, None)
        code, lauf = self.umziehen()
        self.assertEqual(code, 2)
        self.assertIn("läuft", lauf["fehler"])
        self.assertFalse((self.fern.home / "AI/myproject/.werkbank").exists())

        andere = self.mac / "AI" / "ohne" / ".werkbank" / "agents"
        ad.create_world(andere, "ohne", with_main_agent=False)
        code, ohne = self.umziehen(welt=andere)
        self.assertEqual(code, 2)
        self.assertIn("Projektordner", ohne["fehler"])

        (self.fern.home / ".nicht-erreichbar").write_text("")
        code, weg = self.umziehen("--trocken", welt=andere)
        self.assertEqual(code, 2)
        self.assertIn("nicht erreichbar", weg["fehler"])
        self.assertTrue((andere / "world.json").is_file())


if __name__ == "__main__":
    unittest.main()
