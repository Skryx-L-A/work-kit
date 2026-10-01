#!/usr/bin/env bash
# test-schranken-nicht-umgehbar.sh -- eine gesetzte Umgebungsvariable hebt keine
# Schranke auf.
#
# ANLASS: Sicherheits-Review der Spawner am 2026-09-21. Es fand dreimal dieselbe
# Bauform: eine Schutzpruefung liess sich durch eine Variable abschalten, die
# der Aufrufer selbst setzt.
#
#   1. Jede Pruefung wurde ueber "$HOME/.local/bin/…" gefunden, und HOME setzt
#      der Aufrufer. Mit einer eigenen Attrappe von `wb-mensch` (eine Zeile,
#      `exit 0`) galt ein Agent als Mensch -- damit fielen Effort-Deckel und
#      Ein-Worker-Sperre der kostenlosen Spur.
#   2. `WB_KONTINGENT_SKIP` uebersprang Kontingentpruefung und Ein-Worker-Sperre
#      ohne jede Gegenpruefung.
#   3. `WB_ENGINEX_OHNE_BELEGUNG` machte aus einer abgelehnten Speicherbuchung
#      eine Warnung -- rund 14,6 GiB ungebucht, und weg war die Sperre, die nach
#      der Kernel-Panik vom 2026-08-30 eingebaut wurde.
#
# Gemessen wird hier, was NICHT passieren darf: der Umgehungsversuch wird
# gefahren und muss scheitern. Ein Test, der nur den Normalfall prueft, waere
# gruen geblieben, waehrend die Luecke offen stand -- genau so ist sie
# entstanden.
#
# ISOLATION: eigenes HOME (mktemp), eigener tmux-Socket, keine Zeile in die
# lebende Konfiguration. Kein Worker wird gestartet: alle drei Faelle brechen
# vor dem Start ab, und genau das ist die Behauptung.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTHOME="$(mktemp -d "${TMPDIR:-/tmp}/schranken.XXXXXX")"
FALSCHHEIM="$(mktemp -d "${TMPDIR:-/tmp}/falschheim.XXXXXX")"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }
cleanup() {
  for d in "$TESTHOME" "$FALSCHHEIM"; do
    case "$d" in
      "${TMPDIR:-/tmp}"/schranken.*|"${TMPDIR:-/tmp}"/falschheim.*) rm -rf "$d" ;;
      *) echo "Aufraeumen uebersprungen: '$d' unerwartet" >&2 ;;
    esac
  done
}
trap cleanup EXIT

echo "== test-schranken-nicht-umgehbar: gesetzte Variablen heben keine Schranke auf =="
echo "   HOME des Laufs: $TESTHOME   untergeschobenes HOME: $FALSCHHEIM"
echo

# Das untergeschobene Heimatverzeichnis, wie ein Agent es baute: ein wb-mensch,
# das auf jede Frage Ja sagt.
mkdir -p "$FALSCHHEIM/.local/bin"
cat > "$FALSCHHEIM/.local/bin/wb-mensch" <<'EOF'
#!/bin/sh
# Attrappe: behauptet, der Aufruf komme von einem Menschen.
case "${1:-}" in
  beleg) printf 'quelle\tuntergeschoben\n' ;;
esac
exit 0
EOF
chmod +x "$FALSCHHEIM/.local/bin/wb-mensch"

echo "-- A: '--mensch' mit untergeschobenem HOME --"
# WICHTIG: ein Abbruch allein beweist hier NICHTS. Auch die luecken-behaftete
# Fassung endete ungleich 0 -- sie glaubte der Attrappe, lief weiter und
# scheiterte erst spaeter an der fehlenden Registry im untergeschobenen
# Heimatverzeichnis. Gemessen gegen genau diese Fassung: rc unterscheidet die
# beiden nicht, die ABLEHNUNG unterscheidet sie. Deshalb ist die Meldung die
# Behauptung und der Rueckgabewert nur die Begleitangabe.
AUS="$(HOME="$FALSCHHEIM" bash "$REPO/pi-worker" --mensch wprobe lmgamma /tmp 'nichts tun' 2>&1)"
RC=$?
if printf '%s' "$AUS" | grep -q -- "--mensch' abgelehnt" && [ "$RC" -ne 0 ]; then
  ok "A1: pi-worker lehnt die untergeschobene Menschen-Attrappe ausdruecklich ab (rc=$RC)"
else
  bad "A1: die Attrappe wurde nicht als solche abgelehnt (rc=$RC)" "$(printf '%s' "$AUS" | tr '\n' '|' | cut -c1-240)"
fi

echo
echo "-- B: dasselbe fuer wb-code (Orchestrator statt Worker) --"
AUS="$(HOME="$FALSCHHEIM" bash "$REPO/wb-code" --mensch --harness pi --model lmgamma-27b /tmp 2>&1)"
RC=$?
if printf '%s' "$AUS" | grep -q -- "--mensch' abgelehnt" && [ "$RC" -ne 0 ]; then
  ok "B1: wb-code lehnt die Attrappe ausdruecklich ab (rc=$RC)"
else
  bad "B1: die Attrappe wurde nicht als solche abgelehnt (rc=$RC)" "$(printf '%s' "$AUS" | tr '\n' '|' | cut -c1-240)"
fi

