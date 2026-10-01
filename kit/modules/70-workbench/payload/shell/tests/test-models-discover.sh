#!/bin/bash
# test-models-discover.sh — automated tests for 'wb-state models discover'
# (SPEC-V3-MODELS discover, Vertrag scratchpad/CONTRACT-discover.md 2026-07-29).
#
# WARNUNG wie in test-registry.sh: dieser Test ruft die INSTALLIERTEN Skripte
# unter der eigenen Test-PATH auf. Nicht waehrend eines Laufs nach ~/.local/bin
# deployen — das erzeugt Phantom-Fehlschlaege.
#
# ISOLATION (Regeln 2026-07-25/29, wie test-registry.sh):
#   * unset TMUX TMUX_PANE zuerst, eigenes HOME (mktemp -d) — das echte
#     ~/.claude/workbench/models.json wird hier nie gelesen oder geschrieben.
#   * JEDE discover-Quelle ist eine WEGWERF-Fixture, die auf ein Fake-Binary
#     bzw. eine Fake-Datei unter der eigenen Test-PATH/HOME zeigt — nie ein
#     ausgeliefertes Preset (pi/aider/opencode/codex/agy) und nie der echte
#     'ollama'/'opencode'/'agy'-Befehl dieser Maschine: ein Test, der davon
#     abhaengt, was hier zufaellig installiert ist, testet die Maschine statt
#     den Code (Regel 2026-07-29).
#   * eigene, harnessfremde ids (fixollama/fixcmd/fixfile/fixdry) — kollidieren
#     mit nichts Kuratiertem, egal was models.default.json gerade enthaelt.
#
# Run: shell/tests/test-models-discover.sh
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
echo "Geprueft: Repo-Stand aus $REPO"
PASS=0; FAIL=0

TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-discover-test.XXXXXX")" && pwd)"
export HOME="$TESTHOME"
BIN="$TESTHOME/.local/bin"; mkdir -p "$BIN" "$TESTHOME/.claude/workbench" "$TESTHOME/.local/state"
export TMPDIR="$TESTHOME/tmp/"; mkdir -p "$TMPDIR"

HTTP_PID=""
cleanup() {
  if [ -n "$HTTP_PID" ]; then kill "$HTTP_PID" 2>/dev/null || true; wait "$HTTP_PID" 2>/dev/null || true; fi
  rm -rf "$TESTHOME"
}
trap cleanup EXIT INT TERM

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
have() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "erwartet '$3' in: $(printf '%s' "$2" | head -3 | tr '\n' ' ')" ;; esac; }
hasnt(){ case "$2" in *"$3"*) bad "$1" "'$3' steht in der Ausgabe, darf es aber nicht" ;; *) ok "$1" ;; esac; }
eq()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "'$2' != '$3'"; fi; }
exists(){ "$WBS" models get "$1" --field id >/dev/null 2>&1; }   # true = Eintrag da

cp "$REPO/wb-state" "$BIN/wb-state"; chmod +x "$BIN/wb-state"
export PATH="$BIN:$PATH"
WBS="$BIN/wb-state"
MODELSFILE="$TESTHOME/.claude/workbench/models.json"
STATEFILE="$TESTHOME/.local/state/wb-models-discover.json"

# ── Fixture 1: source 'ollama' — ein FAKES ollama-Binary, nie das echte ─────────
cat >"$BIN/ollama" <<EOF
#!/bin/bash
[ "\$1" = "list" ] && cat "$TESTHOME/ollama-list.txt"
EOF
chmod +x "$BIN/ollama"
cat >"$TESTHOME/ollama-list.txt" <<'EOF'
NAME                            ID        SIZE   MODIFIED
curated-ref                     a1        1 GB   1 day ago
alpha-model                     a2        1 GB   1 day ago
beta-model                      a3        1 GB   1 day ago
EOF

# ── Fixture 2: source 'command-lines' — ein Stub, der gezielt scheitern kann ────
cat >"$BIN/fixcmdtool" <<EOF
#!/bin/bash
if [ -f "$TESTHOME/fixcmd-fail" ]; then
  echo "fixcmdtool: kaputt" >&2
  exit 7
fi
cat "$TESTHOME/fixcmd-list.txt"
EOF
chmod +x "$BIN/fixcmdtool"
cat >"$TESTHOME/fixcmd-list.txt" <<'EOF'
cmd-ref-one
cmd-ref-two
EOF

