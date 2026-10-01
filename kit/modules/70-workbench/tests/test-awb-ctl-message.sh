#!/usr/bin/env bash
# The context guard and wb-pane-write look for the desktop app's awb-ctl. The app bundle
# (/Applications/Agent Workbench.app) exists on macOS only: on Linux it is neither tried nor
# named in the message about the missing awb-ctl (VM finding 2026-09-26). A fake uname stands in
# for the host, so both branches run on any machine. Own scratch HOME and tmux dir; the real tmux
# server is never reached.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CG="$HERE/payload/shell/context-guard"
WPW="$HERE/payload/shell/wb-pane-write"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/home" "$W/fake" "$W/tmux" "$W/bin"
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
for os in Linux Darwin; do
  printf '#!/bin/sh\nif [ "$1" = -s ]; then echo %s; else exec /usr/bin/uname "$@"; fi\n' "$os" > "$W/fake/uname-$os"
  mkdir -p "$W/fake-$os"; cp "$W/fake/uname-$os" "$W/fake-$os/uname"; chmod +x "$W/fake-$os/uname"
done
env_run() { # OS cmd...   fresh env: no tmux, scratch HOME, an empty bundle dir standing in for /Applications
  local os="$1"; shift
  ( cd "$W" && env -u TMUX -u TMUX_PANE -u AWB_CTL HOME="$W/home" TMUX_TMPDIR="$W/tmux" \
      PATH="$W/fake-$os:$PATH" WB_SESSION=x timeout 30 "$@" </dev/null 2>&1 )
}

out="$(env_run Linux bash "$CG" %999)"
check "context-guard on Linux: says awb-ctl is missing" 'grep -q "awb-ctl nirgends gefunden" <<<"$out"'
check "context-guard on Linux: no macOS app path in the message" '! grep -q "Applications" <<<"$out"'
out="$(env_run Darwin env WB_AWB_CTL_BUNDLE="$W/none/awb-ctl" bash "$CG" %999)"
check "context-guard on macOS: the app bundle is named" 'grep -q "Applications/Agent Workbench.app" <<<"$out"'

# the bundle candidate is skipped on Linux even when WB_AWB_CTL_BUNDLE is unset and the file exists at the macOS path
# (checked by the message only; the path itself cannot be created here)
grep -q '"${WB_AWB_CTL_BUNDLE:-$_awb_bundle}"' "$CG" && ! grep -q 'WB_AWB_CTL_BUNDLE:-/Applications' "$CG" \
  && ok "context-guard: macOS bundle path only set under uname = Darwin" || bad "context-guard: hard-coded bundle default"

out="$(env_run Linux bash "$WPW" darf pty:999)"
check "wb-pane-write on Linux, pty pane: no macOS app path in any message" '! grep -q "Applications" <<<"$out"'
grep -q '"${WB_AWB_CTL_BUNDLE:-$_wpw_bundle}"' "$WPW" && ! grep -q 'WB_AWB_CTL_BUNDLE:-/Applications' "$WPW" \
  && grep -q '\$HOME/.local/bin${_wpw_app}) -- Pane' "$WPW" \
  && ok "wb-pane-write: macOS bundle path and its mention only set under uname = Darwin" || bad "wb-pane-write: hard-coded bundle default or message"
! pgrep -f "$W" >/dev/null 2>&1 && ok "no process left" || bad "process of the test left"
[ "$fail" = 0 ] && echo "ALL PASSED"
exit "$fail"
