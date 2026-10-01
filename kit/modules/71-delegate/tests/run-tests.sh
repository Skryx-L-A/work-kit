#!/usr/bin/env bash
# Tests for agent-spawn using a fake harness and a private tmux server (own socket, own state).
# Usage: bash tests/run-tests.sh      Needs bash, tmux, git. Touches nothing outside a temp dir.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPAWN="$HERE/../agent-spawn"
T="$(mktemp -d "${TMPDIR:-/tmp}/agent-spawn-test.XXXXXX")"
SOCK="agent-spawn-test-$$"
unset TMUX TMUX_PANE
export AGENT_SPAWN_HOME="$T/state"
export AGENT_SPAWN_CONF="$T/harnesses.conf"
export AGENT_SPAWN_TMUX="tmux -L $SOCK -f /dev/null"
export AGENT_SPAWN_POLL=0.2
export PATH="$T/bin:$PATH"
pass=0
fail=0

cleanup() {
  tmux -L "$SOCK" kill-server >/dev/null 2>&1 || true
  rm -rf "$T"
}
trap cleanup EXIT

ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }
check() { # check <label> <command...>
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi
}
has() { grep -q -- "$2" <<<"$1"; }
wait_for() { # wait_for <seconds> <command...>
  local n=$(($1 * 5))
  shift
  while [ "$n" -gt 0 ]; do
    "$@" >/dev/null 2>&1 && return 0
    sleep 0.2
    n=$((n - 1))
  done
  return 1
}
sp() { "$SPAWN" "$@"; }

# --- fixtures ---------------------------------------------------------------------------

mkdir -p "$T/bin" "$T/work"
cat >"$T/bin/fake-agent" <<'EOF'
#!/usr/bin/env bash
# Fake harness: reads the prompt like a real one would, then acts according to its mode.
mode="$1"
prompt="$2"
task="$(sed -n 's/^You are worker .*Read the task file \(.*\) and carry it out\.$/\1/p' <<<"$prompt")"
result="$(sed -n 's/^When the work is finished.* as Markdown to \(.*\)$/\1/p' <<<"$prompt")"
case "$mode" in
  ok)
    { echo "# Result"; echo "task: $(head -n1 "$task")"; echo "cwd: $PWD"; echo "model: ${AGENT_MODEL:-none}"; echo "arg: ${3:-} ${4:-}"; echo "DONE"; } >"$result" ;;
  nomark)
    echo "half a result" >"$result"; exit 3 ;;
  none)
    exit 1 ;;
  dirty)
    echo x >dirty.txt; echo DONE >"$result" ;;
  hang)
    sleep 300 ;;
esac
EOF
chmod +x "$T/bin/fake-agent"
cat >"$T/harnesses.conf" <<'EOF'
# test harness table
fake     = fake-agent ok "$AGENT_PROMPT"
nomark   = fake-agent nomark "$AGENT_PROMPT"
none     = fake-agent none "$AGENT_PROMPT"
dirty    = fake-agent dirty "$AGENT_PROMPT"
hang     = fake-agent hang "$AGENT_PROMPT"
modelled = fake-agent ok "$AGENT_PROMPT" ${AGENT_MODEL:+--model "$AGENT_MODEL"}
claude   = fake-agent ok "$AGENT_PROMPT"
ghost    = no-such-binary-xyz "$AGENT_PROMPT"
EOF
printf '# Task: demo\n\n## Goal\nwrite a result\n' >"$T/task.md"

# --- harness table ----------------------------------------------------------------------

out="$(sp harnesses)"
for h in codex gemini opencode aider copilot; do
  check "harnesses lists built-in $h" has "$out" "^$h "
done
check "harnesses lists conf-only harness" has "$out" '^fake .*conf'
check "conf overrides built-in claude" has "$out" '^claude .*conf .*fake-agent'
check "harnesses flags missing binary" has "$out" 'ghost.*not on PATH'

# --- argument errors --------------------------------------------------------------------

