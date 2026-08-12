#!/bin/bash
# 编译并打包 VibeTalk.app
# 用法: ./scripts/package_app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f vendor/lib/libwhisper.a ]; then
    echo "静态库不存在，先执行 scripts/build_vendor.sh"
    ./scripts/build_vendor.sh
fi

mkdir -p build

SWIFT_FLAGS=(
  -import-objc-header Sources/BridgingHeader.h
  -I vendor/include
  -L vendor/lib
  -lwhisper -lggml -lggml-base -lggml-cpu -lggml-metal -lggml-blas -lc++
  -framework Foundation -framework Metal -framework MetalKit -framework Accelerate
  -framework AppKit -framework SwiftUI -framework AVFoundation -framework CoreAudio
  -O
)

swiftc Sources/*.swift "${SWIFT_FLAGS[@]}" -target arm64-apple-macos14.0 -o build/VibeTalk-arm64
swiftc Sources/*.swift "${SWIFT_FLAGS[@]}" -target x86_64-apple-macos14.0 -o build/VibeTalk-x86_64
lipo -create build/VibeTalk-arm64 build/VibeTalk-x86_64 -output build/VibeTalk

APP="build/VibeTalk.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/VibeTalk.icns "$APP/Contents/Resources/"
cp build/VibeTalk "$APP/Contents/MacOS/"

codesign --force --sign "VibeTalk Local Signing" "$APP"

echo "打包完成: $APP"
