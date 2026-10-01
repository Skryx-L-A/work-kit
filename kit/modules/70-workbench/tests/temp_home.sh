# shellcheck shell=bash
# Helpers for tests that install the workbench into a fresh temporary HOME. Source it.
#
# A test HOME drops the real ~/.local/bin from PATH, so nothing of an existing workbench is
# used. The prerequisites of the kit (00-python, 01-prereqs, 10-base-tools) also live under the
# real HOME, though; these helpers make them visible in the test HOME again:
#   wb_th_tools REAL_HOME SHIM_DIR    links git, jq, perl and code into SHIM_DIR when they
#                                     resolve to the real ~/.local/bin (wrappers with absolute
#                                     paths); call it while PATH is still the caller's
#   wb_th_python REAL_HOME NEW_HOME   makes the kit CPython of REAL_HOME (00-python via uv, or
#                                     the bootstrap copy of kit/install) visible to
#                                     kit_find_python in NEW_HOME by symlinks; without any, it
#                                     runs 00-python/install.sh into NEW_HOME when the kit
#                                     offline folder is present (uv and its links go to
#                                     NEW_HOME/.kit-python-bin, not ~/.local/bin). Prints the
#                                     python it found.

wb_th_tools() {
  local real="$1" shim="$2" t p
  mkdir -p "$shim"
  for t in git jq perl code; do
    p="$(type -P "$t" 2>/dev/null)" || continue
    case "$p" in "$real/.local/bin/"*) ln -sf "$p" "$shim/$t" ;; esac
  done
}

wb_th_python() {
  local real="$1" new="$2" here kit_lib uvdir boot py clean
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  kit_lib="$here/../../lib/kit-python/kit-python.sh"
  # shellcheck source=../../../lib/kit-python/kit-python.sh
  . "$kit_lib" || return 1
  # Looked up as the test HOME will see it: without the real ~/.local/bin (whose python3 may
  # be a 01-prereqs wrapper or the workbench's own link).
  clean="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vx "$real/.local/bin" | paste -sd: -)"
  if py="$(PATH="$clean" HOME="$new" kit_find_python)"; then printf '%s\n' "$py"; return 0; fi
  uvdir="$real/.local/share/uv/python"
  boot="${KIT_DATA_DIR:-$real/.local/share/work-kit}/bootstrap-python"
  if [ -z "${UV_PYTHON_INSTALL_DIR:-}" ] && [ -d "$uvdir" ] && [ ! -e "$new/.local/share/uv/python" ]; then
    mkdir -p "$new/.local/share/uv" && ln -s "$uvdir" "$new/.local/share/uv/python"
  fi
  if [ -d "$boot" ] && [ ! -e "$new/.local/share/work-kit/bootstrap-python" ]; then
    mkdir -p "$new/.local/share/work-kit" && ln -s "$boot" "$new/.local/share/work-kit/bootstrap-python"
  fi
  if py="$(PATH="$clean" HOME="$new" KIT_DATA_DIR= kit_find_python)"; then printf '%s\n' "$py"; return 0; fi
  if [ -f "$here/../00-python/install.sh" ] && [ -d "$here/../../offline/python" ]; then
    HOME="$new" KIT_DATA_DIR= KIT_TOOL_DIR= KIT_BIN_DIR="$new/.kit-python-bin" \
      UV_PYTHON_BIN_DIR="$new/.kit-python-bin" bash "$here/../00-python/install.sh" >"$new/00-python.log" 2>&1 || true
    if py="$(PATH="$clean" HOME="$new" KIT_DATA_DIR= kit_find_python)"; then printf '%s\n' "$py"; return 0; fi
  fi
  return 1
}
