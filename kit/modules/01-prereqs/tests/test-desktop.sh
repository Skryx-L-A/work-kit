#!/usr/bin/env bash
# VS Code menu entry: uninstall.sh removes our code.desktop and the old work-kit-code.desktop,
# keeps a code.desktop that is not ours. Needs no offline tree. Usage: bash tests/test-desktop.sh
set -uo pipefail
MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
check() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS + 1)); echo "ok   $n"; else FAIL=$((FAIL + 1)); echo "FAIL $n"; fi; }
AP="$T/home/.local/share/applications"; D="$T/home/.local/share/work-kit"
run() { HOME="$T/home" KIT_DATA_DIR="$D" bash "$MOD/uninstall.sh" 2>&1; }

mkdir -p "$AP"
printf '[Desktop Entry]\nName=Visual Studio Code\n# work-kit:01-prereqs\n' >"$AP/code.desktop"
printf '[Desktop Entry]\nName=old\n' >"$AP/work-kit-code.desktop"
run >/dev/null
check "our code.desktop removed" test ! -e "$AP/code.desktop"
check "old work-kit-code.desktop removed" test ! -e "$AP/work-kit-code.desktop"

printf '[Desktop Entry]\nName=Visual Studio Code (system copy)\n' >"$AP/code.desktop"
run >/dev/null
check "foreign code.desktop kept" test -e "$AP/code.desktop"

echo "passed $PASS, failed $FAIL"
[ "$FAIL" = 0 ]
