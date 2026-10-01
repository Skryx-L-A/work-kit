#!/usr/bin/env bash
# test-absende-pruefung.sh -- die Zusagen der Absende-Pruefung in `pi-worker`.
#
# ANLASS (08.08.): Jeder aider-Spawn endete mit "FEHLER: Prompt haengt ... in der
# Inputbox", obwohl der Auftrag angekommen war. Die Pruefung sah dreimal im Abstand
# von zwei Sekunden nach, ob die Eingabezeile wieder frei ist, und tippte bei JEDEM
# Fehlversuch erneut Enter. Sechs Sekunden reichen bei einem lokalen Modell nicht --
# und die zusaetzlichen Tastendruecke gingen in eine Sitzung, die laengst arbeitete.
# Das war der eigentliche Schaden, nicht die falsche Meldung.
#
# DIE VIER AUSSAGEN, die hier gemessen werden:
#   1  Ein Harness, der laenger als sechs Sekunden braucht, gilt als abgeschickt --
#      und WAEHREND er arbeitet, wird kein weiteres Enter getippt.
#   2  Ein Auftrag, der WIRKLICH in der Box haengen bleibt (Bildschirm eingefroren),
#      wird weiterhin als Fehlschlag gemeldet, mit Exit-Code ungleich 0. Dort sind
#      die zusaetzlichen Enter richtig und werden auch getippt.
#   3  Der haeufige Fall (Eingabezeile sofort frei, wie bei claude) bleibt schnell.
#   4  Bewegt sich der Pane bis zur Frist, ohne die Eingabezeile freizugeben, wird
#      WEDER Erfolg noch Fehlschlag behauptet -- und wieder kein Enter nachgetippt.
#
# GEZAEHLT WIRD AN ZWEI STELLEN, unabhaengig voneinander: `wb-pane-write` wird durch
# einen Schirm ersetzt, der jeden Tastendruck protokolliert und danach die ECHTE
# Fassung ausfuehrt (die Entscheidung, wer tippen darf, bleibt also beim echten
# Werkzeug), und der Stellvertreter-Agent schreibt jedes empfangene Enter selbst mit.
# Der zweite Zaehler ist der aussagekraeftigere: er sitzt dort, wo der Tastendruck
# ankommt.
#
# KEIN ECHTER AGENT LAEUFT HIER. Der Stellvertreter (fake-tui.py, daneben) verhaelt
# sich wie eine TUI: Rohmodus, eigene Anzeige, Bracketed Paste. Vier Spielarten --
# `sofort` raeumt die Eingabezeile beim Enter (claude), `langsam` wiederholt den
# Auftrag mit demselben Zeichen, mit dem es seine Eingabezeile zeichnet, und braucht
# acht Sekunden (aider), `hart` nimmt den Text nie an und ruehrt sich nicht mehr,
# `nie` arbeitet sichtbar weiter, ohne die Zeile je freizugeben.
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
SOCKET="wbtest-absenden-$$"
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-absenden-test.XXXXXX")" && pwd)"
SHIM="$TESTHOME/.shim"
MARKE="a$$$RANDOM"
# HOME wird fuer den GANZEN Lauf umgelenkt, nicht nur fuer den Aufruf des Prueflings.
# Beim ersten Bauen dieses Tests stand das `export` nicht hier, sondern nur in der
# Hilfsfunktion `pi` -- und die zwei `wb-state models add` weiter unten schrieben ihre
# Testeintraege prompt in die ECHTE Registry unter ~/.claude/workbench/models.json
# (nachgesehen, herausgenommen, gegen eine Kopie geprueft). Ein Test, der ein Werkzeug
# ohne umgelenktes HOME aufruft, fasst die Live-Konfiguration an.
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

