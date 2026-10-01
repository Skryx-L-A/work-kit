#!/usr/bin/env bash
# Installer logic with fake archives (shell scripts in the real archive layout) in a scratch
# HOME. Runs on any host; it does not prove the real Linux binaries work.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

OFF="$W/offline/docs-tools/bin"
mkdir -p "$OFF" "$W/pk/d2-v0.9.0/bin" "$W/pk/pandoc-3.11/bin"
printf '#!/bin/sh\necho "v0.9.0 fake d2"\n' >"$W/pk/d2-v0.9.0/bin/d2"
printf '#!/bin/sh\necho "pandoc 3.11 fake"\n' >"$W/pk/pandoc-3.11/bin/pandoc"
chmod +x "$W/pk/d2-v0.9.0/bin/d2" "$W/pk/pandoc-3.11/bin/pandoc"
tar -czf "$OFF/d2-v0.9.0-linux-amd64.tar.gz" -C "$W/pk" d2-v0.9.0
tar -czf "$OFF/pandoc-3.11-linux-amd64.tar.gz" -C "$W/pk" pandoc-3.11

export HOME="$W/home"
export KIT_BIN_DIR="$W/home/.local/bin" KIT_DATA_DIR="$W/home/.local/share/work-kit"
export KIT_OFFLINE="$W/offline"
mkdir -p "$HOME"

bash "$MOD/install.sh" >/dev/null 2>&1 || bad "install exits 0"
for t in d2 pandoc; do check "installed $t" "[ -x '$KIT_BIN_DIR/$t' ]"; done
check "d2 is the kit d2" "\"$KIT_BIN_DIR/d2\" | grep -q 'fake d2'"

# shellcheck disable=SC2034  # read inside eval
out="$(bash "$MOD/install.sh" 2>&1)"
check "rerun says up to date" "grep -q 'up to date: $KIT_BIN_DIR/d2' <<<\"\$out\""
check "no backups after identical rerun" "[ -z \"\$(find '$W/home' -name '*.bak-*' || true)\" ]"

printf '#!/bin/sh\necho mine\n' >"$KIT_BIN_DIR/pandoc"
bash "$MOD/install.sh" pandoc >/dev/null 2>&1
BAKS="$KIT_DATA_DIR/backups/12-docs-tools"
check "own pandoc backed up under backups/" "ls '$BAKS' | grep -q '^pandoc.bak-'"
check "backup records the original path" "grep -qx '$KIT_BIN_DIR/pandoc' '$BAKS'/pandoc.bak-*.origin"
check "no backup beside the original" "! ls '$KIT_BIN_DIR' | grep -q 'bak-'"
check "kit pandoc installed" "\"$KIT_BIN_DIR/pandoc\" | grep -q 'pandoc 3.11 fake'"

if bash "$MOD/install.sh" nosuchtool >/dev/null 2>&1; then bad "unknown tool must fail"; else ok "unknown tool fails"; fi
if KIT_OFFLINE="$W/empty" bash "$MOD/install.sh" >/dev/null 2>&1; then bad "missing offline dir must fail"; else ok "missing offline dir fails"; fi
check "apt.sh --print points to 01-prereqs --sudo graphviz" "bash '$MOD/apt.sh' --print | grep -q '01-prereqs/install.sh --sudo graphviz'"

bash "$MOD/uninstall.sh" >/dev/null 2>&1
for t in d2 pandoc; do check "removed $t" "[ ! -e '$KIT_BIN_DIR/$t' ]"; done
check "backup kept" "ls '$BAKS' | grep -q '^pandoc.bak-'"
check "uninstall twice is harmless" "bash '$MOD/uninstall.sh' >/dev/null 2>&1"
exit "$fail"
