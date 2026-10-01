#!/usr/bin/env bash
# Module 95-desktop, build host step: download the pinned artifacts from pins.conf into
# $KIT_OFFLINE/desktop/ and check each sha256. Needs network and curl.
#
# Usage: fetch.sh [--verify] [--list] [--check-meta]
#   (default)     download what is missing, check every file against pins.conf
#   --verify      no network: re-check files already in the offline directory
#   --list        print the pinned artifacts and exit
#   --check-meta  no network: check that every extension zip declares the GNOME major of its
#                 directory in metadata.json "shell-version" (needs unzip or python3)
#
# Environment: KIT_OFFLINE (default: <kit>/offline).
#
# Hook for build/build-offline.sh (not edited by this module), same shape as 12-docs-tools:
#   KIT_OFFLINE="$OFFLINE" bash "$ROOT/kit/modules/95-desktop/fetch.sh" && \
#     KIT_OFFLINE="$OFFLINE" bash "$ROOT/kit/modules/95-desktop/fetch.sh" --check-meta
#   then record every file under "$OFFLINE/desktop" in the manifest.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
OUT="$KIT_OFFLINE/desktop"
PINS="$HERE/pins.conf"

MODE=fetch
for a in "$@"; do
  case "$a" in
    --verify) MODE=verify ;;
    --list) MODE=list ;;
    --check-meta) MODE=meta ;;
    -h|--help) awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

log() { printf '[desktop fetch] %s\n' "$*"; }
die() { printf '[desktop fetch] ERROR: %s\n' "$*" >&2; exit 1; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

pins() { grep -v '^[[:space:]]*#' "$PINS" | grep '|' || true; }

zip_metadata() {
  if command -v unzip >/dev/null 2>&1; then unzip -p "$1" metadata.json
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys,zipfile;sys.stdout.write(zipfile.ZipFile(sys.argv[1]).read("metadata.json").decode())' "$1"
  else die "need unzip or python3 for --check-meta"; fi
}

case "$MODE" in
  list)
    pins | while IFS='|' read -r path url sha; do printf '%s  %s\n    %s\n' "$sha" "$path" "$url"; done
    exit 0 ;;
  verify)
    bad=0
    while IFS='|' read -r path url sha; do
      f="$OUT/$path"
      if [ ! -f "$f" ]; then echo "MISSING  $path"; bad=1
      elif [ "$(sha256_of "$f")" != "$sha" ]; then echo "MISMATCH $path"; bad=1; fi
    done < <(pins)
    [ "$bad" = 0 ] && echo "desktop artifacts match the pins" && exit 0
    exit 1 ;;
  meta)
    bad=0
    while IFS='|' read -r path url sha; do
      case "$path" in extensions/*/*.zip) ;; *) continue ;; esac
      major="$(basename "$(dirname "$path")")"
      uuid="$(basename "$path" .zip)"
      f="$OUT/$path"
      [ -f "$f" ] || { echo "MISSING  $path"; bad=1; continue; }
      meta="$(zip_metadata "$f" | tr -d '\n ')"
      shells="$(printf '%s' "$meta" | sed -n 's/.*"shell-version":\[\([^]]*\)\].*/\1/p' | tr -d '"')"
      muuid="$(printf '%s' "$meta" | sed -n 's/.*"uuid":"\([^"]*\)".*/\1/p')"
      if [ "$muuid" != "$uuid" ]; then echo "UUID     $path says $muuid"; bad=1
      elif printf ',%s,' "$shells" | grep -q ",$major,"; then echo "ok       $path (shell-version $shells)"
      else echo "SHELL    $path supports $shells, not $major"; bad=1; fi
    done < <(pins)
    exit "$bad" ;;
esac

command -v curl >/dev/null 2>&1 || die "curl is required on the build host"
mkdir -p "$OUT"
while IFS='|' read -r path url sha; do
  f="$OUT/$path"
  if [ -f "$f" ] && [ "$(sha256_of "$f")" = "$sha" ]; then log "ok       $path"; continue; fi
  mkdir -p "$(dirname "$f")"
  log "download $path"
  curl -fL --retry 3 --connect-timeout 20 --max-time 1800 -sS -o "$f.part" "$url" || die "download failed: $url"
  got="$(sha256_of "$f.part")"
  [ "$got" = "$sha" ] || { rm -f "$f.part"; die "sha256 mismatch for $path (expected $sha, got $got)"; }
  mv "$f.part" "$f"
done < <(pins)
log "done: $OUT ($(du -sh "$OUT" | awk '{print $1}'))"
