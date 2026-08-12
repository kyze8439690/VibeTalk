import AppKit
import ApplicationServices
import UserNotifications

enum TextInjector {

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func prompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func inject(_ text: String) -> Bool {
        copyToPasteboard(text)

        guard isTrusted() else {
            Log.write("Inject: 未授权辅助功能，仅复制剪贴板")
            notify(title: "VibeTalk", body: "已复制到剪贴板（未授权辅助功能，请手动粘贴）")
            return false
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        Log.write("Inject: 已写入剪贴板并发送 Cmd+V")
        return true
    }

    private static func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func notify(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }
}
