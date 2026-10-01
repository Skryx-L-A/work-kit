"""Tests for the pin-protection settings of kit-sync (no self-update, no analytics) and the pi
adapter. Every test uses a temp HOME. Run: python3 -m unittest discover -s tests -v."""
import json
import unittest

from test_settings import Base


KIT_CLAUDE_ENV = {"DISABLE_AUTOUPDATER": "1", "DISABLE_TELEMETRY": "1", "DISABLE_ERROR_REPORTING": "1"}


class PinsTest(Base):
    def test_every_harness_gets_its_pin(self):
        self.run_sync("--all")
        self.assertEqual(self.jload(".claude/settings.json")["env"], KIT_CLAUDE_ENV)
        toml = (self.home / ".codex/config.toml").read_text()
        self.assertIn("check_for_update_on_startup = false", toml)
        self.assertIs(self.jload(".config/opencode/opencode.json")["autoupdate"], False)
        self.assertIs(self.jload(".gemini/settings.json")["general"]["enableAutoUpdate"], False)
        self.assertIs(self.jload(".copilot/settings.json")["autoUpdate"], False)
        aider = (self.home / ".aider.conf.yml").read_text()
        self.assertIn("check-update: false", aider)
        self.assertIn("analytics-disable: true", aider)
        self.assertIn("auto-commits: false", aider)
        self.assertIn("dirty-commits: false", aider)
        self.assertIn("attribute-co-authored-by: false", aider)
        self.assertIs(self.jload(".pi/agent/settings.json")["enableInstallTelemetry"], False)

    def test_codex_toml_is_valid_and_top_level(self):
        self.run_sync("--harness", "codex")
        cfg = self.home / ".codex/config.toml"
        try:
            import tomllib
        except ImportError:
            self.skipTest("tomllib needs Python 3.11+")
        data = tomllib.loads(cfg.read_text())
        self.assertIs(data["check_for_update_on_startup"], False)
        self.assertEqual(data["analytics"], {"enabled": False})
        self.assertEqual(data["approval_policy"], "never")

    def test_pins_do_not_depend_on_the_approval_mode(self):
        self.run_sync("--all", "--permissions", "ask")
        self.assertEqual(self.jload(".claude/settings.json")["env"], KIT_CLAUDE_ENV)
        self.assertIs(self.jload(".gemini/settings.json")["privacy"]["usageStatisticsEnabled"], False)
        self.assertIn("auto-commits: false", (self.home / ".aider.conf.yml").read_text())
        self.assertIn("check_for_update_on_startup = false", (self.home / ".codex/config.toml").read_text())
        self.assertIs(self.jload(".config/opencode/opencode.json")["autoupdate"], False)
        self.assertIs(self.jload(".gemini/settings.json")["general"]["enableAutoUpdate"], False)
        self.assertIn("check-update: false", (self.home / ".aider.conf.yml").read_text())

    def test_user_values_are_kept(self):
        for rel, data in {".claude/settings.json": {"env": {"DISABLE_AUTOUPDATER": "0", "FOO": "bar", "DISABLE_TELEMETRY": "0"}},
                          ".config/opencode/opencode.json": {"autoupdate": "notify"},
                          ".gemini/settings.json": {"general": {"enableAutoUpdate": True},
                                                    "privacy": {"usageStatisticsEnabled": True}},
                          ".copilot/settings.json": {"autoUpdate": True},
                          ".pi/agent/settings.json": {"enableInstallTelemetry": True}}.items():
            (self.home / rel).parent.mkdir(parents=True, exist_ok=True)
            (self.home / rel).write_text(json.dumps(data))
        (self.home / ".codex").mkdir()
        (self.home / ".codex/config.toml").write_text("check_for_update_on_startup = true\n[analytics]\nenabled = true\n")
        (self.home / ".aider.conf.yml").write_text("check-update: true\nanalytics-disable: false\n"
                                                   "auto-commits: true\ndirty-commits: true\n")
        r = self.run_sync("--all")
        self.assertIn("is your value", r.stdout)
        self.assertEqual(self.jload(".claude/settings.json")["env"],
                         {"DISABLE_AUTOUPDATER": "0", "FOO": "bar", "DISABLE_TELEMETRY": "0",
                          "DISABLE_ERROR_REPORTING": "1"})
        self.assertEqual(self.jload(".config/opencode/opencode.json")["autoupdate"], "notify")
        self.assertIs(self.jload(".gemini/settings.json")["general"]["enableAutoUpdate"], True)
        self.assertIs(self.jload(".gemini/settings.json")["privacy"]["usageStatisticsEnabled"], True)
        self.assertIs(self.jload(".copilot/settings.json")["autoUpdate"], True)
        self.assertIs(self.jload(".pi/agent/settings.json")["enableInstallTelemetry"], True)
        toml = (self.home / ".codex/config.toml").read_text()
        self.assertEqual(toml.count("check_for_update_on_startup"), 1)
        self.assertIn("check_for_update_on_startup = true", toml)
        self.assertEqual(toml.count("analytics"), 1)  # your [analytics] table wins, no clash
        self.assertIn("enabled = true", toml)
        aider = (self.home / ".aider.conf.yml").read_text()
        self.assertEqual(aider.count("check-update"), 1)
        self.assertIn("check-update: true", aider)
        self.assertEqual(aider.count("analytics-disable"), 1)
        self.assertIn("analytics-disable: false", aider)
        self.assertEqual(aider.count("auto-commits"), 1)
        self.assertIn("auto-commits: true", aider)
        self.assertEqual(aider.count("dirty-commits"), 1)
        self.assertIn("dirty-commits: true", aider)

    def test_uninstall_removes_only_kit_keys(self):
        cfg = self.home / ".claude/settings.json"
        cfg.parent.mkdir()
        cfg.write_text(json.dumps({"env": {"FOO": "bar"}, "model": "x"}))
        self.run_sync("--harness", "claude,gemini,opencode,copilot,pi")
        self.assertEqual(self.jload(".claude/settings.json")["env"], {"FOO": "bar", **KIT_CLAUDE_ENV})
        g = self.home / ".gemini/settings.json"
        data = json.loads(g.read_text())
        data["general"]["theme"] = "dark"
        g.write_text(json.dumps(data))
        self.run_sync("--uninstall")
        self.assertEqual(self.jload(".claude/settings.json"), {"env": {"FOO": "bar"}, "model": "x"})
        self.assertEqual(self.jload(".gemini/settings.json"), {"general": {"theme": "dark"}})
        for rel in (".config/opencode/opencode.json", ".copilot/settings.json", ".pi/agent/settings.json"):
            self.assertFalse((self.home / rel).exists(), rel)

    def test_uninstall_keeps_a_value_changed_after_sync(self):
        self.run_sync("--harness", "opencode")
        f = self.home / ".config/opencode/opencode.json"
        data = json.loads(f.read_text())
        data["autoupdate"] = True
        f.write_text(json.dumps(data))
        self.run_sync("--uninstall")
        self.assertIs(self.jload(".config/opencode/opencode.json")["autoupdate"], True)

    def test_rerun_is_idempotent(self):
        self.run_sync("--all")
        r = self.run_sync("--all")
        for verb in ("[update]", "[create]", "[keep]"):
            self.assertNotIn(verb, r.stdout)
        self.assertEqual(list(self.home.rglob("*.bak-*")), [])


