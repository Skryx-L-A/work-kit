#!/usr/bin/env bash
# test-wb-profil.sh -- Rollenprofile des Agents-Features (Bau-Schritt 1,
# AUFTRAG-agents1.md, Abschnitt 4 "Tests", nachgezogen um die
# Reviewer-Befunde aus ~/.pi-workers/results/agents1rev/20260910-173842.md,
# Auftrag Nr. 2): Positivliste (inkl. Skalar-statt-Liste), gesperrte
# Werkzeuge (gehaertet: Gross-/Kleinschreibung, Unicode, killall/msmtp/mailx,
# Pfad-Basisnamen), Stufen-Deckel und Freigabe-Pruefung fuer JEDEN Absender
# (auch "person-1", der jetzt selbst einen Menschen-Beleg braucht), Projekt
# ueberlagert global, `behalten` prueft und schuetzt vor stillem
# Ueberschreiben, `verwerfen` bei arbeitendem Worker, `hinzufuegen` kopiert
# ein Team ohne zu ueberschreiben, JEDE Datei der Bibliothek (Rollen UND
# Teams) besteht `pruefen`, `spawn-argumente` prueft selbst vor und liefert
# nie Einzelzeichen, die Testbett-Bindung von `--mensch-beleg`, deutsche
# Meldungswege, und der Rundtrip von Listenelementen mit Sonderzeichen.
#
# KEIN MODELLAUFRUF, KEIN TMUX, KEIN NETZ -- reine Dateipruefung, dieselbe
# Bauart wie test-wb-aufgabe.sh: TESTHOME (fuer $HOME, mit einem Schirm-
# `wb-mensch`, der IMMER 1 zurueckgibt) und eine GLEICHRANGIGE, eigene BASIS
# fuer --base/--vorrat -- seit Reviewer-Befund 7 gilt --mensch-beleg nur,
# wenn diese Wurzeln ausserhalb des (simulierten) echten HOME liegen.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WURZEL="$(cd "$REPO/.." && pwd)"
MARKE="p$(date +%s)$$$RANDOM"
TESTHOME="$(mktemp -d "${TMPDIR:-/tmp}/wb-profil-test.XXXXXX")"
BASIS="$(mktemp -d "${TMPDIR:-/tmp}/wb-profil-basis.XXXXXX")"
PYBIN_DIR="$(dirname "$(command -v python3)")"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

cleanup() {
  case "$TESTHOME" in
    /tmp/wb-profil-test.*|/private/tmp/wb-profil-test.*|/var/folders/*/wb-profil-test.*)
      rm -rf "$TESTHOME" ;;
    *) echo "WARNUNG: TESTHOME='$TESTHOME' sieht nicht nach einem Testverzeichnis aus -- NICHT geloescht." >&2 ;;
  esac
  case "$BASIS" in
    /tmp/wb-profil-basis.*|/private/tmp/wb-profil-basis.*|/var/folders/*/wb-profil-basis.*)
      rm -rf "$BASIS" ;;
    *) echo "WARNUNG: BASIS='$BASIS' sieht nicht nach einem Testverzeichnis aus -- NICHT geloescht." >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

echo "== wb-profil (HOME $TESTHOME, BASIS $BASIS, Marke $MARKE) =="

[ -x "$REPO/wb-profil" ] || { echo "UEBERSPRUNGEN: shell/wb-profil fehlt oder ist nicht ausfuehrbar"; exit 77; }
[ -x "$REPO/wb-aufgabe" ] || { echo "UEBERSPRUNGEN: shell/wb-aufgabe fehlt (fuer den --aufgabe-Teil noetig)"; exit 77; }

BASE="$BASIS/home"
VORRAT="$BASIS/vorrat"
PROJ="$BASIS/projekt-$MARKE"
BELEG="$BASIS/beleg.txt"
mkdir -p "$BASE" "$VORRAT" "$PROJ" "$TESTHOME/.local/bin"
printf 'mensch\tTest-Beleg %s\n' "$MARKE" > "$BELEG"

cat > "$TESTHOME/.local/bin/wb-mensch" <<'SHIMEOF'
#!/bin/sh
case "$1" in
  beleg) printf 'agent\tSchirm fuer test-wb-profil.sh, immer kein Mensch\n'; exit 0 ;;
  *) exit 1 ;;
esac
SHIMEOF
chmod +x "$TESTHOME/.local/bin/wb-mensch"

wp() {
  env HOME="$TESTHOME" PATH="$PYBIN_DIR:/usr/bin:/bin" TMUX= TMUX_PANE= \
      python3 "$REPO/wb-profil" "$@" --base "$BASE" --vorrat "$VORRAT" 2>&1
}
wa() {
  env HOME="$TESTHOME" PATH="$PYBIN_DIR:/usr/bin:/bin" TMUX= TMUX_PANE= \
      python3 "$REPO/wb-aufgabe" "$@" --vorrat "$VORRAT" --base "$BASE" 2>&1
}
# Nur fuer die Testbett-Sektion: --base zeigt auf TESTHOME selbst (simuliert "echtes HOME").
wp_echtes_home() {
  env HOME="$TESTHOME" PATH="$PYBIN_DIR:/usr/bin:/bin" TMUX= TMUX_PANE= \
      python3 "$REPO/wb-profil" "$@" --base "$TESTHOME" --vorrat "$TESTHOME/vorrat-echthome" 2>&1
}

echo
echo "-- 1: Positivliste -- ein Feld 'model' ist ein Verstoss --"
mkdir -p "$BASIS/direkt"
cat > "$BASIS/direkt/kaputt-$MARKE.md" <<EOF
---
name: kaputt-$MARKE
description: x
tools:
  - Bash
