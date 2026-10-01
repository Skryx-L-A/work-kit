#!/usr/bin/env bash
# shellcheck disable=SC2015  # "A && ok || bad": ok and bad never fail
# 40-data-guard fails closed when gitleaks is missing (secret scan impossible), in a throw-away HOME
# and on a PATH that has no gitleaks. Needs no gitleaks. Covers the plain hook stub, the CLI and the
# kit-sync dispatcher (skipped when 30-agent-setup is not in this kit).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCH="$HERE/../30-agent-setup/git-hooks/dispatch"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
unset XDG_CONFIG_HOME KIT_DATA_DIR KIT_BIN_DIR DATA_GUARD_HOME DATA_GUARD_BIN DATA_GUARD_ALLOW_UNSCANNED DATA_GUARD_STRICT NO_COLOR
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1

# A PATH with the tools the scripts need and no gitleaks (also none in ~/.local/bin of the temp HOME).
TOOLS="$TMP/tools"
mkdir -p "$TOOLS"
for t in bash env git grep sed awk cut sort head tr cat mktemp cp rm mv dirname basename chmod mkdir wc ln touch \
         find cksum date printf ls tee uname readlink id sh true false test expr xargs; do
  p="$(command -v "$t" 2>/dev/null)" && [ -x "$p" ] && ln -sf "$p" "$TOOLS/$t"
done
export PATH="$TOOLS"
command -v gitleaks >/dev/null 2>&1 && { echo "gitleaks still on PATH; cannot run"; exit 2; }
git config --global user.name tester
git config --global user.email tester@example.invalid
git config --global init.defaultBranch main

fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

bash "$HERE/install.sh" >"$TMP/install.out" 2>&1 && ok "install" || { bad "install"; cat "$TMP/install.out"; }
grep -q "BLOCKED" "$TMP/install.out" && ok "install warns that commits are blocked" || bad "install message"
DG="$HOME/.local/bin/data-guard"

# --- CLI ---
printf 'nothing secret here\n' >"$TMP/note.txt"
"$DG" check "$TMP/note.txt" >"$TMP/out" 2>&1; rc=$?
[ "$rc" = 2 ] && grep -q "BLOCKED: gitleaks not found" "$TMP/out" && grep -q "DATA_GUARD_ALLOW_UNSCANNED=1 git commit" "$TMP/out" \
  && ok "check: exit 2 with the one-line override" || { bad "check without gitleaks (rc=$rc)"; cat "$TMP/out"; }
"$DG" scan "$TMP" >/dev/null 2>&1; [ "$?" = 2 ] && ok "scan: exit 2" || bad "scan not failing closed"
DATA_GUARD_ALLOW_UNSCANNED=1 "$DG" check "$TMP/note.txt" >"$TMP/out" 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q "WARNING: gitleaks not found" "$TMP/out" && ok "check: override passes with a warning" || bad "check override (rc=$rc)"
DATA_GUARD_ALLOW_UNSCANNED=1 DATA_GUARD_STRICT=1 "$DG" check "$TMP/note.txt" >/dev/null 2>&1; [ "$?" = 2 ] \
  && ok "STRICT=1 refuses the override" || bad "STRICT did not win"
"$DG" deny add 'acme-customer' >/dev/null
printf 'the acme-customer file\n' >"$TMP/deny.txt"
DATA_GUARD_ALLOW_UNSCANNED=1 "$DG" check "$TMP/deny.txt" >/dev/null 2>&1; [ "$?" = 1 ] \
  && ok "override still applies the deny-list" || bad "deny-list skipped under the override"

# status: red line without gitleaks (forced colour), plain text otherwise
DATA_GUARD_COLOR=always "$DG" status >"$TMP/out" 2>&1
grep -q $'\033\\[31mgitleaks:    NOT FOUND - commits are BLOCKED' "$TMP/out" && ok "status: gitleaks line in red" || { bad "status red"; cat "$TMP/out"; }
"$DG" status >"$TMP/out" 2>&1
grep -q "gitleaks:    NOT FOUND - commits are BLOCKED" "$TMP/out" && ! grep -q $'\033' "$TMP/out" && ok "status: plain without a terminal" || bad "status plain"

