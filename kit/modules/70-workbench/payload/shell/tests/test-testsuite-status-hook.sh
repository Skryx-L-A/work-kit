#!/bin/bash
# test-testsuite-status-hook.sh -- tests for
# ~/.claude/hooks/sessionstart-testsuite-status.sh (Aufgabe 2026-08-04:
# roter woechentlicher Testlauf soll bei Session-Start auffallen).
#
# ISOLATION: eigenes HOME per mktemp -d. Der Hook liest die Statusdatei ueber
# "$HOME/.local/state/wb-testsuite-status.txt" -- ueberschreiben von HOME
# reicht, um die echte Datei unter ~/.local/state/ nie anzufassen. Kein tmux,
# keine echte launchd-Job-Ausfuehrung noetig, der Hook selbst ist reines
# Datei-Lesen.
#
# Der Hook liegt bewusst NICHT im Repo (~/.claude/hooks/), deshalb der feste
# Pfad statt eines Repo-relativen. Existiert er nicht (frischer Rechner ohne
# diesen Hook installiert), meldet dieses Skript das als FAIL statt still zu
# uebergehen -- ein fehlender Hook ist ein echtes Problem fuer diesen Test.
#
# Run:  shell/tests/test-testsuite-status-hook.sh
set -uo pipefail

HOOK="$HOME/.claude/hooks/sessionstart-testsuite-status.sh"
PASS=0; FAIL=0

pass() { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

if [ ! -x "$HOOK" ]; then
  fail "Hook nicht gefunden oder nicht ausfuehrbar: $HOOK"
  echo "PASS: $PASS  FAIL: $FAIL"
  exit 1
fi

TESTHOME="$(mktemp -d "${TMPDIR:-/tmp}/wb-testsuite-hook-test.XXXXXX")"
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT

STATE_DIR="$TESTHOME/.local/state"
STATUS_FILE="$STATE_DIR/wb-testsuite-status.txt"
mkdir -p "$STATE_DIR"

run_hook() {
  HOME="$TESTHOME" "$HOOK"
}

write_status() {
  # $1=fail $2=ts_epoch $3=failed_suites $4=parse_ok
  {
    echo "# fixture"
    echo "ts_epoch=$2"
    echo "ts_iso=fixture"
    echo "parse_ok=${4:-1}"
    echo "exit_code=0"
    echo "pass=1"
    echo "fail=$1"
    echo "skip=0"
    echo "total=2"
    echo "failed_suites=$3"
  } > "$STATUS_FILE"
}

now=$(date +%s)
fresh=$((now - 86400))                 # 1 Tag her
overdue_ts=$((now - 10 * 86400))       # 10 Tage her -- ueber der 9-Tage-Grenze
boundary_ok_ts=$((now - 9 * 86400 + 3600))  # knapp unter 9 Tagen -- noch kein Alarm

# 1) fehlende Datei -> kein Fehler, keine Ausgabe
rm -f "$STATUS_FILE"
out=$(run_hook); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "fehlende Statusdatei: kein Fehler, keine Ausgabe"
else
  fail "fehlende Statusdatei: rc=$rc out='$out'"
fi

# 2) leere Datei -> kein Fehler, keine Ausgabe
: > "$STATUS_FILE"
out=$(run_hook); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "leere Statusdatei: kein Fehler, keine Ausgabe"
else
  fail "leere Statusdatei: rc=$rc out='$out'"
fi

# 3) kaputte Datei (nicht-numerische Werte) -> kein Fehler, keine Ausgabe
{
  echo "ts_epoch=nicht-eine-zahl"
  echo "fail=auch-keine-zahl"
} > "$STATUS_FILE"
out=$(run_hook); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "kaputte Statusdatei: kein Fehler, keine Ausgabe"
else
  fail "kaputte Statusdatei: rc=$rc out='$out'"
fi

# 4) gruen und frisch -> keine Ausgabe
write_status 0 "$fresh" ""
out=$(run_hook); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "gruen+frisch: keine Ausgabe"
else
  fail "gruen+frisch: rc=$rc out='$out'"
fi

# 4b) gruen und knapp unter der 9-Tage-Grenze -> immer noch keine Ausgabe
write_status 0 "$boundary_ok_ts" ""
out=$(run_hook); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "gruen, knapp unter 9 Tagen: keine Ausgabe"
else
  fail "gruen, knapp unter 9 Tagen: rc=$rc out='$out'"
fi

# 5) rot -> genau eine Zeile mit den Suite-Namen
write_status 2 "$fresh" "shell/tests/test-foo.sh,shell/tests/test-bar.sh"
out=$(run_hook); rc=$?
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] && printf '%s' "$out" | grep -q "test-foo.sh" && printf '%s' "$out" | grep -q "test-bar.sh"; then
  pass "rot: genau eine Zeile mit Suite-Namen"
else
  fail "rot: rc=$rc lines=$lines out='$out'"
fi

# 6) ueberfaellig (gruen, aber letzter Lauf > 9 Tage her) -> genau eine Zeile
write_status 0 "$overdue_ts" ""
out=$(run_hook); rc=$?
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] && printf '%s' "$out" | grep -qi "ueberfaellig"; then
  pass "ueberfaellig: genau eine Zeile"
else
  fail "ueberfaellig: rc=$rc lines=$lines out='$out'"
fi

# 7) rot UND ueberfaellig -> immer noch genau eine Zeile (keine Verdopplung)
write_status 1 "$overdue_ts" "shell/tests/test-foo.sh"
out=$(run_hook); rc=$?
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ]; then
  pass "rot+ueberfaellig: genau eine Zeile"
else
  fail "rot+ueberfaellig: rc=$rc lines=$lines out='$out'"
fi

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
