#!/usr/bin/env bash
# Build-host step for 16-harness-clis: fill $KIT_OFFLINE/harness-clis/ with the pinned Linux x86_64
# builds of Claude Code, Codex, opencode, Copilot CLI, Gemini CLI and pi (node_modules trees) and
# the Aider wheels for CPython 3.12. Runs on the Mac or any host with network, curl and python3
# (3.8+); gemini and pi also need npm, aider needs uv (or pip 24+), --relock of claude needs gpg.
#
# Usage: fetch.sh [--verify] [--relock] [--list] [--only NAME[,NAME]]
#   (default)  download what is missing; every file must match lock/artifacts.lock
#   --relock   re-resolve from pins.conf: read the publisher's digest, download, compare, rewrite
#              lock/ (review the diff)
#   --verify   no network: check $KIT_OFFLINE/harness-clis against the lock files
#   --list     print the locked artifacts
#   --only     limit to some of: claude codex opencode copilot gemini pi aider
#
# Hook for build/build-offline.sh: nothing to add. Its `modules` step runs every
# kit/modules/*/fetch.sh with KIT_OFFLINE set and records every new file under $KIT_OFFLINE
# (except uv, python, bin, wheels, models, vscode) in manifest.lock. Use it as
#   build/build-offline.sh --only modules            (add --update to record new versions)
# or run this script alone; it only writes below $KIT_OFFLINE/harness-clis/.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
OUT="$KIT_OFFLINE/harness-clis"
LOCKDIR="$HERE/lock"
LOCK="$LOCKDIR/artifacts.lock"
AIDER_REQ="$LOCKDIR/aider-requirements.txt"
# shellcheck source=pins.conf source-path=SCRIPTDIR
. "$HERE/pins.conf"

ALL="claude codex opencode copilot gemini pi aider"
VERIFY=0
RELOCK=0
LIST=0
ONLY="$ALL"
while [ $# -gt 0 ]; do
  case "$1" in
    --verify) VERIFY=1 ;;
    --relock) RELOCK=1 ;;
    --list) LIST=1 ;;
    --only) ONLY="$(printf '%s' "${2:?--only needs a value}" | tr ',' ' ')"; shift ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
for h in $ONLY; do
  case " $ALL " in *" $h "*) ;; *) echo "unknown harness: $h (known: $ALL)" >&2; exit 2 ;; esac
done

log() { printf '[harness-clis-fetch] %s\n' "$*"; }
die() { printf '[harness-clis-fetch] ERROR: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required for this step ($2)"; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/hc-fetch.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

lock_lines() { grep -vhE '^[[:space:]]*(#|$)' "$LOCK" 2>/dev/null || true; }
lock_for() { lock_lines | awk -v p="$1/" 'index($2, p) == 1'; }   # lock lines of one harness

pinned() { # harness -> version
  case "$1" in
    claude) echo "$CLAUDE_VERSION" ;; codex) echo "$CODEX_VERSION" ;; opencode) echo "$OPENCODE_VERSION" ;;
    copilot) echo "$COPILOT_VERSION" ;; gemini) echo "$GEMINI_VERSION" ;; pi) echo "$PI_VERSION" ;;
    aider) echo "$AIDER_VERSION" ;;
  esac
}

curl_get() { curl -fsSL --retry 3 --connect-timeout 20 "$@"; }
gh_get() { # GitHub API request; GITHUB_TOKEN (if set) only lifts the rate limit
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl_get -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" "$@"
  else
    curl_get -H "Accept: application/vnd.github+json" "$@"
  fi
}

check_elf_x86_64() { # file: ELF header, machine x86-64
  [ "$(head -c 4 "$1" | od -An -c | tr -d ' ')" = '177ELF' ] || die "$1 is not an ELF file"
  [ "$(dd if="$1" bs=1 skip=18 count=1 2>/dev/null | od -An -tx1 | tr -d ' ')" = "3e" ] \
    || die "$1 is not built for x86-64"
}

