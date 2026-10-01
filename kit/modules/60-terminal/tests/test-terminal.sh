#!/usr/bin/env bash
# shellcheck disable=SC2015  # "A && ok || bad": ok and bad never fail
# Test for 60-terminal in a throw-away HOME (own tmux socket, no user files touched).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
SOCK="kit-test-$$"
# shellcheck disable=SC2329  # runs from the EXIT trap
cleanup() { tmux -L "$SOCK" kill-server >/dev/null 2>&1; rm -rf "$TMP"; }
trap cleanup EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
unset XDG_CONFIG_HOME KIT_DATA_DIR KIT_BIN_DIR
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.name tester
git config --global user.email tester@example.invalid
git config --global init.defaultBranch main

fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
printf '# my bashrc\nexport MINE=1\n' >"$HOME/.bashrc"
chmod 644 "$HOME/.bashrc"
cp "$HOME/.bashrc" "$TMP/bashrc.orig"

bash "$HERE/install.sh" >"$TMP/i1.out" 2>&1 && ok "install" || { bad "install"; cat "$TMP/i1.out"; }
bash "$HERE/install.sh" >"$TMP/i2.out" 2>&1 && ok "second install" || bad "second install"
grep -q 'up to date' "$TMP/i2.out" && ! grep -q 'updated' "$TMP/i2.out" && ok "idempotent (no rewrite)" || bad "second run rewrote files"
DIRCONF="$HOME/.config/direnv/direnv.toml"; DSTATE="$HOME/.local/share/work-kit/terminal/default-settings.sha256"
sha256sum "$DIRCONF" | awk '{print "direnv.toml " $1}' >"$DSTATE"
bash "$HERE/install.sh" >"$TMP/default-refresh.out" 2>&1
grep -q "refreshed $DIRCONF" "$TMP/default-refresh.out" && ok "untouched direnv default refreshed" || bad "untouched direnv default not refreshed"
printf '\n# mine\n' >>"$DIRCONF"
bash "$HERE/install.sh" >"$TMP/default-user.out" 2>&1
grep -q '# mine' "$DIRCONF" && [ -f "$DIRCONF.kit-new" ] && grep -q 'kept your' "$TMP/default-user.out" && ok "edited direnv default kept with kit-new" || bad "edited direnv default handling"
rm -f "$DSTATE" "$DIRCONF.kit-new"; printf 'foreign = true\n' >"$DIRCONF"
bash "$HERE/install.sh" >/dev/null
[ "$(cat "$DIRCONF")" = 'foreign = true' ] && [ ! -e "$DIRCONF.kit-new" ] && ok "pre-existing foreign direnv config kept" || bad "foreign direnv config changed"
[ "$(grep -c 'work-kit terminal (managed' "$HOME/.bashrc")" = 1 ] && ok "exactly one block in .bashrc" || bad "block count in .bashrc"
grep -q 'export MINE=1' "$HOME/.bashrc" && ok "user text kept" || bad "user text lost"
BAK="$HOME/.local/share/work-kit/backups/60-terminal"
ls "$BAK"/.bashrc.bak-* >/dev/null 2>&1 && ok "backup of .bashrc made under backups/" || bad "no backup"
grep -qx "$HOME/.bashrc" "$BAK"/.bashrc.bak-*.origin 2>/dev/null && ok "backup records the original path" || bad "no origin record"
[ "$(mode_of "$HOME/.bashrc")" = 644 ] && ok ".bashrc keeps mode 644 (not the temp file's 600)" || bad ".bashrc mode is $(mode_of "$HOME/.bashrc")"
[ "$(mode_of "$HOME/.tmux.conf")" = 644 ] && ok "new ~/.tmux.conf is 644" || bad "new ~/.tmux.conf mode is $(mode_of "$HOME/.tmux.conf")"
ls -A "$HOME" | grep -q 'bak-' && bad "backup left beside the original" || ok "no .bak-* files in HOME"

# shellcheck disable=SC2016  # expanded by the inner shell
out="$(env -i HOME="$HOME" PATH=/usr/bin:/bin bash -i -c 'alias ll; echo MINE=$MINE; type mkcd | head -1; echo $PATH' 2>&1)"
echo "$out" | grep -q "alias ll=" && ok "alias loaded in interactive shell" || { bad "alias missing"; echo "$out"; }
echo "$out" | grep -q 'MINE=1' && ok "user bashrc still runs" || bad "user bashrc broken"
echo "$out" | grep -q "$HOME/.local/bin" && ok "local bin dir on PATH" || bad "PATH not extended"

