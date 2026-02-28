import AppKit

/// Beheert de activation policy van de app (dock icon / Force Quit zichtbaarheid).
/// Schakelt naar .regular wanneer een window zichtbaar is, terug naar .accessory wanneer alle windows gesloten zijn.
@MainActor
class ActivationPolicyManager {
    static let shared = ActivationPolicyManager()

    private var trackedWindows: Set<ObjectIdentifier> = []

    private init() {}

    /// Registreer window observers om automatisch de activation policy te beheren
    func setupWindowTracking() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow,
                  window.styleMask.contains(.titled) else { return }
            MainActor.assumeIsolated {
                self?.windowDidShow(window)
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                self?.windowDidClose(window)
            }
        }
    }

    private func windowDidShow(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        let wasEmpty = trackedWindows.isEmpty
        trackedWindows.insert(id)

        if wasEmpty {
            NSApplication.shared.setActivationPolicy(.regular)
        }
    }

    private func windowDidClose(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        trackedWindows.remove(id)

        if trackedWindows.isEmpty {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}
