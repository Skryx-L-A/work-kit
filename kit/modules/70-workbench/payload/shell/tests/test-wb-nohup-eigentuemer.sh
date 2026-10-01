#!/usr/bin/env bash
# test-wb-nohup-eigentuemer.sh -- die drei Arten von Eigentuemer, und dass
# keine davon geglaubt wird (2026-08-21).
#
# DER BEFUND, der diesen Test ausgeloest hat. `wb-code` entfernt in seiner
# Zeile 52 $TMUX und $TMUX_PANE ("we always attach a fresh client here").
# Alles, was danach kommt, sieht deshalb keinen tmux-Pane mehr -- und
# `wb-nohup` verweigert ohne Pane den Dienst. Seit `wb-mlx-server ensure` in
# wb-code laeuft, brach damit JEDER Start einer Sitzung mit lokalem Modell ab:
#
#   wb-nohup: braucht einen tmux-Pane als Bezugspunkt (kein $TMUX/$TMUX_PANE ...)
#   wb-mlx-server: wb-nohup konnte den Server nicht starten
#   wb-code: 'wb-mlx-server ensure' fuer Kontext 131072 fehlgeschlagen — kein Start.
#
# Gemessen am 21.08. an zwei Laeufen aus einer tmux-Hilfssession; dieselbe
# Kette trifft das Plus-Menue der Oberflaeche, weil Electron erst recht keinen
# Pane hat. Uebrig blieb in beiden Faellen eine Zustandsdatei ohne Sitzung --
# in der Liste ein Eintrag, rechts "Stopped".
#
# DIE FORDERUNG BLEIBT, SIE BEKOMMT NUR ZWEI WEITERE QUELLEN. Ein abgeloester
# Prozess ohne nachweisbaren Eigentuemer ist genau das Problem, gegen das
# wb-nohup gebaut wurde. Neu ist deshalb nicht die Ausnahme, sondern:
#   * der GERETTETE PANE -- dieselbe Art, andere Quelle: wb-code legt die
#     beiden Werte vor seinem `unset` in WB_EIGENTUEMER_TMUX(_PANE) ab.
#   * das WERKBANK-PROGRAMM als dritte Art (--werkbank / WB_EIGENTUEMER_WERKBANK).
#
# Die Zusagen:
#   1  Ohne jede Quelle bleibt es beim harten Nein -- und die Meldung nennt
#      jetzt alle drei Wege.
#   2  Ein geretteter Pane, der LEBT, traegt; die Registrierung nennt ihn.
#   3  Ein geretteter Pane, den es nicht gibt, traegt NICHT.
#   4  Das Werkbank-Programm traegt, wenn es laeuft, so heisst und Vorfahre
#      ist; die Registrierung nennt PID und lstart-Pruefwert.
#   5  Eine Werkbank-PID, die nicht laeuft, wird abgelehnt.
#   6  Eine PID, die laeuft, aber nicht wie die Werkbank heisst, wird
#      abgelehnt -- sonst waere jeder Dauerlaeufer ein Freibrief.
#   7  Eine PID, die laeuft und richtig heisst, aber KEIN Vorfahre ist, wird
#      abgelehnt -- sonst genuegte es, die Nummer abzuschreiben.
#   8  Ein echter Pane geht vor: er landet in der Registrierung, die geerbte
#      Werkbank-PID nicht.
#   9  `wb-code` rettet die beiden Werte wirklich -- geprueft am ECHTEN
#      Quelltext, nicht an einer Nachbildung.
#  10  `wb-waisen` stellt bei der dritten Art dieselbe Tatsachenfrage: lebender
#      Eigentuemer -> keine Waise, toter oder wiederverwendeter -> Waise.
#  11  Ein Benutzer laesst sich EINTRAGEN (`benutzer`, frueher `umschreiben`):
#      ein lebender Pane ja, ein toter nie, und ein abgelehnter Eintrag laesst
#      die Registrierung unbeschaedigt.
#  12  EIN SERVER HAT MEHRERE BENUTZER (21.08., nachmittags). Gemessen an vier
#      Sitzungen auf einem Server: eingetragen war der Pane der zuletzt
#      gestarteten, genau die wurde zuerst geschlossen -- und `wb-waisen`
#      meldete den Server als Waise, waehrend eine lebende Sitzung ihn benutzte.
#      Die drei Faelle, die das festnageln:
#        a  Eigentuemer stirbt, ein anderer Benutzer lebt   -> KEINE Waise
#        b  der letzte Benutzer stirbt                      -> Waise
#        c  von Anfang an kein lebender Benutzer            -> Waise
#
# ISOLATION: eigener tmux-Socket mit PID im Namen, eigenes HOME. Kein Modell,
# kein echter Server, keine Live-Sitzung. Jeder gestartete Prozess wird am
# Ende beendet und das Ende geprueft.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOHUP="$REPO/wb-nohup"
WAISEN="$REPO/wb-waisen"
SOCKET="wbtest-eigentuemer-$$"
# /private/tmp gibt es nur auf macOS (dort ist /tmp ein Verweis darauf); auf Linux legt
# tmux seine Sockets unter /tmp ab. Stand hier der macOS-Pfad fest, fand tmux das
# Verzeichnis auf host2 nicht, legte keinen Pane an, und die Suite brach im Aufbau ab --
# gemessen am 2026-08-21, sie war dort rot, ohne eine einzige Zusage geprueft zu haben.
# Dieselbe Fallunterscheidung steht in wb-hygiene und ist dort seit dem 2026-08-04 gemessen.
if [ -d /private/tmp ]; then
    SOCKPATH="/private/tmp/tmux-$(id -u)/$SOCKET"
