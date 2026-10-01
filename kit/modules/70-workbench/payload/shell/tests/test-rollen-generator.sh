#!/usr/bin/env bash
# test-rollen-generator.sh — Gestalt B: der Rollen-Prompt fuer Harnesses, die eine
# Datei lesen, und die Absende-Pruefung ohne Wortlaut.
#
# Anlass (2026-08-06): Drei Harnesses (codex, opencode, agy) nehmen keinen Rollen-Prompt
# als Flag. Der Aufloeser meldete seit je "diese Datei muss der Generator vorher
# geschrieben haben" — den Generator gab es nicht, und damit wusste ein Worker dort
# nichts vom Ergebnisprotokoll. Dazu: codex waehlt seinen Eingabe-Platzhalter beim Start
# aus einer Liste (fuenf gemessen), weshalb eine feste promptIgnore-Zeichenkette die
# Absendung in der Mehrzahl der Starts faelschlich als haengend meldete.
#
# Geprueft wird:
#   A  Der Projektweg: die Rollendatei liegt im ARBEITSVERZEICHNIS und traegt unseren
#      Text, wenn die CLI startet — belegt dadurch, dass die CLI sie beim Start liest
#      und protokolliert.
#   B  Zwei gleichzeitige Spawns verschiedener Rolle stoeren sich nicht, solange jeder
#      sein eigenes Verzeichnis hat (der Normalfall mit Worktrees).
#   C  Im GETEILTEN Ziel lehnt der zweite Start sichtbar ab, statt dem ersten die Rolle
#      zu ueberschreiben — und es wird nichts gestartet.
#   D  Fremder Inhalt in der Datei bleibt stehen; unser Text kommt zwischen Marken dazu.
#   E  Ein zweiter Start derselben Rolle ersetzt den eigenen Block, statt ihn zu haeufen.
#   F  Eine von uns angelegte Projektdatei landet in .git/info/exclude.
#   G  Absende-Pruefung, BEIDE Richtungen: ein rotierender Platzhalter gilt als
#      abgeschickt, ein wirklich haengender Auftrag weiterhin als haengend.
#
# Die Marken 'ROLLENTEXT-WORKER-77' und 'Vorschlag-DREIUNDVIERZIG' sind erfunden und
# standen vor diesem Lauf nirgends.
#
# SICHERHEIT: eigener Socket, eigenes HOME, eigene Registry. Aufgeraeumt wird nur, was
# der erwarteten Form entspricht — nie $HOME.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

SOCKET="wbtest-rollen-$$"
TESTHOME="$(mktemp -d "${TMPDIR:-/tmp}/rollengen.XXXXXX")"
case "$TESTHOME" in
  "${TMPDIR:-/tmp}"/rollengen.*) ;;
  *) echo "FAIL  unerwartetes Testverzeichnis '$TESTHOME'"; exit 1 ;;
esac
BIN="$TESTHOME/.local/bin"; SHIM="$TESTHOME/.shim"
REG="$TESTHOME/.claude/workbench/models.json"
CLILOG="$TESTHOME/cli.log"