# ── Fixture 3: source 'file-json' — eine Wegwerf-JSON-Datei, nie der echte
# Codex-Cache ─────────────────────────────────────────────────────────────────
FIXFILE="$TESTHOME/fixture-models.json"
cat >"$FIXFILE" <<'EOF'
{"models":[
  {"slug":"file-ref-one","visibility":"list"},
  {"slug":"file-ref-hidden","visibility":"hidden"},
  {"slug":"file-ref-two","visibility":"list"}
]}
EOF

# ── die drei Wegwerf-Harnesses registrieren ─────────────────────────────────────
# fixollama: effort.map traegt bewusst auch 'max'/'ultra', um direkt am generierten
# Eintrag zu pruefen, dass beide in efforts stehen, aber nie im Deckel. refTemplate
# 'pfx/{name}' prueft die woertliche Vertrags-Regel ueber den Slug der FERTIGEN
# modelRef (nicht der rohen Quell-Referenz).
"$WBS" models add --kind harness '{"id":"fixollama","command":"/bin/echo","args":[],"cwdMode":"cd","systemPrompt":{"style":"none"},"readyPattern":"x","promptPattern":"^x","effort":{"style":"arg","args":["--effort","{effort}"],"map":{"low":"low","medium":"medium","high":"high","xhigh":"xhigh","max":"max","ultra":"ultra"}},"discover":{"source":"ollama","provider":"ollama","refTemplate":"pfx/{name}"}}' >/dev/null

"$WBS" models add --kind harness '{"id":"fixcmd","command":"/bin/echo","args":[],"cwdMode":"cd","systemPrompt":{"style":"none"},"readyPattern":"x","promptPattern":"^x","discover":{"source":"command-lines","command":["fixcmdtool"],"provider":"ollama"}}' >/dev/null

FIXFILE_HARNESS_JSON=$(printf '{"id":"fixfile","command":"/bin/echo","args":[],"cwdMode":"cd","systemPrompt":{"style":"none"},"readyPattern":"x","promptPattern":"^x","discover":{"source":"file-json","file":"%s","jsonPath":"models[].slug","filter":{"field":"visibility","equals":"list"},"provider":"ollama"}}' "$FIXFILE")
"$WBS" models add --kind harness "$FIXFILE_HARNESS_JSON" >/dev/null

# Kuratierter Eintrag VOR dem ersten Lauf: (harness=fixollama, modelRef=pfx/curated-ref)
# muss den automatischen Zwilling verhindern (Vertrag 4.2).
"$WBS" models add '{"id":"my-curated","harness":"fixollama","provider":"ollama","modelRef":"pfx/curated-ref","roles":["worker"],"workerClass":["bulk"],"goodFor":"curated fixture"}' >/dev/null

echo "== 1. Neuanlage + kuratierter Eintrag verhindert das Duplikat + Geschwisterwerte =="
out="$("$WBS" models discover fixollama --json)"
have "neue ids: alpha" "$out" "fixollama-pfx-alpha-model"
have "neue ids: beta"  "$out" "fixollama-pfx-beta-model"
hasnt "kein Zwilling fuer den kuratierten Eintrag" "$out" "fixollama-pfx-curated-ref"
eq "curated-ref bleibt als my-curated stehen" "$("$WBS" models get my-curated --field modelRef)" "pfx/curated-ref"
have "kept ist 0 beim ersten Lauf" "$out" '"kept": 0'
eq "roles vom naechsten kuratierten Geschwister" "$("$WBS" models get fixollama-pfx-alpha-model --field roles)" '["worker"]'
eq "machines fest mac+host2" "$("$WBS" models get fixollama-pfx-alpha-model --field machines)" '["mac", "host2"]'
eq "source ist auto" "$("$WBS" models get fixollama-pfx-alpha-model --field source)" "auto"

