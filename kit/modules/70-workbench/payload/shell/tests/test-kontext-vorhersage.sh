#!/usr/bin/env bash
# test-kontext-vorhersage.sh -- bei vorhersage.bauart "eingebaut" muss
# wb-kontext mit dem Koerper rechnen, der wirklich laeuft, nicht mit dem
# ersetzten Ziel-Eintrag (2026-08-21).
#
# DER BEFUND (Auftrag, gemessen an lmgamma-27b): die Registry traegt fuer
# lmgamma-27b vorhersage.bauart="eingebaut" -- der Kommentar in berechne()
# sagte seit dem 20.08. schon selbst, dass dabei der groessere Modellkoerper
# das Ziel ERSETZT (eigener modelRef, kein Zusatzgewicht). Trotzdem rechnete
# berechne() weiter mit res["modelRef"] des ERSETZTEN Ziels: gewichte_gb()
# summierte die kleineren Ziel-safetensors (14,95 statt wirklich geladener
# 19,83 GiB), kv_mib_pro_token() suchte unter dem Ziel-Namen und traf den
# bf16-Wert (0,0625 MiB/Token) statt des gemessenen 8-Bit-Werts fuer den
# Ersatzkoerper (0,0332 MiB/Token) -- beide Fehler in verschiedene
# Richtungen, teils zufaellig gegeneinander aufgehoben. Bei 32k war "passt"
# dadurch faelschlich "ja" (rund 4 GiB zu niedrig gerechnet); bei 256k
# faelschlich "nein", obwohl der Start dort in Wirklichkeit hineinpasst.
#
# SIEBEN ZUSAGEN:
#   1  bauart "eingebaut": modelRef, Gewichte UND KV-Schluessel sind die des
#      ERSATZKOERPERS, nicht des Ziels -- inklusive Gross-/Kleinschreibung
#      im KV-Namensabgleich (der echte Ersatzordner traegt Grossbuchstaben,
#      der gemessene KV-Schluessel ist klein geschrieben).
#   2  bauart "entwerfer" bleibt UNVERAENDERT additiv (--entwerfer-gewichte-gb),
#      auch wenn vorhersage.modell in der Registry auf einen Pfad zeigt --
#      dieser Fall wird von berechne() nicht automatisch gelesen.
#   3  Kein vorhersage-Feld: rechnet exakt wie vor diesem Fix, keine
#      Nebenwirkung durch den neuen Code.
#   4  Ein Ersatzkoerper OHNE gemessenen KV-Eintrag zeigt eine Herkunft, die
#      sichtbar "hergeleitet"/angenommen ist, nie "gemessen".
#
# NACHTRAG 21.08.2026, ZWEI WEITERE BEFUNDE VOM ECHTEN DOPPELSTART, DIESELBE
# DATEI:
#
# BEFUND A: Zusage 1 oben griff auch dann, wenn wb-code/pi-worker die
# Vorhersage GAR NICHT anfordern -- das Registry-Feld allein reicht nicht,
# es braucht zusaetzlich die Sitzungs-Einstellung (orchestratorVorhersage /
# workerVorhersage), die wb-code/pi-worker VOR jedem Aufruf lesen und die auf
# dieser Maschine auf 'false' steht (Absicht). Gemessen lief der SCHLICHTE
# Koerper (14,95 GiB, bf16-KV), waehrend wb-kontext mit dem MTPLX-Koerper
# rechnete (19,83 GiB, q8-KV) -- vor dem ersten Fix zu wenig, jetzt (nur
# Registry, ohne Einstellung prompt) zu viel.
#   5  --vorhersage-einstellung <name>, gelesen: swap greift nur, wenn die
#      benannte Einstellung ("wb-state settings get <name>") wirklich 'true'
#      ist. An + Feld da -> ersetzt. Aus + Feld da -> ersetzt NICHT. Kein
#      --vorhersage-einstellung angegeben -> ersetzt NICHT, selbst wenn eine
#      irgendwie benannte Einstellung zufaellig 'true' waere (der sichere
#      Ausgangswert braucht eine ausdrueckliche Zusage vom Aufrufer).
#
# BEFUND B: wb-kontext und wb-belegung nannten fuer dieselbe Stufe
# verschiedene Zahlen -- wb-kontexts eigene Naeherung fuehrte wb-belegungs
# Zuschlag (Prompt-Cache-/Spitzen-Puffer) nicht mit. Gemessen: wb-kontext
# "bedarfGib 24.08, passt: ja" fuer 131072 Token, derselbe Start ueber
# wb-belegung "verlangt 29,4 GiB, lehnt ab" -- eine Auskunft, die
# freundlicher ist als die Wirklichkeit.
#   6  Fuer mlx-local kommt bedarfGib/passt jetzt von 'wb-belegung darf'
#      selbst (bedarf_wirklich(), Gegenstueck zu plaetze_wirklich() weiter
#      oben) -- dieselbe Zahl wie beim echten Start, nicht eine zweite
#      Formel. bedarfQuelle im JSON sagt, woher die Zahl kam.
#
# ISOLATION: umgelenktes HOME (mktemp -d), echte Kopien von wb-state,
# check-resources UND (fuer Zusage 6) wb-belegung darin (dieselbe
# Isolationstechnik wie test-kontext-kv-namen.sh/test-entwerfer.sh), eine
# eigene Registry-Datei ueber WB_MODELS_FILE (wb-state selbst kennt diese
# Umleitung), eine eigene settings.json unter dem umgelenkten HOME (fuer
# Zusage 5 -- wb-state settings liest sie ueber $HOME, keine eigene
# Umleitungsvariable noetig). Kein Modellstart, kein Netz, keine
# Ollama-Anfrage (alle Fixtures sind Provider "mlx-local"). Zusage 0 unten
# prueft SELBST, dass wb-kontext wirklich auf den Stellvertretern arbeitet
# -- eine Werkzeugsuche, die vor dem umgelenkten HOME rangiert, wuerde sonst
# still auf die echte Maschine durchgreifen und ein gruener Testlauf haette
# nichts geprueft (Lehre vom 21.08., siehe test-kontext-provider.sh).
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WK="${WB_KONTEXT:-$REPO/wb-kontext}"
echo "Geprueft: $WK"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ $# -gt 1 ] && printf '        %s\n' "$2"; }