class TelemetryTest(Base):
    """One test per telemetry key, plus the harnesses that get none."""

    def test_claude_env_keys_and_no_update_block(self):
        self.run_sync("--harness", "claude")
        env = self.jload(".claude/settings.json")["env"]
        self.assertEqual(env["DISABLE_TELEMETRY"], "1")
        self.assertEqual(env["DISABLE_ERROR_REPORTING"], "1")
        # these would block `claude update` or cut more than telemetry: never written
        for k in ("DISABLE_UPDATES", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "DO_NOT_TRACK"):
            self.assertNotIn(k, env)

    def test_claude_user_value_of_one_key_keeps_the_other_kit_key(self):
        f = self.home / ".claude/settings.json"
        f.parent.mkdir()
        f.write_text(json.dumps({"env": {"DISABLE_ERROR_REPORTING": "0"}}))
        r = self.run_sync("--harness", "claude")
        self.assertIn("env.DISABLE_ERROR_REPORTING", r.stdout)
        env = self.jload(".claude/settings.json")["env"]
        self.assertEqual(env["DISABLE_ERROR_REPORTING"], "0")
        self.assertEqual(env["DISABLE_TELEMETRY"], "1")

    def test_codex_analytics_table_is_valid_toml(self):
        self.run_sync("--harness", "codex")
        text = (self.home / ".codex/config.toml").read_text()
        self.assertIn("analytics = { enabled = false }", text)
        self.assertNotIn("feedback", text)  # /feedback is user-initiated, not telemetry
        self.assertNotIn("otel", text)  # exporters are off by default
        try:
            import tomllib
        except ImportError:
            self.skipTest("tomllib needs Python 3.11+")
        self.assertEqual(tomllib.loads(text)["analytics"], {"enabled": False})

    def test_codex_user_analytics_table_wins_and_file_stays_valid(self):
        cfg = self.home / ".codex/config.toml"
        cfg.parent.mkdir()
        cfg.write_text('model = "x"\n\n[analytics]\nenabled = true\n\n[projects."/a"]\ntrust_level = "trusted"\n')
        r = self.run_sync("--harness", "codex")
        self.assertIn("analytics is set by you", r.stdout)
        self.assertNotIn("result would not be valid TOML", r.stdout)
        try:
            import tomllib
        except ImportError:
            self.skipTest("tomllib needs Python 3.11+")
        self.assertEqual(tomllib.loads(cfg.read_text())["analytics"], {"enabled": True})

    def test_codex_user_dotted_analytics_key_wins(self):
        cfg = self.home / ".codex/config.toml"
        cfg.parent.mkdir()
        cfg.write_text("analytics.enabled = true\n")
        r = self.run_sync("--harness", "codex")
        self.assertIn("analytics is set by you", r.stdout)
        self.assertEqual(cfg.read_text().count("analytics"), 1)

    def test_codex_uninstall_removes_the_analytics_line(self):
        cfg = self.home / ".codex/config.toml"
        cfg.parent.mkdir()
        cfg.write_text('model = "x"\n')
        self.run_sync("--harness", "codex")
        self.assertIn("analytics", cfg.read_text())
        self.run_sync("--uninstall")
        self.assertEqual(cfg.read_text().strip(), 'model = "x"')

    def test_gemini_usage_statistics_off(self):
        self.run_sync("--harness", "gemini")
        g = self.jload(".gemini/settings.json")
        self.assertIs(g["privacy"]["usageStatisticsEnabled"], False)
        self.assertNotIn("telemetry", g)  # telemetry.enabled is off by default

    def test_aider_auto_commits_off_in_both_modes(self):
        for mode in ("bypass", "ask"):
            self.run_sync("--harness", "aider", "--permissions", mode)
            aider = (self.home / ".aider.conf.yml").read_text()
            self.assertIn("auto-commits: false", aider, mode)
            self.assertIn("dirty-commits: false", aider, mode)

    def test_aider_user_auto_commits_kept_outside_the_region(self):
        (self.home / ".aider.conf.yml").write_text("auto-commits: true\nmodel: x\n")
        r = self.run_sync("--harness", "aider")
        self.assertIn("has a 'auto-commits:' key already", r.stdout)
        aider = (self.home / ".aider.conf.yml").read_text()
        self.assertEqual(aider.count("auto-commits"), 1)
        self.assertIn("dirty-commits: false", aider)

    def test_aider_uninstall_removes_the_keys(self):
        (self.home / ".aider.conf.yml").write_text("model: x\n")
        self.run_sync("--harness", "aider")
        self.run_sync("--uninstall")
        self.assertEqual((self.home / ".aider.conf.yml").read_text().strip(), "model: x")

    def test_opencode_and_copilot_get_no_telemetry_key(self):
        # no off switch is documented: see docs/adapters.md. Nothing may be invented.
        self.run_sync("--harness", "opencode,copilot")
        self.assertEqual(self.jload(".config/opencode/opencode.json"), {"permission": "allow", "autoupdate": False})
        self.assertEqual(self.jload(".copilot/settings.json"),
                         {"includeCoAuthoredBy": False, "autoUpdate": False})

    def test_pi_install_telemetry_off(self):
        self.run_sync("--harness", "pi")
        self.assertEqual(self.jload(".pi/agent/settings.json"), {"enableInstallTelemetry": False})


