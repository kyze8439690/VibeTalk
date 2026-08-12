#!/bin/bash
# 生成 whisper 测试语料音频：macOS say TTS -> 16kHz 单声道 PCM16
# 用法: ./scripts/generate_test_audio.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="$ROOT/tests/corpus.txt"
OUT_DIR="$ROOT/tests/corpus"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

VOICE=""
for v in Tingting Eddy Flo; do
    if say -v '?' | grep -q "^$v"; then
        VOICE="$v"
        break
    fi
done
if [ -z "$VOICE" ]; then
    echo "error: 没有可用的中文 TTS 语音（Tingting/Eddy/Flo）" >&2
    exit 1
fi
echo "使用 TTS 语音: $VOICE"

mkdir -p "$OUT_DIR"
cp "$CORPUS" "$OUT_DIR/corpus.txt"

while IFS=$'\t' read -r id text; do
    [ -z "$id" ] && continue
    echo "生成: $id"
    say -v "$VOICE" -r 180 -o "$TMP_DIR/$id.aiff" "$text"
    afconvert -f WAVE -d LEI16@16000 -c 1 "$TMP_DIR/$id.aiff" "$TMP_DIR/$id.wav"
    python3 -c "
import wave, sys
w = wave.open('$TMP_DIR/$id.wav', 'rb')
data = w.readframes(w.getnframes())
open('$OUT_DIR/$id.pcm', 'wb').write(data)
print('  %d 帧, %.1fs' % (w.getnframes(), w.getnframes() / 16000))
"
done < "$CORPUS"

echo "完成，输出目录: $OUT_DIR"
ls -la "$OUT_DIR"