download_to() { # url dest sha256 (downloads to a temp file, verifies, moves into place)
  local url="$1" dest="$2" want="$3" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$dest.part"
  curl_get -o "$tmp" "$url" || { rm -f "$tmp"; die "download failed: $url"; }
  if [ "$(sha256_of "$tmp")" != "$want" ]; then
    rm -f "$tmp"
    die "checksum mismatch for $url (expected $want)"
  fi
  mv "$tmp" "$dest"
}

# --- publisher digests ------------------------------------------------------------------------
json_get() { # json-file python-expression-on-d
  python3 - "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
v = eval(sys.argv[2])
if v is None:
    sys.exit(1)
print(v)
PY
}

gh_digest() { # repo tag asset -> sha256 that GitHub records for the release asset
  local f="$TMPD/rel.json" d
  gh_get -o "$f" "https://api.github.com/repos/$1/releases/tags/$2" || die "cannot read release $1 $2"
  d="$(json_get "$f" "next((a['digest'] for a in d['assets'] if a['name'] == '$3'), None)")" \
    || die "release $1 $2 has no asset $3 with a digest"
  case "$d" in sha256:*) printf '%s\n' "${d#sha256:}" ;; *) die "unexpected digest for $3: $d" ;; esac
}

sums_digest() { # url asset -> sha256 from a SHA256SUMS-style file published with the release
  curl_get "$1" | awk -v n="$2" '{ f = $2; sub(/^\*/, "", f); if (f == n) { print $1; exit } }'
}

# --- per-harness specs: print "relpath|url|publisher-sha256" -----------------------------------
spec_claude() {
  local base="https://downloads.claude.ai/claude-code-releases/$CLAUDE_VERSION" fpr sum
  need gpg "verifies the signature of Anthropic's release manifest"
  # runs in a command substitution: the trap belongs to this subshell and stops gpg-agent again
  GPG_HOME="$(mktemp -d /tmp/hc-gpg.XXXXXX)"   # short path: gpg-agent sockets have a length limit
  chmod 700 "$GPG_HOME"
  trap 'GNUPGHOME="$GPG_HOME" gpgconf --kill all >/dev/null 2>&1; rm -rf "$GPG_HOME"' EXIT
  curl_get -o "$TMPD/claude-code.asc" "$CLAUDE_KEY_URL"
  curl_get -o "$TMPD/manifest.json" "$base/manifest.json"
  curl_get -o "$TMPD/manifest.json.sig" "$base/manifest.json.sig"
  GNUPGHOME="$GPG_HOME" gpg --batch --quiet --import "$TMPD/claude-code.asc" 2>/dev/null
  fpr="$(GNUPGHOME="$GPG_HOME" gpg --batch --with-colons --fingerprint | awk -F: '$1 == "fpr" { print $10; exit }')"
  [ "$fpr" = "$CLAUDE_KEY_FPR" ] || die "claude release key fingerprint is $fpr, expected $CLAUDE_KEY_FPR"
  GNUPGHOME="$GPG_HOME" gpg --batch --verify "$TMPD/manifest.json.sig" "$TMPD/manifest.json" 2>&1 \
    | grep -q '^gpg: Good signature' || die "claude manifest signature is not valid"
  [ "$(json_get "$TMPD/manifest.json" "d['version']")" = "$CLAUDE_VERSION" ] \
    || die "claude manifest is for another version than $CLAUDE_VERSION"
  sum="$(json_get "$TMPD/manifest.json" "d['platforms']['linux-x64']['checksum']")"
  echo "claude/claude-$CLAUDE_VERSION-linux-x64|$base/linux-x64/claude|$sum"
}

spec_codex() {
  local tag="rust-v$CODEX_VERSION" asset="codex-package-x86_64-unknown-linux-musl.tar.gz" a b
  a="$(gh_digest openai/codex "$tag" "$asset")"
  b="$(sums_digest "https://github.com/openai/codex/releases/download/$tag/codex-package_SHA256SUMS" "$asset")"
  [ "$a" = "$b" ] || die "codex: GitHub digest ($a) differs from codex-package_SHA256SUMS ($b)"
  echo "codex/codex-package-$CODEX_VERSION-x86_64-unknown-linux-musl.tar.gz|https://github.com/openai/codex/releases/download/$tag/$asset|$a"
}