class CopilotSettingsTest(Base):
    def test_users_old_coauthor_key_is_left_alone(self):
        f = self.home / ".copilot/settings.json"
        f.parent.mkdir()
        f.write_text(json.dumps({"include_coauthor": False, "theme": "auto"}))
        self.run_sync("--harness", "copilot")
        # not written by the kit, so it is the user's: left alone, the new key sits beside it
        d = self.jload(".copilot/settings.json")
        self.assertIs(d["includeCoAuthoredBy"], False)
        self.assertEqual(d["theme"], "auto")

    def test_key_written_by_older_kit_is_replaced(self):
        # state of a kit < 2026-09-25 sync: include_coauthor written and recorded
        state = self.home / ".local/share/work-kit/state/kit-sync.json"
        f = self.home / ".copilot/settings.json"
        f.parent.mkdir()
        f.write_text(json.dumps({"include_coauthor": False}))
        state.parent.mkdir(parents=True)
        state.write_text(json.dumps({"owned": {json.dumps([str(f), "include_coauthor"]): False}}))
        self.run_sync("--harness", "copilot")
        d = self.jload(".copilot/settings.json")
        self.assertNotIn("include_coauthor", d)
        self.assertIs(d["includeCoAuthoredBy"], False)
        self.assertIs(d["autoUpdate"], False)


