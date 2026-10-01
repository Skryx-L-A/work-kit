#!/usr/bin/env bash
# test-wb-aufgabe.sh -- Auftragsdatei und Verlaufsdatei des Agents-Features
# (Bau-Schritt 1, AUFTRAG-agents1.md, Abschnitt 4 "Tests", nachgezogen um die
# Reviewer-Befunde aus ~/.pi-workers/results/agents1rev/20260910-173842.md,
# Auftrag Nr. 2): Anlegen, Freigeben mit Hash und Unveraenderlichkeit danach,
# die Menschen-Sperren (abgenommen/verworfen, Uebergang heraus -- jetzt auch
# ueber antwort/weckzeit/wiederaufnahme/worker-setzen geprueft), die
# Zustellungs-Idempotenz, Rang-Umsortierung ohne Wirkung auf den Hash,
# `pruefen`/`liste --json`, die Testbett-Bindung von `--mensch-beleg` und
# deutsche Meldungswege.
#
# KEIN MODELLAUFRUF, KEIN TMUX, KEIN NETZ -- reine Dateipruefung. Bauart wie
# test-pi-worker-auftragsbuch.sh: eigenes HOME per mktemp -d, ok/bad, trap,
# Kennungen entstehen zur Laufzeit aus einer Marke, die es vor dem Lauf
# nirgends gab.
#
# ISOLATION UND ZWEI WURZELN: PATH schliesst das echte ~/.local/bin aus (nur
# python3 plus /usr/bin:/bin), HOME zeigt auf ein eigenes mktemp-Verzeichnis
# (TESTHOME) mit einem Schirm-`wb-mensch`, der IMMER 1 (kein Mensch)
# zurueckgibt -- damit ist wb-mensch pruefen in der ganzen Suite deterministisch
# "kein Mensch", ohne von der Frage abzuhaengen, ob gerade ein Mensch oder ein
# Agent am Terminal dieser Session sitzt. Die eigentlichen Testdaten (Vorrat,
# Projekt) liegen NICHT unter TESTHOME, sondern unter einem eigenen,
# GLEICHRANGIGEN Verzeichnis BASIS, das per --base an wb-aufgabe geht: seit
# Reviewer-Befund 7 gilt --mensch-beleg nur, wenn --base/--vorrat/WB_VORRAT
# ausserhalb des ECHTEN HOME (hier: TESTHOME) liegen -- eine Testdatenwurzel
# UNTER TESTHOME waere technisch "ein Verzeichnis im eigenen HOME" und wuerde
# --mensch-beleg faelschlich als Testbett-Ausnahme durchlassen. Abschnitt 7
# unten prueft ausdruecklich den Gegenfall (Wurzel = TESTHOME selbst).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKE="a$(date +%s)$$$RANDOM"
TESTHOME="$(mktemp -d "${TMPDIR:-/tmp}/wb-aufgabe-test.XXXXXX")"
BASIS="$(mktemp -d "${TMPDIR:-/tmp}/wb-aufgabe-basis.XXXXXX")"
PYBIN_DIR="$(dirname "$(command -v python3)")"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

cleanup() {
  case "$TESTHOME" in
    /tmp/wb-aufgabe-test.*|/private/tmp/wb-aufgabe-test.*|/var/folders/*/wb-aufgabe-test.*)
      rm -rf "$TESTHOME" ;;
    *) echo "WARNUNG: TESTHOME='$TESTHOME' sieht nicht nach einem Testverzeichnis aus -- NICHT geloescht." >&2 ;;
  esac
  case "$BASIS" in
    /tmp/wb-aufgabe-basis.*|/private/tmp/wb-aufgabe-basis.*|/var/folders/*/wb-aufgabe-basis.*)
      rm -rf "$BASIS" ;;
    *) echo "WARNUNG: BASIS='$BASIS' sieht nicht nach einem Testverzeichnis aus -- NICHT geloescht." >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

echo "== wb-aufgabe (HOME $TESTHOME, BASIS $BASIS, Marke $MARKE) =="

[ -x "$REPO/wb-aufgabe" ] || { echo "UEBERSPRUNGEN: shell/wb-aufgabe fehlt oder ist nicht ausfuehrbar"; exit 77; }

VORRAT="$BASIS/vorrat"
PROJ="$BASIS/projekt-$MARKE"
BELEG="$BASIS/beleg.txt"
mkdir -p "$VORRAT" "$PROJ" "$TESTHOME/.local/bin"
printf 'mensch\tTest-Beleg %s\n' "$MARKE" > "$BELEG"

# Schirm-wb-mensch: IMMER "kein Mensch" (Exit 1) -- deterministisch, egal wer
# diese Suite gerade laufen laesst.
cat > "$TESTHOME/.local/bin/wb-mensch" <<'SHIMEOF'
#!/bin/sh
case "$1" in
  beleg) printf 'agent\tSchirm fuer test-wb-aufgabe.sh, immer kein Mensch\n'; exit 0 ;;
  *) exit 1 ;;
esac
SHIMEOF
chmod +x "$TESTHOME/.local/bin/wb-mensch"

wa() {
  env HOME="$TESTHOME" PATH="$PYBIN_DIR:/usr/bin:/bin" TMUX= TMUX_PANE= \
      python3 "$REPO/wb-aufgabe" "$@" --vorrat "$VORRAT" --base "$BASIS" 2>&1
}
# Nur fuer Abschnitt 7: --base zeigt auf TESTHOME selbst (simuliert "echtes HOME").
wa_echtes_home() {
  env HOME="$TESTHOME" PATH="$PYBIN_DIR:/usr/bin:/bin" TMUX= TMUX_PANE= \
      python3 "$REPO/wb-aufgabe" "$@" --vorrat "$TESTHOME/vorrat-echthome" --base "$TESTHOME" 2>&1
}

echo
echo "-- 1: anlegen schreibt drei Dateien --"
AUS1="$(wa anlegen "$PROJ" --ziel "Testaufgabe $MARKE" --fertig "Suiten gruen")"
RC1=$?
ID="$(printf '%s' "$AUS1" | tail -1)"
AUFTRAG="$PROJ/.companion/auftraege/$ID.json"
VERLAUF="$PROJ/.companion/auftraege/$ID.verlauf.json"
VORRATDATEI="$VORRAT/$ID.json"

