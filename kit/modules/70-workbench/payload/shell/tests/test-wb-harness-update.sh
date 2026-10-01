#!/usr/bin/env bash
set -euo pipefail

unset TMUX TMUX_PANE AWB_CONTROL_SOCKET AWB_MANTEL_SOCKET AWB_MANTEL_TOKEN AWB_TMUX_SOCKET AWB_MODELS_FILE
# Kit: the account's home from the user database, as wb-harness-update's own check reads it,
# so the production-like case also holds when the suite runner uses another HOME.
REAL_HOME="$(/usr/bin/python3 -c 'import os, pwd; print(pwd.getpwuid(os.getuid()).pw_dir)')"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TOOL="$ROOT/shell/wb-harness-update"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/wb-harness-update-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() { grep -F -- "$2" "$1" >/dev/null || fail "$1 enthaelt nicht: $2"; }
assert_not_contains() { if [ -e "$1" ] && grep -F -- "$2" "$1" >/dev/null; then fail "$1 enthaelt unerlaubt: $2"; fi; }

setup_case() {
  CASE="$TMP/$1"
  mkdir -p "$CASE/bin" "$CASE/home" "$CASE/sessions" "$CASE/fake"
  export HOME="$CASE/home"
  export FAKE_DIR="$CASE/fake"
  export CALLS="$CASE/calls"
  export PATH="$CASE/bin:/usr/bin:/bin"
  export AWB_SETTINGS_FILE="$CASE/settings.json"
  export WB_HARNESS_UPDATE_STATE_FILE="$CASE/state.json"
  export WB_HARNESS_UPDATE_LOG_FILE="$CASE/update.log"
  export WB_HARNESS_UPDATE_LOCK_FILE="$CASE/update.lock"
  export WB_HARNESS_UPDATE_SESSIONS_DIR="$CASE/sessions"
  unset FAIL_CODEX AWB_CONTROL_SOCKET AWB_MANTEL_SOCKET AWB_MANTEL_TOKEN AWB_TMUX_SOCKET AWB_MODELS_FILE
  unset FAIL_PROBE SLOW_CODEX
  printf '{}\n' >"$AWB_SETTINGS_FILE"

  cat >"$CASE/bin/fake-harness" <<'SH'
#!/bin/sh
name=$(basename "$0")
[ "${FAIL_PROBE:-}" = 1 ] && [ "$name" = codex ] && { echo 'simulated version probe failure' >&2; exit 9; }
v=$(cat "$FAKE_DIR/$name.version" 2>/dev/null || true)
[ -n "$v" ] || exit 127
printf '%s %s\n' "$name" "$v"
SH
  chmod +x "$CASE/bin/fake-harness"
  for name in codex opencode aider; do ln -s fake-harness "$CASE/bin/$name"; done

  cat >"$CASE/bin/npm" <<'SH'
#!/bin/sh
printf 'npm %s\n' "$*" >>"$CALLS"
if [ "$1" = view ]; then
  case "$2" in
    @openai/codex) echo 0.156.0 ;;
    opencode-ai) echo 1.18.32 ;;
    *) echo 9.9.9 ;;
  esac
  exit 0
fi
if [ "$1" = install ]; then
  [ "${SLOW_CODEX:-}" = 1 ] && [ "$3" = @openai/codex@latest ] && sleep 1
  case "$3" in
    @openai/codex@latest)
      [ "${FAIL_CODEX:-}" = 1 ] && { echo 'simulated codex failure' >&2; exit 9; }
      [ "${FAIL_CODEX:-}" = broken ] && { : >"$FAKE_DIR/codex.version"; echo 'simulated broken codex install' >&2; exit 9; }
      echo 0.156.0 >"$FAKE_DIR/codex.version" ;;
    @openai/codex@0.146.0) echo 0.146.0 >"$FAKE_DIR/codex.version" ;;
    opencode-ai@latest) echo 1.18.32 >"$FAKE_DIR/opencode.version" ;;
  esac
  exit 0
fi
exit 2
SH

  cat >"$CASE/bin/curl" <<'SH'
#!/bin/sh
printf 'curl %s\n' "$*" >>"$CALLS"
case "$*" in
  *aider-chat*) printf '{"info":{"version":"0.86.2"}}\n' ;;
  *gptme*) printf '{"info":{"version":"0.34.0"}}\n' ;;
  *manifests*) printf '{"version":"1.2.8"}\n' ;;
  *) exit 22 ;;
