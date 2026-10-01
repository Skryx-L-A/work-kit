#!/usr/bin/env bash
# Build-host step for 01-prereqs: fill $KIT_OFFLINE/prereqs/ with an offline apt repository
# (Ubuntu jammy, noble, resolute; full dependency closure) and the portable downloads (VS Code, Node).
# Runs on the Mac or any host with network, curl, gpg/gpgv, python3 (3.9+), xz.
#
# Usage: fetch.sh [--verify] [--relock] [--list]
#   (default)  download what is missing; the resolved closure must equal lock/<release>.lock
#   --relock   re-resolve from pins.conf and rewrite lock/*.lock (review the diff), then download
#   --verify   no network: check $KIT_OFFLINE/prereqs against the lock files
#   --list     print item sizes per release from the lock files
#
# Hook for build/build-offline.sh (that script is not edited by this module). Add a step next
# to step_model and record the fetched files the same way:
#
#   step_prereqs() {
#     local script="$ROOT/kit/modules/01-prereqs/fetch.sh" f rel
#     KIT_OFFLINE="$OFFLINE" bash "$script" || die "01-prereqs/fetch.sh failed"
#     while IFS= read -r f; do
#       rel="${f#"$OFFLINE"/}"
#       check_or_record "file:$rel" "$(sha256_of "$f")" "01-prereqs/fetch.sh"
#     done < <(find "$OFFLINE/prereqs" -type f | sort)
#   }
#   ... want prereqs && step_prereqs      (and add "prereqs" to the default ONLY list)
#   ... in the manifest merge:  file:prereqs/*) want prereqs || echo "$sum  $key  $rest" >>"$NEW" ;;
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
OUT="$KIT_OFFLINE/prereqs"
CACHE="${PREREQS_CACHE:-$KIT_ROOT/../build/.cache/prereqs}"
LOCKDIR="$HERE/lock"
# shellcheck source=pins.conf source-path=SCRIPTDIR
. "$HERE/pins.conf"

VERIFY=0
RELOCK=0
LIST=0
for a in "$@"; do
  case "$a" in
    --verify) VERIFY=1 ;;
    --relock) RELOCK=1 ;;
    --list) LIST=1 ;;
    -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

