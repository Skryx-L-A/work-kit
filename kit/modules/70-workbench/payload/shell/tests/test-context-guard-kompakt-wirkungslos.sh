#!/usr/bin/env bash
# test-context-guard-kompakt-wirkungslos.sh -- eine Kompaktierung, die nichts
# befreit, darf den Zyklus nicht toeten.
#
# ANLASS (2026-08-28, gemessen an der companion-Session am Abend des 27.08.):
# Die Wache tippte um 23:18 den Kompaktierbefehl, die Last blieb danach bei rund
# 78 % -- viel dauerhaft gehaltenes Material, das eine Kompaktierung gar nicht
# anfassen kann. Damit galt der Zyklus als verbraucht. Das ist Absicht und bleibt
# es: nie zwei Kompaktierungen hintereinander, sonst wirft die zweite genau den
# Kontext weg, den die erste gerettet hat. Nur wird der Zyklus erst wieder scharf,
# wenn die Last unter mahnenAb minus Wiederscharf-Abstand faellt -- und diesen
# Abfall gibt es ohne wirksame Kompaktierung nie. Ein Patt: die Wache schwieg
# regelkonform, ein zweiter Sentinel wurde ignoriert, und von aussen sah das aus
# wie eine ruhige Wache.
#
# ZWEITER BEFUND, im selben Zug gemessen und hier mitgeprueft: `timeout` gehoert
# auf macOS nicht zum Grundsystem, es kommt aus Homebrews coreutils und liegt in
# /opt/homebrew/bin. Der Wrapper um jeden tmux-Aufruf rief es unbedingt auf. Fehlt
# es im PATH, scheitert damit JEDER tmux-Aufruf, socket_slug() liefert "unknown",
# und die Wache bricht schon beim Start ab. Zwoelf Suiten waren deshalb rot, und
# keine davon sagte, warum. Diese Suite faehrt bewusst mit schlankem PATH und
# prueft als Erstes, dass die Wache trotzdem anlaeuft.
#
# GEPRUEFT WIRD:
#   A  Die Wache laeuft ohne `timeout` im PATH an und sagt, dass sie die
#      Zeitschranke als Eigenbau faehrt.
#   B  Nach einer Kompaktierung, die die Last nur um zehn Punkte senkt (75 -> 85),
#      steht "Kompaktierung WIRKUNGSLOS" mit BEIDEN gemessenen Zahlen im Protokoll.
#   C  Nach der Karenz wird der Zyklus wieder freigegeben. Ohne das bliebe die
#      Wache bis zum Sessionende stumm.
#   D  Gegenprobe im zweiten Lauf: sinkt die Last wirklich (75 -> 10), steht dort
#      "Kompaktierung wirksam" und KEIN "WIRKUNGSLOS". Die Meldung haengt damit an
#      der Messung und nicht am blossen Tippen.
#
# ISOLATION: eigener Socket, eigenes HOME, eigene Registry -- wie die
# Schwestersuiten (Harness-Id "pi", erfundenes Kontextformat "KTX <n> %",
# Kompaktierbefehl "/verdichte").
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"
FAKE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fake-worker-swallow.py"

SOCKET="wbtest-cgwirk-$$"
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
      "id": "pi", "label": "Pruef-pi (Wirkungslos)", "command": "pi",
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

echo "== test-context-guard-kompakt-wirkungslos: eine Kompaktierung ohne Wirkung toetet den Zyklus nicht mehr =="
echo "   Socket: $SOCKET   HOME: $TESTHOME"
echo

# lauf <name> <pct-nachher> -- startet Fake-Orchestrator und Wache, setzt den Sentinel.
# Setzt $ORCH, $GLOG und $GUARDPID fuer die Zusagen danach.
lauf() {
  local name="$1" nachher="$2"
  tm kill-server 2>/dev/null
  tm new-session -d -s wb-Cgw -c /tmp -x 120 -y 30
  tm set-option -wg remain-on-exit on
  tmux_live_hooks_kappen "$SOCKET"
  : > "$TESTHOME/orch-enter-$name.log"
  # 2026-09-10: FAKE_PCT liegt jetzt zwischen dem Warn-Schwellenwert (ORCH_PCT=70) und
  # der Notbremse-Vorgabe (80, hier unveraendert) -- der Sentinel zaehlt seit dem Fix
  # erst NACH der eigenen Warnung dieses Guards, die Warnung muss also wirklich
  # ausgeloest werden, waehrend die Last selbst (75%) unter der Notbremse bleibt:
  # ausschliesslich der Sentinel-Weg soll hier fahren, nicht die Last.
  ORCH="$(tm new-window -d -t "=wb-Cgw:" -P -F '#{pane_id}' \
      "PATH='$PANE_PATH' FAKE_KIND=sofort FAKE_LOG='$TESTHOME/orch-enter-$name.log' FAKE_PCT=75 FAKE_PCT_NACH=$nachher FAKE_COMPACT_TRIGGER='/verdichte' pi" 2>/dev/null)"
  tm set -p -t "$ORCH" @wb_cmd "exec pi"
  sleep 2
  GLOG="$TESTHOME/guard-$name.log"
  STEUER="$(tm new-window -d -t "=wb-Cgw:" -P -F '#{pane_id}')"
  # POLL=2 und KOMPAKT_KARENZ_POLLS=1, damit die Suite nicht auf die Produktionswerte
  # (60 s, 2 Polls) warten muss. ORCH_PCT=70 loest die Warnung bei FAKE_PCT=75 aus, die
  # Notbremse-Vorgabe (80) bleibt darueber unerreicht -- ausschliesslich der Sentinel-
  # Weg soll fahren.
  tm send-keys -t "$STEUER" \
    "{ export PATH='$PANE_PATH' HOME='$TESTHOME'; POLL=2 COMPACT_SETTLE=1 ORCH_PCT=70 WARN_PCT=95 \
       ORCH_REARM_GAP=10 KOMPAKT_KARENZ_POLLS=1 KOMPAKT_WIRKUNG_MIN=10 PROJECT='$TESTHOME' \
       context-guard '$ORCH'; } > $GLOG 2>&1 & echo \$! > $TESTHOME/guard-$name.pid" Enter
  sleep 2
  GUARDPID="$(cat "$TESTHOME/guard-$name.pid" 2>/dev/null || true)"
  # Der Sentinel MUSS nach der eigenen Warnung dieses Guards entstehen (2026-09-10:
  # zaehlt seither nur noch dann), nicht nur nach seinem Start -- also auf die
  # Warnzeile warten und den session-eindeutigen Pfad AUS ihr lesen, statt den alten
  # geteilten Namen zu raten.
  local d=$((SECONDS + 20))
  until grep -qE "brain\+state update requested, warte auf " "$GLOG" 2>/dev/null; do
    [ $SECONDS -ge $d ] && break
    sleep 0.3
  done
  local sentinel_path
  sentinel_path="$(grep -oE 'warte auf .*$' "$GLOG" | tail -1 | sed 's/^warte auf //')"
  rm -f "$sentinel_path"
  sleep 1
  touch "$sentinel_path"
}