model: opus5
stufe: mitglied
absender: person-1
stand: behalten
---
Text
EOF
AUS1="$(wp pruefen "$BASIS/direkt/kaputt-$MARKE.md")"
RC1=$?
[ "$RC1" -eq 2 ] && ok "1: ein Profil mit Feld 'model' faellt bei pruefen durch (Exit 2)" \
                 || bad "1: Exit-Code bei Positivliste-Verstoss" "rc=$RC1 -- $AUS1"
printf '%s' "$AUS1" | grep -qi "'model'" && ok "1: die Meldung nennt das Feld 'model'" \
                                          || bad "1: Meldungstext nennt 'model'" "$AUS1"

echo
echo "-- 1b: Listenfeld als Inline-String ist ein Verstoss, keine Zeichenkette (Befund 1) --"
cat > "$BASIS/direkt/inline-$MARKE.md" <<EOF
---
name: inline-$MARKE
description: x
tools: Bash, wb-mail, kill
stufe: mitglied
absender: person-1
stand: behalten
---
Text
EOF
AUS1B="$(wp pruefen "$BASIS/direkt/inline-$MARKE.md")"
RC1B=$?
[ "$RC1B" -eq 2 ] && ok "1b: 'tools: Bash, wb-mail, kill' (kein YAML, ein Skalar) -> Exit 2" \
                  || bad "1b: Exit-Code bei Skalar statt Liste" "rc=$RC1B -- $AUS1B"
printf '%s' "$AUS1B" | grep -qi "liste" && ok "1b: die Meldung sagt, dass eine Liste erwartet wird" \
                                          || bad "1b: Meldungstext nennt 'Liste'" "$AUS1B"

echo
echo "-- 2: gesperrtes Werkzeug wird bei anlegen abgelehnt --"
AUS2="$(wp anlegen "boese-$MARKE" --bereich x --stufe mitglied --tools Bash --bash "rm -rf /tmp/x" --absender person-1 --mensch-beleg "$BELEG")"
RC2=$?
[ "$RC2" -eq 2 ] && ok "2: anlegen mit 'rm -rf' im bash-Feld -> Exit 2" || bad "2: gesperrtes Werkzeug" "rc=$RC2 -- $AUS2"
[ ! -e "$BASE/.claude/workbench/rollen/boese-$MARKE.md" ] \
  && ok "2: es wurde nichts geschrieben" || bad "2: trotz Ablehnung wurde eine Datei angelegt"

echo
echo "-- 2b: --absender person-1 braucht selbst einen Menschen-Beleg (Befund 2) --"
AUS2B="$(wp anlegen "agent-chef-$MARKE" --bereich x --stufe hauptagent --tools "Bash,Read,wb-shot" --bash "claude --model fable5" --absender person-1)"
RC2B=$?
[ "$RC2B" -eq 2 ] && ok "2b: --absender person-1 OHNE Menschen-Beleg -> Exit 2 (selbst mit Stufe hauptagent + wb-shot/Fable)" \
                  || bad "2b: person-1 ohne Beleg" "rc=$RC2B -- $AUS2B"
[ ! -e "$BASE/.claude/workbench/rollen/agent-chef-$MARKE.md" ] \
  && ok "2b: es wurde nichts geschrieben" || bad "2b: trotz fehlendem Beleg wurde eine Datei angelegt"

AUS2C="$(wp anlegen "agent-chef-ok-$MARKE" --bereich x --stufe hauptagent --tools "Bash,Read" --absender person-1 --mensch-beleg "$BELEG")"
RC2C=$?
[ "$RC2C" -eq 0 ] && ok "2b: --absender person-1 MIT Beleg und Stufe hauptagent geht weiterhin (Auftrag Nr. 2, Punkt 2)" \
                  || bad "2b: person-1 mit Beleg, Stufe hauptagent" "rc=$RC2C -- $AUS2C"

echo
echo "-- 3: Stufe 'hauptagent' vom Hauptagenten abgelehnt --"
IDAUS="$(wa anlegen "$PROJ" --ziel "Profiltest $MARKE" --fertig x)"
ID="$(printf '%s' "$IDAUS" | tail -1)"
AUS3="$(wp anlegen "boss-$MARKE" --bereich x --stufe hauptagent --tools Bash \
        --absender "hauptagent:$ID:2026-09-10" --aufgabe "$ID")"
RC3=$?
[ "$RC3" -eq 2 ] && ok "3: eine vom Hauptagenten angelegte Rolle mit Stufe 'hauptagent' -> Exit 2" \
                 || bad "3: Stufen-Deckel" "rc=$RC3 -- $AUS3"

echo
echo "-- 4: Freigabe ueber die Aufgabe hinaus wird abgelehnt -- fuer JEDEN Absender (Befund 2) --"
AUS4="$(wp anlegen "fabler-$MARKE" --bereich x --stufe mitglied --tools Bash --bash "claude --model fable5" \
        --absender "hauptagent:$ID:2026-09-10" --aufgabe "$ID")"
RC4=$?
[ "$RC4" -eq 2 ] && ok "4: eine hauptagent-Rolle, die Fable nennt, ohne dass die Aufgabe die Freigabe traegt -> Exit 2" \
                 || bad "4: Freigabe-ueber-Aufgabe-hinaus (hauptagent)" "rc=$RC4 -- $AUS4"

AUS4L="$(wp anlegen "fabler-person-1-$MARKE" --bereich x --stufe hauptagent --tools Bash --bash "claude --model fable5" \
        --absender person-1 --aufgabe "$ID" --mensch-beleg "$BELEG")"
