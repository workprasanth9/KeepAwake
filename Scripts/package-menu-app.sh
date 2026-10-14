#!/bin/bash
# Wrap the menu bar executable in a minimal Launch Services app bundle.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "App bundles require macOS." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
if [[ ! -x "$DIST/KeepAwakeMenu" ]]; then
  "$ROOT/Scripts/build-universal.sh"
fi

VERSION="$(sed -n 's/.*static let version = "\([^"]*\)".*/\1/p' "$ROOT/Sources/KeepAwakeCore/Version.swift")"
if [[ -z "$VERSION" ]]; then
  echo "Could not read the version from Sources/KeepAwakeCore/Version.swift." >&2
  exit 1
fi

APP="$DIST/KeepAwake.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$DIST/KeepAwakeMenu" "$APP/Contents/MacOS/KeepAwake"
chmod 755 "$APP/Contents/MacOS/KeepAwake"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>KeepAwake</string>
  <key>CFBundleIdentifier</key>
  <string>com.keepawake.menu</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>KeepAwake</string>
  <key>CFBundleDisplayName</key>
  <string>KeepAwake</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright 2026 KeepAwake contributors</string>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  codesign -s - --force "$APP" || true
fi

echo "Wrote $APP"
