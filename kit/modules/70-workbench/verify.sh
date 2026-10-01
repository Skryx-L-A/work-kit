#!/usr/bin/env bash
# Check the installed agent workbench.
#
#   bash verify.sh               checks of the installation in $HOME (no tmux, nothing started)
#   bash verify.sh --temp-home   installs into a fresh temporary HOME, runs all checks there plus
#                                an end-to-end spawn on a private tmux socket with a stand-in
#                                agent, then uninstalls and checks that nothing is left
#
# Exit 0 = all checks passed. Every process this script starts is stopped before it exits.
#
# This script never hangs: it reads no input (stdin is /dev/null), every external step runs
# under a time limit (a step that hits it is reported as FAIL and the run goes on), and a
# watchdog ends the whole run after WB_VERIFY_MAX_SECS (default 1500) with a FAIL naming the
# step that was running. WB_VERIFY_STEP_SECS (default 45) is the limit of one short step.
set -uo pipefail
exec </dev/null
export GIT_TERMINAL_PROMPT=0 GIT_EDITOR=true GIT_PAGER=cat PAGER=cat

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }
note() { printf '        %s\n' "$*"; }

# wbt SECONDS CMD...: run CMD under a time limit (exit 124 when it was stopped). Uses timeout(1) or
# gtimeout when present, else a shell watchdog; the limit applies to the whole process group.
# kill_tree SIGNAL PID: signal PID and every process below it, children first.
kill_tree() { local c; for c in $(pgrep -P "$2" 2>/dev/null); do kill_tree "$1" "$c"; done; kill "-$1" "$2" 2>/dev/null; return 0; }
WBT_BIN=""
if [ -z "${WB_VERIFY_NO_TIMEOUT_BIN:-}" ]; then WBT_BIN="$(command -v timeout || command -v gtimeout || true)"; fi
wbt() {
  local secs="$1" pid wd rc flag; shift
  if [ -n "$WBT_BIN" ]; then "$WBT_BIN" -k 5 "$secs" "$@"; return $?; fi
  flag="$(mktemp "${TMPDIR:-/tmp}/wbv-to.XXXXXX")"; rm -f "$flag"
  "$@" <&0 & pid=$!
  ( sleep "$secs"; : > "$flag"; kill_tree TERM "$pid"; sleep 3; kill_tree KILL "$pid" ) >/dev/null 2>&1 & wd=$!
  wait "$pid" 2>/dev/null; rc=$?
  kill_tree TERM "$wd"; wait "$wd" 2>/dev/null
  if [ -e "$flag" ]; then rm -f "$flag"; rc=124; fi
  return "$rc"
}
# section TITLE: print the header and remember it for the watchdog.
STEPFILE="$(mktemp "${TMPDIR:-/tmp}/wbv-step.XXXXXX")"
section() { echo "== $*"; printf '%s' "$*" > "$STEPFILE"; }
# timed_out RC WHAT: FAIL line when a step was stopped by its time limit.
timed_out() { [ "$1" = 124 ] || [ "$1" = 137 ] || return 1; bad "$2: no answer within its time limit (stopped)"; return 0; }
WB_VERIFY_MAX_SECS="${WB_VERIFY_MAX_SECS:-1500}"
WB_S="${WB_VERIFY_STEP_SECS:-45}"   # limit of a short step (one command, one guard call)
WATCHDOG=""
watchdog_stop() {
  if [ -n "$WATCHDOG" ]; then kill_tree TERM "$WATCHDOG"; wait "$WATCHDOG" 2>/dev/null; WATCHDOG=""; fi
  rm -f "$STEPFILE" "$STEPFILE.expired"
}
on_signal() {
  if [ -e "$STEPFILE.expired" ]; then bad "verify.sh ran longer than $WB_VERIFY_MAX_SECS s and was stopped (step: $(cat "$STEPFILE" 2>/dev/null))"
  else bad "verify.sh was interrupted (step: $(cat "$STEPFILE" 2>/dev/null))"; fi
  echo; echo "verify: $PASS passed, $FAIL failed"
  exit 1
}
trap on_signal INT TERM
trap watchdog_stop EXIT
# The watchdog polls (no long sleep that could outlive the script) and touches no output stream: it
# stops what the script is waiting for, then signals the script, whose handler reports the FAIL.
SELF=$$
( me="$(sh -c 'echo $PPID')"; i=0
  while [ "$i" -lt "$WB_VERIFY_MAX_SECS" ]; do
    sleep 1; kill -0 "$SELF" 2>/dev/null || exit 0; i=$((i + 1))
  done
  : > "$STEPFILE.expired"
  for c in $(pgrep -P "$SELF" 2>/dev/null); do [ "$c" = "$me" ] || kill_tree TERM "$c"; done
  kill -TERM "$SELF" 2>/dev/null ) >/dev/null 2>&1 &
WATCHDOG=$!
# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
# shellcheck source=tests/temp_home.sh
. "$HERE/tests/temp_home.sh"

TEMP=0
[ "${1:-}" = "--temp-home" ] && TEMP=1