spec_opencode() {
  local tag="v$OPENCODE_VERSION" asset="opencode-linux-x64-baseline.tar.gz"
  echo "opencode/opencode-$OPENCODE_VERSION-linux-x64-baseline.tar.gz|https://github.com/anomalyco/opencode/releases/download/$tag/$asset|$(gh_digest anomalyco/opencode "$tag" "$asset")"
}

spec_copilot() {
  local tag="v$COPILOT_VERSION" asset="copilot-linux-x64.tar.gz" a b
  a="$(gh_digest github/copilot-cli "$tag" "$asset")"
  b="$(sums_digest "https://github.com/github/copilot-cli/releases/download/$tag/SHA256SUMS.txt" "$asset")"
  [ "$a" = "$b" ] || die "copilot: GitHub digest ($a) differs from SHA256SUMS.txt ($b)"
  echo "copilot/copilot-$COPILOT_VERSION-linux-x64.tar.gz|https://github.com/github/copilot-cli/releases/download/$tag/$asset|$a"
}

# --- gemini and pi: node_modules tree from lock/<name>, packed as a reproducible tar ------------
# npm ci checks every tarball against the integrity hashes in package-lock.json (taken from the
# npm registry). The tree is packed with sorted names, mtime 0, owner 0 and no compression, so the
# same lock gives the same bytes on every host.
npm_pkg() { # harness -> npm package
  case "$1" in gemini) echo "@google/gemini-cli" ;; pi) echo "@earendil-works/pi-coding-agent" ;; esac
}
npm_rel() { # harness -> path of the packed tree under offline/harness-clis
  case "$1" in
    gemini) echo "gemini/gemini-cli-$GEMINI_VERSION-linux-x64.tar" ;;
    pi) echo "pi/pi-coding-agent-$PI_VERSION-linux-x64.tar" ;;
  esac
}
npm_entry() { # harness -> the file that starts the CLI, relative to the tree
  case "$1" in
    gemini) echo "node_modules/@google/gemini-cli/bundle/gemini.js" ;;
    pi) echo "node_modules/@earendil-works/pi-coding-agent/dist/cli.js" ;;
  esac
}

npm_add_missing_integrity() { # harness: fill `integrity` of lock entries that lack it from the registry
  # pi's shrinkwrap lists its own @earendil-works/* packages without integrity, so npm ci would not
  # check their tarballs. The registry's dist.integrity is the value `npm audit signatures` checks
  # the registry signature of.
  need npm "reads dist.integrity from the registry"
  python3 - "$LOCKDIR/$1/package-lock.json" <<'PYINT'
import json, subprocess, sys
path = sys.argv[1]
lock = json.load(open(path))
changed = 0
for key, pkg in lock["packages"].items():
    if not key or pkg.get("integrity") or "resolved" not in pkg:
        continue
    name = key.split("node_modules/")[-1]
    spec = "%s@%s" % (name, pkg["version"])
    out = subprocess.run(["npm", "view", spec, "dist.integrity"], capture_output=True, text=True, check=True).stdout.strip()
    if not out.startswith("sha512-"):
        sys.exit("no integrity from the registry for " + spec)
    pkg["integrity"] = out
    changed += 1
if changed:
    with open(path, "w") as fh:
        json.dump(lock, fh, indent=2)
        fh.write("\n")
print("integrity added to %d lock entries" % changed)
PYINT
}

