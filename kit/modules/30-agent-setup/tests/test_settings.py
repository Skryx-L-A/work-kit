"""Tests for kit-sync settings: approval mode, attribution, MCP, AGENTS.md adapters, git hooks,
Python fallback and coexistence with 31-caveman. Every test uses a temp HOME.
Run: python3 -m unittest discover -s tests -v (from this module dir)."""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parent.parent
KIT_SYNC = MODULE / "kit-sync"
CAVEMAN = MODULE.parent / "31-caveman" / "caveman-setup"


class Base(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = Path(self._tmp.name).resolve()
        self.home = self.tmp / "home"
        (self.home / ".local/bin").mkdir(parents=True)
        self.source = self.tmp / "source"
        (self.source / "skills/demo").mkdir(parents=True)
        (self.source / "skills/demo/SKILL.md").write_text("---\nname: demo\ndescription: d\n---\n")
        (self.source / "AGENTS.md").write_text("# Rules\n\n- be brief\n")
        drop = ("CODEX_HOME", "XDG_CONFIG_HOME", "KIT_DATA_DIR", "KIT_BIN_DIR", "CLAUDE_CONFIG_DIR",
                "COPILOT_HOME", "GIT_CONFIG_GLOBAL", "KIT_PYTHON", "UV_PYTHON_INSTALL_DIR",
                "DATA_GUARD_BIN", "CAVEMAN_DEFAULT_MODE", "PI_CODING_AGENT_DIR")
        self.env = {k: v for k, v in os.environ.items() if k not in drop and not k.startswith("GIT_")}
        self.env.update(HOME=str(self.home), PATH="/usr/bin:/bin", PYTHONDONTWRITEBYTECODE="1",
                        GIT_CONFIG_NOSYSTEM="1")

    def tearDown(self):
        self._tmp.cleanup()

    def run_sync(self, *args, check=True):
        cmd = [sys.executable, str(KIT_SYNC), "--home", str(self.home),
               "--source", str(self.source), *args]
        r = subprocess.run(cmd, capture_output=True, text=True, env=self.env)
        if check and r.returncode != 0:
            self.fail(r.stdout + r.stderr)
        return r

    def fake_bin(self, name, body="#!/bin/sh\nexit 0\n"):
        p = self.home / ".local/bin" / name
        p.write_text(body)
        p.chmod(0o755)
        return p

    def jload(self, rel):
        return json.loads((self.home / rel).read_text())


class PermissionsTest(Base):
    def test_default_is_bypass(self):
        self.run_sync("--all")
        c = self.jload(".claude/settings.json")
        self.assertEqual(c["permissions"]["defaultMode"], "bypassPermissions")
        self.assertIs(c["skipDangerousModePermissionPrompt"], True)
        toml = (self.home / ".codex/config.toml").read_text()
        self.assertIn('approval_policy = "never"', toml)
        self.assertIn('sandbox_mode = "danger-full-access"', toml)
        self.assertEqual(self.jload(".gemini/settings.json")["general"]["defaultApprovalMode"], "auto_edit")
        self.assertEqual(self.jload(".config/opencode/opencode.json")["permission"], "allow")
        self.assertIn("yes-always: true", (self.home / ".aider.conf.yml").read_text())

    def test_switch_to_ask_is_recorded_and_sticks(self):
        self.run_sync("--all")
        self.run_sync("--all", "--permissions", "ask")
        conf = (self.home / ".config/work-kit/kit.conf").read_text()
        self.assertIn("permissions=ask", conf)
        self.run_sync("--all")  # no flag: kit.conf decides
        c = self.jload(".claude/settings.json")
        self.assertEqual(c["permissions"]["defaultMode"], "default")
        self.assertNotIn("skipDangerousModePermissionPrompt", c)
        toml = (self.home / ".codex/config.toml").read_text()
        self.assertIn('approval_policy = "on-request"', toml)
        self.assertIn('sandbox_mode = "workspace-write"', toml)
        self.assertNotIn("defaultApprovalMode", json.dumps(self.jload(".gemini/settings.json")))
        self.assertEqual(self.jload(".config/opencode/opencode.json")["permission"], "ask")
        self.assertNotIn("yes-always", (self.home / ".aider.conf.yml").read_text())
        self.run_sync("--all", "--permissions", "bypass")
        self.assertEqual(self.jload(".claude/settings.json")["permissions"]["defaultMode"],
                         "bypassPermissions")

    def test_user_value_kept_unless_explicit(self):
        s = self.home / ".claude/settings.json"
        s.parent.mkdir()
        s.write_text(json.dumps({"permissions": {"defaultMode": "plan", "allow": ["Bash(ls)"]},
                                 "hooks": {"Stop": []}}))
        r = self.run_sync("--harness", "claude")
        self.assertIn("is your value", r.stdout)
        data = self.jload(".claude/settings.json")
        self.assertEqual(data["permissions"]["defaultMode"], "plan")
        self.assertEqual(data["permissions"]["allow"], ["Bash(ls)"])
        self.assertEqual(data["attribution"], {"commit": "", "pr": ""})
        self.assertIn("hooks", data)
        bak = self.home / ".local/share/work-kit/backups/30-agent-setup/.claude"
        self.assertEqual(len(list(bak.glob("settings.json.bak-*"))), 1)
        self.assertEqual(list(s.parent.glob("*.bak-*")), [])
        self.run_sync("--harness", "claude", "--permissions", "bypass")
        self.assertEqual(self.jload(".claude/settings.json")["permissions"]["defaultMode"],
                         "bypassPermissions")

    def test_codex_user_keys_win(self):
        cfg = self.home / ".codex/config.toml"
        cfg.parent.mkdir()
        cfg.write_text('model = "x"\napproval_policy = "untrusted"\n\n[profiles.a]\nmodel = "y"\n')
        self.run_sync("--harness", "codex")
        text = cfg.read_text()
        self.assertEqual(text.count("approval_policy"), 1)
        self.assertIn('sandbox_mode = "danger-full-access"', text)
        self.assertLess(text.index("sandbox_mode"), text.index("[profiles.a]"))
        try:
            import tomllib
        except ImportError:
            return
        data = tomllib.loads(text)
        self.assertEqual(data["approval_policy"], "untrusted")
        self.assertEqual(data["profiles"]["a"]["model"], "y")

    def test_claude_defaults_to_newest_opus_alias(self):
        self.run_sync("--harness", "claude")
        self.assertEqual(self.jload(".claude/settings.json")["model"], "opus")

    def test_claude_model_set_by_hand_stays(self):
        cfg = self.home / ".claude/settings.json"
        cfg.parent.mkdir(parents=True, exist_ok=True)
        cfg.write_text(json.dumps({"model": "sonnet"}))
        self.run_sync("--harness", "claude")
        self.assertEqual(self.jload(".claude/settings.json")["model"], "sonnet")

    def test_codex_sync_does_not_pin_a_model(self):
        self.run_sync("--harness", "codex")
        text = (self.home / ".codex/config.toml").read_text()
        self.assertNotIn("model =", text)
        self.assertNotIn("model_provider =", text)

    def test_invalid_json_left_alone(self):
        s = self.home / ".claude/settings.json"
        s.parent.mkdir()
        s.write_text("{ // comment\n}")
        r = self.run_sync("--harness", "claude")
        self.assertIn("not plain JSON", r.stdout)
        self.assertEqual(s.read_text(), "{ // comment\n}")


class AttributionTest(Base):
    def test_co_author_settings_off(self):
        (self.home / ".config/Code/User").mkdir(parents=True)
        self.run_sync("--all")
        c = self.jload(".claude/settings.json")
        self.assertEqual(c["attribution"], {"commit": "", "pr": ""})
        self.assertIs(c["includeCoAuthoredBy"], False)
        aider = (self.home / ".aider.conf.yml").read_text()
        for key in ("attribute-co-authored-by", "attribute-author", "attribute-committer"):
            self.assertIn(f"{key}: false", aider)
        self.assertIs(self.jload(".copilot/settings.json")["includeCoAuthoredBy"], False)
        self.assertEqual(self.jload(".config/Code/User/settings.json")["git.addAICoAuthor"], "off")


class McpTest(Base):
    FILES = {".claude.json": ("mcpServers",), ".gemini/settings.json": ("mcpServers",),
             ".config/opencode/opencode.json": ("mcp",), ".cursor/mcp.json": ("mcpServers",),
             ".copilot/mcp-config.json": ("mcpServers",)}

    def names(self, rel):
        d = self.jload(rel)
        for k in self.FILES[rel]:
            d = d.get(k, {})
        return set(d)

    def test_only_installed_servers(self):
        self.run_sync("--all")
        self.assertFalse((self.home / ".claude.json").exists())
        brain = self.fake_bin("brain")
        self.run_sync("--all")
        for rel in self.FILES:
            self.assertEqual(self.names(rel), {"brain"}, rel)
        self.assertEqual(self.jload(".claude.json")["mcpServers"]["brain"],
                         {"type": "stdio", "command": str(brain), "args": ["mcp"], "env": {}})
        self.assertEqual(self.jload(".config/opencode/opencode.json")["mcp"]["brain"]["command"],
                         [str(brain), "mcp"])
        self.assertIn("[mcp_servers.brain]", (self.home / ".codex/config.toml").read_text())
        self.assertTrue((self.home / ".continue/mcpServers/work-kit-brain.yaml").is_file())
        self.fake_bin("doc-qa")
        self.run_sync("--all")
        self.assertEqual(self.names(".claude.json"), {"brain", "doc-qa"})
        brain.unlink()  # brain uninstalled: its registrations go
        self.run_sync("--all")
        for rel in self.FILES:
            self.assertEqual(self.names(rel), {"doc-qa"}, rel)
        self.assertNotIn("mcp_servers.brain", (self.home / ".codex/config.toml").read_text())
        self.assertFalse((self.home / ".continue/mcpServers/work-kit-brain.yaml").exists())

    def test_allowlist_is_respected(self):
        self.fake_bin("brain")
        self.fake_bin("doc-qa")
        allow = self.home / ".config/work-kit/mcp-allowlist.yaml"
        allow.parent.mkdir(parents=True)
        allow.write_text("version: 1\ndefault: deny\nservers:\n  - name: brain\n    transport: stdio\n")
        r = self.run_sync("--harness", "claude")
        self.assertEqual(self.names(".claude.json"), {"brain"})
        self.assertIn("doc-qa is installed but not on", r.stdout)

    def test_user_entries_and_state_kept(self):
        self.fake_bin("brain")
        cj = self.home / ".claude.json"
        cj.write_text(json.dumps({"numStartups": 3, "mcpServers": {"other": {"command": "x"}}}))
        self.run_sync("--harness", "claude")
        data = self.jload(".claude.json")
        self.assertEqual(data["numStartups"], 3)
        self.assertEqual(set(data["mcpServers"]), {"other", "brain"})
        self.run_sync("--uninstall")
        data = self.jload(".claude.json")
        self.assertEqual(data, {"numStartups": 3, "mcpServers": {"other": {"command": "x"}}})

    def test_ai_gov_accepts_entries(self):
        gov = MODULE.parent / "13-ai-governance"
        if not (gov / "ai-gov").is_file():
            self.skipTest("13-ai-governance not present")
        try:
            import tomllib  # noqa: F401  ai-gov reads Codex TOML with it
        except ImportError:
            self.skipTest("needs Python 3.11+")
        self.fake_bin("brain")
        (self.home / ".config/Code/User").mkdir(parents=True)
        self.run_sync("--all")
        r = subprocess.run([sys.executable, str(gov / "ai-gov"), "mcp-check", "--json", "--allowlist",
                            str(gov / "policy/mcp-allowlist.yaml")],
                           capture_output=True, text=True, env=self.env)
        rows = json.loads(r.stdout)["rows"]
        brain = [x for x in rows if x.get("name") == "brain"]
        self.assertGreaterEqual(len({x["harness"] for x in brain}), 7, r.stdout)
        # only the TODO(ask IT) approval fields may be open; command and args must match
        self.assertEqual({x["status"] for x in brain} - {"UNCONFIRMED", "OK"}, set(), r.stdout)


class AdapterTest(Base):
    def test_referenced_paths_exist(self):
        """Every path a generated instruction file points at must exist (live defect 2)."""
        self.run_sync("--all")
        refs = []
        for f in (self.home / ".claude/CLAUDE.md",):
            refs += re.findall(r"(?m)^@(\S+)", f.read_text())
        refs += re.findall(r'(?m)^  - "(.+)"$', (self.home / ".aider.conf.yml").read_text())
        self.assertGreaterEqual(len(refs), 2)
        for ref in refs:
            p = Path(ref.replace("~", str(self.home), 1) if ref.startswith("~/") else ref)
            self.assertTrue(p.is_file(), ref)
        self.assertEqual(self.jload(".gemini/settings.json")["context"]["fileName"],
                         ["AGENTS.md", "GEMINI.md"])

    def test_gemini_user_filename_kept(self):
        g = self.home / ".gemini"
        g.mkdir()
        (g / "settings.json").write_text(json.dumps({"context": {"fileName": "CONTEXT.md"}}))
        self.run_sync("--harness", "gemini")
        self.assertIn("- be brief", (g / "GEMINI.md").read_text())
        self.assertFalse((g / "AGENTS.md").exists())
        self.assertEqual(self.jload(".gemini/settings.json")["context"]["fileName"], "CONTEXT.md")

    def test_claude_agents_link_rules(self):
        c = self.home / ".claude"
        c.mkdir()
        other = self.tmp / "stick/source/AGENTS.md"
        other.parent.mkdir(parents=True)
        other.write_text("x")
        (c / "AGENTS.md").symlink_to(other)  # e.g. linked by 70-workbench
        self.run_sync("--harness", "claude")
        self.assertEqual((c / "AGENTS.md").resolve(), (self.source / "AGENTS.md").resolve())
        self.run_sync("--uninstall")
        self.assertFalse((c / "AGENTS.md").is_symlink())
        (c / "AGENTS.md").write_text("mine\n")
        self.run_sync("--harness", "claude")
        self.assertEqual((c / "AGENTS.md").read_text(), "mine\n")

    def test_old_generated_copy_removed(self):
        gen = self.home / ".local/share/work-kit/generated/CONVENTIONS.md"
        gen.parent.mkdir(parents=True)
        gen.write_text("<!-- work-kit:managed - generated by kit-sync, do not edit -->\nold\n")
        conf = self.home / ".aider.conf.yml"
        conf.write_text(f"model: x\n# work-kit: shared agent rules\nread:\n  - {gen}\n")
        self.run_sync("--harness", "aider")
        self.assertFalse(gen.exists())
        text = conf.read_text()
        self.assertTrue(text.startswith("model: x\n"))
        self.assertNotIn(str(gen), text)
        self.assertEqual(text.count("read:"), 1)

    def test_uninstall_removes_settings(self):
        self.fake_bin("brain")
        self.run_sync("--all")
        self.run_sync("--uninstall")
        for rel in (".claude/settings.json", ".claude.json", ".gemini/settings.json",
                    ".config/opencode/opencode.json", ".codex/config.toml", ".aider.conf.yml",
                    ".copilot/settings.json", ".copilot/mcp-config.json", ".cursor/mcp.json",
                    ".gemini/AGENTS.md", ".claude/AGENTS.md", ".pi/agent/settings.json",
                    ".pi/agent/AGENTS.md"):
            self.assertFalse((self.home / rel).exists(), rel)
        self.assertEqual(list((self.home / ".continue/mcpServers").glob("*.yaml")), [])


class GitHookTest(Base):
    def git(self, *args, cwd=None, check=True):
        r = subprocess.run(["git", "-c", "user.name=T", "-c", "user.email=t@example.invalid", *args],
                           cwd=cwd, capture_output=True, text=True, env=self.env)
        if check and r.returncode != 0:
            self.fail(" ".join(args) + "\n" + r.stdout + r.stderr)
        return r

    def repo(self):
        repo = self.tmp / "repo"
        repo.mkdir()
        self.git("init", "-q", str(repo))
        return repo

    def commit(self, repo, msg, name="f.txt", check=True):
        (repo / name).write_text(msg)
        self.git("add", name, cwd=repo)
        return self.git("commit", "-q", "-m", msg, cwd=repo, check=check)

    def hooks(self):
        return self.home / ".config/work-kit/git-hooks"

    def test_strips_co_author_and_chains_repo_hooks(self):
        self.run_sync("--harness", "claude")
        self.assertEqual(self.git("config", "--global", "core.hooksPath").stdout.strip(),
                         str(self.hooks()))
        repo = self.repo()
        h = repo / ".git/hooks"
        h.mkdir(exist_ok=True)
        # a brain-style post-commit hook and a repo commit-msg hook must keep running
        (h / "post-commit").write_text('#!/bin/sh\necho ran >> "$(git rev-parse --git-dir)/post-commit.log"\n')
        (h / "commit-msg").write_text('#!/bin/sh\necho "Change-Id: I1" >> "$1"\n')
        for f in ("post-commit", "commit-msg"):
            (h / f).chmod(0o755)
        self.commit(repo, "Fix bug\n\nBody.\n\nCo-authored-by: Claude <noreply@anthropic.com>\n"
                          "co-authored-by: Other <o@example.invalid>")
        msg = self.git("log", "-1", "--format=%B", cwd=repo).stdout
        self.assertNotIn("uthored-by", msg)
        self.assertIn("Body.", msg)
        self.assertIn("Change-Id: I1", msg)
        self.assertEqual((repo / ".git/post-commit.log").read_text(), "ran\n")

    def test_keep_co_authors_opt_out(self):
        self.run_sync("--harness", "claude")
        repo = self.repo()
        self.git("config", "work-kit.keepCoAuthors", "true", cwd=repo)
        self.commit(repo, "Pair work\n\nCo-authored-by: Ana <a@example.invalid>")
        self.assertIn("Co-authored-by: Ana", self.git("log", "-1", "--format=%B", cwd=repo).stdout)

    def test_repo_hook_failure_blocks_commit(self):
        self.run_sync("--harness", "claude")
        repo = self.repo()
        (repo / ".git/hooks").mkdir(exist_ok=True)
        pc = repo / ".git/hooks/pre-commit"
        pc.write_text("#!/bin/sh\nexit 1\n")
        pc.chmod(0o755)
        r = self.commit(repo, "x", check=False)
        self.assertNotEqual(r.returncode, 0)

    def test_foreign_hooks_path_left_alone(self):
        self.git("config", "--global", "core.hooksPath", "/somewhere/else")
        r = self.run_sync("--harness", "claude")
        self.assertIn("left as is", r.stdout)
        self.assertEqual(self.git("config", "--global", "core.hooksPath").stdout.strip(), "/somewhere/else")
        self.assertFalse(self.hooks().exists())

    def data_guard(self):
        """Fake 40-data-guard: global stubs in the hooks dir, a stub source, a CLI that logs."""
        dg_dir = self.home / ".local/share/work-kit/data-guard"
        dg_dir.mkdir(parents=True)
        stub = dg_dir / "hook-stub.sh"
        stub.write_text("#!/usr/bin/env bash\n# work-kit data-guard hook\nexit 0\n")
        log = self.tmp / "dg.log"
        cli = dg_dir / "data-guard"
        cli.write_text(f'#!/bin/sh\necho "$1" >> "{log}"\n[ -e "{self.tmp}/deny" ] && exit 1\nexit 0\n')
        cli.chmod(0o755)
        return stub, log

    def test_data_guard_global_stubs_are_taken_over_and_restored(self):
        stub, log = self.data_guard()
        self.hooks().mkdir(parents=True)
        for n in ("pre-commit", "post-commit"):
            shutil.copy(stub, self.hooks() / n)
        self.git("config", "--global", "core.hooksPath", str(self.hooks()))
        self.run_sync("--harness", "claude")
        self.assertIn("work-kit git-hook dispatcher", (self.hooks() / "pre-commit").read_text())
        self.assertTrue((self.hooks() / ".data-guard-global").exists())
        repo = self.repo()
        self.commit(repo, "one")
        self.assertEqual(log.read_text(), "staged\n")
        (self.tmp / "deny").write_text("")
        self.assertNotEqual(self.commit(repo, "two", name="g.txt", check=False).returncode, 0)
        (self.tmp / "deny").unlink()
        self.run_sync("--uninstall")
        self.assertIn("work-kit data-guard hook", (self.hooks() / "pre-commit").read_text())
        self.assertEqual(self.git("config", "--global", "core.hooksPath").stdout.strip(), str(self.hooks()))

    def test_data_guard_per_repo(self):
        _stub, log = self.data_guard()
        self.run_sync("--harness", "claude")
        repo = self.repo()
        self.commit(repo, "not guarded")
        self.assertFalse(log.exists())
        lst = self.home / ".config/work-kit/hooked-repos.list"
        lst.write_text(str(repo) + "\n")
        self.commit(repo, "guarded", name="g.txt")
        self.assertEqual(log.read_text(), "staged\n")

    def test_uninstall_unsets_hooks_path(self):
        self.run_sync("--harness", "claude")
        self.run_sync("--uninstall")
        r = self.git("config", "--global", "core.hooksPath", check=False)
        self.assertEqual(r.stdout.strip(), "")
        self.assertEqual([p for p in self.hooks().iterdir() if not p.name.startswith(".")], [])


class PythonFallbackTest(Base):
    def run_sh(self, path_dir):
        env = dict(self.env, PATH=str(path_dir))
        return subprocess.run(["/bin/sh", str(KIT_SYNC), "--home", str(self.home), "--source",
                               str(self.source), "--list"], capture_output=True, text=True, env=env)

    def test_uses_kit_cpython_without_python3(self):
        empty = self.tmp / "emptybin"
        empty.mkdir()
        r = self.run_sh(empty)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("no python3 found", r.stderr)
        kit_py = self.home / ".local/share/uv/python/cpython-3.12.9-linux-x86_64-gnu/bin/python3"
        kit_py.parent.mkdir(parents=True)
        kit_py.symlink_to(sys.executable)
        r = self.run_sh(empty)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("claude", r.stdout)


class InstallScriptTest(Base):
    def test_install_permissions_and_uninstall(self):
        env = dict(self.env)
        (self.home / ".claude").mkdir()
        r = subprocess.run(["bash", str(MODULE / "install.sh"), "--permissions", "ask"],
                           capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        dest = self.home / ".local/share/work-kit/agent-setup"
        self.assertTrue((dest / "git-hooks/dispatch").is_file())
        self.assertIn("permissions=ask", (self.home / ".config/work-kit/kit.conf").read_text())
        self.assertEqual(self.jload(".claude/settings.json")["permissions"]["defaultMode"], "default")
        self.assertIn("@~/.local/share/work-kit/agent-setup/source/AGENTS.md",
                      (self.home / ".claude/CLAUDE.md").read_text())
        hook = (self.home / ".config/work-kit/git-hooks/commit-msg").read_text()
        self.assertEqual(hook, (MODULE / "git-hooks/dispatch").read_text())
        r = subprocess.run(["bash", str(MODULE / "uninstall.sh")], capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse(dest.exists())
        self.assertFalse((self.home / ".claude/settings.json").exists())
        self.assertFalse((self.home / ".local/share/work-kit/state/kit-sync.json").exists())

    def test_install_takes_the_mode_from_kit_permissions(self):
        """The kit installer passes its choice as KIT_PERMISSIONS; the flag beats it."""
        (self.home / ".claude").mkdir()
        env = dict(self.env, KIT_PERMISSIONS="ask")
        r = subprocess.run(["bash", str(MODULE / "install.sh")], capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.jload(".claude/settings.json")["permissions"]["defaultMode"], "default")
        r = subprocess.run(["bash", str(MODULE / "install.sh"), "--permissions", "bypass"],
                           capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.jload(".claude/settings.json")["permissions"]["defaultMode"],
                         "bypassPermissions")
        self.assertIn("permissions=bypass", (self.home / ".config/work-kit/kit.conf").read_text())

    def test_install_rejects_an_unknown_mode_before_changing_anything(self):
        for args, env in ((["--permissions", "yolo"], self.env), ([], dict(self.env, KIT_PERMISSIONS="yolo"))):
            r = subprocess.run(["bash", str(MODULE / "install.sh"), *args],
                               capture_output=True, text=True, env=env)
            self.assertEqual(r.returncode, 2, r.stdout + r.stderr)
            self.assertIn("bypass or ask", r.stderr)
        self.assertFalse((self.home / ".local/share/work-kit/agent-setup").exists())


@unittest.skipUnless(CAVEMAN.is_file(), "31-caveman not present")
class CavemanCoexistenceTest(Base):
    def caveman(self, *args):
        r = subprocess.run([sys.executable, str(CAVEMAN), *args], capture_output=True, text=True,
                           env=self.env)
        if r.returncode != 0:
            self.fail(r.stdout + r.stderr)

    def test_both_orders_and_uninstall(self):
        self.fake_bin("brain")
        self.caveman("install", "--all")
        self.run_sync("--all")
        self.caveman("install", "--all")
        self.run_sync("--all")
        s = self.jload(".claude/settings.json")
        self.assertIn("SessionStart", s["hooks"])
        self.assertEqual(s["permissions"]["defaultMode"], "bypassPermissions")
        claude_md = (self.home / ".claude/CLAUDE.md").read_text()
        self.assertEqual(claude_md.count("work-kit:begin"), 1)
        self.assertEqual(claude_md.count("work-kit-caveman:begin"), 1)
        again = self.run_sync("--all")
        self.assertNotIn("[update]", again.stdout)
        self.assertNotIn("[backup]", again.stdout)
        self.run_sync("--uninstall")
        s = self.jload(".claude/settings.json")
        self.assertIn("SessionStart", s["hooks"])
        self.assertNotIn("permissions", s)
        self.assertIn("work-kit-caveman:begin", (self.home / ".claude/CLAUDE.md").read_text())
        self.assertNotIn("work-kit:begin", (self.home / ".claude/CLAUDE.md").read_text())
        self.assertIn("work-kit-caveman:begin", (self.home / ".codex/AGENTS.md").read_text())
        self.caveman("uninstall")
        self.assertFalse((self.home / ".claude/CLAUDE.md").exists())
        self.assertFalse((self.home / ".codex/AGENTS.md").exists())


if __name__ == "__main__":
    unittest.main()
