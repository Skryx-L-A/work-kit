#!/usr/bin/env bash
# Install the agent workbench: spawners and tools to ~/.local/bin, hooks, roles and rules to
# ~/.claude, pi role files to ~/.pi/agent, the model registry (seeded once), the Claude Code
# hook registration, the VS Code extension and, on Linux x86_64, the Agent Workbench desktop app
# (Electron from kit/offline/workbench-app, launcher agent-workbench, menu entry). Offline, no
# sudo, idempotent: changed files are kept as <file>.bak-<timestamp> in
# ~/.local/share/work-kit/backups/70-workbench/ before they are replaced.
#
#   bash install.sh [--no-hooks] [--no-vscode] [--no-app] [--permissions bypass|accept-edits|ask]
#
# Permissions default to bypass (agents run without asking, protected by the hooks); the
# setting is applied to Claude Code only when you have not chosen a mode yourself.
#
# Needs python3 or the kit CPython (00-python) and bash; tmux, git and jq are needed to run
# workers (checked, not installed).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$HERE/payload"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/workbench"
HOOKS=1
VSCODE=1
APP=1
PERMS="${KIT_PERMISSIONS:-bypass}"   # kit/install passes the chosen mode here
while [ $# -gt 0 ]; do
  case "$1" in
    --no-hooks) HOOKS=0 ;;
    --no-vscode) VSCODE=0 ;;
    --no-app) APP=0 ;;
    --permissions) PERMS="${2:-}"; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "install.sh: unknown option '$1'" >&2; exit 2 ;;
  esac
  shift
done
case "$PERMS" in bypass|accept-edits|ask) ;; *) echo "install.sh: --permissions bypass|accept-edits|ask" >&2; exit 2 ;; esac

log() { printf '[workbench] %s\n' "$*"; }

# Python (module 00-python): system python3 first, then the kit CPython (00-python via uv, or the
# bootstrap copy of kit/install), looked up by the shared kit helper. The tools call
# /usr/bin/python3; without it that path is replaced at install.
# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
PY="$(kit_find_python)" || { echo "install.sh: $(kit_python_hint)" >&2; exit 1; }
# The ~/.local/bin/python3 link an earlier run made: use its target (the link may be removed).
if [ "$PY" = "$HOME/.local/bin/python3" ] && [ -L "$PY" ]; then PY="$(readlink "$PY")"; fi
"$PY" -c 'import sys; sys.exit(sys.version_info < (3, 9))' \
  || { echo "install.sh: $PY is older than 3.9; $(kit_python_hint)" >&2; exit 1; }
if [ -x /usr/bin/python3 ]; then export WB_PYTHON=/usr/bin/python3; else export WB_PYTHON="$PY"; fi
python3() { "$PY" "$@"; }
[ -d "$PAYLOAD/shell" ] || { echo "install.sh: $PAYLOAD missing" >&2; exit 1; }

missing=""
for tool in tmux git jq; do command -v "$tool" >/dev/null || missing="$missing $tool"; done
[ -z "$missing" ] || log "missing:$missing -- needed to run workers; install with: bash ../01-prereqs/install.sh <tool> (jq: 10-base-tools)"

mkdir -p "$DATA_DIR" "$HOME/.local/bin" "$HOME/.claude/workbench" "$HOME/.pi-workers/results"

# One global git-hook dispatcher in the kit: kit-sync's (30-agent-setup). When kit-sync is
# installed or its dispatcher exists, the workbench relies on it; only without 30-agent-setup it
# falls back to its own dispatcher in ~/.claude/git-hooks.
KIT_HOOKS="${XDG_CONFIG_HOME:-$HOME/.config}/work-kit/git-hooks"
KIT_SYNC="$(type -P kit-sync || true)"
USE_KIT=0
if [ -n "$KIT_SYNC" ] || grep -qs "work-kit git-hook dispatcher" "$KIT_HOOKS/commit-msg"; then USE_KIT=1; fi
export WB_SKIP_GIT_HOOKS="$USE_KIT"

# The payload's <your-github-user> placeholder: your GitHub handle when git knows it, else neutral.
WB_GITHUB_USER="$(git config --global --get github.user 2>/dev/null || true)"
case "$WB_GITHUB_USER" in ''|*[!A-Za-z0-9-]*) WB_GITHUB_USER=github-user ;; esac
export WB_GITHUB_USER

