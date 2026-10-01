#!/usr/bin/env python3
"""Merge the workbench hooks into ~/.claude/settings.json, or take them out again.

    claude_settings.py add    <settings.json> <hooks.json> <state.json> [bypass|accept-edits|ask]
    claude_settings.py remove <settings.json> <state.json>

add:     appends every hook command of hooks.json that is not registered yet (matched by event,
         matcher and command), sets the status line only when none is set, and switches off the
         agent co-author attribution (`attribution.commit` / `attribution.pr` = "", plus the older
         `includeCoAuthoredBy: false`) unless the user already set these keys. What was added is
         recorded in state.json. Other keys are never touched. The permission mode (default
         bypass, owner decision 2026-09-25: protected by the hooks) sets
         `permissions.defaultMode` only when the user has not set one.
         One Bash guard (kit): bash-guard.py runs the checks of 32-harness-profiles' kit-guard in
         its own process, so kit-guard's PreToolUse/Bash entry for Claude Code is taken out and
         recorded as displaced.
remove:  takes out exactly what state.json records, if it is still unchanged, and puts a displaced
         kit-guard entry back while kit-guard is still installed.
A backup (settings.json.bak-<timestamp> in ~/.local/share/work-kit/backups/70-workbench/.claude/)
is written before every change.
"""
import json
import os
import shlex
import sys
from pathlib import Path

from kit_backup import copy_aside


def load(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}


