import Foundation
import AppKit

class PremiereChecker {
    static let shared = PremiereChecker()
    
    private init() {}
    
    func isPremiereProRunning() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { app in
            app.bundleIdentifier == "com.adobe.PremierePro" || 
            app.localizedName?.contains("Premiere Pro") == true
        }
    }
    
    func bringPremiereToFront() {
        let runningApps = NSWorkspace.shared.runningApplications
        if let premiereApp = runningApps.first(where: { app in
            app.bundleIdentifier == "com.adobe.PremierePro" || 
            app.localizedName?.contains("Premiere Pro") == true
        }) {
            if #available(macOS 14.0, *) {
                premiereApp.activate()
            } else {
                premiereApp.activate(options: .activateIgnoringOtherApps)
            }
        }
    }
}

