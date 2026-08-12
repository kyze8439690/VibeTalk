# AGENTS.md

AI 代理工作指南。人类用户文档见 [README.md](README.md) 与 [docs/BUILDING.md](docs/BUILDING.md)（构建/签名/测试的详细步骤以这两份为准，此处不复述）。

## 项目概述

macOS 菜单栏语音输入工具（vibecoding 场景）：按住全局热键说话 → 松手后 whisper.cpp 本地识别（Metal 加速）→ 自动粘贴到当前输入框。中英混合 + 编程术语优化。

纯 Swift/SwiftUI（`MenuBarExtra`，LSUIElement），**无 Xcode 工程**：`swiftc` 直编 + 手工打包 .app。识别引擎是 whisper.cpp（git submodule，BridgingHeader 调 C API）。

## 常用命令

```bash
./scripts/build_vendor.sh          # 编译 whisper.cpp 静态库到 vendor/lib + vendor/include
./scripts/package_app.sh           # 开发版（默认）→ build/VibeTalk Dev.app
./scripts/package_app.sh --release # 正式版 → build/VibeTalk.app
python3 tests/run_corpus_mac.py --model <模型路径>   # 识别质量回归测试
./scripts/generate_test_audio.sh                    # corpus.txt 变更后重新生成语料音频
```

- 构建前置：CMake、Ninja、Xcode CLT；自签名证书 "VibeTalk Local Signing"（创建命令见 BUILDING.md，缺失时 codesign 会失败）。
- `package_app.sh` 在 `vendor/lib/libwhisper.a` 缺失时会自动先跑 `build_vendor.sh`。

## 构建/打包注意事项

- **dev/release 双轨**：Bundle ID、图标、App 名均不同（见 BUILDING.md 对照表）。改 Info.plist 模板后由 PlistBuddy 在打包时改写，不要在 .app 产物上直接改。
- **签名身份必须固定**：TCC（辅助功能授权）绑定签名，换证书/改 Bundle ID 都会使授权失效，需用户重新授权。
- 产物为 Universal（arm64 + x86_64，两次 swiftc + lipo）。

## 测试注意事项

- `tests/run_corpus_mac.py` 依赖 `build-mac/bin/whisper-cli`（CMake 构建的 whisper-cli，不在常规构建链路上；缺失需先构建）。
- **测试脚本默认模型是 `~/.cache/vibetalk/ggml-base-q8_0.bin`，与应用实际使用的 medium-q8_0 不同**——对比应用行为时务必用 `--model` 指向 `~/Library/Application Support/VibeTalk/ggml-medium-q8_0.bin`。
- 语料格式：`tests/corpus.txt` 每行 `id<TAB>期望文本`，id 用 `zh_/mixed_/en_` 前缀区分语言场景；改后需重跑 `generate_test_audio.sh` 再跑测试。
- 通过标准为归一化编辑距离相似度 ≥ 0.55（`--min-sim`）。

## 代码约定（未文档化的关键实现，勿随意改动）

`Sources/WhisperTranscriber.swift`：

- **initial prompt 即术语表**：`defaultPrompt` 内置编程术语文案，是识别专有名词的关键，语料回归证明有效（0.84→0.96+）。修改后必须跑语料测试验证。
- **audio_ctx 裁剪**：`samples.count / 320 + 128` 钳制到 **[512, 1500]**。512 是实测准确度临界值，**不得低于**（<512 会丢内容/空识别）。
- **语言检测限制 zh/en**：不用 whisper 原生 auto（全语言检测会把中文误判成日文），取全部概率后只比较 zh/en，失败回落 zh。
- **必须保留时间戳解码**：`no_timestamps=false`，否则句间停顿提前 EOT，只输出第一句。
- GPU 初始化失败自动回落 CPU（双层兜底）。

`Sources/TextInjector.swift`：

- 粘贴前深拷贝备份剪贴板所有 item/type，模拟 Cmd+V 后 **200ms** 恢复。未授权辅助功能时只复制不粘贴（不恢复），并发通知。

`Sources/HotkeyMonitor.swift`：

- 支持 右⌘Command（默认，keyCode 54）/ 右⌥Option / 右⇧Shift / Fn，flagsChanged 全局+本地双监听；选择持久化于 UserDefaults key `hotkeyChoice`。

其他：

- 录音 < 0.3s 丢弃；录音开始播放系统音 "Funk"。
- 日志：`~/Library/Logs/VibeTalk.log`（`Log.write()`，stderr + 文件双写）。排查问题先看日志：热键事件 → 采样数 → 识别文本 → 注入结果逐层定位。
- 模型路径：`~/Library/Application Support/VibeTalk/ggml-medium-q8_0.bin`（下载自 HuggingFace ggerganov/whisper.cpp）。

## CLI 调试模式

```bash
build/VibeTalk.app/Contents/MacOS/VibeTalk --transcribe some.wav   # 转写 16kHz 单声道 16bit WAV
build/VibeTalk.app/Contents/MacOS/VibeTalk --record 5              # 录音 5 秒并转写
```

- `--transcribe` 的模型路径可用环境变量 `VIBETALK_MODEL` 覆盖；`--record` 固定用默认路径。
- CLI 模式下不会启动 GUI（命中参数即执行并 exit）。

## 仓库卫生

- gitignore 已覆盖 `build/`、`build-mac/`、`build-vendor/`、`vendor/lib`、`vendor/include`、`.gradle/`。
- `vendor/whisper.cpp` 是 submodule，pin 在 v1.9.2；升级 whisper.cpp 前注意 large-v3-turbo 的 ggml 模型文件与其 tensor 布局不兼容的已知问题。
