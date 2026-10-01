#!/usr/bin/env bash
# Build the evalkit wheel into offline/wheels (run on the build machine, needs network for the build backend).
# The runtime dependency (pyyaml) must be fetched separately for linux x86_64 by build/build-offline.sh.
set -euo pipefail
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$MODULE_DIR/../../offline/wheels}"
mkdir -p "$OUT"
uv build --wheel --out-dir "$OUT" "$MODULE_DIR"
