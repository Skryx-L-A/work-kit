#!/usr/bin/env python3
"""Fail when an installed instruction file or registration points at a path that does not exist.

Scans the role, rule and command files the workbench installs, the pi role files, the hook
commands in ~/.claude/settings.json, the role files named by the model registry, and the
adapter files of kit module 30-agent-setup when they exist (~/.claude/CLAUDE.md,
~/.codex/AGENTS.md, ~/.gemini/GEMINI.md, ~/.config/opencode/AGENTS.md). Every `~/...` or
`$HOME/...` path in them must exist, except:
  * paths with placeholders (<name>, *, {..}, $VAR other than HOME),
  * runtime paths the workbench creates while working (~/.pi-workers, ~/.local/state,
    ~/.local/trash-snapshots, sentinel and handoff files),
  * paths provided by other kit modules, which are optional (listed in OPTIONAL).
Exit 0 = every referenced path exists, 1 = dangling references (listed).
"""
import json
import os
import re
import sys
from pathlib import Path

HOME = Path(os.environ["HOME"])
PATH_RE = re.compile(r"(?:~|\$HOME|\$\{HOME\})(/[A-Za-z0-9._/\-]+)")
RUNTIME = ("/.pi-workers", "/.local/state", "/.local/trash-snapshots", "/.cache")
OPTIONAL = {
    "/.claude/CLAUDE.md": "kit 30-agent-setup",
    "/.claude/AGENTS.md": "kit 30-agent-setup (linked by the workbench installer when present)",
    "/.agents/skills": "kit 30-agent-setup",
    "/.local/bin/brain": "kit 20-brain",
    "/.config/work-kit/data-classes.md": "kit 40-data-guard (named by the kit AGENTS.md)",
    "/.claude/workbench/settings.json": "written on the first settings change",
    "/.claude/workbench/sessions": "written by the first session",
    "/.msmtprc": "user mail configuration",
}


def files():
    for pattern in (".claude/roles/*.md", ".claude/workbench/rules/*.md", ".claude/commands/*.md",
                    ".pi/agent/*.md"):
        yield from sorted(HOME.glob(pattern))
    for adapter in (".claude/CLAUDE.md", ".codex/AGENTS.md", ".gemini/GEMINI.md",
                    ".config/opencode/AGENTS.md"):
        if (HOME / adapter).is_file():
            yield HOME / adapter


def registered():
    """Hook commands and status line of settings.json, role files of the registry."""
    out = []
    settings = HOME / ".claude/settings.json"
    if settings.is_file():
        data = json.loads(settings.read_text(encoding="utf-8"))
        for groups in data.get("hooks", {}).values():
            for group in groups:
                for hook in group.get("hooks", []):
                    out.append(("settings.json hook", hook.get("command", "")))
        status = data.get("statusLine") or {}
        out.append(("settings.json statusLine", status.get("command", "")))
    registry = HOME / ".claude/workbench/models.json"
    if registry.is_file():
        data = json.loads(registry.read_text(encoding="utf-8"))
        for h in data.get("harnesses", []):
            sp = h.get("systemPrompt") or {}
            for role in ("worker", "orchestrator"):
                if isinstance(sp.get(role), str):
                    out.append((f"models.json harness {h.get('id')} {role} prompt", sp[role]))
    return out


def check(text):
    bad = []
    for m in PATH_RE.finditer(text):
        rel = m.group(1).rstrip(".,;:)`'\"")
        end = m.end()
        tail = text[end:end + 1]
        if tail in "<*{$" and tail:
            continue
        target = HOME / rel.lstrip("/")
        if any(rel.startswith(o) for o in OPTIONAL):
            # Optional (another module provides it) -- but a dangling link is always a defect.
            if target.is_symlink() and not target.exists():
                bad.append("~" + rel + " (dangling link)")
            continue
        if rel.startswith(RUNTIME):
            continue
        if re.search(r"HANDOFF-|\.wb-knowledge-saved|SESSION-STATE", rel):
            continue
        if not (HOME / rel.lstrip("/")).exists():
            bad.append("~" + rel)
    return bad


def main():
    problems = []
    n = 0
    for f in files():
        n += 1
        for p in check(f.read_text(encoding="utf-8", errors="replace")):
            problems.append(f"{f}: {p}")
    for where, text in registered():
        n += 1
        for p in check(text):
            problems.append(f"{where}: {p}")
    if problems:
        print("dangling path references:")
        for p in sorted(set(problems)):
            print("   " + p)
        return 1
    print(f"path references: {n} files/registrations checked, all paths exist")
    return 0


if __name__ == "__main__":
    sys.exit(main())
