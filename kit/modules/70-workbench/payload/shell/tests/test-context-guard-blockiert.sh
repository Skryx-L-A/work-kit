#!/usr/bin/env bash
# Tests fuer context-guard: ein Worker, der vor einer Rueckfrage haengt (ein
# nummerierter Auswahldialog mit Zeiger, wie Claude Codes eigene "Dangerous rm
# operation ... Do you want to proceed? 1. Yes / 2. Yes, and don't ask again /
# 3. No"), wird ueber mehrere Polls hinweg erkannt und GENAU EINMAL an den
# Orchestrator gemeldet.
#
# Anlass (N5, MASTERLISTE-2026-08-04): der Worker `fensterzu` stand rund eine
# Stunde vor genau so einer Rueckfrage. Niemand hat es gemerkt -- der
# Orchestrator fand ihn nur, weil sich seine Kontextzahl zwischen zwei
# Messungen nicht bewegte. Die Fertigmeldung (test-context-guard-
# fertigmeldung.sh) deckt nur den FERTIGEN Worker ab, nicht den blockierten.
#
# Isolation wie im Schwester-Test: eigener Socket (Tests fassen die Live-
# Umgebung nie an), eigenes HOME (Zustandsdateien landen unter $FAKEHOME, nie
# unter ~/.local/state/wb-context-guard). Orchestrator-Pane ist 'cat' statt
# einer echten Shell -- die Meldung darf niemals als Kommando laufen. Der
# Worker-Pane bekommt KEIN echtes Claude, nur ein Skript, das den Dialogtext
# ausgibt und dann wartet (genau wie im Auftrag verlangt: "ein einfaches
# Skript ... reicht").
unset TMUX TMUX_PANE
set -uo pipefail

# Kennzeichen dieses Laufs (siehe test-context-guard-live-socket-unberuehrt.sh):
# haengt an Socket- und Worker-Namen, wenn LIVE_MARKER gesetzt ist -- leer und
# ohne Wirkung, wenn diese Suite einzeln laeuft.
MARK="${LIVE_MARKER:+-$LIVE_MARKER}"
SOCKET="wbtest-blockiert$MARK-$$"
WORKER_BLOCKED="workerBlocked$MARK"
# Repo-relativ statt fest verdrahtet: derselbe Test laeuft auf dem Mac
# ($HOME/AI/...) und auf host2 ($HOME/AI/...). Override bleibt
# moeglich (siehe WB_SESSION_CLOSE-Regel in test-session-close.sh).
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${WB_CONTEXT_GUARD:-$REPO/context-guard}"
echo "Geprueft: $TOOL"
FAKEHOME="$(mktemp -d)"

# Seit dem 06.08. geht jeder Tastendruck des Guards durch `wb-pane-write`, und das
# Werkzeug erkennt den Guard an der kanonischen Datei $HOME/.local/bin/context-guard.
# In einem Test-HOME liegt dort nichts -- also wird es dort hingelegt (Symlink auf den
# Arbeitsbaum, dieselbe Inode, also dieselbe Pruefung wie im Betrieb). wb-state kommt
# seit dem 06.08. (guardMeldetWorkerStatus) dazu: der Guard fragt darueber ab, ob er
# ueberhaupt melden darf, das braucht den echten Leseweg statt eines fehlenden Binaries.
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$FAKEHOME" wb-pane-write wb-mensch context-guard wb-state \
    || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
# guardMeldetWorkerStatus ist per Vorgabe AUS (2026-08-06) -- dieser Test prueft die
# MECHANIK der Haengt-Meldung selbst, also wird der Schalter hier ausdruecklich
# angeschaltet. Das Verhalten des Schalters (aus = keine Meldung, Merker wandert
# trotzdem) steht in test-context-guard-schalter.sh.
HOME="$FAKEHOME" "$FAKEHOME/.local/bin/wb-state" settings set guardMeldetWorkerStatus true >/dev/null
WORK="$(mktemp -d)"
pass=0; fail=0
GUARD_PIDS=()

