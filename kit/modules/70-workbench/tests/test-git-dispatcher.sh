#!/usr/bin/env bash
# One global git-hook dispatcher: with 30-agent-setup (kit-sync) the workbench uses kit-sync's,
# without it the workbench installs its own. Every case runs in its own temporary HOME.
#
#   bash tests/test-git-dispatcher.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENT_SETUP="$(cd "$HERE/.." && pwd)/30-agent-setup"
ROOT="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/wb-gitdisp.XXXXXX")" && pwd -P)"
trap 'rm -rf "$ROOT"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$*"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$*"; }

[ -f "$AGENT_SETUP/install.sh" ] || { echo "SKIP: 30-agent-setup not next to this module"; exit 77; }

# shellcheck source=temp_home.sh
. "$HERE/tests/temp_home.sh"
REAL_HOME="$HOME"
REAL_DATA="${KIT_DATA_DIR:-}"
# git (01-prereqs) and friends from the real ~/.local/bin, before PATH drops it
wb_th_tools "$REAL_HOME" "$ROOT/shim"
FAKE_BIN="$ROOT/fake-bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/git-lfs" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >>"${GIT_LFS_CALLS:?}"
if [ "$1" = pre-push ]; then cat >"${GIT_LFS_STDIN:?}"; fi
EOF
chmod +x "$FAKE_BIN/git-lfs"
new_home() {
  H="$ROOT/$1"; mkdir -p "$H"
  # python for the installers (00-python of the real HOME, linked into this HOME)
  KIT_DATA_DIR="$REAL_DATA" wb_th_python "$REAL_HOME" "$H" >/dev/null || bad "$1: no python for the test HOME"
  export HOME="$H"
  unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME KIT_DATA_DIR KIT_BIN_DIR KIT_TOOL_DIR
  export PATH="$FAKE_BIN:$ROOT/shim:$H/.local/bin:$(printf '%s' "$PATH" | tr ':' '\n' | grep -vx "$REAL_HOME/.local/bin" | grep -vx "$ROOT/shim" | grep -vx "$FAKE_BIN" | paste -sd: -)"
}
KIT_HOOKS_REL=".config/work-kit/git-hooks"
wb()   { bash "$HERE/install.sh" --no-vscode >"$HOME/wb.log" 2>&1 || { bad "70 install failed"; sed 's/^/        /' "$HOME/wb.log"; }; }
kit()  { bash "$AGENT_SETUP/install.sh" >"$HOME/kit.log" 2>&1 || { bad "30 install failed"; tail -5 "$HOME/kit.log"; }; }
hooks_path() { git config --global --get core.hooksPath 2>/dev/null; }
strips() {  # a commit with a co-author trailer loses the trailer
  local r="$HOME/repo"; rm -rf "$r"; git init -q "$r"
  git -C "$r" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty \
    -m "test" -m "Co-authored-by: Some Agent <agent@example.invalid>" || return 1
  ! git -C "$r" log -1 --format=%B | grep -qi 'co-authored-by'
}

