#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
python3 tools/make_fixture.py
xcrun --sdk macosx clang -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror \
  -Isrc -framework Foundation -framework ImageIO -framework CoreGraphics \
  src/QQPCodec.m tests/codec_test.m -o build/codec-test
build/codec-test build/fixture.png | tee build/codec-test.json
