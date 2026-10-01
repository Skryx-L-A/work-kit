#!/usr/bin/env bash
# Check that spec.md and traceability.csv agree.
# Usage: trace-check.sh spec.md traceability.csv [--strict]
set -euo pipefail

spec="${1:-}"; csv="${2:-}"; strict="${3:-}"
[ -f "$spec" ] && [ -f "$csv" ] || { echo "usage: trace-check.sh spec.md traceability.csv [--strict]" >&2; exit 2; }

fail=0
err() { echo "ERROR: $*"; fail=1; }

spec_ids=$(sed -n 's/^### \([A-Z][A-Z]*-[0-9][0-9]*\)\([ ].*\)\{0,1\}$/\1/p' "$spec" | sort)
[ -n "$spec_ids" ] || err "no '### <ID> ' headings found in $spec"

dup=$(printf '%s\n' "$spec_ids" | uniq -d)
[ -z "$dup" ] || err "duplicate spec IDs: $(printf "%s" "$dup" | tr "\n" " ")"

header=$(head -n 1 "$csv")
[ "$header" = "spec_id,code,tests,target_code,target_tests,status" ] \
  || err "unexpected CSV header: $header"

rows=$(tail -n +2 "$csv" | grep -v '^[[:space:]]*$' || true)
csv_ids=$(printf '%s\n' "$rows" | cut -d, -f1 | sort)

for id in $spec_ids; do
  printf '%s\n' "$csv_ids" | grep -qx "$id" || err "$id in spec but not in matrix"
done
for id in $csv_ids; do
  printf '%s\n' "$spec_ids" | grep -qx "$id" || err "$id in matrix but not in spec"
done
dupcsv=$(printf '%s\n' "$csv_ids" | uniq -d)
[ -z "$dupcsv" ] || err "duplicate matrix rows: $(printf "%s" "$dupcsv" | tr "\n" " ")"

# Field checks (simple CSV: fields without embedded commas).
while IFS=, read -r id code tests tcode ttests status _rest; do
  [ -n "$id" ] || continue
  case "$status" in
    specified|planned|migrated|verified|retired|dropped) ;;
    *) err "$id: bad status '$status'"; continue ;;
  esac
  [ "$status" = dropped ] && continue
  [ -n "$code" ] || err "$id: no legacy code reference"
  [ -n "$tests" ] || err "$id: no test (write 'no test: <reason>' if accepted by the validator)"
  case "$status" in
    migrated|verified|retired)
      [ -n "$tcode" ] || err "$id: status $status but no target_code"
      [ -n "$ttests" ] || err "$id: status $status but no target_tests" ;;
  esac
  if [ "$strict" = "--strict" ] && [ "$status" = planned ]; then
    [ -n "$tcode" ] || err "$id: planned but no target_code location yet"
  fi
done <<< "$rows"

if [ "$fail" -eq 0 ]; then
  echo "OK: $(printf '%s\n' "$spec_ids" | wc -l | tr -d ' ') spec items, matrix consistent"
fi
exit "$fail"
