#!/usr/bin/env bash
# test-harness-copilot-cloud.sh — die Zusagen des ZWEITEN Copilot-Eintrags (Cloud/Abo).
#
# Gemessen am 2026-08-10 mit derselben Binary wie 'copilot' (GitHub Copilot CLI 1.0.78),
# aber ohne COPILOT_PROVIDER_*/COPILOT_OFFLINE, also gegen die echte GitHub-Anmeldung
# (Konto <your-github-user>, 'copilot login', Token im macOS-Schluesselbund). env gehoert dem
# Harness, nicht dem Modell (siehe qwen/kimi) — deshalb der zweite Eintrag statt einer
# Umgebungsvariable am bestehenden.
#
# ZENTRALER BEFUND, den dieser Test vor allem absichert: das Konto haengt am KOSTENLOSEN
# Copilot-Plan. Der interaktive Modellwaehler ('/model', kostenlos gemessen — reine
# Menuenavigation, nie abgeschickt) zeigte 26 Eintraege, aber nur 'Auto' ist nutzbar; jeder
# der 25 benannten Modelle (gpt-5.6-sol, claude-opus-5, ...) wurde mit 'Your Copilot Free
# plan doesn't include this model' abgelehnt. Die Registry traegt deshalb GENAU EIN Modell
# fuer diesen Harness (copilot-cloud-auto, modelRef 'auto') — Punkt 5 unten ist eine
# Regression dagegen, dass spaeter versehentlich ein plan-gesperrter Name eingetragen wird.
#
#   1  readyPattern/promptPattern treffen dieselben drei Zustaende wie beim lokalen Eintrag
#      (aufgezeichnet 2026-08-10, eigener tmux-Socket, echtes HOME, Wegwerf-Arbeitsverzeichnis).
#   2  ... und keinen der beiden Erststart-Dialoge (Vertrauensfrage heute erneut ausgeloest).
#   3  env traegt KEINE COPILOT_PROVIDER_*-Variable und KEIN COPILOT_OFFLINE — sonst waere
#      es der lokale Eintrag mit anderem Namen.
#   4  session/contextPattern: dieselbe Datenbank wie lokal (copilot-sqlite), aber das
#      Modell copilot-cloud-auto traegt bewusst KEIN contextWindow — 'auto' wechselt das
#      tatsaechlich antwortende Modell je Zug, ein fester Nenner waere geraten.
#   5  Fuer harness=copilot-cloud steht genau EIN Modell in der Registry, modelRef 'auto'.
#   6  provider 'github-copilot': kein apiKeyEnv, kein keychainService — die CLI verwaltet
#      den Login selbst, wie bei 'chatgpt'.
#   7  resume.probe 'revive-only', autonomy '--allow-all', trustStore-Mechanik wie lokal.
#   8  Der bestehende Eintrag 'copilot' steht unveraendert daneben (Ollama-Variablen intakt).
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
REG="$REPO/models.default.json"
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-copilot-cloud-test.XXXXXX")" && pwd)"
export HOME="$TESTHOME"
export WB_NO_DISCOVER=1
BIN="$TESTHOME/.local/bin"; mkdir -p "$BIN" "$TESTHOME/.claude/workbench" "$TESTHOME/work"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT INT TERM

echo "== test-harness-copilot-cloud =="
echo "Geprueft: Registry-Stand aus $REG"

cp "$REPO/wb-state" "$BIN/wb-state"; chmod +x "$BIN/wb-state"
cp "$REG" "$TESTHOME/.claude/workbench/models.json"
WBS="$BIN/wb-state"

