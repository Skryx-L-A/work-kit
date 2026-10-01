#!/usr/bin/env bash
# Module 11-legacy-toolbox, build host step: download the pinned offline artifacts for
# Linux x86_64 into $KIT_OFFLINE/legacy-toolbox/. Needs network, curl, python3, uv.
#
# Usage: fetch.sh [--verify] [--list] [--no-semgrep-rules]
#   (default)            download what is missing, check every file against the sha256 below
#   --verify             no network: re-check files already in the offline directory
#   --list               print the pinned artifacts and exit
#   --no-semgrep-rules   skip the semgrep rule pack (its licence is not OSI-approved, see README)
#
# Environment: KIT_OFFLINE (default: <kit>/offline). Downloads go straight to the offline directory.
#
# Hook for build/build-offline.sh (that script is not edited by this module). Add a step
# next to step_model and record the fetched files the same way:
#
#   step_legacy() {
#     local script="$ROOT/kit/modules/11-legacy-toolbox/fetch.sh" f rel
#     KIT_OFFLINE="$OFFLINE" bash "$script" || die "11-legacy-toolbox/fetch.sh failed"
#     while IFS= read -r f; do
#       rel="${f#"$OFFLINE"/}"
#       check_or_record "file:$rel" "$(sha256_of "$f")" "11-legacy-toolbox/fetch.sh"
#     done < <(find "$OFFLINE/legacy-toolbox" -type f | sort)
#   }
#   ... want legacy && step_legacy      (and add "legacy" to the default ONLY list)
#   ... in the manifest merge:  file:legacy-toolbox/*) want legacy || echo "$sum  $key  $rest" >>"$NEW" ;;
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
OUT="$KIT_OFFLINE/legacy-toolbox"

PIP_SPEC="pip>=24.2"
PYTHON_SERIES="3.12"

# --- pinned artifacts ---------------------------------------------------------------------
# path under $OUT | url | sha256
# Upstream digests were read from the GitHub release API (or measured, for source archives)
# on 2026-09-25. Grammars are source archives; install.sh compiles them on the laptop.
# tree-sitter >= 0.26 needs glibc 2.39; v0.25.10 (glibc 2.34) is the fallback for Ubuntu 22.04.
ARTIFACTS='
bin/uctags-2026.09.23-linux-x86_64.release.tar.gz|https://github.com/universal-ctags/ctags-nightly-build/releases/download/2026.09.23%2B99b7257c979ea82fb0f3ef911e7cee347d230392/uctags-2026.09.23-linux-x86_64.release.tar.gz|3626d1cff0ecd9b7327d75d0aeadba9c342fc98cfda65076b823972b1a31ad65
bin/scc_Linux_x86_64.tar.gz|https://github.com/boyter/scc/releases/download/v4.1.0/scc_Linux_x86_64.tar.gz|c7328436d3027f4357d3d7853f7dc3ac2bbcb4ca08f1adad91a27c593884079b
bin/tree-sitter-linux-x64.gz|https://github.com/tree-sitter/tree-sitter/releases/download/v0.27.0/tree-sitter-linux-x64.gz|20a1f39ec1c45f2211492dcb8881c802b643b554bb196869a29ac3778277fa77
bin/glibc-2.34/tree-sitter-linux-x64.gz|https://github.com/tree-sitter/tree-sitter/releases/download/v0.25.10/tree-sitter-linux-x64.gz|8283ddba69253c698f6e987ba0e2f9285e079c8db4d36ebe1394b5bb3a0ebdfd
grammars/tree-sitter-java-v0.23.5.tar.gz|https://github.com/tree-sitter/tree-sitter-java/archive/refs/tags/v0.23.5.tar.gz|cb199e0faae4b2c08425f88cbb51c1a9319612e7b96315a174a624db9bf3d9f0
grammars/tree-sitter-c-sharp-v0.23.5.tar.gz|https://github.com/tree-sitter/tree-sitter-c-sharp/archive/refs/tags/v0.23.5.tar.gz|9628b164369071019368618bdefa446f0aab8acaac47b75d5dfb209e93b8903b
grammars/tree-sitter-c-v0.24.2.tar.gz|https://github.com/tree-sitter/tree-sitter-c/archive/refs/tags/v0.24.2.tar.gz|2eeb4db31f8fa0865e45488503d13403923bcb485a1bdb637abff8c42dd97364
grammars/tree-sitter-cpp-v0.23.4.tar.gz|https://github.com/tree-sitter/tree-sitter-cpp/archive/refs/tags/v0.23.4.tar.gz|7a2c55afe3028f4105f25762ea58cc16537d1f5a1dcd9cca90410b3cd5d46051
grammars/tree-sitter-python-v0.25.0.tar.gz|https://github.com/tree-sitter/tree-sitter-python/archive/refs/tags/v0.25.0.tar.gz|4609a3665a620e117acf795ff01b9e965880f81745f287a16336f4ca86cf270c
grammars/tree-sitter-javascript-v0.25.0.tar.gz|https://github.com/tree-sitter/tree-sitter-javascript/archive/refs/tags/v0.25.0.tar.gz|9712fc283d3dc01d996d20b6392143445d05867a7aad76fdd723824468428b86
grammars/tree-sitter-typescript-v0.23.2.tar.gz|https://github.com/tree-sitter/tree-sitter-typescript/archive/refs/tags/v0.23.2.tar.gz|2c4ce711ae8d1218a3b2f899189298159d672870b5b34dff5d937bed2f3e8983
grammars/tree-sitter-sql-v0.3.11.tar.gz|https://github.com/DerekStride/tree-sitter-sql/releases/download/v0.3.11/tree-sitter-sql-v0.3.11.tar.gz|a97a324eae9c81ed68f6e162b9b33f8911fc6442caa2950e57c498e2460d1387
grammars/tree-sitter-cobol-0.1.1.tar.gz|https://github.com/yutaro-sakamoto/tree-sitter-cobol/archive/refs/tags/0.1.1.tar.gz|c5fce60965584eb8dbcea65d0186a8c776ac12f304914c5aac7053fcc686de2e
'
# semgrep rule pack (Semgrep Rules License v1.0), pinned commit of semgrep/semgrep-rules
RULES_ARTIFACT='semgrep/semgrep-rules-a84ff9cc.tar.gz|https://github.com/semgrep/semgrep-rules/archive/a84ff9cc2453ca91d581380de4b8b3f272f6f4be.tar.gz|b227c2d234ffd9c84c4dbd6619a5897a7192637c141baeace3bfc37b0715a887'
# semgrep itself: wheels pinned with hashes in requirements-semgrep.txt (semgrep 1.178.0,
# regenerate with: uv pip compile <(echo semgrep==X) --python-platform x86_64-manylinux_2_34
#   --python-version 3.12 --generate-hashes --no-build --no-header --no-annotate)
REQ="$HERE/requirements-semgrep.txt"
WHEELS="$OUT/semgrep/wheels"
PIP_PLATFORMS=(manylinux_2_34_x86_64 manylinux_2_28_x86_64 manylinux_2_17_x86_64
               manylinux2014_x86_64 manylinux_2_5_x86_64 manylinux1_x86_64 linux_x86_64)

