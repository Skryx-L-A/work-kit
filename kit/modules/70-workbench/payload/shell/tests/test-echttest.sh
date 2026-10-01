#!/usr/bin/env bash
# test-echttest.sh -- die Zusagen von shell/wb-echttest gegen Attrappen, OHNE
# ein echtes Modell zu laden und OHNE tmux anzufassen (wb-echttest selbst
# schreibt nie in einen Pane; es ruft nur pi-worker/wb-close/wb-result/
# wb-belegung/check-resources auf, und genau die werden hier durch Attrappen
# ersetzt).
#
# DIE ZUSAGEN, die hier gemessen werden -- eine je Punkt aus dem Auftrag:
#   1  Jede Aufgabe erzeugt eine Datei, deren Inhalt das Werkzeug SELBST
#      nachrechnet -- ein Worker, der "fertig" meldet, aber eine falsche Zahl
#      schreibt, faellt als FEHLGESCHLAGEN auf statt als Erfolg durchzugehen.
#   2  Vor und nach jedem Spawn stehen "gebucht" (wb-belegungs summe_gib) und
#      "wirklich frei" (check-resources) NEBENEINANDER im Protokoll.
#   3  Jeder Worker bekommt eine gemessene Antwortzeit im Protokoll.
#   4  Am Ende ist aufgeraeumt: alle Buchungen zurueck auf die Baseline, das
#      Werkzeug selbst verifiziert das (nicht nur behauptet es).
#   5  Ein Abbruch mitten im Lauf schliesst die schon gespawnten Worker,
#      gibt ihre Buchungen zurueck und startet keine weiteren.
#
# ISOLATION: eigenes HOME (mktemp -d) mit Attrappen unter .local/bin fuer
# pi-worker, wb-close, wb-result, wb-belegung, check-resources -- kein echter
# Modellserver, kein echter tmux-Pane, keine echte Belegung. Kein Socket noetig:
# wb-echttest ruft tmux nirgends selbst auf.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$REPO/wb-echttest"
echo "Geprueft: $TOOL"
[ -x "$TOOL" ] || { echo "FEHLER: $TOOL fehlt oder ist nicht ausfuehrbar." >&2; exit 1; }

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"

FAKEHOME="$(mktemp -d)"
mkdir -p "$FAKEHOME/.local/bin" "$FAKEHOME/.local/state/fake-belegung" "$FAKEHOME/.wr-done"
cleanup() { rm -rf "$FAKEHOME"; }
trap cleanup EXIT

STATE="$FAKEHOME/.local/state/fake-belegung"
DONE="$FAKEHOME/.wr-done"

# --- Attrappe wb-belegung: 'wer --json' zaehlt offene Buchungen im STATE-Ordner
cat > "$FAKEHOME/.local/bin/wb-belegung" <<EOF
#!/bin/sh
n=\$(ls "$STATE" 2>/dev/null | wc -l | tr -d ' ')
sum=\$(awk -v n="\$n" 'BEGIN{printf "%.3f", n*2.5}')
echo "{\"summe_gib\": \$sum}"
EOF

# --- Attrappe check-resources: freier Speicher sinkt mit jeder offenen Buchung
cat > "$FAKEHOME/.local/bin/check-resources" <<EOF
#!/bin/sh
n=\$(ls "$STATE" 2>/dev/null | wc -l | tr -d ' ')
frei=\$(( 40000 - n*3000 ))
echo "{\"ram\": {\"free_mib\": \$frei, \"total_mib\": 49152}}"
EOF

# --- Attrappe wb-close: gibt die Buchung des Namens zurueck
cat > "$FAKEHOME/.local/bin/wb-close" <<EOF
#!/bin/sh
rm -f "$STATE/\$1"
exit 0
EOF

# --- Attrappe wb-result: 'fertig' nur, wenn ein Marker unter .wr-done liegt
cat > "$FAKEHOME/.local/bin/wb-result" <<EOF
#!/bin/sh
[ -e "$DONE/\$1" ] && exit 0
exit 1
EOF