check "start without harness fails" bash -c "! '$SPAWN' start a1 --task '$T/task.md'"
check "start with unknown harness fails" bash -c "! '$SPAWN' start a1 --harness nope --task '$T/task.md'"
check "start with missing binary fails" bash -c "! '$SPAWN' start a1 --harness ghost --task '$T/task.md'"
check "start with missing task fails" bash -c "! '$SPAWN' start a1 --harness fake --task '$T/none.md'"
check "start with bad name fails" bash -c "! '$SPAWN' start 'a b' --harness fake --task '$T/task.md'"
check "start with dot-leading name fails" bash -c "! '$SPAWN' start .old --harness fake --task '$T/task.md'"
check "failed start leaves no state" bash -c "[ -z \"\$(ls -A '$T/state' 2>/dev/null)\" ]"
check "result of unknown worker fails" bash -c "! '$SPAWN' result nobody"
out="$(sp list)"
check "list with no workers" has "$out" 'no workers'

# --- normal run -------------------------------------------------------------------------

cd "$T/work" || exit 1
out="$(sp start w1 --harness fake --task "$T/task.md" --session ts 2>&1)"
check "start prints pane" has "$out" 'started w1 (fake) pane %'
res="$(sp result w1 --wait 20)"
rc=$?
check "result exits 0 when complete" test "$rc" -eq 0
check "result has the task title" has "$res" 'task: # Task: demo'
check "worker ran in the given directory" has "$res" "cwd: .*work"
check "task copied into state" test -s "$T/state/w1/task.md"
check "worker sees no model by default" has "$res" 'model: none'
check "list: pane waits after finish" wait_for 10 bash -c "'$SPAWN' list | grep -q '^w1 .*done'"
check "exit code recorded" test "$(cat "$T/state/w1/exit")" = 0
check "peek shows the exit hint" has "$(sp peek w1)" 'Press Enter'
check "duplicate name refused" bash -c "! '$SPAWN' start w1 --harness fake --task '$T/task.md' --session ts"
sp stop w1 >/dev/null 2>&1
check "stop on finished worker keeps its status" bash -c "'$SPAWN' list | grep -q '^w1 .*done'"
check "pane gone after stop" bash -c "! '$SPAWN' peek w1"
check "force replaces finished worker" bash -c "'$SPAWN' start w1 --harness fake --task '$T/task.md' --session ts --close --force"
check "old state kept in .old" bash -c "ls '$T/state/.old' | grep -q '^w1-'"
sp result w1 --wait 20 >/dev/null 2>&1
check "--close closes the pane" wait_for 10 bash -c "! tmux -L $SOCK list-panes -a -F '#{@agent_name}' | grep -qx w1"

# --- model, custom result path ----------------------------------------------------------

sp start w2 --harness modelled --model m-7 --task "$T/task.md" --session ts --close \
  --result "$T/out/res.md" >/dev/null 2>&1
res="$(sp result w2 --wait 20)"
check "model reaches the harness env" has "$res" 'model: m-7'
check "model expands in the command template" has "$res" 'arg: --model m-7'
check "custom result path used" test -s "$T/out/res.md"

# --- built-in command templates (stub binaries record their arguments) -----------------------

for h in codex gemini opencode aider copilot; do
  cat >"$T/bin/$h" <<'STUB'
#!/usr/bin/env bash
{ echo "argv:"; for a in "$@"; do printf '%s\n' "$a" | head -n1; done; echo DONE; } >"$AGENT_RESULT_FILE"
STUB
  chmod +x "$T/bin/$h"
done
for h in codex gemini opencode aider copilot; do
  sp start "b-$h" --harness "$h" --model mm --task "$T/task.md" --session ts --close >/dev/null 2>&1
done
argv() { sp result "b-$1" --wait 20 2>&1 | tr '\n' ' '; }
check "codex args" has "$(argv codex)" 'argv: -m mm You are worker "b-codex"'
check "gemini args" has "$(argv gemini)" 'argv: -m mm -i You are worker "b-gemini"'
check "opencode args" has "$(argv opencode)" 'argv: -m mm --prompt You are worker "b-opencode"'
check "aider args" has "$(argv aider)" 'argv: --model mm --message You are worker "b-aider"'
check "copilot args" has "$(argv copilot)" 'argv: --model mm -i You are worker "b-copilot"'

