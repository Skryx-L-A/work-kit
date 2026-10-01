#!/usr/bin/env bash
# test-zustellung-grenzfaelle.sh -- die Raender des Zustellwegs, und die Faelle,
# die SCHEITERN muessen.
#
# ANLASS (2026-08-20, Stresstest der Zustellung). Der Auftragstext traegt im
# Betrieb Pfade, Befehle und Fehlermeldungen; er ist mal drei Woerter lang und
# mal drei Absaetze; und der Empfaenger ist mal wach, mal beschaeftigt, mal
# taub. Geprueft wird hier immer dieselbe Frage -- ist der Auftrag angekommen,
# und stimmt, was das Werkzeug darueber sagt --, aber an den Raendern, wo eine
# Zusage entweder haelt oder still bricht.
#
#   1  SONDERZEICHEN kommen WORTGLEICH an, auf beiden Wegen: Backtick,
#      Dollarzeichen, Anfuehrungszeichen, Umlaute, Tabulator, ein Pfad mit
#      Leerzeichen, eine Fehlermeldung mit Pfeilen. Gemessen am Rohstrom des
#      Panes bzw. an der empfangenen Nachricht, nicht an der Anzeige.
#   2  Ein sehr KURZER Auftrag kommt an wie jeder andere.
#   3  Ein sehr LANGER Auftrag wandert ueber der Schwelle in eine Datei, und
#      DIESE Datei traegt ihn wortgleich -- sonst waere der Zeiger wertlos.
#   4  Ein TAUBER Pane (keine Taste wirkt mehr, Prozess lebt) ist ein lauter
#      Fehlschlag und hinterlaesst keinen Platzhalter, der spaeter wie ein
#      arbeitender Worker aussieht.
#   5  Eine taube SITZUNG (nimmt die Nachricht an und verschluckt sie) ebenso.
#      Das ist derselbe Schaden auf dem anderen Weg.
#   6  Zustellungen, die scheitern MUESSEN, scheitern hoerbar: toter Socket,
#      fremder Prozess am Socket, kein Registereintrag, toter tmux-Server.
#
# ISOLATION und LOESCH-SICHERUNG: siehe lib-zustellbett.sh.
# LAUFZEIT: rund zwei Minuten, davon eine Minute allein fuer Fall 5 -- die
# 60-s-Frist des Socket-Wegs muss dort wirklich ablaufen, sonst misst der Test
# den Fehlschlag nicht, sondern nur die Ungeduld.
set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-zustellbett.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOR="$(cd "$HIER/.." && pwd)"
SONDER="$HIER/fixtures/zustellung-sonderzeichen.txt"
command -v tmux >/dev/null 2>&1 || ueberspringen "tmux nicht im PATH"
[ -x "$VOR/pi-worker" ]                 || ueberspringen "shell/pi-worker fehlt"
[ -x "$VOR/wb-inbox" ]                  || ueberspringen "shell/wb-inbox fehlt"
[ -f "$HIER/fake-claude-inbox.py" ]     || ueberspringen "fake-claude-inbox.py fehlt"
[ -f "$HIER/fake-tui.py" ]              || ueberspringen "fake-tui.py fehlt"
[ -f "$SONDER" ]                        || ueberspringen "fixtures/zustellung-sonderzeichen.txt fehlt"
command -v /usr/bin/python3 >/dev/null  || ueberspringen "python3 fehlt"

echo "== Zustellung an den Raendern: Sonderzeichen, Laenge, taube Empfaenger, Gegenbeweise =="
zustellbett_start || ueberspringen "Testaufbau fehlgeschlagen"
trap zustellbett_ende EXIT INT TERM

SONDERTEXT="$(cat "$SONDER")"

# ── 1a: Sonderzeichen ueber den Tippweg ───────────────────────────────────────
echo
echo "-- 1a: Sonderzeichen kommen wortgleich im Pane an (Tippweg) --"
zustellbett_panes_weg
zustellbett_leeren "$RAWROOT"
zustellbett_claude_tui korrekt
G1="g1$MARKE"
A="$(pi_lauf paste "$G1" "$SONDERTEXT")"
[ "$(zustellweg "$A")" = PASTE ] \
  && ok "1a: die Zustellung meldet Erfolg" \
  || bad "1a: die Zustellung scheiterte: $(printf '%s' "$A" | grep -m1 FEHLER)"
BEFUND="$(/usr/bin/python3 - "$RAWROOT" "$SONDER" <<'PY'
import os, re, sys
wurzel, erwartet = sys.argv[1], open(sys.argv[2], "rb").read().rstrip(b"\n")
bloecke = []
for f in sorted(os.listdir(wurzel)):
    roh = open(os.path.join(wurzel, f), "rb").read()
    bloecke += re.findall(rb"\x1b\[200~(.*?)\x1b\[201~", roh, re.S)
