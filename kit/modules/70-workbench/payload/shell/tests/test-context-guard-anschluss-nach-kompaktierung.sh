#!/usr/bin/env bash
# test-context-guard-anschluss-nach-kompaktierung.sh -- der Anschluss nach dem
# Kompaktieren eines WORKERS kommt zuverlaessig, auch wenn die Kompaktierung selbst
# im selben Sekundenfenster nicht verifiziert werden konnte.
#
# ANLASS (2026-09-03, 20:18-20:52, Worker 'neubau', Pane %138): die Wache forderte
# die Uebergabe an, der Worker schrieb und committete sie, dann tippte die Wache
# den Kompaktierbefehl -- und meldete "Kompaktierbefehl an %138 NICHT verifiziert --
# Text stand nach Enter noch in der Eingabezeile. Lieber einmal ungesendet gemeldet
# als zweimal gesendet: KEIN erneuter Versuch". Der Pane steckte in dem Moment
# mitten in einem fremden Zug (Claude Code zeigt dann "Press up to edit queued
# messages"); der Befehl war in Wahrheit ANGENOMMEN, lief spaeter durch (Anzeige
# 0/1.0M), aber niemand tippte danach den Anschluss -- die alte Kette sandte
# WEITERARBEITEN nur, wenn genau DIESER eine Sende-Check im selben Moment
# erfolgreich war. Der Orchestrator musste 35 Minuten spaeter von Hand eingreifen.
#
# GEPRUEFT WIRD, mit einer echten Claude-Code-Statuszeile ('820k/1.0M', Quelle 1
# aus read_load()) statt des erfundenen Registry-Formats der Schwestertests -- die
# Wache faellt ohne eigene Registry-Eintragung auf ihren eingebauten Kompaktierbefehl
# '/compact' zurueck, genau wie im echten Vorfall:
#
#   A "zug"    Der Kompaktierbefehl trifft einen Pane, der gerade in einem fremden
#              Zug steckt (Spinner + 'esc to interrupt' sichtbar, Eingabezeile zeigt
#              im selben Sekundenfenster noch den Text). Die Wache darf das NICHT
#              als 'NICHT verifiziert' werten (Fix in absenden_verifizieren()) und
#              muss anschliessend trotzdem, sobald die Auslastung faellt UND der
#              Pane idle ist, den Anschluss tippen.
#   B "spaet"  Der Kompaktierbefehl wirkt scheinbar UEBERHAUPT nicht (kein Zug
#              sichtbar, Text haengt) -- die Wache MUSS hier ehrlich 'NICHT
#              verifiziert' melden (das ist keine Regression). Der Befehl wirkt
#              trotzdem, verzoegert -- das ist der Kern des Vorfalls: der Anschluss
#              muss trotz der (richtigen!) 'NICHT verifiziert'-Meldung noch kommen,
#              ueber den neuen, auf Platte gemerkten Anschluss-Mechanismus.
#   C "ohne"   Verschwindet die Uebergabedatei, bevor die Anschluss-Bedingungen
#              eintreten, wird NICHTS getippt, und die Wache sagt das auch so.
#   D          Nach einem Neustart der Wache wird kein zweiter Anschluss getippt --
#              weder fuer A noch fuer B (Merker ist bereits verbraucht).
#
# ISOLATION: eigener Socket, eigenes HOME -- wie die Schwestertests. Bewusst OHNE
# eigene Registry (siehe fake-claude-anschluss.py): die Wache soll ihren normalen
# Vorgabeweg fuer einen unbekannten Harness nehmen ('/compact'), nicht einen
# Testpfad.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"
FAKE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fake-claude-anschluss.py"

SOCKET="wbtest-cganschl-$$"
TESTHOME="$(mktemp -d)"

# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$TESTHOME" || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
BIN="$TESTHOME/.local/bin"
SHIM="$TESTHOME/.shim"
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

PROJECT_DIR="$TESTHOME/project"
mkdir -p "$BIN" "$SHIM" "$TESTHOME/.local/state" "$TESTHOME/.pi-workers/results" "$PROJECT_DIR"
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

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"

echo "== test-context-guard-anschluss-nach-kompaktierung: der Anschluss kommt auch nach einer unverifizierten Kompaktierung =="
echo "   Socket: $SOCKET   HOME: $TESTHOME"
echo

tm kill-server 2>/dev/null
tm new-session -d -s wb-Cga -c "$PROJECT_DIR" -x 140 -y 30
tm set-option -wg remain-on-exit on
tmux_live_hooks_kappen "$SOCKET"

STEUER="$(tm new-window -d -t "=wb-Cga:" -P -F '#{pane_id}')"
# Eigener, inerter Anker-Pane fuer die Orchestrator-Rolle des Guards (2026-09-03):
# dieser Test prueft nur den WORKER-Anschluss, keine Orchestrator-Logik. Ein leerer
# interaktiver Pane bleibt fuer die Wache dauerhaft BLIND und damit unangetastet --
# einen der drei Worker-Panes als Orchestrator-Anker zu missbrauchen wuerde beide
# Rollenzweige auf demselben Pane gegeneinander laufen lassen.
ORCH_ANKER="$(tm new-window -d -t "=wb-Cga:" -P -F '#{pane_id}')"

