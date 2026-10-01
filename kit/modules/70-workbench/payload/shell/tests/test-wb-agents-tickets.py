#!/usr/bin/env python3
"""Isolierte stdlib-Tests für die Ticketübergänge und die Bereitschaft (tickets1)."""

import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path

HERE = Path(__file__).resolve()
SHELL = HERE.parents[1]
sys.path.insert(0, str(SHELL))
import agents_controller as ac
import agents_data as ad
from herkunft_fixture import gebundene_governance, gemessener_mensch

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

import datetime as _dt
# Eine Weckzeit in der Zukunft relativ zur Uhr, damit die Suite nicht am Kalender kippt.
WECKZEIT = (_dt.datetime.now(_dt.timezone.utc).replace(microsecond=0)
            + _dt.timedelta(days=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
WECK_EPOCH = _dt.datetime.strptime(WECKZEIT, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=_dt.timezone.utc).timestamp()
_WEG = object()  # Merker für roh(): Feld entfernen


class _TicketBasis(unittest.TestCase):
    """Gemeinsame Weltaufstellung fuer die Ticketproben (tickets1 und tickets2)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-tickets-")
        self.world = Path(self.tmp.name) / "welt"
        ad.create_world(self.world, name="Tickets", main_name="main")
        self.member("m1")
        self.member("m2")

    def tearDown(self):
        self.tmp.cleanup()

    def member(self, agent_id, team=None, stage="mitglied"):
        return ad.create_agent(self.world, agent_id, stage, team, "Mitglied %s" % agent_id,
                               None, None, None, None, None, None, "lokal", "cli-operator", None)

    def ticket(self, ticket_id="t1", agent="m1", team=None, dependencies=None, sender="main",
               done_items=None, kind=None, priority=None, parent=None, origin=None, limits=None):
        rolle = "hauptagent" if sender == "main" else None
        return ad.create_ticket(self.world, "Titel %s" % ticket_id, "Ziel", "Fertig",
                                [agent] if agent else [], sender, rolle,
                                team=team, dependencies=dependencies, ticket_id=ticket_id,
                                done_items=done_items, kind=kind, priority=priority,
                                parent=parent, origin=origin, limits=limits)

    def roh(self, ticket_id, **aenderungen):
        """Bestand ohne tickets3-Felder: Felder direkt aus ticket.json nehmen oder setzen."""
        path = self.world / "tickets" / ticket_id / "ticket.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        for key, wert in aenderungen.items():
            if wert is _WEG:
                data.pop(key, None)
            else:
                data[key] = wert
        ad._write_json(path, data)
        return data

    def laeuft(self, ticket_id="t1", agent="m1"):
        ad.claim_ticket(self.world, ticket_id, agent, agent, "mitglied")

    def abnahme_reif(self, ticket_id="t1", agent="m1"):
        """Bringt ein Ticket per Ergebnis nach `zur Abnahme`."""
        self.laeuft(ticket_id, agent)
        ad.write_result(self.world, ticket_id, agent, "fertig %s" % ticket_id, None, agent, "mitglied")

    def zur_abnahme(self, ticket_id="t1", agent="m1"):
        self.abnahme_reif(ticket_id, agent)

    def events(self, ticket_id):
        return [json.loads(line) for line
                in (self.world / "tickets" / ticket_id / "verlauf.jsonl").read_text(encoding="utf-8").splitlines()]

    def welt_events(self):
        path = self.world / "verlauf.jsonl"
        if not path.exists():
            return []
        return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


class TicketTransitions(_TicketBasis):

    # Parken ------------------------------------------------------------------
    def test_park_from_running_sets_wartet_and_keeps_assignee(self):
        self.ticket()
        self.laeuft()
        parked = ad.park_ticket(self.world, "t1", "m1", "warte auf Antwort",
                                until=WECKZEIT, sender="m1", claimed_role="mitglied")
        self.assertEqual(parked["state"], "wartet")
        self.assertEqual(parked["assignee"], "m1")
        self.assertEqual((parked["parked"]["reason"], parked["parked"]["until"], parked["parked"]["by"]),
                         ("warte auf Antwort", WECKZEIT, "m1"))
        self.assertTrue(any(e["event"] == "geparkt" for e in self.events("t1")))

    def test_park_only_assignee_and_only_from_running(self):
        self.ticket()
        with self.assertRaises(ad.AgentsError):
            ad.park_ticket(self.world, "t1", "m1", "zu früh", until=WECKZEIT, sender="m1", claimed_role="mitglied")
        self.laeuft()
        with self.assertRaises(ad.AgentsError):
            ad.park_ticket(self.world, "t1", "m1", "falscher Akteur", until=WECKZEIT,
                           sender="m2", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.park_ticket(self.world, "t1", "m1", "Mensch parkt nicht", until=WECKZEIT, sender="mensch")

    def test_park_needs_exactly_one_wake_condition(self):
        self.ticket()
        self.laeuft()
        with self.assertRaises(ad.AgentsError):
            ad.park_ticket(self.world, "t1", "m1", "ohne Weckbedingung", sender="m1", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.park_ticket(self.world, "t1", "m1", "beide", until=WECKZEIT, waiting_for="t2",
                           sender="m1", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.park_ticket(self.world, "t1", "m1", "", until=WECKZEIT,
                           sender="m1", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.park_ticket(self.world, "t1", "m1", "keine Zeit", until="morgen", sender="m1", claimed_role="mitglied")

    def test_park_is_idempotent_and_rejects_other_args(self):
        self.ticket()
        self.laeuft()
        first = ad.park_ticket(self.world, "t1", "m1", "warte", until=WECKZEIT,
                               sender="m1", claimed_role="mitglied")
        second = ad.park_ticket(self.world, "t1", "m1", "warte", until=WECKZEIT,
                                sender="m1", claimed_role="mitglied")
        self.assertEqual(first, second)
        with self.assertRaises(ad.AgentsError):
            ad.park_ticket(self.world, "t1", "m1", "anders", until=WECKZEIT, sender="m1", claimed_role="mitglied")

    def test_park_waiting_for_must_exist_and_not_cycle(self):
        self.ticket("t2", agent="m2")
        self.ticket()
        self.laeuft()
        with self.assertRaises(ad.AgentsError):
            ad.park_ticket(self.world, "t1", "m1", "unbekannt", waiting_for="t-fehlt",
                           sender="m1", claimed_role="mitglied")
        parked = ad.park_ticket(self.world, "t1", "m1", "warte auf t2", waiting_for="t2",
                                sender="m1", claimed_role="mitglied")
        self.assertEqual(parked["parked"]["waiting_for"], "t2")
        ad.claim_ticket(self.world, "t2", "m2", "m2", "mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.park_ticket(self.world, "t2", "m2", "Zyklus", waiting_for="t1",
                           sender="m2", claimed_role="mitglied")

    def test_parked_ticket_frees_the_running_slot(self):
        self.ticket("t1")
        self.ticket("t2")
        self.laeuft("t1")
        ad.park_ticket(self.world, "t1", "m1", "warte", until=WECKZEIT, sender="m1", claimed_role="mitglied")
        claimed = ad.claim_ticket(self.world, "t2", "m1", "m1", "mitglied")
        self.assertEqual(claimed["state"], "läuft")

    # Wecken ------------------------------------------------------------------
    def test_wake_by_time_delivers_to_the_assignee(self):
        self.ticket()
        self.laeuft()
        ad.park_ticket(self.world, "t1", "m1", "bis morgen", until=WECKZEIT, sender="m1", claimed_role="mitglied")
        self.assertEqual(ad.wake_parked_tickets(self.world, WECK_EPOCH - 60), [])
        woke = ad.wake_parked_tickets(self.world, WECK_EPOCH)
        self.assertEqual(woke, ["t1"])
        ticket = ad.read_ticket(self.world, "t1")
        self.assertEqual((ticket["state"], ticket["return_to"]), ("offen", ["m1"]))
        self.assertNotIn("parked", ticket)
        delivery = ad.derived_id("ticket-wake", "t1", 1)
        stored = json.loads((self.world / "agents" / "m1" / "postfach" / (delivery + ".json")).read_text())
        self.assertFalse(stored["acknowledged"])
        self.assertTrue(any(e["event"] == "geweckt" for e in self.events("t1")))
        self.assertEqual(ad.wake_parked_tickets(self.world, WECK_EPOCH + 60), [])

    def test_wake_when_the_waited_ticket_is_approved(self):
        self.ticket("t1")
        self.ticket("t2", agent="m2")
        self.laeuft("t2", "m2")
        ad.park_ticket(self.world, "t2", "m2", "warte auf t1", waiting_for="t1",
                       sender="m2", claimed_role="mitglied")
        self.laeuft("t1")
        ad.write_result(self.world, "t1", "m1", "fertig", None, "m1", "mitglied")
        ad.approve_ticket(self.world, "t1", "main", "hauptagent", "passt")
        ticket = ad.read_ticket(self.world, "t2")
        self.assertEqual(ticket["state"], "offen")
        self.assertEqual(ticket["return_to"], ["m2"])
        self.assertTrue(any(e["event"] == "geweckt" for e in self.events("t2")))

    def test_wake_waiting_ticket_not_approved_before_its_time(self):
        self.ticket("t1")
        self.ticket("t2", agent="m2")
        self.laeuft("t2", "m2")
        ad.park_ticket(self.world, "t2", "m2", "warte auf t1", waiting_for="t1",
                       sender="m2", claimed_role="mitglied")
        self.assertEqual(ad.wake_parked_tickets(self.world, WECK_EPOCH + 60), [])
        self.assertEqual(ad.read_ticket(self.world, "t2")["state"], "wartet")

    # Zurückstellen aus der Triage --------------------------------------------
    def test_triage_park_stays_triage_and_wakes_back(self):
        self.ticket("t1", agent=None)
        parked = ad.park_ticket(self.world, "t1", "main", "später prüfen", until=WECKZEIT,
                                sender="main", claimed_role="hauptagent")
        self.assertEqual(parked["state"], "triage")
        self.assertEqual(parked["parked"]["by"], "main")
        with self.assertRaises(ad.AgentsError):
            ad.triage_accept(self.world, "t1", ["m1"], sender="main", claimed_role="hauptagent")
        with self.assertRaises(ad.AgentsError):
            ad.park_ticket(self.world, "t1", "m1", "kein Mitglied", until=WECKZEIT,
                           sender="m1", claimed_role="mitglied")
        self.assertEqual(ad.wake_parked_tickets(self.world, WECK_EPOCH + 1), ["t1"])
        ticket = ad.read_ticket(self.world, "t1")
        self.assertEqual(ticket["state"], "triage")
        self.assertNotIn("parked", ticket)

    # Braucht dich --------------------------------------------------------------
    def test_flag_sets_braucht_dich_with_question_and_reason(self):
        self.ticket()
        self.laeuft()
        question = ad.ask_question(self.world, "Welche Variante?", ticket_id="t1",
                                   sender="main", claimed_role="hauptagent")
        flagged = ad.flag_ticket(self.world, "t1", question["id"], "Entscheidung fehlt",
                                 sender="main", claimed_role="hauptagent")
        self.assertEqual(flagged["state"], "braucht dich")
        self.assertEqual((flagged["flag"]["question"], flagged["flag"]["reason"], flagged["flag"]["by"]),
                         (question["id"], "Entscheidung fehlt", "main"))
        self.assertTrue(any(e["event"] == "braucht-dich" for e in self.events("t1")))

    def test_flag_only_main_agent_and_only_open_question(self):
        self.ticket()
        self.laeuft()
        question = ad.ask_question(self.world, "Welche Variante?", ticket_id="t1",
                                   sender="main", claimed_role="hauptagent")
        with self.assertRaises(ad.AgentsError):
            ad.flag_ticket(self.world, "t1", question["id"], "kein Hauptagent",
                           sender="m1", claimed_role="mitglied")
        flagged = ad.flag_ticket(self.world, "t1", question["id"], "Entscheidung fehlt",
                                 sender="main", claimed_role="hauptagent")
        self.assertEqual(flagged["state"], "braucht dich")
        with self.assertRaises(ad.AgentsError):
            ad.flag_ticket(self.world, "t1", question["id"], "Frage schon vermerkt",
                           sender="main", claimed_role="hauptagent")
        ad.answer_question(self.world, question["id"], "Variante A", "mensch", None)
        with self.assertRaises(ad.AgentsError):
            ad.flag_ticket(self.world, "t1", question["id"], "Frage beantwortet",
                           sender="main", claimed_role="hauptagent")

    def test_flag_from_wartet_and_idempotent(self):
        self.ticket()
        self.laeuft()
        ad.park_ticket(self.world, "t1", "m1", "wartet eh", until=WECKZEIT, sender="m1", claimed_role="mitglied")
        question = ad.ask_question(self.world, "Weiter so?", ticket_id="t1",
                                   sender="main", claimed_role="hauptagent")
        first = ad.flag_ticket(self.world, "t1", question["id"], "brauche Antwort",
                               sender="main", claimed_role="hauptagent")
        second = ad.flag_ticket(self.world, "t1", question["id"], "brauche Antwort",
                                sender="main", claimed_role="hauptagent")
        self.assertEqual(first, second)
        self.assertEqual(first["state"], "braucht dich")
        self.assertNotIn("parked", first)

    def test_answer_question_reopens_the_flagged_ticket_to_the_assignee(self):
        self.ticket()
        self.laeuft()
        question = ad.ask_question(self.world, "Welche Variante?", ticket_id="t1",
                                   sender="main", claimed_role="hauptagent")
        ad.flag_ticket(self.world, "t1", question["id"], "Entscheidung fehlt",
                       sender="main", claimed_role="hauptagent")
        ad.answer_question(self.world, question["id"], "Variante A", "mensch", None)
        ticket = ad.read_ticket(self.world, "t1")
        self.assertEqual((ticket["state"], ticket["return_to"]), ("offen", ["m1"]))
        self.assertNotIn("flag", ticket)
        delivery = ad.derived_id("ticket-flag", "t1", question["id"])
        self.assertTrue((self.world / "agents" / "m1" / "postfach" / (delivery + ".json")).exists())
        self.assertTrue(any(e["event"] == "beantwortet" for e in self.events("t1")))

    # Verwerfen -----------------------------------------------------------------
    def test_discard_sets_verworfen_and_acknowledges_open_deliveries(self):
        self.ticket()
        delivery = ad.derived_id("ticket", "t1")
        discarded = ad.discard_ticket(self.world, "t1", "nicht-mehr-noetig", "nicht mehr gebraucht",
                                      sender="main", claimed_role="hauptagent")
        self.assertEqual(discarded["state"], "verworfen")
        self.assertEqual((discarded["discard"]["code"], discarded["discard"]["by"]),
                         ("nicht-mehr-noetig", "main"))
        stored = json.loads((self.world / "agents" / "m1" / "postfach" / (delivery + ".json")).read_text())
        self.assertTrue(stored["acknowledged"])
        self.assertTrue(any(e["event"] == "verworfen" for e in self.events("t1")))

    def test_discard_only_sender_main_or_human_and_never_from_approved(self):
        self.ticket(agent="m1", sender="m1")
        discarded = ad.discard_ticket(self.world, "t1", "abgelehnt", "passt nicht", sender="m1",
                                      claimed_role="mitglied")
        self.assertEqual(discarded["state"], "verworfen")
        self.ticket("t2", agent="m2", sender="m2")
        with self.assertRaises(ad.AgentsError):
            ad.discard_ticket(self.world, "t2", "abgelehnt", "fremd", sender="m1", claimed_role="mitglied")
        self.laeuft("t2", "m2")
        ad.write_result(self.world, "t2", "m2", "fertig", None, "m2", "mitglied")
        ad.approve_ticket(self.world, "t2", "main", "hauptagent", "gut")
        with self.assertRaises(ad.AgentsError):
            ad.discard_ticket(self.world, "t2", "nicht-mehr-noetig", "zu spät",
                              sender="main", claimed_role="hauptagent")

    def test_discard_reason_catalog_and_duplicate_rule(self):
        self.ticket()
        with self.assertRaises(ad.AgentsError):
            ad.discard_ticket(self.world, "t1", "egal", None, sender="main", claimed_role="hauptagent")
        with self.assertRaises(ad.AgentsError):
            ad.discard_ticket(self.world, "t1", "duplikat", None, sender="main", claimed_role="hauptagent")
        with self.assertRaises(ad.AgentsError):
            ad.discard_ticket(self.world, "t1", "duplikat", None, duplicate_of="t1",
                              sender="main", claimed_role="hauptagent")
        with self.assertRaises(ad.AgentsError):
            ad.discard_ticket(self.world, "t1", "duplikat", None, duplicate_of="t-fehlt",
                              sender="main", claimed_role="hauptagent")

    def test_duplicate_marks_the_original(self):
        original = self.ticket("t1")
        duplicate = self.ticket("t2")
        discarded = ad.discard_ticket(self.world, "t2", "duplikat", "gleiches Thema",
                                      duplicate_of="t1", sender="main", claimed_role="hauptagent")
        self.assertEqual(discarded["duplicate_of"], "t1")
        self.assertEqual(original["state"], "offen")
        reported = [e for e in self.events("t1") if e["event"] == "duplikat-gemeldet"]
        self.assertEqual([e.get("duplikat") for e in reported], ["t2"])

    def test_discard_is_idempotent_and_rejects_other_args(self):
        self.ticket()
        first = ad.discard_ticket(self.world, "t1", "abgelehnt", "nein", sender="main", claimed_role="hauptagent")
        second = ad.discard_ticket(self.world, "t1", "abgelehnt", "nein", sender="main", claimed_role="hauptagent")
        self.assertEqual(first, second)
        with self.assertRaises(ad.AgentsError):
            ad.discard_ticket(self.world, "t1", "nicht-reproduzierbar", "anders",
                              sender="main", claimed_role="hauptagent")

    def test_discarded_dependency_blocks_claim_and_notifies_dependents(self):
        self.ticket("t1")
        self.ticket("t2", dependencies=["t1"])
        ad.discard_ticket(self.world, "t1", "nicht-reproduzierbar", None, sender="main",
                          claimed_role="hauptagent")
        self.assertEqual(ad.read_ticket(self.world, "t2")["state"], "offen")
        self.assertTrue(any(e["event"] == "abhaengigkeit-verworfen" for e in self.events("t2")))
        with self.assertRaises(ad.AgentsError) as caught:
            ad.claim_ticket(self.world, "t2", "m2", "m2", "mitglied")
        self.assertIn("verworfen", str(caught.exception))
        entries = ad.ready_tickets(self.world)
        reason = next(e["reason"] for e in entries if e["id"] == "t2")
        self.assertEqual(reason, "abhaengigkeit t1 verworfen")

    # Umadressieren --------------------------------------------------------------
    def test_reassign_before_running_delivers_new_and_quits_old(self):
        self.ticket()
        old = ad.derived_id("ticket", "t1")
        reassigned = ad.reassign_ticket(self.world, "t1", ["m2"], reason="falscher Adressat",
                                        sender="main", claimed_role="hauptagent")
        self.assertEqual((reassigned["recipients"], reassigned["state"]), (["m2"], "offen"))
        stored = json.loads((self.world / "agents" / "m1" / "postfach" / (old + ".json")).read_text())
        self.assertTrue(stored["acknowledged"])
        new_delivery = ad.derived_id("ticket-reassign", "t1", 1)
        self.assertTrue((self.world / "agents" / "m2" / "postfach" / (new_delivery + ".json")).exists())
        self.assertTrue(any(e["event"] == "umadressiert" for e in self.events("t1")))

    def test_reassign_from_running_only_by_the_assignee(self):
        self.ticket()
        self.laeuft("t1", "m1")
        with self.assertRaises(ad.AgentsError):
            ad.reassign_ticket(self.world, "t1", ["m2"], reason="nicht der Bearbeiter",
                               sender="main", claimed_role="hauptagent")
        reassigned = ad.reassign_ticket(self.world, "t1", ["m2"], reason="übergeben",
                                        sender="m1", claimed_role="mitglied")
        self.assertEqual((reassigned["state"], reassigned["assignee"]), ("offen", None))

    def test_reassign_needs_reason_and_recipients(self):
        self.ticket()
        with self.assertRaises(ad.AgentsError):
            ad.reassign_ticket(self.world, "t1", [], reason=None, sender="main", claimed_role="hauptagent")
        with self.assertRaises(ad.AgentsError):
            ad.reassign_ticket(self.world, "t1", ["m2"], reason=None, sender="main", claimed_role="hauptagent")

    def test_reassign_is_idempotent(self):
        self.ticket()
        first = ad.reassign_ticket(self.world, "t1", ["m2"], reason="falscher Adressat",
                                   sender="main", claimed_role="hauptagent")
        second = ad.reassign_ticket(self.world, "t1", ["m2"], reason="falscher Adressat",
                                    sender="main", claimed_role="hauptagent")
        self.assertEqual(second["reassign_revision"], 1)
        self.assertEqual(first["reassign"]["reason"], "falscher Adressat")
        with self.assertRaises(ad.AgentsError):
            ad.reassign_ticket(self.world, "t1", [], team=None, reason=None, sender="main", claimed_role="hauptagent")

    # Abnahme mit Grund -----------------------------------------------------------
    def test_approve_reason_code_defaults_and_partly_needs_note(self):
        self.ticket()
        self.laeuft()
        ad.write_result(self.world, "t1", "m1", "fertig", None, "m1", "mitglied")
        approved = ad.approve_ticket(self.world, "t1", "main", "hauptagent", "passt")
        self.assertEqual(approved["approval"]["reason_code"], "erledigt")
        self.ticket("t2", agent="m2")
        self.laeuft("t2", "m2")
        ad.write_result(self.world, "t2", "m2", "halbfertig", None, "m2", "mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.approve_ticket(self.world, "t2", "main", "hauptagent", None, reason_code="teilweise")
        partly = ad.approve_ticket(self.world, "t2", "main", "hauptagent", "Rest fehlt",
                                   reason_code="teilweise")
        self.assertEqual(partly["approval"]["reason_code"], "teilweise")
        self.ticket("t3")
        self.laeuft("t3")
        ad.write_result(self.world, "t3", "m1", "fertig", None, "m1", "mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.approve_ticket(self.world, "t3", "main", "hauptagent", None, reason_code="egal")

    # Triage ------------------------------------------------------------------------
    def test_ticket_without_recipients_lands_in_triage_at_the_main_agent(self):
        ticket = self.ticket("t1", agent=None)
        self.assertEqual((ticket["state"], ticket["recipients"]), ("triage", ["main"]))
        self.assertFalse((self.world / "agents" / "main" / "postfach" / (ad.derived_id("ticket", "t1") + ".json")).exists())
        with self.assertRaises(ad.AgentsError):
            ad.claim_ticket(self.world, "t1", "main", "main", "hauptagent")

    def test_ticket_without_recipients_needs_a_main_agent_field(self):
        world_file = self.world / "world.json"
        world = json.loads(world_file.read_text(encoding="utf-8"))
        world["hauptagent"] = None
        world_file.write_text(json.dumps(world), encoding="utf-8")
        with self.assertRaises(ad.AgentsError):
            self.ticket("t1", agent=None)

    def test_triage_accept_addresses_and_carries_priority_and_kind(self):
        self.ticket("t1", agent=None)
        accepted = ad.triage_accept(self.world, "t1", ["m1"], priority=2, kind="fehler",
                                    sender="main", claimed_role="hauptagent")
        self.assertEqual((accepted["state"], accepted["recipients"], accepted["team"]),
                         ("offen", ["m1"], None))
        self.assertEqual((accepted["priority"], accepted["kind"]), (2, "fehler"))
        delivery = ad.derived_id("ticket-triage", "t1")
        self.assertTrue((self.world / "agents" / "m1" / "postfach" / (delivery + ".json")).exists())
        self.assertTrue(any(e["event"] == "angenommen" for e in self.events("t1")))
        repeated = ad.triage_accept(self.world, "t1", ["m1"], priority=2, kind="fehler",
                                    sender="main", claimed_role="hauptagent")
        self.assertEqual(repeated["triage"]["by"], "main")

    def test_triage_accept_only_main_agent_or_human(self):
        self.ticket("t1", agent=None)
        with self.assertRaises(ad.AgentsError):
            ad.triage_accept(self.world, "t1", ["m1"], sender="m1", claimed_role="mitglied")
        accepted = ad.triage_accept(self.world, "t1", ["m1"], kind="recherche", sender="mensch")
        self.assertEqual(accepted["recipients"], ["m1"])

    # Bereitschaft -------------------------------------------------------------------
    def test_ready_lists_ready_tickets_and_every_blocker_reason(self):
        self.member("m3", team="dev")
        self.ticket("t-bereit", agent="m1", done_items=["fertig"])
        self.ticket("t-besetzt", agent="m2")
        self.laeuft("t-besetzt", "m2")
        self.ticket("t-parked", agent="m1")
        self.laeuft("t-parked", "m1")
        ad.park_ticket(self.world, "t-parked", "m1", "wartet", until=WECKZEIT,
                       sender="m1", claimed_role="mitglied")
        self.ticket("t-dependency", agent="m1", dependencies=["t-besetzt"])
        self.ticket("t1", agent="m1")
        ad.discard_ticket(self.world, "t1", "abgelehnt", None, sender="main", claimed_role="hauptagent")
        self.ticket("t-verworfen", agent="m1", dependencies=["t1"])
        self.ticket("t-triage", agent=None)
        entries = {e["id"]: e for e in ad.ready_tickets(self.world)}
        self.assertTrue(entries["t-bereit"]["ready"])
        self.assertEqual(entries["t-besetzt"]["reason"], "besetzt: Agent bearbeitet t-besetzt")
        self.assertEqual(entries["t-parked"]["reason"], "geparkt bis %s" % WECKZEIT)
        self.assertEqual(entries["t-dependency"]["reason"], "abhaengigkeit t-besetzt ist läuft")
        self.assertEqual(entries["t-verworfen"]["reason"], "abhaengigkeit t1 verworfen")
        self.assertEqual(entries["t-triage"]["reason"], "triage")
        self.assertEqual(entries["t1"]["reason"], "verworfen")
        # Definition of Ready (Satz 45): ein Task ohne Fertig-Liste ist nicht bereit.
        self.ticket("t-liste-fehlt", agent="m1", kind="task")
        entries = {e["id"]: e for e in ad.ready_tickets(self.world)}
        self.assertEqual(entries["t-liste-fehlt"]["reason"], "fehlende Fertig-Liste")
        # Die Vorgabe-Art auftrag kennt keinen Fertig-Listen-Zwang (Orchestrator-Tickets).
        self.ticket("t-auftrag", agent="m1")
        entries = {e["id"]: e for e in ad.ready_tickets(self.world)}
        self.assertNotEqual(entries["t-auftrag"]["reason"], "fehlende Fertig-Liste")

    def test_ready_world_and_agent_pause_block(self):
        self.ticket("t1", agent="m1")
        ad.set_world_state(self.world, "pausiert", "Probe", "mensch", None)
        reason = next(e["reason"] for e in ad.ready_tickets(self.world) if e["id"] == "t1")
        self.assertEqual(reason, "welt pausiert")
        ad.set_world_state(self.world, "läuft", None, "mensch", None)
        ad.set_agent_state(self.world, "m1", "pausiert", "Probe", "mensch", None)
        reason = next(e["reason"] for e in ad.ready_tickets(self.world) if e["id"] == "t1")
        self.assertEqual(reason, "agent pausiert")

    def test_ready_addressee_busy_with_another_ticket(self):
        self.ticket("t1", agent="m1")
        self.ticket("t2", agent="m1")
        self.laeuft("t1", "m1")
        reason = next(e["reason"] for e in ad.ready_tickets(self.world) if e["id"] == "t2")
        self.assertEqual(reason, "agent bearbeitet t1")

    def test_ready_sorts_by_priority_then_created_then_id(self):
        self.ticket("t-a")
        self.ticket("t-b")
        self.ticket("t-c", agent=None)
        ad.triage_accept(self.world, "t-c", ["m1"], priority=1, kind="recherche",
                         sender="main", claimed_role="hauptagent")
        order = [e["id"] for e in ad.ready_tickets(self.world)]
        self.assertEqual(order, ["t-c", "t-a", "t-b"])

    def test_free_delivery_after_approval_exactly_once(self):
        self.ticket("t1")
        self.ticket("t2", agent="m2", dependencies=["t1"])
        old = ad.derived_id("ticket", "t2")
        ad.acknowledge(self.world, "m2", old, "m2", "mitglied")
        self.laeuft("t1")
        ad.write_result(self.world, "t1", "m1", "fertig", None, "m1", "mitglied")
        approved = ad.approve_ticket(self.world, "t1", "main", "hauptagent", "passt")
        free_id = ad.derived_id("ticket-free", "t2", "t1", approved["approval"]["time"])
        self.assertTrue((self.world / "agents" / "m2" / "postfach" / (free_id + ".json")).exists())
        events = self.events("t2")
        self.assertEqual(sum(1 for e in events if e["event"] == "frei"), 1)
        ad.wake_parked_tickets(self.world, WECK_EPOCH)
        self.assertEqual(sum(1 for e in self.events("t2") if e["event"] == "frei"), 1)
        ad.set_world_state(self.world, "pausiert", "Restart", "mensch", None)
        ad.set_world_state(self.world, "läuft", None, "mensch", None)
        self.assertEqual(sum(1 for e in self.events("t2") if e["event"] == "frei"), 1)

    # Ansicht --------------------------------------------------------------------------
    def test_snapshot_carries_the_ticket_counters(self):
        self.ticket("t1")
        self.ticket("t2", agent="m2")
        self.laeuft("t2", "m2")
        self.ticket("t3", agent=None)
        snapshot = ad.world_snapshot(self.world)
        self.assertEqual((snapshot["tickets_braucht_dich"], snapshot["tickets_triage"],
                          snapshot["tickets_laufen"], snapshot["tickets_offen"]), (0, 1, 1, 1))


class ZwischenstandTests(_TicketBasis):
    """Zwischenstände (Plan AGENTS-TICKETS-PLAN, Saetze 15 und 16)."""

    def test_note_from_running_and_waiting_writes_history_without_state_change(self):
        self.ticket()
        self.laeuft()
        noted = ad.note_ticket(self.world, "t1", "m1", "Erste Recherche fertig, Code folgt",
                               sender="m1", claimed_role="mitglied")
        self.assertEqual(noted["state"], "läuft")
        self.laeuft_wartet = None
        ad.park_ticket(self.world, "t1", "m1", "warte", until=WECKZEIT, sender="m1", claimed_role="mitglied")
        ad.note_ticket(self.world, "t1", "m1", "warte auf Freigabe", sender="m1", claimed_role="mitglied")
        events = [e for e in self.events("t1") if e["event"] == "zwischenstand"]
        self.assertEqual([e["text"] for e in events],
                         ["Erste Recherche fertig, Code folgt", "warte auf Freigabe"])
        self.assertEqual([e["actor"]["id"] for e in events], ["m1", "m1"])
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "wartet")

    def test_note_only_assignee_and_only_from_laeuft_or_wartet(self):
        self.ticket()
        with self.assertRaises(ad.AgentsError):
            ad.note_ticket(self.world, "t1", "m1", "zu frueh", sender="m1", claimed_role="mitglied")
        self.laeuft()
        with self.assertRaises(ad.AgentsError):
            ad.note_ticket(self.world, "t1", "m1", "falscher Agent", sender="m2", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.note_ticket(self.world, "t1", "m1", "fremder Agent", sender="m2", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.note_ticket(self.world, "t1", "m1", "kein Mensch", sender="mensch")
        ad.note_ticket(self.world, "t1", "m1", "ok", sender="m1", claimed_role="mitglied")
        self.abnahme_reif("t1")
        with self.assertRaises(ad.AgentsError):
            ad.note_ticket(self.world, "t1", "m1", "zu spaet", sender="m1", claimed_role="mitglied")

    def test_note_limit_and_empty_text(self):
        self.ticket()
        self.laeuft()
        with self.assertRaises(ad.AgentsError):
            ad.note_ticket(self.world, "t1", "m1", "", sender="m1", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.note_ticket(self.world, "t1", "m1", "x" * 2001, sender="m1", claimed_role="mitglied")
        ad.note_ticket(self.world, "t1", "m1", "x" * 2000, sender="m1", claimed_role="mitglied")
        self.assertEqual(len(self.events("t1")[-1]["text"]), 2000)

    def test_carrier_note_and_turn_report(self):
        self.ticket()
        self.laeuft()
        self.assertEqual(len(self.events("t1")), 2)
        self.assertFalse(ad.ticket_turn_reported(self.world, "t1", 2))
        ad.carrier_turn_note(self.world, "t1", "zug-x", "ergebnis_fehlt")
        self.assertTrue(ad.ticket_turn_reported(self.world, "t1", 2))
        entry = self.events("t1")[-1]
        self.assertEqual((entry["event"], entry["text"], entry["zug"], entry["ausgang"]),
                         ("zwischenstand", "Zug ohne Bericht (Träger)", "zug-x", "ergebnis_fehlt"))
        ad.carrier_turn_note(self.world, "t1", "zug-x", "ergebnis_fehlt")
        self.assertEqual(sum(1 for e in self.events("t1")
                             if e["event"] == "zwischenstand" and e.get("zug") == "zug-x"), 1)
        # Ein eigener Übergang des Bearbeiters gilt ebenfalls als Bericht.
        self.laeuft()
        stand = len(self.events("t1"))
        ad.park_ticket(self.world, "t1", "m1", "warte", until=WECKZEIT, sender="m1", claimed_role="mitglied")
        self.assertTrue(ad.ticket_turn_reported(self.world, "t1", stand, "m1"))
        # Ein Uebergang eines anderen Akteurs gilt nicht als Bericht des Bearbeiters.
        ad.wake_parked_tickets(self.world, WECK_EPOCH)
        stand = len(self.events("t1"))
        ad.discard_ticket(self.world, "t1", "abgelehnt", None, sender="main", claimed_role="hauptagent")
        self.assertFalse(ad.ticket_turn_reported(self.world, "t1", stand, "m1"))


class FertigListeTests(_TicketBasis):
    """Fertig-Liste und Abhaken (Plan Satz 2)."""

    PUNKTE = ["Analyse dokumentiert", "Tests gruen", "Doku nachgezogen"]

    def test_create_stores_unchecked_list_and_write_result_blocks_with_names(self):
        self.ticket(done_items=self.PUNKTE)
        self.laeuft()
        ad.check_done_item(self.world, "t1", "m1", 1, sender="m1", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError) as caught:
            ad.write_result(self.world, "t1", "m1", "fertig", None, "m1", "mitglied")
        self.assertIn("offene Punkte", str(caught.exception))
        self.assertIn("Tests gruen", str(caught.exception))
        self.assertIn("Doku nachgezogen", str(caught.exception))
        self.assertNotIn("Analyse dokumentiert", str(caught.exception))
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "läuft")

    def test_check_done_item_idempotent_only_assignee_and_bounds(self):
        self.ticket(done_items=self.PUNKTE)
        with self.assertRaises(ad.AgentsError):
            ad.check_done_item(self.world, "t1", "m1", 1, sender="m1", claimed_role="mitglied")
        self.laeuft()
        with self.assertRaises(ad.AgentsError):
            ad.check_done_item(self.world, "t1", "m1", 1, sender="m2", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.check_done_item(self.world, "t1", "m1", 0, sender="m1", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.check_done_item(self.world, "t1", "m1", 4, sender="m1", claimed_role="mitglied")
        first = ad.check_done_item(self.world, "t1", "m1", 2, sender="m1", claimed_role="mitglied")
        second = ad.check_done_item(self.world, "t1", "m1", 2, sender="m1", claimed_role="mitglied")
        self.assertEqual(first, second)
        item = second["done_items"][1]
        self.assertEqual((item["done"], item["by"]), (True, "m1"))
        self.assertTrue(item["at"])
        events = [e for e in self.events("t1") if e["event"] == "fertig-gehaekt"]
        self.assertEqual(len(events), 1)
        back = ad.check_done_item(self.world, "t1", "m1", 2, done=False, sender="m1", claimed_role="mitglied")
        self.assertFalse(back["done_items"][1]["done"])
        self.assertTrue(any(e["event"] == "fertig-zurueck" for e in self.events("t1")))

    def test_third_tick_unlocks_the_result_and_list_stays_immutable(self):
        self.ticket(done_items=self.PUNKTE)
        self.laeuft()
        for index in (1, 2, 3):
            ad.check_done_item(self.world, "t1", "m1", index, sender="m1", claimed_role="mitglied")
        written = ad.write_result(self.world, "t1", "m1", "fertig", None, "m1", "mitglied")
        self.assertEqual(written["state"], "zur Abnahme")
        items = [dict(item) for item in written["done_items"]]
        with self.assertRaises(ad.AgentsError):
            ad.check_done_item(self.world, "t1", "m1", 1, done=False, sender="m1", claimed_role="mitglied")
        self.assertEqual([dict(item) for item in ad.read_ticket(self.world, "t1")["done_items"]], items)

    def test_empty_list_and_no_list_do_not_block(self):
        self.ticket(done_items=[])
        self.abnahme_reif("t1")
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "zur Abnahme")
        self.ticket("t2")
        self.abnahme_reif("t2")
        self.assertEqual(ad.read_ticket(self.world, "t2")["state"], "zur Abnahme")

    def test_triage_accept_sets_list_only_while_missing(self):
        self.ticket("t1", agent=None)
        with self.assertRaises(ad.AgentsError):
            ad.triage_accept(self.world, "t1", ["m1"], done_items=["", " "], sender="main",
                             claimed_role="hauptagent")
        accepted = ad.triage_accept(self.world, "t1", ["m1"], done_items=self.PUNKTE, sender="main",
                                    claimed_role="hauptagent")
        self.assertEqual([item["text"] for item in accepted["done_items"]], self.PUNKTE)
        self.assertEqual([item["done"] for item in accepted["done_items"]], [False, False, False])
        self.ticket("t2", agent=None, done_items=["schon da"])
        with self.assertRaises(ad.AgentsError):
            ad.triage_accept(self.world, "t2", ["m1"], done_items=["anders"], sender="main",
                             claimed_role="hauptagent")

    def test_haken_cli(self):
        self.ticket(done_items=self.PUNKTE)
        helper = _TicketCliHelper(self.world)
        helper("wb-ticket", "uebernehmen", self.world, "t1", "--agent", "m1", "--absender", "m1")
        helper("wb-ticket", "haken", self.world, "t1", "--agent", "m1", "1", "--absender", "m1")
        with self.assertRaises(AssertionError):
            helper("wb-ticket", "ergebnis", self.world, "t1", "--agent", "m1", "--text", "fertig",
                   "--absender", "m1")
        helper("wb-ticket", "haken", self.world, "t1", "--agent", "m1", "2", "--zurueck",
               "--absender", "m1")
        helper("wb-ticket", "haken", self.world, "t1", "--agent", "m1", "2", "--absender", "m1")
        helper("wb-ticket", "haken", self.world, "t1", "--agent", "m1", "3", "--absender", "m1")
        done = helper("wb-ticket", "ergebnis", self.world, "t1", "--agent", "m1", "--text", "fertig",
                      "--absender", "m1")
        self.assertEqual(done["state"], "zur Abnahme")


class _TicketCliHelper:
    """Duenner Aufrufer fuer die wb-Werkzeuge in den Datenschichtenproben."""

    def __init__(self, world):
        self.world = world

    def __call__(self, tool, *args):
        return _in_process_cli(tool, *args)


def _in_process_cli(tool, *args):
    stdout, stderr = StringIO(), StringIO()
    with redirect_stdout(stdout), redirect_stderr(stderr):
        status = ad.run(tool.removeprefix("wb-"), [*map(str, args), "--json"])
    if status != 0:
        raise AssertionError("%s fehlgeschlagen: %s" % (tool, stderr.getvalue().strip()[-300:]))
    return json.loads(stdout.getvalue())


class DefinitionOfDoneTests(_TicketBasis):
    """Definition of Done je Welt (AGENTS-TICKETS-AGIL Abschnitt 6, Satz 49)."""

    DOD = ["Tests laufen", "Doku aktualisiert"]

    def test_set_by_human_and_main_replaces_with_world_event(self):
        world = ad.set_definition_of_done(self.world, self.DOD, sender="mensch")
        self.assertEqual(world["definition_of_done"], self.DOD)
        ad.set_definition_of_done(self.world, self.DOD, sender="mensch")
        self.assertEqual(len([e for e in self.welt_events() if e["event"] == "dod-gesetzt"]), 1)
        world = ad.set_definition_of_done(self.world, ["Nur eins"], sender="main", claimed_role="hauptagent")
        self.assertEqual(world["definition_of_done"], ["Nur eins"])
        events = [e for e in self.welt_events() if e["event"] == "dod-gesetzt"]
        self.assertEqual(events[-1]["actor"]["id"], "main")

    def test_only_human_or_main_and_points_must_be_texts(self):
        with self.assertRaises(ad.AgentsError):
            ad.set_definition_of_done(self.world, self.DOD, sender="m1", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.set_definition_of_done(self.world, ["ok", ""], sender="mensch")
        with self.assertRaises(ad.AgentsError):
            ad.set_definition_of_done(self.world, [42], sender="mensch")
        cleared = ad.set_definition_of_done(self.world, [], sender="mensch")
        self.assertEqual(cleared["definition_of_done"], [])

    def test_approval_requires_the_dod_confirmation(self):
        ad.set_definition_of_done(self.world, self.DOD, sender="mensch")
        self.ticket("t1")
        self.abnahme_reif("t1")
        with self.assertRaises(ad.AgentsError) as caught:
            ad.approve_ticket(self.world, "t1", "main", "hauptagent", "passt")
        self.assertEqual(str(caught.exception), "Definition of Done nicht bestätigt")
        approved = ad.approve_ticket(self.world, "t1", "main", "hauptagent", "passt", dod_checked=True)
        self.assertEqual(approved["state"], "abgenommen")
        self.assertEqual(approved["approval"]["reason_code"], "erledigt")

    def test_approval_without_dod_and_return_need_no_confirmation(self):
        self.ticket("t1")
        self.abnahme_reif("t1")
        approved = ad.approve_ticket(self.world, "t1", "main", "hauptagent", "passt")
        self.assertEqual(approved["state"], "abgenommen")
        self.ticket("t2")
        self.abnahme_reif("t2")
        returned = ad.approve_ticket(self.world, "t2", "main", "hauptagent", "Der Test fehlt", accept=False)
        self.assertEqual(returned["state"], "zurückgegeben")

    def test_cli_dod_and_abnahme_dod_geprueft(self):
        helper = _TicketCliHelper(self.world)
        helper("wb-welt", "dod", self.world, "setzen", "--punkt", self.DOD[0], "--punkt", self.DOD[1],
               "--absender", "mensch")
        env = dict(os.environ, PYTHONPATH=str(HERE.parents[1]))
        result = subprocess.run([str(HERE.parents[1] / "wb-welt"), "dod", str(self.world), "zeigen"],
                                text=True, capture_output=True, env=env, timeout=60)
        self.assertEqual(result.stdout.splitlines(), ["- %s" % self.DOD[0], "- %s" % self.DOD[1]])
        self.ticket("t1")
        self.abnahme_reif("t1")
        with self.assertRaises(AssertionError):
            helper("wb-ticket", "abnehmen", self.world, "t1", "--absender", "main")
        approved = helper("wb-ticket", "abnehmen", self.world, "t1", "--absender", "main",
                          "--dod-geprueft")
        self.assertEqual(approved["state"], "abgenommen")


class PruefungTests(_TicketBasis):
    """Pruefer und Pruefnotiz (Plan Saetze 25 und 26)."""

    def reif(self, ticket_id="t1", agent="m1"):
        self.ticket(ticket_id, agent=agent)
        self.abnahme_reif(ticket_id, agent)
        return ad.read_ticket(self.world, ticket_id)

    def test_review_moves_to_in_pruefung_with_fields_and_delivery(self):
        self.reif()
        reviewed = ad.review_ticket(self.world, "t1", "m2", sender="main", claimed_role="hauptagent")
        self.assertEqual(reviewed["state"], "in Prüfung")
        self.assertEqual((reviewed["review"]["reviewer"], reviewed["review"]["revision"],
                          reviewed["review"]["requested_by"], reviewed["review"]["note"]),
                         ("m2", 1, "main", None))
        self.assertTrue(reviewed["review"]["at"])
        delivery = ad.derived_id("ticket-review", "t1", 1)
        stored = json.loads((self.world / "agents" / "m2" / "postfach" / (delivery + ".json")).read_text())
        self.assertEqual((stored["kind"], stored["ticket_id"], stored["sender"], stored["acknowledged"]),
                         ("ticket-review", "t1", "main", False))
        self.assertTrue(any(e["event"] == "pruefung-angefordert" for e in self.events("t1")))

    def test_review_rules(self):
        self.reif()
        with self.assertRaises(ad.AgentsError):
            ad.review_ticket(self.world, "t1", "m2", sender="m1", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.review_ticket(self.world, "t1", "m1", sender="main", claimed_role="hauptagent")
        ad.set_agent_state(self.world, "m2", "pausiert", "Probe", "mensch", None)
        with self.assertRaises(ad.AgentsError):
            ad.review_ticket(self.world, "t1", "m2", sender="main", claimed_role="hauptagent")
        ad.set_agent_state(self.world, "m2", "aktiv", None, "mensch", None)
        first = ad.review_ticket(self.world, "t1", "m2", sender="main", claimed_role="hauptagent")
        second = ad.review_ticket(self.world, "t1", "m2", sender="main", claimed_role="hauptagent")
        self.assertEqual(first, second)

    def test_review_once_per_revision_and_again_after_new_result(self):
        self.reif()
        ad.review_ticket(self.world, "t1", "m2", sender="main", claimed_role="hauptagent")
        # Dieselbe Revision wird nur einmal geprüft; ein anderer Prüfer kommt zu spät.
        with self.assertRaises(ad.AgentsError):
            ad.review_ticket(self.world, "t1", "main", sender="main", claimed_role="hauptagent")
        ad.review_result(self.world, "t1", "m2", "passt", "bestanden", sender="m2", claimed_role="mitglied")
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "zur Abnahme")
        # Nach der Rückgabe schreibt der Bearbeiter eine neue Revision; die alte Prüfung fällt weg.
        ad.approve_ticket(self.world, "t1", "main", "hauptagent", "Der Test fehlt", accept=False)
        ad.claim_ticket(self.world, "t1", "m1", "m1", "mitglied")
        ad.write_result(self.world, "t1", "m1", "ueberarbeitet", None, "m1", "mitglied")
        ticket = ad.read_ticket(self.world, "t1")
        self.assertEqual((ticket["result_revision"], ticket.get("review")), (2, None))
        reviewed = ad.review_ticket(self.world, "t1", "m2", sender="main", claimed_role="hauptagent")
        self.assertEqual(reviewed["review"]["revision"], 2)

    def test_review_result_rules_and_delivery_to_the_requester(self):
        self.reif()
        with self.assertRaises(ad.AgentsError):
            ad.review_result(self.world, "t1", "m2", "zu frueh", "bestanden", sender="m2",
                             claimed_role="mitglied")
        ad.review_ticket(self.world, "t1", "m2", sender="main", claimed_role="hauptagent")
        with self.assertRaises(ad.AgentsError):
            ad.review_result(self.world, "t1", "m1", "nicht mein Review", "bestanden", sender="m1",
                             claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.review_result(self.world, "t1", "m2", "egal", "super", sender="m2", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.review_result(self.world, "t1", "m2", "", "bestanden", sender="m2", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.review_result(self.world, "t1", "m2", "x" * 2001, "bestanden", sender="m2",
                             claimed_role="mitglied")
        first = ad.review_result(self.world, "t1", "m2", "Commit prueft die Analyse", "maengel",
                                 sender="m2", claimed_role="mitglied")
        second = ad.review_result(self.world, "t1", "m2", "Commit prueft die Analyse", "maengel",
                                  sender="m2", claimed_role="mitglied")
        self.assertEqual(first, second)
        self.assertEqual(first["state"], "zur Abnahme")
        self.assertEqual((first["review"]["note"], first["review"]["verdict"]),
                         ("Commit prueft die Analyse", "maengel"))
        note = [e for e in self.events("t1") if e["event"] == "pruefnotiz"]
        self.assertEqual([(e["text"], e["verdict"]) for e in note], [("Commit prueft die Analyse", "maengel")])
        delivery = ad.derived_id("ticket-reviewed", "t1", 1)
        stored = json.loads((self.world / "agents" / "main" / "postfach" / (delivery + ".json")).read_text())
        self.assertEqual((stored["kind"], stored["sender"], stored["ticket"], stored["subject"]),
                         ("kanal", "m2", "t1", "Antwort"))
        self.assertIn("Prüfnotiz zu t1 (maengel): Commit prueft die Analyse", stored["text"])

    def test_team_leader_of_the_team_requests_the_review(self):
        self.member("leiter", team="dev", stage="teamleiter")
        self.member("bau1", team="dev")
        self.member("bau2", team="dev")
        self.ticket("t-team", agent="bau1", team="dev", sender="main")
        self.abnahme_reif("t-team", "bau1")
        reviewed = ad.review_ticket(self.world, "t-team", "bau2", sender="leiter", claimed_role="teamleiter")
        self.assertEqual(reviewed["state"], "in Prüfung")
        self.ticket("t-fremd", agent="bau1", sender="main")
        self.abnahme_reif("t-fremd", "bau1")
        with self.assertRaises(ad.AgentsError):
            ad.review_ticket(self.world, "t-fremd", "m1", sender="leiter", claimed_role="teamleiter")

    def test_interrupted_review_resumes_with_the_reviewer(self):
        self.reif()
        ad.review_ticket(self.world, "t1", "m2", sender="main", claimed_role="hauptagent")
        ad.set_world_state(self.world, "gestoppt", "Sofort", "mensch", None)
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "unterbrochen")
        ad.set_world_state(self.world, "läuft", None, "mensch", None)
        reopened = ad.reopen_interrupted_ticket(self.world, "t1", "main", "hauptagent")
        self.assertEqual(reopened["state"], "in Prüfung")
        revision = reopened["result_revision"]
        delivery = ad.derived_id("ticket-review", "t1", revision, reopened["resume_revision"])
        self.assertTrue((self.world / "agents" / "m2" / "postfach" / (delivery + ".json")).exists())
        ad.review_result(self.world, "t1", "m2", "bestanden nach Sichtprüfung", "bestanden",
                         sender="m2", claimed_role="mitglied")
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "zur Abnahme")

    def test_rpc_review_flow(self):
        self.reif()
        controller = ac.AgentController(self.world, "run-1", lambda binding: True)
        main = controller.bind_agent("main", "hauptagent")
        reviewer = controller.bind_agent("m2", "mitglied")
        member = controller.bind_agent("m1", "mitglied")
        try:
            main.request("ticket.review", {"ticket_id": "t1", "reviewer_id": "m2"})
            self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "in Prüfung")
            with self.assertRaises(ac.ControllerError):
                member.request("ticket.review", {"ticket_id": "t1", "reviewer_id": "m2"})
            with self.assertRaises(ac.ControllerError):
                reviewer.request("ticket.review_result", {"ticket_id": "t1", "text": "x", "verdict": "egal"})
            noted = reviewer.request("ticket.review_result",
                                     {"ticket_id": "t1", "text": "prueft", "verdict": "bestanden"})
            self.assertEqual(noted["state"], "zur Abnahme")
            approved = main.request("ticket.approve", {"ticket_id": "t1", "note": "passt",
                                                       "dod_checked": True})
            self.assertEqual(approved["state"], "abgenommen")
            with self.assertRaises(ac.ControllerError):
                member.request("ticket.approve", {"ticket_id": "t1", "note": "nein", "dod_checked": True})
        finally:
            for client in (main, reviewer, member):
                client.close()
            controller.close()
            controller.join()


class WeckenUndUmadressierenTests(_TicketBasis):
    """Folgenachbesserungen aus tickets1: Wecken bei Verwerfen, Umadressieren aus wartet."""

    def test_wake_when_the_waited_ticket_is_discarded_names_the_reason(self):
        self.ticket("t1")
        self.ticket("t2", agent="m2")
        self.laeuft("t2", "m2")
        ad.park_ticket(self.world, "t2", "m2", "warte auf t1", waiting_for="t1",
                       sender="m2", claimed_role="mitglied")
        ad.discard_ticket(self.world, "t1", "nicht-mehr-noetig", None, sender="main",
                          claimed_role="hauptagent")
        woke = ad.wake_parked_tickets(self.world, WECK_EPOCH)
        self.assertEqual(woke, ["t2"])
        ticket = ad.read_ticket(self.world, "t2")
        self.assertEqual((ticket["state"], ticket["return_to"]), ("offen", ["m2"]))
        event = next(e for e in self.events("t2") if e["event"] == "geweckt")
        self.assertEqual(event["grund"], "warteticket t1 verworfen")

    def test_wake_still_needs_approved_or_discarded_waited_ticket(self):
        self.ticket("t1")
        self.ticket("t2", agent="m2")
        self.laeuft("t2", "m2")
        ad.park_ticket(self.world, "t2", "m2", "warte auf t1", waiting_for="t1",
                       sender="m2", claimed_role="mitglied")
        self.assertEqual(ad.wake_parked_tickets(self.world, WECK_EPOCH), [])
        self.assertEqual(ad.read_ticket(self.world, "t2")["state"], "wartet")

    def test_reassign_from_wartet_keeps_state_and_wakes_the_new_addressee(self):
        self.ticket()
        self.laeuft()
        self.ticket("t2", agent="m2")
        ad.park_ticket(self.world, "t1", "m1", "warte auf t2", waiting_for="t2",
                       sender="m1", claimed_role="mitglied")
        moved = ad.reassign_ticket(self.world, "t1", ["m2"], reason="m2 weiss Bescheid",
                                   sender="main", claimed_role="hauptagent")
        self.assertEqual((moved["state"], moved["assignee"], moved["recipients"]),
                         ("wartet", None, ["m2"]))
        self.assertEqual(moved["parked"]["waiting_for"], "t2")
        new_delivery = ad.derived_id("ticket-reassign", "t1", 1)
        stored = json.loads((self.world / "agents" / "m2" / "postfach" / (new_delivery + ".json")).read_text())
        self.assertFalse(stored["acknowledged"])
        old = json.loads((self.world / "agents" / "m1" / "postfach" /
                          (ad.derived_id("ticket", "t1") + ".json")).read_text())
        self.assertTrue(old["acknowledged"])
        self.abnahme_reif("t2", "m2")
        # Die Abnahme von t2 weckt das wartende t1 selbst; die Zustellung geht an den neuen Adressaten.
        ad.approve_ticket(self.world, "t2", "main", "hauptagent", "passt")
        ticket = ad.read_ticket(self.world, "t1")
        self.assertEqual(ticket["state"], "offen")
        self.assertEqual(ticket["return_to"], ["m2"])
        self.assertTrue(any(e["event"] == "geweckt" for e in self.events("t1")))

    def test_reassign_from_braucht_dich_answer_goes_to_the_new_addressee(self):
        self.ticket()
        self.laeuft()
        question = ad.ask_question(self.world, "Welche Variante?", ticket_id="t1",
                                   sender="main", claimed_role="hauptagent")
        ad.flag_ticket(self.world, "t1", question["id"], "Entscheidung fehlt",
                       sender="main", claimed_role="hauptagent")
        moved = ad.reassign_ticket(self.world, "t1", ["m2"], reason="m2 uebernimmt die Frage",
                                   sender="main", claimed_role="hauptagent")
        self.assertEqual((moved["state"], moved["assignee"], moved.get("flag", {}).get("question")),
                         ("braucht dich", None, question["id"]))
        ad.answer_question(self.world, question["id"], "Variante A", "mensch", None)
        ticket = ad.read_ticket(self.world, "t1")
        self.assertEqual((ticket["state"], ticket["return_to"]), ("offen", ["m2"]))


class ZeigenTests(_TicketBasis):
    """`wb-ticket zeigen` listet die Zwischenstaende chronologisch (Plan Satz 15)."""

    def test_zeigen_lists_progress_notes_and_the_review_note(self):
        self.ticket()
        self.laeuft()
        ad.note_ticket(self.world, "t1", "m1", "Erster Stand", sender="m1", claimed_role="mitglied")
        ad.note_ticket(self.world, "t1", "m1", "Zweiter Stand", sender="m1", claimed_role="mitglied")
        self.abnahme_reif("t1")
        ad.review_ticket(self.world, "t1", "m2", sender="main", claimed_role="hauptagent")
        ad.review_result(self.world, "t1", "m2", "Ein Punkt fehlt im Diff", "maengel",
                         sender="m2", claimed_role="mitglied")
        text = self._zeigen()
        self.assertIn("Zwischenstände (2):", text)
        erster = text.find("Erster Stand")
        zweiter = text.find("Zweiter Stand")
        self.assertLess(erster, zweiter)
        self.assertIn("Prüfnotiz von m2 (maengel): Ein Punkt fehlt im Diff", text)
        self.assertIn("Ergebnis (Revision 1)", text)

    def test_zeigen_shows_the_done_list_with_ticks(self):
        self.ticket(done_items=["a", "b"])
        self.laeuft()
        ad.check_done_item(self.world, "t1", "m1", 1, sender="m1", claimed_role="mitglied")
        text = self._zeigen()
        self.assertIn("Fertig-Liste:", text)
        self.assertIn("[x] a", text)
        self.assertIn("[ ] b", text)

    def _zeigen(self):
        env = dict(os.environ, PYTHONPATH=str(HERE.parents[1]))
        result = subprocess.run([str(HERE.parents[1] / "wb-ticket"), "zeigen", str(self.world), "t1"],
                                text=True, capture_output=True, env=env, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout


class TicketRpc(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-tickets-rpc-")
        self.world = Path(self.tmp.name) / "welt"
        ad.create_world(self.world, name="Rpc", main_name="main")
        ad.create_agent(self.world, "member", "mitglied", None, "M", None, None, None, None,
                        None, None, "lokal", "main", "hauptagent")
        self.controller = ac.AgentController(self.world, "run-1", lambda binding: True)
        self.client = self.controller.bind_agent("member", "mitglied")
        self.main = self.controller.bind_agent("main", "hauptagent")

    def tearDown(self):
        for client in (self.client, self.main):
            client.close()
        self.controller.close()
        self.controller.join()
        self.tmp.cleanup()

    def ticket(self, ticket_id="t1", agent="member"):
        return ad.create_ticket(self.world, "Titel", "Ziel", "Fertig", [agent] if agent else [],
                                "main", "hauptagent", ticket_id=ticket_id)

    def test_park_and_flag_over_rpc(self):
        self.ticket()
        self.client.request("ticket.claim", {"ticket_id": "t1"})
        parked = self.client.request("ticket.park", {"ticket_id": "t1", "reason": "warte",
                                                     "until": WECKZEIT})
        self.assertEqual(parked["state"], "wartet")
        question = self.main.request("question.ask", {"question_id": "q1", "text": "Welche?",
                                                      "ticket_id": "t1"})
        flagged = self.main.request("ticket.flag", {"ticket_id": "t1", "question_id": question["id"],
                                                    "reason": "Entscheidung"})
        self.assertEqual(flagged["state"], "braucht dich")
        with self.assertRaises(ac.ControllerError):
            self.main.request("ticket.park", {"ticket_id": "t1", "reason": "nur Bearbeiter",
                                              "until": WECKZEIT})
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "braucht dich")

    def test_discard_reassign_and_triage_over_rpc(self):
        self.ticket("t1")
        discarded = self.main.request("ticket.discard", {"ticket_id": "t1", "reason_code": "abgelehnt",
                                                         "note": "nein"})
        self.assertEqual(discarded["state"], "verworfen")
        self.ticket("t2")
        reassigned = self.main.request("ticket.reassign", {"ticket_id": "t2", "recipients": ["member"],
                                                           "reason": "umziehen"})
        self.assertEqual(reassigned["recipients"], ["member"])
        self.ticket("t3", agent=None)
        accepted = self.main.request("ticket.triage", {"ticket_id": "t3", "recipients": ["member"],
                                                       "priority": 2, "kind": "auftrag"})
        self.assertEqual((accepted["state"], accepted["priority"], accepted["kind"]),
                         ("offen", 2, "auftrag"))
        with self.assertRaises(ac.ControllerError):
            self.main.request("ticket.triage", {"ticket_id": "t3", "recipients": ["member"],
                                                "priority": True})
        with self.assertRaises(ac.ControllerError):
            self.main.request("ticket.discard", {"ticket_id": "t4", "reason_code": "egal"})

    def test_member_cannot_triage(self):
        self.ticket("t1", agent=None)
        with self.assertRaises(ac.ControllerError):
            self.client.request("ticket.triage", {"ticket_id": "t1", "recipients": ["member"]})

    def test_note_and_check_over_rpc(self):
        ad.create_ticket(self.world, "Titel", "Ziel", "Fertig", ["member"], "main", "hauptagent",
                         ticket_id="t1", done_items=["Punkt eins", "Punkt zwei"])
        self.client.request("ticket.claim", {"ticket_id": "t1"})
        noted = self.client.request("ticket.note", {"ticket_id": "t1", "text": "Stand: Recherche steht"})
        self.assertEqual(noted["state"], "läuft")
        with self.assertRaises(ac.ControllerError):
            self.client.request("ticket.note", {"ticket_id": "t1", "text": "x" * 2001})
        with self.assertRaises(ac.ControllerError):
            self.client.request("ticket.check", {"ticket_id": "t1", "index": 3})
        checked = self.client.request("ticket.check", {"ticket_id": "t1", "index": 1})
        self.assertTrue(checked["done_items"][0]["done"])
        with self.assertRaises(ac.ControllerError):
            self.client.request("ticket.result", {"ticket_id": "t1", "text": "zu frueh"})
        self.client.request("ticket.check", {"ticket_id": "t1", "index": 2})
        done = self.client.request("ticket.result", {"ticket_id": "t1", "text": "fertig"})
        self.assertEqual(done["state"], "zur Abnahme")
        with self.assertRaises(ac.ControllerError):
            self.main.request("ticket.note", {"ticket_id": "t1", "text": "kein Bearbeiter"})

    def test_reorder_and_limits_over_rpc(self):
        ad.create_ticket(self.world, "Erstes", "Z", "F", [], "main", "hauptagent", ticket_id="t1")
        ad.create_ticket(self.world, "Zweites", "Z", "F", [], "main", "hauptagent", ticket_id="t2")
        with self.assertRaises(ac.ControllerError):
            self.client.request("ticket.reorder", {"ticket_ids": ["t2", "t1"]})
        ordered = self.main.request("ticket.reorder", {"ticket_ids": ["t2", "t1"]})
        self.assertEqual([t["id"] for t in ordered], ["t2", "t1"])
        self.assertEqual([ad.read_ticket(self.world, t)["order"] for t in ("t1", "t2")], [2, 1])
        with self.assertRaises(ac.ControllerError):
            self.client.request("ticket.limits", {"ticket_id": "t1", "runden": 3})
        with self.assertRaises(ac.ControllerError):
            self.main.request("ticket.limits", {"ticket_id": "t1", "runden": 0})
        limited = self.main.request("ticket.limits", {"ticket_id": "t1", "frist": "2026-10-01T00:00:00Z",
                                                      "runden": 3})
        self.assertEqual(limited["limits"], {"frist": "2026-10-01T00:00:00Z", "runden": 3})


class TicketCli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="agents-tickets-cli-")
        self.world = Path(self.tmp.name) / "welt"
        self.env = dict(os.environ, PYTHONPATH=str(SHELL))
        self.call("wb-welt", "neu", self.world, "--name", "Cli", "--absender", "cli-operator")
        self.call("wb-agent", "neu", self.world, "--name", "m1", "--stufe", "mitglied",
                  "--beschreibung", "M1")

    def tearDown(self):
        self.tmp.cleanup()

    def call(self, tool, *args):
        return _in_process_cli(tool, *args)

    def raw(self, tool, *args):
        return subprocess.run([str(SHELL / tool), *map(str, args)],
                              text=True, capture_output=True, env=self.env)

    def test_parken_bereit_verwerfen_umadressieren_annehmen(self):
        ticket = self.call("wb-ticket", "neu", self.world, "--id", "t-cli", "--titel", "T",
                           "--ziel", "Z", "--fertig", "F", "--an", "m1", "--absender", "hauptagent")
        self.call("wb-ticket", "uebernehmen", self.world, "t-cli", "--agent", "m1", "--absender", "m1")
        parked = self.call("wb-ticket", "parken", self.world, "t-cli", "--agent", "m1",
                           "--grund", "warte", "--bis", WECKZEIT, "--absender", "m1")
        self.assertEqual((parked["state"], parked["parked"]["until"]), ("wartet", WECKZEIT))
        bereit = self.raw("wb-ticket", "bereit", self.world)
        self.assertIn("t-cli nicht bereit: geparkt bis %s" % WECKZEIT, bereit.stdout)
        entries = self.call("wb-ticket", "bereit", self.world)
        self.assertEqual([e["id"] for e in entries], ["t-cli"])
        self.call("wb-ticket", "verwerfen", self.world, "t-cli", "--absender", "hauptagent",
                  "--grund", "nicht-mehr-noetig", "--bemerkung", "weg damit")
        self.assertEqual(ad.read_ticket(self.world, "t-cli")["state"], "verworfen")
        triage = self.call("wb-ticket", "neu", self.world, "--id", "t-triage", "--titel", "T",
                           "--ziel", "Z", "--fertig", "F", "--absender", "hauptagent")
        self.assertEqual(triage["state"], "triage")
        accepted = self.call("wb-ticket", "annehmen", self.world, "t-triage", "--an", "m1",
                             "--prioritaet", "1", "--art", "fehler", "--absender", "hauptagent")
        self.assertEqual((accepted["state"], accepted["priority"], accepted["kind"]),
                         ("offen", 1, "fehler"))
        moved = self.call("wb-ticket", "umadressieren", self.world, "t-triage", "--an", "m1",
                          "--grund", "bleibt", "--absender", "hauptagent")
        self.assertEqual(moved["recipients"], ["m1"])
        bad = self.raw("wb-ticket", "verwerfen", self.world, "t-triage", "--absender", "hauptagent",
                       "--grund", "egal")
        self.assertEqual(bad.returncode, 2)
        self.assertIn("invalid choice", bad.stderr)

    def test_braucht_dich_and_abnehmen_grund(self):
        self.call("wb-ticket", "neu", self.world, "--id", "t-flag", "--titel", "T", "--ziel", "Z",
                  "--fertig", "F", "--an", "m1", "--absender", "hauptagent")
        self.call("wb-ticket", "uebernehmen", self.world, "t-flag", "--agent", "m1", "--absender", "m1")
        self.call("wb-welt", "frage", self.world, "--id", "q-cli", "--text", "Welche?",
                  "--ticket", "t-flag", "--absender", "hauptagent")
        flagged = self.call("wb-ticket", "braucht-dich", self.world, "t-flag", "--frage", "q-cli",
                            "--grund", "Entscheidung fehlt", "--absender", "hauptagent")
        self.assertEqual(flagged["state"], "braucht dich")
        self.call("wb-welt", "antwort", self.world, "q-cli", "--text", "Variante A")
        self.assertEqual(ad.read_ticket(self.world, "t-flag")["state"], "offen")
        self.call("wb-ticket", "uebernehmen", self.world, "t-flag", "--agent", "m1", "--absender", "m1")
        self.call("wb-ticket", "ergebnis", self.world, "t-flag", "--agent", "m1", "--text", "fertig",
                  "--absender", "m1")
        partly = self.raw("wb-ticket", "abnehmen", self.world, "t-flag", "--absender", "hauptagent",
                          "--grund", "teilweise")
        self.assertEqual(partly.returncode, 2)
        approved = self.call("wb-ticket", "abnehmen", self.world, "t-flag", "--absender", "hauptagent",
                             "--grund", "teilweise", "--bemerkung", "Rest folgt")
        self.assertEqual(approved["approval"]["reason_code"], "teilweise")


class ArtUndPrioritaetTests(_TicketBasis):
    """Art und Prioritaet als Pflichtfelder (Plan AGENTS-TICKETS-PLAN Saetze 3, 5, 10 und 38)."""

    def test_kind_defaults_to_task_and_is_validated(self):
        ticket = self.ticket()
        self.assertEqual(ticket["kind"], "auftrag")
        self.assertEqual(ad._ticket_kind_feld(self.roh("t1", kind=_WEG)), "auftrag")
        with self.assertRaises(ad.AgentsError):
            self.ticket("t-bad", kind="epic")
        gewaehlt = self.ticket("t-gut", kind="recherche")
        self.assertEqual(gewaehlt["kind"], "recherche")

    def test_priority_is_zero_to_three_and_defaults_to_normal(self):
        ticket = self.ticket()
        self.assertEqual(ticket["priority"], 2)
        for stufe in (0, 1, 2, 3):
            self.assertEqual(self.ticket("t-p%d" % stufe, priority=stufe)["priority"], stufe)
        with self.assertRaises(ad.AgentsError):
            self.ticket("t-hoch", priority=4)
        with self.assertRaises(ad.AgentsError):
            self.ticket("t-bool", priority=True)
        # Bestand ohne Feld gilt als normal und auftrag (Plan Saetze 3 und 5): kein
        # Fertig-Listen-Zwang, sonst wuerde jedes alte Ticket unzustellbar.
        self.roh("t1", kind=_WEG, priority=_WEG)
        bestand = ad.read_ticket(self.world, "t1")
        self.assertEqual((ad._ticket_kind_feld(bestand), bestand.get("priority")), ("auftrag", None))
        entries = {e["id"]: e for e in ad.ready_tickets(self.world)}
        self.assertNotEqual(entries["t1"]["reason"], "fehlende Fertig-Liste")

    def test_priority_text_reaches_the_view_and_zeigen(self):
        self.ticket("t-sofort", priority=0, kind="auftrag")
        text = self._zeigen("t-sofort")
        self.assertIn("Art: auftrag", text)
        self.assertIn("Prioritaet: 0 (sofort (Betrieb steht, Daten in Gefahr))", text)
        snapshot = ad.world_snapshot(self.world)
        ticket = next(t for t in snapshot["tickets"] if t["id"] == "t-sofort")
        self.assertEqual((ticket["kind"], ticket["priority"]), ("auftrag", 0))
        self.assertEqual(ticket["priority_text"], "sofort (Betrieb steht, Daten in Gefahr)")

    def test_runden_default_at_creation_and_vorhaben_without_limits(self):
        self.assertEqual(self.ticket("t-a")["limits"], {"runden": 6})
        self.assertEqual(self.ticket("t-b", limits={"frist": "2026-10-01T00:00:00Z"})["limits"],
                         {"frist": "2026-10-01T00:00:00Z"})
        vorhaben = self.ticket("t-v", kind="vorhaben")
        self.assertEqual(vorhaben["limits"], {})
        with self.assertRaises(ad.AgentsError):
            self.ticket("t-falsch", limits={"frist": "morgen"})
        with self.assertRaises(ad.AgentsError):
            self.ticket("t-falsch", limits={"runden": 0})

    def test_ready_sorts_triage_by_order_and_missing_priority_as_normal(self):
        self.ticket("t-spater", agent=None)  # triage, order 1
        self.ticket("t-first", agent=None)   # triage, order 2
        self.ticket("t-normal", agent="m1", kind="auftrag")  # fehlende Prioritaet gilt als 2
        ad.reorder_triage(self.world, ["t-first", "t-spater"], "mensch", None)
        order = [e["id"] for e in ad.ready_tickets(self.world)]
        self.assertEqual(order, ["t-first", "t-spater", "t-normal"])

    def _zeigen(self, ticket_id):
        env = dict(os.environ, PYTHONPATH=str(HERE.parents[1]))
        result = subprocess.run([str(HERE.parents[1] / "wb-ticket"), "zeigen", str(self.world), ticket_id],
                                text=True, capture_output=True, env=env, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout


class HierarchieTests(_TicketBasis):
    """Eltern, Herkunft und Kinderzaehler (Plan AGENTS-TICKETS-PLAN Saetze 4, 17, 29, 36, 43 und 51)."""

    def eltern(self, ticket_id="v1", kind="vorhaben", agent="main"):
        return self.ticket(ticket_id, agent=agent, kind=kind)

    def test_allowed_chain_edges(self):
        self.eltern()
        story = self.ticket("s1", agent="m1", kind="story", parent="v1", done_items=["nutzbar"])
        self.assertEqual(story["parent"], "v1")
        task = self.ticket("tk1", agent="m1", kind="task", parent="s1", done_items=[])
        self.assertEqual(task["parent"], "s1")
        sub = self.ticket("st1", agent="m1", kind="subtask", parent="tk1")
        self.assertEqual(sub["parent"], "tk1")
        # task > subtask und story > task sind eigene erlaubte Ketten; task direkt unter
        # vorhaben oder story unter task ist verboten.
        with self.assertRaises(ad.AgentsError):
            self.ticket("tk-ohne", agent="m1", kind="task", parent="v1")
        with self.assertRaises(ad.AgentsError):
            self.ticket("story-unter-task", agent="m1", kind="story", parent="tk1")

    def test_parent_must_exist_not_verworfen_not_abgenommen(self):
        self.eltern()
        self.roh("v1", state="verworfen")
        with self.assertRaises(ad.AgentsError):
            self.ticket("s1", agent="m1", kind="story", parent="v1")
        self.roh("v1", state="abgenommen")
        with self.assertRaises(ad.AgentsError):
            self.ticket("s1", agent="m1", kind="story", parent="v1")
        with self.assertRaises(ad.AgentsError):
            self.ticket("s1", agent="m1", kind="story", parent="t-fehlt")
        with self.assertRaises(ad.AgentsError):
            self.ticket("s1", agent="m1", kind="story", parent="s1")

    def test_depth_is_at_most_three_and_no_cycle(self):
        self.eltern()
        self.ticket("s1", agent="m1", kind="story", parent="v1")
        self.ticket("tk1", agent="m1", kind="task", parent="s1")
        # Die Kette vorhaben > story > task > subtask ist die erlaubte groesste Tiefe (Satz 43).
        sub = self.ticket("st1", agent="m1", kind="subtask", parent="tk1")
        self.assertEqual(sub["parent"], "tk1")
        # Ein Subtask hat nie Kinder (Kette subtask > ... ist unzulaessig).
        with self.assertRaises(ad.AgentsError):
            self.ticket("tiefer", agent="m1", kind="subtask", parent="st1")
        # Zyklen: haengt das Eltern selbst unter dem neuen Kind, wird der Zyklus abgewiesen.
        self.roh("s1", parent="tk1")
        with self.assertRaises(ad.AgentsError):
            self.ticket("st2", agent="m1", kind="subtask", parent="tk1")
        self.assertEqual(ad.read_ticket(self.world, "s1")["parent"], "tk1")

    def test_deeper_than_three_levels_is_refused(self):
        self.eltern()
        self.ticket("v2", agent="m1", kind="vorhaben")
        self.ticket("s1", agent="m1", kind="story", parent="v1")
        self.ticket("tk1", agent="m1", kind="task", parent="s1")
        self.roh("v1", parent="v2")  # beschaedigter Bestand: die Kette waere fuenf Knoten tief
        with self.assertRaises(ad.AgentsError) as caught:
            self.ticket("tief", agent="m1", kind="subtask", parent="tk1")
        self.assertIn("drei Ebenen", str(caught.exception))

    def test_triage_accept_carries_the_parent(self):
        self.eltern()
        ticket = self.ticket("s1", agent=None, kind="story")
        accepted = ad.triage_accept(self.world, "s1", ["m1"], parent="v1", done_items=["nutzbar"],
                                    sender="main", claimed_role="hauptagent")
        self.assertEqual(accepted["parent"], "v1")
        self.ticket("s2", agent=None, kind="task")
        with self.assertRaises(ad.AgentsError):
            ad.triage_accept(self.world, "s2", ["m1"], parent="v1", sender="main",
                             claimed_role="hauptagent")

    def test_children_inherit_priority_and_cycle(self):
        ad.set_cycle(self.world, True, tage=7, ziel="Bauen", sender="mensch")
        eltern = self.eltern(agent=None)
        accepted = ad.triage_accept(self.world, "v1", ["main"], priority=1,
                                    sender="main", claimed_role="hauptagent")
        self.assertEqual(accepted["cycle"], "zyklus-1")
        eigen = self.ticket("s1", agent="m1", kind="story", parent="v1", priority=3, done_items=["x"])
        self.assertEqual((eigen["priority"], eigen["cycle"]), (3, "zyklus-1"))
        erbe = self.ticket("s2", agent="m2", kind="story", parent="v1", done_items=["x"])
        self.assertEqual((erbe["priority"], erbe["cycle"]), (1, "zyklus-1"))

    def test_origin_needs_existence_and_marks_the_origin_ticket(self):
        self.ticket("quelle", agent="m1", kind="recherche")
        folge = self.ticket("f1", agent="m1", origin="quelle", done_items=["fertig"])
        self.assertEqual(folge["origin"], "quelle")
        self.assertTrue(any(e["event"] == "folgeticket" and e.get("folgeticket") == "f1"
                            for e in self.events("quelle")))
        with self.assertRaises(ad.AgentsError):
            self.ticket("f2", agent="m1", origin="t-fehlt", done_items=["fertig"])

    def test_parent_advances_when_the_last_child_is_approved(self):
        self.eltern()
        self.ticket("s1", agent="m1", kind="story", parent="v1", done_items=[])
        self.ticket("s2", agent="m2", kind="story", parent="v1", done_items=[])
        self.abnahme_reif("s1", "m1")
        ad.approve_ticket(self.world, "s1", "main", "hauptagent", "passt")
        self.assertEqual(ad.read_ticket(self.world, "v1")["state"], "offen")
        self.abnahme_reif("s2", "m2")
        ad.approve_ticket(self.world, "s2", "main", "hauptagent", "passt")
        eltern = ad.read_ticket(self.world, "v1")
        self.assertEqual(eltern["state"], "zur Abnahme")
        self.assertEqual(eltern["result"]["text"], "Alle Kinder abgenommen: s1, s2")
        self.assertEqual(eltern["result"]["agent"], "system")
        self.assertTrue(any(e["event"] == "kinder-fertig" for e in self.events("v1")))
        zustellung = self.world / "agents" / "main" / "postfach" / (ad.derived_id("ticket-kinder", "v1") + ".json")
        self.assertTrue(zustellung.exists())
        # Idempotent: ein erneuter Aufruf verdoppelt weder Ereignis noch Zustellung.
        ad._eltern_kinder_fertig(self.world, ad.read_ticket(self.world, "s2"),
                                 {"id": "main", "verified": False})
        self.assertEqual(sum(1 for e in self.events("v1") if e["event"] == "kinder-fertig"), 1)
        self.assertEqual(len(list(self.world.glob("agents/main/postfach/ticket-kinder-*.json"))), 1)

    def test_parent_with_only_discarded_children_does_not_advance(self):
        self.eltern()
        self.ticket("s1", agent="m1", kind="story", parent="v1", done_items=[])
        self.roh("s1", state="verworfen")
        eltern = ad.read_ticket(self.world, "v1")
        ad._eltern_kinder_fertig(self.world, eltern, {"id": "system", "verified": False})
        self.assertEqual(ad.read_ticket(self.world, "v1")["state"], "offen")
        self.assertFalse(any(e["event"] == "kinder-fertig" for e in self.events("v1")))

    def test_parent_already_taken_is_not_moved_again(self):
        self.eltern()
        self.ticket("s1", agent="m1", kind="story", parent="v1", done_items=[])
        self.abnahme_reif("s1", "m1")
        ad.approve_ticket(self.world, "s1", "main", "hauptagent", "passt")
        ad.approve_ticket(self.world, "v1", "main", "hauptagent", "vorhaben passt")
        ad._eltern_kinder_fertig(self.world, ad.read_ticket(self.world, "s1"),
                                 {"id": "system", "verified": False})
        eltern = ad.read_ticket(self.world, "v1")
        self.assertEqual(eltern["state"], "abgenommen")
        self.assertEqual(sum(1 for e in self.events("v1") if e["event"] == "kinder-fertig"), 1)

    def test_children_function_and_snapshot_counters(self):
        self.eltern()
        self.ticket("s1", agent="m1", kind="story", parent="v1", done_items=[])
        self.ticket("s2", agent="m2", kind="story", parent="v1", done_items=[])
        self.ticket("s3", agent="m2", kind="story", parent="v1", done_items=[])
        self.assertEqual([t["id"] for t in ad.children(self.world, "v1")], ["s1", "s2", "s3"])
        self.abnahme_reif("s1", "m1")
        ad.approve_ticket(self.world, "s1", "main", "hauptagent", "passt")
        self.roh("s3", state="verworfen")
        snapshot = ad.world_snapshot(self.world)
        eltern = next(t for t in snapshot["tickets"] if t["id"] == "v1")
        self.assertEqual((eltern["children_total"], eltern["children_approved"]), (2, 1))

    def test_child_readiness_ignores_the_parent_state(self):
        self.eltern()
        self.ticket("s1", agent="m1", kind="story", parent="v1", done_items=["fertig"])
        ad.claim_ticket(self.world, "v1", "main", "main", "hauptagent")
        self.assertEqual(ad.read_ticket(self.world, "v1")["state"], "läuft")
        entries = {e["id"]: e for e in ad.ready_tickets(self.world)}
        # Der Eltern-Stand blockt das Kind nicht; nur dependencies tun das (Plan 5.1 Widerspruch 4).
        self.assertTrue(entries["s1"]["ready"], entries["s1"]["reason"])

    def test_vorhaben_approval_reports_to_the_human(self):
        self.eltern()
        self.ticket("s1", agent="m1", kind="story", parent="v1", done_items=[])
        self.abnahme_reif("s1", "m1")
        ad.approve_ticket(self.world, "s1", "main", "hauptagent", "passt")
        ad.approve_ticket(self.world, "v1", "main", "hauptagent", "alles drin")
        message_id = ad.derived_id("vorhaben-ergebnis", "v1", 0)
        stored = json.loads((self.world / "menschen" / "mensch" / "postfach" / (message_id + ".json")).read_text())
        self.assertEqual((stored["mark"], stored["humans"], stored["ticket"]),
                         ("ergebnis", ["mensch"], "v1"))
        self.assertIn("Vorhaben v1", stored["text"])
        kanal = [m for m in ad.read_messages(self.world) if m.get("id") == message_id]
        self.assertEqual([(m.get("mark"), m.get("humans")) for m in kanal], [("ergebnis", ["mensch"])])
        # Ein einziges Mal: die wiederholte Abnahme des Vorhabens meldet nicht erneut.
        ad._melde_vorhaben(self.world, ad.read_ticket(self.world, "v1"))
        kanal = [m for m in ad.read_messages(self.world) if m.get("ticket") == "v1"]
        self.assertEqual(len(kanal), 1)

    def test_zeigen_lists_kind_children_and_grenzen(self):
        self.eltern()
        self.ticket("s1", agent="m1", kind="story", parent="v1", done_items=["nutzbar"])
        ad.set_ticket_limits(self.world, "s1", frist="2026-10-01T00:00:00Z", sender="mensch")
        env = dict(os.environ, PYTHONPATH=str(HERE.parents[1]))
        result = subprocess.run([str(HERE.parents[1] / "wb-ticket"), "zeigen", str(self.world), "v1"],
                                text=True, capture_output=True, env=env, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Art: vorhaben", result.stdout)
        self.assertIn("Kinder (0 von 1 abgenommen): s1", result.stdout)
        result = subprocess.run([str(HERE.parents[1] / "wb-ticket"), "zeigen", str(self.world), "s1"],
                                text=True, capture_output=True, env=env, timeout=60)
        self.assertIn("Eltern: v1", result.stdout)
        self.assertIn("Frist 2026-10-01T00:00:00Z", result.stdout)


class BacklogTests(_TicketBasis):
    """Backlog, Definition of Ready, Zyklus und WIP (Plan AGENTS-TICKETS-PLAN Saetze 44 bis 48)."""

    def test_order_set_at_creation_and_reorder_only_by_main_or_human(self):
        first = self.ticket("t1", agent=None)
        second = self.ticket("t2", agent=None)
        third = self.ticket("t3", agent=None)
        self.assertEqual((first["order"], second["order"], third["order"]), (1, 2, 3))
        with self.assertRaises(ad.AgentsError):
            ad.reorder_triage(self.world, ["t2"], "m1", "mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.reorder_triage(self.world, ["t2"], "m1", None)  # Mitglied ohne Rolle
        reordered = ad.reorder_triage(self.world, ["t3", "t2"], "mensch")
        self.assertEqual([t["id"] for t in reordered][:2], ["t3", "t2"])
        self.assertEqual([ad.read_ticket(self.world, t)["order"] for t in ("t1", "t2", "t3")], [3, 2, 1])
        self.assertTrue(any(e["event"] == "geordnet" for e in self.events("t3")))
        # Idempotent und abweisend bei unbekannten oder keinen Triage-Tickets.
        again = ad.reorder_triage(self.world, ["t3", "t2"], "mensch")
        self.assertEqual([t["id"] for t in again][:2], ["t3", "t2"])
        self.assertEqual(sum(1 for e in self.events("t3") if e["event"] == "geordnet"), 1)
        with self.assertRaises(ad.AgentsError):
            ad.reorder_triage(self.world, ["t-fehlt"], "mensch")
        addressed = self.ticket("t4", agent="m1", kind="auftrag")
        with self.assertRaises(ad.AgentsError):
            ad.reorder_triage(self.world, ["t4"], "mensch")

    def test_snapshot_and_backlog_cli_deliver_triage_in_order(self):
        self.ticket("t-alt", agent=None)
        self.ticket("t-neu", agent=None)
        ad.reorder_triage(self.world, ["t-neu", "t-alt"], "mensch")
        snapshot = ad.world_snapshot(self.world)
        triage = [t["id"] for t in snapshot["tickets"] if t.get("state") == "triage"]
        self.assertEqual(triage, ["t-neu", "t-alt"])
        env = dict(os.environ, PYTHONPATH=str(HERE.parents[1]))
        result = subprocess.run([str(HERE.parents[1] / "wb-ticket"), "backlog", str(self.world)],
                                text=True, capture_output=True, env=env, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        ids = [line.split(" ")[0] for line in result.stdout.splitlines()]
        self.assertEqual(ids, ["t-neu", "t-alt"])
        result = _TicketCliHelper(self.world)("wb-ticket", "backlog", self.world,
                                              "--ordnen", "t-alt", "--ordnen", "t-neu",
                                              "--absender", "mensch")
        ids = [entry["id"] for entry in result]
        self.assertEqual(ids, ["t-alt", "t-neu"])

    def test_definition_of_ready_blocks_ready_and_the_acceptance(self):
        # fehlende Fertig-Liste bei story/task/subtask
        self.ticket("t-liste", agent="m1", kind="story")
        self.ticket("t-liste-ok", agent="m1", kind="story", done_items=["nutzbar"])
        entries = {e["id"]: e for e in ad.ready_tickets(self.world)}
        self.assertEqual(entries["t-liste"]["reason"], "fehlende Fertig-Liste")
        self.assertTrue(entries["t-liste-ok"]["ready"], entries["t-liste-ok"]["reason"])
        # fehlende Grenzen: Bestand ohne limits und ohne Fertig-Liste-Vorgabe
        self.ticket("t-grenzen", agent="m1", kind="auftrag")
        self.roh("t-grenzen", limits={})
        entries = {e["id"]: e for e in ad.ready_tickets(self.world)}
        self.assertEqual(entries["t-grenzen"]["reason"], "fehlende Grenzen (keine Frist, keine Rundenzahl)")
        # ein Vorhaben braucht nur Titel, Ziel und Fertig-Kriterium
        self.ticket("t-vorhaben", agent="m1", kind="vorhaben")
        entries = {e["id"]: e for e in ad.ready_tickets(self.world)}
        self.assertTrue(entries["t-vorhaben"]["ready"], entries["t-vorhaben"]["reason"])
        # die Annahme verweigert mit demselben Grund
        triage = self.ticket("t-triage", agent=None, kind="story")
        with self.assertRaises(ad.AgentsError) as caught:
            ad.triage_accept(self.world, "t-triage", ["m1"], sender="main", claimed_role="hauptagent")
        self.assertIn("fehlende Fertig-Liste", str(caught.exception))
        accepted = ad.triage_accept(self.world, "t-triage", ["m1"], done_items=["nutzbar"],
                                    sender="main", claimed_role="hauptagent")
        self.assertEqual(accepted["done_items"][0]["text"], "nutzbar")

    def test_wip_limit_blocks_delivery_and_stays_soft(self):
        self.ticket("t1", agent="m1", kind="auftrag")
        self.ticket("t2", agent="m2", kind="auftrag")
        self.ticket("t3", agent="m2", kind="auftrag")
        with self.assertRaises(ad.AgentsError):
            ad.set_wip_limit(self.world, 1, sender="m1", claimed_role="mitglied")
        ad.set_wip_limit(self.world, 1, sender="mensch")
        self.assertEqual(ad.read_world(self.world)["wip_limit"], 1)
        entries = {e["id"]: e for e in ad.ready_tickets(self.world)}
        self.assertTrue(entries["t1"]["ready"])
        self.laeuft("t1", "m1")
        entries = {e["id"]: e for e in ad.ready_tickets(self.world)}
        self.assertEqual(entries["t2"]["reason"], "wip-grenze (1 von 1 laufen)")
        self.assertEqual(entries["t3"]["reason"], "wip-grenze (1 von 1 laufen)")
        # Weich: der Mensch weist trotzdem zu.
        self.laeuft("t2", "m2")
        self.assertEqual(ad.read_ticket(self.world, "t2")["state"], "läuft")
        # Geparkte Tickets zaehlen zur Welt: ein wartet-Ticket treibt die Grenze.
        ad.set_wip_limit(self.world, 2, sender="mensch")
        ad.park_ticket(self.world, "t2", "m2", "wartet", until=WECKZEIT,
                       sender="m2", claimed_role="mitglied")
        entries = {e["id"]: e for e in ad.ready_tickets(self.world)}
        self.assertEqual(entries["t3"]["reason"], "wip-grenze (2 von 2 laufen)")

    def test_wip_limit_default_and_cli(self):
        snapshot = ad.world_snapshot(self.world)
        aktiv = sum(1 for a in snapshot["agents"] if a.get("state") == "aktiv")
        self.assertEqual(snapshot["wip"], {"laufend": 0, "grenze": aktiv + (aktiv + 3) // 4})
        helper = _TicketCliHelper(self.world)
        shown = helper("wb-welt", "wip", self.world)
        self.assertIsNone(shown["wip_limit"])
        helper("wb-welt", "wip", self.world, "--limit", "5", "--absender", "mensch")
        self.assertEqual(ad.read_world(self.world)["wip_limit"], 5)


class ZyklusTests(_TicketBasis):
    """Zyklus einschalten, Schluss mit Übertrag und Zustellung (Plan Satz 46)."""

    def test_set_cycle_permissions_and_defaults(self):
        self.ticket("t1", agent="m1", kind="auftrag")
        with self.assertRaises(ad.AgentsError):
            ad.set_cycle(self.world, True, sender="m1", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.set_cycle(self.world, True, tage=0, sender="mensch")
        world = ad.set_cycle(self.world, True, sender="mensch")
        cycles = world["cycles"]
        self.assertTrue(cycles["enabled"])
        self.assertEqual(cycles["length_days"], 7)
        aktueller = cycles["current"]
        self.assertEqual(aktueller["id"], "zyklus-1")
        self.assertEqual(ad._epoch_of(aktueller["end"]) - ad._epoch_of(aktueller["start"]), 7 * 86400)
        self.assertTrue(any(e["event"] == "zyklus-eingeschaltet" for e in self.welt_events()))
        # ausschalten: zweimal ist harmlos; der letzte Zyklus bleibt sichtbar, die Nummerierung geht weiter.
        ad.set_cycle(self.world, False, sender="mensch")
        ad.set_cycle(self.world, False, sender="mensch")
        cycles = ad.read_world(self.world)["cycles"]
        self.assertFalse(cycles["enabled"])
        self.assertEqual(cycles["current"]["id"], "zyklus-1")
        # erneutes Einschalten nummeriert weiter.
        ad.set_cycle(self.world, True, tage=3, ziel="Bauen", sender="mensch")
        self.assertEqual(ad.read_world(self.world)["cycles"]["current"]["id"], "zyklus-2")

    def test_triage_accept_sets_the_current_cycle(self):
        ad.set_cycle(self.world, True, ziel="Bauen", sender="mensch")
        ticket = self.ticket("t1", agent=None, kind="recherche")
        accepted = ad.triage_accept(self.world, "t1", ["m1"], sender="main", claimed_role="hauptagent")
        self.assertEqual(accepted["cycle"], "zyklus-1")
        ad.set_wip_limit(self.world, 5, sender="mensch")
        self.ticket("t2", agent=None, kind="recherche")
        ad.set_cycle(self.world, False, sender="mensch")
        accepted = ad.triage_accept(self.world, "t2", ["m1"], sender="main", claimed_role="hauptagent")
        self.assertNotIn("cycle", accepted)

    def test_cycle_schluss_transfers_reports_and_delivers(self):
        ad.set_cycle(self.world, True, tage=1, ziel="Erster", sender="mensch")
        self.ticket("t-fertig", agent="m1", kind="auftrag")
        self.abnahme_reif("t-fertig", "m1")
        ad.approve_ticket(self.world, "t-fertig", "main", "hauptagent", "passt")
        self.ticket("t-offen", agent="m1", kind="auftrag")
        self.ticket("t-weg", agent="m1", kind="auftrag")
        ad.discard_ticket(self.world, "t-weg", "abgelehnt", None, sender="main", claimed_role="hauptagent")
        self.ticket("t-ohne-zyklus", agent="m1", kind="auftrag")
        self.roh("t-ohne-zyklus", cycle="zyklus-99")
        ende = ad._epoch_of(ad.read_world(self.world)["cycles"]["current"]["end"])
        summary = ad.cycle_schluss(self.world, ende + 60)
        self.assertEqual(summary["zyklus"], "zyklus-1")
        self.assertEqual(summary["neu"], "zyklus-2")
        self.assertEqual(summary["uebertragen"], ["t-offen"])
        self.assertEqual(summary["zahlen"], {"angelegt": 3, "abgenommen": 1, "uebertragen": 1,
                                             "verworfen": 1, "carried_over": 1})
        # Die Tickets behalten ihre Staende; nichts wird still geschlossen.
        self.assertEqual(ad.read_ticket(self.world, "t-offen")["cycle"], "zyklus-2")
        self.assertEqual(ad.read_ticket(self.world, "t-offen")["state"], "offen")
        self.assertEqual(ad.read_ticket(self.world, "t-fertig")["cycle"], "zyklus-1")
        self.assertEqual(ad.read_ticket(self.world, "t-weg")["cycle"], "zyklus-1")
        self.assertEqual(ad.read_ticket(self.world, "t-ohne-zyklus")["cycle"], "zyklus-99")
        self.assertTrue(any(e["event"] == "uebertragen" for e in self.events("t-offen")))
        eintrag = json.loads((self.world / "zyklen.jsonl").read_text().splitlines()[-1])
        self.assertEqual((eintrag["id"], eintrag["angelegt"], eintrag["abgenommen"],
                          eintrag["uebertragen"], eintrag["verworfen"], eintrag["carried_over"]),
                         ("zyklus-1", 3, 1, 1, 1, 1))
        cycles = ad.read_world(self.world)["cycles"]
        self.assertEqual(cycles["current"]["id"], "zyklus-2")
        # Der neue Zyklus laeuft mit derselben Laenge (hier ein Tag) ab dem Schlusszeitpunkt.
        self.assertEqual(ad._epoch_of(cycles["current"]["end"]), ende + 60 + 86400)
        # Der Hauptagent bekommt die Zustellung mit den Zahlen und dem Retro-Auftrag.
        zustellung = self.world / "agents" / "main" / "postfach" / (summary["zustellung"] + ".json")
        self.assertTrue(zustellung.exists())
        text = json.loads(zustellung.read_text())["text"]
        self.assertIn("zyklus-1", text)
        self.assertIn("Retro", text)
        # Idempotent: der neue Zyklus laeuft noch; ein zweiter Schluss schliesst nichts.
        self.assertIsNone(ad.cycle_schluss(self.world, ende + 120))
        self.assertEqual(len((self.world / "zyklen.jsonl").read_text().splitlines()), 1)

    def test_world_without_cycle_is_untouched(self):
        self.ticket("t1", agent="m1", kind="auftrag")
        self.assertIsNone(ad.cycle_schluss(self.world, ad._epoch_of("2030-01-01T00:00:00Z")))
        self.assertFalse((self.world / "zyklen.jsonl").exists())
        self.assertNotIn("cycles", ad.read_world(self.world))

    def test_zyklus_cli(self):
        helper = _TicketCliHelper(self.world)
        world = helper("wb-welt", "zyklus", self.world, "einschalten", "--tage", "3",
                       "--ziel", "Kalender bauen", "--absender", "mensch")
        self.assertEqual((world["cycles"]["enabled"], world["cycles"]["current"]["goal"]),
                         (True, "Kalender bauen"))
        shown = helper("wb-welt", "zyklus", self.world, "zeigen")
        self.assertEqual(shown["current"]["id"], "zyklus-1")
        env = dict(os.environ, PYTHONPATH=str(HERE.parents[1]))
        text = subprocess.run([str(HERE.parents[1] / "wb-welt"), "zyklus", str(self.world), "zeigen"],
                              text=True, capture_output=True, env=env, timeout=60)
        self.assertIn("Zyklen an, Laenge 3 Tage", text.stdout)
        off = helper("wb-welt", "zyklus", self.world, "ausschalten", "--absender", "mensch")
        self.assertFalse(off["cycles"]["enabled"])
        with self.assertRaises(AssertionError):
            helper("wb-welt", "zyklus", self.world, "einschalten", "--absender", "m1")


class GrenzenTests(_TicketBasis):
    """Frist und Rundenzahl: Pruefung, Escalation und Loesung (Plan AGENTS-TICKETS-PLAN Saetze 6 und 31)."""

    def zug(self, ticket_id, run_id="zug-x", outcome="erfolg"):
        ad.record_run_outcome(self.world, ticket_id, run_id, outcome, "Probe")

    def test_escalation_by_rounds_and_idempotence(self):
        self.ticket("t1", agent="m1", limits={"runden": 2})
        self.assertEqual(ad.enforce_ticket_limits(self.world, 0), [])
        self.zug("t1", "zug-1")
        self.assertEqual(ad.enforce_ticket_limits(self.world, 0), [])
        self.zug("t1", "zug-2")
        escalated = ad.enforce_ticket_limits(self.world, 0)
        self.assertEqual(escalated, ["t1"])
        ticket = ad.read_ticket(self.world, "t1")
        self.assertEqual((ticket["state"], ticket["flag"]["question"], ticket["flag"]["vorher"]),
                         ("braucht dich", None, "offen"))
        self.assertIn("Rundenzahl 2 erreicht", ticket["flag"]["reason"])
        self.assertTrue(any(e["event"] == "braucht-dich" and e.get("frage") is None for e in self.events("t1")))
        # Idempotent und unveraenderlich, solange der Grund steht.
        self.assertEqual(ad.enforce_ticket_limits(self.world, 0), [])

    def test_escalation_by_expired_frist_incl_parked_and_open(self):
        self.ticket("t-offen", agent="m1", limits={"frist": "2026-09-01T00:00:00Z", "runden": 99})
        self.ticket("t-geparkt", agent="m1", limits={"frist": "2026-09-01T00:00:00Z", "runden": 99})
        self.ticket("t-reif", agent="m1", limits={"frist": "2026-09-01T00:00:00Z", "runden": 99})
        self.laeuft("t-geparkt", "m1")
        ad.park_ticket(self.world, "t-geparkt", "m1", "wartet", until=WECKZEIT,
                       sender="m1", claimed_role="mitglied")
        self.abnahme_reif("t-reif", "m1")
        escalated = ad.enforce_ticket_limits(self.world, ad._epoch_of("2026-09-02T00:00:00Z"))
        self.assertEqual(sorted(escalated), ["t-geparkt", "t-offen"])
        offen = ad.read_ticket(self.world, "t-offen")
        self.assertIn("Frist 2026-09-01T00:00:00Z abgelaufen", offen["flag"]["reason"])
        geparkt = ad.read_ticket(self.world, "t-geparkt")
        self.assertEqual((geparkt["state"], geparkt["flag"]["vorher"], geparkt.get("parked")),
                         ("braucht dich", "wartet", None))
        # Zur Abnahme stehende Tickets werden nicht gehoben.
        self.assertEqual(ad.read_ticket(self.world, "t-reif")["state"], "zur Abnahme")

    def test_running_ticket_is_spared_until_its_turn_ends(self):
        self.ticket("t1", agent="m1", limits={"frist": "2026-09-01T00:00:00Z"})
        self.laeuft("t1", "m1")
        escalated = ad.enforce_ticket_limits(self.world, ad._epoch_of("2026-09-02T00:00:00Z"),
                                             busy_ticket_ids={"t1"})
        self.assertEqual(escalated, [])
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "läuft")

    def test_set_ticket_limits_restores_the_previous_state(self):
        self.ticket("t1", agent="m1", limits={"runden": 1})
        self.zug("t1")
        ad.enforce_ticket_limits(self.world, 0)
        self.assertEqual(ad.read_ticket(self.world, "t1")["state"], "braucht dich")
        with self.assertRaises(ad.AgentsError):
            ad.set_ticket_limits(self.world, "t1", runden=5, sender="m1", claimed_role="mitglied")
        with self.assertRaises(ad.AgentsError):
            ad.set_ticket_limits(self.world, "t1", sender="mensch")
        with self.assertRaises(ad.AgentsError):
            ad.set_ticket_limits(self.world, "t1", runden=0, sender="mensch")
        with self.assertRaises(ad.AgentsError):
            ad.set_ticket_limits(self.world, "t1", frist="bald", sender="mensch")
        solved = ad.set_ticket_limits(self.world, "t1", runden=5, sender="mensch")
        self.assertEqual((solved["state"], solved["limits"]["runden"]), ("offen", 5))
        self.assertNotIn("flag", solved)
        self.assertTrue(any(e["event"] == "grenzen-geaendert" for e in self.events("t1")))
        zustellung = self.world / "agents" / "m1" / "postfach" / (ad.derived_id("ticket-grenzen", "t1") + ".json")
        self.assertTrue(zustellung.exists())
        # Ein laufendes Ticket kehrt auf seinen Stand zurück und wird dem Bearbeiter zugestellt.
        self.ticket("t2", agent="m1", limits={"runden": 1})
        self.laeuft("t2", "m1")
        self.zug("t2")
        ad.enforce_ticket_limits(self.world, 0)
        solved = ad.set_ticket_limits(self.world, "t2", frist="2026-10-01T00:00:00Z", sender="main",
                                      claimed_role="hauptagent")
        self.assertEqual((solved["state"], solved["assignee"]), ("läuft", "m1"))
        # Ohne gehobene Grenzen aendert ein Aufruf nur die Zahlen, ohne Zustellung und Stand.
        self.ticket("t3", agent="m1", kind="auftrag")
        before = ad.read_ticket(self.world, "t3")
        changed = ad.set_ticket_limits(self.world, "t3", frist="2026-10-01T00:00:00Z", sender="mensch")
        self.assertEqual(changed["state"], before["state"])
        self.assertFalse((self.world / "agents" / "m1" / "postfach" /
                          (ad.derived_id("ticket-grenzen", "t3") + ".json")).exists())

    def test_grenzen_cli_and_flag_from_a_question_is_not_touched(self):
        helper = _TicketCliHelper(self.world)
        self.ticket("t1", agent="m1", kind="auftrag")
        with self.assertRaises(AssertionError):
            helper("wb-ticket", "grenzen", self.world, "t1", "--frist", "morgen", "--absender", "mensch")
        solved = helper("wb-ticket", "grenzen", self.world, "t1", "--frist", "2026-10-01T00:00:00Z",
                        "--runden", "9", "--absender", "mensch")
        self.assertEqual(solved["limits"], {"frist": "2026-10-01T00:00:00Z", "runden": 9})
        # Eine Frage-Flagge eines Menschen wird von der Grenzloesung nicht angeruehrt.
        self.ticket("t2", agent="m1", kind="auftrag")
        self.laeuft("t2", "m1")
        question = ad.ask_question(self.world, "Weiter so?", ticket_id="t2",
                                   sender="main", claimed_role="hauptagent")
        ad.flag_ticket(self.world, "t2", question["id"], "brauche Antwort",
                       sender="main", claimed_role="hauptagent")
        self.assertEqual(ad.enforce_ticket_limits(self.world, 0), [])
        self.assertEqual(ad.read_ticket(self.world, "t2")["state"], "braucht dich")

    def test_deadline_state_ampel_in_the_snapshot(self):
        weit = self.ticket("t-grau", agent="m1", kind="auftrag",
                           limits={"frist": "2027-01-01T00:00:00Z"})
        # Die gelbe Frist liegt relativ zur Uhr (zwoelf Stunden voraus), sonst kippt der Test
        # nach Mitternacht auf rot (volle Suite 18.09.2026 nach 00:00 UTC).
        import datetime as _dt
        bald = (_dt.datetime.now(_dt.timezone.utc) + _dt.timedelta(hours=12)).strftime("%Y-%m-%dT%H:%M:%SZ")
        nah = self.ticket("t-gelb", agent="m1", kind="auftrag",
                          limits={"frist": bald})
        alt = self.ticket("t-rot", agent="m1", kind="auftrag",
                          limits={"frist": "2026-01-01T00:00:00Z"})
        self.ticket("t-ohne", agent="m1", kind="auftrag")
        snapshot = {t["id"]: t for t in ad.world_snapshot(self.world)["tickets"]}
        self.assertEqual((snapshot["t-grau"]["deadline_state"], snapshot["t-gelb"]["deadline_state"],
                          snapshot["t-rot"]["deadline_state"], snapshot["t-ohne"]["deadline_state"]),
                         ("grau", "gelb", "rot", None))


class MesswerteTests(_TicketBasis):
    """Durchlaufzeit, Zuege und Alter je Ticket im Snapshot (Plan Satz 50)."""

    def test_lead_time_turns_and_age_in_the_snapshot(self):
        self.ticket("t1", agent="m1", kind="auftrag")
        self.laeuft("t1", "m1")
        ad.record_run_outcome(self.world, "t1", "zug-1", "erfolg", "erster Zug")
        ad.record_run_outcome(self.world, "t1", "zug-2", "erfolg", "zweiter Zug")
        ad.write_result(self.world, "t1", "m1", "fertig", None, "m1", "mitglied")
        ad.approve_ticket(self.world, "t1", "main", "hauptagent", "passt")
        self.ticket("t2", agent="m1", kind="auftrag")
        snapshot = {t["id"]: t for t in ad.world_snapshot(self.world)["tickets"]}
        fertig = snapshot["t1"]
        self.assertGreaterEqual(fertig["lead_time_s"], 0)
        self.assertGreaterEqual(fertig["age_s"], fertig["lead_time_s"])
        self.assertEqual(fertig["turns"], 2)
        offen = snapshot["t2"]
        self.assertGreaterEqual(offen["age_s"], 0)
        self.assertLessEqual(offen["lead_time_s"], offen["age_s"])
        self.assertEqual(offen["turns"], 0)


class VorhabenEndeZuEndeTests(_TicketBasis):
    """Ende-zu-Ende (Auftrag tickets3): Vorhaben mit zwei Stories und Tasks, Zyklus, Übertrag,
    Abnahme und Ergebnis beim Menschen."""

    def test_vorhaben_mit_stories_und_zyklus(self):
        ad.set_cycle(self.world, True, tage=1, ziel="Vorhaben bauen", sender="mensch")
        self.eltern_vorhaben()
        self.story("s1", "m1", ["nutzbar"])
        self.story("s2", "m2", ["nutzbar"])
        self.task("tk1", "m1")
        self.task("tk2", "m2")
        # Beide Tasks abgenommen: die Story s1 geht auf "zur Abnahme".
        self.abnahme_reif("tk1", "m1")
        ad.approve_ticket(self.world, "tk1", "main", "hauptagent", "passt")
        self.abnahme_reif("tk2", "m2")
        ad.approve_ticket(self.world, "tk2", "main", "hauptagent", "passt")
        s1 = ad.read_ticket(self.world, "s1")
        self.assertEqual((s1["state"], s1["result"]["text"]), ("zur Abnahme", "Alle Kinder abgenommen: tk1, tk2"))
        self.assertEqual(ad.read_ticket(self.world, "v1")["state"], "offen")
        # Story s1 abgenommen; das Vorhaben wartet auf s2.
        ad.approve_ticket(self.world, "s1", "main", "hauptagent", "passt")
        self.assertEqual(ad.read_ticket(self.world, "v1")["state"], "offen")
        # Zyklusschluss: die offene Story s2 (und das offene Vorhaben) wandern in den neuen Zyklus.
        ende = ad._epoch_of(ad.read_world(self.world)["cycles"]["current"]["end"])
        summary = ad.cycle_schluss(self.world, ende + 60)
        self.assertEqual(summary["uebertragen"], ["s2", "v1"])
        self.assertEqual(summary["zahlen"]["carried_over"], 2)
        self.assertEqual(ad.read_ticket(self.world, "s2")["cycle"], "zyklus-2")
        self.assertEqual(ad.read_ticket(self.world, "s2")["state"], "offen")
        self.assertEqual(ad.read_ticket(self.world, "v1")["cycle"], "zyklus-2")
        # Danach abgenommen: Vorhaben auf "zur Abnahme", abgenommen, Ergebnis beim Menschen.
        ad.claim_ticket(self.world, "s2", "m2", "m2", "mitglied")
        ad.check_done_item(self.world, "s2", "m2", 1, sender="m2", claimed_role="mitglied")
        ad.write_result(self.world, "s2", "m2", "nutzbar geliefert", None, "m2", "mitglied")
        ad.approve_ticket(self.world, "s2", "main", "hauptagent", "passt")
        v1 = ad.read_ticket(self.world, "v1")
        self.assertEqual((v1["state"], v1["result"]["agent"]), ("zur Abnahme", "system"))
        ad.approve_ticket(self.world, "v1", "main", "hauptagent", "Vorhaben fertig")
        message_id = ad.derived_id("vorhaben-ergebnis", "v1", 0)
        stored = json.loads((self.world / "menschen" / "mensch" / "postfach" / (message_id + ".json")).read_text())
        self.assertEqual(stored["mark"], "ergebnis")
        self.assertIn("Vorhaben v1", stored["text"])
        # Der Zyklusschluss hat dem Hauptagenten die Retro-Zustellung gebracht.
        zustellung = self.world / "agents" / "main" / "postfach" / (summary["zustellung"] + ".json")
        self.assertIn("Retro", json.loads(zustellung.read_text())["text"])
        eintraege = [json.loads(line) for line in (self.world / "zyklen.jsonl").read_text().splitlines()]
        self.assertEqual((eintraege[0]["angelegt"], eintraege[0]["abgenommen"],
                          eintraege[0]["uebertragen"]), (5, 3, 2))

    def eltern_vorhaben(self):
        ticket = self.ticket("v1", agent="main", kind="vorhaben")
        self.assertEqual(ticket["cycle"], "zyklus-1")
        return ticket

    def story(self, ticket_id, agent, punkte):
        return self.ticket(ticket_id, agent=agent, kind="story", parent="v1", done_items=punkte,
                           limits={"runden": 9})

    def task(self, ticket_id, agent):
        return self.ticket(ticket_id, agent=agent, kind="task", parent="s1", done_items=[],
                           limits={"runden": 9})


if __name__ == "__main__":
    unittest.main()
