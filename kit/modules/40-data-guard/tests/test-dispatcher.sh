#!/usr/bin/env bash
# shellcheck disable=SC2015  # "A && ok || bad": ok and bad never fail
# 40-data-guard next to the kit-sync git-hook dispatcher (30-agent-setup) in a throw-away HOME.
# Needs no gitleaks: only the deny-list is exercised. Skipped when the dispatcher is not in the kit.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$HERE/../30-agent-setup/git-hooks/dispatch"
[ -f "$DISPATCH" ] || { echo "skip: $DISPATCH not found (30-agent-setup not in this kit)"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
unset XDG_CONFIG_HOME KIT_DATA_DIR KIT_BIN_DIR DATA_GUARD_HOME DATA_GUARD_BIN
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1
export DATA_GUARD_ALLOW_UNSCANNED=1  # this test exercises the deny-list only, gitleaks may be absent
export PATH="$HOME/.local/bin:$PATH"
git config --global user.name tester
git config --global user.email tester@example.invalid
git config --global init.defaultBranch main

fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
expect_pass() { local n="$1"; shift; if "$@" >"$TMP/out" 2>&1; then ok "$n"; else bad "$n"; sed 's/^/     /' "$TMP/out"; fi; }
expect_block() { local n="$1"; shift; if "$@" >"$TMP/out" 2>&1; then bad "$n (was not blocked)"; else ok "$n"; fi; }

CONF="$HOME/.config/work-kit"
GH="$CONF/git-hooks"
list_dispatcher() { # what kit-sync does: the dispatcher under every hook name, hooksPath set
  local n
  mkdir -p "$GH"
  for n in pre-commit commit-msg post-commit; do cp "$DISPATCH" "$GH/$n"; chmod +x "$GH/$n"; done
  git config --global core.hooksPath "$GH"
}
sum_dispatch() { cksum "$GH/pre-commit" "$GH/commit-msg" "$GH/post-commit" | awk '{print $1}' | tr '\n' ' '; }

bash "$HERE/install.sh" >/dev/null 2>&1 && ok "install" || bad "install"
data-guard deny add 'acme-customer' >/dev/null
list_dispatcher
before="$(sum_dispatch)"

# enable-global next to the dispatcher: files stay, flag appears, deny-list blocks
data-guard enable-global >"$TMP/out" 2>&1 && ok "enable-global next to the dispatcher" || { bad "enable-global"; cat "$TMP/out"; }
[ "$(sum_dispatch)" = "$before" ] && ok "dispatcher files not overwritten" || bad "dispatcher files were overwritten"
[ -e "$GH/.data-guard-global" ] && ok "flag file created" || bad "flag file missing"
[ "$(git config --global --get core.hooksPath)" = "$GH" ] && ok "core.hooksPath kept" || bad "core.hooksPath changed"
grep -q "^# work-kit data-guard hook" "$GH/pre-commit" && bad "pre-commit became a data-guard stub" || ok "pre-commit still the dispatcher"

R1="$TMP/r1"; git init -q "$R1"; cd "$R1" || exit 2
echo "contact the acme-customer team" >n.txt
git add n.txt
expect_block "flag: deny-list blocks in an unlisted repo" git commit -q -m x
git reset -q n.txt; rm -f n.txt
echo fine >f.txt; git add f.txt
expect_pass "flag: clean commit passes" git commit -q -m clean
data-guard status >"$TMP/out" 2>&1
grep -q "data-guard on for all repositories" "$TMP/out" && ok "status names the dispatcher mode" || bad "status"

# install-hook while the flag is on: covered, list untouched
data-guard install-hook . >"$TMP/out" 2>&1
grep -q "already covered" "$TMP/out" && [ ! -s "$CONF/hooked-repos.list" ] && ok "install-hook: covered by the flag" || bad "install-hook with flag"

# disable-global: only the flag goes; dispatcher and hooksPath stay
data-guard disable-global >/dev/null 2>&1
[ ! -e "$GH/.data-guard-global" ] && ok "disable-global removes the flag" || bad "flag still there"
[ "$(sum_dispatch)" = "$before" ] && [ "$(git config --global --get core.hooksPath)" = "$GH" ] && ok "disable-global keeps dispatcher and hooksPath" || bad "disable-global touched the dispatcher"
echo "another acme-customer line" >>f.txt; git add f.txt
expect_pass "flag off: repo is unguarded" git commit -q -m unguarded
data-guard disable-global >"$TMP/out" 2>&1
grep -q "not enabled" "$TMP/out" && ok "second disable-global is a no-op" || bad "second disable-global"

# install-hook with the flag off: repo goes on the list and is guarded
R2="$TMP/r2"; git init -q "$R2"; cd "$R2" || exit 2
echo "acme-customer note" >n.txt; git add n.txt
expect_pass "unlisted repo is not guarded" git commit -q -m ok
data-guard install-hook . >"$TMP/out" 2>&1
grep -q "added to" "$TMP/out" && grep -qxF "$(git rev-parse --show-toplevel)" "$CONF/hooked-repos.list" && ok "install-hook lists the repo" || { bad "install-hook list"; cat "$TMP/out"; }
[ ! -e .git/hooks/pre-commit ] && ok "no stub written into the repo" || bad "stub written next to the dispatcher"
echo "second acme-customer note" >m.txt; git add m.txt
expect_block "listed repo is guarded by the dispatcher" git commit -q -m blocked
data-guard status >"$TMP/out" 2>&1
grep -q "guarded by the kit-sync hooks" "$TMP/out" && ok "status: repo guarded" || { bad "status repo line"; cat "$TMP/out"; }
data-guard remove-hook . >/dev/null 2>&1
[ ! -s "$CONF/hooked-repos.list" ] && ok "remove-hook drops the repo from the list" || bad "list not cleared"
expect_pass "repo unguarded after remove-hook" git commit -q -m ok2

# per-repo stub mode: remove-hook clears the list too
rm -rf "$GH"; git config --global --unset core.hooksPath
R3="$TMP/r3"; git init -q "$R3"; cd "$R3" || exit 2
data-guard install-hook . >/dev/null 2>&1
grep -qxF "$R3" "$CONF/hooked-repos.list" && ok "stub mode: repo listed" || bad "stub list"
data-guard remove-hook . >/dev/null 2>&1
grep -qxF "$R3" "$CONF/hooked-repos.list" && bad "stub mode: remove-hook left the repo listed" || ok "stub mode: remove-hook clears the list"

# enable-global without a dispatcher still writes the stubs; a later dispatcher file is not overwritten
data-guard enable-global >/dev/null 2>&1
grep -q "^# work-kit data-guard hook" "$GH/pre-commit" && [ ! -e "$GH/.data-guard-global" ] && ok "no dispatcher: stubs and no flag" || bad "plain enable-global changed"
cp "$DISPATCH" "$GH/commit-msg"
data-guard enable-global >/dev/null 2>&1
grep -q "git-hook dispatcher" "$GH/commit-msg" && ok "single dispatcher file survives a stub refresh" || bad "commit-msg dispatcher overwritten"
data-guard disable-global >/dev/null 2>&1
[ -z "$(git config --global --get core.hooksPath)" ] && ok "no dispatcher: disable-global unsets hooksPath" || bad "hooksPath still set"

cd "$TMP" || exit 2
[ "$fail" = 0 ] && echo "ALL PASSED" || echo "FAILURES"
exit "$fail"
