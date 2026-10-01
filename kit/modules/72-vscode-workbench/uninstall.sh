#!/usr/bin/env bash
# Remove the Kit Workbench extension and kit-wb. Runs, results and the registry stay.
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE="${CODE:-code}"

if command -v "$CODE" >/dev/null 2>&1; then
  "$CODE" --uninstall-extension work-kit.kit-workbench || true
else
  echo "VS Code CLI '$CODE' not found: uninstall 'Kit Workbench' in the Extensions view."
fi
if [ -f "$HOME/.local/bin/kit-wb" ] && cmp -s "$MODULE_DIR/extension/resources/bin/kit-wb" "$HOME/.local/bin/kit-wb"; then
  rm "$HOME/.local/bin/kit-wb"
  echo "removed $HOME/.local/bin/kit-wb"
elif [ -e "$HOME/.local/bin/kit-wb" ]; then
  echo "kept $HOME/.local/bin/kit-wb (changed by the user)"
fi
echo "kept: ~/.local/share/work-kit/workbench (runs) and ~/.config/work-kit/workbench (registry)"
