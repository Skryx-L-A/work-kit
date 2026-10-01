# shellcheck shell=bash
# Shared helpers for the pack runners. Source it; do not execute.
# EVALKIT: command that runs evalkit (default "evalkit"; e.g. "uv run --project <50-eval> evalkit").

pack_log() { printf '[pack] %s\n' "$*" >&2; }
pack_die() { printf '[pack] ERROR: %s\n' "$*" >&2; exit 1; }

# pack_evalkit ARGS...: run evalkit; exit code 2 (invalid suite/usage) aborts the runner.
pack_evalkit() {
  local cmd rc=0
  read -r -a cmd <<<"${EVALKIT:-evalkit}"
  command -v "${cmd[0]}" >/dev/null 2>&1 || pack_die "evalkit not found (install 50-eval or set EVALKIT)"
  "${cmd[@]}" "$@" || rc=$?
  [ "$rc" = 2 ] && pack_die "evalkit rejected the suite or options"
  return 0
}

# pack_python: a Python 3 for the helper scripts.
pack_python() {
  local py
  for py in python3 python; do command -v "$py" >/dev/null 2>&1 && { echo "$py"; return; }; done
  pack_die "python3 not found"
}

# pack_wait_http URL SECONDS: wait until URL answers with HTTP 2xx.
pack_wait_http() {
  local url="$1" t="${2:-120}" i=0
  while [ "$i" -lt "$t" ]; do
    curl -fsS --max-time 3 "$url" >/dev/null 2>&1 && return 0
    sleep 1; i=$((i + 1))
  done
  return 1
}

# pack_out_dir DIR|"" NAME: create and print the output directory.
pack_out_dir() {
  local d="${1:-${EVALKIT_HOME:-${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/evalkit}/packs/$2-$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$d" && echo "$d"
}