esac
SH

  cat >"$CASE/bin/brew" <<'SH'
#!/bin/sh
printf 'brew %s\n' "$*" >>"$CALLS"
if [ "$1" = info ]; then
  printf '{"formulae":[{"versions":{"stable":"1.51.0"}}]}\n'
  exit 0
fi
exit 2
SH

  cat >"$CASE/bin/uv" <<'SH'
#!/bin/sh
printf 'uv %s\n' "$*" >>"$CALLS"
if [ "$1 $2 $3" = 'tool upgrade aider-chat' ]; then
  echo 0.86.2 >"$FAKE_DIR/aider.version"
  exit 0
fi
exit 2
SH

  cat >"$CASE/bin/tmux" <<'SH'
#!/bin/sh
printf 'tmux %s\n' "$*" >>"$CALLS"
case "$*" in
  'has-session -t live') exit 0 ;;
  *) echo "can't find session" >&2; exit 1 ;;
esac
SH

  cat >"$CASE/bin/wb-state" <<'SH'
#!/bin/sh
printf 'wb-state %s\n' "$*" >>"$CALLS"
if [ "$1 $2" = 'harness get' ]; then printf '{}\n'; fi
exit 0
SH

  cat >"$CASE/bin/wb-harness-config" <<'SH'
#!/bin/sh
printf 'wb-harness-config %s\n' "$*" >>"$CALLS"
exit 0
SH
  chmod +x "$CASE/bin/npm" "$CASE/bin/curl" "$CASE/bin/brew" "$CASE/bin/uv" \
    "$CASE/bin/tmux" "$CASE/bin/wb-state" "$CASE/bin/wb-harness-config"
}

json_assert() {
  /usr/bin/python3 - "$1" "$2" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if not eval(sys.argv[2], {"__builtins__": {}}, {"d": data}):
    raise SystemExit("assertion failed: " + sys.argv[2])
PY
}

# Veraltet, keine Sitzung: Installer und Discovery laufen.
setup_case outdated_free
echo 0.146.0 >"$FAKE_DIR/codex.version"
"$TOOL" anwenden codex --force --json >"$CASE/out.json"
json_assert "$CASE/out.json" "d['harnesses'][0]['status'] == 'aktualisiert'"
assert_contains "$CALLS" 'npm install -g @openai/codex@latest'
assert_contains "$CALLS" 'wb-state models discover codex --force'

# Veraltet, lebende Sitzung: nur vormerken, den uv-Installer keinesfalls rufen.
setup_case outdated_live
echo 0.86.1 >"$FAKE_DIR/aider.version"
cat >"$CASE/sessions/live.json" <<'JSON'
{"tmuxSession":"live","harness":"claude","workers":[{"name":"w","kind":"aider","model":"x","dir":"/tmp/w"}]}
JSON
"$TOOL" anwenden aider --force --json >"$CASE/out.json"
json_assert "$CASE/out.json" "d['harnesses'][0]['pending'] is True"
assert_not_contains "$CALLS" 'uv tool upgrade aider-chat'

# Aktuell: nichts installieren.
setup_case current
echo 1.18.32 >"$FAKE_DIR/opencode.version"
"$TOOL" anwenden opencode --force --json >"$CASE/out.json"
json_assert "$CASE/out.json" "d['harnesses'][0]['status'] == 'aktuell'"
assert_not_contains "$CALLS" 'npm install -g opencode-ai'

# Einstellung aus: pruefen darf keinen Katalog und damit kein Netzwerk beruehren.
setup_case disabled
echo 0.146.0 >"$FAKE_DIR/codex.version"
printf '{"harnessUpdateAuto":false}\n' >"$AWB_SETTINGS_FILE"
"$TOOL" pruefen --json >"$CASE/out.json"
json_assert "$CASE/out.json" "d['autoEnabled'] is False"
assert_not_contains "$CALLS" 'npm view'
assert_not_contains "$CALLS" 'brew info'
assert_not_contains "$CALLS" 'curl '

# Ein Harness scheitert; der folgende wird trotzdem aktualisiert.
setup_case continue_after_failure
echo 0.146.0 >"$FAKE_DIR/codex.version"
echo 1.18.31 >"$FAKE_DIR/opencode.version"
export FAIL_CODEX=1
if "$TOOL" anwenden codex opencode --force --json >"$CASE/out.json"; then
  fail 'Gesamtlauf muss den Codex-Fehler signalisieren'