log "files"
python3 "$HERE/lib/install_files.py" install "$PAYLOAD" "$DATA_DIR/manifest.json"
# Tools start with '#!/usr/bin/env python3': with only the kit CPython, put it on PATH.
if [ -z "$(type -P python3)" ] && [ ! -e "$HOME/.local/bin/python3" ]; then
  ln -s "$PY" "$HOME/.local/bin/python3" && printf '%s\n' "$PY" > "$DATA_DIR/python-link"
  log "~/.local/bin/python3 -> $PY"
fi

if [ "$HOOKS" = 1 ]; then
  log "Claude Code settings (hooks, status line, no co-author attribution, permissions: $PERMS)"
  python3 "$HERE/lib/claude_settings.py" add "$HOME/.claude/settings.json" \
    "$PAYLOAD/claude/hooks.json" "$DATA_DIR/claude-settings-state.json" "$PERMS"
else
  log "hooks not registered (--no-hooks)"
fi

# Kit default layout: update it only while it remains the value this kit wrote.  The
# state is deliberately per key, so a user choice is never confused with a first install.
LAYOUT_STATE="$DATA_DIR/default-settings.json"
LAYOUT_FILE="$HOME/.claude/workbench/settings.json"
layout_current="$(python3 - "$LAYOUT_FILE" <<'PY' 2>/dev/null || true
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    value = data.get("workerLayout")
    if value is not None:
        print(value)
except (OSError, ValueError):
    pass
PY
)"
layout_written="$(python3 - "$LAYOUT_STATE" <<'PY' 2>/dev/null || true
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("workerLayout", ""))
except (OSError, ValueError):
    pass
PY
)"
if [ -z "$layout_current" ]; then
  "$HOME/.local/bin/wb-state" settings set workerLayout window --grund "kit default" >/dev/null \
    && printf '{"workerLayout":"window"}\n' >"$LAYOUT_STATE" && log "workerLayout=window"
elif [ -n "$layout_written" ] && [ "$layout_current" = "$layout_written" ]; then
  "$HOME/.local/bin/wb-state" settings set workerLayout window --grund "kit default refresh" >/dev/null \
    && printf '{"workerLayout":"window"}\n' >"$LAYOUT_STATE" && log "workerLayout refreshed to window"
elif [ -n "$layout_written" ]; then
  printf 'window\n' >"$HOME/.claude/workbench/workerLayout.kit-new"
  log "kept your workerLayout; new kit default written to $HOME/.claude/workbench/workerLayout.kit-new"
fi

# Workbench panes: bypass is the built-in default (orchestratorPermissionMode, and workers start
# with the harness' autonomy flag). A stricter choice is written once.
case "$PERMS" in
  accept-edits)
    "$HOME/.local/bin/wb-state" settings set orchestratorPermissionMode acceptEdits >/dev/null
    "$HOME/.local/bin/wb-state" settings set workerSkipPermissions false >/dev/null ;;
  ask)
    "$HOME/.local/bin/wb-state" settings set orchestratorPermissionMode manual >/dev/null
    "$HOME/.local/bin/wb-state" settings set workerSkipPermissions false >/dev/null ;;
esac

GH="$HOME/.claude/git-hooks"
if [ "$USE_KIT" = 1 ]; then
  # A dispatcher an earlier run of this installer set up gives way to kit-sync's.
  state="$(cat "$DATA_DIR/git-hooks-state" 2>/dev/null || true)"
  case "$state" in
    hooksPath)
      [ "$(git config --global --get core.hooksPath 2>/dev/null)" = "$GH" ] \
        && git config --global --unset core.hooksPath && log "git: own core.hooksPath removed" ;;
    chained\ *)
      f="${state#chained }"; [ -f "$f" ] && grep -q 'Global git hook dispatcher' "$f" && rm -f "$f" ;;
  esac
  rm -f "$DATA_DIR/git-hooks-state" "$DATA_DIR/agents-link"
  if [ -n "$KIT_SYNC" ]; then
    # kit-sync links ~/.claude/AGENTS.md, installs the git-hook dispatcher (co-author lines out,
    # repository and data-guard hooks chained) and turns off harness attribution, aider included.
    sync_args=()
    case "$PERMS" in bypass|ask) sync_args=(--permissions "$PERMS") ;; esac
    if "$KIT_SYNC" "${sync_args[@]}" > "$DATA_DIR/kit-sync.log" 2>&1; then
      log "kit-sync: AGENTS.md, git-hook dispatcher, attribution (log: $DATA_DIR/kit-sync.log)"
    else
      log "kit-sync failed, see $DATA_DIR/kit-sync.log"
    fi
  else
    log "git: kit dispatcher in $KIT_HOOKS is used (kit-sync not on PATH)"
  fi
