#!/usr/bin/env bash
# test-context-guard-kompakt-einmal.sh -- der Kompaktierbefehl fuer den
# ORCHESTRATOR darf innerhalb eines Zyklus nie ein zweites Mal getippt werden,
# auch nicht nach einer unverifizierten Absendung.
#
# ANLASS (2026-08-19, Log-Beleg context-guard-wb-AI.log, wortgleich):
#   22:55 orchestrator (%0) at 75% (transcript) -> brain+state update requested, warte auf .../.wb-knowledge-saved
#   22:57 context-guard: Absenden an %0 NICHT verifiziert -- Text stand nach Enter (und einer Nachhilfe) noch in der Eingabezeile.
#   22:58 context-guard: Absenden an %0 NICHT verifiziert -- Text stand nach Enter (und einer Nachhilfe) noch in der Eingabezeile.
#   23:00 orchestrator (%0) -> /compact typed (Sentinel .../.wb-knowledge-saved)
# Drei Kompaktierungen aus EINER einzigen Notbremse: der Abstand zwischen den
# beiden "NICHT verifiziert"-Zeilen (60s = POLL-Default) beweist, dass der
# Kompaktierbefehl bei JEDEM Poll neu getippt wurde, solange die vorherige
# Absendung unverifiziert blieb -- compact_orchestrator() markierte `compacted`
# bis heute nur auf dem Erfolgspfad. Zwei davon waren ueberzaehlig, eine wurde
# von Hand abgefangen, die andere lief durch und warf echten Kontext weg.
#
# GEMESSEN, NICHT UEBERNOMMEN (siehe Kopfkommentar bei absenden_verifizieren()
# in shell/context-guard): der Verdacht, eine Slash-Vervollstaendigungsliste
# male Zeilen mit demselben Zeiger '❯' wie die Eingabezeile, ist an einer
# echten Claude-Code-TUI (isolierter Socket, eigenes Scratch-Verzeichnis)
# widerlegt -- Vorschlagszeilen tragen dort KEIN '❯', nur eine Einrueckung.
# Diese Suite bildet darum nicht die Vervollstaendigungsliste nach, sondern das
# tatsaechlich beobachtbare Symptom aus dem Log: eine Eingabezeile, die nach
# dem Absenden weiterhin etwas Zeigerartiges zeigt (fake-worker-swallow.py,
# FAKE_KIND=hart -- nichts wird je angenommen, derselbe Stellvertreter wie in
# test-context-guard-absende-verschluckt.sh).
#
# GEPRUEFT WIRD, ueber mehrere Poll-Zyklen (POLL=2s, damit die Suite nicht auf
# den Produktions-Vorgabewert von 60s je Zyklus warten muss):
#   A  Der Kompaktierbefehl ('/verdichte', erfundenes Format wie in den
#      Schwestersuiten) taucht in der Eingabezeile der Fake-TUI GENAU EINMAL
#      auf -- ohne den Fix wuerde jeder Poll-Zyklus ihn erneut abschicken, und
#      die (nie geleerte) Eingabezeile wuerde ihn mehrfach hintereinander
#      zeigen.
#   B  Genau EINE "NICHT verifiziert"-Zeile fuer den Orchestrator-Pane im
#      Protokoll -- nicht eine je Poll-Zyklus.
#   C  Kein einziges "-> /verdichte typed" im Protokoll (die Fake-TUI
#      verifiziert nie erfolgreich) -- die Wache behauptet nie faelschlich
#      Erfolg.
#
# ISOLATION: eigener Socket, eigenes HOME, eigene Registry -- wie
# test-context-guard-absende-verschluckt.sh (Harness-Id 'pi', erfundenes
# Kontextformat 'KTX <n> %', Kompaktierbefehl '/verdichte').
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"
FAKE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fake-worker-swallow.py"

SOCKET="wbtest-cgkompakt-$$"
TESTHOME="$(mktemp -d)"

# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$TESTHOME" || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
BIN="$TESTHOME/.local/bin"
SHIM="$TESTHOME/.shim"
REG="$TESTHOME/.claude/workbench/models.json"
GUARDPID=""

