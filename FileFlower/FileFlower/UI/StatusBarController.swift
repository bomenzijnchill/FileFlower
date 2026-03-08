import SwiftUI
import AppKit

/// Beheert het menubar icoon en de popover die verschijnt bij klik of nieuwe downloads
class StatusBarController: NSObject, NSPopoverDelegate {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem
    private var popover: NSPopover

    private override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        super.init()

        // Configureer de popover
        popover.contentSize = NSSize(width: 520, height: 500)
        popover.behavior = .transient // Sluit automatisch bij klik erbuiten
        popover.animates = true
        popover.delegate = self

        let hostingController = NSHostingController(rootView: MenuBarView())
        popover.contentViewController = hostingController

        // Configureer het status bar icoon
        if let button = statusItem.button {
            if let menuBarIcon = NSImage(named: "MenuBarIcon") {
                menuBarIcon.size = NSSize(width: 18, height: 18)
                button.image = menuBarIcon
            } else {
                // Fallback naar system symbol als custom icoon niet gevonden wordt
                button.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "FileFlower")
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        // Clear afgeronde items uit de queue wanneer de popover sluit
        DispatchQueue.main.async {
            AppState.shared.clearFinishedItems()
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            hidePopover()
        } else {
            showPopover()
        }
    }

    /// Toon de popover onder het menubar icoon
    func showPopover() {
        guard let button = statusItem.button else { return }

        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// Verberg de popover
    func hidePopover() {
        popover.performClose(nil)
    }

    /// Check of de popover zichtbaar is
    var isShown: Bool {
        return popover.isShown
    }

    /// Schermpositie van het status bar icoon (voor positionering van overlays)
    var statusItemFrame: NSRect? {
        guard let button = statusItem.button,
              let window = button.window else { return nil }
        let buttonFrame = button.convert(button.bounds, to: nil)
        return window.convertToScreen(buttonFrame)
    }

    /// Zet de popover behavior (bijv. om te voorkomen dat het sluit tijdens NSOpenPanel)
    func setPopoverBehavior(_ behavior: NSPopover.Behavior) {
        popover.behavior = behavior
    }
}