fi
json_assert "$CASE/out.json" "d['harnesses'][0]['status'] == 'Update fehlgeschlagen' and d['harnesses'][1]['status'] == 'aktualisiert'"
assert_contains "$CALLS" 'npm install -g opencode-ai@latest'
assert_contains "$CALLS" 'wb-state models discover opencode --force'

# Der dritte Paketmanagerweg ist ebenfalls echt verdrahtet (uv-Attrappe).
setup_case uv_update
echo 0.86.1 >"$FAKE_DIR/aider.version"
"$TOOL" anwenden aider --force --json >"$CASE/out.json"
assert_contains "$CALLS" 'uv tool upgrade aider-chat'
json_assert "$CASE/out.json" "d['harnesses'][0]['installedAfter'] == '0.86.2'"

# Test-HOME: no installer is allowed without the explicit force override.
setup_case test_home
echo 0.146.0 >"$FAKE_DIR/codex.version"
"$TOOL" anwenden codex --json >"$CASE/out.json"
json_assert "$CASE/out.json" "d['harnesses'][0]['status'] == 'uebersprungen: Testumgebung'"
assert_not_contains "$CALLS" 'npm install -g'

# A failed version probe is unknown, never an invitation to install.
setup_case probe_failure
echo 0.146.0 >"$FAKE_DIR/codex.version"
export FAIL_PROBE=1
if "$TOOL" anwenden codex --force --json >"$CASE/out.json"; then
  fail 'Probe-Fehler muss den Lauf signalisieren'
fi
json_assert "$CASE/out.json" "d['harnesses'][0]['status'].startswith('unbekannt (Probe fehlgeschlagen:')"
assert_not_contains "$CALLS" 'npm install -g'

# A broken in-place npm update restores the exact installed version.
setup_case rollback
echo 0.146.0 >"$FAKE_DIR/codex.version"
export FAIL_CODEX=broken
if "$TOOL" anwenden codex --force --json >"$CASE/out.json"; then
  fail 'Kaputter Installer muss den Lauf signalisieren'
fi
json_assert "$CASE/out.json" "d['harnesses'][0]['status'] == 'Update fehlgeschlagen, zurueckgesetzt'"
assert_contains "$CALLS" 'npm install -g @openai/codex@latest'
assert_contains "$CALLS" 'npm install -g @openai/codex@0.146.0'

# The machine-wide updater lock admits exactly one concurrent run.
setup_case parallel
echo 0.146.0 >"$FAKE_DIR/codex.version"
export SLOW_CODEX=1
"$TOOL" anwenden codex --force --json >"$CASE/first.json" &
first_pid=$!
deadline=$((SECONDS + 5))
while ! grep -F 'npm install -g @openai/codex@latest' "$CALLS" >/dev/null 2>&1; do
  [ "$SECONDS" -lt "$deadline" ] || fail 'erster Lauf hat den Installer nicht rechtzeitig erreicht'
  sleep 0.05
done
if "$TOOL" anwenden codex --force --json >"$CASE/second.json"; then
  fail 'Paralleler Lauf darf nicht ebenfalls starten'
else
  second_rc=$?
  [ "$second_rc" -eq 3 ] || fail "erwarteter Sperrcode 3, erhalten: $second_rc"
fi
wait "$first_pid"
[ "$(grep -c 'npm install -g @openai/codex@latest' "$CALLS")" -eq 1 ] || fail 'Installer lief nicht genau einmal'

# Production-like core: real HOME plus the three sockets from Kernstart.swift
# must still permit anwenden without --force.
setup_case production_like
export HOME="$REAL_HOME"
export AWB_CONTROL_SOCKET="$CASE/awb.sock"
export AWB_MANTEL_SOCKET="$CASE/mantel.sock"
export AWB_MANTEL_TOKEN=production-test-token
echo 0.146.0 >"$FAKE_DIR/codex.version"
"$TOOL" anwenden codex --json >"$CASE/out.json"
json_assert "$CASE/out.json" "d['harnesses'][0]['status'] == 'aktualisiert'"
assert_contains "$CALLS" 'npm install -g @openai/codex@latest'

echo 'test-wb-harness-update: 11 Faelle gruen'