echo
echo "-- C: WB_ENGINEX_OHNE_BELEGUNG hebt die Speicherbuchung nicht mehr auf --"
# wb-belegung sagt Nein; frueher startete der Server trotzdem, sobald die
# Variable gesetzt war. Der Aufruf hier ist ein Agent (diese Testsitzung), also
# muss er abbrechen -- und zwar OHNE enginex zu starten.
mkdir -p "$TESTHOME/.local/bin"
cat > "$TESTHOME/.local/bin/wb-belegung" <<EOF
#!/bin/sh
case "\$1" in
  nimm) echo "gefragt" >> "$TESTHOME/buchung-versucht.log"
        echo "NEIN -- kein Platz (Attrappe)"; exit 1 ;;
  wer)  echo "Offene Belegungen: 0"; exit 0 ;;
  *)    exit 0 ;;
esac
EOF
cat > "$TESTHOME/.local/bin/enginex" <<EOF
#!/bin/sh
echo "GESTARTET \$*" >> "$TESTHOME/enginex-gestartet.log"
exit 0
EOF
cat > "$TESTHOME/.local/bin/wb-nohup" <<EOF
#!/bin/sh
echo "NOHUP \$*" >> "$TESTHOME/enginex-gestartet.log"
exit 0
EOF
cat > "$TESTHOME/.local/bin/wb-state" <<'EOF'
#!/bin/sh
# Nur die Felder, die der Enginex-Weg abfragt.
case "$*" in
  *"--field id"*)            echo "lmgamma-27b" ;;
  *"--field provider"*)      echo "enginex-lokal" ;;
  *"--field modelRef"*)      echo "incoai/Lmgamma-27B-Enginex" ;;
  *"--field gewichteGb"*)    echo "16.2" ;;
  *"--field contextWindow"*) echo "262144" ;;
esac
exit 0
EOF
# check-resources laeuft VOR der Buchung und bricht sonst schon dort ab -- dann
# haette dieser Abschnitt den richtigen Ausgang aus dem falschen Grund gemessen.
cat > "$TESTHOME/.local/bin/check-resources" <<'EOF'
#!/bin/sh
echo "frei: genug (Attrappe)"
exit 0
EOF
chmod +x "$TESTHOME/.local/bin/wb-belegung" "$TESTHOME/.local/bin/enginex" \
         "$TESTHOME/.local/bin/wb-nohup" "$TESTHOME/.local/bin/wb-state" \
         "$TESTHOME/.local/bin/check-resources"
: > "$TESTHOME/enginex-gestartet.log"; : > "$TESTHOME/buchung-versucht.log"
# Aufruf ueber `bash <datei>`, nicht ueber das Ausfuehrungsrecht: sonst haengt
# der Ausgang am Dateimodus, und ein fehlendes x-Bit meldet "abgebrochen" fuer
# einen Lauf, der nie stattgefunden hat (genau das passierte beim ersten
# Messen dieser Suite gegen die alte Fassung).
# EIGENER PORT (WB_ENGINEX_PORT): ohne ihn fragt dieser Abschnitt den LEBENDEN
# Server auf 8000. Gemessen am 21.09.: solange keiner lief, war der Test
# gruen; sobald Orchestrator des Nutzers einen hielt, meldete ensure "laeuft
# bereits" und kam nie bis zur Buchung -- drei Punkte rot, ohne dass am Code
# etwas falsch war. Der Test mass die Maschine statt des Codes.
if [ -f "$REPO/wb-enginex-server" ]; then  # Kit: private Enginex lane not shipped
AUS="$(HOME="$TESTHOME" WB_ENGINEX_OHNE_BELEGUNG=1 WB_ENGINEX_PORT=8765 \
       PATH="$TESTHOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
       bash "$REPO/wb-enginex-server" ensure lmgamma-27b 2>&1)"
RC=$?
# Die Buchung MUSS versucht worden sein -- sonst misst der Abschnitt einen
# Abbruch weiter vorne und nicht die Notluke.
if [ -s "$TESTHOME/buchung-versucht.log" ]; then
  ok "C1: der Lauf kam bis zur Speicherbuchung (sonst wuerde C2/C3 nichts beweisen)"
else
  bad "C1: wb-belegung wurde nie gefragt — der Abbruch liegt woanders" "$(printf '%s' "$AUS" | tr '\n' '|' | cut -c1-240)"
fi
if [ -s "$TESTHOME/enginex-gestartet.log" ] || [ "$RC" -eq 0 ]; then
  bad "C2: trotz abgelehnter Buchung gestartet (rc=$RC)" "$(head -1 "$TESTHOME/enginex-gestartet.log")"
else
  ok "C2: kein Startversuch (rc=$RC) -- die 14,6 GiB werden nicht ungebucht belegt"
fi
if printf '%s' "$AUS" | grep -q "WB_ENGINEX_OHNE_BELEGUNG ignoriert"; then
  ok "C3: der ignorierte Schalter wird laut gemeldet, nicht still verschluckt"
else
  bad "C3: keine Meldung ueber den ignorierten Schalter" "$(printf '%s' "$AUS" | tr '\n' '|' | cut -c1-200)"
fi
else
  ok "C: wb-enginex-server gehoert nicht zum Kit -- Abschnitt entfaellt"
fi

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
