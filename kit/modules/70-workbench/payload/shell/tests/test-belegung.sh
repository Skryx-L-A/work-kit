#!/usr/bin/env bash
# test-belegung.sh -- die Zusagen des Belegungsbuchs (shell/wb-belegung).
#
# ANLASS: Am 10./11.08. ist die Maschine zweimal in zwei Stunden mit derselben
# Signatur stehengeblieben (`completeMemory() prepare count underflow
# @IOGPUMemory.cpp:550`, MLX, 48 Threads). Das ist ein Treiberfehler und kein
# Speichermangel -- eine Verteilung schafft ihn nicht ab. Beide Male stand aber
# derselbe Zustand am Anfang: zwei grosse GPU-Nutzer gleichzeitig. Gemessen wird
# hier also, ob das Buch genau diesen Zustand verhindert, nicht ob es Paniken
# verhindert.
#
# DIE ZUSAGEN, die hier wirklich hergestellt und gemessen werden:
#   1  Eine Belegung sperrt eine zweite, die nicht mehr danebenpasst -- und die
#      Absage nennt WER haelt und SEIT WANN, damit der Frager den anderen
#      ansprechen kann statt blind zu warten.
#   2  Eine Belegung, deren Pane nicht mehr lebt, verfaellt. Das ist das HARTE
#      Kriterium; eine vergessene Belegung sperrt die Maschine nie dauerhaft.
#   3  Eine abgelaufene Frist raeumt einen LAUFENDEN Lauf NICHT ab (Nachtrag vom
#      11.08.): bei lebendem Pane wird die Belegung ueberfaellig, bleibt im Buch
#      und zaehlt weiter. Ohne messbaren Pane verfaellt sie nach Frist + Karenz --
#      sonst koennte niemand sie je loswerden.
#   4  Zwei gleichzeitige Anfragen fuehren nicht zu zwei Belegungen, die zusammen
#      zu gross sind.
#   5  Belegt wird die SPITZE, nicht das Gewicht: dieselben Gewichte mit mehr
#      gleichzeitigen Anfragen werden abgelehnt. Genau in dieser Luecke ist die
#      Maschine gestorben (22 GB Gewichte standen die ganze Nacht; getoetet hat
#      der KV-Cache von sechzehn Anfragen obendrauf).
#   6  Der KV-Bedarf je Token traegt seine HERKUNFT bis in die Antwort, und ein
#      unbekanntes Modell wird nicht mit der geerbten 0,11er-Konstante gerechnet.
#   7  Der freie Speicher wird nicht aus einer einzigen Abtastung genommen: ein
#      einzelnes Tal (MLX gibt seine Puffer verzoegert zurueck) darf nicht als
#      Speichermangel durchgehen -- und die Antwort sagt, wie gemessen wurde.
#   8  Ohne Messung wird ABGELEHNT. Faellt `check-resources` aus, ist die Antwort
#      Nein mit dem Grund im Klartext, und `--ohne-messung` entscheidet dann
#      ausdruecklich allein nach den offenen Belegungen. Und nichts haengt: eine
#      ehrliche Antwort in Sekunden, nicht Stillstand.
#   9  Zwei Belegungen im LADEFENSTER passen zusammen in die Maschine, oder die
#      zweite wird abgelehnt -- und die Reserve bleibt auch dann stehen, wenn der
#      freie Speicher die Grenze setzt.
#  10  Jede unsinnige Zahl wird abgewiesen statt gebucht.
#
# Die Zusagen 8 bis 10 sind am 11.08. aus einem unabhaengigen Pruefdurchgang
# entstanden, der vier Wege zu einem FALSCHEN JA gefunden hat.
#
# ISOLATION: eigener tmux-Socket mit PID im Namen, eigenes HOME (`mktemp -d`),
# eine eigene Wegwerf-Fassung von `check-resources` (ueber WB_BELEGUNG_CHECK).
# Die laufende Sitzung, Fenster des Nutzers, das echte ~/.local/state und der
# echte Speicher der Maschine werden nicht angefasst. Kein Modell wird geladen,
# kein fremder Prozess beendet.
#
# Die Panes, die hier Halter spielen, sind `cat` und keine Shell: was in sie
# hineingeschrieben wuerde, darf nie als Kommando laufen.
unset TMUX TMUX_PANE
set -uo pipefail

MARK="${LIVE_MARKER:+-$LIVE_MARKER}"
SOCKET="wbtest-belegung$MARK-$$"
SESS="wb-belegungstest$MARK-$$"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${WB_BELEGUNG:-$REPO/wb-belegung}"
echo "Geprueft: $TOOL"

FAKEHOME="$(mktemp -d)"
WORK="$(mktemp -d)"
mkdir -p "$FAKEHOME/.local/bin"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

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

# --- Die Wegwerf-Fassung von check-resources --------------------------------
# Ein Test, der den ECHTEN freien Speicher der Maschine liest, ist kein Test,
# sondern eine Wettervorhersage: er wird gruen oder rot, je nachdem was gerade
# laeuft (regeln/tests-und-eingriffe.md, "ein Test STELLT seine Voraussetzung
# HER"). Diese Fassung antwortet im Format des echten Werkzeugs und liest ihre
# Zahl aus einer Datei, die der Test setzt.
STELLVERTRETER="$WORK/check-resources"
cat > "$STELLVERTRETER" <<'EOF'
#!/bin/sh
# Freier Speicher in MiB: entweder fest aus frei.txt, oder -- wenn folge.txt
# existiert -- der naechste Wert einer Folge, damit sich ein einzelnes Tal
# nachstellen laesst. ollama.json/ollama-note.txt sind ABSICHTLICH nur da, wenn
# ein Test sie setzt: fehlen sie, fehlt im Ausgabe-JSON auch 'ollama_loaded'
# komplett -- das ist die Fassung von check-resources OHNE Ollama-Anbindung, und
# wb-belegung muss sie wie bisher behandeln (Nachtrag 16.08.: keine Fassung darf
# haerter werden als sie es vor diesem Umbau war).
d=$(dirname "$0")
if [ -f "$d/folge.txt" ]; then
    n=$(cat "$d/zaehler.txt" 2>/dev/null || echo 0)
    n=$((n + 1)); echo "$n" > "$d/zaehler.txt"
    frei=$(sed -n "${n}p" "$d/folge.txt")
    [ -n "$frei" ] || frei=$(tail -1 "$d/folge.txt")
else
    frei=$(cat "$d/frei.txt" 2>/dev/null || echo 36000)
fi
printf '{"vram":{"kind":"unified","free_mib":%s,"total_mib":49152},' "$frei"
printf '"ram":{"free_mib":%s,"total_mib":49152}' "$frei"
if [ -f "$d/ollama.json" ]; then
    printf ',"ollama_loaded":%s,"ollama_loaded_note":"%s"' \
        "$(cat "$d/ollama.json")" "$(cat "$d/ollama-note.txt" 2>/dev/null || echo "")"
fi
# ollama_local ist genauso optional wie ollama.json und aus demselben Grund:
# fehlt die Datei, fehlt das Feld, und wb-belegung sieht die Antwort einer
# check-resources-Fassung, die den Portbesitzer noch gar nicht kannte. Die darf
# sich weiterhin genau wie vor dem 16.08. verhalten.
if [ -f "$d/ollama-local.txt" ]; then
    printf ',"ollama_local":%s' "$(cat "$d/ollama-local.txt")"
fi
printf '}\n'
EOF
chmod +x "$STELLVERTRETER"
frei_setzen() { rm -f "$WORK/folge.txt" "$WORK/zaehler.txt"; echo "$1" > "$WORK/frei.txt"; }
folge_setzen() { rm -f "$WORK/zaehler.txt"; printf '%s\n' "$@" > "$WORK/folge.txt"; }
# <ollama_loaded-JSON-Array> [loaded_note] -- siehe Kopf des Stellvertreters oben.
ollama_setzen() { printf '%s' "$1" > "$WORK/ollama.json"; printf '%s' "${2:-}" > "$WORK/ollama-note.txt"; }
ollama_leeren() { rm -f "$WORK/ollama.json" "$WORK/ollama-note.txt" "$WORK/ollama-local.txt"; }
# true | false | null -- oder gar nicht aufgerufen fuer die alte Fassung.
ollama_local_setzen() { printf '%s' "$1" > "$WORK/ollama-local.txt"; }
# 30681 von 49152 MiB -- die Zahlen DIESER Maschine, also rund 18 GiB Grundlast.
# Der dritte Pruefdurchgang (11.08.) hat genau hier eine Luecke gefunden: die alte
# Fixture setzte 46000 von 49152 MiB, eine Maschine also praktisch ohne Grundlast.
# Dann liegen Grenze A und Grenze B fast aufeinander, und der schwerste Rechenfehler
# -- zwei Belegungen im Ladefenster, die zusammen nicht mehr hineinpassen -- kann in
# der Suite gar nicht auftreten. Eine Fixture ohne Grundlast bestaetigt eine Rechnung,
# die in der Wirklichkeit nicht traegt.
GRUNDLAST_FREI=30681
frei_setzen "$GRUNDLAST_FREI"

# Das ECHTE HOME, bevor es gleich ueberschrieben wird -- nur fuer die
# Isolations-Gegenprobe in Abschnitt 20 gebraucht.
HOME_ECHT="$HOME"
export HOME="$FAKEHOME"
export WB_BELEGUNG_CHECK="$STELLVERTRETER"

