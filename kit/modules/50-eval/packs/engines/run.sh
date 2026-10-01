#!/usr/bin/env bash
# Compare inference engines with the same model: throughput/latency (bench.py) and quality
# (deterministic cases of the model pack) for every engine in the config, one after another.
#
# Usage: run.sh [--config FILE] [--engines ID[,ID]] [--requests N] [--concurrency C]
#               [--max-tokens M] [-n N] [--quality-cases ID[,ID]|none] [--out DIR]
# Default config: engines.conf next to this script (copy engines.conf.example).
# Output: <id>.bench.json + <id>.json (evalkit) per engine and comparison.md in --out.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$HERE/../lib/common.sh"

CONF="$HERE/engines.conf" ONLY="" REQS=6 CONC=1 MAXTOK=128 REPS=1 OUT=""
QCASES="de-invoice-json,en-ticket-classify,de-math,en-code-explain,en-sql,de-grounded-unknown"
while [ $# -gt 0 ]; do
  case "$1" in
    --config) CONF="${2:?}"; shift ;;
    --engines) ONLY="${2:?}"; shift ;;
    --requests) REQS="${2:?}"; shift ;;
    --concurrency) CONC="${2:?}"; shift ;;
    --max-tokens) MAXTOK="${2:?}"; shift ;;
    -n) REPS="${2:?}"; shift ;;
    --quality-cases) QCASES="${2:?}"; shift ;;
    --out) OUT="${2:?}"; shift ;;
    -h|--help) awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) pack_die "unknown option: $1" ;;
  esac
  shift
done
[ -f "$CONF" ] || pack_die "no engine config $CONF (cp engines.conf.example engines.conf and edit)"
OUT="$(pack_out_dir "$OUT" engines)"
PY="$(pack_python)"
STOP_CMD=""
# shellcheck disable=SC2329  # used by trap
cleanup() { if [ -n "$STOP_CMD" ]; then sh -c "$STOP_CMD" >/dev/null 2>&1 || true; fi; }
trap cleanup EXIT

qargs=()
[ "$QCASES" = none ] || for c in ${QCASES//,/ }; do qargs+=(-c "$c"); done

while IFS='|' read -r id url model start stop; do
  id="$(echo "$id" | xargs)"
  case "$id" in ''|'#'*) continue ;; esac
  if [ -n "$ONLY" ]; then case ",$ONLY," in *",$id,"*) ;; *) continue ;; esac; fi
  url="$(echo "$url" | xargs)"; model="$(echo "$model" | xargs)"
  start="$(echo "$start" | sed 's/^ *//; s/ *$//')"; stop="$(echo "$stop" | sed 's/^ *//; s/ *$//')"
  pack_log "engine $id: $url ($model)"
  if [ -n "$start" ] && [ "$start" != "-" ]; then
    if ! sh -c "$start" >&2 </dev/null; then pack_log "engine $id: start failed, skipped"; continue; fi
    [ "$stop" != "-" ] && STOP_CMD="$stop"
  fi
  if ! pack_wait_http "$url/models" 180 </dev/null; then
    pack_log "engine $id: $url/models not reachable, skipped"
  else
    "$PY" "$HERE/bench.py" --base-url "$url" --model "$model" --label "$id" --requests "$REQS" \
      --concurrency "$CONC" --max-tokens "$MAXTOK" --out "$OUT/$id.bench.json" </dev/null || pack_log "engine $id: bench had errors"
    if [ "${#qargs[@]}" -gt 0 ]; then
      KIT_LLM_BASE_URL="$url" EVAL_MODEL="$model" pack_evalkit run "$HERE/../models/suite.yaml" -p local \
        -n "$REPS" "${qargs[@]}" --out "$OUT/$id.json" --no-save -q >/dev/null </dev/null
    fi
  fi
  if [ -n "$STOP_CMD" ]; then sh -c "$STOP_CMD" >&2 </dev/null || true; STOP_CMD=""; fi
done <"$CONF"
"$PY" "$HERE/../lib/compare.py" --title "Engine comparison" --md "$OUT/comparison.md" "$OUT"
pack_log "results: $OUT"
