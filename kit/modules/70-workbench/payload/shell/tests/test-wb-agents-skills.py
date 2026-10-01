#!/usr/bin/env python3
"""Isolated stdlib tests for skills with scripts, the learning step and token measurement.

Every world and every library used here lives in a throwaway directory; only the three
library skills of the repository are read (and their script tests run), never written.
"""

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve()
SHELL = HERE.parents[1]
REPO = HERE.parents[2]
sys.path.insert(0, str(SHELL))
import agents_data as ad  # noqa: E402
import agents_skills as sk  # noqa: E402
from herkunft_fixture import gebundene_governance, gemessener_mensch  # noqa: E402


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

LIBRARY_SKILLS = ("ergebnis-schreiben", "pruefen-vor-abgabe", "recherche-beleg")
LIBRARY_SCRIPTS = ("diff-zusammenfassung", "lernschritt-schreiben", "tests-laufen", "zitat-beleg")


def script_text(name, body="echo x\n", shebang="#!/bin/sh", suffix=".sh", keys=None):
    header = dict([("name", name), ("zweck", "Tut etwas"), ("aufruf", name + suffix), ("eingaben", "keine"),
                   ("ausgaben", "stdout"), ("grenzen", "keine")])
    header.update(keys or {})
    lines = [shebang, "# ---"] + ["# %s: %s" % item for item in header.items() if item[1] is not None] + ["# ---"]
    return "\n".join(lines) + "\n" + body


def write_script(base, name, body="echo x\n", shebang="#!/bin/sh", suffix=".sh", keys=None, test=True):
    folder = Path(base) / name
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / (name + suffix)
    path.write_text(script_text(name, body, shebang, suffix, keys), encoding="utf-8")
    path.chmod(0o755)
    if test:
        (folder / "tests").mkdir(exist_ok=True)
        (folder / "tests" / ("test_%s.py" % name.replace("-", "_"))).write_text("pass\n", encoding="utf-8")
    return folder


def skill_md(name, description, extra="", references=None):
    return ("---\nname: %s\ndescription: %s\n%s---\n\n# %s\n\n## Auslöser\n\nWenn es passt.\n\n"
            "## Vorgehen\n\n1. Tun.%s\n\n## Grenzen\n\n- Keine.\n") % (
        name, description, "skripte: %s\n" % references if references else "", name, extra)


def write_skill(base, name, description="Beschreibt etwas", scripts=None, references=None):
    folder = Path(base) / name
    (folder / "scripts").mkdir(parents=True, exist_ok=True)
    (folder / "SKILL.md").write_text(skill_md(name, description, references=references), encoding="utf-8")
    for rel, text in (scripts or {}).items():
        path = folder / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        path.chmod(0o755)
    return folder


class SkillsTestBase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-skills-")
        self.base = Path(self.tmp.name)
        self.library = self.base / "bibliothek"
        self.library.mkdir()
        self.world = self.base / "welt"
        ad.create_world(self.world, name="Probe", main_name="main")
        ad.create_agent(self.world, "lead", "teamleiter", "dev", "Leitet Entwicklung", None, None, None, None,
                        None, None, "lokal", "cli-operator", None)
        ad.create_agent(self.world, "member", "mitglied", "dev", "Baut Dateien", None, None, None, None,
                        None, None, "lokal", "cli-operator", None, skills=["lib-skill", "fehlt-ueberall"])
        ad.create_agent(self.world, "other", "mitglied", "dev", "Baut andere Dateien", None, None, None, None,
                        None, None, "lokal", "cli-operator", None)

    def tearDown(self):
        self.tmp.cleanup()

    def history(self, agent_id):
        return json.loads((self.world / "agents" / agent_id / "history.json").read_text(encoding="utf-8"))["entries"]

    def agent_skills(self, agent_id):
        return self.world / "agents" / agent_id / "skills"


class FolderAndVersionTests(SkillsTestBase):
    def test_names_frontmatter_sections_and_hints(self):
        for bad in ("Gross", "../x", "a_b", "-a", "a-", "", "x" * 65):
            with self.assertRaises(ad.AgentsError, msg=bad):
                sk.valid_skill_name(bad)
        folder = write_skill(self.base / "lvl", "gut", sk.frontmatter_value("Tut: etwas"),
                             {"scripts/run.py": "#!/usr/bin/env python3\n"})
        self.assertEqual(sk.frontmatter_value("Tut: etwas"), '"Tut: etwas"')
        info = sk.check_skill(folder)
        self.assertTrue(info["gueltig"], info["befunde"])
        self.assertEqual(info["description"], "Tut: etwas")
        self.assertIn("Skript ohne Test unter tests/: scripts/run.py", [f["text"] for f in info["befunde"]])
        (folder / "tests").mkdir()
        (folder / "tests" / "test_run.py").write_text("", encoding="utf-8")
        self.assertEqual(sk.check_skill(folder)["befunde"], [])
        (folder / "SKILL.md").write_text("---\nname: gut\ndescription: x\n---\n\n## Vorgehen\n", encoding="utf-8")
        texts = [f["text"] for f in sk.check_skill(folder)["befunde"]]
        self.assertIn("Abschnitt 'Auslöser' fehlt", texts)
        self.assertIn("Abschnitt 'Grenzen' fehlt", texts)
        (folder / "SKILL.md").write_text("---\nname: anders\ndescription: >\n  lang\n---\n", encoding="utf-8")
        self.assertFalse(sk.check_skill(folder)["gueltig"])

    def test_version_covers_content_and_mode_but_not_caches(self):
        folder = write_skill(self.base / "lvl", "ver", scripts={"scripts/a.sh": "#!/bin/sh\necho a\n"})
        first = sk.skill_version(folder)
        (folder / "__pycache__").mkdir()
        (folder / "__pycache__" / "x.cpython-312.pyc").write_bytes(b"\0")
        (folder / "scripts" / "b.pyc").write_bytes(b"\0")
        self.assertEqual(sk.skill_version(folder), first)
        (folder / "scripts" / "a.sh").chmod(0o644)
        second = sk.skill_version(folder)
        self.assertNotEqual(second, first)
        (folder / "scripts" / "a.sh").chmod(0o755)
        self.assertEqual(sk.skill_version(folder), first)
        (folder / "scripts" / "a.sh").write_text("#!/bin/sh\necho b\n", encoding="utf-8")
        self.assertNotEqual(sk.skill_version(folder), first)

    def test_symlinks_special_names_and_size_are_rejected(self):
        folder = write_skill(self.base / "lvl", "sym")
        (folder / "link").symlink_to(folder / "SKILL.md")
        with self.assertRaisesRegex(ad.AgentsError, "Symlink"):
            sk.skill_files(folder)
        (folder / "link").unlink()
        (folder / "scripts" / "sub").symlink_to(self.base, target_is_directory=True)
        with self.assertRaisesRegex(ad.AgentsError, "Symlink"):
            sk.skill_files(folder)
        (folder / "scripts" / "sub").unlink()
        (folder / "bad name").write_text("x", encoding="utf-8")
        with self.assertRaisesRegex(ad.AgentsError, "ungueltig"):
            sk.skill_files(folder)
        (folder / "bad name").unlink()
        (folder / "gross.bin").write_bytes(b"0" * (sk.SKILL_FILE_LIMIT + 1))
        with self.assertRaisesRegex(ad.AgentsError, "groesser"):
            sk.skill_files(folder)
        (folder / "gross.bin").unlink()
        linked = self.base / "lvl" / "verlinkt"
        linked.symlink_to(folder, target_is_directory=True)
        with self.assertRaisesRegex(ad.AgentsError, "Symlink"):
            sk.skill_files(linked)
        for rel in ("../x", "/abs", "a/../b", "a\\b", "a//b"):
            with self.assertRaises(ad.AgentsError, msg=rel):
                sk._valid_rel(rel)

    def test_diff_round_trip_with_new_deleted_mode_and_missing_newline(self):
        old = {"SKILL.md": (b"eins\nzwei\ndrei\n", False), "scripts/a.sh": (b"#!/bin/sh\necho a", True),
               "weg.txt": (b"alt\n", False), "modus.sh": (b"#!/bin/sh\n", False)}
        new = {"SKILL.md": (b"eins\nZWEI\ndrei\nvier\n", False), "scripts/a.sh": (b"#!/bin/sh\necho b\n", True),
               "neu/datei.txt": (b"frisch", False), "modus.sh": (b"#!/bin/sh\n", True)}
        diff = sk.skill_diff(old, new)
        self.assertIn("\\ No newline at end of file", diff)
        self.assertIn("new mode 100755", diff)
        self.assertEqual(sk.apply_diff(old, diff), new)
        self.assertEqual(sk.apply_diff({}, sk.skill_diff(None, new)), new)
        with self.assertRaisesRegex(ad.AgentsError, "passt nicht"):
            sk.apply_diff({"SKILL.md": (b"anders\nzwei\ndrei\n", False)}, sk.skill_diff(
                {"SKILL.md": old["SKILL.md"]}, {"SKILL.md": new["SKILL.md"]}))
        with self.assertRaises(ad.AgentsError):
            sk.parse_diff("--- a/../x\n+++ b/../x\n@@ -1 +1 @@\n-a\n+b\n")
        with self.assertRaisesRegex(ad.AgentsError, "vorzeitig"):
            sk.parse_diff("--- a/x\n+++ b/x\n@@ -1,2 +1,2 @@\n-a\n")


