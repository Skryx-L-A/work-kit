#!/usr/bin/env bash
# Optional: install Graphviz (dot) with sudo from the offline apt repository on the stick
# (01-prereqs). No network. Graphviz has no static Linux build, so this is the only route.
# Nothing else in the kit needs it. Usage: apt.sh [--print]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREREQS="$HERE/../01-prereqs/install.sh"

if [ "${1:-}" = "--print" ]; then
  echo "bash $PREREQS --sudo graphviz"
  exit 0
fi
[ -f "$PREREQS" ] || { echo "apt.sh: module 01-prereqs not found next to this module ($PREREQS)" >&2; exit 1; }
exec bash "$PREREQS" --sudo graphviz
