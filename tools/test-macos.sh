#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
python3 tools/make_fixture.py
xcrun --sdk macosx clang -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror \
  -Isrc -framework Foundation -framework ImageIO -framework CoreGraphics \
  src/QQPCodec.m tests/codec_test.m -o build/codec-test
build/codec-test build/fixture.png | tee build/codec-test.json
xcrun --sdk macosx clang -std=c11 -O2 -Wall -Wextra -Werror -DQQP_WEAK_TEST \
  -Isrc src/QQPWeakField.c tests/weak_field_test.c -o build/weak-field-test
build/weak-field-test | tee build/weak-field-test.json
xcrun --sdk macosx clang -std=c11 -O2 -Wall -Wextra -Werror \
  -Isrc -c src/QQPWeakField.c -o build/weak-field-macos.o
cat src/QQPContextInspector.swift tests/context_fixture.swift > build/main.swift
xcrun --sdk macosx swiftc -swift-version 5 -O -g -DQQP_CONTEXT_TEST \
  -import-objc-header src/QQPReflection.h build/main.swift build/weak-field-macos.o \
  -o build/context-fixture 2>&1 | tee build/context-fixture-build.log
build/context-fixture 2> >(tee build/context-fixture.log >&2) | tee build/context-fixture.json
