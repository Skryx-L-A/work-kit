#!/usr/bin/env bash
# Compare CLI harnesses on the same tasks, each run in a fresh temp git repo.
#
# Usage: run.sh --harnesses ID[,ID] [-n N] [--tasks ID[,ID]] [--out DIR] [--keep]
#   ids come from harnesses.conf (copy harnesses.conf.example); fake-good / fake-noop test the pack.
#   --keep leaves every temp repo for inspection (paths in the JSON output).
# Output: one evalkit JSON per harness plus comparison.md in --out.
# Each harness uses its own login, model and data destination: check the data classes before
# running a cloud harness, even on these synthetic tasks.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/../lib/common.sh"

HARN="" REPS=1 TASKS="" OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --harnesses) HARN="${2:?}"; shift ;;
    -n) REPS="${2:?}"; shift ;;
    --tasks) TASKS="${2:?}"; shift ;;
    --out) OUT="${2:?}"; shift ;;
    --keep) export HARNESS_KEEP=1 ;;
    -h|--help) awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) pack_die "unknown option: $1" ;;
  esac
  shift
done
[ -n "$HARN" ] || pack_die "give --harnesses (ids from harnesses.conf)"
command -v git >/dev/null 2>&1 || pack_die "git is required"
OUT="$(pack_out_dir "$OUT" harnesses)"
PY="$(pack_python)"
targs=()
for t in ${TASKS//,/ }; do targs+=(-c "$t"); done
for h in ${HARN//,/ }; do
  pack_log "harness $h"
  pack_evalkit run "$HERE/suite.yaml" -p "$h" -n "$REPS" ${targs[@]+"${targs[@]}"} --out "$OUT/$h.json" --no-save -q >/dev/null
done
"$PY" "$HERE/../lib/compare.py" --title "Harness comparison" --md "$OUT/comparison.md" "$OUT"
pack_log "results: $OUT"
