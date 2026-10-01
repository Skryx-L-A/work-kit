#!/usr/bin/env python3
"""Hook timeouts of the workbench's Claude Code registration (finding F23, 2026-09-27).

Claude Code runs the tool when a PreToolUse hook times out: on a slow CPU the old 5 s let
'rm -rf' through unguarded. Checks:
  1. payload/claude/hooks.json: every hook that can refuse or hold (PreToolUse, PreCompact,
     ConfigChange, Stop) has a timeout of at least 60 s, every other hook at least 30 s;
     the table agrees with port/regenerate.py (HOOK_TIMEOUTS), so a regeneration keeps it.
  2. lib/claude_settings.py add: a fresh install writes these timeouts; a reinstall raises
     the timeout of an entry an earlier install added (recorded in the state file) and leaves
     an entry of the user with the same command alone.
  3. With a settings.json argument: the installed registration carries the same floors.

    test-hook-timeouts.py [<installed settings.json>]
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODULE = HERE.parent
FLOOR_GUARD = 60
FLOOR_OTHER = 30
GUARD_EVENTS = {"PreToolUse", "PreCompact", "ConfigChange", "Stop"}

passed = failed = 0


def check(cond, what):
    global passed, failed
    if cond:
        passed += 1
        print(f"  ok    {what}")
    else:
        failed += 1
        print(f"  FAIL  {what}")


def floor(event):
    return FLOOR_GUARD if event in GUARD_EVENTS else FLOOR_OTHER


def entries(hooks):
    for event, groups in hooks.items():
        for group in groups:
            for hook in group.get("hooks", []):
                yield event, group.get("matcher", ""), hook


def script(command):
    """The hook file a command runs (the installer may rewrite the interpreter)."""
    return command.replace('"', " ").split()[-1].rsplit("/", 1)[-1]


def low(hooks, only=None):
    return [(e, h["command"], h.get("timeout")) for e, m, h in entries(hooks)
            if (only is None or script(h["command"]) in only)
            and not (isinstance(h.get("timeout"), (int, float)) and h["timeout"] >= floor(e))]


payload = json.loads((MODULE / "payload/claude/hooks.json").read_text(encoding="utf-8"))["hooks"]
bad = low(payload)
check(not bad, "payload hooks.json: guards >= 60 s, others >= 30 s" + (f" ({bad})" if bad else ""))
check(any(e == "PreToolUse" and "bash-guard.py" in h["command"] and h["timeout"] >= 60
          for e, _, h in entries(payload)), "bash-guard.py (PreToolUse Bash) registered with >= 60 s")

# port/ is build tooling: the public tree ships only port/neutralise.py, so the comparison
# with the regeneration table runs where the build tooling is present.
if (MODULE / "port/regenerate.py").is_file():
    sys.path.insert(0, str(MODULE / "port"))
    import regenerate  # noqa: E402
    check(all(regenerate.HOOK_TIMEOUTS.get(e) == FLOOR_GUARD for e in GUARD_EVENTS)
          and regenerate.HOOK_TIMEOUT_OTHER == FLOOR_OTHER
          and regenerate.kit_timeout("PreToolUse", 5) == 60 and regenerate.kit_timeout("PreToolUse", 90) == 90,
          "port/regenerate.py applies the same floors (a live value above them stays)")

with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    settings, state = tmp / "settings.json", tmp / "state.json"
    env = {"HOME": str(tmp), "PATH": "/usr/bin:/bin"}
    lib = MODULE / "lib/claude_settings.py"

    def add():
        return subprocess.run([sys.executable, str(lib), "add", str(settings),
                               str(MODULE / "payload/claude/hooks.json"), str(state), "ask"],
                              capture_output=True, text=True, env=env)

    r = add()
    s = json.loads(settings.read_text())
    ours = {script(h["command"]) for _, _, h in entries(payload)}
    check(r.returncode == 0 and not low(s["hooks"], ours), "fresh install writes the payload timeouts")

    # An install of an older kit: our bash-guard entry at 5 s (recorded in state); the user has
    # the same command under another event, not recorded, at 5 s.
    guard = next(h["command"] for e, _, h in entries(payload) if "bash-guard.py" in h["command"])
    for e, m, h in entries(s["hooks"]):
        if h["command"] == guard:
            h["timeout"] = 5
    s["hooks"].setdefault("PostToolUse", []).append({"matcher": "Bash", "hooks": [
        {"type": "command", "command": guard, "timeout": 5}]})
    settings.write_text(json.dumps(s))
    r = add()
    s = json.loads(settings.read_text())
    got = [(e, h.get("timeout")) for e, m, h in entries(s["hooks"]) if h["command"] == guard]
    check(r.returncode == 0 and ("PreToolUse", 60) in got, f"reinstall raises our 5 s entry to 60 s ({got})")
    check(("PostToolUse", 5) in got, "an entry the install did not add keeps its timeout")

if len(sys.argv) > 1:
    installed = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")).get("hooks", {})
    ours = {script(h["command"]) for _, _, h in entries(payload)}
    bad = low(installed, ours)
    check(not bad, "installed settings.json: workbench hooks carry the floors" + (f" ({bad})" if bad else ""))

print(f"test-hook-timeouts: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
