#!/usr/bin/env bash
# test-wb-companion.sh -- der Companion-Client des Agents-Features
# (Bau-Schritt 3, Auftrag traeger3, docs/AGENTS-PLAN.md Anhang
# "Companion-Socket"). Prueft shell/wb-companion gegen einen echten
# Schirm-Daemon (shell/tests/stub-companion-daemon.py, ein Nachbau des
# Companion-Protokolls: hello, request/response nach
# ~/AI/companion/app/protocol/schema/*.json), nie gegen den echten Companion.
#
# ISOLATION: eigenes HOME (TESTHOME) mit einer eigenen tokens.json unter
# TESTHOME/companion/tokens.json (COMPANION_CONFIG_DIR zeigt dorthin, ueber
# --base an wb-companion); der Socket liegt daneben und wird IMMER ueber
# WB_COMPANION_SOCKET benannt -- kein Aufruf in dieser Suite laesst das
# Werkzeug seinen Vorgabe-Pfad selbst herleiten, damit niemals der echte
# Companion-Socket angefasst wird. Kein Netz, kein echter Daemon.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTHOME="$(mktemp -d "${TMPDIR:-/tmp}/wb-companion-test.XXXXXX")"
STEUER="$TESTHOME/steuer"
SOCK="$TESTHOME/companion.sock"
CFG="$TESTHOME/companion"
LOG="$STEUER/log.jsonl"
TOKEN="test-agent-token-$$"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

