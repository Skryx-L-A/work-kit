#!/bin/bash
# test-vorhersagewahl.sh -- DREI Vorhersage-Wege sind waehlbar, und die Wahl
# kommt am Aufruf wirklich an.
#
# ANLASS (der Nutzer, 2026-08-21): "ich will das ich als zweite option lmgamma
# als orchestrator auch mit einem multitokenprediction model starten kann
# anstatt mtplx, ich will mich entscheiden koennen." Auf Nachfrage: beide
# Entwerfer-Wege, also drei Moeglichkeiten. Die Registry fuehrt sie seither
# unter 'vorhersage.wege', die Wahl steht in der Einstellung
# 'orchestratorVorhersageWeg'.
#
# Der Pruefpunkt ist derselbe wie in test-vorhersage.sh und aus demselben
# Grund: NICHT eine Zwischenfunktion, sondern der tatsaechliche Aufruf an den
# MLX-Server. Eine Attrappe von wb-mlx-server protokolliert argv und jede
# WB_MLX_SERVER_VORHERSAGE_*-Variable, die bei ihr ankommt -- "es darf keinen
# stillen Pfad geben, auf dem die Einstellung verlorengeht".
#
# ISOLATION wie test-vorhersage.sh: eigener Socket, eigenes HOME, `unset TMUX
# TMUX_PANE` zuerst, Kopien der geprueften Werkzeuge, fake 'pi'/'ollama'
# statt der echten CLIs. Kein echter Modellstart -- den fahren die Messungen
# im Ergebnisbericht, dieser Test prueft die Durchreichung.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"
echo "Geprueft: Repo-Stand aus $REPO"

SOCK="wbtest-vorhwahl-$$"
SESS="wb-vorhwahltest-$$"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }

TESTHOME="$(mktemp -d)"
cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCK"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L "$SOCK" ls >/dev/null 2>&1; do
    tmux -L "$SOCK" kill-server 2>/dev/null || true
    sleep 0.3
  done
  tmux -L "$SOCK" ls >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCK' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCK"
  chmod -R u+w "$TESTHOME" 2>/dev/null || true
  rm -rf "$TESTHOME"
}
trap cleanup EXIT INT TERM

REALTMUX="$(command -v tmux)"
[ -x "$REALTMUX" ] || { echo "tmux nicht gefunden — Test kann nicht laufen." >&2; exit 1; }
export HOME="$TESTHOME"
export WB_NO_DISCOVER=1
BIN="$TESTHOME/.local/bin"; mkdir -p "$BIN" "$TESTHOME/.claude/workbench" "$TESTHOME/work"
export TMPDIR="$TESTHOME/tmp/"; mkdir -p "$TMPDIR"

cat >"$BIN/tmux" <<EOF
#!/bin/bash
exec "$REALTMUX" -L $SOCK "\$@"
EOF
chmod +x "$BIN/tmux"

cat >"$BIN/pi" <<EOF
#!/bin/bash
while :; do printf '❯ '; IFS= read -r _l || sleep 1; done
EOF
chmod +x "$BIN/pi"

cat >"$BIN/ollama" <<'EOF'
#!/bin/bash
case "$1" in
  list) printf 'NAME\tID\tSIZE\tMODIFIED\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN/ollama"

# Drei Fixture-Verzeichnisse: das Ziel und die beiden Vorhersage-Koerper. Alle
# winzig, aber mit echter config.json-Form, damit wb-kontext natives Maximum
# und Gewichte wirklich LESEN kann statt zu raten.
FIXZIEL="$TESTHOME/fixziel"
FIXEINGEBAUT="$TESTHOME/fix-eingebaut"
FIXENTWERFER_A="$TESTHOME/fix-entwerfer-a"
FIXENTWERFER_B="$TESTHOME/fix-entwerfer-b"
for d in "$FIXZIEL" "$FIXEINGEBAUT" "$FIXENTWERFER_A" "$FIXENTWERFER_B"; do
  mkdir -p "$d"
  cat >"$d/config.json" <<'EOF'
{"text_config": {"max_position_embeddings": 32768}}
EOF
  head -c 1048576 /dev/zero > "$d/model.safetensors"
done

ENSURE_LOG="$TESTHOME/mlx-ensure.log"
cat >"$BIN/wb-mlx-server" <<EOF
#!/bin/bash
{
  echo "ARGV \$*"
  echo "BAUART=\${WB_MLX_SERVER_VORHERSAGE_BAUART:-}"
  echo "MODELL=\${WB_MLX_SERVER_VORHERSAGE_MODELL:-}"
  echo "GEWICHTE_GB=\${WB_MLX_SERVER_VORHERSAGE_GEWICHTE_GB:-}"
  echo "---"
} >> "$ENSURE_LOG"
exit 0
EOF
chmod +x "$BIN/wb-mlx-server"