warte_auf() {   # warte_auf <datei> <muster> <sekunden>
  local d=$((SECONDS + $3))
  until grep -qE "$2" "$1" 2>/dev/null; do
    [ $SECONDS -ge "$d" ] && return 1
    sleep 0.3
  done
  return 0
}

echo "-- A: die Wache laeuft ohne 'timeout' im PATH an --"
case ":$PANE_PATH:" in
  *:/opt/homebrew/bin:*) bad "A: der Test-PATH enthaelt /opt/homebrew/bin -- dann prueft A nichts" ;;
  *) ok "A: der Test-PATH ist schlank (kein /opt/homebrew/bin), 'timeout' fehlt hier wirklich" ;;
esac

lauf wirkungslos 85
if warte_auf "$GLOG" "orchestrator=$ORCH" 20; then
  ok "A: die Wache ist angelaufen und meldet ihren Orchestrator-Pane"
else
  bad "A: die Wache ist nicht angelaufen: $(head -5 "$GLOG" 2>/dev/null)"
fi
if grep -q "weder 'timeout' noch 'gtimeout' im PATH" "$GLOG" 2>/dev/null; then
  ok "A: und sagt, dass sie die Zeitschranke als Eigenbau faehrt, statt still darauf zu verzichten"
else
  bad "A: kein Hinweis auf die Ersatz-Zeitschranke im Protokoll: $(head -3 "$GLOG" 2>/dev/null)"
fi

echo
echo "-- B: die wirkungslose Kompaktierung wird als solche benannt --"
if warte_auf "$GLOG" "Kompaktierung WIRKUNGSLOS" 90; then
  ok "B: 'Kompaktierung WIRKUNGSLOS' steht im Protokoll"
else
  bad "B: keine Meldung ueber die wirkungslose Kompaktierung: $(tail -8 "$GLOG" 2>/dev/null)"
fi
if grep -q "Last vorher 75%.*nachher 85%" "$GLOG" 2>/dev/null; then
  ok "B: mit BEIDEN gemessenen Zahlen (75 -> 85), nicht nur mit einem Urteil"
else
  bad "B: die Meldung nennt nicht beide Zahlen: $(grep -m1 WIRKUNGSLOS "$GLOG" 2>/dev/null)"
fi

echo
echo "-- C: nach der Karenz ist der Zyklus wieder frei --"
if warte_auf "$GLOG" "Karenz abgelaufen" 60; then
  ok "C: der Zyklus wurde nach der Karenz wieder freigegeben"
else
  bad "C: der Zyklus blieb tot -- genau der Patt vom 27.08.: $(tail -8 "$GLOG" 2>/dev/null)"
fi
kill "$GUARDPID" 2>/dev/null

echo
echo "-- D: Gegenprobe -- sinkt die Last wirklich, gilt die Kompaktierung als wirksam --"
lauf wirksam 10
if warte_auf "$GLOG" "Kompaktierung wirksam" 90; then
  ok "D: 'Kompaktierung wirksam' bei einem echten Abfall (75 -> 10)"
else
  bad "D: der wirksame Fall wurde nicht als solcher gemeldet: $(tail -8 "$GLOG" 2>/dev/null)"
fi
if grep -q "WIRKUNGSLOS" "$GLOG" 2>/dev/null; then
  bad "D: der wirksame Lauf wurde faelschlich als wirkungslos gemeldet"
else
  ok "D: und kein faelschliches 'WIRKUNGSLOS' -- die Meldung haengt an der Messung, nicht am Tippen"
fi
kill "$GUARDPID" 2>/dev/null

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
