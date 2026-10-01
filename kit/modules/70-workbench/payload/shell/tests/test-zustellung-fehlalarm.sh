#!/usr/bin/env bash
# test-zustellung-fehlalarm.sh -- der Fehlalarm in der anderen Richtung: ein
# arbeitender Worker, der als gescheitert gemeldet wird.
#
# ANLASS (2026-08-20). Zwei von fuenf Workern dieser Sitzung bekamen eine
# `zustellung-fehlgeschlagen.md`, und BEIDE haben trotzdem gearbeitet. Der
# Schaden war nicht die Datei, sondern der Zeiger: `latest.md` zeigte danach auf
# den Fehlschlag statt auf das kommende Ergebnis, und wer `latest.md` liest --
# Wachen, die Oberflaeche, der Orchestrator -- las stundenlang "gescheitert",
# waehrend der Worker arbeitete.
#
# DIE BEDINGUNG, reproduziert und hier festgehalten: BEIDE Belegquellen waren
# gleichzeitig blind.
#
#   * Der Pane kann nichts belegen. Claude Code laeuft im Alternate Screen, und
#     dafuer fuehrt tmux keinen Verlauf -- gemessen ergibt alternate_on=1 ein
#     history_size=0, und `capture-pane -S -2000` liefert nur das sichtbare
#     Bild. Sobald die Sitzung zu arbeiten anfaengt, ist der Marker heraus.
#   * Die Gespraechsdatei gab es noch nicht. Sie entsteht rund zwei Sekunden
#     nach dem Start einer Sitzung; `pi-worker` fragte einmal, unmittelbar nach
#     dem Senden, und danach nie wieder.
#
# Geprueft werden die drei Zusagen, die daraus folgen:
#   1  Sind beide Quellen blind, lautet das Urteil UNENTSCHIEDEN: Rueckgabewert
#      0, Platzhalter bleibt, KEINE Fehlschlagdatei, latest.md zeigt weiter auf
#      den Platzhalter -- und die Nachricht ist nachweislich angekommen.
#   2  Entsteht die Gespraechsdatei ERST WAEHREND der Wartezeit, wird sie
#      gefunden und die Ankunft belegt. Das ist die Zusage, die das einmalige
#      Nachfragen vorher gebrochen hat.
#   3  Fuehrt der Pane einen Verlauf, bleibt ein fehlender Marker ein LAUTER
#      Fehlschlag. Das neue Urteil darf keinen echten Fehlschlag verschlucken.
#   4  Und `wb-inbox` adressiert nur den tmux-Server, den es bekommt: ohne `-L`
#      loeste es eine Pane-Kennung auf dem umgebenden Server auf und hat so eine
#      Testnachricht in eine laufende Sitzung zugestellt.
#
# ISOLATION und LOESCH-SICHERUNG: siehe lib-zustellbett.sh.
# LAUFZEIT: rund zweieinhalb Minuten, davon zweimal die 60-s-Frist des
# Socket-Wegs -- die muss wirklich ablaufen, sonst misst der Test die Ungeduld.
set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-zustellbett.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOR="$(cd "$HIER/.." && pwd)"
command -v tmux >/dev/null 2>&1 || ueberspringen "tmux nicht im PATH"
[ -x "$VOR/pi-worker" ]             || ueberspringen "shell/pi-worker fehlt"
[ -x "$VOR/wb-inbox" ]              || ueberspringen "shell/wb-inbox fehlt"
[ -f "$HIER/fake-claude-inbox.py" ] || ueberspringen "fake-claude-inbox.py fehlt"
command -v /usr/bin/python3 >/dev/null || ueberspringen "python3 fehlt"

echo "== Fehlalarm: ein arbeitender Worker darf nicht als gescheitert gelten =="
zustellbett_start || ueberspringen "Testaufbau fehlgeschlagen"
trap zustellbett_ende EXIT INT TERM

