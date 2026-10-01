#!/usr/bin/env bash
# Abschirmung des Orchestrator-Panes: in seinen Chat schreiben nur ein GEMESSENER
# Mensch und der context-guard. Alles andere wird abgelehnt, laut und nachvollziehbar.
#
# Anlass (2026-08-06, der Nutzer woertlich): "ich will das niemand ausser mir und dem
# kontext guard in den orchestrator chat promptet, alles andere soll funktionieren ohne
# in den orchestrator chat prompten zu muessen, es muss aber zuverlaessig funktionieren,
# es darf niemals schiefgehen." Am 04.08. hat eine Testsuite in die Live-Sitzung getippt
# und dem Orchestrator eine Anweisung untergeschoben -- genau diese Klasse Fehler soll
# danach unmoeglich sein.
#
# Alles laeuft auf einem EIGENEN tmux-Socket und mit eigenem HOME. Die Panes sind 'cat'
# statt einer Shell: getippter Text darf niemals als Kommando laufen. Die Live-Session,
# das laufende Programm und dessen Steuersocket werden nicht angefasst.
#
# Die Gegenprobe am Ende schaltet die Engstelle aus (eine Attrappe, die alles
# durchlaesst) und zeigt, dass dann genau die Faelle durchgehen, die vorher abgelehnt
# wurden. Ein Test, der auch ohne den Umbau gruen ist, beweist nichts.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

TOOL="${WB_PANE_WRITE:-$REPO/wb-pane-write}"
HOOK="${WB_BASH_GUARD:-$(cd "$REPO/.." && pwd)/hooks/bash-guard.py}"
PY=/usr/bin/python3
# Eine Pane-Kennung, die auf dem Standard-Server sicher NICHT existiert (Begruendung
# bei Zusage 6a): ueber der hoechsten vergebenen, zur Laufzeit gelesen.
HOECHSTE="$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | tr -d '%' | sort -n | tail -1)"
UNBEKANNT="%$(( ${HOECHSTE:-0} + 100000 ))"
echo "Geprueft: $TOOL"
echo "Geprueft: $HOOK"

SOCKET="wbtest-abschirm-$$"
TESTHOME="$(mktemp -d)"
WORK="$(mktemp -d)"
pass=0; fail=0

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
    rm -f "/private/tmp/tmux-$(id -u)/$SOCKET"
    rm -rf "$TESTHOME" "$WORK"
}
trap cleanup EXIT

ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
zeig() { printf '        | %s\n' "$1"; }

werkzeuge_installieren "$TESTHOME" || { echo "Werkzeuge liessen sich nicht installieren" >&2; exit 1; }

# Der Aufrufer ist in dieser Suite IMMER ein Skript: die Testdatei laeuft aus einem
# Bash-Werkzeug heraus, ohne steuerndes Terminal. Damit das auch dann gilt, wenn jemand
# die Suite von Hand im Terminal startet (dann waere sie ein Mensch und jede Ablehnung
# bliebe aus), werden die drei Deskriptoren fuer die Prueflinge umgeleitet -- und die
# Agenten-Umgebungsvariable gesetzt, die wb-mensch als Negativmerkmal liest. Das ist
# keine Schwaechung: WB_AGENT macht aus einem Menschen einen Agenten, nie umgekehrt.
schreib() {   # <verb> <pane> [rest...] -- Text auf stdin, Ausgabe nach $WORK/letzte.err
    local verb="$1" pane="$2"; shift 2
    WB_AGENT=1 HOME="$TESTHOME" WB_TMUX_SOCKET="$SOCKET" \
        "$TOOL" "$verb" "$pane" "$@" >"$WORK/letzte.out" 2>"$WORK/letzte.err" </dev/null
}
schreib_text() {   # <verb> <pane> <text>
    local verb="$1" pane="$2" text="$3"
    printf '%s' "$text" | WB_AGENT=1 HOME="$TESTHOME" WB_TMUX_SOCKET="$SOCKET" \
        "$TOOL" "$verb" "$pane" >"$WORK/letzte.out" 2>"$WORK/letzte.err"
}
fehlertext() { cat "$WORK/letzte.err" 2>/dev/null; }
capture() { tm capture-pane -p -S -500 -t "$1" 2>/dev/null; }

