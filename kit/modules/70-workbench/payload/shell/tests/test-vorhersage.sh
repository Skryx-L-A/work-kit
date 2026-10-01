#!/bin/bash
# test-vorhersage.sh -- Multi-Token-Vorhersage: die Vorgabe je Modell kommt
# aus der Registry (nicht aus dem Code), der Worker-Schalter wirkt getrennt
# vom Orchestrator-Schalter, und die Wahl kommt am Aufruf wirklich an.
#
# ANLASS (Auftrag 2026-08-20): "Es darf keinen stillen Pfad geben, auf dem
# die Einstellung verlorengeht -- genau dieser Fehler ist heute schon
# zweimal aufgetreten (Denkstufe, Kontextfenster)." Deshalb wird hier NICHT
# nur eine Zwischenfunktion geprueft, sondern der tatsaechliche Aufruf, den
# wb-code/pi-worker an den MLX-Server richten -- eine fake wb-mlx-server
# protokolliert argv UND jede WB_MLX_SERVER_VORHERSAGE_*-Umgebungsvariable,
# die bei ihr ankommt.
#
# ISOLATION wie test-registry.sh: eigener Socket, eigenes HOME, `unset TMUX
# TMUX_PANE` zuerst, COPIES der geprueften Werkzeuge (fester
# Repo-Schnappschuss), fake 'pi'/'ollama' statt der echten CLIs. wb-mlx-server
# ist NICHT meine Datei (Auftrag A/parallele Spur) -- hier bewusst durch eine
# eigene, protokollierende Attrappe ersetzt, nicht die echte Datei kopiert.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"
echo "Geprueft: Repo-Stand aus $REPO"

SOCK="wbtest-vorhersage-$$"
SESS="wb-vorhersagetest-$$"
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
  # chmod vor rm: python3-Aufrufe mit HOME=$TESTHOME legen darunter teils
  # eine ~/Library/Caches/com.apple.python/...-Bytecode-Ablage mit engeren
  # Rechten an, die 'rm -rf' sonst mit "Directory not empty" abbrechen laesst
  # (gemessen). Rein kosmetisch (ein /tmp-Scratchverzeichnis), aber ein
  # sauberer Lauf hinterlaesst nichts.
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

# Fake 'ollama': wird fuer die Kontextrechnung ueber ein mlx-local-Verzeichnis
# gar nicht gebraucht (das Fixture-Modell zeigt auf ein echtes Verzeichnis mit
# config.json, kein Ollama-Modell) -- steht nur, falls resolve() ihn im
# Nicht-Registry-Zweig doch befragt.
cat >"$BIN/ollama" <<'EOF'
#!/bin/bash
case "$1" in
  list) printf 'NAME\tID\tSIZE\tMODIFIED\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN/ollama"

# MLX-Fixture-Verzeichnis: klein, echte config.json-Form (wie lmgamma-27b, nur
# winzig), damit wb-kontext natives Maximum/Gewichte wirklich lesen kann statt
# zu raten. Ein winziges 1-Byte-safetensors reicht fuer die Gewichtsrechnung.
FIXMODELL="$TESTHOME/fixmodell"
mkdir -p "$FIXMODELL"
cat >"$FIXMODELL/config.json" <<'EOF'
{"text_config": {"max_position_embeddings": 32768}}
EOF
head -c 1048576 /dev/zero > "$FIXMODELL/model.safetensors"   # 1 MiB, genug zum Summieren

# Fake wb-mlx-server: DER PRUEFPUNKT. Protokolliert argv und jede
# WB_MLX_SERVER_VORHERSAGE_*-Variable, die ankommt -- genau das, was Auftrag
# 2026-08-20 als Beleg verlangt ("die Wahl kommt am Aufruf wirklich an"),
# nicht nur eine Zwischenfunktion.
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

