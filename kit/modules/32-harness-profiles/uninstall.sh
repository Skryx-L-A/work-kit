#!/usr/bin/env bash
# Remove harness profiles: kit hook entries, role files and blocks, pi/opencode adapters, launchers,
# installed copy. Your own settings and text stay. Backups (*.bak-*) are kept.
# Usage: uninstall.sh [--dry-run]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DEST="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/harness-profiles"
# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
PY="$(kit_find_python)" || { echo "[profiles] ERROR: $(kit_python_hint)" >&2; exit 1; }
DRY=0
for arg in "$@"; do
  { [ "$arg" = "--dry-run" ] || [ "$arg" = "-n" ]; } && DRY=1
done

"$PY" "$HERE/profiles-setup" uninstall "$@"
[ "$DRY" = 1 ] && exit 0
for name in kit-guard kit-context kit-statusline kit-profiles; do
  if kit_is_py_launcher "$BIN_DIR/$name"; then rm -f "$BIN_DIR/$name"; fi
done
rm -rf "$DEST"
echo "[profiles] removed $DEST"