for s in wb-state pi-worker claude-worker wb-code wb-grid wb-kontext wb-belegung; do
  cp "$REPO/$s" "$BIN/$s"; chmod +x "$BIN/$s"
done
# check-resources: Attrappe mit reichlich freiem Speicher, damit dieser Test
# das ARGV prueft und nicht die Speicherlage der Testmaschine (derselbe
# Kunstgriff und derselbe Grund wie in test-vorhersage.sh).
cat >"$BIN/check-resources" <<'EOF'
#!/bin/sh
echo '{"ram":{"free_mib":40960,"total_mib":49152},"vram":{"free_mib":40960,"total_mib":49152},"ollama_loaded":[]}'
EOF
chmod +x "$BIN/check-resources"
werkzeuge_installieren "$TESTHOME"

export PATH="$BIN:$PATH"
env HOME="$TESTHOME" PATH="$BIN:$PATH" \
    wb-belegung kv setzen fixziel 0.02 --herkunft gemessen >/dev/null 2>&1
env HOME="$TESTHOME" PATH="$BIN:$PATH" \
    wb-belegung kv setzen fix-eingebaut 0.02 --herkunft gemessen >/dev/null 2>&1
WBS="$BIN/wb-state"

# Fixture-Registry: EIN Modell mit drei Wegen. Die Pfade sind absichtlich
# andere als die echten (MTPLX/DFlash2/DSpark) -- ein Test, der gegen den Code
# statt gegen die Registry laese, fiele damit sofort auf.
cat >"$TESTHOME/.claude/workbench/models.json" <<EOF
{
  "version": 1,
  "providers": [],
  "harnesses": [],
  "models": [
    {
      "id": "vw-modell",
      "label": "Vorhersagewahl-Testmodell",
      "harness": "pi",
      "provider": "mlx-local",
      "modelRef": "$FIXZIEL",
      "roles": ["worker", "orchestrator"],
      "maxEffort": "high",
      "defaultEffort": "low",
      "enabled": true,
      "vorhersage": {
        "bauart": "eingebaut",
        "modell": "$FIXEINGEBAUT",
        "gewichteGb": 2.5,
        "wegVorgabe": "kopf",
        "wege": [
          {
            "id": "kopf",
            "label": "Eingebauter Testkopf",
            "bauart": "eingebaut",
            "modell": "$FIXEINGEBAUT",
            "gewichteGb": 2.5,
            "herkunft": "Test-Fixture, kein echter Kandidat"
          },
          {
            "id": "entwerfer-a",
            "label": "Test-Entwerfer A",
            "bauart": "entwerfer",
            "modell": "$FIXENTWERFER_A",
            "gewichteGb": 1.23,
            "herkunft": "Test-Fixture, kein echter Kandidat"
          },
          {
            "id": "entwerfer-b",
            "label": "Test-Entwerfer B",
            "bauart": "entwerfer",
            "modell": "$FIXENTWERFER_B",
            "gewichteGb": 4.56,
            "herkunft": "Test-Fixture, Guete nicht gemessen"
          }
        ]
      }
    }
  ]
}
EOF

mkses() {
  local try err
  for try in 1 2 3; do
    err="$(tmux -L "$SOCK" new-session -d -s "$SESS" -x 200 -y 50 \
             "bash -c 'while :; do sleep 5; done'" 2>&1)"
    tmux -L "$SOCK" has-session -t "=$SESS" 2>/dev/null && return 0
    echo "  (Testsession-Start $try/3 fehlgeschlagen: ${err:-keine Meldung})" >&2
    sleep 2
  done
  echo "ABBRUCH: Testsession '$SESS' laesst sich auf Socket '$SOCK' nicht anlegen." >&2
  exit 1
}
mkses
tmux -L "$SOCK" set -p -t "$SESS" @wb_role orchestrator
export WB_SESSION="$SESS"

letzter_eintrag() { awk -v RS='---\n' 'END{print}' "$ENSURE_LOG" 2>/dev/null; }
feld() { printf '%s' "$1" | sed -n "s/^$2=//p"; }
buch_leeren() { rm -f "$TESTHOME/.local/state/wb-belegung/buch.json"; }

"$WBS" settings set orchestratorHarness pi >/dev/null
"$WBS" settings set orchestratorModel vw-modell >/dev/null
"$WBS" settings set orchestratorEffort low >/dev/null
"$WBS" settings set orchestratorVorhersage true >/dev/null

