#!/usr/bin/env bash
# Shared helpers for kit modules that need Python. Source this file, do not execute it:
#   source "<kit>/modules/00-python/lib.sh"
# Does not change shell options. Every function returns non-zero on failure.

KIT_PY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$KIT_PY_LIB_DIR/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
KIT_BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
KIT_DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
# Kit tools live in their own directory so `uv tool` state of the user is untouched.
KIT_TOOL_DIR="${KIT_TOOL_DIR:-$KIT_DATA_DIR/tools}"
KIT_PYTHON_VERSION="${KIT_PYTHON_VERSION:-3.12}"

kit_log() { printf '[kit] %s\n' "$*"; }
kit_warn() { printf '[kit] WARNING: %s\n' "$*" >&2; }
kit_die() { printf '[kit] ERROR: %s\n' "$*" >&2; return 1; }

# kit_backup <file> [module]: move an existing file aside into
# $KIT_DATA_DIR/backups/<module>/<name>.bak-<timestamp>. The original path is recorded in
# <name>.bak-<timestamp>.origin next to it. Nothing is written beside the original.
kit_backup() {
  local f="$1" mod="${2:-00-python}" dir b n=0
  [ -e "$f" ] || [ -L "$f" ] || return 0
  dir="$KIT_DATA_DIR/backups/$mod"
  mkdir -p "$dir" || return 1
  b="$dir/$(basename "$f").bak-$(date +%Y%m%d%H%M%S)"
  while [ -e "$b" ] || [ -L "$b" ]; do
    n=$((n + 1)); b="$dir/$(basename "$f").bak-$(date +%Y%m%d%H%M%S)-$n"
  done
  mv "$f" "$b" || return 1
  printf '%s\n' "$f" >"$b.origin"
  kit_log "backup: $f -> $b"
}

# kit_uv: run the uv that the kit installed, else the one on PATH. uv creates the .lock files
# in venvs and tool dirs with mode 0666 whatever the umask (measured with uv 0.11), so every call
# is followed by kit_fix_lock_perms, also when uv failed. umask 022 covers the other files uv writes.
kit_uv() {
  local rc=0
  if [ -x "$KIT_BIN_DIR/uv" ]; then ( umask 022; "$KIT_BIN_DIR/uv" "$@" ) || rc=$?
  else ( umask 022; uv "$@" ) || rc=$?; fi
  kit_fix_lock_perms
  return "$rc"
}

# kit_fix_lock_perms: drop group/other write from uv .lock files under the kit data dir
# (venvs, tool dirs). Shallow search: the locks sit at the top of a venv or tool dir.
kit_fix_lock_perms() {
  [ -d "$KIT_DATA_DIR" ] || return 0
  find "$KIT_DATA_DIR" -maxdepth 5 -name .lock -type f \( -perm -020 -o -perm -002 \) \
    -exec chmod go-w {} + 2>/dev/null || true
}

kit_require_uv() {
  if [ -x "$KIT_BIN_DIR/uv" ] || command -v uv >/dev/null 2>&1; then return 0; fi
  kit_die "uv not found. Run kit/modules/00-python/install.sh first."
}

# kit_pkg_name <pkgdir>: print the [project] name of <pkgdir>/pyproject.toml.
kit_pkg_name() {
  local toml="$1/pyproject.toml"
  [ -f "$toml" ] || { kit_die "no pyproject.toml in $1"; return 1; }
  awk '
    /^\[/ { in_project = ($0 == "[project]"); next }
    in_project && /^name[ \t]*=/ {
      s = $0; sub(/^name[ \t]*=[ \t]*["'\'']/, "", s); sub(/["'\''].*$/, "", s); print s; exit
    }' "$toml"
}

# kit_uv_tool_install <pkgdir>: install the Python CLI defined by <pkgdir>/pyproject.toml
# from $KIT_OFFLINE/wheels (no network). Entry points land in $KIT_BIN_DIR. The kit's own package
# is always reinstalled: a new stick keeps the version number but changes the code.
kit_uv_tool_install() {
  local pkgdir="${1:?usage: kit_uv_tool_install <pkgdir>}" name
  kit_require_uv || return 1
  name="$(kit_pkg_name "$pkgdir")" || return 1
  [ -n "$name" ] || { kit_die "cannot read project name from $pkgdir/pyproject.toml"; return 1; }
  [ -d "$KIT_OFFLINE/wheels" ] || { kit_die "missing $KIT_OFFLINE/wheels (offline wheel cache)"; return 1; }
  mkdir -p "$KIT_TOOL_DIR" "$KIT_BIN_DIR"
  UV_TOOL_DIR="$KIT_TOOL_DIR" UV_TOOL_BIN_DIR="$KIT_BIN_DIR" UV_PYTHON_DOWNLOADS=never \
    kit_uv tool install --force --reinstall-package "$name" --offline --no-index \
      --find-links "$KIT_OFFLINE/wheels" --python "$KIT_PYTHON_VERSION" "$name" \
    && kit_log "installed tool: $name"
}

# kit_uv_tool_uninstall <name>: remove a tool installed with kit_uv_tool_install.
kit_uv_tool_uninstall() {
  local name="${1:?usage: kit_uv_tool_uninstall <name>}"
  kit_require_uv || return 1
  UV_TOOL_DIR="$KIT_TOOL_DIR" UV_TOOL_BIN_DIR="$KIT_BIN_DIR" \
    kit_uv tool uninstall "$name" 2>/dev/null && kit_log "removed tool: $name" || true
}