class CreateListResolveTests(SkillsTestBase):
    def test_create_from_template_writes_directory_and_history(self):
        created = sk.create_skill(self.world, "member", "mein-skill", "Baut: Dateien schneller")
        folder = self.agent_skills("member") / "mein-skill"
        self.assertTrue((folder / "scripts").is_dir())
        self.assertTrue(created["gueltig"], created["befunde"])
        self.assertEqual(sk.check_skill(folder)["description"], "Baut: Dateien schneller")
        directory = json.loads((self.world / "agents" / "member" / "skills.json").read_text(encoding="utf-8"))
        self.assertEqual([(s["name"], s["ebene"], s["version"]) for s in directory["skills"]],
                         [("mein-skill", "agent", created["version"])])
        self.assertEqual(directory["fehlend"], ["fehlt-ueberall", "lib-skill"])
        entry = self.history("member")[-1]
        self.assertEqual((entry["event"], entry["aktion"], entry["skill"]), ("skill", "neu", "mein-skill"))
        with self.assertRaisesRegex(ad.AgentsError, "existiert bereits"):
            sk.create_skill(self.world, "member", "mein-skill", "Nochmal")
        with self.assertRaisesRegex(ad.AgentsError, "nur eigene Skills"):
            sk.create_skill(self.world, "member", "fremd", "Fremd", sender="other")
        sk.create_skill(self.world, "member", "vom-menschen", "Angelegt vom Menschen", sender="mensch")
        with self.assertRaisesRegex(ad.AgentsError, "unbekannt"):
            sk.create_skill(self.world, "member", "x", "y", sender="niemand")

    def test_resolution_prefers_agent_then_world_then_library_by_reference(self):
        write_skill(self.library, "lib-skill", "Aus der Bibliothek")
        write_skill(self.library, "nicht-geladen", "Nicht im Profil")
        write_skill(self.library, "geteilt", "Bibliotheksfassung")
        write_skill(self.world / "skills", "geteilt", "Weltfassung")
        write_skill(self.world / "skills", "kaputt", "x")
        (self.world / "skills" / "kaputt" / "SKILL.md").write_text("kein frontmatter", encoding="utf-8")
        sk.create_skill(self.world, "member", "geteilt", None, source_level="welt", library=self.library)
        directory = sk.skill_directory(self.world, "member", self.library)
        by_name = {s["name"]: s for s in directory["skills"]}
        self.assertEqual(set(by_name), {"geteilt", "lib-skill"})
        self.assertEqual(by_name["geteilt"]["ebene"], "agent")
        self.assertEqual([(v["ebene"], v["gleich"]) for v in by_name["geteilt"]["verdeckt"]],
                         [("welt", True), ("bibliothek", False)])
        self.assertTrue(by_name["lib-skill"]["vorgeladen"])
        self.assertEqual(by_name["lib-skill"]["pfad"], str(self.library / "lib-skill"))
        self.assertEqual(directory["fehlend"], ["fehlt-ueberall"])
        self.assertEqual([(i["name"], i["ebene"]) for i in directory["ungueltig"]], [("kaputt", "welt")])
        other = {s["name"]: s["ebene"] for s in sk.skill_directory(self.world, "other", self.library)["skills"]}
        self.assertEqual(other, {"geteilt": "welt"})
        # An invalid own copy falls back to the valid world skill instead of breaking the agent.
        (self.agent_skills("member") / "geteilt" / "SKILL.md").write_text("kaputt", encoding="utf-8")
        by_name = {s["name"]: s for s in sk.skill_directory(self.world, "member", self.library)["skills"]}
        self.assertEqual(by_name["geteilt"]["ebene"], "welt")
        written = sk.write_skill_directory(self.world, None, self.library)
        self.assertEqual({item["agent"] for item in written}, {"main", "lead", "member", "other"})
        self.assertFalse(sk.write_skill_directory(self.world, "member", self.library)[0]["geaendert"])
        listing = sk.list_skills(self.world, library=self.library)
        self.assertEqual([s["name"] for s in listing["agenten"]["member"]], ["geteilt"])
        shown = sk.show_skill(self.world, "geteilt", "member", None, self.library)
        self.assertEqual(shown["ebene"], "agent")
        self.assertFalse(shown["gueltig"])
        shown = sk.show_skill(self.world, "lib-skill", library=self.library)
        self.assertIn("Aus der Bibliothek", shown["skill_md"])

    def test_symlinked_skill_folder_is_listed_invalid_and_never_followed(self):
        target = write_skill(self.base / "draussen", "boese", "Liegt ausserhalb")
        (self.world / "skills").mkdir(exist_ok=True)
        (self.world / "skills" / "boese").symlink_to(target, target_is_directory=True)
        directory = sk.skill_directory(self.world, "member", self.library)
        self.assertEqual(directory["skills"], [])
        self.assertEqual(directory["ungueltig"][0]["name"], "boese")
        (self.world / "skills" / "boese").unlink()
        (self.world / "skills").rmdir()
        (self.world / "skills").symlink_to(self.base / "draussen", target_is_directory=True)
        with self.assertRaisesRegex(ad.AgentsError, "Symlink"):
            sk.skill_directory(self.world, "member", self.library)


