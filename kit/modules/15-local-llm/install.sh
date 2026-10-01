#!/usr/bin/env bash
# Install llama.cpp (CPU build) and GGUF models from kit/offline/local-llm, plus the kit-llm CLI.
# No network, no sudo. Re-running is safe.
#
# Usage: install.sh [--models ID[,ID]|--all|--no-models]
#   (default)   every model marked "default" in models.conf that is present in kit/offline
#   --models    only these catalog ids;  --all  every model present;  --no-models  engine + CLI only
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$HERE/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
BIN_DIR="${KIT_BIN_DIR:-$HOME/.local/bin}"
DATA_DIR="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}"
LLM_HOME="${KIT_LLM_HOME:-$DATA_DIR/local-llm}"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/work-kit"
SRC="$KIT_OFFLINE/local-llm"
CATALOG="${KIT_LLM_CATALOG:-$HERE/models.conf}"

log() { printf '[local-llm] %s\n' "$*"; }
die() { printf '[local-llm] ERROR: %s\n' "$*" >&2; exit 1; }

SELECT=""
MODE=default
while [ $# -gt 0 ]; do
  case "$1" in
    --models) SELECT="${2:?--models needs ids}"; MODE=select; shift ;;
    --all) MODE=all ;;
    --no-models) MODE=none ;;
    -h|--help) awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# backup FILE: move it to <data dir>/backups/15-local-llm/<name>.bak-<timestamp>, original path
# recorded in <name>.bak-<timestamp>.origin; nothing is left beside the original.
backup() {
  local f="$1" b dir
  [ -e "$f" ] || [ -L "$f" ] || return 0
  dir="$DATA_DIR/backups/15-local-llm"
  mkdir -p "$dir"
  b="$dir/$(basename "$f").bak-$(date +%Y%m%d%H%M%S)"
  while [ -e "$b" ]; do b="$b-1"; done
  mv "$f" "$b" || return 1
  printf '%s\n' "$f" >"$b.origin"
  log "backup: $f -> $b"
}

[ -d "$SRC" ] || die "missing $SRC (run fetch.sh on the build host; kit/offline is incomplete)"

# --- engine -------------------------------------------------------------------------------
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) plat=ubuntu-x64 ;;
  Darwin-arm64) plat=macos-arm64 ;;   # development hosts only (fetch.sh --dev-mac)
  *) die "unsupported platform $(uname -s)-$(uname -m) (needs Linux x86_64)" ;;
esac
archive="$(find "$SRC/engine" -maxdepth 1 -name "llama-*-bin-$plat.tar.gz" 2>/dev/null | sort | tail -n 1)"
[ -n "$archive" ] || die "no llama.cpp build for $plat in $SRC/engine"
build="$(basename "$archive" | sed -E 's/^llama-([^-]+)-bin-.*/\1/')"
mkdir -p "$LLM_HOME/engine" "$LLM_HOME/models" "$LLM_HOME/logs" "$LLM_HOME/run" "$BIN_DIR"
if [ -x "$LLM_HOME/engine/llama-$build/llama-server" ]; then
  log "engine llama.cpp $build up to date"
else
  tmp="$(mktemp -d "$LLM_HOME/engine/.extract.XXXXXX")"
  tar -xzf "$archive" -C "$tmp"
  [ -x "$tmp/llama-$build/llama-server" ] || { rm -rf "$tmp"; die "archive has no llama-$build/llama-server"; }
  rm -rf "$LLM_HOME/engine/llama-$build"
  mv "$tmp/llama-$build" "$LLM_HOME/engine/llama-$build"
  rmdir "$tmp"
  log "engine llama.cpp $build -> $LLM_HOME/engine/llama-$build"
fi
ln -sfn "llama-$build" "$LLM_HOME/engine/current"

# KIT_LLM_FORCE_LIBCHECK=1 runs the library check on any host (tests use it with an ldd shim).
if [ "$plat" = ubuntu-x64 ] || [ -n "${KIT_LLM_FORCE_LIBCHECK:-}" ]; then
  grep -qw avx2 /proc/cpuinfo 2>/dev/null || log "WARNING: CPU reports no AVX2; inference will be slow"
  if command -v ldd >/dev/null 2>&1; then
    # ldd exits 1 for a binary that is not a dynamic ELF ("not a dynamic executable"): that means
    # no missing libraries, not a failure, so its status must not reach set -e / pipefail.
    engine_missing() {
      local out
      out="$(ldd "$LLM_HOME/engine/current/llama-server" 2>&1)" || true
      printf '%s\n' "$out" | awk '/not found/ { print $1 }' | tr '\n' ' '
    }
    missing="$(engine_missing)"
    gomp_deb="$(find "$SRC/engine" -maxdepth 1 -name 'libgomp1_*_amd64.deb' 2>/dev/null | sort | tail -n 1)"
    case " $missing " in
      *" libgomp.so.1 "*)
        # Minimal systems lack the OpenMP runtime: put the kit's copy next to the engine
        # (the engine's RUNPATH is $ORIGIN), never into a system path.
        if [ -n "$gomp_deb" ] && command -v dpkg-deb >/dev/null 2>&1; then
          tmp="$(mktemp -d)"
          dpkg-deb -x "$gomp_deb" "$tmp"
          cp -P "$tmp"/usr/lib/x86_64-linux-gnu/libgomp.so.1* "$LLM_HOME/engine/current/"
          rm -rf "$tmp"
          log "libgomp.so.1 not on this system: kit copy placed next to the engine"
          missing="$(engine_missing)"
        fi ;;
    esac
    [ -z "$missing" ] || log "WARNING: missing system libraries: $missing (ask IT for the Ubuntu packages that provide them, e.g. libgomp1, libssl3 / libssl3t64)"
  fi
