#!/usr/bin/env bash
# Installer and kit-llm logic with a fake engine (tests/fake-llama-server in the real archive
# layout) and a tiny fake model in a scratch HOME. Runs on Linux x86_64 and macOS arm64; it does
# not prove the real llama.cpp binary works (tests/smoke-real.sh does that).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/.." && pwd)"
W="$(mktemp -d)"
# shellcheck disable=SC2329  # used by trap
cleanup() { "$W/home/.local/bin/kit-llm" stop >/dev/null 2>&1 || true; rm -rf "$W"; }
trap cleanup EXIT
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if (set +o pipefail; eval "$2"); then ok "$1"; else bad "$1"; fi; }
sha256_of() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) plat=ubuntu-x64 ;;
  Darwin-arm64) plat=macos-arm64 ;;
  *) echo "skip: unsupported test host"; exit 0 ;;
esac

# --- fake offline tree ----------------------------------------------------------------------
OFF="$W/offline/local-llm"
mkdir -p "$OFF/engine" "$OFF/models" "$W/pk/llama-b1"
cp "$HERE/fake-llama-server" "$W/pk/llama-b1/fake.py"
# shellcheck disable=SC2016  # literal script text
printf '#!/bin/sh\nexec python3 "$(dirname "$0")/fake.py" "$@"\n' >"$W/pk/llama-b1/llama-server"
chmod +x "$W/pk/llama-b1/llama-server"
tar -czf "$OFF/engine/llama-b1-bin-$plat.tar.gz" -C "$W/pk" llama-b1
head -c 3000000 /dev/zero >"$OFF/models/tiny.gguf"
sum="$(sha256_of "$OFF/models/tiny.gguf")"
CAT="$W/models.conf"
{
  echo "# test catalog"
  echo "tiny|x/y|rev|tiny.gguf|$sum|3000000|apache-2.0|0B|default|--fake-extra 1"
  echo "big|x/y|rev|big.gguf|0000|9000000000|apache-2.0|9B|optional|"
} >"$CAT"

export HOME="$W/home" KIT_BIN_DIR="$W/home/.local/bin" KIT_DATA_DIR="$W/home/.local/share/work-kit"
export XDG_CONFIG_HOME="$W/home/.config" KIT_OFFLINE="$W/offline" KIT_LLM_CATALOG="$CAT"
unset KIT_LLM_SERVER KIT_LLM_MODEL KIT_LLM_HOME KIT_LLM_CONF
PORT="$(free_port)"
export KIT_LLM_PORT="$PORT" KIT_LLM_START_TIMEOUT=20
mkdir -p "$HOME"
K="$KIT_BIN_DIR/kit-llm"
LH="$KIT_DATA_DIR/local-llm"