# --- Attrappe pi-worker: bucht, schreibt die Ergebnisdatei nach echter Formel
# n*7+n*13 und Dateizahl im Eingabeverzeichnis -- ausser Umgebungsvariablen
# schalten ein bestimmtes n auf ein Fehlverhalten:
#   FAKE_ECHTTEST_REJECT_N=n   -- Buchung "abgelehnt": Exit 1, nichts gebucht
#   FAKE_ECHTTEST_BAD_N=n      -- meldet fertig, schreibt aber die FALSCHE Zahl
#   FAKE_ECHTTEST_TIMEOUT_N=n  -- bucht, meldet sich aber nie fertig
cat > "$FAKEHOME/.local/bin/pi-worker" <<EOF
#!/bin/sh
NAME="\$1"; WORKDIR="\$3"; shift 3
n="\${NAME##*-}"
if [ "\$n" = "\${FAKE_ECHTTEST_REJECT_N:-}" ]; then exit 1; fi
: > "$STATE/\$NAME"
if [ "\$n" = "\${FAKE_ECHTTEST_TIMEOUT_N:-}" ]; then exit 0; fi
count=\$(ls "\$WORKDIR/eingabe" 2>/dev/null | wc -l | tr -d ' ')
if [ "\$n" = "\${FAKE_ECHTTEST_BAD_N:-}" ]; then
  printf '%s\n%s\n' "999999" "\$count" > "\$WORKDIR/ergebnis-\$n.txt"
else
  erg=\$((n * 7 + n * 13))
  printf '%s\n%s\n' "\$erg" "\$count" > "\$WORKDIR/ergebnis-\$n.txt"
fi
: > "$DONE/\$NAME"
exit 0
EOF

chmod +x "$FAKEHOME/.local/bin/"*

lauf() {   # <arbeitsverzeichnis> <anzahl> [weitere args...]
  local arbeit="$1" anzahl="$2"; shift 2
  HOME="$FAKEHOME" "$TOOL" "$arbeit" fakemodell "$anzahl" "$@"
}

# === Test 1: Erfolgslauf, drei Worker ========================================
W1="$(mktemp -d)"
out1="$(lauf "$W1" 3 2>&1)"; rc1=$?
[ "$rc1" -eq 0 ] && ok "Erfolgslauf: Exit 0" || bad "Erfolgslauf: Exit $rc1" "$out1"
[ -s "$W1/ergebnis-1.txt" ] && [ -s "$W1/ergebnis-2.txt" ] && [ -s "$W1/ergebnis-3.txt" ] \
  && ok "Erfolgslauf: alle drei Ergebnisdateien da" \
  || bad "Erfolgslauf: Ergebnisdatei(en) fehlen"
printf '%s' "$out1" | grep -q ': ok (' \
  && ok "Erfolgslauf: Protokoll-Zusammenfassung meldet 'ok'" \
  || bad "Erfolgslauf: keine 'ok'-Zeile in der Zusammenfassung" "$out1"
[ -f "$W1/echttest-protokoll.tsv" ] || bad "Erfolgslauf: Protokolldatei fehlt"
zeilen=$(wc -l < "$W1/echttest-protokoll.tsv" | tr -d ' ')
[ "$zeilen" -eq 6 ] && ok "Erfolgslauf: Protokoll hat Kopf + start + 3 Spawns + ende (6 Zeilen)" \
  || bad "Erfolgslauf: Protokoll hat $zeilen Zeilen, erwartet 6" "$(cat "$W1/echttest-protokoll.tsv")"
# Buchung/frei stehen nebeneinander in derselben Zeile:
awk -F'\t' '$2=="spawn"{print; exit}' "$W1/echttest-protokoll.tsv" | grep -qE $'\t[0-9]+\\.[0-9]+\t[0-9]+\\.[0-9]+\t[0-9]+\\.[0-9]+\t[0-9]+\\.[0-9]+\t' \
  && ok "Erfolgslauf: gebucht_vor/frei_vor/gebucht_nach/frei_nach sind Zahlen, nebeneinander" \
  || bad "Erfolgslauf: Buchungs-/Freispalten sehen falsch aus" "$(grep spawn "$W1/echttest-protokoll.tsv")"