pass=0; fail=0
tm() { tmux -L "$SOCKET" "$@"; }
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cleanup() {
  [ -n "$GUARDPID" ] && kill "$GUARDPID" 2>/dev/null
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null
    sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

mkdir -p "$BIN" "$SHIM" "$TESTHOME/.local/state" "$TESTHOME/.claude/workbench" \
         "$TESTHOME/.pi-workers/results"
for w in context-guard wb-state; do
  src="$REPO/$w"
  [ -x "$src" ] || src="$REAL_BIN/$w"
  [ -x "$src" ] || { echo "FAIL  $w fehlt (weder $REPO noch $REAL_BIN)"; exit 1; }
  cp "$src" "$BIN/$w"
done
chmod +x "$BIN"/*

cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

cat > "$REG" <<REGEOF
{
  "version": 1,
  "providers": [{"id": "pruefprovider", "label": "Pruefprovider", "kind": "subscription"}],
  "harnesses": [
    {
      "id": "pi", "label": "Pruef-pi (Kompakt-einmal)", "command": "pi",
      "args": ["--model", "{model}"], "cwdMode": "cd", "readyPattern": "KTX",
      "contextPattern": "KTX[[:space:]]*([0-9]{1,3})[[:space:]]*%",
      "compactCommand": "/verdichte"
    }
  ],
  "models": []
}
REGEOF

cat > "$SHIM/pi" <<PIEOF
#!/bin/sh
exec /usr/bin/python3 "$FAKE"
PIEOF
chmod +x "$SHIM/pi"

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"

echo "== test-context-guard-kompakt-einmal: der Kompaktierbefehl wird nie ein zweites Mal in denselben Zyklus getippt =="
echo "   Socket: $SOCKET   HOME: $TESTHOME"
echo

tm kill-server 2>/dev/null
tm new-session -d -s wb-Cgk -c /tmp -x 120 -y 30
tm set-option -wg remain-on-exit on
# War hier vorher nur pane-died + after-split-window -- pane-exited fehlte.
# tmux_live_hooks_kappen (lib-testwerkzeuge.sh) deckt alle drei ab.
tmux_live_hooks_kappen "$SOCKET"

LOG_ORCH="$TESTHOME/orch-enter.log"; : > "$LOG_ORCH"
# 2026-09-10: FAKE_PCT liegt jetzt ZWISCHEN dem Warn-Schwellenwert (ORCH_PCT=70, siehe
# unten) und dem Notbremse-Schwellenwert (Vorgabe 80, hier unveraendert) -- der Sentinel
# zaehlt seit dem Fix erst NACH der eigenen Warnung dieses Guards, also muss die Warnung
# im Test wirklich ausgeloest werden, waehrend die Last selbst (75%) weiterhin UNTER der
# Notbremse bleibt: ausschliesslich der Sentinel-Weg soll hier fahren, nicht die Last.
ORCH="$(tm new-window -d -t "=wb-Cgk:" -P -F '#{pane_id}' \
    "PATH='$PANE_PATH' FAKE_KIND=hart FAKE_LOG='$LOG_ORCH' FAKE_PCT=75 FAKE_PCT_NACH=10 FAKE_COMPACT_TRIGGER='/verdichte' pi" 2>/dev/null)"
tm set -p -t "$ORCH" @wb_cmd "exec pi"
sleep 2

# Kein Worker-Argument noetig: context-guard <orch-pane> laeuft mit leerer
# Worker-Liste, die Orchestrator-Kette (Sentinel/Notbremse) ist davon unabhaengig.
GLOG="$TESTHOME/guard.log"
STEUER="$(tm new-window -d -t "=wb-Cgk:" -P -F '#{pane_id}')"
tm send-keys -t "$STEUER" \
  "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; POLL=2 COMPACT_SETTLE=1 ORCH_PCT=70 WARN_PCT=95 \
     ORCH_REARM_GAP=10 PROJECT='$TESTHOME' \
     context-guard '$ORCH'; } > $GLOG 2>&1 & echo \$! > $TESTHOME/guard.pid" Enter

warte_auf() {   # warte_auf <datei> <muster> <sekunden>
  local d=$((SECONDS + $3))
  until grep -qE "$2" "$1" 2>/dev/null; do
    [ $SECONDS -ge "$d" ] && return 1
    sleep 0.3
  done
  return 0
}

# Auf die Wache WARTEN, nicht schlafen: der Sentinel zaehlt nur, wenn er NACH
# GUARD_START geschrieben wurde. Bis dahin muss die Shell im Steuer-Pane
# hochkommen, die getippte Zeile lesen und context-guard bis zu seiner
# Startmeldung laufen -- unter Last (run-all --jobs 8, Lastdurchschnitt ueber
# 30) dauert das laenger als die festen 2 s, die hier bis zum 2026-09-05
# standen. Dann lag der touch VOR GUARD_START, die Wache meldete "ALTER
# Sentinel (16:51 < Guard-Start) -- ignoriert und entfernt" und tippte nie;
# A und B fielen mit 0x. Gemessen: einmal in fuenf Laeufen unter Last, einzeln
# nie. Die Zeile "context-guard: orchestrator=..." schreibt die Wache erst
# nach GUARD_START -- steht sie im Protokoll, ist der touch sicher juenger.
if warte_auf "$GLOG" "^context-guard: orchestrator=" 60; then
  ok "die Wache ist angelaufen (Startmeldung im Protokoll)"
else
  bad "die Wache hat nach 60 s keine Startmeldung geschrieben: $(tail -5 "$GLOG" 2>/dev/null)"
fi
GUARDPID="$(cat "$TESTHOME/guard.pid" 2>/dev/null || true)"

# 2026-09-10: der Sentinel ist jetzt session-eindeutig und zaehlt nur nach eigener
# Warnung -- die Warnzeile abwarten und den Pfad AUS ihr lesen (genau der Weg, den
# der Orchestrator im echten Betrieb geht), statt den alten geteilten Namen zu raten.
if warte_auf "$GLOG" "brain\+state update requested, warte auf " 30; then
  ok "die Warnzeile mit dem Sentinelpfad steht im Protokoll"
else
  bad "keine Warnzeile im Protokoll: $(tail -10 "$GLOG" 2>/dev/null)"
fi
SENTINEL_PATH="$(grep -oE 'warte auf .*$' "$GLOG" | tail -1 | sed 's/^warte auf //')"
[ -n "$SENTINEL_PATH" ] || bad "kein Sentinelpfad aus der Warnzeile extrahiert"

# Sentinel setzen -- jetzt sicher nach GUARD_START UND nach der eigenen Warnung
# dieses Guards (siehe oben).
touch "$SENTINEL_PATH"

echo "-- Sentinel gesetzt, warte auf die ersten Kompaktier-Versuche (mehrere Poll-Zyklen, POLL=2s) --"
if warte_auf "$GLOG" "Kompaktierbefehl an $ORCH NICHT verifiziert" 20; then
  ok "mindestens ein Versuch wurde unternommen und ehrlich als unverifiziert gemeldet"
else
  bad "kein 'NICHT verifiziert' im Protokoll: $(tail -20 "$GLOG" 2>/dev/null)"
fi

# Mehrere Poll-Zyklen abwarten (POLL=2s): ohne den Fix haette hier laengst ein
# zweiter und dritter Versuch stattgefunden. Zehn Sekunden = ~5 Zyklen.
sleep 10

kill "$GUARDPID" 2>/dev/null
sleep 1
if kill -0 "$GUARDPID" 2>/dev/null; then
  bad "Aufraeumen: Guard $GUARDPID laeuft noch"
  kill -9 "$GUARDPID" 2>/dev/null
fi
GUARDPID=""

echo
echo "-- A: der Kompaktierbefehl steht genau EINMAL in der (nie geleerten) Eingabezeile der Fake-TUI --"
PANEINHALT="$(tm capture-pane -p -t "$ORCH" 2>/dev/null)"
# 2026-09-10: der session-eindeutige Sentinelpfad im Text der Warnung macht die
# Eingabezeile ein paar Zeichen laenger als vorher -- an genau diesem Pane-Umbruch
# (120 Spalten) landet das Wort '/verdichte' mitten im automatischen Zeilenumbruch
# der Fake-TUI und zerfaellt in der Ausgabe von capture-pane in zwei Zeilen. Die
# Zaehlung entfernt darum die Umbrueche, bevor sie zaehlt -- der Pane selbst bricht
# weiterhin normal um, nur die Pruefung soll sich davon nicht taeuschen lassen.
N_TRIGGER=$(printf '%s' "$PANEINHALT" | tr -d '\n' | grep -o '/verdichte' | wc -l | tr -d ' ')
if [ "$N_TRIGGER" = "1" ]; then
  ok "A: '/verdichte' steht genau einmal in der Eingabezeile -- kein zweiter Versuch hat ihn nachgetippt"
else
  bad "A: '/verdichte' steht ${N_TRIGGER}x in der Eingabezeile (erwartet: 1) -- der Kompaktierbefehl wurde erneut getippt: $(printf '%s\n' "$PANEINHALT" | tail -6)"
fi

echo
echo "-- B: genau EINE 'NICHT verifiziert'-Zeile fuer $ORCH, nicht eine je Poll-Zyklus --"
N_UNVERIF=$(grep -c "Kompaktierbefehl an $ORCH NICHT verifiziert" "$GLOG" 2>/dev/null | tr -d ' ')
if [ "$N_UNVERIF" = "1" ]; then
  ok "B: genau eine 'NICHT verifiziert'-Zeile im Protokoll"
else
  bad "B: ${N_UNVERIF}x 'NICHT verifiziert' im Protokoll (erwartet: 1) -- die Wache hat trotz gescheiterter Verifikation erneut getippt"
fi

echo
echo "-- C: die Wache behauptet nie faelschlich Erfolg --"
if grep -qE "\-> /verdichte typed" "$GLOG" 2>/dev/null; then
  bad "C: '-> /verdichte typed' steht im Protokoll, obwohl die Fake-TUI nie verifiziert"
else
  ok "C: kein faelschliches '-> /verdichte typed' im Protokoll"
fi

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
