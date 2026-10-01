#!/usr/bin/env bash
# shellcheck disable=SC2015  # "A && ok || bad": ok and bad never fail
# Tests for 16-harness-clis with fake offline artifacts in a temp dir. Nothing outside it is
# touched, no network, no real harness is started. Usage: bash tests/test-install.sh
set -uo pipefail

MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
# shellcheck source=../pins.conf source-path=SCRIPTDIR
. "$MOD/pins.conf"

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/     | /'; return 0; }
has() { grep -qF -- "$2" <<<"$1"; }
assert_has() { if has "$2" "$3"; then ok "$1"; else bad "$1 (missing: $3)" "$2"; fi; }
assert_lacks() { if has "$2" "$3"; then bad "$1 (unexpected: $3)" "$2"; else ok "$1"; fi; }
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got '$2', want '$3')"; fi; }

pinned_version() {
  case "$1" in
    claude) echo "$CLAUDE_VERSION" ;; codex) echo "$CODEX_VERSION" ;; opencode) echo "$OPENCODE_VERSION" ;;
    copilot) echo "$COPILOT_VERSION" ;; gemini) echo "$GEMINI_VERSION" ;; pi) echo "$PI_VERSION" ;; aider) echo "$AIDER_VERSION" ;;
  esac
}

# ---- fake kit: a copy of the module, fake lock, fake offline artifacts -----------------------------
KIT="$W/kit"
OFF="$KIT/offline/harness-clis"
mkdir -p "$KIT/modules" "$OFF"
cp -R "$MOD" "$KIT/modules/16-harness-clis"
rm -rf "$KIT/modules/16-harness-clis/tests"
M="$KIT/modules/16-harness-clis"
rm -f "$M/lock/artifacts.lock"
LOCKF="$M/lock/artifacts.lock"
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
lockline() { echo "$(sha "$OFF/$1")  $1  https://example.invalid/$1" >>"$LOCKF"; }
script() { # file text: an executable sh script that prints text for --version
  printf '#!/bin/sh\necho "%s"\n' "$2" >"$1"
  chmod 0755 "$1"
}

P="$W/pack"
mkdir -p "$OFF/claude" "$OFF/codex" "$OFF/opencode" "$OFF/copilot" "$OFF/gemini" "$OFF/pi" "$OFF/aider/wheels" "$P/codex/bin" "$P/codex/codex-path" "$P/codex/codex-resources" "$P/oc" "$P/cp" "$P/gem/node_modules/@google/gemini-cli/bundle" "$P/pi/node_modules/@earendil-works/pi-coding-agent/dist"
script "$OFF/claude/claude-$CLAUDE_VERSION-linux-x64" "$CLAUDE_VERSION (Claude Code)"
script "$P/codex/bin/codex" "codex-cli $CODEX_VERSION"
script "$P/codex/bin/codex-code-mode-host" host
script "$P/codex/codex-path/rg" rg
script "$P/codex/codex-resources/bwrap" bwrap
echo '{"layoutVersion":1}' >"$P/codex/codex-package.json"
tar -czf "$OFF/codex/codex-package-$CODEX_VERSION-x86_64-unknown-linux-musl.tar.gz" -C "$P/codex" .
script "$P/oc/opencode" "$OPENCODE_VERSION"
tar -czf "$OFF/opencode/opencode-$OPENCODE_VERSION-linux-x64-baseline.tar.gz" -C "$P/oc" .
script "$P/cp/copilot" "GitHub Copilot CLI $COPILOT_VERSION."
tar -czf "$OFF/copilot/copilot-$COPILOT_VERSION-linux-x64.tar.gz" -C "$P/cp" .
echo "// fake gemini bundle" >"$P/gem/node_modules/@google/gemini-cli/bundle/gemini.js"
tar -cf "$OFF/gemini/gemini-cli-$GEMINI_VERSION-linux-x64.tar" -C "$P/gem" node_modules
echo "// fake pi cli" >"$P/pi/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
tar -cf "$OFF/pi/pi-coding-agent-$PI_VERSION-linux-x64.tar" -C "$P/pi" node_modules
echo fake >"$OFF/aider/wheels/aider_chat-$AIDER_VERSION-py3-none-any.whl"
for f in "claude/claude-$CLAUDE_VERSION-linux-x64" "codex/codex-package-$CODEX_VERSION-x86_64-unknown-linux-musl.tar.gz" \
         "opencode/opencode-$OPENCODE_VERSION-linux-x64-baseline.tar.gz" "copilot/copilot-$COPILOT_VERSION-linux-x64.tar.gz" \
         "gemini/gemini-cli-$GEMINI_VERSION-linux-x64.tar" "pi/pi-coding-agent-$PI_VERSION-linux-x64.tar"; do lockline "$f"; done