if [ "$TEMP" = 1 ]; then
  REAL_HOME="$HOME"
  # Not below /tmp: the snapshot guard exempts temporary folders, and its check must bite here.
  mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}"
  T="$(cd "$(mktemp -d "${XDG_CACHE_HOME:-$HOME/.cache}/wb-verify.XXXXXX")" && pwd -P)"
  SOCKET="wbverify$$"
  # Prerequisites from the real HOME (01-prereqs, 10-base-tools wrappers in ~/.local/bin) stay
  # usable through links in $T/shim; resolved before PATH drops the real ~/.local/bin.
  wb_th_tools "$REAL_HOME" "$T/shim"
  TMUX_REAL="$(command -v tmux || true)"
  export HOME="$T/home"
  mkdir -p "$HOME"
  # Python (00-python): the caller's kit CPython, linked into the test HOME, or a fresh
  # 00-python install there; the installer finds it exactly as on a laptop without python3.
  if TPY="$(wb_th_python "$REAL_HOME" "$HOME")"; then note "python for the test HOME: $TPY"; fi
  unset KIT_DATA_DIR KIT_BIN_DIR KIT_TOOL_DIR
  # Git reads the global config from HOME; make sure no outside config leaks in.
  unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME TMUX TMUX_PANE
  # The real ~/.local/bin stays out of PATH, so nothing of an existing installation is used.
  CLEAN_PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vx "$REAL_HOME/.local/bin" | paste -sd: -)"
  export PATH="$T/shim:$HOME/.local/bin:$CLEAN_PATH"
  if [ -n "$TMUX_REAL" ]; then
    rm -f "$T/shim/tmux"
    printf '#!/bin/sh\nexec "%s" -L "%s" "$@"\n' "$TMUX_REAL" "$SOCKET" > "$T/shim/tmux"
    chmod +x "$T/shim/tmux"
  fi
  # The second-machine branch is stripped: nothing may reach for SSH. Stand-ins log each try.
  for t in ssh scp; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 255\n' "$t" "$T/ssh.log" > "$T/shim/$t"
    chmod +x "$T/shim/$t"
  done
  cleanup() {
    if [ -x "$HOME/.local/bin/context-guard" ]; then
      wbt "$WB_S" "$HOME/.local/bin/context-guard" --stop --all >/dev/null 2>&1 || true
    fi
    [ -n "$TMUX_REAL" ] && wbt "$WB_S" "$TMUX_REAL" -L "$SOCKET" kill-server 2>/dev/null
    # Guards and watchers started in this HOME end with their tmux server; wait for them.
    local d=$((SECONDS + 20))
    while [ $SECONDS -lt $d ] && pgrep -f "$T/home" >/dev/null 2>&1; do sleep 1; done
    # Normally nothing is left here (checked above). After an aborted run, stop what this
    # test started: only processes whose command line names this test's own HOME.
    pgrep -f "$T/home" >/dev/null 2>&1 && pkill -f "$T/home" 2>/dev/null
    rm -f "/tmp/tmux-$(id -u)/$SOCKET" "/private/tmp/tmux-$(id -u)/$SOCKET"
    rm -rf "$T"
  }
  trap 'cleanup; watchdog_stop' EXIT
  section "install into temporary HOME $HOME"
  VSC_ARGS=""
  command -v code >/dev/null && VSC_ARGS="--extensions-dir $T/vscode-ext --user-data-dir $T/vscode-data"
  WB_INSTALL_SECS="${WB_VERIFY_INSTALL_SECS:-900}"
  WB_VSCODE_ARGS="$VSC_ARGS" wbt "$WB_INSTALL_SECS" bash "$HERE/install.sh" > "$T/install.log" 2>&1; rc=$?
  if [ "$rc" = 0 ]; then
    ok "install.sh exit 0"
  else
    timed_out "$rc" "install.sh" || bad "install.sh failed"; sed 's/^/        /' "$T/install.log"
  fi
  if WB_VSCODE_ARGS="$VSC_ARGS" wbt "$WB_INSTALL_SECS" bash "$HERE/install.sh" > "$T/install2.log" 2>&1 \
     && ! grep -q 'backup:' "$T/install2.log" && grep -q 'workerLayout refreshed to window' "$T/install2.log"; then
    ok "second install run is idempotent (no backups, nothing replaced)"
  else
    bad "second install run changed files"; grep 'backup\|files:' "$T/install2.log" | sed 's/^/        /'
  fi
  # A recorded kit default refreshes on reinstall; a user-selected layout stays put and
  # receives the current default beside the settings file.
  wbt "$WB_S" "$HOME/.local/bin/wb-state" settings set workerLayout split >/dev/null
  # Upgrade path: an earlier kit shipped tools a later one strips. The manifest of the earlier
  # install records them; a reinstall removes the unchanged one and backs up the changed one.
  UPG_DATA="$HOME/.local/share/work-kit/workbench"
  printf '#!/bin/sh\necho old\n' > "$HOME/.local/bin/wb-old-stripped"
  printf '#!/bin/sh\necho old\n' > "$HOME/.local/bin/wb-old-edited"
  mkdir -p "$HOME/.claude/hooks/old-lib"; printf 'x = 1\n' > "$HOME/.claude/hooks/old-lib/gone.py"
  # Earlier kits installed a mail-account tool and templates into ~/.local/bin (VM test 2026-09-26).
  OLD_TEMPLATES="wb-totp mailkonten.example.json limit-anker.default.json profile-settings.json wb-self-close.tmux.conf setup-vscode-profile.sh"
  for n in $OLD_TEMPLATES; do printf 'old\n' > "$HOME/.local/bin/$n"; done
  # shellcheck disable=SC2086
  "$(kit_find_python)" - "$UPG_DATA/manifest.json" "$HOME" $OLD_TEMPLATES <<'PY'
import hashlib, json, sys
m = json.load(open(sys.argv[1])); h = sys.argv[2]
d = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
for p in (h + "/.local/bin/wb-old-stripped", h + "/.claude/hooks/old-lib/gone.py"):
    m["files"][p] = d(p)
for n in sys.argv[3:]:
    m["files"][h + "/.local/bin/" + n] = d(h + "/.local/bin/" + n)
