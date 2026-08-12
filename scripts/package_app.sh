#!/bin/bash
# 编译并打包 VibeTalk
# 用法: ./scripts/package_app.sh [--dev|--release]   （默认 --dev）
set -euo pipefail

MODE="dev"
VERSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dev) MODE="dev" ;;
        --release) MODE="release" ;;
        --version) VERSION="${2:?--version 需要参数}"; shift ;;
        *) echo "未知参数: $1（可选 --dev / --release / --version X.Y.Z）" >&2; exit 1 ;;
    esac
    shift
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f vendor/lib/libwhisper.a ]; then
    echo "静态库不存在，先执行 scripts/build_vendor.sh"
    ./scripts/build_vendor.sh
fi

if [ "$MODE" = "release" ]; then
    APP_NAME="VibeTalk"
    BUNDLE_ID="io.github.kyze8439690.VibeTalk"
    ICON="VibeTalk.icns"
else
    APP_NAME="VibeTalk Dev"
    BUNDLE_ID="io.github.kyze8439690.VibeTalk.dev"
    ICON="VibeTalk-Dev.icns"
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

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
cp "Resources/$ICON" "$APP/Contents/Resources/"
cp build/VibeTalk "$APP/Contents/MacOS/"

PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile ${ICON%.icns}" "$PLIST"

if [ -n "$VERSION" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST"
fi

codesign --force --sign "VibeTalk Local Signing" "$APP"

echo "打包完成 ($MODE): $APP  [$BUNDLE_ID]"