[ "$RC1" -eq 0 ] && ok "1: anlegen endet mit Exit 0" || bad "1: anlegen endet mit Exit 0" "rc=$RC1 -- $AUS1"
[ -s "$AUFTRAG" ] && ok "1: Auftragsdatei liegt vor ($ID.json)" || bad "1: Auftragsdatei fehlt" "$AUS1"
[ -s "$VERLAUF" ] && ok "1: Verlaufsdatei liegt vor ($ID.verlauf.json)" || bad "1: Verlaufsdatei fehlt" "$AUS1"
[ -s "$VORRATDATEI" ] && ok "1: Vorratsdatei liegt vor" || bad "1: Vorratsdatei fehlt" "$AUS1"

STAND1="$(python3 -c "import json;print(json.load(open('$VERLAUF'))['stand'])" 2>/dev/null)"
[ "$STAND1" = "offen" ] && ok "1: Stand nach dem Anlegen ist 'offen'" || bad "1: Stand nach Anlegen" "'$STAND1'"

APPROVAL1="$(python3 -c "import json;print(json.load(open('$AUFTRAG'))['approval'])" 2>/dev/null)"
[ "$APPROVAL1" = "None" ] && ok "1: approval ist noch nicht gesetzt" || bad "1: approval nach Anlegen" "'$APPROVAL1'"

echo
echo "-- 2: Freigabe ohne Beleg wird abgelehnt, mit Beleg gesetzt, Hash stimmt --"
AUS2A="$(wa freigeben "$ID")"
RC2A=$?
[ "$RC2A" -eq 2 ] && ok "2: Freigabe ohne Menschen-Beleg -> Exit 2" || bad "2: Exit-Code ohne Beleg" "rc=$RC2A -- $AUS2A"

AUS2B="$(wa freigeben "$ID" --mensch-beleg "$BELEG")"
RC2B=$?
[ "$RC2B" -eq 0 ] && ok "2: Freigabe mit Menschen-Beleg -> Exit 0" || bad "2: Freigabe mit Beleg" "rc=$RC2B -- $AUS2B"

HASH_GESPEICHERT="$(python3 -c "import json;print(json.load(open('$AUFTRAG'))['approval']['text_sha256'])" 2>/dev/null)"
HASH_NEU_BERECHNET="$(python3 - "$AUFTRAG" <<'PY'
import json, hashlib, sys
d = json.load(open(sys.argv[1]))
ohne = {k: v for k, v in d.items() if k != "approval"}
kanon = json.dumps(ohne, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
print(hashlib.sha256(kanon.encode()).hexdigest())
PY
)"
[ -n "$HASH_GESPEICHERT" ] && [ "$HASH_GESPEICHERT" = "$HASH_NEU_BERECHNET" ] \
  && ok "2: der gespeicherte Hash stimmt mit einer unabhaengigen Neuberechnung ueberein" \
  || bad "2: Hash-Vergleich" "gespeichert='$HASH_GESPEICHERT' neu='$HASH_NEU_BERECHNET'"

echo
echo "-- 2b: nach der Freigabe ist die Auftragsdatei unveraenderlich --"
AUS2C="$(wa freigeben "$ID" --mensch-beleg "$BELEG")"
RC2C=$?
[ "$RC2C" -eq 2 ] && ok "2b: eine zweite Freigabe ohne --neu-freigeben -> Exit 2" \
                  || bad "2b: zweite Freigabe" "rc=$RC2C -- $AUS2C"
AUS2D="$(wa freigeben "$ID" --neu-freigeben --mensch-beleg "$BELEG")"
RC2D=$?
[ "$RC2D" -eq 0 ] && ok "2b: --neu-freigeben mit Beleg -> Exit 0 (loescht approval)" \
                  || bad "2b: --neu-freigeben" "rc=$RC2D -- $AUS2D"
APPROVAL_NACH_NEUFREIGABE="$(python3 -c "import json;print(json.load(open('$AUFTRAG'))['approval'])" 2>/dev/null)"
[ "$APPROVAL_NACH_NEUFREIGABE" = "None" ] && ok "2b: approval ist nach --neu-freigeben wieder leer" \
                                           || bad "2b: approval nach --neu-freigeben" "'$APPROVAL_NACH_NEUFREIGABE'"
# neu freigeben, fuer die weiteren Abschnitte
wa freigeben "$ID" --mensch-beleg "$BELEG" >/dev/null

echo
echo "-- 3: 'abgenommen' ohne Mensch wird abgelehnt --"
AUS3="$(wa stand "$ID" abgenommen)"
RC3=$?
[ "$RC3" -eq 2 ] && ok "3: stand abgenommen ohne Beleg -> Exit 2" || bad "3: abgenommen ohne Mensch" "rc=$RC3 -- $AUS3"
STAND3="$(python3 -c "import json;print(json.load(open('$VERLAUF'))['stand'])" 2>/dev/null)"
[ "$STAND3" != "abgenommen" ] && ok "3: der Stand blieb unveraendert (nicht 'abgenommen')" \
                               || bad "3: Stand haette nicht wechseln duerfen" "'$STAND3'"

AUS3B="$(wa stand "$ID" abgenommen --mensch-beleg "$BELEG")"
RC3B=$?
[ "$RC3B" -eq 0 ] && ok "3: stand abgenommen MIT Beleg -> Exit 0" || bad "3: abgenommen mit Mensch" "rc=$RC3B -- $AUS3B"

echo
echo "-- 4: der Uebergang AUS 'abgenommen' heraus wird abgelehnt (stand UND vier weitere Wege, Befund 3) --"
AUS4="$(wa stand "$ID" offen --mensch-beleg "$BELEG")"
RC4=$?
[ "$RC4" -eq 2 ] && ok "4: 'abgenommen' -> 'offen' ueber stand wird abgelehnt, auch mit Menschen-Beleg" \
                 || bad "4: Uebergang aus abgenommen (stand)" "rc=$RC4 -- $AUS4"
