#!/usr/bin/env python3
"""Isolierte Vertragsproben fuer die Denkstufe je Harness (shell/agents_denkstufe.py)."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

SHELL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SHELL))

import agents_denkstufe as dk  # noqa: E402


class DenkstufeTest(unittest.TestCase):
    def test_builtin_spelling_for_claude_codex_and_pi(self):
        self.assertEqual(dk.denkstufe_argumente("claude", "xhigh")[0], ["--effort", "xhigh"])
        self.assertEqual(dk.denkstufe_argumente("codex", "high")[0], ["--config", "model_reasoning_effort=high"])
        self.assertEqual(dk.denkstufe_argumente("pi", "low")[0], ["--thinking", "low"])
        args, befund = dk.denkstufe_argumente("claude", None)
        self.assertEqual((args, befund["wirksam"]), ([], None))
        with self.assertRaises(dk.DenkstufeFehler):
            dk.denkstufe_argumente("claude", "ultra")
        with self.assertRaises(dk.DenkstufeFehler):
            dk.denkstufe_argumente("unbekannt", "low")

    def test_registry_spelling_and_model_limits_only_lower_the_level(self):
        registry = {
            "harnesses": [{"id": "codex", "effort": {"style": "arg", "args": ["-c", "model_reasoning_effort={effort}"],
                                                     "map": {"low": "low", "medium": "medium", "high": "high"}}},
                          {"id": "goose", "effort": {"style": "none", "args": [], "map": {}}}],
            "models": [{"id": "claude-opus-5", "maxEffort": "high"}, {"id": "gpt-5-codex", "efforts": ["low", "medium"]},
                       {"id": "klein", "supportsEffort": False}],
        }
        args, befund = dk.denkstufe_argumente("claude", "xhigh", modell="claude-opus-5", registry=registry)
        self.assertEqual((args, befund["gesenkt"], befund["wirksam"]), (["--effort", "high"], True, "high"))
        self.assertEqual(dk.denkstufe_argumente("claude", "low", modell="claude-opus-5", registry=registry)[0],
                         ["--effort", "low"])
        args, befund = dk.denkstufe_argumente("codex", "xhigh", modell="gpt-5-codex", registry=registry)
        self.assertEqual((args, befund["quelle"]), (["-c", "model_reasoning_effort=medium"], "registry"))
        self.assertEqual(dk.denkstufe_argumente("claude", "high", modell="klein", registry=registry)[1]["grund"],
                         "modell_ohne_stufe")
        self.assertEqual(dk.denkstufe_argumente("goose", "high", registry=registry)[0], [])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "models.json"
            self.assertIsNone(dk.registry_laden(path))
            path.write_text(json.dumps(registry))
            self.assertEqual(dk.registry_laden(path)["models"][0]["id"], "claude-opus-5")
            path.write_text("{")
            self.assertIsNone(dk.registry_laden(path))


if __name__ == "__main__":
    unittest.main()
