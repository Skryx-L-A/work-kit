#!/bin/bash
# test-pi-worker-modellaliase.sh — jeder Claude-Spawn-Name, den die Registry-Tabelle
# ausliefert, muss von pi-worker auch angenommen werden.
#
# Anlass (2026-08-22, im Betrieb aufgetreten): `wb-state models table` liefert die
# Claude-Modelle unter den praefixlosen Kurznamen `sonnet5`, `opus5`, `haiku45`,
# `opus48` und `fable5` aus. Diese Tabelle steht als Routing-Tabelle im Rollen-Prompt
# jedes Orchestrators — sie ist die Anweisung, nach der gespawnt wird. Der
# Modell-case in shell/pi-worker kannte aber nur die `claude-`-Formen. Ein Spawn nach
# Tabelle endete deshalb mit "FEHLER: unbekanntes Modell 'sonnet5'", und die
# Fehlermeldung nannte als Abhilfe ausgerechnet dieselben fuenf Kurznamen, die der
# case gerade abgelehnt hatte. Zwei Quellen derselben Wahrheit, auseinandergelaufen.
#
# WAS DIESE SUITE PRUEFT: dass die Namensmenge der Tabelle in der Namensmenge des
# case enthalten ist. Gematcht wird mit bashs eigenem `case` gegen die Muster, die
# aus der echten Datei gelesen werden — keine nachgebaute Kopie der Logik.
#
# WAS SIE NICHT PRUEFT: dass ein Spawn unter diesem Namen danach auch durchlaeuft.
# Dafuer braucht es einen echten Worker-Start (Kontingent, Pane, Modellserver); das
# ist Sache des Betriebs, nicht dieser Suite.
#
# Hermetisch: liest zwei Dateien, startet nichts, schreibt nur unter mktemp.
set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PI_WORKER="$REPO_ROOT/shell/pi-worker"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok    $1"; }
nok()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
zusage() { if [ "$1" = 0 ]; then ok "$2"; else nok "$2"; fi; }

# --- Die Muster aus der echten Datei lesen --------------------------------------
# Jede Zeile der Bauart `  <muster>) ENGINE=claude; CMODEL="..." ;;` traegt links
# von der Klammer ihr case-Muster. Kommentarzeilen fallen weg, weil sie kein
# ENGINE=claude tragen.
muster_lesen() {
  local datei="$1"
  # Seit dem Familienalias-Umbau (2026-09-23, wb/modelle-discover) traegt die Zeile
  # `claude|claude-sonnet|claude-haiku|claude-fable|claude-opus)` ihr ENGINE=claude
  # erst im Rumpf darunter; sie zaehlt trotzdem als Claude-Muster.
  grep -E 'ENGINE=claude; *CMODEL=|^[[:space:]]*claude\|claude-sonnet\|' "$datei" \
    | grep -vE '^\s*#' \
    | sed 's/).*//' \
    | sed 's/^[[:space:]]*//' \
    | tr '|' '\n' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
    | grep -v '^$'
}
# Aufgespalten wird an '|', weil bash ein Muster aus einer Variablen NICHT erneut
# als Alternation parst: `case $n in $m)` mit m="a|b" sucht die Zeichenkette "a|b",
# nicht a oder b. Gemessen -- ohne das Aufspalten fiel jede Zusage ausser der einen
# Zeile, die schon vorher nur ein einziges Muster trug.

# Ein Name gilt als bekannt, wenn eines der Muster ihn matcht — geprueft von bash
# selbst, mit denselben Regeln, nach denen der case in pi-worker entscheidet.
name_bekannt() {
  local name="$1" datei="$2" m
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    case "$name" in
      $m) return 0 ;;
    esac
  done < <(muster_lesen "$datei")
  return 1
}

echo "== Vorbedingungen =="
[ -r "$PI_WORKER" ]; zusage $? "shell/pi-worker ist lesbar"

MUSTER_ANZAHL="$(muster_lesen "$PI_WORKER" | grep -c .)"
[ "$MUSTER_ANZAHL" -ge 5 ]; zusage $? "der Modell-case traegt mindestens fuenf Claude-Muster (gefunden: $MUSTER_ANZAHL)"

