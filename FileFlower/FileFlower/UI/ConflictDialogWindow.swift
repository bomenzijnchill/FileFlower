import SwiftUI
import AppKit

class ConflictDialogWindowController: NSWindowController, NSWindowDelegate {
    /// Sterke referenties naar open dialogen. Voorheen hield één statische `shared`
    /// alleen het LAATSTE venster bij: bij een batch met meerdere conflicten sloot de
    /// resolutie van venster 1 het venster van item 5, dat daardoor onbeantwoord bleef
    /// (item bleef stil in de wachtrij hangen).
    private static var openControllers: [ConflictDialogWindowController] = []

    let item: DownloadItem
    var onResolve: ((ConflictDialog.ConflictResolution) -> Void)?
    /// Voorkomt dat zowel de knop als het sluiten van het venster resolve aanroept
    private var didResolve = false

    init(item: DownloadItem, onResolve: @escaping (ConflictDialog.ConflictResolution) -> Void) {
        self.item = item
        self.onResolve = onResolve

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bestandsconflict"
        window.center()
        window.isReleasedWhenClosed = false
        window.restorationClass = nil

        // Conflict dialogs zijn altijd floating voor zichtbaarheid
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        super.init(window: window)

        // Sluit ALTIJD het eigen venster (niet een statische 'laatste')
        let contentView = ConflictDialog(item: item) { [weak self] resolution in
            self?.finish(with: resolution)
        }
        .frame(width: 500, height: 400)

        window.contentView = NSHostingView(rootView: contentView)
        window.delegate = self

        Self.openControllers.append(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Window level is al floating ingesteld in init
    }

    private func finish(with resolution: ConflictDialog.ConflictResolution) {
        guard !didResolve else { return }
        didResolve = true
        onResolve?(resolution)
        close()
    }

    /// Venster wegklikken telt als "overslaan": het item blijft anders zonder
    /// resolutie in de wachtrij staan.
    func windowWillClose(_ notification: Notification) {
        if !didResolve {
            didResolve = true
            onResolve?(.skip)
        }
        Self.openControllers.removeAll { $0 === self }
    }

    override func close() {
        window?.close()
        Self.openControllers.removeAll { $0 === self }
    }
}
