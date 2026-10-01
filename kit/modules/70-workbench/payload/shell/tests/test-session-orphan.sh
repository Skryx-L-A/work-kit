#!/usr/bin/env bash
# Tests fuer wb-session-orphan — der Wachposten, der nach dem Schliessen eines
# VS-Code-Fensters entscheidet, ob dessen tmux-Session mitgeht.
#
# Anlass (2026-08-04): der Nutzer schloss drei Fenster, die Sessions liefen weiter,
# die Claude-Prozesse hielten 6,0 GB. Der schwierige Teil ist nicht das
# Schliessen, sondern das NICHT-Schliessen: VS Code deaktiviert die Extension
# beim Neuladen genauso wie beim Schliessen. Deshalb pruefen die ersten beiden
# Faelle hier genau diese Unterscheidung.
#
# Alles laeuft auf einem EIGENEN Socket (Regel: Tests fassen die Live-Umgebung
# nie an), das Marken-Verzeichnis liegt in einem temporaeren HOME, und
# WB_SESSION_CLOSE zeigt auf die Repo-Kopie statt auf ~/.local/bin.
unset TMUX TMUX_PANE
set -uo pipefail

SOCKET="wbtest-session-orphan-$$"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$SELF/lib-testwerkzeuge.sh"
CLOSE_TOOL="${WB_SESSION_CLOSE:-$SELF/../wb-session-close}"
ORPHAN_TOOL="${WB_SESSION_ORPHAN:-$SELF/../wb-session-orphan}"
echo "Geprueft: $CLOSE_TOOL, $ORPHAN_TOOL"
WORK="$(mktemp -d)"
ORPHAN_DIR="$WORK/orphans"
LOG="$WORK/orphan.log"
pass=0; fail=0

tm() { tmux -L "$SOCKET" "$@"; }
cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null
    sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$WORK"
}
trap cleanup EXIT

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

mkdir -p "$ORPHAN_DIR"

# Marke schreiben, wie die Extension sie beim Fensterschluss ablegt.
marke() { # marke <session> <token>
  printf '{"session":"%s","folder":"/tmp/projekt","token":"%s","at":%s}\n' \
    "$1" "$2" "$(( $(date +%s) * 1000 ))" > "$ORPHAN_DIR/$1.json"
}

# Der Wachposten wird aus einem Pane des TESTSERVERS gestartet, nie aus der
# Test-Shell: nur so redet er mit dem Testsocket und nicht mit dem Live-Server.
orphan() { # orphan <steuersession> <args...> -> setzt OUT und RC
  local steuer="$1"; shift
  local f="$WORK/out.$RANDOM"
  tm send-keys -t "$steuer:$WIN.$PANE" \
    "{ WB_SESSION_CLOSE='$CLOSE_TOOL' WB_ORPHAN_DIR='$ORPHAN_DIR' WB_SESSION_ORPHAN_LOG='$LOG' '$ORPHAN_TOOL' $* ; } > $f 2>&1; echo \"RC=\$?\" >> $f; touch $f.done" Enter
  if warte_auf_datei "$f.done" 30 "orphan: $*" "$f"; then
    OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
    RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  else
    OUT="(ZEITLIMIT -- siehe FAIL-Zeile oben)"; RC=124
  fi
  rm -f "$f" "$f.done"
}

echo "== wb-session-orphan =="
tm kill-server 2>/dev/null
tm new-session -d -s steuer -c /tmp
WIN="$(tm show-options -gv base-index 2>/dev/null || echo 0)"
PANE="$(tm show-window-options -gv pane-base-index 2>/dev/null || echo 0)"

