#!/usr/bin/env bash
# Download the default embedding model into $KIT_OFFLINE/models/<name>/ (default kit/offline;
# run on the build machine). Both int8 CPU variants are fetched.
# Files are pinned to a repository revision and checked against sha256. Safe to re-run.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd "$MODULE_DIR/../.." && pwd)"
# shellcheck source=model.conf
. "$MODULE_DIR/model.conf"

DEST="${1:-${KIT_OFFLINE:-$KIT_DIR/offline}/models/$BRAIN_MODEL_NAME}"
BASE="${HF_ENDPOINT:-https://huggingface.co}/$BRAIN_MODEL_REPO/resolve/$BRAIN_MODEL_REVISION"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

mkdir -p "$DEST"
while read -r sum path; do
  [ -n "$path" ] || continue
  file="$DEST/$path"
  if [ -f "$file" ] && [ "$(sha256 "$file")" = "$sum" ]; then
    echo "ok       $path"
    continue
  fi
  mkdir -p "$(dirname "$file")"
  curl -fsSL --retry 3 -o "$file.part" "$BASE/$path"
  got="$(sha256 "$file.part")"
  if [ "$got" != "$sum" ]; then
    rm -f "$file.part"
    echo "sha256 mismatch for $path: got $got, want $sum" >&2
    exit 1
  fi
  mv "$file.part" "$file"
  echo "fetched  $path"
done <<< "$BRAIN_MODEL_FILES"

# Default spec points at the avx2 file, which runs on every x86_64 CPU; install.sh rewrites it
# for the CPU it installs on.
printf '%s\n' "${BRAIN_MODEL_SPEC/@ONNX@/$BRAIN_MODEL_ONNX_AVX2}" > "$DEST/brain-model.json"
printf 'Model: %s (revision %s)\nLicense: %s\nSource: https://huggingface.co/%s\n' \
  "$BRAIN_MODEL_REPO" "$BRAIN_MODEL_REVISION" "$BRAIN_MODEL_LICENSE" "$BRAIN_MODEL_REPO" \
  > "$DEST/SOURCE.txt"
echo "model ready in $DEST"
