import SwiftUI
import AppKit
import Quartz

class FileSafeWindowController: NSWindowController, NSWindowDelegate {
    static var shared: FileSafeWindowController?

    init(initialVolume: ExternalVolume? = nil) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FileSafe"
        window.center()
        window.isReleasedWhenClosed = false
        window.restorationClass = nil
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.minSize = NSSize(width: 650, height: 550)

        let contentView = FileSafeView(initialVolume: initialVolume)
        window.contentView = NSHostingView(rootView: contentView)

        super.init(window: window)
        window.delegate = self
        FileSafeWindowController.shared = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func close() {
        window?.close()
        FileSafeWindowController.shared = nil
    }

    func windowWillClose(_ notification: Notification) {
        FileSafeWindowController.shared = nil
    }

    // MARK: - QLPreviewPanel Support

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = FileSafeQuickLookCoordinator.shared
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        // Coordinator behoudt eigen state
    }
}