else
    SOCKPATH="/tmp/tmux-$(id -u)/$SOCKET"
fi
WORK="$(mktemp -d)"
FAKEHOME="$(mktemp -d)"
REGDIR="$FAKEHOME/.local/state/wb-nohup/eigentuemer"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

tm() { tmux -S "$SOCKPATH" "$@"; }

cleanup() {
    # Was dieser Test gestartet hat, beendet er auch -- und sieht nach.
    if [ -f "$WORK/pids" ]; then
        while read -r p; do
            [ -n "$p" ] || continue
            # NIE DIE EIGENE SHELL (Befund 21.08., siehe ruf()). Ein Gurt neben
            # der Ursache: was auch immer in dieser Liste landet, dieser Test
            # schiesst sich nicht selbst ab.
            [ "$p" = "$$" ] && continue
            # Erst die Kinder (der Fremd-Halter haelt ein python3), dann er
            # selbst -- sonst bleibt das Kind als Waise stehen.
            pkill -P "$p" 2>/dev/null
            kill "$p" 2>/dev/null
        done < "$WORK/pids"
        sleep 0.4
        while read -r p; do
            [ -n "$p" ] || continue
            [ "$p" = "$$" ] && continue
            kill -0 "$p" 2>/dev/null && { kill -9 "$p" 2>/dev/null; sleep 0.2; }
            kill -0 "$p" 2>/dev/null && echo "WARNUNG: PID $p laeuft noch" >&2
        done < "$WORK/pids"
    fi
    tm kill-server 2>/dev/null
    local deadline=$((SECONDS + 5))
    while [ $SECONDS -lt $deadline ] && tm list-sessions >/dev/null 2>&1; do
        tm kill-server 2>/dev/null; sleep 0.3
    done
    tm list-sessions >/dev/null 2>&1 && echo "WARNUNG: tmux-Server '$SOCKET' laeuft noch" >&2
    # HARTNAECKIG AUFRAEUMEN (Befund 21.08.). Ein `kill-server` allein hat nicht
    # gereicht: nach mehreren Laeufen standen tmux-Server dieser Tests noch in
    # der Maschine, und ihre Socketdateien lagen herum. Ursache ist ein Rennen
    # -- ein noch laufender wb-nohup oder eine Attrappe kann den Server nach dem
    # Kill neu heraufziehen. Also mehrfach nachfassen und das Ergebnis PRUEFEN,
    # statt es anzunehmen. Der Socketname traegt die PID dieses Laufs, das
    # Muster kann also nichts Fremdes treffen.
    # DER WARTENDE CLIENT ZIEHT DEN SERVER WIEDER HOCH (gemessen 21.08.). Ein
    # `tmux new-session` der Attrappe bleibt als Client haengen; stirbt der
    # Server unter ihm, startet er einen neuen -- mit derselben Kommandozeile,
    # weshalb der Rest wie ein Server aussieht, der den Kill ueberlebt hat. Ein
    # Blick direkt nach dem kill-server sieht deshalb nichts und ein `break` an
    # dieser Stelle geht zu frueh: nach drei Laeufen standen drei solche
    # Prozesse in der Maschine. Also erst die PROZESSE, dann der Server, und
    # jede Runde mit Abstand -- der Socketname traegt die PID dieses Laufs, das
    # Muster kann nichts Fremdes treffen.
    local versuch hae
    for versuch in 1 2 3; do
        hae="$(pgrep -f "tmux .*$SOCKET" 2>/dev/null | tr '\n' ' ')"
        for p in $hae; do kill "$p" 2>/dev/null; done
        tmux_socket_beenden_ohne_reste "$SOCKET"
        sleep 0.5
    done
    hae="$(pgrep -f "tmux .*$SOCKET" 2>/dev/null | tr '\n' ' ')"
    if [ -n "$hae" ]; then
        for p in $hae; do kill -9 "$p" 2>/dev/null; done
        sleep 0.4
    fi
    hae="$(pgrep -f "tmux .*$SOCKET" 2>/dev/null | tr '\n' ' ')"
    [ -n "$hae" ] && echo "WARNUNG: tmux-Prozesse dieses Tests laufen noch: $hae" >&2
    rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
    rm -rf "$WORK" "$FAKEHOME"
}
trap cleanup EXIT INT TERM

