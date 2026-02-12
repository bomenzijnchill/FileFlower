import SwiftUI
import AppKit

class ProjectPickerWindowController: NSWindowController {
    static var shared: ProjectPickerWindowController?
    
    init(item: DownloadItem?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Kies project en type"
        window.center()
        window.isReleasedWhenClosed = false
        window.restorationClass = nil // Disable window restoration to prevent warnings
        window.level = .floating // Make window appear above other apps
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        
        let contentView = ProjectPickerView(item: item)
            .frame(width: 480, height: 500)
        
        window.contentView = NSHostingView(rootView: contentView)
        
        super.init(window: window)
        
        ProjectPickerWindowController.shared = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.level = .floating // Ensure it stays on top
    }
    
    override func close() {
        window?.close()
        ProjectPickerWindowController.shared = nil
    }
}

