#!/usr/bin/env python3
"""Isolated stdlib tests for the first independent Agents data slice."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
import multiprocessing
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path

HERE = Path(__file__).resolve()
SHELL = HERE.parents[1]
sys.path.insert(0, str(SHELL))
import agents_data as ad
import agents_controller as ac
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


def _run_cli(kind, *args):
    """Exercise the real parser while keeping this module's origin fixtures in-process."""
    stdout, stderr = StringIO(), StringIO()
    with redirect_stdout(stdout), redirect_stderr(stderr):
        status = ad.run(kind, [str(arg) for arg in args])
    return subprocess.CompletedProcess(args, status, stdout.getvalue(), stderr.getvalue())


def _claim_race(world, ticket_id, agent_id, barrier, queue):
    barrier.wait()
    try:
        ticket = ad.claim_ticket(Path(world), ticket_id, agent_id, agent_id, "mitglied")
        queue.put((agent_id, "ok", ticket["assignee"]))
    except Exception as exc:
        queue.put((agent_id, "error", str(exc)))


def _world_race(world, queue):
    try:
        result = ad.create_world(Path(world), name="Race", main_name="main", sender="cli-operator")
        queue.put(("ok", result["hauptagent"]["id"]))
    except Exception as exc:
        queue.put(("error", str(exc)))


def _same_agent_claim_race(world, ticket_id, barrier, queue):
    barrier.wait()
    try:
        ticket = ad.claim_ticket(Path(world), ticket_id, "member", "member", "mitglied")
        queue.put((ticket_id, "ok", ticket["assignee"]))
    except Exception as exc:
        queue.put((ticket_id, "error", str(exc)))


class AgentsDataTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-data-")
        self.world = Path(self.tmp.name) / "world"
        self.created = ad.create_world(self.world, name="Probe", main_name="main", sender="mensch")

    def tearDown(self):
        self.tmp.cleanup()

    def add_team(self):
        lead = ad.create_agent(self.world, "lead", "teamleiter", "dev", "Leitet Entwicklung",
                               None, None, None, None, None, None, "lokal", "mensch", None)
        member = ad.create_agent(self.world, "member", "mitglied", "dev", "Baut Dateien",
                                 None, None, None, None, None, None, "lokal", "mensch", None)
        return lead, member

    def test_world_agent_ticket_result_approval_and_ack(self):
        self.add_team()
        ticket = ad.create_ticket(self.world, "Probe", "Datei bauen", "Test gruen", ["member"],
                                  "main", "hauptagent", team="dev")
        self.assertEqual(ticket["state"], "offen")
        claimed = ad.claim_ticket(self.world, ticket["id"], "member", "member", "mitglied")
        self.assertEqual(claimed["state"], "läuft")
        result = ad.write_result(self.world, ticket["id"], "member", "Erledigt", "abc123", "member", "mitglied")
        self.assertEqual(result["state"], "zur Abnahme")
        accepted = ad.approve_ticket(self.world, ticket["id"], "lead", "teamleiter", "Passt")
        self.assertEqual(accepted["state"], "abgenommen")
        messages = ad.read_messages(self.world)
        result_message = next(item for item in messages if item["id"] == accepted["result_message_id"])
        delivery = ad._delivery_path(self.world, "main", result_message["id"])
        self.assertTrue(delivery.exists())
        self.assertTrue(ad.acknowledge(self.world, "main", result_message["id"], "main", "hauptagent")["acknowledged"])

    def test_direct_chat_is_separate_idempotent_and_quittable(self):
        self.add_team()
        times = iter(("2026-01-01T00:00:00Z", "2026-01-01T00:00:05Z"))
        original_now = ad.now
        ad.now = lambda: next(times)
        try:
            message = ad.send_message(self.world, "member", ["lead"], "Bitte prüfen", None, "fixed-message", "mitglied", True)
            repeated = ad.send_message(self.world, "member", ["lead"], "Bitte prüfen", None, "fixed-message", "mitglied", True)
        finally:
            ad.now = original_now
        self.assertEqual(message, repeated)
        chat = ad.derived_id("chat", "lead", "member")
        self.assertEqual(len(ad.read_messages(self.world, direct_chat=chat)), 1)
        delivery = self.world / "agents" / "lead" / "postfach" / "fixed-message.json"
        ack = ad.acknowledge(self.world, "lead", "fixed-message", "lead", "teamleiter")
        self.assertTrue(ack["acknowledged"])
        self.assertTrue(json.loads(delivery.read_text())["acknowledged"])
        self.assertEqual(ad.acknowledge(self.world, "lead", "fixed-message", "lead", "teamleiter")["acknowledged"], True)
        with self.assertRaises(ad.AgentsError):
            ad.send_message(self.world, "member", ["lead"], "anderer", None, "../escape", "mitglied", True)
        self.assertFalse((self.world / "direktchats" / "escape.json").exists())

    def test_channel_multiple_recipients_do_not_broadcast(self):
        self.add_team()
        ad.send_message(self.world, "main", ["lead", "member"], "Gezielte Nachricht", None, "m-targeted", "hauptagent")
        self.assertEqual(len(ad.read_messages(self.world, recipient="lead")), 1)
        self.assertEqual(len(ad.read_messages(self.world, recipient="member")), 1)
        self.assertEqual(ad.read_messages(self.world, recipient="main")[0]["recipients"], ["lead", "member"])
        self.assertFalse((self.world / "agents" / "main" / "postfach" / "m-targeted.json").exists())
        (self.world / "agents" / "member" / "postfach" / "m-targeted.json").unlink()
        repeated = ad.send_message(self.world, "main", ["lead", "member"], "Gezielte Nachricht",
                                    None, "m-targeted", "hauptagent")
        self.assertEqual(repeated["id"], "m-targeted")
        self.assertTrue((self.world / "agents" / "member" / "postfach" / "m-targeted.json").exists())

    def test_role_and_approval_boundaries(self):
        self.add_team()
        with self.assertRaises(ad.AgentsError):
            ad.create_agent(self.world, "other", "mitglied", "other", "No", None, None, None, None, None, None, "lokal", "lead", "teamleiter")
        ticket = ad.create_ticket(self.world, "T", "G", "D", ["member"], "main", "hauptagent", team="dev")
        ad.claim_ticket(self.world, ticket["id"], "member", "member", "mitglied")
        ad.write_result(self.world, ticket["id"], "member", "done", None, "member", "mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.approve_ticket(self.world, ticket["id"], "member", "mitglied", None)

    def test_pause_and_stop_are_data_states(self):
        self.add_team()
        ticket = ad.create_ticket(self.world, "T", "G", "D", ["member"], "main", "hauptagent", team="dev")
        ad.set_agent_state(self.world, "member", "pausiert", "Pause", "main", "hauptagent")
        with self.assertRaises(ad.AgentsError):
            ad.claim_ticket(self.world, ticket["id"], "member", "member", "mitglied")
        ad.set_agent_state(self.world, "member", "aktiv", None, "main", "hauptagent")
        ad.claim_ticket(self.world, ticket["id"], "member", "member", "mitglied")
        ad.set_agent_state(self.world, "member", "gestoppt", "Abbruch", "main", "hauptagent")
        self.assertEqual(ad.read_ticket(self.world, ticket["id"])["state"], "unterbrochen")
        with self.assertRaises(ad.AgentsError):
            ad.write_result(self.world, ticket["id"], "member", "zu spaet", None, "member", "mitglied")

    def test_agent_profile_recovers_runtime_projection(self):
        self.add_team()
        profile_path = self.world / "agents" / "member" / "agent.json"
        profile = json.loads(profile_path.read_text())
        profile["state"] = "pausiert"
        profile["updated_at"] = "crash-authoritative"
        profile_path.write_text(json.dumps(profile), encoding="utf-8")
        ad.send_message(self.world, "main", ["member"], "Recovery", None, "m-recovery", "hauptagent")
        runtime = json.loads((self.world / "agents" / "member" / "runtime.json").read_text())
        self.assertEqual(runtime["state"], "pausiert")
        self.assertEqual(runtime["updated_at"], "crash-authoritative")

    def test_recovery_repairs_missing_projection_and_result_to_external_sender(self):
        self.add_team()
        ticket = ad.create_ticket(self.world, "T", "G", "D", ["member"], "cli-operator", None)
        delivery_id = ad.derived_id("ticket", ticket["id"])
        postbox = self.world / "agents" / "member" / "postfach" / (delivery_id + ".json")
        postbox.unlink()
        ad.claim_ticket(self.world, ticket["id"], "member", "member", "mitglied")
        self.assertTrue(postbox.exists())  # next transaction recovered it
        ad.write_result(self.world, ticket["id"], "member", "done", None, "member", "mitglied")
        stored_ticket = ad.read_ticket(self.world, ticket["id"])
        result = stored_ticket["result"]
        result_message_id = stored_ticket["result_message_id"]
        (self.world / "agents" / "main" / "postfach" / (result_message_id + ".json")).unlink(missing_ok=True)
        # External sender has no implicit agent postbox; recovery remains successful.
        ad.set_world_state(self.world, "pausiert", "test", "main", "hauptagent")
        self.assertEqual(ad.read_ticket(self.world, ticket["id"])["result"], result)

    def test_rejection_has_stable_return_and_result_revisions(self):
        self.add_team()
        ticket = ad.create_ticket(self.world, "T", "G", "D", ["member"], "main", "hauptagent", team="dev")
        ad.claim_ticket(self.world, ticket["id"], "member", "member", "mitglied")
        first = ad.write_result(self.world, ticket["id"], "member", "first", "abc", "member", "mitglied")
        self.assertEqual(ad.write_result(self.world, ticket["id"], "member", "first", "abc", "member", "mitglied"), first)
        returned = ad.approve_ticket(self.world, ticket["id"], "lead", "teamleiter", "Nacharbeit", False)
        return_id = returned["return_delivery_id"]
        self.assertTrue((self.world / "agents" / "member" / "postfach" / (return_id + ".json")).exists())
        ad.claim_ticket(self.world, ticket["id"], "member", "member", "mitglied")
        second = ad.write_result(self.world, ticket["id"], "member", "second", "def", "member", "mitglied")
        self.assertNotEqual(first["result_message_id"], second["result_message_id"])
        self.assertEqual(ad.write_result(self.world, ticket["id"], "member", "second", "def", "member", "mitglied"), second)
        self.assertEqual(len([m for m in ad.read_messages(self.world) if m["kind"] == "ticket-ergebnis"]), 2)

    def test_long_ids_keep_derived_paths_within_limit(self):
        lead_id = "lead-" + "l" * 50
        member_id = "member-" + "m" * 48
        ticket_id = "ticket-" + "t" * 50
        ad.create_agent(self.world, lead_id, "teamleiter", "dev", "Leitet Entwicklung",
                        None, None, None, None, None, None, "lokal", "main", "hauptagent")
        ad.create_agent(self.world, member_id, "mitglied", "dev", "Baut Dateien",
                        None, None, None, None, None, None, "lokal", "main", "hauptagent")
        direct = ad.send_message(self.world, member_id, [lead_id], "Direkt", None,
                                 "long-direct", "mitglied", True)
        self.assertEqual(direct["id"], "long-direct")
        chat_dirs = [path for path in (self.world / "direktchats").iterdir() if path.is_dir()]
        self.assertEqual(len(chat_dirs), 1)
        self.assertLessEqual(len(chat_dirs[0].name), 64)
        ticket = ad.create_ticket(self.world, "Lang", "G", "D", [member_id], "main", "hauptagent",
                                  team="dev", ticket_id=ticket_id)
        ticket_deliveries = [path for path in (self.world / "agents" / member_id / "postfach").glob("ticket-*.json")]
        self.assertTrue(ticket_deliveries)
        self.assertTrue(all(len(path.name[:-5]) <= 64 for path in ticket_deliveries))
        ad.claim_ticket(self.world, ticket_id, member_id, member_id, "mitglied")
        first = ad.write_result(self.world, ticket_id, member_id, "first", "a", member_id, "mitglied")
        self.assertLessEqual(len(first["result_message_id"]), 64)
        returned = ad.approve_ticket(self.world, ticket_id, lead_id, "teamleiter", "Nacharbeit", False)
        self.assertLessEqual(len(returned["return_delivery_id"]), 64)
        repeated_return = ad.approve_ticket(self.world, ticket_id, lead_id, "teamleiter", "Nacharbeit", False)
        self.assertEqual(repeated_return["return_delivery_id"], returned["return_delivery_id"])
        ad.claim_ticket(self.world, ticket_id, member_id, member_id, "mitglied")
        second = ad.write_result(self.world, ticket_id, member_id, "second", "b", member_id, "mitglied")
        self.assertLessEqual(len(second["result_message_id"]), 64)
        self.assertNotEqual(first["result_message_id"], second["result_message_id"])
        self.assertEqual(ad.approve_ticket(self.world, ticket_id, lead_id, "teamleiter", None)["state"], "abgenommen")

    def test_derived_ids_are_structurally_unambiguous(self):
        self.assertNotEqual(ad.derived_id("chat", "a-b", "c"),
                            ad.derived_id("chat", "a", "b-c"))
        self.assertNotEqual(ad.derived_id("result", "x-2"),
                            ad.derived_id("result", "x", 2))

    def test_unterminated_channel_tail_is_repaired(self):
        self.add_team()
        ad.send_message(self.world, "main", ["lead"], "one", None, "m-one", "hauptagent")
        with (self.world / "kanal.jsonl").open("ab") as stream:
            stream.write(b"{\"crash\":")
        ad.send_message(self.world, "main", ["lead"], "two", None, "m-two", "hauptagent")
        messages = ad.read_messages(self.world)
        self.assertEqual([item["id"] for item in messages], ["m-one", "m-two"])

    def test_symlink_components_are_rejected(self):
        outside = Path(self.tmp.name) / "outside"
        outside.mkdir()
        os.symlink(outside, self.world / "agents" / "evil")
        with self.assertRaises(ad.AgentsError):
            ad.read_agent(self.world, "evil")
        with self.assertRaises(ad.AgentsError):
            ad.list_agents(self.world)
        world_alias = Path(self.tmp.name) / "world-alias"
        os.symlink(self.world, world_alias)
        with self.assertRaises(ad.AgentsError):
            ad.read_agent(world_alias, "main")
        with self.assertRaises(ad.AgentsError):
            ad.list_agents(world_alias)
        with self.assertRaises(ad.AgentsError):
            ad.list_tickets(world_alias)
        with self.assertRaises(ad.AgentsError):
            ad.read_ticket(world_alias, "missing")
        with self.assertRaises(ad.AgentsError):
            ad.read_messages(world_alias)
        postbox = self.world / "agents" / "main" / "postfach"
        shutil_target = outside / "postfach"
        shutil_target.mkdir()
        (shutil_target / "existing.json").write_text("{}", encoding="utf-8")
        postbox.rmdir()
        os.symlink(shutil_target, postbox)
        with self.assertRaises(ad.AgentsError):
            ad.acknowledge(self.world, "main", "existing", "main", "hauptagent")
        (self.world / ".agents.lock").unlink(missing_ok=True)
        os.symlink(outside / "lock", self.world / ".agents.lock")
        with self.assertRaises(ad.AgentsError):
            ad.set_world_state(self.world, "pausiert", "x", "main", "hauptagent")

    def test_failed_initial_write_leaves_no_partial_agent_or_ticket(self):
        original = ad._write_json
        calls = {"n": 0}

        def fail_once(path, data):
            calls["n"] += 1
            if calls["n"] == 1:
                raise OSError("simulated crash")
            return original(path, data)

        ad._write_json = fail_once
        try:
            with self.assertRaises(OSError):
                ad.create_agent(self.world, "broken", "mitglied", None, "x", None, None, None, None, None, None, "lokal", "main", "hauptagent")
        finally:
            ad._write_json = original
        self.assertFalse((self.world / "agents" / "broken").exists())
        calls["n"] = 0
        ad._write_json = fail_once
        try:
            with self.assertRaises(OSError):
                ad.create_ticket(self.world, "broken", "x", "y", ["main"], "main", "hauptagent")
        finally:
            ad._write_json = original
        self.assertEqual(list(self.world.glob("tickets/*/ticket.json")), [])
        calls["n"] = 0
        ad._write_json = fail_once
        try:
            with self.assertRaises(OSError):
                ad.ask_question(self.world, "broken", question_id="broken-question",
                                sender="main", claimed_role="hauptagent")
        finally:
            ad._write_json = original
        self.assertFalse((self.world / "questions" / "broken-question").exists())

    def test_ticket_idempotency_includes_limits(self):
        first = ad.create_ticket(self.world, "T", "G", "D", ["main"], "main", "hauptagent",
                                 limits={"tokens": 10}, ticket_id="limited")
        self.assertEqual(ad.create_ticket(self.world, "T", "G", "D", ["main"], "main", "hauptagent",
                                          limits={"tokens": 10}, ticket_id="limited"), first)
        with self.assertRaises(ad.AgentsError):
            ad.create_ticket(self.world, "T", "G", "D", ["main"], "main", "hauptagent",
                             limits={"tokens": 20}, ticket_id="limited")

    def test_concurrent_claim_has_one_winner(self):
        self.add_team()
        ad.create_agent(self.world, "member2", "mitglied", "dev", "Zweite Arbeit",
                        None, None, None, None, None, None, "lokal", "main", "hauptagent")
        ticket = ad.create_ticket(self.world, "Race", "G", "D", ["member", "member2"], "main", "hauptagent")
        context = multiprocessing.get_context("spawn")
        barrier = context.Barrier(2)
        queue = context.Queue()
        workers = [context.Process(target=_claim_race, args=(str(self.world), ticket["id"], agent, barrier, queue))
                   for agent in ("member", "member2")]
        for worker in workers:
            worker.start()
        outcomes = [queue.get(timeout=10) for _ in workers]
        for worker in workers:
            worker.join(timeout=10)
        self.assertEqual(sum(outcome[1] == "ok" for outcome in outcomes), 1, outcomes)
        self.assertEqual(ad.read_ticket(self.world, ticket["id"])["assignee"], next(outcome[0] for outcome in outcomes if outcome[1] == "ok"))

    def test_dependencies_and_concurrent_claims_same_agent(self):
        self.add_team()
        dependency = ad.create_ticket(self.world, "Dependency", "G", "D", ["member"], "main", "hauptagent")
        blocked = ad.create_ticket(self.world, "Blocked", "G", "D", ["member"], "main", "hauptagent",
                                   dependencies=[dependency["id"]])
        with self.assertRaises(ad.AgentsError):
            ad.claim_ticket(self.world, blocked["id"], "member", "member", "mitglied")
        ad.claim_ticket(self.world, dependency["id"], "member", "member", "mitglied")
        ad.write_result(self.world, dependency["id"], "member", "done", None, "member", "mitglied")
        ad.approve_ticket(self.world, dependency["id"], "main", "hauptagent", None)
        ad.claim_ticket(self.world, blocked["id"], "member", "member", "mitglied")
        ad.write_result(self.world, blocked["id"], "member", "done", None, "member", "mitglied")
        ad.approve_ticket(self.world, blocked["id"], "main", "hauptagent", None)

        left = ad.create_ticket(self.world, "Left", "G", "D", ["member"], "main", "hauptagent")
        right = ad.create_ticket(self.world, "Right", "G", "D", ["member"], "main", "hauptagent")
        context = multiprocessing.get_context("spawn")
        barrier = context.Barrier(2)
        queue = context.Queue()
        workers = [context.Process(target=_same_agent_claim_race, args=(str(self.world), ticket_id, barrier, queue))
                   for ticket_id in (left["id"], right["id"])]
        for worker in workers:
            worker.start()
        outcomes = [queue.get(timeout=10) for _ in workers]
        for worker in workers:
            worker.join(timeout=10)
        self.assertEqual(sum(outcome[1] == "ok" for outcome in outcomes), 1, outcomes)

    def test_concurrent_world_creation_has_one_complete_world(self):
        target = Path(self.tmp.name) / "race-world"
        context = multiprocessing.get_context("spawn")
        queue = context.Queue()
        workers = [context.Process(target=_world_race, args=(str(target), queue)) for _ in range(2)]
        for worker in workers:
            worker.start()
        outcomes = [queue.get(timeout=10) for _ in workers]
        for worker in workers:
            worker.join(timeout=10)
        self.assertEqual(sum(outcome[0] == "ok" for outcome in outcomes), 1)
        self.assertEqual(len(ad.list_agents(target)), 1)
        self.assertTrue((target / "agents" / "main" / "MEMORY.md").is_file())

    def test_world_ids_are_independent_of_display_names(self):
        first = ad.create_world(Path(self.tmp.name) / "first-world", name="Same name")
        second = ad.create_world(Path(self.tmp.name) / "second-world", name="Same name")
        self.assertNotEqual(first["world"]["id"], second["world"]["id"])
        self.assertEqual(first["world"]["name"], second["world"]["name"])
        self.assertEqual(ad.read_world(Path(self.tmp.name) / "first-world")["id"], first["world"]["id"])

    def test_cli_wrappers_and_legacy_agent_script(self):
        env = dict(os.environ, PYTHONPATH=str(SHELL))
        result = subprocess.run([str(SHELL / "wb-welt"), "zeigen", str(self.world), "--json"],
                                text=True, capture_output=True, env=env, check=True)
        self.assertTrue(ad.valid_id(json.loads(result.stdout)["id"]))
        self.assertEqual(subprocess.run([str(SHELL / "wb-agent"), "liste", str(self.world), "--json"],
                                        text=True, capture_output=True, env=env, check=True).returncode, 0)

    def test_cli_full_lifecycle(self):
        env = dict(os.environ, PYTHONPATH=str(SHELL))

        def call(tool, *args):
            return json.loads(subprocess.run([str(SHELL / tool), *map(str, args), "--json"],
                                             text=True, capture_output=True, env=env, check=True).stdout)

        cli_world = Path(self.tmp.name) / "cli-world"
        call("wb-welt", "neu", cli_world, "--name", "CLI", "--absender", "cli-operator")
        call("wb-agent", "neu", cli_world, "--name", "member", "--stufe", "mitglied",
             "--beschreibung", "Baut Dateien", "--absender", "cli-operator")
        ticket = call("wb-ticket", "neu", cli_world, "--id", "stable-ticket", "--titel", "T",
                      "--ziel", "G", "--fertig", "D", "--an", "member", "--absender", "hauptagent")
        call("wb-ticket", "uebernehmen", cli_world, ticket["id"], "--agent", "member", "--absender", "member")
        call("wb-ticket", "ergebnis", cli_world, ticket["id"], "--agent", "member", "--text", "done", "--absender", "member")
        controller = ac.AgentController(cli_world, "run-cli-lifecycle", lambda _binding: True)
        client = controller.bind_agent("hauptagent", "hauptagent")
        try:
            client.request("ticket.approve", {"ticket_id": ticket["id"], "reason_code": "erledigt"})
        finally:
            client.close()
            controller.close()
            controller.join()
        message = call("wb-kanal", "senden", cli_world, "--an", "member", "--text", "Arbeite", "--id", "cli-message")
        self.assertEqual(message["id"], "cli-message")
        delivery = cli_world / "agents" / "member" / "postfach" / "cli-message.json"
        call("wb-kanal", "quittieren", cli_world, "--agent", "member", "--zustellung", "cli-message", "--absender", "member")
        self.assertTrue(json.loads(delivery.read_text())["acknowledged"])

    def test_persistent_questions_are_independent_role_bound_and_idempotent(self):
        self.add_team()

        def call(*args):
            result = _run_cli("welt", *args, "--json")
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads(result.stdout)

        with self.assertRaises(ad.AgentsError):
            ad.ask_question(self.world, "Verboten", question_id="q-member",
                            sender="member", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.ask_question(self.world, "Verboten", question_id="q-lead",
                            sender="lead", claimed_role="teamleiter")

        ticket = ad.create_ticket(self.world, "Fragenbezug", "G", "D", ["main"],
                                  "main", "hauptagent", ticket_id="question-ticket")
        first = ad.ask_question(self.world, "Erste Frage", ["A", "B"], "A",
                                ticket_id=ticket["id"], question_id="q-first",
                                sender="main", claimed_role="hauptagent")
        second = call("frage", self.world, "--id", "q-second", "--text", "Zweite Frage",
                      "--option", "Ja", "--option", "Nein", "--empfehlung", "Nein",
                      "--absender", "main", "--rolle", "hauptagent")
        self.assertEqual(first["state"], "offen")
        self.assertEqual(first["ticket"], "question-ticket")
        self.assertEqual(second["state"], "offen")
        self.assertEqual(call("frage", self.world, "--id", "q-first", "--text", "Erste Frage",
                              "--option", "A", "--option", "B", "--empfehlung", "A",
                              "--ticket", "question-ticket",
                              "--absender", "main", "--rolle", "hauptagent")["id"], "q-first")
        ad.set_world_state(self.world, "pausiert", "Warte auf Antwort", "main", "hauptagent")
        self.assertEqual(call("frage", self.world, "--id", "q-first", "--text", "Erste Frage",
                              "--option", "A", "--option", "B", "--empfehlung", "A",
                              "--ticket", "question-ticket",
                              "--absender", "main", "--rolle", "hauptagent")["id"], "q-first")
        ad.set_world_state(self.world, "läuft", None, "main", "hauptagent")
        with self.assertRaises(ad.AgentsError):
            ad.ask_question(self.world, "Andere Frage", ["A", "B"], "A",
                            question_id="q-first", sender="main", claimed_role="hauptagent")

        with self.assertRaises(ad.AgentsError):
            ad.answer_question(self.world, "q-second", "Freie Antwort mit Begründung",
                               "main", "hauptagent")
        answered = call("antwort", self.world, "q-second", "--text", "Freie Antwort mit Begründung")
        self.assertEqual(answered["state"], "beantwortet")
        self.assertFalse(answered["answer"]["verified"])
        self.assertEqual(call("antwort", self.world, "q-second", "--text",
                              "Freie Antwort mit Begründung")["answer"], answered["answer"])
        with self.assertRaises(ad.AgentsError):
            ad.answer_question(self.world, "q-second", "Andere Antwort", "cli-operator")

        listed = call("fragen", self.world)
        states = {question["id"]: question["state"] for question in listed}
        self.assertEqual(states, {"q-first": "offen", "q-second": "beantwortet"})
        with self.assertRaises(ad.AgentsError):
            ad.withdraw_question(self.world, "q-first", "Nicht mehr nötig", "main", "hauptagent")
        withdrawn = call("ruecknahme", self.world, "q-first", "--grund", "Nicht mehr nötig")
        self.assertEqual(withdrawn["state"], "zurückgenommen")
        self.assertEqual(call("ruecknahme", self.world, "q-first", "--grund", "Nicht mehr nötig"), withdrawn)
        with self.assertRaises(ad.AgentsError):
            ad.withdraw_question(self.world, "q-first", "Anderer Grund", "cli-operator")

        questions_dir = self.world / "questions"
        before = sorted(path.name for path in questions_dir.iterdir())
        with self.assertRaises(ad.AgentsError):
            ad.ask_question(self.world, "Traversal", question_id="../escape",
                            sender="main", claimed_role="hauptagent")
        self.assertEqual(sorted(path.name for path in questions_dir.iterdir()), before)
        outside = Path(self.tmp.name) / "outside-questions"
        outside.mkdir()
        os.symlink(outside, questions_dir / "link")
        with self.assertRaises(ad.AgentsError):
            ad.list_questions(self.world)
        with self.assertRaises(ad.AgentsError):
            ad.ask_question(self.world, "Symlink", question_id="link",
                            sender="main", claimed_role="hauptagent")


class HumanWritePathTests(unittest.TestCase):
    """Auftrag agentsui Nr. 2: the human of a world, ticket return, profile, memory, read state."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-mensch-")
        self.world = Path(self.tmp.name) / "world"
        ad.create_world(self.world, name="Probe", main_name="main", sender="mensch")
        ad.create_agent(self.world, "lead", "teamleiter", "dev", "Leitet", None, None, "sonnet5:high",
                        None, None, None, "host2", "mensch", None)
        ad.create_agent(self.world, "member", "mitglied", "dev", "Baut", None, None, None, None, None,
                        None, "lokal", "mensch", None)

    def tearDown(self):
        self.tmp.cleanup()

    def human_box(self):
        folder = self.world / "menschen" / "mensch" / "postfach"
        return sorted(folder.glob("*.json")) if folder.exists() else []

    def test_agent_writes_to_the_human_in_channel_and_direct_chat(self):
        channel = ad.send_marked_message(self.world, "main", ["mensch"], "Ist das so recht?", "frage",
                                         message_id="m-frage", claimed_role="hauptagent")
        self.assertEqual((channel["recipient"], channel["recipients"], channel["humans"], channel["mark"]),
                         ("mensch", [], ["mensch"], "frage"))
        direct = ad.send_message(self.world, "member", ["mensch"], "Kurzer Bericht", None, "m-direkt",
                                 "mitglied", direct=True)
        self.assertEqual((direct["recipients"], direct["humans"]), ([], ["mensch"]))
        mixed = ad.send_marked_message(self.world, "member", ["lead", "mensch"], "Fertig", "ergebnis",
                                       message_id="m-mix", claimed_role="mitglied")
        self.assertEqual((mixed["recipients"], mixed["humans"]), (["lead"], ["mensch"]))
        # The human's postbox holds all three; no agent directory named "mensch" appears.
        self.assertEqual([path.stem for path in self.human_box()], ["m-direkt", "m-frage", "m-mix"])
        self.assertFalse((self.world / "agents" / "mensch").exists())
        self.assertTrue((self.world / "agents" / "lead" / "postfach" / "m-mix.json").exists())
        # The direct chat with the human is the same chat the human writes into.
        ad.send_message(self.world, "mensch", ["member"], "Danke", None, "m-antwort", None, direct=True)
        chats = [c for c in (self.world / "direktchats").iterdir()]
        self.assertEqual(len(chats), 1)
        self.assertEqual([m["id"] for m in ad.read_messages(self.world, "mensch")], ["m-frage", "m-mix"])
        # Idempotent retry, conflicting retry, recovery after a lost projection.
        ad.send_marked_message(self.world, "main", ["mensch"], "Ist das so recht?", "frage",
                               message_id="m-frage", claimed_role="hauptagent")
        with self.assertRaises(ad.AgentsError):
            ad.send_marked_message(self.world, "main", ["mensch"], "Anders", "frage",
                                   message_id="m-frage", claimed_role="hauptagent")
        (self.world / "menschen" / "mensch" / "postfach" / "m-frage.json").unlink()
        (self.world / "menschen" / "mensch" / "postfach" / "m-direkt.json").unlink()
        ad.send_message(self.world, "main", ["lead"], "anstossen", None, None, "hauptagent")
        self.assertEqual([path.stem for path in self.human_box()], ["m-direkt", "m-frage", "m-mix"])
        # Acknowledged like an agent delivery, but only by a human.
        with self.assertRaises(ad.AgentsError):
            ad.acknowledge(self.world, "mensch", "m-frage", "main", "hauptagent")
        acked = ad.acknowledge(self.world, "mensch", "m-frage", None, None)
        self.assertTrue(acked["acknowledged"])
        snap = ad.world_snapshot(self.world)
        self.assertEqual((snap["humans"]["mensch"]["postbox"]["open"], snap["humans"]["mensch"]["postbox"]["total"]), (2, 3))
        chat = snap["direct_chats"][0]
        self.assertEqual(chat["participants"], ["member", "mensch"])

    def test_rules_for_messages_to_the_human(self):
        with self.assertRaises(ad.AgentsError):
            ad.send_marked_message(self.world, "member", ["mensch"], "Frage?", "frage", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.send_marked_message(self.world, "main", ["lead"], "ohne Mensch", "ergebnis", claimed_role="hauptagent")
        cli_message = ad.send_message(self.world, "cli-operator", ["mensch"], "CLI-Bericht",
                                      None, "m-cli", None)
        self.assertEqual((cli_message["sender"], cli_message["humans"]),
                         ("cli-operator", ["mensch"]))
        with self.assertRaises(ad.AgentsError):
            ad.send_marked_message(self.world, "main", ["mensch"], "x", "wichtig", claimed_role="hauptagent")
        with self.assertRaises(ad.AgentsError):
            ad.create_agent(self.world, "mensch", "mitglied", "dev", "Tarnung", None, None, None, None, None,
                            None, "lokal", "main", "hauptagent")
        self.assertEqual([path.stem for path in self.human_box()], ["m-cli"])
        out = subprocess.run([str(SHELL / "wb-kanal"), "senden", str(self.world), "--absender", "main", "--rolle",
                              "hauptagent", "--an", "mensch", "--text", "Ergebnis steht", "--markierung", "ergebnis",
                              "--json"], capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(out.stdout)["mark"], "ergebnis")

    def approved_ticket(self):
        ad.create_ticket(self.world, "Bauen", "Ziel", "Fertig", ["member"], "main", "hauptagent",
                         team="dev", ticket_id="t-bau")
        ad.claim_ticket(self.world, "t-bau", "member", "member", "mitglied")
        ad.write_result(self.world, "t-bau", "member", "erledigt", "abc123", "member", "mitglied")
        ad.approve_ticket(self.world, "t-bau", "lead", "teamleiter", "passt", True)

    def test_human_returns_an_approved_ticket_to_its_assignee(self):
        self.approved_ticket()
        with self.assertRaises(ad.AgentsError):
            ad.return_ticket(self.world, "t-bau", "   ")
        with self.assertRaises(ad.AgentsError):
            ad.return_ticket(self.world, "t-bau", "Agent darf nicht", "lead", "teamleiter")
        ticket = ad.return_ticket(self.world, "t-bau", "Feiertage fehlen", "mensch")
        self.assertEqual(ticket["state"], "zurückgegeben")
        self.assertEqual((ticket["approval"]["note"], ticket["approval"]["kind"], ticket["approval"]["verified"]),
                         ("Feiertage fehlen", "rueckgabe-mensch", False))
        self.assertEqual(ticket["previous_approval"]["agent"], "lead")
        delivery = ticket["return_delivery_id"]
        self.assertTrue((self.world / "agents" / "member" / "postfach" / (delivery + ".json")).exists())
        self.assertFalse((self.world / "agents" / "lead" / "postfach" / (delivery + ".json")).exists(),
                         "the team lead is not woken for the human's return")
        self.assertEqual(ad.return_ticket(self.world, "t-bau", "Feiertage fehlen", "mensch")["return_revision"], 1)
        with self.assertRaises(ad.AgentsError):
            ad.return_ticket(self.world, "t-bau", "andere Bemerkung", "mensch")
        events = [json.loads(line)["event"] for line in (self.world / "tickets" / "t-bau" / "verlauf.jsonl").read_text().splitlines()]
        self.assertEqual(events[-1], "zurueckgegeben")
        # Rework: the assignee takes it again, the approver takes it off again.
        self.assertEqual(ad.claim_ticket(self.world, "t-bau", "member", "member", "mitglied")["state"], "läuft")
        with self.assertRaises(ad.AgentsError):
            ad.return_ticket(self.world, "t-bau", "zu frueh", "mensch")

    def test_cli_return_routes_by_state_and_sender(self):
        self.approved_ticket()
        out = _run_cli("ticket", "zurueckgeben", self.world, "t-bau", "--absender", "mensch",
                       "--bemerkung=-h fehlt", "--json")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(json.loads(out.stdout)["approval"]["note"], "-h fehlt")
        bad = _run_cli("ticket", "zurueckgeben", self.world, "t-bau", "--absender", "lead",
                       "--rolle", "teamleiter", "--json")
        self.assertEqual(bad.returncode, 0, "an agent's return of a returned ticket still runs the old approval path")

    def test_profile_update(self):
        with self.assertRaises(ad.AgentsError):
            ad.update_agent_profile(self.world, "lead", {"model": "opus5:xhigh"}, "main", "hauptagent")
        with self.assertRaises(ad.AgentsError):
            ad.update_agent_profile(self.world, "lead", {"tools": ["Bash"]}, "mensch")
        with self.assertRaises(ad.AgentsError):
            ad.update_agent_profile(self.world, "lead", {"model": "fable-5:high"}, "mensch")
        with self.assertRaises(ad.AgentsError):
            ad.update_agent_profile(self.world, "lead", {"effort": "max"}, "mensch")
        state_before = json.loads((self.world / "agents" / "lead" / "runtime.json").read_text())
        agent = ad.update_agent_profile(self.world, "lead", {"model": "codex-gpt-5-6-terra:medium", "fallback_model": "lmgamma-27b:high",
                                                            "machine": "ltfserver", "specialty": "Leitet die Entwicklung"}, "mensch")
        profile = agent["model_profile"]
        self.assertEqual((profile["model"], profile["effort"], profile["fallback_model"], profile["fallback_effort"]),
                         ("codex-gpt-5-6-terra:medium", "medium", "lmgamma-27b:high", "high"))
        self.assertEqual((agent["machine"], agent["specialty"]), ("ltfserver", "Leitet die Entwicklung"))
        history = json.loads((self.world / "agents" / "lead" / "history.json").read_text())["entries"]
        self.assertEqual(history[-1]["event"], "profil")
        self.assertEqual(history[-1]["changes"]["model"], ["sonnet5:high", "codex-gpt-5-6-terra:medium"])
        self.assertIn("nächsten Start", history[-1]["note"])
        ad.update_agent_profile(self.world, "lead", {"effort": "xhigh"}, "mensch")
        self.assertEqual(ad.read_agent(self.world, "lead")["model_profile"]["effort"], "xhigh")
        unchanged = ad.update_agent_profile(self.world, "lead", {"machine": "ltfserver"}, "mensch")
        self.assertEqual(len(json.loads((self.world / "agents" / "lead" / "history.json").read_text())["entries"]), 2,
                         "no change, no history entry")
        self.assertEqual(unchanged["machine"], "ltfserver")
        ad.send_message(self.world, "main", ["lead"], "anstossen", None, None, "hauptagent")
        self.assertEqual(json.loads((self.world / "agents" / "lead" / "runtime.json").read_text()), state_before,
                         "a profile change is not a state change")
        out = _run_cli("agent", "profil", self.world, "member", "--fallback", "", "--beschreibung",
                       "Baut Parser", "--json")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(json.loads(out.stdout)["specialty"], "Baut Parser")

    def test_memory_write(self):
        path = self.world / "agents" / "member" / "MEMORY.md"
        loaded = ad.world_snapshot(self.world)
        sha = next(a for a in loaded["agents"] if a["id"] == "member")["memory"]["sha256"]
        with self.assertRaises(ad.AgentsError):
            ad.write_memory(self.world, "member", "# neu", sha, "member", "mitglied")
        result = ad.write_memory(self.world, "member", "# member\n\n- Parser bleibt streng.\n", sha, "mensch")
        self.assertTrue(result["changed"])
        self.assertEqual(path.read_text(), "# member\n\n- Parser bleibt streng.\n")
        with self.assertRaises(ad.AgentsError):
            ad.write_memory(self.world, "member", "# ueberschreibt", sha, "mensch")
        self.assertFalse(ad.write_memory(self.world, "member", "# member\n\n- Parser bleibt streng.\n", result["sha256"], "mensch")["changed"])
        entry = json.loads((self.world / "agents" / "member" / "history.json").read_text())["entries"][-1]
        self.assertEqual((entry["event"], entry["note"]), ("gedaechtnis", "vom Menschen bearbeitet"))
        self.assertEqual([p.name for p in path.parent.iterdir() if p.name.startswith(".MEMORY")], [])
        source = Path(self.tmp.name) / "memory.md"
        source.write_text("# aus Datei\n", encoding="utf-8")
        out = _run_cli("agent", "gedaechtnis", self.world, "member", "--datei", source,
                       "--erwartet", result["sha256"], "--json")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(path.read_text(), "# aus Datei\n")

    def test_shared_read_state_moves_forward_only(self):
        with self.assertRaises(ad.AgentsError):
            ad.mark_read(self.world, "irgendwas", "2026-09-14T10:00:00Z", "m-1")
        with self.assertRaises(ad.AgentsError):
            ad.mark_read(self.world, "kanal", "2026-09-14T10:00:00Z", "m-1", sender="main", claimed_role="hauptagent")
        ad.mark_read(self.world, "kanal", "2026-09-14T10:00:05Z", "m-2", sender="mensch")
        state = ad.mark_read(self.world, "kanal", "2026-09-14T10:00:01Z", "m-1", sender="mensch")
        self.assertEqual(state["conversations"]["kanal"]["id"], "m-2", "an older mark does not move back")
        ad.mark_read(self.world, "einzel:member", "2026-09-14T10:00:07Z", "m-9")
        stored = json.loads((self.world / "menschen" / "mensch" / "gelesen.json").read_text())
        self.assertEqual(sorted(stored["conversations"]), ["einzel:member", "kanal"])
        self.assertEqual(ad.world_snapshot(self.world)["humans"]["mensch"]["read_state"]["einzel:member"]["id"], "m-9")
        out = _run_cli("welt", "gelesen", self.world, "--gespraech", "direkt:chat-1",
                       "--zeit", "2026-09-14T10:01:00Z", "--nachricht", "m-3", "--json")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("direkt:chat-1", json.loads(out.stdout)["conversations"])

    def test_list_questions_skips_a_question_being_created(self):
        ad.ask_question(self.world, "Echt?", question_id="frage-1", sender="main", claimed_role="hauptagent")
        (self.world / "questions" / ".frage-2.creating-abc").mkdir()
        self.assertEqual([q["id"] for q in ad.list_questions(self.world)], ["frage-1"])
        out = subprocess.run([str(SHELL / "wb-welt"), "fragen", str(self.world), "--json"], capture_output=True, text=True, check=True)
        self.assertEqual([q["id"] for q in json.loads(out.stdout)], ["frage-1"])



class AgentCreationTests(unittest.TestCase):
    """Auftrag agentsui Nr. 3: create from a full draft, team leader requests, library templates."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-anlegen-")
        self.world = Path(self.tmp.name) / "world"
        ad.create_world(self.world, name="Probe", main_name="main", sender="mensch")
        ad.create_agent(self.world, "lead", "teamleiter", "dev", "Leitet", None, None, None, None, None,
                        None, "lokal", "mensch", None)

    def tearDown(self):
        self.tmp.cleanup()

    def draft(self, **changes):
        base = {"id": "pruefer", "stage": "mitglied", "team": "dev",
                "specialty": "Liest Änderungen gegen das Ticket.  Ein Satz.",
                "model": "sonnet5:high", "fallback_model": "lmgamma:medium", "machine": "host2",
                "tools": ["Bash", "Read", "Grep"], "bash": ["git diff *", "git status"], "skills": ["debugging-protocol"],
                "context_limit": "Nur die Änderung.", "figure": {"family": "linse", "color": "pruefung"}}
        base.update(changes)
        return base

    def test_create_from_draft_writes_profile_and_instruction_file(self):
        agent = ad.create_agent_from_draft(self.world, self.draft(), "mensch")
        self.assertEqual((agent["stage"], agent["team"], agent["specialty"], agent["machine"]),
                         ("mitglied", "dev", "Liest Änderungen gegen das Ticket. Ein Satz.", "host2"))
        self.assertEqual((agent["model_profile"]["model"], agent["model_profile"]["effort"],
                          agent["model_profile"]["fallback_model"], agent["model_profile"]["fallback_effort"]),
                         ("sonnet5:high", "high", "lmgamma:medium", "medium"))
        # Own patterns first, then the missing service-path defaults (2026-09-15).
        self.assertEqual((agent["tools"], agent["bash"][:2], agent["skills"], agent["context_limit"], agent["figure"]),
                         (["Bash", "Read", "Grep"], ["git diff *", "git status"], ["debugging-protocol"],
                          "Nur die Änderung.", {"family": "linse", "color": "pruefung"}))
        self.assertEqual(agent["bash"][2:], [p for p in ad.DEFAULT_BASH if p not in ("git diff *", "git status")])
        self.assertEqual((agent["created_by"], agent["instructions_source"]),
                         ({"id": "mensch", "kind": "external", "verified": True,
                           "source": "wb-mensch"}, "vorlage"))
        text = (self.world / "agents" / "pruefer" / "AGENTS.md").read_text(encoding="utf-8")
        for part in ("# pruefer – Anweisungen", "Mitglied in Team „dev“ der Welt „Probe“", "## Rolle",
                     "Liest Änderungen gegen das Ticket.",
                     "Bash nur mit diesen Mustern: `git diff *`, `git status`, `python3 */rpc/agents_rpc_client.py *`",
                     "Was du nicht erfährst und nicht erfragst: Nur die Änderung.", "## Meldewege",
                     "gehen an lead.", "regeln/agenten.md"):
            self.assertIn(part, text)
        history = json.loads((self.world / "agents" / "pruefer" / "history.json").read_text())["entries"]
        self.assertEqual([e["event"] for e in history], ["angelegt"])
        # An own instruction file (e.g. from a model proposal) replaces the template.
        own = ad.create_agent_from_draft(self.world,
                                         self.draft(id="zweiter", instructions="# zweiter\n\nEigene Datei.\n"),
                                         "main", "hauptagent")
        self.assertEqual(own["instructions_source"], "entwurf")
        own_text = (self.world / "agents" / "zweiter" / "AGENTS.md").read_text()
        self.assertTrue(own_text.startswith("# zweiter\n\nEigene Datei.\n\n" + ad.INSTRUCTIONS_LIMITS_MARK), own_text)
        self.assertIn("- Bash nur mit diesen Mustern: `git diff *`, `git status`, `python3 */rpc/agents_rpc_client.py *`", own_text)
        # The limits block follows the profile, not an older block pasted into the text.
        stale = ad.preview_agent_draft(self.world, self.draft(id="dritter", instructions=own_text, bash=["git log *"]))["instructions"]
        self.assertEqual(stale.count(ad.INSTRUCTIONS_LIMITS_MARK), 1)
        self.assertIn("`git log *`", stale)
        # `git status` is a default pattern now; a pasted old block would list it a second time.
        self.assertEqual(stale.count("`git status`"), 1)
        # The runtime file is not rewritten by recovery afterwards.
        runtime = (self.world / "agents" / "pruefer" / "runtime.json").read_text()
        ad.send_message(self.world, "cli-operator", ["pruefer"], "Hallo", None, "m-probe", None)
        self.assertEqual((self.world / "agents" / "pruefer" / "runtime.json").read_text(), runtime)

    def test_cli_surface_can_create_the_first_main_agent_but_gains_no_governance_identity(self):
        empty = Path(self.tmp.name) / "surface-world"
        ad.create_world(empty, name="Surface", with_main_agent=False, sender="cli-operator")
        draft = self.draft(id="surface-main", stage="hauptagent", team=None)
        created = ad.create_agent_from_draft(empty, draft, "cli-operator")
        self.assertEqual((created["stage"], created["created_by"]),
                         ("hauptagent", {"id": "cli-operator", "kind": "agent",
                                          "verified": False, "source": "cli-operator-limited"}))
        denied = subprocess.run(
            [str(SHELL / "wb-agent"), "rechte", str(empty), "surface-main", "--werkzeuge", "Read",
             "--absender", "cli-operator"], text=True, capture_output=True, timeout=15)
        self.assertEqual(denied.returncode, 2, denied.stderr)
        self.assertIn("Governance-Mutation", denied.stderr)

    def test_draft_checks_positive_list_tools_house_list_and_stage(self):
        cases = [
            (self.draft(farbe="blau"), "Positivliste"),
            (self.draft(model="claude-fable-5-1:high"), "Fable"),
            (self.draft(fallback_model="fable5"), "Fable"),
            # WebFetch/WebSearch sind seit 15.09. erlaubt (Rechercheagenten); ein MCP-Werkzeug bleibt draussen.
            (self.draft(tools=["Read", "mcp__server__tool"], bash=[]), "nicht erlaubt"),
            (self.draft(bash=["git push *"]), "gesperrt"),
            (self.draft(bash=["rm -rf build"]), "gesperrt"),
            (self.draft(bash=["/usr/bin/pkill node"]), "gesperrt"),
            # Muster ohne Bash sind seit 16.09. kein Fehler mehr: Bash kommt wie beim Dienstweg dazu
            # (test-wb-agents-profilrechte.py, Entwurf des Hauptagenten).
            # `tools=["Bash"], bash=[]` is no longer an error: the default patterns come along (2026-09-15).
            (self.draft(tools=[]), "mindestens ein Werkzeug"),
            (self.draft(stage="teamleiter", team=None), "Team"),
            (self.draft(id="mensch"), "reserviert"),
            (self.draft(id="aufbau"), "reserviert"),
            (self.draft(specialty="x" * 400), "ein Satz"),
            (self.draft(figure={"family": "kern", "color": "pruefung"}), "Figurart"),
            (self.draft(figure={"family": "tier", "color": "lila"}), "Figurfarbe"),
            (self.draft(skills=["Böse Skill"]), "Skillname"),
        ]
        for draft, message in cases:
            with self.subTest(message=message, draft=draft):
                with self.assertRaisesRegex(ad.AgentsError, message):
                    ad.create_agent_from_draft(self.world, draft, "mensch")
        self.assertEqual(sorted(p.name for p in (self.world / "agents").iterdir()), ["lead", "main"])
        # A second main agent is refused; an agent never creates one.
        with self.assertRaisesRegex(ad.AgentsError, "genau einen Hauptagenten"):
            ad.create_agent_from_draft(self.world, self.draft(id="chef", stage="hauptagent", team=None), "mensch")
        with self.assertRaisesRegex(ad.AgentsError, "ueber Teamleiter"):
            ad.create_agent_from_draft(self.world, self.draft(id="chef", stage="hauptagent", team=None), "main", "hauptagent")
        # A new team is fine; the main agent creates, the team leader may not.
        created = ad.create_agent_from_draft(self.world, self.draft(id="neu", team="docs"), "main", "hauptagent")
        self.assertEqual((created["team"], created["created_by"]["kind"]), ("docs", "agent"))
        with self.assertRaisesRegex(ad.AgentsError, "beantragt"):
            ad.create_agent_from_draft(self.world, self.draft(id="heimlich"), "lead", "teamleiter")
        preview = ad.preview_agent_draft(self.world, self.draft(id="vorschau"))
        self.assertEqual((preview["instructions_source"], preview["draft"]["effort"]), ("vorlage", "high"))
        self.assertFalse((self.world / "agents" / "vorschau").exists())

    def test_team_leader_request_lands_as_open_question_at_the_main_agent(self):
        request = ad.request_agent(self.world, self.draft(team=None), "lead", "teamleiter", "antrag-1")
        self.assertEqual((request["kind"], request["to"], request["state"], request["sender"], request["options"]),
                         ("agent-antrag", "main", "offen", "lead", ["anlegen", "ablehnen"]))
        self.assertEqual(request["draft"]["team"], "dev", "without a team the leader's own team")
        self.assertFalse((self.world / "agents" / "pruefer").exists())
        box = list((self.world / "agents" / "main" / "postfach").glob("*.json"))
        self.assertEqual(len(box), 1)
        self.assertIn("antrag-1", json.loads(box[0].read_text())["text"])
        self.assertEqual(ad.request_agent(self.world, self.draft(team=None), "lead", "teamleiter", "antrag-1")["id"], "antrag-1")
        self.assertEqual(len(list((self.world / "agents" / "main" / "postfach").glob("*.json"))), 1)
        with self.assertRaisesRegex(ad.AgentsError, "anderem Inhalt"):
            ad.request_agent(self.world, self.draft(team=None, specialty="Anders."), "lead", "teamleiter", "antrag-1")
        with self.assertRaisesRegex(ad.AgentsError, "eigene Team"):
            ad.request_agent(self.world, self.draft(team="docs"), "lead", "teamleiter", "antrag-2")
        with self.assertRaisesRegex(ad.AgentsError, "nur Mitglieder"):
            ad.request_agent(self.world, self.draft(stage="teamleiter"), "lead", "teamleiter", "antrag-3")
        with self.assertRaisesRegex(ad.AgentsError, "Teamleiter"):
            ad.request_agent(self.world, self.draft(), "mensch", None, "antrag-4")
        with self.assertRaisesRegex(ad.AgentsError, "darf diese Mutation"):
            ad.request_agent(self.world, self.draft(), "main", "hauptagent", "antrag-5")
        ad.create_agent(self.world, "member", "mitglied", "dev", "Baut", None, ["Read"], None, None, None,
                        None, "lokal", "main", "hauptagent")
        with self.assertRaisesRegex(ad.AgentsError, "darf diese Mutation"):
            ad.request_agent(self.world, self.draft(), "member", "mitglied", "antrag-6")
        # Deciding: only the main agent (or an external actor); accepting creates, idempotently.
        with self.assertRaisesRegex(ad.AgentsError, "darf diese Mutation nicht"):
            ad.decide_agent_request(self.world, "antrag-1", True, None, "lead", "teamleiter")
        decided = ad.decide_agent_request(self.world, "antrag-1", True, "passt", "main", "hauptagent")
        self.assertEqual((decided["state"], decided["answer"]["text"], decided["answer"]["agent"], decided["answer"]["sender"]),
                         ("beantwortet", "anlegen", "pruefer", "main"))
        agent = ad.read_agent(self.world, "pruefer")
        self.assertEqual((agent["request"], agent["created_by"]["id"], agent["team"]), ("antrag-1", "main", "dev"))
        self.assertEqual(ad.decide_agent_request(self.world, "antrag-1", True, "passt", "main", "hauptagent")["state"], "beantwortet")
        with self.assertRaisesRegex(ad.AgentsError, "anders entschieden"):
            ad.decide_agent_request(self.world, "antrag-1", False, None, "main", "hauptagent")
        lead_box = [json.loads(p.read_text())["text"] for p in (self.world / "agents" / "lead" / "postfach").glob("*.json")]
        self.assertTrue(any("antrag-1: angelegt" in t for t in lead_box), lead_box)
        # Declining creates nothing; a normal question is no request.
        ad.request_agent(self.world, self.draft(id="zweiter", team=None), "lead", "teamleiter", "antrag-7")
        declined = ad.decide_agent_request(self.world, "antrag-7", False, "nicht jetzt", "cli-operator")
        self.assertEqual((declined["answer"]["text"], declined["answer"]["agent"]), ("ablehnen", None))
        self.assertFalse((self.world / "agents" / "zweiter").exists())
        ad.ask_question(self.world, "Ja?", question_id="frage-1", sender="main", claimed_role="hauptagent")
        with self.assertRaisesRegex(ad.AgentsError, "kein Antrag"):
            ad.decide_agent_request(self.world, "frage-1", True, None, "main", "hauptagent")
        # Retry after a crash between creation and decision: the agent carries the request id.
        ad.request_agent(self.world, self.draft(id="dritter", team=None), "lead", "teamleiter", "antrag-8")
        ad.create_agent_from_draft(self.world, ad.read_question(self.world, "antrag-8")["draft"], "main", "hauptagent", "antrag-8")
        self.assertEqual(ad.decide_agent_request(self.world, "antrag-8", True, None, "main", "hauptagent")["answer"]["agent"], "dritter")

    def test_profiles_without_tools_get_stage_defaults_that_let_a_turn_work(self):
        # agentslauf Nr. 6: an empty tool list made the profile lock refuse every step of a turn.
        main, lead = ad.read_agent(self.world, "main"), ad.read_agent(self.world, "lead")
        full = ["Bash", "Read", "Grep", "Glob", "Write", "Edit"]
        self.assertEqual((main["tools"], lead["tools"]), (full, full))
        self.assertEqual((main["bash"], lead["bash"]), (list(ad.DEFAULT_BASH), list(ad.DEFAULT_BASH)))
        member = ad.create_agent(self.world, "helfer", "mitglied", "dev", "Hilft", None, [], None, None, None, None,
                                 "lokal", "main", "hauptagent")
        # Seit 15.09. schreibt auch ein Mitglied (Entwuerfe, Lagen, Vorlagen), nicht nur Hauptagent und Teamleiter.
        self.assertEqual((member["tools"], member["bash"]), (full, list(ad.DEFAULT_BASH)))
        # Web-Werkzeuge sind je Agent waehlbar und laufen durch die Positivliste.
        web = ad.create_agent(self.world, "radar", "mitglied", "dev", "Sucht", None, ["Read", "WebFetch", "WebSearch"],
                              None, None, None, None, "lokal", "main", "hauptagent")
        self.assertEqual(web["tools"], ["Read", "WebFetch", "WebSearch", "Bash"])
        for pattern in ("python3 */rpc/agents_rpc_client.py *", "python3 */skripte/*/*.py *", "sh */skripte/*/*.sh *",
                        "*/skripte/*/*.py *", "python3 */skills/*/scripts/*.py *", "git status", "git diff *",
                        "git log *", "git show *"):
            self.assertIn(pattern, ad.DEFAULT_BASH)
        # The defaults pass the same checks as a draft, house list of blocked programs included.
        checked = ad.validate_agent_draft({"id": "probe", "specialty": "Probe", "model": "sonnet5:high",
                                           "tools": full, "bash": list(ad.DEFAULT_BASH)})
        self.assertEqual(checked["bash"], list(ad.DEFAULT_BASH))
        own = ad.create_agent(self.world, "eigen", "mitglied", "dev", "Eigene Liste", None, ["Read"], None, None, None,
                              None, "lokal", "main", "hauptagent")
        # 2026-09-15: an own list keeps its tools but always carries the service path, because the
        # first main agent created in the menu (Read/Grep/Glob/Edit/Write) could not answer on host2.
        self.assertEqual((own["tools"], own["bash"]), (["Read", "Bash"], list(ad.DEFAULT_BASH)))
        drafted = ad.create_agent_from_draft(self.world, self.draft(), "mensch")
        self.assertEqual(drafted["tools"], ["Bash", "Read", "Grep"])
        self.assertEqual(drafted["bash"][:2], ["git diff *", "git status"])
        self.assertLessEqual(set(ad.DEFAULT_BASH), set(drafted["bash"]))
        stumm = ad.validate_agent_draft({"id": "stumm", "specialty": "Liest nur.", "model": "sonnet5:high",
                                         "tools": ["Read", "Grep", "Glob", "Edit", "Write"]})
        self.assertEqual((stumm["tools"][-1], stumm["bash"]), ("Bash", list(ad.DEFAULT_BASH)))
        self.assertIn("## Verbindliche Grenzen aus dem Profil",
                      (self.world / "agents" / "pruefer" / "AGENTS.md").read_text(encoding="utf-8"))

    @unittest.skipUnless((SHELL.parent / "agents" / "bibliothek").is_dir(), "kit: the wb-agents library (agents/bibliothek) is not shipped")
    def test_library_templates_and_cli(self):
        templates = ad.list_agent_templates()
        self.assertEqual([t["name"] for t in templates],
                         ["dokumentar", "frontend-entwickler", "recherche-laeufer", "reviewer", "tester"])
        for template in templates:
            self.assertTrue(template["title"] and template["summary"])
            self.assertLessEqual(set(template["draft"]["tools"]), set(ad.AGENT_TOOLS))
            # Every template can report its result, run stored and skill scripts, read git and write its learning step.
            self.assertIn("Bash", template["draft"]["tools"])
            self.assertLessEqual(set(ad.DEFAULT_BASH), set(template["draft"]["bash"]), template["name"])
            self.assertIn("lernschritt-schreiben", template["draft"]["skills"])
            self.assertNotIn("Write", template["draft"]["tools"] if template["name"] in ("reviewer", "tester", "recherche-laeufer") else [])
        folder = Path(self.tmp.name) / "vorlagen"
        folder.mkdir()
        (folder / "boese.json").write_text(json.dumps({"name": "boese", "title": "B", "summary": "",
                                                       "draft": dict(self.draft(), bash=["kill -9 1"])}))
        with self.assertRaisesRegex(ad.AgentsError, "Vorlage boese.json: .*gesperrt"):
            ad.list_agent_templates(folder)
        env = dict(os.environ)
        cli = [sys.executable, str(SHELL / "agents_data.py"), "agent"]
        out = subprocess.run(cli + ["vorlagen", "--json"], capture_output=True, text=True, env=env)
        self.assertEqual(out.returncode, 0, out.stderr)
        tester = next(t for t in json.loads(out.stdout) if t["name"] == "tester")
        out = _run_cli("agent", "anlegen", self.world,
                       "--entwurf=" + json.dumps(dict(tester["draft"], id="tester-1")),
                       "--absender", "mensch", "--json")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(json.loads(out.stdout)["template"], "tester")
        out = _run_cli("agent", "antrag", self.world,
                       "--entwurf=" + json.dumps(self.draft(id="per-cli", team=None)),
                       "--absender", "lead", "--rolle", "teamleiter", "--id", "antrag-cli", "--json")
        self.assertEqual(out.returncode, 0, out.stderr)
        controller = ac.AgentController(self.world, "run-request-decision", lambda _binding: True)
        client = controller.bind_agent("main", "hauptagent")
        try:
            client.request("agent.decide", {"request_id": "antrag-cli", "accept": True})
        finally:
            client.close()
            controller.close()
            controller.join()
        self.assertTrue((self.world / "agents" / "per-cli" / "AGENTS.md").exists())
        wrapper = subprocess.run([str(SHELL / "wb-agent"), "vorlagen", "--json"], capture_output=True, text=True, env=env)
        self.assertEqual((wrapper.returncode, len(json.loads(wrapper.stdout))), (0, 5), wrapper.stderr)



class TeamLeaderApprovalTests(unittest.TestCase):
    """Auftrag agentsui Nr. 4: a team leader approves own tickets sent by members of the team."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-abnahme-")
        self.world = Path(self.tmp.name) / "world"
        ad.create_world(self.world, name="Probe", main_name="main", sender="mensch")
        for agent_id, stage, team in (("lead", "teamleiter", "dev"), ("member", "mitglied", "dev"),
                                      ("other-lead", "teamleiter", "ops"), ("stranger", "mitglied", "ops")):
            ad.create_agent(self.world, agent_id, stage, team, "Probe", None, None, None, None, None, None,
                            "lokal", "mensch", None)

    def tearDown(self):
        self.tmp.cleanup()

    def done_ticket(self, ticket_id, sender, role, recipients, assignee, team=None):
        ad.create_ticket(self.world, "Titel", "Ziel", "Fertig", recipients, sender, role, team, {}, [], ticket_id)
        ad.claim_ticket(self.world, ticket_id, assignee, assignee, None)
        return ad.write_result(self.world, ticket_id, assignee, "Ergebnis", None, assignee, None)

    def test_leader_approves_own_ticket_from_team_member(self):
        self.done_ticket("t-eigen", "member", "mitglied", ["lead"], "lead")
        approved = ad.approve_ticket(self.world, "t-eigen", "lead", "teamleiter", "passt")
        self.assertEqual((approved["state"], approved["approval"]["agent"]), ("abgenommen", "lead"))
        # Returning it works on the same rule.
        self.done_ticket("t-zurueck", "member", "mitglied", ["lead"], "lead")
        returned = ad.approve_ticket(self.world, "t-zurueck", "lead", "teamleiter", "nochmal", False)
        self.assertEqual(returned["state"], "zurückgegeben")

    def test_leader_still_refused_outside_the_rule(self):
        cases = [
            ("t-fremdes-team", "stranger", "mitglied", ["lead"], "lead"),      # sender from another team
            ("t-vom-haupt", "main", "hauptagent", ["lead"], "lead"),           # sender not a member
            ("t-vom-menschen", "mensch", None, ["lead"], "lead"),              # external sender
            ("t-nicht-selbst", "member", "mitglied", ["member"], "member"),     # leader did not process it
        ]
        for ticket_id, sender, role, recipients, assignee in cases:
            with self.subTest(ticket=ticket_id):
                self.done_ticket(ticket_id, sender, role, recipients, assignee)
                with self.assertRaisesRegex(ad.AgentsError, "Teamleiter darf nur"):
                    ad.approve_ticket(self.world, ticket_id, "lead", "teamleiter", None)
                self.assertEqual(ad.read_ticket(self.world, ticket_id)["state"], "zur Abnahme")
        # The team rule itself is unchanged: a team ticket of the own team, and never another team's.
        self.done_ticket("t-team", "main", "hauptagent", [], "member", team="dev")
        self.assertEqual(ad.approve_ticket(self.world, "t-team", "lead", "teamleiter", None)["state"], "abgenommen")
        self.done_ticket("t-ops", "main", "hauptagent", [], "stranger", team="ops")
        with self.assertRaisesRegex(ad.AgentsError, "Teamleiter darf nur"):
            ad.approve_ticket(self.world, "t-ops", "lead", "teamleiter", None)
        self.done_ticket("t-mitglied", "member", "mitglied", ["member"], "member")
        with self.assertRaisesRegex(ad.AgentsError, "darf diese Mutation nicht"):
            ad.approve_ticket(self.world, "t-mitglied", "member", "mitglied", None)



class _FakeInbox:
    """A stand-in for a Claude Code session inbox: one Unix socket in this process."""

    def __init__(self, path):
        import socket
        import threading
        self.path = str(path)
        self.received = []
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(self.path)
        self.server.listen(4)
        self.server.settimeout(0.2)
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def _serve(self):
        while not self.stop.is_set():
            try:
                conn, _ = self.server.accept()
            except OSError:
                continue
            with conn:
                conn.settimeout(2)
                data = b""
                while True:
                    try:
                        chunk = conn.recv(65536)
                    except OSError:
                        break
                    if not chunk:
                        break
                    data += chunk
            self.received.append([json.loads(line) for line in data.decode("utf-8").splitlines() if line])

    def close(self):
        self.stop.set()
        self.thread.join(2)
        self.server.close()


class SessionInboxReturnTests(unittest.TestCase):
    """Auftrag agentsui Nr. 5: `wb-ticket neu --absender orchestrator` and the result in the session inbox.

    Isolation: the session registry lives under a throwaway HOME and names this test process;
    the inbox is a socket of this process under a short /tmp folder. No live session, no pane.
    """

    def setUp(self):
        from unittest import mock
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-rueckweg-")
        self.base = Path(self.tmp.name)
        self.home = self.base / "home"
        self.registry = self.home / ".claude" / "sessions"
        self.registry.mkdir(parents=True)
        self.vorrat = self.base / "vorrat"
        self.vorrat.mkdir()
        self.sock_dir = Path(tempfile.mkdtemp(prefix="wbti-", dir="/tmp"))
        self.inbox = _FakeInbox(self.sock_dir / "s.sock")
        self.env = mock.patch.dict(os.environ, {"HOME": str(self.home), "WB_VORRAT": str(self.vorrat)})
        self.env.start()
        self.register(os.getpid(), "sitzung-1")
        self.world = self.base / "welt"
        ad.create_world(self.world, name="Probe", main_name="main", sender="mensch")
        ad.create_agent(self.world, "worker", "mitglied", None, "Arbeitet", None, None, None, None, None, None,
                        "lokal", "mensch", None)

    def tearDown(self):
        self.env.stop()
        self.inbox.close()
        import shutil
        shutil.rmtree(self.sock_dir, ignore_errors=True)
        self.tmp.cleanup()

    def register(self, pid, session_id, proc_start="probe"):
        (self.registry / ("%d.json" % pid)).write_text(json.dumps({
            "pid": pid, "sessionId": session_id, "procStart": proc_start, "messagingSocketPath": self.inbox.path,
            "name": "orchestrator-probe", "tmux": "probe:1.%9", "cwd": str(self.base)}), encoding="utf-8")
        (self.registry / ("%d.probe.key" % pid)).write_text(json.dumps({"peerToken": "token-probe"}), encoding="utf-8")

    def wb_ticket(self, *args, check=True):
        env = dict(os.environ, HOME=str(self.home), WB_VORRAT=str(self.vorrat), PYTHONDONTWRITEBYTECODE="1")
        result = subprocess.run([str(SHELL / "wb-ticket"), "neu", *map(str, args)], capture_output=True, text=True,
                                env=env, timeout=60)
        if check:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def finish(self, ticket_id, approver="main"):
        ad.claim_ticket(self.world, ticket_id, "worker", "worker", None)
        ad.write_result(self.world, ticket_id, "worker", "Import laeuft, 20 Dateien", "abc123", "worker", None)
        return ad.approve_ticket(self.world, ticket_id, approver, None, "passt")

    def wait_received(self, count):
        import time
        end = time.time() + 5
        while len(self.inbox.received) < count and time.time() < end:
            time.sleep(0.05)
        return self.inbox.received

    def test_orchestrator_ticket_records_the_calling_session_and_gets_the_result(self):
        created = json.loads(self.wb_ticket("--welt", self.world, "--id", "t-code", "--titel", "Import", "--ziel", "ICS lesen",
                                            "--fertig", "Tests gruen", "--an", "worker", "--absender", "orchestrator",
                                            "--json").stdout)
        route = created["limits"]["rueckweg"]
        self.assertEqual((route["art"], route["pid"], route["session_id"], route["socket"]),
                         ("sitzungs-inbox", os.getpid(), "sitzung-1", self.inbox.path))
        self.assertNotIn("token-probe", json.dumps(created))
        # A retry with the same id stays the same ticket.
        again = json.loads(self.wb_ticket("--welt", self.world, "--id", "t-code", "--titel", "Import", "--ziel", "ICS lesen",
                                          "--fertig", "Tests gruen", "--an", "worker", "--absender", "orchestrator",
                                          "--json").stdout)
        self.assertEqual(again["created_at"], created["created_at"])
        approved = self.finish("t-code")
        self.assertEqual(approved["state"], "abgenommen")
        received = self.wait_received(1)
        self.assertEqual(len(received), 1)
        auth, message = received[0]
        self.assertEqual(auth, {"type": "auth", "token": "token-probe"})
        text = message["message"]["content"]
        for part in ("Agents-Welt „Probe“", "t-code „Import“", "Abgenommen von: main, Bemerkung: passt",
                     "Commit abc123", "Import laeuft, 20 Dateien", "kein neuer Auftrag"):
            self.assertIn(part, text)
        marker = json.loads((self.world / "tickets" / "t-code" / "rueckweg.json").read_text(encoding="utf-8"))
        self.assertEqual((marker["status"], marker["pid"]), ("zugestellt", os.getpid()))
        events = [json.loads(line) for line in (self.world / "tickets" / "t-code" / "verlauf.jsonl").read_text().splitlines()]
        self.assertEqual([(e["event"], e.get("status")) for e in events][-2:], [("abgenommen", None), ("rueckweg", "zugestellt")])
        # The carrier may call again: nothing is sent twice.
        self.assertEqual(ad.deliver_to_session_inbox(self.world, "t-code")["status"], "zugestellt")
        self.assertEqual(len(self.wait_received(2)), 1)

    def test_options_without_return_path_and_pinned_pid(self):
        plain = json.loads(self.wb_ticket("--welt", self.world, "--titel", "A", "--ziel", "B", "--fertig", "C",
                                          "--an", "worker", "--json").stdout)
        self.assertNotIn("rueckweg", plain["limits"])
        off = json.loads(self.wb_ticket("--welt", self.world, "--titel", "A", "--ziel", "B", "--fertig", "C", "--an", "worker",
                                        "--absender", "orchestrator", "--inbox", "keine", "--grenzen", '{"budget": 3}',
                                        "--json").stdout)
        # Seit tickets3 gilt ohne Frist und Rundenzahl die Vorgabe von sechs Zuegen.
        self.assertEqual(off["limits"], {"budget": 3, "runden": 6})
        pinned = json.loads(self.wb_ticket(self.world, "--titel", "A", "--ziel", "B", "--fertig", "C", "--an", "worker",
                                           "--absender=orchestrator", "--inbox-pid", os.getpid(), "--grenzen={\"budget\": 4}",
                                           "--json").stdout)
        self.assertEqual((pinned["limits"]["budget"], pinned["limits"]["rueckweg"]["pid"]), (4, os.getpid()))
        missing = self.wb_ticket("--welt", self.world, "--titel", "A", "--ziel", "B", "--fertig", "C", "--an", "worker",
                                 "--absender", "orchestrator", "--inbox-pid", "999999", check=False)
        self.assertEqual(missing.returncode, 2)
        self.assertIn("Keine lebende Claude-Code-Sitzung", missing.stderr)
        wrong = self.wb_ticket("--welt", self.world, "--titel", "A", "--ziel", "B", "--fertig", "C", "--an", "worker",
                               "--inbox", "keine", check=False)
        self.assertEqual(wrong.returncode, 2)
        # Without a registered session in the call chain the ticket is written with a warning.
        (self.registry / ("%d.json" % os.getpid())).unlink()
        unregistered = self.wb_ticket("--welt", self.world, "--titel", "A", "--ziel", "B", "--fertig", "C", "--an", "worker",
                                      "--absender", "orchestrator", "--json")
        self.assertNotIn("rueckweg", json.loads(unregistered.stdout)["limits"])
        self.assertIn("kein Rueckweg eingetragen", unregistered.stderr)
        self.assertEqual(self.inbox.received, [])

    def test_pause_dead_session_and_reused_pid_never_undo_the_approval(self):
        route = ad.find_session_inbox(os.getpid())
        limits = {"rueckweg": route}
        for ticket_id in ("t-pause", "t-weg", "t-fremd"):
            ad.create_ticket(self.world, "Titel", "Ziel", "Fertig", ["worker"], "orchestrator", None, None, limits, [], ticket_id)
        (self.vorrat / ".agentverkehr-pause").write_text("{}", encoding="utf-8")
        self.assertEqual(self.finish("t-pause")["state"], "abgenommen")
        marker = json.loads((self.world / "tickets" / "t-pause" / "rueckweg.json").read_text(encoding="utf-8"))
        self.assertEqual(marker["status"], "zurueckgehalten")
        self.assertEqual(ad.deliver_to_session_inbox(self.world, "t-pause", ignore_pause=True)["status"], "zugestellt")
        (self.vorrat / ".agentverkehr-pause").unlink()
        self.assertEqual(len(self.wait_received(1)), 1)
        # A session restarted under the same pid is a different session: nothing is sent.
        self.register(os.getpid(), "andere-sitzung")
        self.assertEqual(self.finish("t-fremd")["state"], "abgenommen")
        self.assertEqual(json.loads((self.world / "tickets" / "t-fremd" / "rueckweg.json").read_text())["status"], "sitzung-fehlt")
        for path in self.registry.iterdir():
            path.unlink()
        self.assertEqual(self.finish("t-weg")["state"], "abgenommen")
        self.assertEqual(json.loads((self.world / "tickets" / "t-weg" / "rueckweg.json").read_text())["status"], "sitzung-fehlt")
        self.assertEqual(len(self.inbox.received), 1)
        self.assertEqual(ad.deliver_to_session_inbox(self.world, ad.create_ticket(
            self.world, "Ohne", "Ziel", "Fertig", ["worker"], "cli-operator", None)["id"])["status"], "ohne-rueckweg")


# Stellvertreter fuer ssh im Fernweg: fuehrt den entfernten Befehl lokal aus und merkt sich den Host.
SSH_ATTRAPPE = """#!/bin/sh
host=""
for arg in "$@"; do
  case "$arg" in -*) ;; *) if [ -z "$host" ]; then host="$arg"; else befehl="$arg"; fi ;; esac
