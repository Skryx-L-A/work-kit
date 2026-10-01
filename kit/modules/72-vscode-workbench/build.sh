#!/usr/bin/env bash
# Build kit-workbench.vsix on the build machine (needs Node.js 22+ and npm registry access once).
# The laptop install needs only the .vsix: ./install.sh
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/extension"
npm ci --no-audit --no-fund
npm run package
echo "built: $(cd .. && pwd)/kit-workbench.vsix"
