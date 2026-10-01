#!/usr/bin/env bash
# Tests fuer context-guard: Fertigmeldung an den Orchestrator, sobald ein Worker sein
# Ergebnis geschrieben hat.
#
# Anlass (2026-08-04): In der a project-Session hat ein Orchestrator nicht bemerkt, dass
# sein Worker fertig war -- der Nutzer hat es gesehen, der Orchestrator nicht. Es gab
# keinen aktiven Weg vom fertigen Worker zum Orchestrator; der Guard schliesst diese
# Luecke, weil er ohnehin schon einmal je Workbench-Session laeuft und die Panes kennt.
#
# Alles laeuft auf einem EIGENEN Socket (Tests fassen die Live-Umgebung nie an) und mit
# eigenem HOME (Zustands- und Ergebnisdateien landen unter $FAKEHOME, nie unter dem
# echten ~/.pi-workers oder ~/.local/state/wb-context-guard). Der Guard selbst laeuft
# aus einem Pane DIESES Testservers heraus -- seine eigenen ungeflaggten
# `tmux list-panes -a`-Aufrufe reden sonst mit dem Live-/Default-Socket. Orchestrator-
# und Worker-Panes sind 'cat' statt einer echten Shell: getippter Text darf niemals
# als Kommando laufen. Die Meldung eines FERNEN Workers traegt weiterhin Backticks
# (um `wb-result <name>`); die lokale trug bis zum 05.08. eine Aufforderung zum
# Schliessen des Panes und tut es nicht mehr -- der Guard sieht den Pane nicht an,
# und seine Meldung kann eintreffen, wenn der Worker laengst an der naechsten
# Aufgabe sitzt. Punkt (i) unten haelt das fest.
unset TMUX TMUX_PANE
set -uo pipefail

# Kennzeichen dieses Laufs (siehe test-context-guard-live-socket-unberuehrt.sh):
# haengt an Socket- und Worker-Namen, wenn LIVE_MARKER gesetzt ist -- leer und
# ohne Wirkung, wenn diese Suite einzeln laeuft.
MARK="${LIVE_MARKER:+-$LIVE_MARKER}"
SOCKET="wbtest-fertigmeldung$MARK-$$"
WA="workerA$MARK"; WB="workerB$MARK"; WC="workerC$MARK"; WD="workerD$MARK"
WE="workerE$MARK"; WH="workerH$MARK"; WL="workerL$MARK"; WM="workerM$MARK"
# Repo-relativ statt fest verdrahtet: derselbe Test laeuft auf dem Mac
# ($HOME/AI/...) und auf host2 ($HOME/AI/...). Override bleibt
# moeglich (siehe WB_SESSION_CLOSE-Regel in test-session-close.sh).
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${WB_CONTEXT_GUARD:-$REPO/context-guard}"
WBCLOSE="${WB_CLOSE:-$REPO/wb-close}"
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
# MECHANIK der Meldungen selbst (genau einmal, ueberlebt Neustart, trotz geschlossenem
# Pane, ...), also wird der Schalter hier ausdruecklich angeschaltet. Das Verhalten des
# Schalters selbst (aus = keine Meldung, Merker wandert trotzdem) steht in
# test-context-guard-schalter.sh.
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
    printf 'ok\n' >"$dir/20260804-000000.md"
    ln -sf 20260804-000000.md "$dir/latest.md"
}

echo "== context-guard: Fertigmeldung =="
mkdir -p "$FAKEHOME/.pi-workers/results"
tm kill-server 2>/dev/null
tm new-session -d -s wb -x 220 -y 220 -c /tmp
tmux_live_hooks_kappen "$SOCKET"   # sonst greift das echte wb-autorevive in respawn-pane/pane-died ein

ORCH_PANE="$(tm list-panes -t wb -F '#{pane_id}')"
tm respawn-pane -k -t "$ORCH_PANE" "sh -c 'stty -echo; exec cat'"
tm set-option -p -t "$ORCH_PANE" @wb_role orchestrator

