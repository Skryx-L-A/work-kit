#!/usr/bin/env bash
# Remove harness CLIs that install.sh placed under $HOME.
# Usage: uninstall.sh [harness ...]   (default: every harness recorded as installed)
# Keeps the backups (below ~/.local/share/work-kit/backups) and every harness's own config and login (~/.claude, ~/.codex, ~/.gemini,
# ~/.pi, ~/.config/opencode, ~/.copilot, ~/.aider*): those belong to the user.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"

WANT=""
for a in "$@"; do
  case "$a" in
    -h|--help) sed -n '2,6p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    all) WANT="$WANT $HC_ALL" ;;
    -*) hc_die "unknown option: $a" ;;
    *) hc_known "$a" || hc_die "unknown harness: $a (known: $HC_ALL)"; WANT="$WANT $a" ;;
  esac
done
[ -n "$WANT" ] || WANT="$(hc_state_names | tr '\n' ' ')"
[ -n "${WANT// /}" ] || { hc_log "nothing to remove (no state file)"; exit 0; }

for h in $WANT; do
  dst="$KIT_BIN_DIR/$h"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    if hc_ours "$dst"; then rm -f "$dst"; hc_log "removed $dst"
    else hc_warn "$dst is not ours, left in place"; fi
  fi
  if [ -d "$HC_DATA/$h" ]; then rm -rf "${HC_DATA:?}/$h"; hc_log "removed $HC_DATA/$h"; fi
  hc_state_del "$h"
done
rmdir "$HC_DATA" 2>/dev/null || true
