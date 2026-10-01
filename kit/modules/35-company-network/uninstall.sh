#!/usr/bin/env bash
# Remove kit-net and everything it wrote: net.env, the CA bundle, the environment.d file, the
# marked blocks in ~/.bashrc, the login file and VS Code's settings.json. Your own text in those
# files stays; the company CAs you added are backed up first
# (~/.local/share/work-kit/backups/35-company-network).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/company-network"
log() { printf '[company-network] %s\n' "$*"; }

# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
if PY="$(kit_find_python)"; then
  if [ -f "$DATA/lib/kit_net.py" ]; then "$PY" "$DATA/lib/kit_net.py" purge
  else "$PY" "$HERE/kit_net.py" purge; fi
else
  log "WARNING: no python3: the settings files were not cleaned (kit-net purge needs it)"
fi

if kit_is_py_launcher "$BIN_DIR/kit-net"; then rm -f "$BIN_DIR/kit-net"; fi
rm -rf "${DATA:?}/lib"
rmdir "$DATA" 2>/dev/null || true
log "removed"
