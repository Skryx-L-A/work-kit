#!/usr/bin/env bash
# Remove what kit-sync created (managed blocks, generated files, skill links) and kit-sync itself.
# Text you wrote in CLAUDE.md, AGENTS.md etc. stays. Backups (*.bak-* in
# ~/.local/share/work-kit/backups/30-agent-setup/) are kept.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DEST="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/agent-setup"

if [ -x "$DEST/kit-sync" ]; then
  "$DEST/kit-sync" --uninstall
else
  KIT_SYNC_SOURCE="$HERE/source" "$HERE/kit-sync" --uninstall
fi
[ -L "$BIN_DIR/kit-sync" ] && rm -f "$BIN_DIR/kit-sync"
rm -rf "$DEST"
echo "[agent-setup] removed"