tm() { tmux -L "$SOCKET" "$@"; }
cleanup() {
    for p in "${GUARD_PIDS[@]:-}"; do
        [ -n "$p" ] && kill "$p" 2>/dev/null
    done
    tmux_socket_beenden_ohne_reste "$SOCKET"
    local deadline=$((SECONDS + 5))
    while [ $SECONDS -lt $deadline ] && tm list-sessions >/dev/null 2>&1; do
        tm kill-server 2>/dev/null
        sleep 0.3
    done
    tm list-sessions >/dev/null 2>&1 \
        && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
    rm -f "/private/tmp/tmux-$(id -u)/$SOCKET"
    rm -rf "$FAKEHOME" "$WORK"
}
trap cleanup EXIT

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

capture() { tm capture-pane -p -S -2000 -t "$1" 2>/dev/null; }
count_occurrences() { capture "$1" | grep -oF "$2" | wc -l | tr -d ' '; }
wait_count() {   # <pane> <deadline_s> <needle> <n> -> wartet, bis count >= n
    local p="$1" dl=$((SECONDS + $2)) needle="$3" n="$4"
    while [ $SECONDS -lt $dl ]; do
        [ "$(count_occurrences "$p" "$needle")" -ge "$n" ] && return 0
        sleep 0.3
    done
    return 1
}