STAND4="$(python3 -c "import json;print(json.load(open('$VERLAUF'))['stand'])" 2>/dev/null)"
[ "$STAND4" = "abgenommen" ] && ok "4: der Stand blieb 'abgenommen'" || bad "4: Stand nach abgelehntem Uebergang" "'$STAND4'"

# Befund 3: dieselbe Sperre gilt fuer antwort, weckzeit, wiederaufnahme, worker setzen.
# Erst eine Frage stellen (frage ist selbst schon vor Auftrag Nr. 2 gesperrt) --
# das geht nicht mehr, weil die Aufgabe schon abgenommen ist; die Sperre bei
# `frage` deckt exakt denselben Fall ab wie bei `antwort` unten, also reicht
# hier direkt der Test der vier BISHER ungeprueften Wege.
AUS4B="$(wa antwort "$ID" "irgendeine Antwort" --mensch-beleg "$BELEG")"
RC4B=$?
[ "$RC4B" -eq 2 ] && ok "4: 'antwort' aus 'abgenommen' heraus wird abgelehnt (Befund 3)" \
                  || bad "4: antwort aus abgenommen" "rc=$RC4B -- $AUS4B"

AUS4C="$(wa weckzeit "$ID" "2026-09-11T06:00:00Z")"
RC4C=$?
[ "$RC4C" -eq 2 ] && ok "4: 'weckzeit' aus 'abgenommen' heraus wird abgelehnt (Befund 3)" \
                  || bad "4: weckzeit aus abgenommen" "rc=$RC4C -- $AUS4C"

AUS4D="$(wa wiederaufnahme "$ID" "neuer Stand")"
RC4D=$?
[ "$RC4D" -eq 2 ] && ok "4: 'wiederaufnahme' aus 'abgenommen' heraus wird abgelehnt (Befund 3)" \
                  || bad "4: wiederaufnahme aus abgenommen" "rc=$RC4D -- $AUS4D"

AUS4E="$(wa worker "$ID" setzen "w-spaet-$MARKE" --rolle tester --zustand arbeitet)"
RC4E=$?
[ "$RC4E" -eq 2 ] && ok "4: 'worker setzen' aus 'abgenommen' heraus wird abgelehnt (Befund 3)" \
                  || bad "4: worker setzen aus abgenommen" "rc=$RC4E -- $AUS4E"
WORKER_NACH="$(python3 -c "import json;print(len(json.load(open('$VERLAUF'))['worker']))" 2>/dev/null)"
[ "$WORKER_NACH" = "0" ] && ok "4: kein Worker wurde trotzdem eingetragen" \
                          || bad "4: Worker-Liste nach abgelehntem worker setzen" "$WORKER_NACH Eintraege"

echo
echo "-- 5: doppelte Zustellungskennung ist ein No-op --"
ID2AUS="$(wa anlegen "$PROJ" --ziel "Zweite Aufgabe $MARKE" --fertig "x")"
ID2="$(printf '%s' "$ID2AUS" | tail -1)"
V2="$PROJ/.companion/auftraege/$ID2.verlauf.json"

wa verlauf "$ID2" zustellung "Nachricht eins" --kennung "z-$MARKE" >/dev/null
ANZAHL_VOR="$(python3 -c "import json;print(len(json.load(open('$V2'))['verlauf']))" 2>/dev/null)"
AUS5="$(wa verlauf "$ID2" zustellung "Nachricht zwei" --kennung "z-$MARKE")"
RC5=$?
ANZAHL_NACH="$(python3 -c "import json;print(len(json.load(open('$V2'))['verlauf']))" 2>/dev/null)"
[ "$RC5" -eq 0 ] && ok "5: die zweite Zustellung derselben Kennung endet mit Exit 0" \
                 || bad "5: Exit-Code bei doppelter Zustellung" "rc=$RC5 -- $AUS5"
printf '%s' "$AUS5" | grep -qi "schon quittiert" \
  && ok "5: die Ausgabe sagt 'schon quittiert'" || bad "5: Ausgabetext bei doppelter Zustellung" "$AUS5"
[ "$ANZAHL_VOR" = "$ANZAHL_NACH" ] && ok "5: kein zweiter Verlaufseintrag ist entstanden ($ANZAHL_VOR Eintraege)" \
                                    || bad "5: Verlaufslaenge" "vorher=$ANZAHL_VOR nachher=$ANZAHL_NACH"

echo
echo "-- 6: Rang-Umsortierung laesst Hash und Auftragsdatei unberuehrt --"
HASH_VOR_RANG="$HASH_GESPEICHERT"
INHALT_VOR_RANG="$(cat "$AUFTRAG")"
AUS6="$(wa rang "$ID" 9)"
RC6=$?
[ "$RC6" -eq 0 ] && ok "6: rang-Umsortierung endet mit Exit 0" || bad "6: rang" "rc=$RC6 -- $AUS6"
RANG_NACH="$(python3 -c "import json;print(json.load(open('$VORRATDATEI'))['rang'])" 2>/dev/null)"
[ "$RANG_NACH" = "9" ] && ok "6: der Rang im Vorrat steht jetzt auf 9" || bad "6: Rang nach Umsortierung" "'$RANG_NACH'"
INHALT_NACH_RANG="$(cat "$AUFTRAG")"
[ "$INHALT_VOR_RANG" = "$INHALT_NACH_RANG" ] && ok "6: die Auftragsdatei ist byteidentisch geblieben" \
                                              || bad "6: Auftragsdatei nach Rang-Umsortierung veraendert" ""
HASH_NACH_RANG="$(python3 -c "import json;print(json.load(open('$AUFTRAG'))['approval']['text_sha256'])" 2>/dev/null)"
[ "$HASH_VOR_RANG" = "$HASH_NACH_RANG" ] && ok "6: der Freigabe-Hash blieb unveraendert" \
                                          || bad "6: Hash nach Rang-Umsortierung" "vor='$HASH_VOR_RANG' nach='$HASH_NACH_RANG'"

