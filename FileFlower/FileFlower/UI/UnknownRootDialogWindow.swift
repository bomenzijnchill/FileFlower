import SwiftUI
import AppKit

class UnknownRootDialogWindowController: NSWindowController, NSWindowDelegate {
    /// Sterke referenties naar open dialogen (zie ConflictDialogWindowController):
    /// met één statische `shared` sloot de resolutie van het eerste venster het
    /// laatste, waardoor items zonder antwoord in de wachtrij bleven staan.
    private static var openControllers: [UnknownRootDialogWindowController] = []

    /// Projecten waarvoor al een dialoog open staat — root-goedkeuring is per project,
    /// dus een batch van 5 items uit hetzelfde project toont nog maar één venster.
    private static var openProjectPaths: Set<String> = []

    let project: ProjectInfo
    var onResolve: ((UnknownRootDialog.UnknownRootResolution) -> Void)?
    private var didResolve = false

    /// Staat er al een dialoog open voor dit project?
    static func isShowing(for project: ProjectInfo) -> Bool {
        openProjectPaths.contains(project.projectPath)
    }

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

        super.init(window: window)

        let contentView = UnknownRootDialog(project: project) { [weak self] resolution in
            self?.finish(with: resolution)
        }
        .frame(width: 500, height: 350)

        window.contentView = NSHostingView(rootView: contentView)
        window.delegate = self

        Self.openControllers.append(self)
        Self.openProjectPaths.insert(project.projectPath)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(with resolution: UnknownRootDialog.UnknownRootResolution) {
        guard !didResolve else { return }
        didResolve = true
        onResolve?(resolution)
        close()
    }

    /// Wegklikken = annuleren (item blijft in de wachtrij, maar niet in limbo)
    func windowWillClose(_ notification: Notification) {
        if !didResolve {
            didResolve = true
            onResolve?(.cancel)
        }
        Self.openControllers.removeAll { $0 === self }
        Self.openProjectPaths.remove(project.projectPath)
    }

    override func close() {
        window?.close()
        Self.openControllers.removeAll { $0 === self }
        Self.openProjectPaths.remove(project.projectPath)
    }
}
