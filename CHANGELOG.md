# 更新日志

本项目的所有重要变更都记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### 变更
- 菜单栏：麦克风 / 识别语言 / 热键三个子菜单标题不再显示当前状态，选中项以勾选标记显示

## [1.0.0] - 2026-08-12

### 新增
- 菜单栏语音输入：按住全局热键说话，松手后本地识别并自动粘贴到当前输入框
- 全局热键可切换：右 ⌘Command（默认）/ 右 ⌥Option / 右 ⇧Shift / Fn，选择持久化
- 本地识别：whisper.cpp medium-q8_0 模型，Metal GPU 加速，GPU 不可用时自动回落 CPU
- 中英混合优化：内置编程术语引导词（initial prompt），可自定义术语表
- 语言选择：菜单勾选中文 / 英语 / 日语作为识别候选（默认中文 + 英语）
- 自动粘贴：写入剪贴板并模拟 Cmd+V；粘贴前备份剪贴板，粘贴后 200ms 恢复
- 麦克风跟随系统默认输入设备，可手动切换，热插拔自动刷新
- 录音状态可见：录音中菜单栏图标绿色圆底，识别中橙色圆点；开始录音播放提示音（Funk）
- 模型下载：首次使用菜单内一键下载（medium-q8_0，~785MB），带进度显示
- 术语表编辑窗口：应用内编辑，保存后立即生效
- 辅助功能权限引导：未授权时降级为仅复制剪贴板 + 通知
- 语料质量测试工装（tests/）：TTS 生成语料 → 转写 → 相似度断言

### 修复
- audio_ctx 下限 512：低于此值会丢内容/空识别
- zh/en 受限语言检测：避免 whisper auto 将中文短句误判成日文
- 日文识别乱码：日文不注入中文术语 prompt，清洗异常码点
- 术语表窗口在 LSUIElement 应用下无法弹出（改用 NSWindow 控制器）
- Metal 退出时断言崩溃（显式 whisper_free）

### 工程
- dev/release 双轨打包：不同 Bundle ID、图标、App 名，可共存
- 固定自签名证书签名，辅助功能授权跨构建保持
- Universal 二进制（arm64 + x86_64），最低 macOS 14
- GitHub Actions release workflow：证书从 Secrets 导入、打包、发布 Release
- AGENTS.md 面向 AI 代理的工作指南

### 已知问题
- 自签名应用无法通过 Gatekeeper 公证，分发需右击打开或移除隔离属性
- 蓝牙耳机（HFP 模式）麦克风为窄带音质，识别略逊于内置麦克风
