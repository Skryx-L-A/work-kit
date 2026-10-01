#!/usr/bin/env python3
"""Regression proof for sender provenance on the host CLI and controller path.

ISOLATION: every case creates one temporary world.  The forged-home case only
writes an executable below that temporary HOME; the production probe still has
to agree from the account home obtained through the user database.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import hmac
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve()
SHELL = HERE.parents[1]
sys.path.insert(0, str(SHELL))

import agents_controller as ac  # noqa: E402
import agents_data as ad  # noqa: E402
import agents_freigaben as af  # noqa: E402
import agents_zugaenge as az  # noqa: E402
from herkunft_fixture import aufbau_herkunft, gemessener_mensch  # noqa: E402


class HerkunftsbelegTests(unittest.TestCase):
    def setUp(self):
        self.saved_agent_markers = {name: os.environ.pop(name) for name in list(os.environ)
                                    if name == "CLAUDECODE" or name.startswith("CLAUDE_CODE_")
                                    or name == "PI_AGENT" or name.startswith("WB_AGENT")}
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-herkunft-")
        self.root = Path(self.tmp.name)
        self.world = self.root / "welt"
        self.home = self.root / "home"
        self.beleg_dir = self.home / ".claude" / "workbench" / "mobile" / "belege"
        self.beleg_dir.mkdir(parents=True, mode=0o700)
        self.beleg_dir.chmod(0o700)
        self.key = bytes(range(32))
        self.key_path = self.beleg_dir / ".schluessel"
        self.key_path.write_bytes(self.key)
        self.key_path.chmod(0o600)
        self.home_patch = mock.patch.object(ad, "_real_home", return_value=self.home)
        self.home_patch.start()
        self.aufbau_context = aufbau_herkunft(ad)
        self.aufbau = self.aufbau_context.__enter__()
        with gemessener_mensch(ad):
            ad.create_world(self.world, name="Herkunft", main_name="main", sender="mensch")
            ad.create_agent(self.world, "m1", "mitglied", None, "Bearbeitet", None, None,
                            None, None, None, None, "lokal", "mensch", None)

    def tearDown(self):
        self.aufbau_context.__exit__(None, None, None)
        self.home_patch.stop()
        self.tmp.cleanup()
        os.environ.update(self.saved_agent_markers)

    def reifes_ticket(self, ticket_id="t1", sender="main"):
        ad.create_ticket(self.world, "Herkunft pruefen", "Ziel", "Fertig", ["m1"], sender,
                         "hauptagent", ticket_id=ticket_id)
        ad.claim_ticket(self.world, ticket_id, "m1", "m1", "mitglied")
        ad.write_result(self.world, ticket_id, "m1", "Ergebnis", None, "m1", "mitglied")

    def test_gefälschtes_home_und_menschenname_werden_explizit_abgelehnt(self):
        """The old data layer accepted this exact call; it is now the regression vector."""
        self.reifes_ticket()
        fake_home = self.root / "fake-home"
        probe = fake_home / ".local" / "bin" / "wb-mensch"
        probe.parent.mkdir(parents=True)
        probe.write_text("#!/bin/sh\nprintf 'mensch\\tgefälschter Beleg\\n'\n", encoding="utf-8")
        probe.chmod(0o755)
        env = dict(os.environ, HOME=str(fake_home), PYTHONPATH=str(SHELL), CLAUDECODE="angriff")
        run = subprocess.run([str(SHELL / "wb-ticket"), "abnehmen", str(self.world), "t1",
                              "--absender", "mensch", "--grund", "erledigt",
                              "--herkunft-beleg", "wb-mensch"], text=True, capture_output=True,
                             env=env, timeout=15)
        self.assertEqual(run.returncode, 2, run.stderr)
        self.assertIn("Herkunftsbeleg fuer Menschenname 'mensch' abgelehnt", run.stderr)
        self.assertIn("Agenten-Marker CLAUDECODE", run.stderr)
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "zur Abnahme")

    def test_path_hijack_of_wb_mensch_is_ignored_and_explicitly_denied(self):
        self.reifes_ticket()
        fakebin = self.root / "fakebin"
        fakebin.mkdir()
        fake_ps = fakebin / "ps"
        fake_ps.write_text("#!/bin/sh\ncase \"$*\" in *tty=*) echo ttys999;; *) echo '1 safeproc';; esac\n",
                           encoding="utf-8")
        fake_ps.chmod(0o755)
        token = ad._HERKUNFTSBELEG.set("wb-mensch")
        try:
            with mock.patch.dict(os.environ, {"PATH": "%s:/usr/bin:/bin" % fakebin}), \
                    mock.patch.object(ad, "_trusted_wb_mensch_paths", return_value=(SHELL / "wb-mensch",)):
                with self.assertRaisesRegex(ad.AgentsError, "Herkunftsbeleg.*lehnt ab"):
                    ad.approve_ticket(self.world, "t1", "mensch", None, None, True, "erledigt")
        finally:
            ad._HERKUNFTSBELEG.reset(token)
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "zur Abnahme")

    def test_agent_markers_deny_before_the_human_probe(self):
        for marker in ("CLAUDECODE", "CLAUDE_CODE_SESSION_ID", "PI_AGENT", "WB_AGENT", "WB_AGENT_ZUG"):
            with self.subTest(marker=marker), mock.patch.dict(os.environ, {marker: "angriff"}), \
                    mock.patch.object(ad.subprocess, "run") as run:
                measured, reason = ad._measured_human()
                self.assertFalse(measured)
                self.assertIn("Agenten-Marker %s" % marker, reason)
                run.assert_not_called()

    def test_aufbau_is_limited_to_creation_even_with_the_process_fixture(self):
        ticket = ad.create_ticket(self.world, "Aufbau", "Ziel", "Fertig", ["m1"],
                                  self.aufbau, None, ticket_id="t-aufbau")
        event = ad._read_jsonl(self.world / "tickets" / "t-aufbau" / "verlauf.jsonl", "Testverlauf")[0]
        self.assertEqual((ticket["sender"], event["actor"]["id"], event["actor"]["kind"],
                          event["actor"]["verified"], event["actor"]["source"]),
                         ("aufbau", "aufbau", "external", False, "test-aufbau"))
        with self.assertRaisesRegex(ad.AgentsError, "Absender 'aufbau' unbekannt"):
            ad.discard_ticket(self.world, "t-aufbau", "nicht-mehr-noetig", sender=self.aufbau)
        with self.assertRaisesRegex(ad.AgentsError, "Absender 'aufbau' unbekannt"):
            ad.set_agent_rights(self.world, "m1", {"tools": ["Read"]}, self.aufbau)
        with self.assertRaisesRegex(ad.AgentsError, "Absender 'aufbau' unbekannt"):
            ad._require_human(self.world, self.aufbau, None, "Freigaben erteilen")

        ad.claim_ticket(self.world, "t-aufbau", "m1", "m1", "mitglied")
        ad.write_result(self.world, "t-aufbau", "m1", "Ergebnis", None, "m1", "mitglied")
        with self.assertRaisesRegex(ad.AgentsError, "Absender 'aufbau' unbekannt"):
            ad.approve_ticket(self.world, "t-aufbau", self.aufbau, None, None, True, "erledigt")
        self.assertEqual(ad.read_ticket(self.world, "t-aufbau")["state"], "zur Abnahme")

    def test_cli_aufbau_requires_private_runner_proof(self):
        cli_home = self.root / "cli-home"
        cli_home.mkdir(mode=0o700)
        cli_home.chmod(0o700)
        proof = cli_home / ".wb-test-aufbau-beleg"
        proof.write_bytes(os.urandom(32))
        proof.chmod(0o600)
        env = dict(os.environ, HOME=str(cli_home), WB_TEST_AUFBAU_BELEG=str(proof))
        cli_world = self.root / "cli-welt"

        denied = subprocess.run([str(SHELL / "wb-welt"), "neu", str(cli_world),
                                 "--hauptagent", "haupt", "--absender", "aufbau", "--json"],
                                text=True, capture_output=True,
                                env={key: value for key, value in env.items()
                                     if key != "WB_TEST_AUFBAU_BELEG"}, timeout=15)
        self.assertEqual(denied.returncode, 2, denied.stderr)
        self.assertIn("Aufbau-Herkunftsbeleg abgelehnt", denied.stderr)

        created = subprocess.run([str(SHELL / "wb-welt"), "neu", str(cli_world),
                                  "--hauptagent", "haupt", "--absender", "aufbau", "--json"],
                                 text=True, capture_output=True, env=env, timeout=15)
        self.assertEqual(created.returncode, 0, created.stderr)
        agent = subprocess.run([str(SHELL / "wb-agent"), "neu", str(cli_world), "--name", "worker",
                                "--stufe", "mitglied", "--beschreibung", "Baut", "--absender", "aufbau",
                                "--json"], text=True, capture_output=True, env=env, timeout=15)
        self.assertEqual(agent.returncode, 0, agent.stderr)
        ticket = subprocess.run([str(SHELL / "wb-ticket"), "neu", str(cli_world), "--id", "t-cli-aufbau",
                                 "--titel", "Bau", "--ziel", "Ziel", "--fertig", "Fertig", "--an", "worker",
                                 "--absender", "aufbau", "--json"], text=True, capture_output=True,
                                env=env, timeout=15)
        self.assertEqual(ticket.returncode, 0, ticket.stderr)
        self.assertEqual(json.loads(ticket.stdout)["sender"], "aufbau")

        proof.chmod(0o644)
        wrong_mode = subprocess.run([str(SHELL / "wb-ticket"), "neu", str(cli_world), "--id", "t-falsch",
                                     "--titel", "Bau", "--ziel", "Ziel", "--fertig", "Fertig", "--an", "worker",
                                     "--absender", "aufbau", "--json"], text=True, capture_output=True,
                                    env=env, timeout=15)
        self.assertEqual(wrong_mode.returncode, 2, wrong_mode.stderr)
        self.assertIn("Modus 0600", wrong_mode.stderr)

        proof.chmod(0o600)
        outside = self.root / "beleg-ausserhalb-home"
        outside.write_bytes(os.urandom(32))
        outside.chmod(0o600)
        outside_env = dict(env, WB_TEST_AUFBAU_BELEG=str(outside))
        wrong_place = subprocess.run([str(SHELL / "wb-ticket"), "neu", str(cli_world), "--id", "t-aussen",
                                      "--titel", "Bau", "--ziel", "Ziel", "--fertig", "Fertig", "--an", "worker",
                                      "--absender", "aufbau", "--json"], text=True, capture_output=True,
                                     env=outside_env, timeout=15)
        self.assertEqual(wrong_place.returncode, 2, wrong_place.stderr)
        self.assertIn("unter dem Prozess-HOME", wrong_place.stderr)

        link = cli_home / ".wb-test-aufbau-link"
        link.symlink_to(proof)
        link_env = dict(env, WB_TEST_AUFBAU_BELEG=str(link))
        symlink = subprocess.run([str(SHELL / "wb-ticket"), "neu", str(cli_world), "--id", "t-link",
                                  "--titel", "Bau", "--ziel", "Ziel", "--fertig", "Fertig", "--an", "worker",
                                  "--absender", "aufbau", "--json"], text=True, capture_output=True,
                                 env=link_env, timeout=15)
        self.assertEqual(symlink.returncode, 2, symlink.stderr)
        self.assertIn("symlinkfrei", symlink.stderr)

    def test_human_probe_receives_sanitized_loader_and_search_environment(self):
        completed = subprocess.CompletedProcess([], 0, "mensch\tTest M1\n", "")
        with mock.patch.object(ad, "_trusted_wb_mensch_paths", return_value=(SHELL / "wb-mensch",)), \
                mock.patch.dict(os.environ, {"PATH": "/angriff", "PYTHONPATH": "/angriff",
                                             "DYLD_INSERT_LIBRARIES": "/angriff", "LD_PRELOAD": "/angriff",
                                             "WB_MENSCH_QUELLE": "", "WB_APP_PID": ""}), \
                mock.patch.object(ad.subprocess, "run", return_value=completed) as run:
            self.assertTrue(ad._measured_human()[0])
        probe_env = run.call_args.kwargs["env"]
        self.assertEqual(probe_env, {"HOME": os.environ["HOME"],
                                     "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                                     "TMPDIR": "/tmp"})

    def test_human_probe_forwards_only_the_m2_claim_that_wb_mensch_revalidates(self):
        completed = subprocess.CompletedProcess([], 0, "mensch\tTest M2\n", "")
        with mock.patch.object(ad, "_trusted_wb_mensch_paths", return_value=(SHELL / "wb-mensch",)), \
                mock.patch.dict(os.environ, {"WB_MENSCH_QUELLE": "oberflaeche", "WB_APP_PID": "4242",
                                             "BASH_ENV": "/angriff", "DYLD_INSERT_LIBRARIES": "/angriff"}), \
                mock.patch.object(ad.subprocess, "run", return_value=completed) as run:
            self.assertTrue(ad._measured_human()[0])
        self.assertEqual(run.call_args.kwargs["env"], {
            "HOME": os.environ["HOME"],
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": "/tmp",
            "WB_MENSCH_QUELLE": "oberflaeche", "WB_APP_PID": "4242",
        })

    def test_bash_env_cannot_forge_the_real_human_probe(self):
        marker = self.root / "bash-env-was-sourced"
        attack = self.root / "bash-env-attack.sh"
        attack.write_text("/usr/bin/touch %s\nprintf 'mensch\\tgefälscht\\n'\nexit 0\n" % marker,
                          encoding="utf-8")
        with mock.patch.object(ad, "_trusted_wb_mensch_paths", return_value=(SHELL / "wb-mensch",)), \
                mock.patch.dict(os.environ, {"HOME": str(self.home), "BASH_ENV": str(attack)}):
            measured, reason = ad._measured_human()
        self.assertFalse(measured, reason)
        self.assertFalse(marker.exists(), "BASH_ENV reached wb-mensch")
        self.assertNotIn("gefälscht", reason)

    def test_freigabe_probe_uses_the_same_exact_environment(self):
        completed = subprocess.CompletedProcess([], 0, "mensch\tTest M1\n", "")
        run = mock.Mock(return_value=completed)
        with mock.patch.object(ad, "_trusted_wb_mensch_paths", return_value=(SHELL / "wb-mensch",)):
            self.assertEqual(af.mensch_messen(runner=run), ("mensch", "Test M1"))
        self.assertEqual(run.call_args.kwargs["env"], ad._human_probe_env())

    def test_pane_writer_verifiers_have_no_inherited_environment_or_path_fallback(self):
        source = (SHELL / "wb-pane-write").read_text(encoding="utf-8")
        human = source[source.index("ist_mensch()") : source.index("# --- Rolle des Panes")]
        self.assertIn('for pfad in "$heim/.local/bin/wb-mensch" "$echt/.local/bin/wb-mensch"', human)
        helper = source[source.index("echtes_home()") : source.index("# --- Rolle des Panes")]
        self.assertIn('/usr/bin/env -i HOME="$HOME" TMPDIR=/tmp PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin', helper)
        self.assertIn("pwd.getpwuid(os.getuid()).pw_dir", helper)
        self.assertNotIn("command -v wb-mensch", human)
        self.assertIn('/usr/bin/env -i HOME="$HOME" TMPDIR=/tmp PATH=/usr/bin:/bin /usr/bin/python3',
                      source)
        self.assertIn('/usr/bin/env -i HOME="$HOME" TMPDIR=/tmp PATH="$MOBIL_SAUBER_PATH"', source)

    def test_all_repo_human_probe_subprocesses_have_an_explicit_allowlist(self):
        """Repo grep: every shell/Python probe has an explicit environment allowlist."""
        safe = '/usr/bin/env -i HOME="$HOME" TMPDIR=/tmp PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'
        shell_files = ("pi-worker", "wb-code", "wb-freigabe", "wb-rolle", "wb-enginex-server")
        for name in shell_files:
            if not (SHELL / name).exists():  # Kit: private lanes are not shipped
                continue
            source = (SHELL / name).read_text(encoding="utf-8")
            lines = source.splitlines()
            probes = [index for index, line in enumerate(lines)
                      if "/wb-mensch\" pruefen" in line or "/wb-mensch\" beleg" in line]
            self.assertTrue(probes, name)
            for index in probes:
                self.assertIn(safe, "\n".join(lines[max(0, index - 2):index + 1]),
                              "%s:%d has an inherited probe environment" % (name, index + 1))

        found = subprocess.run(
            ["rg", "-l", "subprocess\\.run", str(SHELL / "agents_data.py"),
             str(SHELL / "agents_freigaben.py"),  # Kit: wb-ausrollen is not shipped
             str(SHELL / "wb-aufgabe"), str(SHELL / "wb-belegung"), str(SHELL / "wb-inbox"),
             str(SHELL / "wb-profil"), str(SHELL / "wb-state")],
            text=True, capture_output=True, check=True)
        self.assertEqual(set(found.stdout.splitlines()), {
            str(SHELL / name) for name in ("agents_data.py", "agents_freigaben.py",
                                           "wb-aufgabe", "wb-belegung", "wb-inbox", "wb-profil", "wb-state")})
        for name in ("wb-aufgabe", "wb-belegung", "wb-inbox", "wb-profil", "wb-state"):
            source = (SHELL / name).read_text(encoding="utf-8")
            self.assertIn('"PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"', source, name)
            self.assertIn('"TMPDIR": "/tmp"', source, name)
        self.assertIn("env=_human_probe_env()", (SHELL / "agents_data.py").read_text(encoding="utf-8"))
        self.assertIn("env=ad._human_probe_env()",
                      (SHELL / "agents_freigaben.py").read_text(encoding="utf-8"))

        context_guard = (SHELL / "context-guard").read_text(encoding="utf-8")
        self.assertNotIn("wb-mensch", context_guard,
                         "context-guard must not grow an unsanitized second human probe")

    def test_setup_created_leader_cannot_gain_governance(self):
        setup_world = self.root / "setup-world"
        ad.create_world(setup_world, name="Setup", main_name="setup-main", sender=self.aufbau)
        ad.create_agent(setup_world, "setup-lead", "teamleiter", "t", "Leitet", None, None,
                        None, None, None, None, "lokal", self.aufbau, None)
        ad.create_agent(setup_world, "setup-member", "mitglied", "t", "Arbeitet", None, None,
                        None, None, None, None, "lokal", self.aufbau, None)
        lead = ad.read_agent(setup_world, "setup-lead")
        self.assertEqual(lead["created_by"], {"id": "aufbau", "kind": "external",
                                              "verified": False, "source": "test-aufbau",
                                              "origin": "aufbau"})
        ad.create_agent(setup_world, "laundered-lead", "teamleiter", "t", "Leitet auch", None,
                        None, None, None, None, None, "lokal", "setup-main", "hauptagent")
        self.assertEqual(ad.read_agent(setup_world, "laundered-lead")["created_by"]["origin"], "aufbau")
        ad.create_ticket(setup_world, "Setup", "Ziel", "Fertig", ["setup-member"],
                         self.aufbau, None, team="t", ticket_id="t-setup")
        ad.claim_ticket(setup_world, "t-setup", "setup-member", "setup-member", "mitglied")
        ad.write_result(setup_world, "t-setup", "setup-member", "Ergebnis", None,
                        "setup-member", "mitglied")
        with self.assertRaisesRegex(ad.AgentsError, "Aufbau-Herkunft.*governance"):
            ad.approve_ticket(setup_world, "t-setup", "setup-lead", "teamleiter", None,
                              True, "erledigt")
        with self.assertRaisesRegex(ad.AgentsError, "Aufbau-Herkunft.*governance"):
            ad.approve_ticket(setup_world, "t-setup", "laundered-lead", "teamleiter", None,
                              True, "erledigt")
        with self.assertRaisesRegex(ad.AgentsError, "Aufbau-Herkunft.*governance"):
            ad.set_agent_rights(setup_world, "setup-member", {"tools": ["Read"]}, "setup-main")
        with self.assertRaisesRegex(af.FreigabeFehler, "Aufbau-Herkunft.*governance"):
            af._hauptagent(setup_world, "setup-main", "hauptagent", "Freigaben weitergeben")

    def test_world_without_sender_requires_measurement_and_persists_it(self):
        denied_world = self.root / "denied-world"
        with mock.patch.object(ad, "_measured_human", return_value=(False, "kein Mensch")):
            with self.assertRaisesRegex(ad.AgentsError, "Herkunftsbeleg.*abgelehnt"):
                ad.create_world(denied_world, name="Nein")
        self.assertFalse(denied_world.exists())

        measured_world = self.root / "measured-world"
        with mock.patch.object(ad, "_measured_human", return_value=(True, "Test M1")):
            created = ad.create_world(measured_world, name="Ja")
        expected = {"id": "mensch", "kind": "external", "verified": True, "source": "wb-mensch"}
        self.assertEqual(created["world"]["created_by"], expected)
        self.assertEqual(created["hauptagent"]["created_by"], expected)

    def test_demo_human_fixture_cannot_mutate_outside_its_temp_root(self):
        outside = self.root.parent / (self.root.name + "-outside")
        run = subprocess.run([sys.executable, str(SHELL / "demo_welt_schritte.py"),
                              "welt", "neu", str(outside), "--absender=mensch", "--json"],
                             text=True, capture_output=True,
                             env=dict(os.environ, WB_DEMO_ROOT=str(self.root)), timeout=15)
        self.assertEqual(run.returncode, 2, run.stderr)
        self.assertIn("ausserhalb der Demo-Wurzel", run.stderr)
        self.assertFalse(outside.exists())

    def test_human_mutations_fail_closed_before_any_write(self):
        self.reifes_ticket()
        refused = (False, "Test-Agentenzug")
        with mock.patch.object(ad, "_measured_human", return_value=refused):
            for action in (
                lambda: ad.approve_ticket(self.world, "t1", "mensch", None, None, True, "erledigt"),
                lambda: ad.discard_ticket(self.world, "t1", "abgelehnt", sender="mensch"),
                lambda: ad.set_agent_rights(self.world, "m1", {"skills": ["texte-schreiben"]}, "mensch"),
                lambda: af.widerrufen(self.world, agent_id="m1", grund="Test", absender="mensch"),
                lambda: az.entfernen(self.world, "nicht-da", absender="mensch"),
            ):
                with self.assertRaisesRegex(ad.AgentsError, "Herkunftsbeleg fuer Menschenname"):
                    action()
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "zur Abnahme")
        self.assertNotIn("rights_updated_at", ad.read_agent(self.world, "m1"))

    def test_fixture_measured_human_approves_and_audits_verification(self):
        """A unit fixture proves persistence; it is not an M1/M2 end-to-end measurement."""
        self.reifes_ticket()
        with mock.patch.object(ad, "_measured_human", return_value=(True, "Test fixture M1")):
            approved = ad.approve_ticket(self.world, "t1", "mensch", None, None, True, "erledigt")
        self.assertEqual(approved["state"], "abgenommen")
        self.assertTrue(approved["approval"]["verified"])

    def mobile_beleg(self, name="beleg.json", directory=None, **werte):
        data = {"aktion": "ticket-abnehmen", "welt": str(self.world), "ticket": "t1", "grund": "erledigt",
                "bemerkung": "", "dod_geprueft": False, "request_id": "req-1",
                "ausgestellt_um": dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds")
                .replace("+00:00", "Z")}
        data.update(werte)
        canonical = "|".join(str(data[field]) if field != "dod_geprueft"
                             else ("true" if data[field] else "false")
                             for field in ad.MOBILE_BELEG_FIELDS)
        data.setdefault("quittung", hmac.new(self.key, canonical.encode("utf-8"), hashlib.sha256).hexdigest())
        path = (directory or self.beleg_dir) / name
        path.write_text(json.dumps(data), encoding="utf-8")
        path.chmod(0o600)
        return path

    def run_mobile(self, beleg, ticket="t1"):
        stderr, stdout = StringIO(), StringIO()
        with redirect_stderr(stderr), redirect_stdout(stdout):
            status = ad.run("ticket", ["abnehmen", str(self.world), ticket, "--absender", "mensch",
                                       "--grund", "erledigt", "--herkunft-beleg", "mobil:%s" % beleg,
                                       "--json"])
        return status, stdout.getvalue(), stderr.getvalue()

    def test_mobile_beleg_approves_only_the_bound_ticket(self):
        self.reifes_ticket()
        beleg = self.mobile_beleg()
        status, stdout, stderr = self.run_mobile(beleg)
        self.assertEqual(status, 0, stderr)
        approved = json.loads(stdout)
        self.assertEqual((approved["state"], approved["approval"]["agent"], approved["approval"]["verified"]),
                         ("abgenommen", "mensch", True))
        self.assertEqual(approved["approval"]["herkunft"], {"art": "mobil-kern", "request_id": "req-1"})
        history = [json.loads(line) for line in (self.world / "tickets" / "t1" / "verlauf.jsonl")
                   .read_text(encoding="utf-8").splitlines()]
        self.assertEqual(next(entry for entry in history if entry["event"] == "abgenommen")["actor"]["source"],
                         "mobil-kern")
        used = [json.loads(line) for line in (self.world / "belege-verbraucht.jsonl")
                .read_text(encoding="utf-8").splitlines()]
        self.assertEqual([item["request_id"] for item in used], ["req-1"])

    def test_mobile_beleg_rejects_foreign_path_with_explicit_error(self):
        self.reifes_ticket()
        status, _, stderr = self.run_mobile(self.mobile_beleg(directory=self.root))
        self.assertEqual(status, 2)
        self.assertIn("Mobilbeleg liegt nicht im festen Belegverzeichnis", stderr)
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "zur Abnahme")

    def test_mobile_beleg_rejects_symlink_with_explicit_error(self):
        self.reifes_ticket()
        target = self.mobile_beleg(directory=self.root)
        link = self.beleg_dir / "link.json"
        link.symlink_to(target)
        status, _, stderr = self.run_mobile(link)
        self.assertEqual(status, 2)
        self.assertIn("Mobilbeleg darf kein Symlink sein", stderr)

    def test_mobile_beleg_rejects_wrong_bound_field_with_explicit_error(self):
        self.reifes_ticket()
        status, _, stderr = self.run_mobile(self.mobile_beleg(ticket="anderes-ticket"))
        self.assertEqual(status, 2)
        self.assertIn("Mobilbeleg bindet ein anderes Ticket", stderr)

    def test_mobile_beleg_rejects_wrong_receipt_with_explicit_error(self):
        self.reifes_ticket()
        status, _, stderr = self.run_mobile(self.mobile_beleg(quittung="0" * 64))
        self.assertEqual(status, 2)
        self.assertIn("Mobilbeleg hat eine ungueltige Quittung", stderr)

    def test_mobile_beleg_rejects_old_timestamp_with_explicit_error(self):
        self.reifes_ticket()
        old = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(seconds=121)).isoformat().replace("+00:00", "Z")
        status, _, stderr = self.run_mobile(self.mobile_beleg(ausgestellt_um=old))
        self.assertEqual(status, 2)
        self.assertIn("Mobilbeleg ist aelter als 120 Sekunden", stderr)

    def test_mobile_beleg_rejects_repeated_request_id_with_explicit_error(self):
        self.reifes_ticket()
        beleg = self.mobile_beleg()
        self.assertEqual(self.run_mobile(beleg)[0], 0)
        status, _, stderr = self.run_mobile(beleg)
        self.assertEqual(status, 2)
        self.assertIn("Mobilbeleg-request_id wurde bereits verbraucht", stderr)

    def test_rejected_mobile_approval_does_not_consume_request_id(self):
        ad.create_ticket(self.world, "Noch offen", "Ziel", "Fertig", ["m1"], "main",
                         "hauptagent", ticket_id="t1")
        beleg = self.mobile_beleg()
        status, _, stderr = self.run_mobile(beleg)
        self.assertEqual(status, 2)
        self.assertIn("keine Abnahme moeglich", stderr)
        self.assertFalse((self.world / ad.MOBILE_BELEG_USED_FILE).exists())

        ad.claim_ticket(self.world, "t1", "m1", "m1", "mitglied")
        ad.write_result(self.world, "t1", "m1", "Ergebnis", None, "m1", "mitglied")
        status, _, stderr = self.run_mobile(beleg)
        self.assertEqual(status, 0, stderr)
        used = ad._read_jsonl(self.world / ad.MOBILE_BELEG_USED_FILE, "Testverbrauch")
        self.assertEqual([entry["request_id"] for entry in used], ["req-1"])

    def test_mobile_beleg_rejects_missing_field_and_pipe_in_note(self):
        self.reifes_ticket()
        missing = self.mobile_beleg()
        data = json.loads(missing.read_text(encoding="utf-8"))
        del data["dod_geprueft"]
        missing.write_text(json.dumps(data), encoding="utf-8")
        status, _, stderr = self.run_mobile(missing)
        self.assertEqual(status, 2)
        self.assertIn("Mobilbeleg hat Pflichtfeld(er) nicht: dod_geprueft", stderr)

        pipe = self.mobile_beleg(name="pipe.json", request_id="req-pipe", bemerkung="a|b")
        status, _, stderr = self.run_mobile(pipe)
        self.assertEqual(status, 2)
        self.assertIn("Mobilbeleg-Bemerkung darf kein Trennzeichen | enthalten", stderr)

    def test_mobile_beleg_rejects_missing_key_and_insecure_modes(self):
        self.reifes_ticket()
        beleg = self.mobile_beleg()
        self.key_path.unlink()
        status, _, stderr = self.run_mobile(beleg)
        self.assertEqual(status, 2)
        self.assertIn("Mobilbeleg-Schluessel fehlt", stderr)

        self.key_path.write_bytes(self.key)
        self.key_path.chmod(0o600)
        beleg.chmod(0o644)
        status, _, stderr = self.run_mobile(beleg)
        self.assertEqual(status, 2)
        self.assertIn("Mobilbeleg muss Modus 0600 haben", stderr)
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "zur Abnahme")

    def test_cli_surface_can_create_and_report_but_not_mutate_governance(self):
        stderr, stdout = StringIO(), StringIO()
        with redirect_stderr(stderr), redirect_stdout(stdout):
            status = ad.run("ticket", ["neu", str(self.world), "--id", "t-cli", "--titel", "CLI-Arbeit",
                                       "--ziel", "Ziel", "--fertig", "Fertig", "--an", "m1", "--json"])
        self.assertEqual(status, 0, stderr.getvalue())
        self.assertEqual(json.loads(stdout.getvalue())["sender"], "cli-operator")
        ad.claim_ticket(self.world, "t-cli", "m1", "m1", "mitglied")
        stderr, stdout = StringIO(), StringIO()
        with redirect_stderr(stderr), redirect_stdout(stdout):
            status = ad.run("ticket", ["zwischenstand", str(self.world), "t-cli", "--agent", "m1",
                                       "--text", "Laeuft", "--absender", "m1", "--rolle", "mitglied"])
        self.assertEqual(status, 0, stderr.getvalue())
        ad.write_result(self.world, "t-cli", "m1", "CLI-Ergebnis", None, "m1", "mitglied")

        with mock.patch.dict(os.environ, {"AWB_ROLLEN_DIR": str(self.root / "angreifer-register")}):
            stderr, stdout = StringIO(), StringIO()
            with redirect_stderr(stderr), redirect_stdout(stdout):
                status = ad.run("ticket", ["abnehmen", str(self.world), "t-cli", "--absender", "orchestrator",
                                           "--rolle", "hauptagent", "--grund", "erledigt"])
        self.assertEqual(status, 2)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("keinen passenden run-gebundenen Controller-Beleg", stderr.getvalue())
        self.assertEqual(ad.read_ticket(self.world, "t-cli")["state"], "zur Abnahme")

        ad.create_ticket(self.world, "Weg", "Ziel", "Fertig", ["m1"], "cli-operator", None,
                         ticket_id="t-discard")
        with self.assertRaisesRegex(ad.AgentsError, "Governance-Mutation.*Controller-Beleg"):
            ad.discard_ticket(self.world, "t-discard", "abgelehnt", sender="cli-operator")
        with self.assertRaisesRegex(ad.AgentsError, "Governance-Mutation.*Controller-Beleg"):
            ad.set_agent_rights(self.world, "m1", {"skills": ["texte-schreiben"]}, "orchestrator")
        with self.assertRaisesRegex(ad.AgentsError, "Governance-Mutation.*CLI gesperrt"):
            ad._require_human(self.world, "cli-operator", None, "Freigaben oder Zugaenge aendern")

        for command in (["liste", str(self.world), "--json"], ["zeigen", str(self.world), "t-cli", "--json"]):
            with redirect_stderr(StringIO()), redirect_stdout(StringIO()):
                self.assertEqual(ad.run("ticket", command), 0)

    def test_cli_minted_leader_and_named_existing_main_have_no_governance_binding(self):
        self.reifes_ticket("t-minted")
        created = subprocess.run(
            [str(SHELL / "wb-agent"), "neu", str(self.world), "--name", "boss2",
             "--stufe", "teamleiter", "--team", "t", "--beschreibung", "Angriff",
             "--absender", "cli-operator", "--json"],
            text=True, capture_output=True, timeout=15)
        self.assertEqual(created.returncode, 0, created.stderr)
        minted = subprocess.run(
            [str(SHELL / "wb-ticket"), "abnehmen", str(self.world), "t-minted",
             "--absender", "boss2", "--rolle", "teamleiter", "--grund", "erledigt"],
            text=True, capture_output=True, timeout=15)
        self.assertEqual(minted.returncode, 2, minted.stderr)
        self.assertIn("keinen passenden run-gebundenen Controller-Beleg", minted.stderr)
        self.assertEqual(ad.read_ticket(self.world, "t-minted")["state"], "zur Abnahme")

        for ticket_id in ("t-existing",):
            self.reifes_ticket(ticket_id)
        named = subprocess.run(
            [str(SHELL / "wb-ticket"), "abnehmen", str(self.world), "t-existing",
             "--absender", "main", "--rolle", "hauptagent", "--grund", "erledigt"],
            text=True, capture_output=True, timeout=15)
        rights = subprocess.run(
            [str(SHELL / "wb-agent"), "rechte", str(self.world), "m1", "--werkzeuge", "Read",
             "--absender", "main", "--rolle", "hauptagent"],
            text=True, capture_output=True, timeout=15)
        state = subprocess.run(
            [str(SHELL / "wb-agent"), "pause", str(self.world), "m1", "--absender", "main",
             "--rolle", "hauptagent"], text=True, capture_output=True, timeout=15)
        dod = subprocess.run(
            [str(SHELL / "wb-welt"), "dod", str(self.world), "setzen", "--punkt", "Angriff",
             "--absender", "main", "--rolle", "hauptagent"],
            text=True, capture_output=True, timeout=15)
        ad.create_ticket(self.world, "Route", "Ziel", "Fertig", ["m1"], "cli-operator", None,
                         ticket_id="t-route")
        reroute = subprocess.run(
            [str(SHELL / "wb-ticket"), "umadressieren", str(self.world), "t-route", "--an", "boss2",
             "--grund", "Angriff", "--absender", "main", "--rolle", "hauptagent"],
            text=True, capture_output=True, timeout=15)
        for result in (named, rights, state, dod, reroute):
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("keinen passenden run-gebundenen Controller-Beleg", result.stderr)
        self.assertEqual(ad.read_ticket(self.world, "t-existing")["state"], "zur Abnahme")
        self.assertEqual(ad.read_agent(self.world, "m1")["state"], "aktiv")
        self.assertEqual(ad.read_world(self.world).get("definition_of_done"), [])
        self.assertEqual(ad.read_ticket(self.world, "t-route")["recipients"], ["m1"])
        with self.assertRaisesRegex(af.FreigabeFehler, "keinen passenden run-gebundenen Controller-Beleg"):
            af._hauptagent(self.world, "main", "hauptagent", "Freigaben weitergeben")

    def test_run_bound_main_controller_still_approves_cli_created_ticket(self):
        ad.create_ticket(self.world, "Dienstweg", "Ziel", "Fertig", ["m1"], "cli-operator", None,
                         ticket_id="t-controller")
        ad.claim_ticket(self.world, "t-controller", "m1", "m1", "mitglied")
        ad.write_result(self.world, "t-controller", "m1", "Ergebnis", None, "m1", "mitglied")
        controller = ac.AgentController(self.world, "run-governance", lambda _binding: True)
        client = controller.bind_agent("main", "hauptagent")
        try:
            approved = client.request("ticket.approve", {"ticket_id": "t-controller",
                                                          "reason_code": "erledigt"})
            self.assertEqual((approved["state"], approved["approval"]["agent"]),
                             ("abgenommen", "main"))
            self.assertTrue(approved["approval"]["verified"])
        finally:
            client.close()
            controller.close()
            controller.join()

    def test_orchestrator_aliases_cannot_approve_each_others_work(self):
        for actor_id, ticket_field in (("orchestrator", {"sender": "cli-operator"}),
                                       ("cli-operator", {"assignee": "orchestrator"})):
            with self.subTest(actor=actor_id, ticket=ticket_field), \
                    self.assertRaisesRegex(ad.AgentsError, "darf eigene Arbeit nicht abnehmen"):
                ad._require_approver(self.world,
                                     {"id": actor_id, "kind": "agent", "role": "hauptagent"},
                                     {"assignee": "m1", "sender": "m1", **ticket_field})

    def test_controller_rejects_caller_supplied_sender_before_dispatch(self):
        self.reifes_ticket()
        controller = ac.AgentController(self.world, "run-herkunft", lambda _binding: True)
        client = controller.bind_agent("m1", "mitglied")
        try:
            with self.assertRaisesRegex(ac.ControllerError, "Unbekannte Payloadfelder"):
                client.request("ticket.approve", {"ticket_id": "t1", "sender": "mensch"})
        finally:
            client.close()
            controller.close()
            controller.join()


if __name__ == "__main__":
    unittest.main()
