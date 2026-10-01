#!/bin/bash
# test-hygiene-status-hook.sh -- tests for
# ~/.claude/hooks/sessionstart-hygiene-status.sh (Aufgabe 2026-08-04: roter
# oder ueberfaelliger woechentlicher Hygiene-Lauf soll bei Session-Start
# auffallen, genau wie beim Testsuite-Hook).
#
# ISOLATION: eigenes HOME per mktemp -d. Der Hook liest die Statusdatei ueber
# "$HOME/.local/state/wb-hygiene-status.txt" -- ueberschreiben von HOME
# reicht, um die echte Datei unter ~/.local/state/ nie anzufassen. Kein tmux,
# keine echte launchd-Job-Ausfuehrung noetig, der Hook selbst ist reines
# Datei-Lesen.
#
# Der Hook liegt bewusst NICHT im Repo (~/.claude/hooks/), deshalb der feste
# Pfad statt eines Repo-relativen. Existiert er nicht (frischer Rechner ohne
# diesen Hook installiert), meldet dieses Skript das als FAIL statt still zu
# uebergehen -- ein fehlender Hook ist ein echtes Problem fuer diesen Test.
# Bauart bewusst identisch zu shell/tests/test-testsuite-status-hook.sh.
#
# Run:  shell/tests/test-hygiene-status-hook.sh
set -uo pipefail

HOOK="$HOME/.claude/hooks/sessionstart-hygiene-status.sh"
PASS=0; FAIL=0

pass() { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

if [ ! -x "$HOOK" ]; then
  fail "Hook nicht gefunden oder nicht ausfuehrbar: $HOOK"
  echo "PASS: $PASS  FAIL: $FAIL"
  exit 1
fi

TESTHOME="$(mktemp -d "${TMPDIR:-/tmp}/wb-hygiene-hook-test.XXXXXX")"
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT

STATE_DIR="$TESTHOME/.local/state"
STATUS_FILE="$STATE_DIR/wb-hygiene-status.txt"
mkdir -p "$STATE_DIR"

run_hook() {
  HOME="$TESTHOME" "$HOOK"
}

write_status() {
  # $1=exit_code $2=ts_epoch $3=parse_ok $4=consistency $5=lint $6=freshness
  {
    echo "# fixture"
    echo "ts_epoch=$2"
    echo "ts_iso=fixture"
    echo "parse_ok=${3:-1}"
    echo "exit_code=$1"
    echo "consistency_count=${4:-}"
    echo "lint_undated_count=${5:-}"
    echo "freshness_stale_count=${6:-}"
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
  echo "exit_code=auch-keine-zahl"
} > "$STATUS_FILE"
out=$(run_hook); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "kaputte Statusdatei: kein Fehler, keine Ausgabe"
else
  fail "kaputte Statusdatei: rc=$rc out='$out'"
fi

# 4) gruen und frisch -> keine Ausgabe
write_status 0 "$fresh" 1 0 19 1
out=$(run_hook); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "gruen+frisch: keine Ausgabe"
else
  fail "gruen+frisch: rc=$rc out='$out'"
fi

# 4b) gruen und knapp unter der 9-Tage-Grenze -> immer noch keine Ausgabe
write_status 0 "$boundary_ok_ts" 1 0 19 1
out=$(run_hook); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "gruen, knapp unter 9 Tagen: keine Ausgabe"
else
  fail "gruen, knapp unter 9 Tagen: rc=$rc out='$out'"
fi

# 5) rot, parsbar -> genau eine Zeile mit den drei Zahlen
write_status 1 "$fresh" 1 4 19 2
out=$(run_hook); rc=$?
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] && printf '%s' "$out" | grep -q "Widersprueche: 4" \
   && printf '%s' "$out" | grep -q "undatierte Regeln: 19" && printf '%s' "$out" | grep -q "veraltete STATUS.md: 2"; then
  pass "rot, parsbar: genau eine Zeile mit den drei Zahlen"
else
  fail "rot, parsbar: rc=$rc lines=$lines out='$out'"
fi

# 5b) rot, aber Gegenprobe fehlgeschlagen (parse_ok=0) -> genau eine Zeile ohne erfundene Zahlen
write_status 1 "$fresh" 0
out=$(run_hook); rc=$?
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] && printf '%s' "$out" | grep -qi "nicht parsbar"; then
  pass "rot, unparsbar: genau eine Zeile, keine erfundenen Zahlen"
else
  fail "rot, unparsbar: rc=$rc lines=$lines out='$out'"
fi

# 6) ueberfaellig (gruen, aber letzter Lauf > 9 Tage her) -> genau eine Zeile
write_status 0 "$overdue_ts" 1 0 1 0
out=$(run_hook); rc=$?
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] && printf '%s' "$out" | grep -qi "ueberfaellig"; then
  pass "ueberfaellig: genau eine Zeile"
else
  fail "ueberfaellig: rc=$rc lines=$lines out='$out'"
fi

# 7) rot UND ueberfaellig -> immer noch genau eine Zeile (keine Verdopplung)
write_status 1 "$overdue_ts" 1 4 19 2
out=$(run_hook); rc=$?
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ]; then
  pass "rot+ueberfaellig: genau eine Zeile"
else
  fail "rot+ueberfaellig: rc=$rc lines=$lines out='$out'"
fi