# Ein Orchestrator-Start gegen die Attrappe. Jeder Lauf braucht ein frisches
# Arbeitsverzeichnis, sonst findet wb-code die Sitzung des vorigen Laufs.
lauf() {   # <nummer>
  : > "$ENSURE_LOG"
  buch_leeren
  local dir="$TESTHOME/work-$1"
  rm -rf "$dir"; mkdir -p "$dir"
  timeout 20 "$BIN/wb-code" "$dir" >/dev/null 2>&1 || true
}

echo "== 1  Registry: alle drei Wege sind lesbar =="
WEGE="$("$WBS" models get vw-modell --field vorhersage 2>/dev/null \
  | python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    print(",".join(w.get("id","") for w in (d.get("wege") or [])))
except Exception:
    print("")' 2>/dev/null)"
[ "$WEGE" = "kopf,entwerfer-a,entwerfer-b" ] \
  && ok "vorhersage.wege fuehrt drei Wege in der Reihenfolge der Registry" \
  || bad "vorhersage.wege nicht/falsch gelesen" "gelesen: '$WEGE'"

echo "== 2  ohne Wegwahl: die Vorgabe der Registry (wegVorgabe) =="
"$WBS" settings set orchestratorVorhersageWeg "" >/dev/null 2>&1
lauf 2
E="$(letzter_eintrag)"
if [ "$(feld "$E" BAUART)" = eingebaut ] && [ "$(feld "$E" MODELL)" = "$FIXEINGEBAUT" ]; then
  ok "ohne gesetzten Weg kommt der Vorgabeweg der Registry an (eingebaut)"
else
  bad "ohne gesetzten Weg kam nicht der Vorgabeweg an" "$E"
fi

echo "== 3  Weg 'entwerfer-a': externer Entwerfer statt eingebautem Kopf =="
"$WBS" settings set orchestratorVorhersageWeg entwerfer-a >/dev/null
lauf 3
E="$(letzter_eintrag)"
[ "$(feld "$E" BAUART)" = entwerfer ] \
  && ok "BAUART=entwerfer kam an" || bad "BAUART falsch" "$E"
[ "$(feld "$E" MODELL)" = "$FIXENTWERFER_A" ] \
  && ok "MODELL = Entwerferpfad A" || bad "MODELL falsch" "$E"
[ "$(feld "$E" GEWICHTE_GB)" = "1.23" ] \
  && ok "GEWICHTE_GB des gewaehlten Weges kam an" || bad "GEWICHTE_GB falsch" "$E"

echo "== 4  Weg 'entwerfer-b': der ZWEITE Entwerfer, nicht der erste =="
"$WBS" settings set orchestratorVorhersageWeg entwerfer-b >/dev/null
lauf 4
E="$(letzter_eintrag)"
[ "$(feld "$E" MODELL)" = "$FIXENTWERFER_B" ] \
  && ok "MODELL = Entwerferpfad B" || bad "MODELL falsch" "$E"
[ "$(feld "$E" GEWICHTE_GB)" = "4.56" ] \
  && ok "GEWICHTE_GB von Weg B kam an" || bad "GEWICHTE_GB falsch" "$E"

echo "== 5  zurueck auf den eingebauten Kopf: die Wahl ist umkehrbar =="
"$WBS" settings set orchestratorVorhersageWeg kopf >/dev/null
lauf 5
E="$(letzter_eintrag)"
[ "$(feld "$E" BAUART)" = eingebaut ] && [ "$(feld "$E" MODELL)" = "$FIXEINGEBAUT" ] \
  && ok "Weg 'kopf' kommt wieder als eingebaut an" || bad "Rueckwahl kam nicht an" "$E"

echo "== 6  unbekannter Weg: Vorgabeweg statt stiller Falschwahl =="
"$WBS" settings set orchestratorVorhersageWeg gibtsnicht >/dev/null
lauf 6
E="$(letzter_eintrag)"
if [ "$(feld "$E" MODELL)" = "$FIXEINGEBAUT" ]; then
  ok "unbekannter Weg faellt auf den Vorgabeweg zurueck, nicht auf einen falschen Koerper"
else
  bad "unbekannter Weg fuehrte nicht auf den Vorgabeweg" "$E"
fi

echo "== 7  Schalter aus schlaegt jede Wegwahl =="
"$WBS" settings set orchestratorVorhersageWeg entwerfer-a >/dev/null
"$WBS" settings set orchestratorVorhersage false >/dev/null
lauf 7
E="$(letzter_eintrag)"
[ -z "$(feld "$E" BAUART)" ] \
  && ok "orchestratorVorhersage=aus: nichts kommt an, auch bei gesetztem Weg" \
  || bad "Schalter aus, aber die Wegwahl kam trotzdem durch" "$E"

