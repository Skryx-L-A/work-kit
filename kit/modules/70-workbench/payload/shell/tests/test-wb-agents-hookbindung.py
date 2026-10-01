#!/usr/bin/env python3
"""Bindungsvertrag zwischen Traeger und zugbasiertem Linux-Launcher."""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

SHELL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHELL))

import agents_claude_lauf as acl  # noqa: E402
import agents_data as ad  # noqa: E402
import agents_traeger as at  # noqa: E402


MODEL = "claude-haiku-4-5-20251001"


class VerfuegbareAnmeldung:
    def status(self):
        return {"kind": "test", "available": True, "reason": None}

    def auth_headers(self):
        return (("Authorization", "Bearer test"),)


class HookbindungTest(unittest.TestCase):
    def test_launcher_rejects_an_unbound_agent_turn_before_starting_resources(self):
        lauf = object.__new__(acl.ClaudeLauf)
        lauf.handle = None
        lauf.zug = SimpleNamespace(extra_env=(("WB_AGENT_ZUG", "/state/zug-1"),))

        with mock.patch.object(acl, "_private_dir") as private_dir:
            with self.assertRaisesRegex(acl.LinuxLauncherFehler,
                                        "Agentenzug ohne Bindung.*WB_AGENT_ID.*WB_WELT"):
                acl.ClaudeLauf.start(lauf)
            private_dir.assert_not_called()

    def test_linux_launcher_validation_rejects_a_spec_without_bindings(self):
        launcher = object.__new__(acl.ClaudeZugLauncher)
        spec = acl.StartSpec(("/usr/bin/true",), "/tmp", (("WB_AGENT_ZUG", "/state/zug-1"),))

        with mock.patch.object(acl.LinuxLauncher, "_validate_spec") as basis:
            with self.assertRaisesRegex(acl.LinuxLauncherFehler,
                                        "Agentenzug ohne Bindung.*WB_AGENT_ID.*WB_WELT"):
                launcher._validate_spec(spec)
            basis.assert_called_once_with(spec)

    def test_carrier_records_a_missing_binding_as_start_error_without_calling_factory(self):
        with tempfile.TemporaryDirectory(prefix="agents-hookbindung-") as tmp:
            root = Path(tmp)
            os.chmod(root, 0o700)
            world = root / "world"
            ad.create_world(world, name="Bindungsprobe", main_name="haupt", sender="cli-operator")
            ad.create_agent(world, "a1", "mitglied", None, "Probe", None, None, MODEL, None, None, None,
                            "host2", "haupt", "hauptagent")
            ad.create_ticket(world, "Bindungsprobe", "Zug starten", "fertig", ["a1"], "haupt", "hauptagent",
                             ticket_id="bindung", kind="auftrag")
            konfig = at.TraegerKonfig(world, root / "state", root / "agents", "/opt/claude/claude", "host2",
                                      {"kind": "setup-token", "path": "/nonexistent"})
            fabrik_aufrufe = []

            def fabrik(*_args, **_kwargs):
                fabrik_aufrufe.append(True)
                raise AssertionError("Zugfabrik darf ohne Bindung nicht aufgerufen werden")

            with mock.patch.dict(os.environ, {"WB_AGENTS_ZUSTAND": str(root / "autostart"),
                                              "WB_AGENTS_UNIT_DIR": str(root / "units")}):
                traeger = at.WeltTraeger(konfig, zug_fabrik=fabrik, observer_fabrik=lambda _traeger: object(),
                                         anmeldequelle=VerfuegbareAnmeldung(), kontingentquelle=None,
                                         zeitgeber=lambda _value: None, runtime_quelle=SHELL)
                original_profil = at.ask.profil_umgebung
                original_skills = at.ask.skills_umgebung

                def profil_ohne_welt(*args, **kwargs):
                    env = original_profil(*args, **kwargs)
                    env.pop("WB_WELT", None)
                    return env

                def skills_ohne_welt(*args, **kwargs):
                    env = original_skills(*args, **kwargs)
                    env.pop("WB_WELT", None)
                    return env

                with mock.patch.object(at.ask, "profil_umgebung", side_effect=profil_ohne_welt), \
                     mock.patch.object(at.ask, "skills_umgebung", side_effect=skills_ohne_welt):
                    summary = traeger.einmal()

            self.assertEqual(fabrik_aufrufe, [])
            self.assertEqual(summary["gestartet"], [])
            entries = list(traeger._zuege_lesen()["runs"].values())
            self.assertEqual(len(entries), 1)
            self.assertEqual(entries[0]["outcome"], "startfehler")
            self.assertRegex(entries[0]["detail"], "Agentenzug ohne Bindung.*WB_AGENT_ID.*WB_WELT")
            self.assertIsNotNone(entries[0]["folge"].get("recovery"), "Startfehler behaelt die Recovery-Regel")


if __name__ == "__main__":
    unittest.main()
