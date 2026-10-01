#!/usr/bin/env bash
# Install static CLI tools from kit/offline/bin into ~/.local/bin. No network, no sudo.
# Usage: install.sh [tool ...]   (default: every binary found in kit/offline/bin)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
STATE_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/state"
STATE="$STATE_DIR/10-base-tools.list"
SRC_DIR="$KIT_OFFLINE/bin"

log() { printf '[base-tools] %s\n' "$*"; }
die() { printf '[base-tools] ERROR: %s\n' "$*" >&2; exit 1; }

# backup_file FILE: move FILE to $KIT_DATA_DIR/backups/10-base-tools/<name>.bak-<timestamp> and record
# the original path in <name>.bak-<timestamp>.origin. Nothing is left beside the original.
backup_file() {
  local dir b
  dir="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/10-base-tools"
  mkdir -p "$dir"
  b="$dir/$(basename "$1").bak-$(date +%Y%m%d%H%M%S)"
  while [ -e "$b" ]; do b="$b-1"; done
  mv "$1" "$b" || return 1
  printf '%s\n' "$1" >"$b.origin"
  log "backup: $1 -> $b"
}

[ -d "$SRC_DIR" ] || die "missing $SRC_DIR (kit/offline is incomplete)"

if [ "$#" -gt 0 ]; then
  tools=("$@")
else
  tools=()
  for f in "$SRC_DIR"/*; do
    [ -f "$f" ] && tools+=("$(basename "$f")")
  done
fi
[ "${#tools[@]}" -gt 0 ] || die "no binaries in $SRC_DIR"

mkdir -p "$BIN_DIR" "$STATE_DIR"
touch "$STATE"

for t in "${tools[@]}"; do
  src="$SRC_DIR/$t"
  dst="$BIN_DIR/$t"
  [ -f "$src" ] || die "no such tool in kit/offline/bin: $t"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    log "$t up to date"
  else
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      backup_file "$dst"
    fi
    install -m 0755 "$src" "$dst"
    log "installed $dst"
  fi
  grep -qx "$t" "$STATE" || echo "$t" >>"$STATE"
done

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) log "WARNING: $BIN_DIR is not on PATH (60-terminal adds it, or add it to ~/.profile)" ;;
esac
