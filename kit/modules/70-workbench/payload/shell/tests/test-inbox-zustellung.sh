#!/usr/bin/env bash
# test-inbox-zustellung.sh -- der zweite Zustellweg (Socket-Inbox) und der Beleg,
# der fuer JEDEN Harness gilt.
#
# ANLASS (2026-08-20): In der Nacht auf den 20.08. hat der Tippweg fuenf Panes
# eingefroren und Auftraege stumm verschluckt. Fuer Claude-Code-Worker gibt es
# einen zweiten Weg, der nicht durch die Eingabezeile geht -- die Socket-Inbox der
# Sitzung (siehe shell/wb-inbox). Dieser Test prueft die drei Zusagen, die dabei
# zaehlen, und zwar die UNANGENEHMEN zuerst:
#
#   1  wb-inbox sagt NEIN, wo keine Sitzung ist. Kein Raten, keine Behauptung.
#   2  Verlangt jemand ausdruecklich den Inbox-Weg (workerZustellung=socket) und
#      es gibt ihn nicht, dann SCHEITERT die Zustellung hoerbar -- und sie
#      hinterlaesst KEINEN Platzhalter, der spaeter wie ein arbeitender Worker
#      aussieht. Das ist der Gegenbeweis, den der Auftrag verlangt.
#   3  Ohne die Einstellung faellt derselbe Fall still auf den Tippweg zurueck und
#      funktioniert unveraendert weiter -- der Rueckweg ist immer frei.
#   2b Und der Fehlschlag besetzt NICHT die Stelle, an der spaeter das echte
#      Ergebnis erwartet wird -- sonst ist "Zustellung gescheitert" von "Arbeit
#      fertig" nicht mehr zu unterscheiden. Der Ereignisstrom meldet ihn deshalb
#      auch nicht als "fertig".
#   4  Der INHALTSBELEG laeuft jetzt auch fuer einen Harness OHNE gemessenes
#      promptPattern (kimi, opencode). Vorher war Zustellung dort grundsaetzlich
#      unbelegbar; jetzt ist wenigstens belegt, ob der Auftragstext ueberhaupt im
#      Terminal angekommen ist -- und wenn nicht, ist es ein lauter Fehlschlag
#      statt einer Erfolgsmeldung.
#
# Was hier NICHT gemessen wird, weil es ohne echte Anmeldung nicht geht: eine
# ECHTE Claude-Sitzung mit echter Inbox. Gemessen (2026-08-20): mit umgelenktem
# HOME meldet Claude Code "Not logged in". Der Erfolgsfall des Inbox-Wegs ist
# deshalb mit einem echten Worker auf eigenem tmux-Socket belegt worden (siehe
# Ergebnisdatei des Auftrags 'kommweg'), nicht hier.
#
# ISOLATION: eigener tmux-Socket mit PID im Namen, eigenes HOME, eigene Registry.
# Keine Live-Session, kein ~/.pi-workers des Menschen, kein Netz, kein Modell.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"        # …/claude-workbench/shell
FAKE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fake-tui.py"
TMUX_REAL="$(command -v tmux 2>/dev/null)"
SOCKET="wbtest-inboxzustell-$$"
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-inboxzustell-test.XXXXXX")" && pwd)"
SHIM="$TESTHOME/.shim"
MARKE="z$$$RANDOM"
ECHTHOME="$HOME"
export HOME="$TESTHOME"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local d=$((SECONDS + 5))
  while [ $SECONDS -lt $d ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null; sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT INT TERM

echo "== Zustellung: Inbox-Weg, Gegenbeweis und Inhaltsbeleg (Socket $SOCKET) =="
[ -n "$TMUX_REAL" ]      || ueberspringen "tmux nicht im PATH"
[ -x "$REPO/pi-worker" ] || ueberspringen "shell/pi-worker fehlt"
[ -x "$REPO/wb-inbox" ]  || ueberspringen "shell/wb-inbox fehlt"
[ -f "$FAKE" ]           || ueberspringen "fake-tui.py fehlt neben diesem Test"
command -v /usr/bin/python3 >/dev/null || ueberspringen "python3 fehlt"

mkdir -p "$SHIM" "$TESTHOME/.claude/workbench" "$TESTHOME/.local/bin" "$TESTHOME/arbeit"
export WB_NO_DISCOVER=1

cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

for leer in wb-grid context-guard; do
  printf '#!/bin/sh\nexit 0\n' > "$TESTHOME/.local/bin/$leer"
  chmod +x "$TESTHOME/.local/bin/$leer"
done
for w in wb-state wb-mensch wb-rolle wb-harness-run wb-pane-write wb-inbox wb-ereignisse wb-verzeichniswache; do
  cp "$REPO/$w" "$TESTHOME/.local/bin/$w"
  chmod +x "$TESTHOME/.local/bin/$w"
done
mkdir -p "$TESTHOME/.claude/hooks/lib"
cp "$REPO/../hooks/lib/rollen.py" "$TESTHOME/.claude/hooks/lib/rollen.py" 2>/dev/null || true
cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"

spielart() {  # spielart <dateiname> <kind> <prompt-zeichen>
  cat > "$TESTHOME/.local/bin/$1" <<SHIMEOF
#!/bin/sh
FAKE_KIND=$2 FAKE_PROMPT='$3' exec /usr/bin/python3 "$FAKE"
SHIMEOF
  chmod +x "$TESTHOME/.local/bin/$1"
}
spielart tui-korrekt     korrekt     '❯'
spielart tui-verfaelscht verfaelscht '❯'
# Derselbe Stellvertreter mit einem ANDEREN Prompt-Zeichen -- fuer den Harness
# ohne gemessenes promptPattern. Das Zeichen selbst spielt dort keine Rolle
# (niemand liest die Eingabezeile), es trennt den Fall nur sauber vom claude-Weg.
spielart tui-stumm-ok    korrekt     '>'
spielart tui-stumm-leer  verfaelscht '>'

pi() {
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" TMUX= TMUX_PANE= \
      bash "$REPO/pi-worker" "$@" 2>&1
}

tmux -L "$SOCKET" -f /dev/null new-session -d -s "wb-$MARKE" -x 200 -y 60
tmux -L "$SOCKET" set-option -p -t "wb-$MARKE" @wb_role orchestrator

aufraeumen() {
  local p
  for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id} #{@wb_worker}' 2>/dev/null | awk '$2!=""{print $1}'); do
    tmux -L "$SOCKET" kill-pane -t "$p" 2>/dev/null
  done
}
worker_pane() {   # <name> -> pane-id
  tmux -L "$SOCKET" list-panes -a -F '#{pane_id} #{@wb_worker}' 2>/dev/null \
    | awk -v n="$1" '$2==n{print $1; exit}'
}
ergebnisdatei() { printf '%s\n' "$1" | sed -n 's/^Ergebnis-Datei: \([^ ]*\).*/\1/p' | tail -1; }