m["files"][h + "/.local/bin/wb-old-edited"] = "0" * 64   # changed by the user since then
json.dump(m, open(sys.argv[1], "w"), indent=1)
PY
  WB_VSCODE_ARGS="$VSC_ARGS" wbt "$WB_INSTALL_SECS" bash "$HERE/install.sh" > "$T/install3.log" 2>&1 \
    || timed_out "$?" "install.sh (upgrade run)"
  if [ "$(wbt "$WB_S" "$HOME/.local/bin/wb-state" settings get workerLayout 2>/dev/null)" = split ] \
     && [ "$(cat "$HOME/.claude/workbench/workerLayout.kit-new" 2>/dev/null)" = window ]; then
    ok "edited workerLayout kept; new default written as workerLayout.kit-new"
  else
    bad "edited workerLayout was changed or has no kit-new"
  fi
  rm -f "$UPG_DATA/default-settings.json" "$HOME/.claude/workbench/workerLayout.kit-new"
  wbt "$WB_S" "$HOME/.local/bin/wb-state" settings set workerLayout split >/dev/null
  wbt "$WB_S" bash "$HERE/install.sh" --no-hooks --no-vscode --no-app > "$T/install4.log" 2>&1 || bad "foreign-layout reinstall failed"
  if [ "$(wbt "$WB_S" "$HOME/.local/bin/wb-state" settings get workerLayout 2>/dev/null)" = split ] \
     && [ ! -e "$HOME/.claude/workbench/workerLayout.kit-new" ]; then
    ok "pre-existing workerLayout without kit state kept"
  else
    bad "pre-existing workerLayout without kit state changed"
  fi
  wbt "$WB_S" "$HOME/.local/bin/wb-state" settings set workerLayout window >/dev/null
  bk="$(find "$HOME/.local/share/work-kit/backups/70-workbench/.local/bin" -name 'wb-old-edited.bak-*' 2>/dev/null | head -1)"
  if [ ! -e "$HOME/.local/bin/wb-old-stripped" ] && [ ! -e "$HOME/.local/bin/wb-old-edited" ] \
     && [ ! -e "$HOME/.claude/hooks/old-lib" ] && [ -n "$bk" ] \
     && ! grep -q 'wb-old-' "$UPG_DATA/manifest.json"; then
    ok "reinstall removes files a newer payload no longer ships (changed one backed up first)"
  else
    bad "upgrade path: files of the previous manifest left or not backed up"; grep 'backup\|removed\|files:' "$T/install3.log" | sed 's/^/        /'
  fi
  left=""
  for n in $OLD_TEMPLATES; do [ -e "$HOME/.local/bin/$n" ] && left="$left $n"; done
  [ -z "$left" ] && ok "reinstall removes the old mail tool and templates from ~/.local/bin" \
    || bad "old copies still in ~/.local/bin:$left"
  if [ -n "$VSC_ARGS" ]; then
    # shellcheck disable=SC2086
    if wbt "$WB_S" code $VSC_ARGS --list-extensions 2>/dev/null | grep -qi 'claude-workbench'; then
      ok "VS Code extension installed (own extensions folder)"
    else
      bad "VS Code extension not listed"
    fi
  else
    note "VS Code CLI not found: extension install not checked"
  fi
fi

PY="$(kit_find_python)" || { bad "no python: $(kit_python_hint)"; echo "verify: $PASS passed, $FAIL failed"; exit 1; }
# The installer's ~/.local/bin/python3 link goes away with uninstall.sh: use its target.
if [ -L "$PY" ] && [ "$PY" = "$HOME/.local/bin/python3" ]; then PY="$(readlink "$PY")"; fi
python3() { wbt "$WB_S" "$PY" "$@"; }
BIN="$HOME/.local/bin"
DATA="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/workbench"

section "installed files"
if [ -f "$DATA/manifest.json" ]; then
  miss="$(python3 - "$DATA/manifest.json" <<'PY'
import json, os, sys
m = json.load(open(sys.argv[1]))["files"]
print(sum(1 for p in m if not os.path.isfile(p)))
PY
)"
  [ "$miss" = 0 ] && ok "every file of the manifest is present" || bad "$miss files of the manifest are missing"
else
  bad "no manifest at $DATA/manifest.json (not installed?)"
fi
# Depersonalization placeholders (<your-github-user> and the like) must be filled in at install.
ph="$(python3 - "$DATA/manifest.json" "$HOME" <<'PY' 2>/dev/null
import glob, json, os, re, sys
files = [p for p in json.load(open(sys.argv[1]))["files"] if p.endswith(".json")]
h = sys.argv[2]
files += glob.glob(h + "/.claude/workbench/*.json") + [h + "/.claude/settings.json"]
pat = re.compile(r"<your-[a-z0-9-]+>")
hits = sorted({f for f in files if os.path.isfile(f) and pat.search(open(f, errors="replace").read())})
print(" ".join(hits))
PY
)"
[ -z "$ph" ] && ok "no <your-...> placeholder left in installed JSON" || bad "placeholder left in: $ph"
for c in wb-code claude-worker pi-worker context-guard wb-result wb-close wb-state wb-grid \
         wb-pane-write wb-freigabe wb-brain-zeile wb-worktree wb-request wb-decide wb-revive; do
  [ -x "$BIN/$c" ] || bad "$c missing or not executable in $BIN"
done
ok "core commands present"
# ~/.local/bin holds tools and the data files they read next to themselves, no templates or examples.
stray_data="$(python3 - "$DATA/manifest.json" "$BIN" <<'PY' 2>/dev/null
import json, os, re, sys
ok = {"models.default.json", "wb-profil-gesperrt.json"}
pat = re.compile(r"(\.(json|toml|conf|ya?ml)$|\.example|\.default\.)", re.I)
print(" ".join(sorted(os.path.basename(p) for p in json.load(open(sys.argv[1]))["files"]
                      if os.path.dirname(p) == sys.argv[2] and pat.search(os.path.basename(p)) and os.path.basename(p) not in ok)))
PY
)"
[ -z "$stray_data" ] && ok "no template or example file installed to ~/.local/bin" || bad "template or data file in ~/.local/bin: $stray_data"
# Several hooks read their JSON input with jq and let everything through without it.
if command -v jq >/dev/null 2>&1; then ok "jq on PATH (hooks, status line)"; else bad "jq missing: live-config and commit-trailer guards fail open (kit module 10-base-tools)"; fi

