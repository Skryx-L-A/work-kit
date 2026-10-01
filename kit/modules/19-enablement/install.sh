#!/usr/bin/env bash
# Copy the enablement pack (content/) to ~/work/enablement. No network, no sudo.
# Re-running is safe: files you edited stay as they are; only when the kit ships a new
# version of a file you edited is yours kept first, as <file>.bak-<timestamp> below
# ~/.local/share/work-kit/backups/19-enablement/ (same relative path, original recorded in .origin).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/content"
DEST="${ENABLEMENT_HOME:-$HOME/work/enablement}"
STATE_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/state"
STATE="$STATE_DIR/19-enablement.sha256"
BAK_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/19-enablement"

log() { printf '[enablement] %s\n' "$*"; }
die() { printf '[enablement] ERROR: %s\n' "$*" >&2; exit 1; }

hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

[ -d "$SRC" ] || die "missing $SRC"
mkdir -p "$DEST" "$STATE_DIR"
touch "$STATE"
NEW_STATE="$(mktemp "$STATE_DIR/.19-enablement.XXXXXX")"
trap 'rm -f "$NEW_STATE"' EXIT
stamp="$(date +%Y%m%d%H%M%S)"
added=0 updated=0 same=0 kept=0 backed=0

while IFS= read -r rel; do
  src="$SRC/$rel" dst="$DEST/$rel"
  new_hash="$(hash_of "$src")"
  mkdir -p "$(dirname "$dst")"
  if [ ! -e "$dst" ]; then
    cp "$src" "$dst"; added=$((added + 1))
  else
    cur_hash="$(hash_of "$dst")"
    if [ "$cur_hash" = "$new_hash" ]; then
      same=$((same + 1))
    else
      old_hash="$(awk -v p="$rel" '$2 == p {print $1}' "$STATE")"
      if [ "$cur_hash" != "$old_hash" ] && [ "$new_hash" = "$old_hash" ]; then
        # You edited it and the kit version did not change: keep your file.
        kept=$((kept + 1))
      else
        if [ "$cur_hash" != "$old_hash" ]; then
          # your version is kept below the kit data dir, same relative path, original recorded
          bdir="$BAK_DIR/$(dirname "$rel")"; mkdir -p "$bdir"
          cp -p "$dst" "$bdir/$(basename "$rel").bak-$stamp"
          printf '%s\n' "$dst" >"$bdir/$(basename "$rel").bak-$stamp.origin"
          backed=$((backed + 1))
          log "you edited $rel and the kit has a new version: yours kept in $bdir/$(basename "$rel").bak-$stamp"
        fi
        cp "$src" "$dst"; updated=$((updated + 1))
      fi
    fi
  fi
  printf '%s %s\n' "$new_hash" "$rel" >>"$NEW_STATE"
done < <(cd "$SRC" && find . -type f ! -name '.*' | sed 's|^\./||' | sort)

mv "$NEW_STATE" "$STATE"
trap - EXIT
log "$DEST: $added added, $updated updated, $same unchanged, $kept edited kept, $backed backups"
log "start with $DEST/README.md; fill every TODO(ask IT) before running a session"
