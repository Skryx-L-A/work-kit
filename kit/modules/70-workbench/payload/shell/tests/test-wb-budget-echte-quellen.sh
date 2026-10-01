#!/bin/bash
# test-wb-budget-echte-quellen.sh -- wb-budget --json gegen ECHTE Dateien dieser Maschine.
#
# WARUM EINE ZWEITE SUITE NEBEN test-wb-budget-quellen.sh: jene Suite prueft die Rechenlogik an
# selbst gebauten Fixtures in einem isolierten HOME -- notwendig fuer feste, reproduzierbare
# Zahlen, aber blind gegen alles, was ein echtes Transkript an Eigenheiten mitbringt (fehlende
# Felder, ungewoehnliche Zeilen, sehr grosse Dateien). Diese Suite laeuft ohne Isolation, gegen
# das echte $HOME dieser Maschine, und prueft je Quelle nur EINE Sache: wird die real vorhandene
# Datei ueberhaupt gelesen, nicht als "fehlt" oder "unlesbar" gemeldet. Auftrag 2026-08-15
# ("je neuer Quelle ein Test gegen eine echte Beispieldatei dieser Maschine").
#
# MASCHINENABHAENGIG, ABSICHTLICH. Fehlt eine der sechs Quellendateien auf der laufenden
# Maschine, wird genau diese eine Zusage uebersprungen (nicht die ganze Suite) -- der Bericht
# vom 11.08. (~/.pi-workers/results/verbrauchdaten/latest.md) findet fuer sieben Harnesses
# ausdruecklich KEINE Spur; das ist kein Fehler dieser Suite, sondern der gemessene Zustand.
#
# Isolation: keine, absichtlich (siehe oben). Kein Schreibzugriff -- nur `wb-budget --json`
# lesend gegen das echte HOME.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$REPO/wb-budget"
echo "Geprueft: $TOOL --json gegen \$HOME=$HOME"
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }
uebersprungen_einzel() { SKIP=$((SKIP+1)); printf '  skip  %s\n' "$1"; }

command -v /usr/bin/python3 >/dev/null 2>&1 || { echo "UEBERSPRUNGEN: /usr/bin/python3 fehlt"; exit 77; }
[ -x "$TOOL" ] || { echo "UEBERSPRUNGEN: $TOOL fehlt oder nicht ausfuehrbar"; exit 77; }

FEHLER="$(mktemp "${TMPDIR:-/tmp}/wbeq-err.XXXXXX")"
WB_JSON_DATEI="$(mktemp "${TMPDIR:-/tmp}/wbeq-json.XXXXXX")"
trap 'rm -f "$FEHLER" "$WB_JSON_DATEI"' EXIT
# Grosses Fenster (10 Jahre): diese Suite haengt an vorhandenen Dateien, nicht an einem
# bestimmten Datum -- sie soll nicht flackern, nur weil der letzte codex-Lauf laenger als
# sieben Tage her ist.
"$TOOL" --json --tage 3650 --ohne-kontingent >"$WB_JSON_DATEI" 2>"$FEHLER"
if [ ! -s "$WB_JSON_DATEI" ]; then
  echo "UEBERSPRUNGEN: wb-budget --json lieferte nichts"
  cat "$FEHLER" 2>/dev/null
  exit 77
fi

# Die Ausgabe geht in eine DATEI, nicht in eine Umgebungsvariable: auf peers echtem $HOME
# (Jahre an Transkripten, siehe Anlass oben) traf 'WB_JSON="$AUS" python3 …' zuverlaessig
# 'Argument list too long' -- ein einzelner ~270 KiB grosser Wert reisst hier schon bei
# 128 KiB ab, weit unter dem von 'getconf ARG_MAX' gemeldeten Limit (Befund 2026-08-21,
# nachgestellt mit einem synthetischen String derselben Groesse). Eine Datei kennt dieses
# Limit nicht.
frage() {
  /usr/bin/python3 - "$WB_JSON_DATEI" "$@" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
was = sys.argv[2]
rest = sys.argv[3:]
if was == "zustand":
    for q in d["quellen"]:
        if q["harness"] == rest[0]:
            print(q["zustand"]); break
    else:
        print("QUELLE-FEHLT")
elif was == "nachrichten":
    n = 0
    for q in d["quellen"]:
        if q["harness"] in rest:
            n += q.get("nachrichten", 0) or 0
    print(n)
PY
}