class ProposalTests(SkillsTestBase):
    def propose_member_skill(self, name="teil-skill", description="Teilt Wissen im Team"):
        sk.create_skill(self.world, "member", name, description, library=self.library)
        return sk.propose_skill(self.world, "member", name, "welt", reason="Nuetzt dem Team", library=self.library)

    def test_member_proposal_goes_to_team_leader_with_diff_and_is_idempotent(self):
        proposal = self.propose_member_skill()
        ticket = ad.read_ticket(self.world, proposal["ticket"])
        self.assertEqual(ticket["recipients"], ["lead"])
        self.assertEqual(ticket["sender"], "member")
        self.assertEqual(ticket["limits"]["art"], "skill-vorschlag")
        self.assertIn("+name: teil-skill", ticket["goal"])
        self.assertIn("Begründung: Nuetzt dem Team", ticket["goal"])
        self.assertTrue((self.world / "agents" / "lead" / "postfach" / (ad.derived_id("ticket", ticket["id"]) + ".json")).exists())
        again = sk.propose_skill(self.world, "member", "teil-skill", "welt", library=self.library)
        self.assertEqual(again["ticket"], proposal["ticket"])
        self.assertEqual(len([t for t in ad.list_tickets(self.world)]), 1)
        log = (self.world / "skill-verlauf.jsonl").read_text(encoding="utf-8").splitlines()
        self.assertEqual([json.loads(line)["event"] for line in log], ["vorschlag"])
        with self.assertRaisesRegex(ad.AgentsError, "nur eigene Skills"):
            sk.propose_skill(self.world, "member", "teil-skill", "welt", sender="other", library=self.library)
        with self.assertRaisesRegex(ad.AgentsError, "globalen Welt"):
            sk.propose_skill(self.world, "member", "teil-skill", "bibliothek", library=self.library)
        with self.assertRaisesRegex(ad.AgentsError, "fehlt"):
            sk.propose_skill(self.world, "other", "teil-skill", "welt", library=self.library)

    def test_team_leader_accepts_copy_logs_and_notifies_proposer(self):
        proposal = self.propose_member_skill()
        with self.assertRaisesRegex(ad.AgentsError, "eigenen Skill"):
            sk.accept_proposal(self.world, proposal["ticket"], "member", library=self.library)
        with self.assertRaisesRegex(ad.AgentsError, "adressierte"):
            sk.accept_proposal(self.world, proposal["ticket"], "other", library=self.library)
        accepted = sk.accept_proposal(self.world, proposal["ticket"], "lead", "passt", library=self.library)
        world_skill = self.world / "skills" / "teil-skill"
        self.assertEqual(sk.skill_version(world_skill), proposal["version"])
        # The leader closes the ticket as well (agentsui Nr. 5): an own ticket from a team member.
        self.assertEqual(accepted["ticket_stand"], "abgenommen")
        ticket = ad.read_ticket(self.world, proposal["ticket"])
        self.assertEqual(ticket["assignee"], "lead")
        self.assertEqual((ticket["approval"]["agent"], ticket["approval"]["note"]), ("lead", "passt"))
        self.assertTrue(ticket["result"]["text"].startswith(sk.RESULT_ACCEPTED))
        notice = self.world / "agents" / "member" / "postfach" / (ticket["result_message_id"] + ".json")
        self.assertTrue(notice.exists())
        other_directory = json.loads((self.world / "agents" / "other" / "skills.json").read_text(encoding="utf-8"))
        self.assertEqual([(s["name"], s["ebene"]) for s in other_directory["skills"]], [("teil-skill", "welt")])
        stored = sk.read_proposal(self.world, proposal["ticket"])
        self.assertEqual(stored["stand"], "übernommen")
        self.assertEqual(self.history("member")[-1]["aktion"], "abgenommen")
        # Retry after a lost response changes nothing, also not the approval.
        again = sk.accept_proposal(self.world, proposal["ticket"], "lead", "passt", library=self.library)
        self.assertEqual((again["version"], again["ticket_stand"]), (proposal["version"], "abgenommen"))
        events = [json.loads(line)["event"] for line in (self.world / "skill-verlauf.jsonl").read_text().splitlines()]
        self.assertEqual(events, ["vorschlag", "abgenommen"])
        with self.assertRaisesRegex(ad.AgentsError, "bereits uebernommen"):
            sk.reject_proposal(self.world, proposal["ticket"], "lead", "doch nicht")
        self.assertEqual(ad.read_ticket(self.world, proposal["ticket"])["approval"], ticket["approval"])
        with self.assertRaisesRegex(ad.AgentsError, "keine Abnahme"):
            ad.approve_ticket(self.world, proposal["ticket"], "main", None, "ok")

    def test_unbound_cli_reviewer_cannot_write_acceptance_or_rejection_state(self):
        proposal = self.propose_member_skill()
        ticket_id = proposal["ticket"]
        target = self.world / "skills" / "teil-skill"
        ticket_file = self.world / "tickets" / ticket_id / "ticket.json"
        proposal_file = self.world / sk.PROPOSAL_DIR / ticket_id / "vorschlag.json"
        before_ticket = ticket_file.read_bytes()
        before_proposal = proposal_file.read_bytes()
        before_log = (self.world / sk.WORLD_LOG).read_text(encoding="utf-8")

        # Override the module-wide legacy fixture for this provenance regression:
        # plain CLI role/name claims have no run-bound controller evidence.
        with mock.patch.object(ad, "_controller_binding_matches", return_value=False):
            with self.assertRaisesRegex(ad.AgentsError, "run-gebundenen Controller-Beleg"):
                sk.accept_proposal(self.world, ticket_id, "lead", library=self.library)
            with self.assertRaisesRegex(ad.AgentsError, "run-gebundenen Controller-Beleg"):
                sk.reject_proposal(self.world, ticket_id, "lead", "nicht geeignet")

        self.assertFalse(target.exists(), "abgelehnte Abnahme darf keinen Skill installieren")
        self.assertEqual(ticket_file.read_bytes(), before_ticket)
        self.assertEqual(proposal_file.read_bytes(), before_proposal)
        self.assertEqual((self.world / sk.WORLD_LOG).read_text(encoding="utf-8"), before_log)

    def test_change_of_world_skill_keeps_previous_state_and_rejects_stale_base(self):
        proposal = self.propose_member_skill()
        sk.accept_proposal(self.world, proposal["ticket"], "lead", library=self.library)
        own = self.agent_skills("member") / "teil-skill" / "scripts" / "hilfe.sh"
        own.write_text("#!/bin/sh\necho hilfe\n", encoding="utf-8")
        own.chmod(0o755)
        second = sk.propose_skill(self.world, "member", "teil-skill", "welt", library=self.library)
        self.assertEqual(second["basis_version"], proposal["version"])
        self.assertIn("+echo hilfe", ad.read_ticket(self.world, second["ticket"])["goal"])
        # A second, competing change of the world skill makes the base stale.
        own.write_text("#!/bin/sh\necho andere hilfe\n", encoding="utf-8")
        third = sk.propose_skill(self.world, "member", "teil-skill", "welt", library=self.library)
        with self.assertRaisesRegex(ad.AgentsError, "adressierte"):
            sk.accept_proposal(self.world, second["ticket"], "main", "gut", library=self.library)
        accepted = sk.accept_proposal(self.world, second["ticket"], "lead", "gut", library=self.library)
        self.assertEqual(accepted["ticket_stand"], "abgenommen")
        self.assertEqual(sk.skill_version(Path(accepted["vorher"])), proposal["version"])
        self.assertTrue(os.access(self.world / "skills" / "teil-skill" / "scripts" / "hilfe.sh", os.X_OK))
        with self.assertRaisesRegex(ad.AgentsError, "seit dem Vorschlag geaendert"):
            sk.accept_proposal(self.world, third["ticket"], "lead", library=self.library)
        self.assertEqual(sk.skill_version(self.world / "skills" / "teil-skill"), second["version"])
        self.assertEqual([p.name for p in (self.world / "skills").iterdir() if p.name.startswith(".")], [])

    def test_acceptance_recovers_from_a_crash_between_the_two_renames(self):
        proposal = self.propose_member_skill()
        sk.accept_proposal(self.world, proposal["ticket"], "lead", library=self.library)
        (self.agent_skills("member") / "teil-skill" / "NOTIZ.md").write_text("neu\n", encoding="utf-8")
        second = sk.propose_skill(self.world, "member", "teil-skill", "welt", library=self.library)
        folder = self.world / sk.PROPOSAL_DIR / second["ticket"]
        target = self.world / "skills" / "teil-skill"
        # State a crash leaves behind: old state saved, old folder renamed away, new one not yet in place.
        sk._replace_folder(folder, "vorher", sk.skill_files(target), library_modes=False)
        os.replace(target, self.world / "skills" / ".teil-skill.alt-crash")
        (self.world / "skills" / ".teil-skill.creating-crash").mkdir()
        accepted = sk.accept_proposal(self.world, second["ticket"], "lead", library=self.library)
        self.assertEqual(sk.skill_version(target), second["version"])
        self.assertEqual(sk.skill_version(Path(accepted["vorher"])), proposal["version"])
        self.assertEqual(sorted(p.name for p in (self.world / "skills").iterdir()), ["teil-skill"])

    def test_tampered_stand_member_and_rejection(self):
        proposal = self.propose_member_skill()
        stand = self.world / sk.PROPOSAL_DIR / proposal["ticket"] / "stand" / "SKILL.md"
        original = stand.read_text(encoding="utf-8")
        stand.write_text(original + "\nNachgeschoben\n", encoding="utf-8")
        with self.assertRaisesRegex(ad.AgentsError, "veraendert"):
            sk.accept_proposal(self.world, proposal["ticket"], "lead", library=self.library)
        self.assertFalse((self.world / "skills" / "teil-skill").exists())
        stand.write_text(original, encoding="utf-8")
        rejected = sk.reject_proposal(self.world, proposal["ticket"], "lead", "Zweck deckt sich mit einem Weltskill")
        self.assertEqual(rejected["stand"], "abgelehnt")
        ticket = ad.read_ticket(self.world, proposal["ticket"])
        self.assertIn("Zweck deckt sich", ticket["result"]["text"])
        # A rejection by the leader closes the ticket just like an acceptance.
        self.assertEqual((rejected["ticket_stand"], ticket["state"], ticket["approval"]["agent"]),
                         ("abgenommen", "abgenommen", "lead"))
        with self.assertRaisesRegex(ad.AgentsError, "bereits abgelehnt"):
            sk.accept_proposal(self.world, proposal["ticket"], "lead", library=self.library)
        with self.assertRaisesRegex(ad.AgentsError, "bereits abgelehnt"):
            sk.propose_skill(self.world, "member", "teil-skill", "welt", library=self.library)
        self.assertEqual(self.history("member")[-1]["aktion"], "abgelehnt")

    def test_main_agent_proposal_needs_a_human_and_leader_proposal_goes_to_main(self):
        sk.create_skill(self.world, "main", "haupt-skill", "Vom Hauptagenten", library=self.library)
        own = sk.propose_skill(self.world, "main", "haupt-skill", "welt", library=self.library)
        self.assertEqual(own["pruefer"], "main")
        with self.assertRaisesRegex(ad.AgentsError, "eigenen Skill"):
            sk.accept_proposal(self.world, own["ticket"], "main", library=self.library)
        by_human = sk.accept_proposal(self.world, own["ticket"], "mensch", "freigegeben", library=self.library)
        self.assertEqual(by_human["ticket_stand"], "abgenommen")
        sk.create_skill(self.world, "lead", "leiter-skill", "Vom Teamleiter", library=self.library)
        leader = sk.propose_skill(self.world, "lead", "leiter-skill", "welt", library=self.library)
        self.assertEqual(leader["pruefer"], "main")
        self.assertEqual(sk.accept_proposal(self.world, leader["ticket"], "main", library=self.library)["ticket_stand"],
                         "abgenommen")


class LibraryProposalTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-skills-global-")
        base = Path(self.tmp.name)
        self.library = base / "repo" / "agents" / "bibliothek" / "skills"
        self.global_world = base / "global"
        self.project_world = base / "projekt" / ".werkbank" / "agents"
        ad.create_world(self.global_world, name="Global", main_name="chef", global_world=True)
        ad.create_agent(self.global_world, "kurator", "mitglied", None, "Pflegt Skills", None, None, None, None,
                        None, None, "lokal", "cli-operator", None)
        ad.create_world(self.project_world, name="Projekt", main_name="main")
        write_skill(self.project_world / "skills", "welt-skill", "Aus einem Projekt")

    def tearDown(self):
        self.tmp.cleanup()

    def test_world_skill_of_a_project_reaches_the_library_through_the_global_main_agent(self):
        proposal = sk.propose_skill(self.global_world, "kurator", "welt-skill", "bibliothek",
                                    from_world=self.project_world, library=self.library)
        self.assertEqual(proposal["pruefer"], "chef")
        with self.assertRaisesRegex(ad.AgentsError, "eigenen Skill"):
            sk.accept_proposal(self.global_world, proposal["ticket"], "kurator", library=self.library)
        accepted = sk.accept_proposal(self.global_world, proposal["ticket"], "chef", library=self.library)
        folder = self.library / "welt-skill"
        self.assertEqual(sk.skill_version(folder), proposal["version"])
        self.assertEqual(oct((folder / "SKILL.md").stat().st_mode & 0o777), "0o644")
        self.assertEqual(accepted["ticket_stand"], "abgenommen")
        log = [json.loads(line) for line in (self.global_world / sk.WORLD_LOG).read_text().splitlines()]
        self.assertEqual([(e["event"], e["ziel"]) for e in log], [("vorschlag", "bibliothek"), ("abgenommen", "bibliothek")])
        with self.assertRaisesRegex(ad.AgentsError, "diesen Stand bereits"):
            sk.propose_skill(self.global_world, "kurator", "welt-skill", "bibliothek",
                             from_world=self.project_world, library=self.library)