# ── 1: wb-inbox sagt NEIN, wo keine Claude-Sitzung ist ──────────────────────────
echo
echo "-- 1: wb-inbox findet nichts, wo nichts ist --"
aufraeumen
cp "$TESTHOME/.local/bin/tui-korrekt" "$TESTHOME/.local/bin/claude"
AUS="$(pi "n1$MARKE" claude-haiku45 "$TESTHOME/arbeit" "Erste Aufgabe $MARKE")"
P1="$(worker_pane "n1$MARKE")"
if [ -z "$P1" ]; then
  bad "1: Testaufbau -- kein Worker-Pane angelegt"
else
  RAUS="$(env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
          "$TESTHOME/.local/bin/wb-inbox" finde "$P1" 2>&1)"; RC=$?
  [ "$RC" -ne 0 ] \
    && ok "1: 'wb-inbox finde' auf einem Pane ohne Claude-Sitzung endet mit rc=$RC" \
    || bad "1: 'wb-inbox finde' meldet Erfolg, obwohl dort keine Sitzung laeuft: $RAUS"
  printf '%s' "$RAUS" | grep -q '/tmp/cc-socks' \
    && bad "1: 'wb-inbox finde' hat trotzdem eine Socketadresse geraten: $RAUS" \
    || ok "1: es wird keine Adresse geraten"
  echo "x" > "$TESTHOME/leer.txt"
  RAUS="$(env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
          "$TESTHOME/.local/bin/wb-inbox" sende "$P1" "$TESTHOME/leer.txt" 2>&1)"; RC=$?
  [ "$RC" -ne 0 ] \
    && ok "1: 'wb-inbox sende' scheitert dort ebenfalls, statt still nichts zu tun" \
    || bad "1: 'wb-inbox sende' behauptet Erfolg ohne Empfaenger: $RAUS"
  case "$RAUS" in
    *"keine lebende Claude-Sitzung"*) ok "1: die Meldung sagt, was fehlt" ;;
    *) bad "1: die Meldung nennt den Grund nicht: $RAUS" ;;
  esac
  # Die zweite Belegquelle (2026-08-20) muss dieselbe Zurueckhaltung zeigen: kein
  # Pfad, wo keine Sitzung ist. Ein geratener Pfad waere hier schlimmer als
  # keiner -- pi-worker wuerde in einer fremden Gespraechsdatei nach seinem
  # Marker suchen und ihn dort nie finden.
  RAUS="$(env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
          "$TESTHOME/.local/bin/wb-inbox" transcript "$P1" 2>/dev/null)"; RC=$?
  { [ "$RC" -ne 0 ] && [ -z "$RAUS" ]; } \
    && ok "1: 'wb-inbox transcript' liefert dort keinen Pfad, statt einen zu raten" \
    || bad "1: 'wb-inbox transcript' lieferte '$RAUS' (rc=$RC), obwohl dort keine Sitzung laeuft"
