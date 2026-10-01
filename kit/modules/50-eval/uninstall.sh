#!/usr/bin/env bash
# Remove evalkit. Saved results stay unless --purge is given.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="${KIT_DIR:-$(cd "$MODULE_DIR/../.." && pwd)}"
export PATH="${KIT_BIN_DIR:-$HOME/.local/bin}:$PATH"

# The tool lives in the kit's own uv tool dir (00-python/lib.sh), not in the user's default one.
LIB="$KIT_DIR/modules/00-python/lib.sh"
if [ -f "$LIB" ]; then
  # shellcheck source=/dev/null
  . "$LIB"
  kit_uv_tool_uninstall evalkit
elif command -v uv >/dev/null 2>&1 && uv tool list 2>/dev/null | grep -q '^evalkit '; then
  uv tool uninstall evalkit
else
  echo "evalkit is not installed"
fi

data="${EVALKIT_HOME:-$HOME/.local/share/work-kit/evalkit}"
if [ "${1:-}" = "--purge" ]; then
  rm -rf "$data"
  echo "removed $data"
elif [ -d "$data" ]; then
  echo "kept saved results in $data (use --purge to delete)"
fi
