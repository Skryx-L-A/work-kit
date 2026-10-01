#!/usr/bin/env bash
# test-context-guard-waise.sh -- zwei Befunde vom 2026-08-07, beide an der Frage
# "welcher Guard laeuft eigentlich wofuer".
#
# Punkt 1 -- Erkennung ueber den Pane-NAMEN allein.
#   `--ensure` suchte in `ps` nach einem Guard, dessen Kommandozeile den gesuchten Pane-Namen
#   traegt -- ueber ALLE Prozesse der Maschine. Pane-Namen sind aber nur pro tmux-SERVER
#   eindeutig; jeder frische Socket faengt wieder bei %0 an. Folge: ein Guard auf einem fremden
#   Socket (z. B. aus einer Testsuite) liess `--ensure` auf dem Live-Server "laeuft bereits"
#   melden, und dort startete KEINER -- der Orchestrator stand ohne Kontextwache da, waehrend
#   die Meldung ihm sagte, alles sei in Ordnung. Hier nachgestellt mit zwei Servern nebeneinander,
#   auf beiden ein Pane mit demselben Namen.
#
# Punkt 2 -- Waisen-Guards.
#   Heute frueh liefen zwei Wachen fuer Panes, die es nicht mehr gab. Gemessen an den laufenden
#   Prozessen und ihren Logs: gestartet als schlichtes `--auto <pane>` (die Zeile aus
#   regeln/kontext-guard.md), also ganz ohne Abbruchbedingung; und selbst mit
#   `--exit-when-session-gone` waere die haeufigste Variante durchgerutscht, weil die SESSION den
#   Pane ueberlebt (Log wb-AI: 00:47 orchestrator=%0, 07:41 orchestrator=%26, dieselbe Session).
#   Geprueft wird deshalb der Pane, nicht die Session -- und zwar mit Frist, nicht unbegrenzt.
#
# SICHERHEIT (regeln/tests-und-eingriffe.md): eigene tmux-Sockets mit PID im Namen, eigenes HOME,
# eigene Sessionnamen ('wb-WA-…'). Der PRUEFLING wird an den jeweiligen Testsocket GEBUNDEN, nicht
# nur der Test selbst -- context-guard ruft `tmux` an ueber 30 Stellen intern auf, und eine
# Shell-Funktion gilt im Kindprozess nicht. Der Weg ist derselbe wie in
# test-guard-sessionende.sh: ein `tmux`-Schirm ganz vorn im PATH, hier EINER JE SERVER, und
# context-guard immer ueber den ABSOLUTEN Pfad. `trap` raeumt beide Server, beide Guards und das
# Verzeichnis auf, auch bei Abbruch.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTEXT_GUARD_SRC="${CONTEXT_GUARD:-$REPO/context-guard}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

SOCKET_A="wbtest-waise-a-$$"
SOCKET_B="wbtest-waise-b-$$"
TESTHOME="$(mktemp -d)"

# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$TESTHOME" wb-pane-write wb-mensch \
  || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
BIN="$TESTHOME/.local/bin"

pass=0; fail=0
GUARD_PIDS=()   # jede von diesem Test gestartete Guard-PID -- verifiziert beendet, nicht angenommen

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
note() { printf '  hinweis %s\n' "$1"; }

