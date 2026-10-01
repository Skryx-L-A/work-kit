#!/usr/bin/env bash
# Remove the agent workbench: every installed file that is unchanged since installation, the
# hook registration it added to ~/.claude/settings.json (backup first), the VS Code extension and
# the desktop app (its folder, launcher, menu entry and icons).
# Kept: files you changed, backups, the model registry if you edited it, and workbench state
# (~/.claude/workbench/sessions, ~/.pi-workers).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/workbench"
log() { printf '[workbench] %s\n' "$*"; }
# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
PY="$(kit_find_python)" || { echo "uninstall.sh: $(kit_python_hint)" >&2; exit 1; }
# The ~/.local/bin/python3 link an earlier run made: use its target (the link may be removed).
if [ "$PY" = "$HOME/.local/bin/python3" ] && [ -L "$PY" ]; then PY="$(readlink "$PY")"; fi
python3() { "$PY" "$@"; }

if command -v context-guard >/dev/null 2>&1; then
  context-guard --stop --all >/dev/null 2>&1 || true
fi

GH="$HOME/.claude/git-hooks"
state="$(cat "$DATA_DIR/git-hooks-state" 2>/dev/null || true)"
case "$state" in
  hooksPath)
    if [ "$(git config --global --get core.hooksPath 2>/dev/null)" = "$GH" ]; then
      git config --global --unset core.hooksPath && log "git: core.hooksPath removed"
    fi ;;
  chained\ *)
    f="${state#chained }"
    cmp -s "$f" "$GH/_verteiler" 2>/dev/null && rm -f "$f" && log "git: chained dispatcher removed ($f)" ;;
esac
rm -f "$DATA_DIR/git-hooks-state"
python3 "$HERE/lib/aider_conf.py" remove "$HOME/.aider.conf.yml"

if [ -f "$DATA_DIR/agents-link" ] && [ -L "$HOME/.claude/AGENTS.md" ] \
   && [ "$(readlink "$HOME/.claude/AGENTS.md")" = "$(cat "$DATA_DIR/agents-link")" ]; then
  rm -f "$HOME/.claude/AGENTS.md" && log "~/.claude/AGENTS.md link removed"
fi
rm -f "$DATA_DIR/agents-link"
if [ -f "$DATA_DIR/python-link" ] && [ "$(readlink "$HOME/.local/bin/python3" 2>/dev/null)" = "$(cat "$DATA_DIR/python-link")" ]; then
  rm -f "$HOME/.local/bin/python3"
fi
rm -f "$DATA_DIR/python-link"

log "files"
python3 "$HERE/lib/install_files.py" uninstall "$DATA_DIR/manifest.json"
log "Claude Code settings"
python3 "$HERE/lib/claude_settings.py" remove "$HOME/.claude/settings.json" "$DATA_DIR/claude-settings-state.json"

if command -v code >/dev/null; then
  # shellcheck disable=SC2086
  code ${WB_VSCODE_ARGS:-} --uninstall-extension agent-workbench.claude-workbench >/dev/null 2>&1 \
    && log "VS Code extension removed" || true
fi
python3 "$HERE/lib/install_app.py" uninstall "$DATA_DIR/app-state.json"
rmdir "$DATA_DIR" 2>/dev/null || true
log "done"
