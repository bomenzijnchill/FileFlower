import SwiftUI
import AppKit
#if canImport(BridgeKit)
import BridgeKit
#endif

#if canImport(BridgeKit)
/// Los venster voor de Bridge-verkenner.
///
/// De verkenner past niet in de popover: de locatierail is alleen al 168 pt
/// breed en vraagt 320 pt hoogte, en daarnaast moeten pad, naam, badge, datum en
/// grootte per rij passen. In 520 pt lukt dat niet.
///
/// Zelfde patroon als SettingsWindowController — inclusief de statische
/// `delegate`. Die is functioneel, niet cosmetisch: NSWindow.delegate is weak,
/// dus zonder die extra sterke referentie wordt de delegate opgeruimd, vuurt
/// windowWillClose nooit en geeft show() daarna een dood venster terug.
class BridgeExplorerWindowController: NSObject, NSWindowDelegate {
    private static var windowController: NSWindowController?
    private static var delegate: BridgeExplorerWindowController?

    static func show() {
        if let existing = windowController, let window = existing.window {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        let delegateInstance = BridgeExplorerWindowController()
        delegate = delegateInstance

        // BridgeExplorerView pakt zelf de gedeelde client; er wordt hier bewust
        // geen tweede client aangemaakt — twee engines op één data-dir kan niet.
        let hostingController = NSHostingController(rootView: BridgeExplorerView())

        let window = NSWindow(contentViewController: hostingController)
        window.title = String(localized: "bridge.explorer.window_title", defaultValue: "Bridge")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 1040, height: 680))
        window.minSize = NSSize(width: 820, height: 520)
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("FileFlowerBridgeExplorerWindow")
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
        BridgeExplorerWindowController.windowController = nil
        BridgeExplorerWindowController.delegate = nil
    }
}
#endif
