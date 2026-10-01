#!/usr/bin/env bash
# Copy the usable semgrep rule files out of an unpacked semgrep-rules checkout.
# Usage: select-rules.sh SRC_DIR DST_DIR
# Keeps only *.yaml / *.yml files that have a top-level "rules:" key, skips test fixtures
# (*.test.yaml) and hidden files, and only looks inside the language folders listed in
# $KIT_SEMGREP_RULE_DIRS (default: the languages of legacy code plus shell and Docker).
# The repo's other yaml (.pre-commit-config.yaml, .github, metadata) is not a rule and makes
# `semgrep --config <dir>` fail. Prints the number of rule files copied.
set -euo pipefail

SRC="${1:?usage: select-rules.sh SRC_DIR DST_DIR}"
DST="${2:?usage: select-rules.sh SRC_DIR DST_DIR}"
DIRS="${KIT_SEMGREP_RULE_DIRS:-c csharp java javascript typescript python bash dockerfile}"

mkdir -p "$DST"
n=0
for d in $DIRS; do
  [ -d "$SRC/$d" ] || continue
  while IFS= read -r f; do
    grep -q '^rules:' "$f" || continue
    rel="${f#"$SRC"/}"
    mkdir -p "$DST/$(dirname "$rel")"
    cp "$f" "$DST/$rel"
    n=$((n + 1))
  done < <(find "$SRC/$d" -type f \( -name '*.yaml' -o -name '*.yml' \) \
             ! -name '*.test.yaml' ! -name '*.test.yml' ! -name '.*' | sort)
done
for f in LICENSE LICENSE.md; do [ -f "$SRC/$f" ] && cp "$SRC/$f" "$DST/$f"; done
echo "$n"