# optional tools missing must not produce errors
echo "$out" | grep -qiE 'command not found|syntax error' && bad "errors without optional tools" || ok "no errors without fzf/direnv/just"

if command -v tmux >/dev/null 2>&1; then
  v="$(tmux -L "$SOCK" -f "$HOME/.tmux.conf" start-server \; show-options -g mouse 2>&1)"
  case "$v" in *"mouse on"*) ok "tmux config loads (mouse on)" ;; *) bad "tmux config: $v" ;; esac
  tmux -L "$SOCK" kill-server >/dev/null 2>&1
else
  echo "skip tmux not installed"
fi

# kit-new
export PATH="$HOME/.local/bin:$PATH"
kit-new demo-app >"$TMP/new.out" 2>&1 && ok "kit-new" || { bad "kit-new"; cat "$TMP/new.out"; }
[ -f "$HOME/work/demo-app/justfile" ] && [ -f "$HOME/work/demo-app/.gitignore" ] && ok "template files copied" || bad "template files"
grep -q 'demo-app' "$HOME/work/demo-app/README.md" && ! grep -q '{{name}}' "$HOME/work/demo-app/README.md" && ok "name substituted" || bad "name substitution"
[ "$(git -C "$HOME/work/demo-app" log --oneline | wc -l | tr -d ' ')" = 1 ] && ok "initial commit" || bad "initial commit"
# A freshly copied template .envrc is approved once. A later edit still needs direnv's normal allow.
mkdir -p "$TMP/direnv-bin"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\\n" "$*" >>"$DIRENV_LOG"' >"$TMP/direnv-bin/direnv"
chmod +x "$TMP/direnv-bin/direnv"
DIRENV_LOG="$TMP/direnv.log" PATH="$TMP/direnv-bin:$PATH" kit-new direnv-app >"$TMP/direnv.out" 2>&1 && ok "kit-new with direnv" || { bad "kit-new with direnv"; cat "$TMP/direnv.out"; }
grep -Fx "allow $HOME/work/direnv-app" "$TMP/direnv.log" >/dev/null && ok "kit-new allows its template .envrc" || bad "kit-new did not allow template .envrc"
# A project made by kit-new is safe to trust in Claude Code. Other JSON keys and project entries survive.
mkdir -p "$TMP/claude-bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$TMP/claude-bin/claude"
chmod +x "$TMP/claude-bin/claude"
printf '%s\n' '{"keep": {"value": 1}, "projects": {"/other": {"keep": "yes"}}}' >"$HOME/.claude.json"
chmod 640 "$HOME/.claude.json"
PATH="$TMP/claude-bin:$PATH" kit-new trusted-app >"$TMP/trusted.out" 2>&1 && ok "kit-new with Claude" || { bad "kit-new with Claude"; cat "$TMP/trusted.out"; }
python3 - "$HOME/.claude.json" "$HOME/work/trusted-app" <<'PY' && ok "kit-new trusts only its new Claude project" || bad "Claude trust entry"
import json
import sys
data = json.load(open(sys.argv[1]))
assert data["keep"] == {"value": 1}
assert data["projects"]["/other"] == {"keep": "yes"}
assert data["projects"][sys.argv[2]]["hasTrustDialogAccepted"] is True
PY
[ "$(mode_of "$HOME/.claude.json")" = 640 ] && ok "Claude config mode kept" || bad "Claude config mode changed"
rm -f "$HOME/.claude.json"
PATH="$TMP/claude-bin:$PATH" kit-new missing-trust >"$TMP/missing-trust.out" 2>&1 && ok "kit-new without Claude config" || bad "kit-new without Claude config"
[ ! -e "$HOME/.claude.json" ] && grep -q 'Claude trust not recorded' "$TMP/missing-trust.out" && ok "missing Claude config kept missing" || bad "missing Claude config handling"
printf '%s\n' '{ invalid json' >"$HOME/.claude.json"
PATH="$TMP/claude-bin:$PATH" kit-new broken-trust >"$TMP/broken-trust.out" 2>&1 && ok "kit-new with broken Claude config" || bad "kit-new with broken Claude config"
[ "$(cat "$HOME/.claude.json")" = '{ invalid json' ] && grep -q 'Claude trust not recorded' "$TMP/broken-trust.out" && ok "broken Claude config untouched" || bad "broken Claude config handling"
kit-new demo-app >/dev/null 2>&1 && bad "kit-new overwrote existing" || ok "kit-new refuses existing dir"
kit-new 'Bad Name' >/dev/null 2>&1 && bad "kit-new accepted bad name" || ok "kit-new rejects bad name"