FAKEHOME="$(mktemp -d)"
WORK="$(mktemp -d)"
trap 'rm -rf "$FAKEHOME" "$WORK"' EXIT

mkdir -p "$FAKEHOME/.local/bin" "$FAKEHOME/.local/state/wb-belegung" "$FAKEHOME/.claude/workbench"
cp "$REPO/wb-state" "$REPO/check-resources" "$REPO/wb-belegung" "$FAKEHOME/.local/bin/"
chmod +x "$FAKEHOME/.local/bin/wb-state" "$FAKEHOME/.local/bin/check-resources" "$FAKEHOME/.local/bin/wb-belegung"

einstellung_setzen() {   # <name> <true|false>
    python3 -c "
import json
p = '$FAKEHOME/.claude/workbench/settings.json'
try:
    d = json.load(open(p))
except Exception:
    d = {}
d['$1'] = $2
json.dump(d, open(p, 'w'))
"
}

# ── Fixture-Modellkoerper ────────────────────────────────────────────────
# Architektur (dieselbe fuer Ziel UND Ersatz, wie bei lmgamma-27b/MTPLX: der
# MTP-Kopf aendert die Gewichte, nicht die Form des KV-Cache): 32 Lagen,
# volle Attention alle 4 Lagen (8 wachsende Lagen), 4 KV-Koepfe, Kopfdim 128
# -- gross genug, dass kv_obergrenze_mib() (die architektonische
# Plausibilitaetsschranke) den gemessenen Fixture-Wert unten (0,0332) nicht
# als unmoeglich verwirft.
KONFIG='{
  "max_position_embeddings": 32768,
  "num_hidden_layers": 32,
  "num_attention_heads": 32,
  "num_key_value_heads": 4,
  "head_dim": 128,
  "full_attention_interval": 4
}'

ZIEL="$WORK/ziel-4bit"
# Grossgeschrieben, absichtlich (Zusage 1b) -- wie der echte MTPLX-Ordner
# 'Lmgamma-27B-MTPLX-Optimized-Speed', gegen einen klein geschriebenen
# KV-Schluessel in kv-bedarf.json.
ERSATZ="$WORK/Ersatz-MTP-Koerper"
ERSATZ_UNMESSEN="$WORK/Ersatz-Ohne-Messung"
mkdir -p "$ZIEL" "$ERSATZ" "$ERSATZ_UNMESSEN"
printf '%s' "$KONFIG" > "$ZIEL/config.json"
printf '%s' "$KONFIG" > "$ERSATZ/config.json"
printf '%s' "$KONFIG" > "$ERSATZ_UNMESSEN/config.json"

