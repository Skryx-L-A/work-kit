#!/usr/bin/env bash
# Install 17-meeting-capture: the `meeting` CLI, the meeting AI policy template and a settings
# file in ~/.config/work-kit/. No network, no sudo. Needs python3 or the kit CPython
# (01-prereqs, 00-python; the module does not depend on either). The speech engine comes from
# 80-quassel (optional here; `meeting engine` says what is missing). Re-running never
# overwrites a policy or settings file you edited: the new shipped version goes next to it as
# <file>.kit-new.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/meeting-capture"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/work-kit"
STAMP="$(date +%Y%m%d%H%M%S)"

log() { printf '[meeting-capture] %s\n' "$*"; }

# backup_file FILE: move FILE to $KIT_DATA_DIR/backups/17-meeting-capture/<name>.bak-<timestamp> and record
# the original path in <name>.bak-<timestamp>.origin. Nothing is left beside the original.
backup_file() {
  local dir b
  dir="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/17-meeting-capture"
  mkdir -p "$dir"
  b="$dir/$(basename "$1").bak-$STAMP"
  while [ -e "$b" ]; do b="$b-1"; done
  mv "$1" "$b" || return 1
  printf '%s\n' "$1" >"$b.origin"
  log "backup: $1 -> $b"
}

# copy_managed SRC DST: shipped file the user edits; never overwrite their version.
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

# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
kit_find_python >/dev/null || { log "ERROR: $(kit_python_hint)"; exit 1; }

log "1/3 CLI"
mkdir -p "$BIN_DIR" "$CONF_DIR" "$DATA_DIR"
chmod 700 "$DATA_DIR"
if [ -f "$DATA_DIR/meeting" ] && ! cmp -s "$HERE/meeting" "$DATA_DIR/meeting"; then
  backup_file "$DATA_DIR/meeting"
fi
cp "$HERE/meeting" "$DATA_DIR/meeting"
chmod +x "$DATA_DIR/meeting"

# meeting is a launcher, not a link: the script's python3 shebang fails without system python.
LINK="$BIN_DIR/meeting"
LTMP="$(mktemp "$BIN_DIR/.meeting.XXXXXX")"
kit_write_py_launcher "$LTMP" "$DATA_DIR/meeting" meeting
if [ -f "$LINK" ] && [ ! -L "$LINK" ] && cmp -s "$LTMP" "$LINK"; then
  rm -f "$LTMP"
else
  if [ -e "$LINK" ] || [ -L "$LINK" ]; then backup_file "$LINK"; fi
  mv "$LTMP" "$LINK"
  log "installed $LINK"
fi

log "2/3 policy and settings"
copy_managed "$HERE/policy/meeting-ai-policy.md" "$CONF_DIR/meeting-ai-policy.md"
copy_managed "$HERE/policy/meeting.conf" "$CONF_DIR/meeting.conf"

log "3/3 speech engine check"
"$LINK" engine || log "note: fix the items above before the first recording"
log "next: meeting policy --todo   (questions for IT)   meeting start   (consent reminder, then record)"
