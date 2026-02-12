import Foundation
import AppKit

class LaunchAgentManager {
    static let shared = LaunchAgentManager()
    
    private let plistFileName = "com.fileflower.plist"
    private var launchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
    }

    private var plistURL: URL {
        launchAgentsDirectory.appendingPathComponent(plistFileName)
    }

    private init() {
        cleanupOldLaunchAgent()
    }

    /// Verwijder oude DLtoPremiere launch agent als die bestaat
    private func cleanupOldLaunchAgent() {
        let oldPlistURL = launchAgentsDirectory.appendingPathComponent("com.dltopremiere.plist")
        guard FileManager.default.fileExists(atPath: oldPlistURL.path) else { return }

        let process = Process()
        process.launchPath = "/bin/launchctl"
        process.arguments = ["unload", oldPlistURL.path]
        try? process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(at: oldPlistURL)
        print("LaunchAgentManager: Oude DLtoPremiere launch agent opgeruimd")
    }
    
    func isStartAtLoginEnabled() -> Bool {
        return FileManager.default.fileExists(atPath: plistURL.path)
    }
    
    func enableStartAtLogin() throws {
        // Zorg dat LaunchAgents directory bestaat
        if !FileManager.default.fileExists(atPath: launchAgentsDirectory.path) {
            try FileManager.default.createDirectory(
                at: launchAgentsDirectory,
                withIntermediateDirectories: true
            )
        }
        
        // Haal app bundle path op
        guard let appBundlePath = Bundle.main.bundlePath as String? else {
            throw LaunchAgentError.cannotGetBundlePath
        }
        
        // Maak plist dictionary
        let plistDict: [String: Any] = [
            "Label": "com.fileflower",
            "ProgramArguments": [appBundlePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        
        // Schrijf plist naar disk
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plistDict,
            format: .xml,
            options: 0
        )
        
        try plistData.write(to: plistURL)
        
        // Laad de LaunchAgent
        let process = Process()
        process.launchPath = "/bin/launchctl"
        process.arguments = ["load", plistURL.path]
        try process.run()
        process.waitUntilExit()
    }
    
    func disableStartAtLogin() throws {
        // Unload de LaunchAgent als deze bestaat
        if FileManager.default.fileExists(atPath: plistURL.path) {
            let process = Process()
            process.launchPath = "/bin/launchctl"
            process.arguments = ["unload", plistURL.path]
            try process.run()
            process.waitUntilExit()
        }
        
        // Verwijder plist bestand
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }
}

enum LaunchAgentError: Error {
    case cannotGetBundlePath
    case cannotCreateDirectory
    case cannotWritePlist
}