[ -x "$NOHUP" ] || { echo "wb-nohup fehlt: $NOHUP" >&2; exit 1; }
: > "$WORK/pids"

# Ein Befehl, der lange genug lebt, dass wb-nohup ihn registriert (0,3 s + 1,2 s
# Nachschau). Kein `sleep`: eine Kopie davon wird auf dieser Maschine vom System
# abgeschossen, und `exec sleep` ersetzt den Prozessnamen (beides gemessen).
LANGLAEUFER=(/usr/bin/python3 -c 'import time; time.sleep(45)')

# `wb-nohup` unter eigenem HOME rufen; die PID landet in der Aufraeumliste.
#
# DIE PID GEHT UEBER EINE DATEI, NICHT UEBER EINE VARIABLE. Diese Funktion wird
# in `$(...)` gerufen, also in einer Subshell -- eine dort gesetzte Variable ist
# beim Rueckkehren wieder weg (derselbe Fallstrick wie beim Aufraeumen in
# anderen Suiten des Hauses).
ruf() {   # <umgebung...> -- Ausgabe auf stdout, PID in $WORK/letzte-pid
    : > "$WORK/letzte-pid"
    local pid fehler
    # STDOUT UND STDERR WERDEN GETRENNT, und das ist keine Kosmetik. `wb-nohup`
    # gibt auf stdout NUR die PID aus, seine Meldungen gehen auf stderr. Beides
    # zusammen einzusammeln und die letzte Zeile nach Ziffern zu filtern hat
    # diesen Test seine eigene Shell gekostet: die Ablehnung in Fall 6 nennt die
    # uebergebene PID ("PID 41361 sieht nicht wie das Werkbank-Programm aus"),
    # und das ist genau $$ -- die wanderte in die Aufraeumliste, und beim
    # Beenden hat der Test sich selbst SIGTERM geschickt. Sichtbar wurde es
    # daran, dass die Aufraeumfunktion zweimal anlief und nie zu Ende kam;
    # zurueck blieb jedes Mal ein tmux-Server.
    pid="$(env HOME="$FAKEHOME" "$@" "$NOHUP" probe -- "${LANGLAEUFER[@]}" 2>"$WORK/err" | tr -dc '0-9')"
    fehler="$(cat "$WORK/err" 2>/dev/null)"
    if [ -n "$pid" ] && [ "$pid" != "$$" ]; then
        printf '%s' "$pid" > "$WORK/letzte-pid"
        printf '%s\n' "$pid" >> "$WORK/pids"
    fi
    printf '%s\n%s' "$pid" "$fehler"
}
letzte() { cat "$WORK/letzte-pid" 2>/dev/null; }

