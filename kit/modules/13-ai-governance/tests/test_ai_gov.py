"""Tests for ai-gov. Run: python3 -m pytest tests/  (fake HOME, no network, no real configs)."""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

MOD = Path(__file__).resolve().parent.parent
CLI = MOD / "ai-gov"
HAS_TOML = sys.version_info >= (3, 11)


def load_module():
    loader = importlib.machinery.SourceFileLoader("ai_gov", str(CLI))
    spec = importlib.util.spec_from_loader("ai_gov", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


gov = load_module()

ALLOW = """\
version: 1
default: deny
servers:
  - name: brain
    transport: stdio
    command: brain
    args: [mcp]
    blast_radius: reversible
    tools: {search: read, new_note: reversible}
    approved_by: IT
    approved_on: 2026-10-01
    review_by: 2999-01-01
  - name: mailer
    transport: stdio
    command: /opt/mailer/bin/mailer
    blast_radius: irreversible
    approved_by: IT
    approved_on: 2026-10-01
    review_by: 2999-01-01
  - name: docs
    transport: http
    url: "https://docs.example.invalid/mcp"
    blast_radius: read
    harnesses: [claude-code]
    approved_by: TODO(ask IT)
  - name: old
    transport: stdio
    command: old-server
    blast_radius: read
    approved_by: IT
    approved_on: 2020-01-01
    review_by: 2020-06-01
"""


def write(path: Path, content) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content if isinstance(content, str) else json.dumps(content), encoding="utf-8")
    return path


def run(home: Path, *args):
    env = {k: v for k, v in os.environ.items() if k not in ("XDG_CONFIG_HOME", "COPILOT_HOME")}
    env.update(AI_GOV_HOME=str(home), HOME=str(home))
    res = subprocess.run([sys.executable, str(CLI), *args], capture_output=True, text=True, env=env)
    return res


@pytest.fixture()
def home(tmp_path):
    h = tmp_path / "home"
    write(h / "allow.yaml", ALLOW)
    return h


def check(home, *extra):
    res = run(home, "mcp-check", "--allowlist", str(home / "allow.yaml"), "--json", *extra)
    assert res.returncode in (0, 1), res.stderr
    data = json.loads(res.stdout)
    return res.returncode, {(r["harness"], r["name"], r["status"]) for r in data["rows"]}, data


def test_yaml_subset_parses_shipped_allowlist():
    data = gov.parse_yaml_subset((MOD / "policy" / "mcp-allowlist.yaml").read_text())
    assert data["default"] == "deny"
    brain = data["servers"][0]
    assert brain["name"] == "brain" and brain["args"] == ["mcp"]
    assert brain["tools"]["new_note"] == "reversible"


def test_shipped_allowlist_matches_kit_sync_registration(home):
    """kit-sync registers `brain mcp` and `doc-qa mcp`; the shipped allowlist must accept both."""
    data = gov.parse_yaml_subset((MOD / "policy" / "mcp-allowlist.yaml").read_text())
    by_name = {s["name"]: s for s in data["servers"]}
    assert (by_name["brain"]["command"], by_name["brain"]["args"]) == ("brain", ["mcp"])
    doc = by_name["doc-qa"]
    assert (doc["transport"], doc["command"], doc["args"], doc["blast_radius"]) == ("stdio", "doc-qa", ["mcp"], "read")
    write(home / ".claude.json", {"mcpServers": {
        "brain": {"type": "stdio", "command": "brain", "args": ["mcp"]},
        "doc-qa": {"type": "stdio", "command": "doc-qa", "args": ["mcp"]}}})
    res = run(home, "mcp-check", "--allowlist", str(MOD / "policy" / "mcp-allowlist.yaml"), "--json")
    rows = {(r["name"], r["status"]) for r in json.loads(res.stdout)["rows"]}
    assert not {n for n, st in rows if st in ("NOT-ALLOWED", "MISMATCH")}, rows
    assert {n for n, _ in rows} == {"brain", "doc-qa"}


