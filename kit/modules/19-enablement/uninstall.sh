#!/usr/bin/env bash
# Remove the enablement files that install.sh copied and you did not edit.
# Edited files, backups (below ~/.local/share/work-kit/backups) and your own files stay.
set -euo pipefail

DEST="${ENABLEMENT_HOME:-$HOME/work/enablement}"
STATE="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/state/19-enablement.sha256"

hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

[ -f "$STATE" ] || { echo "[enablement] nothing to remove (no state file)"; exit 0; }
removed=0 kept=0
while read -r h rel; do
  [ -n "$rel" ] || continue
  f="$DEST/$rel"
  [ -f "$f" ] || continue
  if [ "$(hash_of "$f")" = "$h" ]; then
    rm -f "$f"; removed=$((removed + 1))
  else
    echo "[enablement] kept edited file $f"; kept=$((kept + 1))
  fi
done <"$STATE"
# Remove directories that are now empty (deepest first); keep DEST if anything is left.
find "$DEST" -depth -type d -empty -delete 2>/dev/null || true
rm -f "$STATE"
echo "[enablement] removed $removed files, kept $kept edited files"
