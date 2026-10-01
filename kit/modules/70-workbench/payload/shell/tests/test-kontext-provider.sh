#!/usr/bin/env bash
# test-kontext-provider.sh -- der Modell-Eintrag, den pi bekommt, stimmt in
# BEIDEM: im Kontextfenster und im Namen (2026-08-21).
#
# DER BEFUND. In `wb-kontext ensure` stand ein frueher Kurzschluss:
#
#     if basis_eintrag and basis_eintrag.get("contextWindow") == stufe:
#         print(bedient_als or modelref)
#         return
#
# Zwei Fehler in drei Zeilen, beide im Betrieb wirksam:
#
#   1  Er prueft nur das Kontextfenster, nicht die id. Der Provider mlx-local
#      trug einen Eintrag mit der id $HOME/AI/mlx-models/lmgamma-27b-mlx-4bit
#      und contextWindow 262144, waehrend der laufende Server ausschliesslich
#      "mtplx-lmgamma-27b-optimized-speed" bedient. Der Kurzschluss feuerte, gab
#      den bedienten Namen zurueck und liess den Eintrag mit der Pfad-id stehen --
#      pi fragte danach einen Provider nach einem Modell, das er nicht fuehrt.
#   2  Er druckte kein `provider=`. wb-code liest die Zeile und laesst PIPROVIDER
#      sonst auf dem Vorgabewert stehen: auf diesem Pfad blieb der Provider
#      ungesetzt, waehrend das Modell schon den neuen Namen trug.
#
# DIE ZUSAGEN, die hier gemessen werden:
#   1  Richtiges Fenster, aber PFAD-id, waehrend der Server anders heisst: der
#      Kurzschluss feuert NICHT, und danach traegt der Eintrag den bedienten Namen.
#   2  Stimmt beides, feuert er -- und druckt seinen Provider mit.
#   3  Beide Zeilen sind da und werden so gelesen, wie wb-code sie liest.
#   4  Ein alter Eintrag mit PFAD-id in einem Stufen-Provider wird ERSETZT, nicht
#      verdoppelt. Das ist die Selbstheilung: der naechste Lauf stellt richtig,
#      was ein frueherer falsch hinterlassen hat.
#   5  Ohne `--bedient-als` bleibt alles wie vorher -- der modelRef ist dann der Name.
#
# ISOLATION, und sie wird NACHGEPRUEFT statt angenommen: umgelenktes HOME
# (`mktemp -d`), eine Stellvertreter-`models.json` darin. Zusage 0 unten misst,
# dass das Werkzeug wirklich auf dieser Datei arbeitet und nicht auf der echten --
# eine Werkzeug- oder Pfadsuche, die vor dem umgelenkten HOME rangiert, hebelt
# sonst jeden Stellvertreter still aus (eigene Lehre vom 21.08., sie hat acht
# Zusagen in zwei anderen Suiten umgeworfen).
#
# Es wird kein Modell geladen, kein Server gestartet und die echte
# ~/.pi/agent/models.json nicht angefasst.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="${WB_KONTEXT:-$REPO/wb-kontext}"
FAKEHOME="$(mktemp -d)"
WORK="$(mktemp -d)"
trap 'rm -rf "$FAKEHOME" "$WORK"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
echo "Geprueft: $TOOL"

PI="$FAKEHOME/.pi/agent/models.json"
mkdir -p "$(dirname "$PI")"

PFAD="/pfad/zu/lmgamma-27b-mlx-4bit"
BEDIENT="mtplx-lmgamma-27b-optimized-speed"

# `ensure_mlx` wird DIREKT aufgerufen, nicht ueber die Befehlszeile: die
# Auflösung eines Modellnamens haengt an der Registry und an wb-state, und die
# gehoeren nicht zu dem, was hier geprueft wird. Die Verdrahtung der
# Befehlszeile prueft Zusage 3 getrennt.
lauf() {   # <stufe> <label> <bedient_als> -> die zwei gedruckten Zeilen
    HOME="$FAKEHOME" python3 - "$TOOL" "$1" "$2" "$3" "$PFAD" <<'PY' 2>&1
import sys, types
quelle = open(sys.argv[1], encoding="utf-8").read()
mod = types.ModuleType("wbk"); mod.__file__ = sys.argv[1]
exec(compile(quelle, sys.argv[1], "exec"), mod.__dict__)
# argv: 1=Werkzeug, 2=Stufe, 3=Label, 4=bedient_als, 5=modelRef
mod.ensure_mlx(sys.argv[5], int(sys.argv[2]), sys.argv[3], sys.argv[4])
PY
}