# --- per-repository stub ---
R1="$TMP/r1"; git init -q "$R1"; cd "$R1" || exit 2
"$DG" install-hook . >/dev/null
echo fine >a.txt; git add a.txt
git commit -q -m one >"$TMP/out" 2>&1 && bad "stub: commit passed without gitleaks" || ok "stub: commit blocked without gitleaks"
grep -q "BLOCKED" "$TMP/out" && grep -q "DATA_GUARD_ALLOW_UNSCANNED=1 git commit" "$TMP/out" && ok "stub: message names the override" || { bad "stub message"; cat "$TMP/out"; }
DATA_GUARD_ALLOW_UNSCANNED=1 git commit -q -m one >"$TMP/out" 2>&1 && ok "stub: override lets the commit through" || { bad "stub override"; cat "$TMP/out"; }
echo more >>a.txt; git add a.txt
rm -f "$HOME/.local/share/work-kit/data-guard/data-guard"
git commit -q -m two >"$TMP/out" 2>&1 && bad "stub: commit passed with data-guard gone" || ok "stub: commit blocked when the data-guard binary is gone"
DATA_GUARD_ALLOW_UNSCANNED=1 git commit -q -m two >/dev/null 2>&1 && ok "stub: override works without the binary" || bad "stub override without binary"
"$DG" remove-hook . >/dev/null 2>&1

# --- dispatcher (kit-sync) ---
if [ -f "$DISPATCH" ]; then
  bash "$HERE/install.sh" >/dev/null 2>&1
  GH="$HOME/.config/work-kit/git-hooks"
  mkdir -p "$GH"
  for n in pre-commit commit-msg post-commit; do cp "$DISPATCH" "$GH/$n"; chmod +x "$GH/$n"; done
  git config --global core.hooksPath "$GH"
  "$DG" enable-global >/dev/null 2>&1
  R2="$TMP/r2"; git init -q "$R2"; cd "$R2" || exit 2
  echo fine >a.txt; git add a.txt
  git commit -q -m one >"$TMP/out" 2>&1 && bad "dispatcher: commit passed without gitleaks" || ok "dispatcher: commit blocked without gitleaks"
  grep -q "BLOCKED: gitleaks not found" "$TMP/out" && ok "dispatcher: names the missing scanner" || { bad "dispatcher message"; cat "$TMP/out"; }
  DATA_GUARD_ALLOW_UNSCANNED=1 git commit -q -m one >"$TMP/out" 2>&1 && ok "dispatcher: override lets the commit through" || { bad "dispatcher override"; cat "$TMP/out"; }
  echo more >>a.txt; git add a.txt
  DG_REAL="$HOME/.local/share/work-kit/data-guard/data-guard"
  mv "$DG_REAL" "$DG_REAL.off"
  git commit -q -m two >"$TMP/out" 2>&1 && bad "dispatcher: commit passed with data-guard gone" || ok "dispatcher: commit blocked when the data-guard binary is gone"
  grep -q "git-hooks: BLOCKED" "$TMP/out" && ok "dispatcher: message" || bad "dispatcher binary message"
  DATA_GUARD_ALLOW_UNSCANNED=1 git commit -q -m two >/dev/null 2>&1 && ok "dispatcher: override works without the binary" || bad "dispatcher override without binary"
  mv "$DG_REAL.off" "$DG_REAL"
  # data-guard not enabled for the repo: commits are not touched
  "$DG" disable-global >/dev/null 2>&1
  echo three >>a.txt; git add a.txt
  git commit -q -m three >/dev/null 2>&1 && ok "dispatcher: repo without data-guard commits normally" || bad "unguarded repo blocked"
fi

cd "$TMP" || exit 2
[ "$fail" = 0 ] && echo "ALL PASSED" || echo "FAILURES"
exit "$fail"
