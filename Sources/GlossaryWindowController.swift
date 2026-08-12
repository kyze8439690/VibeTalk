import AppKit
import SwiftUI

final class GlossaryWindowController: NSObject, NSWindowDelegate {

    static let shared = GlossaryWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: GlossaryEditorView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "术语表"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.setContentSize(NSSize(width: 420, height: 420))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // 保持引用，重开复用
    }
}
