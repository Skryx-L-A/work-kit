#!/usr/bin/env bash
# Install kit-sync and the shared agent instructions/skills, then sync every detected harness.
# Usage: install.sh [--no-sync] [--permissions bypass|ask]
# No network, no sudo. Needs python3 or the kit CPython of module 00-python.
# The approval mode can also come from KIT_PERMISSIONS; without either, kit.conf or bypass.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
DEST="$DATA_DIR/agent-setup"
BACKUPS="$DATA_DIR/backups/30-agent-setup"   # never next to your files
RUN_SYNC=1
SYNC_ARGS=()
[ -n "${KIT_PERMISSIONS:-}" ] && SYNC_ARGS=(--permissions "$KIT_PERMISSIONS")
while [ $# -gt 0 ]; do
  case "$1" in
    --no-sync) RUN_SYNC=0 ;;
    --permissions) SYNC_ARGS=(--permissions "${2:?--permissions needs bypass or ask}"); shift ;;
    --permissions=*) SYNC_ARGS=(--permissions "${1#*=}") ;;
    *) echo "[agent-setup] ERROR: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

log() { printf '[agent-setup] %s\n' "$*"; }
if [ "${#SYNC_ARGS[@]}" -gt 0 ]; then
  case "${SYNC_ARGS[1]}" in
    bypass|ask) ;;
    *) echo "[agent-setup] ERROR: permissions must be bypass or ask, not '${SYNC_ARGS[1]}'" >&2; exit 2 ;;
  esac
fi
[ -f "$HERE/source/AGENTS.md" ] || { echo "[agent-setup] ERROR: $HERE/source/AGENTS.md missing" >&2; exit 1; }

# Copy kit-sync and source/ to a stable place so links survive removing the stick.
mkdir -p "$DATA_DIR" "$BIN_DIR"
STAGE="$(mktemp -d "$DATA_DIR/.agent-setup.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$HERE/source" "$STAGE/source"
cp -R "$HERE/git-hooks" "$STAGE/git-hooks"
cp "$HERE/kit-sync" "$STAGE/kit-sync"
chmod +x "$STAGE/kit-sync" "$STAGE/git-hooks/dispatch"
if [ -d "$DEST" ] && diff -rq "$STAGE" "$DEST" >/dev/null 2>&1; then
  log "$DEST up to date"
else
  if [ -e "$DEST" ]; then
    mkdir -p "$BACKUPS"
    mv "$DEST" "$BACKUPS/agent-setup.bak-$(date +%Y%m%d%H%M%S)"
    log "previous copy kept as $BACKUPS/agent-setup.bak-*"
  fi
  mv "$STAGE" "$DEST"
  log "installed $DEST"
fi

LINK="$BIN_DIR/kit-sync"
if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$DEST/kit-sync" ]; then
  log "kit-sync already linked"
else
  if [ -e "$LINK" ] || [ -L "$LINK" ]; then
    rel="${BIN_DIR#"$HOME"/}"; mkdir -p "$BACKUPS/${rel#/}"
    mv "$LINK" "$BACKUPS/${rel#/}/kit-sync.bak-$(date +%Y%m%d%H%M%S)"
  fi
  ln -s "$DEST/kit-sync" "$LINK"
  log "linked $LINK"
fi

if [ "$RUN_SYNC" = 1 ]; then
  "$DEST/kit-sync" ${SYNC_ARGS[@]+"${SYNC_ARGS[@]}"}
fi
