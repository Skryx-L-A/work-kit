#!/usr/bin/env bash
# Install uv and a standalone CPython from kit/offline/ into $HOME. No network, no sudo.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

# Platform triple. Linux x86_64 is the target; macOS arm64 exists only for kit tests.
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) UV_TRIPLE="x86_64-unknown-linux-musl" ;;
  Darwin/arm64) UV_TRIPLE="aarch64-apple-darwin" ;;
  *) kit_die "unsupported platform $(uname -s)/$(uname -m) (need Linux x86_64)"; exit 1 ;;
esac

ARCHIVE="$KIT_OFFLINE/uv/uv-$UV_TRIPLE.tar.gz"
[ -f "$ARCHIVE" ] || { kit_die "missing $ARCHIVE (kit/offline is incomplete)"; exit 1; }
[ -d "$KIT_OFFLINE/python" ] || { kit_die "missing $KIT_OFFLINE/python"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
tar -xzf "$ARCHIVE" -C "$TMP"
SRC="$(find "$TMP" -type f -name uv -perm -u+x | head -n 1)"
[ -n "$SRC" ] || { kit_die "uv binary not found in $ARCHIVE"; exit 1; }

mkdir -p "$KIT_BIN_DIR" "$KIT_DATA_DIR/state"
for b in uv uvx; do
  src="$(dirname "$SRC")/$b"
  [ -f "$src" ] || continue
  dst="$KIT_BIN_DIR/$b"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    kit_log "$b already up to date"
    continue
  fi
  kit_backup "$dst" 00-python
  install -m 0755 "$src" "$dst"
  kit_log "installed $dst"
done

UV_PYTHON_INSTALL_MIRROR="file://$KIT_OFFLINE/python" \
  kit_uv python install --no-config "$KIT_PYTHON_VERSION"
kit_fix_lock_perms

: >"$KIT_DATA_DIR/state/00-python.installed"
kit_log "python: $("$KIT_BIN_DIR/uv" python find "$KIT_PYTHON_VERSION")"
case ":$PATH:" in
  *":$KIT_BIN_DIR:"*) ;;
  *) kit_warn "$KIT_BIN_DIR is not on PATH (60-terminal adds it, or add it to ~/.profile)" ;;
esac