npm_verify_unhashed() { # harness: installed packages that npm ci could not check against an integrity
  # A package that arrives through a dependency's npm-shrinkwrap.json is installed from that
  # shrinkwrap, whose entries may lack `integrity` (pi's own @earendil-works/* packages do). Here
  # each such package is compared with the registry's tarball: its sha512 must equal the
  # dist.integrity in the lock (filled from the registry by npm_add_missing_integrity), and the
  # installed files must equal the tarball's.
  local w="$TMPD/npm-$1"
  python3 - "$w" <<'PYVER' || die "$1: a package of the installed tree does not match its registry tarball"
import base64, hashlib, io, json, os, sys, tarfile, urllib.request
w = sys.argv[1]
root = json.load(open(os.path.join(w, "package-lock.json")))["packages"]
inst = json.load(open(os.path.join(w, "node_modules", ".package-lock.json")))["packages"]
checked = 0
for key, pkg in sorted(inst.items()):
    if pkg.get("integrity") or "resolved" not in pkg or pkg.get("link"):
        continue
    want = root.get(key, {}).get("integrity", "")
    if not want.startswith("sha512-"):
        sys.exit("no integrity in the lock for " + key)
    data = urllib.request.urlopen(pkg["resolved"], timeout=60).read()
    got = "sha512-" + base64.b64encode(hashlib.sha512(data).digest()).decode()
    if got != want:
        sys.exit("%s: tarball integrity %s, lock says %s" % (key, got, want))
    files = {}
    with tarfile.open(fileobj=io.BytesIO(data)) as tf:
        for m in tf.getmembers():
            if m.isfile():
                files[m.name.split("/", 1)[1]] = tf.extractfile(m).read()
    base = os.path.join(w, key)
    have = {}
    for d, dirs, names in os.walk(base):
        dirs[:] = [x for x in dirs if x != "node_modules"]
        for n in names:
            full = os.path.join(d, n)
            have[os.path.relpath(full, base)] = open(full, "rb").read()
    if have != files:
        diff = sorted(set(have) ^ set(files)) or [n for n in files if have[n] != files[n]]
        sys.exit("%s: installed files differ from the registry tarball: %s" % (key, ", ".join(diff[:5])))
    checked += 1
print("%d packages without lock integrity match their registry tarballs" % checked)
PYVER
}

build_npm_tar() { # harness dest
  local h="$1" w="$TMPD/npm-$1" dest="$2"
  need npm "installs the locked dependency tree of $(npm_pkg "$h")"
  need python3 "packs the tree"
  rm -rf "$w" && mkdir -p "$w"
  cp "$LOCKDIR/$h/package.json" "$LOCKDIR/$h/package-lock.json" "$w/"
  (cd "$w" && npm ci --os=linux --cpu=x64 --libc=glibc --ignore-scripts --omit=dev --no-audit --no-fund --loglevel=error) \
    || die "npm ci failed (registry unreachable or lock/$h out of date?)"
  [ -f "$w/$(npm_entry "$h")" ] || die "$h: $(npm_entry "$h") missing after npm ci"
  npm_verify_unhashed "$h"
  if [ "$h" = gemini ]; then
    [ -f "$w/node_modules/@lydell/node-pty-linux-x64/package.json" ] || die "linux-x64 pty package missing after npm ci"
  fi
  if [ "$h" = pi ]; then
    # the shrinkwrap of pi lists esbuild with every platform binary (12 MB each, 284 MB in all);
    # nothing in pi's dist/ uses esbuild, so only the linux-x64 one is kept
    find "$w/node_modules" -type d -name '@esbuild' -prune -print | while read -r d; do
      find "$d" -mindepth 1 -maxdepth 1 -type d ! -name linux-x64 -exec rm -rf {} +
    done
  fi
  python3 - "$w" "$dest.part" <<'PY'
import os, sys, tarfile
root, dest = sys.argv[1], sys.argv[2]
skip = {os.path.join("node_modules", ".package-lock.json")}
names = []
for base, dirs, files in os.walk(os.path.join(root, "node_modules")):
    dirs.sort()
    rel = os.path.relpath(base, root)
    names.append(rel)
    for f in sorted(files):
        p = os.path.join(rel, f)
        if p not in skip:
            names.append(p)
    for d in list(dirs):
        if os.path.islink(os.path.join(base, d)):
            names.append(os.path.join(rel, d))
            dirs.remove(d)
names.sort()
with tarfile.open(dest, "w", format=tarfile.GNU_FORMAT) as tf:
    for n in names:
        full = os.path.join(root, n)
        ti = tarfile.TarInfo(n)
        ti.mtime, ti.uid, ti.gid, ti.uname, ti.gname = 0, 0, 0, "", ""
        if os.path.islink(full):
            ti.type, ti.linkname, ti.mode = tarfile.SYMTYPE, os.readlink(full), 0o777
            tf.addfile(ti)
        elif os.path.isdir(full):
            ti.type, ti.mode = tarfile.DIRTYPE, 0o755
            tf.addfile(ti)
        else:
            ti.size = os.path.getsize(full)
            ti.mode = 0o755 if os.stat(full).st_mode & 0o111 else 0o644
            with open(full, "rb") as fh:
                tf.addfile(ti, fh)
PY
  mv "$dest.part" "$dest"
}

