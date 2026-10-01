#!/usr/bin/env python3
"""Isolierte Vertragsproben fuer Autostart (shell/agents_autostart.py) und Fernweg (shell/agents_fernweg.py)."""

from __future__ import annotations

import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SHELL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHELL))

import agents_autostart as au  # noqa: E402
import agents_data as ad  # noqa: E402
import agents_fernweg as fw  # noqa: E402


class AutostartTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-autostart-")
        self.root = Path(self.tmp.name)
        self.env = mock.patch.dict(os.environ, {"WB_AGENTS_ZUSTAND": str(self.root / "zustand"),
                                                "WB_AGENTS_UNIT_DIR": str(self.root / "units")})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def konfig(self, name, maschine="lokal"):
        path = self.root / name / "traeger.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"version": 1, "maschine": maschine}))
        return path

    def test_register_wakes_each_local_world_once_and_records_the_run(self):
        eins, zwei, fremd, kaputt = (self.konfig("eins"), self.konfig("zwei"), self.konfig("fremd", "hostco"),
                                     self.konfig("kaputt"))
        for path in (eins, zwei, fremd, kaputt, eins):
            au.registrieren(path)
        self.assertEqual(len(au.register_lesen()["welten"]), 4)
        kaputt.write_text("{")
        geweckt = []

        def wecker(path):
            geweckt.append(Path(path).parent.name)
            return "gestartet"
        record = au.wecken_alle(wecker)
        self.assertEqual(geweckt, ["eins", "zwei"])
        self.assertEqual([item["ergebnis"] for item in record["ergebnisse"]],
                         ["gestartet", "gestartet", "andere_maschine", "fehler"])
        self.assertEqual(au.letzter_lauf()["ergebnisse"], record["ergebnisse"])
        au.abmelden(zwei)
        self.assertEqual([Path(item["konfig"]).parent.name for item in au.register_lesen()["welten"]],
                         ["eins", "fremd", "kaputt"])
        with self.assertRaises(au.AutostartFehler):
            au.registrieren(self.root / "fehlt" / "traeger.json")
        self.assertTrue(str(au.register_pfad()).startswith(str(self.root)))

    def test_unit_is_oneshot_once_per_login_and_the_mac_plist_is_never_placed_for_launchd(self):
        unit = au.unit_text(Path("/home/u/.local/share/werkbank-agents/laufzeit"))
        for line in ("Type=oneshot", "WantedBy=default.target", "Environment=PATH=/usr/bin:/bin",
                     "ExecStart=/usr/bin/python3 -I /home/u/.local/share/werkbank-agents/laufzeit/shell/agents_autostart.py wecken"):
            self.assertIn(line, unit)
        self.assertNotIn("Restart=", unit)
        target = au.plist_schreiben(Path("/Users/u/laufzeit"), self.root / "autostart.plist")
        data = plistlib.loads(target.read_bytes())
        self.assertEqual((data["Label"], data["RunAtLoad"], data["KeepAlive"], data["ProgramArguments"][-1]),
                         (au.PLIST_LABEL, True, False, "wecken"))
        with self.assertRaises(au.AutostartFehler):
            au.plist_schreiben(Path("/x"), Path("~/Library/LaunchAgents/wb.plist").expanduser())
        repo = SHELL.parent
        laufzeit = au.laufzeit_anlegen(self.root / "laufzeit", repo)
        erwartet = ["shell/agents_traeger.py", "shell/wb-ticket", "hooks/profil-sperre.sh", "hooks/lib/cmdshell.py"]
        if (repo / "agents" / "bibliothek").is_dir():  # Kit: the wb-agents library is not shipped
            erwartet.append("agents/bibliothek/skills/ergebnis-schreiben/SKILL.md")
        for rel in erwartet:
            self.assertTrue((laufzeit / rel).is_file(), rel)
        self.assertTrue(os.access(laufzeit / "shell" / "wb-ticket", os.X_OK))
        au.laufzeit_anlegen(self.root / "laufzeit", repo)
        self.assertEqual(sorted(p.name for p in self.root.iterdir() if p.name.startswith(".laufzeit")), [])
        if sys.platform == "darwin":
            with self.assertRaises(au.AutostartFehler):
                au.installieren(self.root / "laufzeit2", repo)

    def test_runtime_file_list_covers_every_agents_import(self):
        # Befund 16.09.2026: agents_modellwahl.py fehlte in SHELL_DATEIEN; die ausgerollte Laufzeit auf host2
        # konnte agents_traeger nicht mehr importieren, ohne dass eine Suite es sah. Jedes agents_*-Modul,
        # das eine Laufzeitdatei importiert, muss selbst Teil der Laufzeit sein.
        import re
        muster = re.compile(r"^\s*(?:from\s+(agents_\w+)\s+import|import\s+(agents_\w+))", re.M)
        fehlend = set()
        for name in au.SHELL_DATEIEN:
            pfad = SHELL / name
            if not pfad.is_file():
                continue
            for a, b in muster.findall(pfad.read_text(encoding="utf-8", errors="replace")):
                modul = (a or b) + ".py"
                if modul not in au.SHELL_DATEIEN and (SHELL / modul).is_file():
                    fehlend.add("%s <- %s" % (modul, name))
        self.assertEqual(sorted(fehlend), [], "Laufzeitdateien importieren Module ausserhalb von SHELL_DATEIEN")


