#!/usr/bin/env bash
# test-zustellung-last.sh -- haelt die Zustellung unter LAST, oder nur bei
# ruhiger Maschine im Einzelfall?
#
# ANLASS (2026-08-20). Der zweite Zustellweg ist gebaut, gemergt und im
# Einsatz. Was fehlte, war der Nachweis unter Last: JEDER Zustellfehler dieser
# Sitzung ist im BETRIEB aufgefallen, nicht im Test. Diese Suite schliesst
# genau das -- und zwar fuer BEIDE Wege, denn ein Weg, der nur einzeln gemessen
# wurde, hat unter Last nichts zugesagt.
#
# Gefragt wird ueberall dasselbe, und es ist die einzige Frage, die zaehlt: ist
# der Auftrag angekommen, und stimmt das, was das Werkzeug darueber sagt? Ein
# Fehlalarm zaehlt genauso als Fehlschlag wie eine verschluckte Nachricht.
#
#   1  ZEHN Auftraege hintereinander an denselben Worker, Socket-Weg: jeder
#      angekommen, in der richtigen Reihenfolge, jeder mit eigener
#      Ergebnisdatei.
#   2  Dasselbe ueber den Tippweg, gemessen am ROHSTROM des Panes (jedes
#      gelesene Byte) statt an der Anzeige -- und mit gezaehlten Enter, damit
#      auffaellt, wenn ein Auftrag doppelt abgeschickt wird.
#   3  VIER Worker gleichzeitig, beide Wege: jeder Auftrag genau einmal, und im
#      richtigen Pane. Kein Auftrag darf beim Nachbarn landen.
#   4  Zustellung an einen Worker, der GERADE ARBEITET -- der Zustand, in dem in
#      der Nacht auf den 20.08. fuenf Panes eingefroren sind. Der Tippweg darf
#      dabei kein zweites Mal Enter tippen, und der Socket-Weg darf ein spaetes
#      Eintreffen nicht als Fehlschlag ausgeben.
#
# ISOLATION: eigener tmux-Socket mit PID im Namen, eigenes HOME, eigene
# Registry, Stellvertreter statt echter Agenten -- alles in lib-zustellbett.sh,
# einschliesslich der Regel, dass beim Aufraeumen nie ueber eine ungepruefte
# Variable geloescht wird. Keine Live-Sitzung, kein Netz, kein Modell.
#
# LAUFZEIT: rund zwei Minuten. Das ist der Preis von zwei mal zehn echten
# Zustellungen plus zwei gleichzeitigen Vierergruppen -- weniger Auftraege
# waeren kein Lasttest mehr.
set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-zustellbett.sh"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

VOR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v tmux >/dev/null 2>&1 || ueberspringen "tmux nicht im PATH"
[ -x "$VOR/pi-worker" ]         || ueberspringen "shell/pi-worker fehlt"
[ -x "$VOR/wb-inbox" ]          || ueberspringen "shell/wb-inbox fehlt"
[ -f "$(dirname "${BASH_SOURCE[0]}")/fake-claude-inbox.py" ] || ueberspringen "fake-claude-inbox.py fehlt"
[ -f "$(dirname "${BASH_SOURCE[0]}")/fake-tui.py" ]          || ueberspringen "fake-tui.py fehlt"
command -v /usr/bin/python3 >/dev/null || ueberspringen "python3 fehlt"

echo "== Zustellung unter Last: viele Auftraege, viele Worker, ein arbeitender Worker =="
zustellbett_start || ueberspringen "Testaufbau fehlgeschlagen"
trap zustellbett_ende EXIT INT TERM

ANZAHL=10

# ── 1: zehn Auftraege hintereinander, Socket-Weg ───────────────────────────────
echo
echo "-- 1: $ANZAHL Auftraege hintereinander an denselben Worker (Socket-Weg) --"
zustellbett_panes_weg
zustellbett_claude_inbox normal
W1="l1$MARKE"
gemeldet=0; pfade="$TESTHOME/pfade-1.txt"; : > "$pfade"
for i in $(seq 1 "$ANZAHL"); do
  AUS="$(pi_lauf socket "$W1" "SOCKETLAST-$i-$MARKE")"
  [ "$(zustellweg "$AUS")" = SOCKET ] && gemeldet=$((gemeldet+1))
  ergebnisdatei "$AUS" >> "$pfade"
done
[ "$gemeldet" -eq "$ANZAHL" ] \
  && ok "1: alle $ANZAHL Laeufe melden die Zustellung ueber die Inbox" \
  || bad "1: nur $gemeldet von $ANZAHL Laeufen meldeten sie"