belegung() { "$TOOL" "$@"; }
buch() { cat "$FAKEHOME/.local/state/wb-belegung/buch.json" 2>/dev/null; }
buch_anzahl() { buch | /usr/bin/python3 -c 'import json,sys
try: print(len(json.load(sys.stdin)["belegungen"]))
except Exception: print(0)'; }
buch_summe() { buch | /usr/bin/python3 -c 'import json,sys
try: print(sum(b["gb"] for b in json.load(sys.stdin)["belegungen"]))
except Exception: print(0)'; }

# --- Testserver -------------------------------------------------------------
HOME="$FAKEHOME" tm new-session -d -s "$SESS" -n main cat \
    || { echo "tmux-Testserver liess sich nicht starten" >&2; exit 1; }
# Ein Pane, dessen Kommando endet, soll STEHEN bleiben -- sonst waere der tote
# Pane aus Zusage 2 gar nicht mehr da, um ihn als tot zu erkennen.
tm set -g remain-on-exit on

# Ein Befehl IN einem Pane dieses Testservers. Der Pane ist der Anker: tmux setzt
# seiner Shell ein $TMUX auf DIESEN Server, und wb-belegung traegt genau diesen
# Socketpfad in die Belegung ein. Aus der Test-Shell heraus gestartet haette der
# Prueflung diesen Anker nicht (regeln/tests-und-eingriffe.md).
# Danach `exec cat`: der Pane bleibt am Leben, denn er spielt den Halter.
# Der Befehl kommt als EINE Zeichenkette und wird in eine Skriptdatei geschrieben,
# statt durch zwei Anfuehrungsebenen (bash -> tmux -> sh) geschickt zu werden:
# ein Zweck wie 'lmbeta-27b 6bit laden' traegt selbst Anfuehrungszeichen, und die
# gehen auf dem Weg sonst verloren.
im_pane() {   # <fenstername> <befehl-als-eine-zeile> -> Ausgabe in $WORK/<name>.out
    local name="$1" befehl="$2"
    rm -f "$WORK/$name.out" "$WORK/$name.done" "$WORK/$name.rc"
    cat > "$WORK/$name.sh" <<EOF
export HOME="$FAKEHOME"
export WB_BELEGUNG_CHECK="$STELLVERTRETER"
$befehl > "$WORK/$name.out" 2>&1
echo \$? > "$WORK/$name.rc"
touch "$WORK/$name.done"
exec cat
EOF
    tm new-window -d -t "=$SESS" -n "$name" "sh $WORK/$name.sh"
}
pane_von() { tm list-panes -a -F '#{window_name} #{pane_id}' | awk -v n="$1" '$1==n{print $2}'; }
rc_von() { cat "$WORK/$1.rc" 2>/dev/null; }

echo
echo "== 1  Eine Belegung sperrt eine zweite, die nicht mehr passt =="

# 29,96 GiB frei, Reserve 6 -> Grenze A laesst 23,96 GiB zu.
im_pane erste "'$TOOL' nimm --gb 20 --zweck 'lmbeta-27b 6bit laden' --abtastungen 1 --frist 45"
warte_auf_datei "$WORK/erste.done" 20 "erste Belegung" || true
if [ "$(rc_von erste)" = "0" ]; then ok "die erste Belegung wird eingetragen"
else bad "die erste Belegung wurde nicht eingetragen (rc=$(rc_von erste)): $(head -3 "$WORK/erste.out" 2>/dev/null)"; fi

# 20 belegt und noch ladend -> Grenze A ist auf 3,96 GiB zusammengeschrumpft.
im_pane zweite "'$TOOL' nimm --gb 10 --zweck 'zweites Modell' --abtastungen 1"
warte_auf_datei "$WORK/zweite.done" 20 "zweite Belegung" || true
if [ "$(rc_von zweite)" = "1" ]; then ok "die zweite, zu grosse Belegung wird abgelehnt (Exit 1)"
else bad "die zweite Belegung haette abgelehnt werden muessen (rc=$(rc_von zweite))"; fi
if [ "$(buch_anzahl)" = "1" ]; then ok "nach der Absage steht genau eine Belegung im Buch"
else bad "nach der Absage stehen $(buch_anzahl) Belegungen im Buch"; fi

if grep -q "$SESS" "$WORK/zweite.out" && grep -q "seit 0 min" "$WORK/zweite.out"; then
    ok "die Absage nennt WER haelt (Sitzung/Pane) und SEIT WANN"
else
    bad "die Absage nennt Halter oder Zeitpunkt nicht: $(tr '\n' '|' < "$WORK/zweite.out" | cut -c1-300)"
fi
if grep -q "wb-post schreiben\|Sprich den Halter an" "$WORK/zweite.out"; then
    ok "die Absage sagt, wie man den Halter anspricht"
else
    bad "die Absage verweist nicht auf den Halter"
fi

# Was noch danebenpasst, wird weiterhin erlaubt -- das Buch ist eine Verteilung,
# keine Alles-oder-nichts-Sperre.
im_pane dritte "'$TOOL' nimm --gb 3 --zweck 'kleines Modell' --abtastungen 1"
warte_auf_datei "$WORK/dritte.done" 20 "dritte Belegung" || true
if [ "$(rc_von dritte)" = "0" ] && [ "$(buch_anzahl)" = "2" ]; then
    ok "eine kleine Belegung passt weiterhin daneben"
else
    bad "die kleine Belegung wurde abgelehnt (rc=$(rc_von dritte), Buch: $(buch_anzahl))"
fi

echo
echo "== 2  Eine Belegung ohne lebenden Pane verfaellt =="

PANE_DRITTE="$(pane_von dritte)"
tm kill-window -t "=$SESS:dritte"
warte_auf_bedingung 10 "Pane $PANE_DRITTE ist fort" \
    '! tm list-panes -a -F "#{pane_id}" | grep -qx "$PANE_DRITTE"' || true
AUS="$(belegung aufraeumen 2>&1)"
if [ "$(buch_anzahl)" = "1" ] && printf '%s' "$AUS" | grep -q "verfallen"; then
    ok "die Belegung des toten Panes verfaellt und wird gemeldet"
else
    bad "die Belegung des toten Panes steht noch im Buch ($(buch_anzahl)): $AUS"
fi

# Und der Platz ist danach wirklich wieder da.
im_pane vierte "'$TOOL' darf --gb 3 --abtastungen 1"
warte_auf_datei "$WORK/vierte.done" 20 "Nachfrage nach dem Verfall" || true
if [ "$(rc_von vierte)" = "0" ]; then ok "der freigewordene Platz ist sofort wieder vergebbar"
else bad "der Platz blieb nach dem Verfall gesperrt (rc=$(rc_von vierte))"; fi

echo
echo "== 3  Eine abgelaufene Frist raeumt einen laufenden Lauf NICHT ab =="

# Frist 0: die Belegung ist im selben Augenblick ueberfaellig. Ihr Pane lebt.
im_pane frist "'$TOOL' nimm --gb 2 --zweck 'lange Leiter' --abtastungen 1 --frist 0"
warte_auf_datei "$WORK/frist.done" 20 "Belegung mit Frist 0" || true
sleep 1
AUS="$(belegung wer 2>&1)"
if printf '%s' "$AUS" | grep -q "UEBERFAELLIG"; then ok "die abgelaufene Frist wird als UEBERFAELLIG gemeldet"
else bad "die abgelaufene Frist wird nicht als ueberfaellig gemeldet: $AUS"; fi
if printf '%s' "$AUS" | grep -q "Halter fragen"; then ok "der Frager wird an den Halter verwiesen, nicht der Halter abgeraeumt"
else bad "kein Hinweis auf den Halter bei der ueberfaelligen Belegung"; fi

ANZ_VORHER="$(buch_anzahl)"
belegung aufraeumen >/dev/null 2>&1
if [ "$(buch_anzahl)" = "$ANZ_VORHER" ]; then
    ok "auch ein ausdrueckliches 'aufraeumen' laesst die ueberfaellige Belegung stehen"
else
    bad "'aufraeumen' hat die ueberfaellige Belegung mit lebendem Pane entfernt"
fi

SUMME_MIT="$(buch_summe)"
# --reserve-gb 6 AUSDRUECKLICH gesetzt (Nachtrag 27.08.2026, Vorgabe seit
# Anweisung des Nutzers auf 0, siehe Abschnitt 5) -- dieser Fall testet, ob eine
# UEBERFAELLIGE Belegung weiter gegen die Kapazitaet zaehlt, nicht die Reserve
# selbst, und braucht dafuer weiterhin eine Reserve ungleich Null, um an die
# knappe Grenze zu kommen, die diese Zusage ueberhaupt zeigt.
im_pane gegen "'$TOOL' darf --gb 3 --reserve-gb 6 --abtastungen 1"
warte_auf_datei "$WORK/gegen.done" 20 "Anfrage gegen die ueberfaellige Belegung" || true
if [ "$(rc_von gegen)" = "1" ]; then
    ok "die ueberfaellige Belegung zaehlt weiter gegen die Kapazitaet (Summe $SUMME_MIT GiB)"
else
    bad "die ueberfaellige Belegung wurde bei der Rechnung uebergangen (rc=$(rc_von gegen))"
fi

# Verlaengern ist die Antwort des Halters auf die Frage "brauchst Du das noch?".
KENNUNG="$(belegung wer --json | /usr/bin/python3 -c 'import json,sys
for b in json.load(sys.stdin)["belegungen"]:
    if b.get("zweck") == "lange Leiter": print(b["id"]); break')"
belegung verlaengern "$KENNUNG" --frist 45 >/dev/null 2>&1
if ! belegung wer 2>&1 | grep -q "UEBERFAELLIG"; then ok "verlaengern setzt die Frist neu, die Belegung ist wieder in Ordnung"
else bad "verlaengern hat die Ueberfaelligkeit nicht aufgehoben"; fi

# Ohne messbaren Pane ist die Frist das harte Kriterium -- sonst koennte eine
# ausserhalb tmux angelegte Belegung nie mehr verschwinden.
( unset TMUX TMUX_PANE; belegung nimm --gb 1 --zweck 'ohne Pane' --abtastungen 1 \
    --frist 0 --karenz 0 >/dev/null 2>&1 )
sleep 1
AUS="$(belegung aufraeumen 2>&1)"
if printf '%s' "$AUS" | grep -q "kein Pane als Halter"; then
    ok "eine Belegung ohne Pane verfaellt nach Frist + Karenz von selbst"
else
    bad "die Belegung ohne Pane blieb stehen: $AUS"
fi

echo
echo "== 4  Zwei gleichzeitige Anfragen ergeben nie zwei zu grosse Belegungen =="

# Buch leeren, indem die Halter-Panes weggehen.
tm kill-window -t "=$SESS:erste" 2>/dev/null
tm kill-window -t "=$SESS:frist" 2>/dev/null
warte_auf_bedingung 10 "die Halter-Panes sind fort" \
    '[ "$(belegung aufraeumen >/dev/null 2>&1; buch_anzahl)" = "0" ]' || true

# Beide Panes warten auf dieselbe Startdatei und messen dann drei Sekunden lang --
# so ueberlappen sie wirklich, statt nacheinander zu laufen. Zusammen passen 40 GiB
# nicht in die 23,96 GiB, die Grenze A hergibt; genau einer darf durchkommen.
rm -f "$WORK/los"
for n in a b; do
    im_pane "renn$n" "while [ ! -f '$WORK/los' ]; do sleep 0.05; done; \
'$TOOL' nimm --gb 20 --zweck 'Wettlauf $n' --abtastungen 3 --abstand 1"
done
sleep 0.5
touch "$WORK/los"
warte_auf_datei "$WORK/renna.done" 40 "Wettlaeufer a" || true
warte_auf_datei "$WORK/rennb.done" 40 "Wettlaeufer b" || true
JA=0
[ "$(rc_von renna)" = "0" ] && JA=$((JA+1))
[ "$(rc_von rennb)" = "0" ] && JA=$((JA+1))
if [ "$JA" = "1" ]; then ok "genau einer der beiden gleichzeitigen Frager bekommt ein Ja"
else bad "$JA von 2 gleichzeitigen Fragern bekamen ein Ja (a=$(rc_von renna), b=$(rc_von rennb))"; fi
if [ "$(buch_anzahl)" = "1" ] && [ "$(buch_summe)" = "20.0" ]; then
    ok "im Buch steht genau eine Belegung, die Summe bleibt unter der Kapazitaet"
else
    bad "das Buch traegt $(buch_anzahl) Belegungen mit zusammen $(buch_summe) GiB"
fi

echo
echo "== 5  Belegt wird die Spitze, nicht das Gewicht =="

tm kill-window -t "=$SESS:renna" 2>/dev/null
tm kill-window -t "=$SESS:rennb" 2>/dev/null
warte_auf_bedingung 10 "das Buch ist leer" \
    '[ "$(belegung aufraeumen >/dev/null 2>&1; buch_anzahl)" = "0" ]' || true

# Dieselben 22 GB Gewichte wie in der Nacht des Vorfalls. Mit zwei Anfragen
# passt es, mit sechzehn nicht -- und genau diesen Unterschied haette eine
# Belegung, die nur die Gewichte nennt, nicht gesehen.
belegung darf --gewichte-gb 12 --parallel 2 --kontext 2048 --modell kat --abtastungen 1 >/dev/null 2>&1
RC_KLEIN=$?
belegung darf --gewichte-gb 12 --parallel 16 --kontext 8192 --modell kat --abtastungen 1 >/dev/null 2>&1
RC_GROSS=$?
if [ "$RC_KLEIN" = "0" ] && [ "$RC_GROSS" = "1" ]; then
    ok "gleiche Gewichte, mehr gleichzeitige Anfragen: die Spitze entscheidet"
else
    bad "die Spitze entscheidet nicht (klein=$RC_KLEIN, gross=$RC_GROSS)"
fi
AUS="$(belegung darf --gb 20 --abtastungen 1 2>&1)"
# WAR: die Reserve ist an die Notbremsen-Schwelle der Messstrecke gekoppelt
# (6144 MiB) -- stand sie niedriger, gab das Buch einen Lauf frei, den die
# Bremse anschliessend im selben Zustand abfing.
#
# 2026-08-27, ausdrueckliche des Nutzers Anweisung ("aendere die Rechnung so,
# dass sie nicht mehr aufschlaegt, was das Modell per Rechnung braucht"):
# RESERVE_GIB steht auf 0,0 -- die Buchung rechnet jetzt ohne Aufschlag, der
# Ersatz ist `wb-notbremse` (PID-Anbindung, Schwelle 512 MiB) NACH dem Start
# statt einer Reserve DAVOR. Siehe wb-belegung, RESERVE_GIB und der lange
# Nachtrag beim Kopfkommentar.
if printf '%s' "$AUS" | grep -q -- "- 0,0 Reserve"; then
    ok "die Vorgabe-Reserve steht auf 0,0 GiB -- keine Buchungs-Reserve mehr, wb-notbremse ist der Ersatz"
else
    bad "die Vorgabe-Reserve ist nicht mehr Null: $AUS"
fi
if printf '%s' "$AUS" | grep -q "selbst genannt"; then
    ok "eine selbst genannte Spitze wird als solche gekennzeichnet"
else
    bad "eine selbst genannte Spitze wird nicht gekennzeichnet"
fi
if ! belegung darf --gewichte-gb 12 --parallel 4 --abtastungen 1 >/dev/null 2>&1; then
    ok "Gewichte ohne Kontext werden abgelehnt statt geraten"
else
    bad "Gewichte ohne Kontext wurden stillschweigend gerechnet"
fi

echo
echo "== 6  Der KV-Bedarf traegt seine Herkunft bis in die Antwort =="

AUS="$(belegung darf --gewichte-gb 5 --parallel 1 --kontext 1024 --modell kat --abtastungen 1 2>&1)"
if printf '%s' "$AUS" | grep -q "GEMESSEN an 'kat'"; then ok "eine gemessene Zahl wird als gemessen ausgewiesen"
else bad "die gemessene Zahl wird nicht als solche ausgewiesen: $AUS"; fi

AUS="$(belegung darf --gewichte-gb 5 --parallel 1 --kontext 1024 --modell niegesehen --abtastungen 1 2>&1)"
if printf '%s' "$AUS" | grep -q "ANGENOMMEN"; then ok "eine geratene Zahl wird als angenommen ausgewiesen"
else bad "die geratene Zahl wird nicht gekennzeichnet: $AUS"; fi

# GEGENPROBE (Nachtrag "Namensverwechslung lmgamma-27b/MTPLX", 2026-08-21): ein
# Schluessel, der KEINEN Eintrag trifft (nicht mal lose zugeordnet), faellt auf
# den grossen Ersatzwert zurueck -- und die --json-Antwort MUSS das sagen, Feld
# UND Klartext, statt nur knapp abzulehnen und den Rateweg zu verschweigen.
AUSJ="$(belegung darf --gewichte-gb 5 --parallel 1 --kontext 1024 --modell niegesehen --abtastungen 1 --json 2>&1)"
if printf '%s' "$AUSJ" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("kv_ersatzwert") is True else 1)' 2>/dev/null; then
    ok "ein Schluessel ohne jeden Treffer setzt kv_ersatzwert=true im JSON"
else
    bad "kv_ersatzwert fehlt oder ist nicht true fuer ein voellig unbekanntes Modell: $AUSJ"
fi
if printf '%s' "$AUSJ" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("kv_ersatzwert_hinweis") else 1)' 2>/dev/null; then
    ok "kv_ersatzwert traegt einen Klartext-Hinweis, nicht nur das nackte Feld"
else
    bad "kv_ersatzwert_hinweis fehlt: $AUSJ"
fi
# Die Gegenprobe zur Gegenprobe: ein EXAKT gemessener Treffer ('kat') ist kein
# Raten und darf das Feld nicht setzen.
AUSJ_KAT="$(belegung darf --gewichte-gb 5 --parallel 1 --kontext 1024 --modell kat --abtastungen 1 --json 2>&1)"
if printf '%s' "$AUSJ_KAT" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if not d.get("kv_ersatzwert") else 1)' 2>/dev/null; then
    ok "ein exakt gemessener Treffer setzt kv_ersatzwert NICHT"
else
    bad "kv_ersatzwert steht faelschlich auch bei einem exakt gemessenen Treffer: $AUSJ_KAT"
fi
# Der Kern des Nachtrags: ein unbekanntes Modell darf NICHT mit der geerbten
# 0,11er-Konstante gerechnet werden -- an KAT waren es 1,05, fast das Zehnfache.
# Sicherheitsfaktor seit 19.08.2026 (Pruefer-Nachtrag, Vorgabe des Nutzers)
# 1,1 statt 1,5 -- 1,05 x 1,1 = 1,155, angezeigt gerundet 1,16.
KV="$(printf '%s' "$AUS" | sed -n 's/.*Token x \([0-9,]*\) MiB.*/\1/p' | head -1)"
if [ "$KV" = "1,16" ]; then ok "das unbekannte Modell wird mit 1,16 MiB/Token gerechnet (1,05 gemessen x 1,1), nicht mit 0,11"
else bad "das unbekannte Modell wird mit '$KV' MiB/Token gerechnet"; fi

# Wird die Suche umgangen, wenn derselbe Modellstand anders geschrieben wird? Die
# Lehre kommt aus der Sperrliste der Nachbarsitzung, die zusaetzlich gegen den
# Modellpfad und dessen letzten Bestandteil prueft -- sonst waere sie still daran
# vorbeigelaufen.
kv_wert() {   # <modellangabe> -> die gerechnete Zahl, deutsch
    belegung darf --gewichte-gb 1 --parallel 1 --kontext 1000 --modell "$1" --abtastungen 1 2>&1 \
        | sed -n 's/.*Token x \([0-9,]*\) MiB.*/\1/p' | head -1
}
if [ "$(kv_wert "KAT")" = "1,05" ] && [ "$(kv_wert " kat")" = "1,05" ]; then
    ok "Gross- und Kleinschreibung und Rand-Leerzeichen finden den Eintrag"
else
    bad "'KAT' ergab $(kv_wert "KAT"), ' kat' ergab $(kv_wert " kat")"