new_worker_pane() {   # <name> -> setzt PANE_ID auf die neue Pane
    local name="$1"
    tm split-window -t wb -c /tmp
    PANE_ID="$(tm display -p -t wb '#{pane_id}')"
    tm respawn-pane -k -t "$PANE_ID" "sh -c 'stty -echo; exec cat'"
    tm set-option -p -t "$PANE_ID" @wb_role worker
    tm set-option -p -t "$PANE_ID" @wb_worker "$name"
}
new_worker_pane "$WA"; WORKERA_PANE="$PANE_ID"
new_worker_pane "$WB"; WORKERB_PANE="$PANE_ID"
new_worker_pane "$WC"; WORKERC_PANE="$PANE_ID"
new_worker_pane "$WD"; WORKERD_PANE="$PANE_ID"

tm new-window -t wb -n guardrunner -c /tmp
GRUNNER="$(tm display -p -t wb:guardrunner '#{pane_id}')"

start_guard() {   # <logfile> <pidfile>
    tm send-keys -t "$GRUNNER" \
        "HOME='$FAKEHOME' PROJECT='$FAKEHOME' POLL=2 WARN_PCT=95 ORCH_PCT=95 EXIT_GRACE=99999 '$TOOL' --auto '$ORCH_PANE' >'$WORK/$1' 2>&1 & echo \$! >'$WORK/$2'" Enter
}

start_guard guard1.log guard1.pid
warte_auf_bedingung 15 "guard1.pid entsteht" "[ -s '$WORK/guard1.pid' ]"
GPID1="$(cat "$WORK/guard1.pid" 2>/dev/null)"
GUARD_PIDS+=("$GPID1")
warte_auf_bedingung 15 "Guard1 (PID $GPID1) meldet orchestrator= im Log" \
    "grep -q '^context-guard: orchestrator=' '$WORK/guard1.log'" "$WORK/guard1.log" \
  && ok "Guard gestartet (PID $GPID1): $(grep '^context-guard: orchestrator=' "$WORK/guard1.log")"

# workerC bekommt von Anfang an nur einen haengenden Symlink -- nie ein echtes Ziel.
mkdir -p "$FAKEHOME/.pi-workers/results/$WC"
ln -sf nicht-vorhanden.md "$FAKEHOME/.pi-workers/results/$WC/latest.md"

echo "-- (a) Ergebnis erscheint waehrend der Guard laeuft -> genau eine Meldung --"
mkresult "$WA"
NEEDLE_A="Worker $WA is done, result at $FAKEHOME/.pi-workers/results/$WA/20260804-000000.md"
if wait_contains "$ORCH_PANE" 15 "$NEEDLE_A"; then
    ok "(a) Meldung fuer workerA kam an"
else
    bad "(a) keine Meldung fuer workerA -- Pane: $(capture "$ORCH_PANE" | tail -5)"
fi

echo "-- (b) zweiter Poll -> keine zweite Meldung --"
sleep 5
C=$(count_occurrences "$ORCH_PANE" "Worker $WA is done")
[ "$C" = 1 ] && ok "(b) weiterhin genau eine Meldung fuer workerA ($C)" \
             || bad "(b) $C Meldungen fuer workerA statt 1"

echo "-- (e) haengender latest.md-Symlink ohne Inhalt -> keine Meldung --"
sleep 2
if capture "$ORCH_PANE" | grep -qF "Worker $WC is done"; then
    bad "(e) Meldung fuer workerC kam trotz haengendem Symlink"
else
    ok "(e) keine Meldung fuer workerC (haengender Symlink)"
fi

echo "-- (c) Guard neu gestartet -> immer noch keine zweite Meldung fuer workerA --"
kill "$GPID1" 2>/dev/null
warte_auf_bedingung 10 "(c) alter Guard (PID $GPID1) beendet sich" "! kill -0 '$GPID1' 2>/dev/null" \
  && ok "(c) alter Guard (PID $GPID1) beendet"

DONE_MARK="$(find "$FAKEHOME/.local/state/wb-context-guard" -type f -path "*.done-notified/$WA" 2>/dev/null | head -1)"
[ -n "$DONE_MARK" ] && ok "(c) persistente Markierung fuer workerA vorhanden: $DONE_MARK" \
                     || bad "(c) keine persistente Markierung fuer workerA gefunden"

