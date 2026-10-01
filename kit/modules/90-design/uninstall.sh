#!/usr/bin/env bash
# Remove kit-design. Reference folders stay, except kit READMEs in folders with nothing else in them.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
STATE_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/state"
REFS="${DESIGN_REFS:-$HOME/work/design-refs}"
if [ -z "${DESIGN_REFS:-}" ] && [ -f "$STATE_DIR/90-design.env" ]; then
  # shellcheck source=/dev/null
  . "$STATE_DIR/90-design.env"
  REFS="$DESIGN_REFS"
fi

if [ -f "$KIT_ROOT/modules/00-python/lib.sh" ]; then
  # shellcheck source=/dev/null
  . "$KIT_ROOT/modules/00-python/lib.sh"
  kit_uv_tool_uninstall kit-design || true
fi

for c in brand web slides documents diagrams; do
  d="$REFS/$c"
  [ -d "$d" ] || continue
  if [ -f "$d/README.md" ] && cmp -s "$HERE/refs/$c/README.md" "$d/README.md"; then
    rm -f "$d/README.md"
  fi
  rmdir "$d" 2>/dev/null && echo "[design] removed empty $d" || echo "[design] kept $d (has your files)"
done
rmdir "$REFS" 2>/dev/null || true
rm -f "$STATE_DIR/90-design.env"
rm -f "${KIT_BIN_DIR:-$HOME/.local/bin}/kit-chrome-headless"
rm -rf "${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/design/chrome-headless-shell"
echo "[design] uninstalled"
