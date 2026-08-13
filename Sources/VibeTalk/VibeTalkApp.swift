import SwiftUI
import AVFoundation
import FirebaseCore

@main
struct VibeTalkApp: App {
    @StateObject private var appState = AppState.shared

    init() {
        Self.runCLIModeIfRequested()
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        } else {
            Log.write("Firebase: GoogleService-Info.plist 缺失，未初始化")
        }
    }

    static func runCLIModeIfRequested() {
        let args = CommandLine.arguments

        if let flagIndex = args.firstIndex(of: "--record"), args.count > flagIndex + 1,
           let seconds = Double(args[flagIndex + 1]) {
            runRecordSelfTest(seconds: seconds)
        }

        guard let flagIndex = args.firstIndex(of: "--transcribe"), args.count > flagIndex + 1 else { return }
        let wavPath = args[flagIndex + 1]
        let modelPath = ProcessInfo.processInfo.environment["VIBETALK_MODEL"]
            ?? ModelManager().modelURL.path

        guard let samples = WavReader.readFloatMono16k(path: wavPath) else {
            FileHandle.standardError.write("无法读取 WAV: \(wavPath)\n".data(using: .utf8)!)
            exit(1)
        }
        guard let transcriber = WhisperTranscriber(modelPath: modelPath) else {
            FileHandle.standardError.write("模型加载失败: \(modelPath)\n".data(using: .utf8)!)
            exit(1)
        }
        let languages = cliLanguages()
        let start = Date()
        let text = transcriber.transcribe(samples, languages: languages)
        let elapsed = Date().timeIntervalSince(start)
        print(text)
        FileHandle.standardError.write(
            String(format: "音频 %.1fs, 识别 %.0fms\n", Float(samples.count) / 16000, elapsed * 1000).data(using: .utf8)!
        )
        transcriber.close()
        exit(0)
    }

    private static func cliLanguages() -> [String] {
        let env = ProcessInfo.processInfo.environment["VIBETALK_LANGUAGES"] ?? ""
        let list = env.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return list.isEmpty ? ["zh", "en"] : list
    }

    static func runRecordSelfTest(seconds: Double) {
        let sem = DispatchSemaphore(value: 0)
        AVCaptureDevice.requestAccess(for: .audio) { _ in sem.signal() }
        sem.wait()

        let recorder = AudioRecorder()
        do {
            try recorder.start(deviceID: 0)
            Log.write("SelfTest: 录音 \(seconds)s 中…")
        } catch {
            FileHandle.standardError.write("录音启动失败: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
        Thread.sleep(forTimeInterval: seconds)
        let samples = recorder.stop()
        FileHandle.standardError.write("采集 \(samples.count) 采样\n".data(using: .utf8)!)

        guard let transcriber = WhisperTranscriber(modelPath: ModelManager().modelURL.path) else {
            FileHandle.standardError.write("模型加载失败\n".data(using: .utf8)!)
            exit(1)
        }
        let start = Date()
        let text = transcriber.transcribe(samples)
        let elapsed = Date().timeIntervalSince(start)
        print(text)
        FileHandle.standardError.write(String(format: "识别 %.0fms\n", elapsed * 1000).data(using: .utf8)!)
        transcriber.close()
        exit(0)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(appState: appState)
        } label: {
            if appState.recording {
                Image(systemName: "mic.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Circle().fill(Color.green))
            } else if appState.transcribing {
                Image(systemName: "ellipsis")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Circle().fill(Color.orange))
            } else {
                Image(systemName: "mic")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContentView: View {
    @ObservedObject var appState: AppState

    private func toggleLanguage(_ code: String) {
        if appState.selectedLanguages.contains(code) {
            guard appState.selectedLanguages.count > 1 else { return }
            appState.selectedLanguages.remove(code)
        } else {
            appState.selectedLanguages.insert(code)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(appState.statusText)
            Divider()

            Menu("麦克风") {
                Button {
                    appState.selectDevice(0)
                } label: {
                    if appState.followSystem {
                        Label(appState.selectedDeviceName, systemImage: "checkmark")
                    } else {
                        Text(appState.selectedDeviceName)
                    }
                }
                ForEach(appState.inputDevices) { device in
                    Button {
                        appState.selectDevice(device.id)
                    } label: {
                        if !appState.followSystem && device.id == appState.selectedDeviceID {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            }

            Menu("识别语言") {
                Button {
                    toggleLanguage("zh")
                } label: {
                    if appState.selectedLanguages.contains("zh") {
                        Label("中文", systemImage: "checkmark")
                    } else {
                        Text("中文")
                    }
                }
                Button {
                    toggleLanguage("en")
                } label: {
                    if appState.selectedLanguages.contains("en") {
                        Label("英语", systemImage: "checkmark")
                    } else {
                        Text("英语")
                    }
                }
                Button {
                    toggleLanguage("ja")
                } label: {
                    if appState.selectedLanguages.contains("ja") {
                        Label("日语", systemImage: "checkmark")
                    } else {
                        Text("日语")
                    }
                }
            }

            Menu("热键") {
                ForEach(HotkeyChoice.allCases, id: \.self) { choice in
                    Button {
                        appState.hotkeyChoice = choice
                    } label: {
                        if choice == appState.hotkeyChoice {
                            Label(choice.label, systemImage: "checkmark")
                        } else {
                            Text(choice.label)
                        }
                    }
                }
            }

            Button("术语表…") {
                GlossaryWindowController.shared.show()
            }

            Divider()

            if !appState.modelReady {
                if appState.downloading {
                    Text("下载模型中 \(Int(appState.downloadProgress * 100))%")
                } else {
                    Button("下载模型 (medium-q8_0, ~785MB)") {
                        appState.downloadModel()
                    }
                }
            }

            if appState.accessibilityTrusted {
                Label("辅助功能：已授权", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Button("开启辅助功能权限（用于自动粘贴）") {
                    appState.promptAccessibility()
                }
            }

            if let last = appState.lastResult {
                Divider()
                Text("上次识别：\(last)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()
            Text("按住 \(appState.hotkeyChoice.label) 说话，松手识别")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            Text("VibeTalk \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .onAppear {
            appState.refreshDevices()
        }
    }
}