RC4L=$?
[ "$RC4L" -eq 2 ] && ok "4: dieselbe Freigabe-Pruefung greift jetzt AUCH bei --absender person-1 + --aufgabe (Befund 2)" \
                   || bad "4: Freigabe-ueber-Aufgabe-hinaus (person-1)" "rc=$RC4L -- $AUS4L"

echo
echo "-- 4b: mit der Freigabe klappt dieselbe Rolle --"
IDF_AUS="$(wa anlegen "$PROJ" --ziel "Profiltest mit Fable $MARKE" --fertig x --freigabe fable)"
IDF="$(printf '%s' "$IDF_AUS" | tail -1)"
AUS4B="$(wp anlegen "fabler-ok-$MARKE" --bereich x --stufe mitglied --tools Bash --bash "claude --model fable5" \
        --absender "hauptagent:$IDF:2026-09-10" --aufgabe "$IDF")"
RC4B=$?
[ "$RC4B" -eq 0 ] && ok "4b: dieselbe Rolle geht durch, sobald die Aufgabe 'fable' freigibt" \
                  || bad "4b: mit Freigabe" "rc=$RC4B -- $AUS4B"

echo
echo "-- 5: Projekt ueberlagert global --"
wp anlegen "ueberlagert-$MARKE" --bereich "global" --stufe mitglied --tools Bash --absender person-1 --mensch-beleg "$BELEG" >/dev/null
wp anlegen "ueberlagert-$MARKE" --bereich "projekt" --stufe mitglied --tools Bash --absender person-1 --mensch-beleg "$BELEG" --projekt "$PROJ" >/dev/null
AUS5="$(wp liste --projekt "$PROJ" --json)"
RC5=$?
[ "$RC5" -eq 0 ] && ok "5: liste --projekt endet mit Exit 0" || bad "5: liste --projekt Exit-Code" "rc=$RC5"
HERKUNFT="$(printf '%s' "$AUS5" | python3 -c "
import json, sys
d = json.load(sys.stdin)
treffer = [e for e in d if e['name'] == 'ueberlagert-$MARKE']
print(treffer[0]['herkunft'] if treffer else 'FEHLT')
")"
[ "$HERKUNFT" = "projekt" ] && ok "5: die Projektfassung ueberlagert die globale in der Liste" \
                             || bad "5: Herkunft in der Liste" "'$HERKUNFT'"
BEREICH_WIRKSAM="$(python3 -c "
import re
inhalt = open('$PROJ/.werkbank/rollen/ueberlagert-$MARKE.md', encoding='utf-8').read()
m = re.search(r'^description: (.*)\$', inhalt, re.M)
print(m.group(1) if m else 'FEHLT')
")"
[ "$BEREICH_WIRKSAM" = "projekt" ] && ok "5: die Projektdatei traegt wirklich den Projekt-Bereich" \
                                     || bad "5: Inhalt der Projektdatei" "'$BEREICH_WIRKSAM'"

echo
echo "-- 6: 'verwerfen' bei arbeitendem Worker wird abgelehnt --"
wp anlegen "wird-verworfen-$MARKE" --bereich x --stufe mitglied --tools Bash \
   --absender "hauptagent:$ID:2026-09-10" --aufgabe "$ID" >/dev/null
wa worker "$ID" setzen "worker1-$MARKE" --rolle "wird-verworfen-$MARKE" --zustand arbeitet >/dev/null
AUS6A="$(wp verwerfen "wird-verworfen-$MARKE" --aufgabe "$ID" --mensch-beleg "$BELEG")"
RC6A=$?
[ "$RC6A" -eq 2 ] && ok "6: verwerfen mit arbeitendem Worker -> Exit 2" || bad "6: verwerfen blockiert" "rc=$RC6A -- $AUS6A"
[ -f "$PROJ/.companion/auftraege/$ID.rollen/wird-verworfen-$MARKE.md" ] \
  && ok "6: die vorlaeufige Rolle liegt noch da" || bad "6: vorlaeufige Rolle faelschlich geloescht"

wa worker "$ID" entfernen "worker1-$MARKE" >/dev/null
AUS6B="$(wp verwerfen "wird-verworfen-$MARKE" --aufgabe "$ID" --mensch-beleg "$BELEG")"
RC6B=$?
[ "$RC6B" -eq 0 ] && ok "6: ohne arbeitenden Worker klappt verwerfen (Exit 0)" || bad "6: verwerfen nach Entfernen" "rc=$RC6B -- $AUS6B"
[ ! -f "$PROJ/.companion/auftraege/$ID.rollen/wird-verworfen-$MARKE.md" ] \
  && ok "6: die vorlaeufige Rolle ist jetzt weg" || bad "6: vorlaeufige Rolle liegt noch da"

echo
echo "-- 6b: 'behalten' prueft und ueberschreibt nie still (Befund 4) --"
wp anlegen "wird-behalten-$MARKE" --bereich x --stufe mitglied --tools Bash \
   --absender "hauptagent:$ID:2026-09-10" --aufgabe "$ID" >/dev/null
VORLAEUFIGE_DATEI="$PROJ/.companion/auftraege/$ID.rollen/wird-behalten-$MARKE.md"
python3 - "$VORLAEUFIGE_DATEI" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
t = t.replace("tools:\n  - Bash", "tools:\n  - Bash\n  - wb-mail")
open(p, "w", encoding="utf-8").write(t)
PY
AUS6C_BAD="$(wp behalten "wird-behalten-$MARKE" --aufgabe "$ID" --mensch-beleg "$BELEG")"
RC6C_BAD=$?
[ "$RC6C_BAD" -eq 2 ] && ok "6b: behalten prueft die vorlaeufige Datei zuerst -- manipuliert (wb-mail) -> Exit 2" \
                       || bad "6b: behalten mit manipulierter Datei" "rc=$RC6C_BAD -- $AUS6C_BAD"