class FernwegTest(unittest.TestCase):
    def test_remote_world_argument_forwards_the_whole_command(self):
        argv = ["neu", "host2:/home/u/welt", "--id", "t1", "--titel", "T", "--ziel", "Z", "--fertig", "F", "--an", "c1"]
        ziel = fw.fernziel("ticket", argv)
        self.assertEqual(ziel, ("host2", "/home/u/welt", 1))
        command = fw.fernbefehl("ticket", argv, ziel)
        self.assertEqual(command[:4], ["ssh", "-oBatchMode=yes", "-oConnectTimeout=8", "host2"])
        self.assertEqual(command[4], ".local/share/werkbank-agents/laufzeit/shell/wb-ticket neu /home/u/welt --id t1 "
                                     "--titel T --ziel Z --fertig F --an c1")
        self.assertIsNone(fw.fernziel("ticket", ["neu", "/home/u/welt", "--titel", "x:/y", "--ziel", "Z", "--fertig", "F"]))
        self.assertIsNone(fw.fernziel("kanal", ["senden", "welt", "--an", "a", "--text", "host2:/nicht/welt"]))
        self.assertEqual(fw.fernziel("welt", ["ansicht", "host2:/w", "--json"])[:2], ("host2", "/w"))
        with self.assertRaises(fw.FernwegFehler):
            fw.fernziel("welt", ["antwort", "host2:/w/../x", "frage", "--text", "ja"])

    def test_wrappers_forward_remote_worlds_and_keep_local_worlds_local(self):
        with tempfile.TemporaryDirectory(prefix="agents-fernweg-") as tmp:
            root = Path(tmp)
            log = root / "ssh.log"
            fake = root / "ssh"
            fake.write_text("#!/bin/sh\nprintf '%%s\\n' \"$*\" >> %s\necho '{\"id\": \"fern\"}'\nexit 7\n" % log)
            fake.chmod(0o755)
            env = dict(os.environ, PATH="/usr/bin:/bin", WB_FERN_SSH=str(fake))
            result = subprocess.run([str(SHELL / "wb-ticket"), "neu", "host2:/home/u/welt", "--titel", "T", "--ziel", "Z",
                                     "--fertig", "F", "--an", "c1", "--json"], text=True, capture_output=True, env=env,
                                    timeout=30)
            self.assertEqual((result.returncode, json.loads(result.stdout)), (7, {"id": "fern"}))
            self.assertIn("host2 .local/share/werkbank-agents/laufzeit/shell/wb-ticket neu /home/u/welt", log.read_text())
            world = root / "welt"
            ad.create_world(world, name="Lokal", main_name="haupt", sender="cli-operator")
            local = subprocess.run([str(SHELL / "wb-kanal"), "senden", str(world), "--an", "haupt", "--text",
                                    "lies host2:/home/u/x", "--json"], text=True, capture_output=True, env=env, timeout=30)
            self.assertEqual(local.returncode, 0, local.stderr)
            self.assertEqual(len(log.read_text().splitlines()), 1)
            view = subprocess.run([str(SHELL / "wb-welt"), "ansicht", "host2:/home/u/welt", "--json"], text=True,
                                  capture_output=True, env=dict(env, WB_AGENTS_FERN_SHELL="/opt/wb/shell"), timeout=30)
            self.assertEqual(view.returncode, 7)
            self.assertIn("host2 /opt/wb/shell/wb-welt ansicht /home/u/welt --json", log.read_text())


if __name__ == "__main__":
    unittest.main()