# --- Buehne ----------------------------------------------------------------
tm kill-server 2>/dev/null
tm new-session -d -s wb -x 200 -y 60 -c /tmp
tmux_live_hooks_kappen "$SOCKET"   # sonst greift das echte wb-autorevive in respawn-pane/pane-died ein
ORCH="$(tm list-panes -t wb -F '#{pane_id}')"
tm respawn-pane -k -t "$ORCH" "sh -c 'stty -echo; exec cat'"
tm set-option -p -t "$ORCH" @wb_role orchestrator

tm split-window -t wb -c /tmp
WORKER="$(tm display -p -t wb '#{pane_id}')"
tm respawn-pane -k -t "$WORKER" "sh -c 'stty -echo; exec cat'"
tm set-option -p -t "$WORKER" @wb_role worker
tm set-option -p -t "$WORKER" @wb_worker pruefling

tm split-window -t wb -c /tmp
NACKT="$(tm display -p -t wb '#{pane_id}')"
tm respawn-pane -k -t "$NACKT" "sh -c 'stty -echo; exec cat'"
# NACKT traegt mit Absicht KEINE @wb_role -- der Fall "nicht bestimmbar".
sleep 0.5

echo
echo "== 1) Ein Skript kommt an den Orchestrator nicht heran =="

MARKE="SKRIPT-$$-DARF-NICHT"
if schreib_text tippen "$ORCH" "$MARKE"; then
    bad "1a: 'tippen' auf den Orchestrator wurde AUSGEFUEHRT"
else
    rc=$?
    [ "$rc" = 77 ] && ok "1a: 'tippen' auf den Orchestrator abgelehnt (Exit 77)" \
                   || bad "1a: abgelehnt, aber mit Exit $rc statt 77"
fi
capture "$ORCH" | grep -qF "$MARKE" \
    && { bad "1b: der Text steht trotzdem im Orchestrator-Pane"; zeig "$(capture "$ORCH" | tail -2)"; } \
    || ok "1b: im Orchestrator-Pane steht nichts davon"

schreib_text einfuegen "$ORCH" "EINFUEGEN-$$" \
    && bad "1c: 'einfuegen' auf den Orchestrator kam durch" \
    || ok "1c: 'einfuegen' auf den Orchestrator abgelehnt"
schreib taste "$ORCH" Enter \
    && bad "1d: 'taste' auf den Orchestrator kam durch" \
    || ok "1d: 'taste' auf den Orchestrator abgelehnt"
schreib darf "$ORCH" \
    && bad "1e: 'darf' bejaht den Orchestrator fuer ein Skript" \
    || ok "1e: 'darf' verneint den Orchestrator fuer ein Skript"

# Die Behauptung nuetzt nichts. Weder ein Schalter noch eine Variable, die es im
# Werkzeug gar nicht gibt, noch das Merkmal, das wb-mensch fuer die Oberflaeche liest:
# WB_APP_PID muss ein ECHTER Ahne sein, und PID 1 ist keiner von uns.
behauptung() {   # <label> <env-zuweisungen...>
    local label="$1"; shift
    if printf 'BEHAUPTUNG-%s' "$$" | env WB_AGENT=1 HOME="$TESTHOME" WB_TMUX_SOCKET="$SOCKET" "$@" \
            "$TOOL" tippen "$ORCH" >/dev/null 2>"$WORK/letzte.err"; then
        bad "1f: $label kam durch"
    else
        ok "1f: $label kommt nicht durch"
    fi
}
behauptung "WB_MENSCH_QUELLE=oberflaeche + WB_APP_PID=1" WB_MENSCH_QUELLE=oberflaeche WB_APP_PID=1
behauptung "WB_IST_GUARD=1 (eine Variable, die es nicht gibt)" WB_IST_GUARD=1
behauptung "CONTEXT_GUARD=1" CONTEXT_GUARD=1