pass=0; fail=0
tm() { tmux -L "$SOCKET" "$@"; }
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local d=$((SECONDS+5))
  while [ $SECONDS -lt $d ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null; sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  for pf in "$TESTHOME/.local/state/wb-context-guard"/*.pid; do
    [ -f "$pf" ] || continue
    # NUR DIE ERSTE ZEILE (2026-09-18, gemessen): die Merkdatei traegt seit
    # `guard_register` zwei Zeilen -- PID und Startzeit des Prozesses. `cat`
    # lieferte beides, `kill "25457 1789746982"` schlug mit "illegal process id"
    # fehl, und weil der Fehler nach /dev/null ging, sah das Aufraeumen erfolgreich
    # aus. Jeder Lauf liess so eine Wache zurueck, die ihren eigenen tmux-Server
    # ueberlebt: ohne erreichbaren Server kann sie nicht feststellen, dass ihr Pane
    # weg ist, und pollt fuer immer weiter (zwei solche Waisen gefunden, 2,5 h und
    # 1 min alt).
    gp="$(head -1 "$pf" 2>/dev/null)"
    case "$gp" in [0-9]*) kill "$gp" 2>/dev/null; sleep 0.5
      kill -0 "$gp" 2>/dev/null && echo "WARNUNG: Guard $gp laeuft noch" >&2 ;;
    esac
  done
  case "$TESTHOME" in
    "${TMPDIR:-/tmp}"/rollengen.*) rm -rf "$TESTHOME" ;;
    *) echo "Aufraeumen uebersprungen: '$TESTHOME' unerwartet" >&2 ;;
  esac
}
trap cleanup EXIT

mkdir -p "$BIN" "$SHIM" "$TESTHOME/.claude/workbench" "$TESTHOME/.claude/roles" \
         "$TESTHOME/.local/state" "$TESTHOME/.pi-workers"
for w in wb-harness-run wb-state pi-worker context-guard wb-worktree wb-grid wb-workers-window wb-pane-write; do
  src="$REPO/$w"; [ -f "$src" ] || src="$REAL_BIN/$w"
  [ -f "$src" ] && cp "$src" "$BIN/$w"
done
chmod +x "$BIN"/* 2>/dev/null
printf 'ROLLENTEXT-WORKER-77\n' > "$TESTHOME/.claude/roles/agent.md"
printf 'ROLLENTEXT-ORCHESTRATOR-77\n' > "$TESTHOME/.claude/roles/orchestrator.md"

cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

# Die CLIs. 'projektcli' und 'geteiltcli' protokollieren beim Start, WAS in ihrer
# Anweisungsdatei steht — nur so ist belegt, dass sie den Text zum Startzeitpunkt trug.
# Die Attrappen lesen ZEICHENWEISE, weil nur so sichtbar wird, was eine echte TUI zeigt:
# der eingefuegte Text erscheint im Kasten und verschwindet mit dem Absenden. Zeilenweise
# ginge es nicht -- der letzte Einfuege-Abschnitt kommt ohne Zeilenende an, und `read`
# wuerde ihn erst mit dem Enter sehen, also beides in einem. Gemessen: das Terminal
# uebersetzt das Wagenrueck-Zeichen des Enters in ein Zeilenende, deshalb ist die leere
# Lesung das Absende-Signal.
cat > "$SHIM/projektcli" <<CLIEOF
#!/bin/bash
echo "projektcli in \$PWD liest:" >> "$CLILOG"
cat AGENTS.md >> "$CLILOG" 2>/dev/null || echo "(keine AGENTS.md)" >> "$CLILOG"
zeige() { printf '\\n\\n› %s\\n' "\$1"; }
zeige Vorschlag-DREIUNDVIERZIG
puffer=""
while IFS= read -r -n 1 c; do
  case "\$c" in
    '') puffer=""; zeige Vorschlag-DREIUNDVIERZIG ;;
    *) puffer="\$puffer\$c"; zeige "\$puffer" ;;
  esac
done
sleep 600
CLIEOF
cat > "$SHIM/geteiltcli" <<CLIEOF
#!/bin/sh
echo "geteiltcli liest:" >> "$CLILOG"
cat "\$HOME/.geteilt/AGENTS.md" >> "$CLILOG" 2>/dev/null || echo "(keine Datei)" >> "$CLILOG"
printf '\\n\\n› Vorschlag-DREIUNDVIERZIG\\n'
sleep 600
CLIEOF
# Diese Attrappe BEHAELT den eingefuegten Text, auch nach dem Absenden -- der echte
# Haengefall, den die Pruefung weiterhin erkennen muss.
cat > "$SHIM/haengtcli" <<CLIEOF
#!/bin/bash
zeige() { printf '\\n\\n› %s\\n' "\$1"; }
zeige Vorschlag-DREIUNDVIERZIG
puffer=""
while IFS= read -r -n 1 c; do
  case "\$c" in
    '') ;;
    *) puffer="\$puffer\$c"; zeige "\$puffer" ;;
  esac
done
sleep 600
CLIEOF
chmod +x "$SHIM/projektcli" "$SHIM/geteiltcli" "$SHIM/haengtcli"
: > "$CLILOG"

cat > "$REG" <<'REGEOF'
{
  "version": 1,
  "providers": [{"id": "p", "label": "p", "kind": "subscription"}],
  "harnesses": [
    {
      "id": "projekt", "label": "Projektweg", "command": "projektcli",
      "args": ["--model", "{model}"], "cwdMode": "cd",
      "readyPattern": "^›", "promptPattern": "^›", "promptIgnore": "^› Run /review",
      "systemPrompt": {"style": "file", "path": "~/.projekt/AGENTS.md",
                       "projectPath": "AGENTS.md",
                       "worker": "~/.claude/roles/agent.md",
                       "orchestrator": "~/.claude/roles/orchestrator.md"}
    },
    {
      "id": "geteilt", "label": "Geteilter Weg", "command": "geteiltcli",
      "args": ["--model", "{model}"], "cwdMode": "cd",
      "readyPattern": "^›", "promptPattern": "^›",
      "systemPrompt": {"style": "file", "path": "~/.geteilt/AGENTS.md",
                       "worker": "~/.claude/roles/agent.md",
                       "orchestrator": "~/.claude/roles/orchestrator.md"}
    },
    {
      "id": "haengt", "label": "Haengt absichtlich", "command": "haengtcli",
      "args": ["--model", "{model}"], "cwdMode": "cd",
      "readyPattern": "^›", "promptPattern": "^›", "promptIgnore": "^› Run /review",
      "systemPrompt": {"style": "none"}
    }
  ],
  "models": [
    {"id": "m-projekt", "label": "m", "harness": "projekt", "provider": "p",
     "modelRef": "mp", "roles": ["worker", "orchestrator"], "machines": ["mac", "host2"]},
    {"id": "m-geteilt", "label": "m", "harness": "geteilt", "provider": "p",
     "modelRef": "mg", "roles": ["worker", "orchestrator"], "machines": ["mac", "host2"]},
    {"id": "m-haengt", "label": "m", "harness": "haengt", "provider": "p",
     "modelRef": "mh", "roles": ["worker"], "machines": ["mac", "host2"]}
  ]
}
REGEOF

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"
HRUN="$BIN/wb-harness-run"

echo "== test-rollen-generator: Rolle je Spawn (Gestalt B) und Absendung ohne Wortlaut =="
echo "   Socket: $SOCKET   HOME: $TESTHOME"
echo

# ── A/D/E/F: der Generator, ohne tmux geprueft ────────────────────────────
echo "-- A: der Projektweg schreibt ins Arbeitsverzeichnis --"
WD1="$TESTHOME/arbeit1"; mkdir -p "$WD1"
: > "$CLILOG"
( cd "$WD1" && PATH="$SHIM:$BIN:$PATH" HOME="$TESTHOME" timeout 20 "$HRUN" \
  --model m-projekt --role worker --dir "$WD1" --name a1 >/dev/null 2>"$TESTHOME/a.err" ) &
# GEWARTET WIRD AUF DAS ERGEBNIS, NICHT AUF EINE GESCHAETZTE DAUER (2026-08-24,
# Auftrag "was bei zwanzig gleichzeitig passiert"). Hier stand `sleep 6`, und
# unter Last reichte das nicht: die Attrappen dieser Suite sind FRISCH
# GESCHRIEBENE ausfuehrbare Dateien, und macOS prueft jede davon beim ERSTEN
# Start einzeln durch (XprotectService, maschinenweit hintereinander, gemessen
# 100 bis 250 ms je Datei -- bei 24 gleichzeitigen ersten Starts wartete der
# langsamste 2,6 s). Bei 20 gleichzeitigen Suiten war die CLI nach sechs
# Sekunden noch nicht so weit, und Fall A meldete rot, obwohl an der Sache
# nichts falsch war. Das Warten endet jetzt, sobald das Ergebnis dasteht, und
# ein abgelaufenes Zeitlimit sagt laut, worauf es vergeblich gewartet hat.
warte_auf_bedingung 40 "A: die CLI liest die Rollendatei und legt sie im Arbeitsverzeichnis ab" \
  'grep -q ROLLENTEXT-WORKER-77 "$CLILOG" 2>/dev/null && [ -f "$WD1/AGENTS.md" ]' "$CLILOG"
kill %1 2>/dev/null; wait 2>/dev/null
grep -q 'ROLLENTEXT-WORKER-77' "$CLILOG" \
  && ok "A: die CLI hat die Rolle beim Start wirklich gelesen" \
  || bad "A: nichts gelesen: $(cat "$CLILOG")"
grep -q 'ROLLENTEXT-WORKER-77' "$WD1/AGENTS.md" 2>/dev/null \
  && ok "A: die Datei liegt im Arbeitsverzeichnis" || bad "A: keine Datei in $WD1"

echo
echo "-- D/E: fremder Inhalt bleibt, der eigene Block wird ersetzt --"
WD2="$TESTHOME/arbeit2"; mkdir -p "$WD2"
printf 'FREMDER-TEXT-BLEIBT\n' > "$WD2/AGENTS.md"
for i in 1 2; do
  ( cd "$WD2" && PATH="$SHIM:$BIN:$PATH" HOME="$TESTHOME" timeout 20 "$HRUN" \
    --model m-projekt --role worker --dir "$WD2" --name d1 >/dev/null 2>&1 ) &
  warte_auf_bedingung 40 "D/E: Durchgang $i hat seinen Block in AGENTS.md geschrieben" \
    '[ "$(grep -c "wb-rolle worker anfang" "$WD2/AGENTS.md" 2>/dev/null)" -ge 1 ]' "$WD2/AGENTS.md"
  kill %1 2>/dev/null; wait 2>/dev/null
done
grep -q 'FREMDER-TEXT-BLEIBT' "$WD2/AGENTS.md" \
  && ok "D: der fremde Text steht noch da" || bad "D: fremder Text weg: $(cat "$WD2/AGENTS.md")"
[ "$(grep -c 'wb-rolle worker anfang' "$WD2/AGENTS.md")" -eq 1 ] \
  && ok "E: nach zwei Starts steht der eigene Block genau einmal drin" \
  || bad "E: Block $(grep -c 'wb-rolle worker anfang' "$WD2/AGENTS.md")x vorhanden"

echo
echo "-- B: zwei Rollen, zwei Verzeichnisse, keine Stoerung --"
WD3="$TESTHOME/arbeit3"; WD4="$TESTHOME/arbeit4"; mkdir -p "$WD3" "$WD4"
( cd "$WD3" && PATH="$SHIM:$BIN:$PATH" HOME="$TESTHOME" timeout 20 "$HRUN" \
  --model m-projekt --role worker --dir "$WD3" --name b1 >/dev/null 2>&1 ) &
( cd "$WD4" && PATH="$SHIM:$BIN:$PATH" HOME="$TESTHOME" timeout 20 "$HRUN" \
  --model m-projekt --role orchestrator --dir "$WD4" --name b2 >/dev/null 2>&1 ) &
warte_auf_bedingung 40 "B: beide Spawns haben ihre Rolle geschrieben" \
  'grep -q ROLLENTEXT-WORKER-77 "$WD3/AGENTS.md" 2>/dev/null && grep -q ROLLENTEXT-ORCHESTRATOR-77 "$WD4/AGENTS.md" 2>/dev/null'
kill %1 %2 2>/dev/null; wait 2>/dev/null
grep -q 'ROLLENTEXT-WORKER-77' "$WD3/AGENTS.md" 2>/dev/null \
  && grep -q 'ROLLENTEXT-ORCHESTRATOR-77' "$WD4/AGENTS.md" 2>/dev/null \
  && ok "B: jeder hat seine eigene Rolle" \
  || bad "B: Rollen vertauscht oder fehlend"

echo
echo "-- C: geteiltes Ziel, zweite Rolle wird abgelehnt --"
: > "$CLILOG"
PATH="$SHIM:$BIN:$PATH" HOME="$TESTHOME" timeout 20 "$HRUN" \
  --model m-geteilt --role worker --dir "$TESTHOME" --name c1 >/dev/null 2>&1 &
warte_auf_bedingung 40 "C: der erste Start hat seine Rolle ins geteilte Ziel geschrieben" \
  'grep -q ROLLENTEXT-WORKER-77 "$TESTHOME/.geteilt/AGENTS.md" 2>/dev/null' "$CLILOG"
kill %1 2>/dev/null; wait 2>/dev/null
COUT="$(PATH="$SHIM:$BIN:$PATH" HOME="$TESTHOME" timeout 20 "$HRUN" \
        --model m-geteilt --role orchestrator --dir "$TESTHOME" --name c2 2>&1)"
CRC=$?
[ "$CRC" -ne 0 ] && ok "C: der zweite Start endet mit einem Fehler (rc=$CRC)" \
                 || bad "C: der zweite Start lief durch"
printf '%s' "$COUT" | grep -q 'wuerde sie ueberschreiben' \
  && ok "C: und sagt, dass er die fremde Rolle nicht ueberschreibt" \
  || bad "C: Meldung ohne Begruendung: $COUT"
grep -q 'ROLLENTEXT-WORKER-77' "$TESTHOME/.geteilt/AGENTS.md" \
  && ok "C: die Rolle des ersten steht unveraendert da" \
  || bad "C: die Datei traegt nicht mehr die erste Rolle"

echo
echo "-- F: die selbst angelegte Projektdatei wird lokal ausgeschlossen --"
WD5="$TESTHOME/arbeit5"; mkdir -p "$WD5"
( cd "$WD5" && git init -q . 2>/dev/null )
( cd "$WD5" && PATH="$SHIM:$BIN:$PATH" HOME="$TESTHOME" timeout 20 "$HRUN" \
  --model m-projekt --role worker --dir "$WD5" --name f1 >/dev/null 2>&1 ) &
warte_auf_bedingung 40 "F: der Spawn hat AGENTS.md angelegt und lokal ausgeschlossen" \
  '[ -f "$WD5/AGENTS.md" ] && grep -qx AGENTS.md "$WD5/.git/info/exclude" 2>/dev/null'
kill %1 2>/dev/null; wait 2>/dev/null
grep -qx 'AGENTS.md' "$WD5/.git/info/exclude" 2>/dev/null \
  && ok "F: AGENTS.md steht in .git/info/exclude" \
  || bad "F: kein Eintrag in .git/info/exclude"

# ── G: die Absende-Pruefung, beide Richtungen ─────────────────────────────
echo
echo "-- G: Absendung ohne Wortlaut --"
tm kill-server 2>/dev/null
tm new-session -d -s "wb-Rollen-$$" -c /tmp -x 200 -y 50
CTRL="$(tm list-panes -t "=wb-Rollen-$$" -F '#{pane_id}' | head -1)"
tm set -p -t "$CTRL" @wb_role orchestrator
tm set-option -wg remain-on-exit on
tmux_live_hooks_kappen "$SOCKET"   # gemeinsamer Baustein statt der drei Zeilen, siehe lib-testwerkzeuge.sh

lauf() {
  local f="$TESTHOME/out.$RANDOM$RANDOM"
  tm send-keys -t "$CTRL" \
    "{ export PATH='$PANE_PATH' HOME='$TESTHOME' WB_NO_DISCOVER=1; $1 ; } > $f 2>&1; echo \"RC=\$?\" >> $f; touch $f.done" Enter
  if warte_auf_datei "$f.done" 150 "lauf: $1" "$f"; then
    OUT="$(grep -v '^RC=' "$f" 2>/dev/null)"
    RC="$(sed -n 's/^RC=//p' "$f" 2>/dev/null | tail -1)"; RC="${RC:-99}"
  else
    OUT="(ZEITLIMIT -- siehe FAIL-Zeile oben)"; RC=124
  fi
  rm -f "$f" "$f.done"
}

# Der Platzhalter 'Vorschlag-DREIUNDVIERZIG' trifft promptIgnore ('^› Run /review')
# ABSICHTLICH nicht: mit der alten Pruefung waere dieser Fall ein Fehlschlag gewesen.
lauf "pi-worker g1 m-projekt /tmp 'Auftrag'"
printf '%s' "$OUT" | grep -q 'Submission verifiziert' \
  && ok "G: rotierender Platzhalter gilt als abgeschickt" \
  || bad "G: nicht als abgeschickt erkannt: $(printf '%s' "$OUT" | tail -3)"

lauf "pi-worker g2 m-haengt /tmp 'Auftrag'"
printf '%s' "$OUT" | grep -q 'Prompt haengt' \
  && ok "G: ein wirklich haengender Auftrag wird weiterhin als haengend gemeldet" \
  || bad "G: der Haengefall wurde nicht erkannt: $(printf '%s' "$OUT" | tail -3)"
[ "$RC" -ne 0 ] && ok "G: und der Spawn endet mit einem Fehler" \
                || bad "G: der Haengefall endete mit rc=$RC — $(printf '%s' "$OUT" | tr '\n' '|' | rev | cut -c1-260 | rev)"

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
