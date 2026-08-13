#!/bin/bash
# 编译并打包 VibeTalk（SPM 构建）
# 用法: ./scripts/package_app.sh [--dev|--release] [--version X.Y.Z]   （默认 --dev）
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

if [ ! -f vendor/lib/libwhisper_all.a ]; then
    echo "libwhisper_all.a 不存在，先执行 scripts/build_vendor.sh"
    ./scripts/build_vendor.sh
fi

if [ "$MODE" = "release" ]; then
    APP_NAME="VibeTalk"
    BUNDLE_ID="io.github.kyze8439690.VibeTalk"
    ICON="VibeTalk.icns"
    GSPLIST="secrets/GoogleService-Info.plist"
else
    APP_NAME="VibeTalk Dev"
    BUNDLE_ID="io.github.kyze8439690.VibeTalk.dev"
    ICON="VibeTalk-Dev.icns"
    GSPLIST="secrets/GoogleService-Info-Dev.plist"
fi

mkdir -p build

swift build -c release --arch arm64
swift build -c release --arch x86_64
lipo -create \
    .build/arm64-apple-macosx/release/VibeTalk \
    .build/x86_64-apple-macosx/release/VibeTalk \
    -output build/VibeTalk
dsymutil build/VibeTalk -o build/VibeTalk.dSYM 2>/dev/null || true

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
cp "Resources/$ICON" "$APP/Contents/Resources/"
cp build/VibeTalk "$APP/Contents/MacOS/VibeTalk"

if [ -f "$GSPLIST" ]; then
    cp "$GSPLIST" "$APP/Contents/Resources/GoogleService-Info.plist"
else
    echo "警告: $GSPLIST 不存在，Firebase 将不启用" >&2
fi

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