start_guard guard2.log guard2.pid
warte_auf_bedingung 15 "guard2.pid entsteht" "[ -s '$WORK/guard2.pid' ]"
GPID2="$(cat "$WORK/guard2.pid" 2>/dev/null)"
GUARD_PIDS+=("$GPID2")
warte_auf_bedingung 15 "(c) neuer Guard (PID $GPID2) meldet orchestrator= im Log" \
    "grep -q '^context-guard: orchestrator=' '$WORK/guard2.log'" "$WORK/guard2.log" \
  && ok "(c) neuer Guard gestartet (PID $GPID2)"
sleep 5
C=$(count_occurrences "$ORCH_PANE" "Worker $WA is done")
[ "$C" = 1 ] && ok "(c) nach Neustart weiterhin genau eine Meldung fuer workerA ($C)" \
             || bad "(c) nach Neustart $C Meldungen fuer workerA statt 1"

echo "-- (d) Pane vorher geschlossen, Ergebnis vorhanden -> Meldung kommt trotzdem --"
sleep 3   # workerB mind. einmal lebend gesehen, bevor sein Pane verschwindet
tm kill-pane -t "$WORKERB_PANE" 2>/dev/null
mkresult "$WB"
NEEDLE_B="Worker $WB is done, result at $FAKEHOME/.pi-workers/results/$WB/20260804-000000.md"
if wait_contains "$ORCH_PANE" 15 "$NEEDLE_B"; then
    ok "(d) Meldung fuer workerB kam trotz geschlossenem Pane"
else
    bad "(d) keine Meldung fuer workerB nach Pane-Schluss -- Pane: $(capture "$ORCH_PANE" | tail -5)"
fi

echo "-- (f) Orchestrator BUSY -> Meldung kommt beim naechsten Poll --"
tm send-keys -t "$ORCH_PANE" "marker esc to interrupt marker" Enter
sleep 1
mkresult "$WD"
NEEDLE_D="Worker $WD is done, result at $FAKEHOME/.pi-workers/results/$WD/20260804-000000.md"
sleep 4   # mind. ein Poll waehrend busy
if capture "$ORCH_PANE" | grep -qF "$NEEDLE_D"; then
    bad "(f) Meldung kam trotz BUSY sofort"
else
    ok "(f) waehrend BUSY (noch) keine Meldung"
fi
for i in $(seq 1 12); do tm send-keys -t "$ORCH_PANE" "noise-line-$i" Enter; done
if wait_contains "$ORCH_PANE" 15 "$NEEDLE_D"; then
    ok "(f) Meldung kam, nachdem der Pane wieder idle war"
else
    bad "(f) Meldung kam nie, nachdem BUSY vorbei war"
fi

echo "-- (g) wb-close schliesst einen Worker mit frischem, noch ungemeldetem Ergebnis --"
# Simuliert genau den gemessenen Laerm-Fall (2026-08-04: sessionfix, tabnachlegen,
# doctortab, fensterstart): der Orchestrator liest/verarbeitet/schliesst schneller,
# als der naechste Guard-Poll den Worker als "fertig" entdeckt. wb-close muss die
# done-notified-Markierung SOFORT setzen, damit der Guard danach nie mehr meldet --
# nicht per Pane-Pruefung im Guard selbst (das wuerde Fall (d) oben zerstoeren,
# der GENAU denselben Pfad fuer den urspruenglichen a project-Bug offen halten muss).
new_worker_pane "$WE"; WORKERE_PANE="$PANE_ID"
sleep 3   # workerE mind. einmal lebend gesehen (record_known_worker), wie bei (d) --
          # sonst kennt check_worker_results den Namen gar nicht und der Test
          # bestuende auch OHNE die wb-close-Markierung aus dem falschen Grund.
