#!/usr/bin/env bash
# test-remote-control.sh — Orchestrator-Panes starten mit Remote Control, Worker-
# und Agent-Panes ohne (Vorgabe des Nutzers 2026-08-05).
#
# Die Rolle entscheidet, nicht die Aufrufstelle: wb-code haengt '--remote-control
# <name>' NUR im direkten Orchestrator-Zweig an den claude-Aufruf (der Zweig, der
# den eingebauten 'claude'-Harnisch baut); pi-worker (claude-worker/pi-worker) und
# wb-agent lassen '--remote-control' selbst ganz weg, tragen aber AKTIV
# '--settings {"remoteControlAtStartup": false}' auf der Befehlszeile.
#
# WIDERLEGT 2026-08-19 (Pruefer-Befund B9): hier stand bis dahin "kein
# Abschalt-Flag noetig, '--remote-control' ist ein reines Opt-in" -- das war
# FALSCH und ist an einem echten, eingeloggten claude-Prozess auf einem
# isolierten Testsocket widerlegt: 'claude --dangerously-skip-permissions'
# allein zeigt in der Fusszeile ein /rc mit Sitzungs-Link, obwohl kein
# '--remote-control' auf der Befehlszeile steht -- Auto-Verbinden greift
# ausserhalb der Einstellungsdateien (App-/IDE-Schalter). Der einzige Weg, der
# es zuverlaessig abschaltet, ist das explizite '--settings'-Flag; Schritt 4
# prueft deshalb dessen ANWESENHEIT, nicht nur die Abwesenheit von
# '--remote-control'. Ausserdem: der zentrale Registry-Resolver (wb-state
# cmd_resolve) traegt dieselbe Rollen-Entscheidung fuer den Fall, dass ein
# Modell mit harness='claude' je ueber wb-harness-run aufgeloest wird (heute
# unbenutzter, aber erreichbarer Pfad -- siehe Kommentar dort).
#
# Was hier NICHT geprueft wird: ob die echte claude-CLI daraufhin wirklich
# "/remote-control is active" anzeigt. Das ist reales CLI-Verhalten (vom Nutzer
# von Hand gemessen und in dieser Session an einem echten, eingeloggten claude-
# Prozess auf einem isolierten Testsocket nachvollzogen -- Ergebnisdatei dieser
# Session) und braucht ein eingeloggtes Konto samt Netz; das ist in einer
# automatisierten, unbeaufsichtigten Suite weder deterministisch noch angemessen
# (Kontonutzung, Netzabhaengigkeit). Was AUTOMATISIERT und deterministisch
# pruefbar ist -- und die eigentliche Aenderung dieses Auftrags ist -- ist die
# VERDRAHTUNG: bekommt der richtige Pane-Typ die Flagge, in der richtigen Form,
# und bleibt sie nach einem Absturz+Revive erhalten. Ein fake-'claude', der sein
# argv in eine Marke schreibt (wie test-revive.sh), macht das schnell und
# deterministisch.
#
# SELBSTTREFFER-SPERRE: keiner der folgenden Vergleiche darf auf den eigenen
# Quelltext oder die eigene Kommandozeile dieses Testskripts passen. Die Marke
# enthaelt NUR das argv des fake-claude-Prozesses (von claude selbst geschrieben,
# nicht von diesem Skript getippt); nirgends wird die Startzeile per 'echo' erst
# sichtbar in einen Pane getippt und dann zurueckgelesen, was den getippten
# Text mit dem zu suchenden Muster verwechseln wuerde.
#
# SICHERHEIT. Nichts hiervon beruehrt die Live-Umgebung:
#   * eigener tmux-Socket 'wbtest-remotectl-<pid>', ueber einen PATH-Schirm
#     erzwungen -- kein Aufruf kann 'default' erreichen, egal was ein Werkzeug
#     darunter selbst versucht.
#   * eigenes HOME (mktemp -d): Zustandsdateien, Registry-Overrides und Marken
#     entstehen ausschliesslich dort.
#   * fake-'claude' UND fake-'wb-harness-probe'-Binaries -- niemals der echte
#     Login-Zustand, niemals ein echter API-Aufruf.
#   * `trap` raeumt Server und Verzeichnis auf, auch bei Abbruch. Kein pkill.
unset TMUX TMUX_PANE
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/tests/lib-testwerkzeuge.sh"
REAL_BIN="${WB_BIN:-$HOME/.local/bin}"
TMUX_REAL="$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)"

