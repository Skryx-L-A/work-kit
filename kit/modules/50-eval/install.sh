#!/usr/bin/env bash
# Install evalkit from offline/wheels into ~/.local/bin (user level, no sudo).
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KIT_DIR="${KIT_DIR:-$(cd "$MODULE_DIR/../.." && pwd)}"
export PATH="${KIT_BIN_DIR:-$HOME/.local/bin}:$PATH"

LIB="$KIT_DIR/modules/00-python/lib.sh"
if [ -f "$LIB" ]; then
  # shellcheck source=/dev/null
  . "$LIB"
else
  # Fallback used only when 00-python is not part of this checkout; keeps the module testable alone.
  # With 00-python, kit_uv_tool_install runs uv with umask 022 and clears world-writable .lock files.
  kit_uv_tool_install() {
    local pkgdir="$1" name
    name="$(sed -n 's/^name = "\(.*\)"/\1/p' "$pkgdir/pyproject.toml" | head -n1)"
    # umask 022: uv creates its .lock files with the umask, keep them from being world-writable
    ( umask 022; uv tool install --offline --force --reinstall-package "$name" --find-links "$KIT_DIR/offline/wheels" "$name" ) || return
    # uv makes its .lock files 0666 whatever the umask
    find "${KIT_DATA_DIR:-$HOME/.local/share/work-kit}" -maxdepth 5 -name .lock -type f -perm -002 \
      -exec chmod go-w {} + 2>/dev/null || true
  }
fi

command -v uv >/dev/null 2>&1 || { echo "uv not found: install module 00-python first" >&2; exit 1; }

kit_uv_tool_install "$MODULE_DIR"
echo "evalkit installed: $(command -v evalkit || echo "$HOME/.local/bin/evalkit (add $HOME/.local/bin to PATH)")"