echo "aider-chat==$AIDER_VERSION --hash=sha256:00" >"$M/lock/aider-requirements.txt"

# fake tools: node is "24" (its -e version check passes) and "runs" the gemini and pi entry files; uv creates a venv with an aider script
FAKEBIN="$W/fakebin"
mkdir -p "$FAKEBIN"
cat >"$FAKEBIN/node" <<E
#!/bin/sh
if [ "\$1" = "-e" ]; then exit 0; fi
case "\$1" in *gemini.js) echo "$GEMINI_VERSION"; exit 0 ;; *pi-coding-agent/dist/cli.js) echo "$PI_VERSION"; exit 0 ;; esac
exit 1
E
chmod 0755 "$FAKEBIN/node"
# an old node: every minimum-version check fails
mkdir -p "$W/oldbin"
printf '#!/bin/sh\nexit 1\n' >"$W/oldbin/node"
chmod 0755 "$W/oldbin/node"
mkuv() { # dir: install a fake uv into dir; it records `pip install` arguments in $W/uv.args
  mkdir -p "$1"
  cat >"$1/uv" <<E
#!/bin/sh
case "\$1 \$2" in
  "python find") echo /fake/python3.12; exit 0 ;;
  "venv --no-config") d=""; for a in "\$@"; do d="\$a"; done; mkdir -p "\$d/bin"
    printf '#!/bin/sh\necho python\n' >"\$d/bin/python"; chmod 0755 "\$d/bin/python"
    printf '#!/bin/sh\necho "aider $AIDER_VERSION"\n' >"\$d/bin/aider"; chmod 0755 "\$d/bin/aider"; exit 0 ;;
  "pip install") echo "\$*" >"$W/uv.args"; exit 0 ;;
esac
exit 1
E
  chmod 0755 "$1/uv"
}
mkuv "$FAKEBIN"

# fake sibling modules: 01-prereqs installs a node, 00-python installs uv (both record the call)
mkdir -p "$KIT/modules/01-prereqs" "$KIT/modules/00-python" "$W/donor/node/bin"
cp "$FAKEBIN/node" "$W/donor/node/bin/node"
cat >"$KIT/modules/01-prereqs/install.sh" <<E
#!/usr/bin/env bash
echo "\$*" >>"$W/prereqs.calls"
mkdir -p "\$KIT_DATA_DIR/prereqs/node/bin" && cp "$W/donor/node/bin/node" "\$KIT_DATA_DIR/prereqs/node/bin/node"
E
mkuv "$W/donor/uv"
cat >"$KIT/modules/00-python/install.sh" <<E
#!/usr/bin/env bash
echo "\$*" >>"$W/python.calls"
mkdir -p "\$KIT_BIN_DIR" && cp "$W/donor/uv/uv" "\$KIT_BIN_DIR/uv"
E