fi
for SCHREIBWEISE in "/opt/modelle/kat" "kat-6bit" "kat.safetensors" "kat:27b-q6_K"; do
    W="$(kv_wert "$SCHREIBWEISE")"
    if [ "$W" = "1,16" ]; then
        ok "'$SCHREIBWEISE' wird zugeordnet und nie unter den Grundwert gerechnet ($W)"
    else
        bad "'$SCHREIBWEISE' ergab $W statt 1,16"
    fi
done

# Die gefaehrliche Richtung: ein Name, der faelschlich auf einen KLEINEN gemessenen
# Wert passt. Genau genannt darf 'winzig' seine 0,02 behalten -- ueber einen Pfad oder
# ein Quantisierungskuerzel zugeordnet, darf die lose Zuordnung die Zahl nur erhoehen.
belegung kv setzen winzig 0.02 --herkunft gemessen --notiz "Testfixture, kleiner Embedder" >/dev/null 2>&1
if [ "$(kv_wert "winzig")" = "0,02" ]; then
    ok "genau genannt behaelt ein kleiner gemessener Eintrag seine Zahl"
else
    bad "'winzig' ergab $(kv_wert "winzig") statt 0,02"
fi
if [ "$(kv_wert "/opt/modelle/winzig-6bit")" = "1,16" ]; then
    ok "ueber Pfad und Kuerzel zugeordnet, wird der kleine Wert NICHT uebernommen"
else
    bad "die lose Zuordnung hat die Zahl gesenkt: $(kv_wert "/opt/modelle/winzig-6bit")"
fi
# Eine LOSE Zuordnung ist kein Raten ins Blaue -- sie haengt an einem konkreten
# Eintrag ('winzig'), auch wenn der Schluessel anders geschrieben war. kv_ersatzwert
# gilt nur fuer den Fall OHNE jeden Treffer, nicht fuer diesen.
AUSJ_LOSE="$(belegung darf --gewichte-gb 1 --parallel 1 --kontext 1000 --modell "/opt/modelle/winzig-6bit" --abtastungen 1 --json 2>&1)"
if printf '%s' "$AUSJ_LOSE" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if not d.get("kv_ersatzwert") else 1)' 2>/dev/null; then
    ok "eine lose Zuordnung ueber Pfad/Kuerzel setzt kv_ersatzwert NICHT (sie fand einen Eintrag, sie riet nicht ins Blaue)"
else
    bad "kv_ersatzwert steht faelschlich auch bei einer losen Zuordnung: $AUSJ_LOSE"
fi

# Klartext in 'wer' (Nachtrag zweiter Pruefpass, 2026-08-21 abends): der
# Kommentar ueber kv_ersatzwert in cmd_nimm behauptete "sichtbar auch im
# Buch, nicht nur in der Direktantwort" -- belegungen_zeigen(), die
# Funktion, die genau das Buch im Klartext zeigt, las das Feld bis dahin
# nie. 'darf' fragt nur, 'wer' liest das BUCH -- deshalb hier 'nimm', eine
# echte Buchung.
KEN_ERSATZ="$(belegung nimm --gewichte-gb 1 --parallel 1 --kontext 1000 \
    --modell "ganz-unbekannt-fuer-wer" --zweck "wer-ersatzwert-test" --abtastungen 1 --json 2>&1 \
    | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("kennung") or "")' 2>/dev/null)"
KEN_GEMESSEN="$(belegung nimm --gewichte-gb 1 --parallel 1 --kontext 1000 \
    --modell kat --zweck "wer-gemessen-test" --abtastungen 1 --json 2>&1 \
    | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("kennung") or "")' 2>/dev/null)"
WER_TEXT="$(belegung wer 2>&1)"
if [ -n "$KEN_ERSATZ" ] && printf '%s' "$WER_TEXT" | grep -A3 "^  $KEN_ERSATZ " | grep -qF "KV-WERT GERATEN"; then
    ok "'wer' (Klartext) weist eine Buchung auf dem Ersatzwert als solche aus"
else
    bad "'wer' (Klartext) sagt nichts ueber den Ersatzwert der Buchung $KEN_ERSATZ: $WER_TEXT"
fi
if [ -n "$KEN_GEMESSEN" ] && printf '%s' "$WER_TEXT" | grep -A3 "^  $KEN_GEMESSEN " | grep -qF "KV-WERT GERATEN"; then
    bad "'wer' weist faelschlich auch eine Buchung mit getroffenem Schluessel als geraten aus"
else
    ok "eine Buchung mit getroffenem Schluessel ('kat', gemessen) bleibt in 'wer' ohne den Ersatzwert-Hinweis"
fi
belegung gib "$KEN_ERSATZ" >/dev/null 2>&1
belegung gib "$KEN_GEMESSEN" >/dev/null 2>&1

belegung kv setzen niegesehen 0.30 --herkunft gemessen --notiz "Testfixture" >/dev/null 2>&1
AUS="$(belegung darf --gewichte-gb 5 --parallel 1 --kontext 1024 --modell niegesehen --abtastungen 1 2>&1)"
if printf '%s' "$AUS" | grep -q "GEMESSEN an 'niegesehen'"; then
    ok "eine eingetragene Messung ersetzt die Annahme samt Sicherheitsfaktor"
else
    bad "die eingetragene Messung wirkt nicht: $AUS"
fi

echo
echo "== 7  Ein einzelnes Tal ist kein Speichermangel =="

# Der gemessene Fall: unmittelbar nach einer Stufe 735 MiB frei, eine Minute
# spaeter wieder 14,2 GiB. Wer im Tal misst, haelt einen Messartefakt fuer
# Speichermangel.
folge_setzen 735 14540 14540
belegung darf --gb 5 --abtastungen 1 >/dev/null 2>&1
RC_EINE=$?
folge_setzen 735 14540 14540
AUS="$(belegung darf --gb 5 --abtastungen 3 --abstand 0.1 2>&1)"
RC_DREI=$?
if [ "$RC_EINE" = "1" ] && [ "$RC_DREI" = "0" ]; then
    ok "eine einzelne Abtastung faellt auf das Tal herein, der Median nicht"
else
    bad "der Median half nicht (eine=$RC_EINE, drei=$RC_DREI)"
fi
if printf '%s' "$AUS" | grep -q "Median aus 3 Abtastungen"; then
    ok "die Antwort sagt, wie gemessen wurde"
else
    bad "die Antwort nennt das Messverfahren nicht: $AUS"
fi
folge_setzen 735 14540 14540
AUS="$(belegung darf --gb 5 --abtastungen 1 --beruhigen 1 2>&1)"
if printf '%s' "$AUS" | grep -q "Beruhigungsfrist"; then
    ok "die Beruhigungsfrist wird als solche genannt"
else
    bad "die Beruhigungsfrist taucht in der Antwort nicht auf"
fi
frei_setzen "$GRUNDLAST_FREI"

echo
echo "== 8  Ohne Messung wird abgelehnt, und nichts haengt =="

# Der schwerste Befund des dritten Pruefdurchgangs: faellt `check-resources` aus,
# sagte das Buch zu ALLEM ja -- `darf --gb 200` bekam ein Ja, waehrend 44 GiB im Buch
# standen. Der Weg dorthin ist alltaeglich: unter dem nackten launchd-PATH fehlt
# /usr/sbin, `check-resources` findet sein `sysctl` nicht und endet mit Exit 127.
STUMM="$WORK/stummes-check"
printf '#!/bin/sh\nsleep 120\n' > "$STUMM"; chmod +x "$STUMM"
belegung nimm --gb 20 --zweck 'Halter fuer die Messprobe' --abtastungen 1 >/dev/null 2>&1

START=$SECONDS
AUS="$(WB_BELEGUNG_CHECK="$STUMM" belegung darf --gb 200 --abtastungen 1 2>&1)"
RC=$?
DAUER=$((SECONDS - START))
if [ "$RC" = "1" ]; then ok "ohne Messung wird abgelehnt (Exit 1), auch bei 200 GiB"
else bad "ohne Messung kam Exit $RC statt 1 heraus"; fi
if [ "$DAUER" -lt 20 ]; then ok "ein stummes check-resources blockiert nicht (${DAUER}s)"
else bad "der Aufruf hing ${DAUER}s an einem stummen check-resources"; fi
if printf '%s' "$AUS" | grep -q "NICHT MESSBAR"; then
    ok "die fehlende Messung wird im Klartext benannt"
else
    bad "die fehlende Messung wird nicht benannt: $AUS"
fi
if printf '%s' "$AUS" | grep -q -- "--ohne-messung"; then
    ok "die Absage nennt den Schalter, mit dem man sie ausdruecklich uebergeht"
else
    bad "die Absage nennt keinen Weg daran vorbei"
fi

# Und der Schalter entscheidet dann WIRKLICH nach den offenen Belegungen -- der Satz,
# der vorher in der Ausgabe stand, ohne zu stimmen.
AUS="$(WB_BELEGUNG_CHECK="$STUMM" belegung darf --gb 200 --abtastungen 1 --ohne-messung 2>&1)"
RC=$?
if [ "$RC" = "1" ] && printf '%s' "$AUS" | grep -q "Grenze B"; then
    ok "--ohne-messung entscheidet nach Grenze B und lehnt die 200 GiB ab"
else
    bad "--ohne-messung entschied falsch (Exit $RC): $AUS"
fi
# Erwartet wird der Gesamtspeicher DIESER Maschine, nicht ein fest verdrahteter Wert
# einer bestimmten -- gesamtspeicher_unabhaengig() in wb-belegung liefert auf Linux
# ueber os.sysconf(), auf macOS ueber 'sysctl -n hw.memsize', und beide Maschinen
# haben unterschiedlich viel RAM (Befund 2026-08-21: hier hart 48,0 GiB verdrahtet,
# das ist der Mac-Wert, auf Host2-Rechner mit 31 GiB Total ist die Zeile nie getroffen worden).
GESAMT_ERWARTET="$(/usr/bin/python3 -c '
import os, subprocess
g = None
if os.uname().sysname == "Darwin":
    for binaer in ("/usr/sbin/sysctl", "/sbin/sysctl"):
        if not os.access(binaer, os.X_OK):
            continue
        try:
            p = subprocess.run([binaer, "-n", "hw.memsize"], capture_output=True, text=True, timeout=3)
        except (subprocess.TimeoutExpired, OSError):
            continue
        if p.returncode == 0 and p.stdout.strip().isdigit():
            g = float(p.stdout.strip()) / (1024.0 ** 3)
            break
else:
    try:
        g = (os.sysconf("SC_PHYS_PAGES") * os.sysconf("SC_PAGE_SIZE")) / (1024.0 ** 3)
    except (ValueError, OSError, AttributeError):
        g = None
print(("%.1f" % g).replace(".", ",") if g is not None else "")
')"
if [ -n "$GESAMT_ERWARTET" ] && printf '%s' "$AUS" | grep -q "$GESAMT_ERWARTET gesamt"; then
    ok "der Gesamtspeicher kommt dabei aus einer Quelle, die ohne check-resources auskommt"
else
    bad "ohne check-resources war der Gesamtspeicher nicht zu bekommen (erwartet '$GESAMT_ERWARTET gesamt'): $AUS"
fi
WB_BELEGUNG_CHECK="$STUMM" belegung darf --gb 5 --abtastungen 1 --ohne-messung >/dev/null 2>&1
if [ "$?" = "0" ]; then ok "was nach Grenze B passt, wird mit --ohne-messung auch bewilligt"
else bad "--ohne-messung lehnt auch ab, was nach Grenze B passt"; fi
belegung gib --eigene >/dev/null 2>&1
( unset TMUX TMUX_PANE; belegung wer --json ) | /usr/bin/python3 -c 'import json,sys
for b in json.load(sys.stdin)["belegungen"]: print(b["id"])' | while read -r i; do
    belegung gib "$i" --fremd >/dev/null 2>&1
done

if WB_BELEGUNG_CHECK="$WORK/gibtsnicht" belegung darf --gb 10 --abtastungen 1 >/dev/null 2>&1; then
    bad "ein falscher WB_BELEGUNG_CHECK-Pfad faellt stillschweigend auf das echte Werkzeug zurueck"
else
    ok "ein falscher WB_BELEGUNG_CHECK-Pfad ist ein Fehler, kein stiller Rueckfall"
fi

echo
echo "== 9  Zwei Belegungen im Ladefenster passen zusammen in die Maschine =="

# Der Fall, den die alte Fixture ohne Grundlast nicht zeigen konnte. Ein ladendes
# Modell zieht seinen Speicher ueber Minuten; der gemessene freie Speicher sieht es
# also noch nicht. Zwei aufeinanderfolgende Anfragen im Ladefenster reichen, zwei
# gleichzeitige braucht es dafuer nicht.
frei_setzen "$GRUNDLAST_FREI"
belegung nimm --gb 20 --zweck 'erstes Modell laedt' --abtastungen 1 >/dev/null 2>&1
RC_EINS=$?
belegung nimm --gb 24 --zweck 'zweites Modell' --abtastungen 1 >/dev/null 2>&1
RC_ZWEI=$?
if [ "$RC_EINS" = "0" ] && [ "$RC_ZWEI" = "1" ]; then
    ok "20 GiB werden belegt, die 24 GiB daneben abgelehnt (zusammen waeren es 44 auf 30 freie)"
else
    bad "die Zahlen des Pruefdurchgangs gingen beide durch (erste=$RC_EINS, zweite=$RC_ZWEI)"
fi
belegung nimm --gb 3 --zweck 'kleines Modell' --abtastungen 1 >/dev/null 2>&1
if [ "$?" = "0" ] && [ "$(buch_summe)" = "23.0" ]; then
    ok "was neben das ladende Modell passt, wird weiterhin bewilligt"
else
    bad "auch das kleine Modell wurde abgelehnt (Buch: $(buch_summe) GiB)"
fi

KENNUNG="$(belegung wer --json | /usr/bin/python3 -c 'import json,sys
for b in json.load(sys.stdin)["belegungen"]:
    if b.get("zweck") == "erstes Modell laedt": print(b["id"]); break')"
if belegung wer | grep -q "laedt noch"; then ok "eine frische Belegung wird als 'laedt noch' gefuehrt"
else bad "der Ladezustand wird nicht angezeigt"; fi
belegung geladen "$KENNUNG" >/dev/null 2>&1
if belegung wer | grep -q "geladen "; then ok "nach der Meldung 'geladen' steht sie als geladen im Buch"
else bad "die Meldung 'geladen' wirkt nicht: $(belegung wer)"; fi