VERIFY=0
LIST=0
RULES=1
for a in "$@"; do
  case "$a" in
    --verify) VERIFY=1 ;;
    --list) LIST=1 ;;
    --no-semgrep-rules) RULES=0 ;;
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

log() { printf '[legacy-toolbox fetch] %s\n' "$*"; }
die() { printf '[legacy-toolbox fetch] ERROR: %s\n' "$*" >&2; exit 1; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

entries() {
  printf '%s\n' "$ARTIFACTS"
  [ "$RULES" = 1 ] && printf '%s\n' "$RULES_ARTIFACT"
  return 0
}

if [ "$LIST" = 1 ]; then
  entries | while IFS='|' read -r path url sha; do
    [ -n "$path" ] && printf '%s  %s\n    %s\n' "$sha" "$path" "$url"
  done
  grep -cE '^[A-Za-z0-9]' "$REQ" | sed 's/^/python wheels pinned with hashes in requirements-semgrep.txt: /'
  exit 0
fi

check_wheels() { # every file in $WHEELS must carry a hash listed in requirements-semgrep.txt
  python3 - "$REQ" "$WHEELS" <<'PY'
import hashlib, os, re, sys
req, wheels = sys.argv[1], sys.argv[2]
want = set(re.findall(r"--hash=sha256:([0-9a-f]{64})", open(req).read()))
names = re.findall(r"^([A-Za-z0-9][A-Za-z0-9._-]*)==", open(req).read(), re.M)
files = [f for f in os.listdir(wheels) if f.endswith(".whl")] if os.path.isdir(wheels) else []
bad = 0
for f in files:
    h = hashlib.sha256(open(os.path.join(wheels, f), "rb").read()).hexdigest()
    if h not in want:
        print("UNPINNED wheel:", f); bad = 1
if len(files) != len(names):
    print(f"wheel count {len(files)} != pinned packages {len(names)}"); bad = 1
sys.exit(bad)
PY
}

if [ "$VERIFY" = 1 ]; then
  bad=0
  while IFS='|' read -r path url sha; do
    [ -n "$path" ] || continue
    f="$OUT/$path"
    if [ ! -f "$f" ]; then echo "MISSING  $path"; bad=1
    elif [ "$(sha256_of "$f")" != "$sha" ]; then echo "MISMATCH $path"; bad=1; fi
  done < <(entries)
  check_wheels || bad=1
  [ "$bad" = 0 ] && echo "legacy-toolbox artifacts match the pins" && exit 0
  exit 1
fi

for t in curl python3 uv; do command -v "$t" >/dev/null 2>&1 || die "$t is required on the build host"; done
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
done < <(entries)

log "semgrep wheels (linux x86_64, Python $PYTHON_SERIES)"
mkdir -p "$WHEELS"
plat_args=()
for p in "${PIP_PLATFORMS[@]}"; do plat_args+=(--platform "$p"); done
uv tool run --from "$PIP_SPEC" pip download --quiet --no-deps --require-hashes \
  --only-binary=:all: --python-version "$PYTHON_SERIES" --implementation cp \
  --abi "cp${PYTHON_SERIES/./}" --abi abi3 --abi none "${plat_args[@]}" \
  -r "$REQ" -d "$WHEELS" || die "pip download failed"
check_wheels || die "wheel set does not match requirements-semgrep.txt"
log "done: $OUT ($(du -sh "$OUT" | awk '{print $1}'))"