# Ziel: 5.000.000 + 7.000.000 = 12.000.000 Byte. Ersatz: 30.000.000 Byte --
# klar groesser, wie der echte MTPLX-Koerper (19,83 gegen 14,95 GiB).
python3 -c "open('$ZIEL/a.safetensors','wb').write(b'\0' * 5_000_000)"
python3 -c "open('$ZIEL/b.safetensors','wb').write(b'\0' * 7_000_000)"
python3 -c "open('$ERSATZ/c.safetensors','wb').write(b'\0' * 30_000_000)"
python3 -c "open('$ERSATZ_UNMESSEN/d.safetensors','wb').write(b'\0' * 30_000_000)"
ZIEL_GIB="$(python3 -c "print(12_000_000/1024**3)")"
ERSATZ_GIB="$(python3 -c "print(30_000_000/1024**3)")"

# kv-bedarf.json: ein gemessener Eintrag fuer den Ersatzkoerper, klein
# geschrieben -- $ERSATZ_UNMESSEN traegt bewusst KEINEN Eintrag (Zusage 4).
# "ziel-4bit" (Zusage 6, Befund B) ist derselbe Eintrag, den sowohl
# wb-kontext (kv_mib_pro_token) als auch die ECHTE wb-belegung-Kopie
# (kv_fuer()) unter demselben Pfad lesen -- eine geteilte Datei, kein
# zweiter Wert fuer denselben Koerper.
cat > "$FAKEHOME/.local/state/wb-belegung/kv-bedarf.json" <<EOF
{ "version": 1, "modelle": {
  "ersatz-mtp-koerper": { "mib_je_token": 0.0332, "herkunft": "gemessen",
    "wann": "2026-08-21", "notiz": "Fixture fuer test-kontext-vorhersage.sh" },
  "ziel-4bit": { "mib_je_token": 0.02, "herkunft": "gemessen",
    "wann": "2026-08-21", "notiz": "Fixture fuer test-kontext-vorhersage.sh" }
} }
EOF

# ── Registry-Fixture ─────────────────────────────────────────────────────
REGISTRY="$WORK/models.json"
python3 -c "
import json
ziel, ersatz, ersatz_un = '$ZIEL', '$ERSATZ', '$ERSATZ_UNMESSEN'
reg = {'models': [
    {'id': 'fixt-eingebaut', 'harness': 'pi', 'provider': 'mlx-local',
     'modelRef': ziel, 'contextWindow': 32768,
     'vorhersage': {'bauart': 'eingebaut', 'modell': ersatz, 'gewichteGb': 99}},
    {'id': 'fixt-entwerfer', 'harness': 'pi', 'provider': 'mlx-local',
     'modelRef': ziel, 'contextWindow': 32768,
     'vorhersage': {'bauart': 'entwerfer', 'modell': '/nicht/gelesen', 'gewichteGb': 3.5}},
    {'id': 'fixt-ohne-vorhersage', 'harness': 'pi', 'provider': 'mlx-local',
     'modelRef': ziel, 'contextWindow': 32768},
    {'id': 'fixt-eingebaut-unmessen', 'harness': 'pi', 'provider': 'mlx-local',
     'modelRef': ziel, 'contextWindow': 32768,
     'vorhersage': {'bauart': 'eingebaut', 'modell': ersatz_un, 'gewichteGb': 99}},
]}
open('$REGISTRY', 'w').write(json.dumps(reg))
"

lauf() {   # <modell> [weitere wb-kontext-Argumente...] -> setzt JSON, RC, ERR
    local modell="$1"; shift
    local errdatei; errdatei="$(mktemp)"
    JSON="$(HOME="$FAKEHOME" WB_MODELS_FILE="$REGISTRY" "$WK" stufen "$modell" \
        --parallel 1 --denken low --json "$@" 2>"$errdatei")"
    RC=$?
    ERR="$(cat "$errdatei")"; rm -f "$errdatei"
}