# Jetzt steht das erste Modell wirklich im Speicher: 30 - 20 = rund 10 GiB frei. Das
# zweite (3 GiB) laedt noch, also bleibt von den 10 nach Reserve und Ladung 1 GiB.
# --reserve-gb 6 AUSDRUECKLICH gesetzt (Nachtrag 27.08.2026): die Vorgabe ist seit
# Anweisung des Nutzers "keine Buchungs-Reserve mehr" auf 0 gesetzt, siehe Abschnitt
# 5 -- dieser Fall hier testet aber das LADEFENSTER (der noch nicht realisierte
# Speicher wird nicht doppelt vergeben), nicht die Reserve selbst, und braucht dafuer
# weiterhin eine Reserve ungleich Null, um genau an dieser Grenze zu liegen.
frei_setzen 10240
belegung darf --gb 3 --reserve-gb 6 --abtastungen 1 >/dev/null 2>&1
RC_ENG=$?
belegung wer --json | /usr/bin/python3 -c 'import json,sys
for b in json.load(sys.stdin)["belegungen"]:
    if not b.get("realisiert"): print(b["id"])' | while read -r i; do
    belegung geladen "$i" >/dev/null 2>&1
done
belegung darf --gb 3 --reserve-gb 6 --abtastungen 1 >/dev/null 2>&1
RC_DANACH=$?
if [ "$RC_ENG" = "1" ]; then
    ok "solange das zweite Modell laedt, wird sein Speicher nicht ein zweites Mal vergeben"
else
    bad "der Speicher des ladenden Modells wurde erneut vergeben (Exit $RC_ENG)"
fi
if [ "$RC_DANACH" = "0" ]; then
    ok "ist alles gemeldet, zaehlt wieder nur der gemessene freie Speicher"
else
    bad "nach der Meldung blieb doppelt gezaehlt (Exit $RC_DANACH)"
fi