# wb-belegung: pi-worker bucht bei einem mlx-local-Spawn dort seine eigene
# Sequenz (Auftrag vom 19.08. abends, N1-Korrektur) -- ohne die echte Datei
# hier bricht JEDER mlx-local-Spawn ab, bevor er je wb-mlx-server erreicht.
# Nicht meine Datei (Auftrag A/parallele Spur), aber unveraendert kopiert,
# nur als Testabhaengigkeit, genau wie wb-state/wb-kontext auch.
for s in wb-state pi-worker claude-worker wb-code wb-grid wb-kontext wb-belegung; do
  cp "$REPO/$s" "$BIN/$s"; chmod +x "$BIN/$s"
done
# check-resources: Attrappe mit reichlich freiem Speicher, NICHT die echte
# Datei (Nachtrag 21.08.2026, Befund B: wb-kontext fragt fuer mlx-local jetzt
# 'wb-belegung darf', und das rechnet mit wb-belegungs eigener, groesserer
# Systemreserve -- 6 GiB, gegen wb-kontexts vorherige 2048 MiB). Mit der
# ECHTEN check-resources haengt "passt" fuer das winzige Fixture-Modell dann
# am gerade wirklich freien Speicher DIESER Maschine, auf der mehrere
# Sitzungen gleichzeitig laufen -- ein Testlauf war so schon bei rund 8,8 GiB
# frei rot, obwohl das Fixture-Modell selbst kaum Speicher braucht. Derselbe
# Kunstgriff wie test-entwerfer.sh: eine feste, reichliche Zahl, damit dieser
# Test das ARGV, nicht die Speicherlage der Testmaschine, prueft.
cat >"$BIN/check-resources" <<'EOF'
#!/bin/sh
echo '{"ram":{"free_mib":40960,"total_mib":49152},"vram":{"free_mib":40960,"total_mib":49152},"ollama_loaded":[]}'
EOF
chmod +x "$BIN/check-resources"
werkzeuge_installieren "$TESTHOME"

export PATH="$BIN:$PATH"
# Ein KV-Wert fuer "fixmodell" (Nachtrag 21.08.2026, Befund B: wb-kontext
# fragt fuer mlx-local jetzt 'wb-belegung darf' fuer bedarfGib/passt statt
# einer eigenen Naeherung -- siehe wb-kontext bedarf_wirklich()). OHNE einen
# Eintrag faellt wb-belegung auf KV_NOTFALL (1,05 MiB/Token, der hungrigste
# gemessene Wert der ganzen Flotte) zurueck und lehnt selbst das winzige
# Fixture-Modell bei jeder Stufe ab -- pi-worker bricht dann VOR dem
# wb-mlx-server-Aufruf ab, den dieser Test eigentlich prueft. Dieselbe Lehre
# steht schon bei test-entwerfer.sh ("ohne ihn faellt wb-belegung auf den
# WORST-CASE-Festwert zurueck").
env HOME="$TESTHOME" PATH="$BIN:$PATH" \
    wb-belegung kv setzen fixmodell 0.02 --herkunft gemessen >/dev/null 2>&1
WBS="$BIN/wb-state"

