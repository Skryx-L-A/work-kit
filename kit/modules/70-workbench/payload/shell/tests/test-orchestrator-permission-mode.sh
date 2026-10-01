#!/bin/bash
# test-orchestrator-permission-mode.sh -- die vierte Sicherung: der
# Berechtigungsmodus, mit dem der Orchestrator selbst startet (2026-08-16,
# Anweisung des Nutzers: "sessions ab jetzt immer so starten").
#
# Gemessen: 'claude --help' kennt --permission-mode mit genau den sechs Werten
# acceptEdits, auto, bypassPermissions, manual, dontAsk, plan --
# --allow-dangerously-skip-permissions macht 'bypassPermissions' zur Laufzeit
# im /config-Menue erst waehlbar. Zwei Stellen tragen die Zusage:
#   shell/wb-state   orchestratorPermissionMode (DEFAULTS+ENUM), und die
#                    Auflage "SENKEN darf jeder, ANHEBEN auf bypassPermissions
#                    nur ein gemessener Mensch mit --grund" -- dieselbe
#                    Bauform wie effort-cap/guard/wache (siehe
#                    test-mensch-und-schalter.sh).
#   shell/wb-code    haengt --permission-mode (und bei bypassPermissions
#                    zusaetzlich --allow-dangerously-skip-permissions) an die
#                    Startzeile des claude-Orchestrator-Zweigs an. Eine kaputte
#                    oder unlesbare settings.json haengt KEIN Flag an.
#
# ISOLATION (Regeln 2026-07-25): eigener tmux-Server (Socket mit PID), eigenes
# HOME (mktemp -d), `unset TMUX TMUX_PANE` zuerst. Die echte
# ~/.claude/workbench/settings.json wird nie gelesen oder geschrieben.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

SOCK="wbtest-permmode-$$"
SESSBASE="wb-permmodetest-$$"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"      # …/claude-workbench/shell
MARKE="marke$$$(date +%s)"
PASS=0; FAIL=0

echo "Geprueft: Repo-Stand aus $REPO"
echo "Erkennungsmerkmal dieses Laufs: $MARKE"

TESTHOME="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-permmode-test.XXXXXX")" && pwd)"
export HOME="$TESTHOME"
export WB_NO_DISCOVER=1 WB_NO_RESUME=1
AUFBAU_BELEG="$(test_aufbau_beleg_anlegen "$TESTHOME")" || exit 1
BIN="$TESTHOME/.local/bin"
mkdir -p "$BIN" "$TESTHOME/.claude/workbench" "$TESTHOME/.claude/roles" "$TESTHOME/work"
export TMPDIR="$TESTHOME/tmp/"; mkdir -p "$TMPDIR"

# Der ECHTE tmux, absoluter Pfad -- VOR dem Umbiegen der PATH gemessen. Ein
# Wrapper, der 'tmux' ueber die PATH aufruft, NACHDEM diese PATH schon den
# Wrapper selbst enthaelt, ruft sich endlos selbst auf (gemessen 2026-08-06 in
# test-mensch-und-schalter.sh, hier wiederholt gemessen beim ersten Anlauf
# dieses Skripts: derselbe Fehler, derselbe Befund).
REALTMUX="$(command -v tmux)"
[ -x "$REALTMUX" ] || { echo "tmux nicht gefunden — Test kann nicht laufen." >&2; exit 1; }
T() { "$REALTMUX" -L "$SOCK" "$@"; }

