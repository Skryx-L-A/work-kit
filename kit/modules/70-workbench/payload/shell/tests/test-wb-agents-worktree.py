#!/usr/bin/env python3
"""Worktree je Agent (agents_worktree): anlegen, wiederverwenden, pruefen, aufraeumen. Nur Wegwerf-Repos."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SHELL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHELL))

import agents_data as ad  # noqa: E402
import agents_worktree as aw  # noqa: E402

MODEL = "claude-haiku-4-5-20251001"


def git(cwd, *args):
    return subprocess.run(["git", "-c", "user.name=mensch", "-c", "user.email=mensch@example.invalid",
                           "-c", "core.hooksPath=/dev/null", *args],
                          cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


class WorktreeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-worktree-")
        self.root = Path(self.tmp.name).resolve()
        self.addCleanup(self.tmp.cleanup)
        self.env = mock.patch.dict(os.environ, {"WB_AGENTS_ZUSTAND": str(self.root / "zustand")})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.projekt = self.root / "projekt"
        self.projekt.mkdir()
        git(self.projekt, "init", "-q", "-b", "main")
        (self.projekt / "README.md").write_text("x\n")
        git(self.projekt, "add", "README.md")
        git(self.projekt, "commit", "-qm", "init")
        # Die Identitaet des Zuges kommt aus der Konfiguration des Projekts auf dem Traegerhost.
        git(self.projekt, "config", "user.name", "Mensch Probe")
        git(self.projekt, "config", "user.email", "mensch@example.invalid")
        (self.projekt / ".werkbank").mkdir()
        self.welt = self.projekt / ".werkbank" / "agents"
        ad.create_world(self.welt, name="Baumwelt", main_name="haupt", sender="cli-operator")
        for agent in ("a1", "a2"):
            ad.create_agent(self.welt, agent, "mitglied", None, "Probe", None, None, MODEL, None, None, None,
                            "host2", "haupt", "hauptagent")
        self.bereich = self.root / "a"

    def arbeitsordner(self, agent):
        ordner = self.bereich / agent / "work"
        ordner.mkdir(parents=True, exist_ok=True)
        return ordner

    def test_without_git_project_there_is_no_worktree(self):
        ohne = self.root / "ohne"
        ohne.mkdir()
        self.assertIsNone(aw.bereitstellen(ohne, self.arbeitsordner("a1"), "a1"))
        self.assertIsNone(aw.bereitstellen(None, self.arbeitsordner("a1"), "a1"))

    def test_first_call_creates_worktree_on_agent_branch_second_reuses_it(self):
        baum = aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1")
        self.assertEqual((baum.pfad, baum.zweig, baum.basis, baum.neu),
                         (self.bereich / "a1" / "work" / "a1", "agent/a1", "main", True))
        self.assertEqual(git(baum.pfad, "branch", "--show-current"), "agent/a1")
        self.assertEqual(baum.admin.parent, self.projekt / ".git" / "worktrees")
        self.assertTrue((self.projekt / ".git/refs/heads/agent").is_dir())
        self.assertTrue((self.projekt / ".git/logs/refs/heads/agent").is_dir())
        (baum.pfad / "x.txt").write_text("x\n")
        git(baum.pfad, "add", "x.txt")
        git(baum.pfad, "commit", "-qm", "agent")
        wieder = aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1")
        self.assertEqual((wieder.pfad, wieder.admin, wieder.neu), (baum.pfad, baum.admin, False))
        self.assertEqual(git(self.projekt, "rev-parse", "agent/a1"), git(baum.pfad, "rev-parse", "HEAD"))
        self.assertNotEqual(git(self.projekt, "rev-parse", "main"), git(baum.pfad, "rev-parse", "HEAD"))
        env = baum.git_umgebung()
        paare = {env["GIT_CONFIG_KEY_%d" % i]: env["GIT_CONFIG_VALUE_%d" % i]
                 for i in range(int(env["GIT_CONFIG_COUNT"]))}
        self.assertEqual(env["GIT_CONFIG_KEY_0"], "core.hooksPath")
        # Identitaet des Menschen vom Traegerhost, nie die Agentenkennung; der Zweig zeigt den Agenten.
        self.assertEqual((paare["user.name"], paare["user.email"]), ("Mensch Probe", "mensch@example.invalid"))
        self.assertEqual(baum.identitaet, ("Mensch Probe", "mensch@example.invalid"))
        self.assertNotIn("a1", paare["user.name"] + paare["user.email"])
        self.assertEqual((env["GIT_CONFIG_GLOBAL"], env["GIT_CONFIG_NOSYSTEM"]), ("/dev/null", "1"))
        self.assertTrue(all(aw.git_env_erlaubt(name) for name in env))

    def test_existing_branch_without_worktree_and_deleted_folder_are_picked_up(self):
        git(self.projekt, "branch", "agent/a1")
        baum = aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1")
        self.assertEqual(git(baum.pfad, "branch", "--show-current"), "agent/a1")
        # Der Agentenbereich wurde geloescht: der verwaiste Eintrag fuer genau diesen Pfad wird ersetzt.
        subprocess.run(["rm", "-rf", str(self.bereich)], check=True)
        neu = aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1")
        self.assertTrue(neu.neu)
        self.assertEqual(git(neu.pfad, "branch", "--show-current"), "agent/a1")

    def test_branch_checked_out_elsewhere_and_missing_main_are_refused(self):
        git(self.projekt, "worktree", "add", "-q", "-b", "agent/a1", str(self.root / "anderswo"), "main")
        with self.assertRaisesRegex(aw.WorktreeFehler, "ausgecheckt"):
            aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1")
        git(self.projekt, "branch", "-m", "main", "dev")
        with self.assertRaisesRegex(aw.WorktreeFehler, "weder main noch master"):
            aw.bereitstellen(self.projekt, self.arbeitsordner("a2"), "a2")

    def test_tampered_links_are_not_trusted(self):
        baum = aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1")
        gitdatei = (baum.pfad / ".git").read_text()
        (baum.pfad / ".git").write_text("gitdir: %s\n" % (self.root / "fremd"))
        with self.assertRaisesRegex(aw.WorktreeFehler, "zeigt nicht"):
            aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1")
        (baum.pfad / ".git").write_text(gitdatei)
        commondir = (baum.admin / "commondir").read_text()
        (baum.admin / "commondir").write_text(str(self.root / "fremd") + "\n")
        with self.assertRaisesRegex(aw.WorktreeFehler, "commondir"):
            aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1")
        (baum.admin / "commondir").write_text(commondir)
        self.assertFalse(aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1").neu)

    def test_mount_plan_names_only_measured_parts(self):
        baum = aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1")
        plan = baum.einbindung()
        gitdir = self.projekt / ".git"
        self.assertEqual(plan["gitdir"], str(gitdir))
        self.assertEqual(plan["schreiben"], [str(gitdir / "objects"), str(baum.admin), str(gitdir / "refs/heads/agent"),
                                             str(gitdir / "logs/refs/heads/agent")])
        self.assertIn(str(gitdir / "objects/pack"), plan["lesen"])
        self.assertNotIn(str(gitdir / "index"), plan["lesen"])
        self.assertNotIn(str(gitdir / "packed-refs"), plan["lesen"])  # erst nach pack-refs vorhanden
        git(self.projekt, "pack-refs", "--all")
        self.assertIn(str(gitdir / "packed-refs"), baum.einbindung()["lesen"])

    def test_a_carrier_host_without_git_identity_gets_no_worktree(self):
        # Hausregel: ein Agent committet nie unter eigenem Namen. Ohne Identitaet auf dem Host laeuft der Zug
        # wie ohne git-Projekt weiter, der Grund ist sichtbar.
        leer = self.root / "leeres-home"
        leer.mkdir()
        git(self.projekt, "config", "--unset", "user.name")
        umgebung = {"HOME": str(leer), "PATH": os.environ.get("PATH", ""), "GIT_CONFIG_NOSYSTEM": "1"}
        with mock.patch.object(aw, "_umgebung", return_value=umgebung):
            with self.assertRaisesRegex(aw.WorktreeFehler, "keine brauchbare git-Identitaet"):
                aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1")
        self.assertFalse((self.bereich / "a1" / "work" / "a1").exists())

    def test_stale_lock_files_of_the_own_worktree_are_cleared_before_the_next_turn(self):
        baum = aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1", True)
        self.assertEqual((baum.neu, baum.geraeumt), (True, ()))
        fremd = aw.bereitstellen(self.projekt, self.arbeitsordner("a2"), "a2")
        # Ein abgebrochener Zug laesst die Sperren seines Worktrees und seines Zweigs liegen.
        gitdir = self.projekt / ".git"
        (baum.admin / "index.lock").write_text("")
        (gitdir / "refs" / "heads" / "agent" / "a1.lock").write_text("")
        (fremd.admin / "index.lock").write_text("")
        (gitdir / "packed-refs.lock").write_text("")
        (baum.pfad / "x.txt").write_text("x\n")
        with self.assertRaises(subprocess.CalledProcessError):
            git(baum.pfad, "add", "x.txt")
        wieder = aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1", True)
        self.assertEqual(set(wieder.geraeumt), {str(baum.admin / "index.lock"),
                                                str(gitdir / "refs" / "heads" / "agent" / "a1.lock")})
        # Fremde Sperren bleiben: der andere Agent kann gerade arbeiten, und packed-refs gehoert dem Projekt.
        self.assertTrue((fremd.admin / "index.lock").exists())
        self.assertTrue((gitdir / "packed-refs.lock").exists())
        git(baum.pfad, "add", "x.txt")
        git(baum.pfad, "commit", "-qm", "nach der Sperre")
        # Ohne Auftrag zum Raeumen bleibt alles liegen.
        (baum.admin / "index.lock").write_text("")
        self.assertEqual(aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1").geraeumt, ())
        self.assertTrue((baum.admin / "index.lock").exists())

    def test_only_the_git_names_of_the_carrier_are_allowed_in_a_turn(self):
        for name in ("GIT_CONFIG_GLOBAL", "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_COUNT", "GIT_DIR",
                     "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_12"):
            self.assertTrue(aw.git_env_erlaubt(name), name)
        for name in ("GIT_SSH_COMMAND", "GIT_WORK_TREE", "GIT_EXEC_PATH", "GIT_CONFIG", "GIT_CONFIG_KEY_",
                     "GIT_CONFIG_KEY_01", "GIT_CONFIG_KEY_0x", "GIT_CONFIG_VALUE_9999", "WB_AGENT_ZUG"):
            self.assertFalse(aw.git_env_erlaubt(name), name)

    def aufgeloest(self, agent):
        # Einen Befehl zum Aufloesen gibt es noch nicht; aufgeloest heisst archiviert oder ohne Agentenordner.
        pfad = self.welt / "agents" / agent / "agent.json"
        daten = json.loads(pfad.read_text())
        daten["state"] = "archiviert"
        pfad.write_text(json.dumps(daten))

    def test_cleanup_removes_only_dissolved_merged_clean_agents(self):
        b1 = aw.bereitstellen(self.projekt, self.arbeitsordner("a1"), "a1")
        b2 = aw.bereitstellen(self.projekt, self.arbeitsordner("a2"), "a2")
        for baum in (b1, b2):
            (baum.pfad / (baum.zweig.split("/")[1] + ".txt")).write_text("x\n")
            git(baum.pfad, "add", ".")
            git(baum.pfad, "commit", "-qm", baum.zweig)
        # Aktiver Agent bleibt, auch wenn gemergt.
        git(self.projekt, "merge", "-q", "--no-edit", "agent/a1")
        ergebnis = aw.aufraeumen(self.welt)
        self.assertEqual(ergebnis["entfernt"], [])
        self.assertEqual({(i["agent"], i["grund"]) for i in ergebnis["bleibt"]},
                         {("a1", "Agent ist nicht aufgeloest"), ("a2", "Agent ist nicht aufgeloest")})
        self.aufgeloest("a1")
        self.aufgeloest("a2")
        # a2 ist nicht gemergt; a1 hat ungesicherte Aenderungen.
        (b1.pfad / "offen.txt").write_text("offen\n")
        ergebnis = aw.aufraeumen(self.welt)
        gruende = {i["agent"]: i["grund"] for i in ergebnis["bleibt"]}
        self.assertEqual(ergebnis["entfernt"], [])
        self.assertIn("ungesicherte", gruende["a1"])
        self.assertIn("nicht in main gemergt", gruende["a2"])
        (b1.pfad / "offen.txt").unlink()
        ergebnis = aw.aufraeumen(self.welt, "a1")
        self.assertEqual([i["agent"] for i in ergebnis["entfernt"]], ["a1"])
        self.assertFalse(b1.pfad.exists())
        self.assertEqual(subprocess.run(["git", "-C", str(self.projekt), "rev-parse", "--verify", "--quiet",
                                         "refs/heads/agent/a1"], capture_output=True).returncode, 1)
        self.assertTrue(b2.pfad.exists())
        self.assertEqual(git(self.projekt, "rev-parse", "--abbrev-ref", "HEAD"), "main")

    def test_cleanup_of_branch_without_worktree_and_cli(self):
        git(self.projekt, "branch", "agent/weg")
        ausgabe = subprocess.run([sys.executable, str(SHELL / "agents_worktree.py"), "aufraeumen", str(self.welt),
                                  "--json"], capture_output=True, text=True, check=True).stdout
        daten = json.loads(ausgabe)
        # Ein Zweig ohne Agentenordner gilt als aufgeloest; er zeigt auf main und ist damit gemergt.
        self.assertEqual([(i["agent"], i["worktree"]) for i in daten["entfernt"]], [("weg", None)])
        text = subprocess.run([str(SHELL / "wb-welt"), "worktree-aufraeumen", str(self.welt), "fehlt"],
                              capture_output=True, text=True, check=True).stdout
        self.assertIn("kein Zweig und kein Worktree", text)

    def test_world_without_git_project_reports_it(self):
        welt = self.root / "lose"
        ad.create_world(welt, name="Lose", main_name="haupt", sender="cli-operator")
        self.assertIn("kein git-Projekt", aw.aufraeumen(welt)["hinweis"])


if __name__ == "__main__":
    unittest.main()
