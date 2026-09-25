import SwiftUI
import AppKit

class SettingsWindowController: NSObject, NSWindowDelegate {
    private static var windowController: NSWindowController?
    private static var delegate: SettingsWindowController?

    static func show() {
        if let existing = windowController, let window = existing.window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let delegateInstance = SettingsWindowController()
        delegate = delegateInstance

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "common.settings")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.minSize = NSSize(width: 980, height: 680)
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("FileFlowerSettingsWindow")
        window.delegate = delegateInstance

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func close() {
        windowController?.close()
        windowController = nil
        delegate = nil
    }

    func windowWillClose(_ notification: Notification) {
        SettingsWindowController.windowController = nil
        SettingsWindowController.delegate = nil
    }
}