# harness, Zustand "gelesen" ODER "leer" gelten beide als "wurde ausgewertet, kein Lesefehler".
pruefe_zustand() {
  local harness="$1" beschreibung="$2"
  local zustand
  zustand="$(frage zustand "$harness")"
  case "$zustand" in
    gelesen|leer) ok "$harness: $beschreibung, wb-budget meldet '$zustand' (nicht 'fehlt'/'unlesbar')" ;;
    *) bad "$harness: $beschreibung vorhanden, wb-budget meldet '$zustand'" ;;
  esac
}

if ls "$HOME"/.codex/sessions/*/*/*/rollout-*.jsonl >/dev/null 2>&1; then
  pruefe_zustand codex "echte rollout-*.jsonl unter ~/.codex/sessions"
else
  uebersprungen_einzel "codex: keine rollout-*.jsonl unter ~/.codex/sessions auf dieser Maschine"
fi

if find "$HOME/.pi-workers/sessions" -name '*.jsonl' -print -quit 2>/dev/null | grep -q .; then
  pruefe_zustand pi "echte Sitzungsdatei unter ~/.pi-workers/sessions"
else
  uebersprungen_einzel "pi: keine Sitzungsdatei unter ~/.pi-workers/sessions auf dieser Maschine"
fi

if [ -f "$HOME/.local/share/opencode/opencode.db" ]; then
  pruefe_zustand opencode "echte opencode.db vorhanden"
else
  uebersprungen_einzel "opencode: ~/.local/share/opencode/opencode.db fehlt auf dieser Maschine"
fi

if [ -f "$HOME/.copilot/session-store.db" ]; then
  # copilot und copilot-cloud teilen sich dieselbe Datenbank -- beide Zeilen muessen aus
  # derselben echten Datei kommen, nicht nur eine.
  pruefe_zustand copilot-cloud "echte session-store.db (Cloud-Zeilen) vorhanden"
  # Ob 'copilot' (lokales Modell) selbst Zeilen hat, haengt davon ab, ob je ein Ollama-Modell
  # ueber copilot lief -- 'leer' ist hier ein gueltiger, kein fehlerhafter Zustand.
  pruefe_zustand copilot "dieselbe echte session-store.db (lokale Zeilen) vorhanden"
else
  uebersprungen_einzel "copilot/copilot-cloud: ~/.copilot/session-store.db fehlt auf dieser Maschine"
fi

if find "$HOME/.openhands/conversations" -name 'base_state.json' -print -quit 2>/dev/null | grep -q .; then
  pruefe_zustand openhands "echte base_state.json unter ~/.openhands/conversations"
else
  uebersprungen_einzel "openhands: keine base_state.json unter ~/.openhands/conversations auf dieser Maschine"
fi

# claude selbst: gab es schon vor diesem Auftrag, hier nur zur Vollstaendigkeit mitgeprueft --
# die eigene laufende Sitzung IST die echte Beispieldatei.
if find "$HOME/.claude/projects" -name '*.jsonl' -print -quit 2>/dev/null | grep -q .; then
  pruefe_zustand claude "echte Transkripte unter ~/.claude/projects"
else
  uebersprungen_einzel "claude: keine Transkripte unter ~/.claude/projects auf dieser Maschine"
fi

N="$(frage nachrichten codex pi opencode copilot copilot-cloud openhands)"
# Kit: on a machine where none of the six sources has content, there is nothing to count.
GELESEN=0
for h in codex pi opencode copilot copilot-cloud openhands; do
  [ "$(frage zustand "$h")" = gelesen ] && GELESEN=1
done
if [ "${N:-0}" -gt 0 ] 2>/dev/null; then
  ok "die sechs Nicht-Claude-Quellen liefern zusammen $N echte Nachrichten, nicht nur Struktur"
elif [ "$GELESEN" = 0 ]; then
  uebersprungen_einzel "keine der sechs Nicht-Claude-Quellen hat auf dieser Maschine Inhalt"
else
  bad "die sechs Nicht-Claude-Quellen liefern zusammen 0 Nachrichten" \
    "erwartet auf einer Maschine mit mindestens einer der sechs Quellendateien"
fi

echo
echo "  bestanden: $PASS, fehlgeschlagen: $FAIL, uebersprungen: $SKIP"
[ "$FAIL" -eq 0 ]