syntax_bad=""
# Only the workbench's own tools: other kit modules put launchers of their own kind there.
wb_bin="$(python3 - "$DATA/manifest.json" "$BIN" <<'PY' 2>/dev/null
import json, os, sys
print("\n".join(p for p in json.load(open(sys.argv[1]))["files"] if os.path.dirname(p) == sys.argv[2]))
PY
)"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  first="$(head -c 80 "$f" 2>/dev/null | tr -d '\0' | head -1)"
  case "$first" in
    '#!'*bash*|'#!/bin/sh'*) bash -n "$f" 2>/dev/null || syntax_bad="$syntax_bad $(basename "$f")" ;;
    '#!'*python*) python3 -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$f" 2>/dev/null \
                    || syntax_bad="$syntax_bad $(basename "$f")" ;;
  esac
done <<<"$wb_bin"
n_bin="$(printf '%s\n' "$wb_bin" | grep -c .)"
if [ -n "$syntax_bad" ]; then bad "syntax errors:$syntax_bad"
elif [ "$n_bin" -gt 0 ]; then ok "every installed shell and Python tool parses ($n_bin files)"
else bad "no workbench tools found in the manifest"; fi

section "referenced paths exist (instruction files, hooks, registry)"
out="$(python3 "$HERE/tests/check_paths.py")"; rc=$?
if [ "$rc" = 0 ]; then ok "$out"; else timed_out "$rc" "path check" || bad "dangling references"; printf '%s\n' "$out" | sed 's/^/        /'; fi

section "settings"
layout="$(wbt "$WB_S" "$BIN/wb-state" settings get workerLayout 2>/dev/null)"
[ "$layout" = window ] && ok "workerLayout=window" || bad "workerLayout is '$layout', expected window"
n_models="$(wbt "$WB_S" "$BIN/wb-state" models list 2>/dev/null | grep -c . || true)"
[ "${n_models:-0}" -gt 0 ] && ok "model registry answers ($n_models lines)" || bad "wb-state models list is empty"
if [ -f "$HOME/.claude/settings.json" ]; then
  WB_VERIFY_TEMP="$TEMP" python3 - "$HOME/.claude/settings.json" <<'PY' && ok "Claude settings: hooks, status line, attribution off, permission mode" || bad "Claude settings incomplete"
import json, os, sys
s = json.load(open(sys.argv[1]))
cmds = [h["command"] for g in s.get("hooks", {}).get("PreToolUse", []) for h in g.get("hooks", [])]
assert any("bash-guard.py" in c for c in cmds), "bash-guard not registered"
assert "statusline" in s.get("statusLine", {}).get("command", ""), "no status line"
a = s.get("attribution", {})
assert a.get("commit") == "" and a.get("pr") == "", "attribution not off"
if os.environ.get("WB_VERIFY_TEMP") == "1":
    assert s.get("permissions", {}).get("defaultMode") == "bypassPermissions", "default mode not bypass"
PY
else
  note "no ~/.claude/settings.json (installed with --no-hooks?)"
fi
# Hook timeouts (finding F23): a PreToolUse hook that times out lets the tool run unguarded.
ht_args=()
[ -f "$HOME/.claude/settings.json" ] && ht_args=("$HOME/.claude/settings.json")
out="$(wbt "$WB_S" python3 "$HERE/tests/test-hook-timeouts.py" ${ht_args[@]+"${ht_args[@]}"} 2>&1)"; rc=$?
if [ "$rc" = 0 ]; then ok "$(printf '%s\n' "$out" | tail -1) (guards >= 60 s, others >= 30 s)"; else timed_out "$rc" "hook timeout test" || bad "hook timeouts too low"; printf '%s\n' "$out" | grep FAIL | sed 's/^/        /'; fi
hp="$(wbt "$WB_S" git config --global --get core.hooksPath 2>/dev/null || true)"
case "$hp" in
  "$HOME/.claude/git-hooks") ok "git: core.hooksPath is the workbench's co-author stripping dispatcher" ;;
  "${XDG_CONFIG_HOME:-$HOME/.config}/work-kit/git-hooks") ok "git: core.hooksPath is kit-sync's dispatcher (30-agent-setup)" ;;
  *) note "git: core.hooksPath is '${hp:-unset}' (see install output)" ;;
esac

section "kit fixes"
# 1: brain step switchable
z_off="$(WB_BRAIN_STEP=off wbt "$WB_S" "$BIN/wb-brain-zeile" "$HOME")"
case "$z_off" in *"No knowledge-base search"*) ok "brain step off per task (WB_BRAIN_STEP=off)" ;; *) bad "brain step off: '$z_off'" ;; esac
mkdir -p "${TMPDIR:-/tmp}/wbv-proj$$" && touch "${TMPDIR:-/tmp}/wbv-proj$$/.wb-ohne-brain"
z_proj="$(wbt "$WB_S" env -u WB_BRAIN_STEP "$BIN/wb-brain-zeile" "${TMPDIR:-/tmp}/wbv-proj$$")"
# The project marker wins over the task switch: --brain on never brings brain content in.
z_proj_on="$(WB_BRAIN_STEP=on wbt "$WB_S" "$BIN/wb-brain-zeile" "${TMPDIR:-/tmp}/wbv-proj$$")"
rm -rf "${TMPDIR:-/tmp}/wbv-proj$$"
case "$z_proj" in *"No knowledge-base search"*) ok "brain step off per project (.wb-ohne-brain)" ;; *) bad "project marker ignored: '$z_proj'" ;; esac
case "$z_proj_on" in *"No knowledge-base search"*) ok "project marker wins over --brain on" ;; *) bad "--brain on overrode the project marker: '$z_proj_on'" ;; esac
if command -v brain >/dev/null 2>&1 || [ -x "$BIN/brain" ]; then
  z_on="$(WB_BRAIN_STEP=on wbt "$WB_S" "$BIN/wb-brain-zeile" "$HOME")"
  case "$z_on" in *"brain search"*) ok "brain step on (kit brain installed)" ;; *) bad "brain step on: '$z_on'" ;; esac
else
  z_on="$(WB_BRAIN_STEP=on wbt "$WB_S" env PATH=/usr/bin:/bin "$BIN/wb-brain-zeile" "$HOME")"
  [ -z "$z_on" ] && ok "no brain CLI installed: no search step" || bad "search step without brain CLI: '$z_on'"
