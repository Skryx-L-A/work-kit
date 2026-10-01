#!/usr/bin/env bash
# Download the public work-kit offline set.  Python is the only prerequisite.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/fetch_offline.py" "$@"
