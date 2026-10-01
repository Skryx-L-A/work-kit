#!/usr/bin/env bash
# Tests fuer wb-ereignisse (Ereignisstrom) und wb-do (Spawn-Befehl).
#
# Gemessen wird, was der Auftrag verlangt: fuer JEDE der vier Ereignisarten wird
# das Ereignis wirklich hergestellt, die Zeile muss kommen, und genau einmal.
# Dazu: derselbe Anlass zweimal (keine zweite Zeile), ein NEUER Anlass (wieder
# eine), Neustart des Beobachters (kein Nachmelden der Vergangenheit), drei
# Fehlerfaelle (tmux kurz unerreichbar, Verzeichnis fehlt, Datei verschwindet
# zwischen zwei Pruefungen) und die LATENZ zwischen dem Anlegen der
# Ergebnisdatei und der Zeile.
#
# Isolation: eigener tmux-Socket (`wbtest-…`), eigenes HOME (`mktemp -d`). Die
# laufende Sitzung, ihr Steuersocket und Fenster des Nutzers werden nicht beruehrt.
# Der Beobachter laeuft in einem Pane DIESES Testservers -- seine eigenen
# ungeflaggten `tmux`-Aufrufe reden sonst mit dem Live-Socket. Die Worker-Panes
# sind `cat` statt einer Shell: getippter Text darf nie als Kommando laufen.
#
# Zwei Stellen arbeiten mit ZURUECKDATIERTEN Zeitstempeln statt mit echter
# Wartezeit -- der Transcript-mtime und der Bewegungsmerker des Panes. Das ist
# kein Vortaeuschen: genau diese beiden Zeitstempel SIND das Mass, an dem der
# Stillstand haengt, und die Schwelle, die Kindprozess-Bedingung und die
# Anlass-Buchfuehrung laufen unveraendert durch. Der ungekuerzte Weg mit echter
# Wartezeit steht im Dauerlauf (`--dauerlauf`), der einmal von Hand laeuft.
#
#   shell/tests/test-ereignisse.sh              schnelle Suite (~40 s)
#   shell/tests/test-ereignisse.sh --dauerlauf  zusaetzlich >10 min Dauerlauf
unset TMUX TMUX_PANE
set -uo pipefail

DAUERLAUF=0
[ "${1:-}" = "--dauerlauf" ] && DAUERLAUF=1

MARK="${LIVE_MARKER:+-$LIVE_MARKER}"
SOCKET="wbtest-ereignisse$MARK-$$"
SESS="wb-ereignistest$MARK-$$"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${WB_EREIGNISSE:-$REPO/wb-ereignisse}"
WBDO="${WB_DO:-$REPO/wb-do}"
echo "Geprueft: $TOOL"
echo "          $WBDO"

FAKEHOME="$(mktemp -d)"
WORK="$(mktemp -d)"
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$FAKEHOME" wb-state wb-ereignisse wb-do \
    || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
# Kit: wb-do finds a local model's harness in the registry (no built-in local aliases).
mkdir -p "$FAKEHOME/.claude/workbench"
cp "$(dirname "${BASH_SOURCE[0]}")/../models.default.json" "$FAKEHOME/.claude/workbench/models.json"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

tm() { tmux -L "$SOCKET" "$@"; }
cleanup() {
    tmux_socket_beenden_ohne_reste "$SOCKET"
    local deadline=$((SECONDS + 5))
    while [ $SECONDS -lt $deadline ] && tm list-sessions >/dev/null 2>&1; do
        tm kill-server 2>/dev/null
        sleep 0.3
    done
    tm list-sessions >/dev/null 2>&1 \
        && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
    rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
    rm -rf "$FAKEHOME" "$WORK"
}
trap cleanup EXIT

jetzt_ms() { /usr/bin/python3 -c 'import time; print(int(time.time()*1000))'; }
zeilen()   { grep -cF "$1" "$OUT" 2>/dev/null | tr -d ' '; }
warte_auf() {   # <text> <sekunden>
    local dl=$((SECONDS + $2))
    while [ $SECONDS -lt $dl ]; do
        grep -qF "$1" "$OUT" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}

# ---------------------------------------------------------------- Testserver

HOME="$FAKEHOME" tm new-session -d -s "$SESS" -n main cat \
    || { echo "tmux-Testserver liess sich nicht starten" >&2; exit 1; }
tmux_live_hooks_kappen "$SOCKET"   # sonst greifen echtes wb-grid/wb-autorevive in die hier gepruefte Pane-Lebensdauer ein
ORCH=$(tm list-panes -t "=$SESS" -F '#{pane_id}' | head -1)
tm set -p -t "$ORCH" @wb_role orchestrator
# Serverweit, nicht erst nach dem Anlegen: ein Kommando, das sofort endet (w5),
# nimmt seinen Pane sonst mit, bevor die Option ueberhaupt gesetzt werden kann --
# und genau dieser tote Pane ist der Testfall.
tm set -g remain-on-exit on

