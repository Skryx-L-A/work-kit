#!/bin/bash
# test-belegung-ueberfaellig-hook.sh — der SessionStart-Hook, der eine ueberfaellige
# Speicher-Belegung meldet.
#
# Anlass (2026-08-30): der MLX-Server von lmgamma lief nach dem Sessionende der Vorsitzung
# 18,5 Stunden weiter und hielt 15,9 GiB. Das Belegungsbuch sagte es die ganze Zeit — in der
# ersten Zeile von `wb-belegung wer` stand "UEBERFAELLIG (die Frist ist seit 934 min um)".
# Nur fragt beim Sessionstart niemand danach. Der Hook legt die Meldung von selbst in den
# Kontext; diese Suite haelt die drei Faelle fest, auf die es ankommt.
#
# Der wichtigste davon ist das SCHWEIGEN: ein Hook, der bei jeder gesunden Belegung eine
# Zeile schreibt, wird nach drei Sessions ueberlesen, und dann meldet er die echte
# Ueberfaelligkeit an ein Publikum, das nicht mehr hinsieht.
#
# ISOLATION: der Hook liest ueber WB_BELEGUNG_JSON aus einer Datei unter mktemp. Kein
# Zugriff auf das echte Belegungsbuch, kein Prozess ausser python3.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/hooks/sessionstart-belegung-ueberfaellig.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok    $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

buch() {  # buch <datei> <zustand> <alter-in-minuten>
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys, time
datei, zustand, alter = sys.argv[1], sys.argv[2], int(sys.argv[3])
json.dump({"belegungen": [{
    "id": "b4a554", "gb": 17.3, "_zustand": zustand,
    "zweck": "wb-mlx-server: MLX-Server fuer lmgamma-27b (lmgamma), Port 8081",
    "seit": time.time() - alter * 60,
    "halter": {"sitzung": "wb-AI", "pane": "%1"},
}]}, open(datei, "w"))
PY
}

echo "== 1  Eine gesunde Belegung: der Hook schweigt =="
buch "$TMP/offen.json" offen 20
AUSGABE="$(WB_BELEGUNG_JSON="$TMP/offen.json" bash "$HOOK" 2>&1)"
[ -z "$AUSGABE" ] && ok "keine Zeile bei einer offenen Belegung" \
                  || bad "Hook redet, obwohl nichts ueberfaellig ist: $AUSGABE"

echo "== 2  Eine ueberfaellige Belegung: Kennung, Groesse, Alter, Halter =="
buch "$TMP/ueber.json" ueberfaellig 1114
AUSGABE="$(WB_BELEGUNG_JSON="$TMP/ueber.json" bash "$HOOK" 2>&1)"
case "$AUSGABE" in
  *UEBERFAELLIG*) ok "der Zustand steht drin" ;;
  *) bad "kein UEBERFAELLIG in der Ausgabe: $AUSGABE" ;;
esac
case "$AUSGABE" in
  *"17,3 GiB"*) ok "die Groesse steht drin" ;;
  *) bad "keine Groesse in der Ausgabe: $AUSGABE" ;;
esac
case "$AUSGABE" in
  *"1114 min"*) ok "das Alter steht drin" ;;
  *) bad "kein Alter in der Ausgabe: $AUSGABE" ;;
esac
case "$AUSGABE" in
  *wb-AI*) ok "der Halter steht drin" ;;
  *) bad "kein Halter in der Ausgabe: $AUSGABE" ;;
esac
case "$AUSGABE" in
  *"wb-mlx-server stop"*) ok "der Ausweg steht drin" ;;
  *) bad "kein Handgriff genannt: $AUSGABE" ;;
esac

echo "== 3  Eine tote Belegung wird ebenso gemeldet =="
buch "$TMP/tot.json" tot 300
AUSGABE="$(WB_BELEGUNG_JSON="$TMP/tot.json" bash "$HOOK" 2>&1)"
case "$AUSGABE" in
  *TOT*) ok "auch der tote Eintrag kommt in den Kontext" ;;
  *) bad "tote Belegung bleibt unerwaehnt: $AUSGABE" ;;
esac

echo "== 4  Kaputte Eingabe darf den Session-Start nicht stoeren =="
echo 'kein json' > "$TMP/muell.json"
AUSGABE="$(WB_BELEGUNG_JSON="$TMP/muell.json" bash "$HOOK" 2>&1)"; RC=$?
[ "$RC" = "0" ] && ok "Exit 0 trotz Muell" || bad "Exit $RC bei kaputter Eingabe"
[ -z "$AUSGABE" ] && ok "keine Zeile bei kaputter Eingabe" \
                  || bad "Hook redet bei Muell: $AUSGABE"

AUSGABE="$(WB_BELEGUNG_JSON="$TMP/gibtsnicht.json" bash "$HOOK" 2>&1)"; RC=$?
[ "$RC" = "0" ] && [ -z "$AUSGABE" ] && ok "fehlende Datei bleibt still, Exit 0" \
                  || bad "fehlende Datei: rc=$RC, Ausgabe=$AUSGABE"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = "0" ]
