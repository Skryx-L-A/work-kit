#!/usr/bin/env bash
# Remove the brain CLI, its model and the search index. Notes are kept.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"
# shellcheck source=model.conf
. "$MODULE_DIR/model.conf"
LIB="$KIT_DIR/modules/00-python/lib.sh"
if [ -f "$LIB" ]; then
  # shellcheck source=../00-python/lib.sh
  . "$LIB"
  kit_uv_tool_uninstall kitbrain
else
  KIT_DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
  echo "20-brain: $LIB missing; remove the CLI with 'uv tool uninstall kitbrain'" >&2
fi
BRAIN_HOME="${BRAIN_HOME:-$HOME/work/brain}"
rm -rf "$KIT_DATA_DIR/models/$BRAIN_MODEL_NAME"
rm -rf "$BRAIN_HOME/.brain"
echo "20-brain: removed CLI, model and index. Notes in $BRAIN_HOME are kept."
echo "20-brain: its git hooks stay and do nothing without the CLI."
