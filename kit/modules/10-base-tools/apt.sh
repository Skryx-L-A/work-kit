#!/usr/bin/env bash
# Optional: install git, tmux, build tools, zip/unzip and shellcheck with sudo from the offline
# apt repository on the stick (01-prereqs). No network. Nothing else in the kit needs this.
# Usage: apt.sh [--print]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREREQS="$HERE/../01-prereqs/install.sh"
ITEMS=(git tmux build-essential zip shellcheck)

if [ "${1:-}" = "--print" ]; then
  echo "bash $PREREQS --sudo ${ITEMS[*]}"
  exit 0
fi
[ -f "$PREREQS" ] || { echo "apt.sh: module 01-prereqs not found next to this module ($PREREQS)" >&2; exit 1; }
exec bash "$PREREQS" --sudo "${ITEMS[@]}"
