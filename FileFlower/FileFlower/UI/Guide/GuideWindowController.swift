import SwiftUI
import AppKit

/// Toont de gids in een eigen venster.
/// Zelfde patroon als `OnboardingWindowController`, maar ruimer omdat er een
/// hoofdstukzijbalk naast de inhoud staat.
class GuideWindowController: NSObject, NSWindowDelegate {
    private static var windowController: NSWindowController?
    private static var delegate: GuideWindowController?

    /// Opent de gids. Geef een `chapter` mee om direct op dat hoofdstuk te openen
    /// (bijvoorbeeld vanuit de lege staat van een tabblad).
    static func show(chapter: GuideChapter? = nil) {
        // Sluit bestaand window als dat er is
        windowController?.close()

        if let chapter, GuideChapter.enabled.contains(chapter) {
            GuideManager.shared.lastChapter = chapter
        }

        let delegateInstance = GuideWindowController()
        delegate = delegateInstance

        let guideView = GuideView(onClose: {
            close()
        })

        let hostingController = NSHostingController(rootView: guideView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "guide.window_title")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 920, height: 640))
        window.minSize = NSSize(width: 820, height: 560)
        window.center()
        window.isReleasedWhenClosed = false
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

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        GuideWindowController.windowController = nil
        GuideWindowController.delegate = nil
    }
}
