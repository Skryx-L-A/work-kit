#!/bin/bash
# test-ollama-endpoint.sh — belegt fuer den Auftrag vom 2026-08-11 (Nachlass
# ollamaEndpoint-Verbindungsstellen), dass die Einstellung wirklich an einer echten
# Verbindungsstelle ankommt, statt nur in der Oberflaeche zu stehen.
#
# Geprueft an `wb-state models resolve lmalpha-9b`: der Harness 'pi' traegt seinen
# env-Wert OLLAMA_HOST als {baseUrl:ollama}-Platzhalter (shell/models.default.json,
# genau die Stelle, die dieser Auftrag von einem festen Literal umgestellt hat) und
# der Aufloeser in shell/wb-state (ollama_baseurl()) setzt dafuer settings.json ->
# ollamaEndpoint vor die Registry-Adresse, aber nur in gueltiger Form.
#
# ISOLATION: eigenes HOME (mktemp -d), eigene Kopie von wb-state und
# models.default.json aus DIESEM Repo-Stand — nie die echte ~/.claude/workbench/*.
# `models resolve` startet keinen Pane und braucht deshalb keinen eigenen tmux-Socket.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
have() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "erwartet '$3' in: $(printf '%s' "$2" | tr '\n' '|')" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "'$3' steht in der Ausgabe, darf es aber nicht" ;; *) ok "$1" ;; esac; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "'$2' != '$3'"; fi; }

TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-ollama-endpoint-test.XXXXXX")" && pwd)"
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT INT TERM
export HOME="$TESTHOME"
BIN="$TESTHOME/.local/bin"; mkdir -p "$BIN" "$TESTHOME/.claude/workbench" "$TESTHOME/work"
cp "$REPO/wb-state" "$BIN/wb-state"; chmod +x "$BIN/wb-state"
cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"
# Kit: no shipped adapter carries {baseUrl:ollama} (local models run on kit-llm, no Ollama model
# ships); a fixture harness and model carry the placeholder the Ollama provider is resolved into.
/usr/bin/python3 - "$TESTHOME/.claude/workbench/models.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["harnesses"].append({"id": "fixollamaenv", "command": "/bin/echo", "args": ["--model", "{model}"],
                       "cwdMode": "cd", "env": {"OLLAMA_HOST": "{baseUrl:ollama}"},
                       "systemPrompt": {"style": "none"}, "readyPattern": "x", "promptPattern": "^x"})
d["models"].append({"id": "ollama-fix", "harness": "fixollamaenv", "provider": "ollama",
                    "modelRef": "qwen3.5:4b", "roles": ["worker"], "enabled": True,
                    "supportsEffort": False})
json.dump(d, open(sys.argv[1], "w"), indent=2)
PY
# Der Bindungs-Gate von `models resolve` verlangt nur, dass das Binary des Harness
# AUFFINDBAR ist — gestartet wird hier nie etwas, der Fake muss nichts koennen.
printf '#!/bin/bash\nexit 0\n' >"$BIN/pi"; chmod +x "$BIN/pi"
export PATH="$BIN:$PATH"
WBS="$BIN/wb-state"

echo "== 1. ohne gesetzten Wert bleibt die Auslieferung exakt stehen =="
out="$("$WBS" models resolve ollama-fix --role worker --dir "$TESTHOME/work" --name w1 2>&1)"
have "kein settings.json -> Auslieferung http://127.0.0.1:11434" "$out" \
  "$(printf 'env\tOLLAMA_HOST\thttp://127.0.0.1:11434')"

echo "== 2. ein gesetzter ollamaEndpoint erreicht die Verbindungsstelle wirklich =="
"$WBS" settings set ollamaEndpoint "http://10.20.30.40:9999" >/dev/null
out="$("$WBS" models resolve ollama-fix --role worker --dir "$TESTHOME/work" --name w2 2>&1)"
have "OLLAMA_HOST traegt den gesetzten Wert" "$out" \
  "$(printf 'env\tOLLAMA_HOST\thttp://10.20.30.40:9999')"
hasnt "die alte Auslieferung steht nicht mehr in der env-Zeile" "$out" "127.0.0.1:11434"

echo "== 3. leerer Wert schaltet nie still alle lokalen Modelle ab (Auflage des Auftrags) =="
"$WBS" settings set ollamaEndpoint "" >/dev/null
out="$("$WBS" models resolve ollama-fix --role worker --dir "$TESTHOME/work" --name w3 2>&1)"
have "leerer Wert faellt auf die Auslieferung zurueck" "$out" \
  "$(printf 'env\tOLLAMA_HOST\thttp://127.0.0.1:11434')"

echo "== 4. unsinnige Form faellt ebenso auf die Auslieferung zurueck =="
"$WBS" settings set ollamaEndpoint "nicht-mal-eine-url" >/dev/null
out="$("$WBS" models resolve ollama-fix --role worker --dir "$TESTHOME/work" --name w4 2>&1)"
have "unsinniger Wert faellt auf die Auslieferung zurueck" "$out" \
  "$(printf 'env\tOLLAMA_HOST\thttp://127.0.0.1:11434')"

echo "== 5. dieselbe Adresse erreicht auch discover_ollama() (ollama list) =="
# discover_ollama() liest r.stderr nur im Fehlerfall (returncode != 0) -- ein
# echtes 'ollama list' meldet aber Erfolg, also schreibt der Fake den gesehenen
# OLLAMA_HOST in eine Datei, statt sich auf durchgereichtes stderr zu verlassen.
SEEN_HOST_FILE="$TESTHOME/seen-ollama-host.txt"
cat >"$BIN/ollama" <<EOF
#!/bin/bash
if [ "\$1" = "list" ]; then
  printf '%s' "\$OLLAMA_HOST" >"$SEEN_HOST_FILE"
  printf 'NAME\tID\tSIZE\tMODIFIED\n'
fi
EOF
chmod +x "$BIN/ollama"
"$WBS" settings set ollamaEndpoint "http://10.20.30.40:9999" >/dev/null
"$WBS" models add --kind harness '{"id":"fixollamaep","command":"/bin/echo","args":[],"cwdMode":"cd","systemPrompt":{"style":"none"},"readyPattern":"x","promptPattern":"^x","discover":{"source":"ollama","provider":"ollama","refTemplate":"pfx/{name}"}}' >/dev/null
"$WBS" models discover fixollamaep >/dev/null 2>&1
SEEN_HOST="$(cat "$SEEN_HOST_FILE" 2>/dev/null || echo "<nichts geschrieben>")"
eq "discover_ollama() bekam den gesetzten OLLAMA_HOST" "$SEEN_HOST" "http://10.20.30.40:9999"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
