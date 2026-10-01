#!/bin/bash
# Tests for the script step of bash-guard.py (SPEC known defect 9): a local script that holds a guarded
# command is refused or held as a question when a command starts it (`bash x.sh`, `sh x.sh`, `zsh x.sh`,
# `./x.sh`, `source x.sh`, `. x.sh`), with script and line in the reason.
#
# Isolated: own HOME, own guard log and marker folder, own snapshot config, own kit data folder. Touches
# nothing outside the temporary folder and starts no tmux.
set -uo pipefail
unset TMUX TMUX_PANE KIT_AGENT_ROLE

HOOKS_DIR="${HOOKS_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
GUARD="$HOOKS_DIR/bash-guard.py"
WORK=$(cd "$(mktemp -d)" && pwd -P)
trap 'chmod -R u+rw "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

export HOME="$WORK/home"
mkdir -p "$HOME"
export XDG_CONFIG_HOME="$WORK/config"
export AWB_GUARD_LOG="$WORK/guard-blocks.log"
export AWB_GUARD_BLOCKS_DIR="$WORK/blocks"
export AWB_GUARD_GRANTS_DIR="$WORK/grants"
export AWB_ROLLEN_DIR="$WORK/rollen"
export AWB_SETTINGS_FILE="$WORK/settings.json"   # absent: the built-in question patterns apply
export AWB_CONFIG="$WORK/none-config.json"
unset KIT_DATA_DIR
export KIT_DATA_DIR="$WORK/kit"                  # no 32-harness-profiles unless a case links it
mkdir -p "$KIT_DATA_DIR"

# Snapshot guard: own folder; the default exemption of temporary folders is replaced (exempt_glob), so a
# delete of the existing folder below the work folder is refused.
VICTIM="$WORK/victim-data"
mkdir -p "$VICTIM"; echo important > "$VICTIM/file.txt"
printf 'snapshot_dir=%s\nmin_bytes=1\nexempt_glob=/dev/null\n' "$WORK/snapshots" > "$WORK/snapshot.conf"
export SNAPSHOT_GUARD_CONF="$WORK/snapshot.conf"

PASS=0; FAIL=0
FAKE_KEY="sk-""abcdefghijklmnopqrstuvwxyz123456"   # built at run time: no literal key in this file

# guard <command> [cwd] -> "allow" | "deny" | "ask"; the reason lands in $REASON, the raw output in $OUT
guard() {
  OUT=$(python3 -c '
import json, sys
print(json.dumps({"tool_name": "Bash", "session_id": "s", "cwd": sys.argv[2], "tool_input": {"command": sys.argv[1]}}))
' "$1" "${2:-$WORK/w}" | python3 "$GUARD" 2>"$WORK/stderr"); RC=$?
  RESULT=$(printf '%s' "$OUT" | python3 -c '
import json, sys
try:
    o = json.loads(sys.stdin.read())["hookSpecificOutput"]
    print(o["permissionDecision"] + "\t" + o.get("permissionDecisionReason", "").replace("\n", " "))
except Exception:
    print("allow\t")
')
  DECISION=${RESULT%%$'\t'*}; REASON=${RESULT#*$'\t'}
  [ "$RC" = 2 ] && { DECISION=deny; REASON=$(cat "$WORK/stderr"); }
  # the question stage answers "deny" with a QUESTION text: report it as "ask"
  case "$REASON" in "QUESTION, not a refusal"*) DECISION=ask ;; esac
}

expect() {  # expect <allow|deny|ask> <label> <command> [reason-fragment ...]
  local want="$1" label="$2" cmd="$3"; shift 3
  guard "$cmd"
  local ok=1 frag
  [ "$DECISION" = "$want" ] || ok=0
  for frag in "$@"; do case "$REASON" in *"$frag"*) ;; *) ok=0 ;; esac; done
  if [ "$ok" = 1 ]; then PASS=$((PASS+1)); printf '  PASS  %s\n' "$label"
  else FAIL=$((FAIL+1)); printf '  FAIL  %s (want %s, got %s)\n        cmd: %s\n        reason: %s\n' "$label" "$want" "$DECISION" "$cmd" "${REASON:0:300}"; fi
}

mkdir -p "$WORK/w"; cd "$WORK/w" || exit 1
put() { printf '%b' "$2" > "$WORK/w/$1"; chmod "${3:-644}" "$WORK/w/$1"; }

