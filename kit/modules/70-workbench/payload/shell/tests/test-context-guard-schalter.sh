#!/usr/bin/env bash
# Tests fuer den Schalter guardMeldetWorkerStatus: darf der context-guard von sich
# aus etwas ueber den STATUS eines Workers (fertig / haengt in Rueckfrage) in den
# Orchestrator-Pane tippen?
#
# Anlass (2026-08-06): der Nutzer empfindet die Fertig- und die Haengt-Meldung als
# Stoerung -- sie unterbricht ihn und sieht aus wie sein eigenes Wort, obwohl die
# Information ohnehin schon in der App-Oberflaeche steht. Beide Meldungen laufen
# ueber diesen EINEN Schalter, Vorgabe AUS. Praezisiert vom Nutzer selbst: NUR
# diese zwei Stellen fallen darunter -- die Kontext-Warnung, das getippte /compact
# und der WEITERARBEITEN-Prompt danach sind die einzige Schutzfunktion, die nie
# verstummen darf, und bleiben in jedem Fall unberuehrt.
#
# Geprueft wird, in EINEM Guard-Lauf mit dem Schalter AUS (Vorgabe, kein Override):
#   (a) ein fertiges Worker-Ergebnis erzeugt KEINE Meldung im Orchestrator-Pane,
#       der "schon gemeldet"-Merker (DONE_DIR) wird trotzdem gesetzt.
#   (b) ein haengender Rueckfrage-Dialog erzeugt KEINE Meldung im Orchestrator-
#       Pane, der Merker (DIALOG_STATE_DIR/.reported) wird trotzdem gesetzt.
#   (c) die Kontext-Warnung fuer den Orchestrator selbst kommt TROTZDEM an --
#       simuliert ueber die Zehn-Block-Bar-Anzeige, die read_load() ohnehin kennt
#       (keine Registry noetig, siehe context-guard:822 read_load()).
#
# Was NICHT dieser Test ist: die MECHANIK der Fertig- und der Haengt-Meldung
# selbst (genau einmal, ueberlebt Neustart, trotz geschlossenem Pane, Reihenfolge
# der Polls, ...) steht in test-context-guard-fertigmeldung.sh und
# test-context-guard-blockiert.sh -- beide schalten den Schalter dafuer
# ausdruecklich AN und bleiben insofern der Beleg fuer "mit Schalter an
# unveraendert wie heute".
#
# Isolation wie die Schwester-Tests: eigener Socket, eigenes HOME, Orchestrator-
# Pane ist 'cat' statt einer echten Shell (getippter Text darf niemals als Kommando
# laufen), der Worker-Pane fuer den Dialog bekommt eine echte Shell (muss den
# Dialogtext wirklich ausgeben).
unset TMUX TMUX_PANE
set -uo pipefail

MARK="${LIVE_MARKER:+-$LIVE_MARKER}"
SOCKET="wbtest-schalter$MARK-$$"
WF="workerFertig$MARK"; WH="workerHaengt$MARK"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${WB_CONTEXT_GUARD:-$REPO/context-guard}"
echo "Geprueft: $TOOL"
FAKEHOME="$(mktemp -d)"

# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$FAKEHOME" wb-pane-write wb-mensch context-guard wb-state \
    || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
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
wait_contains() {   # <pane> <deadline_s> <needle>
    local p="$1" dl=$((SECONDS + $2)) needle="$3"
    while [ $SECONDS -lt $dl ]; do
        capture "$p" | grep -qF "$needle" && return 0
        sleep 0.3
    done
    return 1
}
mkresult() {   # <name> -- legt ein echtes, nicht-leeres Ergebnis + latest.md-Symlink an
    local name="$1"
    local dir="$FAKEHOME/.pi-workers/results/$name"
    mkdir -p "$dir"
    printf 'ok\n' >"$dir/20260806-000000.md"
    ln -sf 20260806-000000.md "$dir/latest.md"
}

