#!/bin/bash
# Prueft `context-guard --ensure` fuer eine REINE Worker-Session auf eigenem Socket.
#
# Anlass (2026-08-13): auf host2 meldete `--ensure` „Session wb-orch hat keinen lebenden
# @wb_role=orchestrator-Pane — kein Guard gestartet". Dort laufen aber genau die Worker,
# die eine Kontextwache am noetigsten haben. Geprueft wird deshalb dreierlei: dass ein
# Guard startet, dass er im Worker-Modus laeuft (--workers-only), und dass er bei einer
# Session ganz OHNE Agenten-Pane weiterhin NICHT startet.
unset TMUX TMUX_PANE
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"
TOOL="${WB_CONTEXT_GUARD:-$REPO/context-guard}"
pass=0; fail=0
echo "Geprueft: $TOOL"
ok()  { pass=$((pass+1)); echo "  ok    $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

SOCK=wbtest-gnw
TD="$(mktemp -d /tmp/wbgnwXXXX)"
WORK="$(mktemp -d /tmp/wbgnwwXXXX)"
FAKEHOME="$(mktemp -d /tmp/wbgnwhXXXX)"
GUARD_PIDS=""

cleanup() {
  # Zuerst die selbst gestarteten Wachen, per PID — ein Muster wuerde ueber die eigenen
  # Testprozesse hinausreichen, und ein `kill-server` allein laesst sie weiterlaufen.
  local p
  for p in $GUARD_PIDS; do
    kill "$p" 2>/dev/null
  done
  sleep 1
  for p in $GUARD_PIDS; do
    kill -0 "$p" 2>/dev/null && echo "WARNUNG: Guard-PID $p laeuft noch" >&2
  done
  # Panes VOR dem kill-server einsammeln und jeden, der den Server-Tod ueberlebt,
  # direkt beenden statt sich auf das SIGHUP zu verlassen -- dasselbe Muster wie
  # Aufgeraeumt wird ueber die gemeinsame Funktion aus lib-testwerkzeuge.sh --
  # sie nimmt seit dem 24.08. Vorargumente entgegen (-f /dev/null) und
  # beendet ausser den Panes auch die uebrigen Kinder des Serverprozesses. Die
  # handgebaute Schleife, die bis dahin hier stand, kannte nur die Pane-Liste
  # und liess damit genau die Shells stehen, die ein kill-session ueberlebt
  # hatten (Auftrag "was bei zwanzig gleichzeitig passiert", 2026-08-24).
  TMUX_TMPDIR="$TD" tmux_socket_beenden_ohne_reste "$SOCK" -f /dev/null
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && TMUX_TMPDIR="$TD" tmux -L "$SOCK" -f /dev/null list-sessions >/dev/null 2>&1; do
    TMUX_TMPDIR="$TD" tmux -L "$SOCK" -f /dev/null kill-server 2>/dev/null
    sleep 0.3
  done
  TMUX_TMPDIR="$TD" tmux -L "$SOCK" -f /dev/null list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCK' laeuft noch" >&2
  rm -rf "$TD" "$WORK" "$FAKEHOME"
}
trap cleanup EXIT

export TMUX_TMPDIR="$TD"
T() { tmux -L "$SOCK" -f /dev/null "$@"; }

# tmux-Schirm: der Pruefling ruft selbst tmux auf und muss dabei auf DIESEM Socket
# landen, nicht auf dem Standard-Socket (dort ist %0 ein gueltiger Pane — ein stiller
# Fehlgriff mitten in eine echte Session, genau der Vorfall vom 04.08.).
STUB="$WORK/stub"; mkdir -p "$STUB"
REALTMUX="$(command -v tmux)"
cat > "$STUB/tmux" <<EOF
#!/bin/bash
exec "$REALTMUX" -L "$SOCK" -f /dev/null "\$@"
EOF
chmod +x "$STUB/tmux"

T new-session -d -s wb-nurworker -n workers -x 200 -y 50 'while :; do sleep 30; done'
WPANE="$(T list-panes -t '=wb-nurworker' -F '#{pane_id}' | head -1)"
T set -p -t "$WPANE" @wb_role worker
T set -p -t "$WPANE" @wb_worker demo-worker
# Der Runner: eine echte Shell, sonst verpufft jedes send-keys.
T new-window -d -t '=wb-nurworker:' -n runner
RUNNER="$(T list-panes -t '=wb-nurworker:runner' -F '#{pane_id}' | head -1)"

RC=99; OUT=""
run() {   # run <argumente...> -> $RC, $OUT
  local f="$WORK/lauf"
  rm -f "$f" "$f.rc" "$f.done"
  T send-keys -t "$RUNNER" \
    "PATH=\"$STUB:\$PATH\" HOME='$FAKEHOME' bash '$TOOL' $* > $f 2>&1; echo \$? > $f.rc; touch $f.done" Enter
  warte_auf_datei "$f.done" 60 "context-guard $*" "$f"
  RC="$(cat "$f.rc" 2>/dev/null || echo 99)"
  OUT="$(cat "$f" 2>/dev/null)"
}

# --- 1. Reine Worker-Session: es startet eine Wache -------------------------------
run --ensure "$WPANE"
[ "$RC" = 0 ] && ok "reine Worker-Session: Exit 0" || bad "reine Worker-Session: Exit $RC ($OUT)"
grep -q 'reine Worker-Session' <<<"$OUT" \
  && ok "die Meldung nennt den Worker-Modus" \
  || bad "Meldung nennt den Modus nicht: $OUT"
GPID="$(sed -n 's/.*PID \([0-9][0-9]*\).*/\1/p' <<<"$OUT" | head -1)"
if [ -n "$GPID" ]; then
  GUARD_PIDS="$GUARD_PIDS $GPID"
  kill -0 "$GPID" 2>/dev/null && ok "die Wache laeuft wirklich (PID $GPID)" || bad "genannte PID $GPID laeuft nicht"
  args="$(ps -p "$GPID" -o args= 2>/dev/null)"
  grep -q -- '--workers-only' <<<"$args" \
    && ok "die Wache laeuft im Worker-Modus (--workers-only)" \
    || bad "der Wache fehlt --workers-only: $args"
  grep -q -- "$WPANE" <<<"$args" && ok "die Wache haengt am Worker-Pane $WPANE" || bad "falscher Anker-Pane: $args"
else
  bad "keine PID in der Meldung: $OUT"
fi

# --- 2. Kein zweiter Guard fuer dieselbe Session ----------------------------------
run --ensure "$WPANE"
grep -q 'laeuft bereits' <<<"$OUT" \
  && ok "zweiter Aufruf startet keine zweite Wache" \
  || bad "zweiter Aufruf meldete nicht 'laeuft bereits': $OUT"

# --- 3. Session ganz ohne Agenten-Pane: weiterhin KEIN Guard ----------------------
T new-session -d -s wb-leer -n orch -x 200 -y 50 'while :; do sleep 30; done'
EPANE="$(T list-panes -t '=wb-leer' -F '#{pane_id}' | head -1)"
run --ensure "$EPANE"
[ "$RC" != 0 ] && ok "ohne Agenten-Pane: kein Guard, Exit $RC" || bad "ohne Agenten-Pane startete trotzdem ein Guard ($OUT)"
grep -q 'weder einen lebenden' <<<"$OUT" \
  && ok "ohne Agenten-Pane: Grund genannt" \
  || bad "ohne Agenten-Pane: Grund fehlt ($OUT)"

# --- 4. Der Anker wird NACHGEZOGEN, statt mit ihm zu enden ------------------------
# Reviewer-Befund: der Anker ist der erste lebende Worker der Session, also meist der
# aelteste und damit der, der zuerst fertig wird. Auf peers `wb-orch` waere sein
# Verschwinden der Normalfall — und die uebrigen Worker liefen ab da unbewacht weiter.
T new-window -d -t '=wb-nurworker:' -n zweiter 'while :; do sleep 30; done'
W2="$(T list-panes -t '=wb-nurworker:zweiter' -F '#{pane_id}' | head -1)"
T set -p -t "$W2" @wb_role worker
T set -p -t "$W2" @wb_worker nachfolger
GLOG2="$WORK/guard2.log"
# Die Wache aus Fall 1 laeuft noch und wuerde die neue zu Recht abweisen (eine je
# Session). Erst sie beenden — per PID, es ist unsere eigene — und das Ende abwarten.
if [ -n "${GPID:-}" ]; then
  kill "$GPID" 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$GPID" 2>/dev/null || break; sleep 1; done
  kill -0 "$GPID" 2>/dev/null && bad "Vorbedingung: die Wache aus Fall 1 liess sich nicht beenden"
fi
# Eigene Wache mit kurzem Poll, damit der Fall in Sekunden statt Minuten faellt.
T send-keys -t "$RUNNER" \
  "PATH=\"$STUB:\$PATH\" HOME='$FAKEHOME' POLL=2 ORCH_PANE_GONE_POLLS=1 bash '$TOOL' --auto --workers-only --exit-when-session-gone $WPANE > $GLOG2 2>&1 &" Enter
sleep 6
GP2="$(ps -eo pid,args | grep -e "--workers-only --exit-when-session-gone $WPANE" | grep -v grep | awk '{print $1}' | head -1)"
if [ -n "$GP2" ]; then
  GUARD_PIDS="$GUARD_PIDS $GP2"
  ok "Vorbedingung: zweite Wache laeuft (PID $GP2)"
  T kill-pane -t "$WPANE" 2>/dev/null
  sleep 10
  if kill -0 "$GP2" 2>/dev/null; then
    ok "der Anker ist weg, die Wache laeuft weiter"
  else
    bad "die Wache endete mit ihrem Anker, obwohl noch ein Worker laeuft"
  fi
  grep -q "Anker wird $W2" "$GLOG2" 2>/dev/null \
    && ok "das Protokoll nennt den neuen Anker ($W2)" \
    || bad "kein Nachzieh-Eintrag im Protokoll: $(tr '\n' ' ' < "$GLOG2" 2>/dev/null | tail -c 300)"
  # Und jetzt faellt auch der letzte Worker weg: DANN darf die Wache enden.
  T kill-pane -t "$W2" 2>/dev/null
  sleep 10
  kill -0 "$GP2" 2>/dev/null \
    && bad "die Wache laeuft weiter, obwohl kein Worker mehr da ist" \
    || ok "ohne jeden Worker endet die Wache"
else
  bad "die zweite Wache ist nicht angelaufen: $(tr '\n' ' ' < "$GLOG2" 2>/dev/null | tail -c 300)"
fi

# --- 5. Der Kern des Modus: an den ANKER geht nichts Orchestrator-Gerichtetes -----
# Reviewer-Befund: bisher belegte nur die Kommandozeile den Modus, nicht sein Verhalten.
# Hier steht ein Anker mit einer Statuszeile WEIT ueber jeder Schwelle; danach wird der
# Paneinhalt gegengelesen. Erwartet: die Worker-Behandlung (er IST ein Worker) findet
# statt, aber keine der Orchestrator-Ansprachen — kein /compact, kein WEITERARBEITEN,
# keine KONTEXT-WARNUNG.
T new-session -d -s wb-nurworker2 -n workers -x 200 -y 50
A1="$(T list-panes -t '=wb-nurworker2' -F '#{pane_id}' | head -1)"
T set -p -t "$A1" @wb_role worker
T set -p -t "$A1" @wb_worker anker
T send-keys -t "$A1" "clear; printf 'conversation\\n Sonnet xhigh . proj main . 990k/1.0M . 5h 1%%\\n'" Enter
sleep 1
T new-window -d -t '=wb-nurworker2:' -n runner2
RUNNER2="$(T list-panes -t '=wb-nurworker2:runner2' -F '#{pane_id}' | head -1)"
GLOG3="$WORK/guard3.log"
T send-keys -t "$RUNNER2" \
  "PATH=\"$STUB:\$PATH\" HOME='$FAKEHOME' PROJECT='$FAKEHOME' POLL=2 ORCH_PCT=50 WARN_PCT=50 bash '$TOOL' --auto --workers-only --exit-when-session-gone $A1 > $GLOG3 2>&1 &" Enter
sleep 12
GP3="$(ps -eo pid,args | grep -e "--workers-only --exit-when-session-gone $A1" | grep -v grep | awk '{print $1}' | head -1)"
[ -n "$GP3" ] && GUARD_PIDS="$GUARD_PIDS $GP3"
ANKERTEXT="$(T capture-pane -p -S -200 -t "$A1" 2>/dev/null)"
if grep -qE '/compact|CONTINUE \(automatic|CONTEXT WARNING' <<<"$ANKERTEXT"; then
  bad "im Worker-Modus landete doch eine Orchestrator-Ansprache im Anker-Pane"
  printf '%s\n' "$ANKERTEXT" | grep -E '/compact|CONTINUE \(automatic|CONTEXT WARNING' | head -3 | sed 's/^/        /'
else
  ok "im Worker-Modus geht keine Orchestrator-Ansprache in den Anker-Pane"
fi
# Gesucht wird eine HANDLUNG, nicht das Wort. Die Startzeile nennt den Pane, und im
# Worker-Modus sagt sie ausdruecklich "anker=… (Worker-Modus, KEIN Orchestrator)".
grep -qE 'orchestrator /compact getippt|orchestrator WEITERARBEITEN|KONTEXT-WARNUNG bei' "$GLOG3" 2>/dev/null \
  && bad "das Guard-Protokoll verzeichnet eine Orchestrator-Handlung: $(grep -m2 -E 'orchestrator |KONTEXT-WARNUNG' "$GLOG3" | tr '\n' ' ')" \
  || ok "auch das Protokoll verzeichnet keine Orchestrator-Handlung"
grep -q 'anker=' "$GLOG3" 2>/dev/null \
  && ok "die Startzeile nennt den Pane als Anker, nicht als Orchestrator" \
  || bad "die Startzeile behauptet weiter einen Orchestrator: $(head -1 "$GLOG3" 2>/dev/null)"
[ -n "$GP3" ] && kill "$GP3" 2>/dev/null

echo
echo "Ergebnis: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