LOG_ZUG="$TESTHOME/enter-zug.log"; : > "$LOG_ZUG"
LOG_SPAET="$TESTHOME/enter-spaet.log"; : > "$LOG_SPAET"
LOG_OHNE="$TESTHOME/enter-ohne.log"; : > "$LOG_OHNE"

neuer_worker() {   # <fake-kind> <log> <busy-sek> -> setzt PANE_ID
  local kind="$1" log="$2" busy="$3"
  PANE_ID="$(tm new-window -d -t "=wb-Cga:" -c "$PROJECT_DIR" -P -F '#{pane_id}' \
      "PATH='$PANE_PATH' FAKE_KIND='$kind' FAKE_LOG='$log' FAKE_PCT=82 FAKE_PCT_NACH=5 FAKE_BUSY=$busy FAKE_SPAET=$busy python3 '$FAKE'" 2>/dev/null)"
}
neuer_worker zug   "$LOG_ZUG"   3; WORKER_ZUG="$PANE_ID"
neuer_worker spaet "$LOG_SPAET" 3; WORKER_SPAET="$PANE_ID"
neuer_worker zug   "$LOG_OHNE"  8; WORKER_OHNE="$PANE_ID"   # laenger busy -> Zeit, die Uebergabe wegzunehmen
sleep 2

GLOG="$TESTHOME/guard.log"
start_guard() {
  tm send-keys -t "$STEUER" \
    "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; POLL=2 ORCH_PCT=95 WARN_PCT=50 \
       ORCH_REARM_GAP=10 WORKER_REARM_GAP=10 PROJECT='$PROJECT_DIR' \
       context-guard '$ORCH_ANKER' '$WORKER_ZUG:wzug' '$WORKER_SPAET:wspaet' '$WORKER_OHNE:wohne'; } >> $GLOG 2>&1 & echo \$! > $TESTHOME/guard.pid" Enter
  sleep 2
  GUARDPID="$(cat "$TESTHOME/guard.pid" 2>/dev/null || true)"
}
: > "$GLOG"
start_guard

warte_auf() {   # warte_auf <datei> <muster> <sekunden>
  local d=$((SECONDS + $3))
  until grep -qE "$2" "$1" 2>/dev/null; do
    [ $SECONDS -ge "$d" ] && return 1
    sleep 0.3
  done
  return 0
}

echo "-- Vorbereitung: alle drei Worker bekommen ihre Handoff-Anfrage, wir schreiben die Uebergabe --"
for pair in "wzug:$WORKER_ZUG" "wspaet:$WORKER_SPAET" "wohne:$WORKER_OHNE"; do
  name="${pair%%:*}"; pane="${pair##*:}"
  if warte_auf "$GLOG" "$name \($pane\) at 82% -> handoff requested" 20; then
    ok "Vorbereitung: Handoff-Anfrage fuer $name kam an"
  else
    bad "Vorbereitung: keine Handoff-Anfrage fuer $name: $(tail -15 "$GLOG" 2>/dev/null)"
  fi
  printf 'Uebergabe (Test) fuer %s\n' "$name" > "$PROJECT_DIR/HANDOFF-$name.md"
done

echo
echo "-- A: 'zug' -- ein sichtbarer Zug gilt als angenommen, kein falsches 'NICHT verifiziert' --"
if warte_auf "$GLOG" "wzug \($WORKER_ZUG\) -> /compact typed \(handoff persisted\)" 20; then
  ok "A1: der Kompaktierbefehl gilt als verifiziert getippt, trotz sichtbaren Zugs im selben Sekundenfenster"
else
  bad "A1: kein '/compact typed' fuer wzug -- der Zug wurde nicht als Beleg gewertet: $(tail -20 "$GLOG" 2>/dev/null)"
fi
if grep -qE "Kompaktierbefehl an $WORKER_ZUG NICHT verifiziert" "$GLOG" 2>/dev/null; then
  bad "A1: faelschlich 'NICHT verifiziert' fuer wzug -- der sichtbare Zug haette das verhindern muessen"
else
  ok "A1: kein faelschliches 'NICHT verifiziert' fuer wzug"
fi
if warte_auf "$GLOG" "wzug \($WORKER_ZUG\) -> resumed \(Anschluss nach Kompaktierung" 30; then
  ok "A2: der Anschluss kam -- die Kette handoff -> kompaktieren -> Anschluss ist vollstaendig durchgelaufen"
else
  bad "A2: kein Anschluss fuer wzug: $(tail -25 "$GLOG" 2>/dev/null)"