# --- failure paths ----------------------------------------------------------------------

sp start w3 --harness nomark --task "$T/task.md" --session ts --close >/dev/null 2>&1
sp result w3 --wait 20 >/dev/null 2>&1
check "result without DONE exits 5" test "$?" -eq 5
sp start w4 --harness none --task "$T/task.md" --session ts --close >/dev/null 2>&1
sp result w4 --wait 20 >/dev/null 2>&1
check "worker without result exits 4" test "$?" -eq 4
check "list shows exit code" bash -c "'$SPAWN' list | grep -q '^w4 .*exited:1'"

# --- deadline and stop ------------------------------------------------------------------

sp start w5 --harness hang --task "$T/task.md" --session ts >/dev/null 2>&1
sp result w5 --wait 1 >/dev/null 2>&1
check "result deadline exits 3" test "$?" -eq 3
check "hanging worker is running" bash -c "'$SPAWN' list | grep -q '^w5 .*running'"
check "start of running name refused even with --force" \
  bash -c "! '$SPAWN' start w5 --harness fake --task '$T/task.md' --session ts --force"
sp stop w5 >/dev/null 2>&1
check "stop kills the pane" bash -c "! tmux -L $SOCK list-panes -a -F '#{@agent_name}' | grep -qx w5"
check "list shows stopped" bash -c "'$SPAWN' list | grep -q '^w5 .*stopped'"
sp result w5 >/dev/null 2>&1
check "result of stopped worker exits 4" test "$?" -eq 4

# --- worktree ---------------------------------------------------------------------------

git init -q "$T/repo" && cd "$T/repo" || exit 1
git -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
cd "$T/work" || exit 1
check "worktree outside git repo fails" bash -c "! '$SPAWN' start g0 --harness fake --task '$T/task.md' --dir '$T/work' --worktree --session ts"
sp start g1 --harness fake --task "$T/task.md" --dir "$T/repo" --worktree --session ts --close >/dev/null 2>&1
res="$(sp result g1 --wait 20)"
check "worker runs in the worktree" has "$res" "cwd: .*repo.worktrees/g1"
check "worktree branch exists" git -C "$T/repo" rev-parse --verify -q agent/g1
sp stop g1 --remove-worktree >/dev/null 2>&1
check "clean worktree removed by stop" test ! -d "$T/repo.worktrees/g1"
check "branch is kept" git -C "$T/repo" rev-parse --verify -q agent/g1
sp start g2 --harness dirty --task "$T/task.md" --dir "$T/repo" --worktree --session ts --close >/dev/null 2>&1
sp result g2 --wait 20 >/dev/null 2>&1
sp stop g2 --remove-worktree >/dev/null 2>&1
check "dirty worktree is kept, stop exits 1" test "$?" -eq 1
check "dirty worktree still there" test -f "$T/repo.worktrees/g2/dirty.txt"

# --- split inside an existing tmux window -----------------------------------------------

cat >"$T/inner.sh" <<EOF
#!/usr/bin/env bash
"$SPAWN" start s1 --harness hang --task "$T/task.md" >"$T/inner.out" 2>&1
echo \$? >"$T/inner.rc"
sleep 30
EOF
tmux -L "$SOCK" -f /dev/null new-session -d -s host -x 120 -y 40 "bash $T/inner.sh"
check "inner start finished" wait_for 10 test -s "$T/inner.rc"
check "inner start succeeded" test "$(cat "$T/inner.rc" 2>/dev/null)" = 0
n="$(tmux -L "$SOCK" list-panes -t host:0 2>/dev/null | wc -l | tr -d ' ')"
check "worker pane split into the current window" test "$n" -eq 2
check "no session option needed inside tmux" bash -c "! grep -q 'attach -t' '$T/inner.out'"
sp stop s1 >/dev/null 2>&1
check "split pane stopped" bash -c "! tmux -L $SOCK list-panes -a -F '#{@agent_name}' | grep -qx s1"