DIALOG="$WORK/dialog.txt"
cat >"$DIALOG" <<'EOF'
Dangerous rm operation on statically-unresolvable target:
 $HOME/AI/claude-workbench/extension/out/*
 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again for similar commands in $HOME/AI/claude-workbench
   3. No
 Esc to cancel · Tab to amend · ctrl+e to explain
EOF

echo "== context-guard: Schalter guardMeldetWorkerStatus (Vorgabe AUS) =="
mkdir -p "$FAKEHOME/.pi-workers/results"
tm kill-server 2>/dev/null
tm new-session -d -s wb -x 220 -y 60 -c /tmp
tmux_live_hooks_kappen "$SOCKET"   # sonst greift das echte wb-autorevive in respawn-pane/pane-died ein

ORCH_PANE="$(tm list-panes -t wb -F '#{pane_id}')"
tm respawn-pane -k -t "$ORCH_PANE" "sh -c 'stty -echo; exec cat'"
tm set-option -p -t "$ORCH_PANE" @wb_role orchestrator

tm split-window -t wb -c /tmp
WF_PANE="$(tm display -p -t wb '#{pane_id}')"
tm respawn-pane -k -t "$WF_PANE" "sh -c 'stty -echo; exec cat'"
tm set-option -p -t "$WF_PANE" @wb_role worker
tm set-option -p -t "$WF_PANE" @wb_worker "$WF"

tm split-window -t wb -c /tmp
WH_PANE="$(tm display -p -t wb '#{pane_id}')"
tm set-option -p -t "$WH_PANE" @wb_role worker
tm set-option -p -t "$WH_PANE" @wb_worker "$WH"
# ECHTE Shell (kein cat-Sink): der Dialogtext muss wirklich auf dem Bildschirm
# stehen, damit pane_dialog_question() ihn liest.

tm new-window -t wb -n guardrunner -c /tmp
GRUNNER="$(tm display -p -t wb:guardrunner '#{pane_id}')"

# guardMeldetWorkerStatus wird HIER bewusst NICHT gesetzt -- die Vorgabe AUS soll
# genau ohne Zutun greifen, kein Override in $FAKEHOME/.claude/workbench/settings.json.
tm send-keys -t "$GRUNNER" \
    "HOME='$FAKEHOME' PROJECT='$FAKEHOME' POLL=2 WARN_PCT=95 ORCH_PCT=50 DIALOG_CONFIRM_POLLS=2 EXIT_GRACE=99999 '$TOOL' --auto '$ORCH_PANE' >'$WORK/guard.log' 2>&1 & echo \$! >'$WORK/guard.pid'" Enter
warte_auf_bedingung 15 "guard.pid entsteht" "[ -s '$WORK/guard.pid' ]"
GPID="$(cat "$WORK/guard.pid" 2>/dev/null)"
GUARD_PIDS+=("$GPID")
warte_auf_bedingung 15 "Guard (PID $GPID) meldet orchestrator= im Log" \
    "grep -q '^context-guard: orchestrator=' '$WORK/guard.log'" "$WORK/guard.log" \
  && ok "Guard gestartet (PID $GPID): $(grep '^context-guard: orchestrator=' "$WORK/guard.log")"
if grep -q 'guardMeldetWorkerStatus ist AUS' "$WORK/guard.log" 2>/dev/null; then
    ok "Guard meldet beim Start selbst, dass guardMeldetWorkerStatus AUS ist"
else
    bad "keine Start-Ansage zu guardMeldetWorkerStatus -- Log: $(tail -5 "$WORK/guard.log" 2>/dev/null)"
fi

echo "-- (a) fertiges Ergebnis -> KEINE Meldung im Orchestrator-Pane, Merker trotzdem gesetzt --"
mkresult "$WF"
sleep 6   # mehrere Polls (POLL=2), genug Zeit fuer eine Meldung, waere sie erlaubt
if capture "$ORCH_PANE" | grep -qF "Worker $WF is done"; then
    bad "(a) Fertigmeldung kam trotz ausgeschaltetem Schalter im Orchestrator-Pane an"
else
    ok "(a) keine Fertigmeldung im Orchestrator-Pane"
fi
DONE_MARK="$(find "$FAKEHOME/.local/state/wb-context-guard" -type f -path "*.done-notified/$WF" 2>/dev/null | head -1)"
if [ -n "$DONE_MARK" ]; then
    ok "(a) der 'schon gesehen'-Merker wurde trotzdem gesetzt: $DONE_MARK"
else
    bad "(a) kein Merker unter done-notified/$WF gefunden -- ein spaeteres Einschalten wuerde das Ergebnis nachmelden"
fi

echo "-- (b) haengender Rueckfrage-Dialog -> KEINE Meldung, Merker trotzdem gesetzt --"
tm send-keys -t "$WH_PANE" "cat '$DIALOG'; sleep 600" Enter
sleep 6   # >= DIALOG_CONFIRM_POLLS * POLL, genug Zeit fuer eine Meldung, waere sie erlaubt
NEEDLE_HAENGT="WORKER STUCK (automatic): $WH"
if capture "$ORCH_PANE" | grep -qF "$NEEDLE_HAENGT"; then
    bad "(b) Haengt-Meldung kam trotz ausgeschaltetem Schalter im Orchestrator-Pane an"
else
    ok "(b) keine Haengt-Meldung im Orchestrator-Pane"
fi
WH_KEY="$(printf '%s' "$WH" | tr -c 'a-zA-Z0-9' '-')"
DIALOG_MARK="$(find "$FAKEHOME/.local/state/wb-context-guard" -type f -path "*.dialog-notified/$WH_KEY.reported" 2>/dev/null | head -1)"
if [ -n "$DIALOG_MARK" ]; then
    ok "(b) der 'schon gemeldet'-Merker wurde trotzdem gesetzt: $DIALOG_MARK"
else
    bad "(b) kein .reported-Merker fuer $WH gefunden -- ein spaeteres Einschalten wuerde denselben Dialog nochmal melden"
fi

echo "-- (c) Kontext-Warnung des Orchestrators bleibt UNBERUEHRT -- kommt trotzdem an --"
# Zehn-Block-Bar, 60% (sechs gefuellte Bloecke): read_load() liest sie direkt aus
# der Statuszeile, keine Registry noetig (context-guard:822). ORCH_PCT=50 oben,
# der Schwellwert fuer die Bar wird auf 10er-Schritte abgerundet (auch 50), 60 >= 50.
tm send-keys -t "$ORCH_PANE" '▓▓▓▓▓▓░░░░' Enter
if wait_contains "$ORCH_PANE" 20 "CONTEXT WARNING (automatic)"; then
    ok "(c) die Kontext-Warnung kam an, obwohl guardMeldetWorkerStatus aus ist"
else
    bad "(c) keine Kontext-Warnung -- Log: $(tail -8 "$WORK/guard.log" 2>/dev/null)"
fi

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