fi
# Worker spawners mark their panes as workers for 32-harness-profiles (end to end: --temp-home).
miss=""; for c in pi-worker wb-pi wb-agent; do grep -q 'KIT_AGENT_ROLE=worker' "$BIN/$c" 2>/dev/null || miss="$miss $c"; done
[ -z "$miss" ] && ok "worker spawners set KIT_AGENT_ROLE=worker" || bad "KIT_AGENT_ROLE=worker missing in:$miss"
# 4: a waiting question can be withdrawn by its own pane
GB="$(mktemp -d "${TMPDIR:-/tmp}/wbv-gb.XXXXXX")"
printf '{"pane":"%%990","wartet":true,"command":"sudo true","cwd":"/"}' > "$GB/_990.json"
if AWB_GUARD_BLOCKS_DIR="$GB" AWB_GUARD_LOG="$GB/log" TMUX_PANE=%990 wbt "$WB_S" "$BIN/wb-freigabe" zurueckziehen >/dev/null 2>&1 \
   && [ ! -e "$GB/_990.json" ]; then ok "wb-freigabe zurueckziehen removes the own waiting question"; else bad "zurueckziehen failed"; fi
printf '{"pane":"%%991","wartet":true,"command":"sudo true","cwd":"/"}' > "$GB/_991.json"
wbt "$WB_S" "$BIN/wb-mensch" pruefen >/dev/null 2>&1; mrc=$?
if timed_out "$mrc" "wb-mensch pruefen"; then :
elif [ "$mrc" = 0 ]; then
  note "caller measured as a human: withdrawing another pane's question is allowed by design, not checked"
else
  AWB_GUARD_BLOCKS_DIR="$GB" AWB_GUARD_LOG="$GB/log" TMUX_PANE=%990 wbt "$WB_S" "$BIN/wb-freigabe" zurueckziehen %991 </dev/null >/dev/null 2>&1
  [ -e "$GB/_991.json" ] && ok "an agent cannot withdraw another pane's question" || bad "an agent withdrew another pane's question"
fi
rm -rf "$GB"
# guards answer
# guard CMD: what bash-guard.py answers for CMD. A guard that does not answer within $WB_S s yields the
# text "wbv-guard-timeout" (every check below reports it as FAIL) instead of hanging the run.
guard() {
  local out rc
  out="$(printf '{"tool_name":"Bash","tool_input":{"command":%s},"cwd":"%s"}' \
    "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" "$HOME" \
    | AWB_GUARD_BLOCKS_DIR="${TMPDIR:-/tmp}/wbv-gb$$" AWB_GUARD_LOG="${TMPDIR:-/tmp}/wbv-gb$$.log" TMUX_PANE= \
      wbt "$WB_S" "$PY" "$HOME/.claude/hooks/bash-guard.py" 2>&1)"; rc=$?
  if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then printf 'wbv-guard-timeout'; else printf '%s' "$out"; fi
}
case "$(guard 'pkill -f python')" in *wbv-guard-timeout*) bad "bash guard (pkill): no answer within $WB_S s" ;; *deny*) ok "bash guard refuses a broad pkill" ;; *) bad "broad pkill not refused" ;; esac
case "$(guard 'ls -la')" in *wbv-guard-timeout*) bad "bash guard (ls): no answer within $WB_S s" ;; *deny*) bad "bash guard refuses a harmless ls" ;; *) ok "bash guard lets a harmless command through" ;; esac
# One Bash guard for Claude Code: with 32-harness-profiles installed, bash-guard.py runs kit-guard's
# checks and kit-guard's own PreToolUse entry is gone.
if [ -f "${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/harness-profiles/guard/lib/checks.py" ]; then
  case "$(guard 'git commit --no-verify -m x')" in *wbv-guard-timeout*) bad "bash guard (kit-guard checks): no answer within $WB_S s" ;; *kit-guard*deny*|*deny*kit-guard*) ok "bash guard runs kit-guard's checks (32-harness-profiles)" ;; *) bad "kit-guard's checks not run by bash-guard.py" ;; esac
  if [ -f "$HOME/.claude/settings.json" ] && python3 - "$HOME/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
pre = [h["command"] for g in s.get("hooks", {}).get("PreToolUse", []) if "Bash" in (g.get("matcher") or "")
       for h in g.get("hooks", [])]  # kit-guard's Write|Edit entry (policy files) is wanted
sys.exit(1 if any("kit-guard" in c and c.rstrip().endswith("hook claude") for c in pre) else 0)
PY
  then ok "one PreToolUse Bash guard (kit-guard's Claude entry not registered twice)"; else bad "kit-guard and bash-guard both registered for Claude Bash"; fi
fi
# 5: snapshot mandatory when possible, not blocking when impossible
SN="$HOME/wbv-snap$$"; mkdir -p "$SN"; printf 'data\n' > "$SN/file.txt"
case "$(guard "rm -rf $SN")" in *wbv-guard-timeout*) bad "bash guard (delete without snapshot): no answer within $WB_S s" ;; *snapshot*) ok "delete without snapshot is refused (snapshot possible)" ;; *) bad "delete without snapshot passed" ;; esac
chmod 000 "$SN"
case "$(guard "rm -rf $SN")" in *wbv-guard-timeout*) bad "bash guard (unreadable target): no answer within $WB_S s" ;; *snapshot*) bad "unreadable target still blocked (no snapshot possible)" ;; *) ok "unreadable target: no snapshot possible, not blocked" ;; esac
chmod 700 "$SN"; rm -rf "$SN" "${TMPDIR:-/tmp}/wbv-gb$$" "${TMPDIR:-/tmp}/wbv-gb$$.log"
# 6: co-author trailer stripped by the git hook dispatcher
if [ "$hp" = "$HOME/.claude/git-hooks" ] || [ "$hp" = "${XDG_CONFIG_HOME:-$HOME/.config}/work-kit/git-hooks" ]; then
  R="$(mktemp -d "${TMPDIR:-/tmp}/wbv-git.XXXXXX")"
  # Output goes to a file: a hook that leaves a background job (brain reindex) must not hold this run's pipe.
  wbt "$WB_S" git -C "$R" init -q >"$R.out" 2>&1
  wbt 120 git -C "$R" -c user.name=t -c user.email=t@example.invalid \
    commit -q --allow-empty -m "test" -m "Co-authored-by: Some Agent <agent@example.invalid>" >>"$R.out" 2>&1; rc=$?
  if timed_out "$rc" "git commit through the hook dispatcher"; then sed 's/^/        /' "$R.out" | tail -5
  elif [ "$rc" != 0 ]; then bad "git commit through the hook dispatcher failed (exit $rc)"; sed 's/^/        /' "$R.out" | tail -5
  elif wbt "$WB_S" git -C "$R" log -1 --format=%B | grep -qi 'co-authored-by'; then bad "co-author line survived the commit"
  else ok "git hook strips Co-authored-by lines"; fi
  rm -rf "$R" "$R.out"
