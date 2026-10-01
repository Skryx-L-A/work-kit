#!/usr/bin/env bash
# Remove the `meeting` CLI and its data. Your policy and settings files in
# ~/.config/work-kit/ and your notes stay; recordings still waiting in the state folder are
# deleted only with --purge-audio.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/meeting-capture"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/work-kit"

# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
if { [ -L "$BIN_DIR/meeting" ] && [ "$(readlink "$BIN_DIR/meeting")" = "$DATA_DIR/meeting" ]; } \
  || kit_is_py_launcher "$BIN_DIR/meeting"; then
  rm -f "$BIN_DIR/meeting"
fi

if [ "${1:-}" = "--purge-audio" ]; then
  rm -rf "$DATA_DIR"
  echo "[meeting-capture] removed, including recordings in the state folder"
else
  rm -f "$DATA_DIR/meeting" "$DATA_DIR/state/current.json"
  if ls "$DATA_DIR"/state/audio/* >/dev/null 2>&1; then
    echo "[meeting-capture] removed; recordings kept in $DATA_DIR/state/audio (delete with: bash uninstall.sh --purge-audio)"
  else
    rm -rf "$DATA_DIR"
    echo "[meeting-capture] removed"
  fi
fi
echo "[meeting-capture] kept: policy and settings in $CONF_DIR, notes in ~/work/meetings and the brain"
