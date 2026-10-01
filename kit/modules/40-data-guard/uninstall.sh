#!/usr/bin/env bash
# Remove data-guard: hooks it installed, the global opt-in, the CLI. Your policy, deny-list
# and the list of registered repositories (hooked-repos.list) in ~/.config/work-kit/ stay
# (delete them by hand if you want); install.sh puts the hooks back for the listed repositories.
set -euo pipefail

BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/data-guard"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/work-kit"

if [ -x "$DATA_DIR/data-guard" ]; then
  "$DATA_DIR/data-guard" disable-global || true
  if [ -f "$CONF_DIR/hooked-repos.list" ]; then
    # remove-hook also drops each repository from the list; keep the list itself
    keep="$(mktemp)"
    cp "$CONF_DIR/hooked-repos.list" "$keep"
    while IFS= read -r repo; do
      [ -d "$repo" ] && "$DATA_DIR/data-guard" remove-hook "$repo" || true
    done <"$keep"
    cat "$keep" >"$CONF_DIR/hooked-repos.list"
    rm -f "$keep"
  fi
fi
rm -rf "$CONF_DIR/git-hooks"
[ -L "$BIN_DIR/data-guard" ] && rm -f "$BIN_DIR/data-guard"
rm -rf "$DATA_DIR"
echo "[data-guard] removed (policy, deny-list and hooked-repos.list kept in $CONF_DIR)"
