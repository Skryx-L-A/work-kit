#!/usr/bin/env bash
# test-a20-und-rollen.sh — die Registry ist ein Katalog, kein Tuersteher (A20),
# die Startsperren werden gemeinsam gemeldet, und aider bekommt seine Rolle je Spawn.
#
# Anlass (gemessen 2026-08-06):
#   * Ein claude-Modell, das nicht in der Registry stand, liess sich als Worker gar
#     nicht starten — obwohl der Plan in A20 genau das Gegenteil festgelegt hat.
#   * `wb-state models resolve gpt-5-codex` meldete "deaktiviert" und verschwieg, dass
#     ausserdem der Binary fehlt: wer den Namen falsch raet, sucht an der falschen Stelle.
#   * aider startete ohne jeden Rollen-Prompt, weil kein Weg dafuer eingetragen war.
#
# Geprueft wird:
#   A1  Ein UNBEKANNTES claude-Modell startet, und die CLI bekommt genau diesen Namen.
#   A2  Der Start sagt, dass es keine Empfehlung gibt und wo ein Fehler erst auftaucht.
#   B1  Ein unbekanntes Modell ist trotzdem gedeckelt: der Deckel kommt vom HARNESS,
#       und die Meldung sagt das auch.
#   B2  Unterhalb des Harness-Deckels startet dasselbe Modell.
#   C1  Ein abgeschaltetes Modell mit fehlendem Binary nennt BEIDE Gruende in einer Ausgabe.
#   D1  Die ausgelieferte Registry gibt aider seine Rollendatei per --read mit.
#
# Der Modellname 'claude-nichtregistriert-9' und die Effort-Karte des Pruef-Harness
# sind ERFUNDEN und standen vor diesem Lauf nirgends.
#
# SICHERHEIT: eigener Socket, eigenes HOME, eigene Registry. Aufgeraeumt wird nur, was
# der erwarteten Form entspricht — nie $HOME, nie ein fremder Pfad.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

SOCKET="wbtest-a20-$$"
TESTHOME="$(mktemp -d "${TMPDIR:-/tmp}/a20suite.XXXXXX")"

# Seit dem 06.08. geht jeder Tastendruck des Guards durch `wb-pane-write`, und das
# Werkzeug erkennt den Guard an der kanonischen Datei $HOME/.local/bin/context-guard.
# In einem Test-HOME liegt dort nichts -- also wird es dort hingelegt (Symlink auf den
# Arbeitsbaum, dieselbe Inode, also dieselbe Pruefung wie im Betrieb).
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"
werkzeuge_installieren "$TESTHOME" || { echo "Test-Werkzeuge liessen sich nicht installieren" >&2; exit 1; }
case "$TESTHOME" in
  "${TMPDIR:-/tmp}"/a20suite.*) ;;
  *) echo "FAIL  unerwartetes Testverzeichnis '$TESTHOME'"; exit 1 ;;
