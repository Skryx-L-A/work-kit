#!/usr/bin/env bash
# Module check: at least one harness is recorded as installed and every recorded one is on PATH
# and points to files that exist. Light and offline: no harness is started.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"

names="$(hc_state_names | tr '\n' ' ')"
[ -n "${names// /}" ] || { echo "no harness recorded in $HC_STATE" >&2; exit 1; }
bad=0
for h in $names; do
  if [ ! -x "$KIT_BIN_DIR/$h" ] || ! hc_ours "$KIT_BIN_DIR/$h"; then echo "$h: $KIT_BIN_DIR/$h missing or not from this module" >&2; bad=1
  elif [ ! -d "$HC_DATA/$h/current/" ]; then echo "$h: $HC_DATA/$h/current missing" >&2; bad=1
  elif [ -L "$KIT_BIN_DIR/$h" ] && [ ! -e "$KIT_BIN_DIR/$h" ]; then echo "$h: broken link $KIT_BIN_DIR/$h" >&2; bad=1
  fi
done
exit "$bad"
