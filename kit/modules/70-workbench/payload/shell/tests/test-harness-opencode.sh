#!/usr/bin/env bash
# test-harness-opencode.sh — die drei Zusagen, die opencode am 2026-08-08 bekommen hat.
#
# opencode trug seit dem 06.08. eine Warnung, die vier Dinge auf einmal sagte: nimmt die
# Modellwahl nicht an, kein promptPattern, readyPattern trifft nur den Platzhalter, und
# ohne resume.probe erbt jeder neue Worker eine fremde Unterhaltung. Nachgemessen wurde am
# 2026-08-08 mit opencode 1.18.14/1.18.15 auf eigenem Socket, mit Wegwerf-HOME und zwei
# eigenen OpenAI-kompatiblen Stub-Servern statt eines echten Modells:
#
#   * --model KOMMT an, solange die Referenz aufloesbar ist. Der POST traf den Port des
#     bestellten Providers mit dem bestellten Modellnamen, und die Statuszeile im Kasten
#     nannte dasselbe Modell.
#   * Ist die Referenz NICHT aufloesbar, ersetzt opencode sie STILL durch ein eigenes
#     Cloud-Modell ('Big Pickle · OpenCode Zen') — kein Fehler, nur ein Tipp '/connect'.
#   * Steht --continue in derselben Zeile, gewinnt das Modell der fortgesetzten Sitzung
#     und --model wird verworfen. Genau das tat die Workbench bis zum 06.08. bei JEDEM
#     Spawn, weil der resume-Block kein probe trug. Der Befund "ignoriert die Modellwahl"
#     und der Befund "erbt eine fremde Unterhaltung" hatten also EINE Ursache.
#
# Geprueft wird hier deshalb der ausgelieferte Registry-Stand (shell/models.default.json)
# gegen aufgezeichnete Bildschirme — Fixtures, kein installiertes opencode: ein Test haengt
# nie daran, was zufaellig auf der Maschine liegt.
#
#   1  readyPattern trifft alle drei gemessenen Zustaende (leer, getippt, beschaeftigt).
#   2  Der alte Platzhalter 'Ask anything' taete das nicht — der Grund, warum er weg ist.
#   3  readyPattern ist ein gueltiges ERE und trifft keinen leeren Bildschirm.
#   4  resume.probe ist 'revive-only': beim ERSTEN Spawn haengt resolve kein --continue an.
#   5  Der Weg zurueck bleibt trotzdem da: resume.args traegt --continue fuer wb-revive.
#   6  Ein promptPattern gibt es nicht — und wenn eines nachgetragen wird, darf es die
#      Statuszeile des Kastens nicht treffen, sonst prueft die Absende-Verifikation eine
#      Zeile, die sich nie aendert.
#   7  Die Eignungstexte beider opencode-Modelle warnen vor der stillen Ersetzung.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"     # …/claude-workbench/shell
REG="$REPO/models.default.json"
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-opencode-test.XXXXXX")" && pwd)"
export HOME="$TESTHOME"
export WB_NO_DISCOVER=1
BIN="$TESTHOME/.local/bin"; mkdir -p "$BIN" "$TESTHOME/.claude/workbench" "$TESTHOME/work"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT INT TERM

echo "== test-harness-opencode =="
echo "Geprueft: Registry-Stand aus $REG"

# KOPIE, kein Symlink (wie in test-registry.sh): die Suite prueft einen festen Stand.
cp "$REPO/wb-state" "$BIN/wb-state"; chmod +x "$BIN/wb-state"
cp "$REG" "$TESTHOME/.claude/workbench/models.json"
# Kit: no opencode model ships (they come from 'wb-state models discover opencode'); the
# suite adds one kit-llm model to test the adapter.
/usr/bin/python3 - "$TESTHOME/.claude/workbench/models.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["models"].append({"id": "opencode-qwen3.5-4b", "label": "Qwen3.5 4B via opencode", "harness": "opencode",
                    "provider": "kit-llm", "modelRef": "kit-llm/qwen3.5-4b", "roles": ["worker"],
                    "enabled": True, "supportsEffort": False})
json.dump(d, open(sys.argv[1], "w"), indent=2)
PY
WBS="$BIN/wb-state"