esac
BIN="$TESTHOME/.local/bin"; SHIM="$TESTHOME/.shim"
REG="$TESTHOME/.claude/workbench/models.json"
ARGVLOG="$TESTHOME/claude-argv.log"

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
  # pi-worker startet ueber `context-guard --ensure` einen Wachprozess, der NICHT im
  # Pane laeuft und einen kill-server ueberlebt. Seine PID steht in seinem Zustand
  # unter dem TEST-HOME; beendet wird gezielt diese, kein Muster.
  for pf in "$TESTHOME/.local/state/wb-context-guard"/*.pid; do
    [ -f "$pf" ] || continue
    # NUR DIE ERSTE ZEILE (2026-09-18, gemessen an test-rollen-generator.sh, gleiche
    # Stelle): die Merkdatei traegt PID UND Startzeit. `kill "<pid> <startzeit>"`
    # scheitert still, und die Wache ueberlebt den Lauf -- ohne erreichbaren
    # tmux-Server pollt sie danach fuer immer weiter.
    gp="$(head -1 "$pf" 2>/dev/null)"
    case "$gp" in [0-9]*) kill "$gp" 2>/dev/null; sleep 0.5
      kill -0 "$gp" 2>/dev/null && echo "WARNUNG: Guard $gp laeuft noch" >&2 ;;
    esac
  done
  case "$TESTHOME" in
    "${TMPDIR:-/tmp}"/a20suite.*) rm -rf "$TESTHOME" ;;
    *) echo "Aufraeumen uebersprungen: '$TESTHOME' unerwartet" >&2 ;;
  esac
}
trap cleanup EXIT

mkdir -p "$BIN" "$SHIM" "$TESTHOME/.claude/workbench" "$TESTHOME/.claude/roles" \
         "$TESTHOME/.local/state" "$TESTHOME/.pi-workers"
for w in pi-worker wb-state wb-harness-run wb-revive context-guard wb-worktree wb-grid \
         wb-workers-window wb-code; do
  src="$REPO/$w"; [ -f "$src" ] || src="$REAL_BIN/$w"
  [ -f "$src" ] && cp "$src" "$BIN/$w"
done
chmod +x "$BIN"/* 2>/dev/null
printf 'Pruef-Rolle Worker\n' > "$TESTHOME/.claude/roles/agent.md"
printf 'Pruef-Rolle Orchestrator\n' > "$TESTHOME/.claude/roles/orchestrator.md"

cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
cat > "$SHIM/claude" <<CLEOF
#!/bin/sh
echo "ARGV: \$*" >> "$ARGVLOG"
printf '\\n❯ \\n'
sleep 600
CLEOF
# Der eingebaute claude-Weg von pi-worker ruft ABSOLUT auf ($HOME/.local/bin/claude),
# nicht ueber den PATH -- die Attrappe muss deshalb auch dort liegen, sonst wartet die
# Bereitschaftspruefung 60 s auf einen Pane, in dem nie etwas gestartet ist (gemessen).
cp "$SHIM/claude" "$BIN/claude"
chmod +x "$SHIM/tmux" "$SHIM/claude" "$BIN/claude"
# Kit: a stand-in aider, so section D does not depend on an aider installed on the machine.
printf '#!/bin/sh\nexit 0\n' > "$SHIM/aider"; chmod +x "$SHIM/aider"
: > "$ARGVLOG"

# Der Pruef-Harness 'claude' nimmt low, medium, high und max — ABSICHTLICH mit einer
# Luecke bei 'xhigh'. Daran lassen sich die ZWEI Ablehnungen auseinanderhalten, die
# ein unbekanntes Modell treffen koennen, und das ist der Punkt dieses Abschnitts:
#
#   'xhigh' -> der HARNESS kennt die Stufe nicht (Pruefung 1, vor dem Deckel)
#   'max'   -> der Harness kennt sie, aber der Deckel eines unbekannten Modells ist
#              die hoechste Stufe UNTER max (A20, 2026-08-06) -> Harness-Deckel
#
# Bis zum 06.08. stand hier nur die erste Haelfte, und die Zusage darunter verlangte
# trotzdem das Wort "Harness-Deckel". Sie war gruen, solange pi-worker seinen eigenen
# Rangvergleich fuehrte; seit die Entscheidung allein in `wb-state models effort`
# faellt, greift bei 'xhigh' die frueher stehende Pruefung — richtig abgelehnt, nur
# aus einem anderen Grund als behauptet. Ein Test, der den falschen Grund festschreibt,
# haelt den richtigen fuer einen Fehler.
cat > "$REG" <<'REGEOF'
{
  "version": 1,
  "providers": [{"id": "claude-subscription", "label": "Abo", "kind": "subscription"}],
  "harnesses": [
    {
      "id": "claude", "label": "Pruef-Claude", "command": "claude",
      "args": ["--model", "{model}"], "cwdMode": "cd",
      "effort": {"style": "arg", "args": ["--effort", "{effort}"],
                 "map": {"low": "low", "medium": "medium", "high": "high", "max": "max"}},
      "readyPattern": "❯", "promptPattern": "^❯", "compactCommand": "/compact"
    }
  ],
  "models": [
    {"id": "claude-sonnet-5", "label": "Sonnet 5", "harness": "claude",
     "provider": "claude-subscription", "modelRef": "claude-sonnet-5",
     "roles": ["worker", "orchestrator"], "machines": ["mac", "host2"]},
    {"id": "abgeschaltet-und-fehlend", "label": "Beides zugleich", "harness": "fehlt",
     "provider": "claude-subscription", "modelRef": "x", "enabled": false,
     "notes": "Pruefgrund steht hier", "roles": ["worker"], "machines": ["mac", "host2"]}
  ]
}
REGEOF
/usr/bin/python3 - "$REG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["harnesses"].append({"id": "fehlt", "label": "Harness ohne Programm",
                       "command": "gibtesnichtcli", "args": ["--model", "{model}"],
                       "cwdMode": "cd", "readyPattern": "x", "promptPattern": "^x"})
json.dump(d, open(sys.argv[1], "w"), ensure_ascii=False, indent=2)
PY

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/usr/sbin:/sbin"

echo "== test-a20-und-rollen: Katalog statt Tuersteher, Sperren gemeinsam, Rolle je Spawn =="
echo "   Socket: $SOCKET   HOME: $TESTHOME"
echo

tm kill-server 2>/dev/null
# Die Testsession muss aussehen wie eine echte Workbench-Session: pi-worker splittet
# in das Fenster des ORCHESTRATORS und laesst sonst den Guard und die Bereitschaft ins
# Leere laufen (erst gemessen: "Session steuer hat keinen lebenden
# @wb_role=orchestrator-Pane", danach "Agent-TUI nicht bereit").
tm new-session -d -s "wb-A20test-$$" -c /tmp -x 200 -y 50
CTRL="$(tm list-panes -t "=wb-A20test-$$" -F '#{pane_id}' | head -1)"
tm set -p -t "$CTRL" @wb_role orchestrator
tm set-option -wg remain-on-exit on
tmux_live_hooks_kappen "$SOCKET"   # gemeinsamer Baustein statt der drei Zeilen, siehe lib-testwerkzeuge.sh

lauf() {   # lauf <kommando> -> OUT, RC
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

# ── A: ein unbekanntes claude-Modell startet ──────────────────────────────
echo "-- A: unbekanntes Modell startet trotzdem --"
: > "$ARGVLOG"
lauf "pi-worker w1 claude-nichtregistriert-9:high /tmp 'nichts tun'"
[ "$RC" -eq 0 ] && ok "A1: der Start wird nicht mehr abgelehnt (rc=0)" \
                || bad "A1: rc=$RC — $(printf '%s' "$OUT" | tr '\n' '|' | rev | cut -c1-320 | rev)"
grep -q -- '--model claude-nichtregistriert-9' "$ARGVLOG" \
  && ok "A1: die CLI bekommt genau diesen Namen" \
  || bad "A1: kein Aufruf mit dem Namen: $(cat "$ARGVLOG")"
printf '%s' "$OUT" | grep -q 'steht nicht in der Registry' \
  && ok "A2: der Start sagt, dass es keine Empfehlung gibt" \
  || bad "A2: kein Hinweis auf die fehlende Registrierung: $OUT"
printf '%s' "$OUT" | grep -q 'erste' \
  && ok "A2: und dass ein falscher Name erst IM Pane auffaellt" \
  || bad "A2: kein Hinweis auf den spaeten Fehler: $OUT"

# ── B: der Deckel kommt vom Harness ───────────────────────────────────────
echo
echo "-- B: unbekannt heisst nicht ungedeckelt --"
: > "$ARGVLOG"
lauf "pi-worker w2 claude-nichtregistriert-9:xhigh /tmp 'nichts tun'"
[ "$RC" -ne 0 ] && ok "B1: 'xhigh' wird abgelehnt (rc=$RC)" \
                || bad "B1: 'xhigh' lief durch, obwohl der Harness die Stufe nicht kennt"
printf '%s' "$OUT" | grep -q "nimmt effort 'xhigh' nicht an" \
  && ok "B1: und zwar mit dem richtigen Grund -- der Harness kennt die Stufe nicht" \
  || bad "B1: falscher oder fehlender Grund: $OUT"
grep -q -- '--effort xhigh' "$ARGVLOG" \
  && bad "B1: die CLI wurde trotz Ablehnung gestartet" \
  || ok "B1: es wurde nichts gestartet"
# Und der DECKEL, an der einzigen Stufe, an der er ein unbekanntes Modell ueberhaupt
# treffen kann: 'max' kennt dieser Harness, aber ein Modell ohne Registry-Eintrag
# bekommt die hoechste Stufe DARUNTER. Ohne diesen Fall bliebe der Deckel selbst
# ungeprueft -- die Zusage darueber misst die Stufenliste, nicht ihn.
: > "$ARGVLOG"
lauf "pi-worker w2b claude-nichtregistriert-9:max /tmp 'nichts tun'"
[ "$RC" -ne 0 ] && ok "B1b: 'max' wird abgelehnt (rc=$RC)" \
                || bad "B1b: 'max' lief durch -- ein unbekanntes Modell waere ungedeckelt"
printf '%s' "$OUT" | grep -q 'Harness-Deckel' \
  && ok "B1b: die Meldung nennt den Harness als Quelle des Deckels" \
  || bad "B1b: Meldung ohne Quelle: $OUT"
: > "$ARGVLOG"
lauf "pi-worker w3 claude-nichtregistriert-9:high /tmp 'nichts tun'"
grep -q -- '--effort high' "$ARGVLOG" \
  && ok "B2: unterhalb des Deckels startet dasselbe Modell" \
  || bad "B2: der erlaubte Start kam nicht durch: $(cat "$ARGVLOG")"

# ── C: Startsperren gemeinsam melden ──────────────────────────────────────
echo
echo "-- C: abgeschaltet UND Binary fehlt --"
AUS="$(PATH=/usr/bin:/bin HOME="$TESTHOME" "$BIN/wb-state" models resolve abgeschaltet-und-fehlend --role worker 2>&1)"
printf '%s' "$AUS" | grep -q 'abgeschaltet' \
  && ok "C1: der erste Grund steht da (abgeschaltet)" || bad "C1: kein 'abgeschaltet': $AUS"
printf '%s' "$AUS" | grep -q 'nicht installiert' \
  && ok "C1: der zweite Grund steht in DERSELBEN Ausgabe (Binary fehlt)" \
  || bad "C1: kein 'nicht installiert': $AUS"
printf '%s' "$AUS" | grep -q 'Pruefgrund steht hier' \
  && ok "C1: und der Grund aus dem notes-Feld wird mitgenannt" \
  || bad "C1: notes-Grund fehlt: $AUS"

# ── D: aider bekommt seine Rolle je Spawn ─────────────────────────────────
echo
echo "-- D: die AUSGELIEFERTE Registry gibt aider seine Rollendatei --"
D_HOME="$TESTHOME/ausgeliefert"
mkdir -p "$D_HOME/.claude/workbench" "$D_HOME/.claude/roles" "$D_HOME/.local"
cp "$REPO/models.default.json" "$D_HOME/.claude/workbench/models.json"
printf 'Rolle\n' > "$D_HOME/.claude/roles/agent.md"
ln -s "$REAL_BIN" "$D_HOME/.local/bin" 2>/dev/null
DAUS="$(PATH="$SHIM:$PATH" HOME="$D_HOME" "$BIN/wb-state" models resolve aider-qwen3.5-4b \
        --role worker --dir /tmp --name d1 2>&1 | grep '^cmd')"
printf '%s' "$DAUS" | grep -q -- '--read' \
  && ok "D1: die Startzeile traegt --read" || bad "D1: kein --read: $DAUS"
printf '%s' "$DAUS" | grep -q 'roles/agent.md' \
  && ok "D1: und zwar mit der Rollendatei des Workers" || bad "D1: keine Rollendatei: $DAUS"

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
