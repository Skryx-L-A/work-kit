#!/bin/bash
# test-run-all-pool-ueberlebt.sh -- beweist pool_aufheben_oder_loeschen() aus
# run-all.sh in beide Richtungen.
#
# ANLASS (2026-08-22): run-all.sh loeschte sein Pool-Verzeichnis (die .out/
# .meta-Dateien jeder Suite aus dem parallelen Lauf) unmittelbar nach dem
# Pool-Lauf, mit `rm -rf` -- lange bevor am Skriptende feststeht, ob der Lauf
# insgesamt rot war. Wer nach einem roten Lauf wissen wollte, WARUM eine
# Suite fiel, musste den ganzen (zehnminuetigen) Lauf wiederholen. Jetzt
# entscheidet `pool_aufheben_oder_loeschen()` am Skriptende: rot -> nach
# $HOME/.local/state/wb-run-all-letzter-roter-lauf verschoben und der Pfad
# genannt; gruen -> geloescht wie zuvor, damit sich nichts ansammelt.
#
# WARUM WOERTLICH GEZOGEN STATT NACHGEBAUT: dieselbe Begruendung wie
# test-worktree-skip.sh fuer is_worktree() -- was hier laeuft, ist der
# tatsaechlich ausgelieferte Code aus run-all.sh, keine Kopie, die
# auseinanderlaufen koennte. Ein echter, zehnminuetiger run-all.sh-Lauf wird
# dafuer NICHT zweimal wiederholt (einmal "rot", einmal "gruen") -- die
# Funktion nimmt Pool-Verzeichnis und Fehlerzahl als Parameter und laesst
# sich isoliert gegen ein synthetisches Pool-Verzeichnis pruefen.
#
# ISOLATION: eigenes HOME (mktemp), eigenes synthetisches Pool-Verzeichnis --
# das echte ~/.local/state wird nie gelesen und nie geschrieben.
unset TMUX TMUX_PANE
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNALL="$SCRIPT_DIR/run-all.sh"
[ -f "$RUNALL" ] || { echo "FAIL  $RUNALL fehlt"; exit 1; }

TESTHOME="$(mktemp -d)"
trap 'rm -rf "$TESTHOME"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }

# --- die echte Funktion woertlich aus run-all.sh ziehen --------------------
FN="$(sed -n '/^pool_aufheben_oder_loeschen() {   # <pool_dir> <fail_count>$/,/^}$/p' "$RUNALL")"
[ -n "$FN" ] && ok "run-all.sh enthaelt pool_aufheben_oder_loeschen()" \
             || bad "pool_aufheben_oder_loeschen() nicht gefunden (Extraktion leer) -- der Rest dieser Suite kann nichts pruefen"
[ -n "$FN" ] || { echo; echo "PASS: $pass   FAIL: $fail"; exit 1; }

neues_pool() {   # neues_pool <name> -> baut ein synthetisches Pool-Verzeichnis, druckt seinen Pfad
  local p="$TESTHOME/pool-$1"
  mkdir -p "$p"
  printf '== RUN   shell/tests/test-fiktiv.sh ==\nirgendeine Ausgabe\n' > "$p/job0.out"
  printf 'shell/tests/test-fiktiv.sh\tPASS\t3s\t\n' > "$p/job0.meta"
  printf '%s\n' "$p"
}

ZIEL="$TESTHOME/.local/state/wb-run-all-letzter-roter-lauf"

echo "=== 1. Ein GRUENER Lauf haeuft nichts an -- das Pool-Verzeichnis wird geloescht ==="
POOL1="$(neues_pool gruen)"
HOME="$TESTHOME" bash -c "$FN"$'\n''pool_aufheben_oder_loeschen "$1" 0' _ "$POOL1"
if [ -d "$POOL1" ]; then
  bad "1a: das Pool-Verzeichnis eines gruenen Laufs (FAIL_COUNT=0) besteht noch" "$POOL1"
else
  ok "1a: das Pool-Verzeichnis eines gruenen Laufs ist weg"
