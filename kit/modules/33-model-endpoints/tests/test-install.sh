#!/usr/bin/env bash
# Install, use and uninstall kit-models in a temp HOME. No network, no real harness touched.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export HOME="$T" PATH="$T/.local/bin:/usr/bin:/bin" KIT_MODELS_NO_SECRET_TOOL=1 KIT_MODELS_PROXY_PORT=4979
unset XDG_CONFIG_HOME KIT_BIN_DIR KIT_DATA_DIR
fail() { echo "FAIL: $*" >&2; exit 1; }

bash "$HERE/install.sh" >/dev/null
[ -x "$T/.local/bin/kit-models" ] || fail "launcher missing"
kit-models --version | grep -q '^kit-models ' || fail "--version"
mkdir -p "$T/.config/opencode"
kit-models add --name corp --base-url https://llm.example.test/v1 --model m1 --targets opencode,claude >/dev/null
grep -q '{env:KIT_MODEL_CORP_KEY}' "$T/.config/opencode/opencode.json" || fail "opencode entry"
[ -x "$T/.local/bin/claude-corp" ] || fail "claude wrapper"
out="$(bash "$HERE/install.sh")"
case "$out" in *"kit-models up to date"*) ;; *) fail "re-install replaced the launcher" ;; esac
case "$out" in *"[update]"*|*"[create]"*) fail "re-install changed files: $out" ;; esac
kit-models proxy start >/dev/null
kit-models proxy status >/dev/null || fail "proxy status"
TOKF="$T/.local/share/work-kit/model-endpoints/proxy.token"
[ -s "$TOKF" ] || fail "proxy token missing"
[ "$(stat -f %Lp "$TOKF" 2>/dev/null || stat -c %a "$TOKF")" = 600 ] || fail "proxy token mode"
[ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:4979/health)" = 401 ] || fail "keyless request not refused"
[ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer wrong' http://127.0.0.1:4979/health)" = 401 ] || fail "wrong token not refused"
[ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $(cat "$TOKF")" http://127.0.0.1:4979/health)" = 200 ] || fail "token not accepted"
[ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' -H "x-api-key: $(cat "$TOKF")" http://127.0.0.1:4979/health)" = 200 ] || fail "x-api-key not accepted"
bash "$HERE/uninstall.sh" --purge >/dev/null
[ ! -e "$T/.local/bin/kit-models" ] || fail "launcher left"
[ ! -e "$T/.local/bin/claude-corp" ] || fail "wrapper left"
[ ! -e "$T/.config/opencode/opencode.json" ] || fail "opencode entry left"
[ ! -e "$T/.config/work-kit/model-endpoints.json" ] || fail "registry left"
if curl -s -m 1 -o /dev/null "http://127.0.0.1:4979/health" 2>/dev/null; then fail "proxy still running"; fi
echo "test-install: OK"
