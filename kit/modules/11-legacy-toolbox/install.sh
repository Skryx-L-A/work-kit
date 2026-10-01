#!/usr/bin/env bash
# Install the legacy-code toolbox: universal-ctags, scc, tree-sitter (+ grammars), semgrep
# (+ local rules) and kit-depgraph. No network, no sudo, everything under $HOME.
# Usage: install.sh [ctags|scc|tree-sitter|semgrep|depgraph ...]   (default: all)
# Artifacts come from kit/offline/legacy-toolbox (see fetch.sh). A tool whose artifact is
# missing is skipped with a warning; naming it explicitly makes that an error.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
export KIT_DATA_DIR="$DATA_DIR"
TB="$DATA_DIR/legacy-toolbox"
STATE_DIR="$DATA_DIR/state"
STATE="$STATE_DIR/11-legacy-toolbox.list"
BAK_DIR="$DATA_DIR/backups/11-legacy-toolbox"
SRC="$KIT_OFFLINE/legacy-toolbox"
SO_EXT="so"
[ "$(uname -s)" = "Darwin" ] && SO_EXT="dylib"

log() { printf '[legacy-toolbox] %s\n' "$*"; }
warn() { printf '[legacy-toolbox] WARNING: %s\n' "$*" >&2; }
die() { printf '[legacy-toolbox] ERROR: %s\n' "$*" >&2; exit 1; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

mkdir -p "$BIN_DIR" "$STATE_DIR" "$TB"
touch "$STATE"
TMP="$(mktemp -d "$TB/.tmp.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

record() { grep -qxF "$1" "$STATE" || echo "$1" >>"$STATE"; }

# place_file SRC DST [MODE]: copy with backup of a differing existing file, record for uninstall.
place_file() {
  local src="$1" dst="$2" mode="${3:-0755}" bak
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    log "up to date: $dst"
  else
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      # backups live under the data dir, with the original path recorded next to them
      mkdir -p "$BAK_DIR"
      bak="$BAK_DIR/$(basename "$dst").bak-$(date +%Y%m%d%H%M%S)"
      while [ -e "$bak" ]; do bak="$bak-1"; done
      mv "$dst" "$bak"
      printf '%s\n' "$dst" >"$bak.origin"
      log "backup: $dst -> $bak"
    fi
    install -m "$mode" "$src" "$dst"
    log "installed $dst"
  fi
  record "file:$dst"
}

# artifact PATTERN: print the newest file in $SRC matching the glob, or nothing.
artifact() {
  local f
  for f in "$SRC"/$1; do [ -f "$f" ] && echo "$f"; done | sort | tail -n 1
}

# extract_root ARCHIVE DIR: unpack a tar.gz into DIR; print the directory holding the content.
extract_root() {
  local top
  mkdir -p "$2"
  tar -xzf "$1" -C "$2"
  top="$(find "$2" -mindepth 1 -maxdepth 1 | head -n 2)"
  if [ "$(printf '%s\n' "$top" | grep -c .)" = 1 ] && [ -d "$top" ] \
     && [ ! -d "$2/src" ] && [ ! -f "$2/tree-sitter.json" ]; then
    echo "$top"
  else
    echo "$2"
  fi
}

# skip REASON: leave the current tool step (exit code 3 tells the runner it was skipped).
skip() { printf '[legacy-toolbox] SKIP: %s\n' "$*" >&2; exit 3; }

check_version() {
  local v
  if v="$("$1" --version 2>&1)"; then log "$(printf '%s' "$v" | head -n 1)"
  else warn "$1 does not run here (not Linux x86_64?)"; fi
}

# --- ctags ------------------------------------------------------------------------------
install_ctags() {
  local a root
  a="$(artifact 'bin/uctags-*-linux-x86_64.release.tar.gz')"
  [ -n "$a" ] || skip "missing: $SRC/bin/uctags-*.tar.gz"
  root="$(extract_root "$a" "$TMP/ctags")"
  [ -f "$root/bin/ctags" ] || die "bin/ctags not found in $a"
  place_file "$root/bin/ctags" "$BIN_DIR/ctags"
  [ -f "$root/bin/readtags" ] && place_file "$root/bin/readtags" "$BIN_DIR/readtags"
  check_version "$BIN_DIR/ctags"
}

# --- scc --------------------------------------------------------------------------------
install_scc() {
  local a root
  a="$(artifact 'bin/scc_Linux_x86_64.tar.gz')"
  [ -n "$a" ] || skip "missing: $SRC/bin/scc_Linux_x86_64.tar.gz"
  root="$(extract_root "$a" "$TMP/scc")"
  [ -f "$root/scc" ] || die "scc not found in $a"
  place_file "$root/scc" "$BIN_DIR/scc"
  check_version "$BIN_DIR/scc"
}

# --- tree-sitter ------------------------------------------------------------------------
TS="$TB/tree-sitter"

write_wrapper_ts() {
  cat >"$TMP/ts-wrapper" <<'EOF'
#!/bin/sh
# work-kit 11-legacy-toolbox: tree-sitter CLI with kit-owned config, grammars and parser libs.
TS="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/legacy-toolbox/tree-sitter"
: "${TREE_SITTER_DIR:=$TS/config}"
: "${TREE_SITTER_LIBDIR:=$TS/lib}"
export TREE_SITTER_DIR TREE_SITTER_LIBDIR
exec "$TS/bin/tree-sitter" "$@"
EOF
  place_file "$TMP/ts-wrapper" "$BIN_DIR/tree-sitter"
}

# The COBOL grammar ships no tree-sitter.json, so the CLI cannot map file extensions to it.
add_cobol_config() {
  [ -d "$1" ] && [ ! -f "$1/tree-sitter.json" ] || return 0
  cat >"$1/tree-sitter.json" <<'EOF'
{
  "grammars": [
    {
      "name": "COBOL",
      "scope": "source.cobol",
      "path": ".",
      "file-types": ["cbl", "cob", "cobol", "cpy", "pco"]
    }
  ],
  "metadata": {"version": "0.1.1", "license": "MIT"}
}
EOF
}

install_grammars() {
  local gdir="$TS/grammars" f n sha root
  mkdir -p "$gdir" "$TS/lib" "$TS/config"
  for f in "$SRC"/grammars/tree-sitter-*.tar.gz; do
    [ -f "$f" ] || continue
    n="$(basename "$f" .tar.gz | sed -E 's/-v?[0-9]+\.[0-9]+\.[0-9]+$//')"
    sha="$(sha256_of "$f")"
    if [ "$(cat "$gdir/$n/.kit-sha256" 2>/dev/null || true)" = "$sha" ]; then
      log "grammar up to date: $n"
      continue
    fi
    root="$(extract_root "$f" "$TMP/g-$n")"
    rm -rf "${gdir:?}/$n"
    mkdir -p "$gdir/$n"
    cp -R "$root/." "$gdir/$n/"
    [ "$n" = "tree-sitter-cobol" ] && add_cobol_config "$gdir/$n"
    echo "$sha" >"$gdir/$n/.kit-sha256"
    log "grammar unpacked: $n"
  done
  printf '{\n  "parser-directories": ["%s"]\n}\n' "$gdir" >"$TS/config/config.json"
}

find_cc() {
  local c
  for c in "${CC:-}" cc gcc clang; do
    [ -n "$c" ] && command -v "$c" >/dev/null 2>&1 && return 0
  done
  return 1
}

build_parsers() {
  local n p lib top stamp built=0 failed=0 have_cc=0
  find_cc && have_cc=1
  if compgen -G "$SRC/lib/*.$SO_EXT" >/dev/null; then
    cp -f "$SRC"/lib/*."$SO_EXT" "$TS/lib/"
    log "prebuilt parser libraries copied from offline/legacy-toolbox/lib"
  fi
  # dump-languages lists every grammar the CLI can see: name and grammar directory. The glibc-2.34
  # fallback CLI (0.25) prints no "name:" and quotes the path: its grammars are not listed here,
  # so it relies on the prebuilt libraries (a record would need the name for the library file).
  "$BIN_DIR/tree-sitter" dump-languages 2>&1 \
    | awk '/^name: /{n=substr($0,7)} /^parser: /{p=substr($0,9); gsub(/"/, "", p); if(n != "" && !(p in s)){s[p]=1; print n "\t" p}; n=""}' >"$TMP/langs.tsv" || true
  if [ ! -s "$TMP/langs.tsv" ] && compgen -G "$TS/lib/*.$SO_EXT" >/dev/null; then
    log "tree-sitter parsers: $(find "$TS/lib" -name "*.$SO_EXT" | wc -l | tr -d ' ') prebuilt (this CLI lists no grammar names)"
    return 0
  fi
  while IFS=$'\t' read -r n p; do
    [ -n "$n" ] || continue
    lib="$TS/lib/$(printf '%s' "$n" | tr '-' '_').$SO_EXT"
    top="${p#"$TS/grammars/"}"; top="${top%%/*}"
    stamp="$TS/grammars/$top/.kit-sha256"
    if [ -f "$lib" ] && [ ! "$stamp" -nt "$lib" ]; then continue; fi
    if [ "$have_cc" = 0 ]; then failed=$((failed + 1)); continue; fi
    log "compiling grammar $n (large grammars take a minute)"
    if "$BIN_DIR/tree-sitter" build -o "$lib" "$p" >"$TMP/build.log" 2>&1; then
      built=$((built + 1))
    else
      warn "grammar $n did not compile: $(tail -n 1 "$TMP/build.log")"
      failed=$((failed + 1))
    fi
  done <"$TMP/langs.tsv"
  if [ "$have_cc" = 0 ] && [ "$failed" -gt 0 ]; then
    warn "no C compiler found: $failed grammar(s) not compiled. Install one (01-prereqs/install.sh build-essential) and re-run install.sh tree-sitter."
  fi
  log "tree-sitter parsers: $built built, $failed missing"
}

install_tree_sitter() {
  local a
  a="$(artifact 'bin/tree-sitter-linux-x64.gz')"
  [ -n "$a" ] || skip "missing: $SRC/bin/tree-sitter-linux-x64.gz"
  mkdir -p "$TS/bin"
  gunzip -c "$a" >"$TMP/tree-sitter.bin"
  chmod +x "$TMP/tree-sitter.bin"
  # Current releases need glibc 2.39 (Ubuntu 24.04+); older systems get the last 2.34 build.
  if ! "$TMP/tree-sitter.bin" --version >/dev/null 2>&1; then
    a="$(artifact 'bin/glibc-2.34/tree-sitter-linux-x64.gz')"
    if [ -n "$a" ]; then
      log "tree-sitter: current build does not run here (glibc $(ldd --version 2>/dev/null | head -n 1 | awk '{print $NF}')), using $(basename "$(dirname "$a")") fallback"
      gunzip -c "$a" >"$TMP/tree-sitter.bin"
    fi
  fi
  place_file "$TMP/tree-sitter.bin" "$TS/bin/tree-sitter"
  write_wrapper_ts
  install_grammars
  build_parsers
  check_version "$BIN_DIR/tree-sitter"
}

# --- semgrep ----------------------------------------------------------------------------
install_semgrep() {
  local wheels="$SRC/semgrep/wheels" lib="$KIT_ROOT/modules/00-python/lib.sh" rules n wheel want have
  compgen -G "$wheels/semgrep-*.whl" >/dev/null || skip "missing: $wheels/semgrep-*.whl"
  [ -f "$lib" ] || skip "needs module 00-python ($lib not found)"
  # shellcheck disable=SC1090
  . "$lib"
  kit_require_uv >/dev/null 2>&1 || skip "needs uv from module 00-python (run its install.sh first)"
  mkdir -p "$KIT_TOOL_DIR"
  wheel="$(artifact 'semgrep/wheels/semgrep-*.whl')"
  want="$(basename "$wheel" | sed -E 's/^semgrep-([0-9][0-9A-Za-z.+!]*)-.*/\1/')"
  have="$("$BIN_DIR/semgrep" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9A-Za-z.+_-]+)+' | head -n 1 || true)"
  if [ -n "$want" ] && [ "$have" = "$want" ]; then
    log "semgrep: version $want already installed, skipped"
  else
    UV_TOOL_DIR="$KIT_TOOL_DIR" UV_TOOL_BIN_DIR="$BIN_DIR" UV_PYTHON_DOWNLOADS=never \
      kit_uv tool install --force --offline --no-index --find-links "$wheels" \
        --python "$KIT_PYTHON_VERSION" semgrep >"$TMP/uv.log" 2>&1 \
      || { tail -n 5 "$TMP/uv.log" >&2; die "semgrep install failed"; }
    kit_fix_lock_perms
    log "installed semgrep ($BIN_DIR/semgrep)"
  fi
  record "uvtool:semgrep"
  record "file:$BIN_DIR/semgrep"
  record "file:$BIN_DIR/pysemgrep"
  rules="$(artifact 'semgrep/semgrep-rules-*.tar.gz')"
  if [ -n "$rules" ]; then
    # Unpack to a scratch dir, then keep only real rule files of the curated languages: the
    # whole repo holds non-rule yaml that breaks `--config <dir>`, and all rules together
    # make every scan slow.
    mkdir -p "$TMP/rules-src"
    tar -xzf "$rules" -C "$TMP/rules-src" --strip-components=1
    rm -rf "${TB:?}/semgrep-rules"
    n="$(bash "$HERE/select-rules.sh" "$TMP/rules-src" "$TB/semgrep-rules")"
    [ "$n" -gt 0 ] || die "no semgrep rule files found in $rules"
    log "semgrep rules: $n rule files in $TB/semgrep-rules (Semgrep Rules License v1.0, see LICENSE there)"
  else
    warn "no semgrep rule pack in offline/legacy-toolbox/semgrep; pass --config <rules> to kit-semgrep"
  fi
  cat >"$TMP/kit-semgrep" <<'EOF'
#!/bin/sh
# work-kit 11-legacy-toolbox: semgrep scan with local rules, no telemetry, no network.
# Usage: kit-semgrep [semgrep scan options] PATH ...   (own --config replaces the local rules)
RULES="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/legacy-toolbox/semgrep-rules"
SEMGREP="$(dirname "$0")/semgrep"
[ -x "$SEMGREP" ] || SEMGREP=semgrep
export SEMGREP_SEND_METRICS=off SEMGREP_ENABLE_VERSION_CHECK=0
for a in "$@"; do
  case "$a" in --config|--config=*) exec "$SEMGREP" scan --metrics=off --disable-version-check "$@" ;; esac
done
[ -d "$RULES" ] || { echo "kit-semgrep: no local rules in $RULES; pass --config <rules>" >&2; exit 2; }
exec "$SEMGREP" scan --metrics=off --disable-version-check --config "$RULES" "$@"
EOF
  place_file "$TMP/kit-semgrep" "$BIN_DIR/kit-semgrep"
}