echo "=== question patterns inside a script (gh release create, git push --force) ==="
put rel.sh '#!/bin/bash\necho start\ngh release create v1 --title x\necho done\n' 755
guard "gh release create v1"; TYPED=$DECISION
[ "$TYPED" = ask ] && { PASS=$((PASS+1)); echo "  PASS  control: the typed command is held as a question"; } || { FAIL=$((FAIL+1)); echo "  FAIL  control: typed gh release create is $TYPED"; }
expect ask "bash rel.sh"        "bash rel.sh"        "script rel.sh, line 3"
expect ask "sh rel.sh"          "sh rel.sh"          "script rel.sh, line 3"
expect ask "zsh rel.sh"         "zsh rel.sh"         "script rel.sh, line 3"
expect ask "./rel.sh"           "./rel.sh"           "script ./rel.sh, line 3"
expect ask "source rel.sh"      "source rel.sh"      "script rel.sh, line 3"
expect ask ". rel.sh"           ". rel.sh"           "script rel.sh, line 3"
expect ask "bash -x rel.sh a b" "bash -x rel.sh a b" "line 3"
expect ask "sudo bash rel.sh"   "env FOO=1 bash rel.sh" "line 3"
expect ask "bash -c 'sh rel.sh'" "bash -c 'sh rel.sh'" "line 3"
expect ask "script on stdin: bash < rel.sh" "bash < rel.sh" "script rel.sh, line 3"
expect ask "script on stdin: sh <rel.sh" "sh <rel.sh" "line 3"
expect ask "absolute path"      "bash $WORK/w/rel.sh" "line 3"
expect ask "\$HOME-relative"    "bash \$HOME/../w/rel.sh" "line 3"
put push.sh 'echo a\ngit push --force origin main\n'
expect ask "git push --force in a script" "bash push.sh" "script push.sh, line 2"
put twine.sh 'python3 -m twine upload dist/x.whl\n'
expect ask "python -m twine upload inside a script" "bash twine.sh" "script twine.sh, line 1"

echo "=== hard guards inside a script ==="
put kill.sh 'echo a\nfor i in 1 2; do\n  echo $i\ndone\npkill -f node\n'
expect deny "kill pattern names script and line" "bash kill.sh" "script kill.sh, line 5"
put rm.sh "echo a\nrm -rf $VICTIM\necho b\n"
expect allow "delete in a script is typed-only" "bash rm.sh"
rm -rf "$WORK/snapshots"
put both.sh 'gh release create v1\npkill -f node\n'
expect deny "a refusal beats a question in the same script" "bash both.sh" "line 2"
put two.sh 'echo one\n'
expect deny "strictest over two scripts" "bash rel.sh; bash kill.sh" "kill.sh"

echo "=== harmless and unusable scripts change nothing ==="
put ok.sh '#!/bin/bash\nset -euo pipefail\necho hello\nls -la\nkill -0 $$ || true\n'
expect allow "harmless script" "bash ok.sh"
expect allow "harmless script, ./ form" "./ok.sh"
expect allow "missing script" "bash nothere.sh"
mkdir -p "$WORK/w/adir"
expect allow "directory" "bash adir"
python3 -c "open('$WORK/w/big.sh','w').write('echo x\n' * 50000 + 'gh release create v1\n')"
expect allow "file above 256 KiB" "bash big.sh"
printf '\177ELF\000\000gh release create v1\n' > "$WORK/w/bin.sh"
expect allow "binary file" "bash bin.sh"
put empty.sh ''
expect allow "empty file" "bash empty.sh"
put py.py '#!/usr/bin/env python3\n# gh release create v1\nprint(1)\n' 755
expect allow "directly started python script (not shell)" "./py.py"
put locked.sh 'gh release create v1\n'
if [ "$(id -u)" != 0 ]; then chmod 000 "$WORK/w/locked.sh"; expect allow "unreadable file" "bash locked.sh"; chmod 644 "$WORK/w/locked.sh"; fi
expect allow "stdin of a -c command is data" "bash -c 'echo hi' < rel.sh"
expect allow "not a run of the script" "cat rel.sh"
expect allow "not a run of the script (grep)" "grep release rel.sh"
expect allow "\$VAR path is not followed" 'bash $SCRIPT'
expect allow "glob path is not followed" 'bash *.sh'

echo "=== undecidable forms in a script do not count ==="
put var.sh 'D=$(mktemp -d)\nrm -rf "$D/x"\nmv "$D/a" "$D/b"\necho x > "$OUTFILE"\nkill "$PID" 2>/dev/null\ntmux -L "$SOCK" kill-server\n"$PY" tool.py\n'
expect allow "variable targets (rm, mv, >, kill, tmux) and dynamic command name" "bash var.sh"
put mask1.sh 'kill "$PID"\nrm -rf "$D"\npkill -f node\n'
expect deny "a decidable kill after undecidable lines is still found" "bash mask1.sh" "line 3"
put mask2.sh '"$PY" tool.py\ngh release create v1\n'
expect ask "a dynamic command name does not hide a later pattern" "bash mask2.sh" "line 2"
put mask3.sh 'echo "two\nlines"\ngh release create v1\n'
expect ask "a quote over two lines does not hide a later pattern" "bash mask3.sh" "line 3"

