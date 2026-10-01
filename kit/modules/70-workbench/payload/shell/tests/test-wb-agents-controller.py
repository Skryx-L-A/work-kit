#!/usr/bin/env python3
"""Isolated stdlib tests for the run-bound Agents controller channel."""

import json
import os
import struct
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from pathlib import Path

HERE = Path(__file__).resolve()
SHELL = HERE.parents[1]
sys.path.insert(0, str(SHELL))
import agents_controller as ac
import agents_data as ad
from herkunft_fixture import gemessener_mensch


_MENSCH_PATCH = None


def setUpModule():
    global _MENSCH_PATCH
    _MENSCH_PATCH = gemessener_mensch(ad)
    _MENSCH_PATCH.start()


def tearDownModule():
    _MENSCH_PATCH.stop()


class AgentsControllerTests(unittest.TestCase):
    def test_completed_connections_do_not_accumulate_in_long_lived_controller(self):
        controller = self.controller()
        for _ in range(20):
            client = controller.bind_agent('member', 'mitglied')
            self.assertEqual(client.request('inbox.read'), [])
            self.assertEqual(len(controller._sessions), 1)
            client.close()
            controller.join()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-controller-")
        self.world = Path(self.tmp.name) / "world"
        ad.create_world(self.world, name="Controller", main_name="main", sender="cli-operator")
        ad.create_agent(self.world, "member", "mitglied", "dev", "Baut Dateien",
                        None, None, None, None, None, None, "lokal", "main", "hauptagent")
        ad.create_agent(self.world, "lead", "teamleiter", "dev", "Nimmt ab",
                        None, None, None, None, None, None, "lokal", "main", "hauptagent")
        self.controllers = []
        self.active_run = "run-1"

    def tearDown(self):
        for controller in self.controllers:
            controller.close()
            controller.join()
        self.tmp.cleanup()

    def controller(self, checker=True, timeout=1.0, session_timeout=5.0):
        current = (lambda binding: self.active_run == binding.run_id) if checker else None
        controller = ac.AgentController(self.world, self.active_run, current, timeout, session_timeout)
        self.controllers.append(controller)
        return controller

    def test_two_bindings_can_only_use_their_own_identity_and_idempotent_data_ids(self):
        ticket = ad.create_ticket(self.world, "Memberticket", "G", "D", ["member"],
                                  "main", "hauptagent", ticket_id="member-ticket")
        foreign = ad.create_ticket(self.world, "Leadticket", "G", "D", ["lead"],
                                   "main", "hauptagent", ticket_id="lead-ticket")
        controller = self.controller()
        member = controller.bind_agent("member", "mitglied")
        main = controller.bind_agent("main", "hauptagent")
        self.assertFalse(any(name in vars(member) for name in ("world_root", "world_id", "agent_id", "role", "run_id")))
        self.assertFalse(hasattr(controller, "_listener"))

        with self.assertRaises(ac.ControllerError):
            member.request("message.send", {"recipients": ["main"], "text": "ohne ID"})

        sent = member.request("message.send", {"recipients": ["main"], "text": "Status", "message_id": "status-message"})
        repeated = member.request("message.send", {"recipients": ["main"], "text": "Status", "message_id": "status-message"})
        self.assertEqual(sent, repeated)
        inbox = main.request("inbox.read")
        self.assertEqual([item["delivery_id"] for item in inbox], ["status-message"])
        self.assertTrue(main.request("inbox.ack", {"delivery_id": "status-message"})["acknowledged"])
        with self.assertRaises(ac.ControllerError):
            member.request("inbox.ack", {"delivery_id": "status-message"})

        claimed = member.request("ticket.claim", {"ticket_id": ticket["id"]})
        self.assertEqual(claimed["assignee"], "member")
        self.assertEqual(member.request("ticket.claim", {"ticket_id": ticket["id"]}), claimed)
        result = member.request("ticket.result", {"ticket_id": ticket["id"], "text": "fertig", "commit": "abc"})
        self.assertEqual(member.request("ticket.result", {"ticket_id": ticket["id"], "text": "fertig", "commit": "abc"}), result)
        with self.assertRaises(ac.ControllerError):
            member.request("ticket.claim", {"ticket_id": foreign["id"]})
        with self.assertRaises(ac.ControllerError):
            member.request("ticket.claim", {"ticket_id": ticket["id"], "agent_id": "lead"})

        question = main.request("question.ask", {"question_id": "controller-question", "text": "Welche Wahl?",
                                                   "options": ["A", "B"], "recommendation": "A"})
        self.assertEqual(main.request("question.ask", {"question_id": "controller-question", "text": "Welche Wahl?",
                                                        "options": ["A", "B"], "recommendation": "A"}), question)
        with self.assertRaises(ac.ControllerError):
            member.request("question.ask", {"question_id": "member-question", "text": "Nicht erlaubt"})
        with self.assertRaises(ac.ControllerError):
            main.request("question.ask", {"text": "ohne ID"})
        self.assertEqual(ad.list_questions(self.world), [question])

        self.assertEqual(len([message for message in ad.read_messages(self.world)
                              if message.get("id") == "status-message"]), 1)
        self.assertEqual(controller.bind_agent("member", "mitglied").request("ticket.show",
                                                                         {"ticket_id": ticket["id"]})["id"], ticket["id"])

    def test_message_reply_goes_back_to_original_sender_and_chat_only(self):
        controller = self.controller()
        member = controller.bind_agent("member", "mitglied")
        lead = controller.bind_agent("lead", "teamleiter")
        ad.send_message(self.world, "lead", ["member"], "Kanalfrage", None, "lead-kanal", "teamleiter")
        ad.send_message(self.world, "lead", ["member"], "Direktfrage", None, "lead-direkt", "teamleiter", direct=True)
        ad.send_message(self.world, "person-1", ["member"], "Frage vom Nutzer", None, "mensch-kanal", None)
        reply = member.request("message.reply", {"delivery_id": "lead-kanal", "text": "Kanalantwort",
                                                 "message_id": "member-antwort-1"})
        self.assertEqual((reply["sender"], reply["recipients"], reply["kind"]), ("member", ["lead"], "kanal"))
        self.assertEqual(member.request("message.reply", {"delivery_id": "lead-kanal", "text": "Kanalantwort",
                                                          "message_id": "member-antwort-1"})["id"], "member-antwort-1")
        direct = member.request("message.reply", {"delivery_id": "lead-direkt", "text": "Direktantwort",
                                                  "message_id": "member-antwort-2"})
        chat = ad.derived_id("chat", "lead", "member")
        self.assertIn("member-antwort-2", [item["id"] for item in ad.read_messages(self.world, direct_chat=chat)])
        self.assertNotIn("member-antwort-2", [item["id"] for item in ad.read_messages(self.world)])
        self.assertEqual(direct["recipients"], ["lead"])
        self.assertIn("member-antwort-2", [item["delivery_id"] for item in lead.request("inbox.read")])
        human = member.request("message.reply", {"delivery_id": "mensch-kanal", "text": "Hallo der Nutzer",
                                                 "message_id": "member-antwort-3"})
        self.assertEqual((human["recipient"], human["recipients"]), ("person-1", []))
        for payload in ({"delivery_id": "member-antwort-2", "text": "x", "message_id": "m4"},
                        {"delivery_id": "lead-kanal", "text": "x", "message_id": "m5", "recipients": ["main"]},
                        {"delivery_id": "unbekannt", "text": "x", "message_id": "m6"}):
            with self.subTest(payload=payload), self.assertRaises(ac.ControllerError):
                member.request("message.reply", payload)
        with self.assertRaises(ac.ControllerError):
            lead.request("message.reply", {"delivery_id": "lead-kanal", "text": "fremd", "message_id": "m7"})

    def test_replies_and_messages_to_the_human_land_in_the_human_postbox_with_marks(self):
        controller = self.controller()
        member = controller.bind_agent("member", "mitglied")
        main = controller.bind_agent("main", "hauptagent")
        postbox = self.world / "menschen" / "mensch" / "postfach"
        ad.send_message(self.world, "mensch", ["member"], "Kanal vom Menschen", None, "mensch-an-member", None)
        ad.send_message(self.world, "mensch", ["member"], "Direkt vom Menschen", None, "mensch-direkt", None,
                        direct=True)
        ad.send_message(self.world, "lead", ["member", "mensch"], "Runde mit Mensch", None, "lead-runde", "teamleiter",
                        direct=True)
        ad.send_message(self.world, "lead", ["member"], "Nur Agenten", None, "lead-kanal", "teamleiter")

        channel = member.request("message.reply", {"delivery_id": "mensch-an-member", "text": "Erledigt",
                                                   "message_id": "antwort-kanal", "mark": "ergebnis"})
        self.assertEqual((channel["recipient"], channel["humans"], channel["mark"], channel["subject"]),
                         ("mensch", ["mensch"], "ergebnis", "Antwort"))
        stored = json.loads((postbox / "antwort-kanal.json").read_text())
        self.assertEqual((stored["sender"], stored["mark"], stored["acknowledged"]), ("member", "ergebnis", False))
        self.assertEqual(member.request("message.reply", {"delivery_id": "mensch-an-member", "text": "Erledigt",
                                                          "message_id": "antwort-kanal", "mark": "ergebnis"})["id"],
                         "antwort-kanal")

        direct = member.request("message.reply", {"delivery_id": "mensch-direkt", "text": "Direkt zurueck",
                                                  "message_id": "antwort-direkt"})
        self.assertEqual((direct["recipients"], direct["humans"], "mark" in direct), ([], ["mensch"], False))
        chat = ad.derived_id("chat", "member", "mensch")
        self.assertIn("antwort-direkt", [item["id"] for item in ad.read_messages(self.world, direct_chat=chat)])
        self.assertTrue((postbox / "antwort-direkt.json").is_file())

        group = member.request("message.reply", {"delivery_id": "lead-runde", "text": "An beide",
                                                 "message_id": "antwort-runde"})
        self.assertEqual((group["recipients"], group["humans"]), (["lead"], ["mensch"]))
        self.assertIn("antwort-runde", [item["id"] for item in ad.read_messages(
            self.world, direct_chat=ad.derived_id("chat", "lead", "member", "mensch"))])
        self.assertIn("antwort-runde", [item["delivery_id"] for item in controller.bind_agent(
            "lead", "teamleiter").request("inbox.read")])
        self.assertTrue((postbox / "antwort-runde.json").is_file())

        for payload in ({"delivery_id": "lead-kanal", "text": "x", "message_id": "m1", "mark": "ergebnis"},
                        {"delivery_id": "mensch-an-member", "text": "x", "message_id": "m2", "mark": "frage"},
                        {"delivery_id": "mensch-an-member", "text": "x", "message_id": "m3", "mark": "wichtig"},
                        {"delivery_id": "mensch-an-member", "text": "x", "message_id": "m4", "mark": True}):
            with self.subTest(payload=payload), self.assertRaises(ac.ControllerError):
                member.request("message.reply", payload)
        self.assertFalse(any((postbox / name).exists() for name in ("m1.json", "m2.json", "m3.json", "m4.json")))

        result = member.request("message.send", {"recipients": ["mensch"], "text": "Ticket fertig",
                                                 "message_id": "gemeldet", "mark": "ergebnis"})
        self.assertEqual(result["mark"], "ergebnis")
        with self.assertRaises(ac.ControllerError):
            member.request("message.send", {"recipients": ["mensch"], "text": "Frage?", "message_id": "frage-m",
                                            "mark": "frage"})
        with self.assertRaises(ac.ControllerError):
            member.request("message.send", {"recipients": ["lead"], "text": "x", "message_id": "an-lead",
                                            "mark": "ergebnis"})
        asked = main.request("message.send", {"recipients": ["mensch"], "text": "Welche Wahl?",
                                              "message_id": "frage-main", "mark": "frage"})
        self.assertEqual(json.loads((postbox / "frage-main.json").read_text())["mark"], asked["mark"])

    def test_agent_creation_request_and_decision_over_rpc_report_to_the_human(self):
        controller = self.controller()
        main = controller.bind_agent("main", "hauptagent")
        lead = controller.bind_agent("lead", "teamleiter")
        member = controller.bind_agent("member", "mitglied")
        postbox = self.world / "menschen" / "mensch" / "postfach"
        draft = {"id": "rechercheur", "stage": "mitglied", "team": "dev", "specialty": "Sucht Belege",
                 "model": "sonnet5:high", "tools": ["Read"]}
        created = main.request("agent.create", {"draft": draft})
        self.assertEqual((created["id"], created["model_profile"]["effort"]), ("rechercheur", "high"))
        report = json.loads((postbox / (created["meldung"] + ".json")).read_text())
        self.assertEqual((report["sender"], report["mark"]), ("main", "ergebnis"))
        self.assertIn("Agent rechercheur angelegt, Rolle Mitglied im Team dev, Modell sonnet5:high", report["text"])
        with self.assertRaises(ac.ControllerError):
            main.request("agent.create", {"draft": draft})
        with self.assertRaises(ac.ControllerError):
            main.request("agent.create", {"draft": dict(draft, id="chef", stage="hauptagent", team=None)})
        for client in (member, lead):
            with self.subTest(client=client), self.assertRaises(ac.ControllerError):
                client.request("agent.create", {"draft": dict(draft, id="fremd")})
        with self.assertRaises(ac.ControllerError):
            main.request("agent.create", {"draft": "kein Objekt"})

        request = lead.request("agent.request", {"draft": dict(draft, id="helfer"), "request_id": "antrag-1"})
        self.assertEqual((request["to"], request["state"]), ("main", "offen"))
        with self.assertRaises(ac.ControllerError):
            member.request("agent.request", {"draft": dict(draft, id="helfer2"), "request_id": "antrag-2"})
        self.assertIn(ad.derived_id("antrag", "antrag-1"), [item["delivery_id"] for item in main.request("inbox.read")])
        with self.assertRaises(ac.ControllerError):
            lead.request("agent.decide", {"request_id": "antrag-1", "accept": True})
        decided = main.request("agent.decide", {"request_id": "antrag-1", "accept": True, "note": "passt"})
        self.assertEqual((decided["answer"]["agent"], decided["meldung"]), ("helfer", ad.derived_id("agent-angelegt", "helfer")))
        self.assertEqual(ad.read_agent(self.world, "helfer")["request"], "antrag-1")
        self.assertIn(ad.derived_id("antrag-entschieden", "antrag-1"),
                      [item["delivery_id"] for item in lead.request("inbox.read")])
        again = main.request("agent.decide", {"request_id": "antrag-1", "accept": True, "note": "passt"})
        self.assertEqual(again["meldung"], decided["meldung"])
        self.assertEqual(len([p for p in postbox.glob("*.json") if "agent-angelegt" in p.name]), 2)
        lead.request("agent.request", {"draft": dict(draft, id="spaeter"), "request_id": "antrag-3"})
        declined = main.request("agent.decide", {"request_id": "antrag-3", "accept": False, "note": "nicht jetzt"})
        self.assertNotIn("meldung", declined)
        with self.assertRaises(ad.AgentsError):
            ad.read_agent(self.world, "spaeter")

    def test_run_checker_world_binding_and_missing_checker_block_every_request(self):
        controller = self.controller()
        member = controller.bind_agent("member", "mitglied")
        self.active_run = "run-2"
        with self.assertRaises(ac.ControllerError):
            member.request("inbox.read")

        blocked = ac.AgentController(self.world, "run-2", None)
        self.controllers.append(blocked)
        blocked_client = blocked.bind_agent("member", "mitglied")
        with self.assertRaises(ac.ControllerError):
            blocked_client.request("inbox.read")

        world_file = self.world / "world.json"
        world = json.loads(world_file.read_text(encoding="utf-8"))
        world["id"] = "welt-switched"
        world_file.write_text(json.dumps(world), encoding="utf-8")
        world_controller = self.controller()
        world_member = world_controller.bind_agent("member", "mitglied")
        world["id"] = "welt-switched-again"
        world_file.write_text(json.dumps(world), encoding="utf-8")
        with self.assertRaises(ac.ControllerError):
            world_member.request("inbox.read")

    def test_protocol_rejects_unknown_fields_operation_bad_json_oversize_and_timeout(self):
        controller = self.controller()
        client = controller.bind_agent("member", "mitglied")
        with self.assertRaises(ac.ControllerError):
            client.request("ticket.show", {"ticket_id": "missing", "world_root": "/escape"})

        client._sock.sendall(struct.pack("!I", 2) + b"{}")
        self.assertFalse(ac._recv_frame(client._sock)["ok"])

        raw = {"op": "not-allowed", "payload": {}}
        body = json.dumps(raw).encode("utf-8")
        client._sock.sendall(struct.pack("!I", len(body)) + body)
        self.assertFalse(ac._recv_frame(client._sock)["ok"])

        raw = {"op": [], "payload": {}}
        body = json.dumps(raw).encode("utf-8")
        client._sock.sendall(struct.pack("!I", len(body)) + body)
        self.assertFalse(ac._recv_frame(client._sock)["ok"])

        client.close()
        controller.join()
        self.controllers.remove(controller)

        short = self.controller(timeout=0.05)
        timed = short.bind_agent("member", "mitglied")
        timed._sock.sendall(struct.pack("!I", 5) + b"{}")
        timed._sock.settimeout(1.0)
        self.assertFalse(ac._recv_frame(timed._sock)["ok"])
        timed.close()
        short.join()
        self.controllers.remove(short)

        oversized = self.controller(timeout=1.0)
        too_big = oversized.bind_agent("member", "mitglied")
        too_big._sock.sendall(struct.pack("!I", ac.MAX_FRAME + 1))
        self.assertFalse(ac._recv_frame(too_big._sock)["ok"])
        too_big.close()
        oversized.join()
        self.controllers.remove(oversized)

    def test_frame_deadline_is_total_and_idle_uses_session_deadline(self):
        slow = self.controller(timeout=0.05, session_timeout=1.0)
        client = slow.bind_agent("member", "mitglied")
        body = json.dumps({"op": "inbox.read", "payload": {}}, separators=(",", ":")).encode("utf-8")
        client._sock.sendall(struct.pack("!I", len(body)))
        for byte in body:
            try:
                client._sock.sendall(bytes([byte]))
            except OSError:
                break
            time.sleep(0.02)
        client._sock.settimeout(1.0)
        self.assertFalse(ac._recv_frame(client._sock)["ok"])
        client.close()
        slow.join()
        self.controllers.remove(slow)

        idle = self.controller(timeout=0.05, session_timeout=0.5)
        idle_client = idle.bind_agent("member", "mitglied")
        time.sleep(0.08)
        self.assertEqual(idle_client.request("inbox.read"), [])
        idle_client.close()
        idle.join()
        self.controllers.remove(idle)

    def test_client_closes_after_transport_failure(self):
        controller = self.controller()
        client = controller.bind_agent("member", "mitglied")
        controller.close()
        with self.assertRaises(ac.ControllerError):
            client.request("inbox.read")
        self.assertTrue(client._closed)
        controller.join()
        self.controllers.remove(controller)

    def test_bind_start_is_serialized_with_close_and_join(self):
        controller = self.controller(session_timeout=1.0)
        entered_start = threading.Event()
        release_start = threading.Event()
        close_started = threading.Event()
        close_done = threading.Event()
        errors = []
        original_start = threading.Thread.start

        def delayed_start(thread):
            if thread.name == "agents-controller":
                entered_start.set()
                if not release_start.wait(1.0):
                    raise RuntimeError("Teststart wurde nicht freigegeben")
            return original_start(thread)

        def bind():
            try:
                controller.bind_agent("member", "mitglied")
            except BaseException as exc:
                errors.append(exc)

        def close_and_join():
            close_started.set()
            try:
                controller.close()
                controller.join()
            except BaseException as exc:
                errors.append(exc)
            finally:
                close_done.set()

        with patch.object(threading.Thread, "start", delayed_start):
            binder = threading.Thread(target=bind)
            binder.start()
            self.assertTrue(entered_start.wait(1.0))
            closer = threading.Thread(target=close_and_join)
            closer.start()
            self.assertTrue(close_started.wait(1.0))
            time.sleep(0.02)
            self.assertFalse(close_done.is_set())
            release_start.set()
            binder.join(1.0)
            closer.join(1.0)
        self.assertFalse(errors)
        self.assertTrue(close_done.is_set())
        self.controllers.remove(controller)

    def test_disconnect_closes_explicit_controller_service(self):
        controller = self.controller()
        client = controller.bind_agent("member", "mitglied")
        client.close()
        controller.join(timeout=2.0)
        controller.close()


if __name__ == "__main__":
    unittest.main()
