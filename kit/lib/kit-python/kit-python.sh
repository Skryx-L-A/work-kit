# shellcheck shell=bash
# Shared python lookup for kit scripts. Source it; it changes nothing else.
#   kit_find_python            print a python3 >= 3.8: system python3 first, then the CPython
#                              installed by 00-python (uv), then the bootstrap copy that
#                              kit/install unpacks. Exit 1 when none runs.
#   kit_python_hint            the message that tells the user how to get python3
#   kit_write_py_launcher DEST SCRIPT [NAME]
#                              write a self-contained bash launcher DEST that runs the python
#                              script SCRIPT (a python shebang would fail on a laptop without
#                              python3). The interpreter found at write time is recorded in
#                              the launcher and used while it exists; only when it is gone
#                              does the launcher run the kit_find_python lookup (which starts
#                              python once more to check its version).
#   kit_is_py_launcher FILE    true when FILE was written by kit_write_py_launcher
# Same lookup order as kit/install.

kit_python_ok() { "$1" -c 'import sys; sys.exit(sys.version_info < (3, 8))' >/dev/null 2>&1; }

kit_find_python() {
  local c
  if c="$(command -v python3 2>/dev/null)" && kit_python_ok "$c"; then
    printf '%s\n' "$c"
    return 0
  fi
  for c in "${UV_PYTHON_INSTALL_DIR:-$HOME/.local/share/uv/python}"/cpython-3.12*/bin/python3 \
           "${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"/bootstrap-python/python/bin/python3; do
    if [ -x "$c" ] && kit_python_ok "$c"; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

kit_python_hint() {
  echo "python3 (3.8 or newer) not found: run 01-prereqs/install.sh python3 (or --sudo python3), or 00-python/install.sh"
}

kit_write_py_launcher() {
  local dest="$1" script="$2" name="${3:-$(basename "$1")}" found
  found="$(kit_find_python 2>/dev/null || true)"
  {
    echo '#!/usr/bin/env bash'
    echo '# work-kit launcher: runs a python script with python3 or the kit CPython.'
    if [ -n "$found" ]; then
      # shellcheck disable=SC2016
      printf 'PY=%q
[ -x "$PY" ] && exec "$PY" %q "$@"
' "$found" "$script"
    fi
    declare -f kit_python_ok kit_find_python
    # shellcheck disable=SC2016  # the launcher text must keep $PY and $@ unexpanded
    printf 'PY="$(kit_find_python)" || { echo %q >&2; exit 1; }\n' \
      "$name: python3 (3.8 or newer) not found; run 01-prereqs/install.sh python3, or 00-python/install.sh"
    # shellcheck disable=SC2016
    printf 'exec "$PY" %q "$@"\n' "$script"
  } >"$dest"
  chmod 0755 "$dest"
}

kit_is_py_launcher() { grep -qm1 '^# work-kit launcher: runs a python script' "$1" 2>/dev/null; }
