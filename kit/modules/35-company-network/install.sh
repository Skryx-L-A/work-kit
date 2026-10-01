#!/usr/bin/env bash
# Install kit-net. It changes no network behaviour: proxy and CA settings are written only when
# the user runs `kit-net proxy set` or `kit-net ca add`. Re-running refreshes the CLI and, when
# settings already exist, rewrites their files. Standard-library Python (python3 or the kit CPython).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DEST="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/company-network/lib"
STAMP="$(date +%Y%m%d%H%M%S)"
BAK_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/35-company-network"
log() { printf '[company-network] %s\n' "$*"; }

# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
kit_find_python >/dev/null || { log "ERROR: $(kit_python_hint)"; exit 1; }

mkdir -p "$BIN_DIR" "$DEST"
install -m 0644 "$HERE/kit_net.py" "$DEST/kit_net.py"
rm -rf "$DEST/__pycache__"

LINK="$BIN_DIR/kit-net"
LTMP="$(mktemp "$BIN_DIR/.kit-net.XXXXXX")"
kit_write_py_launcher "$LTMP" "$DEST/kit_net.py" kit-net
if [ -f "$LINK" ] && [ ! -L "$LINK" ] && cmp -s "$LTMP" "$LINK"; then
  rm -f "$LTMP"
  log "kit-net up to date"
else
  if [ -e "$LINK" ] || [ -L "$LINK" ]; then
    mkdir -p "$BAK_DIR"
    mv "$LINK" "$BAK_DIR/kit-net.bak-$STAMP"
    printf '%s\n' "$LINK" >"$BAK_DIR/kit-net.bak-$STAMP.origin"
    log "backup: $BAK_DIR/kit-net.bak-$STAMP"
  fi
  mv "$LTMP" "$LINK"
  log "installed $LINK"
fi

if [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/work-kit/net.json" ]; then
  "$LINK" refresh
else
  log "nothing is set. Behind a proxy: kit-net proxy set <url>. Company root certificate: kit-net ca add <file>"
fi
