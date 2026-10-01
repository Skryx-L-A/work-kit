#!/usr/bin/env python3
"""Isolierte Vertragsproben fuer die naechste erlaubte Startzeit (shell/agents_kontingent.py)."""

from __future__ import annotations

import datetime as dt
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHELL))

import agents_kontingent as ak  # noqa: E402

UTC = dt.timezone.utc


def epoch(text: str) -> float:
    return dt.datetime.fromisoformat(text).replace(tzinfo=UTC).timestamp()


class Result:
    def __init__(self, stdout: str, returncode: int = 0):
        self.stdout = stdout
        self.returncode = returncode


class KontingentTest(unittest.TestCase):
    # Fenster von Montag 14. September 14:00 bis Montag 21. September 14:00 (UTC fuer den Test).
    reset = epoch("2026-09-21T14:00:00")

    def budget(self, week, five=0.0, five_reset=None):
        return {"five_hour_pct": five, "five_hour_resets_at_epoch": five_reset,
                "seven_day_pct": week, "seven_day_resets_at_epoch": self.reset}

    def test_five_hour_week_and_daily_budget_are_separate_limits(self):
        now = epoch("2026-09-16T10:00:00")  # Mittwoch = Tag 3, Linie 42,9 %
        self.assertEqual(ak.aus_budget(self.budget(40), now, UTC), [])
        five = ak.aus_budget(self.budget(10, five=100, five_reset=now + 1800), now, UTC)
        self.assertEqual([(item.grund, item.bis) for item in five], [("fuenf_stunden", now + 1800)])
        self.assertEqual(ak.aus_budget(self.budget(10, five=100, five_reset=now - 5), now, UTC), [])
        week = ak.aus_budget(self.budget(100), now, UTC)
        self.assertEqual([(item.grund, item.bis) for item in week], [("wochenfenster", self.reset)])
        for used, day in ((50, "2026-09-17"), (80, "2026-09-19"), (99, "2026-09-20")):
            with self.subTest(used=used):
                daily = ak.aus_budget(self.budget(used), now, UTC)
                self.assertEqual([(item.grund, item.bis) for item in daily],
                                 [("tagesbudget", epoch(day + "T00:00:00"))])
        both = ak.aus_budget(self.budget(80, five=100, five_reset=now + 600), now, UTC)
        self.assertEqual(sorted(item.grund for item in both), ["fuenf_stunden", "tagesbudget"])
        self.assertEqual(ak.naechster_start(both, now), epoch("2026-09-19T00:00:00"))

    def test_kontingent_observation_and_backend_rejection(self):
        now = epoch("2026-09-16T10:00:00")
        data = {"harnesses": {"claude": {"erschoepft": True, "kontingent": {"faellt_zurueck_am": "2026-09-16T12:00:00Z"}}},
                "beobachtungen": {"claude": {"zustand": "erschoepft", "faellt_zurueck_am": "2026-09-16T13:00:00Z"},
                                  "codex": {"zustand": "erschoepft", "faellt_zurueck_am": ""}}}
        found = ak.aus_kontingent(data, now)
        self.assertEqual([(item.quelle, item.bis) for item in found],
                         [("wb-kontingent erschoepft", epoch("2026-09-16T12:00:00")),
                          ("wb-kontingent Beobachtung", epoch("2026-09-16T13:00:00"))])
        expired = {"beobachtungen": {"claude": {"zustand": "erschoepft", "faellt_zurueck_am": "2026-09-16T09:00:00Z"}}}
        self.assertEqual(ak.aus_kontingent(expired, now), [])
        stream = ak.aus_backend({"status": "rejected", "resetsAt": now + 900, "rateLimitType": "five_hour"}, None, now)
        self.assertEqual([(item.grund, item.bis, item.quelle) for item in stream], [("backend", now + 900, "429 five_hour")])
        headers = ak.aus_backend(None, {"at": now, "headers": {"retry-after": "120",
                                                              "anthropic-ratelimit-unified-reset": str(int(now + 60))}}, now)
        self.assertEqual(headers[0].bis, now + 120)
        unknown = ak.aus_backend(None, None, now)
        self.assertEqual(unknown[0].bis, None)
        self.assertEqual(ak.naechster_start(unknown, now), now + ak.RECHECK_S)
        self.assertIsNone(ak.naechster_start([], now))

    def test_source_reads_tools_and_unreadable_sources_never_block_alone(self):
        now = epoch("2026-09-16T10:00:00")
        calls = []

        def runner(command, **kwargs):
            calls.append((command, sorted(kwargs["env"])))
            if command[0] == "wb-budget":
                return Result(json.dumps({"fehler": "kein brauchbarer Limitstand"}), 3)
            raise subprocess.TimeoutExpired(command, 1)

        source = ak.KontingentQuelle(runner=runner, clock=lambda: now, tz=UTC)
        free = source.freigabe()
        self.assertEqual((free.erlaubt, free.naechster_start, free.unbekannt), (True, None, ("wb-budget", "wb-kontingent")))
        self.assertEqual([command for command, _ in calls], [["wb-budget", "--json"], ["wb-kontingent", "zeigen", "--json"]])
        self.assertEqual(calls[0][1], ["HOME", "LANG", "PATH"])
        rejected = source.freigabe(backend_abgewiesen=True, rate_limit={"status": "rejected", "resetsAt": now + 300})
        self.assertEqual((rejected.erlaubt, rejected.naechster_start), (False, now + 300))
        credential = source.freigabe(anmeldung_fehlt=True)
        self.assertEqual((credential.erlaubt, credential.naechster_start), (False, now + ak.RECHECK_S))

        def healthy(command, **_kwargs):
            if command[0] == "wb-budget":
                return Result(json.dumps(self.budget(80, five=100, five_reset=now + 600)), 1)
            return Result(json.dumps({"harnesses": {"claude": {"erschoepft": False}}}))

        blocked = ak.KontingentQuelle(runner=healthy, clock=lambda: now, tz=UTC).freigabe()
        self.assertFalse(blocked.erlaubt)
        self.assertEqual(blocked.naechster_start, epoch("2026-09-19T00:00:00"))
        self.assertEqual(json.loads(json.dumps(blocked.as_dict()))["sperren"][0]["grund"], "fuenf_stunden")

    def test_limits_file_counts_only_when_younger_than_an_hour(self):
        now = epoch("2026-09-16T10:00:00")
        with tempfile.TemporaryDirectory(prefix="agents-kontingent-") as tmp:
            path = Path(tmp) / "limits-latest.json"

            def write(age_s, five=100.0, **extra):
                stamp = dt.datetime.fromtimestamp(now - age_s, UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
                path.write_text(json.dumps(dict({"ts": stamp, "five_hour_pct": five,
                                                 "five_hour_resets_at": str(int(now + 1200)),
                                                 "seven_day_pct": 10, "seven_day_resets_at": str(int(self.reset))},
                                                **extra)))

            def never(command, **_kwargs):
                raise AssertionError("keine Werkzeuge konfiguriert: %s" % command)

            source = ak.KontingentQuelle(None, None, runner=never, clock=lambda: now, tz=UTC, limits_path=path)
            missing = source.freigabe()
            self.assertEqual((missing.erlaubt, missing.unbekannt), (True, ("limits-latest",)))
            self.assertEqual((source.quelle()["art"], source.quelle()["grund"]), ("backend", "limits_fehlen"))
            write(600)
            fresh = source.freigabe()
            self.assertEqual((fresh.erlaubt, fresh.naechster_start), (False, now + 1200))
            self.assertEqual([(item.grund, item.quelle) for item in fresh.sperren],
                             [("fuenf_stunden", "limits-latest five_hour_pct")])
            self.assertEqual(fresh.quelle, {"art": "limits-latest", "limits": str(path), "alter_s": 600,
                                            "werkzeuge": []})
            write(3700)
            old = source.freigabe()
            self.assertEqual((old.erlaubt, old.unbekannt), (True, ("limits-latest",)))
            self.assertEqual((old.quelle["art"], old.quelle["grund"], old.quelle["alter_s"]),
                             ("backend", "limits_zu_alt", 3700))
            rejected = source.freigabe(backend_abgewiesen=True, rate_limit={"status": "rejected",
                                                                            "resetsAt": now + 90})
            self.assertEqual((rejected.erlaubt, rejected.naechster_start), (False, now + 90))
            write(10, five=0.0)
            self.assertTrue(source.freigabe().erlaubt)
            path.write_text(json.dumps({"five_hour_pct": 100}))
            self.assertEqual(source.quelle()["grund"], "limits_ohne_zeit")
            path.write_text("{")
            self.assertEqual(source.quelle()["grund"], "limits_unlesbar")
            self.assertEqual(ak.KontingentQuelle(None, None, clock=lambda: now).quelle(),
                             {"art": "backend", "werkzeuge": []})


if __name__ == "__main__":
    unittest.main()