def save(path, data):
    path = Path(path)
    if path.exists():
        copy_aside(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    tmp.replace(path)


MODES = {"bypass": "bypassPermissions", "accept-edits": "acceptEdits", "ask": None}


def is_kit_guard_pre(hook):
    """kit-guard's Claude PreToolUse hook as 32-harness-profiles registers it."""
    cmd = str(hook.get("command", ""))
    return "kit-guard" in cmd and cmd.rstrip().endswith("hook claude")


def displace_kit_guard(hooks, state):
    """Take kit-guard's PreToolUse/Bash entries out; bash-guard.py runs its checks."""
    moved = 0
    for group in hooks.get("PreToolUse", []):
        if "Bash" not in str(group.get("matcher", "")).split("|"):
            continue
        keep = []
        for hook in group.get("hooks", []):
            if is_kit_guard_pre(hook):
                state.setdefault("displaced", []).append({"matcher": group.get("matcher", ""), "hook": hook})
                moved += 1
            else:
                keep.append(hook)
        group["hooks"] = keep
    if moved:
        hooks["PreToolUse"] = [g for g in hooks["PreToolUse"] if g.get("hooks")]
    return moved


def kit_guard_installed(hook):
    """A file the command names as kit-guard (launcher or script) still exists."""
    try:
        words = shlex.split(str(hook.get("command", "")))
    except ValueError:
        return False
    return any(w.endswith("kit-guard") and os.path.isfile(os.path.expandvars(w)) for w in words)


def add(settings_path, hooks_path, state_path, mode="bypass"):
    settings = load(settings_path)
    wanted = load(hooks_path)
    python = os.environ.get("WB_PYTHON", "")
    if python and python != "/usr/bin/python3":
        wanted = json.loads(json.dumps(wanted).replace("/usr/bin/python3", python))
    state = load(state_path)
    added = state.setdefault("hooks", [])
    changed = False
    hooks = settings.setdefault("hooks", {})
    for event, groups in wanted.get("hooks", {}).items():
        have = hooks.setdefault(event, [])
        for group in groups:
            matcher = group.get("matcher", "")
            for hook in group.get("hooks", []):
                cmd = hook.get("command")
                present = [h for g in have if g.get("matcher", "") == matcher
                           for h in g.get("hooks", []) if h.get("command") == cmd]
                if present:
                    # An entry of an earlier install keeps the payload's timeout: a later kit may
                    # raise it (a PreToolUse hook that times out lets the tool run).
                    ours = {"event": event, "matcher": matcher, "command": cmd} in added
                    for h in present:
                        if ours and "timeout" in hook and h.get("timeout") != hook["timeout"]:
                            h["timeout"] = hook["timeout"]
                            changed = True
                    continue
                target = next((g for g in have if g.get("matcher", "") == matcher), None)
                if target is None:
                    target = {"matcher": matcher, "hooks": []} if matcher else {"hooks": []}
                    have.append(target)
                target["hooks"].append(hook)
                added.append({"event": event, "matcher": matcher, "command": cmd})
                changed = True
    if displace_kit_guard(hooks, state):
        print("settings: kit-guard's Claude Bash hook taken out; bash-guard.py runs its checks")
        changed = True
    if not settings["hooks"]:
        del settings["hooks"]
    status = wanted.get("statusLine")
    if status and "statusLine" not in settings:
        settings["statusLine"] = status
        state["statusLine"] = status
        changed = True
    attribution = settings.get("attribution")
    if attribution is None:
        settings["attribution"] = {"commit": "", "pr": ""}
        state["attribution"] = True
        changed = True
    wanted_mode = MODES[mode]
    perms = settings.setdefault("permissions", {})
    if wanted_mode and "defaultMode" not in perms:
        perms["defaultMode"] = wanted_mode
        state["defaultMode"] = wanted_mode
        changed = True
    if wanted_mode == "bypassPermissions" and "skipDangerousModePermissionPrompt" not in settings:
        settings["skipDangerousModePermissionPrompt"] = True
        state["skipDangerousModePermissionPrompt"] = True
        changed = True
    if not perms:
        del settings["permissions"]
    if "includeCoAuthoredBy" not in settings:
        settings["includeCoAuthoredBy"] = False
        state["includeCoAuthoredBy"] = True
        changed = True
    if changed:
        save(settings_path, settings)
    Path(state_path).parent.mkdir(parents=True, exist_ok=True)
    Path(state_path).write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    print(f"settings: {len(added)} hook entries recorded, "
          f"{'changed' if changed else 'already up to date'}")


def remove(settings_path, state_path):
    settings = load(settings_path)
    state = load(state_path)
    if not settings or not state:
        print("settings: nothing recorded")
        return
    changed = False
    for entry in state.get("hooks", []):
        for group in settings.get("hooks", {}).get(entry["event"], []):
            if group.get("matcher", "") != entry["matcher"]:
                continue
            before = len(group.get("hooks", []))
            group["hooks"] = [h for h in group.get("hooks", []) if h.get("command") != entry["command"]]
            changed |= len(group["hooks"]) != before
    for entry in state.get("displaced", []):
        hook = entry["hook"]
        have = settings.setdefault("hooks", {}).setdefault("PreToolUse", [])
        if not kit_guard_installed(hook) or any(
                h.get("command") == hook.get("command") for g in have for h in g.get("hooks", [])):
            continue
        group = next((g for g in have if g.get("matcher", "") == entry["matcher"]), None)
        if group is None:
            group = {"matcher": entry["matcher"], "hooks": []}
            have.append(group)
        group["hooks"].insert(0, hook)
        print("settings: kit-guard's Claude Bash hook registered again")
        changed = True
    for event in list(settings.get("hooks", {})):
        settings["hooks"][event] = [g for g in settings["hooks"][event] if g.get("hooks")]
        if not settings["hooks"][event]:
            del settings["hooks"][event]
    if "hooks" in settings and not settings["hooks"]:
        del settings["hooks"]
    if state.get("statusLine") and settings.get("statusLine") == state["statusLine"]:
        del settings["statusLine"]
        changed = True
    if state.get("attribution") and settings.get("attribution") == {"commit": "", "pr": ""}:
        del settings["attribution"]
        changed = True
    perms = settings.get("permissions", {})
    if state.get("defaultMode") and perms.get("defaultMode") == state["defaultMode"]:
        del perms["defaultMode"]
        if not perms:
            settings.pop("permissions", None)
        changed = True
    if state.get("skipDangerousModePermissionPrompt") and settings.get("skipDangerousModePermissionPrompt") is True:
        del settings["skipDangerousModePermissionPrompt"]
        changed = True
    if state.get("includeCoAuthoredBy") and settings.get("includeCoAuthoredBy") is False:
        del settings["includeCoAuthoredBy"]
        changed = True
    if changed:
        save(settings_path, settings)
    Path(state_path).unlink(missing_ok=True)
    print(f"settings: {'workbench entries removed' if changed else 'nothing to remove'}")


if __name__ == "__main__":
    if len(sys.argv) in (5, 6) and sys.argv[1] == "add" and (len(sys.argv) == 5 or sys.argv[5] in MODES):
        add(*sys.argv[2:])
    elif len(sys.argv) == 4 and sys.argv[1] == "remove":
        remove(*sys.argv[2:])
    else:
        sys.exit(__doc__)
