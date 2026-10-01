#!/usr/bin/env bash
# Install the brain CLI, its embedding model and the notes repo. Safe to re-run.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"
LIB="$KIT_DIR/modules/00-python/lib.sh"
[ -f "$LIB" ] || { echo "20-brain: $LIB missing; install 00-python first" >&2; exit 1; }
# shellcheck source=../00-python/lib.sh
. "$LIB"
# shellcheck source=model.conf
. "$MODULE_DIR/model.conf"
# shellcheck source=model-variant.sh
. "$MODULE_DIR/model-variant.sh"

MODEL_SRC="$KIT_OFFLINE/models/$BRAIN_MODEL_NAME"
MODEL_DST="$KIT_DATA_DIR/models/$BRAIN_MODEL_NAME"
BRAIN_HOME="${BRAIN_HOME:-$HOME/work/brain}"
export PATH="$KIT_BIN_DIR:$PATH"

say() { printf '20-brain: %s\n' "$*"; }

# 1. CLI
kit_uv_tool_install "$MODULE_DIR"
command -v brain >/dev/null 2>&1 || { say "brain not on PATH after install"; exit 1; }

# 2. Embedding model: one int8 variant for this CPU (without it search is BM25 only)
variant="$(brain_model_variant)"
onnx="$(brain_model_onnx "$variant")"
if [ -f "$MODEL_SRC/$onnx" ] && [ -f "$MODEL_SRC/$BRAIN_MODEL_TOKENIZER" ]; then
  spec="${BRAIN_MODEL_SPEC/@ONNX@/$onnx}"
  if [ -f "$MODEL_DST/brain-model.json" ] && [ "$(cat "$MODEL_DST/brain-model.json")" = "$spec" ] \
     && cmp -s "$MODEL_SRC/$onnx" "$MODEL_DST/$onnx" \
     && cmp -s "$MODEL_SRC/$BRAIN_MODEL_TOKENIZER" "$MODEL_DST/$BRAIN_MODEL_TOKENIZER"; then
    say "model $BRAIN_MODEL_NAME ($variant) already installed"
  else
    tmp="$MODEL_DST.tmp"
    rm -rf "$tmp"
    mkdir -p "$tmp/$(dirname "$onnx")"
    cp "$MODEL_SRC/$onnx" "$tmp/$onnx"
    cp "$MODEL_SRC/$BRAIN_MODEL_TOKENIZER" "$tmp/"
    [ -f "$MODEL_SRC/SOURCE.txt" ] && cp "$MODEL_SRC/SOURCE.txt" "$tmp/"
    printf '%s\n' "$spec" > "$tmp/brain-model.json"
    rm -rf "$MODEL_DST"
    mv "$tmp" "$MODEL_DST"
    say "model $BRAIN_MODEL_NAME ($variant) installed to $MODEL_DST"
  fi
else
  say "model not found in $MODEL_SRC; search will use BM25 only"
fi

# 3. Notes repo (existing notes and files are never overwritten)
BRAIN_HOME="$BRAIN_HOME" brain init
BRAIN_HOME="$BRAIN_HOME" brain reindex

say "done. Check with: brain doctor"
say "MCP server command for agent harnesses: brain mcp"