# 2026-08-06: `efforts` BESCHREIBT jetzt, was der Harness annimmt, und `max` gehoert
# dazu, wo es gemessen ist -- die Liste ist eine Tatsache ueber das Werkzeug, keine
# Erlaubnis. Was `max` fuer einen Agenten weiterhin ausschliesst, ist der DECKEL:
# `maxEffort` bleibt die hoechste Stufe UNTERHALB von max, hier unveraendert xhigh.
# Die Regel von 2026-07-25 gilt damit weiter, sie steht nur in der richtigen Spalte.
# 2026-09-13: seit 7c4263d kennt die Rangfolge auch 'ultra' (Codex) -- es gehoert
# damit in die Stufenliste, liegt aber wie 'max' ueber dem Deckel.
echo "== 2. efforts beschreibt den Harness, maxEffort deckelt (2026-08-06) =="
EFF="$("$WBS" models get fixollama-pfx-alpha-model --field efforts)"
eq "efforts ist die Stufenliste des Harness" "$EFF" '["low", "medium", "high", "xhigh", "max", "ultra"]'
eq "maxEffort bleibt xhigh — 'max' ist nicht der ausgelieferte Deckel" \
   "$("$WBS" models get fixollama-pfx-alpha-model --field maxEffort)" "xhigh"
eq "defaultEffort ist medium" "$("$WBS" models get fixollama-pfx-alpha-model --field defaultEffort)" "medium"

echo "== 3. unveraendert zweiter Lauf =="
out2="$("$WBS" models discover fixollama --json)"
have "zweiter Lauf: nichts neu" "$out2" '"added": []'
have "zweiter Lauf: nichts aktualisiert" "$out2" '"updated": []'
have "zweiter Lauf: nichts entfernt" "$out2" '"removed": []'
have "zweiter Lauf: 2 unveraendert" "$out2" '"kept": 2'

echo "== 4. enabled:false ueberlebt einen erneuten Lauf =="
"$WBS" models set fixollama-pfx-alpha-model enabled false >/dev/null
"$WBS" models discover fixollama --json >/dev/null
eq "enabled bleibt false" "$("$WBS" models get fixollama-pfx-alpha-model --field enabled)" "false"

echo "== 5. verschwundene Referenz wird entfernt =="
cat >"$TESTHOME/ollama-list.txt" <<'EOF'
NAME                            ID        SIZE   MODIFIED
curated-ref                     a1        1 GB   1 day ago
alpha-model                     a2        1 GB   1 day ago
EOF
out5="$("$WBS" models discover fixollama --json)"
have "beta-model steht als entfernt im Ergebnis" "$out5" "fixollama-pfx-beta-model"
have "removed ist nicht leer" "$out5" '"removed": ["fixollama-pfx-beta-model"]'
exists fixollama-pfx-beta-model && bad "beta-model wirklich weg" "existiert noch" || ok "beta-model wirklich weg"
exists fixollama-pfx-alpha-model && ok "alpha-model bleibt (disabled, aber vorhanden)" || bad "alpha-model bleibt (disabled, aber vorhanden)"
exists my-curated && ok "kuratierter Eintrag unangetastet" || bad "kuratierter Eintrag unangetastet"

echo "== 6. file-json + filter: nur visibility==list, echte Codex-Cache-Form =="
out6="$("$WBS" models discover fixfile --json)"
have "file-ref-one erkannt" "$out6" "fixfile-file-ref-one"
have "file-ref-two erkannt" "$out6" "fixfile-file-ref-two"
hasnt "hidden bleibt draussen (filter)" "$out6" "file-ref-hidden"
exists fixfile-file-ref-hidden && bad "hidden wurde nicht angelegt" "existiert" || ok "hidden wurde nicht angelegt"
eq "opencode-Stil-Referenz style=none -> supportsEffort false" "$("$WBS" models get fixfile-file-ref-one --field supportsEffort)" "false"
OUT_GET="$("$WBS" models get fixfile-file-ref-one 2>&1)"
hasnt "keine efforts, wenn supportsEffort false" "$OUT_GET" '"efforts"'

echo "== 7. gescheiterte Quelle entfernt NICHTS =="
out7a="$("$WBS" models discover fixcmd --json)"
have "fixcmd erste Erkennung: 2 neu" "$out7a" '"added": ["fixcmd-cmd-ref-one", "fixcmd-cmd-ref-two"]'
: >"$TESTHOME/fixcmd-fail"
out7b="$("$WBS" models discover fixcmd --json)"; rc7b=$?
have "Fehler wird gemeldet" "$out7b" '"error": "fixcmdtool'
[ "$rc7b" -ne 0 ] && ok "einzig angeforderter Harness gescheitert -> exit != 0" \
  || bad "einzig angeforderter Harness gescheitert -> exit != 0" "rc=$rc7b"