SOCKET="wbtest-remotectl-$$"
TESTHOME="$(mktemp -d)"
BIN="$TESTHOME/.local/bin"
SHIM="$TESTHOME/.shim"

pass=0; fail=0
tm() { tmux -L "$SOCKET" "$@"; }
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCKET"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && tmux -L "$SOCKET" list-sessions >/dev/null 2>&1; do
    tmux -L "$SOCKET" kill-server 2>/dev/null
    sleep 0.3
  done
  tmux -L "$SOCKET" list-sessions >/dev/null 2>&1 \
    && echo "WARNUNG: tmux-Server auf Socket '$SOCKET' laeuft noch" >&2
  rm -f "/private/tmp/tmux-$(id -u)/$SOCKET" "/tmp/tmux-$(id -u)/$SOCKET"
  rm -rf "$TESTHOME"
}
trap cleanup EXIT

mkdir -p "$BIN" "$SHIM" "$TESTHOME/.local/state" "$TESTHOME/.claude/roles" "$TESTHOME/.claude/workbench"
for w in wb-code wb-state claude-worker pi-worker wb-agent wb-harness-run wb-worktree wb-grid wb-revive; do
  src="$REPO/$w"
  [ -x "$src" ] || src="$REAL_BIN/$w"
  [ -x "$src" ] || { echo "FAIL  $w fehlt (weder $REPO noch $REAL_BIN)"; exit 1; }
  cp "$src" "$BIN/$w"