# Angekommen ist die eine Frage, und der Stellvertreter beantwortet sie: er legt
# jede empfangene Nachricht wortgleich und nummeriert ab.
EMPF=$(zustellbett_empfang_zahl)
[ "$EMPF" -eq "$ANZAHL" ] \
  && ok "1: alle $ANZAHL Auftraege sind bei der Sitzung angekommen" \
  || bad "1: nur $EMPF von $ANZAHL Auftraegen angekommen"
reihe_ok=1
for i in $(seq 1 "$ANZAHL"); do
  grep -qF "SOCKETLAST-$i-$MARKE" "$(zustellbett_empfang_datei "$i")" 2>/dev/null || reihe_ok=0
done
[ "$reihe_ok" -eq 1 ] \
  && ok "1: und zwar in der Reihenfolge, in der sie abgeschickt wurden" \
  || bad "1: die Reihenfolge stimmt nicht -- der n-te Empfang traegt nicht den n-ten Auftrag"
EIND=$(sort -u "$pfade" | grep -c .)
[ "$EIND" -eq "$ANZAHL" ] \
  && ok "1: jeder Auftrag hat eine EIGENE Ergebnisdatei" \
  || bad "1: nur $EIND verschiedene Ergebnisdateien fuer $ANZAHL Auftraege -- zwei Auftraege teilen sich Datei UND Ankunftsmarker"
# Der Socket-Weg legt seine Nachricht in eine Zwischendatei. Nach $ANZAHL
# Auftraegen darf davon nichts uebrig sein -- sonst waechst der Ergebnisordner
# bei jedem Auftrag um eine versteckte Kopie des Auftragstexts.
UEBRIG=$(ls -1a "$TESTHOME/.pi-workers/results/$W1" 2>/dev/null | grep -c '\.inbox\.txt$' || true)
[ "${UEBRIG:-0}" -eq 0 ] \
  && ok "1: keine Zwischendatei der Inbox zurueckgeblieben" \
  || bad "1: ${UEBRIG} '.inbox.txt' im Ergebnisordner liegengeblieben"

# ── 2: zehn Auftraege hintereinander, Tippweg ─────────────────────────────────
echo
echo "-- 2: $ANZAHL Auftraege hintereinander an denselben Worker (Tippweg) --"
zustellbett_panes_weg
zustellbett_leeren "$RAWROOT"
rm -f -- "$TESTHOME/enter.log"
zustellbett_claude_tui korrekt
W2="l2$MARKE"
gemeldet=0; pfade2="$TESTHOME/pfade-2.txt"; : > "$pfade2"
for i in $(seq 1 "$ANZAHL"); do
  AUS="$(pi_lauf paste "$W2" "PASTELAST-$i-$MARKE")"
  [ "$(zustellweg "$AUS")" = PASTE ] && gemeldet=$((gemeldet+1))
  ergebnisdatei "$AUS" >> "$pfade2"
done
[ "$gemeldet" -eq "$ANZAHL" ] \
  && ok "2: alle $ANZAHL Laeufe melden eine verifizierte Submission" \
  || bad "2: nur $gemeldet von $ANZAHL Laeufen meldeten sie"
# Der Beleg kommt aus dem ROHSTROM, nicht aus der Anzeige: nur dort steht, was
# wirklich ankam -- ungekuerzt, ohne Umbruch der Oberflaeche, Byte fuer Byte.
BEFUND="$(/usr/bin/python3 - "$RAWROOT" "$MARKE" "$ANZAHL" <<'PY'
import os, re, sys
wurzel, marke, anzahl = sys.argv[1], sys.argv[2].encode(), int(sys.argv[3])
bloecke = []
for f in sorted(os.listdir(wurzel)):
    roh = open(os.path.join(wurzel, f), "rb").read()
    bloecke += re.findall(rb"\x1b\[200~(.*?)\x1b\[201~", roh, re.S)
fehlt = [i for i in range(1, anzahl + 1)
         if not any(b"PASTELAST-%d-" % i + marke in b for b in bloecke)]
reihe = [int(m.group(1)) for b in bloecke
         for m in [re.search(rb"PASTELAST-(\d+)-" + marke, b)] if m]
print("bloecke=%d fehlt=%s reihe_ok=%d"
      % (len(bloecke), ",".join(map(str, fehlt)) or "-",
         1 if reihe == list(range(1, anzahl + 1)) else 0))
PY
)"
case "$BEFUND" in
  *"fehlt=-"*) ok "2: jeder der $ANZAHL Auftraege steht wortgleich im Rohstrom des Panes" ;;
  *) bad "2: Auftraege fehlen im Rohstrom des Panes ($BEFUND)" ;;
esac
case "$BEFUND" in
  *"reihe_ok=1"*) ok "2: und in der abgeschickten Reihenfolge" ;;
  *) bad "2: die Reihenfolge im Pane stimmt nicht ($BEFUND)" ;;
