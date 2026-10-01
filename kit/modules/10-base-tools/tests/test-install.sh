#!/usr/bin/env bash
# Installer in a scratch HOME with fake binaries: install, idempotency, backup of a foreign file
# under the data dir, uninstall. Runs on any host.
# shellcheck disable=SC2016  # check() evaluates its quoted condition later
set -uo pipefail
MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
export HOME="$W/home" KIT_BIN_DIR="$W/home/.local/bin" KIT_DATA_DIR="$W/home/.local/share/work-kit"
export KIT_OFFLINE="$W/offline"
mkdir -p "$HOME" "$KIT_OFFLINE/bin"
printf '#!/bin/sh\necho "rg fake"\n' >"$KIT_OFFLINE/bin/rg"
printf '#!/bin/sh\necho "jq fake"\n' >"$KIT_OFFLINE/bin/jq"
chmod +x "$KIT_OFFLINE/bin/"*
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

bash "$MOD/install.sh" >/dev/null 2>&1
check "tools installed" '[ -x "$KIT_BIN_DIR/rg" ] && [ -x "$KIT_BIN_DIR/jq" ]'
out="$(bash "$MOD/install.sh" 2>&1)"
check "rerun is up to date" 'grep -q "rg up to date" <<<"$out"'
check "no backups after an identical rerun" '[ -z "$(find "$HOME" -name "*.bak-*")" ]'

echo mine >"$KIT_BIN_DIR/rg"
bash "$MOD/install.sh" rg >/dev/null 2>&1
BAKS="$KIT_DATA_DIR/backups/10-base-tools"
check "foreign file backed up under backups/" 'grep -q mine "$BAKS"/rg.bak-*'
check "backup records the original path" 'grep -qx "$KIT_BIN_DIR/rg" "$BAKS"/rg.bak-*.origin'
check "no backup beside the original" '! ls "$KIT_BIN_DIR" | grep -q "bak-"'
check "kit binary restored" '"$KIT_BIN_DIR/rg" | grep -q "rg fake"'

bash "$MOD/uninstall.sh" >/dev/null 2>&1
check "tools removed" '[ ! -e "$KIT_BIN_DIR/rg" ] && [ ! -e "$KIT_BIN_DIR/jq" ]'
check "backup kept" 'ls "$BAKS" | grep -q "^rg.bak-"'
echo "failures: $fails"
[ "$fails" = 0 ]