lfs_dispatcher() { # label dispatcher-dir: covers LFS, non-LFS and an own hook
  local label="$1" d="$2" r h out want
  r="$HOME/lfs-$label"
  rm -rf "$r"; git init -q "$r" || return 1
  export GIT_LFS_CALLS="$r/lfs.calls" GIT_LFS_STDIN="$r/lfs.stdin"
  : >"$GIT_LFS_CALLS"; : >"$GIT_LFS_STDIN"
  printf '*.bin filter=lfs diff=lfs merge=lfs -text\n' >"$r/.gitattributes"
  for h in pre-push post-checkout post-commit post-merge; do
    printf 'refs/heads/main %s refs/heads/main %s\n' 1111111 0000000 >"$r/input"
    (cd "$r" && "$d/$h" origin https://example.invalid/repo.git <"$r/input") || return 1
  done
  want="pre-push
post-checkout
post-commit
post-merge"
  out="$(cat "$GIT_LFS_CALLS")"
  [ "$out" = "$want" ] || { bad "$label: LFS receives each required hook" "$out"; return 0; }
  [ "$(cat "$GIT_LFS_STDIN")" = "refs/heads/main 1111111 refs/heads/main 0000000" ] \
    && ok "$label: LFS receives each required hook and pre-push stdin" \
    || bad "$label: LFS call or pre-push stdin differs" "$out / $(cat "$GIT_LFS_STDIN")"

  rm -f "$r/.gitattributes"; : >"$GIT_LFS_CALLS"
  for h in pre-push post-checkout post-commit post-merge; do
    (cd "$r" && "$d/$h" origin https://example.invalid/repo.git </dev/null) || return 1
  done
  [ ! -s "$GIT_LFS_CALLS" ] && ok "$label: a repository without LFS does not call git-lfs" \
    || bad "$label: a repository without LFS called git-lfs" "$(cat "$GIT_LFS_CALLS")"

  printf '*.bin filter=lfs diff=lfs merge=lfs -text\n' >"$r/.gitattributes"
  cat >"$r/.git/hooks/pre-push" <<'EOF'
#!/bin/sh
printf 'own\n' >>"${OWN_HOOK_CALLS:?}"
cat >"${OWN_HOOK_STDIN:?}"
EOF
  chmod +x "$r/.git/hooks/pre-push"
  export OWN_HOOK_CALLS="$r/own.calls" OWN_HOOK_STDIN="$r/own.stdin"
  : >"$OWN_HOOK_CALLS"; : >"$OWN_HOOK_STDIN"; : >"$GIT_LFS_CALLS"
  printf 'refs/heads/main 1111111 refs/heads/main 0000000\n' | (cd "$r" && "$d/pre-push" origin https://example.invalid/repo.git) || return 1
  if [ "$(cat "$OWN_HOOK_CALLS")" = own ] && [ ! -s "$GIT_LFS_CALLS" ]; then
    ok "$label: an own hook runs without an extra LFS call"
  else
    bad "$label: own hook or LFS exclusion failed" "own=$(cat "$OWN_HOOK_CALLS"), lfs=$(cat "$GIT_LFS_CALLS")"
  fi
}

echo "== A: 70-workbench alone -> its own dispatcher"
new_home a; wb
[ "$(hooks_path)" = "$HOME/.claude/git-hooks" ] && ok "A: core.hooksPath = ~/.claude/git-hooks" || bad "A: core.hooksPath is '$(hooks_path)'"
[ -x "$HOME/.claude/git-hooks/commit-msg" ] && ok "A: own dispatcher installed" || bad "A: own dispatcher missing"
strips && ok "A: co-author line stripped" || bad "A: co-author line survived"
lfs_dispatcher "A" "$HOME/.claude/git-hooks"

echo "== B: 30-agent-setup first, then 70-workbench -> kit-sync's dispatcher only"
new_home b; kit; wb
[ "$(hooks_path)" = "$HOME/$KIT_HOOKS_REL" ] && ok "B: core.hooksPath = kit-sync's folder" || bad "B: core.hooksPath is '$(hooks_path)'"
[ ! -e "$HOME/.claude/git-hooks" ] && ok "B: no ~/.claude/git-hooks" || bad "B: ~/.claude/git-hooks was installed"
[ -e "$HOME/.claude/AGENTS.md" ] && ok "B: ~/.claude/AGENTS.md present (kit-sync)" || bad "B: ~/.claude/AGENTS.md missing"
[ ! -e "$HOME/.local/share/work-kit/workbench/agents-link" ] && ok "B: the workbench did not link AGENTS.md itself" || bad "B: workbench linked AGENTS.md"
strips && ok "B: co-author line stripped" || bad "B: co-author line survived"
lfs_dispatcher "B" "$HOME/$KIT_HOOKS_REL"
bash "$HERE/uninstall.sh" >"$HOME/un.log" 2>&1
[ "$(hooks_path)" = "$HOME/$KIT_HOOKS_REL" ] && ok "B: uninstalling 70 leaves kit-sync's dispatcher" || bad "B: core.hooksPath after uninstall is '$(hooks_path)'"

echo "== C: 70, then 30, then 70 again -> migrates to kit-sync's dispatcher"
new_home c; wb; kit; wb
[ "$(hooks_path)" = "$HOME/$KIT_HOOKS_REL" ] && ok "C: core.hooksPath moved to kit-sync's folder" || bad "C: core.hooksPath is '$(hooks_path)'"
[ ! -e "$HOME/.claude/git-hooks" ] && ok "C: own dispatcher removed" || bad "C: ~/.claude/git-hooks still there"
strips && ok "C: co-author line stripped" || bad "C: co-author line survived"

echo
echo "test-git-dispatcher: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