echo "=== structure of the script ==="
put here.sh 'cat <<EOF\ngh release create v1\nEOF\necho after\n'
expect allow "text inside a here-document is not a command" "bash here.sh"
put cont.sh 'echo a\ngh release create v1 \\\n  --title x\necho b\n'
expect ask "a continued command line" "bash cont.sh" "line 2"
put comment.sh '# gh release create v1\necho a # gh release create v1\n'
expect allow "comments are not commands" "bash comment.sh"
put inner.sh 'gh release create v1\n'
put outer.sh 'bash inner.sh\nsource inner.sh\n'
expect allow "one level deep: what the script starts is not followed" "bash outer.sh"

echo "=== typed command first, relative paths against the hook cwd ==="
guard "pkill -f node; bash ok.sh"
case "$DECISION:$REASON" in deny:*script*) FAIL=$((FAIL+1)); echo "  FAIL  typed refusal is reported as a script refusal";; deny:*) PASS=$((PASS+1)); echo "  PASS  typed refusal comes first, no script named";; *) FAIL=$((FAIL+1)); echo "  FAIL  typed pkill not refused";; esac
mkdir -p "$WORK/w/sub"; cp "$WORK/w/rel.sh" "$WORK/w/sub/rel.sh"
guard "bash sub/rel.sh" "$WORK/w"; [ "$DECISION" = ask ] && { PASS=$((PASS+1)); echo "  PASS  relative path resolves against cwd"; } || { FAIL=$((FAIL+1)); echo "  FAIL  relative path with cwd: $DECISION"; }
guard "bash sub/rel.sh" "$WORK/w/sub"; [ "$DECISION" = allow ] && { PASS=$((PASS+1)); echo "  PASS  same path against another cwd: file not found, previous behaviour"; } || { FAIL=$((FAIL+1)); echo "  FAIL  wrong cwd: $DECISION"; }

echo "=== exemption list ==="
mkdir -p "$XDG_CONFIG_HOME/work-kit"
printf '# scripts the human accepts\n*/w/rel.sh\n' > "$XDG_CONFIG_HOME/work-kit/guard-exceptions.conf"
expect allow "script matched by guard-exceptions.conf is not inspected" "bash rel.sh"
expect ask "another script is still inspected" "bash push.sh" "line 2"
rm -f "$XDG_CONFIG_HOME/work-kit/guard-exceptions.conf"

echo "=== no side effects of the inspection; approval binds to the script text ==="
rm -rf "$AWB_GUARD_BLOCKS_DIR"; rm -f "$AWB_GUARD_LOG"
export TMUX_PANE=%990
guard "bash ok.sh"
if [ ! -e "$AWB_GUARD_LOG" ] && [ -z "$(ls "$AWB_GUARD_BLOCKS_DIR" 2>/dev/null)" ]; then PASS=$((PASS+1)); echo "  PASS  a harmless script leaves no marker and no log entry"; else FAIL=$((FAIL+1)); echo "  FAIL  harmless script wrote marker or log"; fi
guard "bash kill.sh"
n=$(wc -l < "$AWB_GUARD_LOG" 2>/dev/null | tr -d ' ')
if [ "$n" = 1 ] && grep -q '"guard": "kill-pattern"' "$AWB_GUARD_LOG" && grep -q 'script kill.sh, line 5' "$AWB_GUARD_LOG"; then PASS=$((PASS+1)); echo "  PASS  one refusal: exactly one log entry, naming script and line"; else FAIL=$((FAIL+1)); echo "  FAIL  log after one refusal: $n line(s)"; fi
guard "bash rel.sh"
M1=$(python3 -c 'import json,sys,glob; print(json.load(open(glob.glob(sys.argv[1]+"/*.json")[0]))["command"])' "$AWB_GUARD_BLOCKS_DIR" 2>/dev/null)
K1=$(python3 -c 'import json,sys,glob; print(json.load(open(glob.glob(sys.argv[1]+"/*.json")[0])).get("schluessel",""))' "$AWB_GUARD_BLOCKS_DIR" 2>/dev/null)
case "$M1" in "bash rel.sh"*"# [script rel.sh sha256 "*) PASS=$((PASS+1)); echo "  PASS  the waiting question is bound to the command plus a hash of the script";; *) FAIL=$((FAIL+1)); echo "  FAIL  marker command: $M1";; esac
rm -rf "$AWB_GUARD_BLOCKS_DIR"
put rel.sh '#!/bin/bash\necho start\ngh release create v2 --title y\n' 755
guard "bash rel.sh"
K2=$(python3 -c 'import json,sys,glob; print(json.load(open(glob.glob(sys.argv[1]+"/*.json")[0])).get("schluessel",""))' "$AWB_GUARD_BLOCKS_DIR" 2>/dev/null)
if [ -n "$K1" ] && [ -n "$K2" ] && [ "$K1" != "$K2" ]; then PASS=$((PASS+1)); echo "  PASS  an edited script gets another approval key"; else FAIL=$((FAIL+1)); echo "  FAIL  approval key unchanged after editing the script ('$K1' '$K2')"; fi
unset TMUX_PANE

