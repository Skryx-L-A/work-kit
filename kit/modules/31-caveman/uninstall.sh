#!/usr/bin/env bash
# Remove caveman chat style: hooks, managed blocks, generated files, skill links, installed copy.
# Text you wrote in CLAUDE.md, AGENTS.md etc. stays. Backups (in ~/.local/share/work-kit/backups) are kept.
# Usage: uninstall.sh [--dry-run] [--project DIR]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DEST="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/caveman"
# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
PY="$(kit_find_python)" || { echo "[caveman] ERROR: $(kit_python_hint)" >&2; exit 1; }
DRY=0
for arg in "$@"; do
  { [ "$arg" = "--dry-run" ] || [ "$arg" = "-n" ]; } && DRY=1
done

# Use the installed copy: its paths are the ones the settings and links point at.
if [ -x "$DEST/caveman-setup" ]; then
  "$PY" "$DEST/caveman-setup" uninstall "$@"
else
  "$PY" "$HERE/caveman-setup" uninstall "$@"
fi
# Project mode and dry runs leave the installation itself alone.
case " $* " in *" --project "*) exit 0 ;; esac
[ "$DRY" = 1 ] && exit 0
if [ -L "$BIN_DIR/kit-caveman" ] || kit_is_py_launcher "$BIN_DIR/kit-caveman"; then rm -f "$BIN_DIR/kit-caveman"; fi
rm -rf "$DEST"
echo "[caveman] removed $DEST"