echo "== 1  Ohne jede Quelle bleibt es beim harten Nein =="
AUS="$(ruf env -u TMUX -u TMUX_PANE -u WB_EIGENTUEMER_TMUX -u WB_EIGENTUEMER_TMUX_PANE -u WB_EIGENTUEMER_WERKBANK)"
printf '%s' "$AUS" | grep -q 'braucht einen tmux-Pane als Bezugspunkt' \
    && ok "1a: der Start wird abgelehnt" || bad "1a: nicht abgelehnt: $AUS"
printf '%s' "$AUS" | grep -q 'WB_EIGENTUEMER_WERKBANK' \
    && ok "1b: die Meldung nennt auch den Weg ueber die Werkbank" \
    || bad "1b: die Meldung verschweigt den dritten Weg: $AUS"

echo "== 2/3  Der gerettete Pane =="
tm new-session -d -s halter "while :; do sleep 5; done" 2>/dev/null
sleep 0.4
PANE="$(tm list-panes -t halter -F '#{pane_id}' 2>/dev/null | head -1)"
[ -n "$PANE" ] || { echo "  Testaufbau: kein Pane" >&2; exit 1; }
# `-u WB_EIGENTUEMER_WERKBANK` ist hier NICHT Kosmetik (21.08.2026): laeuft dieser Lauf
# unter der Werkbank -- und das tut er, sobald die Sitzung als Kind der Anwendung
# haengt --, dann erbt er die Variable, und `wb-nohup` beantwortet die Frage ueber den
# WERKBANK-Weg statt ueber den Pane. Zusage 1 raeumt sie laengst aus; hier fehlte sie,
# und der Fehler blieb so lange unsichtbar, wie die Sitzung neben der Anwendung lief
# statt unter ihr. Nach einem Neustart, der beide unter ein Dach brachte, fiel Zusage 3
# sofort -- mit der Meldung des Werkbank-Zweigs statt der erwarteten des Pane-Zweigs.
AUS="$(ruf env -u TMUX -u TMUX_PANE -u WB_EIGENTUEMER_WERKBANK WB_EIGENTUEMER_TMUX="$SOCKPATH,0,0" WB_EIGENTUEMER_TMUX_PANE="$PANE")"
PID2="$(letzte)"
if [ -n "$PID2" ] && [ -f "$REGDIR/$PID2.json" ]; then
    ok "2a: der Start geht durch und ist registriert"
    python3 -c "
import json,sys
d=json.load(open('$REGDIR/$PID2.json'))
sys.exit(0 if d.get('pane')=='$PANE' and d.get('socket_path')=='$SOCKPATH' and not d.get('werkbank_pid') else 1)
" && ok "2b: die Registrierung nennt den Pane, keine Werkbank" \
  || bad "2b: falscher Eigentuemer in $REGDIR/$PID2.json"
else
    bad "2: kein Start ueber den geretteten Pane: $AUS"
fi
AUS="$(ruf env -u TMUX -u TMUX_PANE -u WB_EIGENTUEMER_WERKBANK WB_EIGENTUEMER_TMUX="$SOCKPATH,0,0" WB_EIGENTUEMER_TMUX_PANE='%999')"
printf '%s' "$AUS" | grep -q 'braucht einen tmux-Pane als Bezugspunkt' \
    && ok "3: ein Pane, den es nicht gibt, traegt nicht" \
    || bad "3: ein erfundener Pane wurde angenommen: $AUS"

