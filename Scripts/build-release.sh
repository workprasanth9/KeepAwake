#!/bin/bash
# Build every release artifact into dist/:
#   keepawake-<version>-macos-universal.zip  the command line tool
#   KeepAwake-<version>-app.zip              the menu bar app (command line tool inside)
#   KeepAwake-<version>.pkg and keepawake-cli-<version>.pkg
#   keepawake-<version>.sha256
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' Sources/KeepAwakeCore/Version.swift)"

rm -rf dist
./Scripts/build-universal.sh
./Scripts/package-menu-app.sh
./Scripts/build-pkg.sh

cd dist
export COPYFILE_DISABLE=1
mkdir -p "cli/keepawake-${VERSION}"
cp keepawake "cli/keepawake-${VERSION}/keepawake"
cp ../docs/keepawake.1 ../LICENSE ../README.md "cli/keepawake-${VERSION}/"
(cd cli && ditto -c -k --keepParent "keepawake-${VERSION}" "../keepawake-${VERSION}-macos-universal.zip")
rm -rf cli
ditto -c -k --keepParent KeepAwake.app "KeepAwake-${VERSION}-app.zip"
shasum -a 256 "keepawake-${VERSION}-macos-universal.zip" "KeepAwake-${VERSION}-app.zip" \
  "KeepAwake-${VERSION}.pkg" "keepawake-cli-${VERSION}.pkg" > "keepawake-${VERSION}.sha256"
cat "keepawake-${VERSION}.sha256"