[ ! -f "$BASE/.claude/workbench/rollen/wird-behalten-$MARKE.md" ] \
  && ok "6b: nichts wurde global geschrieben, trotz der Ablehnung" \
  || bad "6b: behalten hat trotz Verstoss global geschrieben"

# von Hand reparieren, dann darf es klappen
python3 - "$VORLAEUFIGE_DATEI" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
t = t.replace("tools:\n  - Bash\n  - wb-mail", "tools:\n  - Bash")
open(p, "w", encoding="utf-8").write(t)
PY
AUS6C="$(wp behalten "wird-behalten-$MARKE" --aufgabe "$ID" --mensch-beleg "$BELEG")"
RC6C=$?
[ "$RC6C" -eq 0 ] && ok "6b: behalten mit Menschen-Beleg -> Exit 0 (nach der Reparatur)" || bad "6b: behalten" "rc=$RC6C -- $AUS6C"
[ -f "$BASE/.claude/workbench/rollen/wird-behalten-$MARKE.md" ] \
  && ok "6b: die Rolle liegt jetzt global" || bad "6b: keine globale Kopie entstanden"
STAND_BEHALTEN="$(python3 -c "
import re
inhalt = open('$BASE/.claude/workbench/rollen/wird-behalten-$MARKE.md', encoding='utf-8').read()
m = re.search(r'^stand: (.*)\$', inhalt, re.M)
print(m.group(1) if m else 'FEHLT')
")"
[ "$STAND_BEHALTEN" = "behalten" ] && ok "6b: der Stand steht jetzt auf 'behalten'" \
                                     || bad "6b: Stand nach behalten" "'$STAND_BEHALTEN'"

echo
echo "-- 6c: 'behalten' ueberschreibt ein bestehendes Ziel nie ohne --ersetzen, dann mit Schnappschuss --"
wp anlegen "wird-behalten2-$MARKE" --bereich x1 --stufe mitglied --tools Bash \
   --absender "hauptagent:$ID:2026-09-10" --aufgabe "$ID" >/dev/null
wp behalten "wird-behalten2-$MARKE" --aufgabe "$ID" --mensch-beleg "$BELEG" >/dev/null
wp anlegen "wird-behalten2-$MARKE" --bereich x2 --stufe mitglied --tools Bash \
   --absender "hauptagent:$ID:2026-09-10" --aufgabe "$ID" >/dev/null
AUS6D="$(wp behalten "wird-behalten2-$MARKE" --aufgabe "$ID" --mensch-beleg "$BELEG")"
RC6D=$?
[ "$RC6D" -eq 2 ] && ok "6c: ein zweites behalten OHNE --ersetzen -> Exit 2" || bad "6c: Overwrite-Schutz" "rc=$RC6D -- $AUS6D"
printf '%s' "$AUS6D" | grep -qi -- "--ersetzen" && ok "6c: die Meldung nennt '--ersetzen'" \
                                                  || bad "6c: Meldungstext nennt --ersetzen" "$AUS6D"
AUS6E="$(wp behalten "wird-behalten2-$MARKE" --aufgabe "$ID" --mensch-beleg "$BELEG" --ersetzen)"
RC6E=$?
[ "$RC6E" -eq 0 ] && ok "6c: mit --ersetzen klappt es (Exit 0)" || bad "6c: --ersetzen" "rc=$RC6E -- $AUS6E"
SNAPSHOT_TREFFER="$(find "$BASE/.local/trash-snapshots" -type f -name "wird-behalten2-$MARKE.md" 2>/dev/null | head -1)"
[ -n "$SNAPSHOT_TREFFER" ] && ok "6c: ein Schnappschuss der alten Datei liegt unter trash-snapshots" \
                            || bad "6c: kein Schnappschuss gefunden"
BEREICH_NEU="$(python3 -c "
import re
inhalt = open('$BASE/.claude/workbench/rollen/wird-behalten2-$MARKE.md', encoding='utf-8').read()
m = re.search(r'^description: (.*)\$', inhalt, re.M)
print(m.group(1) if m else 'FEHLT')
")"
[ "$BEREICH_NEU" = "x2" ] && ok "6c: das Ziel traegt wirklich die NEUE Fassung (x2)" \
                           || bad "6c: Ziel nach --ersetzen" "'$BEREICH_NEU'"

echo
echo "-- 7: 'hinzufuegen' kopiert ein Team und ueberschreibt nichts --"
FAKE_LIB="$BASIS/fake-repo"
mkdir -p "$FAKE_LIB/profile/rollen" "$FAKE_LIB/profile/teams" "$FAKE_LIB/shell"
cp "$REPO/wb-profil" "$FAKE_LIB/shell/wb-profil"
cp "$REPO/wb-profil-gesperrt.json" "$FAKE_LIB/shell/wb-profil-gesperrt.json"
chmod +x "$FAKE_LIB/shell/wb-profil"
cat > "$FAKE_LIB/profile/rollen/fleiter-$MARKE.md" <<EOF
---
name: fleiter-$MARKE
description: Leitet.
tools:
  - Bash
