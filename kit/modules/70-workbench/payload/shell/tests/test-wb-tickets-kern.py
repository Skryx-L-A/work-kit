#!/usr/bin/env python3
"""Der Ticketkern ueber die Kommandozeile: Bereitschaft eines Entwurfs und das Rest-Ticket.

Beide Wege laufen hier ueber `wb-ticket`, nicht ueber die Funktion, denn die Oberflaeche und
der Mensch rufen genau diesen Weg. Geprueft wird auch, was nicht passieren darf: die
Entwurfspruefung schreibt nichts, und eine wiederholte Abnahme legt kein zweites Rest-Ticket an.
"""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path

HERE = Path(__file__).resolve()
SHELL = HERE.parents[1]
AUFBAU = "aufbau"
sys.path.insert(0, str(SHELL))
import agents_data as ad
from herkunft_fixture import gemessener_mensch


class _KernBasis(unittest.TestCase):
    """Eine eigene Welt je Probe, im eigenen Testordner; die echte Welt bleibt unberuehrt."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="tickets-kern-")
        self.human_patch = gemessener_mensch(ad)
        self.human_patch.start()
        self.addCleanup(self.human_patch.stop)
        self.world = Path(self.tmp.name) / "welt"
        self.home = Path(self.tmp.name) / "aufbau-home"
        self.home.mkdir(mode=0o700)
        self.home.chmod(0o700)
        self.proof = self.home / ".wb-test-aufbau-beleg"
        self.proof.write_bytes(os.urandom(32))
        self.proof.chmod(0o600)
        self.env = dict(os.environ, HOME=str(self.home), PYTHONPATH=str(SHELL),
                        WB_TEST_AUFBAU_BELEG=str(self.proof))
        self.call("wb-welt", "neu", self.world, "--name", "Kern", "--absender", AUFBAU)
        self.call("wb-agent", "neu", self.world, "--name", "m1", "--stufe", "mitglied",
                  "--beschreibung", "M1", "--absender", AUFBAU)

    def tearDown(self):
        self.tmp.cleanup()

    def raw(self, tool, *args):
        if AUFBAU not in map(str, args):
            return self.in_process(tool, *args)
        return subprocess.run([str(SHELL / tool), *map(str, args)],
                              text=True, capture_output=True, env=self.env)

    def call(self, tool, *args):
        if AUFBAU not in map(str, args):
            result = self.in_process(tool, *args, "--json")
            if result.returncode != 0:
                raise AssertionError("%s fehlgeschlagen: %s" % (tool, result.stderr.strip()))
            return json.loads(result.stdout)
        result = subprocess.run([str(SHELL / tool), *map(str, args), "--json"],
                                text=True, capture_output=True, env=self.env)
        if result.returncode != 0:
            raise AssertionError("%s fehlgeschlagen: %s" % (tool, result.stderr.strip()))
        return json.loads(result.stdout)

    def in_process(self, tool, *args):
        kind = {"wb-welt": "welt", "wb-agent": "agent", "wb-ticket": "ticket"}[tool]
        stdout, stderr = StringIO(), StringIO()
        try:
            with redirect_stdout(stdout), redirect_stderr(stderr):
                status = ad.run(kind, [str(arg) for arg in args])
        except SystemExit as exc:
            status = exc.code if isinstance(exc.code, int) else 2
        return subprocess.CompletedProcess([tool, *map(str, args)], status,
                                           stdout.getvalue(), stderr.getvalue())

    def abdruck(self):
        """Inhalt der ganzen Welt als Abdruck: Pfad und Pruefsumme je Datei."""
        werte = {}
        for pfad in sorted(self.world.rglob("*")):
            if pfad.is_file():
                werte[str(pfad.relative_to(self.world))] = hashlib.sha256(pfad.read_bytes()).hexdigest()
        return werte


class EntwurfBereitTests(_KernBasis):
    """`wb-ticket bereit --entwurf`: Definition of Ready vor der Anlage (Plan Satz 45)."""

    def entwurf(self, *args):
        return self.raw("wb-ticket", "bereit", self.world, "--entwurf", *args)

    def test_vollstaendiger_entwurf_ist_bereit_und_endet_mit_null(self):
        result = self.entwurf("--titel", "T", "--ziel", "Z", "--fertig", "F", "--an", "m1")
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "bereit"))

    def test_leerer_entwurf_nennt_jeden_fehlenden_punkt_und_endet_mit_eins(self):
        result = self.entwurf()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout.strip(),
                         "nicht bereit: fehlender Auftrag (Titel, Ziel oder Fertig-Kriterium); "
                         "fehlende Adressaten")

    def test_json_nennt_die_punkte_mit_kennung(self):
        result = self.entwurf("--titel", "T", "--ziel", "Z", "--fertig", "F", "--an", "m1",
                              "--art", "task", "--json")
        self.assertEqual(result.returncode, 1)
        data = json.loads(result.stdout)
        self.assertFalse(data["bereit"])
        self.assertEqual([punkt["punkt"] for punkt in data["fehlt"]], ["fertig-liste"])
        self.assertEqual(data["grund"], "fehlende Fertig-Liste")
        # Die Vorgabe-Grenze der Anlage zaehlt mit, sonst meldete die Vorschau eine falsche Luecke.
        self.assertEqual(data["entwurf"]["limits"], {"runden": ad.DEFAULT_ROUNDS})

    def test_fertig_liste_macht_den_task_bereit(self):
        result = self.entwurf("--titel", "T", "--ziel", "Z", "--fertig", "F", "--an", "m1",
                              "--art", "task", "--fertig-punkt", "Schritt eins")
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "bereit"))

    def test_vorhaben_braucht_weder_liste_noch_adressat(self):
        result = self.entwurf("--titel", "T", "--ziel", "Z", "--fertig", "F", "--art", "vorhaben")
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "bereit"))

    def test_unbekannter_und_pausierter_adressat_sind_nicht_bereit(self):
        result = self.entwurf("--titel", "T", "--ziel", "Z", "--fertig", "F", "--an", "m9")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Adressat m9 gibt es in dieser Welt nicht", result.stdout)
        self.call("wb-agent", "pause", self.world, "m1", "--grund", "Probe", "--absender", "mensch")
        result = self.entwurf("--titel", "T", "--ziel", "Z", "--fertig", "F", "--an", "m1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Adressat m1 ist pausiert", result.stdout)

    def test_offene_abhaengigkeit_ist_nicht_bereit(self):
        self.call("wb-ticket", "neu", self.world, "--id", "t-dep", "--titel", "T", "--ziel", "Z",
                  "--fertig", "F", "--an", "m1", "--absender", AUFBAU)
        result = self.entwurf("--titel", "T", "--ziel", "Z", "--fertig", "F", "--an", "m1",
                              "--abhaengig-von", "t-dep")
        self.assertEqual(result.returncode, 1)
        self.assertIn("abhaengigkeit t-dep ist offen", result.stdout)

    def test_entwurf_als_json_aus_option_datei_und_standardeingabe(self):
        entwurf = {"titel": "T", "ziel": "Z", "fertig": "F", "an": ["m1"], "art": "story",
                   "fertig-punkt": ["Schritt eins"]}
        text = json.dumps(entwurf, ensure_ascii=False)
        result = self.raw("wb-ticket", "bereit", self.world, "--entwurf-json", text)
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "bereit"))
        datei = Path(self.tmp.name) / "entwurf.json"
        datei.write_text(text, encoding="utf-8")
        result = self.raw("wb-ticket", "bereit", self.world, "--entwurf-datei", str(datei))
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "bereit"))
        result = subprocess.run([str(SHELL / "wb-ticket"), "bereit", str(self.world),
                                 "--entwurf-datei", "-"], input=text, text=True,
                                capture_output=True, env=self.env)
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "bereit"))

    def test_gespeicherte_ticketform_gilt_genauso(self):
        """Die Oberflaeche darf auch die Feldnamen eines Tickets schicken."""
        entwurf = {"title": "T", "goal": "Z", "done_criterion": "F", "recipients": ["m1"],
                   "kind": "task", "done_items": [{"text": "Schritt eins", "done": False}]}
        result = self.raw("wb-ticket", "bereit", self.world, "--entwurf-json",
                          json.dumps(entwurf, ensure_ascii=False))
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "bereit"))

    def test_option_gilt_ueber_dem_json(self):
        entwurf = {"titel": "T", "ziel": "Z", "fertig": "F", "an": ["m9"]}
        result = self.raw("wb-ticket", "bereit", self.world, "--entwurf-json",
                          json.dumps(entwurf), "--an", "m1")
        self.assertEqual((result.returncode, result.stdout.strip()), (0, "bereit"))

    def test_aufruffehler_enden_mit_zwei(self):
        kaputt = self.raw("wb-ticket", "bereit", self.world, "--entwurf-json", "{")
        self.assertEqual(kaputt.returncode, 2)
        self.assertIn("Entwurf braucht JSON", kaputt.stderr)
        art = self.raw("wb-ticket", "bereit", self.world, "--entwurf", "--art", "unfug")
        self.assertEqual(art.returncode, 2)
        frist = self.raw("wb-ticket", "bereit", self.world, "--entwurf", "--titel", "T",
                         "--ziel", "Z", "--fertig", "F", "--an", "m1", "--frist", "gestern")
        self.assertEqual(frist.returncode, 2)
        self.assertIn("ISO-Zeit", frist.stderr)
        ohne_flag = self.raw("wb-ticket", "bereit", self.world, "--titel", "T")
        self.assertEqual(ohne_flag.returncode, 2)
        self.assertIn("nur mit --entwurf", ohne_flag.stderr)

    def test_entwurfspruefung_schreibt_nichts(self):
        vorher = self.abdruck()
        self.entwurf("--titel", "T", "--ziel", "Z", "--fertig", "F", "--an", "m1")
        self.entwurf("--art", "task")
        self.entwurf("--titel", "T", "--ziel", "Z", "--fertig", "F", "--an", "m9", "--json")
        self.assertEqual(self.abdruck(), vorher)
        self.assertEqual(list((self.world / "tickets").iterdir()), [])

    def test_bereiter_entwurf_wird_ein_bereites_ticket(self):
        """Die Vorschau sagt dasselbe wie `bereit`, sobald das Ticket steht."""
        felder = ("--titel", "T", "--ziel", "Z", "--fertig", "F", "--an", "m1",
                  "--art", "task", "--fertig-punkt", "Schritt eins")
        self.assertEqual(self.entwurf(*felder).returncode, 0)
        self.call("wb-ticket", "neu", self.world, "--id", "t-echt", *felder,
                  "--absender", AUFBAU)
        eintraege = {item["id"]: item for item in self.call("wb-ticket", "bereit", self.world)}
        self.assertTrue(eintraege["t-echt"]["ready"], eintraege["t-echt"]["reason"])


class RestTicketTests(_KernBasis):
    """Abnahme `teilweise`: der Rest wird ein neues Ticket mit `origin` (Plan Satz 40)."""

    def ticket(self, ticket_id="t1", art="task", punkte=("Teil A", "Teil B"), eltern=None):
        args = ["--id", ticket_id, "--titel", "Bauen", "--ziel", "Ziel", "--fertig", "Kriterium",
                "--an", "m1", "--art", art, "--absender", AUFBAU]
        for punkt in punkte:
            args += ["--fertig-punkt", punkt]
        if eltern:
            args += ["--eltern", eltern]
        return self.call("wb-ticket", "neu", self.world, *args)

    def zur_abnahme(self, ticket_id="t1", punkte=2):
        self.call("wb-ticket", "uebernehmen", self.world, ticket_id, "--agent", "m1", "--absender", "m1")
        for nr in range(1, punkte + 1):
            self.call("wb-ticket", "haken", self.world, ticket_id, "--agent", "m1", nr, "--absender", "m1")
        self.call("wb-ticket", "ergebnis", self.world, ticket_id, "--agent", "m1",
                  "--text", "Teil A steht", "--absender", "m1")

    def teilweise(self, ticket_id="t1", bemerkung="Teil B fehlt noch"):
        return self.call("wb-ticket", "abnehmen", self.world, ticket_id, "--absender", "mensch",
                         "--grund", "teilweise", "--bemerkung", bemerkung)

    def punkt_oeffnen(self, ticket_id, nr):
        """Bestand und Sonderfall: ein Punkt der Fertig-Liste steht bei der Abnahme offen."""
        pfad = self.world / "tickets" / ticket_id / "ticket.json"
        data = json.loads(pfad.read_text(encoding="utf-8"))
        data["done_items"][nr - 1]["done"] = False
        ad._write_json(pfad, data)

    def test_rest_uebernimmt_art_prioritaet_adressat_und_bemerkung(self):
        self.ticket()
        self.zur_abnahme()
        abgenommen = self.teilweise()
        self.assertEqual(abgenommen["state"], "abgenommen")
        self.assertEqual(abgenommen["approval"]["reason_code"], "teilweise")
        self.assertEqual(abgenommen["approval"]["rest"], "t1-rest")
        rest = ad.read_ticket(self.world, "t1-rest")
        self.assertEqual((rest["origin"], rest["state"], rest["kind"], rest["recipients"]),
                         ("t1", "offen", "task", ["m1"]))
        self.assertEqual(rest["priority"], abgenommen["priority"])
        self.assertIn("Teil B fehlt noch", rest["goal"])
        self.assertEqual(rest["done_criterion"], "Kriterium")
        # Die Fertig-Liste war abgehakt; dann ist die Bemerkung der eine offene Punkt.
        self.assertEqual([item["text"] for item in rest["done_items"]], ["Teil B fehlt noch"])
        self.assertTrue((self.world / "agents" / "m1" / "postfach").is_dir())
        zustellungen = [p.name for p in (self.world / "agents" / "m1" / "postfach").iterdir()]
        self.assertTrue(any("t1-rest" in name for name in zustellungen), zustellungen)

    def test_rest_uebernimmt_die_offenen_punkte_der_fertig_liste(self):
        self.ticket()
        self.zur_abnahme()
        self.punkt_oeffnen("t1", 2)
        self.teilweise()
        rest = ad.read_ticket(self.world, "t1-rest")
        self.assertEqual([item["text"] for item in rest["done_items"]], ["Teil B"])
        self.assertTrue(all(not item["done"] for item in rest["done_items"]))

    def test_verlauf_steht_in_beiden_tickets(self):
        self.ticket()
        self.zur_abnahme()
        self.teilweise()
        alt = [json.loads(zeile) for zeile
               in (self.world / "tickets" / "t1" / "verlauf.jsonl").read_text(encoding="utf-8").splitlines()]
        folge = [e for e in alt if e["event"] == "folgeticket"]
        self.assertEqual([e["folgeticket"] for e in folge], ["t1-rest"])
        self.assertEqual([e["grund"] for e in alt if e["event"] == "abgenommen"], ["teilweise"])
        neu = [json.loads(zeile) for zeile
               in (self.world / "tickets" / "t1-rest" / "verlauf.jsonl").read_text(encoding="utf-8").splitlines()]
        aus_abnahme = [e for e in neu if e["event"] == "rest-aus-abnahme"]
        self.assertEqual([(e["herkunft"], e["bemerkung"]) for e in aus_abnahme],
                         [("t1", "Teil B fehlt noch")])

    def test_zweiter_aufruf_legt_kein_zweites_rest_ticket_an(self):
        self.ticket()
        self.zur_abnahme()
        self.teilweise()
        vorher = sorted(p.name for p in (self.world / "tickets").iterdir())
        wieder = self.teilweise()
        self.assertEqual(wieder["approval"]["rest"], "t1-rest")
        self.assertEqual(sorted(p.name for p in (self.world / "tickets").iterdir()), vorher)
        self.assertEqual(vorher, ["t1", "t1-rest"])

    def test_zweite_abnahme_mit_anderer_bemerkung_wird_abgewiesen(self):
        self.ticket()
        self.zur_abnahme()
        self.teilweise()
        andere = self.raw("wb-ticket", "abnehmen", self.world, "t1", "--absender", "mensch",
                          "--grund", "teilweise", "--bemerkung", "etwas ganz anderes")
        self.assertEqual(andere.returncode, 2)
        self.assertIn("keine Abnahme moeglich", andere.stderr)
        self.assertEqual(sorted(p.name for p in (self.world / "tickets").iterdir()), ["t1", "t1-rest"])

    def test_erledigt_legt_keinen_rest_an(self):
        self.ticket()
        self.zur_abnahme()
        abgenommen = self.call("wb-ticket", "abnehmen", self.world, "t1", "--absender", "mensch",
                               "--grund", "erledigt")
        self.assertNotIn("rest", abgenommen["approval"])
        self.assertEqual(sorted(p.name for p in (self.world / "tickets").iterdir()), ["t1"])

    def test_rest_haengt_am_selben_eltern_und_haelt_es_offen(self):
        self.call("wb-ticket", "neu", self.world, "--id", "v1", "--titel", "Vorhaben", "--ziel", "Z",
                  "--fertig", "F", "--an", "m1", "--art", "vorhaben", "--absender", AUFBAU)
        self.ticket("s1", art="story", eltern="v1")
        self.zur_abnahme("s1")
        self.teilweise("s1")
        rest = ad.read_ticket(self.world, "s1-rest")
        self.assertEqual((rest["parent"], rest["kind"]), ("v1", "story"))
        # Das Vorhaben hat wieder ein offenes Kind; es geht nicht auf `zur Abnahme`.
        self.assertEqual(ad.read_ticket(self.world, "v1")["state"], "offen")

    def test_rest_ist_sofort_bereit(self):
        self.ticket()
        self.zur_abnahme()
        self.teilweise()
        eintraege = {item["id"]: item for item in self.call("wb-ticket", "bereit", self.world)}
        self.assertTrue(eintraege["t1-rest"]["ready"], eintraege["t1-rest"]["reason"])


if __name__ == "__main__":
    unittest.main()
