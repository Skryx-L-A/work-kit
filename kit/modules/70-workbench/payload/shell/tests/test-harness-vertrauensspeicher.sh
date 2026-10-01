#!/usr/bin/env bash
# test-harness-vertrauensspeicher.sh — der Eintrag, der die Vertrauensfrage vorab beantwortet.
#
# agy fragt beim ersten Start in einem Verzeichnis "Do you trust the contents of this
# project?" und zeigt seine Eingabezeile erst danach — auch mit
# --dangerously-skip-permissions, und vererbt wird die Antwort nicht. Weil jeder Worker
# einen frischen Arbeitsbaum bekommt, faellt die Frage bei jedem Spawn an. wb-harness-run
# beantwortet sie vorher, indem es das Arbeitsverzeichnis in die Liste eintraegt, die der
# CLI selbst fuehrt (harness.trustStore).
#
# Geprueft wird der ECHTE Rumpf aus shell/wb-harness-run — er wird hier herausgeloest und
# befragt, nach demselben Muster wie test-harness-wege.sh die Funktion pane_harness. Eine
# zweite Kopie in dieser Datei waere genau die Doppelung, die auseinanderlaeuft.
#
#   1  Ein neuer Pfad wird angehaengt, alle uebrigen Schluessel bleiben stehen.
#   2  Derselbe Pfad ein zweites Mal legt keinen zweiten Eintrag an.
#   3  Fehlt die Datei, wird das gesagt und NICHTS angelegt — der Dialog kommt dann beim
#      Start, das readyPattern trifft ihn nicht, und der Spawn scheitert sichtbar. Das ist
#      der gewollte Ausgang; eine erfundene Konfiguration waere schlimmer.
#   4  Ist der Schluessel keine Liste, bleibt die Datei unveraendert.
#   5  Ein Harness ohne trustStore laesst alles in Ruhe.
#
# Der zweite Stil (2026-08-08) ist codex: kein JSON, sondern ein TOML-Abschnitt je Pfad in
# ~/.codex/config.toml. Dort liegen auch Anmeldungsbezuege und Einstellungen, deshalb wird
# nur ANGEHAENGT und im Zweifel gar nichts geschrieben.
#   6  Der Abschnitt wird angehaengt, der Rest der Datei steht unveraendert davor.
#   7  Ein vorhandener Abschnitt bleibt in Ruhe — kein zweiter, keine Aenderung.
#   8  Fremde Schluessel und Abschnitte werden nicht angefasst.
#   9  Der Pfad wird gequotet, damit Punkte und Leerzeichen darin keine Unterabschnitte
#      werden, und in der Schreibweise eingetragen, die pathForm verlangt (codex: aufgeloest).
#  10  Steht der Pfad in einer Schreibweise da, die der Deuter nicht als Abschnitt erkennt,
#      wird NICHTS angehaengt: eine zweite Definition waere ungueltiges TOML.
#  11  Ist die Tabelle gar keine Tabelle, sondern ein Wert, wird ebenfalls nichts angehaengt.
#  12  Fehlt die Datei, gilt dasselbe wie bei 3.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTHOME="$(mktemp -d)"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT

echo "== test-harness-vertrauensspeicher =="

# Der Rumpf ist das Here-Dokument in wb-harness-run, das trustStore auswertet.
RUMPF="$TESTHOME/vertrauen.py"
awk '
  /<<.PY./       { drin=1; buf=""; next }
  drin && /^PY$/ { if (buf ~ /trustStore/) { printf "%s", buf; exit } drin=0; next }
  drin           { buf = buf $0 "\n" }
' "$REPO/wb-harness-run" > "$RUMPF"
[ -s "$RUMPF" ] || { echo "  FAIL  Rumpf in wb-harness-run nicht gefunden"; exit 1; }
ok "Rumpf aus wb-harness-run herausgeloest"

