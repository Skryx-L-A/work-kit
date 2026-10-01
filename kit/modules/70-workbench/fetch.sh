#!/usr/bin/env bash
# Module 70-workbench, build host step: download the pinned artifacts of the desktop app
# (pins.conf: Electron for linux-x64, node-pty with its linux-x64 prebuild) into
# $KIT_OFFLINE/workbench-app/ and check each sha256. Needs network and curl.
#
# Usage: fetch.sh [--verify] [--list]
#   (default)  download what is missing, check every file against pins.conf
#   --verify   no network: re-check files already in the offline directory
#   --list     print the pinned artifacts and exit
#
# Environment: KIT_OFFLINE (default: <kit>/offline). build/build-offline.sh runs every module's
# fetch.sh in its modules step and records the files in build/manifest.lock.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
OUT="$KIT_OFFLINE/workbench-app"
PINS="$HERE/pins.conf"

MODE=fetch
for a in "$@"; do
  case "$a" in
    --verify) MODE=verify ;;
    --list) MODE=list ;;
    -h|--help) awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

log() { printf '[workbench-app fetch] %s\n' "$*"; }
die() { printf '[workbench-app fetch] ERROR: %s\n' "$*" >&2; exit 1; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

pins() { grep -v '^[[:space:]]*#' "$PINS" | grep '|' || true; }

case "$MODE" in
  list)
    pins | while IFS='|' read -r path url sha; do printf '%s  %s\n    %s\n' "$sha" "$path" "$url"; done
    exit 0 ;;
  verify)
    bad=0
    while IFS='|' read -r path url sha; do
      f="$OUT/$path"
      if [ ! -f "$f" ]; then echo "MISSING  $path"; bad=1
      elif [ "$(sha256_of "$f")" != "$sha" ]; then echo "MISMATCH $path"; bad=1
      else echo "ok       $path"; fi
    done < <(pins)
    [ "$bad" = 0 ] && echo "workbench-app artifacts match the pins"
    exit "$bad" ;;
esac

command -v curl >/dev/null 2>&1 || die "curl is required on the build host"
mkdir -p "$OUT"
while IFS='|' read -r path url sha; do
  f="$OUT/$path"
  if [ -f "$f" ] && [ "$(sha256_of "$f")" = "$sha" ]; then log "ok       $path"; continue; fi
  log "download $path"
  curl -fL --retry 3 --connect-timeout 20 --max-time 1800 -sS -o "$f.part" "$url" || die "download failed: $url"
  got="$(sha256_of "$f.part")"
  [ "$got" = "$sha" ] || { rm -f "$f.part"; die "sha256 mismatch for $path (expected $sha, got $got)"; }
  mv "$f.part" "$f"
done < <(pins)
log "done: $OUT ($(du -sh "$OUT" | awk '{print $1}'))"