# --- kit-depgraph -----------------------------------------------------------------------
install_depgraph() {
  [ -f "$HERE/bin/kit-depgraph" ] || die "missing $HERE/bin/kit-depgraph"
  kit_find_python >/dev/null 2>&1 || warn "$(kit_python_hint); kit-depgraph needs it at run time"
  # The script lives in the data dir; the command in ~/.local/bin is a launcher that finds
  # python3 or the kit CPython when it runs (a python3 shebang fails without system python).
  place_file "$HERE/bin/kit-depgraph" "$TB/kit-depgraph.py"
  kit_write_py_launcher "$TMP/kit-depgraph" "$TB/kit-depgraph.py" kit-depgraph
  place_file "$TMP/kit-depgraph" "$BIN_DIR/kit-depgraph"
}

# --- run --------------------------------------------------------------------------------
ALL=(ctags scc tree-sitter semgrep depgraph)
if [ "$#" -gt 0 ]; then
  wanted=("$@")
  explicit=1
else
  wanted=("${ALL[@]}")
  explicit=0
fi
installed=()
skipped=()
for t in "${wanted[@]}"; do
  case "$t" in
    ctags|scc|semgrep|depgraph) fn="install_$t" ;;
    tree-sitter) fn="install_tree_sitter" ;;
    *) die "unknown tool: $t (choose from: ${ALL[*]})" ;;
  esac
  set +e
  ( set -e; "$fn" )
  rc=$?
  set -e
  case "$rc" in
    0) installed+=("$t") ;;
    3) skipped+=("$t") ;;
    *) die "$t failed (exit $rc)" ;;
  esac
done
log "installed: ${installed[*]:-none}; skipped: ${skipped[*]:-none}"
[ "$explicit" = 1 ] && [ "${#skipped[@]}" -gt 0 ] && exit 1

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) log "WARNING: $BIN_DIR is not on PATH (60-terminal adds it, or add it to ~/.profile)" ;;
esac