# --- die zwei Dialog-"Bildschirme", die der Worker-Pane ausgibt -------------
DIALOG1="$WORK/dialog1.txt"
cat >"$DIALOG1" <<'EOF'
Dangerous rm operation on statically-unresolvable target:
 $HOME/AI/claude-workbench/extension/out/*
 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again for similar commands in $HOME/AI/claude-workbench
   3. No
 Esc to cancel · Tab to amend · ctrl+e to explain
EOF

DIALOG2="$WORK/dialog2.txt"
cat >"$DIALOG2" <<'EOF'
This will force-push over the remote branch history.
Do you want to continue?
 ❯ 1. Yes
   2. No
EOF

echo "== context-guard: blockierter Worker (Rueckfrage-Dialog) =="
tm kill-server 2>/dev/null
tm new-session -d -s wb -x 220 -y 60 -c /tmp
tmux_live_hooks_kappen "$SOCKET"   # sonst greift das echte wb-autorevive in respawn-pane/pane-died ein

ORCH_PANE="$(tm list-panes -t wb -F '#{pane_id}')"
tm respawn-pane -k -t "$ORCH_PANE" "sh -c 'stty -echo; exec cat'"
tm set-option -p -t "$ORCH_PANE" @wb_role orchestrator

tm split-window -t wb -c /tmp
WORKER_PANE="$(tm display -p -t wb '#{pane_id}')"
tm set-option -p -t "$WORKER_PANE" @wb_role worker
tm set-option -p -t "$WORKER_PANE" @wb_worker "$WORKER_BLOCKED"
# ANDERS als der Orchestrator-Pane: eine ECHTE Shell, kein 'cat'-Sink -- der
# Worker-Pane soll `cat dialogfile; sleep 600` wirklich AUSFUEHREN, damit der
# Dialogtext echt auf dem Bildschirm steht (kein echtes Claude noetig, aber
# eine echte Shell schon).

tm new-window -t wb -n guardrunner -c /tmp
GRUNNER="$(tm display -p -t wb:guardrunner '#{pane_id}')"

start_guard() {   # <logfile> <pidfile>
    tm send-keys -t "$GRUNNER" \
        "HOME='$FAKEHOME' PROJECT='$FAKEHOME' POLL=2 WARN_PCT=95 ORCH_PCT=95 DIALOG_CONFIRM_POLLS=2 EXIT_GRACE=99999 '$TOOL' --auto '$ORCH_PANE' >'$WORK/$1' 2>&1 & echo \$! >'$WORK/$2'" Enter
}

start_guard guard1.log guard1.pid
warte_auf_bedingung 15 "guard1.pid entsteht" "[ -s '$WORK/guard1.pid' ]"
GPID1="$(cat "$WORK/guard1.pid" 2>/dev/null)"
GUARD_PIDS+=("$GPID1")
warte_auf_bedingung 15 "Guard1 (PID $GPID1) meldet orchestrator= im Log" \
    "grep -q '^context-guard: orchestrator=' '$WORK/guard1.log'" "$WORK/guard1.log" \
  && ok "Guard gestartet (PID $GPID1): $(grep '^context-guard: orchestrator=' "$WORK/guard1.log")"

NEEDLE="WORKER STUCK (automatic): $WORKER_BLOCKED"

echo "-- (a) Dialog erscheint -> beim ERSTEN Poll danach noch KEINE Meldung --"
tm send-keys -t "$WORKER_PANE" "cat '$DIALOG1'; sleep 600" Enter
sleep 2.5   # ~ ein Poll-Intervall (POLL=2)
if capture "$ORCH_PANE" | grep -qF "$NEEDLE"; then
    bad "(a) Meldung kam schon nach einem einzigen Poll -- zu frueh"
else
    ok "(a) nach einem Poll noch keine Meldung (wie verlangt: einer reicht nicht)"
fi

echo "-- (b) nach mehreren Polls in Folge -> GENAU EINE Meldung --"
if wait_count "$ORCH_PANE" 15 "$NEEDLE" 1; then
    ok "(b) genau eine Meldung fuer workerBlocked kam an"
else
    bad "(b) keine Meldung -- Pane: $(capture "$ORCH_PANE" | tail -8)"
fi
sleep 5   # mehrere weitere Polls, WAEHREND der Dialog unveraendert steht
C=$(count_occurrences "$ORCH_PANE" "$NEEDLE")
[ "$C" = 1 ] && ok "(b) auch nach weiteren Polls weiterhin genau eine Meldung ($C)" \
             || bad "(b) $C Meldungen statt 1 -- Dialog haette nicht erneut gemeldet werden duerfen"

echo "-- (c) Dialog loest sich auf -> keine weitere Meldung --"
tm send-keys -t "$WORKER_PANE" C-c
sleep 0.3
tm send-keys -t "$WORKER_PANE" "clear" Enter
tm send-keys -t "$WORKER_PANE" "echo dialog-aufgeloest" Enter
sleep 6   # mehrere Polls, waehrend der Pane wieder normal aussieht
C=$(count_occurrences "$ORCH_PANE" "$NEEDLE")
[ "$C" = 1 ] && ok "(c) nach Aufloesung weiterhin nur die eine (alte) Meldung ($C)" \
             || bad "(c) $C Meldungen -- eine neue kam, obwohl der Dialog weg war"

echo "-- (d) ein ZWEITER, spaeterer Dialog wird wieder gemeldet --"
tm send-keys -t "$WORKER_PANE" "cat '$DIALOG2'; sleep 600" Enter
if wait_count "$ORCH_PANE" 15 "$NEEDLE" 2; then
    ok "(d) zweiter Dialog wurde erneut gemeldet (jetzt 2 Meldungen insgesamt)"
else
    bad "(d) kein zweiter Dialog gemeldet -- Pane: $(capture "$ORCH_PANE" | tail -8)"
fi
# genau zwei, nicht mehr, nachdem der zweite Dialog auch schon ein paar Polls steht
sleep 5
C=$(count_occurrences "$ORCH_PANE" "$NEEDLE")
[ "$C" = 2 ] && ok "(d) weiterhin genau zwei Meldungen insgesamt ($C)" \
             || bad "(d) $C Meldungen statt 2"

echo "-- Gegenprobe: normaler Text mit Ziffern OHNE Zeiger loest NICHTS aus --"
tm send-keys -t "$WORKER_PANE" C-c
sleep 0.3
NORMALTXT="$WORK/normal-list.txt"
cat >"$NORMALTXT" <<'EOF'
Plan:
1. Read the file
2. Apply the fix
3. Run the tests
Done?
EOF
tm send-keys -t "$WORKER_PANE" "clear" Enter
sleep 0.5
tm send-keys -t "$WORKER_PANE" "cat '$NORMALTXT'; sleep 600" Enter
sleep 6   # mehrere Polls
C=$(count_occurrences "$ORCH_PANE" "$NEEDLE")
[ "$C" = 2 ] && ok "(Gegenprobe) nummerierte Liste ohne Auswahlzeiger loest keine dritte Meldung aus ($C)" \
             || bad "(Gegenprobe) $C Meldungen statt 2 -- normaler nummerierter Text wurde faelschlich als Dialog erkannt"

echo
echo "context-guard blockierter Worker: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
