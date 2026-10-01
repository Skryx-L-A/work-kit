#!/usr/bin/env bash
# Tests fuer context-guard: ein SCHREIBVORGANG, DER HAENGT, haelt die Poll-Schleife
# nicht mehr an.
#
# Anlass (2026-08-26, gemessen an der Live-Umgebung von host2): die Wache des
# Orchestrator-Panes %2 hat ihre Kontextwarnung bei 76 % voellig korrekt ausgeloest
# und ist danach in dem tmux-Aufruf steckengeblieben, mit dem sie sie zustellen
# wollte -- 3 h 42 min in poll(), auf eine Antwort des tmux-Servers, die nie kam
# (PID 2590247, wchan poll_schedule_timeout; darunter wb-pane-write, darunter die
# Wache selbst in do_wait). Weil `nudge()` nie zurueckkam, wurde `warned` nie
# gesetzt, stand keine Zeile im Protokoll -- das `echo` steht HINTER dem `nudge` --
# und die Notbremse bei 80 % kam nie. Die Wache hat EINE Schleife: mit ihr standen
# auch alle fuenf bewachten Panes still. Der Orchestrator lief von 76 % auf 92 %,
# und niemand hat es bemerkt, weil eine Wache, die schweigt, genauso aussieht wie
# eine, der nichts auffaellt.
#
# Was hier geprueft wird, ist deshalb ausdruecklich NICHT nur, dass der Aufruf
# zurueckkehrt. Geprueft wird, dass die SCHLEIFE WEITERLAEUFT, waehrend ein
# Schreibvorgang haengt -- daran hat es gefehlt. Gemessen wird das am Herzschlag:
# einer Datei, deren Inhalt nach JEDEM vollstaendigen Poll neu geschrieben wird.
# Ein lebender Prozess in `ps` beweist gar nichts; genau das war in jener Nacht zu
# sehen, und es sah gesund aus.
#
# GEGENPROBE (Mutation), mit der dieser Test seine eigene Schaerfe belegt:
#   PANE_WRITE_TIMEOUT=9999 ./test-context-guard-haengender-schreibvorgang.sh
# Damit ist die Zeitschranke praktisch aufgehoben -- der Fehler von damals ist
# wiederhergestellt -- und Teil (c) MUSS rot werden. Wird er das nicht, prueft
# dieser Test nichts.
#
# Isolation wie in den Schwester-Tests: eigener Socket, eigenes HOME. Der
# Orchestrator-Pane ist ein 'cat'-Sink, damit nichts, was hineingeschrieben wird,
# je als Kommando laeuft.
unset TMUX TMUX_PANE
set -uo pipefail

MARK="${LIVE_MARKER:+-$LIVE_MARKER}"
SOCKET="wbtest-haengt$MARK-$$"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${WB_CONTEXT_GUARD:-$REPO/context-guard}"
echo "Geprueft: $TOOL"
FAKEHOME="$(mktemp -d)"
WORK="$(mktemp -d)"

# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$FAKEHOME" wb-pane-write wb-mensch context-guard wb-state \
    || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }

# DER HAENGENDE SCHREIBVORGANG. wb-pane-write wird durch ein Skript ersetzt, das
# NIE zurueckkehrt -- genau das Verhalten des echten Aufrufs in jener Nacht. Es
# ist bewusst der Weg ueber wb-pane-write und nicht ueber tmux selbst: dort hing
# es, und dort geht jeder Tastendruck der Wache durch.
# ERST DEN SYMLINK BRECHEN. werkzeuge_installieren legt die Werkzeuge als `ln -sf`
# auf den ARBEITSBAUM -- ein `cat >` auf diesen Pfad folgt dem Symlink und
# ueberschreibt die echte Datei im Repo. Genau das ist am 26.08. beim ersten Lauf
# dieses Tests passiert: shell/wb-pane-write stand danach als Attrappe im Repo
# ("sleep 100000"), und der naechste Test sah wie ein Fehler der Wache aus, obwohl
# er ein Fehler des Tests war. Die Live-Installation unter ~/.local/bin ist eine
# eigene Datei und blieb unberuehrt; das war Glueck und nicht Vorsorge.
rm -f "$FAKEHOME/.local/bin/wb-pane-write"
cat >"$FAKEHOME/.local/bin/wb-pane-write" <<'STUB'
#!/usr/bin/env bash
# Test-Attrappe: haengt fuer immer, wie der echte Aufruf am 25.08.2026 um 23:26:48.
# KEIN stiller Rueckfall auf /dev/null (Einwand von Gewinnmitnahme, 26.08.): waere
# eine der beiden Variablen nicht gesetzt, liefe die Buchfuehrung ins Leere, das
# Aufraeumen faende nichts, die Attrappe bliebe stehen -- und der Lauf meldete
# trotzdem gruen. Das ist genau die Fehlerform, gegen die dieser Test geschrieben
# ist: nicht messen zu koennen sieht aus wie nichts zu melden. Hier bricht es
# stattdessen laut ab, und der Test faellt sichtbar um, statt still zu luegen.
: "${STUB_LOG:?Test-Attrappe ohne STUB_LOG -- der Aufrufer reicht die Variable nicht durch}"
: "${STUB_PIDS:?Test-Attrappe ohne STUB_PIDS -- die Attrappe waere danach nicht mehr zu beenden}"
echo "$(date +%s) $*" >>"$STUB_LOG"
# Die eigene PID notieren und DANN exec: nach dem exec ist diese PID das
# wartende `sleep` selbst, also genau der Prozess, den das Aufraeumen beenden
# muss. Ohne das exec bliebe ein Kind uebrig, das den Vater ueberlebt.
echo "$$" >>"$STUB_PIDS"
exec sleep 100000
STUB
chmod +x "$FAKEHOME/.local/bin/wb-pane-write"
STUB_LOG="$WORK/stub.log"; : >"$STUB_LOG"
STUB_PIDS="$WORK/stub.pids"; : >"$STUB_PIDS"

# Die Zeitschranke, gegen die geprueft wird. Klein, damit der Test in Sekunden
# laeuft statt in Minuten. Ueberschreibbar -- genau das ist die Mutation oben.
PANE_WRITE_TIMEOUT="${PANE_WRITE_TIMEOUT:-3}"
# Wie lange dieser Test wartet, bevor er urteilt. BEWUSST NICHT an die Schranke
# gekoppelt: bei der Mutation oben ist die Schranke 9999s, und ein Test, der so
# lange wartet, laeuft nicht in Rot, sondern gar nicht -- er stuende ewig, und
# genau diese Sorte Pruefung faellt hier gerade auf. Gedeckelt auf 13 Sekunden;
# solange die echte Schranke darunter liegt, wartet der Test nur, was noetig ist.
WARTEZEIT=$(( PANE_WRITE_TIMEOUT + 3 )); [ "$WARTEZEIT" -gt 13 ] && WARTEZEIT=13

pass=0; fail=0
GUARD_PIDS=()
tm() { tmux -L "$SOCKET" "$@"; }
cleanup() {
    for p in "${GUARD_PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done
    # Die Attrappen-Prozesse haengen als Kinder der Wache und ueberleben deren
    # Ende -- sie waeren sonst Waisen. Beendet werden sie ueber die PIDs, die sie
    # SELBST notiert haben, nicht ueber ein Suchmuster: ein `pkill -f` auf einen
    # allgemeinen Text wie 'sleep 100000' trifft, was zufaellig passt, auch
    # fremde Prozesse. test-parallel-sicher-achsen.sh hat genau das an dieser
    # Datei gemeldet (26.08., Befund von Gewinnmitnahme) -- eine Pruefung, die
    # verhindern soll, dass ein abgebrochener Lauf Fremdes festhaelt, darf nicht
    # selbst Fremdes beenden.
    if [ -s "${STUB_PIDS:-/dev/null}" ]; then
        while read -r stubpid; do
            [ -n "$stubpid" ] && kill "$stubpid" 2>/dev/null
        done < "$STUB_PIDS"
    fi
    tmux_socket_beenden_ohne_reste "$SOCKET"
    local deadline=$((SECONDS + 5))
    while [ $SECONDS -lt $deadline ] && tm list-sessions >/dev/null 2>&1; do
        tm kill-server 2>/dev/null; sleep 0.3
    done
    rm -rf "$FAKEHOME" "$WORK"
}
# INT und TERM ausdruecklich mit: ohne sie laesst ein abgebrochener Lauf seinen
# tmux-Testserver stehen -- und mit ihm jede Dateisperre, die er geerbt hat.
# Gemessen am 26.08., als genau das die testlauf-Sperre blockierte.
trap cleanup INT TERM EXIT

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