echo "== pi-worker: Absende-Pruefung (Socket $SOCKET, HOME $TESTHOME) =="
[ -n "$TMUX_REAL" ]     || ueberspringen "tmux nicht im PATH"
[ -x "$REPO/pi-worker" ] || ueberspringen "shell/pi-worker fehlt"
[ -f "$FAKE" ]           || ueberspringen "fake-tui.py fehlt neben diesem Test"
command -v /usr/bin/python3 >/dev/null || ueberspringen "python3 fehlt"

mkdir -p "$SHIM" "$TESTHOME/.claude/workbench" "$TESTHOME/.local/bin" "$TESTHOME/arbeit"
export WB_NO_DISCOVER=1

# tmux des Prueflings auf den Testsocket nageln -- pi-worker ruft es ungeflaggt.
cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

# Werkzeuge, die pi-worker im Vorbeigehen ruft und die hier nichts zu tun haben.
for leer in wb-grid context-guard; do
  printf '#!/bin/sh\nexit 0\n' > "$TESTHOME/.local/bin/$leer"
  chmod +x "$TESTHOME/.local/bin/$leer"
done
cp "$REPO/wb-state" "$TESTHOME/.local/bin/wb-state"
cp "$REPO/wb-mensch" "$TESTHOME/.local/bin/wb-mensch"
cp "$REPO/wb-rolle" "$TESTHOME/.local/bin/wb-rolle"
# Der Registry-Weg (Fall 5) startet den Pane nicht direkt, sondern ueber diesen Schirm.
cp "$REPO/wb-harness-run" "$TESTHOME/.local/bin/wb-harness-run"
chmod +x "$TESTHOME/.local/bin/wb-state" "$TESTHOME/.local/bin/wb-mensch" \
         "$TESTHOME/.local/bin/wb-rolle" "$TESTHOME/.local/bin/wb-harness-run"
mkdir -p "$TESTHOME/.claude/hooks/lib"
cp "$REPO/../hooks/lib/rollen.py" "$TESTHOME/.claude/hooks/lib/rollen.py" 2>/dev/null || true
cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"

# wb-pane-write: die ECHTE Fassung entscheidet weiter, wer tippen darf -- davor haengt
# nur ein Schirm, der mitschreibt. Ein Platzhalter wuerde genau die Entscheidung
# wegnehmen, die hier mitgemessen wird.
cp "$REPO/wb-pane-write" "$TESTHOME/.local/bin/wb-pane-write.echt"
chmod +x "$TESTHOME/.local/bin/wb-pane-write.echt"
TASTENLOG="$TESTHOME/tasten.log"
cat > "$TESTHOME/.local/bin/wb-pane-write" <<SHIMEOF
#!/bin/sh
printf '%s\n' "\$*" >> "$TASTENLOG"
exec "$TESTHOME/.local/bin/wb-pane-write.echt" "\$@"
SHIMEOF
chmod +x "$TESTHOME/.local/bin/wb-pane-write"

# Der Stellvertreter, in vier Spielarten. Jede ist ein Zweizeiler, der die Spielart
# setzt und den einen Stellvertreter ausfuehrt -- so kann jede von ihnen als
# `claude` (schneller Pfad) ODER als Kommando eines Registry-Harness stehen.
AGENTLOG="$TESTHOME/agent.log"
spielart() {  # spielart <dateiname> <kind> <prompt-zeichen> <busy-sekunden>
  cat > "$TESTHOME/.local/bin/$1" <<SHIMEOF
#!/bin/sh
FAKE_KIND=$2 FAKE_PROMPT='$3' FAKE_BUSY=$4 FAKE_LOG='$AGENTLOG' exec /usr/bin/python3 "$FAKE"
SHIMEOF
  chmod +x "$TESTHOME/.local/bin/$1"
}
spielart tui-sofort  sofort  '❯' 0
spielart tui-langsam langsam '❯' 8
spielart tui-hart    hart    '❯' 0
spielart tui-nie     nie     '❯' 0
spielart tui-aider   langsam '>' 8