# --- template and help ------------------------------------------------------------------

out="$(sp template)"
check "template has the sections" has "$out" 'Exclusive paths'
check "help works" bash -c "'$SPAWN' --help | grep -q 'agent-spawn start'"

# --- install / uninstall (all paths redirected into the temp dir) -----------------------------

mkdir -p "$T/h/.claude" "$T/h/skills"
echo mine >"$T/h/bin-existing"
export KIT_BIN_DIR="$T/h/bin" KIT_DATA_DIR="$T/h/data" KIT_SKILLS_DIR="$T/h/skills" \
  KIT_CLAUDE_SKILLS_DIR="$T/h/.claude/skills"
mkdir -p "$KIT_BIN_DIR" && echo mine >"$KIT_BIN_DIR/agent-spawn"
out="$(bash "$HERE/../install.sh" 2>&1)"
check "install links agent-spawn" test "$(readlink "$KIT_BIN_DIR/agent-spawn")" = "$KIT_DATA_DIR/delegate/agent-spawn"
check "install backs up an existing file under backups/" bash -c "grep -q mine '$KIT_DATA_DIR'/backups/71-delegate/agent-spawn.bak-*"
check "backup records the original path" bash -c "grep -qx '$KIT_BIN_DIR/agent-spawn' '$KIT_DATA_DIR'/backups/71-delegate/agent-spawn.bak-*.origin"
check "no backup beside the original" bash -c "! ls '$KIT_BIN_DIR' | grep -q 'bak-'"
check "install links skill into ~/.agents/skills" test -f "$KIT_SKILLS_DIR/delegate/SKILL.md"
check "install links skill for Claude Code" test -f "$KIT_CLAUDE_SKILLS_DIR/delegate/SKILL.md"
check "installed agent-spawn runs" bash -c "'$KIT_BIN_DIR/agent-spawn' --help | grep -q Usage"
out="$(bash "$HERE/../install.sh" 2>&1)"
check "second install is a no-op" has "$out" 'up to date'
check "second install makes no new backup" test "$(find "$KIT_DATA_DIR/backups" -name 'agent-spawn.bak-*' ! -name '*.origin' | wc -l | tr -d ' ')" -eq 1
bash "$HERE/../uninstall.sh" >/dev/null 2>&1
check "uninstall removes links and copy" bash -c "[ ! -e '$KIT_BIN_DIR/agent-spawn' ] && [ ! -e '$KIT_SKILLS_DIR/delegate' ] && [ ! -e '$KIT_CLAUDE_SKILLS_DIR/delegate' ] && [ ! -e '$KIT_DATA_DIR/delegate' ]"
check "uninstall keeps backups" bash -c "ls '$KIT_DATA_DIR/backups/71-delegate' | grep -q '^agent-spawn.bak-'"
unset KIT_BIN_DIR KIT_DATA_DIR KIT_SKILLS_DIR KIT_CLAUDE_SKILLS_DIR

# --- missing tmux: message names 01-prereqs ----------------------------------------------
mkdir -p "$T/notmux"
for t in bash sh env dirname basename cat mkdir date grep sed tr; do
  p="$(command -v "$t")" && ln -sf "$p" "$T/notmux/$t"
done
echo "goal" >"$T/notmux.task"
out="$(env -u AGENT_SPAWN_TMUX PATH="$T/notmux" bash "$SPAWN" start w9 --harness fake --task "$T/notmux.task" 2>&1)"
check "missing tmux is reported" has "$out" "tmux not found"
check "missing tmux names 01-prereqs" has "$out" "01-prereqs/install.sh tmux"

# --- cleanup check ----------------------------------------------------------------------

tmux -L "$SOCK" kill-server >/dev/null 2>&1
check "test tmux server ended" bash -c "! tmux -L $SOCK list-sessions"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
