#!/usr/bin/env bash
# test-post.sh -- die Zusagen des Postfachs zwischen Orchestratoren (shell/wb-post).
#
# ANLASS (11.08.): Auf dieser Maschine laufen mehrere Werkbank-Sitzungen
# nebeneinander, und in der Nacht zum 11.08. sind sich zwei nur deshalb nicht ins
# Gehege gekommen, weil ihre Orchestratoren einander zufaellig Nachrichten
# geschickt haben. Der Weg, den es bisher gab -- die Nachrichtenfunktion des
# Harness --, hat zwei Loecher: er kennt nur Claude-Sitzungen, und seine Adresse
# wird ungueltig, sobald der andere Prozess neu startet (in derselben Nacht lief
# eine Antwort so in einen toten Socket).
#
# DIE ZUSAGEN, die hier hergestellt und gemessen werden:
#   1  Eine Nachricht kommt an: der Empfaenger sieht Text und Absender.
#   2  Sie laesst sich als gelesen markieren und ist danach aus dem Ungelesenen
#      verschwunden, ohne aus dem Postfach zu verschwinden.
#   3  Sie geht NICHT verloren, wenn der Empfaenger gerade nicht laeuft -- weder
#      wenn es seine Sitzung noch gar nicht gibt, noch wenn sie zwischendurch
#      stirbt und neu startet. Das ist der Punkt, an dem der Harness-Weg versagt.
#   4  Zwei Absender in derselben Sekunde ueberschreiben einander nicht.
#   5  Die Zustellung in den Pane geht ausschliesslich ueber `wb-pane-write` und
#      nie mit Enter. In einen Orchestrator-Pane wird sie erwartungsgemaess
#      abgelehnt (das ist Regel des Nutzers vom 06.08., nicht ein Fehlschlag), und
#      genau das wird ehrlich gemeldet -- die Nachricht liegt trotzdem im Postfach.
#   6  Nichts haengt und nichts landet ausserhalb des Postfachverzeichnisses.
#   7  Die drei Befunde des dritten Pruefdurchgangs (11.08.): ein Tippfehler im
#      Zielnamen wird als solcher gemeldet, eine unlesbare Datei wird nicht mehr
#      stillschweigend uebergangen, und ein Orchestrator, dessen Rolle nur im
#      REGISTER steht, wird gefunden -- `wb-pane-write` fragt ueber `wb-rolle lesen`
#      beide Quellen, wer nur `#{@wb_role}` liest, haelt ihn fuer tot.
#
# ISOLATION: eigener tmux-Socket mit PID im Namen, eigenes HOME (`mktemp -d`), die
# Werkzeuge als Symlinks aus dem Arbeitsbaum (lib-testwerkzeuge.sh). Die laufende
# Sitzung und Fenster des Nutzers werden nicht angefasst.
#
# WARUM DAS HIER BESONDERS ZAEHLT: Beim ersten Rauchtest dieses Werkzeugs von Hand,
# ohne Socketwahl, hat der Hinweis den LEBENDEN Orchestrator-Pane getroffen und
# wurde dort von `wb-pane-write` abgelehnt. Geschrieben wurde nichts -- die
# Sicherung hat gehalten --, aber die Suite haengt sich deshalb ausdruecklich an
# den Testsocket, und `wb-post` waehlt seinen Server seither selbst
# (`$TMUX`, sonst `WB_TMUX_SOCKET`).
#
# Die Panes sind `cat` und keine Shell: was hineingeschrieben wuerde, darf nie als
# Kommando laufen.
unset TMUX TMUX_PANE
set -uo pipefail

MARK="${LIVE_MARKER:+-$LIVE_MARKER}"
SOCKET="wbtest-post$MARK-$$"
EMPF="wb-empfaenger$MARK-$$"
ABS="wb-absender$MARK-$$"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${WB_POST:-$REPO/wb-post}"
echo "Geprueft: $TOOL"