herzschlag_datei() { find "$FAKEHOME/.local/state/wb-context-guard" -name '*.heartbeat' 2>/dev/null | head -1; }
herzschlag_wert()  { local f; f="$(herzschlag_datei)"; [ -n "$f" ] && cat "$f" 2>/dev/null; }

# Wartet, bis der Herzschlag WEITERGEZAEHLT hat -- nicht, bis er da ist.
herzschlag_schlaegt() {   # <sekunden> -> 0, wenn der Wert sich erhoeht hat
    local dl=$((SECONDS + $1)) vorher
    vorher="$(herzschlag_wert)"
    [ -n "$vorher" ] || return 1
    while [ $SECONDS -lt $dl ]; do
        local jetzt; jetzt="$(herzschlag_wert)"
        [ -n "$jetzt" ] && [ "$jetzt" -gt "$vorher" ] 2>/dev/null && return 0
        sleep 0.5
    done
    return 1
}

# Eine Claude-Statuszeile, wie sie wirklich aussieht (abgenommen an Pane %2 am
# 26.08.). Die beiden Prozentzahlen hinten sind die Kontingente und duerfen NIE
# als Kontext gelesen werden -- sie stehen hier absichtlich mit drin.
statuszeile() {   # <benutzt> -> die Zeile
    printf '  Opus 5 xhigh · …/a machine-bound project/Polarschern main · ▓▓▓▓▓▓▓▓▓░ %s/1.0M · 5h 28%%→03:30 · 7d 34%%' "$1"
}

echo "== context-guard: ein haengender Schreibvorgang haelt die Schleife nicht an =="
tm kill-server 2>/dev/null
tm new-session -d -s wb -x 200 -y 8 -c /tmp
tmux_live_hooks_kappen "$SOCKET"

ORCH_PANE="$(tm list-panes -t wb -F '#{pane_id}')"
tm respawn-pane -k -t "$ORCH_PANE" "sh -c 'stty -echo; exec cat'"
tm set-option -p -t "$ORCH_PANE" @wb_role orchestrator
sleep 0.5

# Ausgangslage: wenig Kontext. Die Wache hat nichts zu melden und schreibt nicht.
tm send-keys -t "$ORCH_PANE" -l "$(statuszeile 100k)"; tm send-keys -t "$ORCH_PANE" Enter
tm send-keys -t "$ORCH_PANE" -l "  ⏵⏵ bypass permissions on · 1 shell"; tm send-keys -t "$ORCH_PANE" Enter
sleep 0.5

tm new-window -t wb -n guardrunner -c /tmp
GRUNNER="$(tm display -p -t wb:guardrunner '#{pane_id}')"
tm send-keys -t "$GRUNNER" \
    "HOME='$FAKEHOME' PROJECT='$FAKEHOME' POLL=2 PANE_WRITE_TIMEOUT=$PANE_WRITE_TIMEOUT STUB_LOG='$STUB_LOG' STUB_PIDS='$STUB_PIDS' WARN_PCT=95 ORCH_PCT=75 EXIT_GRACE=99999 '$TOOL' --auto '$ORCH_PANE' >'$WORK/guard.log' 2>&1 & echo \$! >'$WORK/guard.pid'" Enter