lauf_text() {   # <modell> [weitere Argumente...] -> setzt TEXT (menschliche Ausgabe, kein --json)
    local modell="$1"; shift
    TEXT="$(HOME="$FAKEHOME" WB_MODELS_FILE="$REGISTRY" "$WK" stufen "$modell" \
        --parallel 1 --denken low "$@" 2>/dev/null)"
}

feld() {   # <json> <python-ausdruck ueber "d"> -> Wert
    python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print($2)
" "$1" "$2" 2>/dev/null || echo FEHLER
}

echo "== 0  Der Test arbeitet wirklich auf den Stellvertretern =="
# Zusagen 1 und 5 brauchen die Einstellung AN (Befund A) -- gesetzt VOR dem
# ersten Lauf, damit Abschnitt 1 (der $JSON von hier wiederverwendet) den
# Ersatzkoerper wirklich sieht.
einstellung_setzen testVorhersageAn True
lauf fixt-eingebaut --vorhersage-einstellung testVorhersageAn
if [ "$RC" -eq 0 ] && [ "$(feld "$JSON" 'd["modell"]')" = "fixt-eingebaut" ]; then
    ok "wb-kontext findet 'fixt-eingebaut' -- das gibt es nur in der Fixture-Registry, nicht in der echten"
else
    bad "wb-kontext hat 'fixt-eingebaut' nicht gefunden -- WB_MODELS_FILE/HOME greifen nicht" "$ERR"
    echo "  bestanden: $pass, gescheitert: $fail"
    exit 1
fi

echo "== 1  bauart eingebaut: modelRef, Gewichte und KV-Schluessel sind die des Ersatzkoerpers =="
mref="$(feld "$JSON" 'd["modelRef"]')"
gewichte="$(feld "$JSON" 'd["gewichteGb"]')"
kv="$(feld "$JSON" 'd["kvMibProToken"]')"
bauart="$(feld "$JSON" 'd["vorhersageBauart"]')"
ersetzt="$(feld "$JSON" 'd["vorhersageErsetztFuer"]')"

[ "$mref" = "$ERSATZ" ] && ok "1a: modelRef ist der Ersatzkoerper ('$ERSATZ'), nicht das Ziel" \
    || bad "1a: modelRef ist '$mref', erwartet '$ERSATZ'"
python3 -c "
import sys
g = float('$gewichte'); erw = round($ERSATZ_GIB, 2); ziel_r = round($ZIEL_GIB, 2)
sys.exit(0 if abs(g - erw) < 1e-6 and abs(g - ziel_r) > 1e-6 else 1)
" && ok "1b: gewichteGb ($gewichte) ist die des Ersatzkoerpers ($ERSATZ_GIB GiB), nicht des Ziels ($ZIEL_GIB GiB)" \
    || bad "1b: gewichteGb ist '$gewichte', erwartet rund $ERSATZ_GIB (Ersatz), nicht $ZIEL_GIB (Ziel)"
[ "$kv" = "0.0332" ] && ok "1c: kvMibProToken (0.0332) ist der GEMESSENE Wert des Ersatzkoerpers, trotz Gross-/Kleinschreibung im Ordnernamen" \
    || bad "1c: kvMibProToken ist '$kv', erwartet 0.0332 (gemessener Ersatz-Wert -- Gross-/Kleinschreibung im KV-Namensabgleich nicht behoben?)"
[ "$bauart" = "eingebaut" ] && ok "1d: vorhersageBauart meldet 'eingebaut'" \
    || bad "1d: vorhersageBauart ist '$bauart', erwartet 'eingebaut'"
[ "$ersetzt" = "$ZIEL" ] && ok "1e: vorhersageErsetztFuer nennt den urspruenglichen Ziel-Pfad -- die Anzeige sagt, WOFUER ersetzt wurde" \
    || bad "1e: vorhersageErsetztFuer ist '$ersetzt', erwartet '$ZIEL'"

echo "== 2  bauart entwerfer bleibt unveraendert additiv (Registry-Pfad wird NICHT automatisch gelesen) =="
lauf fixt-entwerfer
mref2="$(feld "$JSON" 'd["modelRef"]')"
gewichte2="$(feld "$JSON" 'd["gewichteGb"]')"
[ "$mref2" = "$ZIEL" ] && ok "2a: modelRef bleibt das Ziel -- entwerfer ersetzt nicht, es ergaenzt" \
    || bad "2a: modelRef ist '$mref2', erwartet '$ZIEL' (unveraendert)"