else
  # House rules: the tools and the Claude harness entry read ~/.claude/AGENTS.md; without
  # kit-sync, link the kit AGENTS.md when it is next to this module.
  KIT_AGENTS="$(cd "$HERE/.." && pwd)/30-agent-setup/source/AGENTS.md"
  if [ ! -e "$HOME/.claude/AGENTS.md" ] && [ ! -L "$HOME/.claude/AGENTS.md" ] && [ -f "$KIT_AGENTS" ]; then
    ln -s "$KIT_AGENTS" "$HOME/.claude/AGENTS.md" && printf '%s\n' "$KIT_AGENTS" > "$DATA_DIR/agents-link"
    log "~/.claude/AGENTS.md -> $KIT_AGENTS"
  elif [ ! -e "$HOME/.claude/AGENTS.md" ]; then
    log "no ~/.claude/AGENTS.md (install kit module 30-agent-setup for the work rules)"
  fi
  # Fallback dispatcher: strips Co-authored-by lines, then runs the repository's own hook.
  if command -v git >/dev/null; then
    cur="$(git config --global --get core.hooksPath 2>/dev/null || true)"
    if [ -z "$cur" ]; then
      git config --global core.hooksPath "$GH"
      printf 'hooksPath\n' > "$DATA_DIR/git-hooks-state"
      log "git: core.hooksPath=$GH (strips Co-authored-by lines, then runs each repository's hooks)"
    elif [ "$cur" = "$GH" ]; then
      log "git: core.hooksPath already set to the workbench dispatcher"
    elif [ "$cur" = "$KIT_HOOKS" ]; then
      # 40-data-guard's global stubs (no kit-sync dispatcher): chain behind them.
      if [ -e "$cur/commit-msg" ]; then target="$cur/commit-msg.work-kit-chained"; else target="$cur/commit-msg"; fi
      cp "$GH/_verteiler" "$target" && chmod +x "$target"
      printf 'chained %s\n' "$target" > "$DATA_DIR/git-hooks-state"
      log "git: dispatcher chained behind 40-data-guard ($target)"
    else
      log "git: core.hooksPath is '$cur' (not ours); co-author lines are not stripped there."
    fi
  fi
  # Aider: no co-author or author attribution (a marked block; keys you set yourself win).
  python3 "$HERE/lib/aider_conf.py" add "$HOME/.aider.conf.yml"
fi

vsix="$(ls "$PAYLOAD"/vsix/*.vsix 2>/dev/null | head -1)"
if [ "$VSCODE" = 1 ] && [ -n "$vsix" ] && command -v code >/dev/null; then
  log "VS Code extension $(basename "$vsix")"
  # WB_VSCODE_ARGS lets a test point VS Code at its own extensions and user-data folders.
  # shellcheck disable=SC2086
  code ${WB_VSCODE_ARGS:-} --install-extension "$vsix" --force >/dev/null && log "extension installed"
elif [ "$VSCODE" = 1 ]; then
  log "VS Code CLI 'code' not found; install the extension later: code --install-extension $vsix"
fi

# Desktop app (Linux x86_64): Electron and node-pty come from the offline folder of the kit
# (fetch.sh on the build host). Elsewhere, or without them, the step says why and is skipped.
if [ "$APP" = 1 ]; then
  KIT_OFFLINE="${KIT_OFFLINE:-$(cd "$HERE/../.." && pwd)/offline}"
  rc=0
  python3 "$HERE/lib/install_app.py" install "$PAYLOAD" "$KIT_OFFLINE" "$DATA_DIR/app-state.json" || rc=$?
  case "$rc" in
    0|3) ;;
    *) echo "install.sh: desktop app install failed (exit $rc)" >&2; exit 1 ;;
  esac
else
  log "desktop app not installed (--no-app)"
fi

case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) log "add ~/.local/bin to PATH (kit module 60-terminal does this)";; esac
log "done. Start a session: wb-code <project-folder>; check: bash $HERE/verify.sh"
