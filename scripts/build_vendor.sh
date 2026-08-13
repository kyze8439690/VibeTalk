#!/bin/bash
# 从 vendor/whisper.cpp 编译 macOS 静态库（Metal 加速）到 vendor/lib + vendor/include
# 用法: ./scripts/build_vendor.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_DIR=build-vendor

cmake -B "$BUILD_DIR" -S vendor/whisper.cpp \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_SERVER=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -G Ninja

cmake --build "$BUILD_DIR" -j 10

mkdir -p vendor/lib vendor/include
cp "$BUILD_DIR/src/libwhisper.a" \
   "$BUILD_DIR/ggml/src/libggml.a" \
   "$BUILD_DIR/ggml/src/libggml-base.a" \
   "$BUILD_DIR/ggml/src/libggml-cpu.a" \
   "$BUILD_DIR/ggml/src/ggml-metal/libggml-metal.a" \
   "$BUILD_DIR/ggml/src/ggml-blas/libggml-blas.a" \
   vendor/lib/
cp vendor/whisper.cpp/include/whisper.h vendor/include/
cp vendor/whisper.cpp/ggml/include/*.h vendor/include/

libtool -static -o vendor/lib/libwhisper_all.a \
    vendor/lib/libwhisper.a \
    vendor/lib/libggml.a \
    vendor/lib/libggml-base.a \
    vendor/lib/libggml-cpu.a \
    vendor/lib/libggml-metal.a \
    vendor/lib/libggml-blas.a

rm -rf "$BUILD_DIR"
echo "完成: vendor/lib, vendor/include"
