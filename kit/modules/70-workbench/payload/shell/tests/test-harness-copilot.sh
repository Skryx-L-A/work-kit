#!/usr/bin/env bash
# test-harness-copilot.sh — die Zusagen, die die GitHub Copilot CLI am 2026-08-08 bekommen hat.
#
# Gemessen wurde mit Copilot CLI 1.0.78 (npm i -g @github/copilot) auf eigenem tmux-Socket,
# mit Wegwerf-HOME und ollama/qwen3:1.7b ueber einen EIGENEN Modell-Anbieter (BYOK) — ohne
# GitHub-Abo und ohne Anmeldung. Geprueft wird hier der ausgelieferte Registry-Stand
# (shell/models.default.json) gegen AUFGEZEICHNETE Bildschirme und eine nachgebaute
# Sitzungsdatenbank — Fixtures, keine installierte CLI und kein laufendes Modell.
#
#   1  readyPattern trifft alle drei gemessenen Zustaende (leer, getippt, beschaeftigt).
#   2  ... und KEINEN der beiden Erststart-Dialoge. Das ist der Punkt, an dem agy gescheitert
#      ist: ein Muster, das einen Dialog trifft, laesst den Auftrag in einer Ja-Nein-Frage
#      verschwinden.
#   3  Die Absende-Pruefung von pi-worker sagt bei getipptem Text "haengt noch" und bei leerer
#      Box "abgeschickt".
#   4  Die Kontextauslastung kommt NICHT vom Bildschirm (contextPattern leer), sondern aus
#      ~/.copilot/session-store.db. Geprueft wird der ECHTE Leser aus shell/context-guard.
#   5  Die Rolle kommt ueber AGENTS.md im ARBEITSVERZEICHNIS.
#   6  resume.probe ist 'revive-only' — sonst erbt jeder neue Worker die zuletzt benutzte
#      Sitzung.
#   7  Der Vertrauensspeicher: der ECHTE Schreiber aus shell/wb-harness-run traegt den Pfad in
#      eine Datei mit Kommentarkopf ein (JSONC, so schreibt die CLI sie selbst), laesst den
#      Kopf stehen und traegt beim zweiten Lauf nichts doppelt ein.
#   8  Die Umgebung beantwortet den zweiten Erststart-Dialog vorher (COPILOT_SETUP_TERMINAL)
#      und bestellt den eigenen Anbieter, damit keine GitHub-Anmeldung noetig ist.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
REG="$REPO/models.default.json"
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-copilot-test.XXXXXX")" && pwd)"
export HOME="$TESTHOME"
export WB_NO_DISCOVER=1
BIN="$TESTHOME/.local/bin"; mkdir -p "$BIN" "$TESTHOME/.claude/workbench" "$TESTHOME/work"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT INT TERM

echo "== test-harness-copilot =="
echo "Geprueft: Registry-Stand aus $REG"

cp "$REPO/wb-state" "$BIN/wb-state"; chmod +x "$BIN/wb-state"
cp "$REG" "$TESTHOME/.claude/workbench/models.json"
# Kit: the registry ships the copilot adapter (kit-llm) but no copilot model; the suite adds one.
/usr/bin/python3 - "$TESTHOME/.claude/workbench/models.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["models"].append({"id": "copilot-qwen3.5-4b", "label": "Qwen3.5 4B via Copilot", "harness": "copilot",
                    "provider": "kit-llm", "modelRef": "qwen3.5-4b", "roles": ["worker"],
                    "enabled": True, "supportsEffort": False})
json.dump(d, open(sys.argv[1], "w"), indent=2)
PY
WBS="$BIN/wb-state"

