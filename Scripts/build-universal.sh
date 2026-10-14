#!/bin/bash
# Build a universal (arm64 + x86_64) keepawake binary and the menu bar helper.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Universal builds require macOS." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT="${1:-$ROOT/dist}"
mkdir -p "$OUT"

build_split() {
  local arch="$1"
  swift build -c release --arch "$arch" --product keepawake
  swift build -c release --arch "$arch" --product KeepAwakeMenu
}

if swift build -c release --arch arm64 --arch x86_64 --product keepawake \
  && swift build -c release --arch arm64 --arch x86_64 --product KeepAwakeMenu
then
  BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
  cp "$BIN_DIR/keepawake" "$OUT/keepawake"
  cp "$BIN_DIR/KeepAwakeMenu" "$OUT/KeepAwakeMenu"
else
  echo "Combined --arch build failed. Building each architecture and joining with lipo." >&2
  build_split arm64
  build_split x86_64
  ARM="$(swift build -c release --arch arm64 --show-bin-path)"
  X64="$(swift build -c release --arch x86_64 --show-bin-path)"
  lipo -create "$ARM/keepawake" "$X64/keepawake" -output "$OUT/keepawake"
  lipo -create "$ARM/KeepAwakeMenu" "$X64/KeepAwakeMenu" -output "$OUT/KeepAwakeMenu"
fi

chmod 755 "$OUT/keepawake" "$OUT/KeepAwakeMenu"
if command -v codesign >/dev/null 2>&1; then
  codesign -s - --force "$OUT/keepawake" || true
  codesign -s - --force "$OUT/KeepAwakeMenu" || true
fi
lipo -info "$OUT/keepawake"
echo "Wrote $OUT/keepawake"
echo "Wrote $OUT/KeepAwakeMenu"