ZIEL="$TESTHOME/settings.json"
H='{"id":"agy","trustStore":{"style":"json-array","file":"'"$ZIEL"'","key":"trustedWorkspaces"}}'
lauf() { /usr/bin/python3 "$RUMPF" "$1" "$2" 2>&1; }
frage() { /usr/bin/python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
print(json.dumps(d.get(sys.argv[2])), 'telemetrie=' + str(d.get('enableTelemetry')))
" "$ZIEL" trustedWorkspaces; }

printf '%s\n' '{"enableTelemetry": false, "trustedWorkspaces": ["/Users/x/AI"]}' > "$ZIEL"
lauf "$H" /Users/x/worktrees/w1 >/dev/null
IST="$(frage)"
case "$IST" in
  *'"/Users/x/AI", "/Users/x/worktrees/w1"'*telemetrie=False*)
    ok "1: Pfad angehaengt, uebrige Schluessel stehen noch" ;;
  *) bad "1: unerwartet: $IST" ;;
esac

lauf "$H" /Users/x/worktrees/w1 >/dev/null
ANZ="$(/usr/bin/python3 -c "import json;print(len(json.load(open('$ZIEL'))['trustedWorkspaces']))")"
[ "$ANZ" = 2 ] && ok "2: derselbe Pfad legt keinen zweiten Eintrag an" \
               || bad "2: $ANZ Eintraege statt 2"

HFEHLT='{"id":"agy","trustStore":{"style":"json-array","file":"'"$TESTHOME/gibtsnicht.json"'","key":"trustedWorkspaces"}}'
AUS="$(lauf "$HFEHLT" /tmp/x)"
if printf '%s' "$AUS" | grep -q 'gibt es nicht' && [ ! -e "$TESTHOME/gibtsnicht.json" ]; then
  ok "3: fehlende Datei wird gemeldet und nicht angelegt"
else
  bad "3: unerwartet: $AUS"
fi

printf '%s\n' '{"trustedWorkspaces": "kaputt"}' > "$ZIEL"
AUS="$(lauf "$H" /tmp/x)"
if printf '%s' "$AUS" | grep -q 'keine Liste' \
   && grep -q '"kaputt"' "$ZIEL"; then
  ok "4: kein Listen-Schluessel — Datei bleibt unveraendert"
else
  bad "4: unerwartet: $AUS"
fi

AUS="$(lauf '{"id":"claude"}' /tmp/x)"
[ -z "$AUS" ] && ok "5: Harness ohne trustStore sagt und tut nichts" \
              || bad "5: unerwartet: $AUS"

# ---- Stil 2: toml-section (codex) -------------------------------------------
TZIEL="$TESTHOME/config.toml"
HT='{"id":"codex","trustStore":{"style":"toml-section","file":"'"$TZIEL"'","table":"projects","key":"trust_level","value":"trusted","pathForm":"resolved"}}'
# pathForm "resolved" heisst: eingetragen wird der aufgeloeste Pfad, weil codex ihn selbst
# aufloest, bevor er ihn hinschreibt. Der Test rechnet ihn genauso aus, statt /private/var
# fest hineinzuschreiben — auf Linux gibt es diesen Umweg nicht.
aufgeloest() { /usr/bin/python3 -c "import os,sys;print(os.path.realpath(sys.argv[1]))" "$1"; }
mkdir -p "$TESTHOME/echt"
ln -s "$TESTHOME/echt" "$TESTHOME/link"

urzustand() { cat > "$TZIEL" <<'TOML'
[projects."/Users/x/AI"]
trust_level = "trusted"

[notice.model_migrations]
"gpt-5.4-mini" = "gpt-5.6-luna"
TOML
}
urzustand
VOR="$TESTHOME/vorher.toml"; cp "$TZIEL" "$VOR"
P6="$TESTHOME/w1"; R6="$(aufgeloest "$P6")"
lauf "$HT" "$P6" >/dev/null
if [ "$(head -n "$(wc -l < "$VOR")" "$TZIEL")" = "$(cat "$VOR")" ] \
   && grep -qF "[projects.\"$R6\"]" "$TZIEL" \
   && [ "$(grep -c 'trust_level = "trusted"' "$TZIEL")" = 2 ]; then
  ok "6: Abschnitt angehaengt, alles Bisherige steht unveraendert davor"