fi

if [ "$TEMP" = 1 ] && [ -n "${TMUX_REAL:-}" ]; then
  section "end-to-end: wb-code session, two workers, results (private tmux socket)"
  # Stand-in agent as 'claude' in the test HOME; the registry's claude harness starts it.
  printf '#!/bin/sh\nFAKE_LOG="%s" exec "%s" "%s"\n' "$T/agent.log" "$PY" "$HERE/tests/fake_agent.py" > "$BIN/claude"
  chmod +x "$BIN/claude"
  PROJ="$T/project"; mkdir -p "$PROJ"
  # A bare spawner call prints its usage and starts nothing (no session, no guard, no agent).
  bare_rc=""
  for c in wb-code claude-worker pi-worker wb-pi wb-agent; do
    (cd "$PROJ" && wbt "$WB_S" env -u TMUX "$BIN/$c" >/dev/null 2>&1); rc=$?; [ "$rc" = 2 ] || bare_rc="$bare_rc $c=$rc"
  done
  if [ -z "$bare_rc" ] && [ -z "$(wbt "$WB_S" tmux list-sessions 2>/dev/null)" ] && ! pgrep -f "$T/home/.local/bin/context-guard" >/dev/null 2>&1; then
    ok "bare wb-code/claude-worker/pi-worker/wb-pi/wb-agent print usage and start nothing"
  else
    bad "bare spawner call:${bare_rc:- started a session}"
  fi
  # wb-code attaches to the session it creates; a detached launcher session is its terminal.
  wbt "$WB_S" tmux -f /dev/null new-session -d -s launcher -x 220 -y 60 "$BIN/wb-code $PROJ; sleep 3600"
  WBS=""; d=$((SECONDS + 60))
  while [ $SECONDS -lt $d ]; do
    WBS="$(wbt "$WB_S" tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^wb-project-' | head -1)"
    [ -n "$WBS" ] && break; sleep 1
  done
  if [ -n "$WBS" ]; then ok "wb-code created the session $WBS"; else bad "wb-code created no wb-project-* session"; WBS=wb-missing; fi
  ORCH=""; d=$((SECONDS + 30))
  while [ $SECONDS -lt $d ] && [ -z "$ORCH" ]; do
    ORCH="$(wbt "$WB_S" tmux list-panes -s -t "=$WBS" -F '#{pane_id} #{@wb_role}' 2>/dev/null | awk '$2=="orchestrator"{print $1; exit}')"
    [ -n "$ORCH" ] || sleep 1
  done
  [ -n "$ORCH" ] && ok "orchestrator pane tagged ($ORCH)" || bad "no pane with @wb_role=orchestrator"
  ls "$HOME/.claude/workbench/sessions/"*.json >/dev/null 2>&1 && ok "session state file written" || bad "no session state file"
  for w in alpha beta; do
    out="$(WB_SESSION="$WBS" WB_BRAIN_STEP=off wbt 120 "$BIN/claude-worker" "v$w$$" sonnet "$PROJ" "Say hello ($w)." 2>&1)"; rc=$?
    case "$out" in
      *"Submission verifiziert"*|*"verified"*) ok "worker $w: task delivered and submission verified" ;;
      *) timed_out "$rc" "worker $w: claude-worker" || bad "worker $w: spawn rc=$rc"; printf '%s\n' "$out" | tail -8 | sed 's/^/        /' ;;
    esac
  done
  grep -q '\[Protocol — always follow\]' "$T/agent.log" 2>/dev/null \
    && ok "protocol line is English" || bad "no English protocol line in the delivered task"
  # Worker panes are workers for 32-harness-profiles; the wb-code orchestrator keeps its role.
  n_w="$(grep -cx worker "$T/agent.log.roles" 2>/dev/null)"; n_o="$(grep -vcx worker "$T/agent.log.roles" 2>/dev/null)"
  if [ "${n_w:-0}" -ge 2 ] && [ "${n_o:-0}" -ge 1 ]; then ok "workers start with KIT_AGENT_ROLE=worker, the orchestrator without"
  else bad "KIT_AGENT_ROLE per pane: $(tr '\n' ' ' < "$T/agent.log.roles" 2>/dev/null)"; fi
  grep -q 'No knowledge-base search' "$T/agent.log" 2>/dev/null \
    && ok "task-level brain switch reached the task text" || bad "brain switch missing in the task text"
  for w in alpha beta; do
    d=$((SECONDS + 60)); got=""
    while [ $SECONDS -lt $d ]; do got="$(wbt "$WB_S" "$BIN/wb-result" "v$w$$" 2>/dev/null)" && break; sleep 2; done
    case "$got" in *"fake agent answered"*) ok "wb-result v$w: result file read" ;; *) bad "wb-result v$w: no result within 60 s" ;; esac
  done
  wins="$(wbt "$WB_S" tmux list-windows -t "=$WBS" -F '#{window_name}' | tr '\n' ' ')"
  roles="$(wbt "$WB_S" tmux list-panes -s -t "=$WBS" -F '#{@wb_role}' | sort | uniq -c | tr -s ' ' | tr '\n' ' ')"
  case "$roles" in *"2 worker"*) ok "two worker panes tagged (@wb_role): windows: $wins" ;; *) bad "worker panes: $roles / windows: $wins" ;; esac
  sess_state="$(ls "$HOME/.claude/workbench/sessions" 2>/dev/null | head -1)"
  wbt "$WB_S" "$BIN/wb-close" "valpha$$" "vbeta$$" >/dev/null 2>&1 || timed_out "$?" "wb-close"
  left="$(wbt "$WB_S" tmux list-panes -s -t "=$WBS" -F '#{@wb_role}' | grep -c worker || true)"
  [ "$left" = 0 ] && ok "wb-close closed both workers" || bad "$left worker panes left after wb-close"
  wbt "$WB_S" "$BIN/context-guard" --stop --all >/dev/null 2>&1 || true
  wbt "$WB_S" tmux kill-server 2>/dev/null
  # The guard notices its stop file or the vanished session at its next poll (60 s); the
  # spawners' short-lived watchers end within 40 s. Wait for both, then name what is left.
  d=$((SECONDS + 90))
  while [ $SECONDS -lt $d ] && pgrep -f "$T/home" >/dev/null 2>&1; do sleep 2; done
  if pgrep -f "$T/home" >/dev/null 2>&1; then
    bad "processes of the test HOME still running after 90 s: $(pgrep -f "$T/home" | tr '\n' ' ')"
  else
    ok "every process started by the end-to-end test has ended on its own"
  fi
  if [ -s "$T/ssh.log" ]; then bad "SSH attempted: $(head -3 "$T/ssh.log" | tr '\n' ';')"; else ok "no ssh/scp call (this machine is the local one)"; fi
  rm -f "$BIN/claude"
  rm -rf "$HOME/.pi-workers/results/valpha$$" "$HOME/.pi-workers/results/vbeta$$"