BASEPATH="/usr/bin:/bin:/usr/sbin:/sbin"
newhome() { # name -> prints a fresh HOME
  mkdir -p "$W/homes/$1"
  echo "$W/homes/$1"
}
# runmod <home> <path-prefix|-> <script> args...: run a module script in a clean environment
runmod() {
  local h="$1" pre="$2" script="$3" pp
  shift 3
  if [ "$pre" = "-" ]; then pp="$h/.local/bin:$BASEPATH"; else pp="$h/.local/bin:$pre:$BASEPATH"; fi
  env -i HOME="$h" PATH="$pp" KIT_ROOT="$KIT" KIT_OFFLINE="$KIT/offline" HC_SKIP_PLATFORM_CHECK=1 \
    bash "$M/$script" "$@"
}

# ---- 1: full install, run, state ---------------------------------------------------------------------
H="$(newhome full)"
out="$(runmod "$H" "$FAKEBIN" install.sh --list 2>&1)"
assert_has "list shows claude pinned" "$out" "claude    $CLAUDE_VERSION"
out="$(runmod "$H" "$FAKEBIN" install.sh 2>&1)"; rc=$?
assert_eq "default install exits 0" "$rc" 0
[ "$rc" = 0 ] || printf '%s\n' "$out"
for h in claude codex opencode copilot gemini pi aider; do
  v="$(env -i HOME="$H" PATH="$H/.local/bin:$FAKEBIN:$BASEPATH" "$H/.local/bin/$h" --version 2>&1 | head -n 1)"
  assert_has "$h runs from ~/.local/bin" "$v" "$(pinned_version "$h")"
done
assert_eq "state records seven harnesses" "$(wc -l <"$H/.local/share/work-kit/state/16-harness-clis.list" | tr -d ' ')" 7
[ -L "$H/.local/bin/codex" ] && ok "codex is a link into the kit data dir" || bad "codex is not a link"
assert_has "codex link resolves through current/" "$(readlink "$H/.local/bin/codex")" "harness-clis/codex/current/bin/codex"
[ -x "$H/.local/share/work-kit/harness-clis/codex/current/codex-resources/bwrap" ] && ok "codex resources unpacked" || bad "codex resources missing"
grep -q 'work-kit:16-harness-clis' "$H/.local/bin/gemini" && ok "gemini launcher carries the module mark" || bad "no mark in gemini launcher"
grep -q 'work-kit:16-harness-clis' "$H/.local/bin/pi" && ok "pi launcher carries the module mark" || bad "no mark in pi launcher"
assert_has "pi launcher runs the pinned cli.js" "$(cat "$H/.local/bin/pi")" "harness-clis/pi/current/node_modules/@earendil-works/pi-coding-agent/dist/cli.js"
assert_has "pi launcher switches the pi.dev version check off unless the user set it" "$(cat "$H/.local/bin/pi")" 'PI_SKIP_VERSION_CHECK="${PI_SKIP_VERSION_CHECK:-1}"'
assert_lacks "gemini launcher does not set it" "$(cat "$H/.local/bin/gemini")" PI_SKIP_VERSION_CHECK
assert_has "pi launcher asks for Node.js 22.19" "$(cat "$H/.local/bin/pi")" '"22.19"' 
assert_has "aider installed with hashes, offline, from the wheel dir" "$(cat "$W/uv.args")" "--require-hashes"
assert_has "aider install passes --no-index" "$(cat "$W/uv.args")" "--no-index"
assert_has "aider install reads the offline wheel dir" "$(cat "$W/uv.args")" "--find-links $KIT/offline/harness-clis/aider/wheels"
if env -i HOME="$H" PATH="$H/.local/bin:$BASEPATH" KIT_ROOT="$KIT" bash "$M/check.sh" >/dev/null 2>&1; then ok "check.sh passes"; else bad "check.sh fails after install"; fi

# ---- 2: idempotent re-run, no backups ----------------------------------------------------------------------
out="$(runmod "$H" "$FAKEBIN" install.sh 2>&1)"
assert_eq "re-run reports seven 'up to date'" "$(printf '%s\n' "$out" | grep -c 'up to date')" 7
[ -z "$(find "$H/.local" -name '*.bak-*' 2>/dev/null)" ] && ok "re-run makes no backups" || bad "backups created by the re-run"