feld() { /usr/bin/python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
h = next(x for x in d["harnesses"] if x["id"] == "copilot")
cur = h
for k in sys.argv[2].split("."):
    cur = (cur or {}).get(k) if isinstance(cur, dict) else None
print("" if cur is None else (json.dumps(cur, ensure_ascii=False) if not isinstance(cur, str) else cur))
' "$REG" "$1"; }

READY="$(feld readyPattern)"
[ -n "$READY" ] && ok "readyPattern ist gesetzt: $READY" || bad "readyPattern fehlt"

# ── Die aufgezeichneten Bildschirme ──────────────────────────────────────────────────
# Aufgenommen 2026-08-08 in einem 200x50-Pane. Die langen Rahmenbalken sind gekuerzt; das
# Zeichen am Zeilenanfang ist das, worauf es ankommt.
FIX="$TESTHOME/fix"; mkdir -p "$FIX"

cat >"$FIX/leer.txt" <<'EOF'
 ! Model "qwen3:1.7b" is not in the built-in catalog. Using defaults for: prompt tokens
 <arbeitsverzeichnis>
╻▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
┃
╹▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
 / commands · ? help · tab next tab                                            qwen3:1.7b
EOF

cat >"$FIX/getippt.txt" <<'EOF'
 <arbeitsverzeichnis>
╻▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
┃ wie lautet das Kennwort dieses Arbeitsverzeichnisses? antworte nur mit dem Wort.
╹▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
 @ files · # issues                                                            qwen3:1.7b
EOF

# Waehrend der Antwort ist die Box wieder LEER; die Fusszeile wechselt auf 'Working'.
cat >"$FIX/beschaeftigt.txt" <<'EOF'
 ▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
  ❯ wie lautet das Kennwort dieses Arbeitsverzeichnisses? antworte nur mit dem Wort.  21:52
 ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
 <arbeitsverzeichnis>
╻▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
┃
╹▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
 ● Working esc interrupt                                                       qwen3:1.7b
EOF

# Erststart-Dialog 1: die Vertrauensfrage. Sie faellt in JEDEM neuen Verzeichnis an.
cat >"$FIX/vertrauen.txt" <<'EOF'
╭────────────────────────────────────────────────────────────╮
│ Confirm folder trust                                       │
│ ────────────────────────────────────────────────────────── │
│ Do you trust the files in this folder?                     │
│                                                            │
│ ❯ 1. Yes                                                   │
│   2. Yes, and remember this folder for future sessions     │
│   3. No (Esc)                                              │
│ ↑/↓ to navigate · enter to select · esc to cancel          │
╰────────────────────────────────────────────────────────────╯
EOF

# Erststart-Dialog 2: die Terminal-Einrichtung. Sie will eine Tastenbelegung in die
# VS-Code-Konfiguration schreiben.
cat >"$FIX/terminal.txt" <<'EOF'
╭────────────────────────────────────────────────────────────╮
│ Set up terminal for multi-line input support               │
│ Detected terminal VS Code which supports multi-line input  │
│ Would you like to add this key binding to your terminal?   │
│ ❯ 1. Yes                                                   │
│   2. No (Esc)                                              │
╰────────────────────────────────────────────────────────────╯
EOF

printf '\n\n   \n\n' >"$FIX/leerer-bildschirm.txt"

# 1
for z in leer getippt beschaeftigt; do
  if grep -qE "$READY" "$FIX/$z.txt"; then
    ok "1: readyPattern trifft den Zustand '$z'"
  else
    bad "1: readyPattern '$READY' trifft den Zustand '$z' NICHT"
  fi
done

# 2
grep -qE "$READY" "$FIX/leerer-bildschirm.txt" \
  && bad "2: readyPattern trifft schon den leeren Startbildschirm" \
  || ok "2: readyPattern trifft den leeren Startbildschirm nicht"
grep -qE "$READY" "$FIX/vertrauen.txt" \
  && bad "2: readyPattern haelt die Vertrauensfrage fuer die Eingabezeile — der Auftrag landete in einer Ja-Nein-Frage (der Fehler, an dem agy gescheitert ist)" \
  || ok "2: readyPattern trifft die Vertrauensfrage nicht"
grep -qE "$READY" "$FIX/terminal.txt" \
  && bad "2: readyPattern haelt den Terminal-Dialog fuer die Eingabezeile" \
  || ok "2: readyPattern trifft den Terminal-Dialog nicht"

# 3
PROMPT="$(feld promptPattern)"
PIGN="$(feld promptIgnore)"
[ -n "$PROMPT" ] && ok "3: promptPattern ist gesetzt: $PROMPT" || bad "3: promptPattern fehlt"
inbox() { grep -E "$PROMPT" "$1" | tail -1; }
Z_GETIPPT="$(inbox "$FIX/getippt.txt")"
Z_LEER="$(inbox "$FIX/leer.txt")"
case "$Z_GETIPPT" in
  "┃ wie lautet"*) ok "3: die letzte Treffer-Zeile IST die Eingabezeile" ;;
  *) bad "3: letzte Treffer-Zeile ist '$Z_GETIPPT' statt der Eingabezeile" ;;
