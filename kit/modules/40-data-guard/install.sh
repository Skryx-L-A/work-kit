#!/usr/bin/env bash
# Install data-guard: the CLI, gitleaks rules, the data-class policy and the deny-list.
# Usage: install.sh [--global-hooks]   No network, no sudo. Needs git; gitleaks comes from
# 10-base-tools (without it the guard still runs the deny-list and warns).
#   --global-hooks   opt in: set core.hooksPath so every repository is guarded
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/data-guard"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/work-kit"
GLOBAL=0
[ "${1:-}" = "--global-hooks" ] && GLOBAL=1

log() { printf '[data-guard] %s\n' "$*"; }

# backup_file FILE: move it to <data dir>/backups/40-data-guard/<name>.bak-<timestamp> and
# record the original path in <name>.bak-<timestamp>.origin (nothing is left beside the original).
backup_file() {
  local dir b
  dir="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/40-data-guard"
  mkdir -p "$dir"
  b="$dir/$(basename "$1").bak-$(date +%Y%m%d%H%M%S)"
  while [ -e "$b" ]; do b="$b-1"; done
  mv "$1" "$b"
  printf '%s\n' "$1" >"$b.origin"
  log "backup: $1 -> $b"
}

# copy_managed SRC DST: shipped file the user must not lose.
copy_managed() {
  local src="$1" dst="$2"
  if [ ! -e "$dst" ]; then
    cp "$src" "$dst"; log "created $dst"
  elif cmp -s "$src" "$dst"; then
    log "$dst up to date"
  else
    cp "$src" "$dst.kit-new"
    log "kept your $dst; new shipped version written to $dst.kit-new"
  fi
}

mkdir -p "$DATA_DIR" "$BIN_DIR" "$CONF_DIR"
for f in data-guard hook-stub.sh gitleaks.toml; do
  if [ -f "$DATA_DIR/$f" ] && ! cmp -s "$HERE/$f" "$DATA_DIR/$f"; then
    backup_file "$DATA_DIR/$f"
  fi
  cp "$HERE/$f" "$DATA_DIR/$f"
done
chmod +x "$DATA_DIR/data-guard" "$DATA_DIR/hook-stub.sh"
log "installed $DATA_DIR"

LINK="$BIN_DIR/data-guard"
if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$DATA_DIR/data-guard" ]; then
  :
else
  if [ -e "$LINK" ] || [ -L "$LINK" ]; then backup_file "$LINK"; fi
  ln -s "$DATA_DIR/data-guard" "$LINK"
  log "linked $LINK"
fi

copy_managed "$HERE/data-classes.md" "$CONF_DIR/data-classes.md"
copy_managed "$HERE/deny-patterns.txt" "$CONF_DIR/deny-patterns.txt"

# Refresh hooks that earlier runs placed in repositories or in the global hooks dir.
if [ -f "$CONF_DIR/hooked-repos.list" ]; then
  while IFS= read -r repo; do
    [ -d "$repo/.git" ] && "$DATA_DIR/data-guard" install-hook "$repo" >/dev/null
  done <"$CONF_DIR/hooked-repos.list"
fi
if [ "$GLOBAL" = 1 ]; then
  "$DATA_DIR/data-guard" enable-global
else
  log "per repository: data-guard install-hook <repo>   (global opt-in: install.sh --global-hooks)"
fi
if ! command -v gitleaks >/dev/null 2>&1 && [ ! -x "$BIN_DIR/gitleaks" ]; then
  log "WARNING: gitleaks not found; commits are BLOCKED until 10-base-tools is installed (data-guard fails closed)."
  log "For one commit only: DATA_GUARD_ALLOW_UNSCANNED=1 git commit ..."
fi
log "edit $CONF_DIR/data-classes.md (TODO(ask IT) items) and $CONF_DIR/deny-patterns.txt"
