#!/usr/bin/env bash
# Remove the ai-gov CLI and its data. Your policy files in ~/.config/work-kit/ stay
# (guideline, checklist, MCP policy and allowlist); delete them by hand if you want.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/ai-governance"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/work-kit"

# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
if { [ -L "$BIN_DIR/ai-gov" ] && [ "$(readlink "$BIN_DIR/ai-gov")" = "$DATA_DIR/ai-gov" ]; } \
  || kit_is_py_launcher "$BIN_DIR/ai-gov"; then
  rm -f "$BIN_DIR/ai-gov"
fi
rm -rf "$DATA_DIR"
echo "[ai-governance] removed (policy files kept in $CONF_DIR)"