echo
echo "-- 7: pruefen findet einen von Hand kaputt gemachten Hash, Meldung geht nach stderr (Befund 9) --"
AUS7A_OUT="$(wa pruefen "$ID" 2>"$BASIS/stderr7a.log")"
RC7A=$?
[ "$RC7A" -eq 0 ] && ok "7: pruefen ist sauber, bevor etwas kaputt gemacht wurde" \
                  || bad "7: pruefen vor der Sabotage" "rc=$RC7A -- $AUS7A_OUT"

python3 - "$AUFTRAG" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["approval"]["text_sha256"] = "0" * 64
json.dump(d, open(p, "w"), indent=2)
PY
# stdout und stderr getrennt einsammeln (kein 2>&1 in wa()): pruefen muss die
# Befunde auf stderr schreiben, stdout bleibt fuer den Fehlerfall leer (Befund 9).
AUS7B_STDOUT="$(env HOME="$TESTHOME" PATH="$PYBIN_DIR:/usr/bin:/bin" \
    python3 "$REPO/wb-aufgabe" pruefen "$ID" --vorrat "$VORRAT" --base "$BASIS" 2>"$BASIS/stderr7b.log")"
RC7B=$?
AUS7B_STDERR="$(cat "$BASIS/stderr7b.log")"
[ "$RC7B" -eq 2 ] && ok "7: pruefen meldet den kaputten Hash mit Exit 2" || bad "7: pruefen nach Sabotage" "rc=$RC7B"
printf '%s' "$AUS7B_STDERR" | grep -qi "hash" && ok "7: die Meldung auf STDERR nennt das Wort 'Hash'" \
                                               || bad "7: Meldungstext auf stderr nennt den Hash" "$AUS7B_STDERR"
[ -z "$AUS7B_STDOUT" ] && ok "7: stdout bleibt bei einer Ablehnung leer (Befund 9)" \
                        || bad "7: stdout haette bei Ablehnung leer bleiben sollen" "'$AUS7B_STDOUT'"

echo
echo "-- 8: liste --json ist gueltiges JSON in Rangfolge --"
AUS8="$(wa liste --json)"
RC8=$?
[ "$RC8" -eq 0 ] && ok "8: liste --json endet mit Exit 0" || bad "8: liste --json Exit-Code" "rc=$RC8"
GUELTIG="$(printf '%s' "$AUS8" | python3 -c "import json,sys; json.load(sys.stdin); print('ok')" 2>&1)"
[ "$GUELTIG" = "ok" ] && ok "8: die Ausgabe ist gueltiges JSON" || bad "8: JSON-Gueltigkeit" "$GUELTIG -- $AUS8"
SORTIERT="$(printf '%s' "$AUS8" | python3 -c "
import json, sys
d = json.load(sys.stdin)
raenge = [e['rang'] for e in d]
print('ok' if raenge == sorted(raenge) else 'unsortiert: %r' % raenge)
")"
[ "$SORTIERT" = "ok" ] && ok "8: die Eintraege stehen in Rangfolge" || bad "8: Rangfolge" "$SORTIERT"

echo
echo "-- 9: --mensch-beleg gilt nur im Testbett (Befund 7) --"
mkdir -p "$TESTHOME/vorrat-echthome" "$TESTHOME/projekt-echthome"
ID9AUS="$(wa_echtes_home anlegen "$TESTHOME/projekt-echthome" --ziel "Echtes-Home-Test $MARKE" --fertig "x")"
ID9="$(printf '%s' "$ID9AUS" | tail -1)"
AUS9="$(wa_echtes_home freigeben "$ID9" --mensch-beleg "$BELEG")"
RC9=$?
[ "$RC9" -eq 2 ] && ok "9: --mensch-beleg wird abgewiesen, wenn --base auf das echte HOME zeigt" \
                 || bad "9: Testbett-Bindung" "rc=$RC9 -- $AUS9"
printf '%s' "$AUS9" | grep -qi "testbett" && ok "9: die Meldung nennt 'Testbett'" \
                                            || bad "9: Meldungstext nennt Testbett" "$AUS9"
APPROVAL9="$(python3 -c "import json;print(json.load(open('$TESTHOME/projekt-echthome/.companion/auftraege/$ID9.json'))['approval'])" 2>/dev/null)"
[ "$APPROVAL9" = "None" ] && ok "9: die Aufgabe wurde trotzdem NICHT freigegeben" \
                            || bad "9: approval haette leer bleiben muessen" "'$APPROVAL9'"

echo
echo "-- 10: argparse-Ablehnungen sind deutsch, nicht englisch (Befund 9, --freigabe/--nachtmodus) --"
AUS10A="$(wa anlegen "$PROJ" --ziel "Ungueltige Freigabe $MARKE" --fertig x --freigabe quatsch)"
RC10A=$?
[ "$RC10A" -eq 2 ] && ok "10: --freigabe mit unbekanntem Wert -> Exit 2" || bad "10: --freigabe Exit-Code" "rc=$RC10A"
printf '%s' "$AUS10A" | grep -qi "invalid choice" && bad "10: --freigabe-Meldung ist noch englisch (argparse)" "$AUS10A" \
                                                    || ok "10: --freigabe-Meldung ist NICHT die englische argparse-Meldung"
printf '%s' "$AUS10A" | grep -qE "FEHLER|kennt.*nicht" && ok "10: --freigabe-Meldung ist deutsch" \
                                                          || bad "10: --freigabe-Meldung deutscher Wortlaut" "$AUS10A"

AUS10B="$(wa anlegen "$PROJ" --ziel "Ungueltiger Nachtmodus $MARKE" --fertig x --nachtmodus quatsch)"
RC10B=$?
[ "$RC10B" -eq 2 ] && ok "10: --nachtmodus mit unbekanntem Wert -> Exit 2" || bad "10: --nachtmodus Exit-Code" "rc=$RC10B"
printf '%s' "$AUS10B" | grep -qi "invalid choice" && bad "10: --nachtmodus-Meldung ist noch englisch (argparse)" "$AUS10B" \
                                                     || ok "10: --nachtmodus-Meldung ist NICHT die englische argparse-Meldung"