# ---- 3: old versions are dropped on activation -----------------------------------------------------------
mkdir -p "$H/.local/share/work-kit/harness-clis/claude/0.0.1"
rm -f "$H/.local/bin/claude"
out="$(runmod "$H" "$FAKEBIN" install.sh claude 2>&1)"
[ ! -d "$H/.local/share/work-kit/harness-clis/claude/0.0.1" ] && ok "an older version directory is removed" || bad "old version kept"
[ -L "$H/.local/bin/claude" ] && ok "a missing link is restored" || bad "link not restored"

# ---- 4: a foreign command is kept as a backup ----------------------------------------------------------------
H="$(newhome foreign)"
mkdir -p "$H/.local/bin"
echo "my own codex" >"$H/.local/bin/codex"
runmod "$H" "$FAKEBIN" install.sh codex >/dev/null 2>&1
assert_eq "foreign codex backed up under backups/" "$(cat "$H"/.local/share/work-kit/backups/16-harness-clis/codex.bak-[0-9]* 2>/dev/null | grep -v '^/')" "my own codex"
assert_eq "backup records the original path" "$(cat "$H"/.local/share/work-kit/backups/16-harness-clis/codex.bak-*.origin 2>/dev/null)" "$H/.local/bin/codex"
[ -z "$(ls "$H/.local/bin" | grep 'bak-')" ] && ok "no backup beside the original" || bad "backup left in the bin dir"
[ -L "$H/.local/bin/codex" ] && ok "kit codex installed over it" || bad "codex not installed"

# ---- 5: selection ---------------------------------------------------------------------------------------------
H="$(newhome select)"
runmod "$H" "$FAKEBIN" install.sh opencode claude >/dev/null 2>&1
assert_eq "only the chosen harnesses are recorded" "$(sort "$H/.local/share/work-kit/state/16-harness-clis.list" | awk '{ print $1 }' | tr '\n' ' ')" "claude opencode "
out="$(runmod "$H" "$FAKEBIN" install.sh nope 2>&1)"; rc=$?
[ "$rc" != 0 ] && assert_has "unknown harness is rejected" "$out" "unknown harness: nope" || bad "unknown harness accepted"
H2="$(newhome envset)"
env -i HOME="$H2" PATH="$H2/.local/bin:$FAKEBIN:$BASEPATH" KIT_ROOT="$KIT" KIT_OFFLINE="$KIT/offline" HC_SKIP_PLATFORM_CHECK=1 KIT_HARNESS_CLIS="copilot" \
  bash "$M/install.sh" >/dev/null 2>&1
assert_eq "KIT_HARNESS_CLIS limits the default set" "$(awk '{ print $1 }' "$H2/.local/share/work-kit/state/16-harness-clis.list" | tr '\n' ' ')" "copilot "

# ---- 6: damaged or missing artifact fails that harness only ----------------------------------------------------
H="$(newhome damaged)"
cp "$OFF/opencode/opencode-$OPENCODE_VERSION-linux-x64-baseline.tar.gz" "$W/oc.bak"
echo x >>"$OFF/opencode/opencode-$OPENCODE_VERSION-linux-x64-baseline.tar.gz"
mv "$OFF/copilot/copilot-$COPILOT_VERSION-linux-x64.tar.gz" "$W/cp.bak"
out="$(runmod "$H" "$FAKEBIN" install.sh claude opencode copilot 2>&1)"; rc=$?
assert_eq "damaged/missing artifacts give exit 1" "$rc" 1
assert_has "checksum mismatch is named" "$out" "checksum mismatch"
assert_has "missing artifact is named" "$out" "missing"
assert_has "failed harnesses are listed" "$out" "failed: opencode copilot"
[ -L "$H/.local/bin/claude" ] && ok "the intact harness still installed" || bad "claude skipped after other failures"
[ ! -e "$H/.local/bin/opencode" ] && ok "nothing installed for the damaged one" || bad "damaged opencode installed"
mv "$W/oc.bak" "$OFF/opencode/opencode-$OPENCODE_VERSION-linux-x64-baseline.tar.gz"
mv "$W/cp.bak" "$OFF/copilot/copilot-$COPILOT_VERSION-linux-x64.tar.gz"

