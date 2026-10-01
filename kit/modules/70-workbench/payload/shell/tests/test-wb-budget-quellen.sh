#!/bin/bash
# test-wb-budget-quellen.sh — die sechs NEUEN Quellen von `wb-budget --json`.
#
# WARUM (Auftrag 2026-08-11): wb-budget las bis heute ausschliesslich
# ~/.claude/projects/**/*.jsonl und war damit strukturell nur Claude. `--json` liest daneben
# codex, pi, opencode, copilot, copilot-cloud und openhands. Was diese Suite haelt, sind genau
# die Stellen, an denen eine solche Erweiterung leise falsch werden kann:
#
#   1. Jede der sieben Quellen wird ueberhaupt gelesen -- eine, die still nichts liefert, sieht
#      im fertigen Bericht aus wie eine, die nichts zu liefern hatte.
#   2. copilot und copilot-cloud teilen sich EINE Datenbank und sind nur am Modellfeld zu
#      unterscheiden. Werden sie zusammengeworfen, steht der Verbrauch eines lokalen Modells
#      unter dem Cloud-Abo.
#   3. codex fuehrt die zwischengespeicherten Tokens INNERHALB von input_tokens. Wer sie nicht
#      abzieht, zaehlt dieselbe Menge zweimal.
#   4. Token je Sekunde ist nicht ueberall dasselbe: nur copilot traegt eine echte
#      Generierungsrate, alles andere ist Wanduhr. Verliert die Ausgabe diese Unterscheidung,
#      luegt jede Anzeige, die sie zeichnet.
#   5. Ein Abo-Betrag ist ein API-AEQUIVALENT und wurde nie abgebucht. Fehlt diese Kennzeichnung,
#      steht eine erfundene Rechnung auf dem Bildschirm.
#   6. Was nicht messbar ist, muss als Luecke MIT GRUND dastehen, nicht als Schweigen.
#   7. Die Filter (--harness/--modell/--sitzung) und der Fensterschnitt greifen wirklich.
#
# ISOLATION: eigenes HOME in einem mktemp-Verzeichnis. Alle Fixture-Dateien werden hier frisch
# angelegt; keine echte Sitzung, keine echte Datenbank, kein Netz. wb-kontingent wird per
# --ohne-kontingent abgeschaltet, damit die Suite nicht am Kontingentstand der Maschine haengt.
#
# Run: shell/tests/test-wb-budget-quellen.sh
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
TOOL="$REPO/wb-budget"
echo "Geprueft: $TOOL --json"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
ueberspringen() { echo "UEBERSPRUNGEN: $1"; exit 77; }

command -v /usr/bin/sqlite3 >/dev/null 2>&1 || ueberspringen "/usr/bin/sqlite3 fehlt"

TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-budget-quellen.XXXXXX")" && pwd)"
trap 'rm -rf "$TESTHOME"' EXIT
H="$TESTHOME/home"

# Alle Fixture-Zeiten liegen im selben festen Fenster; gemessen wird immer mit --von/--bis,
# damit die Suite nicht davon abhaengt, wann sie laeuft.
VON="2026-03-01T00:00:00Z"
BIS="2026-03-02T00:00:00Z"
# Ein Punkt AUSSERHALB des Fensters, fuer den Fensterschnitt (Fall 7).
DRAUSSEN="2026-02-01T12:00:00Z"