exists fixcmd-cmd-ref-one && ok "cmd-ref-one bleibt trotz gescheiterter Quelle" \
  || bad "cmd-ref-one bleibt trotz gescheiterter Quelle" "wurde entfernt"
exists fixcmd-cmd-ref-two && ok "cmd-ref-two bleibt trotz gescheiterter Quelle" \
  || bad "cmd-ref-two bleibt trotz gescheiterter Quelle" "wurde entfernt"
have "kept zaehlt die unberuehrten Eintraege mit" "$out7b" '"kept": 2'

echo "== 8. Exit-Code: nur wenn ALLE angeforderten Harnesses scheitern =="
outmix="$("$WBS" models discover fixfile fixcmd --json)"; rcmix=$?
[ "$rcmix" -eq 0 ] && ok "ein Erfolg neben einem Fehlschlag -> exit 0" \
  || bad "ein Erfolg neben einem Fehlschlag -> exit 0" "rc=$rcmix"
outboth="$("$WBS" models discover fixcmd doesnotexist --json)"; rcboth=$?
have "unbekannter Harness meldet 'kein discover-Block'" "$outboth" "kein discover-Block fuer 'doesnotexist'"
[ "$rcboth" -ne 0 ] && ok "beide angeforderten Harnesses gescheitert -> exit != 0" \
  || bad "beide angeforderten Harnesses gescheitert -> exit != 0" "rc=$rcboth"
rm -f "$TESTHOME/fixcmd-fail"

echo "== 9. --dry-run rechnet, schreibt aber NICHTS =="
"$WBS" models add --kind harness '{"id":"fixdry","command":"/bin/echo","args":[],"cwdMode":"cd","systemPrompt":{"style":"none"},"readyPattern":"x","promptPattern":"^x","discover":{"source":"ollama","provider":"ollama"}}' >/dev/null
SUM_BEFORE=$(md5 -q "$MODELSFILE" 2>/dev/null || md5sum "$MODELSFILE" | cut -d' ' -f1)
[ -f "$STATEFILE" ] && SUM_STATE_BEFORE=$(md5 -q "$STATEFILE" 2>/dev/null || md5sum "$STATEFILE" | cut -d' ' -f1) || SUM_STATE_BEFORE="(fehlt)"
outdry="$("$WBS" models discover fixdry --dry-run --json)"
have "dry-run rechnet trotzdem: meldet die neuen ids" "$outdry" "fixdry-alpha-model"
exists fixdry-alpha-model && bad "dry-run legt nichts an" "fixdry-alpha-model existiert" || ok "dry-run legt nichts an"
SUM_AFTER=$(md5 -q "$MODELSFILE" 2>/dev/null || md5sum "$MODELSFILE" | cut -d' ' -f1)
eq "models.json bleibt byteweise gleich" "$SUM_BEFORE" "$SUM_AFTER"
if [ -f "$STATEFILE" ]; then SUM_STATE_AFTER=$(md5 -q "$STATEFILE" 2>/dev/null || md5sum "$STATEFILE" | cut -d' ' -f1); else SUM_STATE_AFTER="(fehlt)"; fi
eq "Discover-Zeitstempel bleibt unveraendert" "$SUM_STATE_BEFORE" "$SUM_STATE_AFTER"

echo "== 10. --if-stale ueberspringt innerhalb der TTL =="
have "Zeitstempel fuer fixfile wurde beim echten Lauf (Abschnitt 6) gesetzt" \
  "$(cat "$STATEFILE" 2>/dev/null)" '"fixfile"'
outstale="$("$WBS" models discover fixfile --if-stale --json)"
eq "frischer Harness liefert ein leeres Ergebnis" "$outstale" "{}"
# ein noch nie erkannter Harness ist NIE 'frisch genug' und wird trotzdem erkannt.
outstale2="$("$WBS" models discover fixdry --if-stale --json)"
have "unbekannter Harness wird trotz --if-stale erkannt" "$outstale2" "fixdry-alpha-model"

