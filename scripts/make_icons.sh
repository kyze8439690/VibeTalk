#!/bin/bash
# 生成正式版和开发版两套图标（icns 输出到 Resources/）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

make_icns() {
    local variant="$1"   # release | dev
    local suffix="$2"    # "" | "-Dev"
    local png
    png=$(swift scripts/make_icon.swift build "$variant" | awk '{print $2}')
    local iconset="build/VibeTalk${suffix}.iconset"
    rm -rf "$iconset"
    mkdir -p "$iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$png" --out "$iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) "$png" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$iconset" -o "Resources/VibeTalk${suffix}.icns"
    rm -rf "$iconset"
    echo "生成: Resources/VibeTalk${suffix}.icns"
}

make_icns release ""
make_icns dev "-Dev"
