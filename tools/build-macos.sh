#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build dist
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
SOURCES=(src/QQPRuntime.m src/QQPCodec.m src/QQPImageIO.m src/QQPVideoPreview.m src/QQPPlugin.m src/QQPChat.m)
for ARCH in arm64 arm64e; do
  mkdir -p "build/${ARCH}"
  OBJECTS=()
  for SOURCE in "${SOURCES[@]}"; do
    OBJECT="build/${ARCH}/$(basename "${SOURCE%.m}").o"
    xcrun --sdk iphoneos clang -target "${ARCH}-apple-ios15.0" -isysroot "$SDK" \
      -fobjc-arc -fblocks -O2 -fvisibility=hidden -Wall -Wextra -Wno-unused-parameter \
      -Werror=implicit-function-declaration -Werror=objc-method-access \
      -c -Isrc "$SOURCE" -o "$OBJECT"
    OBJECTS+=("$OBJECT")
  done
  xcrun --sdk iphoneos clang -target "${ARCH}-apple-ios15.0" -isysroot "$SDK" \
    -dynamiclib -framework Foundation -framework UIKit -framework Photos \
    -framework ImageIO -framework AVFoundation -framework CoreMedia \
    -framework CoreGraphics -framework QuartzCore -Wl,-fixup_chains \
    -Wl,-install_name,@rpath/QQPhotoBase64.dylib \
    "${OBJECTS[@]}" -o "build/QQPhotoBase64-${ARCH}.dylib"
  codesign --force --sign - --timestamp=none "build/QQPhotoBase64-${ARCH}.dylib"
  codesign --verify --strict --all-architectures --verbose=2 "build/QQPhotoBase64-${ARCH}.dylib"
done
python3 tools/package.py
