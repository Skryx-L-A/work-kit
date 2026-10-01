#!/usr/bin/env bash
# Install the llm-usage CLI (standard-library Python, no wheels). No network, no sudo.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
LIB_DIR="$DATA_DIR/llm-usage-lib"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/work-kit"
log() { printf '[llm-usage] %s\n' "$*"; }
sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
refresh_default() { # source destination state-key
  local src="$1" dst="$2" key="$3" state="$DATA_DIR/default-settings.sha256" old
  old="$(awk -v k="$key" '$1 == k {print $2}' "$state" 2>/dev/null || true)"
  if [ ! -e "$dst" ]; then
    install -m 0644 "$src" "$dst"; old="$(sha256_of "$dst")"
  elif [ -n "$old" ] && [ "$(sha256_of "$dst")" = "$old" ]; then
    install -m 0644 "$src" "$dst"; old="$(sha256_of "$dst")"; log "refreshed $dst (kit default)"
  elif [ -n "$old" ]; then
    install -m 0644 "$src" "$dst.kit-new"; log "kept your $dst; new kit default written to $dst.kit-new"; return
  else
    log "keeping pre-existing $dst (no kit default state)"; return
  fi
  { awk -v k="$key" '$1 != k' "$state" 2>/dev/null || true; printf '%s %s\n' "$key" "$old"; } >"$state.new"
  mv "$state.new" "$state"
}

mkdir -p "$BIN_DIR" "$LIB_DIR" "$CONF_DIR" "$DATA_DIR/llm-usage"
install -m 0644 "$HERE/llm_usage.py" "$LIB_DIR/llm_usage.py"
dst="$BIN_DIR/llm-usage"
if [ -f "$dst" ] && cmp -s "$HERE/llm-usage" "$dst"; then
  log "llm-usage up to date"
else
  if [ -e "$dst" ] && ! grep -q '^# llm-usage launcher' "$dst" 2>/dev/null; then
    bdir="$DATA_DIR/backups/14-llm-usage"; mkdir -p "$bdir"
    b="$bdir/llm-usage.bak-$(date +%Y%m%d%H%M%S)"; mv "$dst" "$b"
    printf '%s\n' "$dst" >"$b.origin"; log "backup: $dst -> $b"
  fi
  install -m 0755 "$HERE/llm-usage" "$dst"
  log "installed $dst"
fi
refresh_default "$HERE/llm-prices.example.toml" "$CONF_DIR/llm-prices.toml" llm-prices.toml
if ! LLM_USAGE_LIB="$LIB_DIR/llm_usage.py" "$dst" --version >/dev/null 2>&1; then
  log "WARNING: no Python >= 3.11 found; install 00-python or the system python3"
fi
log "done. Try: llm-usage start --upstream http://127.0.0.1:8080/v1 --free"