done
chmod +x "$BIN"/*
: > "$TESTHOME/.claude/roles/orchestrator.md"
: > "$TESTHOME/.claude/roles/agent.md"

cat > "$SHIM/tmux" <<SHIMEOF
#!/bin/sh
exec "$TMUX_REAL" -L "$SOCKET" "\$@"
SHIMEOF
chmod +x "$SHIM/tmux"

# Fake-'claude': schreibt sein komplettes argv in eine Marke und zeigt danach
# eine Eingabezeile ('❯ ', dasselbe Muster wie readyPattern des echten
# claude-Harnisses) -- kein echter Login, kein echter API-Aufruf, kein Netz.
# Die Eingabezeile ist noetig, damit pi-worker (Schritt 3) seine
# Bereitschafts-Wartung ('$READY_RE' gegen den capture-pane-Inhalt) ueberhaupt
# durchlaesst -- ohne sie wartet pi-worker die vollen 60s und meldet
# "Agent-TUI nicht bereit", was in diesem Test wie ein FAIL aussaehe, obwohl es
# nur am fehlenden Fake-Prompt liegt.
MARKER="$TESTHOME/claude-argv.log"
cat > "$SHIM/claude" <<CLAUDEEOF
#!/bin/sh
echo "ARGV: \$*" >> "$MARKER"
while :; do printf '\\xe2\\x9d\\xaf '; IFS= read -r _line || sleep 1; done
CLAUDEEOF
chmod +x "$SHIM/claude"
# wb-state's binary_missing() checks the harness' 'command' at its EXPANDED
# absolute path (~/.local/bin/claude), not only via PATH -- the fake needs to
# exist there too, or 'models resolve' refuses the start (B17-Gate) before
# schritt 6 gets to see the built cmd line at all.
cp "$SHIM/claude" "$BIN/claude"
: > "$MARKER"

export HOME="$TESTHOME"
PANE_PATH="$SHIM:$BIN:/usr/bin:/bin:/sbin:/usr/sbin:/opt/homebrew/bin"
export WB_NO_DISCOVER=1

echo "== test-remote-control: Orchestrator an, Worker/Agent aus =="
echo "   Socket: $SOCKET   HOME: $TESTHOME   Repo-Stand: $REPO"
echo

tm kill-server 2>/dev/null

# ── 1: wb-code baut den Orchestrator-Pane MIT --remote-control ─────────────
echo "-- 1: wb-code (eingebauter claude-Harnisch, Orchestrator) --"
ODIR="$TESTHOME/orch"; mkdir -p "$ODIR"
# wb-code endet in 'exec tmux attach', was ohne Terminal fehlschlaegt -- Session
# und Pane samt Startbefehl stehen zu diesem Zeitpunkt aber schon (derselbe
# Kunstgriff wie in test-registry.sh, Abschnitt 10).
PATH="$PANE_PATH" HOME="$TESTHOME" "$BIN/wb-code" "$ODIR" --model claude-sonnet-5 --effort low \
  >"$TESTHOME/wbcode.out" 2>&1
OSESS="$(PATH="$PANE_PATH" HOME="$TESTHOME" "$BIN/wb-state" session "$ODIR" 2>/dev/null)"
if [ -z "$OSESS" ]; then
  bad "1: Testaufbau -- wb-code hat keine Session angelegt ($(cat "$TESTHOME/wbcode.out"))"
else
  OLINE="$(tm list-panes -t "=$OSESS" -F '#{pane_start_command}' 2>/dev/null | head -1)"
  case "$OLINE" in
    *"--remote-control "*) ok "1: der Orchestrator-Startbefehl traegt --remote-control" ;;
    *) bad "1: --remote-control fehlt im Orchestrator-Startbefehl: $OLINE" ;;
  esac
  case "$OLINE" in
    *"--remote-control $OSESS"*) ok "1: der Name ist der (projektbezogene) Session-Name ($OSESS)" ;;
    *) bad "1: erwarteter Name '$OSESS' fehlt im Startbefehl: $OLINE" ;;
  esac
  if warte_auf_bedingung 15 "1: fake-claude schreibt sein argv" '[ -s "$MARKER" ]' "$MARKER"; then
    case "$(tail -1 "$MARKER" 2>/dev/null)" in
      *"--remote-control "*) ok "1: der fake-claude-Prozess hat die Flagge wirklich im argv (nicht nur im pane_start_command)" ;;
      *) bad "1: --remote-control kam nicht im Prozess-argv an: $(tail -1 "$MARKER" 2>/dev/null)" ;;
    esac
  fi
fi

# ── 2: --name schlaegt den Session-Namen ────────────────────────────────────
echo
echo "-- 2: wb-code --name gewinnt gegen den Session-Namen --"
: > "$MARKER"
ODIR2="$TESTHOME/orch-named"; mkdir -p "$ODIR2"
PATH="$PANE_PATH" HOME="$TESTHOME" "$BIN/wb-code" "$ODIR2" --model claude-sonnet-5 --effort low --name mein-projekt \
  >"$TESTHOME/wbcode2.out" 2>&1
if warte_auf_bedingung 15 "2: fake-claude schreibt sein argv" '[ -s "$MARKER" ]' "$MARKER"; then
  case "$(tail -1 "$MARKER" 2>/dev/null)" in
    *"--remote-control mein-projekt"*) ok "2: --name 'mein-projekt' wird als Remote-Control-Name benutzt" ;;
    *) bad "2: --name kam nicht als Remote-Control-Name an: $(tail -1 "$MARKER" 2>/dev/null)" ;;
  esac
fi

# Beide folgenden Schritte tippen ihr Startkommando ueber eine Datei ein
# ('bash <kurzer Pfad>'), nicht als eine einzige lange Zeile direkt in
# send-keys: eine Zeile mit mehreren vollen TESTHOME-Pfaden (PATH, HOME,
# Zielverzeichnis, Ausgabeumleitung) wird bei ~700+ Zeichen mitten im Tippen
# abgeschnitten (gemessen 2026-08-05, tmux send-keys/das Pane-PTY hat dafuer
# ein Limit) -- der Pane blieb dann auf einer nie abgeschickten Eingabezeile
# stehen, ohne jede Fehlermeldung.

# ── 3: claude-worker/pi-worker (Worker) bleiben OHNE --remote-control ──────
echo
echo "-- 3: claude-worker (Worker-Pane) bleibt ohne --remote-control --"
: > "$MARKER"
WDIR="$TESTHOME/work"; mkdir -p "$WDIR"
tm new-session -d -s wsteuer -c /tmp -x 100 -y 30
CTRL="$(tm list-panes -t wsteuer -F '#{pane_id}' | head -1)"
tm set -p -t "$CTRL" @wb_role orchestrator
cat > "$TESTHOME/run-worker.sh" <<RUNEOF
export PATH='$PANE_PATH'
export HOME='$TESTHOME'
export WB_NO_DISCOVER=1
'$BIN/claude-worker' wtest sonnet5:low '$WDIR' 'testauftrag' > '$TESTHOME/claudeworker.out' 2>&1
touch '$TESTHOME/claudeworker.done'
RUNEOF
tm send-keys -t "$CTRL" "bash '$TESTHOME/run-worker.sh'" Enter
if warte_auf_datei "$TESTHOME/claudeworker.done" 30 "3: claude-worker" "$TESTHOME/claudeworker.out"; then
  warte_auf_bedingung 15 "3: fake-claude schreibt sein argv" '[ -s "$MARKER" ]' "$MARKER" || true
  ARGV="$(tail -1 "$MARKER" 2>/dev/null)"
  case "$ARGV" in
    ARGV:\ *--model\ *) ok "3: der Worker-Pane ist wirklich gestartet (argv vorhanden: $ARGV)" ;;
    *) bad "3: Testaufbau -- kein claude-argv aufgezeichnet ($(cat "$TESTHOME/claudeworker.out" 2>/dev/null))" ;;
  esac
  case "$ARGV" in
    *"remote-control"*) bad "3: --remote-control ist im Worker-argv gelandet: $ARGV" ;;
    *) ok "3: --remote-control fehlt im Worker-argv -- wie vorgesehen" ;;
  esac
fi

# ── 4: wb-agent (Agent-Pane) bleibt ebenfalls ohne --remote-control ────────
echo
echo "-- 4: wb-agent (Agent-Pane) bleibt ohne --remote-control --"
: > "$MARKER"
tm new-session -d -s asteuer -c /tmp -x 100 -y 30
ACTRL="$(tm list-panes -t asteuer -F '#{pane_id}' | head -1)"
tm set -p -t "$ACTRL" @wb_role orchestrator
cat > "$TESTHOME/run-agent.sh" <<RUNEOF
export PATH='$PANE_PATH'
export HOME='$TESTHOME'
export TMUX='dummy,x,0'
'$BIN/wb-agent' > '$TESTHOME/wbagent.out' 2>&1
touch '$TESTHOME/wbagent.done'
RUNEOF
tm send-keys -t "$ACTRL" "bash '$TESTHOME/run-agent.sh'" Enter
warte_auf_datei "$TESTHOME/wbagent.done" 15 "4: wb-agent" "$TESTHOME/wbagent.out" || true
warte_auf_bedingung 15 "4: fake-claude schreibt sein argv" '[ -s "$MARKER" ]' "$MARKER" || true
ARGV="$(tail -1 "$MARKER" 2>/dev/null)"
case "$ARGV" in
  "ARGV: "*) ok "4: der Agent-Pane ist wirklich gestartet (argv vorhanden: $ARGV)" ;;
  *) bad "4: Testaufbau -- kein claude-argv aufgezeichnet ($(cat "$TESTHOME/wbagent.out" 2>/dev/null))" ;;
esac
case "$ARGV" in
  *"remote-control"*) bad "4: --remote-control ist im Agent-argv gelandet: $ARGV" ;;
  *) ok "4: --remote-control fehlt im Agent-argv -- wie vorgesehen" ;;
esac
# Befund B9 (Pruefer, 2026-08-19): das reichte NICHT -- '--remote-control'
# weglassen schaltet Auto-Verbinden nicht ab. Ohne diese Pruefung waere der
# Test auch dann gruen, wenn wb-agent das '--settings'-Flag nie bekommen
# haette (er prueft dann nur weiterhin die Abwesenheit von etwas, das ohnehin
# nie da war).
case "$ARGV" in
  *'--settings {"remoteControlAtStartup": false}'*) ok "4: --settings {\"remoteControlAtStartup\": false} ist im Agent-argv (B9-Fix)" ;;
  *) bad "4: --settings {\"remoteControlAtStartup\": false} fehlt im Agent-argv: $ARGV" ;;
esac

# ── 5: der Wiederbelebungsfall -- Remote Control ueberlebt einen Absturz ───
# wb-revive/wb-autorevive lesen ausschliesslich das persistierte @wb_cmd und
# haengen '--continue' an den ersten 'claude '-Treffer -- beide brauchen also
# KEINE eigene Remote-Control-Logik, WENN @wb_cmd sie schon traegt (von wb-code
# gesetzt, s.o.). Dieser Fall ist der, der in der Praxis wehtut: ein
# abgestuerzter Orchestrator darf seine Fernsteuerung nicht verlieren.
echo
echo "-- 5: Absturz + wb-revive -- der Orchestrator behaelt --remote-control --"
if [ -z "${OSESS:-}" ]; then
  bad "5: Testaufbau aus Schritt 1 fehlt -- uebersprungen"
else
  OPANE="$(tm list-panes -t "=$OSESS" -F '#{pane_id}' | head -1)"
  tm set -p -t "$OPANE" remain-on-exit on
  tm send-keys -t "$OPANE" C-c ""
  tm kill-process -t "$OPANE" 2>/dev/null || tm send-keys -t "$OPANE" C-c "" \; send-keys -t "$OPANE" "exit" Enter
  # Der fake-claude reagiert nicht auf SIGINT (Endlosschleife) -- direkt den
  # Prozess beenden, das ist exakt der Fall, den wb-revive abfaengt (OOM/Kill).
  OPID="$(tm display -p -t "$OPANE" '#{pane_pid}' 2>/dev/null)"
  [ -n "$OPID" ] && kill -9 "$OPID" 2>/dev/null
  if warte_auf_bedingung 10 "5: Orchestrator-Pane als tot markiert" \
       '[ "$(tm display -p -t "$OPANE" "#{pane_dead}" 2>/dev/null)" = "1" ]'; then
    : > "$MARKER"
    PATH="$PANE_PATH" HOME="$TESTHOME" "$BIN/wb-revive" "$OPANE" >"$TESTHOME/wbrevive.out" 2>&1
    RRC=$?
    if warte_auf_bedingung 15 "5: fake-claude schreibt sein argv nach Revive" '[ -s "$MARKER" ]' "$MARKER"; then
      ok "5: fake-claude hat sein argv nach dem Revive protokolliert"
    else
      bad "5: fake-claude hat nach dem Revive kein argv protokolliert"
    fi
    [ "$RRC" -eq 0 ] && ok "5: wb-revive meldet Erfolg (rc=0)" || bad "5: wb-revive rc=$RRC ($(cat "$TESTHOME/wbrevive.out"))"
    NEWARGV="$(tail -1 "$MARKER" 2>/dev/null)"
    case "$NEWARGV" in
      *"--remote-control $OSESS"*) ok "5: der wiederbelebte Orchestrator traegt --remote-control weiterhin ($NEWARGV)" ;;
      *) bad "5: --remote-control fehlt nach dem Revive: $NEWARGV" ;;
    esac
    case "$NEWARGV" in
      *"--continue"*) ok "5: der Revive haengt --continue an (die eigentliche Aufgabe von wb-revive)" ;;
      *) bad "5: --continue fehlt nach dem Revive: $NEWARGV" ;;
    esac
  fi
fi

# ── 6: der zentrale Registry-Resolver traegt dieselbe Regel ────────────────
# Verteidigung in der Tiefe (siehe Kommentar in wb-state): im heutigen
# Aufrufgraphen erreicht harness='claude' diesen Zweig nie (wb-code und
# pi-worker bauen den eingebauten claude-Aufruf direkt selbst), aber `models
# resolve` ist die einzige Stelle, die ein REGISTRIERTES harness='claude' je
# aufloesen wuerde -- die Rolle muss auch dort stimmen.
echo
echo "-- 6: wb-state models resolve (zentraler Registry-Pfad) --"
# 'models resolve' kennt nur, was in models.json REGISTRIERT ist -- ohne diese
# Datei ist MODELS leer und jede Aufloesung scheitert an "nicht registriert",
# egal wie der eingebaute claude-Harnisch aussieht (derselbe Aufbau wie in
# test-registry.sh vor dessen Registry-Abschnitten).
cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"
OUT_O="$(PATH="$PANE_PATH" HOME="$TESTHOME" "$BIN/wb-state" models resolve claude-sonnet-5 --role orchestrator --dir "$TESTHOME/x" --name resolvtest 2>&1)"
case "$OUT_O" in
  *$'\t'*"--remote-control"*"resolvtest"*) ok "6: resolve haengt fuer role=orchestrator --remote-control resolvtest an" ;;
  *) bad "6: --remote-control fehlt im resolve-Ergebnis fuer role=orchestrator: $(printf '%s' "$OUT_O" | grep '^cmd')" ;;
esac
OUT_W="$(PATH="$PANE_PATH" HOME="$TESTHOME" "$BIN/wb-state" models resolve claude-sonnet-5 --role worker --dir "$TESTHOME/x" --name resolvtest 2>&1)"
case "$OUT_W" in
  *"remote-control"*) bad "6: --remote-control ist fuer role=worker im resolve-Ergebnis gelandet: $(printf '%s' "$OUT_W" | grep '^cmd')" ;;
  *) ok "6: --remote-control fehlt fuer role=worker -- wie vorgesehen" ;;
esac

echo
echo "== Ergebnis: $pass ok, $fail FAIL =="
[ "$fail" -eq 0 ]
