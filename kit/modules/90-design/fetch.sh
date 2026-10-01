#!/usr/bin/env bash
# Module 90-design, build host step: download the pinned headless Chromium (Chrome for Testing
# chrome-headless-shell, linux64) into $KIT_OFFLINE/design/. It gives 'kit-design doc -o x.pdf'
# a browser without sudo. Needs network and curl. build/build-offline.sh runs this in step modules.
# Usage: fetch.sh [--verify]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
OUT="${KIT_OFFLINE:-$KIT_ROOT/offline}/design"

# Google publishes no digest for Chrome for Testing; sha256 measured on 2026-09-25.
VERSION=154.0.8037.57
FILE="chrome-headless-shell-linux64-$VERSION.zip"
URL="https://storage.googleapis.com/chrome-for-testing-public/$VERSION/linux64/chrome-headless-shell-linux64.zip"
SHA=5a6979d0ab7cf952ea575d35164e7bdce4872b2ced8f8a215c8f8e8eda00ee09

sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
die() { printf '[design fetch] ERROR: %s\n' "$*" >&2; exit 1; }

mkdir -p "$OUT"
f="$OUT/$FILE"
if [ ! -f "$f" ]; then
  [ "${1:-}" = "--verify" ] && die "missing: $f"
  curl -fsSL -o "$f.part" "$URL" || die "download failed: $URL"
  mv "$f.part" "$f"
fi
got="$(sha256_of "$f")"
[ "$got" = "$SHA" ] || { rm -f "$f"; die "sha256 mismatch for $FILE (expected $SHA, got $got)"; }
printf '[design fetch] ok: %s\n' "$FILE"