echo "== 11. zweispaltige Ausgabe: das echte agy-Format wird gelesen (2026-08-08) =="
# Das Format, an dem discover_command_lines am 08.08. gescheitert ist — als FIXTURE,
# nie durch einen Aufruf des installierten 'agy' (Regel oben: ein Test haengt nie an
# dem, was auf dieser Maschine zufaellig installiert ist). Woertlich abgeschrieben von
# 'agy models' dieses Tages, samt Banner: das echte geht nach stderr, die Zeile auf
# stdout steht zusaetzlich hier, weil der Bannerschutz sie weiter abfangen muss.
cat >"$BIN/fixtsvtool" <<EOF
#!/bin/bash
echo "Fetching available models..." >&2
[ -f "$TESTHOME/fixtsv-empty" ] && exit 0
cat "$TESTHOME/fixtsv-list.txt"
EOF
chmod +x "$BIN/fixtsvtool"
{ printf 'Verfuegbare Modelle:\n'
  printf 'gemini-3.6-flash-high\tGemini 3.6 Flash (High)\n'
  printf 'gemini-3.6-flash-medium\tGemini 3.6 Flash (Medium)\n'
  printf 'gemini-3.6-flash-low\tGemini 3.6 Flash (Low)\n'
  printf 'gemini-3.5-flash-high\tGemini 3.5 Flash (High)\n'
  printf 'gemini-3.5-flash-medium\tGemini 3.5 Flash (Medium)\n'
  printf 'gemini-3.5-flash-low\tGemini 3.5 Flash (Low)\n'
  printf 'gemini-3.1-pro-high\tGemini 3.1 Pro (High)\n'
  printf 'gemini-3.1-pro-low\tGemini 3.1 Pro (Low)\n'
  printf 'claude-sonnet-4-6\tClaude Sonnet 4.6 (Thinking)\n'
  printf 'claude-opus-4-6-thinking\tClaude Opus 4.6 (Thinking)\n'
  printf 'gpt-oss-120b-medium\tGPT-OSS 120B (Medium)\n'
} >"$TESTHOME/fixtsv-list.txt"
"$WBS" models add --kind harness '{"id":"fixtsv","command":"/bin/echo","args":[],"cwdMode":"cd","systemPrompt":{"style":"none"},"readyPattern":"x","promptPattern":"^x","discover":{"source":"command-lines","command":["fixtsvtool"],"provider":"ollama"}}' >/dev/null
out11="$("$WBS" models discover fixtsv --json)"
eq "alle 11 Modelle der zweispaltigen Ausgabe erkannt" \
  "$("$WBS" models list --all | grep -c '^fixtsv-')" "11"
have "erste Spalte ist die Referenz, nicht die ganze Zeile" "$out11" '"fixtsv-gemini-3-6-flash-high"'
have "auch der letzte Eintrag" "$out11" '"fixtsv-gpt-oss-120b-medium"'
hasnt "die Beschreibungsspalte landet in keiner id" "$out11" "flash-high-gemini"
hasnt "Bannerzeile auf stdout wird weiter verworfen" "$out11" "verfuegbare-modelle"
eq "modelRef ist der rohe Name der ersten Spalte" \
  "$("$WBS" models get fixtsv-claude-opus-4-6-thinking --field modelRef)" "claude-opus-4-6-thinking"

echo "== 12. 'separator' aus dem discover-Block fuer ein Format, das nicht zu raten ist =="
cat >"$BIN/fixpipetool" <<'EOF'
#!/bin/bash
printf 'MODELLE\n'
printf 'pipe-ref-one | erste Beschreibung\n'
printf 'pipe-ref-two | zweite Beschreibung\n'
EOF
chmod +x "$BIN/fixpipetool"
"$WBS" models add --kind harness '{"id":"fixpipe","command":"/bin/echo","args":[],"cwdMode":"cd","systemPrompt":{"style":"none"},"readyPattern":"x","promptPattern":"^x","discover":{"source":"command-lines","command":["fixpipetool"],"separator":" | ","provider":"ollama"}}' >/dev/null
out12="$("$WBS" models discover fixpipe --json)"
have "separator ' | ': erste Spalte erkannt" "$out12" '"fixpipe-pipe-ref-one"'
have "separator ' | ': zweite Zeile auch" "$out12" '"fixpipe-pipe-ref-two"'
eq "genau 2 Eintraege — die Kopfzeile ohne Trennzeichen faellt heraus" \
  "$("$WBS" models list --all | grep -c '^fixpipe-')" "2"