class MergeFindingTests(SkillsTestBase):
    def test_findings_name_duplicates_similar_purpose_and_shared_scripts_without_deleting(self):
        script = {"scripts/zaehlen.sh": "#!/bin/sh\nwc -l \"$1\"\n"}
        write_skill(self.world / "skills", "zeilen-zaehlen", "Zaehlt Zeilen einer Textdatei schnell", script)
        write_skill(self.agent_skills("member"), "zeilen-zaehlen", "Zaehlt Zeilen einer Textdatei schnell", script)
        write_skill(self.agent_skills("other"), "textzeilen", "Zaehlt Zeilen einer Textdatei", script)
        write_skill(self.library, "ganz-anders", "Rendert Diagramme als Bilder")
        result = sk.merge_findings(self.world, library=self.library, threshold=0.5)
        kinds = {finding["art"] for finding in result["befunde"]}
        self.assertEqual(kinds, {"gleicher-name", "aehnlicher-zweck", "gleiches-skript"})
        same = next(f for f in result["befunde"] if f["art"] == "gleicher-name")
        self.assertTrue(same["identisch"])
        similar = [f for f in result["befunde"] if f["art"] == "aehnlicher-zweck"]
        self.assertTrue(all("ganz-anders" not in {s["name"] for s in f["skills"]} for f in similar))
        self.assertTrue((self.agent_skills("member") / "zeilen-zaehlen").exists())
        only = sk.merge_findings(self.world, names=["ganz-anders"], library=self.library)
        self.assertEqual(only["befunde"], [])


class LearningStepTests(SkillsTestBase):
    def run_dir(self, name, data):
        folder = self.base / "zuege" / name
        folder.mkdir(parents=True)
        if data is not None:
            (folder / sk.LEARN_FILE).write_text(json.dumps(data) if not isinstance(data, str) else data, encoding="utf-8")
        return folder

    def memory(self, agent_id="member"):
        return (self.world / "agents" / agent_id / "MEMORY.md").read_text(encoding="utf-8")

    def test_lesson_is_short_dated_with_reason_and_applied_once(self):
        step = {"art": "lehre", "text": "Tests erst nach dem Commit laufen lassen.", "grund": "Beleg braucht Commit"}
        result = sk.lernschritt_anwenden(self.world, "member", self.run_dir("z1", step), date="2026-09-14")
        self.assertEqual(result["status"], "angewendet")
        memory = self.memory()
        self.assertIn("## Lehren\n\n- 2026-09-14: Tests erst nach dem Commit laufen lassen. Grund: Beleg braucht Commit\n", memory)
        self.assertNotIn(sk.MEMORY_PLACEHOLDER, memory)
        again = sk.lernschritt_anwenden(self.world, "member", self.base / "zuege" / "z1", date="2026-09-15")
        self.assertEqual(again["status"], "angewendet")
        self.assertEqual(self.memory(), memory)
        self.assertEqual(len([e for e in self.history("member") if e["event"] == "lernschritt"]), 1)
        second = sk.lernschritt_anwenden(self.world, "member", self.run_dir("z2", dict(step)), date="2026-09-16")
        self.assertEqual(second["status"], "vorhanden")
        third = sk.lernschritt_anwenden(self.world, "member", self.run_dir(
            "z3", {"art": "lehre", "text": "Zweite Lehre.", "grund": "anderer Fall"}), date="2026-09-16")
        self.assertEqual(third["status"], "angewendet")
        self.assertTrue(self.memory().endswith("Grund: Beleg braucht Commit\n- 2026-09-16: Zweite Lehre. Grund: anderer Fall\n"))

    def test_memory_limit_nothing_missing_and_invalid(self):
        path = self.world / "agents" / "member" / "MEMORY.md"
        path.write_text("# Gedächtnis\n\n" + "x" * sk.MEMORY_LIMIT, encoding="utf-8")
        full = sk.lernschritt_anwenden(self.world, "member", self.run_dir(
            "voll", {"art": "lehre", "text": "Neu.", "grund": "g"}))
        self.assertEqual(full["status"], "abgewiesen")
        self.assertIn("zusammenfassen", full["fehler"])
        nothing = sk.lernschritt_anwenden(self.world, "member", self.run_dir("n", {"art": "nichts", "text": "nichts gelernt"}))
        self.assertEqual(nothing["status"], "nichts")
        self.assertEqual(sk.lernschritt_anwenden(self.world, "member", self.run_dir("leer", None))["status"], "fehlt")
        for name, data in (("kaputt", "{"), ("art", {"art": "roman"}), ("feld", {"art": "nichts", "extra": 1}),
                           ("ohnegrund", {"art": "lehre", "text": "x"}),
                           ("lang", {"art": "lehre", "text": "x" * 501, "grund": "g"})):
            result = sk.lernschritt_anwenden(self.world, "member", self.run_dir(name, data))
            self.assertEqual(result["status"], "ungueltig", name)
        link_dir = self.run_dir("link", None)
        (link_dir / sk.LEARN_FILE).symlink_to(self.base / "zuege" / "n" / sk.LEARN_FILE)
        self.assertEqual(sk.lernschritt_anwenden(self.world, "member", link_dir)["status"], "ungueltig")
        statuses = [e["status"] for e in self.history("member") if e["event"] == "lernschritt"]
        self.assertEqual(statuses.count("ungueltig"), 6)

    def test_instruction_diff_only_adds(self):
        path = self.world / "agents" / "member" / "AGENTS.md"
        before = path.read_text(encoding="utf-8")
        lines = before.splitlines(keepends=True)
        import difflib
        add = "".join(difflib.unified_diff(lines, lines + ["\n", "Vor jeder Abgabe pruefen-vor-abgabe nutzen.\n"],
                                           "a/AGENTS.md", "b/AGENTS.md"))
        applied = sk.lernschritt_anwenden(self.world, "member", self.run_dir(
            "a1", {"art": "anweisung", "diff": add, "grund": "Belege fehlten zweimal"}))
        self.assertEqual(applied["status"], "angewendet", applied)
        self.assertTrue(path.read_text(encoding="utf-8").endswith("Vor jeder Abgabe pruefen-vor-abgabe nutzen.\n"))
        removal = "".join(difflib.unified_diff(lines, lines[1:], "a/AGENTS.md", "b/AGENTS.md"))
        rejected = sk.lernschritt_anwenden(self.world, "member", self.run_dir(
            "a2", {"art": "anweisung", "diff": removal, "grund": "kuerzer"}))
        self.assertEqual(rejected["status"], "abgewiesen")
        self.assertIn("nur Ergaenzungen", rejected["fehler"])
        stale = sk.lernschritt_anwenden(self.world, "member", self.run_dir(
            "a3", {"art": "anweisung", "diff": add, "grund": "doppelt"}))
        self.assertEqual(stale["status"], "vorhanden")
        self.assertEqual(path.read_text(encoding="utf-8").count("pruefen-vor-abgabe nutzen"), 1)
        wrong = sk.lernschritt_anwenden(self.world, "member", self.run_dir(
            "a4", {"art": "anweisung", "ziel": "CLAUDE.md", "diff": add, "grund": "g"}))
        self.assertEqual(wrong["status"], "abgewiesen")

    def test_skill_changes_own_directly_new_from_null_and_world_skill_as_proposal(self):
        sk.create_skill(self.world, "member", "eigen", "Eigener Skill", library=self.library)
        own_files = sk.skill_files(self.agent_skills("member") / "eigen")
        changed = dict(own_files)
        changed["scripts/tu.sh"] = (b"#!/bin/sh\necho tu\n", True)
        git_style = sk.skill_diff(own_files, changed)
        result = sk.lernschritt_anwenden(self.world, "member", self.run_dir(
            "s1", {"art": "skill", "ziel": "eigen", "diff": git_style, "grund": "Schritt kam dreimal vor"}))
        self.assertEqual(result["status"], "angewendet", result)
        self.assertTrue(os.access(self.agent_skills("member") / "eigen" / "scripts" / "tu.sh", os.X_OK))
        new_skill = sk.skill_diff(None, {"SKILL.md": (skill_md("frisch", "Neu gelernt").encode(), False)})
        created = sk.lernschritt_anwenden(self.world, "member", self.run_dir(
            "s2", {"art": "skill", "ziel": "frisch", "diff": new_skill, "grund": "neuer Ablauf"}))
        self.assertEqual(created["status"], "angewendet", created)
        broken = sk.skill_diff(None, {"SKILL.md": (b"---\nname: anders\ndescription: x\n---\n", False)})
        refused = sk.lernschritt_anwenden(self.world, "member", self.run_dir(
            "s3", {"art": "skill", "ziel": "kaputt", "diff": broken, "grund": "g"}))
        self.assertEqual(refused["status"], "abgewiesen")
        self.assertFalse((self.agent_skills("member") / "kaputt").exists())
        world_skill = write_skill(self.world / "skills", "welt-skill", "Gehoert der Welt")
        world_files = sk.skill_files(world_skill)
        improved = dict(world_files)
        improved["SKILL.md"] = (world_files["SKILL.md"][0].replace(b"1. Tun.", b"1. Tun.\n2. Pruefen."), False)
        proposal = sk.lernschritt_anwenden(self.world, "member", self.run_dir(
            "s4", {"art": "skill", "ziel": "welt-skill", "diff": sk.skill_diff(world_files, improved),
                   "grund": "Pruefschritt fehlte"}))
        self.assertEqual(proposal["status"], "vorschlag", proposal)
        self.assertEqual(sk.skill_files(world_skill), world_files)
        self.assertEqual(proposal["vorschlag"]["pruefer"], "lead")
        self.assertEqual(sk.files_version(sk.skill_files(self.agent_skills("member") / "welt-skill")),
                         proposal["vorschlag"]["version"])
        repeated = sk.lernschritt_anwenden(self.world, "member", self.base / "zuege" / "s4")
        self.assertEqual(repeated["vorschlag"]["ticket"], proposal["vorschlag"]["ticket"])
        traversal = "--- a/../../agents/main/AGENTS.md\n+++ b/../../agents/main/AGENTS.md\n@@ -1 +1 @@\n-a\n+b\n"
        escaped = sk.lernschritt_anwenden(self.world, "member", self.run_dir(
            "s5", {"art": "skill", "ziel": "eigen", "diff": traversal, "grund": "g"}))
        self.assertEqual(escaped["status"], "abgewiesen")