fehlschlagdatei() {   # <worker> -> Pfad oder leer
  ls -1 "$TESTHOME/.pi-workers/results/$1"/*.zustellung-fehlgeschlagen.md 2>/dev/null | head -1
}

# ── 1: beide Quellen blind -> unentschieden ───────────────────────────────────
echo
echo "-- 1: Alternate Screen UND noch keine Gespraechsdatei --"
zustellbett_panes_weg
zustellbett_leeren "$RECV"
zustellbett_wie_claude_code 60 90
zustellbett_claude_inbox normal
F1="f1$MARKE"
A="$(pi_lauf socket "$F1" "FEHLALARM-EINS-$MARKE")"; RC=$?
[ "$RC" -eq 0 ] \
  && ok "1: Rueckgabewert 0 -- kein Fehlschlag behauptet" \
  || bad "1: Rueckgabewert $RC, obwohl nichts widerlegt war"
case "$A" in
  *UNENTSCHIEDEN*) ok "1: das Urteil heisst ausdruecklich UNENTSCHIEDEN" ;;
  *) bad "1: kein unentschieden-Urteil: $(printf '%s' "$A" | grep -m1 -E 'FEHLER|zugestellt')" ;;
esac
case "$A" in
  *"Alternate Screen"*) ok "1: und die Meldung nennt den Grund, aus dem der Pane nichts belegen kann" ;;
  *) bad "1: der Grund wird nicht genannt" ;;
esac
[ -z "$(fehlschlagdatei "$F1")" ] \
  && ok "1: keine Fehlschlagdatei geschrieben" \
  || bad "1: es liegt eine Fehlschlagdatei -- $(fehlschlagdatei "$F1")"
[ "$(zustellbett_platzhalter "$F1")" = steht ] \
  && ok "1: der Platzhalter bleibt stehen" \
  || bad "1: der Platzhalter wurde entfernt, ein spaeteres Ergebnis findet den Zeiger nicht mehr vor"
ZIEL="$(readlink "$TESTHOME/.pi-workers/results/$F1/latest.md" 2>/dev/null)"
case "$ZIEL" in
  *.laufend.md) ok "1: latest.md zeigt weiter auf den Platzhalter, nicht auf einen Fehlschlag" ;;
  *) bad "1: latest.md zeigt auf '${ZIEL:-nichts}'" ;;
esac
# Der Kern der Sache: die Nachricht IST angekommen. Ohne diese Gegenprobe misst
# der Test nur, dass pi-worker still ist, nicht dass es zu Recht still ist.
[ "$(zustellbett_empfang_zahl)" -ge 1 ] \
  && ok "1: die Nachricht war bei der Sitzung angekommen -- der Fehlschlag waere ein Fehlalarm gewesen" \
  || bad "1: die Nachricht kam gar nicht an, dieser Fall misst etwas anderes als gedacht"

# ── 2: die Gespraechsdatei entsteht WAEHREND der Wartezeit ────────────────────
echo
echo "-- 2: die Gespraechsdatei entsteht erst nach dem Senden --"
zustellbett_panes_weg
zustellbett_leeren "$RECV"
# Acht Sekunden: deutlich nach dem Moment, in dem frueher EINMAL gefragt wurde,
# und weit vor der 60-s-Frist. Wer nur einmal fragt, findet hier nichts.
zustellbett_wie_claude_code 60 8
zustellbett_claude_inbox normal
F2="f2$MARKE"
A="$(pi_lauf socket "$F2" "FEHLALARM-ZWEI-$MARKE")"; RC=$?
[ "$RC" -eq 0 ] && ok "2: Rueckgabewert 0" || bad "2: Rueckgabewert $RC"
case "$A" in
  *"Ankunft belegt: Gespraechsdatei"*) ok "2: die Ankunft wird ueber die spaeter entstandene Gespraechsdatei belegt" ;;
  *UNENTSCHIEDEN*) bad "2: es bleibt beim unentschieden -- die Datei wurde nicht erneut gesucht" ;;
  *) bad "2: unerwartete Auskunft: $(printf '%s' "$A" | grep -m1 -E 'FEHLER|zugestellt|UNENTSCHIEDEN')" ;;
esac

# ── 3: fuehrt der Pane einen Verlauf, bleibt es beim lauten Fehlschlag ────────
echo
echo "-- 3: Pane MIT Verlauf, Nachricht verschluckt -- weiterhin ein Fehlschlag --"
zustellbett_panes_weg
zustellbett_leeren "$RECV"
zustellbett_wie_stellvertreter          # kein Alternate Screen: der Pane fuehrt Verlauf
ZB_TRANSCRIPT_NACH=90                   # und auch hier gibt es keine Gespraechsdatei
zustellbett_claude_inbox taub
F3="f3$MARKE"
A="$(pi_lauf socket "$F3" "FEHLALARM-DREI-$MARKE")"; RC=$?
[ "$RC" -ne 0 ] \
  && ok "3: Rueckgabewert $RC -- ein echter Fehlschlag wird nicht verschluckt" \
  || bad "3: Rueckgabewert 0, obwohl der Pane den Marker haette zeigen muessen"
case "$A" in
  *UNENTSCHIEDEN*) bad "3: als unentschieden gemeldet, obwohl der Pane eine gueltige Quelle war" ;;
  *) ok "3: nicht als unentschieden gemeldet" ;;
esac
[ -n "$(fehlschlagdatei "$F3")" ] \
  && ok "3: und die Fehlschlagdatei ist geschrieben" \
  || bad "3: keine Fehlschlagdatei"

# ── 4: wb-inbox adressiert nur den Server, den es bekommt ─────────────────────
echo
echo "-- 4: eine Pane-Kennung ohne ihren Server ist keine Adresse --"
tm -f /dev/null new-session -d -s "fremd-$MARKE" -x 80 -y 20 'sleep 60'
FP="$(tm list-panes -t "fremd-$MARKE" -F '#{pane_id}' | head -1)"
if [ -z "$FP" ]; then
  bad "4: Testaufbau -- kein Pane auf dem Testserver"
else
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
      "$TESTHOME/.local/bin/wb-inbox" -L "$SOCKET" finde "$FP" >/dev/null 2>&1
  [ "$?" -ne 0 ] \
    && ok "4: mit -L wird auf dem Testserver gesucht und dort nichts gefunden" \
    || bad "4: mit -L wurde trotzdem eine Sitzung gefunden -- vermutlich die falsche"
  env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" WB_TMUX_SOCKET="$SOCKET" \
      "$TESTHOME/.local/bin/wb-inbox" finde "$FP" >/dev/null 2>&1
  [ "$?" -ne 0 ] \
    && ok "4: WB_TMUX_SOCKET wirkt genauso" \
    || bad "4: WB_TMUX_SOCKET wurde uebergangen"
  AUS="$(env HOME="$TESTHOME" PATH="$SHIM:$TESTHOME/.local/bin:$PATH" \
         "$TESTHOME/.local/bin/wb-inbox" -L "$SOCKET" --pid 1 finde "$FP" 2>&1)"
  [ "$?" -ne 0 ] \
    && ok "4: der --pid-Riegel weist eine fremde Sitzung ab" \
    || bad "4: der --pid-Riegel liess etwas durch: $AUS"
fi

echo
echo "-- die echte Umgebung blieb unberuehrt --"
zustellbett_umgebung_pruefen "$F1" "$F2" "$F3"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