npm_verify_signatures() { # harness: registry signatures and provenance of the locked packages
  local w="$TMPD/npm-$1"
  [ "${HC_SKIP_NPM_SIGNATURES:-0}" = 1 ] && return 0
  (cd "$w" && npm audit signatures --loglevel=error >"$TMPD/sig.out" 2>&1) \
    || { cat "$TMPD/sig.out" >&2; die "npm audit signatures failed for the locked $1 tree"; }
  sed -n '1,4p' "$TMPD/sig.out"
}

# --- aider: hashed requirements, wheels for cp312 manylinux ------------------------------------
aider_pip() {
  local plat=() p
  for p in manylinux_2_28_x86_64 manylinux_2_17_x86_64 manylinux2014_x86_64 manylinux_2_5_x86_64 manylinux1_x86_64 linux_x86_64; do
    plat+=(--platform "$p")
  done
  local args=(download --quiet --no-deps --require-hashes --only-binary=:all: --python-version "$AIDER_PYTHON"
    --implementation cp --abi "cp${AIDER_PYTHON/./}" --abi abi3 --abi none "${plat[@]}" -r "$AIDER_REQ" -d "$1")
  if command -v uv >/dev/null 2>&1; then uv tool run --from 'pip>=24.2' pip "${args[@]}"
  else python3 -m pip "${args[@]}"; fi
}

count_wheels() { [ -d "$1" ] && find "$1" -maxdepth 1 -name '*.whl' | wc -l | tr -d ' ' || echo 0; }

aider_expected() { # number of pinned distributions
  grep -cE '^[A-Za-z0-9][A-Za-z0-9._-]*==' "$AIDER_REQ" || true
}

aider_fetch() {
  local dest="$OUT/aider/wheels" stage="$TMPD/aider-wheels" n want
  [ -f "$AIDER_REQ" ] || die "$AIDER_REQ missing (run --relock --only aider)"
  want="$(aider_expected)"
  n="$(count_wheels "$dest")"
  if [ "$n" = "$want" ] && aider_verify_quiet; then log "aider: $n wheels already present"; return 0; fi
  need python3 "pip download"
  mkdir -p "$stage"
  aider_pip "$stage" || die "pip download failed (a dependency without a cp312 manylinux wheel?)"
  n="$(count_wheels "$stage")"
  [ "$n" = "$want" ] || die "aider: downloaded $n wheels, lock names $want distributions"
  rm -rf "$dest" && mkdir -p "$(dirname "$dest")"
  mv "$stage" "$dest"
  log "aider: $n wheels ($(du -sh "$dest" | cut -f1))"
}

aider_verify_quiet() { # the wheels in the dir are exactly the pinned name==version set
  python3 - "$AIDER_REQ" "$OUT/aider/wheels" <<'PY'
import os, re, sys
norm = lambda n: re.sub(r"[-_.]+", "-", n).lower()
want = set()
for line in open(sys.argv[1]):
    m = re.match(r"^([A-Za-z0-9][A-Za-z0-9._-]*)==(\S+)", line)
    if m:
        want.add((norm(m.group(1)), m.group(2)))
have = set()
for f in os.listdir(sys.argv[2]) if os.path.isdir(sys.argv[2]) else []:
    if f.endswith(".whl"):
        p = f.split("-")
        have.add((norm(p[0]), p[1]))
sys.exit(0 if have == want and want else 1)
PY
}