# Jeder Worker bekommt ein EIGENES Fenster, nicht einen Split: ein abgehaengtes
# tmux-Fenster ist 80x24 und hat nach drei Splits keinen Platz mehr ("no space
# for a new pane"). `list-panes -s` findet sie sessionweit ohnehin.
neuer_worker() {   # <name> [kommando] -> pane-id
    local name="$1" kmd="${2:-cat}" pane
    pane=$(tm new-window -d -t "=$SESS:" -P -F '#{pane_id}' "$kmd")
    tm set -p -t "$pane" @wb_role worker
    tm set -p -t "$pane" @wb_worker "$name"
    tm set -p -t "$pane" remain-on-exit on
    printf '%s' "$pane"
}

# Ergebnisdatei wie ein echter Worker sie schreibt: <zeitstempel>.md plus
# latest.md-Symlink. Daneben liegen im Betrieb <zeitstempel>.auftrag.txt und
# auftraege.tsv -- die werden hier mit angelegt, denn genau sie duerfen NICHT
# als Ergebnis zaehlen.
ergebnis() {   # <name> <stempel> [text]
    local d="$FAKEHOME/.pi-workers/results/$1"
    mkdir -p "$d"
    printf 'Auftrag\n' >"$d/$2.auftrag.txt"
    printf 'x\t%s\n' "$2" >>"$d/auftraege.tsv"
    printf '%s\n' "${3:-WHAT: fertig}" >"$d/$2.md"
    ln -sf "$d/$2.md" "$d/latest.md"
    printf '%s' "$d/$2.md"
}

# ---------------------------------------------------------------- Beobachter

OUT="$WORK/strom.txt"; ERRF="$WORK/strom.err"
: >"$OUT"; : >"$ERRF"
cat >"$WORK/starte.sh" <<EOF
#!/bin/bash
export HOME="$FAKEHOME"
export PATH="$WORK/bin:\$PATH"
exec "$TOOL" --session "$SESS" --intervall 1 >>"\$1" 2>>"\$2"
EOF
chmod +x "$WORK/starte.sh"
mkdir -p "$WORK/bin"