echo
echo "-- 11: Fallback-Modell (AUFTRAG-agents1-nr3.md) --"
IDFB1AUS="$(wa anlegen "$PROJ" --ziel "Fallback ohne Einstellung $MARKE" --fertig x)"
IDFB1="$(printf '%s' "$IDFB1AUS" | tail -1)"
FB1="$(python3 -c "
import json
d = json.load(open('$PROJ/.companion/auftraege/$IDFB1.json'))
print(d['hauptagent']['fallback']['model'] + ':' + d['hauptagent']['fallback']['effort'])
")"
[ "$FB1" = "qwen3.5-4b:medium" ] \
  && ok "11: Vorbelegung ohne Einstellung ist qwen3.5-4b:medium" \
  || bad "11: Vorbelegung ohne Einstellung" "'$FB1'"

mkdir -p "$BASIS/settings-heim/.claude/workbench"
cat > "$BASIS/settings-heim/.claude/workbench/settings.json" <<'EOF'
{"agents": {"fallbackModell": "haiku45:low"}}
EOF
IDFB2AUS="$(python3 "$REPO/wb-aufgabe" anlegen "$PROJ" --ziel "Fallback aus Einstellung $MARKE" --fertig x \
    --vorrat "$VORRAT" --base "$BASIS/settings-heim")"
IDFB2="$(printf '%s' "$IDFB2AUS" | tail -1)"
FB2="$(python3 -c "
import json
d = json.load(open('$PROJ/.companion/auftraege/$IDFB2.json'))
print(d['hauptagent']['fallback']['model'] + ':' + d['hauptagent']['fallback']['effort'])
")"
[ "$FB2" = "haiku45:low" ] && ok "11: Vorbelegung aus settings.json (agents.fallbackModell) ist haiku45:low" \
                            || bad "11: Vorbelegung aus Einstellung" "'$FB2'"

IDFB3AUS="$(wa anlegen "$PROJ" --ziel "Fallback keins $MARKE" --fertig x --fallback keins)"
IDFB3="$(printf '%s' "$IDFB3AUS" | tail -1)"
FB3="$(python3 -c "
import json
d = json.load(open('$PROJ/.companion/auftraege/$IDFB3.json'))
print(d['hauptagent']['fallback'])
")"
[ "$FB3" = "None" ] && ok "11: --fallback keins -> hauptagent.fallback ist null" || bad "11: --fallback keins" "'$FB3'"

AUSFABLE="$(wa anlegen "$PROJ" --ziel "Fable Fallback $MARKE" --fertig x --fallback "fable51:medium")"
RCFABLE=$?
[ "$RCFABLE" -eq 2 ] && ok "11: ein Fable-Modell als Fallback -> Exit 2" || bad "11: Fable-Fallback" "rc=$RCFABLE -- $AUSFABLE"
printf '%s' "$AUSFABLE" | grep -qi "fable" && ok "11: die Meldung nennt Fable" || bad "11: Meldungstext Fable" "$AUSFABLE"

AUSDLCLOUD="$(wa anlegen "$PROJ" --ziel "Datenlokal Cloud-Fallback $MARKE" --fertig x --daten-lokal \
    --hauptagent qwen3.5-4b:medium --fallback opus55:high)"
RCDLCLOUD=$?
[ "$RCDLCLOUD" -eq 2 ] && ok "11: --daten-lokal mit Cloud-Fallback -> Exit 2" \
                        || bad "11: daten-lokal Cloud-Fallback" "rc=$RCDLCLOUD -- $AUSDLCLOUD"

IDDLOK_AUS="$(wa anlegen "$PROJ" --ziel "Datenlokal lokaler Fallback $MARKE" --fertig x --daten-lokal \
    --hauptagent qwen3.5-4b:medium --fallback qwen3.5-4b:medium)"
RCDLOK=$?
[ "$RCDLOK" -eq 0 ] && ok "11: --daten-lokal mit lokalem Fallback (qwen3.5-4b) -> Exit 0" \
                     || bad "11: daten-lokal lokaler Fallback" "rc=$RCDLOK -- $IDDLOK_AUS"

IDALIAS="$(wa anlegen "$PROJ" --ziel "Alias Hauptagent $MARKE" --fertig x --hauptagent sonnet5:high | tail -1)"
MALIAS="$(python3 -c "
import json
d = json.load(open('$PROJ/.companion/auftraege/$IDALIAS.json'))
print(d['hauptagent']['model'], d['model'], d['hauptagent']['effort'])
" 2>&1)"
[ "$MALIAS" = "claude-sonnet-5 claude-sonnet-5 high" ] \
  && ok "11: --hauptagent sonnet5:high speichert die Registry-Kennung claude-sonnet-5" || bad "11: Alias Hauptagent" "'$MALIAS'"
AUSUNB="$(wa anlegen "$PROJ" --ziel "Unbekanntes Modell $MARKE" --fertig x --hauptagent gibtsnicht:high)"
RCUNB=$?
[ "$RCUNB" -eq 2 ] && printf '%s' "$AUSUNB" | grep -q "nicht in der Registry" \
  && ok "11: --hauptagent mit unbekanntem Modell -> Exit 2, 'nicht in der Registry'" || bad "11: unbekanntes Modell" "rc=$RCUNB -- $AUSUNB"

wa verlauf "$IDFB1" fallback-gewechselt "Wechsel auf Fallback" --grund "Tageslimit erreicht" >/dev/null
LETZTER_EINTRAG="$(python3 -c "
import json
v = json.load(open('$PROJ/.companion/auftraege/$IDFB1.verlauf.json'))
e = v['verlauf'][-1]
print(e['art'] + '|' + e.get('grund', ''))
")"
[ "$LETZTER_EINTRAG" = "fallback-gewechselt|Tageslimit erreicht" ] \
  && ok "11: 'verlauf ... fallback-gewechselt ... --grund' haengt einen Eintrag mit Grund an" \
  || bad "11: fallback-gewechselt Eintrag" "'$LETZTER_EINTRAG'"