# Die Reserve steht auch dann, wenn Grenze A bindet -- vorher wirkte sie nur auf B
# und fiel genau dort aus, wo sie gebraucht wird. --reserve-gb 6 AUSDRUECKLICH
# gesetzt (Nachtrag 27.08.2026): die VORGABE ist seit Anweisung des Nutzers auf 0,
# siehe Abschnitt 5 -- dieser Fall hier testet den MECHANISMUS (zieht eine
# gesetzte Reserve wirklich von Grenze A ab), nicht die Vorgabe selbst.
frei_setzen 10240
belegung gib --eigene >/dev/null 2>&1
( belegung wer --json | /usr/bin/python3 -c 'import json,sys
for b in json.load(sys.stdin)["belegungen"]: print(b["id"])' ) | while read -r i; do
    belegung gib "$i" --fremd >/dev/null 2>&1
done
belegung darf --gb 9.9 --reserve-gb 6 --abtastungen 1 >/dev/null 2>&1
RC_KNAPP=$?
belegung darf --gb 3 --reserve-gb 6 --abtastungen 1 >/dev/null 2>&1
RC_PASST=$?
if [ "$RC_KNAPP" = "1" ] && [ "$RC_PASST" = "0" ]; then
    ok "bei 10,0 GiB frei bleiben 6,0 GiB Reserve stehen: 9,9 abgelehnt, 3,0 bewilligt"
else
    bad "die Reserve wirkt nicht auf Grenze A (9,9=$RC_KNAPP, 3,0=$RC_PASST)"
fi
frei_setzen "$GRUNDLAST_FREI"

echo
echo "== 10  Jede unsinnige Zahl wird abgewiesen statt gebucht =="

# Alles gemessen im dritten Pruefdurchgang, alles mit einem Ja beantwortet.
belegung darf --gewichte-gb 22 --parallel -5 --kontext 8192 --modell kat --abtastungen 1 >/dev/null 2>&1
[ "$?" = "2" ] && ok "--parallel -5 wird abgewiesen" || bad "--parallel -5 wurde angenommen"
belegung darf --gewichte-gb 22 --parallel 16 --kontext 0 --modell kat --abtastungen 1 >/dev/null 2>&1
[ "$?" = "2" ] && ok "--kontext 0 wird abgewiesen" || bad "--kontext 0 wurde angenommen"
belegung nimm --gb -5 --zweck 'negativ' --abtastungen 1 >/dev/null 2>&1
[ "$?" = "2" ] && ok "eine negative Spitze wird abgewiesen" || bad "--gb -5 wurde gebucht"
belegung darf --gb 5 --reserve-gb nan --abtastungen 1 >/dev/null 2>&1
[ "$?" = "2" ] && ok "--reserve-gb nan wird abgewiesen" || bad "nan hat Grenze B lautlos abgeschaltet"
belegung darf --gb 5 --zuschlag-gb inf --abtastungen 1 >/dev/null 2>&1
[ "$?" = "2" ] && ok "--zuschlag-gb inf wird abgewiesen" || bad "inf wurde angenommen"
belegung kv setzen boesewicht -2.0 --herkunft gemessen >/dev/null 2>&1
[ "$?" = "2" ] && ok "ein negativer KV-Bedarf wird abgewiesen" || bad "kv setzen -2,0 wurde angenommen"
belegung kv setzen nullmodell 0 --herkunft gemessen >/dev/null 2>&1
[ "$?" = "2" ] && ok "ein KV-Bedarf von null wird abgewiesen" || bad "kv setzen 0 wurde angenommen"
if [ "$(buch_anzahl)" = "0" ]; then ok "nach all dem steht nichts davon im Buch"
else bad "es steht etwas im Buch, das nicht hineingehoert ($(buch_anzahl))"; fi

# Und eine unbrauchbare Groesse IM Buch haelt die Entscheidung an, statt sie zu
# verfaelschen -- der Eintrag kann von einer aelteren Fassung stammen.
/usr/bin/python3 - "$FAKEHOME/.local/state/wb-belegung/buch.json" <<'PYEOF'
import json, sys, time
pfad = sys.argv[1]
json.dump({"version": 1, "belegungen": [
    {"id": "kaputt", "gb": None, "seit": time.time(), "frist_s": 2700,
     "karenz_s": 3600, "halter": {}}]}, open(pfad, "w"))
PYEOF
AUS="$(belegung darf --gb 5 --abtastungen 1 2>&1)"
if [ "$?" = "3" ] && printf '%s' "$AUS" | grep -q "unbrauchbare Groesse"; then
    ok "ein unbrauchbarer Eintrag im Buch haelt die Entscheidung an"
else
    bad "der unbrauchbare Eintrag wurde mitgerechnet: $AUS"
fi
belegung gib kaputt --fremd >/dev/null 2>&1
belegung darf --gb 5 --abtastungen 1 >/dev/null 2>&1
[ "$?" = "0" ] && ok "und der genannte Ausweg raeumt ihn wirklich weg" \
    || bad "der genannte Ausweg funktioniert nicht"

echo
echo "== 11  Ollama-Ladungen erscheinen im Buch UND in der Summe (Nachtrag 16.08.) =="

# ANLASS: 'wb-belegung wer' zeigte am 16.08. EINE Belegung (25,5 GiB MLX-Server),
# waehrend 'ollama ps' zeitgleich zusaetzlich 'lmalpha:9b' (6,4 GB, 100% GPU)
# fuehrte -- ohne jeden Eintrag. Herkunft, spaeter geklaert: die woechentliche
# Testsuite (launchd agent-workbench.wb-testsuite, sonntags 20:00) spawnt echte
# pi-worker mit lmalpha:9b, ein regulaerer Vorgang ohne Buch-Eintrag. Hier mit
# runden Zahlen derselben Form nachgestellt.
belegung wer --json | /usr/bin/python3 -c 'import json,sys
for b in json.load(sys.stdin)["belegungen"]: print(b["id"])' | while read -r i; do
    belegung gib "$i" --fremd >/dev/null 2>&1
done
ollama_leeren
# 8192 MiB (8 GiB), nicht 40960 wie vor der Gegenprobe vom 20.08.: mit einer
# eigenen Buchung (20) UND einer stabilen Ollama-Ladung (20) auf 48 GiB
# gesamt ist 8 GiB frei genau der Wert, bei dem Grenze A und Grenze B
# UEBEREINSTIMMEN (beide 2 GiB) -- die Gegenprobe (Abschnitt 18) verlangt
# das inzwischen: eine Ollama-Meldung, die im wirklich freien Speicher nicht
# auftaucht, zaehlt nicht mehr mit. 40 GiB frei bei 20 GiB STABILER Ladung
# WAERE genau diese Nichtuebereinstimmung -- das eigene Werkzeug wuerde die
# Ladung jetzt zu Recht anzweifeln, siehe Abschnitt 18.
frei_setzen 8192

belegung nimm --gb 20 --zweck 'MLX-Server, wie am 16.08.' --abtastungen 1 >/dev/null 2>&1
KENNUNG11="$(belegung wer --json | /usr/bin/python3 -c 'import json,sys
for b in json.load(sys.stdin)["belegungen"]:
    if b.get("zweck") == "MLX-Server, wie am 16.08.": print(b["id"]); break')"
belegung geladen "$KENNUNG11" >/dev/null 2>&1
# Eine STABILE Ollama-Ladung: erst in 73 Jahren faellig, also weit ueber der
# 5-Minuten-Schwelle.
ollama_setzen '[{"name":"lmalpha:9b","size_mib":20480,"expires_at":"2099-01-01T00:00:00Z"}]'

AUS="$(belegung wer 2>&1)"
if printf '%s' "$AUS" | grep -q "lmalpha:9b" && printf '%s' "$AUS" | grep -q "ollama, nicht eingetragen"; then
    ok "die Ollama-Ladung erscheint im Buch, gekennzeichnet als nicht eingetragen"
else
    bad "die Ollama-Ladung taucht in 'wer' nicht auf: $AUS"
fi
if printf '%s' "$AUS" | grep -q "20,0 GiB  ollama"; then
    ok "ihre GiB kommen aus der ECHTEN Groesse (size_mib von check-resources), nicht aus einer Annahme"
else
    bad "die Groesse der Ollama-Ladung fehlt oder ist falsch: $AUS"
fi

# Vor diesem Umbau haette Grenze B = 48 - 6 Reserve - 20 (nur Buch) = 22 GiB
# hergegeben und 15 GiB bewilligt. Mit der Ollama-Ladung dazu sind es nur 2 GiB.
belegung darf --gb 15 --abtastungen 1 >/dev/null 2>&1
if [ "$?" = "1" ]; then
    ok "15 GiB werden abgelehnt, weil die STABILE Ollama-Ladung jetzt in Grenze B zaehlt"
else
    bad "die Ollama-Ladung floss nicht in die Vergabe ein -- 15 GiB wurden trotzdem bewilligt"
fi

echo
echo "== 12  Eine FLUECHTIGE Ollama-Ladung wird gezeigt, aber nicht gezaehlt (Nachtrag) =="

# Zweite Praezisierung vom 16.08.: eine Sitzung wurde korrekt abgelehnt (25,5 GiB
# gegen 23,1 GiB frei) und hat DANACH, statt zu warten, ungemessen auf zwei Spuren
# gedrosselt -- genau diese Kombination hat ihren MLX-Server mit
# 'metal::malloc Resource limit (499000) exceeded' zerlegt. Zaehlte kuenftig jede
# FLUECHTIGE Ollama-Ladung voll mit, wird abgelehnt, was heute noch durchgeht, und
# der naechste improvisiert genauso. Schwelle: 5 Minuten (Ollamas eigene Vorgabe
# fuer keep_alive) -- die Frist hier liegt in der Vergangenheit, also erst recht
# darunter.
ollama_setzen '[{"name":"lmalpha:9b","size_mib":20480,"expires_at":"2020-01-01T00:00:00Z"}]'
# Zurueck auf 40 GiB frei: eine FLUECHTIGE Ladung zaehlt fuer Grenze B gar
# nicht (ollama_stabile_summe ist 0), die Gegenprobe aus Abschnitt 18 prueft
# also erst gar nicht nach -- Grenze A darf hier wieder grosszuegig sein.
frei_setzen 40960

AUS="$(belegung darf --gb 15 --abtastungen 1 2>&1)"
if [ "$?" = "0" ]; then
    ok "dieselben 15 GiB werden jetzt bewilligt -- eine fluechtige Ladung zaehlt nicht mit"
else
    bad "eine fluechtige Ladung hat die Vergabe trotzdem gesperrt -- haerter als heute: $AUS"
fi
if printf '%s' "$AUS" | grep -q "lmalpha:9b" && printf '%s' "$AUS" | grep -q "nur ANGEZEIGT"; then
    ok "sie bleibt trotzdem SICHTBAR und als nur angezeigt (nicht gezaehlt) markiert"
else
    bad "die fluechtige Ladung wird nicht mehr angezeigt: $AUS"
fi

echo
echo "== 13  Ollama nicht erreichbar fuehrt zu UNBEKANNT, nicht zu FREI (Gegenprobe) =="

# Dritte Praezisierung: 'unbekannt ist nicht frei' ist die Lehre aus der
# Kontextwache. check-resources meldet diesen Fall als eigenes Feld
# ('ollama_loaded_note'), wenn der Server auf 'ollama ps' antwortet, die
# genauere Abfrage der Groessen aber scheitert.
ollama_setzen '[]' 'der Server antwortet auf ollama ps, /api/ps aber nicht (in 2s)'

AUS="$(belegung wer 2>&1)"
if printf '%s' "$AUS" | grep -q "UNBEKANNT"; then
    ok "eine gescheiterte Ollama-Abfrage wird im Buch als UNBEKANNT gefuehrt"
else
    bad "die gescheiterte Abfrage wird nicht als unbekannt gemeldet: $AUS"
fi
if printf '%s' "$AUS" | grep -qi "keine Ladung gemessen"; then
    bad "eine gescheiterte Abfrage wurde faelschlich als 'keine Ladung' (also frei) gemeldet"
else
    ok "sie wird NICHT als 'keine Ladung' (frei) ausgegeben"
fi
# Und die Vergabe wird dadurch nicht haerter als der heutige Zustand ganz ohne
# Ollama-Kenntnis: dieselben 15 GiB gehen weiterhin durch -- 'unbekannt' zaehlt
# mit 0,0 GiB, sperrt aber nicht blind auf Verdacht.
belegung darf --gb 15 --abtastungen 1 >/dev/null 2>&1
if [ "$?" = "0" ]; then
    ok "'unbekannt' macht die Vergabe nicht haerter als heute (zaehlt mit 0,0 GiB)"
else
    bad "'unbekannt' hat die Vergabe blockiert -- haerter als vor diesem Umbau"
fi

ollama_leeren
belegung wer --json | /usr/bin/python3 -c 'import json,sys
for b in json.load(sys.stdin)["belegungen"]: print(b["id"])' | while read -r i; do
    belegung gib "$i" --fremd >/dev/null 2>&1
done
frei_setzen "$GRUNDLAST_FREI"

echo
echo "== 14  Fremde Ollama-Ladungen zaehlen hier nicht mit (Nachtrag 16.08., zweiter Teil) =="

# ANLASS, gemessen am selben Abend: auf host2 bedient ein ssh-Portforward den
# Port 11434, damit die Scout-Agenten das Embedding-Modell des Macs erreichen.
# `ollama ps` antwortet dort also, beschreibt aber die GPU einer ANDEREN
# Maschine. Aufgefallen ist es daran, dass beide Maschinen dieselbe Ladung mit
# demselben expires_at auf die Mikrosekunde meldeten. Ohne Herkunftspruefung
# haette der Umbau von heute Nachmittag host2 fremde Ladungen als eigene
# Belegung verrechnet -- derselbe Fehlertyp wie "unbekannt wird zu frei", nur
# andersherum: fremd wird zu eigen.
ollama_setzen '[{"name":"embeddinggemma:latest","size_mib":20480,"expires_at":"2099-01-01T00:00:00Z"}]'
ollama_local_setzen false
# 23 GiB ist die Schwelle, an der sich die beiden Faelle ueberhaupt trennen:
# gezaehlt liegt Grenze B bei 22 GiB (48 gesamt - 6 Reserve - 20 Ladung), nicht
# gezaehlt bei 42, gedeckelt durch Grenze A auf 24. Eine kleinere Anfrage ginge
# in BEIDEN Faellen durch und haette gar nichts gemessen.

AUS="$(belegung darf --gb 23 --abtastungen 1 2>&1)"; RC=$?
if [ "$RC" = "0" ]; then
    ok "eine FREMDE 20-GiB-Ladung sperrt 23 GiB hier nicht (sie belegt kein Byte dieser GPU)"
else
    bad "die fremde Ladung wurde als eigene Belegung verrechnet: $AUS"
fi
if printf '%s' "$AUS" | grep -q "embeddinggemma"; then
    ok "sie bleibt trotzdem SICHTBAR -- wer den Speicher sucht, soll wissen, dass es sie gibt"
else
    bad "die fremde Ladung wurde stillschweigend verschwiegen: $AUS"
fi
if printf '%s' "$AUS" | grep -qi "ANDEREN Maschine"; then
    ok "und die Anzeige sagt, dass sie woanders liegt, statt sie wie eine lokale zu fuehren"
else
    bad "die Anzeige unterscheidet fremd nicht von lokal: $AUS"
fi

# Gegenprobe: dieselbe Ladung als LOKAL bestaetigt sperrt sehr wohl -- sonst
# waere die Herkunftspruefung ein Freibrief statt einer Unterscheidung.
ollama_local_setzen true
# 28672 MiB (28 GiB): mit einer STABILEN, LOKALEN 20-GiB-Ladung auf 48 GiB
# gesamt ist das der Wert, bei dem Grenze A und Grenze B uebereinstimmen (je
# 22 GiB) -- die Gegenprobe vom 20.08. (Abschnitt 18) verlangt das inzwischen,
# sonst zweifelt das Werkzeug die Ladung selbst an. --reserve-gb 6 AUSDRUECKLICH
# gesetzt (Nachtrag 27.08.2026, Vorgabe seit Anweisung des Nutzers auf 0, siehe
# Abschnitt 5) -- ohne die 6 GiB liegen Grenze A und B bei 28 statt 22 und die
# Uebereinstimmung, die diese Gegenprobe zeigen soll, verschwindet.
frei_setzen 28672
AUS="$(belegung darf --gb 23 --reserve-gb 6 --abtastungen 1 2>&1)"; RC=$?
if [ "$RC" != "0" ]; then
    ok "dieselbe Ladung als lokal bestaetigt sperrt dieselben 23 GiB (Gegenprobe)"
else
    bad "eine lokale 20-GiB-Ladung ging durch -- die Pruefung haengt am falschen Feld: $AUS"
fi

# Und die alte check-resources-Fassung, die das Feld gar nicht kennt, bleibt
# genau so streng wie vor diesem zweiten Nachtrag -- nicht strenger, nicht
# milder. --reserve-gb 6 aus demselben Grund wie in der Gegenprobe direkt
# darueber (Nachtrag 27.08.2026).
rm -f "$WORK/ollama-local.txt"
AUS="$(belegung darf --gb 23 --reserve-gb 6 --abtastungen 1 2>&1)"; RC=$?
if [ "$RC" != "0" ]; then
    ok "ohne das Feld bleibt es beim Verhalten von heute Nachmittag (Ladung zaehlt)"
else
    bad "das Fehlen des Feldes hat die Vergabe milder gemacht: $AUS"
fi
ollama_leeren
frei_setzen "$GRUNDLAST_FREI"

echo
echo "== 15  'nimm --json' warnt strukturiert vor einer Belegung ohne Pane (Befund N5) =="
# ANLASS: die ACHTUNG-Warnung ("kein tmux-Pane als Halter messbar ... verfaellt
# von selbst") lief bisher NUR im Text-Zweig von cmd_nimm -- ein Aufrufer mit
# --json (genau der Weg, den pi-worker fuer jede Worker-Sequenz nimmt) hat sie
# nie gesehen, obwohl er derselbe gefaehrliche Fall ist. Ohne die Warnung im
# JSON kann ein Skript, das die Antwort nur parst, die Gefahr strukturell gar
# nicht bemerken.

# Ohne Pane (aus der Test-Shell selbst gerufen, kein tmux dahinter):
AUS="$(belegung nimm --gewichte-gb 1 --parallel 1 --kontext 1000 --modell n5-ohne-pane \
       --zweck "N5-Test ohne Pane" --frist 5 --abtastungen 1 --json 2>&1)"
K1="$(printf '%s' "$AUS" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("kennung") or "")' 2>/dev/null)"
if printf '%s' "$AUS" | /usr/bin/python3 -c 'import json,sys
d=json.load(sys.stdin)
w=d.get("warnung") or ""
sys.exit(0 if ("uebernehmen" in w and "Pane" in w) else 1)' 2>/dev/null; then
    ok "ohne Pane traegt die JSON-Antwort eine 'warnung' mit dem Hinweis auf 'uebernehmen'"
else
    bad "die JSON-Antwort ohne Pane warnt nicht (oder nicht verstaendlich): $AUS"
fi
[ -n "$K1" ] && belegung gib "$K1" >/dev/null 2>&1

# Mit einem echten, lebenden Pane als Halter (ueber im_pane -- derselbe Anker
# wie in den frueheren Zusagen):
im_pane n5mitpane "'$TOOL' nimm --gewichte-gb 1 --parallel 1 --kontext 1000 --modell n5-mit-pane --zweck 'N5-Test mit Pane' --frist 5 --abtastungen 1 --json"
warte_auf_datei "$WORK/n5mitpane.done" 20 "N5-Test mit Pane" || true
AUS2="$(cat "$WORK/n5mitpane.out" 2>/dev/null)"
K2="$(printf '%s' "$AUS2" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("kennung") or "")' 2>/dev/null)"
if printf '%s' "$AUS2" | /usr/bin/python3 -c 'import json,sys
d=json.load(sys.stdin)
sys.exit(0 if d.get("warnung") is None else 1)' 2>/dev/null; then
    ok "mit einem lebenden Pane als Halter bleibt 'warnung' null -- kein Fehlalarm"
else
    bad "mit einem lebenden Pane warnt die JSON-Antwort trotzdem faelschlich: $AUS2"
fi
# --fremd: diese Buchung haengt an einem ECHTEN Pane (aus im_pane), die
# Test-Shell selbst hat keinen (TMUX_PANE oben entfernt) -- ohne --fremd
# verweigert cmd_gib die Freigabe einer fremden Belegung (wb-belegung:1509),
# und der Aufraeumschritt wuerde still scheitern (bei einer Vorfassung
# dieses Tests genau so geschehen, hat spaetere Abschnitte falsch belegt).
[ -n "$K2" ] && belegung gib "$K2" --fremd >/dev/null 2>&1

echo
echo "== 16  'uebernehmen' haengt eine Belegung an den EIGENEN Pane (Befund N5) =="
# ANLASS: eine Buchung ohne messbaren Pane haengt an einer FRIST -- einem
# Versprechen, sie irgendwann zu verlaengern. Verspricht niemand das (der
# ueblichste Fall bei einem Worker, der VOR seinem eigenen Pane bucht),
# verfaellt sie irgendwann, waehrend die Sequenz noch laeuft. 'uebernehmen'
# haengt die Belegung stattdessen an eine TATSACHE: den gerade aufrufenden,
# lebenden Pane. Danach entscheidet dieselbe Lebendigkeits-Pruefung wie bei
# jeder anderen Belegung mit Pane -- kein Versprechen mehr noetig.

AUS="$(belegung nimm --gewichte-gb 1 --parallel 1 --kontext 1000 --modell n5-uebernehmen \
       --zweck 'N5-uebernehmen-Test' --frist 5 --ohne-messung --json 2>&1)"
K16="$(printf '%s' "$AUS" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("kennung") or "")' 2>/dev/null)"
if [ -z "$K16" ]; then
    bad "16: Vorbereitung (Buchung ohne Pane) fehlgeschlagen: $AUS"
else
    im_pane uebernimmt "'$TOOL' uebernehmen '$K16'"
    warte_auf_datei "$WORK/uebernimmt.done" 20 "uebernehmen aus echtem Pane" || true
    AUSU="$(cat "$WORK/uebernimmt.out" 2>/dev/null)"
    if printf '%s' "$AUSU" | grep -q "Uebernommen: $K16"; then
        ok "16a: 'uebernehmen' meldet Erfolg aus einem echten, lebenden Pane"
    else
        bad "16a: 'uebernehmen' meldete keinen Erfolg: $AUSU"
    fi
    NEUER_PANE="$(pane_von uebernimmt)"
    HALTER_PANE="$(belegung wer --json | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
for b in d.get("belegungen", []):
    if b.get("id") == "'"$K16"'":
        print((b.get("halter") or {}).get("pane") or "")
        break
')"
    if [ -n "$HALTER_PANE" ] && [ "$HALTER_PANE" = "$NEUER_PANE" ]; then
        ok "16b: die Belegung haengt danach am ECHTEN, gerade aufrufenden Pane (nicht mehr pane-los)"
    else
        bad "16b: Halter-Pane nach 'uebernehmen' ist '$HALTER_PANE', erwartet '$NEUER_PANE'"
    fi
    # --fremd: seit 'uebernehmen' haengt diese Buchung an einem ECHTEN Pane
    # (aus im_pane), nicht mehr an der pane-losen Test-Shell -- derselbe
    # Grund wie beim K2-Aufraeumschritt in Abschnitt 15.
    belegung gib "$K16" --fremd >/dev/null 2>&1
fi

# Ohne eigenen Pane (Regelfall dieser Testdatei, TMUX/TMUX_PANE oben entfernt):
# 'uebernehmen' MUSS verweigern, statt den bisherigen (moeglicherweise noch
# gueltigen) Halter durch GAR KEINEN zu ersetzen.
AUS="$(belegung nimm --gewichte-gb 1 --parallel 1 --kontext 1000 --modell n5-uebernehmen2 \
       --zweck 'N5-uebernehmen-Test2' --frist 5 --ohne-messung --json 2>&1)"
K16B="$(printf '%s' "$AUS" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("kennung") or "")' 2>/dev/null)"
if [ -n "$K16B" ]; then
    AUSR="$(belegung uebernehmen "$K16B" 2>&1)"; RCR=$?
    if [ "$RCR" != 0 ] && printf '%s' "$AUSR" | grep -qi "kein TMUX_PANE"; then
        ok "16c: ohne eigenen Pane verweigert 'uebernehmen', statt den Halter zu leeren"
    else
        bad "16c: 'uebernehmen' ohne Pane haette verweigern muessen: rc=$RCR $AUSR"
    fi
    belegung gib "$K16B" >/dev/null 2>&1
fi

# Mit echtem Pane, aber unbekannter Kennung: die Pane-Pruefung greift zuerst
# (die grundsaetzlichere Voraussetzung), erst DANN die Kennungssuche -- ein
# eigener Pane isoliert also, welche der beiden Pruefungen hier gemeint ist.
im_pane uebernimmtunbekannt "'$TOOL' uebernehmen nicht-existent-xyz"
warte_auf_datei "$WORK/uebernimmtunbekannt.done" 20 "uebernehmen unbekannte Kennung" || true
AUSX="$(cat "$WORK/uebernimmtunbekannt.out" 2>/dev/null)"
RCX="$(rc_von uebernimmtunbekannt)"
if [ "$RCX" = 1 ] && printf '%s' "$AUSX" | grep -qi "keine Belegung"; then
    ok "16d: eine unbekannte Kennung wird sauber abgelehnt (Exit 1)"
else
    bad "16d: unbekannte Kennung ergab rc=$RCX: $AUSX"
fi

echo
echo "== 17  '--gewichte-entwerfer-gb' bucht den Entwerfer sichtbar getrennt vom Ziel (Auftrag 'Vorhersage im Betrieb', 2026-08-20) =="
# Reichlich frei setzen: 'entwerfer-test' ist absichtlich ein unbekanntes
# Modell (die Zusagen hier pruefen die Buchungsformel, nicht kv-bedarf.json)
# und faellt deshalb auf den teuersten gemessenen KV-Wert zurueck -- bei
# 8192 Token allein schon mehrere GiB. Ohne diesen Reset koennte ein
# Reststand aus einem frueheren Abschnitt die Buchung hier grundlos ablehnen.
frei_setzen 40960
# ANLASS: ein externer Entwerfer fuer spekulatives Decoding braucht eigene
# Gewichte (gemessen 3,5-3,6 GB fuer DFlash2/DSpark), zusaetzlich zu den
# 16,1 GiB des Ziels. Wer das nicht bucht, laeuft in dieselbe Speicherlage,
# die am 11.08. zweimal in einer Kernel-Panik endete.

AUS="$(belegung darf --gewichte-gb 16.05 --gewichte-entwerfer-gb 3.6 --modell entwerfer-test \
       --parallel 1 --kontext 8192 --abtastungen 1 2>&1)"
if printf '%s' "$AUS" | grep -q "Gewichte 16,1 (Ziel) + 3,6 (Entwerfer)"; then
    ok "17a: die Spitze zeigt Ziel- und Entwerfergewichte getrennt, nicht als eine Zahl"
else
    bad "17a: kein getrennter Ausweis von Ziel/Entwerfer: $AUS"
fi
SPITZE_MIT="$(printf '%s' "$AUS" | sed -n 's/.*Spitze *\([0-9,]*\) GiB.*/\1/p' | head -1)"
AUS_OHNE="$(belegung darf --gewichte-gb 16.05 --modell entwerfer-test \
       --parallel 1 --kontext 8192 --abtastungen 1 2>&1)"
SPITZE_OHNE="$(printf '%s' "$AUS_OHNE" | sed -n 's/.*Spitze *\([0-9,]*\) GiB.*/\1/p' | head -1)"
if [ -n "$SPITZE_MIT" ] && [ -n "$SPITZE_OHNE" ] && [ "$SPITZE_MIT" != "$SPITZE_OHNE" ]; then
    ok "17b: mit Entwerfer ist die Spitze groesser als ohne ($SPITZE_OHNE -> $SPITZE_MIT GiB)"
else
    bad "17b: Entwerfer-Gewichte veraendern die Spitze nicht: ohne=$SPITZE_OHNE mit=$SPITZE_MIT"
fi
AUSJ="$(belegung nimm --gewichte-gb 16.05 --gewichte-entwerfer-gb 3.6 --modell entwerfer-test \
       --zweck '17c-Entwerfer-Test' --parallel 1 --kontext 8192 --abtastungen 1 --ohne-messung --json 2>&1)"
K17="$(printf '%s' "$AUSJ" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("kennung") or "")' 2>/dev/null)"
if [ -n "$K17" ] && belegung wer --json | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
for b in d.get("belegungen", []):
    if b.get("id") == "'"$K17"'":
        sys.exit(0 if (b.get("rechnung") or {}).get("gewichte_entwerfer_gb") == 3.6 else 1)
sys.exit(1)
'; then
    ok "17c: die Entwerfer-Gewichte stehen im Buch, ueber wb-belegung wer --json abrufbar"
else
    bad "17c: gewichte_entwerfer_gb steht nicht (oder falsch) in der Buchung"
fi
[ -n "$K17" ] && belegung gib "$K17" >/dev/null 2>&1

# Ohne --gewichte-entwerfer-gb bleibt alles wie vorher (Vorgabe 0, kein Bruch
# fuer jeden bestehenden Aufrufer, der den Schalter nicht kennt).
AUS_ALT="$(belegung darf --gb 5 --abtastungen 1 2>&1)"
if [ "$?" != "3" ] && ! printf '%s' "$AUS_ALT" | grep -qi "unbekannte option\|unrecognized"; then
    ok "17d: Aufrufer ohne --gewichte-entwerfer-gb funktionieren unveraendert"
else
    bad "17d: alter Aufruf ohne den neuen Schalter bricht: $AUS_ALT"
fi

echo
echo "== 18  Die Gegenprobe: eine Ollama-Ladung, die im wirklich freien Speicher"
echo "       nicht auftaucht, zaehlt nicht mehr blind (Befund 20.08.2026) =="

# ANLASS: am 20.08. rechnete wb-belegung mit 21,6 GiB verfuegbar (Grenze B,
# eine STABILE Ollama-Ladung abgezogen, deren Prozess laengst tot war),
# waehrend check-resources zeitgleich 30 GiB frei mass -- die Fremdanzeige
# gewann, obwohl die eigene Messung daneben lag, und lehnte vier Laeufe
# hintereinander ab, bevor ueberhaupt ein Worker startete. Hier nachgestellt:
# grosszuegig freier Speicher, eine grosse STABILE Ollama-Ladung, die dort
# nicht auftaucht.
ollama_leeren
belegung wer --json | /usr/bin/python3 -c 'import json,sys
for b in json.load(sys.stdin)["belegungen"]: print(b["id"])' | while read -r i; do
    belegung gib "$i" --fremd >/dev/null 2>&1
done
frei_setzen "$GRUNDLAST_FREI"
ollama_setzen '[{"name":"lmalpha:9b","size_mib":20480,"expires_at":"2099-01-01T00:00:00Z"}]'

# Grenze A = 30,0 frei - 6 Reserve = 24,0. Grenze B MIT der Ladung = 48 - 6 -
# 20 = 22,0 -- vor diesem Umbau haette das 23 GiB abgelehnt, obwohl 24 GiB
# wirklich frei sind.
AUS="$(belegung darf --gb 23 --abtastungen 1 2>&1)"; RC=$?
if [ "$RC" = "0" ]; then
    ok "18a: die 23 GiB werden bewilligt -- die unbestaetigte Ollama-Ladung sperrt nicht mehr blind"
else
    bad "18a: die 23 GiB wurden trotz widerlegter Ollama-Ladung abgelehnt (rc=$RC): $AUS"
fi
if printf '%s' "$AUS" | grep -q "WIDERSPRUCH"; then
    ok "18b: der Widerspruch wird LAUT gemeldet, nicht stillschweigend aufgeloest"
else
    bad "18b: kein WIDERSPRUCH in der Ausgabe: $AUS"
fi
if printf '%s' "$AUS" | grep -q "lmalpha:9b"; then
    ok "18c: die Ladung bleibt trotzdem SICHTBAR (nur ihre Zaehlung wird verweigert)"
else
    bad "18c: die Ladung ist aus der Anzeige verschwunden, statt nur nicht mehr zu zaehlen: $AUS"
fi

AUSJ="$(belegung darf --gb 23 --abtastungen 1 --json 2>&1)"
if printf '%s' "$AUSJ" | /usr/bin/python3 -c 'import json,sys
d=json.load(sys.stdin)
w=d.get("ollama_widerspruch") or ""
sys.exit(0 if ("20,0" in w or "20.0" in w) else 1)' 2>/dev/null; then
    ok "18d: 'ollama_widerspruch' steht auch strukturiert im JSON, nicht nur im Text"
else
    bad "18d: 'ollama_widerspruch' fehlt im JSON oder ist leer: $AUSJ"
fi

# Gegenprobe zur Gegenprobe: eine KLEINE, mit dem gemessenen freien Speicher
# VERTRAEGLICHE stabile Ladung (Abschnitt 11: 20 GiB Buch + 20 GiB Ollama bei
# 8 GiB frei -- Grenze A und B stimmen ueberein) loest KEINEN Widerspruch aus.
# Sonst waere die Toleranz nutzlos und jede stabile Ladung staende immer unter
# Verdacht.
ollama_leeren
frei_setzen 8192
belegung nimm --gb 20 --zweck 'Gegenprobe-Buch' --abtastungen 1 >/dev/null 2>&1
KENNUNG18="$(belegung wer --json | /usr/bin/python3 -c 'import json,sys
for b in json.load(sys.stdin)["belegungen"]:
    if b.get("zweck") == "Gegenprobe-Buch": print(b["id"]); break')"
belegung geladen "$KENNUNG18" >/dev/null 2>&1
ollama_setzen '[{"name":"lmalpha:9b","size_mib":20480,"expires_at":"2099-01-01T00:00:00Z"}]'
AUS="$(belegung darf --gb 1 --abtastungen 1 2>&1)"
if printf '%s' "$AUS" | grep -q "WIDERSPRUCH"; then
    bad "18e: eine mit dem freien Speicher vertraegliche Ladung loest trotzdem einen Widerspruch aus: $AUS"
else
    ok "18e: eine mit dem freien Speicher vertraegliche stabile Ladung bleibt unverdaechtig"
fi
belegung wer --json | /usr/bin/python3 -c 'import json,sys
for b in json.load(sys.stdin)["belegungen"]: print(b["id"])' | while read -r i; do
    belegung gib "$i" --fremd >/dev/null 2>&1
done
ollama_leeren
frei_setzen "$GRUNDLAST_FREI"

echo
echo "== 19  'ollama-freigeben' verlaesst sich nie auf den Erfolgs-Exit von"
echo "       'ollama stop' -- jeder Schritt wird frisch verifiziert (Befund 20.08.2026) =="

# Wegwerf-Fassungen von 'ollama' und 'launchctl'. Wie 'ollama stop' am 20.08.
# wirklich beobachtet: der Befehl meldet IMMER Erfolg (Exit 0), egal ob er
# etwas bewirkt -- gesteuert wird die WIRKUNG separat ueber ollama.json (die
# check-resources-Attrappe von oben), nicht ueber den Exit-Code.
OLLAMA_STOP_LOG="$WORK/ollama-stop-calls.log"
FAKE_OLLAMA="$WORK/fake-ollama"
cat > "$FAKE_OLLAMA" <<EOF
#!/bin/sh
case "\$1" in
    stop)
        echo "\$2" >> "$OLLAMA_STOP_LOG"
        if [ -f "$WORK/ollama-stop-wirkt.txt" ]; then
            echo '[]' > "$WORK/ollama.json"
        fi
        exit 0
        ;;
    ps|list)
        # 'ollama-dienst-down.txt' spielt den toten Dienst: dieselbe Datei,
        # die die launchctl-Attrappe unten setzt/loescht -- 'ollama-freigeben'
        # verifiziert die Rueckkehr des Dienstes GENAU hierueber, nicht ueber
        # check-resources (das meldet einen toten Server als 'leer', nicht
        # als 'unbekannt' -- siehe der Kommentar im Quelltext).
        if [ -f "$WORK/ollama-dienst-down.txt" ]; then
            echo "Error: could not connect to ollama app, is it running?" >&2
            exit 1
        fi
        exit 0
        ;;