# --- install --------------------------------------------------------------------------------
out="$(bash "$MOD/install.sh" 2>&1)" || { bad "install exits 0"; echo "$out"; }
check "kit-llm installed" "[ -x '$K' ]"
check "engine extracted + current link" "[ -x '$LH/engine/current/llama-server' ]"
check "default model copied" "[ -f '$LH/models/tiny.gguf' ]"
check "optional model skipped" "[ ! -e '$LH/models/big.gguf' ]"
check "catalog copied" "cmp -s '$CAT' '$LH/models.conf'"
check "config template written" "grep -q KIT_LLM_PORT '$XDG_CONFIG_HOME/work-kit/local-llm.conf'"
CFG="$XDG_CONFIG_HOME/work-kit/local-llm.conf"
CSTATE="$LH/local-llm.conf.kit-sha256"
sha256_of "$CFG" >"$CSTATE"
out="$(bash "$MOD/install.sh" --no-models 2>&1)"
check "untouched config default is refreshed" "grep -q 'refreshed .*local-llm.conf' <<<\"\$out\""
printf '\n# mine\n' >>"$CFG"
out="$(bash "$MOD/install.sh" --no-models 2>&1)"
check "edited config is kept and gets kit-new" "grep -q '# mine' '$CFG' && [ -f '$CFG.kit-new' ] && grep -q 'kept your' <<<\"\$out\""
rm -f "$CSTATE" "$CFG.kit-new"; printf 'FOREIGN=1\n' >"$CFG"
bash "$MOD/install.sh" --no-models >/dev/null
check "pre-existing foreign config is kept" "[ \"\$(cat '$CFG')\" = 'FOREIGN=1' ] && [ ! -e '$CFG.kit-new' ]"
out="$(bash "$MOD/install.sh" 2>&1)"
check "rerun: engine up to date" "grep -q 'engine llama.cpp b1 up to date' <<<\"\$out\""
check "rerun: model up to date" "grep -q 'model tiny up to date' <<<\"\$out\""
# A newer kit can carry a different model revision with the same byte count.  It must not be
# mistaken for the old pin merely because the destination has the expected size.
printf 'x' | dd of="$OFF/models/tiny.gguf" bs=1 count=1 conv=notrunc >/dev/null 2>&1
sum="$(sha256_of "$OFF/models/tiny.gguf")"
awk -F'|' -v OFS='|' -v sum="$sum" '$1 == "tiny" { $5 = sum } { print }' "$CAT" >"$CAT.new"
mv "$CAT.new" "$CAT"
out="$(bash "$MOD/install.sh" 2>&1)"
check "same-size model revision is refreshed" "cmp -s '$OFF/models/tiny.gguf' '$LH/models/tiny.gguf' && grep -q 'copy model tiny' <<<\"\$out\""
# The engine library check must survive ldd failing (a non-ELF engine: "not a dynamic executable",
# exit 1) under set -e/pipefail. A shim ldd stands in for the host one and the check is forced.
SH="$W/shim"; mkdir -p "$SH"
printf '#!/bin/sh\necho "\tnot a dynamic executable" >&2\nexit 1\n' >"$SH/ldd"; chmod +x "$SH/ldd"
out="$(PATH="$SH:$PATH" KIT_LLM_FORCE_LIBCHECK=1 bash "$MOD/install.sh" --no-models 2>&1)"; rc=$?
check "ldd exit 1 (not a dynamic executable): installer completes" "[ $rc = 0 ] && grep -q 'engine llama.cpp b1 up to date' <<<\"\$out\""
check "ldd exit 1: no bogus missing-library warning" "! grep -q 'missing system libraries' <<<\"\$out\""
printf '#!/bin/sh\necho "\tlibfoo.so.9 => not found"\nexit 0\n' >"$SH/ldd"
out="$(PATH="$SH:$PATH" KIT_LLM_FORCE_LIBCHECK=1 bash "$MOD/install.sh" --no-models 2>&1)"; rc=$?
check "ldd reporting a missing lib: warning names it" "[ $rc = 0 ] && grep -q 'missing system libraries: libfoo.so.9' <<<\"\$out\""
printf '#!/bin/sh\necho "\tlibfoo.so.9 => not found"\nexit 1\n' >"$SH/ldd"
out="$(PATH="$SH:$PATH" KIT_LLM_FORCE_LIBCHECK=1 bash "$MOD/install.sh" --no-models 2>&1)"; rc=$?
check "ldd exit 1 with a missing lib: still reported, no silent death" "[ $rc = 0 ] && grep -q 'missing system libraries: libfoo.so.9' <<<\"\$out\""
if bash "$MOD/install.sh" --models big >/dev/null 2>&1; then bad "missing optional model must fail"; else ok "missing optional model fails"; fi
if bash "$MOD/install.sh" --models nope >/dev/null 2>&1; then bad "unknown model id must fail"; else ok "unknown model id fails"; fi
printf '#!/bin/sh\necho mine\n' >"$K"
bash "$MOD/install.sh" --no-models >/dev/null 2>&1
check "foreign kit-llm backed up under backups/" "grep -q mine '$KIT_DATA_DIR'/backups/15-local-llm/kit-llm.bak-*"
check "backup records the original path" "grep -qx '$K' '$KIT_DATA_DIR'/backups/15-local-llm/kit-llm.bak-*.origin"
check "no backup beside the original" "! ls '$KIT_BIN_DIR' | grep -q 'bak-'"
check "kit-llm restored" "grep -q 'kit-llm: run a local GGUF model' '$K'"

# --- CLI ------------------------------------------------------------------------------------
# --help prints exactly the header comment (no code lines), for the CLI and the installer
for f in "$K" "$MOD/install.sh"; do
  out="$(bash "$f" --help 2>&1)" || bad "--help exits 0: $f"
  expect="$(awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "$f")"
  check "$(basename "$f") --help is exactly the comment block" "[ \"\$out\" = \"\$expect\" ]"
  check "$(basename "$f") --help leaks no code" "! grep -Eq '^(set -|[A-Za-z_]+=)' <<<\"\$out\""
done
for sub in models start stop status ask env logs doctor; do
  for flag in -h --help; do
    "$K" "$sub" "$flag" >"$W/h.out" 2>&1; rc=$?
    check "$sub $flag prints usage, exit 0" "[ $rc = 0 ] && grep -q '^Usage: kit-llm' '$W/h.out'"
  done
done
check "help started nothing" "[ ! -e '$LH/run/server.pid' ]"
check "models lists catalog" "KIT_LLM_MEM_AVAILABLE_MB=16000 '$K' models | grep -q '^tiny'"
check "models marks big as not fitting" "KIT_LLM_MEM_AVAILABLE_MB=8000 '$K' models | grep '^big' | grep -q ' no ('"
check "models header shows the default context" "KIT_LLM_MEM_AVAILABLE_MB=16000 '$K' models | head -1 | grep -q 'NEED-MB@16384'"
check "doctor prints the RAM need per model" "KIT_LLM_MEM_AVAILABLE_MB=16000 '$K' doctor 2>&1 | grep -q 'RAM need tiny: ~.* MB at 16384 tokens context'"
check "doctor flags a model that does not fit" "KIT_LLM_MEM_AVAILABLE_MB=8000 '$K' doctor 2>&1 | grep 'RAM need big' | grep -q 'does NOT fit'"
check "status when stopped exits 3" "set +e; '$K' status >/dev/null; [ \$? = 3 ]"