class MeasurementTests(SkillsTestBase):
    CLAUDE = "\n".join(json.dumps(e) for e in (
        {"type": "system", "subtype": "init", "session_id": "s", "model": "claude-sonnet-5"},
        {"type": "assistant", "message": {"id": "m1", "usage": {"input_tokens": 10, "output_tokens": 5}}},
        {"type": "result", "subtype": "success", "is_error": False, "num_turns": 2, "total_cost_usd": 0.12,
         "usage": {"input_tokens": 120, "output_tokens": 40, "cache_read_input_tokens": 3000,
                   "cache_creation_input_tokens": 500}},
    )) + "\n"

    def test_claude_codex_and_pi_outputs(self):
        claude = sk.measure_turn(self.CLAUDE.encode(), "claude")
        self.assertEqual(claude["tokens"], {"input": 120, "output": 40, "cache_read": 3000, "cache_write": 500,
                                            "reasoning": 0, "gesamt": 3660})
        self.assertEqual((claude["modell"], claude["kosten_usd"], claude["vollstaendig"]), ("claude-sonnet-5", 0.12, True))
        partial = "\n".join(json.dumps(e) for e in (
            {"type": "assistant", "message": {"id": "m1", "usage": {"input_tokens": 10, "output_tokens": 1}}},
            {"type": "assistant", "message": {"id": "m1", "usage": {"input_tokens": 10, "output_tokens": 7}}},
            {"type": "assistant", "message": {"id": "m2", "usage": {"input_tokens": 20, "output_tokens": 3,
                                                                     "cache_read_input_tokens": 100}}},
        )) + "\n{\"type\": \"res"
        fallback = sk.measure_turn(partial, "claude")
        self.assertFalse(fallback["vollstaendig"])
        self.assertEqual(fallback["tokens"]["gesamt"], 10 + 7 + 20 + 3 + 100)
        codex = "\n".join(json.dumps(e) for e in (
            {"type": "turn_context", "payload": {"model": "gpt-5.6-terra"}},
            {"type": "turn.completed", "usage": {"input_tokens": 1000, "cached_input_tokens": 800, "output_tokens": 50,
                                                 "reasoning_output_tokens": 20}},
            {"type": "turn.completed", "usage": {"input_tokens": 500, "cached_input_tokens": 0, "output_tokens": 10}},
        ))
        measured = sk.measure_turn(codex, "codex")
        self.assertEqual(measured["tokens"], {"input": 700, "output": 60, "cache_read": 800, "cache_write": 0,
                                              "reasoning": 20, "gesamt": 1560})
        self.assertEqual(measured["modell"], "gpt-5.6-terra")
        rollout = "\n".join(json.dumps(e) for e in (
            {"type": "event_msg", "payload": {"type": "token_count", "info": None}},
            {"type": "event_msg", "payload": {"type": "token_count", "info": {
                "total_token_usage": {"input_tokens": 300, "cached_input_tokens": 100, "output_tokens": 30},
                "last_token_usage": {"input_tokens": 300, "cached_input_tokens": 100, "output_tokens": 30}}}},
        ))
        self.assertEqual(sk.measure_turn(rollout, "codex")["tokens"]["gesamt"], 330)
        message = {"role": "assistant", "model": "lmgamma", "timestamp": 1, "usage": {
            "input": 900, "output": 100, "cacheRead": 50, "cacheWrite": 0, "cost": {"total": 0}}}
        pi = "\n".join(json.dumps(e) for e in (
            {"type": "message_end", "message": message}, {"type": "turn_end", "message": message},
            {"type": "message_end", "message": {"role": "user", "usage": {"input": 5}}},
            {"type": "message_end", "message": dict(message, timestamp=2)},
        ))
        measured = sk.measure_turn(pi, "pi")
        self.assertEqual(measured["tokens"]["gesamt"], 2 * 1050)
        self.assertEqual(measured["kosten_usd"], 0.0)
        self.assertIsNone(sk.measure_turn(b"kein json\n", "claude"))
        with self.assertRaises(ad.AgentsError):
            sk.measure_turn(b"", "fable")

    def test_record_is_idempotent_per_run_and_evaluation_compares_last_five(self):
        base = sk.measure_turn(self.CLAUDE, "claude")
        # tickets3: das Feld `kind` gewinnt; ohne Feld (Bestand) gilt limits.art, sonst task.
        self.assertEqual(sk.ticket_kind(ad.create_ticket(self.world, "Bau", "Ziel", "Fertig", ["member"],
                                                         "main", None)), "auftrag")
        self.assertEqual(sk.ticket_kind({"id": "t", "limits": {"art": "Code Aenderung"}}), "code-aenderung")
        self.assertEqual(sk.ticket_kind(ad.create_ticket(self.world, "Bau", "Ziel", "Fertig", ["member"], "main",
                                                         None, kind="recherche")), "recherche")
        self.assertEqual(sk.ticket_kind({"id": "t", "kind": "pruefung"}, "nachricht"), "pruefung")
        kind = "task"
        self.assertEqual(sk.ticket_kind(None, "nachricht"), "nachricht")
        self.assertEqual(sk.ticket_kind({"id": "t"}), "ticket")
        for index in range(8):
            measurement = dict(base, tokens=dict(base["tokens"], gesamt=1000 if index < 3 else 500))
            sk.record_measurement(self.world, "member", kind, measurement, "lauf-%d" % index, "t-%d" % index)
        sk.record_measurement(self.world, "member", kind, base, "lauf-0")
        sk.record_measurement(self.world, "member", "nachricht", base, "lauf-n")
        path = self.world / "agents" / "member" / sk.MEASUREMENT_FILE
        self.assertEqual(len(path.read_text().splitlines()), 9)
        with path.open("a", encoding="utf-8") as stream:
            stream.write('{"halb')
        sk.record_measurement(self.world, "member", "nachricht", base, "lauf-m")
        evaluation = sk.evaluate_measurements(self.world, "member")
        code = evaluation["arten"][kind]
        self.assertEqual((code["anzahl"], len(code["letzte"])), (8, 5))
        self.assertEqual(code["mittel_letzte"]["gesamt"], 500)
        self.assertEqual(code["mittel"]["gesamt"], (3 * 1000 + 5 * 500) / 8)
        self.assertEqual(code["veraenderung"], -0.5)
        self.assertEqual(evaluation["arten"]["nachricht"]["anzahl"], 2)
        self.assertEqual(evaluation["fehlerhafte_zeilen"], 0)
        self.assertIsNone(evaluation["arten"]["nachricht"]["veraenderung"])
        with self.assertRaisesRegex(ad.AgentsError, "Ticketart"):
            sk.record_measurement(self.world, "member", "../x", base, "lauf-x")
        with self.assertRaisesRegex(ad.AgentsError, "keine Tokenzahlen"):
            sk.record_measurement(self.world, "member", kind, {"tokens": None}, "lauf-y")


class CliTests(SkillsTestBase):
    def cli(self, *args, check=True):
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
        result = subprocess.run([str(SHELL / "wb-skill"), *map(str, args), "--bibliothek", str(self.library)],
                                capture_output=True, text=True, env=env, timeout=60)
        if check:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_new_list_show_propose_accept_merge_and_learning_step(self):
        created = json.loads(self.cli("neu", self.world, "--agent", "member", "--name", "cli-skill",
                                      "--beschreibung", "Ueber die Kommandozeile", "--json").stdout)
        self.assertEqual(created["ebene"], "agent")
        listing = self.cli("liste", self.world, "--agent", "member").stdout
        self.assertIn("cli-skill", listing)
        self.assertIn("fehlt      lib-skill", listing)
        shown = json.loads(self.cli("zeigen", self.world, "cli-skill", "--agent", "member", "--json").stdout)
        self.assertEqual(shown["version"], created["version"])
        ticket = self.cli("vorschlag", self.world, "--agent", "member", "--name", "cli-skill", "--ziel", "welt").stdout.strip()
        denied = self.cli("abnehmen", self.world, ticket, "--absender", "lead", "--json", check=False)
        self.assertEqual(denied.returncode, 2)
        self.assertIn("run-gebundenen Controller-Beleg", denied.stderr)
        accepted = sk.accept_proposal(self.world, ticket, "lead", library=self.library)
        self.assertEqual(accepted["ticket_stand"], "abgenommen")
        self.assertIn("gleicher-name", self.cli("zusammenfuehren", self.world).stdout)
        run = self.base / "zug-cli"
        run.mkdir()
        (run / sk.LEARN_FILE).write_text(json.dumps({"art": "nichts"}), encoding="utf-8")
        self.assertTrue(self.cli("lernschritt", self.world, "--agent", "member", "--zug", run).stdout.startswith("nichts"))
        self.assertIn("member", self.cli("verzeichnis", self.world).stdout)
        failed = self.cli("neu", self.world, "--agent", "member", "--name", "Gross", "--beschreibung", "x", check=False)
        self.assertEqual(failed.returncode, 2)
        self.assertIn("wb-skill: FEHLER", failed.stderr)
        denied = self.cli("abnehmen", self.world, ticket, "--absender", "other", check=False)
        self.assertEqual(denied.returncode, 2)


