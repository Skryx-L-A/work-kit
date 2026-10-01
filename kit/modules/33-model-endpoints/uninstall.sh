#!/usr/bin/env bash
# Remove kit-models. Without --purge the endpoint registry and the keys stay, and so do the
# entries in harness configs (run `kit-models remove <name>` first to take those out).
# With --purge: every endpoint is removed from every target, then registry, keys and the
# shell snippet are deleted.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/model-endpoints"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/work-kit"
log() { printf '[model-endpoints] %s\n' "$*"; }

# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
CLI=()
if [ -f "$DATA/lib/kit_models.py" ] && PY="$(kit_find_python)"; then
  CLI=("$PY" "$DATA/lib/kit_models.py")
elif PY="$(kit_find_python)"; then
  CLI=("$PY" "$HERE/kit_models.py")
fi

if [ "${#CLI[@]}" -gt 0 ]; then
  "${CLI[@]}" proxy stop >/dev/null 2>&1 || true
  if [ "${1:-}" = "--purge" ]; then
    "${CLI[@]}" purge
  fi
fi

if kit_is_py_launcher "$BIN_DIR/kit-models"; then rm -f "$BIN_DIR/kit-models"; fi
rm -rf "${DATA:?}/lib" "${DATA:?}/proxy.pid"
if [ "${1:-}" = "--purge" ]; then
  rm -rf "$DATA"
  log "removed, including registry, keys and harness entries"
else
  log "removed the CLI; kept $CONF_DIR/model-endpoints.json, $CONF_DIR/secrets.env and harness entries"
  log "(bash uninstall.sh --purge removes those too)"
fi