eintraege() {   # <provider> -> "id|ctx" je Zeile
    python3 - "$PI" "$1" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
p = (d.get("providers") or {}).get(sys.argv[2]) or {}
for m in p.get("models", []):
    print("%s|%s" % (m.get("id"), m.get("contextWindow")))
PY
}

echo "== 0  Der Test arbeitet wirklich auf dem Stellvertreter =="
ZIELDATEI="$(HOME="$FAKEHOME" python3 - "$TOOL" <<'PY' 2>&1
import sys, types
quelle = open(sys.argv[1], encoding="utf-8").read()
mod = types.ModuleType("wbk"); mod.__file__ = sys.argv[1]
exec(compile(quelle, sys.argv[1], "exec"), mod.__dict__)
print(mod.PI_MODELS)
PY
)"
if [ "$ZIELDATEI" = "$PI" ]; then
    ok "das Werkzeug schreibt nach '$PI', nicht in das echte HOME"
else
    bad "das Werkzeug wuerde nach '$ZIELDATEI' schreiben -- der Stellvertreter greift NICHT"
    echo "  bestanden: $pass, gescheitert: $fail"
    exit 1
fi

echo "== 1  Richtiges Fenster, falsche id: der Kurzschluss darf nicht feuern =="
cat > "$PI" <<EOF
{ "providers": { "mlx-local": {
    "baseUrl": "http://127.0.0.1:8080/v1", "api": "openai-completions", "apiKey": "mlx",
    "models": [ { "id": "$PFAD", "contextWindow": 262144, "reasoning": true } ] } } }
EOF
AUS="$(lauf 262144 256k "$BEDIENT")"
Z1="$(printf '%s\n' "$AUS" | sed -n '1p')"
Z2="$(printf '%s\n' "$AUS" | sed -n 's/^provider=//p')"
[ "$Z1" = "$BEDIENT" ] && ok "1a: die erste Zeile ist der bediente Name" \
    || bad "1a: erste Zeile '$Z1', erwartet '$BEDIENT' (Ausgabe: $AUS)"
[ "$Z2" = "mlx-local-256k" ] \
    && ok "1b: der Provider ist der Stufen-Provider, nicht der Basisprovider" \
    || bad "1b: provider= war '$Z2', erwartet 'mlx-local-256k' (Ausgabe: $AUS)"
if [ "$(eintraege mlx-local-256k)" = "$BEDIENT|262144" ]; then
    ok "1c: der geschriebene Eintrag traegt den bedienten Namen und die Stufe"
else
    bad "1c: der Eintrag stimmt nicht: $(eintraege mlx-local-256k)"
fi
# Der Kurzschluss haette gar nichts geschrieben -- dass es den Provider gibt, IST
# der Beweis, dass er nicht gefeuert hat.
[ -n "$(eintraege mlx-local-256k)" ] \
    && ok "1d: es wurde geschrieben, der Kurzschluss hat nicht gefeuert" \
    || bad "1d: kein Stufen-Provider entstanden -- der Kurzschluss hat gefeuert"
# Und die Felder des Basis-Eintrags sind mitgekommen (reasoning), sonst waere
# das Denken auf der Kopie still aus.
python3 -c "
import json,sys
d=json.load(open('$PI'))
m=d['providers']['mlx-local-256k']['models'][0]
sys.exit(0 if m.get('reasoning') is True else 1)" \
    && ok "1e: die Felder des Basis-Eintrags sind mitgekommen (reasoning)" \
    || bad "1e: die Kopie hat die Felder des Basis-Eintrags verloren"

echo "== 2  Stimmt beides, feuert der Kurzschluss -- und nennt seinen Provider =="
cat > "$PI" <<EOF
{ "providers": { "mlx-local": {
    "baseUrl": "http://127.0.0.1:8080/v1", "api": "openai-completions", "apiKey": "mlx",
    "models": [ { "id": "$BEDIENT", "contextWindow": 262144 } ] } } }