echo "== 13. eine LEERE Antwort entfernt NICHTS (Vorfall 2026-08-08) =="
# Der eigentliche Schaden jenes Tages: 'agy models' lieferte fehlerfrei eine leere
# Liste, und der Lauf meldete "-9 entfernt". Diese Zusage schlaegt ohne die Sperre fehl.
: >"$TESTHOME/fixtsv-empty"
SUM_STATE_13=$(md5 -q "$STATEFILE" 2>/dev/null || md5sum "$STATEFILE" | cut -d' ' -f1)
out13="$("$WBS" models discover fixtsv --json)"; rc13=$?
eq "alle 11 Eintraege stehen nach der leeren Antwort immer noch da" \
  "$("$WBS" models list --all | grep -c '^fixtsv-')" "11"
have "removed bleibt leer" "$out13" '"removed": []'
have "die unterbliebene Entscheidung steht im Protokoll" "$out13" "Entscheidung UNTERBLIEBEN"
have "die Meldung nennt den Bestand" "$out13" "11 automatische Eintraege"
have "die Meldung nennt den Ausweg" "$out13" "--allow-empty"
have "maschinenlesbare Marke fuer die Oberflaeche" "$out13" '"skippedEmpty": true'
have "kept zaehlt die geretteten Eintraege" "$out13" '"kept": 11'
[ "$rc13" -ne 0 ] && ok "Ausfall der einzigen Quelle -> exit != 0" \
  || bad "Ausfall der einzigen Quelle -> exit != 0" "rc=$rc13"
SUM_STATE_13B=$(md5 -q "$STATEFILE" 2>/dev/null || md5sum "$STATEFILE" | cut -d' ' -f1)
eq "kein Zeitstempel — die Quelle gilt nicht als frisch erkannt" "$SUM_STATE_13" "$SUM_STATE_13B"
outdry13="$("$WBS" models discover fixtsv --dry-run --json)"
have "--dry-run zeigt dieselbe unterbliebene Entscheidung" "$outdry13" "Entscheidung UNTERBLIEBEN"

echo "== 14. --allow-empty raeumt wirklich ab (der echte Abkuendigungs-Fall) =="
out14="$("$WBS" models discover fixtsv --allow-empty --json)"
have "mit dem Schalter werden sie entfernt" "$out14" '"fixtsv-gemini-3-6-flash-high"'
eq "kein fixtsv-Eintrag mehr uebrig" "$("$WBS" models list --all | grep -c '^fixtsv-')" "0"
hasnt "keine Sperr-Meldung mehr" "$out14" "Entscheidung UNTERBLIEBEN"

echo "== 15. leer OHNE Bestand ist kein Ausfall, sondern ein leeres Ergebnis =="
out15="$("$WBS" models discover fixtsv --json)"; rc15=$?
have "zweiter leerer Lauf meldet keinen Fehler mehr" "$out15" '"error": null'
[ "$rc15" -eq 0 ] && ok "nichts zu verlieren -> exit 0" || bad "nichts zu verlieren -> exit 0" "rc=$rc15"
rm -f "$TESTHOME/fixtsv-empty"

echo "== 16. dieselbe Sperre bei 'file-json' (C: die Luecke klafft in jeder Quellform) =="
out16a="$("$WBS" models discover fixfile --json)"
eq "Ausgangslage: 2 Eintraege aus der Datei" "$("$WBS" models list --all | grep -c '^fixfile-')" "2"
# Nicht kaputt, nicht leer — nur filtert 'visibility' jetzt alles weg. Fehlerfrei, und
# genau deshalb frueher toedlich.
cat >"$FIXFILE" <<'EOF'
{"models":[
  {"slug":"file-ref-one","visibility":"hidden"},
  {"slug":"file-ref-two","visibility":"hidden"}
]}
EOF
out16b="$("$WBS" models discover fixfile --json)"
have "auch hier: nichts entfernt, Entscheidung unterblieben" "$out16b" "Entscheidung UNTERBLIEBEN"
eq "beide Datei-Eintraege stehen noch" "$("$WBS" models list --all | grep -c '^fixfile-')" "2"

