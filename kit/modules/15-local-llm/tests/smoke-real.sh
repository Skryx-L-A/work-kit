#!/usr/bin/env bash
# Real engine + real model in a scratch HOME: install from kit/offline, start, one German and one
# English request, check the answers, stop. Needs the fetched artifacts (fetch.sh; on a Mac
# add --dev-mac). Usage: tests/smoke-real.sh [MODEL_ID]   (default qwen3.5-2b)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/.." && pwd)"
MODEL="${1:-qwen3.5-2b}"
W="$(mktemp -d)"
# shellcheck disable=SC2329  # used by trap
cleanup() { "$W/home/.local/bin/kit-llm" stop >/dev/null 2>&1 || true; rm -rf "$W"; }
trap cleanup EXIT
export HOME="$W/home" KIT_BIN_DIR="$W/home/.local/bin" KIT_DATA_DIR="$W/home/.local/share/work-kit"
export XDG_CONFIG_HOME="$W/home/.config"
export KIT_OFFLINE="${KIT_OFFLINE:-$(cd "$MOD/../.." && pwd)/offline}"
export KIT_LLM_PORT="${KIT_LLM_PORT:-18080}" KIT_LLM_START_TIMEOUT=180
mkdir -p "$HOME"
K="$KIT_BIN_DIR/kit-llm"
bash "$MOD/install.sh" --models "$MODEL"
"$K" doctor || true
"$K" start "$MODEL"
"$K" status
fail=0
de="$("$K" ask 'Antworte mit genau einem Wort: Was ist die Hauptstadt von Deutschland?')"
echo "DE: $de"
grep -qi berlin <<<"$de" || { echo "FAIL German answer"; fail=1; }
grep -q '<think>' <<<"$de" && { echo "FAIL reasoning text leaked"; fail=1; }
en="$("$K" ask 'Reply with only the number: what is 17 + 25?')"
echo "EN: $en"
grep -q 42 <<<"$en" || { echo "FAIL English answer"; fail=1; }
"$K" stop
[ "$fail" = 0 ] && echo "smoke ok: $MODEL"
exit "$fail"