# kit-new without a git identity: exit 1, says how to fix it, does not claim success
GIT_CONFIG_GLOBAL="$TMP/empty.gitconfig" env -u GIT_AUTHOR_NAME -u GIT_AUTHOR_EMAIL \
  "$HOME/.local/bin/kit-new" noid-app </dev/null >"$TMP/noid.out" 2>&1 && bad "kit-new without identity succeeded" || ok "kit-new without identity exits non-zero"
grep -q 'did NOT commit' "$TMP/noid.out" && grep -q 'git config --global user.name' "$TMP/noid.out" && ok "message says how to set the identity" || { bad "identity message"; cat "$TMP/noid.out"; }
grep -qx 'created .*' "$TMP/noid.out" && bad "reported success without a commit" || ok "no success line without a commit"
[ "$(git -C "$HOME/work/noid-app" log --oneline 2>/dev/null | wc -l | tr -d ' ')" = 0 ] && ok "no commit was made" || bad "commit exists"

# kit-new without git: clear message, nothing created
mkdir -p "$TMP/nogit"
for t in bash sh env dirname cat cp mv mkdir sed; do
  p="$(command -v "$t")" && ln -sf "$p" "$TMP/nogit/$t"
done
PATH="$TMP/nogit" "$HOME/.local/bin/kit-new" nogit-app >"$TMP/ng.out" 2>&1 && bad "kit-new without git succeeded" || ok "kit-new without git fails"
grep -q '01-prereqs' "$TMP/ng.out" && ok "message names 01-prereqs" || { bad "message lacks 01-prereqs"; cat "$TMP/ng.out"; }
[ ! -e "$HOME/work/nogit-app" ] && ok "nothing created without git" || bad "directory created without git"

bash "$HERE/uninstall.sh" >/dev/null 2>&1 && ok "uninstall" || bad "uninstall"
cmp -s "$HOME/.bashrc" "$TMP/bashrc.orig" && ok ".bashrc restored to original" || { bad ".bashrc differs"; diff "$TMP/bashrc.orig" "$HOME/.bashrc"; }
[ "$(mode_of "$HOME/.bashrc")" = 644 ] && ok ".bashrc mode kept by uninstall" || bad ".bashrc mode after uninstall is $(mode_of "$HOME/.bashrc")"
# an unusual mode and a symlinked dotfile survive install and uninstall
umask 0
printf '# other\n' >"$HOME/.bashrc"; chmod 640 "$HOME/.bashrc"
bash "$HERE/install.sh" >/dev/null 2>&1; bash "$HERE/uninstall.sh" >/dev/null 2>&1
[ "$(mode_of "$HOME/.bashrc")" = 640 ] && ok ".bashrc mode 640 kept through install and uninstall" || bad ".bashrc mode is $(mode_of "$HOME/.bashrc")"
umask 022
mkdir -p "$TMP/dot"; printf '# linked\n' >"$TMP/dot/bashrc"; rm -f "$HOME/.bashrc"; ln -s "$TMP/dot/bashrc" "$HOME/.bashrc"
bash "$HERE/install.sh" >/dev/null 2>&1
[ -L "$HOME/.bashrc" ] && grep -q 'work-kit terminal' "$TMP/dot/bashrc" && ok "symlinked .bashrc stays a link" || bad "symlinked .bashrc was replaced"
bash "$HERE/uninstall.sh" >/dev/null 2>&1
[ ! -e "$HOME/.local/bin/kit-new" ] && ok "kit-new removed" || bad "kit-new left"

[ "$fail" = 0 ] && echo "ALL PASSED" || echo "FAILURES"
exit "$fail"
