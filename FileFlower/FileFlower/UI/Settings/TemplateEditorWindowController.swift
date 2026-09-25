import SwiftUI
import AppKit

class TemplateEditorWindowController: NSObject, NSWindowDelegate {
    private static var windowController: NSWindowController?
    private static var delegate: TemplateEditorWindowController?

    static func show() {
        if let existing = windowController, let window = existing.window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let delegateInstance = TemplateEditorWindowController()
        delegate = delegateInstance

        let view = TemplateEditorWindowView()
        let hostingController = NSHostingController(rootView: view)

        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "settings.card.template_editor")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 900, height: 640))
        window.minSize = NSSize(width: 760, height: 520)
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("FileFlowerTemplateEditorWindow")
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
        TemplateEditorWindowController.windowController = nil
        TemplateEditorWindowController.delegate = nil
    }
}

/// Wrapper for the existing FolderStructureTemplateView, with auto-save on changes.
private struct TemplateEditorWindowView: View {
    @StateObject private var appState = AppState.shared
    @State private var preset: FolderStructurePreset = .standard

    var body: some View {
        FolderStructureTemplateView(
            appState: appState,
            folderStructurePreset: Binding(
                get: { appState.config.folderStructurePreset },
                set: {
                    appState.config.folderStructurePreset = $0
                    preset = $0
                }
            ),
            onSave: { appState.saveConfig() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            preset = appState.config.folderStructurePreset
        }
    }
}
