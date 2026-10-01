#!/usr/bin/env bash
# shellcheck disable=SC2015  # "A && ok || bad": ok and bad never fail
# Install/uninstall test for 13-ai-governance in a throw-away HOME. No network.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
unset XDG_CONFIG_HOME KIT_DATA_DIR KIT_BIN_DIR COPILOT_HOME
export PATH="$HOME/.local/bin:$PATH"
CONF="$HOME/.config/work-kit"

fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

bash "$HERE/install.sh" >"$TMP/i1" 2>&1 && ok "install" || { bad "install"; cat "$TMP/i1"; }
[ -x "$HOME/.local/bin/ai-gov" ] && ok "ai-gov launcher installed" || bad "ai-gov not linked"
for f in ai-usage-guideline.md deployer-checklist.md mcp-policy.md mcp-allowlist.yaml; do
  [ -f "$CONF/$f" ] && ok "policy $f" || bad "policy $f missing"
done

echo "# my edit" >>"$CONF/ai-usage-guideline.md"
bash "$HERE/install.sh" >"$TMP/i2" 2>&1 && ok "second install" || bad "second install"
grep -q "# my edit" "$CONF/ai-usage-guideline.md" && ok "user edit kept" || bad "user edit lost"
[ -f "$CONF/ai-usage-guideline.md.kit-new" ] && ok "new version beside it" || bad "no .kit-new"

# a foreign launcher and a changed installed copy are backed up under the data dir, not beside them
BAK="$HOME/.local/share/work-kit/backups/13-ai-governance"
printf '#!/bin/sh\necho mine\n' >"$HOME/.local/bin/ai-gov"
echo "# changed" >>"$HOME/.local/share/work-kit/ai-governance/ai-gov"
bash "$HERE/install.sh" >"$TMP/i3" 2>&1 && ok "install over foreign files" || { bad "install over foreign files"; cat "$TMP/i3"; }
grep -q mine "$BAK"/ai-gov.bak-* 2>/dev/null && ok "foreign launcher backed up under backups/" || bad "launcher backup missing"
grep -qx "$HOME/.local/bin/ai-gov" "$BAK"/ai-gov.bak-*.origin 2>/dev/null && ok "backup records the original path" || bad "origin missing"
grep -q "# changed" "$BAK"/ai-gov.bak-* 2>/dev/null && ok "changed installed copy backed up" || bad "installed-copy backup missing"
[ -z "$(ls -A "$HOME/.local/bin" | grep 'bak-')" ] && [ -z "$(ls -A "$HOME/.local/share/work-kit/ai-governance" | grep 'bak-')" ] && ok "no backup beside the originals" || bad "backup left beside an original"

ai-gov open-questions >"$TMP/q" 2>&1 && grep -q "open question(s) for IT" "$TMP/q" && ok "open-questions" || bad "open-questions"
ai-gov mcp-check >"$TMP/m" 2>&1; rc=$?
[ "$rc" = 0 ] && grep -q "no MCP servers configured" "$TMP/m" && ok "mcp-check on empty HOME" || { bad "mcp-check rc=$rc"; cat "$TMP/m"; }
mkdir -p "$HOME/.cursor"
printf '{"mcpServers":{"x":{"command":"npx","args":["-y","x"]}}}' >"$HOME/.cursor/mcp.json"
ai-gov mcp-check >"$TMP/m" 2>&1; rc=$?
[ "$rc" = 1 ] && grep -q "NOT-ALLOWED" "$TMP/m" && ok "mcp-check flags unlisted server" || { bad "mcp-check flag rc=$rc"; cat "$TMP/m"; }
ai-gov template ai-incident | grep -q "AI incident report" && ok "template" || bad "template"

bash "$HERE/uninstall.sh" >"$TMP/u" 2>&1 && ok "uninstall" || bad "uninstall"
[ ! -e "$HOME/.local/bin/ai-gov" ] && ok "link removed" || bad "link still there"
[ -f "$CONF/mcp-allowlist.yaml" ] && ok "policy kept after uninstall" || bad "policy removed"

# No system python3: the kit CPython from uv's directory is used.
H2="$TMP/home2"
mkdir -p "$H2/.local/share/uv/python/cpython-3.12.0-test/bin" "$TMP/nopy"
ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$H2/.local/share/uv/python/cpython-3.12.0-test/bin/python3"
for t in bash sh env dirname basename cat cp mv rm ln mkdir mktemp chmod cmp date grep sed find sort head tail tr wc cut readlink uname touch test; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$TMP/nopy/$t"
done
HOME="$H2" PATH="$TMP/nopy" bash "$HERE/install.sh" >"$TMP/n1" 2>&1 && ok "install without system python3" || { bad "install without system python3"; cat "$TMP/n1"; }
HOME="$H2" PATH="$TMP/nopy" "$H2/.local/bin/ai-gov" template ai-incident 2>/dev/null | grep -q "AI incident report" \
  && ok "ai-gov runs on the kit CPython" || bad "ai-gov without system python3"
HOME="$TMP/home3" PATH="$TMP/nopy" bash "$HERE/install.sh" >"$TMP/n2" 2>&1 && bad "no python at all: refused" || ok "no python at all: refused"
grep -q "01-prereqs" "$TMP/n2" && ok "message names 01-prereqs" || bad "message lacks 01-prereqs"
HOME="$H2" PATH="$TMP/nopy" bash "$HERE/uninstall.sh" >"$TMP/n3" 2>&1
[ ! -e "$H2/.local/bin/ai-gov" ] && ok "launcher removed" || bad "launcher still there"

exit "$fail"
