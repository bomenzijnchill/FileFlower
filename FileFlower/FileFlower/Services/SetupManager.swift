import Foundation
import AppKit

/// Beheert plugin installatie, versie checks en eerste setup
class SetupManager {
    static let shared = SetupManager()
    
    // MARK: - Constants
    
    private let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    private let lastOnboardingVersionKey = "lastOnboardingVersion"
    private let installedPremierePluginVersionKey = "installedPremierePluginVersion"
    private let installedChromeExtensionVersionKey = "installedChromeExtensionVersion"
    private let selectedBrowserKey = "selectedBrowser"
    
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
    
    /// Markeer onboarding als voltooid en sla de huidige versie op
    func completeOnboarding() {
        hasCompletedOnboarding = true
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        UserDefaults.standard.set(currentVersion, forKey: lastOnboardingVersionKey)
        #if DEBUG
        print("SetupManager: Onboarding voltooid voor versie \(currentVersion)")
        #endif
    }

    /// Check of de onboarding opnieuw getoond moet worden na een app update
    var shouldShowOnboardingForUpdate: Bool {
        guard hasCompletedOnboarding else { return false }
        let lastVersion = UserDefaults.standard.string(forKey: lastOnboardingVersionKey) ?? "0"
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return lastVersion != currentVersion
    }
    
    /// Reset onboarding status (voor testing)
    func resetOnboarding() {
        hasCompletedOnboarding = false
        UserDefaults.standard.removeObject(forKey: installedPremierePluginVersionKey)
        UserDefaults.standard.removeObject(forKey: installedChromeExtensionVersionKey)
        #if DEBUG
        print("SetupManager: Onboarding gereset")
        #endif
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
            #if DEBUG
            print("SetupManager: Waarschuwing - kon permissions niet instellen: \(error)")
            #endif
        }

        // Update de opgeslagen versie
        if let version = bundledPremierePluginVersion {
            installedPremierePluginVersion = version
        }

        // Zet CEP debug mode aan zodat Premiere de unsigned extensie laadt
        enableCEPDebugMode()

