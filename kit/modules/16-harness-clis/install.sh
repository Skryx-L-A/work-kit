#!/usr/bin/env bash
# Install harness CLIs from kit/offline/harness-clis into $HOME. No network, no sudo.
# Usage: install.sh [--list] [--ask] [harness ...]
#   no argument   the default set (all seven, or $KIT_HARNESS_CLIS, or edit HC_DEFAULT in common.sh)
#   harness       any of: claude codex opencode copilot gemini pi aider   ("all" = every one)
#   --ask         ask yes/no per harness (needs a terminal)
#   --list        pinned version, offline files and installed version of every harness
# Each harness lands in ~/.local/share/work-kit/harness-clis/<name>/<version>/ with a `current`
# link; the command in ~/.local/bin is a link (a launcher script for gemini and pi). A foreign file with the same
# name is moved to ~/.local/share/work-kit/backups/16-harness-clis/<name>.bak-<timestamp>
# (original path recorded in <name>.bak-<timestamp>.origin). Re-running is safe.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"

usage() { sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

LIST=0
ASK=0
WANT=""
for a in "$@"; do
  case "$a" in
    --list) LIST=1 ;;
    --ask) ASK=1 ;;
    -h|--help) usage; exit 0 ;;
    all) WANT="$WANT $HC_ALL" ;;
    -*) hc_die "unknown option: $a" ;;
    *) hc_known "$a" || hc_die "unknown harness: $a (known: $HC_ALL)"; WANT="$WANT $a" ;;
  esac
done

installed_version() { hc_state_version "$1"; }

do_list() {
  local h rel have inst
  printf '%-9s %-9s %-8s %s\n' harness pinned offline installed
  for h in $HC_ALL; do
    if [ "$h" = aider ]; then
      have="no"; [ -d "$HC_OFF/aider/wheels" ] && have="yes"
    else
      rel="$(hc_artifact "$h")"; have="no"; [ -n "$rel" ] && [ -f "$HC_OFF/$rel" ] && have="yes"
    fi
    inst="$(installed_version "$h")"
    printf '%-9s %-9s %-8s %s\n' "$h" "$(hc_version "$h")" "$have" "${inst:--}"
  done
}
[ "$LIST" = 1 ] && { do_list; exit 0; }

if [ "${HC_SKIP_PLATFORM_CHECK:-0}" != 1 ]; then
  case "$(uname -s)/$(uname -m)" in
    Linux/x86_64) ;;
    *) hc_die "unsupported platform $(uname -s)/$(uname -m) (the builds in offline/harness-clis are Linux x86_64)" ;;
  esac
fi

# --- helpers ----------------------------------------------------------------------------------
smoke() { # harness: the installed command starts and prints a version
  local cmd="$KIT_BIN_DIR/$1" out rc=0 t=""
  [ "${HC_SKIP_SMOKE:-0}" = 1 ] && return 0
  command -v timeout >/dev/null 2>&1 && t="timeout 180"
  # shellcheck disable=SC2086  # $t is empty or "timeout 180"
  out="$($t "$cmd" --version 2>&1)" || rc=$?
  # The first start of a Python harness compiles its packages; a slow CPU can pass 180 s once.
  if [ "$rc" = 124 ]; then
    hc_log "$1: first start took over 180 s, trying once more (up to 600 s)"
    rc=0; out="$(timeout 600 "$cmd" --version 2>&1)" || rc=$?
  fi
  out="${out%%$'\n'*}"
  if [ "$rc" != 0 ] || [ -z "$out" ]; then
    hc_warn "$1: '$cmd --version' failed (exit $rc) ${out:+: $out}"
    return 1
  fi
  hc_log "$1: $out"
}

