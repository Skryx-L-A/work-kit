#!/usr/bin/env bash
# Module 12-docs-tools, build host step: download the pinned offline artifacts for Linux x86_64
# into $KIT_OFFLINE/docs-tools/. Needs network and curl.
#
# Usage: fetch.sh [--verify] [--list]
#   (default)   download what is missing, check every file against the sha256 below
#   --verify    no network: re-check files already in the offline directory
#   --list      print the pinned artifacts and exit
#
# Environment: KIT_OFFLINE (default: <kit>/offline). Downloads go straight to the offline directory.
#
# Hook for build/build-offline.sh (that script is not edited by this module). Add a step
# next to step_model and record the fetched files the same way:
#
#   step_docs() {
#     local script="$ROOT/kit/modules/12-docs-tools/fetch.sh" f rel
#     KIT_OFFLINE="$OFFLINE" bash "$script" || die "12-docs-tools/fetch.sh failed"
#     while IFS= read -r f; do
#       rel="${f#"$OFFLINE"/}"
#       check_or_record "file:$rel" "$(sha256_of "$f")" "12-docs-tools/fetch.sh"
#     done < <(find "$OFFLINE/docs-tools" -type f | sort)
#   }
#   ... want docs && step_docs          (and add "docs" to the default ONLY list)
#   ... in the manifest merge:  file:docs-tools/*) want docs || echo "$sum  $key  $rest" >>"$NEW" ;;
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
OUT="$KIT_OFFLINE/docs-tools"

# --- pinned artifacts ---------------------------------------------------------------------
# path under $OUT | url | sha256   (digests published by the GitHub release API, 2026-09-25)
# Graphviz has no static Linux build: it is an optional sudo step through 01-prereqs (apt.sh).
ARTIFACTS='
bin/d2-v0.9.0-linux-amd64.tar.gz|https://github.com/terrastruct/d2/releases/download/v0.9.0/d2-v0.9.0-linux-amd64.tar.gz|5669ddc46b99e942cc96078f4a4e36d5e62103348f4c05179ede27802fdd87a9
bin/pandoc-3.11-linux-amd64.tar.gz|https://github.com/jgm/pandoc/releases/download/3.11/pandoc-3.11-linux-amd64.tar.gz|37edb3bbcf722f921a009941bf5874e2e0c09263226c9b4a2d980788cb062ab6
'

MODE=fetch
for a in "$@"; do
  case "$a" in
    --verify) MODE=verify ;;
    --list) MODE=list ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

log() { printf '[docs-tools fetch] %s\n' "$*"; }
die() { printf '[docs-tools fetch] ERROR: %s\n' "$*" >&2; exit 1; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

if [ "$MODE" = list ]; then
  while IFS='|' read -r path url sha; do
    [ -n "$path" ] && printf '%s  %s\n    %s\n' "$sha" "$path" "$url"
  done <<<"$ARTIFACTS"
  exit 0
fi

if [ "$MODE" = verify ]; then
  bad=0
  while IFS='|' read -r path url sha; do
    [ -n "$path" ] || continue
    f="$OUT/$path"
    if [ ! -f "$f" ]; then echo "MISSING  $path"; bad=1
    elif [ "$(sha256_of "$f")" != "$sha" ]; then echo "MISMATCH $path"; bad=1; fi
  done <<<"$ARTIFACTS"
  [ "$bad" = 0 ] && echo "docs-tools artifacts match the pins" && exit 0
  exit 1
fi

command -v curl >/dev/null 2>&1 || die "curl is required on the build host"
mkdir -p "$OUT"
while IFS='|' read -r path url sha; do
  [ -n "$path" ] || continue
  f="$OUT/$path"
  if [ -f "$f" ] && [ "$(sha256_of "$f")" = "$sha" ]; then log "ok       $path"; continue; fi
  mkdir -p "$(dirname "$f")"
  log "download $path"
  curl -fL --retry 3 --connect-timeout 20 --max-time 900 -sS -o "$f.part" "$url" || die "download failed: $url"
  got="$(sha256_of "$f.part")"
  [ "$got" = "$sha" ] || { rm -f "$f.part"; die "sha256 mismatch for $path (expected $sha, got $got)"; }
  mv "$f.part" "$f"
done <<<"$ARTIFACTS"
log "done: $OUT ($(du -sh "$OUT" | awk '{print $1}'))"