        #if DEBUG
        print("SetupManager: Premiere plugin succesvol geïnstalleerd naar \(premierePluginDestination.path)")
        #endif
        return .success(())
    }

    /// Escape een pad voor gebruik in single-quoted shell strings
    private func shellEscape(_ path: String) -> String {
        return path.replacingOccurrences(of: "'", with: "'\\''")
    }

    /// Installeer plugin met admin rechten via shell command
    private func installPremierePluginElevated(sourceURL: URL) -> Result<Void, SetupError> {
        let destPath = shellEscape(premierePluginDestination.path)
        let extensionsPath = shellEscape(premierePluginDestination.deletingLastPathComponent().path)
        let sourcePath = shellEscape(sourceURL.path)

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
                // Zet CEP debug mode aan zodat Premiere de unsigned extensie laadt
                enableCEPDebugMode()
                #if DEBUG
                print("SetupManager: Premiere plugin geïnstalleerd met admin rechten naar \(destPath)")
                #endif
                return .success(())
            } else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8) ?? "Onbekende fout"
                #if DEBUG
                print("SetupManager: Elevated install mislukt: \(errorMsg)")
                #endif
                return .failure(.permissionDenied)
            }
        } catch {
            return .failure(.copyFailed(error))
        }
    }
    
    /// Update de Premiere plugin naar de nieuwste versie
    func updatePremierePluginIfNeeded() -> Result<Bool, SetupError> {
        guard isPremierePluginUpdateAvailable else {
            #if DEBUG
            print("SetupManager: Premiere plugin is up-to-date")
            #endif
            return .success(false)
        }
        
        let result = installPremierePlugin()
        switch result {
        case .success:
            #if DEBUG
            print("SetupManager: Premiere plugin ge-updatet naar versie \(bundledPremierePluginVersion ?? "onbekend")")
            #endif
            return .success(true)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Open de Chrome extensie map in Finder — kopieer naar toegankelijke locatie
    func openChromeExtensionFolder() {
        guard let extensionURL = bundledChromeExtensionURL,
              FileManager.default.fileExists(atPath: extensionURL.path) else {
            #if DEBUG
            print("SetupManager: Chrome extensie niet gevonden in bundle")
            #endif
            return
        }

        // Kopieer extensie naar ~/Documents/FileFlower Chrome Extension/
        // zodat Chrome's file picker er bij kan
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let targetURL = documentsURL.appendingPathComponent("FileFlower Chrome Extension")

        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: extensionURL, to: targetURL)
            // Open enclosing folder en selecteer de extensie map
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            #if DEBUG
            print("SetupManager: Chrome extensie gekopieerd naar \(targetURL.path)")
            #endif
        } catch {
            #if DEBUG
            print("SetupManager: Kon Chrome extensie niet kopiëren: \(error)")
            #endif
            // Fallback: open originele locatie
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: extensionURL.path)
        }
    }
    
    /// Markeer de Chrome extensie als geïnstalleerd met huidige versie
    func markChromeExtensionInstalled() {
        if let version = bundledChromeExtensionVersion {
            installedChromeExtensionVersion = version
            #if DEBUG
            print("SetupManager: Chrome extensie gemarkeerd als geïnstalleerd (versie \(version))")
            #endif
        }
    }
    
    // MARK: - Browser Selection

    var selectedBrowser: String {
        get { UserDefaults.standard.string(forKey: selectedBrowserKey) ?? "chrome" }
        set { UserDefaults.standard.set(newValue, forKey: selectedBrowserKey) }
    }

    // MARK: - Safari Extension

    private var safariExtensionAppURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("FileFlower Safari.app")
    }

    /// Verwijder quarantine extended attributes zodat App Translocation niet getriggerd wordt.
    /// Zonder dit kan Safari de extensie niet vinden in een getransloceerde app.
    private func removeQuarantine(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-cr", url.path]
        do {
            try process.run()
            process.waitUntilExit()
            #if DEBUG
            print("SetupManager: Quarantine attributen verwijderd van \(url.path) (status \(process.terminationStatus))")
            #endif
        } catch {
            #if DEBUG
            print("SetupManager: Kon quarantine attributen niet verwijderen: \(error)")
            #endif
        }
    }

    /// Forceer Launch Services om de app te indexeren, zodat Safari de extensie kan ontdekken.
    private func registerWithLaunchServices(at url: URL) {
        let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
        guard FileManager.default.fileExists(atPath: lsregisterPath) else {
            #if DEBUG
            print("SetupManager: lsregister niet gevonden op \(lsregisterPath)")
            #endif
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsregisterPath)
        process.arguments = ["-f", url.path]
        do {
            try process.run()
            process.waitUntilExit()
            #if DEBUG
            print("SetupManager: Launch Services registratie uitgevoerd voor \(url.path) (status \(process.terminationStatus))")
            #endif
        } catch {
            #if DEBUG
            print("SetupManager: Launch Services registratie mislukt: \(error)")
            #endif
        }
    }

    /// Open de Safari extensie container app, die de extensie registreert en Safari preferences opent.
    /// Kopieert de app naar /Applications/ zodat Safari de extensie correct kan vinden en indexeren.
    func openSafariExtensionApp(completion: @escaping (Result<Void, SetupError>) -> Void) {
        guard let bundledAppURL = safariExtensionAppURL,
              FileManager.default.fileExists(atPath: bundledAppURL.path) else {
            #if DEBUG
            print("SetupManager: Safari extensie app niet gevonden in bundle")
            #endif
            completion(.failure(.safariExtensionNotFound))
            return
        }

        // Safari vereist dat de container app in /Applications/ staat om de extensie te kunnen vinden
        let installedAppURL = URL(fileURLWithPath: "/Applications/FileFlower Safari.app")

        // Probeer direct te kopiëren (werkt als gebruiker schrijfrechten heeft op /Applications/)
        do {
            if FileManager.default.fileExists(atPath: installedAppURL.path) {
                try FileManager.default.removeItem(at: installedAppURL)
            }
            try FileManager.default.copyItem(at: bundledAppURL, to: installedAppURL)
            #if DEBUG
            print("SetupManager: Safari app gekopieerd naar /Applications/")
            #endif
            // Strip quarantine attributen na directe kopie
            removeQuarantine(at: installedAppURL)
        } catch {
            #if DEBUG
            print("SetupManager: Directe kopie gefaald, probeer met admin rechten: \(error)")
            #endif
            // Fallback: gebruik AppleScript om met admin rechten te kopiëren (inclusief quarantine removal)
            let escapedSource = bundledAppURL.path.replacingOccurrences(of: "'", with: "'\\''")
            let script = """
            do shell script "rm -rf '/Applications/FileFlower Safari.app' && cp -R '\(escapedSource)' '/Applications/FileFlower Safari.app' && xattr -cr '/Applications/FileFlower Safari.app'" with administrator privileges
            """
            var appleError: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&appleError)
            }
            if let appleError = appleError {
                #if DEBUG
                print("SetupManager: AppleScript kopie ook gefaald: \(appleError)")
                #endif
                completion(.failure(.safariExtensionOpenFailed(
                    NSError(domain: "SetupManager", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Kan Safari extensie niet installeren in /Applications/"])
                )))
                return
            }
        }

        // Registreer bij Launch Services zodat Safari de extensie kan ontdekken
        registerWithLaunchServices(at: installedAppURL)

        // Verifieer dat de .appex daadwerkelijk aanwezig is in de gekopieerde app
        let appexURL = installedAppURL.appendingPathComponent("Contents/PlugIns/FileFlower Safari Extension.appex")
        guard FileManager.default.fileExists(atPath: appexURL.path) else {
            #if DEBUG
            print("SetupManager: Safari extensie appex niet gevonden in gekopieerde app: \(appexURL.path)")
            #endif
            completion(.failure(.safariExtensionOpenFailed(
                NSError(domain: "SetupManager", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Safari extensie is incompleet gekopieerd. Probeer het opnieuw."])
            )))
            return
        }

        // Wacht even zodat Launch Services de app kan indexeren vóór we hem openen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: installedAppURL, configuration: config) { _, error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(.failure(.safariExtensionOpenFailed(error)))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    // MARK: - Finder Extension

    private let finderExtensionBundleID = "com.fileflower.app.FileFlowerFinderSync"

    /// Registreer de FinderSync extensie bij macOS via pluginkit
    /// Stap 1: Voeg de appex expliciet toe aan de pluginkit database
    /// Stap 2: Activeer de extensie
    func registerFinderExtension() {
        // Stap 1: Registreer de appex expliciet bij pluginkit
        if let appexPath = Bundle.main.builtInPlugInsURL?
            .appendingPathComponent("FileFlowerFinderSync.appex").path {
            let addProcess = Process()
            addProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            addProcess.arguments = ["-a", appexPath]
            do {
                try addProcess.run()
                addProcess.waitUntilExit()
                #if DEBUG
                print("SetupManager: FinderSync appex geregistreerd via pluginkit -a (status \(addProcess.terminationStatus))")
                #endif
            } catch {
                #if DEBUG
                print("SetupManager: Fout bij pluginkit -a: \(error)")
                #endif
            }
        }

        // Stap 2: Activeer de extensie
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-e", "use", "-i", finderExtensionBundleID]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                #if DEBUG
                print("SetupManager: FinderSync extensie geactiveerd via pluginkit -e use")
                #endif
            } else {
                #if DEBUG
                print("SetupManager: pluginkit -e use mislukt (status \(process.terminationStatus))")
                #endif
            }
        } catch {
            #if DEBUG
            print("SetupManager: Fout bij activeren FinderSync extensie: \(error)")
            #endif
        }
    }

    /// Check of de FinderSync extensie actief is via pluginkit
    func isFinderExtensionEnabled() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-m", "-p", "com.apple.FinderSync"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            // Zoek naar onze bundle ID met een "+" (enabled) status
            let lines = output.components(separatedBy: "\n")
            let enabled = lines.contains { line in
                line.contains(finderExtensionBundleID) && line.contains("+")
            }
            #if DEBUG
            print("SetupManager: FinderSync extensie enabled: \(enabled)")
            #endif
            return enabled
        } catch {
            #if DEBUG
            print("SetupManager: Fout bij checken FinderSync extensie status: \(error)")
            #endif
            return false
        }
    }

    /// Open Systeeminstellingen op de Login Items & Extensions pagina
    /// Op macOS 13+ verschijnen FinderSync extensies onder General > Login Items & Extensions
    func openFinderExtensionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - DaVinci Resolve Checks

    /// Check of Python 3 beschikbaar is op het systeem
    var isPython3Available: Bool {
        let candidates = [
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3"
        ]
        return candidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Check of de DaVinci Resolve scripting modules beschikbaar zijn
    var isResolveScriptingAvailable: Bool {
        let modulesPath = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"
        return FileManager.default.fileExists(atPath: modulesPath)
    }

    // MARK: - CEP Debug Mode

    /// Zet CEP PlayerDebugMode aan zodat Premiere Pro unsigned extensies laadt.
    /// Zonder deze flag weigert Premiere de FileFlower CEP plugin volledig.
    func enableCEPDebugMode() {
        for version in 10...12 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = ["write", "com.adobe.CSXS.\(version)", "PlayerDebugMode", "1"]
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                #if DEBUG
                print("SetupManager: Kon PlayerDebugMode niet instellen voor CSXS.\(version): \(error)")
                #endif
            }
        }
        #if DEBUG
        print("SetupManager: CEP PlayerDebugMode ingesteld voor CSXS 10-12")
        #endif
    }

    // MARK: - Startup Checks

    /// Voer alle benodigde startup checks uit
    func performStartupChecks() {
        // FinderSync extensie wordt al geregistreerd in applicationDidFinishLaunching

        // Check en update Premiere plugin indien nodig
        if isPremierePluginInstalled {
            // Zorg dat CEP debug mode aan staat (vereist voor unsigned extensies)
            enableCEPDebugMode()

            let result = updatePremierePluginIfNeeded()
            switch result {
            case .success(let updated):
                if updated {
                    #if DEBUG
                    print("SetupManager: Premiere plugin automatisch ge-updatet bij opstarten")
                    #endif
                }
            case .failure(let error):
                #if DEBUG
                print("SetupManager: Fout bij updaten Premiere plugin: \(error.localizedDescription)")
                #endif
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
            #if DEBUG
            print("SetupManager: Fout bij parsen Chrome manifest: \(error)")
            #endif
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
    case safariExtensionNotFound
    case safariExtensionOpenFailed(Error)

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
        case .safariExtensionNotFound:
            return String(localized: "setup.error.safari_not_found")
        case .safariExtensionOpenFailed(let error):
            return String(localized: "setup.error.safari_open_failed \(error.localizedDescription)")
        }
    }
}


