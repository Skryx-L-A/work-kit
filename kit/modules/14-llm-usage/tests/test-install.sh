#!/usr/bin/env bash
# Installer + launcher in a scratch HOME: install, version, background proxy start/status/stop,
# a recorded call through the proxy (fake upstream), uninstall. Needs python3 >= 3.11.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/.." && pwd)"
W="$(mktemp -d)"
UP_PID=""
# shellcheck disable=SC2329  # used by trap
cleanup() { if [ -n "$UP_PID" ]; then kill "$UP_PID" 2>/dev/null || true; wait "$UP_PID" 2>/dev/null || true; fi; "$W/home/.local/bin/llm-usage" stop >/dev/null 2>&1 || true; rm -rf "$W"; }
trap cleanup EXIT
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

export HOME="$W/home" KIT_BIN_DIR="$W/home/.local/bin" KIT_DATA_DIR="$W/home/.local/share/work-kit"
export XDG_CONFIG_HOME="$W/home/.config"
unset LLM_USAGE_HOME LLM_USAGE_LIB
mkdir -p "$HOME"
bash "$MOD/install.sh" >/dev/null || bad "install exits 0"
U="$KIT_BIN_DIR/llm-usage"
check "launcher installed" "[ -x '$U' ]"
check "prices template written" "[ -f '$XDG_CONFIG_HOME/work-kit/llm-prices.toml' ]"
check "version runs" "'$U' --version | grep -q 'llm-usage 1'"
PRICE="$XDG_CONFIG_HOME/work-kit/llm-prices.toml"
PSTATE="$KIT_DATA_DIR/default-settings.sha256"
# Defaults we recorded are refreshed; a changed or pre-kit file is not overwritten.
sha256sum "$PRICE" | awk '{print "llm-prices.toml " $1}' >"$PSTATE"
out="$(bash "$MOD/install.sh")"
check "untouched price default is refreshed" "grep -q 'refreshed .*llm-prices.toml' <<<\"\$out\""
printf '\n# mine\n' >>"$PRICE"
out="$(bash "$MOD/install.sh")"
check "edited price file is kept and gets kit-new" "grep -q '# mine' '$PRICE' && [ -f '$PRICE.kit-new' ] && grep -q 'kept your' <<<\"\$out\""
rm -f "$PSTATE" "$PRICE.kit-new"; printf 'foreign price\n' >"$PRICE"
bash "$MOD/install.sh" >/dev/null
check "pre-existing foreign price file is kept" "[ \"\$(cat '$PRICE')\" = 'foreign price' ] && [ ! -e '$PRICE.kit-new' ]"
cp "$MOD/llm-prices.example.toml" "$PRICE"
# shellcheck disable=SC2034  # read inside eval
rerun="$(bash "$MOD/install.sh")"
check "rerun is idempotent" "grep -q 'up to date' <<<\"\$rerun\""

# help is safe: start/stop/status are listed, -h/--help never starts or stops anything
# shellcheck disable=SC2034  # read inside eval
help_out="$("$U" --help 2>&1)"
check "--help lists start, stop and status" "grep -q 'start \\[proxy options\\]' <<<\"\$help_out\" && grep -q ' stop ' <<<\"\$help_out\" && grep -q ' status ' <<<\"\$help_out\""
for sub in start stop status; do
  for flag in -h --help; do
    rc=0; "$U" "$sub" "$flag" >"$W/h.out" 2>&1 || rc=$?
    check "$sub $flag: usage, exit 0" "[ $rc = 0 ] && grep -q 'llm-usage stop' '$W/h.out'"
  done
done
check "help started no proxy" "[ ! -e '$KIT_DATA_DIR/llm-usage/proxy.pid' ] && [ ! -e '$KIT_DATA_DIR/llm-usage/proxy.log' ]"
rc=0; "$U" stop extra >/dev/null 2>&1 || rc=$?
check "stop with an argument: exit 2" "[ $rc = 2 ]"
# shellcheck disable=SC2034  # read inside eval
tail_out="$("$U" tail 2>&1)"
check "tail on an empty log says so" "grep -q 'no records' <<<\"\$tail_out\""

# a foreign launcher is backed up under the data dir, not beside the original
printf '#!/bin/sh\necho mine\n' >"$U"
bash "$MOD/install.sh" >/dev/null
check "foreign launcher backed up" "grep -q mine '$KIT_DATA_DIR'/backups/14-llm-usage/llm-usage.bak-*"
check "backup records the original path" "grep -qx '$U' '$KIT_DATA_DIR'/backups/14-llm-usage/llm-usage.bak-*.origin"
check "no backup beside the original" "! ls '$KIT_BIN_DIR' | grep -q 'bak-'"

# fake upstream on a free port
port_file="$W/port"
python3 - "$port_file" <<'PY' &
import http.server, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        self.rfile.read(int(self.headers["Content-Length"]))
        d = json.dumps({"id": "x", "model": "m", "choices": [{"message": {"content": "ok"}, "finish_reason": "stop"}],
                        "usage": {"prompt_tokens": 5, "completion_tokens": 1}}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(d))); self.end_headers(); self.wfile.write(d)
s = http.server.HTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1], "w").write(str(s.server_address[1]))
s.serve_forever()
PY
UP_PID=$!
for _ in $(seq 1 50); do [ -s "$port_file" ] && break; sleep 0.1; done
up_port="$(cat "$port_file")"
pport="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"

"$U" start --upstream "http://127.0.0.1:$up_port/v1" --port "$pport" --free --tag t >/dev/null || bad "proxy start"
check "status running" "'$U' status >/dev/null"
curl -fsS "http://127.0.0.1:$pport/v1/chat/completions" -H 'Content-Type: application/json' \
  -d '{"model":"m","messages":[{"role":"user","content":"hi"}]}' >/dev/null || bad "call through proxy"
check "summary shows the call" "'$U' summary --by tag | grep -q '| t | 1 | 0 | 5 | 1 | 0.0000 |'"
"$U" stop >/dev/null
check "stopped" "! '$U' status >/dev/null 2>&1"
pid_gone=1; pgrep -f "llm_usage.py proxy --upstream http://127.0.0.1:$up_port" >/dev/null && pid_gone=0
check "no proxy process left" "[ $pid_gone = 1 ]"

bash "$MOD/uninstall.sh" >/dev/null
check "launcher removed" "[ ! -e '$U' ]"
check "logs kept" "ls '$KIT_DATA_DIR/llm-usage/' | grep -q '^usage-'"
exit "$fail"