# ---- 7: runtimes come from the sibling modules when missing -------------------------------------------------------
H="$(newhome runtimes)"
runmod "$H" - install.sh gemini pi aider >"$W/rt.out" 2>&1; rc=$?
assert_eq "gemini, pi and aider install without node/uv on PATH" "$rc" 0
[ "$rc" = 0 ] || cat "$W/rt.out"
assert_eq "01-prereqs was asked for node" "$(cat "$W/prereqs.calls" 2>/dev/null)" "node"
[ -s "$W/python.calls" ] && ok "00-python was run for uv and CPython" || bad "00-python not run"
v="$(env -i HOME="$H" PATH="$H/.local/bin:$BASEPATH" "$H/.local/bin/gemini" --version 2>&1)"
assert_has "gemini launcher finds the kit node without PATH help" "$v" "$GEMINI_VERSION"
v="$(env -i HOME="$H" PATH="$H/.local/bin:$BASEPATH" "$H/.local/bin/pi" --version 2>&1)"
assert_has "pi launcher finds the kit node without PATH help" "$v" "$PI_VERSION"
rm -rf "$KIT/modules/01-prereqs" "$KIT/modules/00-python"
H="$(newhome noruntime)"
out="$(runmod "$H" - install.sh gemini 2>&1)"; rc=$?
[ "$rc" != 0 ] && assert_has "no node and no 01-prereqs: hint" "$out" "01-prereqs/install.sh node" || bad "gemini installed without node"
H="$(newhome oldnode)"
out="$(runmod "$H" "$W/oldbin" install.sh pi 2>&1)"; rc=$?
[ "$rc" != 0 ] && assert_has "a Node.js older than 22.19 is refused for pi" "$out" "Node.js 22.19+ not found" || bad "pi installed with an old node"
[ ! -e "$H/.local/bin/pi" ] && ok "nothing installed for pi on an old node" || bad "pi launcher written on an old node"

# ---- 8: uninstall -----------------------------------------------------------------------------------------------------
H="$(newhome un)"
runmod "$H" "$FAKEBIN" install.sh claude codex gemini pi copilot >/dev/null 2>&1
mkdir -p "$H/.claude" "$H/.codex" "$H/.pi/agent"
echo keep >"$H/.claude/settings.json"
echo keep >"$H/.codex/config.toml"
echo keep >"$H/.pi/agent/settings.json"
rm -f "$H/.local/bin/copilot"
echo "user copilot" >"$H/.local/bin/copilot"
runmod "$H" "$FAKEBIN" uninstall.sh >"$W/un.out" 2>&1; rc=$?
assert_eq "uninstall exits 0" "$rc" 0
[ ! -e "$H/.local/bin/claude" ] && [ ! -e "$H/.local/bin/codex" ] && [ ! -e "$H/.local/bin/gemini" ] && [ ! -e "$H/.local/bin/pi" ] && ok "our commands are removed" || bad "commands remain"
assert_eq "a foreign command is left alone" "$(cat "$H/.local/bin/copilot")" "user copilot"
[ ! -d "$H/.local/share/work-kit/harness-clis" ] && ok "harness data removed" || bad "harness data remains"
[ ! -f "$H/.local/share/work-kit/state/16-harness-clis.list" ] && ok "state removed" || bad "state remains"
assert_eq "harness config is kept" "$(cat "$H/.claude/settings.json" "$H/.codex/config.toml" "$H/.pi/agent/settings.json" | tr '\n' ' ')" "keep keep keep "
out="$(runmod "$H" "$FAKEBIN" uninstall.sh 2>&1)"
assert_has "second uninstall is a no-op" "$out" "nothing to remove"