esac
exit 0
EOF
chmod +x "$FAKE_OLLAMA"

# launchctl: 'stop' raeumt die Ladung IMMER wirklich ab (wie am 20.08.
# beobachtet, 'launchctl stop homebrew.mxcl.ollama' wirkte) -- und heilt sich
# in DIESER Fassung sofort selbst (KeepAlive=true im echten Plist bringt den
# Dienst binnen Millisekunden zurueck, kein 'launchctl start' noetig). Die
# 'ollama-dienst-down.txt'-Fassung fuer den selteneren Fall, dass er das NICHT
# von selbst tut, kommt erst bei 19e -- eigene Definition dort.
LAUNCHCTL_LOG="$WORK/launchctl-calls.log"
FAKE_LAUNCHCTL="$WORK/fake-launchctl"
cat > "$FAKE_LAUNCHCTL" <<EOF
#!/bin/sh
echo "\$1 \$2" >> "$LAUNCHCTL_LOG"
[ "\$1" = "stop" ] && echo '[]' > "$WORK/ollama.json"
exit 0
EOF
chmod +x "$FAKE_LAUNCHCTL"

# check-resources-Attrappe fuer diesen Abschnitt. 'ollama-unbekannt.txt'
# spielt den Fall aus 'UNBEKANNT IST NICHT FREI' im Kopf dieser Datei nach
# (der Server antwortet auf 'ollama ps', die genauere /api/ps-Abfrage aber
# nicht) -- NICHT denselben Fall wie ein bestaetigt toter Server (der zaehlt
# als 'leer', siehe dort). Die Ollama-Ladung selbst kommt weiterhin aus
# ollama.json wie in den fruehen Abschnitten.
STELLVERTRETER_19="$WORK/check-resources-19"
cat > "$STELLVERTRETER_19" <<EOF
#!/bin/sh
d="$WORK"
frei=\$(cat "\$d/frei.txt" 2>/dev/null || echo 36000)
printf '{"vram":{"kind":"unified","free_mib":%s,"total_mib":49152},' "\$frei"
printf '"ram":{"free_mib":%s,"total_mib":49152}' "\$frei"
if [ -f "\$d/ollama-unbekannt.txt" ]; then
    printf ',"ollama_loaded":[],"ollama_loaded_note":"der Server antwortet auf ollama ps, /api/ps aber nicht (Attrappe)"'
elif [ -f "\$d/ollama.json" ]; then
    printf ',"ollama_loaded":%s,"ollama_loaded_note":""' "\$(cat "\$d/ollama.json")"
fi
printf '}\n'
EOF
chmod +x "$STELLVERTRETER_19"

freigeben() {
    rm -f "$OLLAMA_STOP_LOG" "$LAUNCHCTL_LOG"
    WB_BELEGUNG_CHECK="$STELLVERTRETER_19" WB_BELEGUNG_OLLAMA_BIN="$FAKE_OLLAMA" \
        WB_BELEGUNG_LAUNCHCTL_BIN="$FAKE_LAUNCHCTL" "$TOOL" ollama-freigeben "$@"
}

echo
echo "-- 19a: nichts geladen -> sofortiger Erfolg, nichts angefasst --"
rm -f "$WORK/ollama-stop-wirkt.txt" "$WORK/ollama-dienst-down.txt"
frei_setzen 30000
echo '[]' > "$WORK/ollama.json"
AUS="$(freigeben --frist 3 2>&1)"; RC=$?
if [ "$RC" = "0" ] && [ ! -s "$OLLAMA_STOP_LOG" ]; then
    ok "19a: nichts geladen -> Erfolg ohne 'ollama stop' aufzurufen"
else
    bad "19a: rc=$RC, stop-log: $(cat "$OLLAMA_STOP_LOG" 2>/dev/null): $AUS"
fi

echo
echo "-- 19b: 'ollama stop' wirkt -> keine Eskalation noetig --"
touch "$WORK/ollama-stop-wirkt.txt"
echo '[{"name":"lmalpha:9b","size_mib":6400,"expires_at":"2099-01-01T00:00:00Z"}]' > "$WORK/ollama.json"
AUS="$(freigeben --frist 5 2>&1)"; RC=$?
if [ "$RC" = "0" ] && grep -q "lmalpha:9b" "$OLLAMA_STOP_LOG" && [ ! -s "$LAUNCHCTL_LOG" ]; then
    ok "19b: wirkendes 'ollama stop' reicht -- launchctl wird gar nicht erst gerufen"
else
    bad "19b: rc=$RC, stop-log: $(cat "$OLLAMA_STOP_LOG" 2>/dev/null), launchctl-log: $(cat "$LAUNCHCTL_LOG" 2>/dev/null): $AUS"
fi

echo
echo "-- 19c: 'ollama stop' meldet Erfolg und wirkt NICHT (Befund 20.08.) -> Eskalation --"
rm -f "$WORK/ollama-stop-wirkt.txt" "$WORK/ollama-dienst-down.txt"
echo '[{"name":"lmalpha:9b","size_mib":6400,"expires_at":"2099-01-01T00:00:00Z"}]' > "$WORK/ollama.json"
AUS="$(freigeben --frist 5 2>&1)"; RC=$?
# Die launchctl-Eskalation ist im Werkzeug ausdruecklich auf Darwin begrenzt
# (wb-belegung: `if os.uname().sysname != "Darwin"` vor jedem launchctl-Aufruf,
# noch vor launchctl_binaer() -- WB_BELEGUNG_LAUNCHCTL_BIN kommt also auf Linux
# nie zum Zug). Auf jeder anderen Plattform bleibt es beim ehrlichen Abbruch statt
# einer Eskalation, die es dort nicht geben kann (Befund 2026-08-21).
if [ "$(uname -s)" = "Darwin" ]; then
    if [ "$RC" = "0" ] && grep -q "lmalpha:9b" "$OLLAMA_STOP_LOG" && grep -q "^stop homebrew.mxcl.ollama$" "$LAUNCHCTL_LOG"; then
        ok "19c: 'ollama stop' wirkte nicht -> eskaliert auf 'launchctl stop', verifiziert frei"
    else
        bad "19c: rc=$RC, stop-log: $(cat "$OLLAMA_STOP_LOG" 2>/dev/null), launchctl-log: $(cat "$LAUNCHCTL_LOG" 2>/dev/null): $AUS"
    fi
    if printf '%s' "$AUS" | grep -qi "Dienst antwortet wieder"; then
        ok "19d: der Dienst wird nach der Eskalation als wieder erreichbar VERIFIZIERT, nicht angenommen"
    else
        bad "19d: keine Verifikation, dass der Dienst zurueck ist: $AUS"
    fi