else
  bad "6: unerwartet:"$'\n'"$(cat "$TZIEL")"
fi

SUMME="$(md5 -q "$TZIEL" 2>/dev/null || md5sum "$TZIEL" | cut -d' ' -f1)"
lauf "$HT" "$P6" >/dev/null
SUMME2="$(md5 -q "$TZIEL" 2>/dev/null || md5sum "$TZIEL" | cut -d' ' -f1)"
[ "$SUMME" = "$SUMME2" ] && ok "7: vorhandener Abschnitt bleibt in Ruhe, kein zweiter" \
                         || bad "7: Datei hat sich beim zweiten Lauf geaendert"

if grep -q '\[notice.model_migrations\]' "$TZIEL" \
   && grep -qF '"gpt-5.4-mini" = "gpt-5.6-luna"' "$TZIEL" \
   && grep -qF '[projects."/Users/x/AI"]' "$TZIEL"; then
  ok "8: fremde Abschnitte und Schluessel unangetastet"
else
  bad "8: fremder Inhalt verloren:"$'\n'"$(cat "$TZIEL")"
fi

P9="$TESTHOME/link/mein worker.v2"; R9="$(aufgeloest "$P9")"
lauf "$HT" "$P9" >/dev/null
printf '%s\n' '{"trustedWorkspaces": []}' > "$ZIEL"
lauf "$H" "$P9" >/dev/null
if [ "$R9" != "$P9" ] && grep -qF "[projects.\"$R9\"]" "$TZIEL" \
   && ! grep -qF "$P9" "$TZIEL" \
   && /usr/bin/python3 -c "
import json,sys
sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1]))['trustedWorkspaces'] else 1)" "$ZIEL" "$P9"; then
  ok "9: Punkt und Leerzeichen gequotet, Pfad aufgeloest — json-array bleibt beim logischen"
else
  bad "9: unerwartet: R9=$R9"$'\n'"$(cat "$TZIEL")"
fi

urzustand
printf '%s\n' '[projects]' "\"$R6\" = { trust_level = \"trusted\" }" >> "$TZIEL"
SUMME="$(md5 -q "$TZIEL" 2>/dev/null || md5sum "$TZIEL" | cut -d' ' -f1)"
AUS="$(lauf "$HT" "$P6")"
SUMME2="$(md5 -q "$TZIEL" 2>/dev/null || md5sum "$TZIEL" | cut -d' ' -f1)"
if printf '%s' "$AUS" | grep -q 'steht schon in' && [ "$SUMME" = "$SUMME2" ]; then
  ok "10: nicht deutbare Schreibweise — nichts angehaengt, Datei unveraendert"
else
  bad "10: unerwartet: $AUS"
fi

printf '%s\n' 'projects = 5' > "$TZIEL"
AUS="$(lauf "$HT" "$P6")"
if printf '%s' "$AUS" | grep -q 'keine Tabelle' && [ "$(cat "$TZIEL")" = 'projects = 5' ]; then
  ok "11: Tabelle ist ein Wert — nichts angehaengt"
else
  bad "11: unerwartet: $AUS"
fi

HTFEHLT='{"id":"codex","trustStore":{"style":"toml-section","file":"'"$TESTHOME/kein.toml"'","table":"projects","key":"trust_level","value":"trusted","pathForm":"resolved"}}'
AUS="$(lauf "$HTFEHLT" "$P6")"
if printf '%s' "$AUS" | grep -q 'gibt es nicht' && [ ! -e "$TESTHOME/kein.toml" ]; then
  ok "12: fehlende Datei wird gemeldet und nicht angelegt"
else
  bad "12: unerwartet: $AUS"
fi

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