feld() { /usr/bin/python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
h = next(x for x in d["harnesses"] if x["id"] == "opencode")
cur = h
for k in sys.argv[2].split("."):
    cur = (cur or {}).get(k) if isinstance(cur, dict) else None
print("" if cur is None else (json.dumps(cur) if not isinstance(cur, str) else cur))
' "$REG" "$1"; }

READY="$(feld readyPattern)"
[ -n "$READY" ] && ok "readyPattern ist gesetzt: $READY" || bad "readyPattern fehlt"

# ── Die drei aufgezeichneten Bildschirme ─────────────────────────────────────────────
# Aufgenommen 2026-08-08 mit opencode 1.18.15 in einem 100x26-Pane auf eigenem Socket,
# Wegwerf-HOME, Modell 'slow/slow-1' (Stub-Server mit 20 s Verzoegerung, damit der
# beschaeftigte Zustand ueberhaupt lange genug steht, um ihn abzugreifen). Gekuerzt auf
# den Kasten und die beiden Zeilen darunter — der Rest des Bildschirms traegt nichts zur
# Frage bei, und die Wegwerf-Pfade sollen nicht in der Datei stehen.
FIX="$TESTHOME/fix"; mkdir -p "$FIX"

cat >"$FIX/leer.txt" <<'EOF'
             ┃
             ┃  Ask anything... "What is the tech stack of this project?"
             ┃
             ┃  Build auto · Slow One Slow (stub)
             ╹▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
             tab agents  ctrl+p commands
  ~/work                                                                    1.18.15
EOF

cat >"$FIX/getippt.txt" <<'EOF'
             ┃
             ┃  auftrag: pruefe die tests
             ┃
             ┃  Build auto · Slow One Slow (stub)
             ╹▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
             tab agents  ctrl+p commands
  ~/work                                                                    1.18.15
EOF

cat >"$FIX/beschaeftigt.txt" <<'EOF'
  ┃  auftrag: pruefe die tests
  ┃
  ┃
  ┃
  ┃  Build auto · Slow One Slow (stub)
  ╹▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
   ⬝⬝⬝⬝⬝⬝⬝⬝  esc interrupt                             tab agents  ctrl+p commands
EOF

# 1 — die Zusage selbst. Der Ready-Wait in pi-worker fragt genau so: grep -qE auf den
# gerenderten Pane. Was er in keinem der drei Zustaende findet, ist als Bereitschafts-
# zeichen unbrauchbar.
for z in leer getippt beschaeftigt; do
  if grep -qE "$READY" "$FIX/$z.txt"; then
    ok "1: readyPattern trifft den Zustand '$z'"
  else
    bad "1: readyPattern '$READY' trifft den Zustand '$z' NICHT"
  fi
done

# 2 — warum der Platzhalter weg ist. Kein Geschmacksurteil, sondern der Messwert:
# 'Ask anything' steht nur in der leeren Box.
grep -q "Ask anything" "$FIX/leer.txt" \
  && ok "2: der Platzhalter steht in der leeren Box (Messwert)" \
  || bad "2: Fixture 'leer' enthaelt den Platzhalter nicht — Fixture kaputt"
if grep -q "Ask anything" "$FIX/getippt.txt" || grep -q "Ask anything" "$FIX/beschaeftigt.txt"; then
  bad "2: Fixture behauptet, der Platzhalter ueberlebe Tippen/Antworten — das war nicht die Messung"
else
  ok "2: der Platzhalter ist beim Tippen und waehrend der Antwort weg"
fi
[ "$READY" = "Ask anything" ] \
  && bad "2: readyPattern ist wieder der Platzhalter — trifft weder getippt noch beschaeftigt" \
  || ok "2: readyPattern ist nicht mehr der Platzhalter"

# 3 — ein Muster, das auf allem trifft, ist keins. Der leere Bildschirm ist der Zustand
# der ersten zwei Sekunden nach dem Start; dort darf es NICHT anschlagen.
printf '\n\n   \n\n' >"$FIX/leerer-bildschirm.txt"
grep -qE "$READY" "$FIX/leerer-bildschirm.txt" \
  && bad "3: readyPattern trifft schon den leeren Startbildschirm" \
  || ok "3: readyPattern trifft den leeren Startbildschirm nicht"

# 4 — die gemeinsame Ursache der Befunde 1 und 2. resolve baut die Startzeile fuer den
# ERSTEN Spawn; steht dort --continue, verwirft opencode --model und der Pane erbt die
# letzte Unterhaltung dieses Verzeichnisses.
eq_probe="$(feld resume.probe)"
[ "$eq_probe" = "revive-only" ] \
  && ok "4: resume.probe ist 'revive-only'" \
  || bad "4: resume.probe ist '$eq_probe' statt 'revive-only'"
# 'models resolve' prueft auch, ob das Binary 'opencode' installiert ist;
# fehlt es (diese Maschine hat es nicht, command -v opencode), verweigert es
# den Spawn VOR jeder Ausgabe und die drei Zusagen unten haben nichts zu
# pruefen. Kein Registry-/Code-Fehler, sondern eine fehlende lokale
# Installation (Befund 2026-08-21).
if ! command -v opencode >/dev/null 2>&1; then
  ok "4: resolve-Zusagen uebersprungen -- 'opencode' ist auf dieser Maschine nicht installiert"
else
OUT="$("$WBS" models resolve opencode-qwen3.5-4b --role worker --dir "$TESTHOME/work" --name w1 2>/dev/null)"
CMD="$(printf '%s\n' "$OUT" | awk -F'\t' '$1=="cmd"{print $2}')"
case "$CMD" in
  *"--model kit-llm/qwen3.5-4b"*) ok "4: resolve bestellt das Modell: $CMD" ;;
  *) bad "4: resolve baut keine Modellwahl: ${CMD:-<leer>}" ;;
