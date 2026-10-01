#!/usr/bin/env bash
# Tests for 31-caveman. Every run uses a temp HOME; nothing outside it is touched.
# Usage: bash tests/run-tests.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
export PYTHONDONTWRITEBYTECODE=1
unset CLAUDE_CONFIG_DIR CODEX_HOME XDG_CONFIG_HOME KIT_DATA_DIR KIT_BIN_DIR CAVEMAN_DEFAULT_MODE

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }
check() { # check "<name>" <command...>
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi
}
contains() { grep -qF -- "$2" "$1"; }

new_home() { # new_home <name> -> prints path
  local h="$ROOT/$1"
  mkdir -p "$h"
  printf '%s' "$h"
}

# hook_cmd <home> <event> -> command string from settings.json
hook_cmd() {
  python3 - "$1/.claude/settings.json" "$2" <<'E'
import json, sys
s = json.load(open(sys.argv[1]))
for e in s["hooks"][sys.argv[2]]:
    for h in e["hooks"]:
        if "caveman-hook.sh" in h["command"]:
            print(h["command"]); raise SystemExit
raise SystemExit(1)
E
}

# --- 1. install everywhere into a home that already has user content --------------------
H="$(new_home h1)"
mkdir -p "$H/.claude" "$H/.codex" "$H/.gemini"
printf '# my notes\n' > "$H/.claude/CLAUDE.md"
printf '# codex notes\n' > "$H/.codex/AGENTS.md"
cat > "$H/.claude/settings.json" <<'E'
{"permissions": {"allow": ["Bash(ls)"]}, "hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "echo mine"}]}]}}
E
printf 'model: x\n' > "$H/.aider.conf.yml"

OUT="$ROOT/install1.txt"
HOME="$H" bash "$HERE/install.sh" --all > "$OUT" 2>&1
check "install.sh --all exits 0" test -s "$OUT"
DEST="$H/.local/share/work-kit/caveman"

for f in caveman-hook.sh caveman-setup rules/caveman-rule.md upstream/LICENSE upstream/SHA256SUMS \
         upstream/UPSTREAM.md upstream/skills/caveman/SKILL.md upstream/src/hooks/caveman-activate.js \
         upstream/src/hooks/caveman-mode-tracker.js upstream/src/hooks/caveman-config.js \
         upstream/src/hooks/caveman-statusline.sh; do
  check "installed copy has $f" test -f "$DEST/$f"
done
check "kit-caveman launcher installed" test -x "$H/.local/bin/kit-caveman"

# always-on rule in every harness
for f in .claude/CLAUDE.md .codex/AGENTS.md .gemini/GEMINI.md .config/opencode/AGENTS.md \
         .copilot/copilot-instructions.md .continue/rules/caveman.md \
         .local/share/work-kit/generated/caveman-cursor-user-rule.md \
         .local/share/work-kit/generated/caveman-aider.md; do
  check "rule present: $f" contains "$H/$f" "caveman style, level full"
done
check "user text kept in CLAUDE.md" contains "$H/.claude/CLAUDE.md" "# my notes"
check "user text kept in codex AGENTS.md" contains "$H/.codex/AGENTS.md" "# codex notes"
check "CLAUDE.md backup made under backups/" bash -c "ls '$H/.local/share/work-kit/backups/31-caveman'/.claude/CLAUDE.md.bak-* >/dev/null"
check "no backup beside a user file" bash -c "[ -z \"\$(find '$H' -name '*.bak-*' -not -path '$H/.local/share/work-kit/backups/31-caveman/*')\" ]"
check "continue rule is alwaysApply" contains "$H/.continue/rules/caveman.md" "alwaysApply: true"
check "aider conf keeps user key and lists the rule file" bash -c "grep -q 'model: x' '$H/.aider.conf.yml' && grep -q 'caveman-aider.md' '$H/.aider.conf.yml'"

# skills
check "skill link ~/.claude/skills/caveman" test -f "$H/.claude/skills/caveman/SKILL.md"
check "skill link ~/.agents/skills/caveman" test -f "$H/.agents/skills/caveman/SKILL.md"

# settings.json
check "settings.json valid JSON" python3 -c "import json;json.load(open('$H/.claude/settings.json'))"
check "settings.json keeps permissions" contains "$H/.claude/settings.json" "Bash(ls)"
check "settings.json keeps foreign hook" contains "$H/.claude/settings.json" "echo mine"
check "SessionStart hook wired" hook_cmd "$H" SessionStart
check "UserPromptSubmit hook wired" hook_cmd "$H" UserPromptSubmit
check "prompt hook timeout leaves room for a slow laptop" python3 -c "
import json
s=json.load(open('$H/.claude/settings.json'))
e=next(e for e in s['hooks']['UserPromptSubmit'] if 'caveman-hook.sh' in str(e))
assert e['hooks'][0]['timeout'] >= 60"
check "statusLine badge wired (none before)" contains "$H/.claude/settings.json" "caveman-statusline.sh"
check "settings.json backup made under backups/" bash -c "ls '$H/.local/share/work-kit/backups/31-caveman'/.claude/settings.json.bak-* >/dev/null"

# --- 2. hook output: node and shell fallback -------------------------------------------
SS="$(hook_cmd "$H" SessionStart)"
UP="$(hook_cmd "$H" UserPromptSubmit)"

if command -v node >/dev/null 2>&1; then
  rm -f "$H/.claude/.caveman-active"
  HOME="$H" sh -c "$SS" < /dev/null > "$ROOT/ss-node.txt" 2>&1
  check "node: SessionStart prints active header" contains "$ROOT/ss-node.txt" "CAVEMAN MODE ACTIVE — level: full"
  check "node: SessionStart prints the rules" contains "$ROOT/ss-node.txt" "Respond terse like smart caveman"
  check "node: only the full row of the level table" bash -c "grep -q '^| \*\*full\*\*' '$ROOT/ss-node.txt' && ! grep -q '^| \*\*ultra\*\*' '$ROOT/ss-node.txt'"
  check "node: flag file says full" bash -c "[ \"\$(cat '$H/.claude/.caveman-active')\" = full ]"
  printf '{"prompt":"fix the bug"}' | HOME="$H" sh -c "$UP" > "$ROOT/up-node.txt" 2>&1
  check "node: UserPromptSubmit emits JSON reminder" python3 -c "
import json;d=json.load(open('$ROOT/up-node.txt'));assert 'CAVEMAN MODE ACTIVE (full)' in d['hookSpecificOutput']['additionalContext']"
printf '{"prompt":"stop caveman"}' | HOME="$H" sh -c "$UP" > /dev/null 2>&1
check "node: 'stop caveman' removes the flag" test ! -e "$H/.claude/.caveman-active"
else
  echo "skip node tests: node not installed"
fi

# Shell fallback: PATH with basic tools only, no node.
NN="$ROOT/nonode"
mkdir -p "$NN"
for b in sh awk head tr rm mv mkdir dirname cat grep sed; do ln -sf "$(command -v "$b")" "$NN/$b"; done
rm -f "$H/.claude/.caveman-active"
HOME="$H" PATH="$NN" sh -c "$SS" < /dev/null > "$ROOT/ss-sh.txt" 2>&1
check "shell: SessionStart prints active header" contains "$ROOT/ss-sh.txt" "CAVEMAN MODE ACTIVE — level: full"
check "shell: flag file says full" bash -c "[ \"\$(cat '$H/.claude/.caveman-active')\" = full ]"
check "shell: no frontmatter in output" bash -c "! grep -q '^name: caveman' '$ROOT/ss-sh.txt'"
if [ -f "$ROOT/ss-node.txt" ]; then
  check "shell output equals node output" bash -c "diff <(cat '$ROOT/ss-node.txt'; echo) '$ROOT/ss-sh.txt'"
fi
printf '{"prompt":"fix the bug"}' | HOME="$H" PATH="$NN" sh -c "$UP" > "$ROOT/up-sh.txt" 2>&1
check "shell: UserPromptSubmit emits JSON reminder" python3 -c "
import json;d=json.load(open('$ROOT/up-sh.txt'));assert 'CAVEMAN MODE ACTIVE (full)' in d['hookSpecificOutput']['additionalContext']"
printf '{"prompt":"How do I exit vim normal mode?"}' | HOME="$H" PATH="$NN" sh -c "$UP" > "$ROOT/up-sh2.txt" 2>&1
check "shell: 'normal mode' inside a question keeps caveman" test -e "$H/.claude/.caveman-active"
printf '{"prompt":"stop caveman"}' | HOME="$H" PATH="$NN" sh -c "$UP" > "$ROOT/up-sh3.txt" 2>&1
check "shell: 'stop caveman' removes the flag and emits nothing" bash -c "test ! -e '$H/.claude/.caveman-active' && test ! -s '$ROOT/up-sh3.txt'"

# Slow-node simulation: track must not start Node, so this prompt returns within one second.
SLOW="$ROOT/slow-node"; mkdir -p "$SLOW"
printf '%s\n' '#!/bin/sh' 'sleep 6' > "$SLOW/node"; chmod +x "$SLOW/node"
printf full > "$H/.claude/.caveman-active"
check "track bypasses a slow node shim" bash -c "printf '{\\\"prompt\\\":\\\"fix the bug\\\"}' | HOME='$H' PATH='$SLOW':\$PATH python3 -c '
import subprocess, sys
r = subprocess.run([\"sh\", \"-c\", sys.argv[1]], input=sys.stdin.read(), text=True, capture_output=True, timeout=1)
assert r.returncode == 0 and \"CAVEMAN MODE ACTIVE\" in r.stdout
' '$UP'"

# --- 3. idempotent rerun ----------------------------------------------------------------
BEFORE="$(cd "$H" && find . -type f -not -path './.claude/.caveman*' | sort | xargs shasum -a 256 | shasum -a 256)"
HOME="$H" bash "$HERE/install.sh" --all > "$ROOT/install2.txt" 2>&1
AFTER="$(cd "$H" && find . -type f -not -path './.claude/.caveman*' | sort | xargs shasum -a 256 | shasum -a 256)"
check "rerun changes no file" test "$BEFORE" = "$AFTER"
check "rerun creates no extra backup" bash -c "[ \$(ls '$H/.local/share/work-kit/backups/31-caveman'/.claude/CLAUDE.md.bak-* | wc -l) -eq 1 ]"
check "rerun reports unchanged" contains "$ROOT/install2.txt" "[unchanged]"

# --- 4. uninstall -----------------------------------------------------------------------
HOME="$H" bash "$HERE/uninstall.sh" > "$ROOT/uninstall1.txt" 2>&1
check "uninstall: caveman rule gone from CLAUDE.md" bash -c "! grep -q 'caveman' '$H/.claude/CLAUDE.md'"
check "uninstall: user text kept in CLAUDE.md" contains "$H/.claude/CLAUDE.md" "# my notes"
check "uninstall: user text kept in codex AGENTS.md" contains "$H/.codex/AGENTS.md" "# codex notes"
check "uninstall: gemini file removed (held only the block)" test ! -e "$H/.gemini/GEMINI.md"
check "uninstall: hooks gone, foreign hook and permissions kept" python3 -c "
import json;s=json.load(open('$H/.claude/settings.json'))
assert 'caveman' not in json.dumps(s).lower(), s
assert s['hooks']['SessionStart'][0]['hooks'][0]['command']=='echo mine'
assert s['permissions']['allow']==['Bash(ls)']
assert 'statusLine' not in s"
check "uninstall: skill links gone" bash -c "test ! -e '$H/.claude/skills/caveman' && test ! -e '$H/.agents/skills/caveman'"
check "uninstall: generated files gone" bash -c "test ! -e '$H/.continue/rules/caveman.md' && test ! -e '$H/.local/share/work-kit/generated/caveman-aider.md'"
check "uninstall: aider conf keeps user key" bash -c "grep -q 'model: x' '$H/.aider.conf.yml' && ! grep -q caveman '$H/.aider.conf.yml'"
check "uninstall: installed copy and command removed" bash -c "test ! -e '$DEST' && test ! -e '$H/.local/bin/kit-caveman'"

# --- 5. detection: only detected harnesses, no --all ------------------------------------
H2="$(new_home h2)"
mkdir -p "$H2/.codex"
OUT2="$(HOME="$H2" PATH="/usr/bin:/bin" bash "$HERE/install.sh" 2>&1)"
check "detected: codex only gets a file" bash -c "test -f '$H2/.codex/AGENTS.md' && test ! -e '$H2/.gemini/GEMINI.md' && test ! -e '$H2/.claude/settings.json'"
check "detected: skill linked for codex" test -f "$H2/.agents/skills/caveman/SKILL.md"
check "detected: says what was skipped" bash -c "grep -q 'not detected' <<<'$OUT2'"

# --- 6. dry run writes nothing ----------------------------------------------------------
H3="$(new_home h3)"
HOME="$H3" bash "$HERE/install.sh" --dry-run --all > "$ROOT/dry.txt" 2>&1
check "dry run prints plan" contains "$ROOT/dry.txt" "[would create]"
check "dry run writes nothing" bash -c "[ -z \"\$(find '$H3' -type f -o -type l)\" ]"

# --- 7. hooks are not added when the caveman plugin is enabled or hooks exist ------------
H4="$(new_home h4)"
mkdir -p "$H4/.claude"
echo '{"enabledPlugins": {"caveman@caveman": true}}' > "$H4/.claude/settings.json"
HOME="$H4" bash "$HERE/install.sh" --harness claude > "$ROOT/plugin.txt" 2>&1
check "plugin enabled: settings.json untouched" bash -c "[ \"\$(cat '$H4/.claude/settings.json')\" = '{\"enabledPlugins\": {\"caveman@caveman\": true}}' ]"
check "plugin enabled: says so" contains "$ROOT/plugin.txt" "brings its own hooks"
H5="$(new_home h5)"
mkdir -p "$H5/.claude"
echo '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "node ~/.claude/hooks/caveman-activate.js"}]}]}}' > "$H5/.claude/settings.json"
HOME="$H5" bash "$HERE/install.sh" --harness claude > "$ROOT/foreign.txt" 2>&1
check "foreign caveman hook kept, ours not duplicated" bash -c "! grep -q caveman-hook.sh '$H5/.claude/settings.json' || python3 -c \"
import json;s=json.load(open('$H5/.claude/settings.json'));assert len(s['hooks']['SessionStart'])==1\""
check "foreign caveman hook: says so" contains "$ROOT/foreign.txt" "exists already"

# --- 8. invalid settings.json is left alone ---------------------------------------------
H6="$(new_home h6)"
mkdir -p "$H6/.claude"
printf '{ not json' > "$H6/.claude/settings.json"
HOME="$H6" bash "$HERE/install.sh" --harness claude > "$ROOT/badjson.txt" 2>&1
check "invalid settings.json untouched" bash -c "[ \"\$(cat '$H6/.claude/settings.json')\" = '{ not json' ]"
check "invalid settings.json reported" contains "$ROOT/badjson.txt" "not valid JSON"

# --- 8b. aider conf with its own read: key: its items stay, the rule file joins the list, once ------
H61="$(new_home h61)"
printf 'read:\n  - CONVENTIONS.md\nmodel: x\n' > "$H61/.aider.conf.yml"
HOME="$H61" bash "$HERE/install.sh" --harness aider > "$ROOT/aider.txt" 2>&1
HOME="$H61" bash "$HERE/install.sh" --harness aider > "$ROOT/aider2.txt" 2>&1
check "aider: own read: list kept, rule file added once" bash -c "[ \"\$(grep -c 'CONVENTIONS.md' '$H61/.aider.conf.yml')\" = 1 ] && [ \"\$(grep -c 'caveman-aider.md' '$H61/.aider.conf.yml')\" = 1 ] && [ \"\$(grep -c '^read:' '$H61/.aider.conf.yml')\" = 1 ] && grep -q 'model: x' '$H61/.aider.conf.yml'"
check "aider: second run unchanged" contains "$ROOT/aider2.txt" "[unchanged]"
HOME="$H61" bash "$HERE/uninstall.sh" > /dev/null 2>&1
check "aider: uninstall leaves the user's read: list" bash -c "[ \"\$(cat '$H61/.aider.conf.yml')\" = \"\$(printf 'read:\\n  - CONVENTIONS.md\\nmodel: x')\" ]"

# --- 9. CLAUDE_CONFIG_DIR and CODEX_HOME are respected ----------------------------------
H7="$(new_home h7)"
HOME="$H7" CLAUDE_CONFIG_DIR="$H7/cc" CODEX_HOME="$H7/cx" bash "$HERE/install.sh" --harness claude,codex > /dev/null 2>&1
check "CLAUDE_CONFIG_DIR used" test -f "$H7/cc/settings.json"
check "CODEX_HOME used" test -f "$H7/cx/AGENTS.md"
check "nothing written to default ~/.claude" test ! -e "$H7/.claude"

# --- 10. project mode -------------------------------------------------------------------
H8="$(new_home h8)"
P="$H8/repo"
mkdir -p "$P"
printf '# Project rules\n' > "$P/AGENTS.md"
HOME="$H8" bash "$HERE/install.sh" --project "$P" > /dev/null 2>&1
check "project: AGENTS.md block, text kept" bash -c "grep -q 'caveman style' '$P/AGENTS.md' && grep -q '# Project rules' '$P/AGENTS.md'"
check "project: copilot instructions" contains "$P/.github/copilot-instructions.md" "caveman style"
check "project: cursor rule alwaysApply" contains "$P/.cursor/rules/caveman.mdc" "alwaysApply: true"
HOME="$H8" bash "$HERE/uninstall.sh" --project "$P" > /dev/null 2>&1
check "project uninstall: text kept, files gone" bash -c "grep -q '# Project rules' '$P/AGENTS.md' && ! grep -q caveman '$P/AGENTS.md' && test ! -e '$P/.cursor/rules/caveman.mdc' && test ! -e '$P/.github/copilot-instructions.md'"

# --- 11. integrity: a modified upstream file stops the install --------------------------
COPY="$ROOT/kitcopy/modules/31-caveman"
mkdir -p "$ROOT/kitcopy/modules"
cp -R "$HERE/../../lib" "$ROOT/kitcopy/lib"
cp -R "$HERE" "$COPY"
rm -rf "$COPY/tests"
echo "// tampered" >> "$COPY/upstream/src/hooks/caveman-activate.js"
H9="$(new_home h9)"
if HOME="$H9" bash "$COPY/install.sh" --all > "$ROOT/tamper.txt" 2>&1; then bad "tampered upstream file is refused"; else ok "tampered upstream file is refused"; fi
check "tamper: nothing installed" bash -c "[ -z \"\$(find '$H9' -type f -o -type l)\" ]"
check "tamper: names the file" contains "$ROOT/tamper.txt" "caveman-activate.js"

# --- 12. pinned copy and license --------------------------------------------------------
check "upstream SHA256SUMS verifies (shasum)" bash -c "cd '$HERE/upstream' && shasum -a 256 -c SHA256SUMS"
check "LICENSE is MIT" contains "$HERE/upstream/LICENSE" "MIT License"
check "UPSTREAM.md names the commit" contains "$HERE/upstream/UPSTREAM.md" "0d95a81d35a9f2d123a5e9430d1cfc43d55f1bb0"

# --- 13. no system python3: the kit CPython is used ---------------------------------------
# PATH holds only the tools the scripts need, python3 excluded; the kit CPython sits where 00-python puts it.
NOPY="$ROOT/nopy-bin"
mkdir -p "$NOPY"
for t in bash sh env dirname basename cat cp mv rm ln mkdir mktemp chmod cmp diff date grep sed find sort head tail tr wc cut readlink uname touch printf test true false tee id ls sleep; do
  p="$(command -v "$t" 2>/dev/null)" && [ -x "$p" ] && ln -sf "$p" "$NOPY/$t"
done
H13="$(new_home h13)"
mkdir -p "$H13/.local/share/uv/python/cpython-3.12.0-test/bin"
ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$H13/.local/share/uv/python/cpython-3.12.0-test/bin/python3"
if HOME="$H13" PATH="$NOPY" bash "$HERE/install.sh" --all > "$ROOT/nopy.txt" 2>&1; then ok "no system python3: install uses the kit CPython"; else bad "no system python3: install uses the kit CPython"; fi
check "no system python3: kit-caveman launcher runs" env HOME="$H13" PATH="$NOPY" "$H13/.local/bin/kit-caveman" --help
H14="$(new_home h14)"
if HOME="$H14" PATH="$NOPY" bash "$HERE/install.sh" --all > "$ROOT/nopy2.txt" 2>&1; then bad "no python at all: install refuses"; else ok "no python at all: install refuses"; fi
check "no python at all: message names 01-prereqs" contains "$ROOT/nopy2.txt" "01-prereqs"
HOME="$H13" PATH="$NOPY" bash "$HERE/uninstall.sh" > /dev/null 2>&1
check "no system python3: uninstall works" bash -c "test ! -e '$H13/.local/bin/kit-caveman' && test ! -e '$H13/.local/share/work-kit/caveman'"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
