#!/usr/bin/env bash
# work-kit data-guard hook
# Installed as a git hook by `data-guard install-hook` or `data-guard enable-global`.
# pre-commit: run data-guard on the staged changes. Every hook name: run the hook that
# was there before (repo hook when installed globally, <hook>.work-kit-chained per repo).
name="$(basename "$0")"
DG="${DATA_GUARD_BIN:-${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/data-guard/data-guard}"

if [ "$name" = "pre-commit" ]; then
  if [ -x "$DG" ]; then
    "$DG" staged || exit $?
  elif [ "${DATA_GUARD_ALLOW_UNSCANNED:-0}" = 1 ]; then
    echo "data-guard: WARNING: $DG not found, commit is not checked (DATA_GUARD_ALLOW_UNSCANNED=1)" >&2
  else
    echo "data-guard: BLOCKED: $DG not found, so the commit cannot be checked (install module 40-data-guard again)." >&2
    echo "data-guard: For this one commit only: DATA_GUARD_ALLOW_UNSCANNED=1 git commit ..." >&2
    exit 1
  fi
fi

chain="$0.work-kit-chained"
if [ ! -x "$chain" ]; then
  common="$(git rev-parse --git-common-dir 2>/dev/null)" || common=""
  chain="$common/hooks/$name"
fi
if [ -x "$chain" ] && [ ! "$chain" -ef "$0" ] && ! grep -q "work-kit data-guard hook" "$chain" 2>/dev/null; then
  exec "$chain" "$@"
fi
exit 0