esac
ENTER=$(grep -c '^ENTER' "$TESTHOME/enter.log" 2>/dev/null || true)
[ "${ENTER:-0}" -eq "$ANZAHL" ] \
  && ok "2: genau $ANZAHL Enter angekommen -- kein Auftrag doppelt abgeschickt" \
  || bad "2: ${ENTER:-0} Enter statt $ANZAHL -- es wurde nachgetippt oder eines verschluckt"
EIND2=$(sort -u "$pfade2" | grep -c .)
[ "$EIND2" -eq "$ANZAHL" ] \
  && ok "2: jeder Auftrag hat eine EIGENE Ergebnisdatei" \
  || bad "2: nur $EIND2 verschiedene Ergebnisdateien fuer $ANZAHL Auftraege"

# ── 3: vier Worker gleichzeitig ───────────────────────────────────────────────
gleichzeitig() {   # <weg> <namenspraefix> <auftragskennung>
  local weg="$1" praefix="$2" kennung="$3" k
  zustellbett_panes_weg
  for k in 1 2 3 4; do
    ( pi_lauf "$weg" "${praefix}${k}$MARKE" "$kennung-$k-$MARKE" > "$TESTHOME/par-$kennung-$k.txt" 2>&1 ) &
  done
  wait
}

echo
echo "-- 3a: vier Worker gleichzeitig (Socket-Weg) --"
zustellbett_leeren "$RECV"
zustellbett_claude_inbox normal
gleichzeitig socket "p" "GLEICHSOCK"
schlecht=0
for k in 1 2 3 4; do
  [ "$(zustellweg "$(cat "$TESTHOME/par-GLEICHSOCK-$k.txt")")" = SOCKET ] || schlecht=$((schlecht+1))
done
[ "$schlecht" -eq 0 ] \
  && ok "3a: alle vier melden die Zustellung ueber die Inbox" \
  || bad "3a: $schlecht von vier meldeten sie nicht"
schlecht=0
for k in 1 2 3 4; do
  n=$(grep -rlF "GLEICHSOCK-$k-$MARKE" "$RECV" 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -eq 1 ] || { schlecht=$((schlecht+1)); bad "3a: Auftrag $k kam ${n}-mal an (erwartet: genau einmal)"; }
done
[ "$schlecht" -eq 0 ] && ok "3a: jeder der vier Auftraege kam genau einmal an"

echo
echo "-- 3b: vier Worker gleichzeitig (Tippweg) --"
zustellbett_leeren "$RAWROOT"
zustellbett_claude_tui korrekt
gleichzeitig paste "q" "GLEICHPASTE"
schlecht=0
for k in 1 2 3 4; do
  [ "$(zustellweg "$(cat "$TESTHOME/par-GLEICHPASTE-$k.txt")")" = PASTE ] || schlecht=$((schlecht+1))
done
[ "$schlecht" -eq 0 ] \
  && ok "3b: alle vier melden eine verifizierte Submission" \
  || bad "3b: $schlecht von vier meldeten sie nicht"
# Die haerteste Frage bei Gleichzeitigkeit: landet ein Auftrag im Pane des
# NACHBARN? Ein Rohstrom je Pane beantwortet das eindeutig.
BEFUND="$(/usr/bin/python3 - "$RAWROOT" "$MARKE" <<'PY'
import os, re, sys
wurzel, marke = sys.argv[1], sys.argv[2].encode()
je_datei = {}
for f in sorted(os.listdir(wurzel)):
    roh = open(os.path.join(wurzel, f), "rb").read()
    je_datei[f] = re.findall(rb"\x1b\[200~(.*?)\x1b\[201~", roh, re.S)
schlecht = ["%d:%d" % (k, len([f for f, bs in je_datei.items()
                               if any(b"GLEICHPASTE-%d-" % k + marke in b for b in bs)]))
            for k in range(1, 5)
            if len([f for f, bs in je_datei.items()
                    if any(b"GLEICHPASTE-%d-" % k + marke in b for b in bs)]) != 1]
mehrfach = [f for f, bs in je_datei.items() if len(bs) > 1]
print("schlecht=%s mehrfach=%d" % (",".join(schlecht) or "-", len(mehrfach)))
PY
)"
case "$BEFUND" in
  *"schlecht=-"*) ok "3b: jeder Auftrag steht in genau EINEM Pane" ;;
  *) bad "3b: ein Auftrag steht in keinem oder in mehreren Panes ($BEFUND)" ;;
esac
case "$BEFUND" in
  *"mehrfach=0"*) ok "3b: und kein Pane hat mehr als einen Auftrag bekommen" ;;
  *) bad "3b: ein Pane hat mehr als einen Auftrag bekommen ($BEFUND)" ;;
