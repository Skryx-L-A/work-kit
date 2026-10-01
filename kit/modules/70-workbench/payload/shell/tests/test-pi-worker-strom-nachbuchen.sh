#!/usr/bin/env bash
# test-pi-worker-strom-nachbuchen.sh -- ein WIEDERVERWENDETER Pane muss
# nachsehen, ob seine eigene Strom-Buchung noch im Buch steht, und sonst
# nachbuchen (Nachtrag 2026-09-08, ZWEITE RUNDE, Auftrag "buchung", Risiko 9).
#
# DER BEFUND: "── Eigene Sequenz buchen" in shell/pi-worker liess einen
# wiederverwendeten Pane bisher UNBEDINGT ohne Buchung durch -- das setzt
# still voraus, dass seine URSPRUENGLICHE Strom-Buchung noch im Buch steht.
# Sie kann aber verfallen sein (Frist ohne 'uebernehmen', ein zwischen-
# zeitliches 'wb-belegung aufraeumen', ein von Hand freigegebener Eintrag) --
# dann fehlt genau dieser Strom in wb-mlx-servers gebuchte_sequenzen_summe(),
# und kapazitaet_pruefen() unterschaetzt den wirklichen Bedarf. GEMESSEN wird
# hier NICHT, ob das im echten Betrieb genau so passiert (dafuer braeuchte es
# einen echten, langlebigen Worker-Pane ueber mehrere Auftraege) -- sondern
# die ENTSCHEIDUNG selbst: findet die Pruefung eine noch gueltige eigene
# Buchung, wird nicht nachgebucht; findet sie keine, schon.
#
# GEPRUEFT WIRD DIE ECHTE FUNKTION, nicht eine Nachstellung: das Python-
# Fragment aus pi-worker ("EIGENE_STROM_STEHT=...") wird WORTWOERTLICH aus
# der Datei extrahiert (kein Abtippen) und gegen ein gestelltes
# 'wb-belegung wer --json' ausgefuehrt -- kein echter wb-belegung-Aufruf,
# kein echtes Modell, kein echter Worker-Spawn.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${WB_PI_WORKER:-$REPO/pi-worker}"
echo "Geprueft: $TOOL"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }

START_ANKER='EIGENE_STROM_STEHT="$("$HOME/.local/bin/wb-belegung" wer --json 2>/dev/null | python3 -c '\'''
ENDE_ANKER='"$BMODELL" 2>/dev/null)"'

START_ZEILE="$(grep -nF "$START_ANKER" "$TOOL" | head -1 | cut -d: -f1)"
ENDE_ZEILE="$(grep -nF "$ENDE_ANKER" "$TOOL" | head -1 | cut -d: -f1)"
case "$START_ZEILE" in ''|*[!0-9]*) echo "FEHLER: Start-Anker nicht gefunden -- Textanker in $TOOL pruefen." >&2; exit 1 ;; esac
case "$ENDE_ZEILE" in ''|*[!0-9]*) echo "FEHLER: Ende-Anker nicht gefunden -- Textanker in $TOOL pruefen." >&2; exit 1 ;; esac
PY_START=$((START_ZEILE + 1))
PY_ENDE=$((ENDE_ZEILE - 1))

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PY_DATEI="$WORK/fragment.py"
sed -n "${PY_START},${PY_ENDE}p" "$TOOL" > "$PY_DATEI"
if [ ! -s "$PY_DATEI" ]; then
  echo "FEHLER: $PY_DATEI ist leer -- Zeilenbereich $PY_START..$PY_ENDE in $TOOL pruefen." >&2
  exit 1
fi

pruefen() {   # <bezeichnung> <buch-json> <TMUX_PANE> <modell> <erwartet: ja|leer>
  local bez="$1" buch="$2" pane="$3" modell="$4" erwartet="$5"
  local aus
  aus="$(printf '%s' "$buch" | TMUX_PANE="$pane" python3 "$PY_DATEI" "$modell" 2>&1)"
  if [ "$erwartet" = ja ]; then
    if [ "$aus" = ja ]; then
      ok "$bez: meldet 'ja' -- die eigene Strom-Buchung steht noch, keine Nachbuchung"
    else
      bad "$bez: erwartet 'ja'" "$aus"
    fi
  else
    if [ -z "$aus" ]; then
      ok "$bez: meldet nichts -- keine eigene Strom-Buchung gefunden, pi-worker muesste nachbuchen"
    else
      bad "$bez: erwartet leere Ausgabe (nachbuchen noetig)" "$aus"
    fi
  fi
}

echo "== 1  eigene Strom-Buchung steht noch (gleicher Pane, gleiches Modell, zweck pi-worker:) =="
BUCH1='{"belegungen": [{"modell": "lmgamma-27b-mlx-4bit", "zweck": "pi-worker:eins", "halter": {"pane": "%1"}}]}'
pruefen "1" "$BUCH1" "%1" "lmgamma-27b-mlx-4bit" ja

echo "== 2  keine Buchung fuer dieses Modell -- nachbuchen noetig =="
pruefen "2" "$BUCH1" "%1" "ein-anderes-modell" leer

echo "== 3  Buchung existiert, aber unter einem ANDEREN Pane -- nachbuchen noetig (nicht MEIN Strom) =="
pruefen "3" "$BUCH1" "%2" "lmgamma-27b-mlx-4bit" leer

echo "== 4  Buchung existiert, aber mit zweck OHNE 'pi-worker:'-Praefix (z.B. die Server-eigene Basisstrom-Buchung) -- zaehlt NICHT als eigene Worker-Buchung =="
BUCH4='{"belegungen": [{"modell": "lmgamma-27b-mlx-4bit", "zweck": "wb-mlx-server: MLX-Server fuer lmgamma-27b-mlx-4bit (kein Alias), Port 8081", "halter": {"pane": "%1"}}]}'
pruefen "4" "$BUCH4" "%1" "lmgamma-27b-mlx-4bit" leer

echo "== 5  eine TOTE Buchung zaehlt nicht als noch stehend -- nachbuchen noetig =="
BUCH5='{"belegungen": [{"modell": "lmgamma-27b-mlx-4bit", "zweck": "pi-worker:eins", "halter": {"pane": "%1"}, "_zustand": "tot"}]}'
pruefen "5" "$BUCH5" "%1" "lmgamma-27b-mlx-4bit" leer

echo "== 6  kein TMUX_PANE gesetzt -- nie faelschlich 'ja' behaupten (kein Eigentumsnachweis moeglich) =="
pruefen "6" "$BUCH1" "" "lmgamma-27b-mlx-4bit" leer

echo
echo "Ergebnis: $pass ok, $fail FAIL"
[ "$fail" -eq 0 ]