echo "=== with 32-harness-profiles (kit-guard) installed: its checks run over the script too ==="
KG="${KIT_GUARD_DIR:-$HOOKS_DIR/../../../32-harness-profiles/guard}"
if [ -f "$KG/lib/checks.py" ]; then
  mkdir -p "$KIT_DATA_DIR/harness-profiles" && cp -R "$KG" "$KIT_DATA_DIR/harness-profiles/guard"
  POLICY_FILE="$XDG_CONFIG_HOME/work-kit/guard.conf"
  mkdir -p "$(dirname "$POLICY_FILE")"
  expect deny "policy redirect" "echo commit=allow > $POLICY_FILE" "the human edits"
  put policy.sh "echo commit=allow > $POLICY_FILE\n"
  expect deny "policy redirect in a script" "bash policy.sh" "script policy.sh, line 1" "the human edits"
  put sec.sh "echo a\nexport API_KEY=$FAKE_KEY\n"
  expect allow "secret text in a script is typed-only" "bash sec.sh"
  put c.sh 'echo a\ngit commit -m x\n'
  expect allow "commit policy in a script is typed-only" "bash c.sh"
  expect allow "KIT_COMMIT_OK=1 in front of the script command" "KIT_COMMIT_OK=1 bash c.sh"
  put routine.sh "git add -A\ntmux -L private set-option -p @wb_role worker\nrm -rf $WORK/victim-data\nexport API_KEY=$FAKE_KEY\n"
  expect allow "routine test operations stay typed-only" "bash routine.sh"
  put nonpublish.sh 'npm run publish\ngh repo create demo --private\n'
  expect allow "nonpublication command names in a script" "bash nonpublish.sh"
  put trailer.sh 'git commit -m "fix\nCo-Authored-By: Claude <noreply@anthropic.com>"\n'
  expect deny "commit trailer in script" "bash trailer.sh" "script trailer.sh" "trailer"
  # publish question: asked ONCE. What the workbench question stage holds goes through its queue (kit-guard
  # defers); what it does not cover is asked by kit-guard as a native "ask".
  expect ask "git push --force: the workbench question stage (queue)" "git push --force origin main" "QUESTION"
  expect ask "docker push: kit-guard's own ask" "docker push img:1" "kit-guard (publish)"
  for pub in 'gh repo create demo --public' 'gh release upload v1 a.zip' 'gh release edit v1' \
             'gh release delete v1' 'gh pr merge 12' 'gh repo edit --visibility public' \
             'docker push img:1' 'podman push img:1' 'uv publish' 'twine upload dist/a.whl' \
             'cargo publish'; do
    expect ask "publish typed: $pub" "$pub"
    put publish.sh "$pub\n"
    expect ask "publish in script: $pub" 'bash publish.sh' 'script publish.sh, line 1'
  done
  expect allow "KIT_PUBLISH_OK=1 docker push" "KIT_PUBLISH_OK=1 docker push img:1"
  expect allow "normal git push" "git push origin main"
  put dock.sh 'echo a\ndocker push img:1\n'
  expect ask "docker push inside a script" "bash dock.sh" "script dock.sh, line 2" "kit-guard (publish)"
  expect allow "KIT_PUBLISH_OK=1 in front of the script command" "KIT_PUBLISH_OK=1 bash dock.sh"
  expect ask "publish approval on an earlier command does not cover the script" "KIT_PUBLISH_OK=1 echo ok; bash dock.sh" "script dock.sh"
  guard "gh release create v1"; ONE=$(printf '%s' "$OUT" | grep -c .)
  [ "$ONE" = 1 ] && { PASS=$((PASS+1)); echo "  PASS  one answer only (asked once, not twice)"; } || { FAIL=$((FAIL+1)); echo "  FAIL  $ONE answers for one publish command"; }
else
  echo "  SKIP  kit-guard sources not found ($KG)"
fi

echo
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
