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
  swift build -c release --arch "$arch" --product keepawake \
    && swift build -c release --arch "$arch" --product KeepAwakeMenu
}

if swift build -c release --arch arm64 --arch x86_64 --product keepawake \
  && swift build -c release --arch arm64 --arch x86_64 --product KeepAwakeMenu
then
  BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
  cp "$BIN_DIR/keepawake" "$OUT/keepawake"
  cp "$BIN_DIR/KeepAwakeMenu" "$OUT/KeepAwakeMenu"
else
  echo "Combined --arch build failed. Building each architecture and joining with lipo." >&2
  HOST_ARCH="$(uname -m)"
  if [[ "$HOST_ARCH" == "x86_64" ]]; then OTHER_ARCH="arm64"; else OTHER_ARCH="x86_64"; fi
  TMP_ARCH="$(mktemp -d)"
  build_split "$HOST_ARCH"
  SRC_BIN="$(swift build -c release --arch "$HOST_ARCH" --show-bin-path)"
  HOST_BIN="$TMP_ARCH/$HOST_ARCH"; mkdir -p "$HOST_BIN"
  cp "$SRC_BIN/keepawake" "$SRC_BIN/KeepAwakeMenu" "$HOST_BIN/"
  if build_split "$OTHER_ARCH"; then
    SRC_BIN="$(swift build -c release --arch "$OTHER_ARCH" --show-bin-path)"
    OTHER_BIN="$TMP_ARCH/$OTHER_ARCH"; mkdir -p "$OTHER_BIN"
    cp "$SRC_BIN/keepawake" "$SRC_BIN/KeepAwakeMenu" "$OTHER_BIN/"
    lipo -create "$HOST_BIN/keepawake" "$OTHER_BIN/keepawake" -output "$OUT/keepawake"
    lipo -create "$HOST_BIN/KeepAwakeMenu" "$OTHER_BIN/KeepAwakeMenu" -output "$OUT/KeepAwakeMenu"
  else
    echo "Warning: $OTHER_ARCH build failed with this toolchain (common with Command Line Tools only)." >&2
    echo "Producing a $HOST_ARCH only build. Install full Xcode or use the CI release for a universal binary." >&2
    cp "$HOST_BIN/keepawake" "$OUT/keepawake"
    cp "$HOST_BIN/KeepAwakeMenu" "$OUT/KeepAwakeMenu"
  fi
fi

chmod 755 "$OUT/keepawake" "$OUT/KeepAwakeMenu"
if command -v codesign >/dev/null 2>&1; then
  codesign -s - --force "$OUT/keepawake" || true
  codesign -s - --force "$OUT/KeepAwakeMenu" || true
fi
lipo -info "$OUT/keepawake"
echo "Wrote $OUT/keepawake"
echo "Wrote $OUT/KeepAwakeMenu"