feld() { /usr/bin/python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
h = next(x for x in d["harnesses"] if x["id"] == "copilot-cloud")
cur = h
for k in sys.argv[2].split("."):
    cur = (cur or {}).get(k) if isinstance(cur, dict) else None
print("" if cur is None else (json.dumps(cur, ensure_ascii=False) if not isinstance(cur, str) else cur))
' "$REG" "$1"; }

READY="$(feld readyPattern)"
[ -n "$READY" ] && ok "readyPattern ist gesetzt: $READY" || bad "readyPattern fehlt"

# ── Die aufgezeichneten Bildschirme ──────────────────────────────────────────────────
# Aufgenommen 2026-08-10, eigener tmux-Socket (wbcopilotcloud-*), echtes HOME (Anmeldung
# liegt dort), Wegwerf-Arbeitsverzeichnis. Nie abgeschickt — kein Cloud-Zug dabei (belegt
# im Ergebnisbericht ueber ~/.copilot/session-store.db, vorher/nachher unveraendert).
FIX="$TESTHOME/fix"; mkdir -p "$FIX"

cat >"$FIX/leer.txt" <<'EOF'
  Session   Issues   Pull requests   Gists                                    Session: 0 AIC used
╻▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
┃
╹▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
 / commands · ? help · tab next tab                                                          Auto
EOF

cat >"$FIX/getippt.txt" <<'EOF'
╻▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄
┃ schreibe das Wort BEREIT und sonst nichts
╹▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
 @ files · # issues                                                                          Auto
EOF

# Erststart-Dialog: dieselbe Vertrauensfrage wie beim lokalen Eintrag, heute erneut mit
# einem frischen Wegwerf-Arbeitsverzeichnis ausgeloest.
cat >"$FIX/vertrauen.txt" <<'EOF'
╭──────────────────────────────────────────────────────────────╮
│ Confirm folder trust                                          │
│ ─────────────────────────────────────────────────────────────│
│ Do you trust the files in this folder?                        │
│                                                                │
│ ❯ 1. Yes                                                       │
│   2. Yes, and remember this folder for future sessions         │
│   3. No (Esc)                                                  │
│ ↑/↓ to navigate · enter to select · esc to cancel               │
╰──────────────────────────────────────────────────────────────╯
EOF

printf '\n\n   \n\n' >"$FIX/leerer-bildschirm.txt"

# 1
for z in leer getippt; do
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
  && bad "2: readyPattern haelt die Vertrauensfrage fuer die Eingabezeile" \
  || ok "2: readyPattern trifft die Vertrauensfrage nicht"

# 3 — der ganze Grund fuer den zweiten Eintrag: env OHNE Ollama-Anbieter und OHNE Offline.
ENVJSON="$(feld env)"
echo "$ENVJSON" | grep -q "COPILOT_PROVIDER_BASE_URL" \
  && bad "3: env traegt noch COPILOT_PROVIDER_BASE_URL — das waere der lokale Eintrag" \
  || ok "3: env traegt kein COPILOT_PROVIDER_BASE_URL"
echo "$ENVJSON" | grep -q "COPILOT_PROVIDER_TYPE" \
  && bad "3: env traegt noch COPILOT_PROVIDER_TYPE" \
  || ok "3: env traegt kein COPILOT_PROVIDER_TYPE"
echo "$ENVJSON" | grep -q "COPILOT_PROVIDER_API_KEY" \
  && bad "3: env traegt noch COPILOT_PROVIDER_API_KEY" \
  || ok "3: env traegt kein COPILOT_PROVIDER_API_KEY"
echo "$ENVJSON" | grep -q "COPILOT_OFFLINE" \
  && bad "3: env traegt noch COPILOT_OFFLINE — die Cloud-Spur waere abgeschnitten" \
  || ok "3: env traegt kein COPILOT_OFFLINE"
echo "$ENVJSON" | grep -q "COPILOT_MODEL" \
  && ok "3: env traegt COPILOT_MODEL (Modellwahl bleibt moeglich)" \
  || bad "3: env traegt kein COPILOT_MODEL"

# 4 — session wie lokal, aber KEIN contextWindow am Modell (siehe Kopf).
[ -z "$(feld contextPattern)" ] || [ "$(feld contextPattern)" = "null" ] \
  && ok "4: contextPattern ist leer, wie beim lokalen Eintrag" \
  || bad "4: contextPattern ist '$(feld contextPattern)', gemessen wurde aber keine Anzeige"
[ "$(feld session.format)" = "copilot-sqlite" ] \
  && ok "4: session.format ist 'copilot-sqlite'" \
  || bad "4: session.format ist '$(feld session.format)'"
CW="$(/usr/bin/python3 -c '
import json
d = json.load(open("'"$REG"'"))
m = next(x for x in d["models"] if x["id"] == "copilot-cloud-auto")
print(m.get("contextWindow", "FEHLT"))
')"
[ "$CW" = "FEHLT" ] \
  && ok "4: copilot-cloud-auto traegt bewusst KEIN contextWindow (auto wechselt das Modell je Zug)" \
  || bad "4: copilot-cloud-auto traegt contextWindow=$CW — das waere ein geratener Nenner fuer ein wechselndes Modell"
# 4b — der Nenner wurde am 2026-08-10 an drei Stellen gesucht und an keiner gefunden. Das
#      steht im contextProbe, und es steht dort nicht als Schmuck: ohne diese Notiz sucht
#      der Naechste dieselben drei Stellen noch einmal ab. Geprueft werden die Stichworte,
#      nicht der Wortlaut.
# Kit: measurement records of the live registry (contextProbe) name the build machine's data
# and do not ship (port/kit_registry.py); the finding is kept in docs/workbench-port.md.
[ -z "$(feld contextProbe)" ] \
  && ok "4: contextPattern stays empty; the upstream measurement record is not shipped" \
  || bad "4: contextProbe ships: $(feld contextProbe)"

# 5 — Regression gegen die Kernauflage: nur 'auto' ist auf dem FREE-Plan nutzbar.
MODELLE="$(/usr/bin/python3 -c '
import json
d = json.load(open("'"$REG"'"))
print(",".join(sorted(x["id"] for x in d["models"] if x.get("harness") == "copilot-cloud")))
')"
[ "$MODELLE" = "copilot-cloud-auto" ] \
  && ok "5: harness copilot-cloud traegt genau EIN Modell (copilot-cloud-auto)" \
  || bad "5: harness copilot-cloud traegt '$MODELLE' statt nur copilot-cloud-auto — wurde ein plan-gesperrter Name eingetragen?"
REF="$(/usr/bin/python3 -c '
import json
d = json.load(open("'"$REG"'"))
m = next(x for x in d["models"] if x["id"] == "copilot-cloud-auto")
print(m["modelRef"])
')"
[ "$REF" = "auto" ] \
  && ok "5: modelRef ist 'auto' (der einzige laut --help dokumentierte, plan-unabhaengige Wert)" \
  || bad "5: modelRef ist '$REF' statt 'auto'"

# 6 — provider github-copilot: kein Key, kein Keychain-Dienst ueber unsere Injektion.
PROV="$(/usr/bin/python3 -c '
import json
d = json.load(open("'"$REG"'"))
p = next(x for x in d["providers"] if x["id"] == "github-copilot")
print(p.get("apiKeyEnv"), p.get("keychainService"))
')"
[ "$PROV" = "None None" ] \
  && ok "6: provider github-copilot hat weder apiKeyEnv noch keychainService — die CLI verwaltet den Login selbst" \
  || bad "6: provider github-copilot traegt '$PROV' — wb-state wuerde versuchen, einen Schluessel zu injizieren"

# 7 — resume/autonomy/trustStore wie beim lokalen Eintrag (dieselbe Binary, dieselbe Datei).
[ "$(feld resume.probe)" = "revive-only" ] \
  && ok "7: resume.probe ist 'revive-only'" \
  || bad "7: resume.probe ist '$(feld resume.probe)'"
# copilot-cloud-auto traegt bewusst 'machines: [mac]' (Registry) -- der Login
# haengt am macOS-Schluesselbund (siehe Kopfkommentar dieser Datei), nicht an
# einer Datei, die sich einfach mitkopieren liesse. 'models resolve' verweigert
# also ausserhalb macOS zu Recht, und das ist hier die zu pruefende Zusage, nicht
# ein Ausfall (Befund 2026-08-21: diese Suite lief bis dahin nie auf einer
# zweiten Maschine, darum blieb der Zweig ungeprueft).
OUT="$("$WBS" models resolve copilot-cloud-auto --role worker --dir "$TESTHOME/work" --name w1 2>&1)"
RC=$?
CMD="$(printf '%s\n' "$OUT" | awk -F'\t' '$1=="cmd"{print $2}')"
if [ "$(uname -s)" = "Darwin" ]; then
    case "$CMD" in
      *--continue*) bad "7: resolve haengt --continue an den ersten Spawn: $CMD" ;;
      *)            ok "7: der erste Spawn bekommt kein --continue" ;;
    esac
    case "$CMD" in
      *--allow-all*) ok "7: die Autonomie-Flags haengen an (--allow-all)" ;;
      *) bad "7: die Startzeile traegt kein --allow-all: $CMD" ;;
    esac
    env_wert() { printf '%s\n' "$OUT" | awk -F'\t' -v k="$1" '$1=="env" && $2==k{print $3}'; }
    [ "$(env_wert COPILOT_MODEL)" = "auto" ] \
      && ok "7: COPILOT_MODEL wird ueber resolve auf 'auto' aufgeloest" \
      || bad "7: COPILOT_MODEL ist '$(env_wert COPILOT_MODEL)' statt 'auto'"