# tmux schickt beim Einfuegen ein CR fuer jedes LF -- das ist die
# Terminal-Konvention (Zeilenende = Wagenruecklauf), keine Verfaelschung: jede
# TUI im Klammer-Einfuege-Modus liest es als Zeilenumbruch zurueck. Genau diese
# eine Ersetzung wird deshalb rueckgaengig gemacht, sonst nichts.
treffer = any(erwartet in b.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
              for b in bloecke)
klammern = len(bloecke)
print("wortgleich=%d bloecke=%d" % (1 if treffer else 0, klammern))
PY
)"
case "$BEFUND" in
  *"wortgleich=1"*) ok "1a: der Auftragstext steht Byte fuer Byte im Rohstrom des Panes" ;;
  *) bad "1a: der Auftragstext kam NICHT wortgleich an ($BEFUND)" ;;
esac
case "$BEFUND" in
  *"bloecke=1"*) ok "1a: und zwar als EIN Klammer-Einfuegen, nicht in Stuecken" ;;
  *) bad "1a: der Text kam nicht als ein einziger Einfuege-Block an ($BEFUND)" ;;
esac

# ── 1b: dieselben Zeichen ueber den Socket-Weg ────────────────────────────────
echo
echo "-- 1b: dieselben Zeichen ueber die Sitzungs-Inbox --"
zustellbett_panes_weg
zustellbett_leeren "$RECV"
zustellbett_claude_inbox normal
G2="g2$MARKE"
A="$(pi_lauf socket "$G2" "$SONDERTEXT")"
[ "$(zustellweg "$A")" = SOCKET ] \
  && ok "1b: die Zustellung meldet Erfolg" \
  || bad "1b: die Zustellung scheiterte: $(printf '%s' "$A" | grep -m1 FEHLER)"
EMPFANG="$(zustellbett_empfang_datei 1)"
if [ -z "$EMPFANG" ]; then
  bad "1b: es kam gar keine Nachricht an"
else
  /usr/bin/python3 - "$EMPFANG" "$SONDER" <<'PY' && ok "1b: die Nachricht traegt den Auftragstext Byte fuer Byte, ohne jede Ersetzung" || bad "1b: der Auftragstext kam nicht wortgleich an"
import sys
got = open(sys.argv[1], "rb").read()
erwartet = open(sys.argv[2], "rb").read().rstrip(b"\n")
sys.exit(0 if erwartet in got else 1)
PY
fi

# ── 2: ein sehr kurzer Auftrag ────────────────────────────────────────────────
echo
echo "-- 2: ein sehr kurzer Auftrag --"
zustellbett_panes_weg
zustellbett_leeren "$RECV"
zustellbett_claude_inbox normal
G3="g3$MARKE"
A="$(pi_lauf socket "$G3" "x$MARKE")"
[ "$(zustellweg "$A")" = SOCKET ] \
  && ok "2: auch ein Auftrag aus einem Wort wird zugestellt und belegt" \
  || bad "2: der kurze Auftrag scheiterte: $(printf '%s' "$A" | grep -m1 FEHLER)"
grep -rqF "x$MARKE" "$RECV" 2>/dev/null \
  && ok "2: und er ist angekommen" \
  || bad "2: der kurze Auftrag kam nie an"
case "$A" in
  *"Zeichen lang"*) bad "2: ein kurzer Auftrag wurde unnoetig in eine Datei ausgelagert" ;;
  *) ok "2: er bleibt im Text der Nachricht, ohne Umweg ueber eine Datei" ;;
esac

# ── 3: ein sehr langer Auftrag ────────────────────────────────────────────────
echo
echo "-- 3: ein sehr langer Auftrag wandert in eine Datei, und die Datei stimmt --"
zustellbett_panes_weg
zustellbett_leeren "$RAWROOT"
zustellbett_claude_tui korrekt
LANGDATEI="$TESTHOME/lang.txt"
/usr/bin/python3 - "$SONDER" "$LANGDATEI" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read().rstrip("\n")
open(sys.argv[2], "w", encoding="utf-8").write((t + "\n") * 8)
PY
LANGTEXT="$(cat "$LANGDATEI")"
G4="g4$MARKE"
A="$(pi_lauf paste "$G4" "$LANGTEXT")"
[ "$(zustellweg "$A")" = PASTE ] \
  && ok "3: die Zustellung meldet Erfolg" \
  || bad "3: die Zustellung scheiterte: $(printf '%s' "$A" | grep -m1 FEHLER)"
