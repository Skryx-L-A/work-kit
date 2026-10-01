"""Tests for kit-sync. Run: python3 -m unittest discover -s tests -v (from this module dir)."""
import contextlib
import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parent.parent
KIT_SYNC = MODULE / "kit-sync"


class KitSyncTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name).resolve()
        self.home = self.tmp / "home"
        self.home.mkdir()
        self.source = self.tmp / "source"
        (self.source / "skills/demo").mkdir(parents=True)
        (self.source / "skills/demo/SKILL.md").write_text("---\nname: demo\ndescription: d\n---\n")
        (self.source / "AGENTS.md").write_text("# Rules\n\n- be brief\n")
        self.env = {k: v for k, v in os.environ.items()
                    if k not in ("CODEX_HOME", "XDG_CONFIG_HOME", "KIT_DATA_DIR", "KIT_BIN_DIR",
                                 "CLAUDE_CONFIG_DIR", "COPILOT_HOME", "GIT_CONFIG_GLOBAL",
                                 "KIT_PYTHON", "UV_PYTHON_INSTALL_DIR", "PI_CODING_AGENT_DIR")}
        self.env["GIT_CONFIG_NOSYSTEM"] = "1"
        self.env["HOME"] = str(self.home)
        self.env["PATH"] = "/usr/bin:/bin"
        self.env["PYTHONDONTWRITEBYTECODE"] = "1"

    def tearDown(self):
        self._tmp.cleanup()

    def run_sync(self, *args, check=True):
        cmd = [sys.executable, str(KIT_SYNC), "--home", str(self.home),
               "--source", str(self.source), *args]
        r = subprocess.run(cmd, capture_output=True, text=True, env=self.env)
        if check and r.returncode != 0:
            self.fail(r.stdout + r.stderr)
        return r

    def snapshot(self):
        # "Library" is created by Apple's system python itself, not by kit-sync.
        return sorted(str(p.relative_to(self.home)) for p in self.home.rglob("*")
                      if not str(p.relative_to(self.home)).startswith("Library"))

    def test_dry_run_writes_nothing(self):
        (self.home / ".claude").mkdir()
        r = self.run_sync("--dry-run")
        self.assertIn("would create", r.stdout)
        self.assertEqual(self.snapshot(), [".claude"])

    def test_detects_only_present_harnesses(self):
        (self.home / ".claude").mkdir()
        r = self.run_sync()
        self.assertIn("detected: claude", r.stdout)
        self.assertTrue((self.home / ".claude/CLAUDE.md").is_file())
        self.assertFalse((self.home / ".codex").exists())

    def test_idempotent(self):
        (self.home / ".claude").mkdir()
        self.run_sync()
        before = self.snapshot()
        r = self.run_sync()
        self.assertEqual(before, self.snapshot())
        self.assertNotIn("backup", r.stdout)
        self.assertNotIn("update", r.stdout)

    def test_existing_user_text_kept_and_backed_up(self):
        codex = self.home / ".codex"
        codex.mkdir()
        (codex / "AGENTS.md").write_text("my own notes\n")
        self.run_sync()
        text = (codex / "AGENTS.md").read_text()
        self.assertTrue(text.startswith("my own notes\n\n<!-- work-kit:begin"))
        self.assertIn("- be brief", text)
        bak = self.home / ".local/share/work-kit/backups/30-agent-setup/.codex"
        self.assertEqual(len(list(bak.glob("AGENTS.md.bak-*"))), 1)
        self.assertEqual(list(codex.glob("*.bak-*")), [])

    def test_block_update_replaces_only_block(self):
        codex = self.home / ".codex"
        codex.mkdir()
        (codex / "AGENTS.md").write_text("top\n")
        self.run_sync()
        (self.source / "AGENTS.md").write_text("# Rules\n\n- be very brief\n")
        text = (codex / "AGENTS.md").read_text() + "bottom\n"
        (codex / "AGENTS.md").write_text(text)
        self.run_sync()
        new = (codex / "AGENTS.md").read_text()
        self.assertIn("top\n", new)
        self.assertIn("bottom\n", new)
        self.assertIn("be very brief", new)
        self.assertNotIn("- be brief", new)
        self.assertEqual(new.count("work-kit:begin"), 1)

    def test_claude_md_is_thin_import_of_agents_md(self):
        claude = self.home / ".claude"
        claude.mkdir()
        (claude / "CLAUDE.md").write_text("my own notes\n")
        self.run_sync()
        text = (claude / "CLAUDE.md").read_text()
        self.assertTrue(text.startswith("my own notes\n\n<!-- work-kit:begin"))
        self.assertIn("@" + str((self.source / "AGENTS.md").resolve()), text)
        self.assertNotIn("- be brief", text)  # no copy of the rules
        self.assertEqual((claude / "AGENTS.md").resolve(), (self.source / "AGENTS.md").resolve())

    def test_skills_linked_canonical_and_claude(self):
        (self.home / ".claude").mkdir()
        self.run_sync()
        canon = self.home / ".agents/skills/demo"
        self.assertTrue(canon.is_symlink())
        self.assertTrue((canon / "SKILL.md").is_file())
        self.assertEqual((self.home / ".claude/skills/demo").resolve(),
                         (self.source / "skills/demo").resolve())

    def test_stale_skill_link_pruned(self):
        (self.home / ".claude").mkdir()
        self.run_sync()
        (self.source / "skills/demo/SKILL.md").unlink()
        self.run_sync()
        self.assertFalse((self.home / ".agents/skills/demo").is_symlink())
        self.assertFalse((self.home / ".claude/skills/demo").is_symlink())

    def test_user_skill_survives_sync(self):
        mine = self.home / ".agents/skills/mine"
        mine.mkdir(parents=True)
        (mine / "SKILL.md").write_text("x")
        self.run_sync("--all")
        self.assertTrue((mine / "SKILL.md").is_file())

    def test_all_harness_targets(self):
        self.run_sync("--all")
        h = self.home
        for rel in (".claude/CLAUDE.md", ".codex/AGENTS.md", ".gemini/AGENTS.md",
                    ".config/opencode/AGENTS.md", ".copilot/copilot-instructions.md",
                    ".pi/agent/AGENTS.md", ".continue/rules/work-kit.md", ".aider.conf.yml",
                    ".local/share/work-kit/generated/cursor-user-rules.md"):
            self.assertTrue((h / rel).is_file(), rel)
        self.assertIn("read:", (h / ".aider.conf.yml").read_text())
        # AGENTS.md is read directly; no generated copy for Aider, no rules copy in GEMINI.md
        self.assertFalse((h / ".local/share/work-kit/generated/CONVENTIONS.md").exists())
        self.assertFalse((h / ".gemini/GEMINI.md").exists())

    def test_codex_home_respected(self):
        self.env["CODEX_HOME"] = str(self.tmp / "codexhome")
        self.run_sync("--harness", "codex")
        self.assertTrue((self.tmp / "codexhome/AGENTS.md").is_file())

    def test_aider_existing_read_key_not_touched(self):
        conf = self.home / ".aider.conf.yml"
        conf.write_text("read:\n  - other.md\n")
        r = self.run_sync("--harness", "aider")
        text = conf.read_text()
        self.assertTrue(text.startswith("read:\n  - other.md\n"))
        self.assertEqual(text.count("read:"), 1)  # no second 'read' key
        self.assertIn("attribute-co-authored-by: false", text)
        self.assertIn("add ", r.stdout)

    def test_aider_sync_keeps_profiles_role_line(self):
        # 32-harness-profiles adds its role file to the read: list inside the kit region; a later
        # sync must carry it over instead of dropping it (VM finding 2026-09-25).
        conf = self.home / ".aider.conf.yml"
        self.run_sync("--harness", "aider")
        mark = "  - /x/harness-profiles/roles/lead.md  # work-kit-profiles role"
        text = conf.read_text()
        head = text.split("\n", 2)
        self.assertEqual(head[1], "read:")
        item = text.split("\n")[2]
        conf.write_text(text.replace(item + "\n", item + "\n" + mark + "\n", 1))
        with_role = conf.read_text()
        self.run_sync("--harness", "aider")
        self.assertEqual(conf.read_text().count("work-kit-profiles role"), 1)
        self.assertEqual(conf.read_text(), with_role)
        self.assertEqual(conf.read_text().count("read:"), 1)

    def test_new_dotfile_is_644_and_existing_mode_is_kept(self):
        old = os.umask(0o077)
        try:
            self.run_sync("--harness", "aider")
        finally:
            os.umask(old)
        conf = self.home / ".aider.conf.yml"
        self.assertEqual(conf.stat().st_mode & 0o777, 0o644)
        conf.write_text("model: local\n")
        conf.chmod(0o640)
        self.run_sync("--harness", "aider")
        self.assertIn("model: local", conf.read_text())
        self.assertEqual(conf.stat().st_mode & 0o777, 0o640)

    def test_uninstall_restores_user_text(self):
        claude = self.home / ".claude"
        claude.mkdir()
        (claude / "CLAUDE.md").write_text("mine\n")
        self.run_sync("--all")
        self.run_sync("--uninstall")
        self.assertEqual((claude / "CLAUDE.md").read_text(), "mine\n")
        self.assertFalse((self.home / ".codex/AGENTS.md").exists())
        self.assertFalse((self.home / ".agents/skills/demo").is_symlink())
        self.assertFalse((self.home / ".aider.conf.yml").exists())

    def test_project_creates_adapters_and_keeps_existing(self):
        repo = self.tmp / "repo"
        repo.mkdir()
        (repo / "CLAUDE.md").write_text("existing\n")
        r = self.run_sync("--project", str(repo))
        self.assertTrue((repo / "AGENTS.md").is_file())
        self.assertEqual((repo / "CLAUDE.md").read_text(), "existing\n")
        self.assertIn("skip", r.stdout)
        self.assertTrue((repo / ".github/copilot-instructions.md").is_file())
        self.assertTrue((repo / ".cursor/rules/work-kit.mdc").is_file())
        agents = (repo / "AGENTS.md").read_text()
        (repo / "AGENTS.md").write_text(agents + "\n- extra rule\n")
        self.run_sync("--project", str(repo))
        self.assertIn("extra rule", (repo / ".github/copilot-instructions.md").read_text())

    def test_project_dry_run(self):
        repo = self.tmp / "repo"
        repo.mkdir()
        self.run_sync("--project", str(repo), "--dry-run")
        self.assertEqual(list(repo.iterdir()), [])

    def test_project_claude_imports_agents(self):
        repo = self.tmp / "repo"
        repo.mkdir()
        self.run_sync("--project", str(repo), "--harness", "claude")
        self.assertTrue((repo / "CLAUDE.md").read_text().startswith("@AGENTS.md"))

    def test_unknown_harness_fails(self):
        r = self.run_sync("--harness", "nope", check=False)
        self.assertNotEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main()