beobachter_start() {   # [out] [err]
    tm new-window -d -t "=$SESS:" -n beob \
        "bash $WORK/starte.sh '${1:-$OUT}' '${2:-$ERRF}'"
    local dl=$((SECONDS + 10))
    while [ $SECONDS -lt $dl ]; do
        [ -s "$FAKEHOME/.local/state/wb-ereignisse"/*/pid ] 2>/dev/null && return 0
        sleep 0.2
    done
    return 0
}
beobachter_pid() { cat "$FAKEHOME/.local/state/wb-ereignisse"/*/pid 2>/dev/null | head -1; }
beobachter_stop() {
    local p; p=$(beobachter_pid)
    tm kill-window -t "=$SESS:beob" 2>/dev/null
    [ -n "$p" ] && kill "$p" 2>/dev/null
    local dl=$((SECONDS + 5))
    while [ $SECONDS -lt $dl ]; do
        [ -n "$p" ] && kill -0 "$p" 2>/dev/null || return 0
        sleep 0.2
    done
    return 1
}

echo
echo "== wb-ereignisse: die vier Ereignisarten =="

# Vorgeschichte, die NICHT nachgemeldet werden darf: ein Worker, der lange vor
# dem Start des Beobachters fertig war.
ALT=$(neuer_worker alt)
ALTDATEI=$(ergebnis alt 20260101-000000)
touch -t 202601010000 "$ALTDATEI"

W1=$(neuer_worker w1)
W2=$(neuer_worker w2)
W4=$(neuer_worker w4)
W5=$(neuer_worker w5 'sh -c "exit 0"')   # stirbt sofort, Pane bleibt (remain-on-exit)

beobachter_start
sleep 3

# ---- (1) fertig, mit Latenzmessung -------------------------------------------
T0=$(jetzt_ms)
D1=$(ergebnis w1 20260807-000100)
if warte_auf "fertig  w1  $D1" 20; then
    T1=$(jetzt_ms)
    LATENZ_MS=$((T1 - T0))
    ok "fertig wird gemeldet (Latenz ${LATENZ_MS} ms)"
else
    LATENZ_MS=-1
    bad "fertig wird gemeldet"
fi

sleep 4
[ "$(zeilen "fertig  w1")" = 1 ] \
    && ok "derselbe Anlass meldet kein zweites Mal" \
    || bad "derselbe Anlass meldet kein zweites Mal (Zeilen: $(zeilen "fertig  w1"))"

# Neuer Anlass: ein ZWEITES Ergebnis desselben Workers.
D2=$(ergebnis w1 20260807-000200)
if warte_auf "fertig  w1  $D2" 20; then
    ok "ein neues Ergebnis ist ein neuer Anlass"
else
    bad "ein neues Ergebnis ist ein neuer Anlass"
fi
[ "$(zeilen "fertig  w1")" = 2 ] \
    && ok "genau zwei Meldungen fuer zwei Ergebnisse" \
    || bad "genau zwei Meldungen fuer zwei Ergebnisse (Zeilen: $(zeilen "fertig  w1"))"

# Der alte Worker bleibt still.
[ "$(zeilen "fertig  alt")" = 0 ] \
    && ok "Vergangenheit vor dem Start wird nicht nachgemeldet" \
    || bad "Vergangenheit vor dem Start wird nicht nachgemeldet"

# latest.md ist kein Ergebnis: die Meldung nennt die AUFGELOESTE Datei.
grep -qF "latest.md" "$OUT" \
    && bad "Meldung nennt latest.md statt der echten Datei" \
    || ok "Meldung nennt die echte Datei, nie latest.md"

# Weder .auftrag.txt noch auftraege.tsv zaehlen als Ergebnis.
grep -qE "fertig .*(auftrag\.txt|auftraege\.tsv)" "$OUT" \
    && bad "Auftragsdateien werden als Ergebnis gezaehlt" \
    || ok "Auftragsdateien zaehlen nicht als Ergebnis"

# ---- (2) braucht Freigabe: Antrag --------------------------------------------
mkdir -p "$FAKEHOME/.pi-workers/requests"
cat >"$FAKEHOME/.pi-workers/requests/w1-20260807.json" <<'EOF'
{"ts":"2026-08-07T00:05:00Z","parent":"w1","parent_model":"claude-opus-5",
 "child_name":"teilstueck","child_model":"claude-haiku-4-5","child_effort":"low",
 "dir":"/tmp","files":["a"],"task":"t","done":"d","why":"w","est":"e"}
EOF
if warte_auf "freigabe  w1  beantragt Worker 'teilstueck'" 20; then
    ok "Antrag wird als Freigabe gemeldet"
else
    bad "Antrag wird als Freigabe gemeldet"
fi
sleep 3
[ "$(zeilen "beantragt Worker 'teilstueck'")" = 1 ] \
    && ok "Antrag meldet nur einmal" \
    || bad "Antrag meldet nur einmal (Zeilen: $(zeilen "beantragt Worker 'teilstueck'"))"

# ---- (2b) braucht Freigabe: angehaltener Bash-Befehl -------------------------
mkdir -p "$FAKEHOME/.pi-workers/guard-blocks"
sicher_pane=$(printf '%s' "$W2" | tr -c 'a-zA-Z0-9_.-' '_')
cat >"$FAKEHOME/.pi-workers/guard-blocks/$sicher_pane.json" <<EOF
{"pane":"$W2","guard":"muster","reason":"Rueckfrage (sudo): Laeuft mit Systemrechten.",
 "command":"sudo ls","cwd":"/tmp","session_id":"s","ts":"2026-08-07T00:06:00Z","wartet":true}
EOF
if warte_auf "freigabe  w2  $W2  wartet auf Freigabe: Rueckfrage (sudo)" 20; then
    ok "angehaltener Bash-Befehl wird als Freigabe gemeldet"
else
    bad "angehaltener Bash-Befehl wird als Freigabe gemeldet"
fi
sleep 3
[ "$(zeilen "freigabe  w2  $W2  wartet")" = 1 ] \
    && ok "angehaltener Befehl meldet nur einmal" \
    || bad "angehaltener Befehl meldet nur einmal"

# Neuer Anlass an derselben Pane: neuer Zeitstempel im Marker.
cat >"$FAKEHOME/.pi-workers/guard-blocks/$sicher_pane.json" <<EOF
{"pane":"$W2","guard":"kill-pattern","reason":"Kill-Muster ohne eigenen Testsocket.",
 "command":"pkill x","cwd":"/tmp","session_id":"s","ts":"2026-08-07T00:07:00Z"}
EOF
if warte_auf "freigabe  w2  $W2  Befehl abgelehnt: Kill-Muster" 20; then
    ok "ein neuer Block derselben Pane ist ein neuer Anlass"
else
    bad "ein neuer Block derselben Pane ist ein neuer Anlass"
fi

# ---- (4) weg -----------------------------------------------------------------
# Der Pane von w5 ist tot (Prozess beendet, remain-on-exit haelt ihn), ohne dass
# je ein Ergebnis kam -- genau der Fall, den heute niemand bemerkt haette.
if warte_auf "weg  w5  $W5  Pane tot, kein Ergebnis — zurueckholen: wb-revive w5" 20; then
    ok "toter Pane ohne Ergebnis wird gemeldet"
else
    bad "toter Pane ohne Ergebnis wird gemeldet"
fi

tm kill-pane -t "$W4" 2>/dev/null
if warte_auf "weg  w4  -  Pane fort, kein Ergebnis — neu beauftragen: wb-do w4" 20; then
    ok "verschwundener Pane ohne Ergebnis wird gemeldet"
else
    bad "verschwundener Pane ohne Ergebnis wird gemeldet"
fi
sleep 3
[ "$(zeilen "weg  w4")" = 1 ] \
    && ok "weg meldet nur einmal" \
    || bad "weg meldet nur einmal (Zeilen: $(zeilen "weg  w4"))"

# Ein Worker MIT Ergebnis, dessen Pane geschlossen wird, ist nicht "weg".
tm kill-pane -t "$W1" 2>/dev/null
sleep 4
[ "$(zeilen "weg  w1")" = 0 ] \
    && ok "Worker mit Ergebnis wird nicht als weg gemeldet" \
    || bad "Worker mit Ergebnis wird nicht als weg gemeldet"

# ---- (3) steht still ---------------------------------------------------------
# Schwelle aus der geteilten Einstellungsdatei, nicht aus dem Code.
HOME="$FAKEHOME" "$FAKEHOME/.local/bin/wb-state" settings set stallMinutes 5 >/dev/null 2>&1
[ "$(HOME="$FAKEHOME" "$FAKEHOME/.local/bin/wb-state" settings get stallMinutes)" = 5 ] \
    && ok "stallMinutes kommt aus der Einstellungsdatei" \
    || bad "stallMinutes kommt aus der Einstellungsdatei"

# w6 mit TRANSCRIPT (Quelle 1): Zustandseintrag anlegen, Transcript
# zurueckdatieren -- 20 Minuten Stille bei einer Schwelle von 5.
W6=$(neuer_worker w6)
HOME="$FAKEHOME" "$FAKEHOME/.local/bin/wb-state" touch "$WORK" "$SESS" >/dev/null 2>&1
HOME="$FAKEHOME" "$FAKEHOME/.local/bin/wb-state" add-worker w6 claude claude-sonnet-5:high \
    "$WORK" "$SESS" --claude-session 11111111-2222-3333-4444-555555555555 >/dev/null 2>&1
TSLUG=$(printf '%s' "$WORK" | tr -c 'a-zA-Z0-9' '-')
mkdir -p "$FAKEHOME/.claude/projects/$TSLUG"
TRANS="$FAKEHOME/.claude/projects/$TSLUG/11111111-2222-3333-4444-555555555555.jsonl"
printf '{"type":"assistant"}\n' >"$TRANS"
[ "$(HOME="$FAKEHOME" "$FAKEHOME/.local/bin/wb-state" worker-transcript w6)" = "$TRANS" ] \
    && ok "Transcript-Pfad kommt aus der Zustandsdatei" \
    || bad "Transcript-Pfad kommt aus der Zustandsdatei"
/usr/bin/python3 -c 'import os,sys,time; t=time.time()-1200; os.utime(sys.argv[1],(t,t))' "$TRANS"

if warte_auf "steht still  w6  $W6  seit 20 min ohne Bewegung" 40; then
    ok "Stillstand am Transcript gemessen und gemeldet"
else
    bad "Stillstand am Transcript gemessen und gemeldet"
fi
sleep 20
[ "$(zeilen "steht still  w6")" = 1 ] \
    && ok "Stillstand meldet nur einmal je Anlass" \
    || bad "Stillstand meldet nur einmal je Anlass (Zeilen: $(zeilen "steht still  w6"))"

# Bewegung, dann erneuter Stillstand: ein NEUER Anlass.
/usr/bin/python3 -c 'import os,sys,time; t=time.time()-900; os.utime(sys.argv[1],(t,t))' "$TRANS"
if warte_auf "steht still  w6  $W6  seit 15 min ohne Bewegung" 40; then
    ok "neuer Stillstand nach Bewegung ist ein neuer Anlass"
else
    bad "neuer Stillstand nach Bewegung ist ein neuer Anlass"
fi

# w7 OHNE Transcript (Quelle 2, Pane-Ausgabe) und mit einem JUNGEN Kindprozess:
# ein langlaufendes Werkzeug ist Arbeit, kein Stillstand. Genau die Falle aus
# regeln/worker-panes.md.
# `sh -c "sleep 900"` taugt hier NICHT: die Shell exect den einen Befehl, der
# Pane-Prozess IST dann das sleep und hat gar kein Kind. Aber auch
# `sh -c "sleep 1; sleep 900"` (zwei Befehle, durch ';' getrennt) reicht NICHT
# ueberall: bash exect als LETZTEN Befehl eines '-c'-Skripts ebenfalls, wenn
# nichts mehr danach kommt -- unter peers bash (5.x, /bin/sh -> bash) wird
# 'sleep 900' so zum Pane-Prozess SELBST statt zu seinem Kind, und
# juengstes_kind() findet dann gar nichts (Befund 2026-08-21: 'ps --forest'
# zeigte den Pane-PID direkt als 'sleep', kein Kind darunter -- die Suite
# maskierte damit echte Stillstandsmeldungen als bestanden). Ein Hintergrund-Job
# mit explizitem 'wait' erzwingt den Fork unabhaengig von dieser Optimierung:
# der Shell-Prozess muss auf das Kind warten und kann sich nicht wegexecen.
W7=$(neuer_worker w7 'sh -c "sleep 1; sleep 900 & wait"')
W8=$(neuer_worker w8)
# Die Stillstandspruefung laeuft in eigenem Takt (15 s), erst sie legt den
# Bewegungsmerker an. Einmal abwarten, sonst gibt es nichts zurueckzudatieren.
sleep 20
BEWDIR="$FAKEHOME/.local/state/wb-ereignisse"
BEWD=$(ls -d "$BEWDIR"/*/bewegung 2>/dev/null | head -1)
if [ -f "$BEWD/w7.pane" ]; then
    /usr/bin/python3 - "$BEWD/w7.pane" <<'PY'
import sys, time
p = sys.argv[1]
summe = open(p).read().split()[0]
open(p, "w").write("%s %d\n" % (summe, int(time.time()) - 1200))
PY
    sleep 20
    [ "$(zeilen "steht still  w7")" = 0 ] \
        && ok "junger Kindprozess verhindert die Stillstandsmeldung" \
        || bad "junger Kindprozess verhindert die Stillstandsmeldung"
else
    bad "Bewegungsmerker fuer w7 (Pane-Ausgabe) wurde nicht angelegt"
fi

# w8 OHNE Transcript und OHNE jungen Kindprozess: muss gemeldet werden.
if [ -f "$BEWD/w8.pane" ]; then
    /usr/bin/python3 - "$BEWD/w8.pane" <<'PY'
import sys, time
p = sys.argv[1]
summe = open(p).read().split()[0]
open(p, "w").write("%s %d\n" % (summe, int(time.time()) - 1800))
PY
    if warte_auf "steht still  w8  $W8" 40; then
        ok "Stillstand an der Pane-Ausgabe gemessen und gemeldet"
    else
        bad "Stillstand an der Pane-Ausgabe gemessen und gemeldet"
    fi
else
    bad "Bewegungsmerker fuer w8 (Pane-Ausgabe) wurde nicht angelegt"
fi

echo
echo "== Neustart des Beobachters =="

VORHER=$(wc -l <"$OUT" | tr -d ' ')
beobachter_stop || bad "Beobachter liess sich nicht beenden"
OUT2="$WORK/strom2.txt"; : >"$OUT2"
beobachter_start "$OUT2" "$WORK/strom2.err"
sleep 6
NEU=$(grep -cvE '^[[:space:]]*$' "$OUT2" 2>/dev/null | tr -d ' ')
[ "${NEU:-0}" = 0 ] \
    && ok "Neustart meldet nichts aus der Vergangenheit nach" \
    || { bad "Neustart meldet nichts nach (neue Zeilen: $NEU)"; sed -n '1,10p' "$OUT2"; }
# Und danach meldet er wieder normal.
D3=$(ergebnis w2 20260807-001000)
OUT_ALT="$OUT"; OUT="$OUT2"
if warte_auf "fertig  w2  $D3" 20; then
    ok "nach dem Neustart wird wieder normal gemeldet"
else
    bad "nach dem Neustart wird wieder normal gemeldet"
fi
OUT="$OUT_ALT"

echo
echo "== Fehlerfaelle =="

BPID=$(beobachter_pid)

# (a) tmux kurz unerreichbar: eine Huelle vor dem echten tmux, die eine Weile
#     scheitert. Sie liegt nur im PATH des Beobachters.
ECHTES_TMUX="$(command -v tmux)"
cat >"$WORK/bin/tmux" <<EOF
#!/bin/bash
[ -f "$WORK/tmux-aus" ] && { echo "tmux: no server running" >&2; exit 1; }
exec "$ECHTES_TMUX" "\$@"
EOF
chmod +x "$WORK/bin/tmux"
WEG_VORHER=$(grep -c '^weg  ' "$OUT2" 2>/dev/null | tr -d ' ')
touch "$WORK/tmux-aus"
sleep 5
if [ -n "$BPID" ] && kill -0 "$BPID" 2>/dev/null; then
    ok "tmux unerreichbar beendet den Beobachter nicht"
else
    bad "tmux unerreichbar beendet den Beobachter nicht"
fi
# Und er darf waehrenddessen NICHT jeden lebenden Worker als verschwunden
# melden: "tmux hat nicht geantwortet" ist etwas anderes als "keine Panes da".
WEG_NACHHER=$(grep -c '^weg  ' "$OUT2" 2>/dev/null | tr -d ' ')
[ "${WEG_NACHHER:-0}" = "${WEG_VORHER:-0}" ] \
    && ok "tmux unerreichbar meldet keinen lebenden Worker als weg" \
    || { bad "tmux unerreichbar meldet keinen lebenden Worker als weg"; grep '^weg  ' "$OUT2"; }

# Eine Fertigmeldung darf der Aussetzer nicht verschlucken: sie haengt an
# Dateien, nicht an tmux.
DTMUX=$(ergebnis w6 20260807-003000)
OUT_ALT="$OUT"; OUT="$OUT2"
warte_auf "fertig  w6  $DTMUX" 15 \
    && ok "fertig wird auch bei unerreichbarem tmux gemeldet" \
    || bad "fertig wird auch bei unerreichbarem tmux gemeldet"
OUT="$OUT_ALT"

# (b) Verzeichnisse fehlen, waehrend er laeuft.
rm -rf "$FAKEHOME/.pi-workers/requests" "$FAKEHOME/.pi-workers/guard-blocks"
sleep 3
if [ -n "$BPID" ] && kill -0 "$BPID" 2>/dev/null; then
    ok "fehlende Verzeichnisse beenden den Beobachter nicht"
else
    bad "fehlende Verzeichnisse beenden den Beobachter nicht"
fi

# (c) Eine Ergebnisdatei erscheint und verschwindet wieder, mehrfach.
mkdir -p "$FAKEHOME/.pi-workers/results/w2"
for i in 1 2 3 4 5 6 7 8 9 10; do
    printf 'flackernd\n' >"$FAKEHOME/.pi-workers/results/w2/2026080%d-999999.md" "$i"
    rm -f "$FAKEHOME/.pi-workers/results/w2/2026080$i-999999.md"
done
sleep 3
if [ -n "$BPID" ] && kill -0 "$BPID" 2>/dev/null; then
    ok "verschwindende Dateien beenden den Beobachter nicht"
else
    bad "verschwindende Dateien beenden den Beobachter nicht"
fi

# ... und danach meldet er wieder ganz normal.
rm -f "$WORK/tmux-aus"
mkdir -p "$FAKEHOME/.pi-workers/requests"
W9=$(neuer_worker w9)
sleep 3
D9=$(ergebnis w9 20260807-002000)
OUT_ALT="$OUT"; OUT="$OUT2"
if warte_auf "fertig  w9  $D9" 30; then
    ok "nach den Fehlerfaellen meldet er wieder normal"
else
    bad "nach den Fehlerfaellen meldet er wieder normal"
fi
OUT="$OUT_ALT"

# Ohne $TMUX und ohne --session darf er sich NICHT still an die zuletzt benutzte
# Session des Standard-Servers haengen.
RAUS=$( (unset TMUX TMUX_PANE; HOME="$FAKEHOME" "$TOOL" --einmal 2>&1); echo "rc=$?")
case "$RAUS" in
    *"keine tmux-Session bestimmbar"*rc=2*) ok "ohne Pane und ohne --session wird nicht geraten" ;;
    *) bad "ohne Pane und ohne --session wird nicht geraten (bekam: $RAUS)" ;;
esac

echo
echo "== wb-do =="

# Stubs statt echter Spawns: geprueft wird, WOMIT wb-do aufruft, nicht ob tmux
# einen Pane baut -- das ist die Sache von pi-worker und dort schon geprueft.
for w in claude-worker pi-worker; do
    cat >"$FAKEHOME/.local/bin/$w" <<EOF
#!/bin/bash
printf '$w'
printf ' %s' "\$@"
printf '\n'
EOF
    chmod +x "$FAKEHOME/.local/bin/$w"
done
HOME="$FAKEHOME" "$FAKEHOME/.local/bin/wb-state" settings set workerModel sonnet5 >/dev/null 2>&1
HOME="$FAKEHOME" "$FAKEHOME/.local/bin/wb-state" settings set workerEffort xhigh >/dev/null 2>&1

RAUS=$(cd "$WORK" && HOME="$FAKEHOME" "$WBDO" pruefer "Lies die Datei." 2>"$WORK/do.err")
case "$RAUS" in
    "claude-worker pruefer default $WORK Lies die Datei.")
        ok "wb-do ruft claude-worker mit 'default' und dem aktuellen Verzeichnis" ;;
    *) bad "wb-do ruft claude-worker richtig auf (bekam: $RAUS)" ;;
esac
grep -q "laeuft KEIN Ereignisstrom" "$WORK/do.err" \
    && ok "wb-do warnt laut, wenn kein Ereignisstrom laeuft" \
    || bad "wb-do warnt laut, wenn kein Ereignisstrom laeuft"
grep -q -- "--session" "$WORK/do.err" \
    && ok "die Warnung nennt den genauen Startbefehl" \
    || bad "die Warnung nennt den genauen Startbefehl"

RAUS=$(cd "$WORK" && HOME="$FAKEHOME" "$WBDO" --modell sonnet5:xhigh --dir /tmp mess "Miss." 2>/dev/null)
case "$RAUS" in
    "claude-worker mess sonnet5:xhigh /tmp Miss.")
        ok "wb-do reicht ein ausdrueckliches Modell unveraendert durch" ;;
    *) bad "wb-do reicht ein ausdrueckliches Modell durch (bekam: $RAUS)" ;;
esac

RAUS=$(cd "$WORK" && HOME="$FAKEHOME" "$WBDO" --modell qwen3.5-4b lokal "Lokal." 2>/dev/null)
case "$RAUS" in
    "pi-worker lokal qwen3.5-4b $WORK Lokal.")
        ok "ein lokales Modell geht an pi-worker" ;;
    *) bad "ein lokales Modell geht an pi-worker (bekam: $RAUS)" ;;
esac

RAUS=$(cd "$WORK" && HOME="$FAKEHOME" "$WBDO" "../boese" "x" 2>&1)
case "$RAUS" in
    *"unzulaessiger Worker-Name"*) ok "wb-do weist einen unzulaessigen Namen ab" ;;
    *) bad "wb-do weist einen unzulaessigen Namen ab (bekam: $RAUS)" ;;
esac

RAUS=$(cd "$WORK" && HOME="$FAKEHOME" "$WBDO" nurname 2>&1; echo "rc=$?")
case "$RAUS" in
    *"rc=2"*) ok "wb-do verlangt einen Auftrag" ;;
    *) bad "wb-do verlangt einen Auftrag (bekam: $RAUS)" ;;
esac

# Laeuft ein Strom, schweigt die Warnung. Der Beobachter oben laeuft noch.
RAUS=$(cd "$WORK" && HOME="$FAKEHOME" TMUX="$(tm display -p '#{socket_path}'),0,0" \
        WB_SESSION="$SESS" "$WBDO" still "x" 2>"$WORK/do2.err")
grep -q "laeuft KEIN Ereignisstrom" "$WORK/do2.err" \
    && bad "wb-do warnt, obwohl ein Ereignisstrom laeuft" \
    || ok "wb-do schweigt, wenn ein Ereignisstrom laeuft"

# ---------------------------------------------------------------- Ereignis-Modus

# Der Beweis, dass wirklich das DATEISYSTEM weckt und nicht doch der Takt: der
# Beobachter laeuft mit einem Takt von 30 s und einem Netz von 30 s. Kommt die
# Zeile trotzdem in wenigen Sekunden, kann sie aus keiner Schleife stammen.
echo
echo "== Ereignis-Modus (Wecken statt Takt) =="

beobachter_stop >/dev/null 2>&1

EOUT="$WORK/ereignis.txt"; EERR="$WORK/ereignis.err"
: >"$EOUT"; : >"$EERR"
cat >"$WORK/starte-modus.sh" <<EOF
#!/bin/bash
export HOME="$FAKEHOME"
export PATH="$WORK/bin:\$PATH"
export WB_EREIGNISSE_NETZ="\$3"
exec "$TOOL" --session "$SESS" --intervall 30 --modus "\$4" >>"\$1" 2>>"\$2"
EOF
chmod +x "$WORK/starte-modus.sh"

modus_start() {   # <netz> <modus>
    tm new-window -d -t "=$SESS:" -n beobm \
        "bash $WORK/starte-modus.sh '$EOUT' '$EERR' '$1' '$2'"
    # Auf die STARTZEILE warten, nicht auf eine feste Zeitspanne: der Beobachter
    # liest erst Einstellungen (startet python) und wirft dann die Wache an --
    # unter Last dauert das laenger als jede geratene Sekundenzahl.
    local dl=$((SECONDS + 20))
    while [ $SECONDS -lt $dl ]; do
        grep -q "beobachte Session" "$EERR" 2>/dev/null && break
        sleep 0.2
    done
    sleep 1
}
modus_stop() {
    local p; p=$(beobachter_pid)
    tm kill-window -t "=$SESS:beobm" 2>/dev/null
    [ -n "$p" ] && kill "$p" 2>/dev/null
    local dl=$((SECONDS + 5))
    while [ $SECONDS -lt $dl ]; do
        [ -n "$p" ] && kill -0 "$p" 2>/dev/null || break
        sleep 0.2
    done
}
warte_auf_e() {   # <text> <sekunden>
    local dl=$((SECONDS + $2))
    while [ $SECONDS -lt $dl ]; do
        grep -qF "$1" "$EOUT" 2>/dev/null && return 0
        sleep 0.2
    done
    return 1
}

EREIGNISQUELLE_DA=1
if ! command -v fswatch >/dev/null 2>&1 && ! command -v inotifywait >/dev/null 2>&1; then
    EREIGNISQUELLE_DA=0
fi

if [ ! -x "$REPO/wb-verzeichniswache" ]; then
    bad "wb-verzeichniswache fehlt neben wb-ereignisse"
elif [ "$EREIGNISQUELLE_DA" = 0 ]; then
    # wb-verzeichniswache selbst faellt hier korrekt und LAUT auf den Takt zurueck
    # (siehe seine eigene Fehlermeldung "keine Ereignisquelle") -- das ist kein
    # Fehlschlag dieser Suite, sondern eine fehlende Paketabhaengigkeit dieser
    # Maschine (Befund 2026-08-21: weder fswatch noch inotify-tools installiert).
    # Nachruesten: 'sudo dnf install inotify-tools'. Die Poll-Rueckfallpruefungen
    # unten brauchen die Quelle nicht und laufen deshalb unveraendert weiter.
    ok "Ereignis-Modus uebersprungen -- weder fswatch noch inotifywait auf dieser Maschine (nachruesten: sudo dnf install inotify-tools)"
else
    modus_start 30 ereignis
    grep -q "Ereignisse + Netz" "$EERR" \
        && ok "Ereignis-Modus meldet sich als solcher" \
        || bad "Ereignis-Modus meldet sich als solcher (stderr: $(tail -c 200 "$EERR" | tr '\n' ' '))"

    # Die Wache ist ein EIGENER Prozess und muss laufen.
    WACHE_LAEUFT=0
    pgrep -f "wb-verzeichniswache --frist 30 $FAKEHOME/.pi-workers/results" >/dev/null 2>&1 && WACHE_LAEUFT=1
    [ "$WACHE_LAEUFT" = 1 ] \
        && ok "die Verzeichniswache laeuft als eigener Prozess" \
        || bad "die Verzeichniswache laeuft als eigener Prozess"

    ET0=$(jetzt_ms)
    EW=$(neuer_worker ew1)
    ED=$(ergebnis ew1 20260820-000100)
    if warte_auf_e "fertig  ew1  $ED" 20; then
        ET1=$(jetzt_ms); ELAT=$((ET1 - ET0))
        # Takt und Netz stehen beide auf 30 s. Alles unter 15 s kann nur vom
        # Dateisystem kommen -- eine Schleife haette noch nicht wieder
        # hingesehen. Die 15 s sind bewusst grosszuegig: gemessen liegt die
        # Latenz bei unter einer Sekunde, der Test soll unter Last nicht kippen.
        [ "$ELAT" -lt 15000 ] \
            && ok "fertig kommt vom Dateisystem, nicht vom Takt (${ELAT} ms bei 30 s Takt)" \
            || bad "fertig kam erst nach ${ELAT} ms — das ist der Takt, nicht das Ereignis"
    else
        bad "fertig wurde im Ereignis-Modus ueberhaupt nicht gemeldet"
    fi

    # Zweiter Anlass, damit belegt ist, dass das Wecken nicht einmalig war.
    ED2=$(ergebnis ew1 20260820-000200)
    warte_auf_e "fertig  ew1  $ED2" 20 \
        && ok "auch das zweite Ereignis weckt" \
        || bad "auch das zweite Ereignis weckt"

    modus_stop
    sleep 1
    # Prozess-Hygiene: was der Beobachter gestartet hat, ist mit ihm weg.
    pgrep -f "wb-verzeichniswache --frist 30 $FAKEHOME/.pi-workers/results" >/dev/null 2>&1 \
        && bad "die Verzeichniswache lebt weiter, nachdem der Beobachter beendet wurde" \
        || ok "die Verzeichniswache endet mit dem Beobachter"
fi

if [ -x "$REPO/wb-verzeichniswache" ]; then
    # Der Rueckweg: derselbe Code im Takt-Modus, ohne Wache -- unabhaengig davon,
    # ob eine Ereignisquelle installiert ist.
    : >"$EOUT"; : >"$EERR"
    modus_start 30 poll
    grep -q "(Takt 30s" "$EERR" \
        && ok "--modus poll bleibt beim alten Takt" \
        || bad "--modus poll bleibt beim alten Takt (stderr: $(tail -c 200 "$EERR" | tr '\n' ' '))"
    pgrep -f "wb-verzeichniswache --frist 30 $FAKEHOME/.pi-workers/results" >/dev/null 2>&1 \
        && bad "--modus poll startet trotzdem eine Wache" \
        || ok "--modus poll startet keine Wache"
    modus_stop
fi

RAUS=$(HOME="$FAKEHOME" "$TOOL" --session "$SESS" --modus quatsch 2>&1; echo "rc=$?")
case "$RAUS" in
    *"rc=2"*) ok "ein unbekannter Modus wird abgewiesen" ;;
    *) bad "ein unbekannter Modus wird abgewiesen (bekam: $RAUS)" ;;
esac

beobachter_start
sleep 2

# ---------------------------------------------------------------- Dauerlauf

if [ "$DAUERLAUF" = 1 ]; then
    echo
    echo "== Dauerlauf (>10 min, echte Wartezeit) =="
    HOME="$FAKEHOME" "$FAKEHOME/.local/bin/wb-state" settings set stallMinutes 1 >/dev/null 2>&1
    OUT="$OUT2"
    DL_W=""
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        n="dl$i"; DL_W="$DL_W $n"
        neuer_worker "$n" >/dev/null
    done
    # Ein echter Stillstand ohne Zurueckdatieren: dl1 tut 70 s lang nichts.
    STILL_START=$SECONDS
    verlust=0
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        n="dl$i"
        t0=$(jetzt_ms)
        d=$(ergebnis "$n" "20260807-0100$i")
        if warte_auf "fertig  $n  $d" 30; then
            t1=$(jetzt_ms); echo "   $n: $((t1 - t0)) ms"
        else
            verlust=$((verlust+1)); echo "   $n: VERLOREN"
        fi
        sleep 50
    done
    [ "$verlust" = 0 ] \
        && ok "Dauerlauf: kein Ereignis verloren ($((SECONDS - STILL_START)) s)" \
        || bad "Dauerlauf: $verlust Ereignisse verloren"
    # Das Trennzeichen MUSS mit: "fertig  dl1" steht auch in den Zeilen von
    # dl10, dl11 und dl12, und der Zaehler meldete daraufhin eine Dopplung, die
    # es nicht gab (gemessen 2026-08-07).
    dopp=0
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        [ "$(zeilen "fertig  dl$i  ")" = 1 ] || { dopp=$((dopp+1)); echo "   dl$i: $(zeilen "fertig  dl$i  ") Zeilen"; }
    done
    [ "$dopp" = 0 ] \
        && ok "Dauerlauf: keine Dopplung" \
        || bad "Dauerlauf: $dopp Worker doppelt gemeldet"
    # dl1 hat inzwischen weit ueber eine Minute nichts getan.
    [ "$(zeilen "steht still  dl1  ")" -ge 1 ] \
        && ok "Dauerlauf: echter Stillstand ohne Zurueckdatieren gemeldet" \
        || bad "Dauerlauf: echter Stillstand ohne Zurueckdatieren gemeldet"
    p=$(beobachter_pid)
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null \
        && ok "Dauerlauf: Beobachter laeuft noch" \
        || bad "Dauerlauf: Beobachter laeuft noch"
    OUT="$OUT_ALT"
fi

beobachter_stop >/dev/null 2>&1

echo
echo "Latenz fertig -> Zeile: ${LATENZ_MS} ms"
echo "bestanden: $pass   fehlgeschlagen: $fail"
[ "$fail" = 0 ]