done
printf '%s\\n' "$host" >> "$WB_TEST_SSH_LOG"
exec /bin/sh -c "$befehl"
"""


class WorldAccessTests(unittest.TestCase):
    """Zugaenge einer Welt (agents_zugaenge): CLI, Pruefung, Ansicht, Anweisung und Fernweg."""

    def setUp(self):
        import agents_zugaenge as az
        self.az = az
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-zugaenge-")
        self.base = Path(self.tmp.name)
        self.world = self.base / "world"
        ad.create_world(self.world, name="Zugang", main_name="main", sender="mensch")
        self.key = self.base / "keys" / "id_probe"
        self.key.parent.mkdir()
        self.key.write_text("NICHT-ECHT\n")
        self.key.chmod(0o600)
        (self.key.parent / "known_hosts").write_text("[127.0.0.1]:2222 ssh-ed25519 AAAAattrappe\n")

    def tearDown(self):
        self.tmp.cleanup()

    def wb_welt(self, *args, env=None):
        if env is None:
            return _run_cli("welt", *args)
        return subprocess.run([str(SHELL / "wb-welt"), *map(str, args)], text=True, capture_output=True, timeout=60,
                              env=dict(os.environ, **(env or {})))

    def test_cli_adds_only_when_confirmed_writes_private_file_and_reports_in_channel(self):
        base = ["zugang", self.world, "hinzufuegen", "--name", "probe", "--ziel", "agent@127.0.0.1", "--port", "2222",
                "--schluessel", self.key, "--json"]
        refused = self.wb_welt(*base)
        self.assertEqual(refused.returncode, 2)
        self.assertIn("--bestaetigt", refused.stderr)
        self.assertFalse((self.world / "zugaenge.json").exists())
        added = self.wb_welt(*base, "--bestaetigt")
        self.assertEqual(added.returncode, 0, added.stderr)
        entry = json.loads(added.stdout)
        self.assertEqual(entry["known_hosts"], str(self.key.parent / "known_hosts"))
        self.assertEqual(entry["muster"], ["ssh probe *", "scp *probe:*", "rsync *probe:*"])
        path = self.world / "zugaenge.json"
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(path.read_text()), {"version": 1, "zugaenge": [entry]})
        again = self.wb_welt(*base, "--bestaetigt")
        self.assertIn("existiert bereits", again.stderr)
        listed = self.wb_welt("zugang", self.world, "liste")
        self.assertEqual(listed.stdout.strip(), "probe (ssh) -> agent@127.0.0.1")
        messages = ad.read_messages(self.world)
        self.assertEqual([(m["sender"], m["subject"], m["text"]) for m in messages],
                         [("mensch", "Zugang", "Zugang probe (ssh) hinzugefügt.")])
        self.assertEqual(list((self.world / "agents" / "main" / "postfach").glob("*.json")), [])
        removed = self.wb_welt("zugang", self.world, "entfernen", "--name", "probe", "--json")
        self.assertEqual((removed.returncode, json.loads(removed.stdout)["entfernt"]), (0, True), removed.stderr)
        self.assertEqual(json.loads(path.read_text())["zugaenge"], [])
        self.assertEqual(ad.read_messages(self.world)[-1]["text"], "Zugang probe (ssh) entfernt.")

    def test_validation_rejects_bad_names_targets_keys_patterns_and_agents(self):
        az = self.az

        def fails(expected, **changes):
            entry = dict({"name": "probe", "ziel": "agent@127.0.0.1", "schluessel": str(self.key),
                          "known_hosts": str(self.key.parent / "known_hosts")}, **changes)
            with self.assertRaises(ad.AgentsError) as caught:
                az.hinzufuegen(self.world, entry, bestaetigt=True, absender=changes.pop("absender", None))
            self.assertIn(expected, str(caught.exception))

        fails("Zugangsname", name="Probe Server")
        fails("Zugangsname", name="../x")
        fails("user@host oder ein ssh-Alias", ziel="agent@host; rm")
        fails("user@host oder ein ssh-Alias", ziel="-oProxyCommand=x")
        fails("fehlt auf dem Traegerhost", schluessel=str(self.base / "fehlt"))
        fails("absoluten kanonischen Pfad", schluessel="keys/id_probe")
        fails("Port", port=0)
        fails("beginnt nicht mit ssh", muster=["curl *"])
        fails("muss mit 'ssh probe' beginnen", muster=["ssh anderer *"])
        fails("muss das Ziel 'probe:' nennen", muster=["scp * anderer:*"])
        fails("gesperrt", muster=["ssh probe kill *"])
        ad.create_agent(self.world, "worker", "mitglied", None, "Arbeitet", None, None, None, None, None, None,
                        "lokal", "main", "hauptagent")
        with self.assertRaises(ad.AgentsError) as caught:
            az.hinzufuegen(self.world, {"name": "probe", "ziel": "agent@127.0.0.1", "schluessel": str(self.key),
                                        "known_hosts": str(self.key.parent / "known_hosts")},
                           bestaetigt=True, absender="worker")
        self.assertIn("nur der Mensch", str(caught.exception))
        self.assertFalse((self.world / "zugaenge.json").exists())
        (self.world / "zugaenge.json").write_text('{"version": 1, "zugaenge": [{"name": "x", "art": "telnet"}]}')
        with self.assertRaises(ad.AgentsError):
            az.lesen(self.world)

    def test_snapshot_and_instructions_name_accesses_without_target_or_key(self):
        self.az.hinzufuegen(self.world, {"name": "myproject-server", "ziel": "root@192.0.2.10", "schluessel": str(self.key),
                                         "known_hosts": str(self.key.parent / "known_hosts")},
                            bestaetigt=True, absender="mensch")
        snapshot = ad.world_snapshot(self.world)
        self.assertEqual(snapshot["zugaenge"], [{"name": "myproject-server", "art": "ssh"}])
        text = json.dumps(snapshot)
        self.assertNotIn(str(self.key), text)
        self.assertNotIn("192.0.2.10", text)
        view = self.wb_welt("ansicht", self.world, "--json")
        self.assertEqual(json.loads(view.stdout)["zugaenge"], [{"name": "myproject-server", "art": "ssh"}])
        preview = ad.preview_agent_draft(self.world, {"id": "neu", "specialty": "Prueft den Server.", "tools": ["Bash"]})
        self.assertIn("- Zugänge: myproject-server (ssh) – `ssh myproject-server <befehl>`.", preview["instructions"])
        self.assertIn("außer über die Zugänge", preview["instructions"])
        self.assertNotIn("192.0.2.10", preview["instructions"])

    def test_remote_world_runs_the_access_command_on_the_carrier_host(self):
        log = self.base / "ssh.log"
        ssh = self.base / "ssh"
        ssh.write_text(SSH_ATTRAPPE)
        ssh.chmod(0o755)
        env = {"WB_FERN_SSH": str(ssh), "WB_AGENTS_FERN_SHELL": str(SHELL), "WB_TEST_SSH_LOG": str(log)}
        added = self.wb_welt("zugang", self.world, "hinzufuegen", "--name", "probe",
                             "--ziel", "agent@127.0.0.1", "--schluessel", self.key,
                             "--bestaetigt", "--json")
        self.assertEqual(added.returncode, 0, added.stderr)
        result = self.wb_welt("zugang", "traegerhost:%s" % self.world, "liste", "--json", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([item["name"] for item in json.loads(result.stdout)], ["probe"])
        self.assertEqual(log.read_text().split(), ["traegerhost"])
        # Der Schluessel wird dort geprueft, wo der Befehl laeuft: ein nur hier vorhandener Pfad scheitert dort genauso.
        missing = self.wb_welt("zugang", "traegerhost:%s" % self.world, "hinzufuegen", "--name", "zwei",
                               "--ziel", "agent@127.0.0.1", "--schluessel", self.base / "fehlt", "--bestaetigt", env=env)
        self.assertEqual(missing.returncode, 2)
        self.assertIn("fehlt auf dem Traegerhost", missing.stderr)
        listed = self.wb_welt("zugang", "traegerhost:%s" % self.world, "liste", "--json", env=env)
        self.assertEqual([item["name"] for item in json.loads(listed.stdout)], ["probe"])


if __name__ == "__main__":
    unittest.main()
