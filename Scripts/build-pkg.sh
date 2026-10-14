#!/bin/bash
# Build an unsigned pkg that installs the binary at /usr/local/bin/keepawake.
# Sign the package with your Developer ID before a broad Jamf deployment.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "pkgbuild requires macOS." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -x "$ROOT/dist/keepawake" ]]; then
  "$ROOT/Scripts/build-universal.sh"
fi

VERSION="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' "$ROOT/Sources/KeepAwakeCore/Version.swift")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp "$ROOT/dist/keepawake" "$STAGE/keepawake"
chmod 755 "$STAGE/keepawake"

mkdir -p "$ROOT/dist"
pkgbuild \
  --root "$STAGE" \
  --identifier com.keepawake.cli \
  --version "$VERSION" \
  --install-location /usr/local/bin \
  "$ROOT/dist/keepawake-cli.pkg"

echo "Wrote $ROOT/dist/keepawake-cli.pkg"
echo "This package is unsigned. Sign it before production deployment."