echo "== 17. dieselbe Sperre bei 'ollama' — die Quelle mit dem groessten Bestand =="
# Gemessen 2026-08-08 mit einem unerreichbaren Dienst (OLLAMA_HOST auf einen toten
# Port): 'ollama list' meldet "Error: could not connect to ollama server" und endet
# mit 1 — ein gestopptes Ollama war also nie der gefaehrliche Fall, das faengt der
# err-Zweig seit jeher ab. Gefaehrlich ist ein LAUFENDES Ollama ohne ein einziges
# Modell: nur die Kopfzeile, Exit 0. Genau das steht hier als Fixture, weil es sich
# ohne Loeschen echter Modelle nicht herstellen laesst.
cat >"$TESTHOME/ollama-list.txt" <<'EOF'
NAME                            ID        SIZE   MODIFIED
EOF
out17="$("$WBS" models discover fixollama --json)"
have "leere ollama-Liste: Entscheidung unterblieben" "$out17" "Entscheidung UNTERBLIEBEN"
exists fixollama-pfx-alpha-model && ok "alpha-model ueberlebt die leere ollama-Liste" \
  || bad "alpha-model ueberlebt die leere ollama-Liste" "wurde entfernt"
exists my-curated && ok "kuratierter Eintrag ohnehin unangetastet" || bad "kuratierter Eintrag ohnehin unangetastet"

echo "== 18. binary-strings: Picker-Label, 1M-Variante, Alias und Versionswechsel =="
cat >"$BIN/fixbinary" <<EOF
#!/bin/bash
[ "\${1:-}" = "--version" ] && { cat "$TESTHOME/fixbinary-version"; exit 0; }
# claude-opus-5-5
# claude-opus-5-5[1m]
# claude-opus-4-20250514
# Opus 5.5 - best for everyday, complex tasks
# Opus 5.5 with 1M context
EOF
printf 'fixbinary 1.0.0\n' >"$TESTHOME/fixbinary-version"
chmod +x "$BIN/fixbinary"
"$WBS" models add --kind harness '{"id":"fixbinary","command":"fixbinary","args":[],"cwdMode":"cd","systemPrompt":{"style":"none"},"readyPattern":"x","promptPattern":"^x","effort":{"style":"arg","args":["--effort","{effort}"],"map":{"low":"low","high":"high"}},"discover":{"source":"binary-strings","pattern":"(?P<id>claude-(?P<family>opus|sonnet)-(?P<version>[0-9]+(?:-[0-9]+)*)(?:\\[1m\\])?)","labelPattern":"{familyTitle} {versionDots} - ","variantLabelPattern":"{familyTitle} {versionDots} with 1M context","idPrefix":"","provider":"ollama","contextWindowBySuffix":{"[1m]":1000000}}}' >/dev/null
out18a="$("$WBS" models discover fixbinary --json)"
have "Binary-Basismodell erkannt" "$out18a" 'claude-opus-5-5'
have "1M-Variante als eigener Eintrag erkannt" "$out18a" 'claude-opus-5-5-1m'
hasnt "alte API-Kennung ohne Picker-Label ausgeschlossen" "$out18a" '20250514'
eq "1M-Kontext am Varianteneintrag" "$("$WBS" models get claude-opus-5-5-1m --field contextWindow)" '1000000'
eq "Fund merkt die installierte CLI-Version" "$("$WBS" models get claude-opus-5-5 --field discoveredVersion)" '1.0.0'
"$WBS" models add '{"id":"fix-alias-target","alias":"opus55","harness":"fixbinary","provider":"ollama","modelRef":"alias-target","roles":["worker"],"maxEffort":"high","defaultEffort":"low"}' >/dev/null
eq "Registry-Alias wird aufgeloest" "$("$WBS" models get opus55 --field id)" 'fix-alias-target'
out18b="$("$WBS" models discover fixbinary --if-stale --json)"
eq "gleiche frische Binary-Version wird uebersprungen" "$out18b" '{}'
cat >>"$BIN/fixbinary" <<'EOF'
# claude-sonnet-5-6
# Sonnet 5.6 - fast and capable
EOF
printf 'fixbinary 2.0.0\n' >"$TESTHOME/fixbinary-version"
out18c="$("$WBS" models discover fixbinary --if-stale --json)"
have "Versionswechsel invalidiert TTL sofort" "$out18c" 'claude-sonnet-5-6'
eq "erneuter Fund aktualisiert die CLI-Version" "$("$WBS" models get claude-sonnet-5-6 --field discoveredVersion)" '2.0.0'