[ "$(ls "$STATE" 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ] \
  && ok "Erfolgslauf: keine offene Buchung uebrig (Endzustand belegt)" \
  || bad "Erfolgslauf: noch offene Buchung(en): $(ls "$STATE")"
rm -rf "$W1"; rm -f "$DONE"/*

# === Test 2: kaputter Worker (schreibt falsche Zahl) faellt auf ============
W2="$(mktemp -d)"
out2="$(FAKE_ECHTTEST_BAD_N=1 lauf "$W2" 1 2>&1)"; rc2=$?
[ "$rc2" -ne 0 ] && ok "Kaputter Worker: Exit != 0" || bad "Kaputter Worker: Exit 0, haette scheitern muessen"
printf '%s' "$out2" | grep -q 'FEHLGESCHLAGEN.*Zeile 1' \
  && ok "Kaputter Worker: Falschmeldung wird als FEHLGESCHLAGEN erkannt (nicht als 'fertig')" \
  || bad "Kaputter Worker: keine Zeile-1-Falschmeldung in der Ausgabe" "$out2"
rm -rf "$W2"; rm -f "$DONE"/*

# === Test 3: Buchung abgelehnt (Maschine voll) wird gemeldet, nicht verschluckt
W3="$(mktemp -d)"
out3="$(FAKE_ECHTTEST_REJECT_N=1 lauf "$W3" 1 2>&1)"; rc3=$?
[ "$rc3" -ne 0 ] && ok "Abgelehnte Buchung: Exit != 0" || bad "Abgelehnte Buchung: Exit 0, haette scheitern muessen"
printf '%s' "$out3" | grep -q 'pi-worker rc=' \
  && ok "Abgelehnte Buchung: pi-worker-Fehlschlag steht im Protokoll" \
  || bad "Abgelehnte Buchung: kein Hinweis auf den pi-worker-Fehlschlag" "$out3"
rm -rf "$W3"; rm -f "$DONE"/*

# === Test 4: Zeitlimit greift, und danach ist nichts mehr gebucht ==========
W4="$(mktemp -d)"
out4="$(FAKE_ECHTTEST_TIMEOUT_N=1 lauf "$W4" 1 --deadline-s 3 2>&1)"; rc4=$?
[ "$rc4" -ne 0 ] && ok "Zeitlimit: Exit != 0" || bad "Zeitlimit: Exit 0, haette scheitern muessen"
printf '%s' "$out4" | grep -q 'kein Ergebnis nach 3s' \
  && ok "Zeitlimit: Ausgabe nennt die abgelaufene Deadline" \
  || bad "Zeitlimit: keine Deadline-Meldung" "$out4"
[ "$(ls "$STATE" 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ] \
  && ok "Zeitlimit: haengender Worker wurde trotzdem geschlossen, Buchung zurueck" \
  || bad "Zeitlimit: Buchung des haengenden Workers blieb offen: $(ls "$STATE")"
rm -rf "$W4"; rm -f "$DONE"/*

# === Test 5: Abbruch mitten im Lauf raeumt auf und spawnt nicht weiter =====
W5="$(mktemp -d)"
FAKE_ECHTTEST_TIMEOUT_N=2 HOME="$FAKEHOME" "$TOOL" "$W5" fakemodell 4 --deadline-s 60 \
  >"$W5/lauf.log" 2>&1 &
PID=$!
warte_auf_datei "$DONE/echttest-$PID-1" 10 "Worker 1 des Abbruchtests meldet fertig" "$W5/lauf.log"
# Worker 2 haengt (Timeout-Attrappe): jetzt ist ein guter Moment fuer den Abbruch --
# Worker 1 ist fertig und geschlossen, 2 laeuft/haengt, 3 und 4 sind noch nicht dran.
warte_auf_bedingung 5 "Worker 2 des Abbruchtests hat gebucht" \
  "[ -e \"$STATE/echttest-$PID-2\" ]" "$W5/lauf.log"
kill -TERM "$PID" 2>/dev/null
warte_auf_bedingung 15 "Abbruchtest-Prozess ist beendet" \
  "! kill -0 $PID 2>/dev/null" "$W5/lauf.log"
wait "$PID" 2>/dev/null; rc5=$?
[ "$rc5" -eq 130 ] && ok "Abbruch: Exit 130 (SIGINT/SIGTERM-Konvention)" \
  || bad "Abbruch: Exit $rc5, erwartet 130" "$(cat "$W5/lauf.log")"
warte_auf_bedingung 15 "Abbruch: alle Buchungen sind nach dem Aufraeumen wieder frei" \
  "[ \"\$(ls \"$STATE\" 2>/dev/null | wc -l | tr -d ' ')\" -eq 0 ]" "$W5/lauf.log"
[ -e "$STATE/echttest-$PID-3" ] || [ -e "$STATE/echttest-$PID-4" ] \
  && bad "Abbruch: Worker 3 oder 4 wurden trotz Abbruch noch gespawnt" \
  || ok "Abbruch: nach dem Abbruch wurden keine weiteren Worker gespawnt"
grep -q 'Abbruch empfangen' "$W5/lauf.log" \
  && ok "Abbruch: Meldung an stderr, dass der Abbruch ankam" \
  || bad "Abbruch: keine Abbruchmeldung im Log" "$(cat "$W5/lauf.log")"
rm -rf "$W5"; rm -f "$DONE"/*

echo
echo "Ergebnis: $pass ok, $fail FAIL"
[ "$fail" -eq 0 ]
