#!/usr/bin/env bash
# Remove the llm-usage CLI. Recorded usage logs and llm-prices.toml are kept.
set -euo pipefail
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
log() { printf '[llm-usage] %s\n' "$*"; }
if [ -x "$BIN_DIR/llm-usage" ]; then "$BIN_DIR/llm-usage" stop >/dev/null 2>&1 || true; fi
if [ -f "$BIN_DIR/llm-usage" ] && grep -q '^# llm-usage launcher' "$BIN_DIR/llm-usage"; then
  rm -f "$BIN_DIR/llm-usage"; log "removed $BIN_DIR/llm-usage"
fi
rm -rf "$DATA_DIR/llm-usage-lib"
log "kept logs in $DATA_DIR/llm-usage (delete by hand if not needed)"
