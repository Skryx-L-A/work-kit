#!/usr/bin/env bash
# Module 15-local-llm, build host step: download the pinned llama.cpp CPU build for Linux x86_64
# and the GGUF models from models.conf into $KIT_OFFLINE/local-llm/. Needs network and curl.
#
# Usage: fetch.sh [--models ID[,ID]|--all] [--dev-mac] [--verify] [--list]
#   (default)   engine + every model marked "default" in models.conf
#   --models    only these model ids (plus the engine); --all = every model in models.conf
#   --dev-mac   also fetch the macOS arm64 build of the same release (for tests on a Mac only;
#               not needed on the laptop)
#   --verify    no network: re-check files already in the offline directory
#   --list      print the pinned artifacts and exit
#
# Environment: KIT_OFFLINE (default: <kit>/offline).
#
# Hook for build/build-offline.sh (that script is not edited by this module):
#
#   step_llm() {
#     local f rel
#     KIT_OFFLINE="$OFFLINE" bash "$ROOT/kit/modules/15-local-llm/fetch.sh" || die "15-local-llm/fetch.sh failed"
#     while IFS= read -r f; do
#       rel="${f#"$OFFLINE"/}"
#       check_or_record "file:$rel" "$(sha256_of "$f")" "15-local-llm/fetch.sh"
#     done < <(find "$OFFLINE/local-llm" -type f | sort)
#   }
#   ... want llm && step_llm            (and add "llm" to the default ONLY list)
#   ... in the manifest merge:  file:local-llm/*) want llm || echo "$sum  $key  $rest" >>"$NEW" ;;
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
OUT="$KIT_OFFLINE/local-llm"
CATALOG="$HERE/models.conf"

# --- pinned engine ------------------------------------------------------------------------
# llama.cpp release v0.5.0 = build tag b11146 (2026-09-23). Digests from the GitHub release API.
# The ubuntu-x64 build ships CPU backends for many x86 levels (sse42 ... haswell=AVX2 ...
# sapphirerapids) and picks the best one at runtime, so AVX2 machines get AVX2 code.
LLAMA_BUILD="b11146"
ENGINE_LINUX="engine/llama-$LLAMA_BUILD-bin-ubuntu-x64.tar.gz|https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_BUILD/llama-$LLAMA_BUILD-bin-ubuntu-x64.tar.gz|c150306eb16b5ab696f76a8bdf810c35fd98a24e82158742e6fa28f420ff8410"
# OpenMP runtime the engine links against. Minimal Ubuntu images lack libgomp1; the Ubuntu 22.04
# build (glibc 2.35) runs on every supported release. Hash from the gpgv-checked jammy-updates index.
LIBGOMP="engine/libgomp1_12.3.0-1ubuntu1~22.04.3_amd64.deb|http://archive.ubuntu.com/ubuntu/pool/main/g/gcc-12/libgomp1_12.3.0-1ubuntu1~22.04.3_amd64.deb|870c27299185a5dd4accad3b15bf82a7409fd7073cccaa8025875307da4d0ce2"
ENGINE_MAC="engine/llama-$LLAMA_BUILD-bin-macos-arm64.tar.gz|https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_BUILD/llama-$LLAMA_BUILD-bin-macos-arm64.tar.gz|1ad3f9eff80edb9dbef4259ad564d1720612ef7eea48fa4afed0e54f5f3d5711"

MODE=fetch
SELECT=""
ALL=0
DEV_MAC=0
while [ $# -gt 0 ]; do
  case "$1" in
    --verify) MODE=verify ;;
    --list) MODE=list ;;
    --models) SELECT="${2:?--models needs ids}"; shift ;;
    --all) ALL=1 ;;
    --dev-mac) DEV_MAC=1 ;;
    -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

log() { printf '[local-llm fetch] %s\n' "$*"; }
die() { printf '[local-llm fetch] ERROR: %s\n' "$*" >&2; exit 1; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# artifacts: print "path|url|sha256" lines for everything selected.
artifacts() {
  echo "$ENGINE_LINUX"
  echo "$LIBGOMP"
  [ "$DEV_MAC" = 1 ] && echo "$ENGINE_MAC"
  local id repo rev file sha _rest ship found=""
  while IFS='|' read -r id repo rev file sha _rest; do
    case "$id" in ''|'#'*) continue ;; esac
    ship="$(printf '%s' "$_rest" | cut -d'|' -f4)"
    if [ -n "$SELECT" ]; then
      case ",$SELECT," in *",$id,"*) found="$found,$id" ;; *) continue ;; esac
    elif [ "$ALL" = 0 ] && [ "$ship" != default ]; then
      continue
    fi
    echo "models/$file|https://huggingface.co/$repo/resolve/$rev/$file|$sha"
  done <"$CATALOG"
  if [ -n "$SELECT" ]; then
    local want
    for want in ${SELECT//,/ }; do
      case "$found," in *",$want,"*) ;; *) die "unknown model id: $want (see models.conf)" ;; esac
    done
  fi
}

LIST="$(artifacts)"

if [ "$MODE" = list ]; then
  while IFS='|' read -r path url sha; do
    [ -n "$path" ] && printf '%s  %s\n    %s\n' "$sha" "$path" "$url"
  done <<<"$LIST"
  exit 0
fi

if [ "$MODE" = verify ]; then
  bad=0
  while IFS='|' read -r path _url sha; do
    [ -n "$path" ] || continue
    f="$OUT/$path"
    if [ ! -f "$f" ]; then echo "MISSING  $path"; bad=1
    elif [ "$(sha256_of "$f")" != "$sha" ]; then echo "MISMATCH $path"; bad=1
    else echo "ok       $path"; fi
  done <<<"$LIST"
  exit "$bad"
fi

command -v curl >/dev/null 2>&1 || die "curl is required on the build host"
mkdir -p "$OUT/engine" "$OUT/models"
cp "$CATALOG" "$OUT/models.conf"
while IFS='|' read -r path url sha; do
  [ -n "$path" ] || continue
  f="$OUT/$path"
  if [ -f "$f" ] && [ "$(sha256_of "$f")" = "$sha" ]; then log "ok       $path"; continue; fi
  log "download $path"
  curl -fL --retry 3 --connect-timeout 20 --max-time 3600 -sS -C - -o "$f.part" "$url" \
    || die "download failed: $url"
  got="$(sha256_of "$f.part")"
  [ "$got" = "$sha" ] || { rm -f "$f.part"; die "sha256 mismatch for $path (expected $sha, got $got)"; }
  mv "$f.part" "$f"
done <<<"$LIST"
log "done: $OUT ($(du -sh "$OUT" | awk '{print $1}'))"