class HookEnvironmentTests(SkillsTestBase):
    """skills_umgebung for the carrier, and the hook's own version rule kept equal to ours."""

    def hook_lib(self):
        sys.path.insert(0, str(REPO / "hooks" / "lib"))
        try:
            import skills_sperre
        finally:
            sys.path.remove(str(REPO / "hooks" / "lib"))
        return skills_sperre

    def test_environment_comes_from_written_directory(self):
        with self.assertRaisesRegex(ad.AgentsError, "zuerst wb-skill verzeichnis"):
            sk.skills_umgebung(self.world, "member")
        write_skill(self.library, "lib-skill", "Aus der Bibliothek")
        write_skill(self.world / "skills", "welt-skill", "Weltweit")
        sk.create_skill(self.world, "member", "eigen", "Eigener Skill", library=self.library)
        env = sk.skills_umgebung(self.world, "member")
        self.assertEqual(env["WB_WELT"], str(self.world))
        self.assertEqual(env["WB_AGENT_ID"], "member")
        self.assertEqual(env["WB_SKILLS_JSON"], str(self.world / "agents" / "member" / "skills.json"))
        self.assertEqual(env["WB_SKILL_PFADE"].split(os.pathsep),
                         [str(self.agent_skills("member") / "eigen"), str(self.library / "lib-skill"),
                          str(self.world / "skills" / "welt-skill")])
        self.assertEqual(env["WB_SKILL_BIBLIOTHEK"], str(self.library))
        self.assertTrue(all(isinstance(value, str) for value in env.values()))
        path = self.world / "agents" / "member" / "skills.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        path.write_text(json.dumps(dict(data, agent="other")), encoding="utf-8")
        with self.assertRaisesRegex(ad.AgentsError, "gehoert nicht"):
            sk.skills_umgebung(self.world, "member")

    def test_profile_environment_and_project_folder(self):
        env = sk.profil_umgebung(self.world, "member")
        self.assertEqual(env["WB_AGENT_PROFIL"], str(self.world / "agents" / "member" / "agent.json"))
        self.assertEqual(env["WB_WELT_PROJEKT"], "")  # a world outside <projekt>/.werkbank/agents names no project
        self.assertEqual((env["WB_AGENT_WORKTREE"], env["WB_AGENT_TMP"]), ("", ""))
        work, tmp = self.base / "work", self.base / "tmp"
        work.mkdir()
        tmp.mkdir()
        env = sk.profil_umgebung(self.world, "member", worktree=work, tmp=tmp, project=self.base)
        self.assertEqual((env["WB_AGENT_WORKTREE"], env["WB_AGENT_TMP"], env["WB_WELT_PROJEKT"]),
                         (str(work), str(tmp), str(self.base)))
        with self.assertRaisesRegex(ad.AgentsError, "kein Ordner"):
            sk.profil_umgebung(self.world, "member", worktree=self.base / "fehlt")
        with self.assertRaisesRegex(ad.AgentsError, "umfasst zu viel"):
            sk.profil_umgebung(self.world, "member", tmp="/")
        with self.assertRaises(ad.AgentsError):
            sk.profil_umgebung(self.world, "niemand")
        project = self.base / "projekt"
        project_world = project / ".werkbank" / "agents"
        ad.create_world(project_world, name="Projekt", main_name="main")
        self.assertEqual(sk.world_project(project_world), project)
        self.assertEqual(sk.profil_umgebung(project_world, "main")["WB_WELT_PROJEKT"], str(project))
        global_world = self.base / "global"
        ad.create_world(global_world, name="Global", main_name="chef", global_world=True)
        self.assertEqual(sk.world_project(global_world), Path.home() / "AI")
        sk.write_skill_directory(project_world, "main", self.library)
        merged = sk.skills_umgebung(project_world, "main")
        self.assertEqual(merged["WB_AGENT_PROFIL"], str(project_world / "agents" / "main" / "agent.json"))
        self.assertEqual(merged["WB_WELT_PROJEKT"], str(project))

    def test_hook_version_equals_module_version(self):
        hook = self.hook_lib()
        folder = write_skill(self.base / "lvl", "gleich", scripts={"scripts/a.sh": "#!/bin/sh\necho a\n",
                                                                   "tests/test_a.py": "pass\n"})
        (folder / "__pycache__").mkdir()
        (folder / "__pycache__" / "x.pyc").write_bytes(b"\0")
        (folder / "daten.bin").write_bytes(bytes(range(256)))
        self.assertEqual(hook.skill_version(str(folder)), sk.skill_version(folder))
        (folder / "scripts" / "a.sh").chmod(0o644)
        self.assertEqual(hook.skill_version(str(folder)), sk.skill_version(folder))
        (folder / "link").symlink_to(folder / "SKILL.md")
        self.assertIsNone(hook.skill_version(str(folder)))
        unit = write_script(self.base / "lvl-skripte", "gleich-skript")
        self.assertEqual(hook.skill_version(str(unit)), sk.skill_version(unit))

    def test_hook_decides_with_the_environment_from_the_module(self):
        hook = self.hook_lib()
        write_skill(self.library, "lib-skill", "Aus der Bibliothek", {"scripts/x.sh": "#!/bin/sh\necho x\n"})
        write_skill(self.library, "lib-fremd", "Nicht im Profil", {"scripts/x.sh": "#!/bin/sh\necho y\n"})
        write_script(self.world / "agents" / "member" / "skripte", "eigen-skript")
        write_script(self.world / "agents" / "other" / "skripte", "fremd-skript")
        sk.write_skill_directory(self.world, "member", self.library)
        env = sk.skills_umgebung(self.world, "member")
        # The content check chain (bash-guard, Testschutz) is proven against copies in
        # hooks/tests/test-skills-sperre.sh; here it stays off, so no live hook or pane is touched.
        env.update({hook.KETTEN_MARKER: "1"})
        saved = {key: os.environ.get(key) for key in list(env) + ["TMUX", "TMUX_PANE"]}
        os.environ.pop("TMUX", None)
        os.environ.pop("TMUX_PANE", None)
        os.environ.update(env)
        try:
            def decide(command):
                return hook.entscheiden({"tool_name": "Bash", "tool_input": {"command": command},
                                         "cwd": str(self.base)})
            self.assertIsNone(decide("sh %s/lib-skill/scripts/x.sh" % self.library))
            self.assertIn("not in the skills.json", decide("sh %s/lib-fremd/scripts/x.sh" % self.library))
            self.assertIn("wb-skill vorschlag", decide("rm -rf %s/lib-skill" % self.library))
            skripte = self.world / "agents"
            self.assertIsNone(decide("sh %s/member/skripte/eigen-skript/eigen-skript.sh" % skripte))
            self.assertIn("not in the skills.json", decide("sh %s/other/skripte/fremd-skript/fremd-skript.sh" % skripte))
            self.assertIn("not in the skills.json", hook.entscheiden({"tool_name": "Skill", "tool_input": {
                "skill": "eigen-skript"}, "cwd": str(self.base)}))
        finally:
            for key, value in saved.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value


class RepositoryLibraryHookTests(SkillsTestBase):
    """The real library: pruefen-vor-abgabe pulls its stored scripts into the directory, the hook follows it."""

    @unittest.skipUnless((REPO / "agents" / "bibliothek").is_dir(), "kit: the wb-agents library (agents/bibliothek) is not shipped")
    def test_library_skill_brings_its_stored_scripts_and_the_hook_allows_only_those(self):
        library = REPO / "agents" / "bibliothek" / "skills"
        scripts = REPO / "agents" / "bibliothek" / "skripte"
        ad.create_agent(self.world, "pruefer", "mitglied", "dev", "Prueft vor Abgabe", None, None, None, None,
                        None, None, "lokal", "cli-operator", None, skills=["pruefen-vor-abgabe"])
        sk.write_skill_directory(self.world, "pruefer", library)
        directory = json.loads((self.world / "agents" / "pruefer" / "skills.json").read_text(encoding="utf-8"))
        self.assertEqual(sorted((e["art"], e["name"], e["ebene"]) for e in directory["skills"]),
                         [("skill", "pruefen-vor-abgabe", "bibliothek"), ("skript", "diff-zusammenfassung", "bibliothek"),
                          ("skript", "tests-laufen", "bibliothek")])
        env = sk.skills_umgebung(self.world, "pruefer")
        self.assertEqual(env["WB_SKRIPT_BIBLIOTHEK"], str(scripts))
        sys.path.insert(0, str(REPO / "hooks" / "lib"))
        try:
            import skills_sperre as hook
        finally:
            sys.path.remove(str(REPO / "hooks" / "lib"))
        saved = {key: os.environ.get(key) for key in list(env) + [hook.KETTEN_MARKER, "TMUX", "TMUX_PANE"]}
        os.environ.pop("TMUX", None)
        os.environ.pop("TMUX_PANE", None)
        os.environ.update(env, **{hook.KETTEN_MARKER: "1"})
        try:
            def decide(tool, **fields):
                return hook.entscheiden({"tool_name": tool, "tool_input": fields, "cwd": str(self.base)})
            self.assertIsNone(decide("Bash", command="python3 %s/tests-laufen/tests-laufen.py --test 'true'" % scripts))
            self.assertIsNone(decide("Read", file_path=str(scripts / "diff-zusammenfassung" / "diff-zusammenfassung.py")))
            self.assertIn("not in the skills.json", decide("Bash", command="python3 %s/zitat-beleg/zitat-beleg.py" % scripts))
            self.assertIn("wb-skill skript vorschlag", decide("Edit", file_path=str(scripts / "tests-laufen" / "tests-laufen.py")))
        finally:
            for key, value in saved.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value