# Ein Skript, das sich context-guard NENNT, ist keiner: verglichen wird die Datei
# (Geraet+Inode), nicht der Name.
mkdir -p "$WORK/falsch"
cat > "$WORK/falsch/context-guard" <<EOF
#!/bin/bash
printf 'HOCHSTAPLER-$$' | WB_AGENT=1 HOME='$TESTHOME' WB_TMUX_SOCKET='$SOCKET' '$TOOL' tippen '$ORCH'
EOF
chmod +x "$WORK/falsch/context-guard"
if "$WORK/falsch/context-guard" >/dev/null 2>"$WORK/letzte.err"; then
    bad "1g: ein gleichnamiges Skript gilt als der Guard"
else
    ok "1g: ein gleichnamiges Skript gilt NICHT als der Guard (Inode statt Name)"
fi
capture "$ORCH" | grep -qF "HOCHSTAPLER-$$" \
    && bad "1h: der Text des Hochstaplers steht im Orchestrator-Pane" \
    || ok "1h: vom Hochstapler steht nichts im Orchestrator-Pane"

# Den Guard-Pfad NENNEN ist nicht, ihn AUSFUEHREN. Bis 2026-08-15 genuegte ein Wort in
# der Kommandozeile irgendeines Ahnen (Bugjagd-Befund, hier nachgestellt: der Aufruf kam
# mit Exit 0 durch). Beide Formen des Wegs stehen hier: die kanonische Datei als Wort im
# `-c`-Text einer Shell, und dieselbe Datei als erstes Argument eines Programms, das sie
# gar nicht ausfuehrt.
GUARD_DATEI="$TESTHOME/.local/bin/context-guard"
NENNT="NENNT-STATT-FUEHRT-$$"
if bash -c ": $GUARD_DATEI ; printf '%s' '$NENNT' | WB_AGENT=1 HOME='$TESTHOME' WB_TMUX_SOCKET='$SOCKET' '$TOOL' tippen '$ORCH'" \
        >/dev/null 2>"$WORK/letzte.err"; then
    bad "1i: der Guard-Pfad als blosses Wort in der Kommandozeile kam durch"
else
    ok "1i: der Guard-Pfad als blosses Wort in der Kommandozeile kommt nicht durch"
fi
capture "$ORCH" | grep -qF "$NENNT" \
    && bad "1j: der Text steht trotzdem im Orchestrator-Pane" \
    || ok "1j: im Orchestrator-Pane steht nichts davon"

cat > "$WORK/traegt-guard-im-argv" <<EOF
#!/bin/bash
# Bekommt die kanonische Guard-Datei als argv[1] und fuehrt sie NIE aus.
printf 'ARGV1-$$' | WB_AGENT=1 HOME='$TESTHOME' WB_TMUX_SOCKET='$SOCKET' '$TOOL' tippen '$ORCH'
EOF
chmod +x "$WORK/traegt-guard-im-argv"
if "$WORK/traegt-guard-im-argv" "$GUARD_DATEI" >/dev/null 2>"$WORK/letzte.err"; then
    bad "1k: die Guard-Datei als Argument eines fremden Programms kam durch"
else
    ok "1k: die Guard-Datei als Argument eines fremden Programms kommt nicht durch"
fi

echo
echo "== 2) Der echte context-guard kommt durch =="