python3 -c "import sys; sys.exit(0 if abs(float('$gewichte2') - round($ZIEL_GIB, 2)) < 1e-6 else 1)" \
    && ok "2b: ohne --entwerfer-gewichte-gb bleibt gewichteGb ($gewichte2) das reine Zielgewicht" \
    || bad "2b: gewichteGb ist '$gewichte2', erwartet $ZIEL_GIB (kein automatischer Zuschlag)"
lauf fixt-entwerfer --entwerfer-gewichte-gb 3.5
gewichte2b="$(feld "$JSON" 'd["gewichteGb"]')"
python3 -c "import sys; sys.exit(0 if abs(float('$gewichte2b') - round($ZIEL_GIB + 3.5, 2)) < 1e-6 else 1)" \
    && ok "2c: MIT --entwerfer-gewichte-gb 3.5 (wie wb-code/pi-worker es reichen) addiert sich das Gewicht wie bisher" \
    || bad "2c: gewichteGb ist '$gewichte2b', erwartet $(python3 -c "print($ZIEL_GIB + 3.5)")"

echo "== 3  kein vorhersage-Feld: rechnet unveraendert =="
lauf fixt-ohne-vorhersage
mref3="$(feld "$JSON" 'd["modelRef"]')"
bauart3="$(feld "$JSON" 'd["vorhersageBauart"]')"
[ "$mref3" = "$ZIEL" ] && [ "$bauart3" = "None" ] \
    && ok "3: ohne vorhersage-Feld bleibt modelRef das Ziel, vorhersageBauart ist leer" \
    || bad "3: modelRef='$mref3' (erwartet '$ZIEL'), vorhersageBauart='$bauart3' (erwartet leer)"

echo "== 4  Ersatzkoerper ohne gemessenen KV-Eintrag: Herkunft ist sichtbar hergeleitet, nie 'gemessen' =="
lauf fixt-eingebaut-unmessen --vorhersage-einstellung testVorhersageAn
mref4="$(feld "$JSON" 'd["modelRef"]')"
[ "$mref4" = "$ERSATZ_UNMESSEN" ] && ok "4a: modelRef ist trotzdem der Ersatzkoerper" \
    || bad "4a: modelRef ist '$mref4', erwartet '$ERSATZ_UNMESSEN'"
# kvMibProToken selbst traegt im JSON keine Quelle -- die menschliche Ausgabe
# (nicht --json) druckt sie aus. Dort wird geprueft, dass "gemessen" NICHT
# vorkommt, "hergeleitet" oder "Annahme" aber schon.
lauf_text fixt-eingebaut-unmessen --vorhersage-einstellung testVorhersageAn
if printf '%s' "$TEXT" | grep -q "KV je Token" && ! printf '%s' "$TEXT" | grep "KV je Token" | grep -qi "gemessen"; then
    ok "4b: die KV-Quelle fuer den unmessenen Ersatzkoerper nennt sich nicht 'gemessen'"
else
    bad "4b: die KV-Quelle nennt sich faelschlich 'gemessen', oder die Zeile fehlt ganz" "$TEXT"
fi
if printf '%s' "$TEXT" | grep "KV je Token" | grep -qiE "hergeleitet|annahme"; then
    ok "4c: die KV-Quelle nennt sich sichtbar hergeleitet/angenommen"
else
    bad "4c: die KV-Quelle nennt weder 'hergeleitet' noch 'Annahme'" "$TEXT"
fi

echo "== 5  Befund A: der Swap greift nur, wenn Registry-Feld UND Einstellung zusammen 'an' sind =="
einstellung_setzen testVorhersageAn True
lauf fixt-eingebaut --vorhersage-einstellung testVorhersageAn
mref5a="$(feld "$JSON" 'd["modelRef"]')"
[ "$mref5a" = "$ERSATZ" ] && ok "5a: Vorhersage AN + Feld da -> ersetzt (modelRef ist der Ersatzkoerper)" \
    || bad "5a: modelRef ist '$mref5a', erwartet '$ERSATZ' (Einstellung stand auf true)"

einstellung_setzen testVorhersageAn False
lauf fixt-eingebaut --vorhersage-einstellung testVorhersageAn
mref5b="$(feld "$JSON" 'd["modelRef"]')"
[ "$mref5b" = "$ZIEL" ] && ok "5b: Vorhersage AUS + Feld da -> ersetzt NICHT (modelRef bleibt das Ziel)" \
    || bad "5b: modelRef ist '$mref5b', erwartet '$ZIEL' (Einstellung stand auf false, Feld war trotzdem da)"