ZEIGER="$(printf '%s\n' "$A" | sed -n 's/.*Zeiger darauf (\([^)]*\)).*/\1/p' | tail -1)"
if [ -z "$ZEIGER" ]; then
  bad "3: ueber der Schwelle wurde KEIN Dateizeiger benutzt -- der lange Text ging als ein Block in den Pane"
else
  ok "3: ueber der Schwelle steht im Pane nur ein Zeiger auf eine Datei"
  /usr/bin/python3 - "$ZEIGER" "$LANGDATEI" <<'PY' && ok "3: und diese Datei traegt den Auftrag wortgleich" || bad "3: die Zeigerdatei weicht vom Auftragstext ab"
import sys
a = open(sys.argv[1], "rb").read()
b = open(sys.argv[2], "rb").read().rstrip(b"\n")
sys.exit(0 if a == b else 1)
PY
  BEFUND="$(/usr/bin/python3 - "$RAWROOT" "$ZEIGER" <<'PY'
import os, re, sys
wurzel, zeiger = sys.argv[1], sys.argv[2].encode()
bloecke = []
for f in sorted(os.listdir(wurzel)):
    roh = open(os.path.join(wurzel, f), "rb").read()
    bloecke += re.findall(rb"\x1b\[200~(.*?)\x1b\[201~", roh, re.S)
laenge = max([len(b) for b in bloecke] or [0])
print("zeiger_im_pane=%d groesster_block=%d"
      % (1 if any(zeiger in b for b in bloecke) else 0, laenge))
PY
)"
  case "$BEFUND" in
    *"zeiger_im_pane=1"*) ok "3: der Pane bekommt wirklich den Zeiger, nicht den ganzen Text" ;;
    *) bad "3: der Zeiger steht nicht im Pane ($BEFUND)" ;;
  esac
fi

# ── 4: ein tauber Pane (Tippweg) ──────────────────────────────────────────────
echo
echo "-- 4: ein Pane, der keine Taste mehr annimmt (Tippweg) --"
zustellbett_panes_weg
zustellbett_claude_tui taub
G5="g5$MARKE"
A="$(pi_lauf paste "$G5" "TAUB-PASTE-$MARKE")"; RC=$?
[ "$RC" -ne 0 ] \
  && ok "4: Exit-Code ungleich 0 ($RC)" \
  || bad "4: Exit-Code 0, obwohl der Pane nichts angenommen hat"
[ "$(zustellweg "$A")" = FEHLSCHLAG ] \
  && ok "4: kein Wort von Erfolg" \
  || bad "4: es wird Erfolg behauptet: $(printf '%s' "$A" | tail -2)"
[ "$(zustellbett_platzhalter "$G5")" = weg ] \
  && ok "4: kein Platzhalter zurueckgeblieben" \
  || bad "4: '.laufend.md' steht noch da -- der Fehlschlag sieht spaeter wie ein arbeitender Worker aus"
RESPFAD="$(sed -n 's/^- Erwartete Ergebnisdatei: \([^ ]*\).*/\1/p' \
           "$TESTHOME/.pi-workers/results/$G5"/*.zustellung-fehlgeschlagen.md 2>/dev/null | tail -1)"
if [ -z "$RESPFAD" ]; then
  bad "4: es wurde keine Fehlschlagdatei mit erwartetem Ergebnispfad geschrieben"
else
  [ -e "$RESPFAD" ] \
    && bad "4: der Fehlschlag liegt unter dem ERGEBNISPFAD ($RESPFAD)" \
    || ok "4: der Ergebnispfad ist frei geblieben, der Fehlschlag liegt woanders"
fi

# ── 5: eine taube Sitzung (Socket-Weg) ────────────────────────────────────────
echo
echo "-- 5: eine Sitzung, die die Nachricht annimmt und verschluckt (Socket-Weg) --"
zustellbett_panes_weg
zustellbett_leeren "$RECV"
zustellbett_claude_inbox taub
G6="g6$MARKE"
A="$(pi_lauf socket "$G6" "TAUB-SOCKET-$MARKE")"; RC=$?
[ "$RC" -ne 0 ] \
  && ok "5: Exit-Code ungleich 0 ($RC)" \
  || bad "5: Exit-Code 0, obwohl die Sitzung den Auftrag verschluckt hat"
case "$A" in
  *"Geschrieben heisst nicht angekommen"*) ok "5: die Meldung sagt genau, woran es liegt" ;;
  *) bad "5: die erwartete Meldung fehlt: $(printf '%s' "$A" | tail -2)" ;;
esac
[ "$(zustellbett_platzhalter "$G6")" = weg ] \
  && ok "5: kein Platzhalter zurueckgeblieben" \
  || bad "5: '.laufend.md' steht noch da"
