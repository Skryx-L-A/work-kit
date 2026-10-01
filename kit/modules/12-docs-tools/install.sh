#!/usr/bin/env bash
# Install d2 and pandoc from kit/offline/docs-tools into ~/.local/bin. No network, no sudo.
# Usage: install.sh [d2|pandoc ...]   (default: both)
# Graphviz (dot) is optional and not static: see apt.sh (delegates to 01-prereqs --sudo).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
STATE_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/state"
STATE="$STATE_DIR/12-docs-tools.list"
SRC="$KIT_OFFLINE/docs-tools/bin"

log() { printf '[docs-tools] %s\n' "$*"; }
warn() { printf '[docs-tools] WARNING: %s\n' "$*" >&2; }
die() { printf '[docs-tools] ERROR: %s\n' "$*" >&2; exit 1; }

# backup_file FILE: move FILE to $KIT_DATA_DIR/backups/12-docs-tools/<name>.bak-<timestamp> and record
# the original path in <name>.bak-<timestamp>.origin. Nothing is left beside the original.
backup_file() {
  local dir b
  dir="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/12-docs-tools"
  mkdir -p "$dir"
  b="$dir/$(basename "$1").bak-$(date +%Y%m%d%H%M%S)"
  while [ -e "$b" ]; do b="$b-1"; done
  mv "$1" "$b" || return 1
  printf '%s\n' "$1" >"$b.origin"
  log "backup: $1 -> $b"
}

[ -d "$SRC" ] || die "missing $SRC (kit/offline is incomplete)"
mkdir -p "$BIN_DIR" "$STATE_DIR"
touch "$STATE"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# install_from ARCHIVE_GLOB MEMBER_SUFFIX NAME: unpack the newest archive matching the glob and
# install the file whose path ends in MEMBER_SUFFIX as $BIN_DIR/NAME (backup of a differing file).
install_from() {
  local glob="$1" member="$2" name="$3" archive src dst v f
  archive="$(for f in "$SRC"/$glob; do [ -f "$f" ] && echo "$f"; done | sort | tail -n 1)"
  [ -n "$archive" ] || die "no archive matching $SRC/$glob"
  mkdir -p "$TMP/$name"
  tar -xzf "$archive" -C "$TMP/$name"
  src="$(find "$TMP/$name" -type f -path "*$member" | head -n 1)"
  [ -n "$src" ] || die "$member not found in $archive"
  dst="$BIN_DIR/$name"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    log "up to date: $dst"
  else
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      backup_file "$dst"
    fi
    install -m 0755 "$src" "$dst"
    log "installed $dst"
  fi
  grep -qx "$name" "$STATE" || echo "$name" >>"$STATE"
  if v="$("$dst" --version 2>&1)"; then log "$(printf '%s' "$v" | head -n 1)"
  else warn "$dst does not run here (not Linux x86_64?)"; fi
  rm -rf "${TMP:?}/$name"
}

if [ "$#" -gt 0 ]; then tools=("$@"); else tools=(d2 pandoc); fi
for t in "${tools[@]}"; do
  case "$t" in
    d2) install_from 'd2-v*-linux-amd64.tar.gz' '/bin/d2' d2 ;;
    pandoc) install_from 'pandoc-*-linux-amd64.tar.gz' '/bin/pandoc' pandoc ;;
    *) die "unknown tool: $t (choose from: d2 pandoc)" ;;
  esac
done

command -v dot >/dev/null 2>&1 || log "graphviz (dot) not installed: optional, 'bash $HERE/apt.sh' (sudo, offline apt repo from 01-prereqs)"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) log "WARNING: $BIN_DIR is not on PATH (60-terminal adds it, or add it to ~/.profile)" ;;
esac