fi
if grep -qF "HANDOFF-wzug.md" "$GLOG" 2>/dev/null; then
  ok "A2: das Protokoll nennt die Uebergabedatei im Anschluss-Kontext"
else
  bad "A2: die Uebergabedatei fehlt im Protokoll"
fi

echo
echo "-- B: 'spaet' -- ehrliches 'NICHT verifiziert', der Anschluss kommt trotzdem --"
if warte_auf "$GLOG" "Kompaktierbefehl an $WORKER_SPAET NICHT verifiziert" 20; then
  ok "B1: die Wache meldet ehrlich 'NICHT verifiziert' -- hier haengt wirklich nichts an einem Zug"
else
  bad "B1: keine 'NICHT verifiziert'-Zeile fuer wspaet: $(tail -20 "$GLOG" 2>/dev/null)"
fi
if grep -qE "wspaet \($WORKER_SPAET\) -> /compact typed" "$GLOG" 2>/dev/null; then
  bad "B1: '/compact typed' steht faelschlich im Protokoll fuer wspaet"
else
  ok "B1: kein faelschliches '/compact typed' fuer wspaet"
fi
if warte_auf "$GLOG" "wspaet \($WORKER_SPAET\) -> resumed \(Anschluss nach Kompaktierung" 30; then
  ok "B2: DAS ist die behobene Regression -- der Anschluss kommt, obwohl die Kompaktierung selbst nie verifiziert werden konnte"
else
  bad "B2: kein Anschluss fuer wspaet -- genau der Vorfall vom 2026-09-03 waere hier reproduziert: $(tail -25 "$GLOG" 2>/dev/null)"
fi

echo
echo "-- C: 'ohne' -- die Uebergabe verschwindet, bevor der Anschluss faellig wird --"
if warte_auf "$GLOG" "wohne \($WORKER_OHNE\) -> /compact typed \(handoff persisted\)" 20; then
  ok "C1: der Kompaktierbefehl fuer wohne wurde getippt"
  rm -f "$PROJECT_DIR/HANDOFF-wohne.md"
  ok "C1: die Uebergabedatei wurde entfernt, bevor die Auslastung faellt (FAKE_BUSY=8s Vorsprung)"
else
  bad "C1: kein '/compact typed' fuer wohne: $(tail -25 "$GLOG" 2>/dev/null)"
fi
if warte_auf "$GLOG" "wohne \($WORKER_OHNE\): kein Anschluss getippt" 30; then
  ok "C2: die Wache meldet ehrlich, dass keine Uebergabedatei mehr da ist, und tippt nichts"
else
  bad "C2: keine 'kein Anschluss getippt'-Zeile fuer wohne: $(tail -25 "$GLOG" 2>/dev/null)"
fi
if grep -qE "wohne \($WORKER_OHNE\) -> resumed" "$GLOG" 2>/dev/null; then
  bad "C2: 'resumed' steht dennoch im Protokoll fuer wohne -- es haette nichts getippt werden duerfen"
else
  ok "C2: kein 'resumed' fuer wohne"
fi

echo
echo "-- D: Neustart der Wache -- kein zweiter Anschluss fuer wzug/wspaet --"
kill "$GUARDPID" 2>/dev/null
deadline=$((SECONDS + 10))
while [ $SECONDS -lt $deadline ] && kill -0 "$GUARDPID" 2>/dev/null; do sleep 0.3; done
if kill -0 "$GUARDPID" 2>/dev/null; then
  bad "D0: der alte Guard-Prozess $GUARDPID lebt noch -- Neustart nicht sauber moeglich"
  kill -9 "$GUARDPID" 2>/dev/null
  sleep 1
fi
start_guard
sleep 12   # mehrere Poll-Zyklen (POLL=2s) nach dem Neustart

N_ZUG=$(grep -cE "wzug \($WORKER_ZUG\) -> resumed \(Anschluss nach Kompaktierung" "$GLOG" 2>/dev/null | tr -d ' ')
[ "$N_ZUG" = "1" ] \
  && ok "D1: weiterhin genau EIN Anschluss fuer wzug, auch nach dem Neustart der Wache" \
  || bad "D1: ${N_ZUG}x Anschluss fuer wzug im Protokoll (erwartet: 1)"
N_SPAET=$(grep -cE "wspaet \($WORKER_SPAET\) -> resumed \(Anschluss nach Kompaktierung" "$GLOG" 2>/dev/null | tr -d ' ')
[ "$N_SPAET" = "1" ] \
  && ok "D2: weiterhin genau EIN Anschluss fuer wspaet, auch nach dem Neustart der Wache" \
  || bad "D2: ${N_SPAET}x Anschluss fuer wspaet im Protokoll (erwartet: 1)"

kill "$GUARDPID" 2>/dev/null
sleep 1
if kill -0 "$GUARDPID" 2>/dev/null; then
  bad "Aufraeumen: Guard $GUARDPID laeuft noch"
  kill -9 "$GUARDPID" 2>/dev/null
fi
GUARDPID=""

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
