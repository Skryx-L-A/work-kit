#!/usr/bin/env bash
# Install 13-ai-governance: the `ai-gov` CLI, templates, and the policy files (AI usage
# guideline, deployer checklist, MCP policy, MCP allowlist) as editable copies in
# ~/.config/work-kit/. No network, no sudo. Needs python3 or the kit CPython (01-prereqs,
# 00-python; the module does not depend on either). Re-running never overwrites a policy file you edited: the new shipped
# version goes next to it as <file>.kit-new.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/ai-governance"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/work-kit"
STAMP="$(date +%Y%m%d%H%M%S)"

log() { printf '[ai-governance] %s\n' "$*"; }

# backup_file FILE: move FILE to $KIT_DATA_DIR/backups/13-ai-governance/<name>.bak-<timestamp> and record
# the original path in <name>.bak-<timestamp>.origin. Nothing is left beside the original.
backup_file() {
  local dir b
  dir="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/13-ai-governance"
  mkdir -p "$dir"
  b="$dir/$(basename "$1").bak-$STAMP"
  while [ -e "$b" ]; do b="$b-1"; done
  mv "$1" "$b" || return 1
  printf '%s\n' "$1" >"$b.origin"
  log "backup: $1 -> $b"
}

# copy_managed SRC DST: shipped file the user edits; never overwrite their version.
copy_managed() {
  local src="$1" dst="$2"
  if [ ! -e "$dst" ]; then
    cp "$src" "$dst"; log "created $dst"
  elif cmp -s "$src" "$dst"; then
    log "$dst up to date"
  else
    cp "$src" "$dst.kit-new"
    log "kept your $dst; new shipped version written to $dst.kit-new"
  fi
}

# shellcheck source=../../lib/kit-python/kit-python.sh
. "$HERE/../../lib/kit-python/kit-python.sh"
PY="$(kit_find_python)" || { log "ERROR: $(kit_python_hint)"; exit 1; }

mkdir -p "$BIN_DIR" "$CONF_DIR" "$DATA_DIR/templates" "$DATA_DIR/policy"
if [ -f "$DATA_DIR/ai-gov" ] && ! cmp -s "$HERE/ai-gov" "$DATA_DIR/ai-gov"; then
  backup_file "$DATA_DIR/ai-gov"
fi
cp "$HERE/ai-gov" "$DATA_DIR/ai-gov"
chmod +x "$DATA_DIR/ai-gov"
cp "$HERE"/templates/*.md "$DATA_DIR/templates/"
cp "$HERE"/policy/* "$DATA_DIR/policy/"
log "installed $DATA_DIR"

# ai-gov is a launcher, not a link: the script's python3 shebang fails without system python.
LINK="$BIN_DIR/ai-gov"
LTMP="$(mktemp "$BIN_DIR/.ai-gov.XXXXXX")"
kit_write_py_launcher "$LTMP" "$DATA_DIR/ai-gov" ai-gov
if [ -f "$LINK" ] && [ ! -L "$LINK" ] && cmp -s "$LTMP" "$LINK"; then
  rm -f "$LTMP"
else
  if [ -e "$LINK" ] || [ -L "$LINK" ]; then backup_file "$LINK"; fi
  mv "$LTMP" "$LINK"
  log "installed $LINK"
fi

for f in ai-usage-guideline.md deployer-checklist.md mcp-policy.md mcp-allowlist.yaml; do
  copy_managed "$HERE/policy/$f" "$CONF_DIR/$f"
done

if "$PY" -c 'import sys; sys.exit(sys.version_info < (3, 11))'; then :; else
  log "note: $PY is older than 3.11; Codex config.toml files are reported as UNREADABLE"
fi
log "next: ai-gov open-questions   (questions for IT)   ai-gov mcp-check   (MCP servers vs. allowlist)"
