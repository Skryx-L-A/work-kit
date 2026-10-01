#!/usr/bin/env bash
# kit-depgraph against tests/fixtures: expected edges per language, output formats, cycles.
# shellcheck disable=SC2015  # "cmd && ok || bad": ok never fails
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DG="$HERE/../bin/kit-depgraph"
FX="$HERE/fixtures"
fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

# edge DIR FROM TO [COUNT]: the file-level TSV graph of a fixture must contain the edge.
edge() {
  local dir="$1" from="$2" to="$3" n="${4:-1}"
  if python3 "$DG" "$FX/$dir" --level file --format tsv --external 2>/dev/null | grep -qxF "$(printf '%s\t%s\t%s' "$from" "$to" "$n")"; then
    ok "$dir: $from -> $to ($n)"
  else bad "$dir: missing edge $from -> $to ($n)"; fi
}
noedge() {
  local dir="$1" needle="$2"
  if python3 "$DG" "$FX/$dir" --level file --format tsv --external 2>/dev/null | grep -qF "$needle"; then
    bad "$dir: unexpected $needle"; else ok "$dir: no $needle"; fi
}

edge java src/com/acme/app/Main.java src/com/acme/util/Strings.java 2
edge java src/com/acme/app/Main.java src/com/acme/model/Customer.java
edge java src/com/acme/app/Main.java "ext: java.util"
noedge java Ghost
edge cs Web/Controller.cs Core/Service.cs
edge cs Web/Controller.cs Core/Data.cs
edge cs Core/Service.cs Web/Controller.cs
edge c src/main.c src/util.h
edge c src/main.c include/lib/net.h
edge c src/util.h include/lib/net.h
edge c src/main.c "ext: <stdio.h>"
noedge c ghost.h
edge py pkg/__init__.py pkg/core.py
edge py pkg/core.py pkg/sub/helpers.py 2
edge py pkg/sub/helpers.py pkg/core.py 2
edge py pkg/core.py "ext: requests"
edge js src/a/index.ts src/b/util.ts
edge js src/a/index.ts src/b/types.ts
edge js src/a/index.ts src/b/index.ts
edge js src/a/index.ts src/a/local.js
edge js src/a/local.js src/b/util.ts
edge js src/a/index.ts "ext: @scope/pkg"
edge cobol PAYROLL.cbl CUSTREC.cpy
edge cobol PAYROLL.cbl TAXCALC.cbl
edge cobol TAXCALC.cbl CUSTREC.cpy
noedge cobol GHOSTREC

# formats and cycles
out="$(python3 "$DG" "$FX/java" --format dot 2>/dev/null)"
case "$out" in "digraph deps {"*"}") ok "dot wrapper";; *) bad "dot wrapper";; esac
grep -q 'color=red' <<<"$out" && ok "dot marks cycle nodes" || bad "dot marks cycle nodes"
out="$(python3 "$DG" "$FX/java" --format d2 2>/dev/null)"
grep -qF '"src/com/acme/app" -> "src/com/acme/util": 2' <<<"$out" && ok "d2 edge with count" || bad "d2 edge with count"
grep -q 'style.stroke: red' <<<"$out" && ok "d2 marks cycle nodes" || bad "d2 marks cycle nodes"
python3 "$DG" "$FX/java" --format tsv 2>&1 >/dev/null | grep -q '1 cycle group' && ok "cycle summary on stderr" || bad "cycle summary"
python3 "$DG" "$FX/js" --level dir --depth 1 --format tsv 2>/dev/null | grep -qxF "$(printf 'src\tsrc\t1')" \
  && bad "self edge kept" || ok "no self edges at depth 1"
[ "$(python3 "$DG" "$FX/py" --lang java --format tsv 2>/dev/null | wc -l | tr -d ' ')" = 1 ] && ok "--lang filter" || bad "--lang filter"
python3 "$DG" "$FX/py" --exclude 'helpers.py' --level file --format tsv 2>/dev/null | grep -q helpers && bad "--exclude" || ok "--exclude"
python3 "$DG" /nonexistent >/dev/null 2>&1 && bad "bad path accepted" || ok "bad path rejected"

# a git repo is read through git ls-files: ignored files are not scanned
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cp -R "$FX/py/pkg" "$T/pkg"
git -C "$T" init -q
printf 'import pkg.core\n' >"$T/ignored_mod.py"
echo 'ignored_mod.py' >"$T/.gitignore"
git -C "$T" add pkg .gitignore
python3 "$DG" "$T" --level file --format tsv 2>/dev/null | grep -q ignored_mod && bad "git-ignored file scanned" || ok "git-tracked files only"
exit "$fail"
