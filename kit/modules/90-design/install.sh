#!/usr/bin/env bash
# Install module 90-design: reference folders ~/work/design-refs/<category>/ (each with a
# README) and the kit-design CLI from kit/offline/wheels. No network, no sudo. Safe to re-run.
# Usage: install.sh [--refs-only]
# Environment: DESIGN_REFS (default ~/work/design-refs), KIT_OFFLINE, KIT_BIN_DIR, KIT_DATA_DIR.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
REFS="${DESIGN_REFS:-$HOME/work/design-refs}"
STATE_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/state"
CATEGORIES=(brand web slides documents diagrams)

log() { printf '[design] %s\n' "$*"; }
die() { printf '[design] ERROR: %s\n' "$*" >&2; exit 1; }

# backup_file FILE SUBDIR: move FILE to $KIT_DATA_DIR/backups/90-design/SUBDIR/<name>.bak-<timestamp>
# and record the original path in <name>.bak-<timestamp>.origin. Nothing is left beside the original.
backup_file() {
  local dir b
  dir="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/90-design/$2"
  mkdir -p "$dir"
  b="$dir/$(basename "$1").bak-$(date +%Y%m%d%H%M%S)"
  while [ -e "$b" ]; do b="$b-1"; done
  mv "$1" "$b" || return 1
  printf '%s\n' "$1" >"$b.origin"
  log "backup: $1 -> $b"
}

refs_only=0
for a in "$@"; do
  case "$a" in
    --refs-only) refs_only=1 ;;
    -h|--help) sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $a" ;;
  esac
done

# 1. reference folders; your own files are never touched, a changed README is backed up
for c in "${CATEGORIES[@]}"; do
  mkdir -p "$REFS/$c"
  src="$HERE/refs/$c/README.md" dst="$REFS/$c/README.md"
  if [ ! -e "$dst" ]; then
    cp "$src" "$dst"
  elif ! cmp -s "$src" "$dst"; then
    backup_file "$dst" "$c"
    cp "$src" "$dst"
  fi
done
mkdir -p "$STATE_DIR"
printf 'DESIGN_REFS=%q\n' "$REFS" >"$STATE_DIR/90-design.env"
log "reference folders ready: $REFS/{$(IFS=,; echo "${CATEGORIES[*]}")}"
[ "$refs_only" = 1 ] && exit 0

# 2. kit-design CLI (needs 00-python and the offline wheels)
LIB="$KIT_ROOT/modules/00-python/lib.sh"
[ -f "$LIB" ] || die "modules/00-python/lib.sh not found: install 00-python, or run with --refs-only"
# shellcheck source=/dev/null
. "$LIB"
kit_uv_tool_install "$HERE" || die "kit-design not installed (reference folders are in place)"
BIN="${KIT_BIN_DIR:-$HOME/.local/bin}/kit-design"
"$BIN" --version >/dev/null || die "$BIN does not run"
log "installed $BIN"

# 3. headless Chromium for PDF output (no sudo): kit-chrome-headless wrapper
CHS_ZIP="$(ls "$KIT_OFFLINE"/design/chrome-headless-shell-linux64-*.zip 2>/dev/null | tail -n 1 || true)"
CHS_DIR="$KIT_DATA_DIR/design/chrome-headless-shell"
if [ -n "$CHS_ZIP" ] && [ "$(uname -m)" = x86_64 ]; then
  PY="$KIT_TOOL_DIR/kit-design/bin/python"
  [ -x "$PY" ] || PY=python3
  rm -rf "${CHS_DIR:?}.new"
  mkdir -p "$CHS_DIR.new"
  "$PY" - "$CHS_ZIP" "$CHS_DIR.new" <<'PYEOF'
import os, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    for i in z.infolist():
        z.extract(i, sys.argv[2])
        mode = (i.external_attr >> 16) & 0o777
        if mode:
            os.chmod(os.path.join(sys.argv[2], i.filename), mode)
PYEOF
  rm -rf "$CHS_DIR"
  mv "$CHS_DIR.new" "$CHS_DIR"
  # Ubuntu 23.10+ blocks the Chromium sandbox for unprivileged users; headless printing of
  # local files runs without it.
  cat >"$KIT_BIN_DIR/kit-chrome-headless" <<WEOF
#!/usr/bin/env bash
# kit-chrome-headless: headless Chromium for kit-design PDF output (90-design).
case "\${1:-}" in -h|--help) echo "usage: kit-chrome-headless [chrome-headless-shell options] URL   (used by kit-design doc -o x.pdf)"; exit 0 ;; esac
exec "$CHS_DIR/chrome-headless-shell-linux64/chrome-headless-shell" --no-sandbox "\$@"
WEOF
  chmod +x "$KIT_BIN_DIR/kit-chrome-headless"
  if "$KIT_BIN_DIR/kit-chrome-headless" --version >/dev/null 2>&1; then
    log "installed $KIT_BIN_DIR/kit-chrome-headless (PDF output)"
  else
    log "note: kit-chrome-headless does not start (missing system libraries?); PDF needs a Chromium-family browser"
  fi
fi

# 4. optional helpers: report only
if ! command -v kit-chrome-headless >/dev/null 2>&1 && ! command -v chromium >/dev/null 2>&1 && ! command -v chromium-browser >/dev/null 2>&1 \
  && ! command -v google-chrome >/dev/null 2>&1 && ! command -v microsoft-edge >/dev/null 2>&1 \
  && [ ! -x /snap/bin/chromium ]; then
  log "note: no Chromium-family browser found; 'kit-design doc -o x.pdf' needs one (HTML output works)"
fi
command -v pandoc >/dev/null 2>&1 || log "note: pandoc not found; DOCX output needs module 12-docs-tools"
command -v soffice >/dev/null 2>&1 || log "note: LibreOffice not found; PPTX to PDF/PNG checks need it"
log "done. Try: kit-design refs"