else
    if [ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -qi "darf auf dieser Maschine"; then
        ok "7: ausserhalb macOS verweigert resolve copilot-cloud-auto -- der Login haengt am macOS-Schluesselbund"
    else
        bad "7: unerwartetes Verhalten ausserhalb macOS (rc=$RC): $OUT"
    fi
fi
[ "$(feld trustStore.file)" = "~/.copilot/config.json" ] \
  && ok "7: trustStore zeigt auf dieselbe Datei wie der lokale Eintrag" \
  || bad "7: trustStore.file ist '$(feld trustStore.file)'"

# 8 — der bestehende lokale Eintrag bleibt unveraendert (Auftrag: 'copilot bleibt, wie es ist').
LOKAL="$(/usr/bin/python3 -c '
import json
d = json.load(open("'"$REG"'"))
h = next(x for x in d["harnesses"] if x["id"] == "copilot")
print(h["env"].get("COPILOT_OFFLINE"), h["env"].get("COPILOT_PROVIDER_TYPE"))
')"
[ "$LOKAL" = "true openai" ] \
  && ok "8: der bestehende Eintrag 'copilot' traegt weiterhin COPILOT_OFFLINE=true / COPILOT_PROVIDER_TYPE=openai" \
  || bad "8: der bestehende Eintrag 'copilot' hat sich veraendert: '$LOKAL'"

echo
echo "== $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