# --- claude ---------------------------------------------------------------------------------
mkdir -p "$H/.claude/projects/-Users-<user>--pi-workers-worktrees-probe"
cat > "$H/.claude/projects/-Users-<user>--pi-workers-worktrees-probe/sitzung-a.jsonl" <<EOF
{"type":"assistant","timestamp":"2026-03-01T10:00:00Z","message":{"model":"claude-opus-5","usage":{"input_tokens":1000,"output_tokens":200,"cache_creation_input_tokens":50,"cache_read_input_tokens":9000}}}
{"type":"assistant","timestamp":"2026-03-01T10:00:10Z","message":{"model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":11000}}}
{"type":"assistant","timestamp":"$DRAUSSEN","message":{"model":"claude-opus-5","usage":{"input_tokens":777000,"output_tokens":777000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
EOF

# --- codex ----------------------------------------------------------------------------------
# input_tokens=1200 ENTHAELT cached_input_tokens=900 -> erwartet: input 300, cache_read 900.
mkdir -p "$H/.codex/sessions/2026/03/01"
cat > "$H/.codex/sessions/2026/03/01/rollout-2026-03-01T09-00-00-abc.jsonl" <<EOF
{"timestamp":"2026-03-01T09:00:00Z","type":"session_meta","payload":{"session_id":"codex-1","cwd":"/tmp/codexprobe"}}
{"timestamp":"2026-03-01T09:00:01Z","type":"turn_context","payload":{"model":"gpt-5.6-terra"}}
{"timestamp":"2026-03-01T09:00:05Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1200,"cached_input_tokens":900,"cache_write_input_tokens":40,"output_tokens":60,"reasoning_output_tokens":10}}}}
{"timestamp":"2026-03-01T09:00:09Z","type":"event_msg","payload":{"type":"token_count","info":null}}
EOF

# --- pi -------------------------------------------------------------------------------------
mkdir -p "$H/.pi-workers/sessions/probeworker"
cat > "$H/.pi-workers/sessions/probeworker/2026-03-01T08-00-00-000Z_pi-1.jsonl" <<EOF
{"type":"message","timestamp":"2026-03-01T08:00:00Z","message":{"role":"assistant","model":"lmalpha:9b","provider":"ollama","usage":{"input":500,"output":80,"cacheRead":0,"cacheWrite":0,"reasoning":0,"cost":{"total":0}}}}
{"type":"message","timestamp":"2026-03-01T08:00:04Z","message":{"role":"assistant","model":"lmalpha:9b","provider":"ollama","usage":{"input":600,"output":120,"cacheRead":10,"cacheWrite":0,"reasoning":0,"cost":{"total":0}}}}
EOF

# --- opencode -------------------------------------------------------------------------------
mkdir -p "$H/.local/share/opencode"
OC_CREATED=$(/usr/bin/python3 -c "
from datetime import datetime, timezone
print(int(datetime(2026,3,1,7,0,0,tzinfo=timezone.utc).timestamp()*1000))")
/usr/bin/sqlite3 "$H/.local/share/opencode/opencode.db" <<EOF
CREATE TABLE message (id text PRIMARY KEY, session_id text NOT NULL, time_created integer NOT NULL, time_updated integer NOT NULL, data text NOT NULL);
INSERT INTO message VALUES ('m1','oc-1',$OC_CREATED,$OC_CREATED,
 '{"role":"assistant","cost":0.25,"tokens":{"total":700,"input":600,"output":100,"reasoning":0,"cache":{"write":5,"read":20}},"modelID":"claude-3-5-sonnet","providerID":"anthropic","path":{"cwd":"/tmp/ocprobe"},"time":{"created":$OC_CREATED,"completed":$((OC_CREATED+2000))}}');
EOF

# --- copilot UND copilot-cloud, EINE Datenbank ----------------------------------------------
# gpt-5-mini ist in der Registry ein copilot-cloud-Modell, 'lmalpha:9b' ein lokales copilot-Modell.
mkdir -p "$H/.copilot"
/usr/bin/sqlite3 "$H/.copilot/session-store.db" <<'EOF'
CREATE TABLE assistant_usage_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL, turn_index INTEGER,
  agent_id TEXT, parent_tool_call_id TEXT, model TEXT NOT NULL, input_tokens INTEGER,
  output_tokens INTEGER, cache_read_tokens INTEGER, cache_write_tokens INTEGER,
  reasoning_tokens INTEGER, total_nano_aiu INTEGER, request_multiplier REAL, duration_ms INTEGER,
  time_to_first_token_ms REAL, inter_token_latency_ms REAL, initiator TEXT, api_endpoint TEXT,
  reasoning_effort TEXT, finish_reason TEXT, content_filter_triggered INTEGER,
  token_details_json TEXT, created_at TEXT);
-- 201 Ausgabe-Tokens bei 10 ms Abstand -> 200 * 0,01 s = 2,0 s -> 100,5 Token/s.
INSERT INTO assistant_usage_events (session_id, model, input_tokens, output_tokens,
  cache_read_tokens, cache_write_tokens, reasoning_tokens, total_nano_aiu, duration_ms,
  time_to_first_token_ms, inter_token_latency_ms, created_at)
 VALUES ('cop-1','gpt-5-mini',1000,201,300,0,0,2000000000,4000,1500.0,10.0,'2026-03-01T06:00:00Z');
INSERT INTO assistant_usage_events (session_id, model, input_tokens, output_tokens,
  cache_read_tokens, cache_write_tokens, reasoning_tokens, total_nano_aiu, duration_ms,
  time_to_first_token_ms, inter_token_latency_ms, created_at)
 VALUES ('cop-2','lmalpha:9b',400,50,0,0,0,0,900,300.0,NULL,'2026-03-01T06:05:00Z');
EOF

# --- openhands ------------------------------------------------------------------------------
mkdir -p "$H/.openhands/conversations/oh-1/events"
cat > "$H/.openhands/conversations/oh-1/base_state.json" <<'EOF'
{"id":"oh-1","workspace":{"working_dir":"/tmp/ohprobe"},
 "stats":{"usage_to_metrics":{"agent":{"model_name":"openai/lmalpha:9b","accumulated_cost":0.0,
  "response_latencies":[{"model":"openai/lmalpha:9b","latency":4.0,"response_id":"chatcmpl-1"}],
  "token_usages":[{"model":"openai/lmalpha:9b","prompt_tokens":900,"completion_tokens":40,
   "cache_read_tokens":0,"cache_write_tokens":0,"reasoning_tokens":0,"response_id":"chatcmpl-1"}]}}}}
EOF
cat > "$H/.openhands/conversations/oh-1/events/event-00002-x.json" <<'EOF'
{"id":"e2","timestamp":"2026-03-01T05:00:00","source":"agent","kind":"MessageEvent","llm_response_id":"chatcmpl-1"}
EOF

# =============================================================================================
lauf() { HOME="$H" "$TOOL" --json --von "$VON" --bis "$BIS" --ohne-kontingent "$@"; }

AUS="$(lauf 2>"$TESTHOME/err")"
if [ -z "$AUS" ]; then
  bad "wb-budget --json lieferte nichts" "$(head -c 400 "$TESTHOME/err")"
  echo; echo "  bestanden: $PASS, fehlgeschlagen: $FAIL"; exit 1
fi
[ -s "$TESTHOME/err" ] && printf '  (stderr) %s\n' "$(head -c 300 "$TESTHOME/err")"

# Ein kleiner Leser statt eines jq-Ausdrucks je Zusage: das JSON reist als Umgebungsvariable,
# nie als Quelltext in einen weiteren Aufruf (derselbe Grund wie in test-app-ampel-budget.sh).
frage() { WB_JSON="$AUS" /usr/bin/python3 "$TESTHOME/frage.py" "$@"; }
cat > "$TESTHOME/frage.py" <<'PY'
import json, os, sys
d = json.loads(os.environ["WB_JSON"])
was = sys.argv[1]
if was == "quelle":                       # quelle <harness> <feld>
    for q in d["quellen"]:
        if q["harness"] == sys.argv[2]:
            print(q[sys.argv[3]]); break
    else:
        print("QUELLE-FEHLT")
elif was == "harness":                    # harness <id> <feld>
    for z in d["je_harness"]:
        if z["harness"] == sys.argv[2]:
            print(z[sys.argv[3]]); break
    else:
        print("0")
elif was == "modell":                     # modell <harness> <modell> <pfad.mit.punkten>
    for z in d["je_modell"]:
        if z["harness"] == sys.argv[2] and z["modell"] == sys.argv[3]:
            w = z
            for t in sys.argv[4].split("."):
                w = w[t]
            print(w); break
    else:
        print("MODELL-FEHLT")
elif was == "luecke":                     # luecke <harness>
    for l in d["luecken"]:
        if l["harness"] == sys.argv[2]:
            print(l["grund"]); break
    else:
        print("KEINE-LUECKE")
elif was == "sitzung":                    # sitzung <harness> <id> <feld>
    for z in d["je_sitzung"]:
        if z["harness"] == sys.argv[2] and z["sitzung"] == sys.argv[3]:
            print(z[sys.argv[4]]); break
    else:
        print("SITZUNG-FEHLT")
elif was == "harnesses":
    print(",".join(sorted(z["harness"] for z in d["je_harness"])))
elif was == "modelle":
    print(",".join(sorted(z["modell"] for z in d["je_modell"])))
else:
    w = d
    for t in was.split("."):
        w = w[t]
    print(w)
PY

# --- 1. Jede Quelle wird gelesen -------------------------------------------------------------
for h in claude codex pi opencode copilot copilot-cloud openhands; do
  Z="$(frage quelle "$h" zustand)"
  [ "$Z" = "gelesen" ] && ok "Quelle $h gelesen" || bad "Quelle $h: zustand=$Z" "$(frage quelle "$h" hinweis)"
done

# --- 2. copilot und copilot-cloud aus DERSELBEN Datenbank, getrennt --------------------------
[ "$(frage harness copilot-cloud output)" = "201" ] \
  && ok "copilot-cloud bekommt das Cloud-Modell (gpt-5-mini)" \
  || bad "copilot-cloud output=$(frage harness copilot-cloud output), erwartet 201"
[ "$(frage harness copilot output)" = "50" ] \
  && ok "copilot bekommt das lokale Modell (lmalpha:9b) -- dieselbe Datenbank, anderer Harness" \
  || bad "copilot output=$(frage harness copilot output), erwartet 50"

# --- 3. codex: cached_input_tokens steckt IN input_tokens ------------------------------------
[ "$(frage modell codex gpt-5.6-terra input)" = "300" ] \
  && ok "codex: input 1200 minus 900 zwischengespeicherte = 300, nicht doppelt gezaehlt" \
  || bad "codex input=$(frage modell codex gpt-5.6-terra input), erwartet 300"
[ "$(frage modell codex gpt-5.6-terra cache_read)" = "900" ] \
  && ok "codex: die 900 stehen als Cache-Lesen da, nicht als Eingabe" \
  || bad "codex cache_read=$(frage modell codex gpt-5.6-terra cache_read), erwartet 900"
[ "$(frage modell codex gpt-5.6-terra reasoning)" = "10" ] \
  && ok "codex: reasoning_output_tokens uebernommen" \
  || bad "codex reasoning=$(frage modell codex gpt-5.6-terra reasoning)"

# --- 4. Token je Sekunde: gemessen gegen genaehert --------------------------------------------
[ "$(frage modell copilot-cloud gpt-5-mini tempo.art)" = "gemessen" ] \
  && ok "copilot-cloud: Rate als 'gemessen' ausgewiesen (inter_token_latency_ms)" \
  || bad "copilot-cloud tempo.art=$(frage modell copilot-cloud gpt-5-mini tempo.art)"
[ "$(frage modell copilot-cloud gpt-5-mini tempo.wert)" = "100.5" ] \
  && ok "copilot-cloud: 201 Tokens bei 10 ms Abstand = 100,5 Token/s" \
  || bad "copilot-cloud tempo.wert=$(frage modell copilot-cloud gpt-5-mini tempo.wert), erwartet 100.5"
[ "$(frage modell claude claude-opus-5 tempo.art)" = "naeherung" ] \
  && ok "claude: Rate ausdruecklich als Naeherung gekennzeichnet" \
  || bad "claude tempo.art=$(frage modell claude claude-opus-5 tempo.art)"
[ "$(frage modell pi lmalpha:9b tempo.art)" = "naeherung" ] \
  && ok "pi: Rate ausdruecklich als Naeherung gekennzeichnet" \
  || bad "pi tempo.art=$(frage modell pi lmalpha:9b tempo.art)"
[ "$(frage modell openhands openai/lmalpha:9b tempo.art)" = "naeherung" ] \
  && ok "openhands: Rate ausdruecklich als Naeherung gekennzeichnet" \
  || bad "openhands tempo.art=$(frage modell openhands openai/lmalpha:9b tempo.art)"
[ "$(frage modell copilot lmalpha:9b tempo.art)" = "unbekannt" ] \
  && ok "ohne inter_token_latency_ms bleibt die Rate 'unbekannt' statt geraten" \
  || bad "copilot tempo.art=$(frage modell copilot lmalpha:9b tempo.art)"

# --- 5. Kosten: zwei Groessen, nie eine Zahl --------------------------------------------------
[ "$(frage modell claude claude-opus-5 preis.art)" = "abo-aequivalent" ] \
  && ok "claude: der Dollarbetrag ist ein API-Aequivalent" \
  || bad "claude preis.art=$(frage modell claude claude-opus-5 preis.art)"
[ "$(frage modell claude claude-opus-5 preis.nie_abgebucht)" = "True" ] \
  && ok "claude: 'nie abgebucht' steht am Betrag selbst, nicht in einer Fussnote" \
  || bad "claude preis.nie_abgebucht=$(frage modell claude claude-opus-5 preis.nie_abgebucht)"
[ "$(frage modell opencode claude-3-5-sonnet preis.art)" = "harness-angabe" ] \
  && ok "opencode: der vom Harness selbst gerechnete Betrag gilt und ist als solcher benannt" \
  || bad "opencode preis.art=$(frage modell opencode claude-3-5-sonnet preis.art)"
[ "$(frage modell opencode claude-3-5-sonnet preis.usd)" = "0.25" ] \
  && ok "opencode: der Betrag stimmt (0,25 USD aus der Datenbank)" \
  || bad "opencode preis.usd=$(frage modell opencode claude-3-5-sonnet preis.usd)"
AIU="$(frage modell copilot-cloud gpt-5-mini aiu)"
[ "$AIU" = "2.0" ] \
  && ok "copilot-cloud: total_nano_aiu wird als AIC ausgewiesen, nicht in Dollar umgerechnet" \
  || bad "copilot-cloud aiu=$AIU, erwartet 2.0"

# --- 6. Luecken: mit Grund, nicht als Schweigen ----------------------------------------------
for h in aider; do  # Kit: the other harnesses of this list are not in the kit registry
  G="$(frage luecke "$h")"
  case "$G" in
    KEINE-LUECKE|"") bad "Luecke $h fehlt in der Ausgabe" ;;
    *) : ;;
  esac
done
# Kit: forge (and its own reason) is not in the kit registry; aider above is the shipped gap.
[ "$(frage luecke aider)" != "KEINE-LUECKE" ] \
  && ok "der nicht messbare ausgelieferte Harness (aider) steht mit Grund in 'luecken'" \
  || bad "luecken unvollstaendig"

# --- 7. Fensterschnitt und Filter -------------------------------------------------------------
[ "$(frage modell claude claude-opus-5 output)" = "300" ] \
  && ok "Fensterschnitt: die Nachricht vom Februar zaehlt nicht mit" \
  || bad "claude output=$(frage modell claude claude-opus-5 output), erwartet 300 (777000 waeren die Nachricht ausserhalb)"

AUS="$(lauf --harness pi 2>/dev/null)"
[ "$(frage harnesses)" = "pi" ] \
  && ok "--harness pi liefert nur pi" || bad "--harness pi -> $(frage harnesses)"

AUS="$(lauf --modell lmalpha:9b 2>/dev/null)"
[ "$(frage harnesses)" = "copilot,pi" ] \
  && ok "--modell greift ueber Harness-Grenzen hinweg (copilot und pi fahren dasselbe Modell)" \
  || bad "--modell lmalpha:9b -> $(frage harnesses)"

AUS="$(lauf --sitzung codex-1 2>/dev/null)"
[ "$(frage harnesses)" = "codex" ] && ok "--sitzung waehlt genau eine Sitzung" \
  || bad "--sitzung codex-1 -> $(frage harnesses)"

AUS="$(lauf --harness pi --modell nichtdanebengibtsnicht 2>/dev/null)"
[ "$(frage gesamt.nachrichten)" = "0" ] \
  && ok "zwei Filter zusammen schneiden sich, statt sich zu addieren" \
  || bad "kombinierter Filter -> $(frage gesamt.nachrichten) Nachrichten"

# --- 8. Sitzung und Worker --------------------------------------------------------------------
AUS="$(lauf 2>/dev/null)"
[ "$(frage sitzung claude sitzung-a worker)" = "probe" ] \
  && ok "claude: der Workername kommt aus dem Arbeitsbaum-Pfad" \
  || bad "worker=$(frage sitzung claude sitzung-a worker), erwartet probe"
[ "$(frage sitzung pi pi-1 worker)" = "probeworker" ] \
  && ok "pi: der Ordnername IST der Workername" \
  || bad "worker=$(frage sitzung pi pi-1 worker)"
[ "$(frage sitzung openhands oh-1 worker)" = "ohprobe" ] \
  && ok "openhands: Worker aus dem Arbeitsverzeichnis der Unterhaltung" \
  || bad "worker=$(frage sitzung openhands oh-1 worker)"

# --- 9. Der alte Bericht bleibt, wie er war ---------------------------------------------------
# Ein Umbau, der die Standardausgabe mitnimmt, faellt sonst erst dem Menschen auf.
ALT="$(HOME="$H" "$TOOL" 2>/dev/null)"
case "$ALT" in
  *"== letzte 5 Stunden =="*) ok "der Standardbericht laeuft unveraendert weiter" ;;
  *) bad "Standardbericht veraendert" "$(printf '%s' "$ALT" | head -c 200)" ;;
esac

echo
echo "  bestanden: $PASS, fehlgeschlagen: $FAIL"
[ "$FAIL" -eq 0 ]
