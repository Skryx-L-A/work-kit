#!/usr/bin/env python3
"""Mail-Freigaben einer Welt, die Mailkonten des Hosts (mailkonten.json) und der Sendeweg `<werkzeug> senden`.

Belegt: der Mensch erteilt (Beleg ueber wb-mensch oder --bestaetigt mit Wortlaut); der Hauptagent gibt eine
Teilmenge weiter, eine Obermenge, einen spaeteren Ablauf, Teamleiter und Mitglieder weist die Datenschicht ab;
Entzug und Widerruf samt Kette; die drei Controlleroperationen mit Meldung an den Menschen; `mail.senden` und
`wb-myproject senden` gegen einen lokalen SMTP-Dummy (Port 0, nur 127.0.0.1) mit Freigabe erfolgreich und mit
Logzeile, ohne Freigabe, mit einer Adresse aus `nie` oder `rundschreiben` abgewiesen, ein SMTP-Fehler ist ein Fehler,
das Passwort steht nie in Ausgabe oder Log; die Profil-Sperre laesst das Sendewerkzeug eines Kontos nur mit Freigabe
durch. Fehlt mailkonten.json oder das Konto, scheitern Erteilung, Weitergabe und Versand mit dem Pfad der Datei.

ISOLATION: eigene Welt im Wegwerfordner, eigenes HOME fuer die Programmaufrufe, AWB_STATE_DIR auf eine
Wegwerf-Konfiguration (Konto `beispiel`, example.org), Testpasswort `NICHT-ECHT-…` aus einer eigenen Datei, kein
Schluesselbund, keine echte Mail, kein Netz ausser 127.0.0.1.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import socket
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve()
SHELL = HERE.parents[1]
REPO = SHELL.parent
sys.path.insert(0, str(SHELL))
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(REPO / "hooks" / "lib"))

import agents_controller as ac  # noqa: E402
import agents_data as ad  # noqa: E402
import agents_freigaben as af  # noqa: E402
from herkunft_fixture import gebundene_governance, gemessener_mensch  # noqa: E402
from agents_controller_endpoint import ControllerEndpoint  # noqa: E402
from smtp_dummy import SmtpDummy  # noqa: E402

PASSWORT = "NICHT-ECHT-smtp-4711"
ALLE = ["info@example.org", "kontakt@example.org", "rechnung@example.org", "technik@example.org",
        "postmaster@example.org", "abuse@example.org", "inhaber@example.org"]
WORTLAUT = "Er soll für die Beispiel-Mails die Freigaben haben die auch du hast (Test)"
BENUTZER = "postfach@example.org"
KONFIG = {"version": 1, "konten": {
    "beispiel": {
        "domain": "example.org", "smtp_host": "smtp.example.org", "smtp_port": 465, "smtp_modus": "ssl",
        "benutzer": BENUTZER, "schluesselbund": "wb-beispiel-smtp", "werkzeug": "wb-myproject",
        "umfang_quelle": "COMPLIANCE.md, Tabelle „Sendebefugnis je Adresse“, Spalte „Ohne Rückfrage“",
        "ohne_rueckfrage": ALLE,
        "nie": {"privat@example.org": "privat@example.org wird nur gelesen; von dieser Adresse wird nie gesendet."},
        "rundschreiben": {"neuigkeiten@example.org": "neuigkeiten@example.org sendet nur tools/versand.py im Projekt."},
        "hinweise": ["Nachfasstakt: sieben Tage."]},
    "zweit": {
        "domain": "example.net", "smtp_host": "smtp.example.net", "smtp_port": 587, "smtp_modus": "starttls",
        "benutzer": "zweit@example.net", "schluesselbund": "wb-zweit-smtp", "werkzeug": "wb-zweit",
        "umfang_quelle": "Test", "ohne_rueckfrage": ["hallo@example.net"]}}}
MENSCH = ("mensch", "Test: steuerndes Terminal")
AGENT = ("agent", "Test: kein Terminal")
_GOVERNANCE_CONTEXT = None
_MENSCH_PATCH = None


def setUpModule():
    global _GOVERNANCE_CONTEXT, _MENSCH_PATCH
    _MENSCH_PATCH = gemessener_mensch(ad)
    _MENSCH_PATCH.start()
    _GOVERNANCE_CONTEXT = gebundene_governance(ad)
    _GOVERNANCE_CONTEXT.__enter__()


def tearDownModule():
    _GOVERNANCE_CONTEXT.__exit__(None, None, None)
    _MENSCH_PATCH.stop()


class Grundlage(unittest.TestCase):
    def setUp(self):
        # Kurzer Pfad unter HOME: Unix-Sockets haben eine Laengengrenze, und der Controllerordner braucht Vorfahren
        # ohne Fremdschreibrechte (wie test-wb-agents-controller-endpoint.py).
        self.tmp = tempfile.TemporaryDirectory(prefix=".wb-fg-", dir=Path.home())
        self.root = Path(self.tmp.name)
        os.chmod(self.root, 0o700)
        self.world = self.root / "welt"
        ad.create_world(self.world, name="Mail-Probe", main_name="haupt")
        for agent_id, stage, team in (("lead", "teamleiter", "post"), ("post", "mitglied", "post"),
                                      ("recht", "mitglied", "recht")):
            ad.create_agent(self.world, agent_id, stage, team, "Probe", None, None, None, None, None, None, "lokal",
                            "haupt", "hauptagent")
        self.pwdatei = self.root / "pw"
        self.pwdatei.write_text(PASSWORT + "\n")
        self.dummy = SmtpDummy(PASSWORT, BENUTZER).starten()
        self.addCleanup(self.dummy.beenden)
        self.zustand = self.root / "zustand"
        self.zustand.mkdir()
        self.konfig(KONFIG)
        self.env = mock.patch.dict(os.environ, {
            "AWB_STATE_DIR": str(self.zustand),
            "WB_MAIL_SMTP": "127.0.0.1:%d:klartext" % self.dummy.port,
            "WB_MAIL_SMTP_PASSWORT_DATEI": str(self.pwdatei)})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.controllers = []

    def tearDown(self):
        for controller in self.controllers:
            controller.close()
            controller.join()
        self.tmp.cleanup()

    def konfig(self, daten):
        pfad = self.zustand / af.KONFIG_DATEI
        if daten is None:
            pfad.unlink()
        else:
            pfad.write_text(json.dumps(daten, ensure_ascii=False))

    def erteilen(self, agent="haupt", adressen=None, konto="beispiel", **kwargs):
        kwargs.setdefault("bestaetigt", True)
        kwargs.setdefault("wortlaut", WORTLAUT)
        kwargs.setdefault("messung", AGENT)
        kwargs.setdefault("absender", "mensch")
        return af.erteilen(self.world, [agent], "email", konto, adressen or list(ALLE), **kwargs)[0]

    def client(self, agent, role):
        # Endliche Sessionfrist wie in test-wb-agents-controller.py: ein Dienst endet spaetestens damit.
        controller = ac.AgentController(self.world, "run-1", lambda _b: True, 1.0, 5.0)
        self.controllers.append(controller)
        return controller.bind_agent(agent, role)

    def log(self):
        pfad = self.world / af.VERSANDLOG
        return [json.loads(line) for line in pfad.read_text().splitlines()] if pfad.exists() else []

    def kanal(self):
        return ad.read_messages(self.world)

    def verlauf(self, agent):
        pfad = self.world / "agents" / agent / "history.json"
        return json.loads(pfad.read_text())["entries"] if pfad.exists() else []


class MenschTests(Grundlage):
    def test_mensch_erteilt_mit_beleg_und_ohne_beleg_geschieht_nichts(self):
        with self.assertRaisesRegex(af.FreigabeFehler, "--bestaetigt"):
            self.erteilen(bestaetigt=False)
        with self.assertRaisesRegex(af.FreigabeFehler, "Wortlaut"):
            self.erteilen(wortlaut=None)
        self.assertFalse((self.world / af.DATEI).exists())
        eintrag = self.erteilen()
        self.assertEqual(eintrag["inhaber"], "haupt")
        self.assertEqual([a["adresse"] for a in eintrag["adressen"]], ALLE)
        self.assertTrue(all(a["umfang"] == "ohne_rueckfrage" for a in eintrag["adressen"]))
        self.assertIn("Sendebefugnis je Adresse", eintrag["umfang_quelle"])
        self.assertEqual(eintrag["erteilt_von"]["beleg"], {"art": "bestaetigt", "wortlaut": WORTLAUT,
                                                          "wb_mensch": AGENT[1]})
        self.assertEqual(eintrag["kette"], ["mensch:mensch", "haupt"])
        self.assertIsNone(eintrag["quelle"])
        self.assertEqual((self.world / af.DATEI).stat().st_mode & 0o777, 0o600)
        self.assertEqual([item["id"] for item in af.gueltige(self.world, "haupt")], [eintrag["id"]])
        self.assertEqual(self.verlauf("haupt")[-1]["event"], "freigabe-erteilt")
        self.assertIn("Freigabe email (beispiel) für haupt erteilt", self.kanal()[-1]["text"])
        self.assertEqual((eintrag["konto"], eintrag["werkzeug"]), ("beispiel", "wb-myproject"))
        # Wiederholung mit gleichem Inhalt: nichts Neues.
        self.assertEqual(self.erteilen()["id"], eintrag["id"])
        # wb-mensch belegt einen Menschen: dann reicht --bestaetigt.
        gemessen = self.erteilen(agent="post", adressen=["kontakt@example.org"], wortlaut=None, messung=MENSCH)
        self.assertEqual(gemessen["erteilt_von"]["beleg"], {"art": "wb-mensch", "grund": MENSCH[1]})

    def test_feste_sperren_und_fremde_absender(self):
        for adresse, text in (("neuigkeiten@example.org", "versand.py"), ("privat@example.org", "nur gelesen"),
                              ("chef@example.org", "ohne Rückfrage")):
            with self.assertRaisesRegex(af.FreigabeFehler, text):
                self.erteilen(adressen=["info@example.org", adresse])
        with self.assertRaisesRegex(ad.AgentsError, "nur der Mensch"):
            self.erteilen(absender="haupt")
        with self.assertRaises(ad.AgentsError):
            self.erteilen(agent="gibtsnicht")
        with self.assertRaisesRegex(af.FreigabeFehler, "Zukunft"):
            self.erteilen(ablauf="2020-01-01")

    def test_mensch_widerruft_mit_kette(self):
        wurzel = self.erteilen()
        weiter = af.weitergeben(self.world, "haupt", "hauptagent", "post", "email", ["info@example.org"])
        betroffen = af.widerrufen(self.world, freigabe_id=wurzel["id"], grund="Test", absender="mensch")
        self.assertEqual(betroffen, [wurzel["id"], weiter["id"]])
        self.assertEqual(af.gueltige(self.world, "haupt"), [])
        self.assertEqual(af.gueltige(self.world, "post"), [])
        eintraege = {item["id"]: item for item in af.lesen(self.world)}
        self.assertEqual(eintraege[weiter["id"]]["widerrufen"]["grund"], "Quelle %s widerrufen" % wurzel["id"])
        self.assertEqual(self.verlauf("post")[-1]["event"], "freigabe-widerrufen")

    def test_ablauf_endet_die_freigabe_und_die_weitergabe(self):
        wurzel = self.erteilen(ablauf="2d")
        weiter = af.weitergeben(self.world, "haupt", "hauptagent", "post", "email")
        self.assertEqual(weiter["ablauf"], wurzel["ablauf"], "ohne eigenen Ablauf erbt die Weitergabe den der Quelle")
        spaeter = dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=3)
        self.assertEqual(af.gueltige(self.world, "haupt", jetzt=spaeter), [])
        self.assertEqual(af.gueltige(self.world, "post", jetzt=spaeter), [])
        with self.assertRaisesRegex(af.FreigabeFehler, "Nie weiter"):
            af.weitergeben(self.world, "haupt", "hauptagent", "recht", "email", ablauf="30d")
        kuerzer = af.weitergeben(self.world, "haupt", "hauptagent", "recht", "email", ablauf="1d")
        self.assertTrue(af._zeit(kuerzer["ablauf"]) < af._zeit(wurzel["ablauf"]))

    def test_cli_wb_welt_freigabe(self):
        home = self.root / "home"
        home.mkdir()
        env = dict(os.environ, HOME=str(home), PATH="/usr/bin:/bin")
        basis = [str(SHELL / "wb-welt"), "freigabe", str(self.world)]
        ohne = subprocess.run(basis + ["erteilen", "--art", "email", "--konto", "beispiel", "--an", "haupt",
                                       "--adressen", "info@example.org", "--bestaetigt"],
                              capture_output=True, text=True, env=env, timeout=60)
        self.assertEqual(ohne.returncode, 2, ohne.stderr)
        self.assertIn("--beleg", ohne.stderr)
        mit = subprocess.run(basis + ["erteilen", "--art", "email", "--konto", "beispiel", "--an", "haupt,post",
                                      "--adressen", "info@example.org,kontakt@example.org", "--ablauf", "2099-12-31",
                                      "--bestaetigt", "--beleg", WORTLAUT, "--json"],
                             capture_output=True, text=True, env=env, timeout=60)
        self.assertEqual(mit.returncode, 2, mit.stderr)
        self.assertIn("Herkunftsbeleg", mit.stderr)
        self.assertFalse((self.world / af.DATEI).exists())


class WeitergabeTests(Grundlage):
    def test_hauptagent_gibt_teilmenge_weiter_obermenge_und_andere_stufen_abgewiesen(self):
        self.erteilen(adressen=["info@example.org", "kontakt@example.org"])
        weiter = af.weitergeben(self.world, "haupt", "hauptagent", "post", "email", ["kontakt@example.org"])
        self.assertTrue(weiter["neu"])
        self.assertEqual(weiter["kette"], ["mensch:mensch", "haupt", "post"])
        self.assertEqual(weiter["erteilt_von"]["id"], "haupt")
        self.assertEqual(af.adressen_von(af.gueltige(self.world, "post")), ["kontakt@example.org"])
        self.assertEqual(self.verlauf("post")[-1]["event"], "freigabe-weitergegeben")
        with self.assertRaisesRegex(af.FreigabeFehler, "Nie weiter"):
            af.weitergeben(self.world, "haupt", "hauptagent", "recht", "email", ["technik@example.org"])
        with self.assertRaisesRegex(af.FreigabeFehler, "neuigkeiten"):
            af.weitergeben(self.world, "haupt", "hauptagent", "recht", "email", ["neuigkeiten@example.org"])
        with self.assertRaisesRegex(af.FreigabeFehler, "nur der Hauptagent"):
            af.weitergeben(self.world, "lead", "teamleiter", "post", "email", ["kontakt@example.org"])
        with self.assertRaisesRegex(af.FreigabeFehler, "nur der Hauptagent"):
            af.weitergeben(self.world, "post", "mitglied", "recht", "email", ["kontakt@example.org"])
        with self.assertRaisesRegex(af.FreigabeFehler, "selbst"):
            af.weitergeben(self.world, "haupt", "hauptagent", "haupt", "email")
        # Wiederholung: nichts Neues; eine andere Teilmenge ersetzt die alte Weitergabe.
        self.assertFalse(af.weitergeben(self.world, "haupt", "hauptagent", "post", "email",
                                        ["kontakt@example.org"])["neu"])
        ersatz = af.weitergeben(self.world, "haupt", "hauptagent", "post", "email", ["info@example.org"])
        self.assertEqual(ersatz["ersetzt"], [weiter["id"]])
        self.assertEqual(af.adressen_von(af.gueltige(self.world, "post")), ["info@example.org"])

    def test_ohne_eigene_freigabe_keine_weitergabe_und_entzug(self):
        with self.assertRaisesRegex(af.FreigabeFehler, "keine gueltige Freigabe"):
            af.weitergeben(self.world, "haupt", "hauptagent", "post", "email")
        wurzel = self.erteilen()
        menschlich = self.erteilen(agent="recht", adressen=["info@example.org"])
        weiter = af.weitergeben(self.world, "haupt", "hauptagent", "post", "email", ["technik@example.org"])
        with self.assertRaisesRegex(af.FreigabeFehler, "widerruft nur er"):
            af.entziehen(self.world, "haupt", "hauptagent", "recht", "email")
        with self.assertRaisesRegex(af.FreigabeFehler, "nur der Hauptagent"):
            af.entziehen(self.world, "lead", "teamleiter", "post", "email")
        self.assertEqual(af.entziehen(self.world, "haupt", "hauptagent", "post", "email"), [weiter["id"]])
        self.assertEqual(af.gueltige(self.world, "post"), [])
        self.assertEqual([i["id"] for i in af.gueltige(self.world, "recht")], [menschlich["id"]])
        self.assertEqual([i["id"] for i in af.gueltige(self.world, "haupt")], [wurzel["id"]])
        self.assertEqual(self.verlauf("post")[-1]["event"], "freigabe-entzogen")

    def test_weitergabe_verliert_gueltigkeit_wenn_der_geber_nicht_mehr_hauptagent_ist(self):
        self.erteilen()
        af.weitergeben(self.world, "haupt", "hauptagent", "post", "email", ["info@example.org"])
        daten = json.loads((self.world / "agents" / "haupt" / "agent.json").read_text())
        daten["stage"] = "teamleiter"
        (self.world / "agents" / "haupt" / "agent.json").write_text(json.dumps(daten))
        self.assertEqual(af.gueltige(self.world, "post"), [])

    def test_controller_operationen_mit_meldung_an_den_menschen(self):
        self.erteilen(adressen=["info@example.org", "rechnung@example.org"])
        haupt = self.client("haupt", "hauptagent")
        lead = self.client("lead", "teamleiter")
        antwort = haupt.request("freigabe.weitergeben", {"agent_id": "post", "art": "email",
                                                         "adressen": ["info@example.org", "rechnung@example.org"]})
        self.assertEqual(antwort["inhaber"], "post")
        meldung = next(item for item in self.kanal() if item["id"] == antwort["meldung"])
        self.assertEqual((meldung["mark"], meldung["recipient"], meldung["sender"]), ("ergebnis", "mensch", "haupt"))
        self.assertIn("an post weitergegeben durch haupt", meldung["text"])
        self.assertIn("info@example.org, rechnung@example.org", meldung["text"])
        wiederholt = haupt.request("freigabe.weitergeben", {"agent_id": "post", "art": "email",
                                                            "adressen": ["info@example.org", "rechnung@example.org"]})
        self.assertIsNone(wiederholt["meldung"])
        with self.assertRaisesRegex(ac.ControllerError, "nur der Hauptagent"):
            lead.request("freigabe.weitergeben", {"agent_id": "post", "art": "email"})
        with self.assertRaisesRegex(ac.ControllerError, "nur der Hauptagent"):
            lead.request("freigabe.liste", {})
        with self.assertRaisesRegex(ac.ControllerError, "Nie weiter"):
            haupt.request("freigabe.weitergeben", {"agent_id": "recht", "art": "email",
                                                   "adressen": ["info@example.org", "technik@example.org"]})
        liste = haupt.request("freigabe.liste", {})
        self.assertEqual(sorted((item["inhaber"], item["gueltig"]) for item in liste),
                         [("haupt", True), ("post", True)])
        entzogen = haupt.request("freigabe.entziehen", {"agent_id": "post", "art": "email"})
        self.assertEqual(entzogen["entzogen"], [antwort["id"]])
        meldung = next(item for item in self.kanal() if item["id"] == entzogen["meldung"])
        self.assertIn("Freigabe email von post entzogen durch haupt", meldung["text"])
        with self.assertRaisesRegex(ac.ControllerError, "Unbekannte Payloadfelder"):
            haupt.request("freigabe.weitergeben", {"agent_id": "post", "art": "email", "inhaber": "haupt"})


class SendenTests(Grundlage):
    def mail(self, **extra):
        payload = {"von": "kontakt@example.org", "an": ["kunde@example.org"], "betreff": "Terminvorschlag",
                   "text": "Guten Tag,\nDienstag 10 Uhr ist frei.\n", "ticket_id": "t-1", "sendung_id": "s-1"}
        payload.update(extra)
        return payload

    def test_mail_senden_ueber_controller_mit_freigabe_logzeile_ohne_passwort(self):
        self.erteilen()
        af.weitergeben(self.world, "haupt", "hauptagent", "post", "email", ["kontakt@example.org"])
        post = self.client("post", "mitglied")
        ergebnis = post.request("mail.senden", self.mail(cc=["kollege@example.org"]))
        self.assertTrue(ergebnis["gesendet"])
        self.assertEqual(len(self.dummy.mails), 1)
        mail = self.dummy.mails[0]
        self.assertEqual(mail["von"], "kontakt@example.org")
        self.assertEqual(mail["an"], ["kunde@example.org", "kollege@example.org"])
        self.assertEqual(mail["kopf"]["Subject"], "Terminvorschlag")
        self.assertEqual(mail["kopf"]["Message-ID"], ergebnis["message_id"])
        self.assertEqual(self.dummy.anmeldungen, [{"benutzer": BENUTZER, "ok": True}])
        zeile = self.log()[-1]
        self.assertEqual({k: zeile[k] for k in ("agent", "ticket", "von", "an", "cc", "betreff", "sendung_id")},
                         {"agent": "post", "ticket": "t-1", "von": "kontakt@example.org", "an": ["kunde@example.org"],
                          "cc": ["kollege@example.org"], "betreff": "Terminvorschlag", "sendung_id": "s-1"})
        self.assertEqual(zeile["ergebnis"]["gesendet"], True)
        self.assertEqual(zeile["text_sha256"], af._sha256(self.mail()["text"]))
        self.assertTrue(zeile["freigabe"].startswith("fg-"))
        roh = (self.world / af.VERSANDLOG).read_text()
        self.assertNotIn(PASSWORT, roh)
        self.assertNotIn("Dienstag 10 Uhr", roh, "nie der Wortlaut im Log")
        self.assertEqual((self.world / af.VERSANDLOG).stat().st_mode & 0o777, 0o600)
        # Dieselbe Sendungskennung sendet nicht noch einmal.
        wieder = post.request("mail.senden", self.mail(cc=["kollege@example.org"]))
        self.assertTrue(wieder["wiederholt"])
        self.assertEqual(len(self.dummy.mails), 1)

    def test_abweisungen_und_fehler(self):
        post = self.client("post", "mitglied")
        with self.assertRaisesRegex(ac.ControllerError, "keine gueltige Freigabe email"):
            post.request("mail.senden", self.mail())
        self.assertEqual(self.log()[-1]["ergebnis"], {"gesendet": False, "abgewiesen": "keine Freigabe email"})
        self.erteilen()
        af.weitergeben(self.world, "haupt", "hauptagent", "post", "email", ["kontakt@example.org"])
        post = self.client("post", "mitglied")
        for von, text in (("privat@example.org", "nur gelesen"), ("neuigkeiten@example.org", "versand.py"),
                          ("info@example.org", "nicht in deiner Freigabe"), ("x@example.com", "keinem Konto")):
            with self.assertRaisesRegex(ac.ControllerError, text):
                post.request("mail.senden", self.mail(von=von, sendung_id="s-" + von))
        self.assertEqual(self.dummy.mails, [])
        with self.assertRaisesRegex(ac.ControllerError, "Betreff"):
            post.request("mail.senden", self.mail(betreff="Zeile\nBcc: boese@example.org"))
        # Ein SMTP-Fehler ist ein Fehler, kein stiller Erfolg; das Passwort steht nicht in der Meldung.
        self.dummy.passwort = "anderes"
        with self.assertRaisesRegex(ac.ControllerError, "SMTP-Versand gescheitert") as fehler:
            post.request("mail.senden", self.mail(sendung_id="s-fehler"))
        self.assertNotIn(PASSWORT, str(fehler.exception))
        self.assertEqual(self.log()[-1]["ergebnis"]["gesendet"], False)
        self.dummy.passwort = PASSWORT
        self.dummy.ablehnen.add("weg@example.org")
        with self.assertRaisesRegex(ac.ControllerError, "SMTP"):
            post.request("mail.senden", self.mail(an=["weg@example.org"], sendung_id="s-weg"))
        self.assertNotIn(PASSWORT, (self.world / af.VERSANDLOG).read_text())
        # Widerruf wirkt vor dem naechsten Versand.
        af.widerrufen(self.world, agent_id="haupt", absender="mensch")
        with self.assertRaisesRegex(ac.ControllerError, "keine gueltige Freigabe"):
            post.request("mail.senden", self.mail(sendung_id="s-nach-widerruf"))

    def test_klartext_nur_an_loopback(self):
        with self.assertRaisesRegex(af.MailFehler, "Loopback"):
            af.smtp_ziel("beispiel", {"WB_MAIL_SMTP": "smtp.example.org:25:klartext"})
        self.assertEqual(af.smtp_ziel("beispiel", {}), ("smtp.example.org", 465, "ssl"))
        self.assertEqual(af.smtp_ziel("zweit", {}), ("smtp.example.net", 587, "starttls"))

    def endpoint(self, agent, role):
        controller = ac.AgentController(self.world, "run-1", lambda _b: True, 1.0, 5.0)
        self.controllers.append(controller)
        ordner = self.root / "ctl"
        ordner.mkdir(mode=0o700, exist_ok=True)
        endpoint = ControllerEndpoint(controller, agent, role, ordner / ("%s.sock" % agent))
        self.addCleanup(endpoint.close)
        return endpoint

    def werkzeug(self, env, *args):
        textdatei = self.root / "entwurf.txt"
        textdatei.write_text("Guten Tag,\nder Beleg fehlt noch.\n")
        cmd = [sys.executable, str(SHELL / "wb-myproject"), "senden", "--von", "rechnung@example.org", "--an",
               "kunde@example.org", "--betreff", "Beleg", "--text", str(textdatei)] + list(args)
        return subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=60)

    @unittest.skipUnless((SHELL / "wb-myproject").exists(), "kit: the project mailbox tool is not shipped (port/strip.txt)")
    def test_wb_acme_senden_im_zug_ueber_den_controller(self):
        endpoint = self.endpoint("post", "mitglied")
        zug = {"PATH": "/usr/bin:/bin", "HOME": str(self.root / "zughome"), "WB_AGENT_ID": "post",
               "WB_WELT": str(self.world), "WB_CONTROLLER_SOCKET": str(endpoint.path)}
        ohne = self.werkzeug(zug)
        self.assertEqual(ohne.returncode, 3, ohne.stderr)
        self.assertIn("keine gueltige Freigabe email", ohne.stderr)
        self.erteilen()
        af.weitergeben(self.world, "haupt", "hauptagent", "post", "email", ["rechnung@example.org"])
        mit = self.werkzeug(zug, "--ticket", "t-7")
        self.assertEqual(mit.returncode, 0, mit.stderr)
        self.assertIn("gesendet von rechnung@example.org an kunde@example.org", mit.stdout)
        self.assertEqual(self.dummy.mails[-1]["rumpf"], "Guten Tag,\nder Beleg fehlt noch.\n")
        self.assertEqual(self.log()[-1]["ticket"], "t-7")
        for ausgabe in (ohne.stdout, ohne.stderr, mit.stdout, mit.stderr, (self.world / af.VERSANDLOG).read_text()):
            self.assertNotIn(PASSWORT, ausgabe)
        falsch = self.werkzeug(zug)
        self.assertEqual(falsch.returncode, 0)  # neue Sendungskennung: zweite Mail, gewollt
        weg = dict(zug)
        weg.pop("WB_AGENT_ID")
        self.assertEqual(self.werkzeug(weg).returncode, 3, "Zugumgebung ohne Agentenbindung sendet nie")
        # Im Zug hilft auch die Passwortdatei des Traegers nicht: das Werkzeug fasst sie nicht an.
        self.dummy.passwort = "anderes"
        gescheitert = self.werkzeug(zug)
        self.assertEqual(gescheitert.returncode, 1, gescheitert.stderr)
        self.assertIn("SMTP-Versand gescheitert", gescheitert.stderr)

    @unittest.skipUnless((SHELL / "wb-myproject").exists(), "kit: the project mailbox tool is not shipped (port/strip.txt)")
    def test_wb_acme_ignores_a_forged_home_human_probe(self):
        home = self.root / "mensch"
        (home / ".local" / "bin").mkdir(parents=True)
        messung = home / ".local" / "bin" / "wb-mensch"
        env = {"PATH": "/usr/bin:/bin", "HOME": str(home), "XDG_STATE_HOME": str(home / "state"),
               "AWB_STATE_DIR": str(self.zustand), "WB_MAIL_SMTP": os.environ["WB_MAIL_SMTP"],
               "WB_MAIL_SMTP_PASSWORT_DATEI": str(self.pwdatei)}
        messung.write_text("#!/bin/sh\nprintf 'agent\\tTest: kein Terminal\\n'\n")
        messung.chmod(0o755)
        kein = self.werkzeug(env)
        self.assertEqual(kein.returncode, 3, kein.stderr)
        self.assertIn("nur fuer einen Menschen", kein.stderr)
        messung.write_text("#!/bin/sh\nprintf 'mensch\\tTest: steuerndes Terminal\\n'\n")
        ok = self.werkzeug(env)
        self.assertEqual(ok.returncode, 3, ok.stderr)
        self.assertIn("nur fuer einen Menschen", ok.stderr)
        self.assertFalse((home / "state" / "wb-mail-agenten" / "beispiel" / af.VERSANDLOG).exists())


class SperreTests(Grundlage):
    def setUp(self):
        super().setUp()
        import profil_sperre
        self.sperre = profil_sperre
        for agent_id in ("post", "recht"):
            pfad = self.world / "agents" / agent_id / "agent.json"
            daten = json.loads(pfad.read_text())
            daten["tools"] = ["Bash", "Read"]
            daten["bash"] = list(ad.DEFAULT_BASH) + (["wb-myproject *"] if agent_id == "recht" else [])
            pfad.write_text(json.dumps(daten))

    def entscheiden(self, agent, befehl):
        env = {"WB_AGENT_ID": agent, "WB_WELT": str(self.world), "WB_PROFIL_BIN": str(SHELL / "wb-profil"),
               "HOME": str(Path.home())}
        with mock.patch.dict(os.environ, env):
            for name in ("WB_AGENT_PROFIL", "WB_WELT_PROJEKT", "WB_AGENT_WORKTREE", "WB_AGENT_TMP", "WB_ZUGAENGE"):
                os.environ.pop(name, None)
            return self.sperre.entscheiden({"tool_name": "Bash", "tool_input": {"command": befehl},
                                            "cwd": str(self.world / "agents" / agent)})

    def test_senden_nur_mit_freigabe(self):
        befehl = "wb-myproject senden --von info@example.org --an a@example.org --betreff x --text entwurf.txt"
        for agent in ("post", "recht"):
            grund = self.entscheiden(agent, befehl)
            self.assertIsNotNone(grund, agent)
            self.assertIn("email approval", grund)  # Kit: English lock texts
            self.assertIn("wb-welt freigabe", grund)
            self.assertIn("freigabe.weitergeben", grund)
        self.assertIsNone(self.entscheiden("recht", "wb-myproject recent 5"), "Lesen bleibt am Muster")
        self.assertIsNotNone(self.entscheiden("post", "wb-myproject recent 5"))
        self.erteilen()
        af.weitergeben(self.world, "haupt", "hauptagent", "post", "email", ["info@example.org"])
        self.assertIsNone(self.entscheiden("post", befehl))
        grund = self.entscheiden("post", befehl.replace("info@", "kontakt@"))
        self.assertIn("is not in your email approval", grund)
        self.assertIsNotNone(self.entscheiden("post", "echo x | xargs wb-myproject senden --von kontakt@example.org"))
        self.assertIsNone(self.entscheiden("post", "sh -c 'wb-myproject senden --von info@example.org --an a@b.de "
                                                   "--betreff x --text y'"))
        self.assertIsNotNone(self.entscheiden("recht", befehl))
        af.entziehen(self.world, "haupt", "hauptagent", "post", "email")
        self.assertIsNotNone(self.entscheiden("post", befehl))
        grund = self.entscheiden("post", "echo x >> %s" % (self.world / af.VERSANDLOG))
        self.assertIn("approval or carrier file", grund)

    def test_sperre_und_datenschicht_stimmen_ueberein(self):
        wurzel = self.erteilen(ablauf="2d")
        af.weitergeben(self.world, "haupt", "hauptagent", "post", "email", ["info@example.org"])
        jetzt = dt.datetime.now(dt.timezone.utc)
        for zeit in (jetzt, jetzt + dt.timedelta(days=3)):
            for agent in ("haupt", "post", "recht"):
                self.assertEqual(self.sperre.mail_freigabe(str(self.world), agent, zeit),
                                 af.adressen_von(af.gueltige(self.world, agent, jetzt=zeit)), (agent, zeit))
        # Im Zug ist das Profil des Hauptagenten nicht eingebunden: die Sperre laesst die Weitergabe dann gelten,
        # der Controller prueft die Stufe mit der ganzen Weltablage.
        haupt = self.world / "agents" / "haupt" / "agent.json"
        haupt.chmod(0)
        try:
            self.assertEqual(self.sperre.mail_freigabe(str(self.world), "post"), ["info@example.org"])
        finally:
            haupt.chmod(0o600)
        af.widerrufen(self.world, freigabe_id=wurzel["id"], absender="mensch")
        self.assertEqual(self.sperre.mail_freigabe(str(self.world), "post"), [])


class MailkontoTests(Grundlage):
    """Hostkonfiguration mailkonten.json: fehlt sie oder das Konto, scheitern Erteilung und Versand klar."""

    def welt_cli(self, *args):
        env = dict(os.environ, HOME=str(self.root), PATH="/usr/bin:/bin")
        return subprocess.run([str(SHELL / "wb-welt")] + list(args), capture_output=True, text=True, env=env,
                              timeout=60)

    def test_konfiguration_fehlt(self):
        wurzel = self.erteilen()
        weiter = af.weitergeben(self.world, "haupt", "hauptagent", "post", "email", ["kontakt@example.org"])
        self.konfig(None)
        erwartet = "Mailkonto beispiel ist auf diesem Host nicht eingerichtet: ~/%s" % (
            self.zustand / af.KONFIG_DATEI).relative_to(Path.home())
        with self.assertRaises(af.FreigabeFehler) as fehler:
            self.erteilen(agent="recht")
        self.assertEqual(str(fehler.exception), erwartet)
        with self.assertRaisesRegex(af.FreigabeFehler, "Mailkonto beispiel ist auf diesem Host nicht eingerichtet"):
            af.weitergeben(self.world, "haupt", "hauptagent", "recht", "email")
        post = self.client("post", "mitglied")
        payload = {"von": "kontakt@example.org", "an": ["kunde@example.org"], "betreff": "Frage", "text": "Hallo\n",
                   "sendung_id": "s-ohne-konfig"}
        with self.assertRaisesRegex(ac.ControllerError, "Mailkonto beispiel ist auf diesem Host nicht eingerichtet"):
            post.request("mail.senden", payload)
        self.assertEqual(self.dummy.mails, [])
        self.assertEqual(self.log()[-1]["ergebnis"]["gesendet"], False)
        # Lesen, Liste und Widerruf gehen ohne Konfiguration weiter.
        self.assertEqual([item["id"] for item in af.gueltige(self.world, "post")], [weiter["id"]])
        self.assertEqual(af.widerrufen(self.world, freigabe_id=wurzel["id"], absender="mensch"),
                         [wurzel["id"], weiter["id"]])
        zeigen = self.welt_cli("mailkonto", "zeigen")
        self.assertEqual(zeigen.returncode, 2, "Fehler der Datenschicht enden mit Exit 2")
        self.assertIn("Kein Mailkonto ist auf diesem Host eingerichtet", zeigen.stderr + zeigen.stdout)

    def test_konto_unbekannt(self):
        with self.assertRaisesRegex(af.FreigabeFehler, "Mailkonto gibtsnicht ist auf diesem Host nicht eingerichtet"):
            self.erteilen(konto="gibtsnicht")
        self.assertFalse((self.world / af.DATEI).exists())
        with self.assertRaisesRegex(af.MailFehler, "Mailkonto gibtsnicht ist auf diesem Host nicht eingerichtet"):
            af.versenden(agent=None, freigaben=None, logpfad=self.root / "log.jsonl", von="info@example.org",
                         an=["kunde@example.org"], betreff="x", text="y", konto="gibtsnicht")
        zeigen = self.welt_cli("mailkonto", "zeigen", "gibtsnicht")
        self.assertEqual(zeigen.returncode, 2, "Fehler der Datenschicht enden mit Exit 2")
        self.assertIn("Mailkonto gibtsnicht ist auf diesem Host nicht eingerichtet", zeigen.stderr + zeigen.stdout)

    def test_kaputte_konfiguration_und_geschrumpfter_umfang(self):
        kaputt = json.loads(json.dumps(KONFIG))
        kaputt["konten"]["beispiel"]["passwort"] = "NICHT-ECHT"
        self.konfig(kaputt)
        with self.assertRaisesRegex(af.FreigabeFehler, "unbekannte Felder passwort"):
            self.erteilen()
        fremd = json.loads(json.dumps(KONFIG))
        fremd["konten"]["beispiel"]["ohne_rueckfrage"].append("jemand@example.com")
        self.konfig(fremd)
        with self.assertRaisesRegex(af.FreigabeFehler, "Adressen der Domaene example.org"):
            self.erteilen()
        self.konfig(KONFIG)
        self.erteilen()
        af.weitergeben(self.world, "haupt", "hauptagent", "post", "email", ["kontakt@example.org"])
        kleiner = json.loads(json.dumps(KONFIG))
        kleiner["konten"]["beispiel"]["ohne_rueckfrage"].remove("kontakt@example.org")
        self.konfig(kleiner)
        post = self.client("post", "mitglied")
        with self.assertRaisesRegex(ac.ControllerError, "keinen Umfang „ohne Rückfrage“ mehr"):
            post.request("mail.senden", {"von": "kontakt@example.org", "an": ["kunde@example.org"],
                                         "betreff": "Frage", "text": "Hallo\n", "sendung_id": "s-klein"})
        self.assertEqual(self.dummy.mails, [])

    def test_wb_welt_mailkonto_zeigen(self):
        alle = self.welt_cli("mailkonto", "zeigen")
        self.assertEqual(alle.returncode, 0, alle.stderr)
        self.assertIn("beispiel (@example.org)", alle.stdout)
        self.assertIn("zweit (@example.net)", alle.stdout)
        self.assertIn("Werkzeug: wb-myproject senden", alle.stdout)
        self.assertIn("Sendet nie: privat@example.org", alle.stdout)
        eins = self.welt_cli("mailkonto", "zeigen", "zweit", "--json")
        self.assertEqual(eins.returncode, 0, eins.stderr)
        daten = json.loads(eins.stdout)
        self.assertEqual(list(daten["konten"]), ["zweit"])
        self.assertEqual(daten["konten"]["zweit"]["smtp_modus"], "starttls")
        self.assertEqual(daten["datei"], "~/zustand/%s" % af.KONFIG_DATEI, "HOME des Aufrufs ist self.root")
        self.assertNotIn(PASSWORT, alle.stdout + alle.stderr + eins.stdout)

    def test_sperre_kennt_das_werkzeug_jedes_kontos(self):
        import profil_sperre
        pfad = self.world / "agents" / "post" / "agent.json"
        daten = json.loads(pfad.read_text())
        daten["tools"], daten["bash"] = ["Bash", "Read"], list(ad.DEFAULT_BASH) + ["wb-zweit *"]
        pfad.write_text(json.dumps(daten))

        def entscheiden(befehl):
            env = {"WB_AGENT_ID": "post", "WB_WELT": str(self.world), "WB_PROFIL_BIN": str(SHELL / "wb-profil"),
                   "HOME": str(Path.home())}
            with mock.patch.dict(os.environ, env):
                for name in ("WB_AGENT_PROFIL", "WB_WELT_PROJEKT", "WB_AGENT_WORKTREE", "WB_AGENT_TMP", "WB_ZUGAENGE"):
                    os.environ.pop(name, None)
                return profil_sperre.entscheiden({"tool_name": "Bash", "tool_input": {"command": befehl},
                                                  "cwd": str(self.world / "agents" / "post")})

        zweit = "wb-zweit senden --von hallo@example.net --an a@example.org --betreff x --text y"
        self.assertIsNone(entscheiden(zweit), "ohne Freigabe fuer wb-zweit gilt noch das Bash-Muster")
        self.erteilen(adressen=["hallo@example.net"], konto="zweit")
        self.erteilen(adressen=["info@example.org"])
        af.weitergeben(self.world, "haupt", "hauptagent", "post", "email", ["info@example.org"])
        self.assertEqual(profil_sperre.mail_werkzeuge(str(self.world)), {"wb-myproject", "wb-zweit"})
        grund = entscheiden(zweit)
        self.assertIsNotNone(grund, "sobald ein Konto wb-zweit nennt, braucht senden eine Freigabe")
        self.assertIn("'wb-zweit senden' needs an email approval", grund)
        self.assertIsNone(entscheiden("wb-myproject senden --von info@example.org --an a@example.org --betreff x "
                                      "--text y"))
        self.assertIn("is not in your email approval", entscheiden(
            "wb-myproject senden --von hallo@example.net --an a@example.org --betreff x --text y"))
        af.weitergeben(self.world, "haupt", "hauptagent", "post", "email", ["hallo@example.net"])
        self.assertEqual(profil_sperre.mail_freigabe(str(self.world), "post", werkzeug="wb-zweit"),
                         ["hallo@example.net"])
        self.assertIsNone(entscheiden(zweit))
        # Eine alte Freigabe ohne Feld werkzeug gilt fuer den Rueckfall.
        eintraege = json.loads((self.world / af.DATEI).read_text())
        for item in eintraege["freigaben"]:
            item.pop("werkzeug", None)
        (self.world / af.DATEI).write_text(json.dumps(eintraege))
        self.assertEqual(profil_sperre.mail_werkzeuge(str(self.world)), {"wb-myproject"})
        self.assertEqual(sorted(profil_sperre.mail_freigabe(str(self.world), "post")),
                         sorted(af.adressen_von(af.gueltige(self.world, "post"))))


if __name__ == "__main__":
    unittest.main()