# activate <harness> <version>: point `current` at the version and drop the other versions
activate() {
  local h="$1" v="$2" d
  ln -sfn "$v" "$HC_DATA/$h/current"
  for d in "$HC_DATA/$h"/*; do
    [ -d "$d" ] && [ ! -L "$d" ] && [ "$(basename "$d")" != "$v" ] && rm -rf "$d"
  done
  return 0
}

# place_tree <harness> <version> <staging-dir>: move a prepared tree to <harness>/<version>
place_tree() {
  local h="$1" v="$2" stage="$3"
  rm -rf "${HC_DATA:?}/$h/$v"
  mv "$stage" "$HC_DATA/$h/$v"
}

stage_for() { # harness -> fresh staging dir (printed)
  local s="$HC_DATA/$1/.stage.$$"
  rm -rf "$s" && mkdir -p "$s" && echo "$s"
}

up_to_date() { # harness version link-target-relative-to-current
  local h="$1" v="$2" rel="$3"
  [ "$(hc_state_version "$h")" = "$v" ] || return 1
  [ -L "$HC_DATA/$h/current" ] && [ "$(readlink "$HC_DATA/$h/current")" = "$v" ] || return 1
  [ -x "$HC_DATA/$h/current/$rel" ] || return 1
  [ -L "$KIT_BIN_DIR/$h" ] && [ "$(readlink "$KIT_BIN_DIR/$h")" = "$HC_DATA/$h/current/$rel" ] || return 1
}

finish() { # harness version relpath: link the command, record state, smoke test
  local h="$1" v="$2" rel="$3"
  activate "$h" "$v"
  hc_link "$h" "$HC_DATA/$h/current/$rel"
  smoke "$h" || return 1
  hc_state_set "$h" "$v"
}

# Runtimes that another kit module provides. They are installed from their own offline sources
# when missing, so a single harness works without running the whole menu first.
# Node.js minimum: "20" (Gemini CLI) or "22.19" (pi), as major or major.minor.
node_ok() { # node-binary minimum
  "$1" -e 'const [a, b] = process.versions.node.split(".").map(Number), [x, y = 0] = process.argv[1].split(".").map(Number); process.exit(a > x || (a === x && b >= y) ? 0 : 1)' "$2" >/dev/null 2>&1
}
find_node() { # minimum
  local c
  for c in "$(command -v node 2>/dev/null || true)" "$KIT_DATA_DIR/prereqs/node/bin/node"; do
    [ -n "$c" ] && [ -x "$c" ] && node_ok "$c" "$1" && { echo "$c"; return 0; }
  done
  return 1
}
ensure_node() { # minimum
  find_node "$1" >/dev/null && return 0
  if [ -f "$HERE/../01-prereqs/install.sh" ]; then
    hc_log "Node.js $1+ not found: installing it with 01-prereqs"
    KIT_BIN_DIR="$KIT_BIN_DIR" KIT_DATA_DIR="$KIT_DATA_DIR" KIT_OFFLINE="$KIT_OFFLINE" bash "$HERE/../01-prereqs/install.sh" node || true
  fi
  find_node "$1" >/dev/null || hc_die "Node.js $1+ not found (01-prereqs/install.sh node installs it, or install nodejs $1+)"
}

find_uv() {
  if [ -x "$KIT_BIN_DIR/uv" ]; then echo "$KIT_BIN_DIR/uv"; elif command -v uv >/dev/null 2>&1; then command -v uv; else return 1; fi
}
find_python312() {
  local uv
  uv="$(find_uv)" || return 1
  UV_PYTHON_DOWNLOADS=never "$uv" python find --no-config "$AIDER_PYTHON" 2>/dev/null
}
ensure_python() {
  find_python312 >/dev/null && return 0
  if [ -f "$HERE/../00-python/install.sh" ]; then
    hc_log "uv and CPython $AIDER_PYTHON not found: installing them with 00-python"
    KIT_BIN_DIR="$KIT_BIN_DIR" KIT_DATA_DIR="$KIT_DATA_DIR" KIT_OFFLINE="$KIT_OFFLINE" bash "$HERE/../00-python/install.sh" || true
  fi
  find_python312 >/dev/null || hc_die "CPython $AIDER_PYTHON via uv not found (run 00-python/install.sh)"
}

# --- installers (each runs in a subshell; a failure only fails that harness) --------------------
need_artifact() { # harness -> path (verified)
  local rel
  rel="$(hc_artifact "$1")"
  [ -n "$rel" ] || hc_die "$1 is not in lock/artifacts.lock"
  hc_verify "$rel" || hc_die "$1: offline artifact missing or damaged"
  echo "$rel"
}

install_claude() {
  local v="$CLAUDE_VERSION" rel stage
  up_to_date claude "$v" claude && { hc_log "claude $v up to date"; return 0; }
  rel="$(need_artifact claude)"
  mkdir -p "$HC_DATA/claude"; stage="$(stage_for claude)"
  install -m 0755 "$HC_OFF/$rel" "$stage/claude"
  place_tree claude "$v" "$stage"
  finish claude "$v" claude
}

install_tarball() { # harness relpath-of-command tar-flags
  local h="$1" cmdrel="$2" v rel stage
  v="$(hc_version "$h")"
  up_to_date "$h" "$v" "$cmdrel" && { hc_log "$h $v up to date"; return 0; }
  rel="$(need_artifact "$h")"
  mkdir -p "$HC_DATA/$h"; stage="$(stage_for "$h")"
  tar -xzf "$HC_OFF/$rel" -C "$stage"
  [ -f "$stage/$cmdrel" ] || hc_die "$h: $cmdrel not found in $rel"
  chmod 0755 "$stage/$cmdrel"
  place_tree "$h" "$v" "$stage"
  finish "$h" "$v" "$cmdrel"
}

install_codex() {
  local v="$CODEX_VERSION" rel stage f
  up_to_date codex "$v" bin/codex && { hc_log "codex $v up to date"; return 0; }
  rel="$(need_artifact codex)"
  mkdir -p "$HC_DATA/codex"; stage="$(stage_for codex)"
  tar -xzf "$HC_OFF/$rel" -C "$stage"
  [ -f "$stage/bin/codex" ] || hc_die "codex: bin/codex not found in $rel"
  for f in bin/codex bin/codex-code-mode-host codex-path/rg codex-resources/bwrap; do
    [ -f "$stage/$f" ] && chmod 0755 "$stage/$f"
  done
  place_tree codex "$v" "$stage"
  finish codex "$v" bin/codex
}

node_launcher() { # harness entry-js min-node: launcher script running the entry with the first Node.js that is new enough
  local h="$1" js="$2" min="$3" dst="$KIT_BIN_DIR/$1" tmp envline=""
  # pi checks pi.dev for a newer version at every start; only this variable switches that off
  # (the pinned kit version is never self-updated). A value set by the user wins.
  [ "$h" = pi ] && envline='export PI_SKIP_VERSION_CHECK="${PI_SKIP_VERSION_CHECK:-1}"'
  tmp="$(mktemp "$KIT_BIN_DIR/.$h.XXXXXX")"
  cat >"$tmp" <<E
#!/usr/bin/env bash
# $HC_MARK: runs the pinned $h with Node.js $min or newer
$envline
for n in "\$(command -v node 2>/dev/null)" "$KIT_DATA_DIR/prereqs/node/bin/node"; do
  if [ -x "\$n" ] && "\$n" -e 'const [a, b] = process.versions.node.split(".").map(Number), [x, y = 0] = "$min".split(".").map(Number); process.exit(a > x || (a === x && b >= y) ? 0 : 1)' 2>/dev/null; then
    exec "\$n" "$HC_DATA/$h/current/$js" "\$@"
  fi
done
echo "$h: Node.js $min+ not found (run 01-prereqs/install.sh node)" >&2
exit 1
E
  chmod 0755 "$tmp"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if hc_ours "$dst"; then rm -f "$dst"
    else hc_backup "$dst"; fi
  fi
  mv "$tmp" "$dst"
}

# install_node_tree <harness> <entry-js> <min-node>: a locked node_modules tree (tar) plus a launcher
install_node_tree() {
  local h="$1" js="$2" min="$3" v rel stage
  v="$(hc_version "$h")"
  if [ "$(hc_state_version "$h")" = "$v" ] && [ -f "$HC_DATA/$h/current/$js" ] && hc_ours "$KIT_BIN_DIR/$h" \
     && [ "$(readlink "$HC_DATA/$h/current")" = "$v" ]; then
    hc_log "$h $v up to date"; return 0
  fi
  ensure_node "$min"
  rel="$(need_artifact "$h")"
  mkdir -p "$HC_DATA/$h" "$KIT_BIN_DIR"; stage="$(stage_for "$h")"
  tar -xf "$HC_OFF/$rel" -C "$stage"
  [ -f "$stage/$js" ] || hc_die "$h: $js not found in $rel"
  place_tree "$h" "$v" "$stage"
  activate "$h" "$v"
  node_launcher "$h" "$js" "$min"
  smoke "$h" || return 1
  hc_state_set "$h" "$v"
}

install_gemini() { install_node_tree gemini node_modules/@google/gemini-cli/bundle/gemini.js "$NODE_MIN_MAJOR"; }
install_pi() { install_node_tree pi node_modules/@earendil-works/pi-coding-agent/dist/cli.js "$PI_NODE_MIN"; }

install_aider() {
  local v="$AIDER_VERSION" uv py dir="$HC_DATA/aider/$AIDER_VERSION"
  up_to_date aider "$v" venv/bin/aider && { hc_log "aider $v up to date"; return 0; }
  [ -d "$HC_OFF/aider/wheels" ] || hc_die "aider: $HC_OFF/aider/wheels is missing"
  [ -f "$HC_LOCKDIR/aider-requirements.txt" ] || hc_die "aider: lock/aider-requirements.txt is missing"
  ensure_python
  uv="$(find_uv)"; py="$(find_python312)"
  command -v git >/dev/null 2>&1 || hc_warn "git not found: aider needs it at run time (01-prereqs/install.sh git)"
  mkdir -p "$HC_DATA/aider"
  rm -rf "$dir"
  # the venv is built in place: its scripts contain absolute paths
  if ! "$uv" venv --no-config --python "$py" "$dir/venv" >/dev/null \
     || ! UV_PYTHON_DOWNLOADS=never "$uv" pip install --no-config --offline --no-index --require-hashes \
          --find-links "$HC_OFF/aider/wheels" --python "$dir/venv/bin/python" -r "$HC_LOCKDIR/aider-requirements.txt"; then
    rm -rf "$dir"
    hc_die "aider: offline install failed (wheel set incomplete for CPython $AIDER_PYTHON?)"
  fi
  finish aider "$v" venv/bin/aider
}

install_one() {
  case "$1" in
    claude) install_claude ;;
    codex) install_codex ;;
    opencode) install_tarball opencode opencode ;;
    copilot) install_tarball copilot copilot ;;
    gemini) install_gemini ;;
    pi) install_pi ;;
    aider) install_aider ;;
  esac
}

# --- main -------------------------------------------------------------------------------------
if [ -z "$WANT" ]; then
  if [ "$ASK" = 1 ]; then
    for h in $HC_DEFAULT; do
      printf 'Install %s %s? [y/N] ' "$h" "$(hc_version "$h")"
      read -r ans || ans=""
      case "$ans" in y|Y|yes) WANT="$WANT $h" ;; esac
    done
  else
    WANT="$HC_DEFAULT"
  fi
fi
WANT="$(printf '%s\n' "$WANT" | tr -s ' ' '\n' | awk 'NF && !seen[$0]++' | tr '\n' ' ')"
[ -n "${WANT// /}" ] || { hc_log "nothing selected"; exit 0; }
for h in $WANT; do hc_known "$h" || hc_die "unknown harness: $h (known: $HC_ALL)"; done

mkdir -p "$HC_DATA" "$KIT_BIN_DIR"
trap 'rm -rf "$HC_DATA"/*/.stage.$$' EXIT
failed=""
for h in $WANT; do
  hc_log "$h $(hc_version "$h")"
  # errexit stays in force inside the subshell only when it is not run as an `if` condition
  rc=0
  set +e
  ( set -e; install_one "$h" )
  rc=$?
  set -e
  if [ "$rc" != 0 ]; then failed="$failed $h"; hc_warn "$h failed"; fi
done

case ":$PATH:" in
  *":$KIT_BIN_DIR:"*) ;;
  *) hc_warn "$KIT_BIN_DIR is not on PATH (60-terminal adds it, or add it to ~/.profile)" ;;
esac
[ -z "$failed" ] || { echo "[harness-clis] ERROR: failed:$failed" >&2; exit 1; }
hc_log "done: $WANT"