def test_yaml_subset_nested_lists_and_quotes():
    text = 'a:\n  - x: "1 # not a comment"\n    y: [p, "q, r"]\n  - plain\nb: {k: v}\n'
    assert gov.parse_yaml_subset(text) == {"a": [{"x": "1 # not a comment", "y": ["p", "q, r"]}, "plain"],
                                         "b": {"k": "v"}}


def test_no_configs_is_clean(home):
    code, rows, _ = check(home)
    assert code == 0 and rows == set()


def test_allowed_server_ok_and_unknown_denied(home):
    write(home / ".claude.json", {"mcpServers": {
        "brain": {"type": "stdio", "command": "/home/u/.local/bin/brain", "args": ["mcp"]},
        "random": {"command": "node", "args": ["server.js"]}}})
    code, rows, _ = check(home)
    assert ("claude-code", "brain", "OK") in rows
    assert ("claude-code", "random", "NOT-ALLOWED") in rows
    assert code == 1


def test_mismatch_unpinned_inline_secret(home):
    write(home / ".cursor" / "mcp.json", {"mcpServers": {
        "brain": {"command": "brain", "args": ["serve"]},
        "mailer": {"command": "npx", "args": ["-y", "some-mailer"],
                   "env": {"API_TOKEN": "abc123", "SAFE_TOKEN": "${MAILER_TOKEN}", "REGION": "eu"}}}})
    code, rows, data = check(home)
    assert ("cursor", "brain", "MISMATCH") in rows
    assert ("cursor", "mailer", "MISMATCH") in rows      # command npx != /opt/mailer/bin/mailer
    assert ("cursor", "mailer", "UNPINNED") in rows
    assert ("cursor", "mailer", "INLINE-SECRET") in rows
    assert "abc123" not in json.dumps(data)               # never print secret values
    detail = next(r["detail"] for r in data["rows"] if r["status"] == "INLINE-SECRET")
    assert "API_TOKEN" in detail and "SAFE_TOKEN" not in detail
    assert code == 1


def test_pinned_launchers():
    s = lambda cmd, *args: {"command": cmd, "args": list(args)}
    assert gov._pinned(s("npx", "-y", "@scope/pkg@1.2.3"))
    assert not gov._pinned(s("npx", "-y", "@scope/pkg"))
    assert gov._pinned(s("uvx", "tool==0.4.1"))
    assert not gov._pinned(s("uvx", "tool"))
    assert gov._pinned(s("/usr/local/bin/brain", "mcp"))


def test_http_url_and_harness_restriction(home):
    write(home / ".gemini" / "settings.json", {"mcpServers": {
        "docs": {"httpUrl": "https://docs.example.invalid/mcp"}}})
    write(home / ".claude.json", {"mcpServers": {
        "docs": {"type": "http", "url": "https://docs.example.invalid/mcp"}},
        "projects": {"/work/p": {"mcpServers": {"docs": {"type": "http", "url": "https://evil.invalid/mcp"}}}}})
    _, rows, _ = check(home)
    assert ("gemini-cli", "docs", "NOT-ALLOWED") in rows              # only claude-code allowed
    assert ("claude-code", "docs", "UNCONFIRMED") in rows             # allowed, approval TODO
    assert ("claude-code (local: /work/p)", "docs", "MISMATCH") in rows


def test_strict_turns_warnings_into_failures(home):
    write(home / ".claude.json", {"mcpServers": {"docs": {"type": "http", "url": "https://docs.example.invalid/mcp"}}})
    assert check(home)[0] == 0
    assert check(home, "--strict")[0] == 1


def test_expired_review(home):
    write(home / ".claude.json", {"mcpServers": {"old": {"command": "old-server"}}})
    code, rows, _ = check(home)
    assert ("claude-code", "old", "EXPIRED") in rows and code == 1