class ScriptUnitTests(SkillsTestBase):
    """Stored scripts: one executable file with an instruction header, on the same three levels as skills."""

    def setUp(self):
        super().setUp()
        self.scripts = self.base / "skripte"  # sibling of the skill library, as agents/bibliothek/skripte

    def files(self, folder):
        return sk.skill_files(folder)

    def test_header_format_carries_shell_and_python_and_is_checked(self):
        for language, suffix in (("sh", ".sh"), ("bash", ".sh"), ("python", ".py")):
            file_name, text = sk.script_template("vorlage", "Prüft: etwas", language)
            self.assertEqual(file_name, "vorlage" + suffix)
            info = sk.check_script_files("vorlage", {file_name: (text.encode(), True)})
            self.assertTrue(info["gueltig"], info["befunde"])
            self.assertEqual(info["description"], "Prüft: etwas")
            self.assertEqual([f["stufe"] for f in info["befunde"]], ["hinweis"])
            self.assertIn("\n", info["kopf"]["grenzen"])  # continuation line
        python_folder = write_script(self.base / "lvl", "py-skript", "print('x')\n", "#!/usr/bin/env python3", ".py")
        self.assertEqual(sk.check_unit(python_folder, "skript")["befunde"], [])
        result = subprocess.run([sys.executable, str(python_folder / "py-skript.py")], capture_output=True, text=True)
        self.assertEqual(result.stdout, "x\n")  # the header is plain comments for the interpreter

        def errors(files, name="x"):
            return [f["text"] for f in sk.check_script_files(name, files)["befunde"] if f["stufe"] == "fehler"]

        good = script_text("x").encode()
        self.assertEqual(errors({"x.sh": (good, True)}), [])
        self.assertIn("Skriptdatei ist nicht ausfuehrbar: x.sh", errors({"x.sh": (good, False)}))
        self.assertIn("Nur die Skriptdatei darf ausfuehrbar sein: tests/run.sh",
                      errors({"x.sh": (good, True), "tests/run.sh": (b"#!/bin/sh\n", True)}))
        self.assertTrue(any("nur tests/ erlaubt" in e for e in errors({"x.sh": (good, True), "README.md": (b"x", False)})))
        self.assertTrue(any("genau eine Skriptdatei" in e for e in errors({"x.sh": (good, True), "x.py": (good, True)})))
        self.assertTrue(any("genau eine Skriptdatei" in e for e in errors({"anders.sh": (good, True)})))
        self.assertTrue(any("Shebang" in e for e in errors({"x.sh": (good.split(b"\n", 1)[1], True)})))
        self.assertTrue(any("Zeile 2" in e for e in errors({"x.sh": (b"#!/bin/sh\necho x\n", True)})))
        self.assertTrue(any("Unbekannter Schluessel" in e for e in errors(
            {"x.sh": (script_text("x", keys={"autor": "y"}).encode(), True)})))
        self.assertIn("Kopfzeile 'ausgaben' fehlt oder ist leer", errors(
            {"x.sh": (script_text("x", keys={"ausgaben": None}).encode(), True)}))
        self.assertTrue(any("passt nicht zum Ordner" in e for e in errors(
            {"x.sh": (script_text("y").encode(), True)})))
        self.assertTrue(any("nicht mit '# ---' abgeschlossen" in e for e in errors(
            {"x.sh": (b"#!/bin/sh\n# ---\n# name: x\n", True)})))
        self.assertTrue(any("ohne '# ---'" in e for e in errors(
            {"x.sh": (b"#!/bin/sh\n# ---\n# name: x\necho x\n", True)})))
        replaced = sk.set_script_purpose(script_text("x", keys={"zweck": "alt\n#   weiter"}).encode(), "Neu")
        self.assertEqual(sk.parse_script_header(replaced)["zweck"], "Neu")
        import difflib

        def plain(rel):  # unified diff without git mode lines
            return "".join(difflib.unified_diff([], good.decode().splitlines(keepends=True), "/dev/null", "b/" + rel))

        self.assertTrue(sk.apply_diff({}, plain("x.sh"), "skript")["x.sh"][1])
        self.assertFalse(sk.apply_diff({}, plain("tests/t.sh"), "skript")["tests/t.sh"][1])
        self.assertFalse(sk.apply_diff({}, plain("x.sh"), "skill")["x.sh"][1])
        with self.assertRaisesRegex(ad.AgentsError, "kein gueltiger Skriptname"):
            sk.script_references("gut, Schlecht")
        self.assertEqual(sk.script_references(" a-b, c  a-b "), ["a-b", "c"])

    def test_create_resolve_over_three_levels_environment_and_listing(self):
        write_skill(self.library, "lib-skill", "Aus der Bibliothek", references="lib-skript, fehlt-skript")
        write_script(self.scripts, "lib-skript")
        write_script(self.scripts, "nicht-verwiesen")
        write_script(self.scripts, "nur-profil")
        write_script(self.scripts, "geteilt-skript", "echo bibliothek\n")
        write_script(self.world / "skripte", "geteilt-skript")
        write_script(self.world / "skripte", "kaputt-skript")
        (self.world / "skripte" / "kaputt-skript" / "kaputt-skript.sh").chmod(0o644)
        created = sk.create_script(self.world, "member", "geteilt-skript", None, source_level="welt",
                                   library=self.library)
        self.assertEqual((created["art"], created["ebene"]), ("skript", "agent"))
        python = sk.create_script(self.world, "member", "neu-py", "Rechnet: schnell", language="python",
                                  library=self.library)
        self.assertTrue(python["datei"].endswith("neu-py.py") and os.access(python["datei"], os.X_OK))
        self.assertFalse((self.world / "agents" / "member" / "skripte" / "neu-py" / "scripts").exists())
        with self.assertRaisesRegex(ad.AgentsError, "Skript existiert bereits"):
            sk.create_script(self.world, "member", "neu-py", "Nochmal", library=self.library)
        with self.assertRaisesRegex(ad.AgentsError, "Zweck fehlt"):
            sk.create_script(self.world, "member", "ohne-zweck", library=self.library)
        directory = sk.skill_directory(self.world, "member", self.library)
        self.assertEqual(directory["schema_version"], sk.DIRECTORY_SCHEMA_VERSION)
        self.assertEqual(directory["skript_bibliothek"], str(self.scripts))
        scripts = {e["name"]: e for e in directory["skills"] if e["art"] == "skript"}
        self.assertEqual(set(scripts), {"geteilt-skript", "lib-skript", "neu-py"})
        self.assertEqual([(v["ebene"], v["gleich"]) for v in scripts["geteilt-skript"]["verdeckt"]],
                         [("welt", True), ("bibliothek", False)])
        self.assertEqual(scripts["lib-skript"]["genutzt_von"], ["lib-skill"])
        self.assertEqual(scripts["lib-skript"]["datei"], str(self.scripts / "lib-skript" / "lib-skript.sh"))
        self.assertEqual(scripts["lib-skript"]["aufruf"], "lib-skript.sh")
        skill = next(e for e in directory["skills"] if e["art"] == "skill")
        self.assertEqual((skill["name"], skill["skripte"]), ("lib-skill", ["lib-skript", "fehlt-skript"]))
        self.assertEqual(directory["fehlende_skripte"], [{"skript": "fehlt-skript", "skills": ["lib-skill"]}])
        self.assertEqual([(i["art"], i["name"]) for i in directory["ungueltig"]], [("skript", "kaputt-skript")])
        other = {e["name"] for e in sk.skill_directory(self.world, "other", self.library)["skills"]}
        self.assertEqual(other, {"geteilt-skript"})  # no skill names lib-skript, so the library script stays out
        ad.create_agent(self.world, "profil", "mitglied", "dev", "Nennt ein Skript", None, None, None, None,
                        None, None, "lokal", "cli-operator", None, skills=["nur-profil"])
        profile = sk.skill_directory(self.world, "profil", self.library)
        self.assertEqual({e["name"]: e["vorgeladen"] for e in profile["skills"] if e["art"] == "skript"},
                         {"geteilt-skript": False, "nur-profil": True})
        self.assertEqual(profile["fehlend"], [])
        sk.write_skill_directory(self.world, "member", self.library)
        env = sk.skills_umgebung(self.world, "member")
        self.assertEqual(env["WB_SKILL_PFADE"], str(self.library / "lib-skill"))
        self.assertEqual(env["WB_SKRIPT_PFADE"].split(os.pathsep),
                         [str(self.world / "agents" / "member" / "skripte" / "geteilt-skript"),
                          str(self.scripts / "lib-skript"), str(self.world / "agents" / "member" / "skripte" / "neu-py")])
        self.assertEqual(env["WB_SKRIPT_BIBLIOTHEK"], str(self.scripts))
        shown = sk.show_unit(self.world, "lib-skript", "skript", library=self.library)
        self.assertEqual(shown["ebene"], "bibliothek")
        self.assertIn("# name: lib-skript", shown["inhalt"])
        listing = sk.list_skills(self.world, library=self.library)
        self.assertEqual([s["name"] for s in listing["skripte"]["welt"]], ["geteilt-skript", "kaputt-skript"])
        self.assertEqual(listing["welt"], [])
        empty = self.base / "leer"
        ad.create_world(empty, name="Leer", main_name="main")
        sk.write_skill_directory(empty, "main", self.base / "gibt-es-nicht" / "skills")
        self.assertEqual((sk.skills_umgebung(empty, "main")["WB_SKRIPT_BIBLIOTHEK"],
                          sk.skills_umgebung(empty, "main")["WB_SKILL_BIBLIOTHEK"]), ("", ""))

    def test_script_proposal_acceptance_rejection_and_learning_step(self):
        sk.create_script(self.world, "member", "team-skript", "Hilft dem Team", library=self.library)
        own = self.world / "agents" / "member" / "skripte" / "team-skript" / "team-skript.sh"
        own.write_text(own.read_text(encoding="utf-8").replace('echo "team-skript: noch ohne Inhalt" >&2\nexit 2\n',
                                                               "echo team\n"), encoding="utf-8")
        proposal = sk.propose_skill(self.world, "member", "team-skript", "welt", reason="Nuetzt allen",
                                    library=self.library, art="skript")
        self.assertTrue(proposal["ticket"].startswith("skript-"))
        ticket = ad.read_ticket(self.world, proposal["ticket"])
        self.assertEqual(ticket["title"], "Skill-Vorschlag: Skript team-skript von member in welt")
        self.assertEqual((ticket["recipients"], ticket["limits"]["art"], ticket["limits"]["einheit"]),
                         (["lead"], "skill-vorschlag", "skript"))
        self.assertIn("+echo team", ticket["goal"])
        self.assertIn("wb-skill skript abnehmen", ticket["goal"])
        accepted = sk.accept_proposal(self.world, proposal["ticket"], "lead", "gut", library=self.library)
        world_script = self.world / "skripte" / "team-skript"
        self.assertEqual((accepted["art"], sk.skill_version(world_script)), ("skript", proposal["version"]))
        self.assertFalse((world_script / "scripts").exists())
        self.assertTrue(ad.read_ticket(self.world, proposal["ticket"])["result"]["text"].startswith(
            "Skill übernommen: Skript team-skript"))
        other = json.loads((self.world / "agents" / "other" / "skills.json").read_text(encoding="utf-8"))
        self.assertEqual([(e["art"], e["name"], e["ebene"]) for e in other["skills"]], [("skript", "team-skript", "welt")])
        log = [json.loads(line) for line in (self.world / sk.WORLD_LOG).read_text().splitlines()]
        self.assertEqual([(e["event"], e["art"]) for e in log], [("vorschlag", "skript"), ("abgenommen", "skript")])
        self.assertEqual(self.history("member")[-1]["art"], "skript")

        run = self.base / "zuege"
        # Learning step on a world script: own copy with the change plus a proposal to the world.
        files = sk.skill_files(world_script)
        changed = {rel: ((data.replace(b"echo team", b"echo team; echo mehr"), x) if rel.endswith(".sh") else (data, x))
                   for rel, (data, x) in files.items()}
        (run / "k1").mkdir(parents=True)
        (run / "k1" / sk.LEARN_FILE).write_text(json.dumps({"art": "skript", "ziel": "team-skript", "grund": "mehr",
                                                            "diff": sk.skill_diff(files, changed)}), encoding="utf-8")
        result = sk.lernschritt_anwenden(self.world, "other", run / "k1")
        self.assertEqual(result["status"], "vorschlag", result)
        self.assertEqual((result["vorschlag"]["art"], result["vorschlag"]["pruefer"]), ("skript", "lead"))
        self.assertEqual(sk.skill_files(world_script), files)
        self.assertTrue((self.world / "agents" / "other" / "skripte" / "team-skript").is_dir())
        # A new own script from /dev/null, as a plain unified diff without mode, gets its executable bit from the shebang.
        (run / "k2").mkdir()
        import difflib
        new = "".join(difflib.unified_diff([], script_text("frisch").splitlines(keepends=True), "/dev/null", "b/frisch.sh"))
        (run / "k2" / sk.LEARN_FILE).write_text(json.dumps({"art": "skript", "ziel": "frisch", "grund": "neu",
                                                            "diff": new}), encoding="utf-8")
        self.assertEqual(sk.lernschritt_anwenden(self.world, "member", run / "k2")["status"], "angewendet")
        self.assertTrue(os.access(self.world / "agents" / "member" / "skripte" / "frisch" / "frisch.sh", os.X_OK))
        (run / "k3").mkdir()
        two = sk.skill_diff(None, {"zwei.sh": (script_text("zwei").encode(), False),
                                   "zwei.py": (script_text("zwei").encode(), False)})
        (run / "k3" / sk.LEARN_FILE).write_text(json.dumps({"art": "skript", "ziel": "zwei", "grund": "g",
                                                            "diff": two}), encoding="utf-8")
        refused = sk.lernschritt_anwenden(self.world, "member", run / "k3")
        self.assertEqual(refused["status"], "abgewiesen")
        self.assertIn("genau eine Skriptdatei", refused["fehler"])
        rejected = sk.reject_proposal(self.world, result["vorschlag"]["ticket"], "lead", "Zweck deckt sich")
        self.assertEqual((rejected["art"], rejected["stand"]), ("skript", "abgelehnt"))
        self.assertIn("Skill-Vorschlag abgelehnt: Skript team-skript",
                      ad.read_ticket(self.world, result["vorschlag"]["ticket"])["result"]["text"])

    def test_merge_finding_names_a_skill_that_copies_a_stored_script(self):
        body = "wc -l \"$1\"\n"
        folder = write_script(self.world / "skripte", "zeilen", body)
        text = (folder / "zeilen.sh").read_text(encoding="utf-8")
        write_skill(self.agent_skills("member"), "zaehler", "Zaehlt", {"scripts/zeilen.sh": text})
        findings = sk.merge_findings(self.world, library=self.library)["befunde"]
        copy = next(f for f in findings if f["art"] == "gleiches-skript")
        self.assertEqual(sorted((s["art"], s["name"]) for s in copy["skills"]), [("skill", "zaehler"), ("skript", "zeilen")])
        self.assertIn("kopiert ein gespeichertes Skript", copy["empfehlung"])

    def test_cli_script_commands(self):
        def cli(*args, check=True):
            result = subprocess.run([str(SHELL / "wb-skill"), *map(str, args), "--bibliothek", str(self.library)],
                                    capture_output=True, text=True, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"),
                                    timeout=60)
            if check:
                self.assertEqual(result.returncode, 0, result.stderr)
            return result

        created = cli("skript", "neu", self.world, "--agent", "member", "--name", "cli-skript",
                      "--zweck", "Ueber die Kommandozeile", "--sprache", "python").stdout.strip()
        self.assertTrue(created.endswith("cli-skript/cli-skript.py"))
        self.assertIn("cli-skript", cli("skript", "liste", self.world, "--agent", "member").stdout)
        self.assertNotIn("cli-skript", cli("liste", self.world, "--agent", "member").stdout)
        shown = json.loads(cli("skript", "zeigen", self.world, "cli-skript", "--agent", "member", "--json").stdout)
        self.assertEqual((shown["art"], shown["datei"]), ("skript", "cli-skript.py"))
        ticket = cli("skript", "vorschlag", self.world, "--agent", "member", "--name", "cli-skript",
                     "--ziel", "welt").stdout.strip()
        denied = cli("skript", "abnehmen", self.world, ticket, "--absender", "lead", "--json", check=False)
        self.assertEqual(denied.returncode, 2)
        self.assertIn("run-gebundenen Controller-Beleg", denied.stderr)
        accepted = sk.accept_proposal(self.world, ticket, "lead", library=self.library)
        self.assertEqual(accepted["pfad"], str(self.world / "skripte" / "cli-skript"))
        self.assertIn("1 Skripte", cli("verzeichnis", self.world, "--agent", "other").stdout)
        sk.create_skill(self.world, "member", "cli-skill", "Ein Skill", library=self.library)
        skill_ticket = sk.propose_skill(self.world, "member", "cli-skill", "welt", library=self.library)["ticket"]
        wrong = cli("skript", "ablehnen", self.world, skill_ticket, "--absender", "lead", "--grund", "x", check=False)
        self.assertEqual(wrong.returncode, 2)
        self.assertIn("schlaegt kein Skript vor", wrong.stderr)


