#!/usr/bin/env bash
# Remove what 01-prereqs installed. Usage: uninstall.sh [--sudo] [ITEM ...]
#   (default)  every installed item; no-sudo items are removed, apt items are only listed
#   --sudo     also remove apt-installed items with apt-get remove
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh source-path=SCRIPTDIR
. "$HERE/common.sh"

SUDO=0
SEL=()
for a in "$@"; do
  case "$a" in
    --sudo) SUDO=1 ;;
    -h|--help) sed -n '2,4p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) pq_die "unknown option: $a" ;;
    *) IFS=', ' read -r -a more <<<"$a"; SEL+=("${more[@]}") ;;
  esac
done
if [ "${#SEL[@]}" -eq 0 ]; then
  while IFS= read -r i; do SEL+=("$i"); done < <(pq_state_items)
fi
# Wrappers without a state entry (interrupted install) are removed with the last item.

# Menu entry of VS Code: code.desktop only when it carries our mark (a system or user file stays),
# and the work-kit-code.desktop an earlier version wrote.
rm_desktop() {
  rm -f "$PQ_APPS/work-kit-code.desktop"
  if grep -q "^# $PQ_MARK" "$PQ_APPS/code.desktop" 2>/dev/null; then rm -f "$PQ_APPS/code.desktop"; fi
}

apt_pkgs=()
for item in ${SEL[@]+"${SEL[@]}"}; do
  mode="$(pq_state_mode "$item")"
  if [ "$mode" = sudo ]; then
    read -r -a pk <<<"$(pq_field "$item" 4)"
    apt_pkgs+=(${pk[@]+"${pk[@]}"})
    pq_state_del "$item"
    continue
  fi
  for f in "$KIT_BIN_DIR"/*; do
    [ -f "$f" ] && grep -q "^# $PQ_MARK item=$item " "$f" 2>/dev/null && rm -f "$f" && pq_log "removed $f"
  done
  case "$item" in
    vscode) rm -rf "$PQ_VSCODE"; rm_desktop ;;
    python3) rm -rf "$PQ_DATA/python" ;;
    node) rm -rf "$PQ_DATA/node" ;;
  esac
  pq_state_del "$item"
  pq_log "$item removed"
done

if [ -z "$(pq_state_items)" ]; then
  for f in "$KIT_BIN_DIR"/*; do
    if pq_is_ours "$f"; then rm -f "$f" && pq_log "removed $f"; fi
  done
  rm_desktop
  rm -rf "$PQ_VSCODE" "$PQ_DATA"
  pq_log "removed $PQ_DATA"
fi

if [ "${#apt_pkgs[@]}" -gt 0 ]; then
  if [ "$SUDO" = 1 ]; then
    sudo apt-get remove -y "${apt_pkgs[@]}"
  else
    pq_log "installed with apt; remove with: sudo apt-get remove ${apt_pkgs[*]}"
  fi
fi