stufe: teamleiter
absender: person-1
stand: behalten
---
Prompt Leiter
EOF
cat > "$FAKE_LIB/profile/rollen/fmitglied-$MARKE.md" <<EOF
---
name: fmitglied-$MARKE
description: Arbeitet.
tools:
  - Bash
stufe: mitglied
absender: person-1
stand: behalten
---
Prompt Mitglied
EOF
cat > "$FAKE_LIB/profile/teams/fteam-$MARKE.md" <<EOF
---
name: fteam-$MARKE
leiter: fleiter-$MARKE
mitglieder:
  - fmitglied-$MARKE
absender: person-1
stand: behalten
---
Testteam
EOF

wpf() {
  env HOME="$TESTHOME" PATH="$PYBIN_DIR:/usr/bin:/bin" TMUX= TMUX_PANE= \
      python3 "$FAKE_LIB/shell/wb-profil" "$@" --base "$BASE" --vorrat "$VORRAT" 2>&1
}
AUS7A="$(wpf hinzufuegen "fteam-$MARKE")"
RC7A=$?
[ "$RC7A" -eq 0 ] && ok "7: hinzufuegen eines Teams endet mit Exit 0" || bad "7: hinzufuegen" "rc=$RC7A -- $AUS7A"
[ -f "$BASE/.claude/workbench/teams/fteam-$MARKE.md" ] \
  && ok "7: die Teamdatei liegt jetzt global" || bad "7: Teamdatei fehlt nach hinzufuegen"
[ -f "$BASE/.claude/workbench/rollen/fleiter-$MARKE.md" ] && [ -f "$BASE/.claude/workbench/rollen/fmitglied-$MARKE.md" ] \
  && ok "7: beide Rollen des Teams wurden mitkopiert" || bad "7: Rollen des Teams fehlen nach hinzufuegen"
AUS7T="$(wpf pruefen "$BASE/.claude/workbench/teams/fteam-$MARKE.md")"
RC7T=$?
[ "$RC7T" -eq 0 ] && ok "7: das kopierte Team besteht seinerseits pruefen (Existenz-Pruefung greift ueber das Ziel)" \
                  || bad "7: pruefen auf kopiertes Team" "rc=$RC7T -- $AUS7T"

echo "hier stand vorher etwas anderes" >> "$BASE/.claude/workbench/rollen/fleiter-$MARKE.md"
VORHER="$(cat "$BASE/.claude/workbench/rollen/fleiter-$MARKE.md")"
AUS7B="$(wpf hinzufuegen "fteam-$MARKE")"
NACHHER="$(cat "$BASE/.claude/workbench/rollen/fleiter-$MARKE.md")"
[ "$VORHER" = "$NACHHER" ] && ok "7: ein zweites hinzufuegen ohne --ersetzen ueberschreibt NICHTS" \
                            || bad "7: hinzufuegen hat trotzdem ueberschrieben" "$AUS7B"
AUS7C="$(wpf hinzufuegen "fteam-$MARKE" --ersetzen)"
NACHHER_ERSETZT="$(cat "$BASE/.claude/workbench/rollen/fleiter-$MARKE.md")"
[ "$NACHHER_ERSETZT" != "$VORHER" ] && ok "7: mit --ersetzen wird die Datei wirklich erneuert" \
                                       || bad "7: --ersetzen hatte keine Wirkung" "$AUS7C"