fi

# --- models -------------------------------------------------------------------------------
cp "$CATALOG" "$LLM_HOME/models.conf"
installed=0
while IFS='|' read -r id _repo _rev file sha bytes _lic _params ship _args; do
  case "$id" in ''|'#'*) continue ;; esac
  case "$MODE" in
    none) continue ;;
    default) [ "$ship" = default ] || continue ;;
    select) case ",$SELECT," in *",$id,"*) ;; *) continue ;; esac ;;
  esac
  src="$SRC/models/$file"
  dst="$LLM_HOME/models/$file"
  if [ ! -f "$src" ]; then
    [ "$MODE" = select ] && die "model $id not in kit/offline ($src); fetch it with: fetch.sh --models $id"
    log "skip $id (not in kit/offline)"
    continue
  fi
  if [ -f "$dst" ] && [ "$(sha256_of "$dst")" = "$sha" ]; then
    log "model $id up to date"
  else
    free_kb="$(df -Pk "$LLM_HOME/models" | awk 'NR == 2 { print $4 }')"
    [ "$free_kb" -gt $((bytes / 1024 + 1048576)) ] || die "not enough disk space for $id ($((bytes / 1048576)) MB + 1 GB margin)"
    log "copy model $id ($((bytes / 1048576)) MB)"
    cp "$src" "$dst.part"
    [ "$(sha256_of "$dst.part")" = "$sha" ] || { rm -f "$dst.part"; die "sha256 mismatch for $file"; }
    mv "$dst.part" "$dst"
  fi
  installed=$((installed + 1))
done <"$CATALOG"
if [ "$MODE" = select ]; then
  for want in ${SELECT//,/ }; do
    grep -q "^$want|" "$CATALOG" || die "unknown model id: $want"
  done
fi

# --- CLI and config -----------------------------------------------------------------------
dst="$BIN_DIR/kit-llm"
if [ -f "$dst" ] && cmp -s "$HERE/kit-llm" "$dst"; then
  log "kit-llm up to date"
else
  [ -e "$dst" ] && ! grep -q '^# kit-llm: run a local GGUF model' "$dst" 2>/dev/null && backup "$dst"
  install -m 0755 "$HERE/kit-llm" "$dst"
  log "installed $dst"
fi
mkdir -p "$CONF_DIR"
if [ ! -f "$CONF_DIR/local-llm.conf" ]; then
  :
fi
default_conf="$(mktemp)"
trap 'rm -f "$default_conf"' EXIT
cat >"$default_conf" <<'EOF'
# kit-llm settings (KEY=value, environment variables win). Remove the # to change a value.
# KIT_LLM_MODEL=qwen3.5-4b
# KIT_LLM_PORT=8080
# KIT_LLM_CTX=4096
# KIT_LLM_THREADS=
# KIT_LLM_RESERVE_MB=1024
EOF
state="$LLM_HOME/local-llm.conf.kit-sha256"
old="$(cat "$state" 2>/dev/null || true)"
if [ ! -e "$CONF_DIR/local-llm.conf" ]; then
  mv "$default_conf" "$CONF_DIR/local-llm.conf"; sha256_of "$CONF_DIR/local-llm.conf" >"$state"; log "wrote $CONF_DIR/local-llm.conf"
elif [ -n "$old" ] && [ "$(sha256_of "$CONF_DIR/local-llm.conf")" = "$old" ]; then
  mv "$default_conf" "$CONF_DIR/local-llm.conf"; sha256_of "$CONF_DIR/local-llm.conf" >"$state"; log "refreshed $CONF_DIR/local-llm.conf (kit default)"
elif [ -n "$old" ]; then
  mv "$default_conf" "$CONF_DIR/local-llm.conf.kit-new"; log "kept your $CONF_DIR/local-llm.conf; new kit default written to $CONF_DIR/local-llm.conf.kit-new"
else
  rm -f "$default_conf"; log "keeping pre-existing $CONF_DIR/local-llm.conf (no kit default state)"
fi
trap - EXIT

log "done: engine $build, $installed model(s). Next: kit-llm models && kit-llm start"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) log "WARNING: $BIN_DIR is not on PATH" ;; esac
