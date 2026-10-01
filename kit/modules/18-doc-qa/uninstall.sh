#!/usr/bin/env bash
# Remove the doc-qa search index. The config and the ingested documents stay (delete them by
# hand if the approval ends: ~/.config/work-kit/doc-qa.toml and the scope home).
set -euo pipefail

CONFIG="${DOCQA_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/work-kit/doc-qa.toml}"
HOME_DIR="$HOME/work/doc-qa"
if [ -f "$CONFIG" ]; then
  line="$(grep -E '^[[:space:]]*home[[:space:]]*=' "$CONFIG" | head -n1 || true)"
  if [ -n "$line" ]; then
    value="$(printf '%s' "$line" | sed -E 's/^[^=]*=[[:space:]]*"([^"]*)".*/\1/')"
    [ -n "$value" ] && HOME_DIR="${value/#\~/$HOME}"
  fi
fi
rm -rf "$HOME_DIR/.brain"
echo "18-doc-qa: removed the index in $HOME_DIR/.brain."
echo "18-doc-qa: kept $CONFIG and the documents in $HOME_DIR."