# Zwei Suiten teilen sich diesen Nachweis, und zwar arbeitsteilig.
#
# Dass der ECHTE context-guard durchkommt, zeigt seine eigene Suite: in
# test-context-guard-fertigmeldung.sh laeuft der unveraenderte Guard, und seine
# Fertigmeldung muss im Orchestrator-Pane ankommen. Waere er von der Engstelle
# ausgesperrt, faellt dort jeder Fall um.
#
# Hier wird die TRAGENDE EINZELHEIT geprueft, ohne die jene Suite nichts belegen
# koennte: erkennt die Ahnenpruefung die kanonische Guard-Datei, wenn sie wirklich in
# der Prozesskette steht? Der Guard selbst hat keinen Modus, der etwas Fremdes
# ausfuehrt -- den einzubauen waere genau das Loch, gegen das dieser Umbau gebaut ist.
# Deshalb tritt fuer diesen einen Fall eine eigene Datei an den kanonischen Pfad, die
# nichts weiter tut als ihr Argument zu starten. Geprueft wird damit der Mechanismus:
# steht die Datei unter $HOME/.local/bin/context-guard in der Ahnenreihe, kommt der
# Schreibversuch durch -- und in 1g steht daneben, dass ein gleichnamiges Skript an
# einem anderen Ort es NICHT tut.
cat > "$WORK/als-guard.sh" <<EOF
#!/bin/bash
# Steht stellvertretend fuer die Stelle IM Guard, die wb-pane-write ruft.
printf 'GUARDTEXT-$$' | WB_AGENT=1 HOME='$TESTHOME' WB_TMUX_SOCKET='$SOCKET' '$TOOL' tippen '$ORCH' || exit 1
WB_AGENT=1 HOME='$TESTHOME' WB_TMUX_SOCKET='$SOCKET' '$TOOL' taste '$ORCH' Enter
EOF
chmod +x "$WORK/als-guard.sh"
# Der Kniff: die kanonische Guard-Datei wird zu einem Skript, das dieses Skript ruft.
# Damit ist sie ein ECHTER Ahne -- nichts wird behauptet, die Prozesstabelle zeigt es.
# Die Datei unter $TESTHOME/.local/bin ist ein Symlink in den Arbeitsbaum; fuer diesen
# einen Fall wird er durch eine eigene Datei ersetzt und danach zurueckgelegt.
rm -f "$TESTHOME/.local/bin/context-guard"
cat > "$TESTHOME/.local/bin/context-guard" <<EOF
#!/bin/bash
# KEIN exec: `exec` ersetzt den eigenen Prozess, und damit waere die Guard-Datei aus
# der Ahnenreihe verschwunden -- geprueft wuerde dann das Gegenteil dessen, was hier
# gemeint ist. Als Kindprozess bleibt sie stehen, genau wie im Betrieb.
"\$@"
EOF
chmod +x "$TESTHOME/.local/bin/context-guard"
if "$TESTHOME/.local/bin/context-guard" "$WORK/als-guard.sh" >/dev/null 2>"$WORK/letzte.err"; then
    ok "2a: unter der kanonischen Guard-Datei kommt der Schreibversuch durch"
else
    bad "2a: der Guard wurde in seiner eigenen Ahnenreihe abgelehnt"
    zeig "$(fehlertext | head -3 | tr '\n' ' ')"
fi
sleep 0.4
capture "$ORCH" | grep -qF "GUARDTEXT-$$" \
    && ok "2b: der Text des Guards steht im Orchestrator-Pane" \
    || { bad "2b: der Text des Guards fehlt im Orchestrator-Pane"; zeig "$(capture "$ORCH" | tail -2)"; }
# Zurueck auf den Symlink, damit der Rest der Suite wieder gegen die echte Datei prueft.
ln -sf "$REPO/context-guard" "$TESTHOME/.local/bin/context-guard"

echo
echo "== 3) Worker-Panes nehmen weiter alles an (Regressionsprobe) =="

WMARKE="WORKER-$$-KOMMT-DURCH"
if schreib_text tippen "$WORKER" "$WMARKE"; then
    ok "3a: 'tippen' in einen Worker-Pane kommt durch"
else
    bad "3a: der Orchestrator kann keine Auftraege mehr vergeben"
    zeig "$(fehlertext | head -2 | tr '\n' ' ')"
fi
schreib taste "$WORKER" Enter
sleep 0.4
capture "$WORKER" | grep -qF "$WMARKE" \
    && ok "3b: der Text steht im Worker-Pane" \
    || { bad "3b: der Text fehlt im Worker-Pane"; zeig "$(capture "$WORKER" | tail -2)"; }
schreib_text einfuegen "$WORKER" "EINFUEGEN-WORKER-$$" \
    && ok "3c: 'einfuegen' in einen Worker-Pane kommt durch" \
    || bad "3c: 'einfuegen' in einen Worker-Pane abgelehnt"
schreib taste "$WORKER" Enter \
    && ok "3d: 'taste' in einen Worker-Pane kommt durch" \
    || bad "3d: 'taste' in einen Worker-Pane abgelehnt"

echo
echo "== 4) Fail-closed: unbestimmbare Rolle gilt als Orchestrator =="

schreib_text tippen "$NACKT" "NACKT-$$" \
    && bad "4a: ein Pane ohne @wb_role nahm den Text an" \
    || ok "4a: ein Pane ohne @wb_role gilt als Orchestrator und lehnt ab"