class PiTest(Base):
    def test_instructions_skills_and_settings(self):
        self.run_sync("--harness", "pi")
        agents = (self.home / ".pi/agent/AGENTS.md").read_text()
        self.assertIn("- be brief", agents)
        self.assertIn("work-kit:begin", agents)
        # pi reads ~/.agents/skills itself: no per-harness skill links
        self.assertTrue((self.home / ".agents/skills/demo").is_symlink())
        self.assertFalse((self.home / ".pi/agent/skills").exists())

    def test_user_agents_md_keeps_its_content(self):
        f = self.home / ".pi/agent/AGENTS.md"
        f.parent.mkdir(parents=True)
        f.write_text("# Mine\n\n- keep me\n")
        self.run_sync("--harness", "pi")
        text = f.read_text()
        self.assertIn("- keep me", text)
        self.assertIn("- be brief", text)
        self.run_sync("--uninstall")
        self.assertEqual(f.read_text().strip(), "# Mine\n\n- keep me")

    def test_override_file_is_reported(self):
        d = self.home / ".pi/agent"
        d.mkdir(parents=True)
        (d / "AGENTS.override.md").write_text("x")
        r = self.run_sync("--harness", "pi")
        self.assertIn("AGENTS.override.md", r.stdout)

    def test_agent_dir_env_is_respected(self):
        self.env["PI_CODING_AGENT_DIR"] = str(self.tmp / "pidir")
        self.run_sync("--harness", "pi")
        self.assertTrue((self.tmp / "pidir/AGENTS.md").is_file())
        self.assertTrue((self.tmp / "pidir/settings.json").is_file())
        self.assertFalse((self.home / ".pi").exists())

    def test_detected_by_binary_or_config_dir(self):
        self.assertNotIn("detected: pi", self.run_sync().stdout)
        self.fake_bin("pi")
        self.assertIn("pi", self.run_sync("--dry-run").stdout.split("detected:")[1].split("\n")[0])

    def test_dry_run_writes_nothing(self):
        self.run_sync("--harness", "pi", "--dry-run")
        self.assertFalse((self.home / ".pi").exists())


if __name__ == "__main__":
    unittest.main()