fi

# ── 2: workerZustellung=socket, aber keine Inbox -- lauter Fehlschlag ───────────
echo
echo "-- 2: Gegenbeweis -- eine Zustellung, die scheitern MUSS, scheitert hoerbar --"
aufraeumen
cp "$TESTHOME/.local/bin/tui-korrekt" "$TESTHOME/.local/bin/claude"
AUS="$(env WB_ZUSTELLUNG=socket HOME="$TESTHOME" \
        PATH="$SHIM:$TESTHOME/.local/bin:$PATH" TMUX= TMUX_PANE= \
        bash "$REPO/pi-worker" "n2$MARKE" claude-haiku45 "$TESTHOME/arbeit" "Zweite Aufgabe $MARKE" 2>&1)"
RC=$?
[ "$RC" -ne 0 ] && ok "2: Exit-Code ungleich 0 ($RC)" || bad "2: Exit-Code 0 trotz unmoeglicher Zustellung"
case "$AUS" in
  *"Submission verifiziert"*|*"zugestellt"*) bad "2: es wird Erfolg behauptet: $(printf '%s' "$AUS" | tail -3)" ;;
  *) ok "2: kein Wort von Erfolg" ;;
esac
case "$AUS" in
  *"keine lebende Claude-Sitzung eingetragen"*) ok "2: die Meldung nennt den Grund" ;;
  *) bad "2: die erwartete Meldung fehlt"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
esac
case "$AUS" in
  *"NICHT ersatzweise getippt"*) ok "2: und sie sagt ausdruecklich, dass NICHT ersatzweise getippt wurde" ;;
  *) bad "2: es bleibt offen, ob ersatzweise getippt wurde" ;;
esac
# Der Kern des Gegenbeweises: kein Platzhalter, der spaeter wie Arbeit aussieht.
RES2="$TESTHOME/.pi-workers/results/n2$MARKE"
if [ -e "$RES2/.laufend.md" ]; then
  bad "2: der Platzhalter '.laufend.md' steht noch da -- der Fehlschlag sieht spaeter wie ein arbeitender Worker aus"
else
  ok "2: kein Platzhalter zurueckgeblieben"
fi
ZIEL2="$(readlink "$RES2/latest.md" 2>/dev/null)"
case "$ZIEL2" in
  *.laufend.md|"") bad "2: latest.md zeigt nicht auf eine echte Datei (zeigt auf: '${ZIEL2:-nichts}')" ;;
  *) if grep -q "Zustellung an" "$ZIEL2" 2>/dev/null; then
       ok "2: latest.md zeigt auf eine echte Datei, die den Fehlschlag benennt"
     else
       bad "2: latest.md zeigt auf '$ZIEL2', dort steht aber kein Fehlschlag"
     fi ;;
esac
# ── 2b: und der Fehlschlag besetzt NICHT die Stelle des Ergebnisses ────────────
# Anlass (2026-08-20, Betrieb, Worker 'dsharness'): die Zustellpruefung schlug
# Alarm, obwohl der Auftrag angekommen war. pi-worker schrieb den Fehlschlag
# damals nach $RES -- also genau dorthin, wo spaeter das echte Ergebnis erwartet
# wird -- und der Ereignisstrom meldete den gerade erst anfangenden Worker als
# FERTIG. Danach ist "Zustellung gescheitert" von "Arbeit fertig" nicht mehr zu
# unterscheiden. Diese Zusage haelt beides auseinander.
RESPFAD2="$(printf '%s\n' "$AUS" | sed -n 's/^Ergebnis-Datei: \([^ ]*\).*/\1/p' | tail -1)"
if [ -z "$RESPFAD2" ]; then
  # Der Fehlschlag endet, BEVOR die Zeile "Ergebnis-Datei:" gedruckt wird -- dann
  # steht der erwartete Pfad in der Fehlschlagdatei selbst.
  RESPFAD2="$(sed -n 's/^- Erwartete Ergebnisdatei: \([^ ]*\).*/\1/p' "$ZIEL2" 2>/dev/null | tail -1)"