schreib_text tippen "$UNBEKANNT" "GEISTER-$$" \
    && bad "4b: ein Pane, den es nicht gibt, wurde bejaht" \
    || ok "4b: ein Pane, den es nicht gibt, wird abgelehnt"
WB_AGENT=1 HOME="$TESTHOME" WB_TMUX_SOCKET="nicht-vorhanden-$$" "$TOOL" darf "$ORCH" \
    >/dev/null 2>"$WORK/letzte.err" \
    && bad "4c: ohne erreichbares tmux wurde bejaht" \
    || ok "4c: ohne erreichbares tmux wird abgelehnt"

echo
echo "== 5) Die Ablehnung ist laut und sagt wer, was, wohin =="

schreib_text tippen "$ORCH" "LAUT-$$"
TXT="$(fehlertext)"
[ -n "$TXT" ] && ok "5a: es gibt ueberhaupt eine Meldung auf stderr" \
              || bad "5a: die Ablehnung ist STILL"
case "$TXT" in *ABGELEHNT*) ok "5b: die Meldung nennt die Entscheidung" ;;
               *) bad "5b: 'ABGELEHNT' fehlt in der Meldung" ;; esac
case "$TXT" in *"$ORCH"*) ok "5c: die Meldung nennt den Pane ($ORCH)" ;;
               *) bad "5c: der Pane fehlt in der Meldung" ;; esac
case "$TXT" in *tippen*) ok "5d: die Meldung nennt, was versucht wurde" ;;
               *) bad "5d: das Verb fehlt in der Meldung" ;; esac
case "$TXT" in *"PID $"*|*"PID "*) ok "5e: die Meldung nennt den Aufrufer (PID/Ahnenreihe)" ;;
               *) bad "5e: der Aufrufer fehlt in der Meldung" ;; esac
case "$TXT" in *results*|*requests*) ok "5f: die Meldung nennt den Ersatzweg" ;;
               *) bad "5f: der Ersatzweg fehlt in der Meldung" ;; esac
printf '%s\n' "$TXT" | sed 's/^/        | /'

echo
echo "== 6) Der Hook faengt den Weg an der Engstelle vorbei =="

hook() {   # <kommando> -> Entscheidung: deny|allow
    local befehl="$1" out
    out=$(printf '%s' "$("$PY" -c '
import json, sys
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}, "cwd": "/tmp"}))
' "$befehl")" | AWB_GUARD_BLOCKS="$WORK/blocks" AWB_GUARD_LOG="$WORK/guard.log" \
        AWB_SETTINGS_FILE="$WORK/keine-einstellungen.json" "$PY" "$HOOK" 2>/dev/null)
    printf '%s' "$out" | grep -q '"permissionDecision": *"deny"' && { echo deny; return; }
    echo allow
}
printf '{}\n' > "$WORK/keine-einstellungen.json"

# Ein echter Orchestrator-Pane auf DIESEM Testserver ist fuer den Hook nicht sichtbar
# (er fragt den Standard-Server). Genau das ist der fail-closed-Fall, und der wird
# geprueft: unbestimmbar heisst Orchestrator, heisst Ablehnung.
#
# Die Pane-Kennung darf auf dem Standard-Server NICHT existieren -- sonst prueft die
# Zusage etwas anderes. Bis zum 2026-09-05 stand hier fest '%99'; an diesem Tag lief
# die Werkbank so viele Worker, dass der Standard-Server bei %101 stand und %99 ein
# echter Worker-Pane einer fremden Sitzung war. Der Hook hat ihn richtig als Worker
# erkannt und den Befehl durchgelassen -- die Suite fiel rot, obwohl der Hook stimmte.
# Deshalb: eine Kennung, die sicher ueber jeder vergebenen liegt, zur Laufzeit gelesen.
[ "$(hook "tmux send-keys -t $UNBEKANNT 'hallo' Enter")" = deny ] \
    && ok "6a: 'tmux send-keys' auf einen unbestimmbaren Pane wird abgelehnt" \
    || bad "6a: 'tmux send-keys' auf einen unbestimmbaren Pane kam durch"