log() { printf '[prereqs-fetch] %s\n' "$*"; }
die() { printf '[prereqs-fetch] ERROR: %s\n' "$*" >&2; exit 1; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

lock_lines() { grep -vhE '^[[:space:]]*(#|$)' "$@"; }

if [ "$LIST" = 1 ]; then
  for rel in $RELEASES; do
    [ -f "$LOCKDIR/$rel.lock" ] || continue
    echo "$rel:"
    awk '!/^#/ { n = split($7, it, ","); for (i = 1; i <= n; i++) { s[it[i]] += $4; c[it[i]]++ } ; t += $4; p++ }
         END { for (k in s) printf "  %-16s %4d packages %8.1f MB\n", k, c[k], s[k] / 1e6;
               printf "  %-16s %4d packages %8.1f MB (repository)\n", "total", p, t / 1e6 }' "$LOCKDIR/$rel.lock" | sort
  done
  lock_lines "$LOCKDIR/files.lock" | while read -r sum path _url; do
    printf '  file %s (%s)\n' "$path" "$sum"
  done
  exit 0
fi

# --- verify ---------------------------------------------------------------------------------
verify_all() {
  local bad=0 rel sum file n pk
  for rel in $RELEASES; do
    pk="$OUT/apt/dists/$rel/main/binary-amd64/Packages"
    [ -f "$pk" ] || { echo "MISSING  $pk"; bad=1; }
    [ -f "$OUT/apt/dists/$rel/Release" ] || { echo "MISSING  apt/dists/$rel/Release"; bad=1; }
    while read -r _ _ sum _ file _; do
      if [ ! -f "$OUT/apt/$file" ]; then echo "MISSING  apt/$file"; bad=1
      elif [ "$(sha256_of "$OUT/apt/$file")" != "$sum" ]; then echo "MISMATCH apt/$file"; bad=1; fi
    done < <(lock_lines "$LOCKDIR/$rel.lock")
    if [ -f "$pk" ]; then
      n="$(grep -c '^Package: ' "$pk")"
      [ "$n" = "$(lock_lines "$LOCKDIR/$rel.lock" | wc -l | tr -d ' ')" ] \
        || { echo "MISMATCH $pk ($n packages, lock differs)"; bad=1; }
      grep -q "$(sha256_of "$pk")" "$OUT/apt/dists/$rel/Release" 2>/dev/null \
        || { echo "MISMATCH apt/dists/$rel/Release (Packages hash)"; bad=1; }
    fi
  done
  while read -r sum file _url; do
    if [ ! -f "$OUT/$file" ]; then echo "MISSING  $file"; bad=1
    elif [ "$(sha256_of "$OUT/$file")" != "$sum" ]; then echo "MISMATCH $file"; bad=1; fi
  done < <(lock_lines "$LOCKDIR/files.lock")
  return "$bad"
}

if [ "$VERIFY" = 1 ]; then
  verify_all && log "offline/prereqs matches lock/" && exit 0
  exit 1
fi

# --- network steps --------------------------------------------------------------------------
for t in curl gpg gpgv python3 xz; do command -v "$t" >/dev/null 2>&1 || die "$t is required"; done
mkdir -p "$CACHE" "$OUT/apt/pool"
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

get() { # url dest
  curl -fL --retry 3 --connect-timeout 20 --max-time 1800 -sS -o "$2.part" "$1" \
    || { rm -f "$2.part"; die "download failed: $1"; }
  mv "$2.part" "$2"
}

keyring() { # name fingerprint url -> keyring file for gpgv; the key must carry the fingerprint.
  # Only `gpg --show-keys` and `--dearmor` are used: nothing is imported into the user's keyring.
  local kr="$TMPD/$1.gpg"
  if [ ! -s "$kr" ]; then
    get "$3" "$TMPD/$1.asc"
    gpg --batch --with-colons --show-keys "$TMPD/$1.asc" 2>/dev/null \
      | grep -q "^fpr:::::::::$2:" || die "$1 key does not have fingerprint $2"
    gpg --batch --dearmor <"$TMPD/$1.asc" >"$kr" || die "cannot dearmor $1 key"
  fi
  echo "$kr"
}

verified_inrelease() { # url dest keyring: download InRelease and check its signature
  get "$1" "$2"
  gpgv --keyring "$3" "$2" 2>/dev/null || die "bad signature: $1"
}

ubuntu_kr="$(keyring ubuntu "$UBUNTU_KEY" "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x$UBUNTU_KEY")"
ms_kr="$(keyring microsoft "$MS_KEY" "$MS_KEY_URL")"
google_kr="$(keyring google "$GOOGLE_KEY" "$GOOGLE_KEY_URL")"

# Vendor indexes (signed), shared by all releases.
vendor_args=()
while IFS='|' read -r vname base keyvar pkg ver; do
  [ -n "$vname" ] || continue
  case "$keyvar" in MS) kr="$ms_kr" ;; GOOGLE) kr="$google_kr" ;; *) die "unknown key $keyvar" ;; esac
  d="$TMPD/vendor/$vname"; mkdir -p "$d"
  verified_inrelease "$base/dists/stable/InRelease" "$d/InRelease" "$kr"
  get "$base/dists/stable/main/binary-amd64/Packages" "$d/Packages"
  vendor_args+=(--vendor "$vname=$d/InRelease=$d/Packages=$base=$pkg=$ver")
done <<<"$VENDORS"