mkresult "$WE"
[ -x "$WBCLOSE" ] || { echo "FAIL  $WBCLOSE fehlt oder ist nicht ausfuehrbar"; exit 1; }
# DIREKT aufgerufen, nicht mehr per `tm send-keys` in $GRUNNER getippt (2026-08-22).
# Ein echter Orchestrator ruft wb-close als eigenen Unterprozess auf, nie per
# getipptem Tastenanschlag in eine fremde Pane -- der Umweg ueber $GRUNNER bildete
# den echten Ablauf gar nicht ab, sondern fuegte ihm eine zusaetzliche, rein
# testeigene Verzoegerung hinzu (Tastatureingabe muss erst vom GRUNNER-Pane
# geplant und von dessen Shell verarbeitet werden, bevor wb-close ueberhaupt
# startet). TMUX_BIN uebernimmt denselben Socket wie `tm()`, damit wb-close's
# eigene $T-Aufrufe den Test-Server treffen, nicht den echten/Default-Socket.
#
# WICHTIG, gemessen (2026-08-22, unter Last mit 3x10, 8x10 und 6x10 parallelen
# Laeufen: 3 Treffer in 170 mit dieser direkt aufrufenden Fassung, 1 Treffer in
# 110 mit der vorherigen `tm send-keys`-Fassung -- keine Verbesserung der Rate):
# Diese Umstellung macht den Test naeher am echten Ablauf und beseitigt eine
# unnoetige Verzoegerungsquelle, schliesst das Wettrennen aber NICHT. Der
# eigentliche Engpass liegt in context-guard selbst, nicht im Aufrufweg hier:
# check_worker_results() prueft den Merker frisch unmittelbar vor nudge()
# (Commit 9c7634f), aber nudge() selbst ist danach nicht mehr atomar -- der
# BUSY-Check per `tmux capture-pane` und `schreib_text()` sind eigene
# Unterprozess-Aufrufe, die unter Last selbst wieder auf CPU warten muessen,
# und SOBALD schreib_text() den Text in die Pane geschrieben hat, ist die
# Meldung sichtbar -- ob wb-close in genau diesem Fenster fertig wird oder
# nicht, entscheidet reiner Zufall der Prozess-Planung. Kein Test-seitiges
# Timing kann dieses Fenster schliessen, weil es nicht am Aufruf hier haengt,
# sondern an der Zeit, die der GUARD selbst zwischen Pruefung und sichtbarem
# Tippen braucht. Ein vollstaendiger Schluss braeuchte eine Sperre zwischen
# wb-close's Markierungs-Schreibzugriff und context-guards Pruef-Entscheide-
# Tipp-Kette fuer denselben Worker -- eine echte Nebenlaeufigkeitsaenderung
# im Guard, keine Kleinigkeit, siehe Ergebnisdatei fuer den Vorschlag.
WBCLOSE_OUT="$(HOME="$FAKEHOME" TMUX_BIN="tmux -L $SOCKET" "$WBCLOSE" "$WE" 2>&1)"
warte_auf_bedingung 5 "(g) wb-close setzt die done-notified-Markierung" \
    "[ -n \"\$(find '$FAKEHOME/.local/state/wb-context-guard' -type f -path '*.done-notified/$WE' 2>/dev/null)\" ]" \
  || { echo "  wb-close-Ausgabe: $WBCLOSE_OUT"; }
MARK_E="$(find "$FAKEHOME/.local/state/wb-context-guard" -type f -path "*.done-notified/$WE" 2>/dev/null | head -1)"
[ -n "$MARK_E" ] && ok "(g) wb-close setzt die done-notified-Markierung sofort: $MARK_E" \
                  || bad "(g) keine done-notified-Markierung nach wb-close gefunden -- $WBCLOSE_OUT"
sleep 6   # mehrere Poll-Zyklen abwarten (POLL=2 -> 3 Zyklen), jetzt AB der
          # tatsaechlich bestaetigten Markierung, nicht ab einer geratenen
          # Verzoegerung nach mkresult
NEEDLE_E="Worker $WE is done"
if capture "$ORCH_PANE" | grep -qF "$NEEDLE_E"; then
    bad "(g) Meldung fuer workerE kam trotz wb-close-Markierung -- genau der gemessene Laerm"
else
    ok "(g) keine Meldung fuer workerE (wb-close hat ihn schon als abgeholt markiert)"
fi

