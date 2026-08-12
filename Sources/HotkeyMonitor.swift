import AppKit

enum HotkeyChoice: String, CaseIterable {
    case rightCommand
    case rightOption
    case rightShift
    case fn

    var label: String {
        switch self {
        case .rightCommand: return "右 ⌘Command"
        case .rightOption: return "右 ⌥Option"
        case .rightShift: return "右 ⇧Shift"
        case .fn: return "Fn"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightCommand: return 54
        case .rightOption: return 61
        case .rightShift: return 60
        case .fn: return 63
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .rightCommand: return .command
        case .rightOption: return .option
        case .rightShift: return .shift
        case .fn: return .function
        }
    }
}

final class HotkeyMonitor {

    var hotkey: HotkeyChoice = .rightCommand

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pressed = false

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == hotkey.keyCode else { return }
        let isDown = event.modifierFlags.contains(hotkey.flag)

        DispatchQueue.main.async {
            if isDown && !self.pressed {
                self.pressed = true
                Log.write("HotkeyMonitor: \(self.hotkey.label) 按下")
                self.onKeyDown?()
            } else if !isDown && self.pressed {
                self.pressed = false
                Log.write("HotkeyMonitor: \(self.hotkey.label) 松开")
                self.onKeyUp?()
            }
        }
    }
}