for rel in $RELEASES; do
  idx="$CACHE/$SNAPSHOT/$rel"
  for suite in "$rel" "$rel-updates" "$rel-security"; do
    mkdir -p "$idx"
    [ -s "$idx/$suite.InRelease" ] \
      || verified_inrelease "$SNAPSHOT_URL/dists/$suite/InRelease" "$idx/$suite.InRelease" "$ubuntu_kr"
    gpgv --keyring "$ubuntu_kr" "$idx/$suite.InRelease" 2>/dev/null || die "bad signature: $idx/$suite.InRelease"
    for comp in $COMPONENTS; do
      f="$idx/$suite/$comp/Packages.xz"
      mkdir -p "$(dirname "$f")"
      [ -s "$f" ] || get "$SNAPSHOT_URL/dists/$suite/$comp/binary-amd64/Packages.xz" "$f"
    done
  done
  log "resolve $rel"
  python3 "$HERE/resolve.py" --release "$rel" --index-dir "$idx" --snapshot-url "$SNAPSHOT_URL" \
    --components "$COMPONENTS" --items "$HERE/items.conf" "${vendor_args[@]}" --out "$TMPD/$rel" \
    || die "resolve failed for $rel"
  if [ "$RELOCK" = 1 ]; then
    cp "$TMPD/$rel/$rel.lock" "$LOCKDIR/$rel.lock"
    log "wrote lock/$rel.lock (review the diff)"
  elif ! cmp -s "$TMPD/$rel/$rel.lock" "$LOCKDIR/$rel.lock"; then
    diff "$LOCKDIR/$rel.lock" "$TMPD/$rel/$rel.lock" | head -20 >&2 || true
    die "resolved closure for $rel differs from lock/$rel.lock; run --relock and review"
  fi
  # Standard (non-flat) layout: apt on the laptop uses "deb [trusted=yes] file:<apt> <rel> main".
  pdir="$OUT/apt/dists/$rel/main/binary-amd64"
  mkdir -p "$pdir"
  cp "$TMPD/$rel/Packages" "$pdir/Packages"
  {
    printf 'Origin: work-kit\nLabel: work-kit 01-prereqs\nSuite: %s\nCodename: %s\n' "$rel" "$rel"
    printf 'Components: main\nArchitectures: amd64\nDescription: offline closure from %s\n' "$SNAPSHOT_URL"
    printf 'SHA256:\n %s %s main/binary-amd64/Packages\n' "$(sha256_of "$pdir/Packages")" "$(wc -c <"$pdir/Packages" | tr -d ' ')"
  } >"$OUT/apt/dists/$rel/Release"
done

# --- download .deb files (shared pool) ------------------------------------------------------
n=0
while read -r _name _ver sum _size file url _items; do
  dest="$OUT/apt/$file"
  if [ -f "$dest" ] && [ "$(sha256_of "$dest")" = "$sum" ]; then continue; fi
  mkdir -p "$(dirname "$dest")"
  get "$url" "$dest"
  got="$(sha256_of "$dest")"
  [ "$got" = "$sum" ] || { rm -f "$dest"; die "sha256 mismatch for $file (expected $sum, got $got)"; }
  n=$((n + 1))
done < <(for rel in $RELEASES; do lock_lines "$LOCKDIR/$rel.lock"; done | sort -u -k5,5)
log "downloaded $n new .deb files"

# Remove debs no lock refers to any more (after a relock).
for rel in $RELEASES; do lock_lines "$LOCKDIR/$rel.lock"; done | awk '{ print $5 }' | sort -u >"$TMPD/keep"
(cd "$OUT/apt" && find pool -type f -name '*.deb' | sort) | comm -23 - "$TMPD/keep" | while read -r f; do
  log "remove stale $f"; rm -f "$OUT/apt/$f"
done

# --- portable downloads ---------------------------------------------------------------------
while read -r sum file url; do
  dest="$OUT/$file"
  if [ -f "$dest" ] && [ "$(sha256_of "$dest")" = "$sum" ]; then continue; fi
  log "fetch $file"
  mkdir -p "$(dirname "$dest")"
  get "$url" "$dest"
  got="$(sha256_of "$dest")"
  [ "$got" = "$sum" ] || { rm -f "$dest"; die "sha256 mismatch for $file (expected $sum, got $got)"; }
done < <(lock_lines "$LOCKDIR/files.lock")

verify_all || die "verification failed after download"
log "done: $OUT ($(du -sh "$OUT" | cut -f1))"