fi
if [ -z "$RESPFAD2" ]; then
  bad "2b: der erwartete Ergebnispfad steht nirgends -- die Zusage kann nichts messen"
else
  [ -e "$RESPFAD2" ] \
    && bad "2b: der Fehlschlag liegt unter dem ERGEBNISPFAD ($RESPFAD2) -- genau die Verwechslung vom 20.08." \
    || ok "2b: der Ergebnispfad ist frei geblieben, der Fehlschlag liegt woanders"
  case "$ZIEL2" in
    *.zustellung-fehlgeschlagen.md) ok "2b: die Fehlschlagdatei traegt einen sprechenden Namen" ;;
    *) bad "2b: die Fehlschlagdatei heisst '$ZIEL2' -- am Namen ist sie nicht zu erkennen" ;;
  esac
fi
# Und `wb-result` darf sie nicht als Ergebnis ausgeben: den Text ZEIGEN ja --
# wer fragt, will genau das wissen -- aber nicht mit Exit 0 antworten, denn das
# heisst "fertig".
if [ -x "$REPO/wb-result" ]; then
  RES_AUS="$(env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
      "$REPO/wb-result" "n2$MARKE" 2>&1)"; RC=$?
  [ "$RC" -ne 0 ] \
    && ok "2b: wb-result meldet den Fehlschlag NICHT als fertig (rc=$RC)" \
    || bad "2b: wb-result meldet den Fehlschlag als fertig (rc=0) -- dieselbe Verwechslung, nur an anderer Stelle"
  case "$RES_AUS" in
    *"Zustellung"*) ok "2b: wb-result zeigt trotzdem, was los ist" ;;
    *) bad "2b: wb-result schweigt ueber den Grund: $RES_AUS" ;;
  esac
else
  bad "2b: shell/wb-result fehlt -- die Gegenprobe faellt aus"
fi
# Und der Ereignisstrom darf sie nicht als Ergebnis melden.
if [ -x "$REPO/wb-ereignisse" ]; then
  EREIG_AUS="$(env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
      "$REPO/wb-ereignisse" --session "wb-$MARKE" --einmal 2>/dev/null)"
  case "$EREIG_AUS" in
    *"fertig  n2$MARKE"*) bad "2b: der Ereignisstrom meldet den Fehlschlag als 'fertig' -- der Fehlalarm vom 20.08. in Reinform" ;;
    *) ok "2b: der Ereignisstrom meldet den Fehlschlag NICHT als 'fertig'" ;;
  esac
else
  bad "2b: shell/wb-ereignisse fehlt -- die Gegenprobe des Ereignisstroms faellt aus"
fi

# ── 3: ohne die Einstellung faellt derselbe Fall auf den Tippweg zurueck ────────
echo
echo "-- 3: der Rueckweg ist frei -- ohne Vorgabe wird wie bisher getippt --"
aufraeumen
cp "$TESTHOME/.local/bin/tui-korrekt" "$TESTHOME/.local/bin/claude"
AUS="$(pi "n3$MARKE" claude-haiku45 "$TESTHOME/arbeit" "Dritte Aufgabe $MARKE")"; RC=$?
[ "$RC" -eq 0 ] && ok "3: Exit-Code 0" || bad "3: Exit-Code $RC"
case "$AUS" in
  *"Submission verifiziert"*) ok "3: der Tippweg meldet unveraendert Erfolg" ;;
  *) bad "3: der Rueckfall auf den Tippweg funktioniert nicht"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
esac
case "$AUS" in
  *"Sitzungs-Inbox"*) bad "3: es wird von der Inbox geredet, obwohl es keine gibt" ;;
  *) ok "3: die Inbox wird nicht erwaehnt, wo es keine gibt" ;;
esac

# ── 4: workerZustellung=paste ruehrt die Inbox gar nicht erst an ────────────────
echo
echo "-- 4: workerZustellung=paste laesst die Inbox unangetastet --"
aufraeumen
AUS="$(env WB_ZUSTELLUNG=paste HOME="$TESTHOME" \
        PATH="$SHIM:$TESTHOME/.local/bin:$PATH" TMUX= TMUX_PANE= \
        bash "$REPO/pi-worker" "n4$MARKE" claude-haiku45 "$TESTHOME/arbeit" "Vierte Aufgabe $MARKE" 2>&1)"
