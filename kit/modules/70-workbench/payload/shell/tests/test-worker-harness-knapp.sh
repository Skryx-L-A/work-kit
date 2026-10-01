#!/usr/bin/env bash
# Codex-Worker starten standardmaessig ohne die teuren Plugin-MCPs. Andere
# Harnesses und der ausdrueckliche Vollmodus bleiben unveraendert.
set -uo pipefail

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok: %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL: %s\n' "$1"; }

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUF="$(cd "$HIER/.." && pwd)/wb-harness-run"
TESTBASIS="${TMPDIR:-$PWD}"
TESTROOT="$(mktemp -d "$TESTBASIS/wb-harness-knapp.XXXXXX")"
trap 'rm -rf -- "$TESTROOT"' EXIT INT TERM
mkdir -p "$TESTROOT/.local/bin" "$TESTROOT/arbeit"

cat >"$TESTROOT/.local/bin/wb-state" <<'SH'
#!/bin/bash
if [ "$1 $2" = "models resolve" ]; then
  case "$3" in
    codex-test) harness=codex ;;
    opencode-test) harness=opencode ;;
    pi-test) harness=pi ;;
    *) exit 2 ;;
  esac
  printf 'harness\t%s\n' "$harness"
  printf 'cmd\tcd %q && exec %s --model testmodell\n' "$WB_TEST_ARBEIT" "$harness"
elif [ "$1 $2" = "harness get" ]; then
  printf '{"id":"%s","systemPrompt":{"style":"none"}}\n' "$3"
else
  exit 2
fi
SH

for harness in codex opencode pi; do
  cat >"$TESTROOT/.local/bin/$harness" <<SH
#!/bin/sh
printf '%s\n' "\$@" >"$TESTROOT/$harness.args"
SH
  chmod +x "$TESTROOT/.local/bin/$harness"
done
chmod +x "$TESTROOT/.local/bin/wb-state"

lauf() {
  env HOME="$TESTROOT" WB_TEST_ARBEIT="$TESTROOT/arbeit" \
    PATH="$TESTROOT/.local/bin:/usr/bin:/bin" "$@"
}

lauf "$LAUF" --model codex-test --role worker --dir "$TESTROOT/arbeit"
if grep -qx -- '--disable' "$TESTROOT/codex.args" \
   && grep -qx -- 'plugins' "$TESTROOT/codex.args"; then
  ok "Codex-Worker bekommt --disable plugins"
else
  bad "Codex-Worker hat die knappe Plugin-Ausstattung nicht"
fi

rm -f -- "$TESTROOT/codex.args"
MELDUNG="$(lauf env WB_MCP_VOLL=1 "$LAUF" --model codex-test --role worker \
  --dir "$TESTROOT/arbeit" 2>&1)"
if ! grep -qx -- '--disable' "$TESTROOT/codex.args" \
   && [[ "$MELDUNG" = *WB_MCP_VOLL* ]]; then
  ok "WB_MCP_VOLL stellt Codex-Plugins wieder her und meldet das"
else
  bad "Codex-Vollmodus ist nicht wirksam oder bleibt still"
fi

lauf "$LAUF" --model opencode-test --role worker --dir "$TESTROOT/arbeit"
lauf "$LAUF" --model pi-test --role worker --dir "$TESTROOT/arbeit"
if ! grep -qx -- '--disable' "$TESTROOT/opencode.args" \
   && ! grep -qx -- '--disable' "$TESTROOT/pi.args"; then
  ok "OpenCode und pi bleiben von der Codex-Regel unberuehrt"
else
  bad "Codex-Regel ist in einen anderen Harness gelaufen"
fi

printf 'bestanden: %d, fehlgeschlagen: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
