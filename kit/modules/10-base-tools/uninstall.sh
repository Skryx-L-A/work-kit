#!/usr/bin/env bash
# Remove the tools that install.sh placed in ~/.local/bin. Backups in ~/.local/share/work-kit/backups are kept.
set -euo pipefail

BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
STATE="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/state/10-base-tools.list"

[ -f "$STATE" ] || { echo "[base-tools] nothing to remove (no state file)"; exit 0; }
while IFS= read -r t; do
  [ -n "$t" ] || continue
  rm -f "$BIN_DIR/$t"
  echo "[base-tools] removed $BIN_DIR/$t"
done <"$STATE"
rm -f "$STATE"