# --- Die Namen, die die Tabelle wirklich ausliefert ------------------------------
# Quelle ist wb-state; fehlt es (fremde Maschine, nackte Umgebung), faellt die Suite
# auf die fuenf im Anlass genannten Namen zurueck statt sich gruen zu melden.
WBSTATE="$HOME/.local/bin/wb-state"
TABELLE_NAMEN=""
if [ -x "$WBSTATE" ]; then
  TABELLE_NAMEN="$("$WBSTATE" models table 2>/dev/null \
    | awk -F'|' 'NF>3 && $4 ~ /^ *claude *$/ {print $3}' \
    | tr -d ' `' \
    | sed 's/:.*//' \
    | sort -u)"
fi
QUELLE="wb-state models table"
if [ -z "$TABELLE_NAMEN" ]; then
  TABELLE_NAMEN=$'sonnet5\nopus5\nhaiku45\nopus48\nfable5'
  QUELLE="Rueckfall (wb-state nicht erreichbar oder ohne claude-Zeilen)"
fi
echo "== Claude-Spawn-Namen aus: $QUELLE =="

ANZ=0
while IFS= read -r n; do
  [ -n "$n" ] || continue
  ANZ=$((ANZ+1))
  # Eine Kennung, die nicht im schnellen Pfad steht (z. B. `claude-opus-5-5`, seit
  # 2026-09-22 per Discover in der Tabelle), startet pi-worker ueber den Zweig
  # `claude*)` aus der Registry -- bekannt ist sie, wenn die Registry sie kennt.
  if name_bekannt "$n" "$PI_WORKER"; then
    ok "pi-worker kennt den Spawn-Namen '$n'"
  elif [ -x "$WBSTATE" ] && [ -n "$("$WBSTATE" models get "$n" --field id 2>/dev/null || true)" ]; then
    ok "pi-worker kennt den Spawn-Namen '$n' (ueber die Registry, Zweig claude*)"
  else
    nok "pi-worker kennt den Spawn-Namen '$n'"
  fi
done <<< "$TABELLE_NAMEN"
# Vier, nicht fuenf: `fable5` steht wegen der Fable-Sperre nicht in der Tabelle.
# Kit: three Claude models ship (haiku45, sonnet5, opus55).
[ "$ANZ" -ge 3 ]; zusage $? "die Tabelle liefert mindestens drei Claude-Namen (gefunden: $ANZ)"

# Die `claude-`-Formen bleiben erhalten — der Fix ergaenzt, er ersetzt nicht.
for n in claude claude-sonnet claude-sonnet5 claude-opus5 claude-haiku45 claude-opus; do
  name_bekannt "$n" "$PI_WORKER"; zusage $? "die bisherige Form '$n' wird weiterhin erkannt"
done

# Ein Name, den niemand kennt, darf NICHT durchrutschen: sonst passt jedes Muster
# auf alles und die Zusagen oben saehen gruen aus, ohne etwas zu messen.
name_bekannt "voellig-unbekanntes-modell-xyz" "$PI_WORKER"
[ $? -ne 0 ]; zusage $? "ein unbekannter Name wird NICHT erkannt (die Muster greifen nicht blind)"

# --- Gegenprobe gegen die unreparierte Fassung -----------------------------------
# Ein Regressionstest, der auch auf der kaputten Fassung durchlaeuft, sagt nichts.
# Nachgestellt wird der Stand vor dem 2026-08-22: die Kurzformen aus den Mustern
# entfernt, alles andere unveraendert.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ALT="$TMP/pi-worker-alt"
sed -E 's/\|sonnet5\)/)/; s/\|haiku45\)/)/; s/\|fable51\)/)/; s/\|opus5\)/)/; s/\|opus48\)/)/' \
  "$PI_WORKER" > "$ALT"

echo "== Gegenprobe: dieselben Zusagen gegen die unreparierte Fassung =="
GEFALLEN=0
for n in sonnet5 opus5 haiku45 opus48 fable51; do
  if name_bekannt "$n" "$ALT"; then
    nok "die alte Fassung haette '$n' erkannt — dann misst die Zusage oben nichts"
  else
    GEFALLEN=$((GEFALLEN+1))
  fi
done
[ "$GEFALLEN" -eq 5 ]; zusage $? "alle fuenf Kurzformen fallen auf der unreparierten Fassung ($GEFALLEN von 5)"

# ... und die alte Fassung erkennt die `claude-`-Formen weiter: die Gegenprobe hat
# also wirklich nur die Kurzformen entfernt und nicht den ganzen case zerlegt.
name_bekannt "claude-sonnet5" "$ALT"; zusage $? "die unreparierte Fassung kennt 'claude-sonnet5' weiterhin (die Gegenprobe zielt eng)"

echo
echo "PASS: $PASS  FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
