#!/usr/bin/env bash
# Install the Kit Workbench VS Code extension from the offline .vsix and the kit-wb helper.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="${KIT_DIR:-$(cd "$MODULE_DIR/../.." && pwd)}"
BIN="$HOME/.local/bin"
CODE="${CODE:-code}"

VSIX=""
for candidate in "$MODULE_DIR/kit-workbench.vsix" "$KIT_DIR/offline/vscode/kit-workbench.vsix"; do
  if [ -f "$candidate" ]; then VSIX="$candidate"; break; fi
done
[ -n "$VSIX" ] || { echo "kit-workbench.vsix not found (run ./build.sh on the build machine)" >&2; exit 1; }

# kit-wb: terminal orchestrators delegate through it. Keep a user-edited file as a backup.
mkdir -p "$BIN"
SRC="$MODULE_DIR/extension/resources/bin/kit-wb"
if [ -e "$BIN/kit-wb" ] && ! cmp -s "$SRC" "$BIN/kit-wb"; then
  # backup below the kit data dir, original path recorded in <name>.origin
  BAK_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/72-vscode-workbench"
  mkdir -p "$BAK_DIR"
  BAK="$BAK_DIR/kit-wb.bak-$(date +%Y%m%d%H%M%S)"
  while [ -e "$BAK" ]; do BAK="$BAK-1"; done
  cp -p "$BIN/kit-wb" "$BAK"
  printf '%s\n' "$BIN/kit-wb" >"$BAK.origin"
  echo "backup: $BIN/kit-wb -> $BAK"
fi
install -m 755 "$SRC" "$BIN/kit-wb"
echo "kit-wb installed: $BIN/kit-wb"

if command -v "$CODE" >/dev/null 2>&1; then
  "$CODE" --install-extension "$VSIX" --force
  echo "Kit Workbench installed. Reload VS Code windows that are open."
else
  echo "VS Code CLI '$CODE' not found. Install manually:"
  echo "  VS Code > Extensions > ... > Install from VSIX... > $VSIX"
  echo "  or: code --install-extension '$VSIX'"
fi