[ "$(hook "tmux send-keys hallo")" = deny ] \
    && ok "6b: 'tmux send-keys' ohne -t wird abgelehnt" \
    || bad "6b: 'tmux send-keys' ohne -t kam durch"
[ "$(hook "tmux paste-buffer -p -b x -t $UNBEKANNT")" = deny ] \
    && ok "6c: 'tmux paste-buffer' wird abgelehnt" \
    || bad "6c: 'tmux paste-buffer' kam durch"
[ "$(hook "tmux -L wbtest-eigener send-keys -t %0 hallo Enter")" = allow ] \
    && ok "6d: derselbe Befehl auf einem EIGENEN Socket kommt durch" \
    || bad "6d: ein Test auf eigenem Socket wurde abgelehnt"
[ "$(hook "tmux capture-pane -p -t %0")" = allow ] \
    && ok "6e: Lesen (capture-pane) bleibt unberuehrt" \
    || bad "6e: capture-pane wurde abgelehnt"
[ "$(hook "wb-pane-write tippen %0")" = allow ] \
    && ok "6f: der Weg ueber die Engstelle selbst kommt durch" \
    || bad "6f: wb-pane-write wurde vom Hook abgelehnt"
[ "$(hook "echo 'tmux send-keys ist ein Beispiel im Text'")" = allow ] \
    && ok "6g: ein blosses Echo ueber send-keys wird nicht abgelehnt" \
    || bad "6g: ein Echo ueber send-keys wurde abgelehnt"

echo
echo "== 7) Gegenprobe: ohne die Engstelle geht alles durch =="

# Eine Attrappe an der Stelle des Werkzeugs -- dieselbe Aufrufform, aber ohne Regel.
# Wenn die Faelle aus Abschnitt 1 damit durchgehen, misst die Suite wirklich die
# Engstelle und nicht irgendeine andere Eigenschaft der Buehne.
cat > "$WORK/attrappe" <<'EOF'
#!/bin/bash
SOCKET="${WB_TMUX_SOCKET:-}"
tmm() { if [ -n "$SOCKET" ]; then tmux -L "$SOCKET" "$@"; else tmux "$@"; fi; }
case "${1:-}" in
    darf) exit 0 ;;
    tippen) tmm send-keys -t "$2" "$(cat)" ;;
    taste)  tmm send-keys -t "$2" "$3" ;;
    einfuegen) tmm load-buffer -b attr - && tmm paste-buffer -p -b attr -d -t "$2" ;;
esac
EOF
chmod +x "$WORK/attrappe"
GEGEN="GEGENPROBE-$$"
if printf '%s' "$GEGEN" | WB_AGENT=1 HOME="$TESTHOME" WB_TMUX_SOCKET="$SOCKET" \
        "$WORK/attrappe" tippen "$ORCH" >/dev/null 2>&1; then
    WB_AGENT=1 HOME="$TESTHOME" WB_TMUX_SOCKET="$SOCKET" "$WORK/attrappe" taste "$ORCH" Enter >/dev/null 2>&1
    sleep 0.4
    capture "$ORCH" | grep -qF "$GEGEN" \
        && ok "7a: ohne die Engstelle landet der Text im Orchestrator-Pane -- die Probe misst sie wirklich" \
        || bad "7a: auch ohne die Engstelle kam nichts an -- die Probe misst etwas anderes"
else
    bad "7a: die Attrappe liess sich nicht ausfuehren"
fi
WB_AGENT=1 HOME="$TESTHOME" WB_TMUX_SOCKET="$SOCKET" "$WORK/attrappe" darf "$ORCH" \
    && ok "7b: ohne die Engstelle bejaht 'darf' den Orchestrator" \
    || bad "7b: die Attrappe verneint -- sie ist keine Attrappe"
# Und die Engstelle selbst lehnt denselben Fall unveraendert weiter ab.
schreib_text tippen "$ORCH" "NACH-GEGENPROBE-$$" \
    && bad "7c: nach der Gegenprobe kommt das Skript durch" \
    || ok "7c: nach der Gegenprobe lehnt die Engstelle unveraendert ab"

echo
echo "$pass bestanden, $fail fehlgeschlagen."
[ "$fail" -eq 0 ]