EOF
AUS="$(lauf 262144 256k "$BEDIENT")"
Z1="$(printf '%s\n' "$AUS" | sed -n '1p')"
Z2="$(printf '%s\n' "$AUS" | sed -n 's/^provider=//p')"
[ "$Z1" = "$BEDIENT" ] && ok "2a: die erste Zeile ist der bediente Name" \
    || bad "2a: erste Zeile '$Z1' (Ausgabe: $AUS)"
[ "$Z2" = "mlx-local" ] \
    && ok "2b: der Kurzschluss druckt seinen Provider mit -- frueher fehlte die Zeile ganz" \
    || bad "2b: provider= war '$Z2', erwartet 'mlx-local' (Ausgabe: $AUS)"
[ -z "$(eintraege mlx-local-256k)" ] \
    && ok "2c: es wurde nichts geschrieben -- genau dafuer gibt es den Kurzschluss" \
    || bad "2c: es entstand doch ein Stufen-Provider: $(eintraege mlx-local-256k)"

echo "== 3  Beide Zeilen, so gelesen wie wb-code sie liest =="
# wb-code: PIMODEL aus 'head -1', KPROV aus "sed -n 's/^provider=//p'".
grep -q "head -1" "$REPO/wb-code" && grep -q "s/\^provider=//p" "$REPO/wb-code" \
    && ok "3a: wb-code liest beide Zeilen genau so" \
    || bad "3a: wb-code liest die Zeilen anders als hier geprueft"
grep -q -- "--bedient-als" "$REPO/wb-code" \
    && ok "3b: wb-code reicht den bedienten Namen an wb-kontext weiter" \
    || bad "3b: wb-code reicht --bedient-als nicht weiter"
"$TOOL" ensure --help 2>&1 | grep -q -- "--bedient-als" \
    && ok "3c: 'wb-kontext ensure' kennt --bedient-als auf der Befehlszeile" \
    || bad "3c: --bedient-als fehlt in der Befehlszeile von ensure"

echo "== 4  Selbstheilung: ein alter Eintrag mit PFAD-id wird ERSETZT =="
cat > "$PI" <<EOF
{ "providers": {
  "mlx-local": { "baseUrl": "http://127.0.0.1:8080/v1", "api": "openai-completions",
    "models": [ { "id": "$PFAD", "contextWindow": 262144 } ] },
  "mlx-local-64k": { "baseUrl": "http://127.0.0.1:8080/v1", "api": "openai-completions",
    "models": [ { "id": "$PFAD", "contextWindow": 65536 } ] } } }
EOF
AUS="$(lauf 65536 64k "$BEDIENT")"
ZEILEN="$(eintraege mlx-local-64k)"
if [ "$ZEILEN" = "$BEDIENT|65536" ]; then
    ok "4: der alte Eintrag mit PFAD-id ist ERSETZT, kein zweiter daneben"
else
    bad "4: der Stufen-Provider traegt jetzt: $ZEILEN"
fi

echo "== 5  Ohne --bedient-als bleibt alles wie vorher =="
cat > "$PI" <<EOF
{ "providers": { "mlx-local": {
    "baseUrl": "http://127.0.0.1:8080/v1", "api": "openai-completions",
    "models": [ { "id": "$PFAD", "contextWindow": 262144 } ] } } }
EOF
AUS="$(lauf 32768 32k "")"
Z1="$(printf '%s\n' "$AUS" | sed -n '1p')"
[ "$Z1" = "$PFAD" ] && ok "5a: ohne bedienten Namen ist der modelRef der Name" \
    || bad "5a: erste Zeile '$Z1', erwartet '$PFAD' (Ausgabe: $AUS)"
[ "$(eintraege mlx-local-32k)" = "$PFAD|32768" ] \
    && ok "5b: der Eintrag traegt den modelRef" \
    || bad "5b: der Eintrag stimmt nicht: $(eintraege mlx-local-32k)"
# Und der Kurzschluss feuert dann auch weiterhin, wenn beides passt.
AUS="$(lauf 262144 256k "")"
[ "$(printf '%s\n' "$AUS" | sed -n 's/^provider=//p')" = "mlx-local" ] \
    && ok "5c: ohne bedienten Namen feuert der Kurzschluss wie frueher, jetzt mit provider=" \
    || bad "5c: der Kurzschluss verhaelt sich ohne bedienten Namen anders: $AUS"

echo
echo "  bestanden: $pass, gescheitert: $fail"
[ "$fail" -eq 0 ]
