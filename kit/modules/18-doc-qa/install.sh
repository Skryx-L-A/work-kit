#!/usr/bin/env bash
# Set up doc-qa in its disabled state. Safe to re-run; never overwrites the config.
set -euo pipefail

KIT_BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
export PATH="$KIT_BIN_DIR:$PATH"

if ! command -v doc-qa >/dev/null 2>&1; then
  echo "18-doc-qa: 'doc-qa' not found. Install 20-brain first (bash ../20-brain/install.sh)." >&2
  exit 1
fi
doc-qa init
doc-qa status || true
echo "18-doc-qa: stays disabled until an approved scope is filled in (see README.md)."