echo "== 4  Das Werkbank-Programm traegt =="
# Ein Vorfahre, der wie die Oberflaeche heisst. Der Name steht im Dateinamen,
# also in `ps -o command=` -- genau dort sieht wb-nohup nach.
cat > "$WORK/electron" <<EOF
#!/bin/bash
export HOME="$FAKEHOME"
env -u TMUX -u TMUX_PANE WB_EIGENTUEMER_WERKBANK=\$\$ "$NOHUP" probe -- \
  /usr/bin/python3 -c 'import time; time.sleep(45)' 2>/dev/null
EOF
chmod +x "$WORK/electron"
AUS="$("$WORK/electron")"
PID4="$(printf '%s\n' "$AUS" | tail -1 | tr -dc '0-9')"
[ -n "$PID4" ] && [ "$PID4" != "$$" ] && printf '%s\n' "$PID4" >> "$WORK/pids"
if [ -n "$PID4" ] && [ -f "$REGDIR/$PID4.json" ]; then
    ok "4a: der Start ueber das Werkbank-Programm geht durch"
    python3 -c "
import json,sys
d=json.load(open('$REGDIR/$PID4.json'))
sys.exit(0 if d.get('werkbank_pid') and d.get('werkbank_lstart') and not d.get('pane') else 1)
" && ok "4b: die Registrierung nennt PID und lstart-Pruefwert, keinen Pane" \
  || bad "4b: unvollstaendige Registrierung in $REGDIR/$PID4.json"
else
    bad "4: kein Start ueber die Werkbank: $AUS"
fi

echo "== 5/6/7  Und was NICHT traegt =="
TOTE=99999
while kill -0 "$TOTE" 2>/dev/null; do TOTE=$((TOTE-1)); done
AUS="$(ruf env -u TMUX -u TMUX_PANE WB_EIGENTUEMER_WERKBANK="$TOTE")"
printf '%s' "$AUS" | grep -q 'laeuft gerade nicht' \
    && ok "5: eine PID, die nicht laeuft, wird abgelehnt" || bad "5: angenommen: $AUS"
# Die eigene Shell laeuft und ist Vorfahre -- heisst aber nicht wie die Werkbank.
AUS="$(ruf env -u TMUX -u TMUX_PANE WB_EIGENTUEMER_WERKBANK="$$")"
printf '%s' "$AUS" | grep -q 'sieht nicht wie das Werkbank-Programm aus' \
    && ok "6: ein fremder Dauerlaeufer wird abgelehnt" || bad "6: angenommen: $AUS"
# Ein Prozess, der richtig heisst und laeuft, aber nicht in der Ahnenreihe steht.
# OHNE `exec`: mit exec ersetzt python3 den Prozess, der Name waere dann
# 'python3' und der Fall scheiterte schon an der Namenspruefung -- gemessen.
# So bleibt die Shell mit ihrem Dateinamen stehen und heisst wie die Werkbank.
cat > "$WORK/electron-fremd" <<'EOF'
#!/bin/bash
/usr/bin/python3 -c 'import time; time.sleep(45)'
EOF
chmod +x "$WORK/electron-fremd"
"$WORK/electron-fremd" & FREMD=$!
printf '%s\n' "$FREMD" >> "$WORK/pids"
sleep 0.5
AUS="$(ruf env -u TMUX -u TMUX_PANE WB_EIGENTUEMER_WERKBANK="$FREMD")"
if printf '%s' "$AUS" | grep -q 'nicht aus ihrer Prozesskette'; then
    ok "7: eine fremde Werkbank-PID wird abgelehnt, obwohl sie laeuft und passt"
else
    bad "7: eine fremde PID wurde angenommen: $AUS"
fi

echo "== 8  Ein echter Pane geht vor =="
AUS="$(ruf env TMUX="$SOCKPATH,0,0" TMUX_PANE="$PANE" WB_EIGENTUEMER_WERKBANK="$$")"
PID8="$(letzte)"
if [ -n "$PID8" ] && [ -f "$REGDIR/$PID8.json" ]; then
    python3 -c "
import json,sys
d=json.load(open('$REGDIR/$PID8.json'))
sys.exit(0 if d.get('pane')=='$PANE' and not d.get('werkbank_pid') else 1)
" && ok "8: der Pane steht in der Registrierung, die geerbte Werkbank-PID nicht" \
  || bad "8: die geerbte Werkbank-PID hat den Pane verdraengt"