def test_auto_approvals(home):
    write(home / ".claude" / "settings.json", {"permissions": {"allow": [
        "mcp__brain__search", "mcp__brain__new_note", "mcp__mailer", "mcp__unknown_srv__do_it", "Bash(ls:*)"]},
        "enableAllProjectMcpServers": True})
    write(home / ".gemini" / "settings.json", {"mcpServers": {
        "brain": {"command": "brain", "args": ["mcp"], "trust": True}}})
    write(home / ".config" / "Code" / "User" / "settings.json",
          '{\n  // comment\n  "chat.tools.global.autoApprove": true,\n}\n')
    _, rows, _ = check(home)
    auto = {(h, n) for h, n, s in rows if s == "AUTO-APPROVED"}
    assert ("claude-code", "mailer") in auto
    assert ("claude-code", "unknown_srv") in auto
    assert ("claude-code", "brain") not in auto          # read and reversible tools may be allowed
    assert ("claude-code", "*project .mcp.json servers*") in auto
    assert ("gemini-cli", "brain") in auto               # trust on a non read-only server
    assert ("vscode", "*all*") in auto


def test_other_harness_formats(home):
    write(home / ".config" / "opencode" / "opencode.json", {"mcp": {
        "brain": {"type": "local", "command": ["brain", "mcp"]}}})
    write(home / ".config" / "Code" / "User" / "mcp.json", {"servers": {"x": {"command": "x"}}})
    write(home / ".copilot" / "mcp-config.json", {"mcpServers": {"brain": {"command": "brain", "args": ["mcp"]}}})
    write(home / ".continue" / "config.yaml", "name: a\nmcpServers:\n  - name: brain\n    command: brain\n    args: [mcp]\n")
    write(home / ".continue" / "mcpServers" / "extra.yaml", "name: extra\ncommand: extra-server\n")
    _, rows, _ = check(home)
    assert ("opencode", "brain", "OK") in rows
    assert ("vscode", "x", "NOT-ALLOWED") in rows
    assert ("copilot-cli", "brain", "OK") in rows
    assert ("continue", "brain", "OK") in rows
    assert ("continue", "extra", "NOT-ALLOWED") in rows


@pytest.mark.skipif(not HAS_TOML, reason="tomllib needs Python 3.11+")
def test_codex_toml(home):
    write(home / ".codex" / "config.toml",
          '[mcp_servers.brain]\ncommand = "brain"\nargs = ["mcp"]\n\n'
          '[mcp_servers.remote]\nurl = "https://x.invalid/mcp"\nbearer_token = "zzz"\n')
    _, rows, _ = check(home)
    assert ("codex", "brain", "OK") in rows
    assert ("codex", "remote", "NOT-ALLOWED") in rows
    assert ("codex", "remote", "INLINE-SECRET") in rows


def test_project_configs(home, tmp_path):
    proj = tmp_path / "repo"
    write(proj / ".mcp.json", {"mcpServers": {"sneaky": {"command": "npx", "args": ["-y", "sneaky"]}}})
    write(proj / ".vscode" / "mcp.json", {"servers": {"brain": {"command": "brain", "args": ["mcp"]}}})
    _, rows, _ = check(home, "--project", str(proj))
    assert ("project:claude-code/copilot-cli", "sneaky", "NOT-ALLOWED") in rows
    assert ("project:vscode", "brain", "OK") in rows


def test_unreadable_config_is_reported(home):
    write(home / ".cursor" / "mcp.json", "{ not json")
    code, rows, _ = check(home)
    assert ("cursor", "-", "UNREADABLE") in rows and code == 0


def test_open_questions_and_template(home):
    res = run(home, "open-questions", str(MOD / "policy" / "ai-usage-guideline.md"))
    assert res.returncode == 0 and "open question(s) for IT" in res.stdout
    assert int(res.stdout.strip().splitlines()[-1].split()[0]) > 10
    res = run(home, "template", "ai-system-record")
    assert res.returncode == 0 and "- risk_tier:" in res.stdout
    assert run(home, "template", "nope").returncode == 2


def test_inventory_template_copy_in_skill_is_identical():
    skill = MOD.parent / "30-agent-setup" / "source" / "skills" / "ai-inventory" / "references" / "ai-system-record.md"
    if not skill.exists():
        pytest.skip("30-agent-setup not present")
    assert skill.read_text() == (MOD / "templates" / "ai-system-record.md").read_text()

