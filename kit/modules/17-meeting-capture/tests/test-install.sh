#!/usr/bin/env bash
# shellcheck disable=SC2015  # "A && ok || bad": ok and bad never fail
# Install/uninstall test for 17-meeting-capture in a throw-away HOME. No network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
unset XDG_CONFIG_HOME KIT_DATA_DIR KIT_BIN_DIR MEETING_WHISPER_URL MEETING_RECORD_CMD
export PATH="$HOME/.local/bin:$PATH"
CONF="$HOME/.config/work-kit"

fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

bash "$HERE/install.sh" >"$TMP/i1" 2>&1 && ok "install" || { bad "install"; cat "$TMP/i1"; }
[ -x "$HOME/.local/bin/meeting" ] && ok "meeting launcher installed" || bad "meeting not installed"
for f in meeting-ai-policy.md meeting.conf; do
  [ -f "$CONF/$f" ] && ok "config $f" || bad "config $f missing"
done
grep -q "80-quassel" "$TMP/i1" && ok "install reports the missing speech engine" || bad "engine check not reported"

echo "# my edit" >>"$CONF/meeting-ai-policy.md"
bash "$HERE/install.sh" >"$TMP/i2" 2>&1 && ok "second install" || bad "second install"
grep -q "# my edit" "$CONF/meeting-ai-policy.md" && ok "user edit kept" || bad "user edit lost"
[ -f "$CONF/meeting-ai-policy.md.kit-new" ] && ok "new version beside it" || bad "no .kit-new"

# a foreign launcher and a changed installed copy are backed up under the data dir, not beside them
BAK="$HOME/.local/share/work-kit/backups/17-meeting-capture"
printf '#!/bin/sh\necho mine\n' >"$HOME/.local/bin/meeting"
echo "# changed" >>"$HOME/.local/share/work-kit/meeting-capture/meeting"
bash "$HERE/install.sh" >"$TMP/i3" 2>&1 && ok "install over foreign files" || { bad "install over foreign files"; cat "$TMP/i3"; }
grep -q mine "$BAK"/meeting.bak-* 2>/dev/null && ok "foreign launcher backed up under backups/" || bad "launcher backup missing"
grep -qx "$HOME/.local/bin/meeting" "$BAK"/meeting.bak-*.origin 2>/dev/null && ok "backup records the original path" || bad "origin missing"
grep -q "# changed" "$BAK"/meeting.bak-* 2>/dev/null && ok "changed installed copy backed up" || bad "installed-copy backup missing"
[ -z "$(ls -A "$HOME/.local/bin" | grep 'bak-')" ] && [ -z "$(ls -A "$HOME/.local/share/work-kit/meeting-capture" | grep 'bak-')" ] && ok "no backup beside the originals" || bad "backup left beside an original"

meeting policy --todo >"$TMP/p" 2>&1 && grep -q "open question(s) for IT" "$TMP/p" && ok "policy --todo" || bad "policy --todo"
meeting status >"$TMP/s" 2>&1 && grep -q idle "$TMP/s" && ok "status idle" || bad "status"
meeting start </dev/null >"$TMP/c" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "CONSENT REMINDER" "$TMP/c" && ok "start without consent refused, reminder shown" || { bad "consent gate rc=$rc"; cat "$TMP/c"; }

bash "$HERE/uninstall.sh" >"$TMP/u" 2>&1 && ok "uninstall" || bad "uninstall"
[ ! -e "$HOME/.local/bin/meeting" ] && ok "launcher removed" || bad "launcher still there"
[ -f "$CONF/meeting-ai-policy.md" ] && ok "policy kept after uninstall" || bad "policy removed"
[ ! -e "$HOME/.local/share/work-kit/meeting-capture" ] && ok "data removed" || bad "data still there"

# No system python3: the kit CPython from uv's directory is used.
H2="$TMP/home2"
mkdir -p "$H2/.local/share/uv/python/cpython-3.12.0-test/bin" "$TMP/nopy"
ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$H2/.local/share/uv/python/cpython-3.12.0-test/bin/python3"
for t in bash sh env dirname basename cat cp mv rm ln mkdir mktemp chmod cmp date grep sed find sort head tail tr wc cut readlink uname touch test ls; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$TMP/nopy/$t"
done
HOME="$H2" PATH="$TMP/nopy" bash "$HERE/install.sh" >"$TMP/n1" 2>&1 && ok "install without system python3" || { bad "install without system python3"; cat "$TMP/n1"; }
HOME="$H2" PATH="$TMP/nopy" "$H2/.local/bin/meeting" status 2>/dev/null | grep -q idle \
  && ok "meeting runs on the kit CPython" || bad "meeting without system python3"
HOME="$TMP/home3" PATH="$TMP/nopy" bash "$HERE/install.sh" >"$TMP/n2" 2>&1 && bad "no python at all: refused" || ok "no python at all: refused"
grep -q "01-prereqs" "$TMP/n2" && ok "message names 01-prereqs" || bad "message lacks 01-prereqs"
HOME="$H2" PATH="$TMP/nopy" bash "$HERE/uninstall.sh" >"$TMP/n3" 2>&1
[ ! -e "$H2/.local/bin/meeting" ] && ok "launcher removed (kit CPython)" || bad "launcher still there"

exit "$fail"
