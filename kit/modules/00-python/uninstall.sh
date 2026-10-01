#!/usr/bin/env bash
# Remove uv and the standalone Python installed by install.sh. Tools installed by other
# modules (brain, evalkit) stop working afterwards; uninstall those first.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

if [ -x "$KIT_BIN_DIR/uv" ]; then
  "$KIT_BIN_DIR/uv" python uninstall --no-config "$KIT_PYTHON_VERSION" 2>/dev/null || true
fi
rm -f "$KIT_BIN_DIR/uv" "$KIT_BIN_DIR/uvx"
rm -f "$KIT_DATA_DIR/state/00-python.installed"
kit_log "removed uv and Python $KIT_PYTHON_VERSION (backups in ~/.local/share/work-kit/backups are kept)"