DAEMON_PID=""
cleanup() {
  [ -n "$DAEMON_PID" ] && { kill "$DAEMON_PID" 2>/dev/null || true; }
  case "$TESTHOME" in
    /tmp/wb-companion-*|/private/tmp/wb-companion-*|/var/folders/*/wb-companion-*) rm -rf "$TESTHOME" ;;
    *) echo "WARNUNG: '$TESTHOME' sieht nicht nach einem Testverzeichnis aus -- NICHT geloescht." >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

echo "== wb-companion (HOME $TESTHOME) =="
[ -x "$REPO/wb-companion" ] || { echo "UEBERSPRUNGEN: shell/wb-companion fehlt"; exit 77; }
command -v python3 >/dev/null || { echo "UEBERSPRUNGEN: python3 fehlt"; exit 77; }

mkdir -p "$CFG" "$STEUER"
printf '{"human":"nicht-benutzt","agent":"%s"}\n' "$TOKEN" > "$CFG/tokens.json"

wbc() {
  WB_COMPANION_SOCKET="$SOCK" COMPANION_CONFIG_DIR="$CFG" python3 "$REPO/wb-companion" "$@"
}

modus() { printf '%s' "$1" > "$STEUER/modus"; }
letzte_anfrage() { tail -1 "$LOG" 2>/dev/null; }
anfrage_n() { sed -n "${1}p" "$LOG" 2>/dev/null; }
feld() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2], {"d": d}))' "$1" "$2" 2>/dev/null; }
zeilen() { wc -l < "$LOG" 2>/dev/null | tr -d ' '; }

daemon_starten() {
  : > "$LOG"; rm -f "$STEUER/modus" "$STEUER/stop"
  python3 "$REPO/tests/stub-companion-daemon.py" "$SOCK" "$STEUER" "$TOKEN" &
  DAEMON_PID=$!
  local i=0
  while [ ! -S "$SOCK" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
  [ -S "$SOCK" ]
}
daemon_stoppen() {
  [ -n "$DAEMON_PID" ] && kill "$DAEMON_PID" 2>/dev/null
  wait "$DAEMON_PID" 2>/dev/null || true
  DAEMON_PID=""
  rm -f "$SOCK"
}

# ==========================================================================
echo; echo "-- A: status, modus ok --"
daemon_starten || { bad "A: Schirm-Daemon startet nicht"; }
modus ok
AUS="$(wbc status 20260910-auf-a --stand laeuft --grund gestartet --titel "Testziel A" --weckzeit 2099-01-01T00:00:00Z --maschine mac --json)"
RC=$?
[ "$RC" = 0 ] && ok "A: status Exit 0 bei modus ok" || bad "A: Exit" "rc=$RC"
echo "$AUS" | grep -q '"status": "ok"' && ok "A: --json zeigt status:ok" || bad "A: JSON-Ausgabe" "$AUS"
REQ="$(letzte_anfrage)"
[ "$(feld "$REQ" 'd["request"]')" = "report_status" ] && ok "A: Anfrage-Art report_status" || bad "A: request" "$REQ"
[ "$(feld "$REQ" 'd["status"]["id"]')" = "wb-traeger:20260910-auf-a" ] && ok "A: Sitzungskennung wb-traeger:<id>" || bad "A: id" "$REQ"
[ "$(feld "$REQ" 'd["status"]["auftrag_id"]')" = "20260910-auf-a" ] && ok "A: auftrag_id gesetzt" || bad "A: auftrag_id" "$REQ"
[ "$(feld "$REQ" 'd["status"]["state"]')" = "busy" ] && ok "A: 'laeuft' -> SessionState 'busy'" || bad "A: state" "$REQ"
[ "$(feld "$REQ" 'd["status"]["task_state"]')" = "laeuft" ] && ok "A: additives Feld task_state" || bad "A: task_state" "$REQ"
[ "$(feld "$REQ" 'd["status"]["task_reason"]')" = "gestartet" ] && ok "A: task_reason = --grund" || bad "A: task_reason" "$REQ"
[ "$(feld "$REQ" 'd["status"]["task_title"]')" = "Testziel A" ] && ok "A: task_title = --titel" || bad "A: task_title" "$REQ"
[ "$(feld "$REQ" 'd["status"]["task_wake_at"]')" = "2099-01-01T00:00:00Z" ] && ok "A: task_wake_at = --weckzeit" || bad "A: task_wake_at" "$REQ"
[ "$(feld "$REQ" 'd["status"]["task_machine"]')" = "mac" ] && ok "A: task_machine = --maschine" || bad "A: task_machine" "$REQ"
[ "$(feld "$REQ" 'd["status"]["machine"]')" = "{'origin': 'measured', 'value': 'mac'}" ] && ok "A: Kernfeld machine gemessen aus --maschine" || bad "A: machine" "$REQ"
[ "$(feld "$REQ" 'd["status"]["model"]')" = "{'origin': 'unknown'}" ] && ok "A: unbekannte Kernfelder als origin unknown" || bad "A: model" "$REQ"
grep -q '"token"' "$LOG" && bad "A: Token im Protokoll gelandet" || ok "A: kein Token im Anfrage-Protokoll"
echo "$AUS" | grep -qi "$TOKEN" && bad "A: Token in der Ausgabe" || ok "A: kein Token in --json-Ausgabe"
daemon_stoppen

# ==========================================================================
echo; echo "-- B: frage sendet zwei Anfragen in DERSELBEN Verbindung --"
daemon_starten
modus ok
AUS="$(wbc frage 20260910-auf-b --text "weiter so?" --grund "braucht Antwort" --titel "Vollständiger Stand" --weckzeit 2099-01-01T01:02:03Z --maschine mac --json)"
RC=$?
[ "$RC" = 0 ] && ok "B: frage Exit 0" || bad "B: Exit" "rc=$RC / $AUS"
[ "$(zeilen)" = 2 ] && ok "B: zwei Anfragen protokolliert (Stand, dann Frage)" || bad "B: Anzahl Anfragen" "$(zeilen) / $(cat "$LOG")"
R1="$(anfrage_n 1)"; R2="$(anfrage_n 2)"
[ "$(feld "$R1" 'd["request"]')" = "report_status" ] && [ "$(feld "$R1" 'd["status"]["task_state"]')" = "wartet_auf_nutzer" ] \
  && ok "B: erste Anfrage ist der eigene Stand wartet_auf_nutzer" || bad "B: erste Anfrage" "$R1"
[ "$(feld "$R2" 'd["request"]')" = "ask_question" ] && ok "B: zweite Anfrage ist ask_question" || bad "B: zweite Anfrage" "$R2"
[ "$(feld "$R2" 'd["session_id"]')" = "wb-traeger:20260910-auf-b" ] && ok "B: dieselbe Sitzungskennung wie der Stand" || bad "B: session_id" "$R2"
[ "$(feld "$R2" 'd["question"]')" = "weiter so?" ] && ok "B: Fragetext unveraendert durchgereicht" || bad "B: question" "$R2"
echo "$(feld "$R2" 'd["question_id"]')" | grep -q "^20260910-auf-b-" && ok "B: question_id beginnt mit der Aufgabenkennung" || bad "B: question_id" "$(feld "$R2" 'd["question_id"]')"
[ "$(feld "$R1" 'd["status"]["task_title"]')" = "Vollständiger Stand" ] && [ "$(feld "$R1" 'd["status"]["task_reason"]')" = "braucht Antwort" ] \
  && ok "B: voller Status bleibt vor ask_question erhalten" || bad "B: Statusfelder" "$R1"
daemon_stoppen

# ==========================================================================
echo; echo "-- C: bericht sendet Stand zur_abnahme, dann report mit result_path --"
daemon_starten
modus ok
AUS="$(wbc bericht 20260910-auf-c --pfad /tmp/ergebnis-c.md --text "Ziel erreicht" --grund "fertig" --titel "Prüfbarer Bericht" --maschine mac --json)"
RC=$?
[ "$RC" = 0 ] && ok "C: bericht Exit 0" || bad "C: Exit" "rc=$RC / $AUS"
[ "$(zeilen)" = 2 ] && ok "C: zwei Anfragen protokolliert" || bad "C: Anzahl" "$(zeilen)"
R1="$(anfrage_n 1)"; R2="$(anfrage_n 2)"
[ "$(feld "$R1" 'd["status"]["task_state"]')" = "zur_abnahme" ] && ok "C: erster Stand zur_abnahme" || bad "C: erster Stand" "$R1"
[ "$(feld "$R2" 'd["request"]')" = "report" ] && ok "C: zweite Anfrage ist report" || bad "C: request" "$R2"
[ "$(feld "$R2" 'd["result_path"]')" = "/tmp/ergebnis-c.md" ] && ok "C: result_path = --pfad" || bad "C: result_path" "$R2"
[ "$(feld "$R2" 'd["message"]')" = "Ziel erreicht" ] && ok "C: message = --text" || bad "C: message" "$R2"
[ "$(feld "$R1" 'd["status"]["task_title"]')" = "Prüfbarer Bericht" ] && [ "$(feld "$R1" 'd["status"]["task_reason"]')" = "fertig" ] \
  && ok "C: voller Status bleibt vor report erhalten" || bad "C: Statusfelder" "$R1"
daemon_stoppen

# ==========================================================================
echo; echo "-- D: modus not_supported -- lehnt ab, Exit 2 --"
daemon_starten
modus not_supported
set +e
AUS="$(wbc status 20260910-auf-d --stand steckt --json)"; RC=$?
set -e
[ "$RC" = 2 ] && ok "D: Exit 2 bei 'not_supported'" || bad "D: Exit" "rc=$RC"
echo "$AUS" | grep -q '"status": "error"' && ok "D: --json zeigt status:error" || bad "D: JSON" "$AUS"
echo "$AUS" | grep -q "not_supported" && ok "D: Ablehnungscode in der Ausgabe" || bad "D: Code fehlt" "$AUS"
daemon_stoppen

# ==========================================================================
echo; echo "-- E: modus drop -- Verbindung weg nach hello, Exit 3 --"
daemon_starten
modus drop
set +e
AUS="$(wbc status 20260910-auf-e --stand steckt --json)"; RC=$?
set -e
[ "$RC" = 3 ] && ok "E: Exit 3, wenn die Verbindung nach der Anfrage abbricht" || bad "E: Exit" "rc=$RC / $AUS"
echo "$AUS" | grep -q "no_connection" && ok "E: --json meldet no_connection" || bad "E: JSON" "$AUS"
daemon_stoppen

# ==========================================================================
echo; echo "-- F: kein Daemon erreichbar -- Exit 3, ohne je zu verbinden --"
rm -f "$SOCK"
set +e
AUS="$(wbc status 20260910-auf-f --stand offen --json)"; RC=$?
set -e
[ "$RC" = 3 ] && ok "F: Exit 3 ohne laufenden Daemon" || bad "F: Exit" "rc=$RC / $AUS"

# ==========================================================================
echo; echo "-- G: falsches Token -- hello wird abgelehnt, Exit 2 --"
daemon_starten
modus ok
printf '{"human":"nicht-benutzt","agent":"falsches-token"}\n' > "$CFG/tokens.json"
set +e
AUS="$(wbc status 20260910-auf-g --stand offen --json)"; RC=$?
set -e
[ "$RC" = 2 ] && ok "G: Exit 2 bei falschem Token (hello:rejected)" || bad "G: Exit" "rc=$RC / $AUS"
[ ! -s "$LOG" ] && ok "G: keine Anfrage protokolliert -- hello scheiterte vor jeder Anfrage" || bad "G: Anfrage trotz Ablehnung" "$(cat "$LOG")"
printf '{"human":"nicht-benutzt","agent":"%s"}\n' "$TOKEN" > "$CFG/tokens.json"
daemon_stoppen

# ==========================================================================
echo; echo "-- H: sende, allgemeiner Weg --"
daemon_starten
modus ok
AUS="$(wbc sende '{"request":"report_status","status":{"id":"wb-traeger:auf-h","adapter":"wb-traeger","machine":{"origin":"unknown"},"project":null,"model":{"origin":"unknown"},"state":"idle","runtime_ms":{"origin":"unknown"},"context":{"origin":"unknown"},"budget":{"origin":"unknown"},"iteration":{"origin":"unknown"},"last_output":null,"open_question":null,"auftrag_id":"auf-h","kind":{"origin":"unknown"},"display_name":{"origin":"unknown"},"machine_identity":{"origin":"unknown"}}}' --json)"
RC=$?
[ "$RC" = 0 ] && ok "H: sende mit von Hand gebautem JSON ohne task_*-Felder, Exit 0 (Kennung frei, wie beim Daemon)" || bad "H: Exit" "rc=$RC / $AUS"
[ "$(zeilen)" = 1 ] && ok "H: genau eine Anfrage protokolliert" || bad "H: Anzahl" "$(zeilen)"
set +e
AUS="$(wbc sende '{"request":"report_status","status":{"auftrag_id":"ungueltig","task_state":"offen"}}' --json 2>&1)"; RC=$?
set -e
[ "$RC" = 2 ] && ok "H: sende prüft bei task_*-Feldern die Auftragskennung vor dem Socket" || bad "H: Vertrags-Exit" "rc=$RC / $AUS"
[ "$(zeilen)" = 1 ] && ok "H: ungültiger allgemeiner Status erzeugt keine Anfrage" || bad "H: Vertrags-Anfrage" "$(cat "$LOG")"
RLO="$(printf '\342\200\256')"
AUS="$(wbc sende '{"request":"report_status","status":{"auftrag_id":"20260910-auf-h","task_state":"offen","task_title":"a'"$RLO"'b   c","task_wake_at":"kaputt"}}' --json)"
REQ="$(letzte_anfrage)"
[ "$(feld "$REQ" 'd["status"]["task_title"]')" = "a b c" ] && [ "$(feld "$REQ" 'd["status"]["task_wake_at"] is None')" = True ] \
  && ok "H: sende normalisiert task_*-Text und Weckzeit wie die Unterbefehle" || bad "H: sende-Normalisierung" "$REQ"
set +e
AUS="$(wbc sende '{nicht valide' --json 2>&1)"; RC=$?
set -e
[ "$RC" = 2 ] && ok "H: ungueltiges JSON -> Exit 2, ohne zu verbinden" || bad "H: Exit bei kaputtem JSON" "rc=$RC"
[ "$(zeilen)" = 2 ] && ok "H: kaputtes JSON erzeugt keine weitere Anfrage" || bad "H: Anzahl nach kaputtem JSON" "$(zeilen)"
daemon_stoppen

# ==========================================================================
echo; echo "-- I: Vertragsgrenzen werden vor dem Socket normalisiert --"
daemon_starten
modus ok
LANG="$(python3 -c 'print("x" * 650)')"
AUS="$(wbc status 20260910-vertrag-a --stand offen --grund "$LANG" --titel "$LANG" --maschine "$LANG" --weckzeit "kein Datum" --json)"
RC=$?
REQ="$(letzte_anfrage)"
[ "$RC" = 0 ] && ok "I: überlange, bereinigbare Felder werden gesendet" || bad "I: Exit" "rc=$RC / $AUS"
[ "$(feld "$REQ" 'len(d["status"]["task_reason"])')" = 500 ] && ok "I: Grund auf 500 Zeichen gedeckelt" || bad "I: Grund" "$REQ"
[ "$(feld "$REQ" 'len(d["status"]["task_title"])')" = 200 ] && ok "I: Titel auf 200 Zeichen gedeckelt" || bad "I: Titel" "$REQ"
[ "$(feld "$REQ" 'len(d["status"]["task_machine"])')" = 64 ] && ok "I: Maschine auf 64 Zeichen gedeckelt" || bad "I: Maschine" "$REQ"
[ "$(feld "$REQ" 'd["status"]["task_wake_at"] is None')" = True ] && ok "I: ungültige Weckzeit ausgelassen" || bad "I: Weckzeit" "$REQ"
set +e
AUS="$(wbc status nicht-gueltig --stand offen --json 2>&1)"; RC=$?
set -e
[ "$RC" = 2 ] && ok "I: ungültige Auftragskennung wird vor Socket abgelehnt" || bad "I: ID Exit" "rc=$RC / $AUS"
[ "$(zeilen)" = 1 ] && ok "I: ungültige Auftragskennung erzeugt keine Anfrage" || bad "I: ID Anfrage" "$(cat "$LOG")"
STEUER=$'Titel\tmit\nSteuerzeichen'
AUS="$(wbc status 20260910-vertrag-b --stand offen --titel "$STEUER" --json)"
RC=$?
REQ="$(letzte_anfrage)"
[ "$RC" = 0 ] && [ "$(feld "$REQ" 'd["status"]["task_title"]')" = "Titel mit Steuerzeichen" ] \
  && ok "I: Steuerzeichen werden vor dem Socket zu Leerzeichen" || bad "I: Steuerzeichen" "$REQ"
UNSICHTBAR="$(printf 'links\342\200\256rechts\342\200\213  weit')"
AUS="$(wbc status 20260910-vertrag-c --stand offen --grund "$UNSICHTBAR" --json)"
REQ="$(letzte_anfrage)"
[ "$(feld "$REQ" 'd["status"]["task_reason"]')" = "links rechts weit" ] \
  && ok "I: Richtungs- und Nullbreitenzeichen werden Leerzeichen, Leerraum zusammengezogen" || bad "I: unsichtbare Zeichen" "$REQ"
[ "$(feld "$REQ" 'd["status"]["project"] is None and d["status"]["last_output"] is None and "last_activity_ms" not in d["status"] and "transcript_path" not in d["status"]')" = True ] \
  && ok "I: project/last_output als null, last_activity_ms/transcript_path fehlen (SessionStatus-Typ)" || bad "I: Statusfelder" "$REQ"
AUS="$(wbc status 20260910-vertrag-d --stand pausiert_weckzeit --weckzeit 2099-01-01T01:02:03 --json)"
REQ="$(letzte_anfrage)"
[ "$(feld "$REQ" 'd["status"]["task_wake_at"]')" = "2099-01-01T01:02:03Z" ] \
  && ok "I: Weckzeit ohne Zone wird als UTC in RFC 3339 geschrieben" || bad "I: Weckzeit ohne Zone" "$REQ"
AUS="$(wbc status 20260910-vertrag-e --stand pausiert_weckzeit --weckzeit 2099-01-01T01:02:03+02:00 --json)"
REQ="$(letzte_anfrage)"
[ "$(feld "$REQ" 'd["status"]["task_wake_at"]')" = "2099-01-01T01:02:03+02:00" ] \
  && ok "I: Weckzeit mit Versatz bleibt erhalten" || bad "I: Weckzeit mit Versatz" "$REQ"
N="$(zeilen)"
LANGE_ID="20260910-$(python3 -c 'print("a" * 41)')"
for ID in 20261399-datum "$LANGE_ID" 20260910-doppel--strich 20260910-GROSS; do
  set +e; wbc status "$ID" --stand offen --json >/dev/null 2>&1; RC=$?; set -e
  [ "$RC" = 2 ] && ok "I: Kennung '$ID' wird wie beim Daemon abgelehnt" || bad "I: Kennung $ID" "rc=$RC"
done
[ "$(zeilen)" = "$N" ] && ok "I: keine der abgelehnten Kennungen erreicht den Socket" || bad "I: Anfragen trotz Ablehnung" "$(zeilen) statt $N"
ZAEHLER_ID="20260910-$(python3 -c 'print("a" * 40)')-2"
set +e; wbc status "$ZAEHLER_ID" --stand offen --json >/dev/null 2>&1; RC=$?; set -e
[ "$RC" = 0 ] && ok "I: Slug von 40 Zeichen mit Kollisionszähler wird angenommen" || bad "I: Zählerkennung" "rc=$RC"
daemon_stoppen

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