echo "-- (h) Guard mit stdout+stderr auf /dev/null schreibt die Fertigmeldung trotzdem ins Log --"
# Deckt log_orch_notify() / ORCH_NOTIFY_LOG ab (context-guard Zeile 363f., Anlass Zeile 352ff.):
# PID 91894 lief mit stdout+stderr auf /dev/null und eine echte Fertigmeldung hinterliess
# nirgends eine Spur. Zweiter Guard hier weg, damit nur ein Poller auf den Orchestrator-Pane
# schreibt -- sonst wuerden zwei Guards um denselben Pane konkurrieren.
kill "$GPID2" 2>/dev/null
warte_auf_bedingung 10 "GPID2 (alter Guard) beendet sich" "! kill -0 '$GPID2' 2>/dev/null"

tm send-keys -t "$GRUNNER" \
    "HOME='$FAKEHOME' PROJECT='$FAKEHOME' POLL=2 WARN_PCT=95 ORCH_PCT=95 EXIT_GRACE=99999 '$TOOL' --auto '$ORCH_PANE' >/dev/null 2>&1 & echo \$! >'$WORK/guard3.pid'" Enter
warte_auf_bedingung 15 "guard3.pid entsteht" "[ -s '$WORK/guard3.pid' ]"
GPID3="$(cat "$WORK/guard3.pid" 2>/dev/null)"
GUARD_PIDS+=("$GPID3")
sleep 2
if kill -0 "$GPID3" 2>/dev/null; then
    ok "(h) Guard mit /dev/null-Stdout gestartet (PID $GPID3)"
else
    bad "(h) Guard mit /dev/null-Stdout nicht gestartet oder sofort beendet"
fi

new_worker_pane "$WH"; WORKERH_PANE="$PANE_ID"
sleep 3   # workerH mind. einmal lebend gesehen, wie bei (d)/(g)
mkresult "$WH"
NEEDLE_H="Worker $WH is done, result at $FAKEHOME/.pi-workers/results/$WH/20260804-000000.md"
if wait_contains "$ORCH_PANE" 15 "$NEEDLE_H"; then
    ok "(h) Meldung fuer workerH kam trotz stdout/stderr auf /dev/null"
else
    bad "(h) keine Meldung fuer workerH -- Pane: $(capture "$ORCH_PANE" | tail -5)"
fi

# warte_auf_bedingung statt Sofort-Check (2026-08-22, Auftrag fertigmeldung): log_orch_notify()
# schreibt die Zeile erst NACHDEM nudge() zurueckgekehrt ist -- und nudge() tippt den Text
# zuerst (das macht wait_contains() oben schon gruen) und schlaeft danach noch eine volle
# Sekunde, bevor es Enter drueckt und zurueckkehrt. Zwischen "Text steht im Pane" und "Zeile
# steht im Log" liegt also planmaessig ueber eine Sekunde -- ein Sofort-Check direkt im
# Anschluss an wait_contains() liest die Logdatei fruehestens gleichzeitig mit ihrem Schreiber
# und ist unter Last (Reproduktion: mehrere parallele Suiten) sporadisch zu frueh dran.
if warte_auf_bedingung 10 "(h) orchestrator-notified.log enthaelt die Fertigmeldung fuer $WH" \
    "grep -qF 'worker $WH fertig' \"\$(find '$FAKEHOME/.local/state/wb-context-guard' -type f -name '*.orchestrator-notified.log' 2>/dev/null | head -1)\" 2>/dev/null"; then
    LOG_H="$(find "$FAKEHOME/.local/state/wb-context-guard" -type f -name '*.orchestrator-notified.log' 2>/dev/null | head -1)"
    ok "(h) orchestrator-notified.log enthaelt die Fertigmeldung trotz /dev/null-Stdout: $LOG_H"
fi

