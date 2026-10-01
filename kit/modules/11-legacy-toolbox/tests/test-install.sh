#!/usr/bin/env bash
# Installer logic with fake artifacts (shell scripts in the real archive layout) in a scratch
# HOME: install, idempotency, backup, wrapper environment, parser build step, skip rules,
# uninstall. Runs on any host; it does not prove the real Linux binaries work.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# --- fake offline directory -------------------------------------------------------------
OFF="$W/offline/legacy-toolbox"
mkdir -p "$OFF/bin" "$OFF/grammars" "$W/pk/uctags-1/bin" "$W/pk/scc" "$W/gr"
printf '#!/bin/sh\necho "Universal Ctags fake"\n' >"$W/pk/uctags-1/bin/ctags"
printf '#!/bin/sh\necho readtags fake\n' >"$W/pk/uctags-1/bin/readtags"
printf '#!/bin/sh\necho "scc fake"\n' >"$W/pk/scc/scc"
chmod +x "$W/pk/uctags-1/bin/"* "$W/pk/scc/scc"
tar -czf "$OFF/bin/uctags-2026.09.23-linux-x86_64.release.tar.gz" -C "$W/pk" uctags-1
tar -czf "$OFF/bin/scc_Linux_x86_64.tar.gz" -C "$W/pk/scc" scc
# fake tree-sitter: dump-languages lists the grammar dirs, build touches the output file
cat >"$W/ts.sh" <<'EOF'
#!/bin/sh
case "$1" in
  --version) echo "tree-sitter fake 0.27.0" ;;
  env) echo "DIR=$TREE_SITTER_DIR LIB=$TREE_SITTER_LIBDIR" ;;
  dump-languages)
    d="$(sed -n 's/.*\["\(.*\)"\].*/\1/p' "$TREE_SITTER_DIR/config.json")"
    for g in "$d"/tree-sitter-*; do
      n="${g##*/tree-sitter-}"
      echo "name: $n" >&2; echo "parser: $g/." >&2; echo "" >&2
    done ;;
  build) [ "$2" = "-o" ] && { : >"$3"; exit 0; }; exit 1 ;;
esac
EOF
gzip -c "$W/ts.sh" >"$OFF/bin/tree-sitter-linux-x64.gz"
for n in c-sharp cobol; do
  mkdir -p "$W/gr/tree-sitter-$n-1.0.0/src"
  echo "int x;" >"$W/gr/tree-sitter-$n-1.0.0/src/parser.c"
  tar -czf "$OFF/grammars/tree-sitter-$n-v1.0.0.tar.gz" -C "$W/gr" "tree-sitter-$n-1.0.0"
done

export HOME="$W/home"
export KIT_BIN_DIR="$W/home/.local/bin" KIT_DATA_DIR="$W/home/.local/share/work-kit"
export KIT_OFFLINE="$W/offline" KIT_ROOT="$W/kitroot"
mkdir -p "$HOME" "$KIT_ROOT"          # KIT_ROOT without modules/00-python: semgrep must be skipped
export CC=true                        # any existing command counts as a compiler for the fake build

# --- 1. default install ------------------------------------------------------------------
out="$(bash "$MOD/install.sh" 2>&1)" || bad "install exits 0 when semgrep is skipped"
for t in ctags readtags scc tree-sitter kit-depgraph; do check "installed $t" "[ -x '$KIT_BIN_DIR/$t' ]"; done
check "semgrep skipped, not failed" "grep -q 'skipped: semgrep' <<<\"\$out\""
check "wrapper sets kit config dir" "\"$KIT_BIN_DIR/tree-sitter\" env | grep -q 'DIR=$KIT_DATA_DIR/legacy-toolbox/tree-sitter/config'"
check "wrapper respects TREE_SITTER_DIR" "TREE_SITTER_DIR=/x \"$KIT_BIN_DIR/tree-sitter\" env | grep -q 'DIR=/x '"
check "config lists grammar dir" "grep -q 'legacy-toolbox/tree-sitter/grammars' '$KIT_DATA_DIR/legacy-toolbox/tree-sitter/config/config.json'"
check "cobol config added" "grep -q source.cobol '$KIT_DATA_DIR/legacy-toolbox/tree-sitter/grammars/tree-sitter-cobol/tree-sitter.json'"
ext=so; [ "$(uname -s)" = Darwin ] && ext=dylib
check "parser lib name uses underscore" "[ -f '$KIT_DATA_DIR/legacy-toolbox/tree-sitter/lib/c_sharp.$ext' ]"
check "kit-depgraph runs" "'$KIT_BIN_DIR/kit-depgraph' '$MOD/tests/fixtures/c' --level file --format tsv 2>/dev/null | grep -q util.h"