echo "== 8  wb-kontext rechnet mit dem KOERPER, den wb-code nennt -- auch ueber einen Pfad =="
# 'eingebaut' ERSETZT das Ziel (der groessere Koerper laeuft statt des
# kleinen), 'entwerfer' laeuft NEBEN ihm. wb-code uebergibt das Modell als
# PFAD, und ueber einen Pfad findet wb-kontext seinen Registry-Eintrag NICHT
# ('wb-state models get <pfad>' ist nicht registriert) -- der eingebaute Weg
# muss deshalb ausgesprochen werden, sonst rechnet wb-kontext den schlichten
# Koerper, waehrend der groessere startet.
KJSON_OHNE="$("$BIN/wb-kontext" stufen "$FIXZIEL" --json --parallel 1 \
  --vorhersage-einstellung orchestratorVorhersage 2>/dev/null)"
KJSON_MIT="$("$BIN/wb-kontext" stufen "$FIXZIEL" --json --parallel 1 \
  --vorhersage-einstellung orchestratorVorhersage --vorhersage-koerper "$FIXEINGEBAUT" 2>/dev/null)"
ktx() { printf '%s' "$1" | python3 -c "import json,sys; print(json.load(sys.stdin).get(sys.argv[1]) or '')" "$2" 2>/dev/null; }
[ "$(ktx "$KJSON_OHNE" modelRef)" = "$FIXZIEL" ] \
  && ok "ohne --vorhersage-koerper bleibt es beim Ziel-Koerper" \
  || bad "ohne --vorhersage-koerper wurde trotzdem umgebogen" "$KJSON_OHNE"
[ "$(ktx "$KJSON_MIT" modelRef)" = "$FIXEINGEBAUT" ] \
  && ok "mit --vorhersage-koerper rechnet wb-kontext den wirklich startenden Koerper" \
  || bad "--vorhersage-koerper hat den Koerper nicht ersetzt" "$KJSON_MIT"
[ "$(ktx "$KJSON_MIT" vorhersageErsetztFuer)" = "$FIXZIEL" ] \
  && ok "die Anzeige nennt, WOFUER der Koerper eingesprungen ist" \
  || bad "vorhersageErsetztFuer fehlt/falsch" "$KJSON_MIT"

echo "== 9  wb-code reicht den eingebauten Koerper an wb-kontext durch =="
# Der eingebaute Weg braucht BEIDE Uebergaben: den Koerper an wb-kontext
# (Speicherrechnung) und die drei Umgebungsvariablen an wb-mlx-server
# (Serverstart). Geprueft wird hier die erste -- eine Attrappe schreibt das
# argv mit und ruft danach das echte Werkzeug, damit der Lauf weiterlaeuft.
cp "$BIN/wb-kontext" "$BIN/wb-kontext.echt"
KONTEXT_LOG="$TESTHOME/kontext-argv.log"
cat >"$BIN/wb-kontext" <<EOF
#!/bin/bash
echo "\$*" >> "$KONTEXT_LOG"
exec "$BIN/wb-kontext.echt" "\$@"
EOF
chmod +x "$BIN/wb-kontext"
: > "$KONTEXT_LOG"
"$WBS" settings set orchestratorVorhersage true >/dev/null   # Abschnitt 7 hatte ihn ausgeschaltet
"$WBS" settings set orchestratorVorhersageWeg kopf >/dev/null
lauf 9
if grep -q -- "--vorhersage-koerper $FIXEINGEBAUT" "$KONTEXT_LOG"; then
  ok "wb-code nennt wb-kontext den eingebauten Koerper des gewaehlten Weges"
else
  bad "wb-code hat --vorhersage-koerper nicht durchgereicht" "$(cat "$KONTEXT_LOG")"
fi

echo "== 10  beim Entwerferweg zaehlt das Entwerfer-Gewicht ZUSAETZLICH, kein Ersatz =="
: > "$KONTEXT_LOG"
"$WBS" settings set orchestratorVorhersageWeg entwerfer-b >/dev/null
lauf 10
if grep -q -- "--entwerfer-gewichte-gb 4.56" "$KONTEXT_LOG" \
   && ! grep -q -- "--vorhersage-koerper" "$KONTEXT_LOG"; then
  ok "Entwerferweg: Gewicht kommt hinzu, der Ziel-Koerper bleibt stehen"
else
  bad "Entwerferweg falsch an wb-kontext gereicht" "$(cat "$KONTEXT_LOG")"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