echo "-- (i) die Meldung fordert zu KEINER Handlung auf --"
# Am 05.08. endete jede Fertigmeldung mit "schliesse den Pane mit `wb-close
# <name>`". Der Guard sieht den Pane dabei nie an, und seine Meldung trifft
# spaeter ein als das Ergebnis: hat der Orchestrator es inzwischen gelesen und
# demselben Worker die naechste Aufgabe gegeben, gilt die Aufforderung einem
# arbeitenden Worker. Geprueft wird der Pane-Inhalt, nicht die Quelle -- also
# das, was der Orchestrator tatsaechlich zu lesen bekommt.
ALLES="$(capture "$ORCH_PANE")"
if printf '%s' "$ALLES" | grep -qE 'wb-close|schliesse den Pane'; then
    bad "(i) eine Meldung fordert zum Schliessen eines Panes auf: $(printf '%s' "$ALLES" | grep -oE '.{0,40}(wb-close|schliesse den Pane).{0,40}' | head -1)"
else
    ok "(i) keine Meldung fordert zum Schliessen eines Panes auf"
fi
# Gegenprobe: der Pane traegt ueberhaupt Meldungen, sonst prueft (i) nichts.
if printf '%s' "$ALLES" | grep -qF "is done, result at"; then
    ok "(i) Gegenprobe: es stehen Fertigmeldungen im Pane, (i) prueft also etwas"
else
    bad "(i) Gegenprobe: im Pane steht gar keine Fertigmeldung"
fi

echo "-- (j) jedes Ergebnis genau EINMAL, jedes NEUE Ergebnis wieder --"
# Anlass (2026-08-06): Vier Fertigmeldungen desselben Workers lasen sich wie dieselbe
# Meldung viermal, weil jede von ihnen 'latest.md' nannte statt der Datei dahinter. Der
# Merker haengt seitdem an Pfad UND Zeitstempel, und die Meldung nennt die aufgeloeste
# Datei. Beides wird hier gemessen, in beide Richtungen: nichts doppelt, nichts
# verschluckt.
zaehle_A() { count_occurrences "$ORCH_PANE" "Worker $WA is done"; }
VOR_J="$(zaehle_A)"

# (j1) Ein NEUES Ergebnis desselben Workers -> eine weitere Meldung, und sie nennt die
#      neue Datei, nicht die alte.
printf 'zweiter lauf\n' >"$FAKEHOME/.pi-workers/results/$WA/20260804-111111.md"
ln -sf 20260804-111111.md "$FAKEHOME/.pi-workers/results/$WA/latest.md"
NEEDLE_A2="Worker $WA is done, result at $FAKEHOME/.pi-workers/results/$WA/20260804-111111.md"
if wait_contains "$ORCH_PANE" 25 "$NEEDLE_A2"; then
    ok "(j1) ein NEUES Ergebnis desselben Workers wird gemeldet, mit der neuen Datei im Text"
else
    bad "(j1) das neue Ergebnis von $WA wurde verschluckt"
    zeig=$(capture "$ORCH_PANE" | tail -3); printf '        | %s\n' "$zeig"
fi
NACH_J1="$(zaehle_A)"
[ "$NACH_J1" -eq $((VOR_J + 1)) ] \
    && ok "(j1) genau EINE weitere Meldung ($VOR_J -> $NACH_J1)" \
    || bad "(j1) $((NACH_J1 - VOR_J)) weitere Meldungen statt genau einer"

# (j2) Zwei weitere Polls an derselben Datei -> keine dritte Meldung.
sleep 6
NACH_J2="$(zaehle_A)"
[ "$NACH_J2" -eq "$NACH_J1" ] \
    && ok "(j2) zwei weitere Polls an derselben Datei melden nichts nach ($NACH_J2)" \
    || bad "(j2) dieselbe Datei wurde erneut gemeldet ($NACH_J1 -> $NACH_J2)"

# (j3) DIESELBE Datei, aber nachgeschrieben -> wieder eine Meldung. Der Zweifel faellt
#      hier absichtlich andersherum aus als sonst in diesem Haus: lieber einmal zuviel
#      melden als eine Nachbesserung verschlucken, die niemand mehr sieht.
sleep 1
printf 'nachgetragen\n' >>"$FAKEHOME/.pi-workers/results/$WA/20260804-111111.md"
touch "$FAKEHOME/.pi-workers/results/$WA/20260804-111111.md"
dl=$((SECONDS + 25)); NACH_J3="$NACH_J2"
while [ $SECONDS -lt $dl ]; do
    NACH_J3="$(zaehle_A)"
    [ "$NACH_J3" -gt "$NACH_J2" ] && break
    sleep 1
