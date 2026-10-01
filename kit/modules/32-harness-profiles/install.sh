#!/usr/bin/env bash
# Install harness profiles: role prompts (lead|worker), kit-guard hooks, session context (brain recall,
# project KERN.md) and status line for every detected AI harness. No network, no sudo.
# Needs python3 or the kit CPython (01-prereqs, 00-python). Optional: 20-brain, 31-caveman, 40-data-guard.
# Usage: install.sh [--dry-run] [--all | --harness LIST] [--role lead|worker|none]
#                   [--orchestration auto|workbench|delegate|none] [--no-guard] [--no-context] [--no-statusline]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
DEST="$DATA_DIR/harness-profiles"

log() { printf '[profiles] %s\n' "$*"; }
# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
PY="$(kit_find_python)" || { echo "[profiles] ERROR: $(kit_python_hint)" >&2; exit 1; }

for arg in "$@"; do
  if [ "$arg" = "--dry-run" ] || [ "$arg" = "-n" ]; then
    exec "$PY" "$HERE/profiles-setup" install "$@"
  fi
done

# Copy to a stable place so hooks survive removing the stick. Roles are rendered by profiles-setup.
mkdir -p "$DATA_DIR" "$BIN_DIR"
STAGE="$(mktemp -d "$DATA_DIR/.harness-profiles.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
for d in guard context statusline adapters; do cp -R "$HERE/$d" "$STAGE/$d"; done
cp "$HERE/profiles-setup" "$STAGE/"
cp -R "$HERE/roles" "$STAGE/roles-src"
find "$STAGE" -name __pycache__ -prune -exec rm -rf {} +
if [ -d "$DEST" ]; then
  # keep the state; code and role templates are replaced, rendered roles are written again below
  [ -f "$DEST/state.json" ] && cp "$DEST/state.json" "$STAGE/"
  [ -d "$DEST/roles" ] && cp -R "$DEST/roles" "$STAGE/roles"
  rm -rf "$DEST.old"
  mv "$DEST" "$DEST.old"
fi
mv "$STAGE" "$DEST"
rm -rf "$DEST.old"
log "installed $DEST"

for pair in kit-guard:guard/kit-guard kit-context:context/kit-context kit-statusline:statusline/kit-statusline \
            kit-profiles:profiles-setup; do
  name="${pair%%:*}"; script="$DEST/${pair#*:}"
  link="$BIN_DIR/$name"
  tmp="$(mktemp "$BIN_DIR/.$name.XXXXXX")"
  kit_write_py_launcher "$tmp" "$script" "$name"
  if [ -f "$link" ] && cmp -s "$tmp" "$link"; then
    rm -f "$tmp"
  else
    if [ -e "$link" ] && ! kit_is_py_launcher "$link"; then
      rel="${BIN_DIR#"$HOME"/}"; bak="$DATA_DIR/backups/32-harness-profiles/${rel#/}"; mkdir -p "$bak"
      mv "$link" "$bak/$name.bak-$(date +%Y%m%d%H%M%S)"
    fi
    mv "$tmp" "$link"
    log "installed $link"
  fi
done

"$PY" "$DEST/profiles-setup" install "$@"
