import Foundation
import ServiceManagement
import AppKit

class LaunchAgentManager {
    static let shared = LaunchAgentManager()

    private init() {
        cleanupOldLaunchAgents()
    }

    /// Verwijder oude handmatige launch agents (DLtoPremiere en FileFlower plist-gebaseerd)
    private func cleanupOldLaunchAgents() {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")

        let oldPlists = ["com.dltopremiere.plist", "com.fileflower.plist"]
        for plistName in oldPlists {
            let plistURL = launchAgentsDir.appendingPathComponent(plistName)
            guard FileManager.default.fileExists(atPath: plistURL.path) else { continue }

            // Unload eerst
            let process = Process()
            process.launchPath = "/bin/launchctl"
            process.arguments = ["unload", plistURL.path]
            try? process.run()
            process.waitUntilExit()

            // Verwijder het plist bestand
            try? FileManager.default.removeItem(at: plistURL)
            print("LaunchAgentManager: Oude launch agent opgeruimd: \(plistName)")
        }
    }

    /// Check of de app geregistreerd is als login item via SMAppService
    func isStartAtLoginEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }

    /// Registreer de app als login item via SMAppService
    /// De app verschijnt automatisch in Systeeminstellingen > Algemeen > Inlogonderdelen
    func enableStartAtLogin() throws {
        // Unregister eerst als al enabled (voorkomt stale state)
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        }
        try SMAppService.mainApp.register()
        print("LaunchAgentManager: Start bij login ingeschakeld via SMAppService")
    }

    /// Verwijder de app als login item
    func disableStartAtLogin() throws {
        try SMAppService.mainApp.unregister()
        print("LaunchAgentManager: Start bij login uitgeschakeld via SMAppService")
    }
}
