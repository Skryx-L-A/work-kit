#!/usr/bin/env bash
# Tests for 32-harness-profiles. Everything runs in temp HOMEs; nothing outside them is touched.
#   1. unit and installer tests (python unittest)
#   2. install.sh / uninstall.sh round trip with the launchers
#   3. opencode plugin loaded by node (skipped without node)
#   4. pi end to end: real pi CLI, scripted faux model, kit extension (skipped without pi)
#   5. shellcheck (skipped when not installed)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
PY="$(kit_find_python)" || { echo "SKIP all: $(kit_python_hint)"; exit 1; }
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export PYTHONDONTWRITEBYTECODE=1
unset KIT_AGENT_ROLE KIT_DATA_DIR KIT_BIN_DIR CODEX_HOME CLAUDE_CONFIG_DIR BRAIN_HOME PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR
FAIL=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     | /'; }

# 1
if out="$(cd "$HERE" && "$PY" -m unittest discover -s tests 2>&1)"; then ok "unittest ($(tail -3 <<<"$out" | head -1))"
else bad "unittest" "$(tail -30 <<<"$out")"; fi

# 2
H="$ROOT/home"; mkdir -p "$H/.claude" "$H/.pi"
E=(env HOME="$H" XDG_CONFIG_HOME="$H/.config" PATH="/usr/bin:/bin")
if out="$("${E[@]}" bash "$HERE/install.sh" 2>&1)"; then ok "install.sh"; else bad "install.sh" "$out"; fi
for t in kit-guard kit-context kit-statusline kit-profiles; do
  [ -x "$H/.local/bin/$t" ] && ok "launcher $t" || bad "launcher $t"
done
"${E[@]}" "$H/.local/bin/kit-guard" check -- "pkill -f node" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "kit-guard launcher refuses pkill (exit 2)" || bad "kit-guard launcher exit $rc"
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"tmux kill-server"},"cwd":"/"}' |
  "${E[@]}" bash -c "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print([h["command"] for g in d["hooks"]["PreToolUse"] for h in g["hooks"]][0])' "$H/.claude/settings.json")")"
grep -q '"permissionDecision": "deny"' <<<"$out" && ok "claude hook command from settings.json denies" || bad "claude hook" "$out"
if out="$("${E[@]}" bash "$HERE/install.sh" 2>&1)" && ! grep -q '^\[update\]\|^\[create\]' <<<"$out"; then
  ok "install.sh second run changes nothing"; else bad "install.sh rerun" "$out"; fi
if out="$("${E[@]}" bash "$HERE/uninstall.sh" 2>&1)"; then ok "uninstall.sh"; else bad "uninstall.sh" "$out"; fi
left="$(cd "$H" && find . -type f ! -name '*.bak-*' ! -path './Library/*' | sort | tr '\n' ' ')"
[ "$left" = "./.claude/settings.json " ] && ok "uninstall leaves only settings.json" || bad "uninstall leftovers: $left"
grep -q 'kit-' "$H/.claude/settings.json" && bad "settings.json still has kit entries" || ok "settings.json clean"

# 3 and 4 need a fresh install
H2="$ROOT/home2"; mkdir -p "$H2/.pi" "$H2/.config/opencode"
E2=(env HOME="$H2" XDG_CONFIG_HOME="$H2/.config")
"${E2[@]}" PATH="/usr/bin:/bin" bash "$HERE/install.sh" --harness pi,opencode >/dev/null 2>&1 || bad "install for e2e"
if command -v node >/dev/null 2>&1; then
  cp "$H2/.config/opencode/plugins/work-kit.js" "$ROOT/plugin.mjs"
  cat >"$ROOT/oc.mjs" <<'JS'
const { WorkKitGuard } = await import(process.argv[2])
const hooks = await WorkKitGuard({ directory: "/" })
const run = async (command) => { try { await hooks["tool.execute.before"]({ tool: "bash" }, { args: { command } }); return "allow" } catch (e) { return "blocked: " + e.message.slice(0, 40) } }
console.log(await run("ls"), "|", await run("pkill -f node"), "|", await run("git commit -m x"))
JS
  out="$("${E2[@]}" PATH="/usr/bin:/bin:$(dirname "$(command -v node)")" node "$ROOT/oc.mjs" "$ROOT/plugin.mjs" 2>&1)"
  if grep -q '^allow | blocked: kit-guard (kill)' <<<"$out" && grep -q 'blocked: kit-guard (commit)' <<<"$out"; then
    ok "opencode plugin: allow ls, block pkill, block unasked commit"; else bad "opencode plugin" "$out"; fi
else
  echo "SKIP opencode plugin (no node)"
fi
if command -v pi >/dev/null 2>&1; then
  W="$ROOT/work"; mkdir -p "$W"
  pirun() { (cd "$W" && "${E2[@]}" PATH="$PATH" FAUX_CMD="$1" timeout 60 pi -e "$HERE/tests/pi-faux-provider.ts" \
    --provider faux --model faux-1 -p "run it" 2>&1 | tail -1) </dev/null; }
  out="$(pirun "pkill -f node")"
  grep -q '^ROLE=lead CTX=true TOOL=kit-guard (kill)' <<<"$out" && ok "pi: kill refused, role + context injected" ||
    bad "pi kill" "$out"
  out="$(pirun "echo hello-from-bash")"
  grep -q 'TOOL=hello-from-bash' <<<"$out" && ok "pi: harmless command runs" || bad "pi allow" "$out"
  out="$(pirun "printf '%s%s\\n' sk-abcdefghij klmnopqrstuvwxyz0123")"  # key only in the output
  grep -q 'redacted openai_key' <<<"$out" && ok "pi: secret in bash output redacted" || bad "pi redact" "$out"
  out="$(cd "$W" && "${E2[@]}" KIT_AGENT_ROLE=worker PATH="$PATH" FAUX_CMD="git commit -m x" timeout 60 pi \
    -e "$HERE/tests/pi-faux-provider.ts" --provider faux --model faux-1 -p "run it" 2>&1 </dev/null | tail -1)"
  grep -q '^ROLE=worker' <<<"$out" && ! grep -q 'kit-guard (commit)' <<<"$out" &&
    ok "pi: KIT_AGENT_ROLE=worker switches role, worker may commit" || bad "pi worker" "$out"
else
  echo "SKIP pi end to end (no pi)"
fi

# 5
if command -v shellcheck >/dev/null 2>&1; then
  if out="$(shellcheck -x "$HERE/install.sh" "$HERE/uninstall.sh" "$HERE/tests/run-tests.sh" 2>&1)"; then ok "shellcheck"
  else bad "shellcheck" "$out"; fi
else
  echo "SKIP shellcheck (not installed)"
fi

[ "$FAIL" = 0 ] && { echo "all passed"; exit 0; }
echo "$FAIL failed"; exit 1
