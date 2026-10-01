#!/usr/bin/env bash
# Compare models on the same cases. Local models are started one after another with kit-llm
# (15-local-llm); other candidates are providers defined in the suite (for example a cloud model).
#
# Usage: run.sh [--models ID[,ID]] [--providers ID[,ID]] [-n N] [--cases ID[,ID]]
#               [--suite FILE] [--out DIR]
#   --models     kit-llm catalog ids (kit-llm models); each is started, measured, stopped
#   --providers  provider ids from the suite (default when neither is given: every default provider)
#   -n           repetitions per case (default 3)
# Output: one evalkit JSON per candidate plus comparison.md in --out (default under evalkit's data dir).
# Environment: EVALKIT (evalkit command), KIT_LLM (kit-llm command).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/../lib/common.sh"

MODELS="" PROVIDERS="" REPS=3 CASES="" SUITE="$HERE/suite.yaml" OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --models) MODELS="${2:?}"; shift ;;
    --providers) PROVIDERS="${2:?}"; shift ;;
    -n) REPS="${2:?}"; shift ;;
    --cases) CASES="${2:?}"; shift ;;
    --suite) SUITE="${2:?}"; shift ;;
    --out) OUT="${2:?}"; shift ;;
    -h|--help) awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) pack_die "unknown option: $1" ;;
  esac
  shift
done
OUT="$(pack_out_dir "$OUT" models)"
PY="$(pack_python)"
KIT_LLM="${KIT_LLM:-kit-llm}"
case_args=()
for c in ${CASES//,/ }; do case_args+=(-c "$c"); done

STARTED=""
# shellcheck disable=SC2329  # used by trap
cleanup() { [ -n "$STARTED" ] && $KIT_LLM stop >/dev/null 2>&1; true; }
trap cleanup EXIT

if [ -n "$MODELS" ]; then
  command -v "${KIT_LLM%% *}" >/dev/null 2>&1 || pack_die "kit-llm not found (install 15-local-llm or set KIT_LLM)"
  $KIT_LLM status >/dev/null 2>&1 && pack_die "a kit-llm server is already running; stop it first (kit-llm stop)"
  for m in ${MODELS//,/ }; do
    pack_log "model $m: start"
    if ! $KIT_LLM start "$m" >&2; then pack_log "model $m: could not start, skipped"; continue; fi
    STARTED=1
    url="$($KIT_LLM env | sed -n 's/^export KIT_LLM_BASE_URL=//p')"
    KIT_LLM_BASE_URL="$url" EVAL_MODEL="$m" pack_evalkit run "$SUITE" -p local -n "$REPS" \
      ${case_args[@]+"${case_args[@]}"} --out "$OUT/$m.json" --no-save -q
    $KIT_LLM stop >&2; STARTED=""
  done
fi
if [ -n "$PROVIDERS" ] || [ -z "$MODELS" ]; then
  if [ -n "$PROVIDERS" ]; then ids="${PROVIDERS//,/ }"; else ids=""; fi
  if [ -z "$ids" ]; then
    pack_evalkit run "$SUITE" -n "$REPS" ${case_args[@]+"${case_args[@]}"} --out "$OUT/default.json" --no-save -q
  else
    for p in $ids; do
      pack_log "provider $p"
      pack_evalkit run "$SUITE" -p "$p" -n "$REPS" ${case_args[@]+"${case_args[@]}"} --out "$OUT/$p.json" --no-save -q
    done
  fi
fi
"$PY" "$HERE/../lib/compare.py" --title "Model comparison" --md "$OUT/comparison.md" "$OUT"
pack_log "results: $OUT"