# Fixture-Registry: EIN Modell mit harness=pi/provider=mlx-local und einem
# 'vorhersage'-Feld -- absichtlich ein ANDERER Wert als der echte
# models.default.json-Eintrag (DFlash2), damit ein Test, der zufaellig gegen
# den Code statt gegen die Registry laesen wuerde, sofort auffiele.
cat >"$TESTHOME/.claude/workbench/models.json" <<EOF
{
  "version": 1,
  "providers": [],
  "harnesses": [],
  "models": [
    {
      "id": "vh-modell",
      "label": "Vorhersage-Testmodell",
      "harness": "pi",
      "provider": "mlx-local",
      "modelRef": "$FIXMODELL",
      "roles": ["worker", "orchestrator"],
      "maxEffort": "high",
      "defaultEffort": "low",
      "enabled": true,
      "vorhersage": {
        "bauart": "entwerfer",
        "modell": "$TESTHOME/fake-entwerfer",
        "gewichteGb": 1.23,
        "herkunft": "Test-Fixture, kein echter Kandidat"
      }
    },
    {
      "id": "vh-ohne",
      "label": "Modell ohne Vorhersage-Eintrag",
      "harness": "pi",
      "provider": "mlx-local",
      "modelRef": "$FIXMODELL",
      "roles": ["worker", "orchestrator"],
      "maxEffort": "high",
      "defaultEffort": "low",
      "enabled": true
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

letzter_eintrag() {   # liest den letzten '---'-getrennten Block aus dem Log
  awk -v RS='---\n' 'END{print}' "$ENSURE_LOG" 2>/dev/null
}

# Die Attrappe fuer wb-mlx-server (oben) gibt eine gebuchte Belegung NIE
# wieder frei -- sie protokolliert nur und beendet sich (exit 0), ohne je
# 'wb-belegung frei' aufzurufen. Jeder pi-worker-Lauf dieses Tests bucht aber
# wirklich (Nachtrag 21.08.2026, Befund B: wb-kontext fragt fuer mlx-local
# jetzt wb-belegung selbst, und der Aufruf davor -- pi-worker -- bucht
# genauso echt wie immer). Ohne diese Leerung haetten Abschnitt 3 und
# folgende noch die offene Belegung von Abschnitt 1/2 im Buch stehen und
# saehen dadurch weniger frei, als wirklich gemeint ist -- ein Test-Artefakt,
# keine Aussage ueber das Werkzeug.
buch_leeren() {
  rm -f "$TESTHOME/.local/state/wb-belegung/buch.json"
}

echo "== 1  pi-worker: workerVorhersage aus (Vorgabe) -- am Aufruf kommt NICHTS an =="
: > "$ENSURE_LOG"
buch_leeren
"$WBS" settings set workerVorhersage false >/dev/null
"$BIN/pi-worker" w-eins vh-modell "$TESTHOME/work" >/dev/null 2>&1
EINTRAG="$(letzter_eintrag)"
if [ -z "$(printf '%s' "$EINTRAG" | sed -n 's/^BAUART=//p')" ]; then
  ok "workerVorhersage aus: wb-mlx-server bekam keine BAUART, obwohl das Modell einen Eintrag hat"
else
  bad "workerVorhersage aus, aber BAUART kam trotzdem an" "$EINTRAG"
fi

echo "== 2  pi-worker: workerVorhersage an, Modell OHNE Registry-Eintrag -- nichts zu uebergeben =="
: > "$ENSURE_LOG"
buch_leeren
"$WBS" settings set workerVorhersage true >/dev/null
"$BIN/pi-worker" w-zwei vh-ohne "$TESTHOME/work" >/dev/null 2>&1
EINTRAG="$(letzter_eintrag)"
if [ -z "$(printf '%s' "$EINTRAG" | sed -n 's/^BAUART=//p')" ]; then
  ok "workerVorhersage an, aber kein Registry-Eintrag: wb-mlx-server bekam trotzdem keine BAUART"
else
  bad "kein Registry-Eintrag, aber BAUART kam trotzdem an" "$EINTRAG"
fi

echo "== 3  pi-worker: workerVorhersage an, Modell MIT Registry-Eintrag -- kommt am Aufruf an =="
: > "$ENSURE_LOG"
buch_leeren
"$BIN/pi-worker" w-drei vh-modell "$TESTHOME/work" >/dev/null 2>&1
EINTRAG="$(letzter_eintrag)"
BAUART="$(printf '%s' "$EINTRAG" | sed -n 's/^BAUART=//p')"
MODELL="$(printf '%s' "$EINTRAG" | sed -n 's/^MODELL=//p')"
GEWICHTE="$(printf '%s' "$EINTRAG" | sed -n 's/^GEWICHTE_GB=//p')"
[ "$BAUART" = entwerfer ] && ok "BAUART=entwerfer kam am wb-mlx-server-Aufruf an" \
  || bad "BAUART kam nicht/falsch an" "$EINTRAG"
[ "$MODELL" = "$TESTHOME/fake-entwerfer" ] && ok "MODELL-Pfad aus der Registry kam unveraendert an" \
  || bad "MODELL kam nicht/falsch an" "$EINTRAG"
[ "$GEWICHTE" = "1.23" ] && ok "GEWICHTE_GB aus der Registry kam an" \
  || bad "GEWICHTE_GB kam nicht/falsch an" "$EINTRAG"

echo "== 4  Registry-Quelle, nicht Code: der Wert AENDERT sich mit der Registry =="
python3 - "$TESTHOME/.claude/workbench/models.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
for m in d["models"]:
    if m["id"] == "vh-modell":
        m["vorhersage"] = {"bauart": "eingebaut", "modell": "/anderer/pfad", "gewichteGb": 9.99}
json.dump(d, open(p, "w"))
PY
: > "$ENSURE_LOG"
buch_leeren
"$BIN/pi-worker" w-vier vh-modell "$TESTHOME/work" >/dev/null 2>&1
EINTRAG="$(letzter_eintrag)"
BAUART="$(printf '%s' "$EINTRAG" | sed -n 's/^BAUART=//p')"
MODELL="$(printf '%s' "$EINTRAG" | sed -n 's/^MODELL=//p')"
if [ "$BAUART" = eingebaut ] && [ "$MODELL" = "/anderer/pfad" ]; then
  ok "geaenderte Registry-Zeile aendert den Aufruf mit -- die Vorgabe kommt aus der Registry, nicht aus dem Code"
else
  bad "Aenderung an der Registry schlug sich nicht im Aufruf nieder" "$EINTRAG"
fi

echo "== 5  wb-code (Orchestrator): eigener Schalter, unabhaengig vom Worker-Schalter =="
: > "$ENSURE_LOG"
buch_leeren
"$WBS" settings set orchestratorVorhersage true >/dev/null
"$WBS" settings set workerVorhersage false >/dev/null      # Gegenprobe: Worker-Schalter aus
"$WBS" settings set orchestratorHarness pi >/dev/null
"$WBS" settings set orchestratorModel vh-modell >/dev/null
"$WBS" settings set orchestratorEffort low >/dev/null
mkdir -p "$TESTHOME/work2"
timeout 20 "$BIN/wb-code" "$TESTHOME/work2" >/dev/null 2>&1 || true
EINTRAG="$(letzter_eintrag)"
BAUART="$(printf '%s' "$EINTRAG" | sed -n 's/^BAUART=//p')"
if [ "$BAUART" = eingebaut ]; then
  ok "wb-code (orchestratorVorhersage=an) reicht die Registry-Wahl an denselben Aufruf durch"
else
  bad "wb-code hat die Vorhersage-Wahl nicht durchgereicht" "$EINTRAG"
fi

echo "== 6  Orchestrator-Schalter aus, obwohl Worker-Schalter (Abschnitt 5) auf aus stand =="
: > "$ENSURE_LOG"
buch_leeren
"$WBS" settings set orchestratorVorhersage false >/dev/null
rm -rf "$TESTHOME/work2"; mkdir -p "$TESTHOME/work2"
tmux -L "$SOCK" kill-session -t "=wb-work2-$$" 2>/dev/null || true
timeout 20 "$BIN/wb-code" "$TESTHOME/work2" >/dev/null 2>&1 || true
EINTRAG="$(letzter_eintrag)"
BAUART="$(printf '%s' "$EINTRAG" | sed -n 's/^BAUART=//p')"
if [ -z "$BAUART" ]; then
  ok "orchestratorVorhersage=aus: nichts kommt an, unabhaengig vom Worker-Schalter"
else
  bad "orchestratorVorhersage=aus, aber trotzdem etwas angekommen" "$EINTRAG"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