esac

# ── 4: Zustellung an einen Worker, der GERADE ARBEITET ────────────────────────
echo
echo "-- 4a: zweiter Auftrag, waehrend der Worker arbeitet (Tippweg) --"
zustellbett_panes_weg
zustellbett_leeren "$RAWROOT"
rm -f -- "$TESTHOME/enter.log"
zustellbett_claude_tui langsam 15
W4="l4$MARKE"
A1="$(pi_lauf paste "$W4" "ARBEITET-EINS-$MARKE")"
A2="$(pi_lauf paste "$W4" "ARBEITET-ZWEI-$MARKE")"
[ "$(zustellweg "$A1")" = PASTE ] \
  && ok "4a: der erste Auftrag ist belegt abgeschickt" \
  || bad "4a: schon der erste Auftrag scheiterte"
[ "$(zustellweg "$A2")" = PASTE ] \
  && ok "4a: auch der zweite, obwohl der Pane gerade arbeitete" \
  || bad "4a: der zweite Auftrag an den arbeitenden Pane scheiterte: $(printf '%s' "$A2" | grep -m1 FEHLER)"
ENTER=$(grep -c '^ENTER' "$TESTHOME/enter.log" 2>/dev/null || true)
[ "${ENTER:-0}" -eq 2 ] \
  && ok "4a: genau zwei Enter -- in einen arbeitenden Pane wird nicht nachgetippt" \
  || bad "4a: ${ENTER:-0} Enter statt 2 -- es wurde in eine laufende Arbeit hineingetippt"
BEIDE="$(/usr/bin/python3 - "$RAWROOT" "$MARKE" <<'PY'
import os, re, sys
wurzel, marke = sys.argv[1], sys.argv[2].encode()
bloecke = []
for f in sorted(os.listdir(wurzel)):
    roh = open(os.path.join(wurzel, f), "rb").read()
    bloecke += re.findall(rb"\x1b\[200~(.*?)\x1b\[201~", roh, re.S)
eins = sum(1 for b in bloecke if b"ARBEITET-EINS-" + marke in b)
zwei = sum(1 for b in bloecke if b"ARBEITET-ZWEI-" + marke in b)
misch = sum(1 for b in bloecke if b"ARBEITET-EINS-" + marke in b
            and b"ARBEITET-ZWEI-" + marke in b)
print("eins=%d zwei=%d misch=%d" % (eins, zwei, misch))
PY
)"
[ "$BEIDE" = "eins=1 zwei=1 misch=0" ] \
  && ok "4a: beide Auftraege kamen wortgleich und GETRENNT an" \
  || bad "4a: die beiden Auftraege kamen nicht sauber getrennt an ($BEIDE)"

echo
echo "-- 4b: Sitzung meldet 'busy', die Nachricht erscheint erst spaeter (Socket-Weg) --"
zustellbett_panes_weg
zustellbett_leeren "$RECV"
# Die Sitzung steckt mitten in einem Zug: die Inbox stellt erst an der
# Turn-Grenze zu. 12 s sind mit Absicht gewaehlt -- laenger als die 10 s, die
# der Tippweg als Beleg-Frist hat, und kuerzer als die 60 s, die der Socket-Weg
# genau fuer diesen Fall bekommt. Die Ankunft muss am Ende BELEGT sein und
# nicht bloss behauptet; mit der kuerzeren Frist waere sie es nicht.
zustellbett_claude_inbox normal busy 12
W5="l5$MARKE"
A5="$(pi_lauf socket "$W5" "BESCHAEFTIGT-$MARKE")"
[ "$(zustellweg "$A5")" = SOCKET ] \
  && ok "4b: die spaete Zustellung an eine beschaeftigte Sitzung wird belegt, nicht als Fehlschlag ausgegeben" \
  || bad "4b: kein Erfolg gemeldet: $(printf '%s' "$A5" | grep -m1 -E 'FEHLER|steht noch aus')"
grep -rqF "BESCHAEFTIGT-$MARKE" "$RECV" 2>/dev/null \
  && ok "4b: und sie ist wirklich angekommen" \
  || bad "4b: der Auftrag ist bei der Sitzung nie angekommen"

# ── die echte Umgebung blieb unberuehrt ───────────────────────────────────────
echo
echo "-- die echte Umgebung blieb unberuehrt --"
zustellbett_umgebung_pruefen "$W1" "$W2" "$W4" "$W5" \
  "p1$MARKE" "p2$MARKE" "p3$MARKE" "p4$MARKE" \
  "q1$MARKE" "q2$MARKE" "q3$MARKE" "q4$MARKE"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
