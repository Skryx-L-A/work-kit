#!/usr/bin/env python3
"""Isolated resolver/shim regression: roles, exact model IDs and shell quoting."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SHELL = Path(__file__).resolve().parents[1]


class ModelSelection(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="wb-modelwahl-")
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / ".local/bin"
        self.bin.mkdir(parents=True)
        self.work = self.home / "project with spaces"
        self.work.mkdir()
        self.original = "Project rules\n<!-- wb-rolle worker anfang -->\nold worker\n<!-- wb-rolle worker ende -->\n"
        (self.work / "AGENTS.md").write_text(self.original)
        for name in ("wb-state", "wb-harness-run"):
            shutil.copy2(SHELL / name, self.bin / name)
        hook = self.bin / "wb-chat-hook-install"
        hook.write_text("#!/bin/sh\nexit 0\n")
        hook.chmod(0o755)
        self.cli = self.bin / "fixture-cli"
        self.cli.write_text("#!/usr/bin/env python3\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n")
        self.cli.chmod(0o755)
        self.roles = {}
        for role in ("worker", "orchestrator"):
            text = role + '\nQuotes: " \' $HOME $(touch SHOULD_NOT_EXIST) `false` Grüße\\end\n'
            path = self.home / (role + ".md")
            path.write_text(text)
            self.roles[role] = str(path)
        self.registry = self.home / ".claude/workbench/models.json"
        self.registry.parent.mkdir(parents=True)
        self.data = {
            "version": 1,
            "providers": [{"id": "fixture", "kind": "subscription"}],
            "harnesses": [{"id": "fixture", "command": str(self.cli),
                "args": ["--model", "{model}"], "readyPattern": "^ready",
                "effort": {"style": "arg", "args": ["--effort", "{effort}"],
                           "map": {e: e for e in ("low", "medium", "high")}},
                "systemPrompt": {"style": "config-content", "flag": "-c",
                    "key": "developer_instructions", **self.roles}}],
            "models": [{"id": "chosen", "modelRef": "provider/exact-model",
                "provider": "fixture", "harness": "fixture", "maxEffort": "high"}]
        }
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(("WB_", "TMUX", "CLAUDE"))}
        self.env.update(HOME=str(self.home), PATH=str(self.bin) + ":/opt/homebrew/bin:/usr/bin:/bin",
                        WB_NO_DISCOVER="1")

    def launch(self, role="orchestrator", effort="medium"):
        self.registry.write_text(json.dumps(self.data))
        return subprocess.run([str(self.bin / "wb-harness-run"), "--model", "chosen",
            "--role", role, "--effort", effort, "--dir", str(self.work)],
            env=self.env, cwd=self.work, text=True, capture_output=True, timeout=15)

    def test_both_roles_in_same_directory_preserve_project(self):
        for role in self.roles:
            for effort in ("low", "medium", "high"):
                with self.subTest(role=role, effort=effort):
                    result = self.launch(role, effort)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    args = json.loads(result.stdout)
                    self.assertEqual(args[args.index("--model") + 1], "provider/exact-model")
                    self.assertEqual(args[args.index("--effort") + 1], effort)
                    config = args[args.index("-c") + 1]
                    self.assertEqual(json.loads(config.split("=", 1)[1]), Path(self.roles[role]).read_text())
                    self.assertEqual((self.work / "AGENTS.md").read_text(), self.original)
                    self.assertFalse((self.work / "SHOULD_NOT_EXIST").exists())

    def test_old_file_contract_reproduces_conflict(self):
        self.data["harnesses"][0]["systemPrompt"].update(style="file", projectPath="AGENTS.md")
        result = self.launch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("traegt bereits die Rolle worker", result.stderr)

    def test_missing_role_fails_before_cli(self):
        Path(self.roles["orchestrator"]).unlink()
        result = self.launch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Rollendatei", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_invalid_effort_rejected(self):
        result = self.launch(effort="max")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def selection(self, harness="", model="chosen"):
        self.registry.write_text(json.dumps(self.data))
        (self.registry.parent / "settings.json").write_text(json.dumps({
            "orchestratorHarness": "claude", "orchestratorModel": model}))
        source = (SHELL / "wb-code").read_text()
        start = source.index('# V3 (SPEC-V3 C): `--model')
        end = source.index('# ── Die Stufe, mit der der ORCHESTRATOR')
        program = 'set -eu\nMODEL=""; MODEL_FLAG=""; EFFORT=""; RESUME=""\n'
        program += 'HARNESS="$1"; HARNESS_FLAG="$1"\n' + source[start:end]
        program += '\nprintf "%s %s" "$HARNESS" "$MODEL"\n'
        return subprocess.run(["bash", "-c", program, "fixture", harness],
            env=self.env, cwd=self.work, text=True, capture_output=True, timeout=15)

    def test_saved_model_selects_its_adapter(self):
        result = self.selection()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "fixture chosen")

    def test_explicit_wrong_builtin_adapter_rejected(self):
        for harness in ("claude", "pi"):
            result = self.selection(harness)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("gehoert zu Harness", result.stderr)

    def test_human_levels_below_cap_pass_preflight(self):
        self.registry.write_text(json.dumps(self.data))
        source = (SHELL / "wb-code").read_text()
        start = source.index('  if [ -n "$MENSCH" ]; then', source.index('elif [ "$HARNESS" != "claude" ]; then'))
        end = source.index('  $HOME/.local/bin/wb-state models resolve', start)
        for effort, accepted in (("low", True), ("medium", True), ("high", True), ("max", False)):
            script = 'set -eu\nMENSCH=1; MODEL=chosen; HARNESS=fixture; EFFORT="$1"\n'
            result = subprocess.run(["bash", "-c", script + source[start:end], "fixture", effort],
                                    env=self.env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode == 0, accepted, result.stderr)

    def test_every_shipped_adapter_preserves_model_reference(self):
        defaults = json.loads((SHELL / "models.default.json").read_text())
        for original in defaults["harnesses"]:
            with self.subTest(harness=original["id"]):
                # Run the actual argument and role contract, with external dependencies isolated.
                h = dict(original)
                h.update(command=str(self.cli), readyPattern="^ready", configFiles=[],
                         trustStore={}, session={}, env={})
                sp = dict(h.get("systemPrompt") or {})
                sp.update(self.roles)
                h["systemPrompt"] = sp
                self.data["harnesses"] = [h]
                self.data["models"][0]["harness"] = h["id"]
                levels = list((h.get("effort") or {}).get("map") or {})
                effort = "medium" if "medium" in levels or not levels else levels[0]
                self.registry.write_text(json.dumps(self.data))
                result = subprocess.run([str(self.bin / "wb-state"), "models", "resolve", "chosen",
                    "--role", "orchestrator", "--effort", effort, "--dir", str(self.work)],
                    env=self.env, cwd=self.work, text=True, capture_output=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("model\tprovider/exact-model\n", result.stdout)

    def test_shipped_registry_is_laptop_only_and_routable(self):
        # Kit: the shipped registry holds the 15-local-llm catalog (provider kit-llm, one pi and
        # one aider entry per model) and a few public cloud ids per harness, nothing else.
        defaults = json.loads((SHELL / "models.default.json").read_text())
        harnesses = {h["id"]: h for h in defaults["harnesses"]}
        providers = {p["id"] for p in defaults["providers"]}
        models = {m["id"]: m for m in defaults["models"]}
        for m in models.values():
            with self.subTest(model=m["id"]):
                self.assertIn(m["harness"], harnesses)
                self.assertIn(m["provider"], providers)
                emap = (harnesses[m["harness"]].get("effort") or {}).get("map") or {}
                for e in m.get("efforts") or []:
                    self.assertIn(e, emap)
                for w in m.get("workerClass", []):
                    if isinstance(w, dict) and m.get("efforts"):
                        self.assertIn(w["effort"], m["efforts"])
        # Every orchestrator default names a shipped model (id, alias or family alias).
        for hid, h in harnesses.items():
            want = h.get("orchestratorDefaultModel")
            if not want:
                continue
            with self.subTest(harness=hid):
                hit = [m for m in models.values() if want in (m["id"], m.get("alias"))
                       or (m["harness"] == hid and m["modelRef"].startswith("%s-%s-" % (hid, want)))]
                self.assertTrue(hit, "%s: orchestratorDefaultModel %r is not shipped" % (hid, want))
                self.assertTrue(any(m.get("enabled") and "orchestrator" in m.get("roles", []) for m in hit))
        self.assertEqual(harnesses["codex"]["orchestratorDefaultModel"], "codex-gpt-5-5")
        # Local models: each catalog entry once for pi and once for aider, data stays local.
        local = {m["id"]: m for m in models.values() if m["provider"] == "kit-llm"}
        pi_ids = {i for i, m in local.items() if m["harness"] == "pi"}
        self.assertTrue(pi_ids)
        for i in pi_ids:
            self.assertEqual(local["aider-" + i]["modelRef"], "openai/" + i)
            self.assertTrue(local[i]["dataStaysLocal"] and local["aider-" + i]["dataStaysLocal"])
        catalog = SHELL.parents[1] / "port/registry/kit-registry.json"
        if catalog.is_file():  # in the kit repository: same set as the 15-local-llm catalog
            src = json.loads(catalog.read_text())
            self.assertEqual(pi_ids, {c["id"] for c in src["localModels"]["catalog"]})
            self.assertEqual({i for i, m in models.items() if m["provider"] != "kit-llm"},
                             {m["id"] for m in src["models"]})
        # Capability routing still has a model for the classes the roles route by.
        classes = {w["class"] if isinstance(w, dict) else w
                   for m in models.values() if m.get("enabled") for w in m.get("workerClass", [])}
        self.assertTrue({"mechanisch", "bulk", "coding-kurz", "coding-lang", "reasoning", "review",
                         "recherche", "zweitmeinung"} <= classes, classes)

if __name__ == "__main__":
    unittest.main()
