#!/usr/bin/env bash
# Build-host step for 80-quassel: fill $KIT_OFFLINE/quassel/ with everything install.sh needs.
# Runs on the Mac (or any host with network); every artifact is for Linux x86_64.
#
# Usage: fetch.sh [--verify] [--relock-wheels]
#   (default)        download what is missing, check every file against fetch.lock /
#                    requirements.lock, fail on any mismatch
#   --verify         no network: only check $KIT_OFFLINE/quassel against the lock files
#   --relock-wheels  re-resolve requirements.in into requirements.lock (review the diff)
#
# Called by build/build-offline.sh (step "quassel"); also runs standalone.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_OFFLINE="${KIT_OFFLINE:-$(cd "$HERE/../.." && pwd)/offline}"
OUT="$KIT_OFFLINE/quassel"
LOCK="$HERE/fetch.lock"
REQ="$HERE/requirements.lock"
PYTHON_SERIES="3.12"
PIP_SPEC="pip>=24.2"
PLATFORMS=(manylinux_2_28_x86_64 manylinux_2_17_x86_64 manylinux2014_x86_64 linux_x86_64)

VERIFY=0
RELOCK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --verify) VERIFY=1 ;;
    --relock-wheels) RELOCK=1 ;;
    -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

log() { printf '[quassel-fetch] %s\n' "$*"; }
die() { printf '[quassel-fetch] ERROR: %s\n' "$*" >&2; exit 1; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

lock_entries() { grep -vE '^[[:space:]]*(#|$)' "$LOCK"; }

# Wheel hashes from requirements.lock: one "name==version sha..." block per package.
wheel_ok() { # file -> 0 if its sha256 is listed in requirements.lock
  grep -q "sha256:$(sha256_of "$1")" "$REQ"
}

if [ "$RELOCK" = 1 ]; then
  command -v uv >/dev/null 2>&1 || die "uv is required (brew install uv)"
  uv pip compile "$HERE/requirements.in" --python-platform x86_64-manylinux_2_28 \
    --python-version "$PYTHON_SERIES" --generate-hashes --no-build --no-header --no-annotate \
    -q -o "$REQ" || die "cannot resolve requirements.in"
  log "requirements.lock updated; review the diff, then run fetch.sh"
  exit 0
fi

# --- verify ---------------------------------------------------------------------------
verify_all() {
  local bad=0 sum path _url n=0
  while read -r sum path _url; do
    if [ ! -f "$OUT/$path" ]; then echo "MISSING  $path"; bad=1
    elif [ "$(sha256_of "$OUT/$path")" != "$sum" ]; then echo "MISMATCH $path"; bad=1; fi
  done < <(lock_entries)
  for w in "$OUT"/wheels/*.whl; do
    [ -f "$w" ] || continue
    n=$((n + 1))
    wheel_ok "$w" || { echo "UNPINNED $(basename "$w")"; bad=1; }
  done
  local want
  want="$(grep -cE '^[A-Za-z0-9]' "$REQ")"
  [ "$n" -ge "$want" ] || { echo "MISSING  wheels ($n of $want packages)"; bad=1; }
  return "$bad"
}

if [ "$VERIFY" = 1 ]; then
  verify_all && log "offline/quassel matches fetch.lock and requirements.lock" && exit 0
  exit 1
fi

# --- download -------------------------------------------------------------------------
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v uv >/dev/null 2>&1 || die "uv is required on the build host (brew install uv)"
mkdir -p "$OUT"

while read -r sum path url; do
  dest="$OUT/$path"
  if [ -f "$dest" ] && [ "$(sha256_of "$dest")" = "$sum" ]; then
    log "ok      $path"
    continue
  fi
  log "fetch   $path"
  mkdir -p "$(dirname "$dest")"
  curl -fL --retry 3 --connect-timeout 20 --max-time 1800 -sS -o "$dest.part" "$url" \
    || { rm -f "$dest.part"; die "download failed: $url"; }
  got="$(sha256_of "$dest.part")"
  [ "$got" = "$sum" ] || { rm -f "$dest.part"; die "sha256 mismatch for $path (expected $sum, got $got)"; }
  mv "$dest.part" "$dest"
done < <(lock_entries)
chmod 0755 "$OUT/bin/ydotool" "$OUT/bin/ydotoold"

# Wheels: same pip download rules as build/build-offline.sh, into a module-private folder so
# the kit-wide wheels/ set stays untouched.
plat_args=()
for p in "${PLATFORMS[@]}"; do plat_args+=(--platform "$p"); done
mkdir -p "$OUT/wheels"
log "wheels  $(grep -cE '^[A-Za-z0-9]' "$REQ") pinned packages (linux x86_64, CPython $PYTHON_SERIES)"
uv tool run --from "$PIP_SPEC" pip download --quiet --no-deps --require-hashes \
  --only-binary=:all: --python-version "$PYTHON_SERIES" --implementation cp \
  --abi "cp${PYTHON_SERIES/./}" --abi abi3 --abi none "${plat_args[@]}" \
  -r "$REQ" -d "$OUT/wheels" || die "pip download failed"
# Drop wheels that are no longer pinned (after a relock).
for w in "$OUT"/wheels/*.whl; do
  [ -f "$w" ] || continue
  wheel_ok "$w" || { log "remove  stale $(basename "$w")"; rm -f "$w"; }
done

verify_all || die "verification failed after download"
log "done: $OUT ($(du -sh "$OUT" | cut -f1))"
