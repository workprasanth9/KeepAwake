#!/bin/bash
# Fail if repository text contains U+2014.
# Build that code point at runtime. A literal escape in this file would
# match itself on macOS bash 3.2, which does not expand it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

em_dash="$(printf '\342\200\224')"

if grep -RIn \
  --exclude-dir=.git \
  --exclude-dir=.build \
  --exclude-dir=.swiftpm \
  --exclude-dir=dist \
  --exclude=check-text.sh \
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
  -e "$em_dash" .
then
  echo "Em dashes are not allowed in this repository." >&2
  exit 1
fi
