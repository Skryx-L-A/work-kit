#!/usr/bin/env bash
# test-sicherheit-rest.sh -- three narrow security regressions from 2026-09-21.
#
# Isolation: every invoked tool receives a disposable HOME.  The pi-worker run
# creates a real worker pane only on this suite's tmux socket; its inbox and
# agent are fixtures, so no model, live session, or user configuration runs.
unset TMUX TMUX_PANE
set -uo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/lib-testwerkzeuge.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_TMUX="$(command -v tmux 2>/dev/null || true)"
SOCKET="wbtest-sicherheit-rest-$$"
TESTHOME="$(mktemp -d "${TMPDIR:-/tmp}/wb-sicherheit-rest.XXXXXX")"
BIN="$TESTHOME/.local/bin"
SHIM="$TESTHOME/.shim"
INBOXMODE="$TESTHOME/inbox.mode"
TRANSCRIPT="$TESTHOME/transcript.txt"
PASS=0; FAIL=0

ok() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }
mode() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; }

cleanup() {
  [ -n "$REAL_TMUX" ] && tmux_socket_beenden_ohne_reste "$SOCKET"
  case "$TESTHOME" in
    /tmp/wb-sicherheit-rest.*|/private/tmp/wb-sicherheit-rest.*|/var/folders/*/wb-sicherheit-rest.*)
      rm -rf "$TESTHOME" ;;
    *) echo "WARNUNG: Testverzeichnis nicht entfernt: $TESTHOME" >&2 ;;
  esac
}
trap cleanup EXIT INT TERM

echo "== Sicherheitsrest: Rechte, Key-Riegel, Enginex-Umgebung =="
[ -n "$REAL_TMUX" ] || { echo "UEBERSPRUNGEN: tmux fehlt"; exit 77; }

mkdir -p "$BIN" "$SHIM" "$TESTHOME/.claude/workbench" "$TESTHOME/arbeit"
cp "$REPO/pi-worker" "$BIN/pi-worker"
cp "$REPO/wb-state" "$BIN/wb-state"
cp "$REPO/wb-pane-write" "$BIN/wb-pane-write"
cp "$REPO/wb-mensch" "$BIN/wb-mensch"
cp "$REPO/wb-rolle" "$BIN/wb-rolle"
cp "$REPO/models.default.json" "$TESTHOME/.claude/workbench/models.json"
chmod +x "$BIN/pi-worker" "$BIN/wb-state" "$BIN/wb-pane-write" "$BIN/wb-mensch" "$BIN/wb-rolle"
mkdir -p "$TESTHOME/.claude/hooks/lib"
cp "$REPO/../hooks/lib/rollen.py" "$TESTHOME/.claude/hooks/lib/rollen.py"

cat > "$SHIM/tmux" <<EOF
#!/bin/sh
exec "$REAL_TMUX" -L "$SOCKET" "\$@"
EOF
chmod +x "$SHIM/tmux"

# The fake Claude never executes received text.  wb-inbox records the exact
# temporary inbox mode before pi-worker removes it, then exposes the same text
# as a transcript so the real delivery proof completes without a 60s wait.
cat > "$BIN/claude" <<'EOF'
#!/bin/sh
stty -echo 2>/dev/null
printf '\342\235\257 \n'
exec cat
EOF
cat > "$BIN/wb-inbox" <<EOF
#!/bin/sh
case "\$1" in
  finde) exit 0 ;;
  status) printf 'idle\n' ;;
  sende) stat -f '%Lp' "\$3" > "$INBOXMODE" 2>/dev/null || stat -c '%a' "\$3" > "$INBOXMODE"; cp "\$3" "$TRANSCRIPT"; exit 0 ;;
  transcript) printf '%s\n' "$TRANSCRIPT" ;;
esac
exit 1
EOF
for tool in wb-grid context-guard nohup; do
  printf '#!/bin/sh\nexit 0\n' > "$BIN/$tool"
  chmod +x "$BIN/$tool"
done
chmod +x "$BIN/claude" "$BIN/wb-inbox"

tmux -L "$SOCKET" -f /dev/null new-session -d -s "wb-sicherheit-rest-$$" -x 200 -y 40
ORCH="$(tmux -L "$SOCKET" list-panes -t "=wb-sicherheit-rest-$$" -F '#{pane_id}' | head -1)"
tmux -L "$SOCKET" set-option -p -t "$ORCH" @wb_role orchestrator
tmux_live_hooks_kappen "$SOCKET"

echo
echo "-- 1: echter, isolierter pi-worker Spawn --"
OUT="$(umask 022; env HOME="$TESTHOME" PATH="$SHIM:$BIN:$PATH" WB_ZUSTELLUNG=socket \
  TMUX= TMUX_PANE= bash "$BIN/pi-worker" rechte opus5 "$TESTHOME/arbeit" 'Rechte pruefen' 2>&1)"
RC=$?
RESDIR="$TESTHOME/.pi-workers/results/rechte"
AUFTRAG="$(find "$RESDIR" -name '*.auftrag.txt' -type f -print -quit 2>/dev/null)"
MCP="$TESTHOME/.claude/workbench/mcp-worker.json"
[ "$RC" -eq 0 ] && ok "pi-worker Spawn und Inbox-Zustellung enden erfolgreich" \
  || { bad "pi-worker Spawn endet mit rc=$RC"; printf '%s\n' "$OUT" | tail -20; }
[ "$(mode "$RESDIR")" = 700 ] && ok "Ergebnisverzeichnis ist 0700" \
  || bad "Ergebnisverzeichnis hat Modus $(mode "$RESDIR") statt 700"
[ -n "$AUFTRAG" ] && [ "$(mode "$AUFTRAG")" = 600 ] && ok "Auftragstext ist 0600" \
  || bad "Auftragstext fehlt oder ist nicht 0600 (Modus: $(mode "$AUFTRAG" 2>/dev/null || echo fehlt))"
ERGEBNISDATEIEN="$(find "$RESDIR" -type f -print 2>/dev/null)"
if [ -n "$ERGEBNISDATEIEN" ] && ! find "$RESDIR" -type f ! -perm 600 -print | grep -q .; then
  ok "alle angelegten Ergebnisdateien sind 0600"
else
  bad "mindestens eine angelegte Ergebnisdatei ist nicht 0600"
fi
[ -f "$MCP" ] && [ "$(mode "$MCP")" = 600 ] && ok "MCP-Worker-Datei ist 0600" \
  || bad "MCP-Worker-Datei fehlt oder ist nicht 0600"
[ "$(cat "$INBOXMODE" 2>/dev/null)" = 600 ] && ok "temporäre Inbox-Datei war vor dem Aufräumen 0600" \
  || bad "temporäre Inbox-Datei hatte Modus $(cat "$INBOXMODE" 2>/dev/null || echo fehlt) statt 600"

echo
echo "-- 2: wb-code weist ausbrechenden Key vor jedem mkdir ab --"
ESCAPE="$TESTHOME/.pi-workers/tmp/ausbruch"
OUT="$(env HOME="$TESTHOME" WB_NO_DISCOVER=1 bash "$REPO/wb-code" --key '../../../tmp/ausbruch' --harness pi "$TESTHOME/arbeit" 2>&1)"
RC=$?
[ "$RC" -ne 0 ] && printf '%s' "$OUT" | grep -q "unzulaessiger Session-Key '../../../tmp/ausbruch'" \
  && ok "ausbrechender Key wird mit nachvollziehbarem Fehler abgelehnt" \
  || bad "ausbrechender Key wurde nicht wie erwartet abgelehnt (rc=$RC)"
[ ! -e "$ESCAPE" ] && ok "der abgewiesene Key legt kein Verzeichnis außerhalb von sessions an" \
  || bad "der abgewiesene Key legte dennoch $ESCAPE an"

echo
echo "-- 3: Enginex-Startzeile leert nur die störende API-Key-Umgebung --"
# Kein Enginex-Prozess: ein echter Start reserviert auf dieser geteilten Maschine
# rund 14,6 GiB. Mit einer absichtlich gesetzten Variable wird deshalb die
# tatsächliche, an wb-nohup übergebene Startzeile geprüft; eine HTTP-Antwort des
# echten Servers ist ausdrücklich außerhalb dieses Tests.
if [ ! -f "$REPO/wb-enginex-server" ]; then
  ok "wb-enginex-server gehoert nicht zum Kit -- Pruefung entfaellt"
elif ENGINEX_API_KEY='test-key-darf-nicht-ankommen' \
   grep -qF 'env -u ENGINEX_API_KEY "$ENGINEX" serve' "$REPO/wb-enginex-server"; then
  ok "die gebaute Enginex-Startzeile entfernt gesetztes ENGINEX_API_KEY vor serve"
else
  bad "die gebaute Enginex-Startzeile entfernt gesetztes ENGINEX_API_KEY nicht"
fi

echo
echo "== Ergebnis: $PASS ok, $FAIL FAIL =="
[ "$FAIL" -eq 0 ]
