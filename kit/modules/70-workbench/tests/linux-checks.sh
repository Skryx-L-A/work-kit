#!/usr/bin/env bash
# Linux-only checks of an installed workbench (docs/workbench-port.md, "Linux-only items"):
# human measurement (/proc), detached processes and orphans, memory probes, context guard
# lifecycle, status line (jq, GNU date) and the optional systemd user units.
#
#   bash tests/linux-checks.sh      (run as the user whose $HOME has the workbench)
#
# Uses a private tmux socket; every process it starts is stopped before it exits.
# Exit 0 = all checks passed, 77 = not Linux.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "$(uname -s)" = Linux ] || { echo "SKIP: not Linux"; exit 77; }
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
note() { printf '        %s\n' "$*"; }
# shellcheck source=../../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
PY="$(kit_find_python)" || { echo "no python: $(kit_python_hint)"; exit 1; }

BIN="$HOME/.local/bin"
[ -x "$BIN/wb-code" ] || { echo "workbench not installed in $HOME"; exit 1; }
mkdir -p "$HOME/.cache"
T="$(mktemp -d "$HOME/.cache/wb-linux-checks.XXXXXX")"
SOCKET="wblc$$"
TMUX_REAL="$(command -v tmux)" || { echo "tmux missing"; exit 1; }
mkdir -p "$T/shim"
printf '#!/bin/sh\nexec "%s" -L "%s" "$@"\n' "$TMUX_REAL" "$SOCKET" > "$T/shim/tmux"
chmod +x "$T/shim/tmux"
export PATH="$T/shim:$BIN:$PATH"
unset TMUX TMUX_PANE
SLEEPER=""
cleanup() {
  "$BIN/context-guard" --stop --all >/dev/null 2>&1 || true
  [ -n "$SLEEPER" ] && kill "$SLEEPER" 2>/dev/null
  "$TMUX_REAL" -L "$SOCKET" kill-server 2>/dev/null
  rm -f "/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$T"
}
trap cleanup EXIT INT TERM
wait_for() {  # wait_for <seconds> <command...>: true once the command succeeds
  local d=$((SECONDS + $1)); shift
  while [ $SECONDS -lt $d ]; do "$@" && return 0; sleep 1; done
  return 1
}

echo "== wb-mensch (/proc, controlling terminal)"
b="$(setsid "$BIN/wb-mensch" beleg </dev/null 2>&1)"
case "$b" in agent*) ok "no terminal (setsid): agent" ;; *) bad "no terminal: '$b'" ;; esac
tmux -f /dev/null new-session -d -s lc-human -x 120 -y 30 bash --norc
tmux send-keys -t lc-human "\"$BIN/wb-mensch\" beleg > \"$T/mensch.txt\" 2>&1" Enter
if wait_for 15 test -s "$T/mensch.txt"; then
  ok "wb-mensch answers inside a tmux pane"; note "pane shell: $(head -1 "$T/mensch.txt")"
else
  bad "wb-mensch gave no answer inside a tmux pane"
fi
"$BIN/wb-mensch" ahnen >/dev/null 2>&1 && ok "wb-mensch ahnen reads the process ancestry" || bad "wb-mensch ahnen failed"

echo "== wb-nohup / wb-waisen (owner registry, /proc)"
# A stand-in local model server: wb-waisen only looks at known categories (llama-server is one).
mkdir -p "$T/fake"
printf '#!/bin/bash\nwhile :; do sleep 5; done\n' > "$T/fake/llama-server"; chmod +x "$T/fake/llama-server"
tmux new-session -d -s lc-owner -x 120 -y 30 bash --norc
tmux send-keys -t lc-owner "\"$BIN/wb-nohup\" lccheck$$ --log \"$T/nohup.log\" -- \"$T/fake/llama-server\" --port 0 > \"$T/nohup.out\" 2>&1; echo \$? > \"$T/nohup.rc\"" Enter
wait_for 20 test -s "$T/nohup.rc"
SLEEPER="$(pgrep -u "$(id -u)" -f "$T/fake/llama-server" | head -1)"
if [ "$(cat "$T/nohup.rc" 2>/dev/null)" = 0 ] && [ -n "$SLEEPER" ]; then
  ok "wb-nohup started a detached process (pid $SLEEPER)"
else
  bad "wb-nohup: rc=$(cat "$T/nohup.rc" 2>/dev/null) pid='$SLEEPER'"; sed 's/^/        /' "$T/nohup.out" 2>/dev/null | head -5
fi
if [ -n "$SLEEPER" ]; then
  timeout 120 "$BIN/wb-waisen" --lines --nur-waisen > "$T/w1.txt" 2>&1
  grep -q "^$SLEEPER|" "$T/w1.txt" && bad "owner pane alive, still called an orphan" || ok "owner pane alive: not an orphan"
  "$TMUX_REAL" -L "$SOCKET" kill-session -t lc-owner
  timeout 120 "$BIN/wb-waisen" --lines --nur-waisen > "$T/w2.txt" 2>&1
  if grep -q "^$SLEEPER|.*|waise|" "$T/w2.txt"; then ok "owner pane gone: reported as orphan"
  else bad "orphan not reported"; sed 's/^/        /' "$T/w2.txt" | head -5; fi
  kill "$SLEEPER" 2>/dev/null; SLEEPER=""
fi

echo "== memory probes"
if "$BIN/wb-speicher" --json > "$T/sp.json" 2>"$T/sp.err" && "$PY" -c 'import json,sys; json.load(open(sys.argv[1]))' "$T/sp.json"; then
  ok "wb-speicher --json: valid report"