# --- 2. idempotent, no backups on identical content --------------------------------------
# shellcheck disable=SC2034  # read inside eval
out="$(bash "$MOD/install.sh" ctags scc tree-sitter depgraph 2>&1)"
check "second run says up to date" "grep -q 'up to date: $KIT_BIN_DIR/scc' <<<\"\$out\""
check "no backups after identical rerun" "[ -z \"\$(find '$HOME' -name '*.bak-*' || true)\" ]"

# --- 3. differing existing file is backed up ---------------------------------------------
printf '#!/bin/sh\necho mine\n' >"$KIT_BIN_DIR/scc"
bash "$MOD/install.sh" scc >/dev/null 2>&1
BAKS="$KIT_DATA_DIR/backups/11-legacy-toolbox"
check "own scc backed up under backups/" "ls '$BAKS' | grep -q '^scc.bak-'"
check "backup records the original path" "grep -qx '$KIT_BIN_DIR/scc' '$BAKS'/scc.bak-*.origin"
check "no backup beside the original" "! ls '$KIT_BIN_DIR' | grep -q 'bak-'"
check "kit scc restored" "\"$KIT_BIN_DIR/scc\" | grep -q 'scc fake'"

# --- 4. explicit request for a missing tool fails ----------------------------------------
if bash "$MOD/install.sh" semgrep >/dev/null 2>&1; then bad "explicit semgrep without wheels must fail"; else ok "explicit semgrep fails"; fi
if bash "$MOD/install.sh" nosuchtool >/dev/null 2>&1; then bad "unknown tool must fail"; else ok "unknown tool fails"; fi

# --- 4b. no system python3: kit-depgraph finds the kit CPython at run time ------------------
NOPY="$W/nopy"
mkdir -p "$NOPY" "$HOME/.local/share/uv/python/cpython-3.12.0-test/bin"
ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$HOME/.local/share/uv/python/cpython-3.12.0-test/bin/python3"
for t in bash sh env dirname basename cat grep readlink uname tr sort head tail wc cut mkdir date git; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$NOPY/$t"
done
check "kit-depgraph runs without system python3" "PATH='$NOPY' '$KIT_BIN_DIR/kit-depgraph' '$MOD/tests/fixtures/c' --level file --format tsv 2>/dev/null | grep -q util.h"
# The first install can have recorded the build host's Python. Clear only that optional fast
# path so this branch checks the launcher's runtime discovery after the kit CPython is removed.
awk 'BEGIN { cleared = 0 } !cleared && /^PY=/ { print "PY="; cleared = 1; next } { print }' \
  "$KIT_BIN_DIR/kit-depgraph" >"$KIT_BIN_DIR/kit-depgraph.new"
mv "$KIT_BIN_DIR/kit-depgraph.new" "$KIT_BIN_DIR/kit-depgraph"
chmod +x "$KIT_BIN_DIR/kit-depgraph"
rm -rf "$HOME/.local/share/uv"
# shellcheck disable=SC2034  # read inside eval
out="$(PATH="$NOPY" "$KIT_BIN_DIR/kit-depgraph" "$MOD/tests/fixtures/c" 2>&1 || true)"
check "no python at all: message names 01-prereqs" "grep -q 01-prereqs <<<\"\$out\""

# --- 5. uninstall ------------------------------------------------------------------------
bash "$MOD/uninstall.sh" >/dev/null 2>&1
for t in ctags readtags scc tree-sitter kit-depgraph; do check "removed $t" "[ ! -e '$KIT_BIN_DIR/$t' ]"; done
check "data dir removed" "[ ! -d '$KIT_DATA_DIR/legacy-toolbox' ]"
check "backup kept" "ls '$BAKS' | grep -q '^scc.bak-'"
check "uninstall twice is harmless" "bash '$MOD/uninstall.sh' >/dev/null 2>&1"
exit "$fail"