echo "-- Reload: die Marke ist weg, die Session bleibt --"
# Das ist der Fall, an dem in der Nacht des 2026-08-04 eine laufende Unterhaltung
# verlorenging. Ein zurueckgekehrtes Fenster raeumt seine Marke ab; der Wachposten
# darf danach nichts mehr anfassen.
tm new-session -d -s wb-reload -c /tmp
rm -f "$ORPHAN_DIR/wb-reload.json"
orphan steuer --session wb-reload --token t1 --grace 0
if [ "$RC" -eq 0 ] && tm has-session -t "=wb-reload" 2>/dev/null; then
  ok "ohne Marke wird nichts geschlossen (Fenster ist zurueckgekommen)"
else
  bad "ohne Marke haette die Session leben muessen (rc=$RC): $OUT"
fi
grep -q "grund=marke-weg" "$LOG" 2>/dev/null \
  && ok "Grund steht im Log" || bad "Grund fehlt im Log"

echo "-- Fenster zu: Basis und gruppierte Sicht gehen zusammen --"
# Gruppierte Sessions teilen ihre Fenster: bliebe die '-view'-Schwester stehen,
# waere genau der Zustand wieder da, in dem drei der vier verwaisten Sessions
# vom 2026-08-04 steckten.
tm new-session -d -s wb-zu -c /tmp
tm new-session -d -t wb-zu -s wb-zu-view
marke wb-zu t2
orphan steuer --session wb-zu --token t2 --grace 0
if [ "$RC" -eq 0 ] \
   && ! tm has-session -t "=wb-zu" 2>/dev/null \
   && ! tm has-session -t "=wb-zu-view" 2>/dev/null; then
  ok "Basis und Sicht sind beide geschlossen"
else
  bad "Gruppe nicht vollstaendig geschlossen (rc=$RC): $OUT"
fi
[ -f "$ORPHAN_DIR/wb-zu.json" ] \
  && bad "Marke haette nach dem Schliessen verschwinden muessen" \
  || ok "Marke ist nach dem Schliessen weg"

echo "-- laufender Worker: wird gemeldet, nicht geschlossen --"
tm new-session -d -s wb-arbeit -c /tmp
tm set-option -p -t "wb-arbeit:$WIN.$PANE" @wb_role worker 2>/dev/null
marke wb-arbeit t3
orphan steuer --session wb-arbeit --token t3 --grace 0
if tm has-session -t "=wb-arbeit" 2>/dev/null; then
  ok "Session mit laufendem Worker bleibt offen"
else
  bad "Session mit laufendem Worker wurde geschlossen"
fi
if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "NICHT geschlossen"; then
  ok "die Verweigerung wird sichtbar gemeldet"
else
  bad "Verweigerung nicht gemeldet (rc=$RC): $OUT"
fi
[ -f "$ORPHAN_DIR/wb-arbeit.json" ] \
  && ok "Marke bleibt liegen, damit wb-session-sweep sie spaeter aufgreift" \
  || bad "Marke wurde trotz Verweigerung entfernt"

echo "-- ueberholter Wachposten haelt sich heraus --"
# Fenster zu, wieder auf, wieder zu: in der Marke steht dann das Kennzeichen des
# juengeren Wachpostens, und der aeltere darf nichts mehr tun.
tm new-session -d -s wb-neu -c /tmp
marke wb-neu tNEU
orphan steuer --session wb-neu --token tALT --grace 0
if [ "$RC" -eq 0 ] && tm has-session -t "=wb-neu" 2>/dev/null; then
  ok "der aeltere Wachposten laesst die Session in Ruhe"
else
  bad "aelterer Wachposten haette nichts tun duerfen (rc=$RC): $OUT"
fi

echo "-- Session gibt es nicht mehr: Marke wird aufgeraeumt --"
marke wb-fort t5
orphan steuer --session wb-fort --token t5 --grace 0
if [ "$RC" -eq 0 ] && [ ! -f "$ORPHAN_DIR/wb-fort.json" ]; then
  ok "verwaiste Marke ohne Session wird entfernt"
else
  bad "Marke ohne Session blieb liegen (rc=$RC)"
fi

echo
printf '%s bestanden, %s fehlgeschlagen\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
