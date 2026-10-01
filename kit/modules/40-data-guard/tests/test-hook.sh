#!/usr/bin/env bash
# shellcheck disable=SC2015  # "A && ok || bad": ok and bad never fail
# End-to-end test for 40-data-guard in a throw-away HOME. Needs gitleaks on PATH or in
# $GITLEAKS_BIN_DIR. The fake secrets are built at run time, so this file holds none.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
unset XDG_CONFIG_HOME KIT_DATA_DIR KIT_BIN_DIR DATA_GUARD_HOME
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1
export PATH="$HOME/.local/bin:${GITLEAKS_BIN_DIR:+$GITLEAKS_BIN_DIR:}$PATH"
git config --global user.name tester
git config --global user.email tester@example.invalid
git config --global init.defaultBranch main

fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
expect_pass() { local n="$1"; shift; if "$@" >"$TMP/out" 2>&1; then ok "$n"; else bad "$n"; sed 's/^/     /' "$TMP/out"; fi; }
expect_block() { local n="$1"; shift; if "$@" >"$TMP/out" 2>&1; then bad "$n (was not blocked)"; else ok "$n"; fi; }

command -v gitleaks >/dev/null || { echo "gitleaks not found; set GITLEAKS_BIN_DIR"; exit 2; }
rand() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"; }
FAKE_TOKEN="gh""p_$(rand 36)"

bash "$HERE/install.sh" >"$TMP/install.out" 2>&1 && ok "install" || { bad "install"; cat "$TMP/install.out"; }
bash "$HERE/install.sh" >"$TMP/install2.out" 2>&1 && ok "install is idempotent" || bad "second install"
[ -x "$HOME/.local/bin/data-guard" ] && ok "CLI linked" || bad "CLI not linked"
[ -f "$HOME/.config/work-kit/data-classes.md" ] && grep -q 'TODO(ask IT)' "$HOME/.config/work-kit/data-classes.md" && ok "policy has TODO(ask IT)" || bad "policy"

REPO="$TMP/repo"
git init -q "$REPO"
cd "$REPO" || exit 2
# pre-existing hook must be chained, not replaced
printf '#!/bin/sh\necho chained-hook-ran >>"%s/chain.log"\n' "$TMP" >.git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
data-guard install-hook . >/dev/null
[ -x .git/hooks/pre-commit.work-kit-chained ] && ok "old hook kept as chained" || bad "old hook lost"

echo "hello" >clean.txt
git add clean.txt
expect_pass "clean commit passes" git commit -q -m "clean"
grep -q chained-hook-ran "$TMP/chain.log" 2>/dev/null && ok "chained hook ran" || bad "chained hook did not run"

printf 'token = "%s"\n' "$FAKE_TOKEN" >leak.txt
git add leak.txt
expect_block "planted secret is blocked" git commit -q -m "leak"
grep -q "$FAKE_TOKEN" "$TMP/out" && bad "secret printed in output" || ok "secret not echoed (redacted)"
git reset -q leak.txt
rm -f leak.txt

printf -- '-----BEGIN RSA PRIVATE KEY-----\n%s\n%s\n%s\n-----END RSA PRIVATE KEY-----\n' \
  "$(rand 64)" "$(rand 64)" "$(rand 64)" >key.pem
git add key.pem
expect_block "planted private key is blocked" git commit -q -m "key"
git reset -q key.pem
rm -f key.pem

data-guard deny add 'acme-customer' >/dev/null
data-guard deny add '\.corp\.invalid' >/dev/null
echo "contact the ACME-Customer team" >note.txt
git add note.txt
expect_block "deny-list match is blocked (case-insensitive)" git commit -q -m "deny"
git reset -q note.txt
echo "host build01.corp.invalid" >host.txt
git add host.txt
expect_block "deny-list host pattern is blocked" git commit -q -m "deny2"
git reset -q host.txt
echo "example acme-customer  # data-guard:allow" >allowed.txt
git add allowed.txt
expect_pass "data-guard:allow marker skips a line" git commit -q -m "allowed"
echo "text" >acme-customer-notes.txt
git add acme-customer-notes.txt
expect_block "deny-list matches file names" git commit -q -m "name"
git reset -q acme-customer-notes.txt

echo "safe change" >>clean.txt
git add clean.txt
expect_pass "commit after blocked attempts passes" git commit -q -m "safe"

printf 'no secret here\n' >"$TMP/text-ok.txt"
expect_pass "check: clean text" data-guard check "$TMP/text-ok.txt"
printf 'x = "%s"\n' "$FAKE_TOKEN" >"$TMP/text-bad.txt"
expect_block "check: secret in text" data-guard check "$TMP/text-bad.txt"
# A real-looking AWS access key id (built at run time) is caught. The documented AWS example id
# (ends in EXAMPLE) is a placeholder that gitleaks' default rule allowlists on purpose.
AWS_KEY="AK""IA""QYLPMN""5HHHFPZ""AM2"  # fixed body: gitleaks needs enough entropy
printf 'aws_access_key_id = %s\n' "$AWS_KEY" >"$TMP/text-aws.txt"
expect_block "check: AWS access key id (not the EXAMPLE placeholder)" data-guard check "$TMP/text-aws.txt"
echo "mentions acme-customer" | { data-guard check - >"$TMP/out" 2>&1 && bad "check stdin deny" || ok "check: deny-list on stdin"; }
mkdir "$TMP/tree" && cp "$TMP/text-bad.txt" "$TMP/tree/"
expect_block "scan: tree with secret" data-guard scan "$TMP/tree"

data-guard remove-hook . >/dev/null
[ -x .git/hooks/pre-commit ] && ! grep -q 'work-kit data-guard hook' .git/hooks/pre-commit && ok "remove-hook restores old hook" || bad "remove-hook"

# global opt-in
REPO2="$TMP/repo2"
git init -q "$REPO2"
cd "$REPO2" || exit 2
printf '#!/bin/sh\necho repo-hook-ran >>"%s/chain2.log"\n' "$TMP" >.git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
data-guard enable-global >/dev/null 2>&1 && ok "enable-global" || bad "enable-global"
printf 'token = "%s"\n' "$FAKE_TOKEN" >leak.txt
git add leak.txt
expect_block "global hook blocks planted secret" git commit -q -m "leak"
git reset -q leak.txt
rm -f leak.txt
echo ok >f.txt
git add f.txt
expect_pass "global hook lets clean commit through" git commit -q -m "f"
grep -q repo-hook-ran "$TMP/chain2.log" 2>/dev/null && ok "global hook chains to repo hook" || bad "repo hook skipped by global hooksPath"
data-guard disable-global >/dev/null && [ -z "$(git config --global --get core.hooksPath)" ] && ok "disable-global" || bad "disable-global"

cd "$TMP" || exit 2
bash "$HERE/uninstall.sh" >/dev/null 2>&1 && [ ! -e "$HOME/.local/bin/data-guard" ] && ok "uninstall" || bad "uninstall"
[ -f "$HOME/.config/work-kit/data-classes.md" ] && ok "uninstall keeps user policy" || bad "policy removed"

[ "$fail" = 0 ] && echo "ALL PASSED" || echo "FAILURES"
exit "$fail"
