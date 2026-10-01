#!/usr/bin/env bash
# Optional sudo parts of 95-desktop through the offline apt repository of 01-prereqs:
#   alacritty   Alacritty terminal (Ubuntu universe; Ghostty ships user-level without sudo)
#   dconf       dconf CLI, only if it is missing (Ubuntu desktop has it by default)
#   zip         unzip for extension zips, only if it is missing
# Usage: apt.sh [--print] [ITEM ...]   (default: alacritty)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREREQS="$HERE/../01-prereqs"
PRINT=0 items=()
for a in "$@"; do
  case "$a" in
    --print) PRINT=1 ;;
    -h|--help) awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) items+=("$a") ;;
  esac
done
[ "${#items[@]}" -gt 0 ] || items=(alacritty)

missing=()
for i in "${items[@]}"; do
  grep -q "^${i}[[:space:]]*|" "$PREREQS/items.conf" 2>/dev/null || missing+=("$i")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "apt.sh: 01-prereqs has no item for: ${missing[*]} (not on this stick)." >&2
  echo "Ask the kit maintainer to add them to 01-prereqs/items.conf, e.g.:" >&2
  echo "  alacritty | no | none | alacritty | alacritty | Alacritty terminal (95-desktop)" >&2
  echo "  dconf     | no | deb  | dconf-cli | dconf     | dconf CLI (95-desktop backup)" >&2
  exit 1
fi
if [ "$PRINT" = 1 ]; then echo "bash $PREREQS/install.sh --sudo ${items[*]}"; exit 0; fi
exec bash "$PREREQS/install.sh" --sudo "${items[@]}"
