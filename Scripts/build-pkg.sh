#!/bin/bash
# Build the installer packages in dist/:
#   KeepAwake-<version>.pkg      KeepAwake.app in /Applications and keepawake in /usr/local/bin
#   keepawake-cli-<version>.pkg  only /usr/local/bin/keepawake, for Jamf and other MDM policies
# Both are product archives with a thank you page. Neither loads a launchd job.
# Set PKG_SIGN_ID to a Developer ID Installer identity to sign them.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "pkgbuild requires macOS." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ ! -x dist/keepawake ]]; then
  ./Scripts/build-universal.sh
fi
if [[ ! -d dist/KeepAwake.app ]]; then
  ./Scripts/package-menu-app.sh
fi

VERSION="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' Sources/KeepAwakeCore/Version.swift)"
REPO_URL="$(sed -n 's/.*static let repositoryURL = "\([^"]*\)".*/\1/p' Sources/KeepAwakeCore/Version.swift)"
if [[ -z "$VERSION" || -z "$REPO_URL" ]]; then
  echo "Could not read the version or repository URL from Version.swift." >&2
  exit 1
fi
export COPYFILE_DISABLE=1

SIGN_ARGS=()
if [[ -n "${PKG_SIGN_ID:-}" ]]; then SIGN_ARGS=(--sign "$PKG_SIGN_ID"); fi

# build_product <payload root> <identifier> <title> <app paragraph html> <output>
build_product() {
  local payload="$1" identifier="$2" title="$3" app_html="$4" output="$5"
  local work; work="$(mktemp -d)"
  mkdir -p "$work/packages" "$work/resources"
  xattr -cr "$payload" 2>/dev/null || true

  # Install to the fixed paths even if another copy of the app exists elsewhere.
  pkgbuild --analyze --root "$payload" "$work/components.plist" >/dev/null
  if plutil -extract 0 xml1 -o /dev/null "$work/components.plist" 2>/dev/null; then
    plutil -replace 0.BundleIsRelocatable -bool false "$work/components.plist"
  fi

  pkgbuild --root "$payload" \
    --component-plist "$work/components.plist" \
    --identifier "$identifier" \
    --version "$VERSION" \
    --install-location / \
    --filter '\.DS_Store$' \
    "$work/packages/component.pkg"

  sed -e "s|__VERSION__|${VERSION}|g" -e "s|__REPO_URL__|${REPO_URL}|g" \
    -e "s|__APP_PARAGRAPH__|${app_html}|g" \
    Installer/conclusion.html > "$work/resources/conclusion.html"

  productbuild --synthesize --package "$work/packages/component.pkg" "$work/distribution.xml" >/dev/null
  python3 - "$work/distribution.xml" "$title" <<'PY'
import re, sys
path, title = sys.argv[1], sys.argv[2]
xml = open(path).read()
xml = re.sub(r'\s*<options [^>]*/>', '', xml)
extra = (
    f'\n    <title>{title}</title>'
    '\n    <conclusion file="conclusion.html" mime-type="text/html"/>'
    '\n    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>'
    '\n    <domains enable_localSystem="true"/>'
)
xml = re.sub(r'(<installer-gui-script[^>]*>)', lambda m: m.group(1) + extra, xml, count=1)
open(path, 'w').write(xml)
PY

  productbuild --distribution "$work/distribution.xml" \
    --resources "$work/resources" \
    --package-path "$work/packages" \
    ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
    "$output"
  rm -rf "$work"
  echo "Wrote $output"
}

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Full package: menu bar app plus the command line tool.
mkdir -p "$STAGE/full/Applications" "$STAGE/full/usr/local/bin"
ditto dist/KeepAwake.app "$STAGE/full/Applications/KeepAwake.app"
install -m 755 dist/keepawake "$STAGE/full/usr/local/bin/keepawake"
build_product "$STAGE/full" com.keepawake.pkg "KeepAwake ${VERSION}" \
  '<p>Open <b>KeepAwake</b> from your Applications folder. It lives in the menu bar near the clock and has no Dock icon. On a MacBook with a notch, a crowded menu bar can hide it behind the notch.</p>' \
  "dist/KeepAwake-${VERSION}.pkg"

# Command line only package, for MDM policies.
mkdir -p "$STAGE/cli/usr/local/bin"
install -m 755 dist/keepawake "$STAGE/cli/usr/local/bin/keepawake"
build_product "$STAGE/cli" com.keepawake.cli "KeepAwake command line tool ${VERSION}" "" \
  "dist/keepawake-cli-${VERSION}.pkg"

if [[ -z "${PKG_SIGN_ID:-}" ]]; then
  echo "These packages are unsigned. Sign them before a production deployment."
fi
