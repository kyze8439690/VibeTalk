# VibeTalk

<p align="center">
  <img src="Resources/icon_1024.png" width="160" alt="VibeTalk">
</p>

macOS 菜单栏语音输入工具：按住全局热键说话，松手后本地语音识别转文字，自动粘贴到当前输入框。为 vibecoding 场景设计（中英混合、编程术语优化）。

完全本地运行，基于 [whisper.cpp](https://github.com/ggml-org/whisper.cpp) + Metal GPU 加速，无网络依赖（仅首次下载模型需要联网）。

## 功能

- **按住说话**：按住右 ⌘Command（可切换 右⌥Option / 右⇧Shift / Fn）开始录音，松手自动识别并粘贴
- **本地识别**：whisper medium-q8_0 模型，Metal 加速；中英混合优化，内置编程术语引导词
- **自动粘贴**：写入剪贴板并模拟 Cmd+V 输入到当前焦点输入框
- **麦克风**：默认跟随系统输入设备，可手动指定蓝牙耳机等；热插拔自动刷新
- **状态可见**：录音时菜单栏图标绿色圆底、识别中橙色；开始录音有提示音

## 构建

依赖：macOS（arm64/x86_64）、Xcode Command Line Tools（swiftc）、CMake、Ninja。

```bash
git submodule update --init   # 拉取 vendor/whisper.cpp
./scripts/build_vendor.sh     # 编译 whisper.cpp 静态库（Metal，双架构）
./scripts/package_app.sh      # 编译 Swift + 打包 + 签名
open build/VibeTalk.app
```

产物为 Universal 二进制（arm64 + x86_64），最低系统 macOS 14。

## 首次使用

1. 启动后授予**麦克风权限**
2. 首次识别前需下载模型（medium-q8_0，~785MB，菜单内一键下载）
3. 菜单中点击**开启辅助功能权限**（用于模拟粘贴；未授权时降级为仅复制剪贴板 + 通知）
4. 在任意输入框按住右 ⌘Command 说话，松手即得文字

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

调试模式：

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
