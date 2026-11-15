#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build dist
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
SOURCES=(src/QQPRuntime.m src/QQPCodec.m src/QQPImageIO.m src/QQPPlugin.m src/QQPChat.m)
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
    -std=c11 -O2 -Wall -Wextra -Werror -fvisibility=hidden -Isrc \
    -c src/QQPWeakField.c -o "build/${ARCH}/QQPWeakField.o"
  OBJECTS+=("build/${ARCH}/QQPWeakField.o")
  # Let the Swift driver link its own platform runtime; do not guess library paths.
  xcrun --sdk iphoneos swiftc -target "${ARCH}-apple-ios15.0" -sdk "$SDK" \
    -swift-version 5 -O -parse-as-library -emit-library -module-name QQPhotoBase64 \
    -import-objc-header src/QQPReflection.h \
    src/QQPContextInspector.swift "${OBJECTS[@]}" \
    -framework Foundation -framework UIKit -framework Photos -framework ImageIO \
    -framework QuickLook -framework UniformTypeIdentifiers -framework CoreGraphics \
    -framework QuartzCore -Xlinker -fixup_chains \
    -Xlinker -install_name -Xlinker @rpath/QQPhotoBase64.dylib \
    -o "build/QQPhotoBase64-${ARCH}.dylib"
done
xcrun lipo -create build/QQPhotoBase64-arm64.dylib build/QQPhotoBase64-arm64e.dylib -output build/QQPhotoBase64.dylib
codesign --force --sign - --timestamp=none build/QQPhotoBase64.dylib
codesign --verify --strict --all-architectures --verbose=2 build/QQPhotoBase64.dylib
python3 tools/package.py
