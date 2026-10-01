#!/usr/bin/env bash
# ok/bad never fail, so "A && ok || bad" is safe here.
# shellcheck disable=SC2015
# Checks install/uninstall of 18-doc-qa in a throwaway HOME. Needs `doc-qa` from 20-brain:
# either installed, or run from a 20-brain checkout with DOCQA_BIN pointing at a wrapper.
set -euo pipefail

MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }

export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" KIT_BIN_DIR="$TMP/home/.local/bin"
mkdir -p "$KIT_BIN_DIR"

# Without doc-qa the installer refuses.
if PATH="/usr/bin:/bin" bash "$MOD/install.sh" >/dev/null 2>&1; then bad "install without doc-qa"; else ok "install without doc-qa refused"; fi

if [ -n "${DOCQA_BIN:-}" ]; then ln -s "$DOCQA_BIN" "$KIT_BIN_DIR/doc-qa"; fi
command -v doc-qa >/dev/null 2>&1 || [ -x "$KIT_BIN_DIR/doc-qa" ] || { echo "no doc-qa available"; exit 1; }

out="$(bash "$MOD/install.sh")"
cfg="$XDG_CONFIG_HOME/work-kit/doc-qa.toml"
[ -f "$cfg" ] && grep -q '^enabled = false' "$cfg" && ok "config written, disabled" || bad "config"
echo "$out" | grep -q "disabled" && ok "status says disabled" || bad "status output"
echo "# my edit" >> "$cfg"
bash "$MOD/install.sh" >/dev/null
grep -q '# my edit' "$cfg" && ok "re-run keeps user config" || bad "config overwritten"
if "$KIT_BIN_DIR/doc-qa" ask "x" >/dev/null 2>&1; then bad "ask works while disabled"; else ok "ask refused while disabled"; fi

mkdir -p "$HOME/work/doc-qa/.brain"
bash "$MOD/uninstall.sh" >/dev/null
[ ! -d "$HOME/work/doc-qa/.brain" ] && [ -f "$cfg" ] && ok "uninstall removes index, keeps config" || bad "uninstall"
exit "$fail"
