#!/usr/bin/env bash
# Remove the managed blocks from ~/.bashrc and ~/.tmux.conf and the files install.sh created.
# Your own text in those files, ~/.config/work-kit/bashrc.local and backups are kept
# (backups: ~/.local/share/work-kit/backups/60-terminal).
set -euo pipefail

BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/terminal"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/work-kit"

drop_block() {
  local file="$1" begin end tmp bdir b
  [ -f "$file" ] || return 0
  begin="# >>> work-kit terminal (managed, do not edit) >>>"
  end="# <<< work-kit terminal <<<"
  grep -qxF "$begin" "$file" || return 0
  tmp="$(mktemp)"
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip { print }' "$file" >"$tmp"
  bdir="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/60-terminal"
  mkdir -p "$bdir"
  b="$bdir/$(basename "$file").bak-$(date +%Y%m%d%H%M%S)"
  while [ -e "$b" ]; do b="$b-1"; done
  cp -p "$file" "$b"
  printf '%s\n' "$file" >"$b.origin"
  cat "$tmp" >"$file"  # in place: keeps the mode of the user's file
  rm -f "$tmp"
  echo "[terminal] block removed from $file"
}

drop_block "$HOME/.bashrc"
drop_block "$HOME/.tmux.conf"
rm -f "$CONF_DIR/bashrc.kit" "$CONF_DIR/tmux.conf" "$BIN_DIR/kit-new"
rm -rf "$DATA_DIR/project-template"
rmdir "$DATA_DIR" 2>/dev/null || true
echo "[terminal] removed"
