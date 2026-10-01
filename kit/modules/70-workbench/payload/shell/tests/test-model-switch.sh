#!/usr/bin/env bash
# Isolated regression for the two-stage live model switch.
# Own HOME, registry, tmux socket and fake Claude process; no real session or
# model server is touched.
unset TMUX TMUX_PANE AWB_CONTROL_SOCKET AWB_MANTEL_SOCKET AWB_MANTEL_TOKEN
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "$REPO/.test-tmp"
TESTHOME="$(mktemp -d "$REPO/.test-tmp/model-switch.XXXXXX")"
SOCKET="wbtest-model-switch-$$"
BIN="$TESTHOME/.local/bin"
STATE="$TESTHOME/.claude/workbench/sessions"
pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
cleanup() {
  tmux -L "$SOCKET" kill-server >/dev/null 2>&1 || true
  [ "${KEEP_MODEL_SWITCH_TEST:-0}" = 1 ] || rm -rf "$TESTHOME"
  rmdir "$REPO/.test-tmp" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM HUP

mkdir -p "$BIN" "$STATE" "$TESTHOME/work"
cp "$REPO/shell/wb-state" "$REPO/shell/wb-revive" "$REPO/shell/wb-resume-id" \
   "$REPO/shell/wb-model-switch" "$BIN/"
chmod +x "$BIN/"*
cp "$REPO/shell/models.default.json" "$TESTHOME/.claude/workbench/models.json"
# Kit: discoveredVersion comes from 'wb-state models discover claude'; the shipped entry has
# none, so the suite sets what a discovery between the two tested CLI versions would record.
/usr/bin/python3 - "$TESTHOME/.claude/workbench/models.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for m in d["models"]:
    if m["id"] == "claude-opus-5-5":
        m["discoveredVersion"] = "2.1.275"
json.dump(d, open(sys.argv[1], "w"), indent=2)
PY

# The fake CLI renders a real prompt, accepts /model, can request an update,
# and shows the resumed history marker after respawn.
cat > "$BIN/claude" <<'FAKE'
#!/usr/bin/env bash
printf 'START %s\n' "$*" >> "$HOME/claude.log"
resume=""; previous=""
for arg in "$@"; do
  [ "$previous" = "--resume" ] && resume="$arg"
  previous="$arg"
done
[ -n "$resume" ] && printf 'HISTORY %s\n' "$resume"
if [ "$(cat "$HOME/mode" 2>/dev/null || true)" = busy ]; then
  printf 'working...\n'
else
  printf '❯\n'
fi
while IFS= read -r line; do
  printf 'INPUT %s\n' "$line" >> "$HOME/claude.log"
  if [ "$line" = "/model claude-opus-5-5" ] && [ "$(cat "$HOME/mode" 2>/dev/null || true)" = update ]; then
    printf 'update required\n❯\n'
  else
    printf 'MODEL claude-opus-5-5\n❯\n'
  fi
done
FAKE
chmod +x "$BIN/claude"

export HOME="$TESTHOME" PATH="$BIN:$PATH" AWB_WB_STATE="$BIN/wb-state" AWB_WB_REVIVE="$BIN/wb-revive"

make_pane() {
  local name="$1" mode="$2"
  printf '%s\n' "$mode" > "$HOME/mode"
  tmux -L "$SOCKET" new-session -d -s "$name" -c "$TESTHOME/work" \
    "$BIN/claude --model claude-sonnet-5 --effort high"
  local pane
  pane="$(tmux -L "$SOCKET" display-message -p -t "$name" '#{pane_id}')"
  tmux -L "$SOCKET" set -p -t "$pane" @wb_role orchestrator
  tmux -L "$SOCKET" set -p -t "$pane" @wb_cmd "$BIN/claude --model claude-sonnet-5 --effort high"
  "$BIN/wb-state" touch "$TESTHOME/work" "$name" --harness claude --model claude-sonnet-5 --claude-session "conv-$name" >/dev/null
  sleep 0.3
  printf '%s\n' "$pane"
}

echo "== Live-Modellwechsel (Socket $SOCKET) =="

# 1. Current CLI knows the model: slash command, same process.
PANE="$(make_pane slash okay)"; PID_VOR="$(tmux -L "$SOCKET" display-message -p -t "$PANE" '#{pane_pid}')"
OUT="$($BIN/wb-model-switch --tmux-socket "$SOCKET" --pane "$PANE" --model claude-opus-5-5 --process-version 2.1.280)"
PID_NACH="$(tmux -L "$SOCKET" display-message -p -t "$PANE" '#{pane_pid}')"
printf '%s' "$OUT" | grep -q '"mode": "slash"' && [ "$PID_VOR" = "$PID_NACH" ] \
  && ok "bekannte Version wechselt per Slash ohne Prozessneustart" \
  || bad "Slash-Wechsel oder Prozesskontinuitaet"
grep -q 'INPUT /model claude-opus-5-5' "$HOME/claude.log" \
  && ok "der registrierte Slash-Befehl wurde eingegeben" || bad "Slash-Befehl fehlt"

# 2. CLI reports update required: same pane respawns and resumes its own id.
PANE="$(make_pane fallback update)"; printf 'update\n' > "$HOME/mode"
OUT="$($BIN/wb-model-switch --tmux-socket "$SOCKET" --pane "$PANE" --model claude-opus-5-5 --process-version 2.1.280)"
sleep 0.4
printf '%s' "$OUT" | grep -q '"mode": "restart"' \
  && ok "update-required faellt auf den sicheren Neustart zurueck" || bad "Update-Fallback"
[ "$(tmux -L "$SOCKET" display-message -p -t "$PANE" '#{pane_id}')" = "$PANE" ] \
  && ok "der Neustart behaelt denselben Pane" || bad "Pane wurde ersetzt"
tmux -L "$SOCKET" capture-pane -p -t "$PANE" | grep -q 'HISTORY conv-fallback' \
  && ok "die Unterhaltung wurde im neu gestarteten Prozess fortgesetzt" || bad "Resume-Historie fehlt"
tmux -L "$SOCKET" show-options -pqv -t "$PANE" @wb_cmd | grep -q -- '--model claude-opus-5-5' \
  && ok "der neue Modellstand bleibt der saubere Revive-Befehl" || bad "@wb_cmd blieb beim alten Modell"

# 3. Installed discovery says the running process is too old: no doomed slash.
PANE="$(make_pane old okay)"; VOR="$(grep -c '^INPUT ' "$HOME/claude.log" || true)"
OUT="$($BIN/wb-model-switch --tmux-socket "$SOCKET" --pane "$PANE" --model claude-opus-5-5 --process-version 2.1.270)"
NACH="$(grep -c '^INPUT ' "$HOME/claude.log" || true)"
printf '%s' "$OUT" | grep -q '"mode": "restart"' && [ "$VOR" = "$NACH" ] \
  && ok "aeltere laufende Version startet direkt neu, ohne Slash-Versuch" \
  || bad "Versionsschranke"

# 4. Busy pane: no input and no respawn.
PANE="$(make_pane busy busy)"; PID_VOR="$(tmux -L "$SOCKET" display-message -p -t "$PANE" '#{pane_pid}')"
VOR="$(grep -c '^INPUT ' "$HOME/claude.log" || true)"
set +e
OUT="$($BIN/wb-model-switch --tmux-socket "$SOCKET" --pane "$PANE" --model claude-opus-5-5 --process-version 2.1.280)"; RC=$?
set -e
PID_NACH="$(tmux -L "$SOCKET" display-message -p -t "$PANE" '#{pane_pid}')"
NACH="$(grep -c '^INPUT ' "$HOME/claude.log" || true)"
[ "$RC" -eq 3 ] && [ "$PID_VOR" = "$PID_NACH" ] && [ "$VOR" = "$NACH" ] \
  && ok "beschaeftigter Pane bleibt vollstaendig unangetastet" || bad "Busy-Sperre"

printf '\nPASS=%d FAIL=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
