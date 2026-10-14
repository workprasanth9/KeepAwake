#!/bin/bash
# Fail if the repository text contains an em dash.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if grep -RIn \
  --exclude-dir=.git \
  --exclude-dir=.build \
  --exclude-dir=.swiftpm \
  --exclude-dir=dist \
  --include='*.swift' \
  --include='*.md' \
  --include='*.yml' \
  --include='*.yaml' \
  --include='*.sh' \
  --include='*.plist' \
  --include='*.mobileconfig' \
  --include='*.1' \
  --include='Makefile' \
  --include='LICENSE' \
  --include='.gitignore' \
  -e $'\u2014' .
then
  echo "Em dashes are not allowed in this repository." >&2
  exit 1
fi