out="$(KIT_LLM_MEM_AVAILABLE_MB=500 "$K" start tiny 2>&1 || true)"
check "RAM guard refuses" "grep -q 'not enough free memory' <<<\"\$out\""
check "RAM guard leaves nothing running" "! '$K' status >/dev/null 2>&1"
check "unknown model refused" "! '$K' start nope >/dev/null 2>&1"
check "not installed model refused" "'$K' start big 2>&1 | grep -q 'not installed'"

out="$(KIT_LLM_MEM_AVAILABLE_MB=16000 "$K" start tiny 2>&1)" || { bad "start"; echo "$out"; }
check "start reports ready" "grep -q 'ready: tiny at http://127.0.0.1:$PORT/v1' <<<\"\$out\""
check "status running + health ok" "'$K' status | grep -q 'health ok'"
check "status --json" "'$K' status --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"running\"] and d[\"model\"]==\"tiny\"'"
check "binds 127.0.0.1 with alias, ctx, cpu, catalog args" "grep -q -- '--host 127.0.0.1 --port $PORT -c 16384 -ngl 0 --alias tiny --fake-extra 1' '$LH/logs/server.log'"
check "ask returns the answer" "'$K' ask 'Hallo' 2>/dev/null | grep -q 'echo: Hallo'"
check "ask says it is waiting, on stderr only" "'$K' ask 'Hallo' 2>&1 >/dev/null | grep -q 'waiting for tiny'"
check "ask keeps the waiting line off stdout" "! '$K' ask 'Hallo' 2>/dev/null | grep -q waiting"
check "env points at the server" "'$K' env | grep -q 'OPENAI_BASE_URL=http://127.0.0.1:$PORT/v1'"
check "second start of same model is a no-op" "KIT_LLM_MEM_AVAILABLE_MB=16000 '$K' start tiny | grep -q 'already running'"
check "logs tail" "'$K' logs -n 5 | grep -q 'fake llama-server args'"
pid="$(cat "$LH/run/server.pid")"
check "stop" "'$K' stop | grep -q 'stopped tiny'"
check "process gone after stop" "! kill -0 $pid 2>/dev/null"
check "stop twice is harmless" "'$K' stop | grep -q 'not running'"

out="$(KIT_LLM_MEM_AVAILABLE_MB=500 "$K" start tiny --force 2>&1)" || bad "start --force"
check "--force overrides the guard with a warning" "grep -q 'RAM guard overridden' <<<\"\$out\""
"$K" stop >/dev/null

python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
busy=$!
sleep 1
check "busy port refused" "KIT_LLM_MEM_AVAILABLE_MB=16000 '$K' start tiny 2>&1 | grep -q 'already in use'"
kill "$busy"; wait "$busy" 2>/dev/null || true

out="$(FAKE_LLAMA_FAIL=1 KIT_LLM_MEM_AVAILABLE_MB=16000 "$K" start tiny 2>&1 || true)"
check "engine crash at start is reported" "grep -q 'server exited during start' <<<\"\$out\""
check "no stale pid after crash" "[ ! -f '$LH/run/server.pid' ]"

echo "KIT_LLM_CTX=2048" >"$XDG_CONFIG_HOME/work-kit/local-llm.conf"
# shellcheck disable=SC2016  # must stay literal: proves the file is not executed
echo 'KIT_LLM_THREADS=$(touch /tmp/kit-llm-pwned)' >>"$XDG_CONFIG_HOME/work-kit/local-llm.conf"
KIT_LLM_MEM_AVAILABLE_MB=16000 "$K" start tiny >/dev/null 2>&1 || true
check "config file is read" "grep -q -- '-c 2048' '$LH/logs/server.log'"
check "config file is not executed" "[ ! -e /tmp/kit-llm-pwned ]"
"$K" stop >/dev/null

# --- uninstall ------------------------------------------------------------------------------
bash "$MOD/uninstall.sh" --keep-models >/dev/null
check "keep-models keeps models" "[ -f '$LH/models/tiny.gguf' ] && [ ! -e '$LH/engine' ]"
bash "$MOD/install.sh" --no-models >/dev/null 2>&1
bash "$MOD/uninstall.sh" >/dev/null
check "uninstall removes everything" "[ ! -e '$LH' ] && [ ! -e '$K' ]"
check "backup kept" "ls '$KIT_DATA_DIR'/backups/15-local-llm | grep -q '^kit-llm.bak-'"
check "uninstall twice is harmless" "bash '$MOD/uninstall.sh' >/dev/null 2>&1"
exit "$fail"
