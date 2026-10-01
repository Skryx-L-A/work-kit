#!/usr/bin/env bash
# test-chat-hook-installation.sh — die gemeinsame Hook-Installation fuer die
# Zuordnung (SPEC-V4 6.3 Punkt 4, gebaut 2026-08-11).
#
# WORUM ES GEHT. Die Chat-Ansicht muss wissen, WELCHE Sitzung in DIESEM Pane
# laeuft. Ueber das Arbeitsverzeichnis geht das nur, solange dort eine einzige
# lebt — im Worker-Grid ist zwei im selben Ordner der Normalfall. Wo ein Harness
# Hooks hat, schreibt `wb-harness-run` sich deshalb vor dem Start einen: er
# laeuft IM Prozess des Harness, sieht $TMUX_PANE und legt die Sitzungskennung
# als Pane-Option @wb_chat_session ab.
#
# WAS HIER HAENGT:
#   1  Der Haken wird angelegt, ist ausfuehrbar, und der Eintrag in der
#      Konfiguration des Harness zeigt auf ihn.
#   2  Ein zweiter Start verdoppelt ihn NICHT. Jeder Spawn laeuft hier durch;
#      eine Datei, die bei jedem Start um einen Eintrag waechst, waere in einer
#      Woche unlesbar.
#   3  FREMDE Eintraege bleiben stehen. In ~/.claude/settings.json stehen sieben
#      Hook-Ereignisse dieses Hauses; sie zu ueberschreiben waere schlimmer als
#      keine Zuordnung.
#   4  Bei codex gehoeren ZWEI Schritte dazu: hooks.json schreiben UND den
#      trusted_hash in config.toml nachziehen. Ohne den zweiten laeuft der Hook
#      STILL nicht — deshalb muss das Fehlen der Pruefsumme eine sichtbare
#      Meldung sein und kein Schweigen.
#   5  Ein Harness, der nicht ueber einen Hook zugeordnet wird, bekommt keinen.
#   6  Der Haken selbst tut, was er soll: aus der Hook-Eingabe die
#      Sitzungskennung holen und sie als Pane-Option setzen — und ohne
#      $TMUX_PANE gar nichts.
#
# ISOLATION: eigenes HOME, eigenes TMPDIR, ein STUB fuer `wb-state` und ein STUB
# fuer `tmux`. Kein echter Harness, kein echter tmux-Server, keine Datei der
# laufenden Sitzung wird angefasst — das Startkommando ist `/usr/bin/true`.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUF="$REPO/shell/wb-harness-run"
TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-chathook.XXXXXX")" && pwd)"
export TMPDIR="$TESTHOME/tmp"
mkdir -p "$TESTHOME/.local/bin" "$TESTHOME/.claude" "$TESTHOME/.codex" "$TMPDIR"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() { rm -rf "$TESTHOME"; }
trap cleanup EXIT INT TERM

echo "== Hook-Installation der Chat-Zuordnung =="
echo "Geprueft: $LAUF"

# --- der wb-state-Stub: er antwortet auf genau zwei Fragen --------------------
cat > "$TESTHOME/.local/bin/wb-state" <<'STUB'
#!/bin/sh
# Stub fuer den Test: kein echtes wb-state, keine echte Registry.
case "$1 $2" in
  "models resolve")
    printf 'harness\t%s\n' "$WB_TEST_HARNESS"
    printf 'cmd\t/usr/bin/true\n'
    ;;
  "harness get")
    cat "$WB_TEST_HJSON"
    ;;
esac
exit 0
STUB
chmod +x "$TESTHOME/.local/bin/wb-state"

lauf() { # lauf <harness-id> <json-datei> -> die Ausgabe des Laufs
  # `env` und nicht nur Zuweisungen davor: eine Zeile aus lauter Zuweisungen
  # OHNE Befehl setzt die Variablen in DIESER Shell und fuehrt nichts aus --
  # der Test lief dann gegen sich selbst statt gegen wb-harness-run.
  env HOME="$TESTHOME" TMPDIR="$TMPDIR" WB_TEST_HARNESS="$1" WB_TEST_HJSON="$2" \
    bash "$LAUF" --model testmodell --role worker --dir "$TESTHOME" 2>&1
}

hjson() { # hjson <datei> <id> <hook-json>
  cat > "$1" <<JSON
{"id": "$2", "session": {"via": "sessionFile", "ort": "~/x/{sessionId}.jsonl",
 "format": "claude-transcript", "zuordnung": "hook", "live": true, "eingabe": "pane",
 "zeigtNicht": [], "probe": {"datum": "2026-08-11", "beleg": "Test"},
 "hook": $3}}
JSON
}

