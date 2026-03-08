import SwiftUI
import AppKit

class ConflictDialogWindowController: NSWindowController {
    static var shared: ConflictDialogWindowController?
    
    let item: DownloadItem
    var onResolve: ((ConflictDialog.ConflictResolution) -> Void)?
    
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
        
        let contentView = ConflictDialog(item: item) { resolution in
            onResolve(resolution)
            ConflictDialogWindowController.shared?.close()
        }
        .frame(width: 500, height: 400)
        
        window.contentView = NSHostingView(rootView: contentView)
        
        super.init(window: window)
        
        ConflictDialogWindowController.shared = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Window level is al floating ingesteld in init
    }
    
    override func close() {
        window?.close()
        ConflictDialogWindowController.shared = nil
    }
}