# 8) rot, aber Einzelzahl fehlt (Werkzeug "nicht gefunden" -> leeres Feld trotz parse_ok=1)
# -> keine Ausgabe wird durch das leere Feld ausgeloest oder verschluckt
write_status 1 "$fresh" 1 4 "" 2
out=$(run_hook); rc=$?
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] && printf '%s' "$out" | grep -q "Widersprueche: 4"; then
  pass "rot, eine Zahl leer: genau eine Zeile, stuerzt nicht ab"
else
  fail "rot, eine Zahl leer: rc=$rc lines=$lines out='$out'"
fi

# Ab hier: Tests fuer das Feld rot_gruende (2026-09-04). Anlass: wb-hygiene
# setzt findings=1 an drei Stellen (Groessengrenze, wb-consistency, Speicher-
# Ampel ROT), die Statusdatei nannte aber keine davon namentlich -- gemessen
# am 04.09. war exit_code=1 ausschliesslich wegen Speicher-Ampel ROT bei
# 4,47 GiB, die rote Zeile sprach trotzdem nur von Widersprueche/Regeln/
# STATUS.md. write_status_v2 schreibt eine Statusdatei mit den zusaetzlichen
# Feldern speicher_ampel/speicher_gesamt/rot_gruende.
write_status_v2() {
  # $1=exit_code $2=ts_epoch $3=parse_ok $4=consistency $5=lint $6=freshness
  # $7=speicher_ampel $8=speicher_gesamt $9=rot_gruende
  {
    echo "# fixture v2"
    echo "ts_epoch=$2"
    echo "ts_iso=fixture"
    echo "parse_ok=${3:-1}"
    echo "exit_code=$1"
    echo "consistency_count=${4:-}"
    echo "lint_undated_count=${5:-}"
    echo "freshness_stale_count=${6:-}"
    echo "speicher_ampel=${7:-}"
    echo "speicher_gesamt=${8:-}"
    echo "rot_gruende=${9:-}"
  } > "$STATUS_FILE"
}

# 9) rot NUR wegen Speicher (Groesse und Widersprueche beide unauffaellig) ->
# die Zeile muss "Speicher" UND die gemessene Groesse nennen, genau der Fall
# vom 04.09., der bis jetzt unsichtbar blieb.
write_status_v2 1 "$fresh" 1 0 0 0 ROT "4.47 GiB" speicher
out=$(run_hook); rc=$?
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] && printf '%s' "$out" | grep -q "Speicher" \
   && printf '%s' "$out" | grep -q "4.47 GiB"; then
  pass "rot nur wegen Speicher: Wort Speicher und Groesse stehen in der Zeile"
else
  fail "rot nur wegen Speicher: rc=$rc lines=$lines out='$out'"
fi

# 10) alte Statusdatei ganz ohne rot_gruende (so, wie wb-hygiene sie vor
# dieser Aenderung schrieb) -> der Hook faellt auf die bisherige
# Zaehlwert-Zeile zurueck, statt zu schweigen oder abzustuerzen.
write_status 1 "$fresh" 1 4 19 2
out=$(run_hook); rc=$?
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] && printf '%s' "$out" | grep -q "rot"; then
  pass "alte Statusdatei ohne rot_gruende: genau eine sinnvolle Zeile"
else
  fail "alte Statusdatei ohne rot_gruende: rc=$rc lines=$lines out='$out'"
fi

# 11) rot aus ZWEI Gruenden gleichzeitig (Widersprueche UND Speicher) -> die
# Zeile muss BEIDE nennen. Der alte Hook kennt "Speicher" gar nicht -- er
# haette hier nur die drei Zaehlwerte gezeigt und den Speicher-Grund
# unterschlagen, obwohl er mitentschieden hat. Staerkster Beleg dafuer, dass
# rot_gruende nicht nur den Einzelfall (Test 9), sondern auch den Mischfall
# richtig behandelt.
write_status_v2 1 "$fresh" 1 3 0 0 ROT "5.10 GiB" "consistency,speicher"
out=$(run_hook); rc=$?
lines=$(printf '%s\n' "$out" | grep -c .)
if [ "$rc" -eq 0 ] && [ "$lines" -eq 1 ] && printf '%s' "$out" | grep -q "Widersprueche: 3" \
   && printf '%s' "$out" | grep -q "Speicher" && printf '%s' "$out" | grep -q "5.10 GiB"; then
  pass "rot aus zwei Gruenden: beide stehen in der einen Zeile"
else
  fail "rot aus zwei Gruenden: rc=$rc lines=$lines out='$out'"
fi

# 11b) gruen, aber im neuen Format (rot_gruende-Feld vorhanden und leer) ->
# weiterhin keine Ausgabe. Regression: ein leeres Feld darf keine Phantom-
# Zeile ("rot -- ") ausloesen. (Gegenprobe fuer diesen Fall: strukturell
# unmoeglich rot zu kriegen -- alt UND neu schweigen hier identisch, siehe
# Ergebnisdatei.)
write_status_v2 0 "$fresh" 1 0 0 0 GRUEN "1.00 GiB" ""
out=$(run_hook); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  pass "gruen im neuen Format mit leerem rot_gruende: keine Ausgabe"
else
  fail "gruen im neuen Format mit leerem rot_gruende: rc=$rc out='$out'"
fi

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