HAKEN="$TESTHOME/.claude/workbench/chat-zuordnung.sh"

# --- 1: der Haken entsteht und wird eingetragen -------------------------------
hjson "$TESTHOME/h-claude.json" testclaude \
  '{"style": "claude-settings-json", "file": "~/.claude/settings.json", "event": "SessionStart", "matcher": "startup|resume", "timeout": 5}'
printf '%s\n' '{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/fremd/guard.sh"}]}]}, "model": "opus"}' \
  > "$TESTHOME/.claude/settings.json"
AUSGABE="$(lauf testclaude "$TESTHOME/h-claude.json")"

[ -x "$HAKEN" ] && ok "1: der Haken liegt da und ist ausfuehrbar" || bad "1: $HAKEN fehlt oder ist nicht ausfuehrbar"
if /usr/bin/python3 - "$TESTHOME/.claude/settings.json" "$HAKEN" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
h = (d.get("hooks") or {}).get("SessionStart") or []
sys.exit(0 if any(e.get("command") == sys.argv[2] for g in h for e in (g.get("hooks") or [])) else 1)
PY
then ok "1: der Eintrag in settings.json zeigt auf den Haken"
else bad "1: kein SessionStart-Eintrag mit dem Pfad des Hakens"; fi
case "$AUSGABE" in *"Chat-Zuordnung als SessionStart-Hook"*) ok "1: der Start sagt, dass er eingetragen hat" ;;
  *) bad "1: keine Meldung ueber den Eintrag (Ausgabe: $AUSGABE)" ;; esac

# --- 2 und 3: idempotent, und Fremdes bleibt ----------------------------------
lauf testclaude "$TESTHOME/h-claude.json" >/dev/null
ZAEHLER="$(/usr/bin/python3 - "$TESTHOME/.claude/settings.json" "$HAKEN" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
h = (d.get("hooks") or {}).get("SessionStart") or []
print(sum(1 for g in h for e in (g.get("hooks") or []) if e.get("command") == sys.argv[2]))
PY
)"
[ "$ZAEHLER" = 1 ] && ok "2: ein zweiter Start traegt ihn NICHT noch einmal ein" \
  || bad "2: der Haken steht ${ZAEHLER}x in settings.json"
if /usr/bin/python3 - "$TESTHOME/.claude/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
pre = (d.get("hooks") or {}).get("PreToolUse") or []
gut = d.get("model") == "opus" and any(
    e.get("command") == "/fremd/guard.sh" for g in pre for e in (g.get("hooks") or []))
sys.exit(0 if gut else 1)
PY
then ok "3: fremde Hooks und Einstellungen stehen unveraendert daneben"
else bad "3: die Datei hat fremde Eintraege verloren"; fi

# --- 4: codex, beide Schritte -------------------------------------------------
CODEXHOOKS="$TESTHOME/.codex/hooks.json"
CODEXTOML="$TESTHOME/.codex/config.toml"
printf '%s\n' '[projects."/x"]' 'trust_level = "trusted"' > "$CODEXTOML"
hjson "$TESTHOME/h-codex.json" testcodex \
  "{\"style\": \"codex-hooks-json\", \"file\": \"$CODEXHOOKS\", \"event\": \"SessionStart\", \"trustFile\": \"$CODEXTOML\", \"trustTable\": \"hooks.state\"}"
AUSGABE="$(lauf testcodex "$TESTHOME/h-codex.json")"
[ -f "$CODEXHOOKS" ] && ok "4: hooks.json ist geschrieben" || bad "4: hooks.json fehlt"
case "$AUSGABE" in *"NICHT ausfuehren"*) ok "4: der fehlende trusted_hash wird SICHTBAR gemeldet" ;;
  *) bad "4: das Fehlen der Pruefsumme blieb still (Ausgabe: $AUSGABE)" ;; esac
grep -q "trusted_hash" "$CODEXTOML" && bad "4: ohne Pruefsumme wurde trotzdem etwas eingetragen" \
  || ok "4: ohne Pruefsumme bleibt config.toml unangetastet"

# … und mit gemessener Pruefsumme wird sie nachgezogen.
rm -f "$CODEXHOOKS"
HASH="sha256:$(printf 'x' | shasum -a 256 | cut -d' ' -f1)"
hjson "$TESTHOME/h-codex2.json" testcodex \
  "{\"style\": \"codex-hooks-json\", \"file\": \"$CODEXHOOKS\", \"event\": \"SessionStart\", \"trustFile\": \"$CODEXTOML\", \"trustTable\": \"hooks.state\", \"trustedHash\": \"$HASH\"}"
