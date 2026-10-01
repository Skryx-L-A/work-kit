#!/usr/bin/env bash
# Remove everything install.sh placed: binaries and wrappers in ~/.local/bin, the semgrep
# tool environment and the module data directory. Backups (in ~/.local/share/work-kit/backups) are kept.
set -euo pipefail

DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
STATE="$DATA_DIR/state/11-legacy-toolbox.list"
TB="$DATA_DIR/legacy-toolbox"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"

log() { printf '[legacy-toolbox] %s\n' "$*"; }

[ -f "$STATE" ] || { log "nothing to remove (no state file)"; exit 0; }
while IFS= read -r line; do
  case "$line" in
    file:*) rm -f "${line#file:}"; log "removed ${line#file:}" ;;
    uvtool:*)
      lib="$KIT_ROOT/modules/00-python/lib.sh"
      if [ -f "$lib" ]; then
        # shellcheck disable=SC1090
        . "$lib"
        kit_uv_tool_uninstall "${line#uvtool:}" || true
      else
        log "00-python/lib.sh not found: run 'uv tool uninstall ${line#uvtool:}' with UV_TOOL_DIR=$DATA_DIR/tools"
      fi ;;
  esac
done <"$STATE"
case "$TB" in
  */work-kit/legacy-toolbox) rm -rf "$TB"; log "removed $TB" ;;
esac
rm -f "$STATE"