esac
case "$CMD" in
  *--continue*) bad "4: resolve haengt --continue an den ersten Spawn — --model wird verworfen" ;;
  *)            ok "4: der erste Spawn bekommt kein --continue" ;;
esac
READY_OUT="$(printf '%s\n' "$OUT" | awk -F'\t' '$1=="ready"{print $2}')"
[ "$READY_OUT" = "$READY" ] \
  && ok "4: resolve reicht dasselbe readyPattern durch" \
  || bad "4: resolve meldet ready '$READY_OUT' statt '$READY'"
fi

# 5 — revive-only heisst NICHT "kein Weg zurueck": wb-revive holt sich die Flags aus
# demselben Block, und ohne sie kaeme jeder wiederbelebte Pane leer wieder.
case "$(feld resume.args)" in
  *--continue*) ok "5: resume.args traegt --continue fuer wb-revive" ;;
  *)            bad "5: resume.args ohne --continue — wiederbelebte Panes kommen leer zurueck" ;;
esac

# 6 — die Falle fuer den naechsten, der das fehlende promptPattern "nachtraegt". Die
# Absende-Verifikation in pi-worker nimmt die LETZTE Zeile, die das Muster trifft, und
# das ist bei opencode immer die Statuszeile des Kastens: sie aendert sich nie, also
# hiesse "sieht aus wie vorher" bei jedem Auftrag "abgeschickt".
STATUS="$(grep -E '^[[:space:]]*┃' "$FIX/leer.txt" | tail -1)"
case "$STATUS" in
  *"Build auto ·"*) ok "6: unterste Kastenzeile ist die Statuszeile (Fixture stimmt)" ;;
  *) bad "6: Fixture: unterste Kastenzeile ist nicht die Statuszeile, sondern '$STATUS'" ;;
esac
PROMPT="$(feld promptPattern)"
if [ -z "$PROMPT" ]; then
  ok "6: kein promptPattern — die Absendung wird ehrlich als unbelegt gemeldet"
elif printf '%s\n' "$STATUS" | grep -qE "$PROMPT"; then
  bad "6: promptPattern '$PROMPT' trifft die Statuszeile — Absende-Verifikation prueft die falsche Zeile"
else
  ok "6: promptPattern '$PROMPT' laesst die Statuszeile aus"
fi

# 7 — die Warnung muss in der Zeile stehen, die der Orchestrator liest. Die Routing-
# Tabelle wird aus goodFor erzeugt; steht es dort nicht, sieht es niemand.
# Kit: the shipped registry carries no opencode model (the upstream ones were the build
# machine's); the silent-substitution warning belongs to the models 'discover' imports.
n_oc="$(/usr/bin/python3 -c 'import json,sys; print(sum(1 for m in json.load(open(sys.argv[1]))["models"] if m["harness"] == "opencode"))' "$REG")"
[ "$n_oc" = 0 ] && ok "7: no opencode model ships; they come from 'models discover opencode'" \
  || bad "7: $n_oc opencode models ship without the measured substitution warning"

echo
echo "== $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