pi() {
  # Kit: the target session is named, not guessed from the wb-* sessions of the socket
  # (under load the guess once failed with 'Ziel-Workbench nicht eindeutig bestimmbar').
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" TMUX= TMUX_PANE= WB_SESSION="wb-$MARKE" \
      bash "$REPO/pi-worker" "$@" 2>&1
}
# Vor jedem Lauf beide Zaehler auf null.
zaehler_zuruecksetzen() { : > "$TASTENLOG"; : > "$AGENTLOG"; }
getippte_enter()  { grep -c 'taste .* Enter' "$TASTENLOG" 2>/dev/null | tr -d ' '; }
erhaltene_enter() { grep -c '^ENTER' "$AGENTLOG" 2>/dev/null | tr -d ' '; }

tmux -L "$SOCKET" -f /dev/null new-session -d -s "wb-$MARKE" -x 200 -y 60
tmux -L "$SOCKET" set-option -p -t "wb-$MARKE" @wb_role orchestrator

# Nach jedem Fall wird der Worker-Pane wieder abgeraeumt. Nicht Kosmetik: mit vier
# gestapelten Panes wird jeder einzelne so flach, dass die Anzeige des Stellvertreters
# aus dem sichtbaren Bereich scrollt -- dann findet `capture-pane` keine Eingabezeile
# mehr, und der Test misst die Pane-Groesse statt der Absende-Pruefung. Beim ersten
# Bauen ist genau das passiert (Fall 4 meldete faelschlich 'verifiziert', Fall 5 bekam
# 'no space for a new pane'). Gekillt wird nach PANE-ID aus der Worker-Markierung,
# nie nach Muster.
aufraeumen() {
  local p
  for p in $(tmux -L "$SOCKET" list-panes -a -F '#{pane_id} #{@wb_worker}' 2>/dev/null | awk '$2!=""{print $1}'); do
    tmux -L "$SOCKET" kill-pane -t "$p" 2>/dev/null
  done
}

# ── 1: ein langsamer Harness gilt als abgeschickt, ohne zweites Enter ────────────
echo
echo "-- 1: acht Sekunden beschaeftigt (aider-Form), Auftrag ist angekommen --"
aufraeumen
cp "$TESTHOME/.local/bin/tui-langsam" "$TESTHOME/.local/bin/claude"
zaehler_zuruecksetzen
T0=$SECONDS
AUS="$(pi "w1$MARKE" claude-haiku45 "$TESTHOME/arbeit" "Erste Aufgabe $MARKE")"; RC=$?
DAUER=$(( SECONDS - T0 ))
case "$AUS" in
  *"Submission verifiziert"*) ok "1: der Auftrag gilt als abgeschickt (nach ${DAUER}s)" ;;
  *) bad "1: keine Verifikation nach ${DAUER}s, rc=$RC"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
esac
[ "$RC" -eq 0 ] && ok "1: Exit-Code 0" || bad "1: Exit-Code $RC"
[ "$DAUER" -ge 8 ] \
  && ok "1: es wurde laenger als die alten sechs Sekunden gewartet (${DAUER}s)" \
  || bad "1: der Lauf war nach ${DAUER}s durch -- die acht Sekunden Arbeit koennen nicht abgewartet worden sein"
E_GETIPPT="$(getippte_enter)"; E_ERHALTEN="$(erhaltene_enter)"
[ "$E_GETIPPT" = "1" ] \
  && ok "1: genau EIN Enter getippt, keines nachgeschoben" \
  || bad "1: $E_GETIPPT Enter getippt -- in einen laufenden Auftrag wurde hineingetippt"
[ "$E_ERHALTEN" = "1" ] \
  && ok "1: der Stellvertreter hat genau ein Enter empfangen" \
  || bad "1: der Stellvertreter empfing $E_ERHALTEN Enter"