einstellung_setzen testVorhersageAn True
lauf fixt-eingebaut
mref5c="$(feld "$JSON" 'd["modelRef"]')"
[ "$mref5c" = "$ZIEL" ] && ok "5c: kein --vorhersage-einstellung angegeben -> ersetzt NICHT, obwohl die Einstellung gerade 'true' ist (sicherer Ausgangswert braucht die ausdrueckliche Zusage vom Aufrufer)" \
    || bad "5c: modelRef ist '$mref5c', erwartet '$ZIEL' (ohne den Namen darf nicht geraten werden)"
einstellung_setzen testVorhersageAn False

echo "== 6  Befund B: bedarfGib/passt fuer mlx-local sind dieselbe Zahl wie 'wb-belegung darf' =="
lauf fixt-ohne-vorhersage
stufe32k="$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
s = next((x for x in d['stufen'] if x['tokens'] == 32768), None)
print('%s|%s|%s' % (s['bedarfGib'], s['passt'], s['bedarfQuelle']) if s else 'FEHLT|FEHLT|FEHLT')
" "$JSON" 2>/dev/null || echo "FEHLT|FEHLT|FEHLT")"
bedarf6="${stufe32k%%|*}"; rest6="${stufe32k#*|}"; passt6="${rest6%%|*}"; quelle6="${rest6#*|}"
if [ "$bedarf6" = FEHLT ]; then
    bad "6: Stufe 32768 fehlt in der Ausgabe" "$JSON"
else
    UNABHAENGIG="$(env HOME="$FAKEHOME" PATH="$FAKEHOME/.local/bin:$PATH" \
        wb-belegung darf --gewichte-gb "$ZIEL_GIB" --modell ziel-4bit \
        --parallel 1 --kontext 32768 --abtastungen 1 --abstand 0 --json 2>/dev/null)"
    spitze_unabh="$(printf '%s' "$UNABHAENGIG" | python3 -c "import json,sys; print(json.load(sys.stdin)['spitze_gib'])" 2>/dev/null || echo FEHLT)"
    ja_unabh="$(printf '%s' "$UNABHAENGIG" | python3 -c "import json,sys; print(json.load(sys.stdin)['ja'])" 2>/dev/null || echo FEHLT)"
    python3 -c "import sys; sys.exit(0 if abs(float('$bedarf6') - float('$spitze_unabh')) < 0.01 else 1)" \
        && ok "6a: bedarfGib ($bedarf6) ist EXAKT die Zahl, die eine unabhaengige 'wb-belegung darf'-Anfrage fuer dieselbe Stufe liefert ($spitze_unabh)" \
        || bad "6a: bedarfGib ist '$bedarf6', 'wb-belegung darf' sagt '$spitze_unabh' -- zwei Formeln, nicht eine"
    [ "$passt6" = "$([ "$ja_unabh" = True ] && echo True || echo False)" ] \
        && ok "6b: passt ($passt6) stimmt mit wb-belegungs 'ja' ($ja_unabh) ueberein" \
        || bad "6b: passt='$passt6', wb-belegung sagt ja='$ja_unabh'"
    printf '%s' "$quelle6" | grep -qi "wb-belegung" \
        && ok "6c: bedarfQuelle nennt wb-belegung als Herkunft dieser Zahl" \
        || bad "6c: bedarfQuelle nennt wb-belegung nicht: '$quelle6'"
fi
# Waehlbar bleibt sie in jedem Fall (ausdrueckliche des Nutzers Vorgabe,
# unveraendert) -- unabhaengig davon, ob 'passt' gerade wahr oder falsch ist.
alle_stufen_da="$(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(len(d['stufen']))
" "$JSON" 2>/dev/null || echo 0)"
[ "$alle_stufen_da" -gt 0 ] 2>/dev/null \
    && ok "6d: die Stufenliste bleibt vollstaendig (${alle_stufen_da} Stufen, unabhaengig von 'passt')" \
    || bad "6d: die Stufenliste ist leer oder unlesbar"

echo
echo "Ergebnis: $pass ok, $fail FAIL"
[ "$fail" -eq 0 ]