else
    if [ "$RC" = "1" ] && grep -q "lmalpha:9b" "$OLLAMA_STOP_LOG" && [ ! -s "$LAUNCHCTL_LOG" ] \
        && printf '%s' "$AUS" | grep -qi "kein macOS"; then
        ok "19c: ausserhalb macOS bricht es ehrlich ab, statt eine Eskalation vorzutaeuschen, die es dort nicht gibt"
    else
        bad "19c: rc=$RC, stop-log: $(cat "$OLLAMA_STOP_LOG" 2>/dev/null), launchctl-log: $(cat "$LAUNCHCTL_LOG" 2>/dev/null): $AUS"
    fi
    if [ "$RC" = "1" ]; then
        ok "19d: ausserhalb macOS entfaellt die Dienst-Verifikation -- es gibt nichts, das eskaliert wurde"
    else
        bad "19d: unerwarteter Erfolg ausserhalb macOS: $AUS"
    fi
fi

echo
echo "-- 19e: der Dienst kommt nicht von selbst zurueck -> 'launchctl start' wird nachgeholt --"
rm -f "$WORK/ollama-stop-wirkt.txt"
echo '[{"name":"lmalpha:9b","size_mib":6400,"expires_at":"2099-01-01T00:00:00Z"}]' > "$WORK/ollama.json"
# Diese Fassung von 'launchctl stop' laesst den Dienst DAUERHAFT unten stehen
# (kein KeepAlive-Neustart simuliert) -- erst 'launchctl start' raeumt
# 'ollama-dienst-down.txt' weg.
cat > "$FAKE_LAUNCHCTL" <<EOF
#!/bin/sh
echo "\$1 \$2" >> "$LAUNCHCTL_LOG"
case "\$1" in
    stop)  echo '[]' > "$WORK/ollama.json"; touch "$WORK/ollama-dienst-down.txt" ;;
    start) rm -f "$WORK/ollama-dienst-down.txt" ;;
esac
exit 0
EOF
chmod +x "$FAKE_LAUNCHCTL"
AUS="$(freigeben --frist 3 2>&1)"; RC=$?
if [ "$(uname -s)" = "Darwin" ]; then
    if [ "$RC" = "0" ] && grep -q "^start homebrew.mxcl.ollama$" "$LAUNCHCTL_LOG"; then
        ok "19e: 'launchctl start' wird ausdruecklich nachgeholt, wenn der Dienst nicht von selbst zurueckkommt"
    else
        bad "19e: 'launchctl start' wurde nicht nachgeholt: rc=$RC, launchctl-log: $(cat "$LAUNCHCTL_LOG" 2>/dev/null): $AUS"
    fi
else
    if [ "$RC" = "1" ] && [ ! -s "$LAUNCHCTL_LOG" ]; then
        ok "19e: ausserhalb macOS wird kein launchctl gerufen -- die Eskalation bleibt macOS vorbehalten"
    else
        bad "19e: unerwartetes Verhalten ausserhalb macOS: rc=$RC, launchctl-log: $(cat "$LAUNCHCTL_LOG" 2>/dev/null): $AUS"
    fi
fi

echo
echo "-- 19f: Ollama-Zustand nicht messbar -> nichts wird angefasst --"
rm -f "$WORK/ollama.json" "$WORK/ollama-dienst-down.txt" "$WORK/ollama-unbekannt.txt"
touch "$WORK/ollama-unbekannt.txt"
AUS="$(freigeben --frist 3 2>&1)"; RC=$?
if [ "$RC" = "1" ] && [ ! -s "$OLLAMA_STOP_LOG" ] && [ ! -s "$LAUNCHCTL_LOG" ]; then
    ok "19f: ein nicht messbarer Ollama-Zustand wird NICHT angefasst (kein 'ollama stop', kein launchctl)"
else
    bad "19f: trotz unmessbarem Zustand wurde etwas versucht: rc=$RC, stop-log: $(cat "$OLLAMA_STOP_LOG" 2>/dev/null), launchctl-log: $(cat "$LAUNCHCTL_LOG" 2>/dev/null)"
fi
rm -f "$WORK/ollama-dienst-down.txt" "$WORK/ollama-unbekannt.txt" "$WORK/ollama-stop-wirkt.txt"
frei_setzen "$GRUNDLAST_FREI"

echo
echo "== 20  Karteileichen: eine Belegung ueberlebt den Prozess, den sie beschreibt =="
echo "       (Nachtrag 2026-08-21 abends -- gemessen: ein MLX-Server starb ohne"
echo "       Abschiedszeile, seine Buchung lief drei Stunden unbeirrt als 'geladen'"
echo "       weiter und belastete jede Vergabe um ihre volle Groesse. GEGEN STELL-"
echo "       VERTRETER: kein echtes Modell, nur harmlose 'sleep'-Prozesse dieser"
echo "       Test-Shell spielen die 'PID des Servers'.)"
frei_setzen "$GRUNDLAST_FREI"
# Gross genug, dass eine zusaetzliche, kleine Anfrage sichtbar daran scheitert,
# WENN sie faelschlich mitgezaehlt wird -- klein genug, dass GRUNDLAST_FREI (rund
# 30 GiB) allein noch reichlich Luft laesst.
PHANTOM_GB=20
kennung_aus_json() { /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("kennung") or "")'; }
zustand_von() {   # <buch-json-von-stdin> <kennung>
    /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
e = next((x for x in d.get("belegungen", []) if x.get("id") == sys.argv[1]), None)
print(e.get("_zustand") if e else "FEHLT")' "$1"
}

echo
echo "-- 20a: lebender Prozess -- die Belegung bleibt normal 'offen' --"
sleep 300 & LEBT_PID=$!
KEN_LEBT="$(belegung nimm --gb $PHANTOM_GB --zweck '20a lebt' --abtastungen 1 --json | kennung_aus_json)"
belegung geladen "$KEN_LEBT" --pid "$LEBT_PID" >/dev/null 2>&1
if ps -p "$LEBT_PID" >/dev/null 2>&1; then
    ok "20a: Testvoraussetzung haelt -- PID $LEBT_PID lebt wirklich (eigener sleep-Prozess dieser Shell)"
else
    bad "20a: Testvoraussetzung verletzt -- PID $LEBT_PID lebt schon vor der Pruefung nicht mehr"
fi
Z20A="$(belegung wer --json 2>&1 | zustand_von "$KEN_LEBT")"
if [ "$Z20A" = "offen" ]; then
    ok "20a: eine Belegung mit lebendem Prozess bleibt 'offen', nicht 'tot'"
else
    bad "20a: Zustand '$Z20A' statt 'offen' fuer eine Belegung mit lebendem Prozess"
fi
belegung gib "$KEN_LEBT" >/dev/null 2>&1
kill "$LEBT_PID" 2>/dev/null; wait "$LEBT_PID" 2>/dev/null

echo
echo "-- 20b: toter Prozess -- als 'tot' erkannt, belastet die Vergabe NICHT mehr --"
sleep 300 & TOT_PID=$!
KEN_TOT="$(belegung nimm --gb $PHANTOM_GB --zweck '20b tot' --abtastungen 1 --json | kennung_aus_json)"
belegung geladen "$KEN_TOT" --pid "$TOT_PID" >/dev/null 2>&1
# Der Prozess stirbt jetzt WIRKLICH -- 'kill' plus 'wait' (nicht nur ein kurzer
# sleep, der Wettlaeufe waere): danach ist die PID garantiert weg, nicht nur
# vermutlich.
kill "$TOT_PID" 2>/dev/null
wait "$TOT_PID" 2>/dev/null
if ps -p "$TOT_PID" >/dev/null 2>&1; then
    bad "20b: Testvoraussetzung verletzt -- PID $TOT_PID lebt nach 'kill'+'wait' immer noch"
else
    Z20B="$(belegung wer --json 2>&1 | zustand_von "$KEN_TOT")"
    if [ "$Z20B" = "tot" ]; then
        ok "20b: eine Belegung mit totem Prozess wird als 'tot' erkannt"
    else
        bad "20b: Zustand '$Z20B' statt 'tot' fuer eine Belegung mit nachweislich totem Prozess"
    fi
    # Die Vergabe: eine kleine Anfrage muss trotz der GROSSEN toten Buchung
    # durchgehen -- wuerde die tote Buchung noch mitzaehlen, bliebe fuer diese
    # Anfrage rechnerisch kein Platz (PHANTOM_GB allein ist fast der ganze freie
    # Speicher dieser Fixture).
    AUS_DARF="$(belegung darf --gb 5 --abtastungen 1 --json 2>&1)"
    JA_DARF="$(printf '%s' "$AUS_DARF" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("ja"))' 2>/dev/null)"
    if [ "$JA_DARF" = "True" ]; then
        ok "20b: die Vergabe ignoriert die tote Buchung -- eine kleine Anfrage geht trotzdem durch"
    else
        bad "20b: die tote Buchung belastet die Vergabe weiterhin: $AUS_DARF"
    fi
fi
belegung gib "$KEN_TOT" >/dev/null 2>&1

echo
echo "-- 20c: wiederverwendete PID (Prozess lebt, aber es ist NICHT mehr derselbe) -- gilt als tot --"
# Eine PID allein beweist nichts (siehe shell/wb-waisen, 'PID-WIEDERVERWENDUNG'):
# dieselbe Nummer kann laengst zu einem anderen Prozess gehoeren. Nachgestellt
# OHNE eine echte PID-Wiederverwendung abzuwarten (nicht deterministisch
# erzwingbar): ein WIRKLICH lebender Prozess, dessen gespeicherter
# 'prozess_lstart' auf einen falschen (nicht seinen echten) Startzeitpunkt
# zeigt -- exakt die Situation, die eine Wiederverwendung hinterlaesst, und
# exakt der Vergleich, den prozess_lebt() zieht.
sleep 300 & WVPID_PID=$!
KEN_WVPID="$(belegung nimm --gb $PHANTOM_GB --zweck '20c wiederverwendet' --abtastungen 1 --json | kennung_aus_json)"
belegung geladen "$KEN_WVPID" --pid "$WVPID_PID" >/dev/null 2>&1
/usr/bin/python3 - "$FAKEHOME/.local/state/wb-belegung/buch.json" "$KEN_WVPID" <<'PYEOF'
import json, sys
pfad, kennung = sys.argv[1], sys.argv[2]
d = json.load(open(pfad))
getroffen = False
for e in d.get("belegungen", []):
    if e.get("id") == kennung:
        e["prozess_lstart"] = "Thu Jan  1 00:00:00 1970"
        getroffen = True
if not getroffen:
    sys.exit("Kennung nicht im Buch gefunden")
json.dump(d, open(pfad, "w"))
PYEOF
if ps -p "$WVPID_PID" >/dev/null 2>&1; then
    ok "20c: Testvoraussetzung haelt -- PID $WVPID_PID lebt wirklich (nur ihr GESPEICHERTER Startzeitpunkt ist jetzt falsch)"
else
    bad "20c: Testvoraussetzung verletzt -- PID $WVPID_PID lebt nicht mehr"
fi
Z20C="$(belegung wer --json 2>&1 | zustand_von "$KEN_WVPID")"
if [ "$Z20C" = "tot" ]; then
    ok "20c: eine lebende PID mit falschem gespeichertem Startzeitpunkt gilt als 'tot' -- die PID allein reicht nicht"
else
    bad "20c: Zustand '$Z20C' statt 'tot' -- die PID-Wiederverwendung wurde nicht erkannt"
fi
belegung gib "$KEN_WVPID" >/dev/null 2>&1
kill "$WVPID_PID" 2>/dev/null; wait "$WVPID_PID" 2>/dev/null

echo
echo "-- 20d: 'laedt noch' (nie 'geladen' gemeldet) bleibt UNANGETASTET -- der genaue"
echo "        Zustand jedes Fehlversuchs der Kernel-Panik-Nacht --"
KEN_LAEDT="$(belegung nimm --gb $PHANTOM_GB --zweck '20d laedt noch' --abtastungen 1 --json | kennung_aus_json)"
# Absichtlich KEIN 'geladen' -- diese Belegung bleibt 'realisiert: false'. Ein
# offensichtlich toter PID-Wert wird ihr trotzdem eingetragen (direkt am Buch, ein
# Caller-Fehler oder ein Rest aus einem frueheren Versuch waere plausibel) --
# prozess_tot() muss sie DENNOCH nie anfassen: 'realisiert' wird zuerst gepr
# ueft, bevor die PID ueberhaupt gelesen wird.
/usr/bin/python3 - "$FAKEHOME/.local/state/wb-belegung/buch.json" "$KEN_LAEDT" <<'PYEOF'
import json, sys
pfad, kennung = sys.argv[1], sys.argv[2]
d = json.load(open(pfad))
for e in d.get("belegungen", []):
    if e.get("id") == kennung:
        e["prozess_pid"] = 999999   # garantiert keine laufende PID
        e["prozess_lstart"] = "Thu Jan  1 00:00:00 1970"
json.dump(d, open(pfad, "w"))
PYEOF
Z20D="$(belegung wer --json 2>&1 | zustand_von "$KEN_LAEDT")"
if [ "$Z20D" != "tot" ]; then
    ok "20d: eine ladende Belegung ('realisiert: false') bleibt unangetastet, auch mit einer toten PID eingetragen (Zustand: $Z20D)"
else
    bad "20d: eine ladende Belegung wurde faelschlich als 'tot' eingestuft -- das raeumt einem startenden Server die Buchung unter den Fuessen weg"
fi
belegung gib "$KEN_LAEDT" >/dev/null 2>&1

echo
echo "-- die echte Maschine blieb unberuehrt (Abschnitt 20) --"
if [ ! -f "$HOME_ECHT/.local/state/wb-belegung/buch.json" ] \
   || ! grep -qF "20a lebt" "$HOME_ECHT/.local/state/wb-belegung/buch.json" 2>/dev/null; then
    ok "20: keine der 'sleep'-Testbuchungen steht im ECHTEN Buch dieser Maschine"
else
    bad "20: eine Testbuchung ist im ECHTEN Buch gelandet -- Testisolation gebrochen"
fi

frei_setzen "$GRUNDLAST_FREI"

