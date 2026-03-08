import SwiftUI
import AppKit

class UnknownRootDialogWindowController: NSWindowController {
    static var shared: UnknownRootDialogWindowController?

    let project: ProjectInfo
    var onResolve: ((UnknownRootDialog.UnknownRootResolution) -> Void)?

    init(project: ProjectInfo, onResolve: @escaping (UnknownRootDialog.UnknownRootResolution) -> Void) {
        self.project = project
        self.onResolve = onResolve

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "unknown_root.window_title")
        window.center()
        window.isReleasedWhenClosed = false
        window.restorationClass = nil

        // Floating voor zichtbaarheid (zelfde als ConflictDialogWindowController)
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let contentView = UnknownRootDialog(project: project) { resolution in
            onResolve(resolution)
            UnknownRootDialogWindowController.shared?.close()
        }
        .frame(width: 500, height: 350)

        window.contentView = NSHostingView(rootView: contentView)

        super.init(window: window)

        UnknownRootDialogWindowController.shared = self
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
        UnknownRootDialogWindowController.shared = nil
    }
}