# ── 2: ein wirklich haengender Auftrag bleibt ein Fehlschlag ─────────────────────
echo
echo "-- 2: eingefrorener Pane, Text bleibt in der Box --"
aufraeumen
cp "$TESTHOME/.local/bin/tui-hart" "$TESTHOME/.local/bin/claude"
zaehler_zuruecksetzen
T0=$SECONDS
AUS="$(pi "w2$MARKE" claude-haiku45 "$TESTHOME/arbeit" "Zweite Aufgabe $MARKE")"; RC=$?
DAUER=$(( SECONDS - T0 ))
case "$AUS" in
  *"FEHLER: Prompt haengt"*) ok "2: der Fehlschlag wird gemeldet (nach ${DAUER}s)" ;;
  *) bad "2: kein Fehlschlag gemeldet"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
esac
[ "$RC" -ne 0 ] && ok "2: Exit-Code ungleich 0 ($RC)" || bad "2: Exit-Code 0 trotz haengendem Auftrag"
case "$AUS" in
  *"Submission verifiziert"*) bad "2: es wird trotzdem eine Verifikation behauptet" ;;
  *) ok "2: keine Erfolgsbehauptung" ;;
esac
E_GETIPPT="$(getippte_enter)"; E_ERHALTEN="$(erhaltene_enter)"
[ "$E_GETIPPT" = "3" ] \
  && ok "2: ein Enter plus zwei Nachhilfen -- bei einem stehenden Pane richtig" \
  || bad "2: $E_GETIPPT Enter getippt statt 3"
[ "$E_ERHALTEN" = "3" ] \
  && ok "2: alle drei kamen beim Stellvertreter an" \
  || bad "2: der Stellvertreter empfing $E_ERHALTEN Enter statt 3"

# ── 3: der haeufige Fall bleibt schnell ─────────────────────────────────────────
echo
echo "-- 3: Eingabezeile sofort frei (claude-Form) --"
aufraeumen
cp "$TESTHOME/.local/bin/tui-sofort" "$TESTHOME/.local/bin/claude"
zaehler_zuruecksetzen
T0=$SECONDS
AUS="$(pi "w3$MARKE" claude-haiku45 "$TESTHOME/arbeit" "Dritte Aufgabe $MARKE")"; RC=$?
DAUER=$(( SECONDS - T0 ))
case "$AUS" in
  *"Submission verifiziert"*) ok "3: der Auftrag gilt als abgeschickt (nach ${DAUER}s)" ;;
  *) bad "3: keine Verifikation, rc=$RC"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
esac
[ "$DAUER" -le 15 ] \
  && ok "3: der haeufige Fall bleibt schnell (${DAUER}s inklusive Spawn)" \
  || bad "3: ${DAUER}s fuer den haeufigen Fall -- zu langsam"
E_GETIPPT="$(getippte_enter)"
[ "$E_GETIPPT" = "1" ] && ok "3: genau EIN Enter getippt" || bad "3: $E_GETIPPT Enter getippt statt 1"

# ── 4: Pane arbeitet, Zeile wird nie frei -- weder Erfolg noch Fehlschlag ────────
echo
echo "-- 4: bis zur Frist in Bewegung, Eingabezeile bleibt belegt (dauert ~45s) --"
aufraeumen
cp "$TESTHOME/.local/bin/tui-nie" "$TESTHOME/.local/bin/claude"
zaehler_zuruecksetzen
T0=$SECONDS
AUS="$(pi "w4$MARKE" claude-haiku45 "$TESTHOME/arbeit" "Vierte Aufgabe $MARKE")"; RC=$?
DAUER=$(( SECONDS - T0 ))
case "$AUS" in
  *"Submission NICHT verifiziert"*) ok "4: es wird offen gesagt, dass nichts verifiziert ist (nach ${DAUER}s)" ;;
  *) bad "4: die ehrliche Meldung fehlt"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