lauf testcodex "$TESTHOME/h-codex2.json" >/dev/null
if grep -q "\[hooks.state.\"$CODEXHOOKS:session_start:0:0\"\]" "$CODEXTOML" && grep -q "$HASH" "$CODEXTOML"; then
  ok "4: mit Pruefsumme steht der Vertrauenseintrag in codex-Schreibweise da"
else
  bad "4: der Vertrauenseintrag fehlt oder heisst anders: $(grep -c hooks.state "$CODEXTOML") Treffer"
fi
grep -q '\[projects."/x"\]' "$CODEXTOML" && ok "4: der bestehende Vertrauensspeicher blieb stehen" \
  || bad "4: config.toml hat ihre bisherigen Abschnitte verloren"

# --- 5: kein Hook, wo keiner hingehoert ---------------------------------------
cat > "$TESTHOME/h-cwd.json" <<'JSON'
{"id": "testcwd", "session": {"via": "sessionFile", "ort": "~/y/*.jsonl", "format": "pi-jsonl",
 "zuordnung": "cwd", "live": true, "eingabe": "pane", "zeigtNicht": [],
 "probe": {"datum": "2026-08-11", "beleg": "Test"}}}
JSON
printf '%s\n' '{}' > "$TESTHOME/.claude/settings.json"
lauf testcwd "$TESTHOME/h-cwd.json" >/dev/null
grep -q chat-zuordnung "$TESTHOME/.claude/settings.json" \
  && bad "5: ein Harness mit Zuordnung ueber cwd bekam einen Hook" \
  || ok "5: wer nicht ueber einen Hook zugeordnet wird, bekommt keinen"

# … und eine Zuordnung 'hook' OHNE Angabe, wohin, meldet die Luecke.
cat > "$TESTHOME/h-luecke.json" <<'JSON'
{"id": "testluecke", "session": {"via": "sessionFile", "ort": "~/y/{sessionId}.jsonl",
 "format": "claude-transcript", "zuordnung": "hook", "live": true, "eingabe": "pane",
 "zeigtNicht": [], "probe": {"datum": "2026-08-11", "beleg": "Test"}}}
JSON
AUSGABE="$(lauf testluecke "$TESTHOME/h-luecke.json")"
case "$AUSGABE" in *"nennt keinen Stil"*) ok "5: eine Luecke in der Registry wird gemeldet" ;;
  *) bad "5: die fehlende hook-Angabe blieb still (Ausgabe: $AUSGABE)" ;; esac

# --- 6: der Haken selbst ------------------------------------------------------
# Ein tmux-STUB statt des echten: der Test fasst keinen laufenden Server an.
cat > "$TESTHOME/.local/bin/tmux" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$TMUX_STUB_LOG"
exit 0
STUB
chmod +x "$TESTHOME/.local/bin/tmux"
export TMUX_STUB_LOG="$TESTHOME/tmux-aufrufe.log"
: > "$TMUX_STUB_LOG"
printf '%s' '{"session_id":"abc-123","source":"startup"}' \
  | PATH="$TESTHOME/.local/bin:$PATH" TMUX_PANE="%42" sh "$HAKEN"
if grep -q 'set-option -p -t %42 @wb_chat_session abc-123' "$TMUX_STUB_LOG"; then
  ok "6: der Haken legt die Sitzungskennung an den Pane"
else
  bad "6: keine Pane-Option gesetzt (Log: $(cat "$TMUX_STUB_LOG"))"
fi
: > "$TMUX_STUB_LOG"
printf '%s' '{"session_id":"abc-123"}' | PATH="$TESTHOME/.local/bin:$PATH" sh "$HAKEN"
[ -s "$TMUX_STUB_LOG" ] && bad "6: ohne \$TMUX_PANE wurde trotzdem etwas gesetzt" \
  || ok "6: ohne \$TMUX_PANE tut der Haken gar nichts"
: > "$TMUX_STUB_LOG"
printf '%s' 'kein json' | PATH="$TESTHOME/.local/bin:$PATH" TMUX_PANE="%42" sh "$HAKEN"
[ -s "$TMUX_STUB_LOG" ] && bad "6: aus kaputter Eingabe wurde etwas gesetzt" \
  || ok "6: eine kaputte Hook-Eingabe setzt nichts"

echo
echo "  bestanden: $pass, fehlgeschlagen: $fail"
[ "$fail" -eq 0 ]