else
  bad "wb-speicher --json failed"; head -5 "$T/sp.err" | sed 's/^/        /'
fi
"$BIN/wb-speicher" --pruefen >/dev/null 2>&1; rc=$?
[ "$rc" -le 2 ] && ok "wb-speicher --pruefen answers (exit $rc)" || bad "wb-speicher --pruefen exit $rc"
out="$("$BIN/wb-notbremse" pruefen 2>&1)"; rc=$?
[ "$rc" -le 1 ] && ok "wb-notbremse pruefen answers (exit $rc)" || { bad "wb-notbremse pruefen exit $rc"; printf '%s\n' "$out" | head -5 | sed 's/^/        /'; }
out="$("$BIN/wb-notbremse" status 2>&1)"; rc=$?
[ "$rc" -le 1 ] && ok "wb-notbremse status answers (exit $rc)" || { bad "wb-notbremse status exit $rc"; printf '%s\n' "$out" | head -5 | sed 's/^/        /'; }

echo "== status line (jq, GNU date)"
if command -v jq >/dev/null; then
  mkdir -p "$T/sl"
  line="$(printf '%s' '{"model":{"display_name":"Stand-in"},"workspace":{"current_dir":"/tmp"},"context_window":{"total_input_tokens":50000,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1700000000},"seven_day":{"used_percentage":3}}}' \
    | HOME="$T/sl" bash "$HOME/.claude/statusline-command.sh" 2>&1)"
  want="→$(date -d @1700000000 +%H:%M)"
  case "$line" in *"$want"*) ok "5 h reset time shown ($want)" ;; *) bad "status line without reset time: $line" ;; esac
  case "$line" in *"50k/200k"*) ok "context bar shown" ;; *) bad "no context bar: $line" ;; esac
  [ -s "$T/sl/.claude/workbench/limits-latest.json" ] && ok "limit snapshot written" || bad "no limit snapshot"
else
  bad "jq missing (kit module 10-base-tools): the status line shows model and folder only"
fi

echo "== context guard lifecycle"
tmux new-session -d -s wb-lc-guard -x 120 -y 30 bash --norc
PANE="$(tmux display-message -p -t wb-lc-guard '#{pane_id}')"
tmux set-option -p -t "$PANE" @wb_role orchestrator   # what wb-code sets on its pane
# POLL=10: the guard checks its stop file once per poll (60 s in normal use).
POLL=10 "$BIN/context-guard" --ensure "$PANE" > "$T/cg1.txt" 2>&1
guards() {  # guard processes, without the guard's own short-lived subshells
  ps -u "$(id -u)" -o pid=,ppid=,args= | awk '/context-guard .*--auto/ && !/awk/ {p[$1]=$2}
    END {n=0; for (k in p) if (!(p[k] in p)) n++; print n}'
}
has_guard() { [ "$(guards)" -ge 1 ]; }
no_guard()  { [ "$(guards)" = 0 ]; }
if wait_for 15 has_guard; then ok "context-guard --ensure started a guard"; else bad "no guard running"; sed 's/^/        /' "$T/cg1.txt" | head -5; fi
POLL=10 "$BIN/context-guard" --ensure "$PANE" > "$T/cg2.txt" 2>&1
sleep 2
[ "$(guards)" = 1 ] && ok "second --ensure starts no duplicate" || bad "$(guards) guards after a second --ensure"
# A stop request that arrives while the guard is still starting is lost (it clears old stop
# files during its start-up); wait for its first heartbeat, i.e. its first poll.
heartbeat() { ls "$HOME/.local/state/wb-context-guard/"*"$SOCKET"*.heartbeat >/dev/null 2>&1; }
wait_for 60 heartbeat || note "no heartbeat within 60 s"
"$BIN/context-guard" --stop --all > "$T/cg3.txt" 2>&1
if wait_for 90 no_guard; then ok "context-guard --stop --all: guard ended"
else
  bad "guard still running 90 s after --stop"
  hb="$(ls -t "$HOME/.local/state/wb-context-guard/"*"$SOCKET"*.heartbeat 2>/dev/null | head -1)"
  [ -n "$hb" ] && note "last heartbeat $(( $(date +%s) - $(cat "$hb") )) s ago"
  tail -3 "$(ls -t "$HOME/.local/state/"context-guard-*"$SOCKET"*.log 2>/dev/null | head -1)" 2>/dev/null | sed 's/^/        /'
fi

echo "== systemd user units (optional, not enabled by the installer)"
if command -v systemd-analyze >/dev/null; then
  U="$T/units"; mkdir -p "$U"
  cp "$HERE/payload/shell/systemd/"*.service "$HERE/payload/shell/systemd/"*.timer "$U/"
  if out="$(cd "$U" && systemd-analyze --user verify ./*.service ./*.timer 2>&1)"; then
    ok "systemd-analyze --user verify: units parse"
  elif printf '%s' "$out" | grep -qi 'bus\|connect\|XDG_RUNTIME_DIR\|RuntimeDirectory\|No such device'; then
    note "no user systemd manager in this session: $(printf '%s' "$out" | head -1)"
    if out="$(cd "$U" && systemd-analyze verify ./*.service ./*.timer 2>&1)"; then ok "systemd-analyze verify: units parse"
    else bad "systemd-analyze verify"; printf '%s\n' "$out" | head -6 | sed 's/^/        /'; fi
  else
    bad "systemd-analyze --user verify"; printf '%s\n' "$out" | head -6 | sed 's/^/        /'
  fi
else
  note "systemd-analyze not found: units not checked"
fi

echo
echo "linux-checks: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