cleanup() {
  tmux_socket_beenden_ohne_reste "$SOCK"
  local deadline=$((SECONDS + 5))
  while [ $SECONDS -lt $deadline ] && T ls >/dev/null 2>&1; do
    T kill-server 2>/dev/null || true
    sleep 0.3
  done
  if T ls >/dev/null 2>&1; then
    echo "WARNUNG: tmux-Server auf Socket '$SOCK' laeuft noch: tmux -L $SOCK ls" >&2
  fi
  rm -f "/private/tmp/tmux-$(id -u)/$SOCK"
  case "$TESTHOME" in
    /tmp/wb-permmode-test.*|/private/tmp/wb-permmode-test.*|/var/folders/*/wb-permmode-test.*)
      rm -rf "$TESTHOME" ;;
    *)
      echo "WARNUNG: TESTHOME='$TESTHOME' sieht nicht nach einem Testverzeichnis aus — NICHT geloescht." >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
nok()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

for f in wb-state wb-mensch wb-code; do
  cp "$REPO/$f" "$BIN/$f"; chmod +x "$BIN/$f"
done
cat > "$BIN/tmux" <<EOF
#!/bin/bash
exec "$REALTMUX" -L $SOCK "\$@"
EOF
chmod +x "$BIN/tmux"
# Eine ROLLENDATEI, damit der claude-Zweig sein '--append-system-prompt' ohne
# Fehlermeldung fuellen kann; der Inhalt spielt fuer diesen Test keine Rolle.
printf 'Testrolle %s\n' "$MARKE" > "$TESTHOME/.claude/roles/orchestrator.md"
# Ein FAKE 'claude', das laenger lebt als der Test braucht: das ECHTE Binary
# fehlt im Test-BIN, und ohne ein ueberlebendes Kommando toetet tmux die
# einzige Pane sofort wieder (remain-on-exit wird erst NACH new-session
# gesetzt) -- die Session waere beim Nachsehen schon wieder weg.
cat > "$BIN/claude" <<'EOF'
#!/bin/bash
sleep 60
EOF
chmod +x "$BIN/claude"
export PATH="$BIN:$PATH"

# ── Ein Pane, der als AGENT markiert ist (fuer im_pane) ─────────────────────
T new-session -d -s "$SESSBASE" -x 200 -y 50 "sleep 600"
sleep 0.5
ORCHPANE=$(T list-panes -t "=$SESSBASE" -F '#{pane_id}' | head -1)
T set -p -t "$ORCHPANE" @wb_role orchestrator

# im_pane <als-agent|als-mensch|als-agent-belegt|als-mensch-belegt>
#         <kommando…> -> Ausgabe auf stdout, Exitcode
# ueber RC(). Wortgleiche Bauart wie test-mensch-und-schalter.sh (dort
# gemessen und begruendet, hier nur uebernommen, nicht neu erfunden).
RC() { cat "$TESTHOME/letzter.rc" 2>/dev/null || echo 99; }
im_pane() {
  local art="$1"; shift
  local basis skript aus rc pane los
  basis="$TESTHOME/cmd.$RANDOM$RANDOM"
  skript="$basis.sh"; aus="$basis.out"; rc="$basis.rc"; los="$basis.los"
  rm -f "$skript" "$aus" "$rc" "$los"
  {
    printf '#!/bin/bash\n'
    printf 'while [ ! -e %q ]; do sleep 0.05; done\n' "$los"
    printf 'unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SESSION_ID CLAUDE_CODE_EXECPATH CLAUDE_PID\n'
    printf 'export HOME=%q\nexport PATH=%q\nexport TMPDIR=%q\n' "$TESTHOME" "$PATH" "$TMPDIR"
    case "$art" in
      *-belegt) printf 'export WB_TEST_AUFBAU_BELEG=%q\n' "$AUFBAU_BELEG" ;;
      *) printf 'unset WB_TEST_AUFBAU_BELEG\n' ;;
    esac
    printf '%s > %q 2>&1\n' "$*" "$aus"
    printf 'echo $? > %q\n' "$rc"
  } > "$skript"
  chmod +x "$skript"
  pane=$(T new-window -d -t "=$SESSBASE:" -P -F '#{pane_id}' "bash $skript")
  case "$art" in als-agent|als-agent-belegt) T set -p -t "$pane" @wb_role worker ;; esac
  : > "$los"
  local d=$((SECONDS + 25))
  while [ ! -s "$rc" ] && [ $SECONDS -lt $d ]; do sleep 0.2; done
  T kill-pane -t "$pane" 2>/dev/null || true
  cat "$rc" 2>/dev/null > "$TESTHOME/letzter.rc" || echo 99 > "$TESTHOME/letzter.rc"
  [ -s "$TESTHOME/letzter.rc" ] || echo 99 > "$TESTHOME/letzter.rc"
  cat "$aus" 2>/dev/null
}

echo
echo "=== 1. wb-state settings set orchestratorPermissionMode: die Auflage ========="

AUS=$(wb-state settings get orchestratorPermissionMode 2>&1)
if [ "$AUS" = "bypassPermissions" ]; then
  ok "Vorgabe (frisches HOME, keine settings.json): bypassPermissions"
else
  nok "Vorgabe: bypassPermissions" "$AUS"
fi

# (d) SENKEN darf jeder -- auch ein Agent, ohne Grund.
AUS=$(im_pane als-agent "wb-state settings set orchestratorPermissionMode plan"); RC=$(RC)
if [ "$RC" = 0 ]; then ok "(d) SENKEN (bypassPermissions -> plan) verlangt keinen Menschen"
else nok "(d) SENKEN verlangt keinen Menschen" "rc=$RC $AUS"; fi
AUS=$(wb-state settings get orchestratorPermissionMode 2>&1)
[ "$AUS" = plan ] && ok "... und die Senkung ist wirklich gespeichert (plan)" \
  || nok "Senkung gespeichert" "$AUS"

# Ein anderer gesenkter Wert -> ein anderer gesenkter Wert ist ebenfalls KEIN
# Anheben (beide unterhalb von bypassPermissions) und geht ohne Grund/Mensch.
AUS=$(im_pane als-agent "wb-state settings set orchestratorPermissionMode manual"); RC=$(RC)
if [ "$RC" = 0 ]; then ok "Wechsel zwischen zwei gesenkten Werten (plan -> manual) braucht ebenfalls keinen Menschen"
else nok "Wechsel zwischen zwei gesenkten Werten" "rc=$RC $AUS"; fi

# (c) ANHEBEN auf bypassPermissions aus einem Agenten-Pane wird abgewiesen --
# selbst MIT --grund und mit gueltigem Runner-Beleg. Der Beleg ersetzt nie die
# Menschenmessung.
AUS=$(im_pane als-agent-belegt "wb-state settings set orchestratorPermissionMode bypassPermissions --grund 'zurueck $MARKE'"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -Eq "nur ein MENSCH|echten Benutzer-Home"; then
  ok "(c) ANHEBEN auf bypassPermissions aus einem Pane heraus scheitert, trotz --grund"
else
  nok "(c) ANHEBEN aus einem Pane heraus scheitert" "rc=$RC $AUS"
fi
AUS=$(wb-state settings get orchestratorPermissionMode 2>&1)
[ "$AUS" = manual ] && ok "... und der Wert blieb unveraendert (manual)" \
  || nok "Wert blieb unveraendert" "$AUS"

# Ein umgebogenes HOME darf weder sein eigenes Pruefprogramm noch eine per
# AWB_SETTINGS_FILE eingeschmuggelte Zieldatei als Beleg fuer die Lockerung
# verwenden. Der Override ist nur Testinfrastruktur und hebt den Deckel nie an.
FAKEHOME="$TESTHOME/falsches-home"
mkdir -p "$FAKEHOME/.local/bin"
printf '#!/bin/sh\nexit 0\n' > "$FAKEHOME/.local/bin/wb-mensch"
chmod +x "$FAKEHOME/.local/bin/wb-mensch"
AUS=$(env HOME="$FAKEHOME" AWB_SETTINGS_FILE="$TESTHOME/.claude/workbench/settings.json" \
  "$BIN/wb-state" settings set orchestratorPermissionMode bypassPermissions \
  --grund "gefälschter Beleg $MARKE" 2>&1); RC=$?
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -Eq "nur ein MENSCH|WB_TEST_AUFBAU_BELEG"; then
  ok "umgebogenes HOME plus AWB_SETTINGS_FILE hebt den Deckel nicht an"
else
  nok "HOME-/Settings-Override bleibt fail-closed" "rc=$RC $AUS"
fi
AUS=$(wb-state settings get orchestratorPermissionMode 2>&1)
[ "$AUS" = manual ] && ok "... und die echte Testkonfiguration blieb unveraendert (manual)" \
  || nok "Override hat die Zieldatei nicht veraendert" "$AUS"

# Anheben als MENSCH, aber OHNE --grund: ebenfalls abgewiesen (Reihenfolge:
# der Grund wird zuerst verlangt, wie bei effort-cap/guard).
AUS=$(im_pane als-mensch "wb-state settings set orchestratorPermissionMode bypassPermissions"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -qi "grund"; then
  ok "Anheben als Mensch OHNE --grund wird ebenfalls abgewiesen"
else
  nok "Anheben als Mensch ohne --grund wird abgewiesen" "rc=$RC $AUS"
fi

# Auch ein echter Mensch im privaten Test-HOME braucht den Runner-Beleg.
AUS=$(im_pane als-mensch "wb-state settings set orchestratorPermissionMode bypassPermissions --grund 'zurueck $MARKE'"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "WB_TEST_AUFBAU_BELEG"; then
  ok "Anheben aus isolierter HOME bleibt ohne Runner-Beleg gesperrt"
else
  nok "Isolierte HOME ohne Beleg kann den Deckel nicht anheben" "rc=$RC $AUS"
fi
AUS=$(wb-state settings get orchestratorPermissionMode 2>&1)
[ "$AUS" = manual ] && ok "... und der Wert blieb unveraendert (manual)" \
  || nok "Wert blieb nach isoliertem Anheben unveraendert" "$AUS"

# Derselbe reale Menschenweg MIT privatem Runner-Beleg darf die isolierte
# Standard-Settingsdatei anheben.
AUS=$(im_pane als-mensch-belegt "wb-state settings set orchestratorPermissionMode bypassPermissions --grund 'zurueck $MARKE'"); RC=$(RC)
if [ "$RC" = 0 ]; then
  ok "Anheben als gemessener Mensch MIT gueltigem Runner-Beleg kommt an"
else
  nok "Belegter Menschenweg hebt im Test-HOME an" "rc=$RC $AUS"
fi
AUS=$(wb-state settings get orchestratorPermissionMode 2>&1)
[ "$AUS" = bypassPermissions ] && ok "... und bypassPermissions ist wirklich gespeichert" \
  || nok "Belegtes Anheben gespeichert" "$AUS"

# Wieder senken, damit die Negativfaelle erneut eine echte Erhoehung pruefen.
im_pane als-agent "wb-state settings set orchestratorPermissionMode manual" >/dev/null
BAD_BELEG="$TESTHOME/.wb-test-aufbau-falscher-modus"
cp "$AUFBAU_BELEG" "$BAD_BELEG"; chmod 0644 "$BAD_BELEG"
AUS=$(im_pane als-mensch-belegt "WB_TEST_AUFBAU_BELEG='$BAD_BELEG' wb-state settings set orchestratorPermissionMode bypassPermissions --grund 'modus $MARKE'"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "Modus 0600"; then
  ok "Aufbau-Beleg mit falschem Modus wird abgelehnt"
else
  nok "Falscher Belegmodus bleibt fail-closed" "rc=$RC $AUS"
fi

AUSSEN_BELEG="$TESTHOME/../wb-permmode-beleg-aussen-$MARKE"
cp "$AUFBAU_BELEG" "$AUSSEN_BELEG"; chmod 0600 "$AUSSEN_BELEG"
AUS=$(im_pane als-mensch-belegt "WB_TEST_AUFBAU_BELEG='$AUSSEN_BELEG' wb-state settings set orchestratorPermissionMode bypassPermissions --grund 'pfad $MARKE'"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "unter dem Prozess-HOME"; then
  ok "Aufbau-Beleg ausserhalb des privaten HOME wird abgelehnt"
else
  nok "Beleg ausserhalb HOME bleibt fail-closed" "rc=$RC $AUS"
fi
rm -f "$AUSSEN_BELEG"

# Ein unsinniger Wert wird unabhaengig von Mensch/Grund abgelehnt (dieselbe
# Formpruefung wie orchestratorEffort/workerEffort).
AUS=$(im_pane als-mensch "wb-state settings set orchestratorPermissionMode quatsch --grund 'x'"); RC=$(RC)
if [ "$RC" != 0 ] && printf '%s' "$AUS" | grep -q "kennt nur"; then
  ok "Ein unbekannter Wert wird abgelehnt, mit der Liste der sechs gueltigen"
else
  nok "Unbekannter Wert wird abgelehnt" "rc=$RC $AUS"
fi

# Der Testtreiber stellt den bereits geltenden Wert direkt her. Erneutes
# explizites Setzen desselben Werts ist kein Anheben und braucht daher keinen
# Herkunftsbeleg.
/usr/bin/python3 - "$TESTHOME/.claude/workbench/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
data["orchestratorPermissionMode"] = "bypassPermissions"
with open(p, "w") as f:
    json.dump(data, f)
PY
AUS=$(im_pane als-agent "wb-state settings set orchestratorPermissionMode bypassPermissions --grund 'noop $MARKE'"); RC=$(RC)
if [ "$RC" = 0 ]; then ok "Denselben Wert (bypassPermissions -> bypassPermissions) erneut setzen ist keine Lockerung, geht ohne Menschen"
else nok "Gleicher Wert erneut setzen braucht keinen Menschen" "rc=$RC $AUS"; fi

echo
echo "=== 2. shell/wb-code: die Flags an der Startzeile des Orchestrators =========="

wb_cmd_of() {   # <session-name-suffix> -> Inhalt der Pane-Option @wb_cmd
  local sess pane
  sess=$(T list-sessions -F '#{session_name}' 2>/dev/null | grep -- "-$1\$" | head -1)
  [ -n "$sess" ] || { echo ""; return 1; }
  pane=$(T list-panes -t "=$sess" -F '#{pane_id}' 2>/dev/null | head -1)
  [ -n "$pane" ] || { echo ""; return 1; }
  T display -p -t "$pane" '#{@wb_cmd}' 2>/dev/null
}

# (a) Vorgabe (bypassPermissions, wieder hergestellt oben) -> beide Flags.
timeout 20 wb-code --key permA "$TESTHOME/work" >"$TESTHOME/wbcode-a.out" 2>&1
CMD=$(wb_cmd_of permA)
case "$CMD" in
  *"--permission-mode bypassPermissions"*"--allow-dangerously-skip-permissions"*)
    ok "(a) Vorgabe bypassPermissions erzeugt BEIDE Flags" ;;
  *)
    nok "(a) Vorgabe erzeugt beide Flags" "CMD=$CMD | $(cat "$TESTHOME/wbcode-a.out")" ;;
esac

# (b) Ein gesenkter Wert -> nur --permission-mode, NICHT das zweite Flag.
im_pane als-agent "wb-state settings set orchestratorPermissionMode dontAsk" >/dev/null
timeout 20 wb-code --key permB "$TESTHOME/work" >"$TESTHOME/wbcode-b.out" 2>&1
CMD=$(wb_cmd_of permB)
case "$CMD" in
  *"--allow-dangerously-skip-permissions"*)
    nok "(b) gesenkter Wert (dontAsk) haengt trotzdem das Skip-Flag an" "CMD=$CMD" ;;
  *"--permission-mode dontAsk"*)
    ok "(b) gesenkter Wert (dontAsk) erzeugt NUR --permission-mode" ;;
  *)
    nok "(b) gesenkter Wert erzeugt --permission-mode dontAsk" "CMD=$CMD | $(cat "$TESTHOME/wbcode-b.out")" ;;
esac

# (e) Kaputte settings.json -> KEIN Flag, dafuer eine Zeile nach stderr.
cp "$TESTHOME/.claude/workbench/settings.json" "$TESTHOME/.claude/workbench/settings.json.bak"
printf 'das ist kein JSON { %s' "$MARKE" > "$TESTHOME/.claude/workbench/settings.json"
timeout 20 wb-code --key permE "$TESTHOME/work" >"$TESTHOME/wbcode-e.out" 2>&1
CMD=$(wb_cmd_of permE)
case "$CMD" in
  *"--permission-mode"*)
    nok "(e) kaputte settings.json haengt trotzdem ein Flag an" "CMD=$CMD" ;;
  *)
    ok "(e) kaputte settings.json: kein --permission-mode, kein Skip-Flag" ;;
esac
if grep -q "kein gueltiges JSON" "$TESTHOME/wbcode-e.out"; then
  ok "... und wb-code sagt auf stderr, warum (kein gueltiges JSON)"
else
  nok "wb-code nennt den Grund auf stderr" "$(cat "$TESTHOME/wbcode-e.out")"
fi
mv "$TESTHOME/.claude/workbench/settings.json.bak" "$TESTHOME/.claude/workbench/settings.json"

# Gegenprobe zu (e): 'wb-state settings valid' selbst, direkt geprueft --
# ohne sie waere (e) oben nur eine Behauptung ueber wb-code, nicht ueber das
# Werkzeug, das die Unterscheidung tatsaechlich liefert.
printf 'das ist kein JSON { %s' "$MARKE" > "$TESTHOME/.claude/workbench/settings.json.probe"
if /usr/bin/python3 -c "
import json
try:
    json.load(open('$TESTHOME/.claude/workbench/settings.json.probe'))
    raise SystemExit(1)
except json.JSONDecodeError:
    raise SystemExit(0)
"; then
  ok "Vorbedingung: die Probedatei ist wirklich kein gueltiges JSON"
else
  nok "Vorbedingung: Probedatei ist kein gueltiges JSON" "Test misst sonst nichts"
fi
rm -f "$TESTHOME/.claude/workbench/settings.json.probe"

echo
echo "================================================================"
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