# --- modes ------------------------------------------------------------------------------------
do_list() {
  lock_lines | while read -r sum path url; do printf '%s  %s\n    %s\n' "$sum" "$path" "$url"; done
  [ -f "$AIDER_REQ" ] && printf 'aider: %s pinned distributions in lock/aider-requirements.txt\n' "$(aider_expected)"
  return 0
}

do_verify() {
  local bad=0 h path sum have
  for h in $ONLY; do
    case "$h" in
      aider)
        if [ -d "$OUT/aider/wheels" ] && [ "$(count_wheels "$OUT/aider/wheels")" = "$(aider_expected)" ] \
           && aider_verify_quiet; then echo "ok       aider wheels"
        else echo "MISSING  aider/wheels (count or names differ from the lock)"; bad=1; fi ;;
      *)
        [ -n "$(lock_for "$h")" ] || { echo "NOLOCK   $h"; bad=1; continue; }
        while read -r sum path _; do
          if [ ! -f "$OUT/$path" ]; then echo "MISSING  $path"; bad=1
          else
            have="$(sha256_of "$OUT/$path")"
            if [ "$have" = "$sum" ]; then echo "ok       $path"; else echo "MISMATCH $path"; bad=1; fi
          fi
        done < <(lock_for "$h")
        ;;
    esac
  done
  return "$bad"
}

do_fetch() {
  local h sum path url
  for h in $ONLY; do
    log "$h $(pinned "$h")"
    case "$h" in
      aider) aider_fetch ;;
      gemini|pi)
        read -r sum path _ <<<"$(lock_for "$h")"
        [ -n "${path:-}" ] || die "$h is not in lock/artifacts.lock (run --relock --only $h)"
        case "$path" in *"-$(pinned "$h")-"*) ;; *) die "$h: lock names $path but pins.conf pins $(pinned "$h") (run --relock)" ;; esac
        if [ -f "$OUT/$path" ] && [ "$(sha256_of "$OUT/$path")" = "$sum" ]; then log "$path already present"; continue; fi
        mkdir -p "$OUT/$h"
        build_npm_tar "$h" "$OUT/$path"
        [ "$(sha256_of "$OUT/$path")" = "$sum" ] \
          || { rm -f "$OUT/$path"; die "$h tree differs from the lock (npm/registry change?): $path; --relock reviews it"; }
        ;;
      *)
        read -r sum path url <<<"$(lock_for "$h")"
        [ -n "${path:-}" ] || die "$h is not in lock/artifacts.lock (run --relock --only $h)"
        case "$path" in *"-$(pinned "$h")-"*) ;; *) die "$h: lock names $path but pins.conf pins $(pinned "$h") (run --relock)" ;; esac
        if [ -f "$OUT/$path" ] && [ "$(sha256_of "$OUT/$path")" = "$sum" ]; then log "$path already present"; continue; fi
        log "downloading $url"
        download_to "$url" "$OUT/$path" "$sum"
        [ "$h" = claude ] && check_elf_x86_64 "$OUT/$path"
        chmod 0644 "$OUT/$path"
        ;;
    esac
  done
}

lock_header() {
  cat <<'E'
# 16-harness-clis pinned downloads: sha256  path-under-offline/harness-clis  source
# Written by `fetch.sh --relock`. Every sha256 equals the publisher's own digest, read at relock
# time (docs/harness-clis.md lists where): claude = GPG-signed manifest.json, codex and copilot =
# GitHub asset digest and the release's SHA256SUMS file, opencode = GitHub asset digest.
# The gemini and pi lines are the packed node_modules trees of lock/gemini and lock/pi (npm ci,
# integrity from the registry). Aider wheels are pinned with hashes in aider-requirements.txt.
E
}