AUSLISTE="$(wa liste --json)"
HAT_HAUPTAGENT="$(printf '%s' "$AUSLISTE" | python3 -c "
import json, sys
d = json.load(sys.stdin)
treffer = [e for e in d if e['id'] == '$IDFB1']
print('ok' if treffer and treffer[0].get('hauptagent', {}).get('fallback') else 'FEHLT')
")"
[ "$HAT_HAUPTAGENT" = "ok" ] && ok "11: liste --json gibt hauptagent mit fallback aus" \
                              || bad "11: liste --json hauptagent" "$HAT_HAUPTAGENT"

echo
echo "-- 11b: Bau-Schritt 2 -- pfade, sitzung, steckt_vorher, naechste, aufnehmen, verschieben --"
# Eigener Vorrat, damit die Rangfolge nicht von den Aufgaben der Abschnitte oben abhaengt.
VORRAT2="$BASIS/vorrat2"
wa2() {
  env HOME="$TESTHOME" PATH="$PYBIN_DIR:/usr/bin:/bin" TMUX= TMUX_PANE= WB_TRAEGER_NACHSEHEN=0 \
      python3 "$REPO/wb-aufgabe" "$@" --vorrat "$VORRAT2" --base "$BASIS" 2>&1
}
v2() {
  python3 - "$1" "$2" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
print(eval(sys.argv[2], {"v": v, "E": v.get("verlauf") or []}))
PY
}
gt() { env HOME="$TESTHOME" GIT_CONFIG_NOSYSTEM=1 git -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"; }
P2A="$BASIS/p2a-$MARKE"; P2B="$BASIS/p2b-$MARKE"; mkdir -p "$P2A" "$P2B"
X1="$(wa2 anlegen "$P2A" --ziel "X1 $MARKE" --fertig x --maschine mac | tail -1)"
X2="$(wa2 anlegen "$P2A" --ziel "X2 $MARKE" --fertig x --maschine mac | tail -1)"
X3="$(wa2 anlegen "$P2B" --ziel "X3 $MARKE" --fertig x --maschine mac | tail -1)"
for x in "$X1" "$X2" "$X3"; do wa2 freigeben "$x" --mensch-beleg "$BELEG" >/dev/null; done
VX1="$P2A/.companion/auftraege/$X1.verlauf.json"
VX3="$P2B/.companion/auftraege/$X3.verlauf.json"

wa2 pfade "$X1" setzen a.txt b/c.txt >/dev/null
wa2 pfade "$X1" setzen a.txt >/dev/null
[ "$(v2 "$VX1" 'v["pfade"]')" = "['a.txt', 'b/c.txt']" ] && ok "11b: pfade setzen fuehrt jeden Pfad einmal" \
  || bad "11b: pfade setzen" "$(v2 "$VX1" 'v["pfade"]')"
wa2 pfade "$X1" entfernen a.txt >/dev/null
[ "$(v2 "$VX1" 'v["pfade"]')" = "['b/c.txt']" ] && ok "11b: pfade entfernen nimmt genau den Pfad heraus" \
  || bad "11b: pfade entfernen" "$(v2 "$VX1" 'v["pfade"]')"
wa2 pfade "$X1" entfernen gibt-es-nicht >/dev/null; RCP=$?
[ "$RCP" -eq 2 ] && ok "11b: pfade entfernen eines unbekannten Pfads -> Exit 2" || bad "11b: pfade entfernen unbekannt" "rc=$RCP"

wa2 sitzung "$X1" setzen --tmux-session s1 --pane %7 --pid 4242 >/dev/null
[ "$(v2 "$VX1" '(v["hauptagent_sitzung"]["tmux_session"], v["hauptagent_sitzung"]["pane"], v["hauptagent_sitzung"]["pid"])')" = "('s1', '%7', 4242)" ] \
  && ok "11b: sitzung setzen schreibt tmux_session, pane und pid" || bad "11b: sitzung setzen" "$(v2 "$VX1" 'v["hauptagent_sitzung"]')"
wa2 sitzung "$X1" gesehen >/dev/null
[ "$(v2 "$VX1" 'v["hauptagent_sitzung"].get("zuletzt_gesehen") is not None')" = "True" ] \
  && ok "11b: sitzung gesehen stempelt zuletzt_gesehen" || bad "11b: sitzung gesehen" "$(v2 "$VX1" 'v["hauptagent_sitzung"]')"
[ "$(v2 "$VX1" 'sum(1 for e in E if e["art"]=="sitzung")')" -ge 1 ] \
  && ok "11b: sitzung schreibt die Verlaufsart 'sitzung', nicht 'gestartet'" || bad "11b: Verlaufsart sitzung"
wa2 sitzung "$X1" leeren >/dev/null
[ "$(v2 "$VX1" 'v["hauptagent_sitzung"]')" = "None" ] && ok "11b: sitzung leeren loescht das Feld" || bad "11b: sitzung leeren"

wa2 stand "$X3" steckt --grund Umgebung >/dev/null
[ "$(v2 "$VX3" '(v["stand"], v["grund"], v["steckt_vorher"])')" = "('steckt', 'Umgebung', 'offen')" ] \
  && ok "11b: steckt merkt den vorigen Stand in steckt_vorher" || bad "11b: steckt_vorher" "$(v2 "$VX3" '(v["stand"], v["grund"], v["steckt_vorher"])')"
wa2 stand "$X3" offen >/dev/null
[ "$(v2 "$VX3" 'v["steckt_vorher"]')" = "None" ] && ok "11b: der Weg zurueck leert steckt_vorher" || bad "11b: steckt_vorher geleert"

N1="$(wa2 naechste --maschine mac --json)"
[ "$(printf '%s' "$N1" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')" = "$X1" ] \
  && ok "11b: naechste nennt die vorderste freigegebene offene Aufgabe" || bad "11b: naechste vorderste" "$N1"
wa2 stand "$X1" läuft >/dev/null
N2="$(wa2 naechste --maschine mac --json)"
[ "$(printf '%s' "$N2" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["id"], d["zurueckgestellt"])')" \
  = "$X3 [{'id': '$X2', 'grund': 'Repo belegt durch Aufgabe $X1'}]" ] \
  && ok "11b: naechste ueberspringt das belegte Repo und nennt den Grund" || bad "11b: naechste Repo belegt" "$N2"
N3="$(wa2 naechste --maschine mac --json --ausser "$X3" | grep '^{')"; RCN3=${PIPESTATUS[0]}
[ "$RCN3" -eq 1 ] && [ "$(printf '%s' "$N3" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')" = "None" ] \
  && ok "11b: naechste --ausser -> keine Kandidatin, Exit 1 mit id null" || bad "11b: naechste --ausser" "rc=$RCN3 $N3"
wa2 naechste --maschine host2 --json >/dev/null 2>&1; RCN4=$?
[ "$RCN4" -eq 1 ] && ok "11b: naechste --maschine filtert nach Maschine" || bad "11b: naechste --maschine" "rc=$RCN4"

rm -f "$VORRAT2/$X3.json"
wa2 aufnehmen "$P2B" "$X3" >/dev/null
[ "$(python3 -c "import json;print(json.load(open('$VORRAT2/$X3.json'))['maschine'])" 2>/dev/null)" = "mac" ] \
  && ok "11b: aufnehmen legt den Vorratseintrag aus der Auftragsdatei an" || bad "11b: aufnehmen"
AUSAUF="$(wa2 aufnehmen "$P2B" "$X3")"
printf '%s' "$AUSAUF" | grep -q "schon im Vorrat" && ok "11b: ein zweites aufnehmen tut nichts" || bad "11b: aufnehmen idempotent" "$AUSAUF"

wa2 worker "$X2" setzen w1 --rolle tester --zustand arbeitet >/dev/null
wa2 verschieben "$X2" --nach host2 >/dev/null; RCV1=$?
[ "$RCV1" -eq 2 ] && ok "11b: verschieben mit arbeitendem Worker -> Exit 2" || bad "11b: verschieben Worker" "rc=$RCV1"
XD="$(wa2 anlegen "$P2B" --ziel "XD $MARKE" --fertig x --maschine mac --daten-lokal --hauptagent qwen3.5-4b:medium --fallback keins | tail -1)"
wa2 verschieben "$XD" --nach host2 >/dev/null; RCV2=$?
[ "$RCV2" -eq 2 ] && ok "11b: verschieben bei 'Daten bleiben auf der Maschine' -> Exit 2" || bad "11b: verschieben daten-lokal" "rc=$RCV2"
REMOTE="$BASIS/remote-$MARKE.git"; P2G="$BASIS/p2g-$MARKE"
gt init -q --bare "$REMOTE"; gt init -q "$P2G"
XG="$(wa2 anlegen "$P2G" --ziel "XG $MARKE" --fertig x --maschine mac | tail -1)"
gt -C "$P2G" add .gitignore && gt -C "$P2G" commit -q -m init && gt -C "$P2G" remote add origin "$REMOTE" \
  && gt -C "$P2G" push -q -u origin HEAD 2>/dev/null
wa2 verschieben "$XG" --nach host2 >/dev/null; RCV3=$?
[ "$RCV3" -eq 0 ] && [ "$(python3 -c "import json;print(json.load(open('$VORRAT2/$XG.json'))['maschine'])")" = "host2" ] \
  && [ "$(v2 "$P2G/.companion/auftraege/$XG.verlauf.json" '(v["maschine"], E[-1]["art"])')" = "('host2', 'verschoben')" ] \
  && ok "11b: verschieben bei gepushtem Stand stellt Vorrat und Verlauf um" || bad "11b: verschieben gepusht" "rc=$RCV3"
gt -C "$P2G" commit -q --allow-empty -m zwei
wa2 verschieben "$XG" --nach mac >/dev/null; RCV4=$?
[ "$RCV4" -eq 2 ] && ok "11b: verschieben mit ungepushtem Commit -> Exit 2" || bad "11b: verschieben ungepusht" "rc=$RCV4"

echo
echo "-- 11c: Nachzug nach dem Reviewer-Pass (Auftrag traeger Nr. 2) --"
grep -qx ".companion/auftraege/" "$P2G/.gitignore" && [ "$(v2 "$P2G/.companion/auftraege/$XG.verlauf.json" 'sum(1 for e in E if e["art"]=="gitignore")')" = 1 ] \
  && ok "11c: anlegen ergaenzt .companion/auftraege/ in .gitignore eines git-Projekts, mit Verlaufseintrag" || bad "11c: gitignore" "$(cat "$P2G/.gitignore" 2>/dev/null)"
[ ! -e "$P2B/.gitignore" ] && ok "11c: ausserhalb von git keine .gitignore" || bad "11c: .gitignore ohne git"

P2C="$BASIS/p2c-$MARKE"; mkdir -p "$P2C"
Y1="$(wa2 anlegen "$P2C" --ziel "Y1 $MARKE" --fertig x --maschine mac | tail -1)"
wa2 freigeben "$Y1" --mensch-beleg "$BELEG" >/dev/null
AY="$P2C/.companion/auftraege/$Y1.json"
wa2 zeigen "$Y1" | grep -q "Freigabe: gültig" && ok "11c: zeigen nennt die gueltige Freigabe" || bad "11c: zeigen gueltig" "$(wa2 zeigen "$Y1")"
python3 -c "import json;p='$AY';a=json.load(open(p));a['goal']+=' geaendert';json.dump(a,open(p,'w'))"
wa2 zeigen "$Y1" | grep -q "Freigabe: UNGÜLTIG" && ok "11c: zeigen erkennt den gebrochenen Hash" || bad "11c: zeigen ungueltig" "$(wa2 zeigen "$Y1")"
wa2 pruefen "$Y1" >/dev/null 2>&1; RCPR=$?
[ "$RCPR" -eq 2 ] && ok "11c: pruefen meldet den gebrochenen Hash (Exit 2)" || bad "11c: pruefen" "rc=$RCPR"
NY="$(wa2 naechste --maschine mac --json --ausser "$X3" | grep '^{')"
[ "$(printf '%s' "$NY" | python3 -c "import json,sys;d=json.load(sys.stdin);print(any(z['id']=='$Y1' and z['grund']=='Freigabe ungültig' and z.get('warten') for z in d['zurueckgestellt']), d['id'])")" = "True None" ] \
  && ok "11c: naechste startet keine Aufgabe mit ungueltiger Freigabe und meldet sie zum Warten" || bad "11c: naechste Freigabe" "$NY"

for p in . .. "" /etc/passwd "a/../b" "../aussen"; do
  wa2 pfade "$X1" setzen "$p" >/dev/null 2>&1; RCPF=$?
  [ "$RCPF" -eq 2 ] && ok "11c: pfade setzen '$p' abgelehnt" || bad "11c: pfade setzen '$p'" "rc=$RCPF"
done
wa2 pfade "$X1" setzen unterordner/ >/dev/null 2>&1 && ok "11c: ein Verzeichnis im Repo ist erlaubt" || bad "11c: Verzeichnis abgelehnt"

VX2="$P2A/.companion/auftraege/$X2.verlauf.json"
for i in $(seq 1 30); do
  wa2 verlauf "$X2" notiz "n$i" >/dev/null 2>&1 &
  wa2 sitzung "$X2" gesehen >/dev/null 2>&1 &
done
wait
[ "$(v2 "$VX2" 'sum(1 for e in E if e["art"]=="notiz")')" = 30 ] && ok "11c: D9: 30 parallele Schreiber, 30 Eintraege" \
  || bad "11c: D9 verlorene Eintraege" "$(v2 "$VX2" 'sum(1 for e in E if e["art"]=="notiz")') von 30"

wa2 verlauf "$X2" wach "ohne Zeit" >/dev/null 2>&1; RCW=$?
[ "$RCW" -eq 2 ] && ok "11c: wach ohne --bis -> Exit 2" || bad "11c: wach ohne bis" "rc=$RCW"
wa2 verlauf "$X2" wach "ScheduleWakeup" --bis 2099-01-01T00:00:00Z >/dev/null 2>&1
[ "$(v2 "$VX2" '[e.get("bis") for e in E if e["art"]=="wach"]')" = "['2099-01-01T00:00:00Z']" ] \
  && ok "11c: wach --bis steht mit Zeit im Verlauf" || bad "11c: wach --bis"

AUSV="$(wa2 verschieben "$X1" --nach host2)"; RCV5=$?
[ "$RCV5" -eq 2 ] && printf '%s' "$AUSV" | grep -q "läuft" && ok "11c: D7: verschieben einer laufenden Aufgabe -> Exit 2" || bad "11c: verschieben laeuft" "rc=$RCV5 $AUSV"
wa2 sitzung "$X3" setzen --pane %9 --pid $$ >/dev/null
AUSV="$(wa2 verschieben "$X3" --nach host2)"; RCV6=$?
[ "$RCV6" -eq 2 ] && printf '%s' "$AUSV" | grep -q "lebenden Hauptagenten" && ok "11c: verschieben bei lebender hauptagent_sitzung -> Exit 2" || bad "11c: verschieben Sitzung" "rc=$RCV6 $AUSV"

VORRAT3="$BASIS/vorrat3"
env HOME="$TESTHOME" PATH="$PYBIN_DIR:/usr/bin:/bin" WB_TRAEGER_NACHSEHEN=0 python3 "$REPO/wb-aufgabe" aufnehmen "$P2G" "$XG" \
  --vorrat "$VORRAT3" --base "$BASIS" >/dev/null 2>&1
[ "$(python3 -c "import json;print(json.load(open('$VORRAT3/$XG.json'))['maschine'])" 2>/dev/null)" = "host2" ] \
  && ok "11c: aufnehmen nimmt die aktuelle Maschine aus dem Verlauf" || bad "11c: aufnehmen Verlauf-Maschine"
rm -f "$VORRAT3/$XG.json"
env HOME="$TESTHOME" PATH="$PYBIN_DIR:/usr/bin:/bin" WB_TRAEGER_NACHSEHEN=0 python3 "$REPO/wb-aufgabe" aufnehmen "$P2G" "$XG" \
  --maschine hostco --vorrat "$VORRAT3" --base "$BASIS" >/dev/null 2>&1
[ "$(python3 -c "import json;print(json.load(open('$VORRAT3/$XG.json'))['maschine'])" 2>/dev/null)" = "hostco" ] \
  && ok "11c: aufnehmen --maschine setzt die Maschine" || bad "11c: aufnehmen --maschine"

mkdir -p "$TESTHOME/anstoss"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/anstoss/log"\n' "$TESTHOME" > "$TESTHOME/anstoss/wb-traeger"
chmod +x "$TESTHOME/anstoss/wb-traeger"
Y2="$(wa2 anlegen "$P2C" --ziel "Y2 $MARKE" --fertig x --maschine mac | tail -1)"
env HOME="$TESTHOME" PATH="$TESTHOME/anstoss:$PYBIN_DIR:/usr/bin:/bin" TMUX= TMUX_PANE= \
    python3 "$REPO/wb-aufgabe" freigeben "$Y2" --mensch-beleg "$BELEG" --vorrat "$VORRAT2" --base "$BASIS" >/dev/null 2>&1
ERW="nachsehen --base $(python3 -c 'import os,sys;print(os.path.abspath(sys.argv[1]))' "$BASIS") --vorrat $(python3 -c 'import os,sys;print(os.path.abspath(sys.argv[1]))' "$VORRAT2")"
i=0; while [ $i -lt 25 ] && ! [ -s "$TESTHOME/anstoss/log" ]; do sleep 0.2; i=$((i+1)); done
grep -qxF "$ERW" "$TESTHOME/anstoss/log" 2>/dev/null && ok "11c: Hinweis 16: freigeben stoesst den Traeger mit --base und --vorrat an" \
  || bad "11c: anstossen" "$(cat "$TESTHOME/anstoss/log" 2>/dev/null) / erwartet: $ERW"

echo
echo "-- 12: die echte Umgebung blieb unberuehrt --"
[ ! -e "$HOME/.claude/workbench/vorrat/$ID.json" ] \
  && ok "12: kein Eintrag unter dem ECHTEN ~/.claude/workbench/vorrat" \
  || bad "12: es wurde in den echten Vorrat geschrieben"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