echo
echo "== 21  Prozess-Halter (--prozess-haelt) -- Nachtrag 2026-09-08, Auftrag 'buchung' =="
echo "       (ZWEITE RUNDE, Gegenleser-Befunde zu 78c865d: der Prozess-Halter"
echo "       braucht eine eigene Eigentumsregel (Befund 1), 'uebernehmen' darf ihn"
echo "       nicht stillschweigend zu einem Pane zurueckmachen (Risiko 5), und die"
echo "       Herkunftsfelder duerfen beim Umhaengen nicht verlorengehen (Risiko 4).)"
zustand_von_kennung() {   # <buch-json-von-stdin> <kennung>
    /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
e = next((x for x in d.get("belegungen", []) if x.get("id") == sys.argv[1]), None)
print(e.get("_zustand") if e else "FEHLT")' "$1"
}
halter_art_von() {   # <buch-json-von-stdin> <kennung>
    /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
e = next((x for x in d.get("belegungen", []) if x.get("id") == sys.argv[1]), None)
print((e.get("halter") or {}).get("halter_art", "") if e else "FEHLT")' "$1"
}
realisiert_von() {   # <buch-json-von-stdin> <kennung>
    /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
e = next((x for x in d.get("belegungen", []) if x.get("id") == sys.argv[1]), None)
print(e.get("realisiert") if e else "FEHLT")' "$1"
}

echo
echo "-- 21a: eigen-Regel -- ein lebender Prozess-Halter gehoert NIEMANDEM ohne --fremd (Befund 1) --"
sleep 300 & P21A=$!
KEN21A="$(belegung nimm --gb 1 --zweck '21a prozess lebt' --abtastungen 1 --json | kennung_aus_json)"
belegung geladen "$KEN21A" --pid "$P21A" --prozess-haelt >/dev/null 2>&1
if belegung gib "$KEN21A" >/dev/null 2>&1; then
    bad "21a: 'gib <kennung>' OHNE --fremd hat einen lebenden Prozess-Halter freigegeben -- gehoert niemandem war der alte, falsche Zustand"
else
    ok "21a: 'gib <kennung>' ohne --fremd lehnt einen lebenden Prozess-Halter ab"
fi
if belegung gib --eigene >/dev/null 2>&1; then
    bad "21a: 'gib --eigene' (kein Pane im Aufrufer) hat den lebenden Prozess-Halter mit freigegeben"
else
    :  # exit 1 heisst hier vermutlich nur "nichts eigenes da" -- die Hauptpruefung ist die naechste Zeile.
fi
Z21A_NACH_EIGENE="$(belegung wer --json 2>&1 | zustand_von_kennung "$KEN21A")"
if [ "$Z21A_NACH_EIGENE" != FEHLT ]; then
    ok "21a: 'gib --eigene' hat den lebenden Prozess-Halter NICHT getroffen -- er steht noch im Buch"
else
    bad "21a: der lebende Prozess-Halter ist nach 'gib --eigene' aus dem Buch verschwunden"
fi
if belegung gib "$KEN21A" --fremd >/dev/null 2>&1; then
    ok "21a: 'gib <kennung> --fremd' gibt einen lebenden Prozess-Halter ausdruecklich frei"
else
    bad "21a: 'gib <kennung> --fremd' haette den Prozess-Halter freigeben muessen"
fi
kill "$P21A" 2>/dev/null; wait "$P21A" 2>/dev/null

echo
echo "-- 21b: ein TOTER Prozess-Halter verfaellt SOFORT (nicht 'tot', symmetrisch zu einem toten Pane) --"
sleep 300 & P21B=$!
KEN21B="$(belegung nimm --gb 1 --zweck '21b prozess stirbt' --abtastungen 1 --frist 240 --json | kennung_aus_json)"
belegung geladen "$KEN21B" --pid "$P21B" --prozess-haelt >/dev/null 2>&1
kill "$P21B" 2>/dev/null; wait "$P21B" 2>/dev/null
AUS21B="$(belegung wer --json 2>&1)"
Z21B="$(printf '%s' "$AUS21B" | zustand_von_kennung "$KEN21B")"
if [ "$Z21B" = FEHLT ]; then
    ok "21b: eine Belegung mit totem Prozess-Halter verfaellt sofort, trotz Frist 240 min -- symmetrisch zu einem toten Pane"
else
    bad "21b: Zustand '$Z21B' statt 'verfallen'/FEHLT fuer einen nachweislich toten Prozess-Halter"
fi
VERFALLEN21B="$(printf '%s' "$AUS21B" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(any(v.get("id")==sys.argv[1] for v in d.get("verfallen", [])))' "$KEN21B" 2>/dev/null)"
if [ "$VERFALLEN21B" = True ]; then
    ok "21b: 'wer' meldet die Belegung ausdruecklich als 'verfallen', nicht stillschweigend"
else
    bad "21b: 'verfallen' fehlt in der Antwort fuer $KEN21B"
fi

echo
echo "-- 21c: PID-Wiederverwendung beim Prozess-Halter (falscher gespeicherter Startzeitpunkt) -- verfaellt, lebt nicht als 'offen' weiter --"
sleep 300 & P21C=$!
KEN21C="$(belegung nimm --gb 1 --zweck '21c pid wiederverwendet' --abtastungen 1 --json | kennung_aus_json)"
belegung geladen "$KEN21C" --pid "$P21C" --prozess-haelt >/dev/null 2>&1
/usr/bin/python3 - "$FAKEHOME/.local/state/wb-belegung/buch.json" "$KEN21C" <<'PYEOF'
import json, sys
pfad, kennung = sys.argv[1], sys.argv[2]
d = json.load(open(pfad))
for e in d.get("belegungen", []):
    if e.get("id") == kennung:
        e["prozess_lstart"] = "Thu Jan  1 00:00:00 1970"
json.dump(d, open(pfad, "w"))
PYEOF
Z21C="$(belegung wer --json 2>&1 | zustand_von_kennung "$KEN21C")"
if [ "$Z21C" = FEHLT ]; then
    ok "21c: eine lebende PID mit falschem gespeichertem Startzeitpunkt gilt beim Prozess-Halter als verfallen -- die PID allein reicht nicht"
else
    bad "21c: Zustand '$Z21C' statt verfallen/FEHLT -- die PID-Wiederverwendung wurde beim Prozess-Halter nicht erkannt"
fi
kill "$P21C" 2>/dev/null; wait "$P21C" 2>/dev/null

echo
echo "-- 21d: 'aufraeumen' entfernt eine verfallene Prozess-Halter-Buchung wirklich aus dem Buch --"
sleep 300 & P21D=$!
KEN21D="$(belegung nimm --gb 1 --zweck '21d aufraeumen' --abtastungen 1 --json | kennung_aus_json)"
belegung geladen "$KEN21D" --pid "$P21D" --prozess-haelt >/dev/null 2>&1
kill "$P21D" 2>/dev/null; wait "$P21D" 2>/dev/null
belegung aufraeumen >/dev/null 2>&1
if buch | grep -qF "$KEN21D"; then
    bad "21d: 'aufraeumen' liess die verfallene Prozess-Halter-Buchung im Buch stehen"
else
    ok "21d: 'aufraeumen' entfernt eine verfallene Prozess-Halter-Buchung aus dem Buch"
fi

echo
echo "-- 21e: 'uebernehmen' macht aus einem Prozess-Halter NIE stillschweigend einen Pane-Halter (Risiko 5) --"
sleep 300 & P21E=$!
KEN21E="$(belegung nimm --gb 1 --zweck '21e uebernehmen-guard' --abtastungen 1 --json | kennung_aus_json)"
belegung geladen "$KEN21E" --pid "$P21E" --prozess-haelt >/dev/null 2>&1
im_pane p21e "'$TOOL' uebernehmen '$KEN21E'"
warte_auf_datei "$WORK/p21e.done" 20 "21e uebernehmen ohne --fremd" || true
if [ "$(rc_von p21e)" = "0" ]; then
    bad "21e: 'uebernehmen' OHNE --fremd hat einen Prozess-Halter stillschweigend zu einem Pane-Halter gemacht"
else
    ok "21e: 'uebernehmen' ohne --fremd lehnt einen Prozess-Halter ab (rc=$(rc_von p21e))"
fi
HALTER_ART_21E="$(belegung wer --json 2>&1 | halter_art_von "$KEN21E")"
if [ "$HALTER_ART_21E" = prozess ]; then
    ok "21e: der Halter ist nach der Ablehnung weiterhin 'prozess', nicht umgeschrieben"
else
    bad "21e: halter_art ist '$HALTER_ART_21E' statt 'prozess' -- die Ablehnung hat trotzdem etwas veraendert"
fi
im_pane p21e2 "'$TOOL' uebernehmen '$KEN21E' --fremd"
warte_auf_datei "$WORK/p21e2.done" 20 "21e uebernehmen --fremd" || true
if [ "$(rc_von p21e2)" = "0" ]; then
    ok "21e: 'uebernehmen ... --fremd' erlaubt den Wechsel zurueck auf einen Pane, ausdruecklich"
else
    bad "21e: 'uebernehmen ... --fremd' haette den Prozess-Halter zurueck auf einen Pane haengen sollen (rc=$(rc_von p21e2)): $(cat "$WORK/p21e2.out" 2>/dev/null)"
fi
belegung gib "$KEN21E" --fremd >/dev/null 2>&1
kill "$P21E" 2>/dev/null; wait "$P21E" 2>/dev/null

echo
echo "-- 21f: 'uebernehmen --pid' (frueher Transfer, Befund 11) haengt an einen Prozess, OHNE 'realisiert' anzufassen --"
sleep 300 & P21F=$!
KEN21F="$(belegung nimm --gb 1 --zweck '21f frueher transfer' --abtastungen 1 --json | kennung_aus_json)"
AUS21F="$(belegung uebernehmen "$KEN21F" --pid "$P21F" 2>&1)"
RC21F=$?
BUCH21F="$(belegung wer --json 2>&1)"
HALTER_ART_21F="$(printf '%s' "$BUCH21F" | halter_art_von "$KEN21F")"
REALISIERT_21F="$(printf '%s' "$BUCH21F" | realisiert_von "$KEN21F")"
if [ "$RC21F" -eq 0 ] && [ "$HALTER_ART_21F" = prozess ]; then
    ok "21f: 'uebernehmen --pid' haengt die Belegung an den Prozess, VOR jeder Health-Bestaetigung"
else
    bad "21f: 'uebernehmen --pid' schlug fehl oder setzte halter_art nicht auf 'prozess' (rc=$RC21F, halter_art=$HALTER_ART_21F)" "$AUS21F"
fi
if [ "$REALISIERT_21F" = False ]; then
    ok "21f: 'realisiert' bleibt False -- Grenze A zieht die Buchung weiterhin als 'laedt noch' ab, anders als bei 'geladen --prozess-haelt'"
else
    bad "21f: 'realisiert' ist '$REALISIERT_21F' statt False -- 'uebernehmen --pid' haette es nicht anfassen duerfen"
fi
kill "$P21F" 2>/dev/null; wait "$P21F" 2>/dev/null
belegung gib "$KEN21F" --fremd >/dev/null 2>&1

echo
echo "-- 21g: 'geladen --pid --prozess-haelt' nimmt sitzung/worker vom vorherigen Pane-Halter mit (Risiko 4) --"
im_pane p21g "'$TOOL' nimm --gb 1 --zweck '21g herkunft' --abtastungen 1 --frist 1 --halter meinetikett --json"
warte_auf_datei "$WORK/p21g.done" 20 "21g Buchung" || true
KEN21G="$(cat "$WORK/p21g.out" 2>/dev/null | kennung_aus_json)"
if [ -n "$KEN21G" ]; then
    sleep 300 & P21G=$!
    belegung geladen "$KEN21G" --pid "$P21G" --prozess-haelt >/dev/null 2>&1
    HALTER_TEXT_21G="$(belegung wer 2>&1 | grep -A1 "^  $KEN21G " | head -1)"
    if printf '%s' "$HALTER_TEXT_21G" | grep -q 'Prozess PID' && printf '%s' "$HALTER_TEXT_21G" | grep -q 'aus '; then
        ok "21g: die Anzeige nennt nach dem Umhaengen sowohl 'Prozess PID' als auch die Herkunft (Pane/Sitzung), nicht nur die PID"
    else
        bad "21g: die Herkunft (sitzung/worker) fehlt in der Anzeige nach 'geladen --prozess-haelt'" "$HALTER_TEXT_21G"
    fi
    kill "$P21G" 2>/dev/null; wait "$P21G" 2>/dev/null
    belegung gib "$KEN21G" --fremd >/dev/null 2>&1
else
    bad "21g: die Vorab-Buchung (im_pane) lieferte keine Kennung -- Test uebersprungen"
fi

echo
echo "-- die echte Maschine blieb unberuehrt (Abschnitt 21) --"
if [ ! -f "$HOME_ECHT/.local/state/wb-belegung/buch.json" ] \
   || ! grep -qF "21a prozess lebt" "$HOME_ECHT/.local/state/wb-belegung/buch.json" 2>/dev/null; then
    ok "21: keine der 'sleep'-Testbuchungen steht im ECHTEN Buch dieser Maschine"
else
    bad "21: eine Testbuchung ist im ECHTEN Buch gelandet -- Testisolation gebrochen"
fi

frei_setzen "$GRUNDLAST_FREI"

echo
echo "== 22  --nur-gewichte -- eine Buchung ohne jeden KV-Anteil (Auftrag 'buchung', erste Runde) =="
echo "       (wird von wb-mlx-server seit der ZWEITEN Runde nicht mehr benutzt -- der"
echo "       Serverstart bucht seither einen festen Basisstrom, siehe Abschnitt 9 in"
echo "       test-mlx-server-kapazitaet.sh -- bleibt aber ein eigenstaendiges,"
echo "       getestetes Werkzeug in wb-belegung.)"
AUS22="$(belegung nimm --gewichte-gb 10 --nur-gewichte --modell 22-modell --zweck '22 nur-gewichte' --abtastungen 1 --json 2>&1)"
SPITZE22="$(printf '%s' "$AUS22" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("spitze_gib"))' 2>/dev/null)"
if [ "$SPITZE22" = "10.0" ]; then
    ok "22: --nur-gewichte bucht exakt die Gewichte (10.0 GiB), kein KV-Anteil obendrauf"
else
    bad "22: erwartet spitze_gib=10.0" "$AUS22"
fi
KEN22="$(printf '%s' "$AUS22" | kennung_aus_json)"
PARALLEL22="$(buch | /usr/bin/python3 -c 'import json,sys
d = json.load(sys.stdin)
e = next((x for x in d.get("belegungen", []) if x.get("id") == sys.argv[1]), None)
print((e.get("rechnung") or {}).get("parallel") if e else "FEHLT")' "$KEN22" 2>/dev/null)"
if [ "$PARALLEL22" = 0 ]; then
    ok "22: rechnung.parallel steht auf 0 -- diese Buchung beansprucht ausdruecklich keinen Strom"
else
    bad "22: rechnung.parallel ist '$PARALLEL22' statt 0" "$AUS22"
fi
belegung gib "$KEN22" >/dev/null 2>&1

frei_setzen "$GRUNDLAST_FREI"

echo
echo "Ergebnis: $pass ok, $fail FAIL"
[ "$fail" -eq 0 ]
