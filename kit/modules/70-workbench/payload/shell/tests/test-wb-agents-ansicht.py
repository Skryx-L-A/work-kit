#!/usr/bin/env python3
"""Isolated tests for the read-only views of the Agents data model.

`wb-welt finden` and `wb-welt ansicht` feed the Agents view of both
surfaces.  They must see everything the view draws, skip what a running
transaction stages, and never write: no repair, no recovery, no lock file.
"""

import fcntl
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve()
SHELL = HERE.parents[1]
sys.path.insert(0, str(SHELL))
import agents_data as ad
from herkunft_fixture import gebundene_governance, gemessener_mensch


_MENSCH_PATCH = None
_GOVERNANCE_CONTEXT = None


def setUpModule():
    global _MENSCH_PATCH, _GOVERNANCE_CONTEXT
    _MENSCH_PATCH = gemessener_mensch(ad)
    _MENSCH_PATCH.start()
    _GOVERNANCE_CONTEXT = gebundene_governance(ad)
    _GOVERNANCE_CONTEXT.__enter__()


def tearDownModule():
    _GOVERNANCE_CONTEXT.__exit__(None, None, None)
    _MENSCH_PATCH.stop()


def tree(root):
    """Every path below root with size and mtime -- the fingerprint of a read."""
    result = {}
    for folder, dirs, files in os.walk(root):
        for name in dirs + files:
            path = os.path.join(folder, name)
            st = os.lstat(path)
            result[os.path.relpath(path, root)] = (st.st_size, st.st_mtime_ns)
    return result


class ViewTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-ansicht-")
        self.base = Path(self.tmp.name)
        self.project = self.base / "AI" / "kalender"
        self.project.mkdir(parents=True)
        self.world = self.project / ".werkbank" / "agents"
        ad.create_world(self.world, name="Kalender", main_name="haupt")
        for agent_id, stage, team, text in (
                ("dev-leiter", "teamleiter", "entwicklung", "Leitet die Entwicklung"),
                ("parser", "mitglied", "entwicklung", "Liest Kalenderdateien"),
                ("quellen", "mitglied", None, "Prüft Quellen")):
            ad.create_agent(self.world, agent_id, stage, team, text, None, None, None, None,
                            None, None, "host2", "haupt", None)

    def tearDown(self):
        self.tmp.cleanup()

    def populate(self):
        ticket = ad.create_ticket(self.world, "Parser bauen", "ICS lesen", "Suite grün",
                                  ["parser"], "mensch", None, ticket_id="t-parser")
        ad.claim_ticket(self.world, ticket["id"], "parser", "parser", "mitglied")
        ad.send_message(self.world, "haupt", ["dev-leiter"], "Bitte Parser verteilen", "t-parser",
                        "m-eins", "hauptagent")
        ad.send_message(self.world, "mensch", ["haupt"], "Wie weit ist der Parser?", None,
                        "m-direkt", None, direct=True)
        ad.send_message(self.world, "parser", ["dev-leiter"], "Frage zum Format", None,
                        "m-team", "mitglied", direct=True)
        ad.ask_question(self.world, "Soll der Import nachts laufen?", ["ja", "nein"], "ja",
                        "t-parser", "frage-nacht", "haupt", "hauptagent")

    def test_snapshot_contains_what_the_view_draws(self):
        self.populate()
        snap = ad.world_snapshot(self.world)
        self.assertTrue(snap["consistent"])
        self.assertEqual(snap["world"]["name"], "Kalender")
        self.assertEqual([a["id"] for a in snap["agents"]], ["dev-leiter", "haupt", "parser", "quellen"])
        parser = next(a for a in snap["agents"] if a["id"] == "parser")
        self.assertEqual(parser["stage"], "mitglied")
        self.assertEqual(parser["team"], "entwicklung")
        self.assertEqual(parser["runtime"]["state"], "aktiv")
        self.assertIn("Gedächtnis", parser["memory"]["text"])
        self.assertFalse(parser["memory"]["truncated"])
        self.assertEqual(parser["postbox"]["open"], 1, "the ticket delivery is unacknowledged")
        leiter = next(a for a in snap["agents"] if a["id"] == "dev-leiter")
        self.assertEqual(leiter["postbox"]["total"], 2, "channel message and direct chat")
        self.assertEqual(snap["tickets"][0]["state"], "läuft")
        self.assertEqual([e["event"] for e in snap["tickets"][0]["history"]["events"]],
                         ["erstellt", "uebernommen"])
        self.assertEqual(snap["channel_total"], 1)
        self.assertEqual(snap["channel"][0]["text"], "Bitte Parser verteilen")
        chats = {tuple(c["participants"]): c for c in snap["direct_chats"]}
        self.assertEqual(chats[("haupt", "mensch")]["messages"][0]["text"], "Wie weit ist der Parser?")
        self.assertEqual(chats[("dev-leiter", "parser")]["total"], 1)
        self.assertEqual(snap["questions"][0]["state"], "offen")
        self.assertEqual(snap["questions"][0]["recommendation"], "ja")
        self.assertEqual(snap["errors"], [])

    def test_snapshot_never_writes(self):
        self.populate()
        before = tree(self.world)
        ad.world_snapshot(self.world)
        out = subprocess.run([str(SHELL / "wb-welt"), "ansicht", str(self.world), "--json"],
                             capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(out.stdout)["world"]["name"], "Kalender")
        self.assertEqual(tree(self.world), before)
        # Without a lock file the read must not create one either.
        (self.world / ".agents.lock").unlink()
        before = tree(self.world)
        self.assertTrue(ad.world_snapshot(self.world)["consistent"])
        self.assertEqual(tree(self.world), before)

    def test_snapshot_skips_staging_and_tolerates_a_torn_channel_tail(self):
        self.populate()
        stage = self.world / "agents" / ".ghost.creating-abc"
        stage.mkdir()
        (stage / "agent.json").write_text(json.dumps({"id": "ghost"}), encoding="utf-8")
        (self.world / "tickets" / ".t-neu.creating-abc").mkdir()
        (self.world / "questions" / ".frage-neu.creating-abc").mkdir()
        (self.world / "agents" / "parser" / "postfach" / ".x.json.tmp-1").write_text("{", encoding="utf-8")
        with (self.world / "kanal.jsonl").open("a", encoding="utf-8") as stream:
            stream.write('{"id": "halb')
        snap = ad.world_snapshot(self.world)
        self.assertNotIn("ghost", [a["id"] for a in snap["agents"]])
        self.assertEqual(len(snap["tickets"]), 1)
        self.assertEqual(len(snap["questions"]), 1)
        self.assertEqual(snap["channel_total"], 1)
        self.assertEqual(snap["errors"], [])

    def test_snapshot_reports_a_broken_section_and_keeps_the_rest(self):
        self.populate()
        (self.world / "tickets" / "t-parser" / "ticket.json").write_text("{kaputt", encoding="utf-8")
        snap = ad.world_snapshot(self.world)
        self.assertEqual(snap["tickets"], [])
        self.assertEqual(snap["errors"][0]["section"], "tickets")
        self.assertEqual(len(snap["agents"]), 4)

    def test_snapshot_waits_for_a_writer_and_then_marks_itself_inconsistent(self):
        with (self.world / ".agents.lock").open("a+") as lock:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
            try:
                snap = ad.world_snapshot(self.world, lock_timeout=0.2)
            finally:
                fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        self.assertFalse(snap["consistent"])
        self.assertEqual(len(snap["agents"]), 4)
        self.assertTrue(ad.world_snapshot(self.world)["consistent"])

    def test_limits_cut_the_tail(self):
        for index in range(5):
            ad.send_message(self.world, "haupt", ["parser"], "Nachricht %d" % index, None,
                            "m-%d" % index, "hauptagent")
        snap = ad.world_snapshot(self.world, limit=2)
        self.assertEqual([m["text"] for m in snap["channel"]], ["Nachricht 3", "Nachricht 4"])
        self.assertEqual(snap["channel_total"], 5)
        with self.assertRaises(ad.AgentsError):
            ad.world_snapshot(self.world, limit=0)

    def test_find_worlds(self):
        global_world = self.base / "home" / ".claude" / "workbench" / "agents"
        ad.create_world(global_world, name="Global", global_world=True)
        other = self.base / "anderswo" / "notizen"
        other.mkdir(parents=True)
        ad.create_world(other / ".werkbank" / "agents", name="Notizen")
        (self.base / "AI" / "ohne-welt").mkdir()
        hidden = self.base / "AI" / ".versteckt"
        ad.create_world(hidden / ".werkbank" / "agents", name="Versteckt")
        broken = self.base / "AI" / "kaputt" / ".werkbank" / "agents"
        broken.mkdir(parents=True)
        (broken / "world.json").write_text("{", encoding="utf-8")
        before = tree(self.base)
        found = ad.find_worlds([str(self.base / "AI")], [str(other), str(self.project)], str(global_world))
        self.assertEqual(tree(self.base), before)
        self.assertEqual([(f["kind"], f["name"]) for f in found],
                         [("global", "Global"), ("project", "Notizen"), ("project", "Kalender"), ("project", "kaputt")])
        self.assertEqual(found[1]["project"], str(other))
        self.assertIsNone(found[0]["project"])
        self.assertEqual(found[2]["state"], "läuft")
        self.assertIsNotNone(found[3]["error"])
        # CLI: an explicit root replaces the default ~/AI; --ohne-global drops the global world.
        env = dict(os.environ, HOME=str(self.base / "home"))
        out = subprocess.run([str(SHELL / "wb-welt"), "finden", "--wurzel", str(self.base / "AI"), "--json"],
                             capture_output=True, text=True, check=True, env=env)
        self.assertEqual([f["name"] for f in json.loads(out.stdout)], ["Global", "Kalender", "kaputt"])
        out = subprocess.run([str(SHELL / "wb-welt"), "finden", "--ohne-global", "--json"],
                             capture_output=True, text=True, check=True, env=env)
        self.assertEqual(json.loads(out.stdout), [], "HOME has no AI folder")
        out = subprocess.run([str(SHELL / "wb-welt"), "finden", "--wurzel", str(self.base / "AI")],
                             capture_output=True, text=True, check=True, env=env)
        self.assertEqual(out.stdout.splitlines()[0], str(global_world))

    def test_existing_commands_are_unchanged(self):
        out = subprocess.run([str(SHELL / "wb-welt"), "liste", str(self.world), "--json"],
                             capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(out.stdout)[0]["name"], "Kalender")
        bad = subprocess.run([str(SHELL / "wb-welt"), "ansicht", str(self.base / "fehlt"), "--json"],
                             capture_output=True, text=True)
        self.assertEqual(bad.returncode, 2)
        self.assertIn("FEHLER", bad.stderr)



