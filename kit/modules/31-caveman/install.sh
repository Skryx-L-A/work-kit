#!/usr/bin/env bash
# Install caveman chat style (level full) for every detected AI harness. No network, no sudo.
# Needs python3 or the kit CPython (01-prereqs, 00-python); node is optional (hooks fall back to shell without it).
# Usage: install.sh [--dry-run] [--all | --harness LIST] [--project DIR]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
DEST="$DATA_DIR/caveman"

log() { printf '[caveman] %s\n' "$*"; }

# backup_file FILE: move FILE to $KIT_DATA_DIR/backups/31-caveman/<name>.bak-<timestamp> and record
# the original path in <name>.bak-<timestamp>.origin. Nothing is left beside the original.
backup_file() {
  local dir b
  dir="$DATA_DIR/backups/31-caveman"
  mkdir -p "$dir"
  b="$dir/$(basename "$1").bak-$(date +%Y%m%d%H%M%S)"
  while [ -e "$b" ]; do b="$b-1"; done
  mv "$1" "$b" || return 1
  printf '%s\n' "$1" >"$b.origin"
  log "backup: $1 -> $b"
}
# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
PY="$(kit_find_python)" || { echo "[caveman] ERROR: $(kit_python_hint)" >&2; exit 1; }
for f in caveman-setup caveman-hook.sh rules/caveman-rule.md upstream/SHA256SUMS; do
  [ -f "$HERE/$f" ] || { echo "[caveman] ERROR: $HERE/$f missing" >&2; exit 1; }
done

# Dry run: nothing is copied, the setup script only reports.
for arg in "$@"; do
  if [ "$arg" = "--dry-run" ] || [ "$arg" = "-n" ]; then
    "$PY" "$HERE/caveman-setup" verify
    exec "$PY" "$HERE/caveman-setup" install "$@"
  fi
done

# Copy to a stable place so hooks and links survive removing the stick.
mkdir -p "$DATA_DIR" "$BIN_DIR"
STAGE="$(mktemp -d "$DATA_DIR/.caveman.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$HERE/upstream" "$STAGE/upstream"
cp -R "$HERE/rules" "$STAGE/rules"
cp "$HERE/caveman-hook.sh" "$HERE/caveman-setup" "$STAGE/"
chmod +x "$STAGE/caveman-hook.sh" "$STAGE/caveman-setup" "$STAGE/upstream/src/hooks/caveman-statusline.sh"
"$PY" "$STAGE/caveman-setup" verify

if [ -d "$DEST" ] && diff -rq "$STAGE" "$DEST" >/dev/null 2>&1; then
  log "$DEST up to date"
else
  if [ -e "$DEST" ]; then
    backup_file "$DEST"
  fi
  mv "$STAGE" "$DEST"
  log "installed $DEST"
fi

# kit-caveman is a launcher, not a link: the script's python3 shebang fails without system python.
LINK="$BIN_DIR/kit-caveman"
LTMP="$(mktemp "$BIN_DIR/.kit-caveman.XXXXXX")"
kit_write_py_launcher "$LTMP" "$DEST/caveman-setup" kit-caveman
if [ -f "$LINK" ] && [ ! -L "$LINK" ] && cmp -s "$LTMP" "$LINK"; then
  rm -f "$LTMP"
  log "kit-caveman already installed"
else
  if [ -e "$LINK" ] || [ -L "$LINK" ]; then
    backup_file "$LINK"
  fi
  mv "$LTMP" "$LINK"
  log "installed $LINK"
fi

"$PY" "$DEST/caveman-setup" install "$@"
command -v node >/dev/null 2>&1 || log "node not found: Claude Code hooks use the shell fallback (level full only)"
log "restart the harness; Claude Code hooks fire at session start"
