#!/usr/bin/env bash
# Install kit-models: registers company model endpoints for every harness and kit tool.
# Standard-library Python (python3 or the kit CPython), no network, no sudo, no other module.
# Re-running refreshes the CLI and rewrites the targets of endpoints that are already registered.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DEST="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/model-endpoints/lib"
STAMP="$(date +%Y%m%d%H%M%S)"
log() { printf '[model-endpoints] %s\n' "$*"; }

# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
kit_find_python >/dev/null || { log "ERROR: $(kit_python_hint)"; exit 1; }

mkdir -p "$BIN_DIR" "$DEST"
for f in kit_models.py kit_models_files.py kit_models_proxy.py kit_models_targets.py; do
  install -m 0644 "$HERE/$f" "$DEST/$f"
done
rm -rf "$DEST/__pycache__"

LINK="$BIN_DIR/kit-models"
LTMP="$(mktemp "$BIN_DIR/.kit-models.XXXXXX")"
kit_write_py_launcher "$LTMP" "$DEST/kit_models.py" kit-models
if [ -f "$LINK" ] && [ ! -L "$LINK" ] && cmp -s "$LTMP" "$LINK"; then
  rm -f "$LTMP"
  log "kit-models up to date"
else
  if [ -e "$LINK" ] || [ -L "$LINK" ]; then mv "$LINK" "$LINK.bak-$STAMP"; log "backup: $LINK.bak-$STAMP"; fi
  mv "$LTMP" "$LINK"
  log "installed $LINK"
fi

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/work-kit/model-endpoints.json"
if [ -f "$CONF" ]; then
  "$LINK" sync
else
  log "next: kit-models add   (asks for URL, models, key; see kit-models --help)"
fi