echo "== 19. files: Verzeichnisse, Markerfilter, Geschwister und frischer Plattenstand =="
mkdir -p "$TESTHOME/models/main-one" "$TESTHOME/models/draft-one"
printf '{"model_type":"qwen3_5"}\n' >"$TESTHOME/models/main-one/config.json"
printf '{"architectures":["DFlash2DraftModel"]}\n' >"$TESTHOME/models/draft-one/config.json"
"$WBS" models add --kind harness '{"id":"fixrunner","command":"/bin/echo","args":[],"cwdMode":"cd","systemPrompt":{"style":"none"},"readyPattern":"x","promptPattern":"^x"}' >/dev/null
FIXPROV=$(printf '{"id":"fixfiles","label":"Fixture files","kind":"local","defaultRunner":"fixrunner","discover":{"source":"files","labelFromRef":"basename","roots":[{"path":"%s/models","glob":"*","kind":"dir","marker":"config.json","ref":"absolute","markerExcludePattern":"DFlash2DraftModel"}]}}' "$TESTHOME")
"$WBS" models add --kind provider "$FIXPROV" >/dev/null
"$WBS" models add "$(printf '{"id":"fixfiles-curated","harness":"fixrunner","provider":"fixfiles","modelRef":"%s/models/curated","roles":["worker"],"machines":["mac"]}' "$TESTHOME")" >/dev/null
out19a="$("$WBS" models discover fixfiles --json)"
have "Hauptmodellverzeichnis erkannt" "$out19a" 'fixrunner-fixfiles-'
hasnt "Entwerferverzeichnis per Config ausgeschlossen" "$out19a" 'draft-one'
AUTO19="$("$WBS" models list --all | awk '/^fixrunner-fixfiles-/ {print $1; exit}')"
eq "Label kommt vom Basisnamen" "$("$WBS" models get "$AUTO19" --field label)" 'main-one'
eq "Rolle vom Provider-Geschwister" "$("$WBS" models get "$AUTO19" --field roles)" '["worker"]'
eq "Maschine vom Provider-Geschwister" "$("$WBS" models get "$AUTO19" --field machines)" '["mac"]'
mkdir -p "$TESTHOME/models/main-two"
printf '{"model_type":"qwen3_5"}\n' >"$TESTHOME/models/main-two/config.json"
out19b="$("$WBS" models discover fixfiles --if-stale --json)"
have "files wird trotz frischer TTL neu inventarisiert" "$out19b" 'main-two'

echo "== 20. files: Enginex-artige Platte plus read-only Endpoint, Endpoint-Ausfall harmlos =="
mkdir -p "$TESTHOME/enginex/owner/disk-model"
PORTFILE="$TESTHOME/http-port"
python3 - "$PORTFILE" <<'PY' &
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body=json.dumps({"data":[{"id":"owner/live-model"}]}).encode()
        self.send_response(200); self.send_header("Content-Type","application/json")
        self.send_header("Content-Length",str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *_): pass
s=HTTPServer(("127.0.0.1",0),H)
open(sys.argv[1],"w").write(str(s.server_port))
s.serve_forever()
PY
HTTP_PID=$!
for _ in $(seq 1 50); do [ -s "$PORTFILE" ] && break; sleep 0.05; done
HTTP_PORT="$(cat "$PORTFILE")"
FIXENGINEX=$(printf '{"id":"fixenginex","label":"Fixture Enginex","kind":"local","defaultRunner":"fixrunner","discover":{"source":"files","roots":[{"path":"%s/enginex","glob":"*/*","kind":"dir","ref":"relative"}],"endpoint":{"url":"http://127.0.0.1:%s/v1/models","jsonPath":"data[].id"}}}' "$TESTHOME" "$HTTP_PORT")
"$WBS" models add --kind provider "$FIXENGINEX" >/dev/null
out20a="$("$WBS" models discover fixenginex --json)"
have "Enginex-Paket auf Platte erkannt" "$out20a" 'owner-disk-model'
have "laufender Endpoint read-only vereinigt" "$out20a" 'owner-live-model'
kill "$HTTP_PID" 2>/dev/null || true; wait "$HTTP_PID" 2>/dev/null || true; HTTP_PID=""
out20b="$("$WBS" models discover fixenginex --json)"
have "toter Endpoint laesst Plattenmodell bestehen" "$out20b" '"error": null'
exists fixrunner-fixenginex-owner-disk-model && ok "Plattenmodell bleibt registriert" || bad "Plattenmodell bleibt registriert"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