esac
case "$AUS" in
  *"Submission verifiziert"*) bad "4: es wird eine Verifikation behauptet" ;;
  *) ok "4: keine Erfolgsbehauptung" ;;
esac
case "$AUS" in
  *"FEHLER: Prompt haengt"*) bad "4: ein arbeitender Pane wird als haengend gemeldet" ;;
  *) ok "4: kein Fehlschlag behauptet -- der Pane arbeitet ja" ;;
esac
[ "$RC" -eq 0 ] && ok "4: Exit-Code 0" || bad "4: Exit-Code $RC"
E_GETIPPT="$(getippte_enter)"
[ "$E_GETIPPT" = "1" ] \
  && ok "4: kein Enter nachgeschoben, solange sich etwas tut" \
  || bad "4: $E_GETIPPT Enter getippt statt 1"

# ── 5: dasselbe fuer ein anderes Harness aus der Registry ('>' statt '❯') ────────
echo
echo "-- 5: derselbe langsame Fall ueber die Registry, Prompt-Zeichen '>' --"
aufraeumen
"$TESTHOME/.local/bin/wb-state" models add --kind harness \
  '{"id":"fakeaidercli","label":"Fake aider","command":"tui-aider","args":[],"cwdMode":"cd","systemPrompt":{"style":"none"},"readyPattern":"^>","promptPattern":"^>"}' >/dev/null 2>&1
"$TESTHOME/.local/bin/wb-state" models add \
  '{"id":"fake-aider-1","harness":"fakeaidercli","provider":"ollama","modelRef":"fake-aider","roles":["worker"],"defaultEffort":"low","workerClass":["bulk"]}' >/dev/null 2>&1
if [ -n "$("$TESTHOME/.local/bin/wb-state" models get fake-aider-1 --field id 2>/dev/null)" ]; then
  zaehler_zuruecksetzen
  T0=$SECONDS
  AUS="$(pi "w5$MARKE" fake-aider-1 "$TESTHOME/arbeit" "Fuenfte Aufgabe $MARKE")"; RC=$?
  DAUER=$(( SECONDS - T0 ))
  case "$AUS" in
    *"Submission verifiziert"*) ok "5: auch mit '>' gilt der Auftrag als abgeschickt (nach ${DAUER}s)" ;;
    *) bad "5: keine Verifikation, rc=$RC"; printf '%s\n' "$AUS" | sed 's/^/      | /' | tail -8 ;;
  esac
  E_GETIPPT="$(getippte_enter)"
  [ "$E_GETIPPT" = "1" ] \
    && ok "5: genau EIN Enter getippt -- die Aenderung haengt nicht am Harness" \
    || bad "5: $E_GETIPPT Enter getippt statt 1"
else
  bad "5: der Testharness liess sich nicht in die Registry eintragen"
fi

# ── die echte Umgebung blieb unberuehrt ─────────────────────────────────────────
echo
echo "-- die echte Umgebung blieb unberuehrt --"
UEBRIG=0
for n in "w1$MARKE" "w2$MARKE" "w3$MARKE" "w4$MARKE" "w5$MARKE"; do
  [ -e "$ECHTHOME/.pi-workers/results/$n" ] && UEBRIG=$((UEBRIG+1))
done
[ "$UEBRIG" -eq 0 ] \
  && ok "kein Ergebnisordner unter dem echten HOME" \
  || bad "$UEBRIG Ergebnisordner im ECHTEN ~/.pi-workers -- Testisolation gebrochen"
# Und die Gegenprobe zu dem Fehler, mit dem dieser Test angefangen hat: die echte
# Registry darf keinen der beiden Testeintraege tragen.
if grep -q 'fakeaidercli\|fake-aider-1' "$ECHTHOME/.claude/workbench/models.json" 2>/dev/null; then
  bad "die ECHTE Registry traegt Testeintraege -- Testisolation gebrochen"
else
  ok "die echte Registry blieb ohne Testeintraege"
fi

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
