import Foundation

class Quarantine {
    static func removeQuarantineAttribute(from url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-d", "com.apple.quarantine", url.path]
        
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        // Non-zero exit is OK if attribute doesn't exist or permission denied
        // (App Sandbox can block this, but that's OK - file will still work)
        if process.terminationStatus != 0 {
            // Silently ignore - file can still be used without removing quarantine
            print("Note: Could not remove quarantine attribute (may need App Sandbox disabled)")
        }
    }
}

