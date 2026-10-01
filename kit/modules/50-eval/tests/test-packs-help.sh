#!/usr/bin/env bash
# `run.sh --help` of every pack prints exactly the header comment: no code lines, and nothing runs.
set -uo pipefail
MOD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fails=0
for f in "$MOD"/packs/*/run.sh; do
  name="$(basename "$(dirname "$f")")"
  out="$(cd "$W" && HOME="$W" bash "$f" --help 2>&1)"; rc=$?
  expect="$(awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "$f")"
  if [ "$rc" = 0 ] && [ "$out" = "$expect" ] && ! grep -Eq '^(set -|[A-Za-z_]+=)' <<<"$out"; then echo "ok   $name --help is the comment block"
  else echo "FAIL $name --help"; fails=$((fails + 1)); fi
done
[ -z "$(find "$W" -mindepth 1)" ] && echo "ok   help wrote nothing" || { echo "FAIL help wrote files"; fails=$((fails + 1)); }
echo "failures: $fails"
[ "$fails" = 0 ]