cleanup() {
  local s p noch_da="" deadline
  for p in "${GUARD_PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    kill -0 "$p" 2>/dev/null && kill "$p" 2>/dev/null
  done
  for s in "$SOCKET_A" "$SOCKET_B"; do
    tmux_socket_beenden_ohne_reste "$s"
    deadline=$((SECONDS + 5))
    while [ $SECONDS -lt $deadline ] && tmux -L "$s" list-sessions >/dev/null 2>&1; do
      tmux -L "$s" kill-server 2>/dev/null
      sleep 0.3
    done
    tmux -L "$s" list-sessions >/dev/null 2>&1 \
      && echo "WARNUNG: tmux-Server auf Socket '$s' laeuft noch" >&2
    rm -f "/private/tmp/tmux-$(id -u)/$s" "/tmp/tmux-$(id -u)/$s"
  done
  sleep 0.5
  for p in "${GUARD_PIDS[@]:-}"; do
    [ -n "$p" ] || continue
    kill -0 "$p" 2>/dev/null && noch_da="$noch_da $p"
  done
  [ -n "$noch_da" ] && echo "WARNUNG: Guard-PID(s)$noch_da laufen nach dem Aufraeumen noch" >&2
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

guard_gemerkt() {   # <pid> -> merkt eine Guard-PID genau einmal
  local neu="$1" p
  [ -n "$neu" ] || return 0
  for p in "${GUARD_PIDS[@]:-}"; do [ "$p" = "$neu" ] && return 0; done
  GUARD_PIDS+=("$neu")
}

[ -x "$CONTEXT_GUARD_SRC" ] || { echo "FAIL  context-guard nicht gefunden/ausfuehrbar: $CONTEXT_GUARD_SRC"; exit 1; }

mkdir -p "$BIN" "$TESTHOME/.claude/workbench/sessions" "$TESTHOME/.local/state"
# ERST den Symlink aus werkzeuge_installieren entfernen, DANN kopieren: ein `cp` auf einen
# Symlink schreibt durch ihn hindurch und wuerde bei CONTEXT_GUARD=<andere Fassung> die Datei
# im Arbeitsbaum ueberschreiben.
rm -f "$BIN/context-guard"
cp "$CONTEXT_GUARD_SRC" "$BIN/context-guard"
chmod +x "$BIN/context-guard"
# wb-state ruft context-guard ueber den HARTKODIERTEN Pfad $HOME/.local/bin/wb-state auf;
# die echte, unveraenderte Kopie reicht (sie liest nur Schwellen, die hier auf ihren Defaults
# bleiben).
cp "$HOME/.local/bin/wb-state" "$BIN/wb-state" 2>/dev/null && chmod +x "$BIN/wb-state"

GUARD="$BIN/context-guard"   # IMMER absolut aufrufen, siehe Kopfkommentar

schirm() {   # <socket> -> Pfad eines PATH-Verzeichnisses, dessen `tmux` auf diesen Socket zwingt
  local s="$1" d="$TESTHOME/.shim-$1"
  mkdir -p "$d"
  cat > "$d/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$s" "\$@"
SHIMEOF
  chmod +x "$d/tmux"
  printf '%s' "$d"
}
SHIM_A="$(schirm "$SOCKET_A")"
SHIM_B="$(schirm "$SOCKET_B")"

export HOME="$TESTHOME"
PATH_A="$SHIM_A:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"
PATH_B="$SHIM_B:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"

tma() { tmux -L "$SOCKET_A" "$@"; }
tmb() { tmux -L "$SOCKET_B" "$@"; }

# Kommando in der STEUER-Pane des jeweiligen Testservers ausfuehren (nie aus dieser Shell heraus):
# nur dort zeigt $TMUX auf den Testsocket, und context-guards eigene tmux-Aufrufe laufen ueber den
# PATH-Schirm dieses Servers.
lauf() {   # lauf <socket> <path> <kommando> -> setzt OUT und RC
  local sock="$1" pfad="$2" cmd="$3" f="$TESTHOME/out.$RANDOM$RANDOM"
  tmux -L "$sock" send-keys -t ctrl \
    "{ export PATH='$pfad' HOME='$TESTHOME'; $cmd ; } > $f 2>&1; echo \"RC=\$?\" >> $f; touch $f.done" Enter
  if warte_auf_datei "$f.done" 30 "lauf: $cmd" "$f"; then
    OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
    RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  else
    OUT="(ZEITLIMIT -- siehe FAIL-Zeile oben)"; RC=124
  fi
  rm -f "$f" "$f.done"
}

wait_gone() {   # <pid> <timeout> -> 0, wenn der Prozess verschwindet; setzt ELAPSED
  local pid="$1" timeout="$2" start=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    if (( SECONDS - start >= timeout )); then ELAPSED=$((SECONDS-start)); return 1; fi
    sleep 0.5
  done
  ELAPSED=$((SECONDS-start))
  return 0
}

echo "== context-guard: Erkennung je tmux-Server, und keine Waisen =="

# Beide Server in DERSELBEN Reihenfolge aufbauen: Pane-IDs sind ein Zaehler je Server und fangen
# bei %0 an, die Orchestrator-Panes tragen damit auf beiden Servern denselben Namen. Genau diese
# Gleichheit ist der Befund -- sie wird geprueft, nicht angenommen.
tma kill-server 2>/dev/null; tmb kill-server 2>/dev/null
tma new-session -d -s ctrl -c /tmp
tmb new-session -d -s ctrl -c /tmp
# ~/.tmux.conf ist keine Isolationsgrenze -- pane-died band echtes wb-autorevive an
# jeden Testserver, das haette gegen den hier absichtlich herbeigefuehrten Pane-Tod gearbeitet.
tmux_live_hooks_kappen "$SOCKET_A"
tmux_live_hooks_kappen "$SOCKET_B"
tma new-session -d -s wb-WA-eins -c /tmp
tmb new-session -d -s wb-WA-eins -c /tmp
PANE_A="$(tma list-panes -t '=wb-WA-eins' -F '#{pane_id}' | head -1)"
PANE_B="$(tmb list-panes -t '=wb-WA-eins' -F '#{pane_id}' | head -1)"
tma set -p -t "$PANE_A" @wb_role orchestrator
tmb set -p -t "$PANE_B" @wb_role orchestrator

echo "-- Punkt 1: derselbe Pane-Name auf zwei Servern --"
if [ -n "$PANE_A" ] && [ "$PANE_A" = "$PANE_B" ]; then
  ok "beide Server haben einen Orchestrator-Pane namens $PANE_A -- der Befund ist hergestellt"
else
  bad "Pane-Namen unterscheiden sich (A=$PANE_A B=$PANE_B) -- ohne Namensgleichheit prueft dieser Punkt nichts"
fi

lauf "$SOCKET_A" "$PATH_A" "POLL=3 '$GUARD' --ensure '$PANE_A'"
printf '%s\n' "$OUT" | grep -qF "gestartet fuer" \
  && ok "Server A: --ensure hat einen Guard gestartet" \
  || bad "Server A: --ensure hat keinen Guard gestartet: $OUT"
PID_A="$(printf '%s\n' "$OUT" | sed -n 's/.*PID \([0-9][0-9]*\).*/\1/p' | head -1)"
guard_gemerkt "$PID_A"
[ -n "$PID_A" ] && kill -0 "$PID_A" 2>/dev/null \
  && ok "Server A: Guard laeuft (PID $PID_A)" \
  || bad "Server A: kein lebender Guard-Prozess nach --ensure"

# Der Kern: auf Server B laeuft KEIN Guard, obwohl der Pane genauso heisst. Vor der Aenderung
# meldete --ensure hier "laeuft bereits" und startete nichts -- diese Session blieb unbewacht.
lauf "$SOCKET_B" "$PATH_B" "POLL=3 '$GUARD' --ensure '$PANE_B'"
PID_B="$(printf '%s\n' "$OUT" | sed -n 's/.*PID \([0-9][0-9]*\).*/\1/p' | head -1)"
if printf '%s\n' "$OUT" | grep -qF "gestartet fuer"; then
  guard_gemerkt "$PID_B"
  ok "Server B: --ensure startet trotz gleichnamigem Pane auf Server A einen eigenen Guard"
else
  bad "Server B: --ensure hat KEINEN Guard gestartet -- der Guard auf dem fremden Socket hat ihn blockiert: $OUT"
fi
[ -n "$PID_B" ] && [ "$PID_B" != "$PID_A" ] && kill -0 "$PID_B" 2>/dev/null \
  && ok "Server B: eigener, zweiter Guard-Prozess laeuft (PID $PID_B, A war $PID_A)" \
  || bad "Server B: kein eigener lebender Guard (PID_B='$PID_B', PID_A='$PID_A')"

# Gegenprobe in der anderen Richtung: die Erkennung darf ihren EIGENEN Guard nicht verlieren,
# sonst waere sie mit lauter Doppelstartern erkauft.
lauf "$SOCKET_A" "$PATH_A" "'$GUARD' --ensure '$PANE_A'"
printf '%s\n' "$OUT" | grep -qF "laeuft bereits fuer $PANE_A" \
  && ok "Server A: der zweite --ensure-Aufruf erkennt den eigenen laufenden Guard" \
  || bad "Server A: der eigene laufende Guard wurde nicht erkannt, es waere ein zweiter entstanden: $OUT"
printf '%s\n' "$OUT" | grep -qF "gestartet fuer" \
  && guard_gemerkt "$(printf '%s\n' "$OUT" | sed -n 's/.*PID \([0-9][0-9]*\).*/\1/p' | head -1)"

ANZ_PID_DATEIEN="$(ls "$TESTHOME/.local/state/wb-context-guard/"*.pid 2>/dev/null | wc -l | tr -d ' ')"
[ "$ANZ_PID_DATEIEN" -ge 2 ] \
  && ok "zwei getrennte Merkdateien, eine je Server ($ANZ_PID_DATEIEN insgesamt)" \
  || bad "erwartet wurden mindestens zwei Merkdateien (eine je Server), gefunden: $ANZ_PID_DATEIEN"

# Server B wird nicht mehr gebraucht -- sein Guard geht mit der Session (Punkt 2 gilt auch hier).
tmux_socket_beenden_ohne_reste "$SOCKET_B"

echo "-- Punkt 2: Pane weg, Session lebt weiter -- der Guard darf keine Waise werden --"
# Genau die gemessene Lage: die Session ueberlebt ihren Orchestrator-Pane (zweites Fenster), und
# der Guard laeuft als schlichtes `--auto`, ohne jede Abbruchbedingung -- die Startzeile aus
# regeln/kontext-guard.md, mit der beide Waisen von heute frueh gestartet worden waren.
tma new-session -d -s wb-WA-waise -c /tmp
PANE_W="$(tma list-panes -t '=wb-WA-waise' -F '#{pane_id}' | head -1)"
tma set -p -t "$PANE_W" @wb_role orchestrator
tma new-window -t '=wb-WA-waise' -c /tmp     # haelt die Session am Leben, wenn der Pane faellt
POLL_W=2
lauf "$SOCKET_A" "$PATH_A" "POLL=$POLL_W nohup '$GUARD' --auto '$PANE_W' >'$TESTHOME/waise.log' 2>&1 & echo PID=\$!"
PID_W="$(printf '%s\n' "$OUT" | sed -n 's/^PID=//p')"
guard_gemerkt "$PID_W"
if [ -n "$PID_W" ] && kill -0 "$PID_W" 2>/dev/null; then
  ok "Guard fuer $PANE_W gestartet (PID $PID_W, POLL=${POLL_W}s, ohne jedes Exit-Flag)"
  sleep 1   # sicherstellen, dass er im Poll-Schlaf steckt, nicht mitten im Start
  START_KILL=$SECONDS
  tma kill-pane -t "$PANE_W" 2>/dev/null
  tma has-session -t '=wb-WA-waise' 2>/dev/null \
    && ok "die Session lebt nach dem Entfernen des Panes weiter -- genau die gemessene Lage" \
    || bad "die Session ist mitgestorben; dann prueft dieser Punkt die Session, nicht den Pane"
  FRIST=$(( POLL_W * 2 + 10 ))
  if wait_gone "$PID_W" "$FRIST"; then
    ok "Guard beendet sich ${ELAPSED}s nach dem Verschwinden seines Panes (Frist ${FRIST}s)"
  else
    bad "Guard laeuft ${ELAPSED}s nach dem Verschwinden seines Panes noch -- Waise (Frist ${FRIST}s)"
  fi
  WAISE_PID_DATEI="$(ls "$TESTHOME/.local/state/wb-context-guard/"*wb-WA-waise.pid 2>/dev/null | wc -l | tr -d ' ')"
  [ "$WAISE_PID_DATEI" = "0" ] \
    && ok "der Guard hat seine Merkdatei beim Ende wieder entfernt" \
    || bad "die Merkdatei des beendeten Guards steht noch ($WAISE_PID_DATEI Stueck) -- ein spaeteres --ensure muesste sie als tot erkennen"
  grep -qF "existiert nicht mehr" "$TESTHOME/waise.log" \
    && ok "das Ende steht im Protokoll: $(grep -F 'existiert nicht mehr' "$TESTHOME/waise.log" | tail -1)" \
    || bad "im Protokoll steht keine Zeile ueber das Ende: $(tail -3 "$TESTHOME/waise.log" 2>/dev/null | tr '\n' ' ')"
else
  bad "Vorbereitung fuer Punkt 2 fehlgeschlagen: kein Guard gestartet ($OUT)"
fi
tma kill-session -t '=wb-WA-waise' 2>/dev/null

echo "-- Punkt 3: ein TOTER Pane zaehlt als da (wb-revive belebt ihn unter derselben ID wieder) --"
# Die Gegenrichtung zu Punkt 2, und der Grund fuer die Unterscheidung: `wb-revive`/`wb-autorevive`
# rufen `respawn-pane -k` auf, der Pane behaelt seine ID. Ein Guard, der beim Absturz geht, laesst
# den wiederbelebten Orchestrator unbewacht zurueck.
tma new-session -d -s wb-WA-tot -c /tmp
PANE_T="$(tma list-panes -t '=wb-WA-tot' -F '#{pane_id}' | head -1)"
tma set -p -t "$PANE_T" @wb_role orchestrator
tma set -p -t "$PANE_T" remain-on-exit on
POLL_T=2
lauf "$SOCKET_A" "$PATH_A" "POLL=$POLL_T nohup '$GUARD' --auto '$PANE_T' >'$TESTHOME/tot.log' 2>&1 & echo PID=\$!"
PID_TP="$(printf '%s\n' "$OUT" | sed -n 's/^PID=//p')"
guard_gemerkt "$PID_TP"
if [ -n "$PID_TP" ] && kill -0 "$PID_TP" 2>/dev/null; then
  tma send-keys -t "$PANE_T" "exit" Enter
  sleep 2
  TOT="$(tma list-panes -a -F '#{pane_id} #{pane_dead}' | awk -v p="$PANE_T" '$1==p{print $2}')"
  if [ "$TOT" = "1" ]; then
    ok "$PANE_T ist tot, aber weiterhin gelistet -- der Befund ist hergestellt"
  else
    note "$PANE_T liess sich nicht in den Zustand 'tot' bringen (pane_dead='$TOT') -- Punkt 3 prueft dann nur, dass der Guard einen lebenden Pane nicht verlaesst"
  fi
  sleep $(( POLL_T * 3 ))
  kill -0 "$PID_TP" 2>/dev/null \
    && ok "der Guard laeuft nach $(( POLL_T * 3 ))s weiter -- ein toter Pane beendet ihn nicht" \
    || bad "der Guard hat sich wegen eines TOTEN (nicht verschwundenen) Panes beendet: $(tail -2 "$TESTHOME/tot.log" 2>/dev/null | tr '\n' ' ')"
  kill "$PID_TP" 2>/dev/null
else
  bad "Vorbereitung fuer Punkt 3 fehlgeschlagen: kein Guard gestartet ($OUT)"
fi
tma kill-session -t '=wb-WA-tot' 2>/dev/null

echo
echo "wb-context-guard-waise: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