do_relock() {
  local h spec rel url pub tmp sum new="$TMPD/new.lock" keep="$TMPD/keep.lock"
  need python3 "parses the publishers' metadata"
  : >"$new"
  for h in $ONLY; do
    log "relock $h $(pinned "$h")"
    case "$h" in
      aider)
        need uv "resolves the wheel set (uv pip compile)"
        echo "aider-chat==$AIDER_VERSION" >"$TMPD/aider.in"
        uv pip compile "$TMPD/aider.in" --python-platform x86_64-manylinux_2_28 --python-version "$AIDER_PYTHON" \
          --generate-hashes --no-build --no-header --no-annotate -o "$TMPD/aider-body.txt" >/dev/null 2>"$TMPD/uv.err" \
          || { cat "$TMPD/uv.err" >&2; die "cannot resolve aider-chat==$AIDER_VERSION"; }
        {
          echo "# aider-chat $AIDER_VERSION for CPython $AIDER_PYTHON on manylinux x86_64, wheels only. Written by fetch.sh --relock from:"
          echo "# uv pip compile --python-platform x86_64-manylinux_2_28 --python-version $AIDER_PYTHON --generate-hashes --no-build"
          cat "$TMPD/aider-body.txt"
        } >"$TMPD/aider-req.new"
        mkdir -p "$LOCKDIR" && mv "$TMPD/aider-req.new" "$AIDER_REQ"
        rm -rf "$OUT/aider/wheels"
        aider_fetch
        ;;
      gemini|pi)
        mkdir -p "$LOCKDIR/$h" "$OUT/$h"
        printf '{\n  "name": "work-kit-%s",\n  "version": "0.0.0",\n  "private": true,\n  "dependencies": {\n    "%s": "%s"\n  }\n}\n' \
          "$h" "$(npm_pkg "$h")" "$(pinned "$h")" >"$LOCKDIR/$h/package.json"
        rm -f "$LOCKDIR/$h/package-lock.json"
        need npm "resolves the $h tree"
        (cd "$LOCKDIR/$h" && npm install --package-lock-only --os=linux --cpu=x64 --libc=glibc --ignore-scripts --no-audit --no-fund --loglevel=error) \
          || die "npm could not resolve $(npm_pkg "$h")@$(pinned "$h")"
        npm_add_missing_integrity "$h"
        rel="$(npm_rel "$h")"
        build_npm_tar "$h" "$OUT/$rel"
        npm_verify_signatures "$h"
        echo "$(sha256_of "$OUT/$rel")  $rel  npm-ci:lock/$h" >>"$new"
        ;;
      *)
        spec="$(spec_"$h")" || die "$h: cannot resolve the publisher's digest"
        rel="${spec%%|*}"; spec="${spec#*|}"; url="${spec%%|*}"; pub="${spec#*|}"
        [ "${#pub}" = 64 ] || die "$h: publisher digest '$pub' is not a sha256"
        tmp="$TMPD/dl-$h"
        log "downloading $url"
        curl_get -o "$tmp" "$url" || die "download failed: $url"
        sum="$(sha256_of "$tmp")"
        [ "$sum" = "$pub" ] || die "$h: downloaded file has sha256 $sum, the publisher says $pub"
        [ "$h" = claude ] && check_elf_x86_64 "$tmp"
        mkdir -p "$OUT/$(dirname "$rel")"
        rm -f "$OUT/$(dirname "$rel")"/*.part
        mv "$tmp" "$OUT/$rel" && chmod 0644 "$OUT/$rel"
        echo "$sum  $rel  $url" >>"$new"
        ;;
    esac
  done
  # keep the lines of harnesses that were not relocked
  : >"$keep"
  for h in $ALL; do
    case " $ONLY " in *" $h "*) continue ;; esac
    lock_for "$h" >>"$keep"
  done
  mkdir -p "$LOCKDIR"
  { lock_header; cat "$keep" "$new" | sort -k2,2; } >"$LOCK.tmp" && mv "$LOCK.tmp" "$LOCK"
  log "wrote $LOCK; review the diff of lock/"
}

[ "$LIST" = 1 ] && { do_list; exit 0; }
[ "$VERIFY" = 1 ] && { do_verify; exit $?; }
mkdir -p "$OUT"
if [ "$RELOCK" = 1 ]; then do_relock; else do_fetch; fi
log "done: $OUT"