class RepositoryLibraryTests(unittest.TestCase):
    def run_tests(self, folder):
        tests = sorted((folder / "tests").glob("test_*.py"))
        self.assertTrue(tests, folder.name)
        for test in tests:
            env = {key: value for key, value in os.environ.items() if not key.startswith("WB_SKRIPT")}
            env["PYTHONDONTWRITEBYTECODE"] = "1"
            result = subprocess.run([sys.executable, str(test)], capture_output=True, text=True, env=env, timeout=300)
            self.assertEqual(result.returncode, 0, "%s\n%s" % (test, result.stderr[-2000:]))

    @unittest.skipUnless((REPO / "agents" / "bibliothek").is_dir(), "kit: the wb-agents library (agents/bibliothek) is not shipped")
    def test_library_templates_are_valid_have_tested_scripts_and_tests_pass(self):
        library = REPO / "agents" / "bibliothek" / "skills"
        scripts = REPO / "agents" / "bibliothek" / "skripte"
        self.assertEqual(sk.script_library_path(library), scripts)
        names = sorted(item.name for item in library.iterdir() if not item.name.startswith("."))
        for name in LIBRARY_SKILLS:
            self.assertIn(name, names)
        for name in names:
            info = sk.check_skill(library / name, name)
            self.assertTrue(info["gueltig"], (name, info["befunde"]))
            self.assertEqual(info["befunde"], [], name)
            self.assertTrue(info["skripte"] or info["verweise"], name)
            for rel in info["skripte"]:
                self.assertTrue(os.access(library / name / rel, os.X_OK), rel)
            for reference in info["verweise"]:
                self.assertTrue(sk.check_unit(scripts / reference, "skript", reference)["gueltig"], reference)
            if info["skripte"]:
                self.run_tests(library / name)
        script_names = sorted(item.name for item in scripts.iterdir() if not item.name.startswith("."))
        self.assertEqual(tuple(script_names), LIBRARY_SCRIPTS)
        for name in script_names:
            info = sk.check_unit(scripts / name, "skript", name)
            self.assertTrue(info["gueltig"], (name, info["befunde"]))
            self.assertEqual(info["befunde"], [], name)
            self.assertTrue(os.access(scripts / name / info["datei"], os.X_OK), name)
            self.run_tests(scripts / name)
        # No copy: the stored scripts' code is not duplicated inside a skill.
        stored = {hashlib.sha256((scripts / n / sk.check_unit(scripts / n, "skript")["datei"]).read_bytes()).hexdigest()
                  for n in script_names}
        copies = [rel for rel in library.rglob("scripts/*") if hashlib.sha256(rel.read_bytes()).hexdigest() in stored]
        self.assertEqual(copies, [])
        self.assertFalse(list(library.rglob("__pycache__")) + list(scripts.rglob("__pycache__")))


if __name__ == "__main__":
    unittest.main()
