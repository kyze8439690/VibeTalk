import AVFoundation
import AppKit
import Combine

final class AppState: ObservableObject {

    static let shared = AppState()

    @Published var recording = false
    @Published var transcribing = false
    @Published var modelReady = false
    @Published var downloading = false
    @Published var downloadProgress: Float = 0
    @Published var accessibilityTrusted = false
    @Published var inputDevices: [AudioInputDevice] = []
    @Published var selectedDeviceID: AudioDeviceID = 0
    @Published var systemDefaultDeviceID: AudioDeviceID = 0
    @Published var hotkeyChoice: HotkeyChoice = .rightCommand {
        didSet {
            hotkey.hotkey = hotkeyChoice
            UserDefaults.standard.set(hotkeyChoice.rawValue, forKey: "hotkeyChoice")
        }
    }
    @Published var lastResult: String?
    @Published var statusMessage = "初始化中…"
    @Published var glossaryText = ""

    var followSystem: Bool { selectedDeviceID == 0 }

    var selectedDeviceName: String {
        if followSystem {
            if let name = inputDevices.first(where: { $0.id == systemDefaultDeviceID })?.name {
                return "跟随系统（\(name)）"
            }
            return "跟随系统"
        }
        return inputDevices.first { $0.id == selectedDeviceID }?.name ?? "跟随系统"
    }

    var statusText: String {
        if recording { return "录音中…" }
        if transcribing { return "识别中…" }
        if downloading { return "下载模型中…" }
        if !modelReady { return statusMessage }
        return statusMessage
    }

    private let recorder = AudioRecorder()
    private var transcriber: WhisperTranscriber?
    private let modelManager = ModelManager()
    private let hotkey = HotkeyMonitor()
    private var permissionTimer: Timer?

    private init() {
        requestMicPermission()
        refreshDevices()
        glossaryText = modelManager.loadGlossary().joined(separator: "\n")
        AudioRecorder.addDeviceChangeListener { [weak self] in
            self?.refreshDevices()
        }
        if let saved = UserDefaults.standard.string(forKey: "hotkeyChoice"),
           let choice = HotkeyChoice(rawValue: saved) {
            hotkeyChoice = choice
        }
        hotkey.hotkey = hotkeyChoice
        hotkey.onKeyDown = { [weak self] in self?.startRecording() }
        hotkey.onKeyUp = { [weak self] in self?.stopRecordingAndTranscribe() }
        hotkey.start()

        accessibilityTrusted = TextInjector.isTrusted()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            let trusted = TextInjector.isTrusted()
            if trusted != self?.accessibilityTrusted {
                self?.accessibilityTrusted = trusted
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.transcriber?.close()
        }

        if modelManager.isModelReady {
            loadModel()
        } else {
            statusMessage = "模型未下载"
        }
    }

    private func requestMicPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        Log.write("Mic: 当前权限状态=\(status.rawValue)")
        if status == .denied || status == .restricted {
            statusMessage = "麦克风权限被拒绝，请在系统设置中开启"
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Log.write("Mic: requestAccess 结果=\(granted)")
            if !granted {
                DispatchQueue.main.async {
                    self.statusMessage = "麦克风权限被拒绝，请在系统设置中开启"
                }
            }
        }
    }

    func refreshDevices() {
        inputDevices = AudioRecorder.listInputDevices()
        systemDefaultDeviceID = AudioRecorder.defaultInputDeviceID()
        if !followSystem && !inputDevices.contains(where: { $0.id == selectedDeviceID }) {
            selectedDeviceID = 0
        }
    }

    func selectDevice(_ id: AudioDeviceID) {
        selectedDeviceID = id
    }

    func downloadModel() {
        guard !downloading else { return }
        downloading = true
        downloadProgress = 0
        Task {
            do {
                try await modelManager.download { [weak self] progress in
                    Task { @MainActor in self?.downloadProgress = progress }
                }
                await MainActor.run {
                    self.downloading = false
                    self.loadModel()
                }
            } catch {
                await MainActor.run {
                    self.downloading = false
                    self.statusMessage = "下载失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func loadModel() {
        statusMessage = "加载模型中…"
        Task.detached { [weak self] in
            let transcriber = WhisperTranscriber(modelPath: ModelManager().modelURL.path)
            await MainActor.run {
                if transcriber != nil {
                    self?.transcriber = transcriber
                    self?.modelReady = true
                    self?.statusMessage = "就绪"
                } else {
                    self?.statusMessage = "模型加载失败"
                }
            }
        }
    }

    private func startRecording() {
        Log.write("Hotkey: 按下 (ready=\(modelReady), recording=\(recording), transcribing=\(transcribing))")
        guard modelReady, !recording, !transcribing else { return }
        do {
            try recorder.start(deviceID: selectedDeviceID)
            recording = true
            NSSound(named: "Funk")?.play()
        } catch {
            statusMessage = "录音启动失败：\(error.localizedDescription)"
            Log.write("Hotkey: 录音启动失败 \(error)")
        }
    }

    private func stopRecordingAndTranscribe() {
        Log.write("Hotkey: 松开 (recording=\(recording))")
        guard recording else { return }
        let samples = recorder.stop()
        recording = false

        let seconds = Float(samples.count) / 16000
        guard seconds > 0.3 else {
            statusMessage = "录音太短"
            return
        }

        guard let transcriber else { return }
        transcribing = true
        Task.detached { [weak self] in
            let start = Date()
            let text = transcriber.transcribe(samples)
            let elapsed = Date().timeIntervalSince(start)
            Log.write("Transcribe: 文本=\(text.isEmpty ? "(空)" : text)")
            await MainActor.run {
                self?.transcribing = false
                if text.isEmpty {
                    self?.statusMessage = "未识别到内容"
                } else {
                    self?.lastResult = text
                    self?.statusMessage = String(format: "就绪（%.1fs 音频，识别 %.0fms）", seconds, elapsed * 1000)
                    let pasted = TextInjector.inject(text)
                    Log.write("Inject: pasted=\(pasted)")
                    if !pasted {
                        self?.statusMessage = "已复制到剪贴板（未授权辅助功能，无法自动粘贴）"
                    }
                }
            }
        }
    }

    func promptAccessibility() {
        TextInjector.prompt()
    }

    func saveGlossary(_ text: String) {
        let terms = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        modelManager.saveGlossary(terms)
        glossaryText = terms.joined(separator: "\n")
    }
}