esac
printf '%s' "$Z_GETIPPT" | grep -qE "${PROMPT}[[:space:]]+[^[:space:]]" \
  && ok "3: getippter Text wird als 'haengt noch' erkannt" \
  || bad "3: getippter Text gilt faelschlich als abgeschickt — der Fehler, den ein Muster mit Leerzeichen am Ende macht"
printf '%s' "$Z_LEER" | grep -qE "${PROMPT}[[:space:]]+[^[:space:]]" \
  && bad "3: die leere Box gilt als haengend — jeder Spawn meldete einen Fehlschlag" \
  || ok "3: die leere Box gilt als abgeschickt"
[ -z "$PIGN" ] || [ "$PIGN" = "null" ] \
  && ok "3: promptIgnore ist leer (die leere Box zeigt keinen Platzhalter)" \
  || bad "3: promptIgnore ist '$PIGN'; gemessen wurde kein Platzhalter"

# 4 — die fuenfte Quelle der Kontextwache, gegen den echten Leser.
[ -z "$(feld contextPattern)" ] || [ "$(feld contextPattern)" = "null" ] \
  && ok "4: contextPattern ist leer — die CLI zeigt ihre Auslastung nicht in der Fusszeile" \
  || bad "4: contextPattern ist '$(feld contextPattern)', gemessen wurde aber keine Anzeige"
[ "$(feld session.format)" = "copilot-sqlite" ] \
  && ok "4: session.format ist 'copilot-sqlite'" \
  || bad "4: session.format ist '$(feld session.format)' — ohne sie ist ein copilot-Worker unbewacht"

# Der Leser liegt seit 2026-08-11 nicht mehr eingebettet in context-guard,
# sondern als eigenes Skript daneben (shell/wb-session-load) -- EIN Leser fuer
# die Wache UND das Worker-Modell der Oberflaeche, statt ihn ein zweites Mal in
# TypeScript nachzubauen. Kein Herausloesen mehr noetig, nur der echte Pfad.
LESER="$REPO/wb-session-load"
[ -x "$LESER" ] && ok "4: der Leser shell/wb-session-load ist vorhanden und ausfuehrbar" \
  || bad "4: shell/wb-session-load fehlt oder ist nicht ausfuehrbar"

# Eine nachgebaute Sitzungsdatenbank mit genau den Spalten, die gemessen wurden.
DB="$TESTHOME/session-store.db"
/usr/bin/python3 - "$DB" "$TESTHOME/work" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("create table sessions (id text primary key, cwd text, repository text, "
            "host_type text, branch text, summary text, created_at text, updated_at text)")
con.execute("create table assistant_usage_events (id integer primary key autoincrement, "
            "session_id text, turn_index integer, model text, input_tokens integer, "
            "output_tokens integer)")
con.execute("insert into sessions values ('s1', ?, null, null, null, null, "
            "'2026-08-08T19:52:47.519Z', '2026-08-08T19:52:58.805Z')", (sys.argv[2],))
con.execute("insert into assistant_usage_events (session_id, turn_index, model, input_tokens, "
            "output_tokens) values ('s1', 0, 'qwen3:1.7b', 13140, 121)")
con.commit(); con.close()
PY
SPEC="{\"via\":\"sessionFile\",\"format\":\"copilot-sqlite\",\"ort\":\"$DB\"}"
# 13140 + 121 = 13261 von 40960 sind 32 Prozent.
GELESEN="$(/usr/bin/python3 "$LESER" "$SPEC" "$TESTHOME/work" 40960 2>/dev/null)"
[ "$GELESEN" = "13261 32 40960" ] \
  && ok "4: der Leser nennt 32 % (13140+121 von 40960) fuer das eigene Arbeitsverzeichnis" \
  || bad "4: der Leser nennt '$GELESEN' statt '13261 32 40960'"
FREMD="$(/usr/bin/python3 "$LESER" "$SPEC" "$TESTHOME/fix" 40960 2>/dev/null)"
[ -z "$FREMD" ] \
  && ok "4: fuer ein FREMDES Arbeitsverzeichnis liefert der Leser nichts" \
  || bad "4: fuer ein fremdes Arbeitsverzeichnis kam '$FREMD' — das waere die Zahl eines anderen Panes"