# Die Gegenprobe zur Gegenprobe: die Nachricht IST am Socket angekommen. Der
# Fehlschlag betrifft also wirklich das Verschlucken und nicht das Senden --
# sonst pruefte dieser Fall bloss noch einmal Fall 6.
[ "$(zustellbett_empfang_zahl)" -ge 1 ] \
  && ok "5: die Nachricht wurde am Socket sehr wohl entgegengenommen -- der Fehlschlag trifft das Verschlucken, nicht das Senden" \
  || bad "5: die Nachricht kam gar nicht erst am Socket an -- dieser Fall misst etwas anderes als gedacht"

# ── 6: Zustellungen, die scheitern MUESSEN ────────────────────────────────────
echo
echo "-- 6a: der Registereintrag zeigt auf einen Socket, an dem niemand lauscht --"
zustellbett_panes_weg
zustellbett_claude_inbox totersocket
G7="g7$MARKE"
A="$(pi_lauf socket "$G7" "TOT-$MARKE")"; RC=$?
[ "$RC" -ne 0 ] && ok "6a: Exit-Code ungleich 0 ($RC)" || bad "6a: Exit-Code 0"
case "$A" in
  *"nicht erreichbar"*) ok "6a: wb-inbox nennt den unerreichbaren Socket" ;;
  *) bad "6a: der Grund wird nicht genannt: $(printf '%s' "$A" | tail -2)" ;;
esac
case "$A" in
  *"verbietet den Rueckfall auf das Tippen"*) ok "6a: und es wurde NICHT ersatzweise getippt" ;;
  *) bad "6a: es bleibt offen, ob ersatzweise getippt wurde" ;;
esac

echo
echo "-- 6b: am Socket haengt ein ANDERER Prozess als der eingetragene --"
zustellbett_panes_weg
zustellbett_claude_inbox fremde-pid
G8="g8$MARKE"
A="$(pi_lauf socket "$G8" "FREMD-$MARKE")"; RC=$?
[ "$RC" -ne 0 ] && ok "6b: Exit-Code ungleich 0 ($RC)" || bad "6b: Exit-Code 0"
case "$A" in
  *"haengt Prozess"*) ok "6b: die Gegenstelle wird gemessen und die Abweichung benannt" ;;
  *) bad "6b: die Verwechslung faellt nicht auf: $(printf '%s' "$A" | tail -2)" ;;
esac

echo
echo "-- 6c: gar kein Registereintrag --"
zustellbett_panes_weg
zustellbett_claude_inbox kein-eintrag
G9="g9$MARKE"
A="$(pi_lauf socket "$G9" "OHNE-$MARKE")"; RC=$?
[ "$RC" -ne 0 ] && ok "6c: Exit-Code ungleich 0 ($RC)" || bad "6c: Exit-Code 0"
case "$A" in
  *"keine lebende Claude-Sitzung eingetragen"*) ok "6c: die Meldung nennt, was fehlt" ;;
  *) bad "6c: die erwartete Meldung fehlt: $(printf '%s' "$A" | tail -2)" ;;
esac
[ "$(zustellbett_platzhalter "$G9")" = weg ] \
  && ok "6c: kein Platzhalter zurueckgeblieben" \
  || bad "6c: '.laufend.md' steht noch da"

# ── 6d: der tmux-Server ist weg (ganz zuletzt, er nimmt das Testbett mit) ──────
echo
echo "-- 6d: die Sitzung ist geschlossen, es gibt gar keinen Pane mehr --"
NAMEN_VOR_ENDE=("$G1" "$G2" "$G3" "$G4" "$G5" "$G6" "$G7" "$G8" "$G9")
zustellbett_kill_ohne_reste
sleep 1
G10="ga$MARKE"
A="$(pi_lauf socket "$G10" "SERVERWEG-$MARKE")"; RC=$?
[ "$RC" -ne 0 ] \
  && ok "6d: Exit-Code ungleich 0 ($RC)" \
  || bad "6d: Exit-Code 0, obwohl es keinen tmux-Server mehr gibt"
[ "$(zustellweg "$A")" = FEHLSCHLAG ] \
  && ok "6d: kein Wort von Erfolg" \
  || bad "6d: es wird Erfolg behauptet, ohne dass ein Pane existiert"
[ "$(zustellbett_platzhalter "$G10")" = weg ] \
  && ok "6d: kein Platzhalter zurueckgeblieben" \
  || bad "6d: '.laufend.md' steht noch da"

# ── die echte Umgebung blieb unberuehrt ───────────────────────────────────────
echo
echo "-- die echte Umgebung blieb unberuehrt --"
zustellbett_umgebung_pruefen "${NAMEN_VOR_ENDE[@]}" "$G10"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