warte_auf_bedingung 15 "guard.pid entsteht" "[ -s '$WORK/guard.pid' ]"
GPID="$(cat "$WORK/guard.pid" 2>/dev/null)"
GUARD_PIDS+=("$GPID")
warte_auf_bedingung 15 "Wache meldet orchestrator= im Protokoll" \
    "grep -q '^context-guard: orchestrator=' '$WORK/guard.log'" "$WORK/guard.log" \
  && ok "Wache gestartet (PID $GPID)"

echo "-- (a) im Normalbetrieb schlaegt der Herzschlag --"
if warte_auf_bedingung 20 "Herzschlag-Datei entsteht" "[ -n \"\$(find '$FAKEHOME/.local/state/wb-context-guard' -name '*.heartbeat' 2>/dev/null)\" ]"; then
    if herzschlag_schlaegt 15; then
        ok "(a) der Herzschlag zaehlt weiter -- die Schleife pollt"
    else
        bad "(a) der Herzschlag steht schon ohne haengenden Schreibvorgang"
    fi
else
    bad "(a) keine Herzschlag-Datei -- ohne sie ist ein Stillstand nicht von Ruhe zu unterscheiden"
fi

echo "-- (b) bei hohem Kontext wird geschrieben, und der Schreibvorgang haengt --"
tm send-keys -t "$ORCH_PANE" -l "$(statuszeile 900k)"; tm send-keys -t "$ORCH_PANE" Enter
tm send-keys -t "$ORCH_PANE" -l "  ⏵⏵ bypass permissions on · 1 shell"; tm send-keys -t "$ORCH_PANE" Enter
if warte_auf_bedingung 20 "die Wache versucht zu schreiben" "[ -s '$STUB_LOG' ]"; then
    ok "(b) die Wache hat den Schreibvorgang begonnen (Attrappe gerufen: $(head -1 "$STUB_LOG"))"
else
    bad "(b) die Wache hat bei 90 % gar nicht erst geschrieben -- dann prueft (c) nichts"
fi

echo "-- (c) DER KERN: die Schleife laeuft weiter, obwohl der Schreibvorgang haengt --"
# Erst muss die Zeitschranke ueberhaupt greifen koennen: Poll (2s) + Schranke.
sleep "$WARTEZEIT"
if herzschlag_schlaegt 25; then
    ok "(c) der Herzschlag zaehlt weiter, waehrend der Schreibvorgang haengt"
else
    bad "(c) DER HERZSCHLAG STEHT -- die Wache haengt am Schreibvorgang, genau wie am 25.08."
fi

echo "-- (d) der Abbruch steht LAUT im Protokoll, nicht nur im Verhalten --"
if grep -q 'nicht geantwortet und wurde abgebrochen' "$WORK/guard.log"; then
    ok "(d) der abgebrochene Schreibvorgang ist protokolliert"
else
    bad "(d) nichts im Protokoll -- ein stiller Abbruch ist derselbe Fehler in leise. Protokoll: $(tail -3 "$WORK/guard.log")"
fi

echo "-- (e) auch die Warnung selbst bleibt unerledigt statt still verlorenzugehen --"
# Weil `warned` nur auf dem Erfolgspfad gesetzt wird, versucht die Wache es beim
# naechsten Poll ERNEUT. Genau das gehoert so: eine nicht zugestellte Warnung darf
# nicht als zugestellt gelten.
sleep "$WARTEZEIT"
N=$(wc -l <"$STUB_LOG" | tr -d ' ')
if [ "$N" -ge 2 ]; then
    ok "(e) die Zustellung wird wiederholt versucht ($N Versuche)"
else
    bad "(e) nur $N Versuch -- eine verlorene Warnung darf nicht als erledigt gelten"
fi

echo
echo "== $pass ok, $fail FAIL =="
[ "$fail" = 0 ]