OHNE="$(/usr/bin/python3 "$LESER" "$SPEC" "$TESTHOME/work" 0 2>/dev/null)"
[ -z "$OHNE" ] \
  && ok "4: ohne contextWindow liefert der Leser nichts, statt eine Prozentzahl zu erfinden" \
  || bad "4: ohne contextWindow kam '$OHNE'"

# 5
[ "$(feld systemPrompt.style)" = "file" ] \
  && ok "5: systemPrompt.style ist 'file'" || bad "5: systemPrompt.style ist '$(feld systemPrompt.style)'"
[ "$(feld systemPrompt.projectPath)" = "AGENTS.md" ] \
  && ok "5: projectPath 'AGENTS.md' — jeder Worker bekommt seine eigene Datei" \
  || bad "5: projectPath ist '$(feld systemPrompt.projectPath)' statt AGENTS.md"
[ -n "$(feld systemPrompt.worker)" ] \
  && ok "5: eine Rollendatei fuer 'worker' ist eingetragen" \
  || bad "5: keine Rollendatei fuer 'worker' — der Worker startet ohne Rollen-Prompt"

# 6
[ "$(feld resume.probe)" = "revive-only" ] \
  && ok "6: resume.probe ist 'revive-only'" \
  || bad "6: resume.probe ist '$(feld resume.probe)' — jeder neue Worker erbte die zuletzt benutzte Sitzung"
OUT="$("$WBS" models resolve copilot-qwen3.5-4b --role worker --dir "$TESTHOME/work" --name w1 2>/dev/null)"
CMD="$(printf '%s\n' "$OUT" | awk -F'\t' '$1=="cmd"{print $2}')"
case "$CMD" in
  *--continue*) bad "6: resolve haengt --continue an den ersten Spawn: $CMD" ;;
  *)            ok "6: der erste Spawn bekommt kein --continue" ;;
esac
case "$(feld resume.args)" in
  *--continue*) ok "6: resume.args traegt --continue fuer wb-revive" ;;
  *)            bad "6: resume.args ohne --continue — wiederbelebte Panes kommen leer zurueck" ;;
esac
case "$CMD" in
  *--allow-all*) ok "6: die Autonomie-Flags haengen an (--allow-all)" ;;
  *) bad "6: die Startzeile traegt kein --allow-all — der Worker bliebe an jeder Freigabe stehen: $CMD" ;;
esac

# 7 — der Vertrauensspeicher, gegen den ECHTEN Schreiber aus wb-harness-run.
[ "$(feld trustStore.style)" = "json-array" ] \
  && ok "7: trustStore.style ist 'json-array'" || bad "7: trustStore.style ist '$(feld trustStore.style)'"
[ "$(feld trustStore.key)" = "trustedFolders" ] \
  && ok "7: trustStore.key ist 'trustedFolders'" || bad "7: trustStore.key ist '$(feld trustStore.key)'"
[ "$(feld trustStore.jsonc)" = "true" ] \
  && ok "7: trustStore.jsonc ist gesetzt — die Datei der CLI beginnt mit zwei Kommentarzeilen" \
  || bad "7: trustStore.jsonc fehlt; json.load scheitert am Kommentarkopf und der Dialog kaeme trotzdem"

SCHREIBER="$TESTHOME/truststore.py"
/usr/bin/python3 - "$REPO/wb-harness-run" "$SCHREIBER" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
marke = '/usr/bin/python3 - "$HJSON2" "${DIR:-$PWD}" <<' + chr(39) + "PY" + chr(39)
i = src.index(marke)
j = src.index("\nPY\n", i)
open(sys.argv[2], "w", encoding="utf-8").write(src[src.index("\n", i) + 1:j])
PY
[ -s "$SCHREIBER" ] && ok "7: der Schreiber aus shell/wb-harness-run ist herausgeloest" \
  || bad "7: der Schreiber aus shell/wb-harness-run liess sich nicht herausloesen"

# Die Datei sieht aus wie die der CLI: zwei Kommentarzeilen, dann JSON.
ZIEL="$TESTHOME/copilot-config.json"
printf '%s\n' '// User settings belong in settings.json.' \
              '// This file is managed automatically.' \
              '{ "firstLaunchAt": "2026-07-23T21:57:55.514Z" }' > "$ZIEL"
