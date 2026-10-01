#!/usr/bin/env bash
# Stop the server and remove kit-llm, the engine and (unless --keep-models) the models.
# The settings file ~/.config/work-kit/local-llm.conf is kept.
set -euo pipefail

BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
LLM_HOME="${KIT_LLM_HOME:-$DATA_DIR/local-llm}"
KEEP=0
[ "${1:-}" = "--keep-models" ] && KEEP=1

log() { printf '[local-llm] %s\n' "$*"; }

if [ -x "$BIN_DIR/kit-llm" ]; then
  KIT_LLM_HOME="$LLM_HOME" "$BIN_DIR/kit-llm" stop || true
fi
if [ -f "$BIN_DIR/kit-llm" ] && grep -q '^# kit-llm: run a local GGUF model' "$BIN_DIR/kit-llm"; then
  rm -f "$BIN_DIR/kit-llm"
  log "removed $BIN_DIR/kit-llm"
fi
if [ -d "$LLM_HOME" ]; then
  if [ "$KEEP" = 1 ]; then
    find "$LLM_HOME" -mindepth 1 -maxdepth 1 ! -name models -exec rm -rf {} +
    log "removed engine and state, kept $LLM_HOME/models"
  else
    rm -rf "$LLM_HOME"
    log "removed $LLM_HOME"
  fi
fi