echo
echo "-- 8: JEDE Datei der Bibliothek (Rollen UND Teams) besteht pruefen (Befund 5) --"
BIB_FAIL=0
BIB_ZAHL=0
for f in "$WURZEL/profile/rollen"/*.md "$WURZEL/profile/teams"/*.md; do
  [ -e "$f" ] || continue   # Kit: the profile library (profile/) is not shipped
  BIB_ZAHL=$((BIB_ZAHL+1))
  AUS="$(wp pruefen "$f")"
  RC=$?
  if [ "$RC" -ne 0 ]; then
    BIB_FAIL=$((BIB_FAIL+1))
    bad "8: $(basename "$f") besteht pruefen" "$AUS"
  fi
done
[ "$BIB_FAIL" -eq 0 ] && ok "8: alle $BIB_ZAHL Bibliotheksdateien unter profile/ (Rollen und Teams) bestehen pruefen" \
                       || echo "  (8: $BIB_FAIL von $BIB_ZAHL Bibliotheksdateien durchgefallen)"

echo
echo "-- 8b: pruefen im Teammodus findet eine kaputte Teamdatei (Befund 5) --"
cat > "$BASIS/direkt/kaputtes-team-$MARKE.md" <<EOF
---
name: kaputtes-team-$MARKE
leiter: nichtexistent-leiter-$MARKE
mitglieder:
  - nichtexistent-mitglied-$MARKE
absender: person-1
stand: behalten
tools: Bash
---
x
EOF
AUS8B="$(wp pruefen "$BASIS/direkt/kaputtes-team-$MARKE.md")"
RC8B=$?
[ "$RC8B" -eq 2 ] && ok "8b: eine Teamdatei mit nicht existierendem Leiter/Mitglied faellt durch (Exit 2)" \
                  || bad "8b: kaputte Teamdatei" "rc=$RC8B -- $AUS8B"
printf '%s' "$AUS8B" | grep -qi "existiert nicht" && ok "8b: die Meldung nennt die fehlende Existenz" \
                                                     || bad "8b: Meldungstext" "$AUS8B"
printf '%s' "$AUS8B" | grep -qi "positivliste" && ok "8b: 'tools' auf einer Teamdatei ist ein Positivlisten-Verstoss" \
                                                 || bad "8b: Team-Positivliste" "$AUS8B"

echo
echo "-- 9: gehaertete gesperrte Liste (Befund 6) --"
for probe in "Kill,PKill" "Git push" "killall -9 Safari" "wb-mailx,msmtp" "/bin/kill -9 1" "./kill -9 1"; do
  N="probe-$(printf '%s' "$probe" | tr -c 'a-zA-Z0-9' '-' | cut -c1-24)-$MARKE"
  AUS="$(wp anlegen "$N" --bereich x --stufe mitglied --tools Bash --bash "$probe" --absender person-1 --mensch-beleg "$BELEG")"
  RC=$?
  [ "$RC" -eq 2 ] && ok "9: '$probe' wird gesperrt (Exit 2)" || bad "9: '$probe' haette gesperrt werden muessen" "rc=$RC -- $AUS"
done
AUS9K="$(wp anlegen "kyrillisch-$MARKE" --bereich x --stufe mitglied --tools Bash --bash "Кill -9 Safari" --absender person-1 --mensch-beleg "$BELEG")"
RC9K=$?
[ "$RC9K" -eq 2 ] && ok "9: ein kyrillisches 'Кill' (Homoglyph) wird als nicht-lateinischer Programmname gesperrt" \
                  || bad "9: Kyrillisch-Homoglyph" "rc=$RC9K -- $AUS9K"
printf '%s' "$AUS9K" | grep -qi "nicht-lateinisch" && ok "9: die Meldung nennt 'nicht-lateinisch'" \
                                                     || bad "9: Meldungstext nennt nicht-lateinisch" "$AUS9K"
AUS9S="$(wp anlegen "harmlos-$MARKE" --bereich x --stufe mitglied --tools Bash --bash "npm test" --absender person-1 --mensch-beleg "$BELEG")"
RC9S=$?
[ "$RC9S" -eq 0 ] && ok "9: ein harmloses Muster ('npm test') bleibt weiterhin erlaubt (kein Übereifer)" \
                  || bad "9: falscher Alarm bei harmlosem Muster" "rc=$RC9S -- $AUS9S"

echo
echo "-- 10: --mensch-beleg gilt nur im Testbett (Befund 7) --"
mkdir -p "$TESTHOME/vorrat-echthome"
AUS10="$(wp_echtes_home anlegen "spaeher-$MARKE" --bereich x --stufe mitglied --tools Bash --absender person-1 --mensch-beleg "$BELEG")"
RC10=$?
[ "$RC10" -eq 2 ] && ok "10: --mensch-beleg wird abgewiesen, wenn --base auf das echte HOME zeigt" \
                  || bad "10: Testbett-Bindung" "rc=$RC10 -- $AUS10"
printf '%s' "$AUS10" | grep -qi "testbett" && ok "10: die Meldung nennt 'Testbett'" \
                                             || bad "10: Meldungstext nennt Testbett" "$AUS10"
[ ! -e "$TESTHOME/.claude/workbench/rollen/spaeher-$MARKE.md" ] \
  && ok "10: es wurde trotzdem nichts angelegt" || bad "10: Rolle wurde trotz Testbett-Ablehnung angelegt"

echo
echo "-- 11: Meldungswege -- pruefen nach stderr, argparse deutsch (Befund 9) --"
AUS11_STDOUT="$(env HOME="$TESTHOME" PATH="$PYBIN_DIR:/usr/bin:/bin" \
    python3 "$REPO/wb-profil" pruefen "$BASIS/direkt/kaputt-$MARKE.md" --base "$BASE" --vorrat "$VORRAT" 2>"$BASIS/stderr11.log")"
RC11=$?
AUS11_STDERR="$(cat "$BASIS/stderr11.log")"
[ "$RC11" -eq 2 ] && ok "11: pruefen bei einem Verstoss -> Exit 2" || bad "11: pruefen Exit-Code" "rc=$RC11"
[ -z "$AUS11_STDOUT" ] && ok "11: stdout bleibt bei einer Ablehnung leer" \
                        || bad "11: stdout haette leer bleiben sollen" "'$AUS11_STDOUT'"
printf '%s' "$AUS11_STDERR" | grep -qi "'model'" && ok "11: die Meldung steht auf STDERR" \
                                                    || bad "11: stderr-Inhalt" "$AUS11_STDERR"

AUS11B="$(wp anlegen "argtest-$MARKE" --bereich x --stufe quatsch --tools Bash --absender person-1 --mensch-beleg "$BELEG")"
RC11B=$?
[ "$RC11B" -eq 2 ] && ok "11: --stufe mit unbekanntem Wert -> Exit 2" || bad "11: --stufe Exit-Code" "rc=$RC11B"
printf '%s' "$AUS11B" | grep -qi "invalid choice" && bad "11: --stufe-Meldung ist noch englisch (argparse)" "$AUS11B" \
                                                     || ok "11: --stufe-Meldung ist NICHT die englische argparse-Meldung"
printf '%s' "$AUS11B" | grep -qE "FEHLER|kennt.*nicht" && ok "11: --stufe-Meldung ist deutsch" \
                                                          || bad "11: --stufe-Meldung deutscher Wortlaut" "$AUS11B"

echo
echo "-- 12: spawn-argumente prueft vorher, gibt bei Verstoss nichts aus (Befund 8) --"
wp anlegen "spawntest-$MARKE" --bereich x --stufe mitglied --tools "Bash,Read" --bash "npm test" \
   --skills "recherche" --absender person-1 --mensch-beleg "$BELEG" >/dev/null
AUS12A="$(wp spawn-argumente "spawntest-$MARKE" --harness claude)"
GUELTIG_A="$(printf '%s' "$AUS12A" | python3 -c "import json,sys; d=json.load(sys.stdin); print('ok' if 'tools' in d and 'disallowedTools' in d and 'prompt_datei' in d and 'bash_muster' in d else 'unvollstaendig: %r' % d)" 2>&1)"
[ "$GUELTIG_A" = "ok" ] && ok "12: spawn-argumente --harness claude liefert gueltiges, vollstaendiges JSON" \
                         || bad "12: claude-Ausgabe" "$GUELTIG_A -- $AUS12A"

AUS12B="$(wp spawn-argumente "spawntest-$MARKE" --harness pi)"
GUELTIG_B="$(printf '%s' "$AUS12B" | python3 -c "import json,sys; d=json.load(sys.stdin); print('ok' if d.get('no_skills') is True and 'skill' in d and 'prompt_datei' in d and 'bash_muster' in d else 'unvollstaendig: %r' % d)" 2>&1)"
[ "$GUELTIG_B" = "ok" ] && ok "12: spawn-argumente --harness pi liefert gueltiges, vollstaendiges JSON" \
                         || bad "12: pi-Ausgabe" "$GUELTIG_B -- $AUS12B"

# jetzt die Rolle von Hand kaputt machen (gesperrtes Werkzeug einschmuggeln) und pruefen, dass NICHTS mehr rauskommt
DATEI_SPAWNTEST="$BASE/.claude/workbench/rollen/spawntest-$MARKE.md"
python3 - "$DATEI_SPAWNTEST" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
t = t.replace("tools:\n  - Bash\n  - Read", "tools:\n  - Bash\n  - Read\n  - kill")
open(p, "w", encoding="utf-8").write(t)
PY
AUS12C_STDOUT="$(env HOME="$TESTHOME" PATH="$PYBIN_DIR:/usr/bin:/bin" \
    python3 "$REPO/wb-profil" spawn-argumente "spawntest-$MARKE" --base "$BASE" --vorrat "$VORRAT" 2>"$BASIS/stderr12.log")"
RC12C=$?
[ "$RC12C" -eq 2 ] && ok "12: spawn-argumente auf einer manipulierten Rolle -> Exit 2" \
                    || bad "12: spawn-argumente nach Manipulation" "rc=$RC12C"
[ -z "$AUS12C_STDOUT" ] && ok "12: stdout bleibt bei der Ablehnung leer -- kein Einzelzeichen-Leak" \
                         || bad "12: stdout haette leer bleiben sollen" "'$AUS12C_STDOUT'"

echo
echo "-- 13: Rundtrip von Listenelementen mit Doppelpunkt (Hinweis 12) --"
wp anlegen "colontest-$MARKE" --bereich x --stufe mitglied --tools Bash \
   --skills "caveman:caveman-review,recherche" --absender person-1 --mensch-beleg "$BELEG" >/dev/null
DATEI_COLON="$BASE/.claude/workbench/rollen/colontest-$MARKE.md"
grep -q '"caveman:caveman-review"' "$DATEI_COLON" && ok "13: der Skill-Name mit Doppelpunkt wird beim Schreiben gequotet" \
                                                     || bad "13: Datei traegt kein Quoting" "$(cat "$DATEI_COLON")"
AUS13="$(wp zeigen "colontest-$MARKE" --json)"
SKILL_ZURUECK="$(printf '%s' "$AUS13" | python3 -c "import json,sys; print(json.load(sys.stdin)['frontmatter']['skills'][0])")"
[ "$SKILL_ZURUECK" = "caveman:caveman-review" ] && ok "13: beim Lesen kommt wieder genau 'caveman:caveman-review' heraus (Rundtrip)" \
                                                  || bad "13: Rundtrip-Ergebnis" "'$SKILL_ZURUECK'"

echo
echo "-- 14: Modell- und Fallback-Vorbelegung (AUFTRAG-agents1-nr3.md) --"
wp anlegen "fbrolle-$MARKE" --bereich x --stufe mitglied --tools Bash --absender person-1 --mensch-beleg "$BELEG" >/dev/null

AUS14A="$(wp spawn-argumente "fbrolle-$MARKE")"
MODVOR_LEER="$(printf '%s' "$AUS14A" | python3 -c "import json,sys; print(json.load(sys.stdin)['modell_vorbelegung'])")"
FBVOR_VORGABE="$(printf '%s' "$AUS14A" | python3 -c "import json,sys; d=json.load(sys.stdin)['fallback_vorbelegung']; print(d['model']+':'+d['effort'])")"
[ "$MODVOR_LEER" = "None" ] && ok "14: modell_vorbelegung ist null, ohne jede Einstellung" \
                             || bad "14: modell_vorbelegung ohne Einstellung" "'$MODVOR_LEER'"
[ "$FBVOR_VORGABE" = "qwen3.5-4b:medium" ] \
  && ok "14: fallback_vorbelegung ist die Hausvorgabe, ohne jede Einstellung" \
  || bad "14: fallback_vorbelegung ohne Einstellung" "'$FBVOR_VORGABE'"

cat > "$BASE/.claude/workbench/settings.json" <<EOF
{"agents": {"rollen": {"fbrolle-$MARKE": {"modell": "sonnet5:high", "fallback": "haiku45:low"}}}}
EOF
AUS14B="$(wp spawn-argumente "fbrolle-$MARKE")"
MODVOR_ROLLE="$(printf '%s' "$AUS14B" | python3 -c "import json,sys; d=json.load(sys.stdin)['modell_vorbelegung']; print(d['model']+':'+d['effort'])")"
FBVOR_ROLLE="$(printf '%s' "$AUS14B" | python3 -c "import json,sys; d=json.load(sys.stdin)['fallback_vorbelegung']; print(d['model']+':'+d['effort'])")"
[ "$MODVOR_ROLLE" = "sonnet5:high" ] && ok "14: modell_vorbelegung kommt aus agents.rollen.<name>.modell" \
                                      || bad "14: modell_vorbelegung je Rolle" "'$MODVOR_ROLLE'"
[ "$FBVOR_ROLLE" = "haiku45:low" ] && ok "14: fallback_vorbelegung kommt aus agents.rollen.<name>.fallback" \
                                    || bad "14: fallback_vorbelegung je Rolle" "'$FBVOR_ROLLE'"

AUS14C="$(wp spawn-argumente "fbrolle-$MARKE" --fallback keins)"
FBVOR_KEINS="$(printf '%s' "$AUS14C" | python3 -c "import json,sys; print(json.load(sys.stdin)['fallback_vorbelegung'])")"
[ "$FBVOR_KEINS" = "None" ] && ok "14: --fallback keins am Aufruf -> fallback_vorbelegung ist null" \
                              || bad "14: --fallback keins" "'$FBVOR_KEINS'"

AUS14D="$(wp spawn-argumente "fbrolle-$MARKE" --modell "opus5:xhigh")"
MODVOR_UEBERSCHRIEBEN="$(printf '%s' "$AUS14D" | python3 -c "import json,sys; d=json.load(sys.stdin)['modell_vorbelegung']; print(d['model']+':'+d['effort'])")"
[ "$MODVOR_UEBERSCHRIEBEN" = "opus5:xhigh" ] && ok "14: --modell am Aufruf ueberschreibt die Einstellungs-Vorbelegung" \
                                              || bad "14: --modell ueberschreibt" "'$MODVOR_UEBERSCHRIEBEN'"

AUS14E="$(wp spawn-argumente "fbrolle-$MARKE" --fallback "fable51:medium")"
RC14E=$?
[ "$RC14E" -eq 2 ] && ok "14: Fable als Fallback am Aufruf -> Exit 2" || bad "14: Fable am Aufruf" "rc=$RC14E -- $AUS14E"
printf '%s' "$AUS14E" | grep -qi "fable" && ok "14: die Meldung nennt Fable" || bad "14: Meldungstext Fable" "$AUS14E"

GUELTIG_14F="$(printf '%s' "$AUS14B" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('ok' if 'modell_vorbelegung' in d and 'fallback_vorbelegung' in d and d['modell_vorbelegung'] and d['fallback_vorbelegung'] else 'unvollstaendig: %r' % d)
")"
[ "$GUELTIG_14F" = "ok" ] && ok "14: spawn-argumente liefert beide Vorbelegungen als gueltiges JSON" \
                           || bad "14: JSON-Vollstaendigkeit beider Vorbelegungen" "$GUELTIG_14F"

echo
echo "-- 15: die echte Umgebung blieb unberuehrt --"
[ ! -e "$HOME/.claude/workbench/rollen/spawntest-$MARKE.md" ] \
  && ok "15: keine Datei dieses Laufs unter dem ECHTEN ~/.claude/workbench/rollen" \
  || bad "15: es wurde in das echte Rollenverzeichnis geschrieben"

echo
echo "-- 16: schreibsperre (hooks5, reviewer-sperre) -- neues Feld in der Positivliste --"
mkdir -p "$BASE/.claude/workbench/rollen"
cat > "$BASE/.claude/workbench/rollen/sperrrolle-$MARKE.md" <<EOF
---
name: sperrrolle-$MARKE
description: nur schreiben auf den Ergebnispfad
tools:
  - Read
  - Write
bash:
  - "brain search"
stufe: mitglied
schreibsperre: true
absender: person-1
stand: behalten
---
Rollen-Prompt.
EOF
AUS16A="$(wp pruefen "sperrrolle-$MARKE")"
RC16A=$?
[ "$RC16A" -eq 0 ] && ok "16: 'schreibsperre: true' ist kein Positivliste-Verstoss (Exit 0)" \
                    || bad "16: pruefen mit schreibsperre" "rc=$RC16A -- $AUS16A"

AUS16B="$(wp zeigen "sperrrolle-$MARKE" --json)"
SCHREIBSPERRE_JSON="$(printf '%s' "$AUS16B" | python3 -c "import json,sys; print(json.load(sys.stdin)['frontmatter']['schreibsperre'])")"
[ "$SCHREIBSPERRE_JSON" = "True" ] && ok "16: 'zeigen --json' liefert schreibsperre als echtes bool (true)" \
                                     || bad "16: schreibsperre im JSON" "'$SCHREIBSPERRE_JSON' -- $AUS16B"

cat > "$BASE/.claude/workbench/rollen/keinesperre-$MARKE.md" <<EOF
---
name: keinesperre-$MARKE
description: normale Rolle ohne Schreibsperre
tools:
  - Read
stufe: mitglied
absender: person-1
stand: behalten
---
Rollen-Prompt.
EOF
AUS16C="$(wp zeigen "keinesperre-$MARKE" --json)"
FEHLT16C="$(printf '%s' "$AUS16C" | python3 -c "import json,sys; print('schreibsperre' in json.load(sys.stdin)['frontmatter'])")"
[ "$FEHLT16C" = "False" ] && ok "16: ohne das Feld im Profil fehlt 'schreibsperre' auch im JSON (kein erfundenes false)" \
                            || bad "16: schreibsperre ohne Feld" "$AUS16C"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