FAKEHOME="$(mktemp -d)"
WORK="$(mktemp -d)"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$FAKEHOME" wb-pane-write wb-mensch context-guard wb-post \
    || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }

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

export HOME="$FAKEHOME"

# Ein Schirm um wb-pane-write: er schreibt jeden Aufruf mit und fuehrt danach die
# ECHTE Fassung aus. Die Entscheidung, wer tippen darf, bleibt also beim echten
# Werkzeug -- gezaehlt wird nur, WAS wb-post von ihm verlangt hat. Dasselbe Muster
# wie in test-absende-pruefung.sh.
SCHIRM="$WORK/wb-pane-write"
cat > "$SCHIRM" <<EOF
#!/bin/sh
echo "\$*" >> "$WORK/panewrite.log"
exec "$FAKEHOME/.local/bin/wb-pane-write" "\$@"
EOF
chmod +x "$SCHIRM"
export WB_PANE_WRITE="$SCHIRM"

post() { "$TOOL" "$@"; }
postfach() { echo "$FAKEHOME/.local/state/wb-post/$1"; }
anzahl_im_postfach() { ls "$(postfach "$1")"/*.json 2>/dev/null | wc -l | tr -d ' '; }

# --- Testserver -------------------------------------------------------------
HOME="$FAKEHOME" tm new-session -d -s "$ABS" -n main cat \
    || { echo "tmux-Testserver liess sich nicht starten" >&2; exit 1; }
tm set -g remain-on-exit on

empfaenger_starten() {
    HOME="$FAKEHOME" tm new-session -d -s "$EMPF" -n main cat || return 1
    local pane
    pane=$(tm list-panes -t "=$EMPF" -F '#{pane_id}' | head -1)
    # Der Empfaenger ist ein ORCHESTRATOR-Pane -- genau der Fall, um den es geht.
    tm set -p -t "$pane" @wb_role orchestrator
    printf '%s' "$pane"
}

# Ein Befehl in einem Pane des Testservers. Der Pane ist der Anker: tmux setzt
# seiner Shell ein $TMUX auf DIESEN Server, wb-post redet dadurch mit dem
# Testserver und nicht mit dem laufenden (regeln/tests-und-eingriffe.md).
#
# Der neue Pane traegt @wb_role=worker (wie test-mensch-und-schalter.sh es fuer
# jeden simulierten Agenten tut): eine nackte tmux-Pane mit geleerter
# Agenten-Umgebung gilt `wb-mensch` sonst als MENSCH (M1, steuerndes Terminal) --
# ob die Nachricht ueber `wb-post` von einem Agenten oder einem Menschen kommt,
# haengt sonst vom Zufall ab, ob CLAUDECODE o.ae. aus der aufrufenden Umgebung in
# den Pane durchsickert. Gemessen: ohne die Markierung meldet Abschnitt 2 der
# Suite "eingefuegt" statt "abgelehnt", sobald der Lauf ohne solche Variablen
# startet -- der Orchestrator-Schutz wird dann gar nicht erst geprueft.
im_pane() {   # <session> <fenstername> <befehl-als-eine-zeile>
    local sess="$1" name="$2" befehl="$3" pane
    rm -f "$WORK/$name.out" "$WORK/$name.done" "$WORK/$name.rc"
    cat > "$WORK/$name.sh" <<EOF
export HOME="$FAKEHOME"
export WB_PANE_WRITE="$SCHIRM"
$befehl > "$WORK/$name.out" 2>&1
echo \$? > "$WORK/$name.rc"
touch "$WORK/$name.done"
exec cat
EOF
    pane=$(tm new-window -d -t "=$sess" -n "$name" -P -F '#{pane_id}' "sh $WORK/$name.sh")
    tm set -p -t "$pane" @wb_role worker
}
rc_von() { cat "$WORK/$1.rc" 2>/dev/null; }
ausgabe() { cat "$WORK/$1.out" 2>/dev/null; }

echo
echo "== 1  Eine Nachricht kommt an =="

EMPF_PANE="$(empfaenger_starten)"
im_pane "$ABS" senden "'$TOOL' schreiben '$EMPF' --betreff 'Speicher' \
    Ich lade lmbeta-27b und halte 30 GiB fuer 40 min."
warte_auf_datei "$WORK/senden.done" 20 "das Senden" || true
if [ "$(rc_von senden)" = "0" ]; then ok "die Nachricht wird abgelegt (Exit 0)"
else bad "das Senden schlug fehl (rc=$(rc_von senden)): $(ausgabe senden)"; fi
if [ "$(anzahl_im_postfach "$EMPF")" = "1" ]; then ok "sie liegt als eine Datei im Postfach des Empfaengers"
else bad "im Postfach liegen $(anzahl_im_postfach "$EMPF") Dateien"; fi

im_pane "$EMPF" lesen1 "'$TOOL' lesen"
warte_auf_datei "$WORK/lesen1.done" 20 "das Lesen" || true
if [ "$(rc_von lesen1)" = "0" ] && ausgabe lesen1 | grep -q "lmbeta-27b"; then
    ok "der Empfaenger liest den Text in seinem eigenen Pane"
else
    bad "der Empfaenger sah den Text nicht (rc=$(rc_von lesen1)): $(ausgabe lesen1)"
fi
if ausgabe lesen1 | grep -q "$ABS"; then ok "die Nachricht nennt die Sitzung des Absenders"
else bad "der Absender fehlt: $(ausgabe lesen1)"; fi
if ausgabe lesen1 | grep -q "Betreff: Speicher"; then ok "der Betreff kommt mit"
else bad "der Betreff fehlt"; fi

echo
echo "== 2  Die Zustellung geht ueber wb-pane-write und nie mit Enter =="

if grep -q "einfuegen $EMPF_PANE" "$WORK/panewrite.log" 2>/dev/null; then
    ok "der Hinweis wurde ueber wb-pane-write an den Pane des Empfaengers versucht"
else
    bad "wb-pane-write wurde nicht mit dem Pane des Empfaengers gerufen: $(cat "$WORK/panewrite.log" 2>/dev/null)"
fi
if grep -qi "taste\|Enter" "$WORK/panewrite.log" 2>/dev/null; then
    bad "es wurde eine Taste geschickt: $(cat "$WORK/panewrite.log")"
else
    ok "es wurde nie eine Taste geschickt, also nichts in einem fremden Chat abgesendet"
fi
if ausgabe senden | grep -q "abgelehnt (Orchestrator-Schutz"; then
    ok "die Ablehnung durch den Orchestrator-Schutz wird ehrlich gemeldet"
else
    bad "die Ablehnung wird nicht als solche gemeldet: $(ausgabe senden)"
fi
if ausgabe senden | grep -q "liegt im Postfach"; then
    ok "und die Meldung sagt, dass die Nachricht trotzdem liegt"
else
    bad "die Meldung sagt nicht, dass die Nachricht liegt"
fi

echo
echo "== 3  Als gelesen markieren =="

KENNUNG="$(post lesen --sitzung "$EMPF" --json \
    | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["nachrichten"][0]["id"])')"
im_pane "$EMPF" markieren "'$TOOL' gelesen $KENNUNG"
warte_auf_datei "$WORK/markieren.done" 20 "das Markieren" || true
if [ "$(rc_von markieren)" = "0" ]; then ok "die Nachricht laesst sich als gelesen markieren"
else bad "das Markieren schlug fehl: $(ausgabe markieren)"; fi

im_pane "$EMPF" lesen2 "'$TOOL' lesen"
warte_auf_datei "$WORK/lesen2.done" 20 "das zweite Lesen" || true
if [ "$(rc_von lesen2)" = "1" ]; then ok "danach ist nichts Ungelesenes mehr da (Exit 1)"
else bad "die gelesene Nachricht taucht weiter als ungelesen auf: $(ausgabe lesen2)"; fi
if [ "$(anzahl_im_postfach "$EMPF")" = "1" ] && post lesen --sitzung "$EMPF" --alle | grep -q "GELESEN"; then
    ok "sie ist aus dem Ungelesenen verschwunden, nicht aus dem Postfach"
else
    bad "die gelesene Nachricht ist aus dem Postfach verschwunden"
fi

echo
echo "== 4  Nichts geht verloren, wenn der Empfaenger nicht laeuft =="

TOT="wb-nichtda$MARK-$$"
im_pane "$ABS" andietote "'$TOOL' schreiben '$TOT' Bitte melde Dich, wenn Du wieder da bist."
warte_auf_datei "$WORK/andietote.done" 20 "das Senden an eine tote Sitzung" || true
if [ "$(rc_von andietote)" = "0" ]; then ok "an eine Sitzung, die es nicht gibt, wird trotzdem abgelegt (Exit 0)"
else bad "das Senden an eine tote Sitzung schlug fehl (rc=$(rc_von andietote))"; fi
if ausgabe andietote | grep -q "kein lebender Orchestrator-Pane"; then
    ok "und es wird gesagt, dass niemand da war"
else
    bad "der fehlende Empfaenger wird nicht benannt: $(ausgabe andietote)"
fi
if [ "$(anzahl_im_postfach "$TOT")" = "1" ]; then ok "die Nachricht liegt im Postfach der noch gar nicht laufenden Sitzung"
else bad "im Postfach der toten Sitzung liegt nichts"; fi

# Der Empfaenger stirbt und kommt zurueck -- genau der Fall, an dem der
# Harness-Weg scheitert, weil seine Adresse mit dem Prozess stirbt.
im_pane "$ABS" vordemtod "'$TOOL' schreiben '$EMPF' Diese Nachricht muss den Neustart ueberleben."
warte_auf_datei "$WORK/vordemtod.done" 20 "das Senden vor dem Neustart" || true
tm kill-session -t "=$EMPF" 2>/dev/null
warte_auf_bedingung 10 "die Empfaenger-Sitzung ist fort" \
    '! tm has-session -t "=$EMPF" 2>/dev/null' || true
EMPF_PANE="$(empfaenger_starten)"
im_pane "$EMPF" lesen3 "'$TOOL' lesen"
warte_auf_datei "$WORK/lesen3.done" 20 "das Lesen nach dem Neustart" || true
if ausgabe lesen3 | grep -q "muss den Neustart ueberleben"; then
    ok "die Nachricht ueberlebt Tod und Neustart des Empfaengers"
else
    bad "die Nachricht ist beim Neustart verlorengegangen: $(ausgabe lesen3)"
fi

echo
echo "== 5  Zwei Absender in derselben Sekunde ueberschreiben einander nicht =="

VOR="$(anzahl_im_postfach "$EMPF")"
rm -f "$WORK/los"
for n in a b; do
    im_pane "$ABS" "gleich$n" "while [ ! -f '$WORK/los' ]; do sleep 0.02; done; \
'$TOOL' schreiben '$EMPF' Gleichzeitig $n"
done
sleep 0.3
touch "$WORK/los"
warte_auf_datei "$WORK/gleicha.done" 20 "Absender a" || true
warte_auf_datei "$WORK/gleichb.done" 20 "Absender b" || true
NACH="$(anzahl_im_postfach "$EMPF")"
if [ "$((NACH - VOR))" = "2" ]; then ok "beide gleichzeitigen Nachrichten liegen im Postfach"
else bad "aus zwei gleichzeitigen Nachrichten wurden $((NACH - VOR))"; fi

echo
echo "== 6  Grenzen: kein Haengen, nichts ausserhalb des Postfachs =="

START=$SECONDS
if ( unset TMUX TMUX_PANE WB_SESSION; post lesen </dev/null >/dev/null 2>&1 ); then
    bad "'lesen' ohne Sitzung ausserhalb von tmux lief einfach durch"
else
    ok "'lesen' ohne Sitzung ausserhalb von tmux sagt, dass die Adresse fehlt"
fi
if [ $((SECONDS - START)) -lt 10 ]; then ok "und es wartet dabei auf nichts"
else bad "der Aufruf hing $((SECONDS - START))s"; fi

if ( unset TMUX TMUX_PANE; post schreiben "$EMPF" </dev/null >/dev/null 2>&1 ); then
    bad "eine leere Nachricht wurde abgelegt"
else
    ok "eine leere Nachricht wird abgelehnt statt abgelegt"
fi

# Ein Sitzungsname mit '../' darf nichts ausserhalb von ~/.local/state/wb-post
# anlegen. Am 28.07. hat ein Pane namens '../evil' aus einer
# Path-Traversal-Reproduktion in laufender des Nutzers Sitzung gestanden.
( unset TMUX TMUX_PANE; echo "harmlos" | post schreiben "../evil" --nur-ablegen >/dev/null 2>&1 )
if [ ! -e "$FAKEHOME/.local/state/evil" ] && [ -d "$FAKEHOME/.local/state/wb-post/.._evil" ]; then
    ok "ein Zielname mit '../' bleibt im Postfachverzeichnis"
else
    bad "der Zielname '../evil' hat ausserhalb des Postfachs geschrieben"
fi

# Ausserhalb eines Panes, dafuer mit WB_TMUX_SOCKET auf den Testserver -- das ist
# zugleich die Probe darauf, dass wb-post seinen Server auch ohne $TMUX richtig
# waehlt und nicht beim Vorgabeserver landet.
( unset TMUX TMUX_PANE
  WB_TMUX_SOCKET="$SOCKET" WB_PANE_WRITE="$WORK/gibtsnicht" \
      post schreiben "$EMPF" egal >/dev/null 2>&1
  echo $? > "$WORK/ohnewerkzeug.rc" )
if [ "$(rc_von ohnewerkzeug)" = "2" ]; then
    ok "ein ausdruecklich falscher WB_PANE_WRITE-Pfad ist ein Fehler, kein stiller Rueckfall"
else
    bad "ein falscher WB_PANE_WRITE-Pfad wurde stillschweigend uebergangen (rc=$(rc_von ohnewerkzeug))"
fi

echo
echo "== 7  Was der dritte Pruefdurchgang gefunden hat =="

# Befund 14: ein Tippfehler im Zielnamen verschluckte die Nachricht lautlos, weil die
# Zustellzeile Wort fuer Wort dieselbe war wie bei einem Empfaenger, der gerade nicht
# laeuft.
TIPPFEHLER="wb-Empfaenger-mit-Tippfehler$MARK-$$"
AUS="$( ( unset TMUX TMUX_PANE
          WB_TMUX_SOCKET="$SOCKET" post schreiben "$TIPPFEHLER" --nur-ablegen \
              "wichtig: ich halte 30 GiB" ) 2>&1 )"
if printf '%s' "$AUS" | grep -q "moeglicherweise ein Tippfehler"; then
    ok "ein unbekannter Zielname wird als vermutlicher Tippfehler gemeldet"
else
    bad "der unbekannte Zielname ging lautlos durch: $AUS"
fi
if printf '%s' "$AUS" | grep -q "Bekannt sind:.*$EMPF"; then
    ok "und die bekannten Namen stehen daneben"
else
    bad "die bekannten Namen fehlen in der Warnung: $AUS"
fi
if [ "$(anzahl_im_postfach "$TIPPFEHLER")" = "1" ]; then
    ok "abgelegt wird sie trotzdem — eine Sitzung kann es auch erst spaeter geben"
else
    bad "die Nachricht wurde wegen der Warnung gar nicht abgelegt"
fi
AUS="$( ( unset TMUX TMUX_PANE
          WB_TMUX_SOCKET="$SOCKET" post schreiben "$EMPF" --nur-ablegen "an das bekannte Ziel" ) 2>&1 )"
if ! printf '%s' "$AUS" | grep -q "Tippfehler"; then
    ok "ein bekanntes Ziel wird nicht angemeckert"
else
    bad "auch das bekannte Ziel wurde als Tippfehler gemeldet: $AUS"
fi

# Befund 15: eine unlesbare Datei wurde uebergangen, ohne dass es jemand erfuhr --
# gegen den eigenen Anspruch, dass keine Nachricht verschwindet, weil niemand hinsah.
echo "das ist kein JSON" > "$(postfach "$EMPF")/1700000000-defekt.json"
AUS="$( ( unset TMUX TMUX_PANE; WB_TMUX_SOCKET="$SOCKET" post lesen --sitzung "$EMPF" ) 2>&1 )"
if printf '%s' "$AUS" | grep -q "ist nicht lesbar"; then
    ok "eine beschaedigte Nachricht wird gemeldet statt stillschweigend uebergangen"
else
    bad "die beschaedigte Nachricht blieb unsichtbar: $AUS"
fi
if printf '%s' "$AUS" | grep -q "an das bekannte Ziel"; then
    ok "und die lesbaren Nachrichten kommen trotzdem durch"
else
    bad "die beschaedigte Datei hat das Lesen abgebrochen"
fi
rm -f "$(postfach "$EMPF")/1700000000-defekt.json"

# Befund 16: der Empfaenger wurde nur ueber die Pane-Option gefunden. `wb-pane-write`
# fragt ueber `wb-rolle lesen` BEIDE Quellen und gibt dem Register sogar den Vorrang;
# ein Orchestrator, dessen Rolle nur im Register steht, sah fuer wb-post aus wie eine
# tote Sitzung. Der Stellvertreter hier antwortet wie `wb-rolle lesen`, damit der Test
# nicht am Format des echten Registers haengt.
REG="wb-nur-im-register$MARK-$$"
HOME="$FAKEHOME" tm new-session -d -s "$REG" -n main cat
REG_PANE=$(tm list-panes -t "=$REG" -F '#{pane_id}' | head -1)
ROLLE_SCHIRM="$WORK/wb-rolle"
cat > "$ROLLE_SCHIRM" <<EOF
#!/bin/sh
echo "\$*" >> "$WORK/wbrolle.log"
# Nur der Pane aus dem Register ist Orchestrator; alle anderen sind es nicht.
for a in "\$@"; do
    if [ "\$a" = "$REG_PANE" ]; then printf 'register\torchestrator\neffektiv\torchestrator\n'; exit 0; fi
done
printf 'effektiv\t\n'
EOF
chmod +x "$ROLLE_SCHIRM"
AUS="$( ( unset TMUX TMUX_PANE
          WB_TMUX_SOCKET="$SOCKET" WB_ROLLE="$ROLLE_SCHIRM" \
              post schreiben "$REG" "nur im Register" ) 2>&1 )"
if printf '%s' "$AUS" | grep -q "Pane $REG_PANE"; then
    ok "ein Orchestrator, dessen Rolle nur im Register steht, wird gefunden"
else
    bad "der Empfaenger aus dem Register wurde nicht gefunden: $AUS"
fi
if grep -q "lesen $REG_PANE" "$WORK/wbrolle.log" 2>/dev/null; then
    ok "gefragt wird ueber 'wb-rolle lesen', nicht ueber eine eigene zweite Quelle"
else
    bad "wb-rolle wurde nicht gefragt: $(cat "$WORK/wbrolle.log" 2>/dev/null)"
fi
tm kill-session -t "=$REG" 2>/dev/null

echo
echo "== 8  Der Ueberblick ueber die Postfaecher =="

AUS="$(post postfaecher 2>&1)"
if printf '%s' "$AUS" | grep -q "$EMPF" && printf '%s' "$AUS" | grep -q "$TOT"; then
    ok "postfaecher zeigt beide Postfaecher mit ihrem Ungelesenen"
else
    bad "postfaecher zeigt nicht alle: $AUS"
fi

echo
echo "Ergebnis: $pass ok, $fail FAIL"
[ "$fail" -eq 0 ]