HJSON="$(/usr/bin/python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
h = next(x for x in d["harnesses"] if x["id"] == "copilot")
h["trustStore"]["file"] = sys.argv[2]
print(json.dumps(h, ensure_ascii=False))
' "$REG" "$ZIEL")"
/usr/bin/python3 "$SCHREIBER" "$HJSON" "$TESTHOME/work" 2>/dev/null
head -2 "$ZIEL" | grep -q '^//' \
  && ok "7: der Kommentarkopf steht nach dem Schreiben noch da" \
  || bad "7: der Kommentarkopf ist weg — die CLI schreibt ihn zwar wieder hin, aber wir haben ihre Datei umgeschrieben"
NACH="$(/usr/bin/python3 -c '
import json, sys
z = [l for l in open(sys.argv[1]) if not l.lstrip().startswith("//")]
d = json.loads("".join(z))
print(len(d.get("trustedFolders") or []), d.get("firstLaunchAt") or "-")
' "$ZIEL")"
[ "$NACH" = "1 2026-07-23T21:57:55.514Z" ] \
  && ok "7: genau ein Pfad eingetragen, und der uebrige Inhalt steht unveraendert da" \
  || bad "7: nach dem Schreiben steht dort '$NACH' statt '1 2026-07-23T21:57:55.514Z'"
/usr/bin/python3 "$SCHREIBER" "$HJSON" "$TESTHOME/work" 2>/dev/null
ZWEI="$(/usr/bin/python3 -c '
import json, sys
z = [l for l in open(sys.argv[1]) if not l.lstrip().startswith("//")]
print(len(json.loads("".join(z)).get("trustedFolders") or []))
' "$ZIEL")"
[ "$ZWEI" = "1" ] \
  && ok "7: ein zweiter Start traegt denselben Pfad NICHT noch einmal ein" \
  || bad "7: nach dem zweiten Start stehen $ZWEI Pfade in der Liste"

# 8 — die Umgebung: der zweite Dialog wird vorher beantwortet, und der eigene Anbieter
#     macht die GitHub-Anmeldung entbehrlich.
env_wert() { printf '%s\n' "$OUT" | awk -F'\t' -v k="$1" '$1=="env" && $2==k{print $3}'; }
[ "$(env_wert COPILOT_SETUP_TERMINAL)" = "false" ] \
  && ok "8: COPILOT_SETUP_TERMINAL=false — der Terminal-Dialog des Erststarts faellt aus" \
  || bad "8: COPILOT_SETUP_TERMINAL ist '$(env_wert COPILOT_SETUP_TERMINAL)'; der Erststart bliebe in einer Ja-Nein-Frage stehen"
case "$(env_wert COPILOT_PROVIDER_BASE_URL)" in
  */v1) ok "8: COPILOT_PROVIDER_BASE_URL endet auf /v1 ($(env_wert COPILOT_PROVIDER_BASE_URL))" ;;
  *) bad "8: COPILOT_PROVIDER_BASE_URL ist '$(env_wert COPILOT_PROVIDER_BASE_URL)' — ohne /v1 findet die CLI den OpenAI-kompatiblen Endpunkt nicht" ;;
esac
[ "$(env_wert COPILOT_PROVIDER_TYPE)" = "openai" ] \
  && ok "8: COPILOT_PROVIDER_TYPE ist 'openai' (der Typ fuer Ollama laut eigener Hilfe)" \
  || bad "8: COPILOT_PROVIDER_TYPE ist '$(env_wert COPILOT_PROVIDER_TYPE)'"
[ "$(env_wert COPILOT_MODEL)" = "qwen3.5-4b" ] \
  && ok "8: COPILOT_MODEL traegt die bestellte Modellreferenz" \
  || bad "8: COPILOT_MODEL ist '$(env_wert COPILOT_MODEL)' statt der Modellreferenz"
[ "$(env_wert COPILOT_OFFLINE)" = "true" ] \
  && ok "8: COPILOT_OFFLINE=true — kein Netzzugriff, keine GitHub-Anmeldung, kein Abo noetig" \
  || bad "8: COPILOT_OFFLINE ist '$(env_wert COPILOT_OFFLINE)'"

echo
echo "== $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