class SkillsViewTests(unittest.TestCase):
    """Auftrag agentsui Nr. 4: agents_skills_ansicht.py reads skills, proposals and measurements, writes nothing."""

    def setUp(self):
        import agents_skills as sk
        self.sk = sk
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-skillansicht-")
        base = Path(self.tmp.name)
        self.library = base / "bibliothek"
        (self.library / "lib-skill" / "scripts").mkdir(parents=True)
        (self.library / "lib-skill" / "SKILL.md").write_text(
            "---\nname: lib-skill\ndescription: Aus der Bibliothek\n---\n\n# lib-skill\n\n## Auslöser\n\nImmer.\n\n"
            "## Vorgehen\n\n1. Tun.\n\n## Grenzen\n\n- Keine.\n", encoding="utf-8")
        self.world = base / "welt"
        ad.create_world(self.world, name="Probe", main_name="main")
        ad.create_agent(self.world, "lead", "teamleiter", "dev", "Leitet", None, None, None, None, None, None,
                        "lokal", "cli-operator", None)
        ad.create_agent(self.world, "member", "mitglied", "dev", "Baut", None, None, None, None, None, None,
                        "lokal", "cli-operator", None, skills=["lib-skill", "fehlt-ueberall"])
        sk.create_skill(self.world, "member", "eigen", "Eigener Skill fuer Tests", library=self.library)
        self.proposal = sk.propose_skill(self.world, "member", "eigen", "welt", reason="nuetzt allen", library=self.library)
        tokens = {"input": 100, "output": 50, "cache_read": 0, "cache_write": 0, "reasoning": 0, "gesamt": 150}
        for index, gesamt in enumerate((1000, 1000, 400, 400, 400, 400, 400)):
            sk.record_measurement(self.world, "member", "ticket", {"tokens": dict(tokens, gesamt=gesamt)}, "lauf-%d" % index)

    def tearDown(self):
        self.tmp.cleanup()

    def stand(self):
        return sorted((str(p.relative_to(self.world)), p.stat().st_mtime_ns, p.stat().st_size)
                      for p in self.world.rglob("*") if not p.is_dir())

    def test_view_lists_skills_history_measurement_and_proposal_without_writing(self):
        import agents_skills_ansicht as view
        (self.world / "agents" / "member" / "skills.json").unlink()  # computed without the file
        before = self.stand()
        data = view.skills_view(self.world, str(self.library))
        self.assertEqual(self.stand(), before, "the view writes nothing")
        member = data["agenten"]["member"]
        self.assertEqual(member["quelle"], "berechnet")
        self.assertEqual([(s["name"], s["ebene"], s["vorgeladen"]) for s in member["skills"]],
                         [("eigen", "agent", False), ("lib-skill", "bibliothek", True)])
        self.assertIn("## Vorgehen", member["skills"][1]["skill_md"])
        self.assertEqual(member["fehlend"], ["fehlt-ueberall"])
        self.assertEqual([e.get("aktion") for e in member["verlauf"]], ["neu", "vorschlag"])
        messung = member["messung"]["arten"]["ticket"]
        self.assertEqual((messung["anzahl"], messung["mittel_letzte"]["gesamt"], messung["veraenderung"]), (7, 400, -0.6))
        vorschlag = data["vorschlaege"][self.proposal["ticket"]]
        self.assertEqual((vorschlag["skill"], vorschlag["agent"], vorschlag["ziel"], vorschlag["stand"], vorschlag["pruefer"]),
                         ("eigen", "member", "welt", "offen", "lead"))
        self.assertIn("+name: eigen", vorschlag["diff"])
        self.assertEqual([e["event"] for e in data["verlauf"]], ["vorschlag"])
        self.assertTrue(data["consistent"])
        # With skills.json present, it is read as it stands.
        self.sk.write_skill_directory(self.world, "member", self.library)
        data = view.skills_view(self.world, str(self.library))
        self.assertEqual(data["agenten"]["member"]["quelle"], "skills.json")
        self.assertEqual(data["agenten"]["lead"]["skills"], [])
        # CLI, and a world that is not one.
        out = subprocess.run([sys.executable, str(SHELL / "agents_skills_ansicht.py"), str(self.world), "--bibliothek",
                              str(self.library), "--json"], capture_output=True, text=True, timeout=60)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(sorted(json.loads(out.stdout)["agenten"]), ["lead", "main", "member"])
        bad = subprocess.run([sys.executable, str(SHELL / "agents_skills_ansicht.py"), str(Path(self.tmp.name) / "nichts"), "--json"],
                             capture_output=True, text=True, timeout=60)
        self.assertEqual(bad.returncode, 2)

    def test_catalog_lists_valid_world_and_library_skills(self):
        """Auftrag agentsform: the create menu offers the skills of the world and the library."""
        import agents_skills_ansicht as view
        welt_skill = self.world / "skills" / "welt-skill"
        welt_skill.mkdir(parents=True, exist_ok=True)
        (welt_skill / "SKILL.md").write_text(
            "---\nname: welt-skill\ndescription: Fuer die ganze Welt\n---\n\n# welt-skill\n\n## Auslöser\n\nImmer.\n\n"
            "## Vorgehen\n\n1. Tun.\n\n## Grenzen\n\n- Keine.\n", encoding="utf-8")
        (self.library / "kaputt").mkdir()
        before = self.stand()
        katalog = view.skills_view(self.world, str(self.library))["katalog"]
        self.assertEqual(self.stand(), before, "the catalog writes nothing")
        self.assertIn(("welt-skill", "Fuer die ganze Welt"), [(k["name"], k["beschreibung"]) for k in katalog["welt"]])
        self.assertEqual([(k["name"], k["beschreibung"]) for k in katalog["bibliothek"]], [("lib-skill", "Aus der Bibliothek")])


if __name__ == "__main__":
    unittest.main()