else
    bad "8: kein Start mit echtem Pane: $AUS"
fi

echo "== 9  wb-code rettet die Werte wirklich =="
# Geprueft wird der ECHTE Ausschnitt aus wb-code, nicht eine Nachbildung: die
# beiden Zeilen werden aus der Datei geschnitten und ausgefuehrt. Faende der
# Schnitt nichts, liefe der Test auf einer leeren Datei -- deshalb zuerst die
# Laengenpruefung.
sed -n '/^export WB_EIGENTUEMER_TMUX=/,/^unset TMUX TMUX_PANE$/p' "$REPO/wb-code" > "$WORK/rettung.sh"
if [ "$(wc -l < "$WORK/rettung.sh")" -eq 3 ]; then
    ok "9a: der Ausschnitt aus wb-code ist gefunden (3 Zeilen)"
    # Gelesen wird in einem KIND-Prozess, nicht in derselben Shell: gerettet
    # ist nur, was auch weitergereicht wird, und genau das muss `wb-mlx-server`
    # spaeter vorfinden. Ohne `export` stuende hier "leer".
    ERG="$(env TMUX="$SOCKPATH,0,0" TMUX_PANE="$PANE" bash -c "
      source '$WORK/rettung.sh'
      bash -c 'echo \"\${WB_EIGENTUEMER_TMUX:-leer}|\${WB_EIGENTUEMER_TMUX_PANE:-leer}|\${TMUX:-weg}\"'")"
    [ "$ERG" = "$SOCKPATH,0,0|$PANE|weg" ] \
        && ok "9b: ein Kindprozess sieht beide Werte, \$TMUX ist weg" \
        || bad "9b: unerwartet: $ERG"
else
    bad "9a: der Ausschnitt aus wb-code fehlt oder hat sich geaendert"
fi

echo "== 10  wb-waisen stellt dieselbe Tatsachenfrage =="
# Die Funktion wird aus dem ECHTEN Quelltext geschnitten und aufgerufen.
sed -n '/^werkbank_laeuft()/,/^}/p' "$WAISEN" > "$WORK/waisenfn.sh"
if [ "$(wc -l < "$WORK/waisenfn.sh")" -ge 8 ]; then
    ok "10a: die Pruefung ist in wb-waisen vorhanden"
    LST="$(LC_ALL=C ps -o lstart= -p "$FREMD" 2>/dev/null)"
    bash -c "source '$WORK/waisenfn.sh'; werkbank_laeuft '$FREMD' '$LST'" \
        && ok "10b: ein lebender Eigentuemer gilt als lebend" \
        || bad "10b: ein lebender Eigentuemer wurde nicht erkannt"
    bash -c "source '$WORK/waisenfn.sh'; werkbank_laeuft '$FREMD' 'Mon Jan  1 00:00:00 2001'" \
        && bad "10c: ein falscher lstart-Pruefwert ging durch (PID-Wiederverwendung)" \
        || ok "10c: ein falscher lstart-Pruefwert wird abgelehnt"
    bash -c "source '$WORK/waisenfn.sh'; werkbank_laeuft '$TOTE' ''" \
        && bad "10d: eine tote PID galt als lebender Eigentuemer" \
        || ok "10d: eine tote PID ist kein Eigentuemer"
    bash -c "source '$WORK/waisenfn.sh'; werkbank_laeuft '$$' ''" \
        && bad "10e: ein fremder Prozessname ging durch" \
        || ok "10e: ein fremder Prozessname ist kein Eigentuemer"
else
    bad "10a: werkbank_laeuft fehlt in wb-waisen"
fi