RC=$?
[ "$RC" -eq 0 ] && ok "4: Exit-Code 0" || bad "4: Exit-Code $RC"
case "$AUS" in
  *"Submission verifiziert"*) ok "4: es wird getippt und verifiziert wie zuvor" ;;
  *) bad "4: der Paste-Weg meldet keinen Erfolg"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
esac

# ── 5: Inhaltsbeleg fuer einen Harness OHNE gemessenes promptPattern ────────────
echo
echo "-- 5: ein Harness ohne promptPattern -- angekommen ist jetzt belegbar --"
aufraeumen
"$TESTHOME/.local/bin/wb-state" models add --kind harness \
  '{"id":"stummcli","label":"Harness ohne Prompt-Muster","command":"tui-stumm-ok","args":[],"cwdMode":"cd","systemPrompt":{"style":"none"},"readyPattern":"^>"}' >/dev/null 2>&1
"$TESTHOME/.local/bin/wb-state" models add \
  '{"id":"stumm-1","harness":"stummcli","provider":"ollama","modelRef":"stumm","roles":["worker"],"defaultEffort":"low","workerClass":["bulk"]}' >/dev/null 2>&1
if [ -z "$("$TESTHOME/.local/bin/wb-state" models get stumm-1 --field id 2>/dev/null)" ]; then
  bad "5: der Testharness liess sich nicht in die Registry eintragen"
else
  AUS="$(pi "n5$MARKE" stumm-1 "$TESTHOME/arbeit" "Fuenfte Aufgabe $MARKE")"; RC=$?
  [ "$RC" -eq 0 ] && ok "5: Exit-Code 0" || bad "5: Exit-Code $RC"
  case "$AUS" in
    *"ANGEKOMMEN ist er"*) ok "5: das Ankommen des Auftragstexts wird BELEGT, nicht mehr offengelassen" ;;
    *) bad "5: der Inhaltsbeleg fehlt"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
  esac
  case "$AUS" in
    *"nicht pruefbar"*) ok "5: und was weiterhin offen ist (das Absenden), wird beim Namen genannt" ;;
    *) bad "5: es wird nicht gesagt, was offen bleibt" ;;
  esac
  # Gegenprobe: derselbe Harness, aber der Text kommt NICHT im Pane an.
  aufraeumen
  "$TESTHOME/.local/bin/wb-state" models set --kind harness stummcli command '"tui-stumm-leer"' >/dev/null 2>&1
  AUS="$(pi "n6$MARKE" stumm-1 "$TESTHOME/arbeit" "Sechste Aufgabe $MARKE")"; RC=$?
  [ "$RC" -ne 0 ] \
    && ok "6: kommt der Text NICHT an, ist das jetzt ein Fehlschlag (rc=$RC) statt einer Erfolgsmeldung" \
    || bad "6: Exit-Code 0, obwohl der Auftragstext nie im Pane stand"
  case "$AUS" in
    *"weder belegt"*) ok "6: die Meldung sagt genau, was nicht belegt ist" ;;
    *) bad "6: die erwartete Meldung fehlt"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
  esac
  RES6="$TESTHOME/.pi-workers/results/n6$MARKE"
  [ -e "$RES6/.laufend.md" ] \
    && bad "6: Platzhalter zurueckgeblieben" \
    || ok "6: auch hier bleibt kein Platzhalter stehen"
fi

# ── die echte Umgebung blieb unberuehrt ─────────────────────────────────────────
echo
echo "-- die echte Umgebung blieb unberuehrt --"
UEBRIG=0
for n in "n1$MARKE" "n2$MARKE" "n3$MARKE" "n4$MARKE" "n5$MARKE" "n6$MARKE"; do
  [ -e "$ECHTHOME/.pi-workers/results/$n" ] && UEBRIG=$((UEBRIG+1))
done
[ "$UEBRIG" -eq 0 ] \
  && ok "kein Ergebnisordner unter dem echten HOME" \
  || bad "$UEBRIG Ergebnisordner im ECHTEN ~/.pi-workers -- Testisolation gebrochen"
if grep -q 'stummcli\|stumm-1' "$ECHTHOME/.claude/workbench/models.json" 2>/dev/null; then
  bad "die ECHTE Registry traegt Testeintraege -- Testisolation gebrochen"
else
  ok "die echte Registry blieb ohne Testeintraege"
fi

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
