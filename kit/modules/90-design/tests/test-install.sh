#!/usr/bin/env bash
# Installer test in a scratch HOME. Reference folders always; the kit-design CLI only when a
# wheel cache is given (KIT_OFFLINE=<dir with wheels/>) or TEST_BUILD_WHEELS=1 (builds one for
# this host, needs network once). Runs on any host with bash and uv.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# keep the host uv Python visible (00-python installs it on the laptop)
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-$(uv python dir)}"
export HOME="$W/home" KIT_BIN_DIR="$W/home/.local/bin" KIT_DATA_DIR="$W/home/.local/share/work-kit"
export UV_CACHE_DIR="${UV_CACHE_DIR:-$W/uv-cache}"
mkdir -p "$HOME"
R="$HOME/work/design-refs"

bash "$MOD/install.sh" --refs-only >/dev/null || bad "refs-only exits 0"
for c in brand web slides documents diagrams; do check "folder $c with README" "[ -f '$R/$c/README.md' ]"; done

echo "my logo" >"$R/brand/logo.svg"
echo "edited" >"$R/slides/README.md"
bash "$MOD/install.sh" --refs-only >/dev/null
check "own file kept" "grep -q 'my logo' '$R/brand/logo.svg'"
BAKS="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/backups/90-design"
check "edited README backed up under backups/" "grep -q edited '$BAKS'/slides/README.md.bak-*"
check "backup records the original path" "grep -qx '$R/slides/README.md' '$BAKS'/slides/README.md.bak-*.origin"
check "no backup beside the original" "! ls '$R/slides' | grep -q 'bak-'"
check "README restored" "cmp -s '$MOD/refs/slides/README.md' '$R/slides/README.md'"
# shellcheck disable=SC2034  # read inside eval
out="$(bash "$MOD/install.sh" --refs-only 2>&1)"
check "rerun makes no new backup" "[ \"\$(ls '$BAKS/slides' | grep -c 'bak-[0-9]*$')\" = 1 ] && ! grep -q backup <<<\"\$out\""

if [ "${TEST_BUILD_WHEELS:-0}" = 1 ] && [ -z "${KIT_OFFLINE:-}" ]; then
  export KIT_OFFLINE="$W/offline"
  mkdir -p "$KIT_OFFLINE/wheels"
  uv build -q --wheel --out-dir "$KIT_OFFLINE/wheels" "$MOD"
  uv tool run --from 'pip>=24.2' pip download -q --only-binary=:all: -d "$KIT_OFFLINE/wheels" \
    'python-pptx>=1.0' 'markdown>=3.5'
fi
if [ -n "${KIT_OFFLINE:-}" ] && [ -d "$KIT_OFFLINE/wheels" ]; then
  bash "$MOD/install.sh" >"$W/install.log" 2>&1 || { cat "$W/install.log"; bad "full install exits 0"; }
  check "kit-design runs" "'$KIT_BIN_DIR/kit-design' --version | grep -q '^0\\.'"
  "$KIT_BIN_DIR/kit-design" new deck "$W/deck" >/dev/null
  check "sample deck builds" "'$KIT_BIN_DIR/kit-design' deck '$W/deck/deck.md' >/dev/null 2>&1 && [ -s '$W/deck/deck.pptx' ] && [ -s '$W/deck/deck.html' ]"
  bash "$MOD/uninstall.sh" >/dev/null
  check "kit-design removed" "[ ! -e '$KIT_BIN_DIR/kit-design' ]"
else
  echo "skip CLI install (no KIT_OFFLINE wheels; set TEST_BUILD_WHEELS=1 to build them)"
  bash "$MOD/uninstall.sh" >/dev/null
fi
check "folder with own file kept" "[ -f '$R/brand/logo.svg' ]"
check "empty folder removed" "[ ! -d '$R/web' ]"
exit "$fail"