echo "== 11  Ein Benutzer laesst sich eintragen =="
# Ein Modellserver wird gestartet, BEVOR es die Sitzung gibt, die ihn benutzt.
# Der vorlaeufige Eigentuemer muss deshalb spaeter durch den richtigen ersetzt
# werden koennen -- sonst zeigt die Registrierung nach dem Abraeumen der
# Hilfssession auf einen toten Pane, und wb-waisen meldet einen benutzten
# Server als Waise.
tm new-session -d -s ziel "while :; do sleep 5; done" 2>/dev/null
sleep 0.4
ZIELPANE="$(tm list-panes -t ziel -F '#{pane_id}' 2>/dev/null | head -1)"
AUS="$(ruf env -u TMUX -u TMUX_PANE WB_EIGENTUEMER_TMUX="$SOCKPATH,0,0" WB_EIGENTUEMER_TMUX_PANE="$PANE")"
PID11="$(letzte)"
if [ -n "$PID11" ] && [ -n "$ZIELPANE" ]; then
    env HOME="$FAKEHOME" "$NOHUP" benutzer "$PID11" --pane "$ZIELPANE" --socket "$SOCKPATH" >/dev/null 2>&1
    python3 -c "
import json,sys
d=json.load(open('$REGDIR/$PID11.json'))
sys.exit(0 if d.get('pane')=='$ZIELPANE' and d.get('eigentuemer_gewechselt') else 1)
" && ok "11a: die Registrierung nennt jetzt den Pane der Zielsitzung" \
  || bad "11a: der Wechsel steht nicht in $REGDIR/$PID11.json"
    # Ein Pane, den es nicht gibt, wird abgelehnt -- ein toter Eigentuemer waere
    # schlechter als der alte.
    env HOME="$FAKEHOME" "$NOHUP" benutzer "$PID11" --pane '%999' --socket "$SOCKPATH" >/dev/null 2>&1 \
      && bad "11b: ein toter Pane wurde als neuer Eigentuemer angenommen" \
      || ok "11b: ein Pane, den es nicht gibt, wird abgelehnt"
    python3 -c "
import json,sys
d=json.load(open('$REGDIR/$PID11.json'))
sys.exit(0 if d.get('pane')=='$ZIELPANE' else 1)
" && ok "11c: nach der Ablehnung steht der alte, gueltige Eigentuemer noch da" \
  || bad "11c: die abgelehnte Umschreibung hat die Registrierung beschaedigt"
else
    bad "11: der Fall liess sich nicht stellen (PID '$PID11', Pane '$ZIELPANE')"
fi
# Eine PID ohne Registrierung ist kein Fehlerfall zum Verschweigen.
# NICHT direkt in eine Pipe: `set -o pipefail` faerbt die ganze Pipe rot, weil
# das Werkzeug hier absichtlich mit Exit 1 endet -- das Ergebnis von `grep`
# waere dann bedeutungslos. Erst einfangen, dann pruefen.
AUS11="$(env HOME="$FAKEHOME" "$NOHUP" benutzer 999999 --pane "$ZIELPANE" --socket "$SOCKPATH" 2>&1)"
printf '%s' "$AUS11" | grep -q 'keine Registrierung' \
  && ok "11d: eine PID ohne Registrierung wird benannt, nicht stillschweigend uebergangen" \
  || bad "11d: die Meldung fehlt: $AUS11"

echo "== 12  Ein Server mit mehreren Benutzern =="
# Der Fall wird an der ENTSCHEIDUNG von wb-waisen gemessen, nicht an einer
# Meinung darueber: die beiden Funktionen werden aus dem echten Quelltext
# geschnitten und mit einer selbstgebauten Registrierung aufgerufen. Ein
# vollstaendiger wb-waisen-Lauf braeuchte einen Kandidaten mit ppid 1, ohne
# Terminal und ueber der RSS-Schwelle -- das misst dann den Kandidaten-Filter,
# nicht die Frage, um die es hier geht.
sed -n '/^LEBENDER_PANE=""/,/^}/p' "$WAISEN" > "$WORK/benutzerfn.sh"
sed -n '/^pane_ist_lebendig()/,/^}/p' "$WAISEN" >> "$WORK/benutzerfn.sh"
if [ "$(grep -c 'ein_benutzer_lebt' "$WORK/benutzerfn.sh")" -ge 1 ]; then
    ok "12-0: die Pruefung ist aus wb-waisen geschnitten (nicht nachgebaut)"
else
    bad "12-0: ein_benutzer_lebt fehlt in wb-waisen"
