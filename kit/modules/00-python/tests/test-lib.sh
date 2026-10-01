#!/usr/bin/env bash
# lib.sh helpers in a scratch HOME: backups go under the data dir with the original path
# recorded, kit_uv runs with umask 022, kit_fix_lock_perms clears world-writable .lock files.
# shellcheck disable=SC2016  # check() evaluates its quoted condition later
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
export HOME="$W/home" KIT_BIN_DIR="$W/home/.local/bin" KIT_DATA_DIR="$W/home/.local/share/work-kit"
mkdir -p "$KIT_BIN_DIR"
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

# shellcheck source=../lib.sh
. "$HERE/../lib.sh"

# --- kit_backup --------------------------------------------------------------------------
echo mine >"$HOME/.bashrc"
kit_backup "$HOME/.bashrc" 60-terminal >/dev/null
b="$(ls "$KIT_DATA_DIR"/backups/60-terminal/.bashrc.bak-* 2>/dev/null | grep -v '\.origin$' | head -n 1)"
check "backup lands under backups/<module>" '[ -f "$b" ] && [ "$(cat "$b")" = mine ]'
check "original moved away" '[ ! -e "$HOME/.bashrc" ]'
check "origin recorded" '[ "$(cat "$b.origin")" = "$HOME/.bashrc" ]'
check "no backup beside the original" '[ -z "$(ls -A "$HOME" | grep "\.bak-" || true)" ]'
echo again >"$HOME/.bashrc"
kit_backup "$HOME/.bashrc" 60-terminal >/dev/null
check "same-second backups do not collide" '[ "$(ls -A "$KIT_DATA_DIR"/backups/60-terminal | grep -c "^\.bashrc\.bak-[0-9-]*$")" = 2 ]'
kit_backup "$HOME/does-not-exist" x >/dev/null
check "missing file is a no-op" '[ ! -d "$KIT_DATA_DIR/backups/x" ]'
echo x >"$KIT_BIN_DIR/uv.txt"
kit_backup "$KIT_BIN_DIR/uv.txt" >/dev/null
check "default module is 00-python" 'ls "$KIT_DATA_DIR"/backups/00-python/uv.txt.bak-* >/dev/null 2>&1'

# --- kit_uv umask ------------------------------------------------------------------------
# fake uv: like the real one it makes its .lock file 0666 whatever the umask, and it can fail
printf '#!/bin/sh\numask >"$KIT_TEST_UMASK"\n: >"$KIT_TEST_LOCK"\nmkdir -p "$KIT_DATA_DIR/tools"\n: >"$KIT_DATA_DIR/tools/.lock"\nchmod 666 "$KIT_DATA_DIR/tools/.lock"\n[ -z "$KIT_TEST_FAIL" ] || exit 7\n' >"$KIT_BIN_DIR/uv"
chmod +x "$KIT_BIN_DIR/uv"
export KIT_TEST_UMASK="$W/umask" KIT_TEST_LOCK="$W/lock" KIT_TEST_FAIL=
( umask 000; kit_uv tool list )
check "kit_uv runs uv with umask 022" '[ "$(cat "$KIT_TEST_UMASK")" = 0022 ]'
check "uv's own 0666 .lock is fixed after the call" '[ "$(stat -c %a "$KIT_DATA_DIR/tools/.lock" 2>/dev/null || stat -f %Lp "$KIT_DATA_DIR/tools/.lock")" = 644 ]'
chmod 666 "$KIT_DATA_DIR/tools/.lock"
KIT_TEST_FAIL=1 kit_uv tool list; rc=$?
check "a failing uv keeps its exit code" '[ "$rc" = 7 ]'
check "lock fixed even when uv failed" '[ "$(stat -c %a "$KIT_DATA_DIR/tools/.lock" 2>/dev/null || stat -f %Lp "$KIT_DATA_DIR/tools/.lock")" = 644 ]'
check "file created by uv is not world-writable" '[ "$(stat -c %a "$KIT_TEST_LOCK" 2>/dev/null || stat -f %Lp "$KIT_TEST_LOCK")" = 644 ]'

# --- kit_fix_lock_perms ------------------------------------------------------------------
mkdir -p "$KIT_DATA_DIR/quassel/venv" "$KIT_DATA_DIR/tools/x"
: >"$KIT_DATA_DIR/quassel/venv/.lock"; chmod 666 "$KIT_DATA_DIR/quassel/venv/.lock"
: >"$KIT_DATA_DIR/tools/x/.lock"; chmod 664 "$KIT_DATA_DIR/tools/x/.lock"
: >"$KIT_DATA_DIR/tools/x/other"; chmod 666 "$KIT_DATA_DIR/tools/x/other"
kit_fix_lock_perms
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
check "0666 lock file fixed" '[ "$(mode "$KIT_DATA_DIR/quassel/venv/.lock")" = 644 ]'
check "0664 lock file fixed" '[ "$(mode "$KIT_DATA_DIR/tools/x/.lock")" = 644 ]'
check "other files untouched" '[ "$(mode "$KIT_DATA_DIR/tools/x/other")" = 666 ]'

echo "failures: $fails"
[ "$fails" = 0 ]