fi

section "desktop app (Linux x86_64)"
APP_STATE="$DATA/app-state.json"
APP_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/workbench-app"
APP_OFF="${KIT_OFFLINE:-$(cd "$HERE/../.." && pwd)/offline}/workbench-app"
if [ "$(uname -s)" != Linux ] || [ "$(uname -m)" != x86_64 ]; then
  note "desktop app: built for Linux x86_64, not checked on $(uname -s) $(uname -m)"
elif [ ! -f "$APP_STATE" ]; then
  if ls "$APP_OFF"/electron-v*-linux-x64.zip >/dev/null 2>&1; then
    bad "desktop app not installed although $APP_OFF holds its files (bash install.sh)"
  else
    note "desktop app not installed: no Electron in $APP_OFF (build host: bash fetch.sh)"
  fi
else
  E="$APP_DIR/electron/electron"
  if [ -x "$BIN/agent-workbench" ] && bash -n "$BIN/agent-workbench" 2>/dev/null; then ok "launcher agent-workbench"; else bad "launcher $BIN/agent-workbench missing or broken"; fi
  DESK="$HOME/.local/share/applications/agent-workbench.desktop"
  if grep -qx 'Name=Agent Workbench' "$DESK" 2>/dev/null && grep -qx "Exec=$BIN/agent-workbench" "$DESK" \
     && grep -qx 'Keywords=workbench;werkbank;agents;' "$DESK" && grep -qx 'Icon=agent-workbench' "$DESK"; then
    ok "menu entry Agent Workbench (Exec, Keywords, Icon)"
  else
    bad "menu entry $DESK missing or incomplete"
  fi
  if command -v desktop-file-validate >/dev/null 2>&1; then
    v="$(desktop-file-validate "$DESK" 2>&1)" && ok "desktop-file-validate: no errors" || bad "desktop-file-validate: $v"
  fi
  miss=""
  for s in 16 32 48 64 128 256 512; do [ -f "$HOME/.local/share/icons/hicolor/${s}x${s}/apps/agent-workbench.png" ] || miss="$miss ${s}"; done
  [ -z "$miss" ] && ok "hicolor icons 16..512" || bad "icons missing:$miss"
  want="v$("$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))["electron"])' "$APP_DIR/app/kit-build.json" 2>/dev/null)"
  got="$(wbt "$WB_S" env -u DISPLAY -u WAYLAND_DISPLAY "$BIN/agent-workbench" --version 2>"$APP_DIR.verify.err")"; rc=$?
  if [ "$got" = "$want" ]; then
    ok "Electron starts headless: agent-workbench --version = $got"
  else
    timed_out "$rc" "agent-workbench --version" || bad "agent-workbench --version gave '$got' (want $want): $(head -c 300 "$APP_DIR.verify.err")"
    libs="$(ldd "$E" 2>/dev/null | awk '/not found/ {print $1}' | tr '\n' ' ')"
    [ -n "$libs" ] && note "missing libraries: $libs(the VS Code item of 01-prereqs installs the same ones: bash ../01-prereqs/install.sh vscode)"
  fi
  rm -f "$APP_DIR.verify.err"
  pty="$(ELECTRON_RUN_AS_NODE=1 wbt "$WB_S" "$E" -e '
    const p = require(process.argv[1]).spawn("/bin/sh", ["-c", "echo pty-$((6*7))"], {});
    let out = ""; p.onData((d) => { out += d; }); p.onExit(() => { console.log(out.trim()); process.exit(0); });' \
    "$APP_DIR/app/node_modules/node-pty" 2>&1)"
  case "$pty" in *pty-42*) ok "node-pty (linux-x64 prebuild) runs a pseudo terminal under Electron" ;; *) bad "node-pty under Electron: $(printf '%s' "$pty" | head -c 300)" ;; esac
  out="$(ELECTRON_RUN_AS_NODE=1 wbt "$WB_S" "$E" "$APP_DIR/app/bin/awb-ctl" socket-path 2>&1)"
  case "$out" in /*.sock) ok "awb-ctl runs under Electron ($out)" ;; *) bad "awb-ctl: $out" ;; esac
  # The app itself: main.js loads, the windows' code is found and the control socket answers.
  # Headless (Ozone), in a HOME, runtime and tmux folder of its own, so it sees no session of
  # the user and no running app; ended with its whole process tree.
  AT="$(mktemp -d "${TMPDIR:-/tmp}/wbv-app.XXXXXX")"; mkdir -p "$AT/home" "$AT/run" "$AT/tmux"; chmod 700 "$AT/run"
  flags=""
  if [ ! -u "$APP_DIR/electron/chrome-sandbox" ] && [ "$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null)" = 1 ]; then flags="--no-sandbox"; fi
  # shellcheck disable=SC2086
  env -u DISPLAY -u WAYLAND_DISPLAY HOME="$AT/home" XDG_RUNTIME_DIR="$AT/run" TMUX_TMPDIR="$AT/tmux" PATH="$BIN:$PATH" \
    "$E" $flags --ozone-platform=headless "$APP_DIR/app" > "$AT/log" 2>&1 &
  apid=$!
  d=$((SECONDS + ${WB_VERIFY_APP_SECS:-180}))
  while [ $SECONDS -lt $d ] && kill -0 "$apid" 2>/dev/null && ! grep -q '^awb-ready ' "$AT/log"; do sleep 1; done
  sock="$(sed -n 's/^awb-ready //p' "$AT/log" | head -1)"
  pong=""
  [ -n "$sock" ] && pong="$(ELECTRON_RUN_AS_NODE=1 wbt "$WB_S" "$E" "$APP_DIR/app/bin/awb-ctl" --socket "$sock" ping 2>&1)"
  case "$pong" in
    *'"pong":true'*) ok "app main.js loads and its control socket answers (headless, own HOME)" ;;
    *) bad "app did not come up headless: ${pong:-no awb-ready line}"; tail -5 "$AT/log" | sed 's/^/        /' ;;
  esac
  # SIGTERM to the main process only: the app shuts down on its own (about 2 s). Killing its
  # helper processes first made Electron abort with a core dump.
  kill -TERM "$apid" 2>/dev/null
  d=$((SECONDS + 20)); while [ $SECONDS -lt $d ] && kill -0 "$apid" 2>/dev/null; do sleep 1; done
  if kill -0 "$apid" 2>/dev/null; then kill_tree KILL "$apid"; bad "app did not end within 20 s of SIGTERM (killed)"; fi
  wait "$apid" 2>/dev/null
  rm -rf "$AT"
fi

section "model registry (own temporary HOME)"
if [ -x "$BIN/wb-state" ]; then
  out="$(wbt 300 bash "$HERE/tests/test-models.sh" "$BIN" 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then
    ok "$(printf '%s\n' "$out" | tail -1)"
  else
    timed_out "$rc" "model registry test" || bad "model registry test failed"; printf '%s\n' "$out" | grep FAIL | sed 's/^/        /'
  fi
fi


if [ "$TEMP" = 1 ]; then
  section "uninstall"
  cp "$HOME/.claude/settings.json" "$T/settings.before" 2>/dev/null
  WB_VSCODE_ARGS="${VSC_ARGS:-}" wbt 300 bash "$HERE/uninstall.sh" > "$T/uninstall.log" 2>&1; rc=$?
  if [ "$rc" = 0 ]; then ok "uninstall.sh exit 0"; else timed_out "$rc" "uninstall.sh" || bad "uninstall.sh failed"; sed 's/^/        /' "$T/uninstall.log"; fi
  left="$(find "$HOME/.local/bin" "$HOME/.claude/hooks" "$HOME/.claude/roles" "$HOME/.claude/git-hooks" -type f 2>/dev/null | grep -v '\.bak-' | wc -l | tr -d ' ')"
  [ "$left" = 0 ] && ok "no installed file left" || { bad "$left installed files left"; find "$HOME/.local/bin" "$HOME/.claude/hooks" -type f 2>/dev/null | head -5 | sed 's/^/        /'; }
  python3 - "$HOME/.claude/settings.json" <<'PY' && ok "hook entries and attribution removed from Claude settings" || bad "Claude settings still carry workbench entries"
import json, os, sys
p = sys.argv[1]
s = json.load(open(p)) if os.path.exists(p) else {}
text = json.dumps(s)
assert ".claude/hooks/" not in text and "attribution" not in s
PY
  [ -z "$(wbt "$WB_S" git config --global --get core.hooksPath 2>/dev/null)" ] && ok "core.hooksPath removed" || bad "core.hooksPath still set"
  if [ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ]; then
    left=""
    for f in "$HOME/.local/share/work-kit/workbench-app" "$HOME/.local/bin/agent-workbench" \
             "$HOME/.local/share/applications/agent-workbench.desktop" "$HOME/.local/share/icons/hicolor/48x48/apps/agent-workbench.png"; do
      [ -e "$f" ] && left="$left $f"
    done
    [ -z "$left" ] && ok "desktop app, launcher, menu entry and icons removed" || bad "desktop app left:$left"
  fi
  stray="$(find "$HOME" -name '*.bak-*' -not -path "*/.local/share/work-kit/backups/*" 2>/dev/null | head -3)"
  [ -z "$stray" ] && ok "backups only below ~/.local/share/work-kit/backups/" || bad "backup next to a file: $stray"
fi

if [ "$TEMP" = 1 ]; then
  section "one global git-hook dispatcher (own temporary HOMEs)"
  out="$(HOME="$REAL_HOME" wbt 300 bash "$HERE/tests/test-git-dispatcher.sh" 2>&1)"; rc=$?
  if [ "$rc" = 0 ]; then
    ok "$(printf '%s\n' "$out" | tail -1)"
  elif [ "$rc" = 77 ]; then
    note "30-agent-setup not next to this module: dispatcher test skipped"
  else
    timed_out "$rc" "dispatcher test" || bad "dispatcher test failed"; printf '%s\n' "$out" | grep FAIL | sed 's/^/        /'
  fi
fi

echo
echo "verify: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
