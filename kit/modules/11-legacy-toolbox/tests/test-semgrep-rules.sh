#!/usr/bin/env bash
# The shipped semgrep rules directory must contain only valid rule files.
#  1. select-rules.sh on a fake repo: non-rule yaml, tests and other languages are dropped.
#  2. If semgrep is available: `semgrep --validate` on the directory select-rules.sh builds
#     from the pinned rule pack (kit/offline/legacy-toolbox/semgrep) and on the rules
#     directory install.sh already put under the data dir.
# Semgrep is looked up in KIT_SEMGREP, ~/.local/bin, PATH; without it step 2 is skipped.
# shellcheck disable=SC2016  # check() evaluates its quoted condition later
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOD="$(cd "$HERE/.." && pwd)"
KIT_ROOT="${KIT_ROOT:-$(cd "$MOD/../.." && pwd)}"
KIT_OFFLINE="${KIT_OFFLINE:-$KIT_ROOT/offline}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
fails=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi; }

# --- 1. selection logic on a fake repo ---------------------------------------------------
R="$W/repo"
mkdir -p "$R/java/lang" "$R/python/x" "$R/ruby" "$R/.github" "$R/yaml"
printf 'rules:\n- id: a\n  pattern: foo()\n' >"$R/java/lang/a.yaml"
printf 'class A {}\n' >"$R/java/lang/a.java"
printf 'rules:\n- id: b\n  pattern: bar()\n' >"$R/python/x/b.yml"
printf 'rules:\n- id: t\n  pattern: t()\n' >"$R/python/x/b.test.yaml"
printf 'repos:\n- repo: local\n' >"$R/python/.pre-commit-config.yaml"
printf 'key: value\n' >"$R/python/x/data.yaml"
printf 'rules:\n- id: r\n  pattern: r()\n' >"$R/ruby/r.yaml"
printf 'rules:\n- id: m\n' >"$R/.github/stale.yml"
echo license >"$R/LICENSE"
n="$(bash "$MOD/select-rules.sh" "$R" "$W/out")"
check "counts the two rule files" '[ "$n" = 2 ]'
check "keeps java and python rules" '[ -f "$W/out/java/lang/a.yaml" ] && [ -f "$W/out/python/x/b.yml" ]'
check "drops source files, tests, non-rule yaml, hidden files" \
  '[ -z "$(cd "$W/out" && find . -type f | grep -vE "a.yaml|b.yml|LICENSE")" ]'
check "drops languages outside the curated list" '[ ! -e "$W/out/ruby" ]'
check "keeps the licence" '[ -f "$W/out/LICENSE" ]'
n="$(KIT_SEMGREP_RULE_DIRS='ruby' bash "$MOD/select-rules.sh" "$R" "$W/out2")"
check "KIT_SEMGREP_RULE_DIRS overrides the list" '[ "$n" = 1 ] && [ -f "$W/out2/ruby/r.yaml" ]'

# --- 2. semgrep --validate ---------------------------------------------------------------
SEMGREP="${KIT_SEMGREP:-}"
[ -n "$SEMGREP" ] || SEMGREP="$(ls "${KIT_BIN_DIR:-$HOME/.local/bin}/semgrep" 2>/dev/null || command -v semgrep || true)"
validate() { # DIR
  SEMGREP_SEND_METRICS=off SEMGREP_ENABLE_VERSION_CHECK=0 \
    "$SEMGREP" --validate --config "$1" --metrics=off --disable-version-check >"$W/validate.log" 2>&1
}
if [ -z "$SEMGREP" ]; then
  echo "skip semgrep --validate: no semgrep found (set KIT_SEMGREP)"
else
  pack="$(ls "$KIT_OFFLINE"/legacy-toolbox/semgrep/semgrep-rules-*.tar.gz 2>/dev/null | tail -n 1)"
  if [ -n "$pack" ]; then
    mkdir -p "$W/pack"
    tar -xzf "$pack" -C "$W/pack" --strip-components=1
    bash "$MOD/select-rules.sh" "$W/pack" "$W/shipped" >/dev/null
    check "semgrep --validate: rules built from the pinned pack" 'validate "$W/shipped" || { tail -n 5 "$W/validate.log"; false; }'
    if ! validate "$W/pack"; then echo "note: the raw pack fails validation, as before the fix:"; tail -n 2 "$W/validate.log"; fi
  else
    echo "skip pinned pack: no semgrep-rules tarball in $KIT_OFFLINE/legacy-toolbox/semgrep"
  fi
  inst="${KIT_DATA_DIR:-$HOME/.local/share/work-kit}/legacy-toolbox/semgrep-rules"
  if [ -d "$inst" ]; then
    check "semgrep --validate: installed rules dir" 'validate "$inst" || { tail -n 5 "$W/validate.log"; false; }'
  fi
fi
echo "failures: $fails"
[ "$fails" = 0 ]
