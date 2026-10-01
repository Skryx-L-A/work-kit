#!/usr/bin/env bash
# verify.sh must never hang (VM finding 2026-09-26: it stopped for good after the snapshot check).
# Covers, without installing anything and without tmux:
#   1. wbt (the time limit around every external step): stops a hanging command with exit 124,
#      passes exit codes and stdin through, with timeout(1) and with the shell fallback
#   2. the watchdog: a run in which every python call hangs ends with a FAIL naming the step,
#      exit 1, within seconds, and leaves no process behind
#   3. a step limit turns one hanging step into a FAIL and the run goes on
# Own scratch HOME; nothing of the real HOME is used.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$(mktemp -d)"
trap 'pkill -f "$W/fakebin" 2>/dev/null; rm -rf "$W"' EXIT
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# --- 1. wbt --------------------------------------------------------------------------------------
# The helper block of verify.sh, taken from the script itself (between its two marker comments).
sed -n '/^# wbt SECONDS CMD/,/^# section TITLE/p' "$HERE/verify.sh" | sed '$d' > "$W/wbt.sh"
[ -s "$W/wbt.sh" ] || { bad "wbt helper not found in verify.sh"; exit 1; }
for mode in timeout fallback; do
  run() { # body of a fresh bash that has wbt
    if [ "$mode" = fallback ]; then WB_VERIFY_NO_TIMEOUT_BIN=1 bash -c ". '$W/wbt.sh'; $1" </dev/null
    else bash -c ". '$W/wbt.sh'; $1" </dev/null; fi
  }
  t0=$SECONDS; run 'wbt 2 sleep 30'; rc=$?; dt=$((SECONDS - t0))
  check "wbt ($mode): a hanging command is stopped (exit 124, ${dt}s)" '[ "$rc" = 124 ] && [ "$dt" -le 10 ]'
  run 'wbt 5 sh -c "exit 7"'; rc=$?
  check "wbt ($mode): exit code of a finished command is kept" '[ "$rc" = 7 ]'
  out="$(printf 'piped\n' | { if [ "$mode" = fallback ]; then WB_VERIFY_NO_TIMEOUT_BIN=1 bash -c ". '$W/wbt.sh'; wbt 5 cat"; else bash -c ". '$W/wbt.sh'; wbt 5 cat"; fi; })"
  check "wbt ($mode): stdin reaches the command" '[ "$out" = piped ]'
  # a child of the command that would keep sleeping is stopped with it
  t0=$SECONDS; run 'wbt 2 sh -c "sleep 30 & wait"'; rc=$?; dt=$((SECONDS - t0))
  check "wbt ($mode): command with a child ends in time (${dt}s)" '[ "$rc" = 124 ] && [ "$dt" -le 10 ]'
done

# --- 2. watchdog: every python call hangs -----------------------------------------------------------
mkdir -p "$W/fakebin" "$W/home"
cat > "$W/fakebin/python3" <<EOF
#!/bin/sh
# passes the version probe of kit_find_python, hangs on everything else
case "\$*" in *version_info*) exit 0 ;; esac
exec sleep 300
EOF
chmod +x "$W/fakebin/python3"
t0=$SECONDS
out="$(HOME="$W/home" PATH="$W/fakebin:$PATH" WB_VERIFY_MAX_SECS=6 WB_VERIFY_STEP_SECS=300 \
        bash "$HERE/verify.sh" 2>&1)"; rc=$?
dt=$((SECONDS - t0))
check "watchdog: run with hanging python ends within 30 s (${dt}s)" '[ "$dt" -le 30 ]'
check "watchdog: exit 1" '[ "$rc" = 1 ]'
check "watchdog: FAIL names the limit and the step" 'grep -q "FAIL  verify.sh ran longer than 6 s and was stopped (step: installed files)" <<<"$out"'
check "watchdog: summary line printed" 'grep -q "^verify: .* passed, [1-9][0-9]* failed" <<<"$out"'
sleep 1
left="$(pgrep -fl "$W/fakebin|sleep 300" 2>/dev/null)"; check "watchdog: no process of the run is left" '[ -z "$left" ]'; [ -z "$left" ] || echo "$left"

# --- 3. step limit: a hanging step is a FAIL and the run continues -----------------------------------
t0=$SECONDS
out="$(HOME="$W/home" PATH="$W/fakebin:$PATH" WB_VERIFY_MAX_SECS=120 WB_VERIFY_STEP_SECS=2 \
        bash "$HERE/verify.sh" 2>&1)"; rc=$?
dt=$((SECONDS - t0))
check "step limit: run ends by itself (${dt}s), exit 1" '[ "$rc" = 1 ] && [ "$dt" -le 110 ]'
check "step limit: reaches a later section after the hanging python calls" 'grep -q "^== kit fixes" <<<"$out"'
check "step limit: reports the summary" 'grep -q "^verify: " <<<"$out"'

[ "$fail" = 0 ] && echo "ALL PASSED"
exit "$fail"
