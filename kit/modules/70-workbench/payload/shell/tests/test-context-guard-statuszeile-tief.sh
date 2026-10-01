#!/usr/bin/env bash
# Tests fuer context-guard: eine Statuszeile, die aus den letzten FUENF Zeilen
# herausgerutscht ist, wird trotzdem gelesen -- und ein alter, hochgescrollter
# Balken wird dabei NICHT verwechselt.
#
# Anlass (2026-08-26, gemessen an den fuenf lebenden Claude-Panes von host2): die
# Wache liest die Auslastung aus `capture-pane | tail -5`. In allen fuenf Panes
# stand die Statuszeile zwei bis drei Zeilen ueber dem unteren Rand -- also mit
# zwei bis drei Zeilen Luft. Ein zusaetzlicher Hinweis unter der Eingabezeile
# ("Press up to edit queued messages") oder eine ueber mehrere Zeilen
# umgebrochene Eingabe reicht, um sie herauszudruecken. Dann meldet die Wache
# den Pane als BLIND, obwohl er breit genug ist und die Zahlen dastehen -- und
# eine Wache, die einen lesbaren Pane fuer unlesbar haelt, warnt nie.
# Im Protokoll der Nacht steht genau so ein einzelner BLIND-Eintrag (04:06),
# waehrend Quelle 1 denselben Pane Stunden spaeter einwandfrei las.
#
# Der zweite Teil ist der Preis dafuer, und er wird hier mitgeprueft: tiefer zu
# suchen darf NICHT dazu fuehren, dass ein alter Balken aus dem Verlauf gelesen
# wird. Am 25.07. hat genau das eine Kompaktierung ausgeloest, die nicht haette
# stattfinden duerfen (ein hochgescrollter Balken las 80 %, die lebende
# Statuszeile sagte 76 %). Deshalb zaehlt in der tiefen Suche nur eine Zeile,
# die Zahlenpaar UND Balken zusammen traegt -- also wirklich eine Statuszeile.
#
# GEGENPROBE (Mutation), mit der dieser Test seine Schaerfe belegt. Mutiert wird
# AN ORT UND STELLE, mit Sicherung und Wiederherstellung:
#   cp shell/context-guard /tmp/sicherung
#   sed -i '/2b) Die Statuszeile/,/^    # 3) last resort/{/^    # 3) last resort/!d}' \
#       shell/context-guard
#   ./test-context-guard-statuszeile-tief.sh ; cp /tmp/sicherung shell/context-guard
# Gemessen am 26.08.: (a) und (c) bleiben gruen, NUR (b) wird rot -- der Test
# trifft also genau das, was er treffen soll. Wird (b) nicht rot, prueft er nichts.
# NICHT ueber WB_CONTEXT_GUARD auf eine Kopie ausserhalb des Arbeitsbaums zeigen:
# wb-pane-write erkennt die Wache am kanonischen Pfad, eine Kopie in /tmp gilt ihm
# als Fremder und wird abgewiesen -- dann faellt AUCH (a) um, und die Mutation
# beweist nichts mehr (gemessen, 26.08.).
unset TMUX TMUX_PANE
set -uo pipefail

MARK="${LIVE_MARKER:+-$LIVE_MARKER}"
SOCKET="wbtest-statustief$MARK-$$"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${WB_CONTEXT_GUARD:-$REPO/context-guard}"
echo "Geprueft: $TOOL"
FAKEHOME="$(mktemp -d)"
WORK="$(mktemp -d)"

# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$FAKEHOME" wb-pane-write wb-mensch context-guard wb-state \
    || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }

pass=0; fail=0
GUARD_PIDS=()
# Kein "${GUARD_PIDS[-1]}" (2026-08-28): der negative Index kam erst mit bash 4.3,
# und /bin/bash ist auf diesem Mac 3.2.57 (Apples letzte GPLv2-Fassung). Unter
# `set -u` war das kein stiller Fehlgriff, sondern ein Abbruch mitten im Lauf --
# "bad array subscript" plus "unbound variable", und die Suite endete nach der
# ersten Zusage. Diese Funktion nennt denselben Eintrag portabel.
letzte_guard_pid() { local n=${#GUARD_PIDS[@]}; (( n > 0 )) && printf '%s' "${GUARD_PIDS[$(( n - 1 ))]}"; }
tm() { tmux -L "$SOCKET" "$@"; }
cleanup() {
    for p in "${GUARD_PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
    tmux_socket_beenden_ohne_reste "$SOCKET"
    local deadline=$((SECONDS + 5))
    while [ $SECONDS -lt $deadline ] && tm list-sessions >/dev/null 2>&1; do
        tm kill-server 2>/dev/null; sleep 0.3
    done
    # Die Socketdatei mitnehmen wie die Schwestersuiten: ohne diese Zeile blieb
    # je Lauf eine tote wbtest-statustief-<pid> in /private/tmp/tmux-<uid>/ liegen
    # (sieben Stueck nach einer Lastmessung am 2026-09-05).
    rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
    rm -rf "$FAKEHOME" "$WORK"
}
# INT und TERM ausdruecklich mit: ohne sie laesst ein abgebrochener Lauf seinen
# tmux-Testserver stehen -- und mit ihm jede Dateisperre, die er geerbt hat.
# Gemessen am 26.08., als genau das die testlauf-Sperre blockierte.
trap cleanup INT TERM EXIT

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

zeile() { tm send-keys -t "$ORCH_PANE" -l "$1"; tm send-keys -t "$ORCH_PANE" Enter; }

# Eine echte Claude-Statuszeile (abgenommen an Pane %2 am 26.08.). Die beiden
# Prozentzahlen hinten sind die KONTINGENTE (5h/7d) und stehen absichtlich mit
# drin: wer sie als Kontext liest, misst etwas voellig anderes.
statuszeile() { printf '  Opus 5 xhigh · …/a machine-bound project/Polarschern main · ▓▓▓▓▓▓▓▓▓░ %s/1.0M · 5h 28%%→03:30 · 7d 34%%' "$1"; }

wache_starten() {   # <logdatei>
    tm send-keys -t "$GRUNNER" \
        "HOME='$FAKEHOME' PROJECT='$FAKEHOME' POLL=2 WARN_PCT=95 ORCH_PCT=75 EXIT_GRACE=99999 '$TOOL' --auto '$ORCH_PANE' >'$WORK/$1' 2>&1 & echo \$! >'$WORK/$1.pid'" Enter
    warte_auf_bedingung 15 "$1.pid entsteht" "[ -s '$WORK/$1.pid' ]"
    GUARD_PIDS+=("$(cat "$WORK/$1.pid" 2>/dev/null)")
}

echo "== context-guard: Statuszeile ausserhalb der letzten fuenf Zeilen =="
tm kill-server 2>/dev/null
tm new-session -d -s wb -x 200 -y 16 -c /tmp
tmux_live_hooks_kappen "$SOCKET"

ORCH_PANE="$(tm list-panes -t wb -F '#{pane_id}')"
tm respawn-pane -k -t "$ORCH_PANE" "sh -c 'stty -echo; exec cat'"
tm set-option -p -t "$ORCH_PANE" @wb_role orchestrator
sleep 0.5
tm new-window -t wb -n guardrunner -c /tmp
GRUNNER="$(tm display -p -t wb:guardrunner '#{pane_id}')"

echo "-- (a) der Normalfall: Statuszeile dicht am Rand wird von Quelle 1 gelesen --"
zeile "$(statuszeile 900k)"
zeile "  ⏵⏵ bypass permissions on · 1 shell"
wache_starten guard_a.log
if warte_auf_bedingung 20 "Wache meldet 90% aus Quelle 'exact'" \
     "grep -qE 'orchestrator .* at 90% \(exact\)' '$WORK/guard_a.log'" "$WORK/guard_a.log"; then
    ok "(a) Quelle 1 liest die Statuszeile am Rand"
else
    bad "(a) Quelle 1 hat nicht gelesen -- Protokoll: $(tail -3 "$WORK/guard_a.log")"
fi
kill "$(letzte_guard_pid)" 2>/dev/null; sleep 0.5

echo "-- (b) DER KERN: dieselbe Statuszeile, aus den letzten fuenf Zeilen gedraengt --"
tm respawn-pane -k -t "$ORCH_PANE" "sh -c 'stty -echo; exec cat'"
tm set-option -p -t "$ORCH_PANE" @wb_role orchestrator
sleep 0.5
zeile "$(statuszeile 900k)"
zeile "  ⏵⏵ bypass permissions on · 1 shell"
# Sechs Zeilen darunter -- so, wie eine ueber mehrere Zeilen umgebrochene Eingabe
# oder ein zusaetzlicher Hinweis sie erzeugt. Keine davon traegt Zahlen.
for i in 1 2 3 4 5 6; do zeile "❯ Press up to edit queued messages ($i)"; done
sleep 0.5
TIEFE=$(tm capture-pane -p -t "$ORCH_PANE" | tac | grep -nE '[0-9]+[kKmM]/[0-9.]+[kKmM]' | head -1 | cut -d: -f1)
echo "     (Statuszeile steht $TIEFE Zeilen ueber dem unteren Rand)"
[ -n "$TIEFE" ] && [ "$TIEFE" -gt 5 ] \
  && ok "(b) Vorbedingung: die Statuszeile liegt wirklich ausserhalb der letzten fuenf Zeilen" \
  || bad "(b) Vorbedingung verfehlt (Tiefe '$TIEFE') -- der Test prueft dann nicht, was er soll"
wache_starten guard_b.log
if warte_auf_bedingung 25 "Wache meldet 90% aus der tiefen Suche" \
     "grep -qE 'orchestrator .* at 90% \(exact-tief\)' '$WORK/guard_b.log'" "$WORK/guard_b.log"; then
    ok "(b) die herausgedraengte Statuszeile wird gelesen"
else
    bad "(b) NICHT GELESEN -- der Pane gilt als blind, obwohl die Zahlen dastehen. Protokoll: $(tail -3 "$WORK/guard_b.log")"
fi
kill "$(letzte_guard_pid)" 2>/dev/null; sleep 0.5

echo "-- (c) ein alter Balken OHNE Zahlenpaar wird nicht als Statuszeile gelesen --"
tm respawn-pane -k -t "$ORCH_PANE" "sh -c 'stty -echo; exec cat'"
tm set-option -p -t "$ORCH_PANE" @wb_role orchestrator
sleep 0.5
# Ein hochgescrollter Balken aus dem Verlauf, wie er nach einem Bildschirmaufbau
# stehenbleibt -- ohne Zahlenpaar. Er darf NICHT als 80 % gelesen werden.
zeile "  ▓▓▓▓▓▓▓▓░░ (ein alter Balken aus dem Verlauf, ohne Zahlen)"
for i in 1 2 3 4 5 6; do zeile "irgendeine Ausgabe ($i)"; done
sleep 0.5
wache_starten guard_c.log
sleep 8
if grep -qE 'orchestrator .* at 80% \(exact-tief\)' "$WORK/guard_c.log"; then
    bad "(c) ein alter Balken wurde als Statuszeile gelesen -- genau der Fehlgriff vom 25.07."
else
    ok "(c) der alte Balken wurde nicht als Statuszeile gelesen"
fi
# Die Wache aus (c) muss weg, BEVOR (d) eine neue startet: seit dem 08.08. startet
# eine zweite Wache fuer dieselbe Workbench-Instanz nicht, sondern meldet die erste
# und endet mit 0. Ohne dieses kill lief (d) gegen das Protokoll von (c).
kill "$(letzte_guard_pid)" 2>/dev/null; sleep 2

echo "-- (d) ein zu kleiner Pane wird mit seiner GEMESSENEN Groesse gemeldet --"
# Anlass (26.08.): die BLIND-Meldung riet die Ursache ("Vermutlich schmaler als
# minWorkerPaneWidth=80 Spalten — mit wb-grid gegenpruefen") und lag zweimal daneben.
# Sie nannte nur die Breite, obwohl auch die HOEHE reicht (Pane %15 war 40x4), und
# sie zeigte auf wb-grid, obwohl die Groesse von einem tmux-Client kam. Zwei Sessions
# mussten von Hand vermessen werden, um das zu sehen. Die Zahl steht in einem
# einzigen tmux-Aufruf da.
# GEGENPROBE: in announce_blind() die Zeile mit 'Gemessen:' wieder durch den alten
# Satz ersetzen -- dann MUSS (d) rot werden.
KLEIN="$(tm split-window -t "$ORCH_PANE" -l 3 -P -F '#{pane_id}' "sh -c 'stty -echo; exec cat'")"
tm set-option -p -t "$KLEIN" @wb_role worker
tm set-option -p -t "$KLEIN" @wb_worker winzig
sleep 0.5
MASS="$(tm display -p -t "$KLEIN" '#{pane_width}x#{pane_height}')"
echo "     (der kleine Pane misst $MASS)"
wache_starten guard_d.log
if warte_auf_bedingung 25 "BLIND-Meldung nennt $MASS" \
     "grep -qF 'Gemessen: $MASS Zeichen' '$WORK/guard_d.log'" "$WORK/guard_d.log"; then
    ok "(d) die BLIND-Meldung nennt die gemessene Groesse ($MASS), statt sie zu raten"
else
    bad "(d) die Groesse wird geraten statt gemessen: $(grep -m1 winzig "$WORK/guard_d.log" | cut -c1-200)"
fi
kill "$(letzte_guard_pid)" 2>/dev/null; sleep 0.5

echo "-- (e) ein Pane OHNE Agenten wird einmal benannt und danach uebergangen --"
# Anlass (26.08., Einwand von Polarschern): der Mac-Spiegel %5 ist eine nackte
# `bash` in einem ssh-Aufruf. Sie hat keine Statuszeile und wird nie eine haben.
# Die wiederholte Blindheitsmeldung -- richtig fuer einen Agenten-Pane -- waere
# ausgerechnet dort am lautesten, wo sie nichts bedeutet, und genau so gewoehnt
# man sich das Hinsehen ab. Geprueft wird beides: dass er EINMAL genannt wird
# (nicht stillschweigend uebergangen) und dass er NICHT als BLIND zaehlt.
# GEGENPROBE: in announce_blind() den Ausstieg 'kein Agenten-Pane' entfernen --
# dann meldet der Pane BLIND und (e) wird rot.
tm respawn-pane -k -t "$ORCH_PANE" "sh -c 'stty -echo; exec cat'"
tm set-option -p -t "$ORCH_PANE" @wb_role orchestrator
sleep 0.5
zeile "$(statuszeile 900k)"
zeile "  ⏵⏵ bypass permissions on · 1 shell"
# Eine Schale, die eine Schale BLEIBT. `bash -lc 'sleep 600'` waere keine: bash
# ersetzt sich bei einem einzelnen Kommando durch dieses, und `pane_current_command`
# meldete dann `sleep`. Gemessen am 26.08. -- der erste Anlauf dieses Teils ist
# genau daran gescheitert, und zwar am Testaufbau, nicht an der Wache.
SCHALE="$(tm split-window -t "$ORCH_PANE" -l 6 -P -F '#{pane_id}' "bash -lc 'while :; do sleep 5; done'")"
tm set-option -p -t "$SCHALE" @wb_role worker
tm set-option -p -t "$SCHALE" @wb_worker spiegel
sleep 1
wache_starten guard_e.log
if warte_auf_bedingung 25 "die Schale wird als Nicht-Agent benannt" \
     "grep -q 'kein Agenten-Pane' '$WORK/guard_e.log'" "$WORK/guard_e.log"; then
    ok "(e) der Pane ohne Agenten wird benannt, nicht stillschweigend uebergangen"
else
    bad "(e) gar keine Meldung — stilles Uebergehen ist so schlecht wie lautes Fehlmelden: $(tail -3 "$WORK/guard_e.log")"
fi
if grep -q "spiegel .*: BLIND" "$WORK/guard_e.log"; then
    bad "(e) der Pane ohne Agenten wird trotzdem als BLIND gemeldet — genau das Geraeusch, das gemeint war"
else
    ok "(e) er zaehlt nicht als BLIND und wird deshalb auch nicht wiederholt gemeldet"
fi
N_VORHER=$(grep -c 'kein Agenten-Pane' "$WORK/guard_e.log")
sleep 8   # mehrere weitere Polls
N_NACHHER=$(grep -c 'kein Agenten-Pane' "$WORK/guard_e.log")
[ "$N_VORHER" = "$N_NACHHER" ] \
  && ok "(e) auch nach weiteren Polls genau $N_NACHHER Meldung(en) — er wird uebergangen" \
  || bad "(e) die Meldung wiederholt sich ($N_VORHER -> $N_NACHHER)"
kill "$(letzte_guard_pid)" 2>/dev/null; sleep 0.5

echo
echo "== $pass ok, $fail FAIL =="
[ "$fail" = 0 ]
