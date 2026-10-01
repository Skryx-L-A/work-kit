#!/usr/bin/env bash
# Remove agent-spawn, the delegate skill and their links. Worker state and backups are kept.
set -euo pipefail

BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
SKILLS_DIR="${KIT_SKILLS_DIR:-$HOME/.agents/skills}"
CLAUDE_SKILLS_DIR="${KIT_CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
DEST="$DATA_DIR/delegate"

# unlink <path> <target>: remove the link only if it points at our copy.
unlink_ours() {
  if [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; then
    rm -f "$1"
    echo "[delegate] removed $1"
  fi
}

unlink_ours "$BIN_DIR/agent-spawn" "$DEST/agent-spawn"
unlink_ours "$SKILLS_DIR/delegate" "$DEST/skill/delegate"
unlink_ours "$CLAUDE_SKILLS_DIR/delegate" "$DEST/skill/delegate"
rm -rf "$DEST"
echo "[delegate] removed $DEST (worker state in $DATA_DIR/agents is kept)"