fi
if [ -e "$ZIEL" ]; then
  bad "1b: ein gruener Lauf hat trotzdem etwas unter $ZIEL abgelegt"
else
  ok "1b: ein gruener Lauf legt nichts unter $ZIEL ab"
fi

echo
echo "=== 2. Ein ROTER Lauf ueberlebt -- die AUSGABE liegt danach unter ZIEL ========"
POOL2="$(neues_pool rot)"
AUS="$(HOME="$TESTHOME" bash -c "$FN"$'\n''pool_aufheben_oder_loeschen "$1" 2' _ "$POOL2" 2>&1)"
if [ ! -e "$POOL2" ] && [ -d "$ZIEL" ]; then
  ok "2a: das urspruengliche Pool-Verzeichnis ist weg, ZIEL besteht"
else
  bad "2a: entweder besteht das alte Pool-Verzeichnis noch, oder ZIEL fehlt" "POOL2=$POOL2 ZIEL=$ZIEL"
fi
if [ -f "$ZIEL/job0.out" ] && grep -q "irgendeine Ausgabe" "$ZIEL/job0.out"; then
  ok "2b: die volle .out-Ausgabe der Suite ist unter ZIEL erhalten -- genau das, was vorher verloren ging"
else
  bad "2b: job0.out fehlt unter ZIEL oder traegt nicht mehr den erwarteten Inhalt"
fi
if [ -f "$ZIEL/job0.meta" ]; then
  ok "2c: auch die .meta-Datei (Name/Status/Dauer/Grund) ist erhalten"
else
  bad "2c: job0.meta fehlt unter ZIEL"
fi
if printf '%s' "$AUS" | grep -qF "$ZIEL"; then
  ok "2d: der Pfad des Aufgehobenen wird genannt (sonst sucht ihn keiner)"
else
  bad "2d: der Pfad wurde nicht ausgegeben" "$AUS"
fi

echo
echo "=== 3. Ein ZWEITER roter Lauf ersetzt den ersten -- kein Anhaeufen ============"
POOL3="$(neues_pool rot-zwei)"
printf 'ZWEITER-LAUF-MARKER\n' >> "$POOL3/job0.out"
HOME="$TESTHOME" bash -c "$FN"$'\n''pool_aufheben_oder_loeschen "$1" 5' _ "$POOL3"
if grep -q "ZWEITER-LAUF-MARKER" "$ZIEL/job0.out" 2>/dev/null; then
  ok "3a: der zweite rote Lauf steht jetzt unter ZIEL"
else
  bad "3a: ZIEL traegt nicht den Inhalt des zweiten roten Laufs"
fi
FUNDE="$(find "$TESTHOME/.local/state" -maxdepth 1 -name 'wb-run-all-letzter-roter-lauf*' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$FUNDE" = "1" ]; then
  ok "3b: es liegt genau EIN aufgehobener roter Lauf, nicht mehrere nebeneinander"
else
  bad "3b: es liegen $FUNDE Verzeichnisse statt genau eines"
fi

echo
echo "=== 4. Ein dritter, GRUENER Lauf raeumt einen liegengebliebenen roten NICHT weg ="
# Bewusst: pool_aufheben_oder_loeschen() raeumt nur das EIGENE Pool-Verzeichnis
# des aktuellen Laufs ab, nie ZIEL selbst -- ein gruener Lauf ohne eigenen
# Befund darf ein noch nicht angesehenes rotes Ergebnis nicht stillschweigend
# wegwerfen.
POOL4="$(neues_pool gruen-zwei)"
HOME="$TESTHOME" bash -c "$FN"$'\n''pool_aufheben_oder_loeschen "$1" 0' _ "$POOL4"
if grep -q "ZWEITER-LAUF-MARKER" "$ZIEL/job0.out" 2>/dev/null; then
  ok "4: der liegengebliebene rote Lauf steht nach einem gruenen Folgelauf immer noch da"
else
  bad "4: ein gruener Folgelauf hat den vorherigen roten Befund geloescht"
fi

echo
echo "================================================================"
echo "PASS: $pass   FAIL: $fail"
[ "$fail" -eq 0 ]