done
[ "$NACH_J3" -gt "$NACH_J2" ] \
    && ok "(j3) dieselbe Datei mit neuem Zeitstempel wird erneut gemeldet ($NACH_J2 -> $NACH_J3)" \
    || bad "(j3) eine nachgeschriebene Ergebnisdatei wurde verschluckt"

# (j4) Keine einzige Meldung nennt je den Symlink -- er zeigt schon auf das naechste
#      Ergebnis, sobald der Worker weiterarbeitet, und waere damit ein Zeiger ins Leere.
if capture "$ORCH_PANE" | grep -qF "Ergebnis unter $FAKEHOME/.pi-workers/results/$WA/latest.md"; then
    bad "(j4) eine Meldung nennt latest.md statt der Datei dahinter"
else
    ok "(j4) keine Meldung nennt latest.md"
fi

echo "-- (k) latest.md zeigt auf den Platzhalter '.laufend.md' -> KEINE Meldung --"
# Anlass (2026-09-18, Session wb-AI-b310aa-1d39e0): "17:38 worker mobil-spec fertig",
# eine Minute nach dem Spawn -- der Worker hatte gerade erst angefangen. pi-worker
# biegt latest.md WAEHREND der Laufzeit auf ".laufend.md" (siehe pi-worker,
# $PLATZHALTER); die Datei ist nicht leer und passiert damit "-s" anstandslos.
# wb-result kennt diesen Fall seit jeher, der Guard nicht.
new_worker_pane "$WL"; WORKERL_PANE="$PANE_ID"
new_worker_pane "$WM"; WORKERM_PANE="$PANE_ID"
mkdir -p "$FAKEHOME/.pi-workers/results/$WL"
printf '# Worker laeuft\n\nNoch kein Ergebnis -- diese Datei ist ein Platzhalter.\n' \
    >"$FAKEHOME/.pi-workers/results/$WL/.laufend.md"
ln -sf "$FAKEHOME/.pi-workers/results/$WL/.laufend.md" "$FAKEHOME/.pi-workers/results/$WL/latest.md"
# ANKER statt Wartezeit: workerM bekommt im selben Moment ein ECHTES Ergebnis. Seine
# Meldung beweist, dass der Guard einen vollstaendigen check_worker_results-Durchlauf
# gemacht hat, IN DEM workerL schon mit seinem Platzhalter dastand -- ohne diesen Anker
# wuerde ein blosses "sleep" unter Last (gemessene Polls von 3 bis 15 s) den Fall aus
# dem falschen Grund bestehen lassen.
mkresult "$WM"
if wait_contains "$ORCH_PANE" 30 "Worker $WM is done"; then
    ok "(k) Anker: der Guard hat einen vollen Durchlauf gemacht, waehrend workerL den Platzhalter trug"
else
    bad "(k) Anker fehlt -- der Guard hat in der Wartezeit nichts gemeldet, (k) prueft nichts"
fi
if capture "$ORCH_PANE" | grep -qF "Worker $WL is done"; then
    bad "(k) Meldung fuer workerL kam, obwohl latest.md nur auf den Platzhalter zeigt"
else
    ok "(k) keine Meldung, solange latest.md auf '.laufend.md' zeigt"
fi

echo "-- (k2) danach das echte Ergebnis -> die Meldung kommt --"
printf 'fertig\n' >"$FAKEHOME/.pi-workers/results/$WL/20260918-174500.md"
ln -sf 20260918-174500.md "$FAKEHOME/.pi-workers/results/$WL/latest.md"
if wait_contains "$ORCH_PANE" 25 "Worker $WL is done, result at $FAKEHOME/.pi-workers/results/$WL/20260918-174500.md"; then
    ok "(k2) das echte Ergebnis wird gemeldet -- der Platzhalter hat die Meldung nicht verbraucht"
else
    bad "(k2) das echte Ergebnis von $WL wurde verschluckt: $(capture "$ORCH_PANE" | tail -3)"
fi

echo
echo "context-guard Fertigmeldung: $pass ok, $fail fehlgeschlagen"
[ "$fail" -eq 0 ]