fi
tm new-session -d -s zweiter "while :; do sleep 5; done" 2>/dev/null
sleep 0.4
PANE_B="$(tm list-panes -t zweiter -F '#{pane_id}' 2>/dev/null | head -1)"
# a) Zwei Benutzer, der erste ist tot -- der zweite lebt.
LISTE="$(printf '%s\t%%999\n%s\t%s' "$SOCKPATH" "$SOCKPATH" "$PANE_B")"
if bash -c "TMUX_BIN='$(command -v tmux)'; source '$WORK/benutzerfn.sh'; ein_benutzer_lebt \"\$1\"" _ "$LISTE"; then
    ok "12a: ein toter Eigentuemer und ein lebender Benutzer heissen zusammen: KEINE Waise"
else
    bad "12a: der lebende Benutzer wurde uebersehen -- ein benutzter Server waere gemeldet worden"
fi
# b) Derselbe Fall, nachdem auch der zweite gegangen ist.
tm kill-session -t "=zweiter" 2>/dev/null
sleep 0.4
if bash -c "TMUX_BIN='$(command -v tmux)'; source '$WORK/benutzerfn.sh'; ein_benutzer_lebt \"\$1\"" _ "$LISTE"; then
    bad "12b: nach dem Ende des letzten Benutzers galt der Server noch als benutzt"
else
    ok "12b: stirbt der letzte Benutzer, ist es eine Waise"
fi
# c) Gar kein Benutzer, von Anfang an.
if bash -c "TMUX_BIN='$(command -v tmux)'; source '$WORK/benutzerfn.sh'; ein_benutzer_lebt ''"; then
    bad "12c: eine leere Liste galt als lebender Benutzer"
else
    ok "12c: ohne jeden Benutzer ist es eine Waise"
fi

echo "== 13  Der Eintrag ist additiv, nicht ersetzend =="
# Genau das war die Ursache: ein zweiter Eintrag darf den ersten nicht
# verdraengen, sonst haengt alles am zuletzt gestarteten.
tm new-session -d -s dritter "while :; do sleep 5; done" 2>/dev/null
sleep 0.4
PANE_C="$(tm list-panes -t dritter -F '#{pane_id}' 2>/dev/null | head -1)"
AUS="$(ruf env -u TMUX -u TMUX_PANE WB_EIGENTUEMER_TMUX="$SOCKPATH,0,0" WB_EIGENTUEMER_TMUX_PANE="$PANE")"
PID13="$(letzte)"
if [ -n "$PID13" ] && [ -n "$PANE_C" ]; then
    env HOME="$FAKEHOME" "$NOHUP" benutzer "$PID13" --pane "$PANE_C" --socket "$SOCKPATH" >/dev/null 2>&1
    python3 -c "
import json,sys
d=json.load(open('$REGDIR/$PID13.json'))
b=[x.get('pane') for x in d.get('benutzer', [])]
sys.exit(0 if '$PANE' in b and '$PANE_C' in b else 1)
" && ok "13a: BEIDE Panes stehen in der Benutzerliste" \
  || bad "13a: der zweite Eintrag hat den ersten verdraengt"
    # Zweimal derselbe Pane bleibt ein Eintrag -- sonst waere die Liste nur Rauschen.
    env HOME="$FAKEHOME" "$NOHUP" benutzer "$PID13" --pane "$PANE_C" --socket "$SOCKPATH" >/dev/null 2>&1
    python3 -c "
import json,sys
d=json.load(open('$REGDIR/$PID13.json'))
b=[x.get('pane') for x in d.get('benutzer', [])]
sys.exit(0 if b.count('$PANE_C') == 1 else 1)
" && ok "13b: derselbe Pane zweimal eingetragen bleibt ein Eintrag" \
  || bad "13b: die Liste sammelt Doppelte"
else
    bad "13: der Fall liess sich nicht stellen (PID '$PID13', Pane '$PANE_C')"
fi
tm kill-session -t "=dritter" 2>/dev/null

echo
echo "  bestanden: $pass, gescheitert: $fail"
[ "$fail" -eq 0 ]
