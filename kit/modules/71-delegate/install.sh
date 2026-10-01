#!/usr/bin/env bash
# Install agent-spawn and the delegate skill. No network, no sudo. Needs tmux to run workers.
# Usage: install.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
SKILLS_DIR="${KIT_SKILLS_DIR:-$HOME/.agents/skills}"
CLAUDE_SKILLS_DIR="${KIT_CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
DEST="$DATA_DIR/delegate"

log() { printf '[delegate] %s\n' "$*"; }

# backup_file FILE: move FILE to $KIT_DATA_DIR/backups/71-delegate/<name>.bak-<timestamp> and record
# the original path in <name>.bak-<timestamp>.origin. Nothing is left beside the original.
backup_file() {
  local dir b
  dir="$DATA_DIR/backups/71-delegate"
  mkdir -p "$dir"
  b="$dir/$(basename "$1").bak-$(date +%Y%m%d%H%M%S)"
  while [ -e "$b" ]; do b="$b-1"; done
  mv "$1" "$b" || return 1
  printf '%s\n' "$1" >"$b.origin"
  log "backup: $1 -> $b"
}

[ -f "$HERE/agent-spawn" ] || { echo "[delegate] ERROR: $HERE/agent-spawn missing" >&2; exit 1; }
[ -f "$HERE/skill/delegate/SKILL.md" ] || { echo "[delegate] ERROR: skill missing" >&2; exit 1; }

# Copy to a stable place so the links survive removing the stick.
mkdir -p "$DATA_DIR" "$BIN_DIR" "$SKILLS_DIR"
STAGE="$(mktemp -d "$DATA_DIR/.delegate.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp "$HERE/agent-spawn" "$STAGE/agent-spawn"
chmod +x "$STAGE/agent-spawn"
cp "$HERE/harnesses.conf.example" "$STAGE/harnesses.conf.example"
mkdir -p "$STAGE/skill"
cp -R "$HERE/skill/delegate" "$STAGE/skill/delegate"
if [ -d "$DEST" ] && diff -rq "$STAGE" "$DEST" >/dev/null 2>&1; then
  log "$DEST up to date"
else
  if [ -e "$DEST" ]; then
    backup_file "$DEST"
  fi
  mv "$STAGE" "$DEST"
  log "installed $DEST"
fi

# link <path> <target>: idempotent symlink, existing different content is backed up.
link() {
  if [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]; then
    log "$1 already linked"
    return
  fi
  if [ -e "$1" ] || [ -L "$1" ]; then
    backup_file "$1"
  fi
  ln -s "$2" "$1"
  log "linked $1"
}

link "$BIN_DIR/agent-spawn" "$DEST/agent-spawn"
link "$SKILLS_DIR/delegate" "$DEST/skill/delegate"
# Claude Code reads ~/.claude/skills, not ~/.agents/skills. Link straight to the installed copy
# (a link via ~/.agents/skills would be pruned by kit-sync as a stale skill).
if [ -d "$(dirname "$CLAUDE_SKILLS_DIR")" ]; then
  mkdir -p "$CLAUDE_SKILLS_DIR"
  link "$CLAUDE_SKILLS_DIR/delegate" "$DEST/skill/delegate"
fi

command -v tmux >/dev/null 2>&1 || log "WARNING: tmux not found; agent-spawn needs it: bash <kit>/modules/01-prereqs/install.sh tmux"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) log "WARNING: $BIN_DIR is not on PATH (60-terminal adds it, or add it to ~/.profile)" ;;
esac
log "harness table: cp $DEST/harnesses.conf.example ~/.config/work-kit/harnesses.conf (optional)"
