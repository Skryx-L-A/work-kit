#!/usr/bin/env bash
# Install the terminal setup: additive bash/tmux/direnv config, project template, kit-new.
# No network, no sudo. Your ~/.bashrc and ~/.tmux.conf keep their content; a managed block is
# added (after a backup) that loads the kit files. Needs nothing else; fzf, direnv, just, fd
# are used when present (10-base-tools).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/terminal"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/work-kit"
DIRENV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/direnv"

log() { printf '[terminal] %s\n' "$*"; }
stamp() { date +%Y%m%d%H%M%S; }
BAK_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/60-terminal"

# backup MODE PATH: keep PATH (MODE cp: copy, mv: move) under $BAK_DIR/<name>.bak-<timestamp>
# and record the original path in <name>.bak-<timestamp>.origin. Nothing lands beside PATH.
backup() {
  local mode="$1" f="$2" b
  mkdir -p "$BAK_DIR"
  b="$BAK_DIR/$(basename "$f").bak-$(stamp)"
  while [ -e "$b" ]; do b="$b-1"; done
  if [ "$mode" = mv ]; then mv "$f" "$b"; else cp -pR "$f" "$b"; fi
  printf '%s\n' "$f" >"$b.origin"
  log "backup: $f -> $b"
}

# put_file SRC DST: our own file, replaced when it changed (old one is kept as a backup).
put_file() {
  local src="$1" dst="$2"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then log "$dst up to date"; return; fi
  if [ -e "$dst" ]; then backup mv "$dst"; fi
  cp "$src" "$dst"
  log "installed $dst"
}

# put_block FILE NAME LINE...: managed block in a user file, other text untouched.
put_block() {
  local file="$1" name="$2" begin end tmp
  shift 2
  begin="# >>> work-kit $name (managed, do not edit) >>>"
  end="# <<< work-kit $name <<<"
  tmp="$(mktemp)"
  {
    if [ -f "$file" ]; then
      awk -v b="$begin" -v e="$end" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip { print }' "$file"
    fi
    printf '%s\n' "$begin"
    printf '%s\n' "$@"
    printf '%s\n' "$end"
  } >"$tmp"
  if [ -f "$file" ] && cmp -s "$tmp" "$file"; then
    log "$file up to date"
    rm -f "$tmp"
    return
  fi
  if [ -f "$file" ]; then
    backup cp "$file"
    cat "$tmp" >"$file"  # rewrite in place: keeps the owner's mode (and a symlinked dotfile)
  else
    install -m 644 "$tmp" "$file"
  fi
  rm -f "$tmp"
  log "updated $file"
}

mkdir -p "$BIN_DIR" "$DATA_DIR" "$CONF_DIR" "$DIRENV_DIR" "$HOME/work"

put_file "$HERE/bashrc.kit" "$CONF_DIR/bashrc.kit"
put_file "$HERE/tmux.conf" "$CONF_DIR/tmux.conf"
default_file() { # source destination state-key
  local src="$1" dst="$2" key="$3" state="$DATA_DIR/default-settings.sha256" old hash
  hash() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
  old="$(awk -v k="$key" '$1 == k {print $2}' "$state" 2>/dev/null || true)"
  if [ ! -e "$dst" ]; then cp "$src" "$dst"; old="$(hash "$dst")"
  elif [ -n "$old" ] && [ "$(hash "$dst")" = "$old" ]; then cp "$src" "$dst"; old="$(hash "$dst")"; log "refreshed $dst (kit default)"
  elif [ -n "$old" ]; then cp "$src" "$dst.kit-new"; log "kept your $dst; new kit default written to $dst.kit-new"; return
  else log "keeping pre-existing $dst (no kit default state)"; return; fi
  { awk -v k="$key" '$1 != k' "$state" 2>/dev/null || true; printf '%s %s\n' "$key" "$old"; } >"$state.new"; mv "$state.new" "$state"
}
default_file "$HERE/direnv.toml" "$DIRENV_DIR/direnv.toml" direnv.toml
local_default="$(mktemp)"; printf '# Your own shell additions. kit updates never touch this file.\n' >"$local_default"
default_file "$local_default" "$CONF_DIR/bashrc.local" bashrc.local; rm -f "$local_default"

# shellcheck disable=SC2016  # the line must reach ~/.bashrc unexpanded
put_block "$HOME/.bashrc" "terminal" '[ -f "$HOME/.config/work-kit/bashrc.kit" ] && . "$HOME/.config/work-kit/bashrc.kit"'
put_block "$HOME/.tmux.conf" "terminal" "source-file -q $CONF_DIR/tmux.conf"

# Project template and kit-new
rm -rf "$DATA_DIR/project-template.new"
cp -R "$HERE/project-template" "$DATA_DIR/project-template.new"
if [ -d "$DATA_DIR/project-template" ] && diff -rq "$DATA_DIR/project-template" "$DATA_DIR/project-template.new" >/dev/null 2>&1; then
  rm -rf "$DATA_DIR/project-template.new"
  log "project template up to date"
else
  [ -d "$DATA_DIR/project-template" ] && backup mv "$DATA_DIR/project-template"
  mv "$DATA_DIR/project-template.new" "$DATA_DIR/project-template"
  log "installed project template"
fi
put_file "$HERE/kit-new" "$BIN_DIR/kit-new"
chmod +x "$BIN_DIR/kit-new"

log "open a new shell to load it; start a prototype with: kit-new <name>"
