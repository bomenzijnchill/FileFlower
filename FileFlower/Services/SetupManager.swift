import Foundation
import AppKit

/// Beheert plugin installatie, versie checks en eerste setup
class SetupManager {
    static let shared = SetupManager()
    
    // MARK: - Constants
    
    private let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    private let installedPremierePluginVersionKey = "installedPremierePluginVersion"
    private let installedChromeExtensionVersionKey = "installedChromeExtensionVersion"
    
    // Plugin locaties
    private var premierePluginDestination: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Adobe/CEP/extensions/FileFlowerBridge")
    }
    
    private var bundledPremierePluginURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("PremierePlugin")
    }
    
    private var bundledChromeExtensionURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("ChromeExtension")
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Onboarding Status
    
    /// Check of de onboarding al is voltooid
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedOnboardingKey) }
    }
    
    /// Markeer onboarding als voltooid
    func completeOnboarding() {
        hasCompletedOnboarding = true
        print("SetupManager: Onboarding voltooid")
    }
    
    /// Reset onboarding status (voor testing)
    func resetOnboarding() {
        hasCompletedOnboarding = false
        UserDefaults.standard.removeObject(forKey: installedPremierePluginVersionKey)
        UserDefaults.standard.removeObject(forKey: installedChromeExtensionVersionKey)
        print("SetupManager: Onboarding gereset")
    }
    
    // MARK: - Version Management
    
    /// Geïnstalleerde Premiere plugin versie
    var installedPremierePluginVersion: String? {
        get { UserDefaults.standard.string(forKey: installedPremierePluginVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: installedPremierePluginVersionKey) }
    }
    
    /// Geïnstalleerde Chrome extensie versie (voor tracking/instructies)
    var installedChromeExtensionVersion: String? {
        get { UserDefaults.standard.string(forKey: installedChromeExtensionVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: installedChromeExtensionVersionKey) }
    }
    
    /// Lees de versie uit de gebundelde Premiere plugin manifest
    var bundledPremierePluginVersion: String? {
        guard let pluginURL = bundledPremierePluginURL else { return nil }
        let manifestURL = pluginURL.appendingPathComponent("CSXS/manifest.xml")
        return parseVersionFromManifest(at: manifestURL)
    }
    
    /// Lees de versie uit de gebundelde Chrome extensie manifest
    var bundledChromeExtensionVersion: String? {
        guard let extensionURL = bundledChromeExtensionURL else { return nil }
        let manifestURL = extensionURL.appendingPathComponent("manifest.json")
        return parseVersionFromChromeManifest(at: manifestURL)
    }
    
    /// Lees de versie uit een geïnstalleerde Premiere plugin
    var currentlyInstalledPremierePluginVersion: String? {
        let manifestURL = premierePluginDestination.appendingPathComponent("CSXS/manifest.xml")
        return parseVersionFromManifest(at: manifestURL)
    }
    
    // MARK: - Plugin Installation
    
    /// Check of de Premiere plugin geïnstalleerd is
    var isPremierePluginInstalled: Bool {
        FileManager.default.fileExists(atPath: premierePluginDestination.path)
    }
    
    /// Check of er een plugin update beschikbaar is
    var isPremierePluginUpdateAvailable: Bool {
        guard let bundled = bundledPremierePluginVersion,
              let installed = currentlyInstalledPremierePluginVersion else {
            // Als bundled beschikbaar is maar niet geïnstalleerd, is er een "update" (eerste installatie)
            return bundledPremierePluginVersion != nil && !isPremierePluginInstalled
        }
        return compareVersions(bundled, isNewerThan: installed)
    }
    
    /// Check of er een Chrome extensie update beschikbaar is
    var isChromeExtensionUpdateAvailable: Bool {
        guard let bundled = bundledChromeExtensionVersion,
              let installed = installedChromeExtensionVersion else {
            return bundledChromeExtensionVersion != nil
        }
        return compareVersions(bundled, isNewerThan: installed)
    }
    
    /// Installeer de Premiere plugin
    /// - Returns: Result met succes of foutmelding
    func installPremierePlugin() -> Result<Void, SetupError> {
        guard let sourceURL = bundledPremierePluginURL else {
            return .failure(.pluginNotBundled)
        }

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .failure(.pluginNotBundled)
        }

        let fileManager = FileManager.default
        let extensionsDir = premierePluginDestination.deletingLastPathComponent()

        // Probeer eerst via FileManager (werkt als permissions OK zijn)
        var needsElevatedInstall = false

        // Check of extensions directory schrijfbaar is
        if fileManager.fileExists(atPath: extensionsDir.path) {
            if !fileManager.isWritableFile(atPath: extensionsDir.path) {
                needsElevatedInstall = true
            }
        } else {
            // Directory bestaat niet, probeer aan te maken
            do {
                try fileManager.createDirectory(at: extensionsDir, withIntermediateDirectories: true)
            } catch {
                needsElevatedInstall = true
            }
        }

        if needsElevatedInstall {
            return installPremierePluginElevated(sourceURL: sourceURL)
        }

        // Verwijder bestaande plugin als die bestaat
        if fileManager.fileExists(atPath: premierePluginDestination.path) {
            do {
                try fileManager.removeItem(at: premierePluginDestination)
            } catch {
                // Als verwijderen mislukt, probeer elevated
                return installPremierePluginElevated(sourceURL: sourceURL)
            }
        }

        // Kopieer de nieuwe plugin
        do {
            try fileManager.copyItem(at: sourceURL, to: premierePluginDestination)
        } catch {
            // Als kopiëren mislukt, probeer elevated
            return installPremierePluginElevated(sourceURL: sourceURL)
        }

        // Set juiste permissions
        do {
            try setPermissions(at: premierePluginDestination)
        } catch {
            print("SetupManager: Waarschuwing - kon permissions niet instellen: \(error)")
        }

        // Update de opgeslagen versie
        if let version = bundledPremierePluginVersion {
            installedPremierePluginVersion = version
        }

        print("SetupManager: Premiere plugin succesvol geïnstalleerd naar \(premierePluginDestination.path)")
        return .success(())
    }

    /// Installeer plugin met admin rechten via shell command
    private func installPremierePluginElevated(sourceURL: URL) -> Result<Void, SetupError> {
        let destPath = premierePluginDestination.path
        let extensionsPath = premierePluginDestination.deletingLastPathComponent().path
        let sourcePath = sourceURL.path

        // Bouw shell script dat mkdir, rm en cp doet
        let script = """
        do shell script "mkdir -p '\(extensionsPath)' && rm -rf '\(destPath)' && cp -R '\(sourcePath)' '\(destPath)' && chmod -R 755 '\(destPath)'" with administrator privileges
        """

        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                // Update de opgeslagen versie
                if let version = bundledPremierePluginVersion {
                    installedPremierePluginVersion = version
                }
                print("SetupManager: Premiere plugin geïnstalleerd met admin rechten naar \(destPath)")
                return .success(())
            } else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8) ?? "Onbekende fout"
                print("SetupManager: Elevated install mislukt: \(errorMsg)")
                return .failure(.permissionDenied)
            }
        } catch {
            return .failure(.copyFailed(error))
        }
    }
    
    /// Update de Premiere plugin naar de nieuwste versie
    func updatePremierePluginIfNeeded() -> Result<Bool, SetupError> {
        guard isPremierePluginUpdateAvailable else {
            print("SetupManager: Premiere plugin is up-to-date")
            return .success(false)
        }
        
        let result = installPremierePlugin()
        switch result {
        case .success:
            print("SetupManager: Premiere plugin ge-updatet naar versie \(bundledPremierePluginVersion ?? "onbekend")")
            return .success(true)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Open de Chrome extensie map in Finder
    func openChromeExtensionFolder() {
        guard let extensionURL = bundledChromeExtensionURL,
              FileManager.default.fileExists(atPath: extensionURL.path) else {
            print("SetupManager: Chrome extensie niet gevonden in bundle")
            return
        }
        
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: extensionURL.path)
    }
    
    /// Markeer de Chrome extensie als geïnstalleerd met huidige versie
    func markChromeExtensionInstalled() {
        if let version = bundledChromeExtensionVersion {
            installedChromeExtensionVersion = version
            print("SetupManager: Chrome extensie gemarkeerd als geïnstalleerd (versie \(version))")
        }
    }
    
    // MARK: - Startup Checks
    
    /// Voer alle benodigde startup checks uit
    func performStartupChecks() {
        // Check en update Premiere plugin indien nodig
        if isPremierePluginInstalled {
            let result = updatePremierePluginIfNeeded()
            switch result {
            case .success(let updated):
                if updated {
                    print("SetupManager: Premiere plugin automatisch ge-updatet bij opstarten")
                }
            case .failure(let error):
                print("SetupManager: Fout bij updaten Premiere plugin: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Parse versie uit CEP manifest.xml
    private func parseVersionFromManifest(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        // Zoek naar ExtensionBundleVersion="X.X.X"
        let pattern = #"ExtensionBundleVersion="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let versionRange = Range(match.range(at: 1), in: content) else {
            return nil
        }
        
        return String(content[versionRange])
    }
    
    /// Parse versie uit Chrome manifest.json
    private func parseVersionFromChromeManifest(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let version = json["version"] as? String {
                return version
            }
        } catch {
            print("SetupManager: Fout bij parsen Chrome manifest: \(error)")
        }
        
        return nil
    }
    
    /// Vergelijk twee versie strings (semver-style)
    private func compareVersions(_ version1: String, isNewerThan version2: String) -> Bool {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }
        
        let maxLength = max(v1Components.count, v2Components.count)
        
        for i in 0..<maxLength {
            let v1Part = i < v1Components.count ? v1Components[i] : 0
            let v2Part = i < v2Components.count ? v2Components[i] : 0
            
            if v1Part > v2Part { return true }
            if v1Part < v2Part { return false }
        }
        
        return false
    }
    
    /// Set uitvoerbare permissions op een directory
    private func setPermissions(at url: URL) throws {
        let fileManager = FileManager.default
        
        // Set 755 permissions op de directory en subdirectories
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fileURL.path)
        }
        
        // Set permissions op de root directory
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

// MARK: - Errors

enum SetupError: LocalizedError {
    case pluginNotBundled
    case cannotCreateDirectory(Error)
    case cannotRemoveExisting(Error)
    case copyFailed(Error)
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .pluginNotBundled:
            return "De plugin is niet gevonden in de app bundle"
        case .cannotCreateDirectory(let error):
            return "Kan de doelmap niet aanmaken: \(error.localizedDescription)"
        case .cannotRemoveExisting(let error):
            return "Kan bestaande plugin niet verwijderen: \(error.localizedDescription)"
        case .copyFailed(let error):
            return "Kan plugin niet kopiëren: \(error.localizedDescription)"
        case .permissionDenied:
            return "Geen toegang tot de doellocatie"
        }
    }
}


