# 构建与开发

本文档包含 VibeTalk 的编译、签名、测试与开发调试相关内容。使用者请先看 [README](../README.md)。

## 构建

依赖：macOS（arm64/x86_64）、Xcode Command Line Tools（swiftc）、CMake、Ninja。

```bash
git submodule update --init   # 拉取 vendor/whisper.cpp
./scripts/build_vendor.sh     # 编译 whisper.cpp 静态库（Metal，双架构）
./scripts/package_app.sh      # 编译 Swift + 打包 + 签名（开发版）
open "build/VibeTalk Dev.app"
```

打包模式：

| 模式 | 命令 | Bundle ID | 图标 | App 名 |
|---|---|---|---|---|
| 开发版（默认） | `./scripts/package_app.sh` 或 `--dev` | `io.github.kyze8439690.VibeTalk.dev` | 橙红 + DEV | VibeTalk Dev |
| 正式版 | `./scripts/package_app.sh --release` | `io.github.kyze8439690.VibeTalk` | 蓝紫 | VibeTalk |

两个版本可共存安装，注意两者辅助功能权限独立授予。图标由 `scripts/make_icons.sh` 重新生成（调 `make_icon.swift` + iconutil）。

产物为 Universal 二进制（arm64 + x86_64），最低系统 macOS 14。

## 签名说明

应用使用本地自签名证书 **"VibeTalk Local Signing"** 签名（首次打包前需创建，见下方），因为 macOS 的辅助功能授权（TCC）绑定签名身份——证书不变，重新打包后权限保持。

```bash
# 创建自签名证书（一次性）
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -subj "/CN=VibeTalk Local Signing" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning"
openssl pkcs12 -legacy -export -out vt.p12 -inkey key.pem -in cert.pem \
  -passout pass:vibetalk -name "VibeTalk Local Signing"
security import vt.p12 -k ~/Library/Keychains/login.keychain-db -P vibetalk -A -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
```

> 自签名无法过 Gatekeeper 公证，分发时用户需右击打开。正式分发需 Apple Developer ID + notarization。

## 识别质量测试

`tests/` 内置语料工装：macOS TTS 生成编程场景中英混合语音，跑 whisper 转写并计算归一化编辑距离相似度。

```bash
./scripts/generate_test_audio.sh        # 生成语料音频（macOS say TTS）
python3 tests/run_corpus_mac.py \
  --model ~/.cache/vibetalk/ggml-medium-q8_0.bin \
  --language auto                       # 可选 --prompt / --threads / --min-sim
```

当前 medium-q8_0 在 10 条语料上平均相似度 1.00（base-q8_0 为 0.96）。新增语料只需在 `tests/corpus.txt` 加一行 `id<TAB>期望文本` 并重跑生成脚本。

## 调试模式

```bash
# 直接转写已有 WAV（16kHz 单声道 16bit）
build/VibeTalk.app/Contents/MacOS/VibeTalk --transcribe some.wav

# 录音 N 秒并转写（验证麦克风链路）
build/VibeTalk.app/Contents/MacOS/VibeTalk --record 5
```

运行日志：`~/Library/Logs/VibeTalk.log`

## 目录结构

```
Sources/            # SwiftUI 应用源码
  VibeTalkApp.swift       # 菜单栏入口 + CLI 调试模式
  AppState.swift          # 状态机：录音→识别→注入
  AudioRecorder.swift     # AVAudioEngine 采集 + 16kHz 重采样 + 设备管理
  WhisperTranscriber.swift# whisper.cpp C API 封装（zh/en 受限语言检测）
  HotkeyMonitor.swift     # 全局热键按住检测（flagsChanged）
  TextInjector.swift      # 剪贴板 + Cmd+V 注入（辅助功能）
  ModelManager.swift      # 模型下载
Resources/          # Info.plist + 图标
vendor/whisper.cpp  # 语音引擎（git submodule，lib/include 由脚本生成）
scripts/            # 构建/打包/图标/语料脚本
tests/              # 识别质量语料测试
```

## 关键技术决策记录

- **模型 medium-q8_0**：速度与准确度平衡点；small-q8_0 语料 0.97、medium-q8_0 1.00。large-v3-turbo 的 ggml 文件与 whisper.cpp v1.9.2 tensor 布局不兼容，不可用
- **音频上下文裁剪**：`audio_ctx = max(512, 音频长度)`——whisper 默认按 30s 窗口跑 encoder，短语音裁剪后显著加速；下限 512 是实测的准确度临界值（<512 会丢内容/空识别）
- **语言检测限制 zh/en**：whisper `auto` 全语言检测在短句上会把中文误判成日文，改为只在中文/英文间取概率高者
- **initial prompt 引导**：注入编程术语文案后，"git commit / push" 等术语识别从丢失到正确，语料相似度 0.84 → 0.96+
- **时间戳解码**：`no_timestamps=false` 必须保留，否则句间停顿处会提前 EOT 导致只输出第一句话
- **Android 端 GPU 不可用**（早期原型结论）：realme ColorOS 上 Vulkan 驱动编译 shader 段错误；Android 16 linker 命名空间隔离禁止加载 OpenCL；故放弃手机端，识别全部在 Mac 本地完成

## 术语表

| 术语 | 说明 |
|---|---|
| whisper.cpp | OpenAI Whisper 模型的 C/C++ 推理实现（ggml 后端），本项目用它做本地语音识别 |
| ggml | whisper.cpp 底层的张量计算库，支持 CPU/Metal/Vulkan/OpenCL 等后端 |
| Q8_0 | 8-bit 量化格式，模型体积约为 fp16 的一半，精度损失很小 |
| Metal | Apple GPU 计算框架；whisper.cpp 在 macOS 上通过它实现 GPU 加速 |
| audio_ctx | whisper 的音频上下文窗口（单位 20ms，1500=30s）。短语音裁剪此窗口可显著加速 |
| initial prompt | 给 whisper 的引导词，声明内容风格和术语，可显著提升专有名词识别率 |
| zh/en 受限语言检测 | whisper 原生 auto 检测遍历全部 99 种语言，短句易误判日文；本项目只在中文/英文间取概率高者 |
| TCC | macOS 隐私权限框架（Transparency, Consent, Control），辅助功能授权绑定应用签名身份 |
| 辅助功能权限 | Accessibility 权限，模拟 Cmd+V 粘贴所必需；系统设置 → 隐私与安全性 → 辅助功能 |
| HFP | 蓝牙耳机的通话模式（Hands-Free Profile），开麦时自动切换，音质降为窄带 |
| AVAudioEngine | macOS/iOS 音频采集框架，本项目的录音入口 |
| CGEvent | macOS 底层事件注入 API，用于模拟 Cmd+V 键盘事件 |
| adhoc 签名 | `codesign -s -` 的临时签名，cdhash 随构建变化，TCC 权限不保持 |
| Gatekeeper / notarization | macOS 应用分发安全检查；自签名应用未公证，首次需右击打开 |
| 语料测试 | `tests/` 下的识别质量回归工装，TTS 生成语音 → 转写 → 相似度断言 |
| 相似度（sim） | 归一化编辑距离（1 - Levenshtein/长度），1.0 为完全一致 |