# ---- 9: platform guard (only where this host is not Linux x86_64) ------------------------------------------------------
if [ "$(uname -s)/$(uname -m)" != "Linux/x86_64" ]; then
  H="$(newhome plat)"
  out="$(env -i HOME="$H" PATH="$H/.local/bin:$FAKEBIN:$BASEPATH" KIT_ROOT="$KIT" KIT_OFFLINE="$KIT/offline" bash "$M/install.sh" claude 2>&1)"; rc=$?
  [ "$rc" != 0 ] && assert_has "non Linux x86_64 host is refused" "$out" "unsupported platform" || bad "platform guard missing"
fi

# ---- 10: the real lock and pins are consistent --------------------------------------------------------------------------
RL="$MOD/lock/artifacts.lock"
for pair in "claude:$CLAUDE_VERSION" "codex:$CODEX_VERSION" "opencode:$OPENCODE_VERSION" "copilot:$COPILOT_VERSION" "gemini:$GEMINI_VERSION" "pi:$PI_VERSION"; do
  n="${pair%%:*}"; v="${pair#*:}"
  line="$(grep -E "^[0-9a-f]{64}  $n/" "$RL" || true)"
  case "$line" in *"-$v-"*) ok "real lock: $n pinned at $v with a sha256" ;; *) bad "real lock: $n line missing or not $v" "$line" ;; esac
done
grep -q "^aider-chat==$AIDER_VERSION " "$MOD/lock/aider-requirements.txt" && ok "real lock: aider-chat==$AIDER_VERSION with hashes" || bad "real lock: aider pin"
[ "$(grep -c -- '--hash=sha256:' "$MOD/lock/aider-requirements.txt")" -ge 100 ] && ok "real lock: every requirement carries hashes" || bad "real lock: too few hashes"
! grep -vE '^(#|$)' "$RL" | grep -v 'https://\|npm-ci:' >/dev/null && ok "real lock: sources are https or npm-ci" || bad "real lock: odd source"
grep -q '"@google/gemini-cli": "'"$GEMINI_VERSION"'"' "$MOD/lock/gemini/package.json" && ok "gemini package.json matches the pin" || bad "gemini package.json differs from pins.conf"
grep -q '"@earendil-works/pi-coding-agent": "'"$PI_VERSION"'"' "$MOD/lock/pi/package.json" && ok "pi package.json matches the pin" || bad "pi package.json differs from pins.conf"
node -e 'const l=require(process.argv[1]); const p=l.packages["node_modules/@earendil-works/pi-coding-agent"]; if(!p||p.version!==process.argv[2]||!p.integrity) process.exit(1); for (const [k,v] of Object.entries(l.packages)) if (k && !v.integrity) process.exit(1)' "$MOD/lock/pi/package-lock.json" "$PI_VERSION" 2>/dev/null \
  && ok "pi package-lock pins the cli at $PI_VERSION and every package has integrity" || bad "pi package-lock incomplete (or no node here)"
node -e 'const l=require(process.argv[1]); const p=l.packages["node_modules/@google/gemini-cli"]; if(!p||!p.integrity||l.packages["node_modules/@lydell/node-pty-linux-x64"].integrity==null) process.exit(1)' "$MOD/lock/gemini/package-lock.json" 2>/dev/null \
  && ok "gemini package-lock has integrity for the cli and the linux-x64 pty package" || bad "gemini package-lock incomplete (or no node here)"

# ---- 11: the module names no private setup --------------------------------------------------------------------------------
private_re='werkbank|ll''pc|sync''thing|knowledge vault|tmux worker|lille''bor|avi''sion'
if grep -rniE "$private_re" "$MOD" --include='*' -l 2>/dev/null | grep -v '/tests/' | grep -q .; then
  bad "private setup referenced in the module" "$(grep -rniE "$private_re" "$MOD" | grep -v '/tests/' | head -3)"
else ok "no reference to a private setup"; fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
