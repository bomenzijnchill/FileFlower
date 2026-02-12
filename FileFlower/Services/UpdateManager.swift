import Foundation
import AppKit
import Combine
import UserNotifications

/// Beheert app updates via Sparkle framework
/// Note: Sparkle moet worden toegevoegd als Swift Package in Xcode:
/// https://github.com/sparkle-project/Sparkle (versie 2.x)
class UpdateManager: ObservableObject {
    static let shared = UpdateManager()
    
    // MARK: - Published Properties
    
    @Published var isCheckingForUpdates = false
    @Published var lastUpdateCheck: Date?
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var currentVersion: String
    @Published var updateError: String?
    
    // MARK: - Constants
    
    /// URL naar de appcast.xml voor updates
    /// Pas dit aan naar je GitHub repository
    /// Formaat: https://raw.githubusercontent.com/USERNAME/REPO/main/appcast.xml
    static let appcastURL = "https://raw.githubusercontent.com/bomenzijnchill/FileFlower/main/appcast.xml"
    
    /// Interval voor automatische update checks (in seconden)
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60 // 24 uur
    
    // MARK: - Initialization
    
    private init() {
        // Haal huidige versie op uit bundle
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        
        // Laad laatste check datum
        if let lastCheck = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date {
            lastUpdateCheck = lastCheck
        }
        
        // Check automatisch voor updates bij opstarten (na korte delay)
        if automaticUpdatesEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.checkForUpdatesIfNeeded()
            }
        }
    }
    
    /// Check voor updates als het tijd is (laatste check > 24 uur geleden)
    private func checkForUpdatesIfNeeded() {
        guard automaticUpdatesEnabled else { return }
        
        // Check alleen als laatste check meer dan 24 uur geleden was
        if let lastCheck = lastUpdateCheck {
            let timeSinceLastCheck = Date().timeIntervalSince(lastCheck)
            if timeSinceLastCheck < UpdateManager.automaticCheckInterval {
                print("UpdateManager: Laatste check was \(Int(timeSinceLastCheck / 3600)) uur geleden, skip automatische check")
                return
            }
        }
        
        print("UpdateManager: Automatische update check gestart")
        checkForUpdates()
    }
    
    // MARK: - Public Methods
    
    /// Check handmatig voor updates
    func checkForUpdates() {
        isCheckingForUpdates = true
        updateError = nil
        
        checkForUpdatesManually()
    }
    
    /// Check of automatische updates zijn ingeschakeld (standaard AAN)
    var automaticUpdatesEnabled: Bool {
        get {
            // Default is true - als key niet bestaat, return true
            if UserDefaults.standard.object(forKey: "automaticUpdatesEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "automaticUpdatesEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "automaticUpdatesEnabled")
        }
    }
    
    // MARK: - Manual Update Check (zonder Sparkle)
    
    /// Handmatige update check via appcast.xml
    /// Dit wordt vervangen door Sparkle wanneer dat is geïntegreerd
    private func checkForUpdatesManually() {
        guard let url = URL(string: UpdateManager.appcastURL) else {
            updateError = "Ongeldige update URL"
            isCheckingForUpdates = false
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isCheckingForUpdates = false
                self?.lastUpdateCheck = Date()
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")

                if let error = error {
                    self?.updateError = "Kan niet verbinden: \(error.localizedDescription)"
                    return
                }

                // Check HTTP status code
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    self?.updateError = "Update server niet bereikbaar (HTTP \(httpResponse.statusCode))"
                    return
                }

                guard let data = data else {
                    self?.updateError = "Geen data ontvangen"
                    return
                }

                // Parse de appcast XML
                self?.parseAppcast(data: data)
            }
        }
        task.resume()
    }
    
    /// Parse de appcast.xml om de nieuwste versie te vinden
    private func parseAppcast(data: Data) {
        // Simpele XML parsing voor versie
        guard let xmlString = String(data: data, encoding: .utf8) else {
            updateError = "Kan appcast niet lezen"
            return
        }

        // Check of response XML is (niet HTML of andere content)
        let trimmed = xmlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.hasPrefix("<?xml") && !trimmed.hasPrefix("<rss") {
            updateError = "Appcast URL geeft geen geldige XML terug"
            return
        }

        // Zoek naar sparkle:version in de XML
        // Ondersteunt zowel element syntax (<sparkle:version>1.1</sparkle:version>)
        // als attribute syntax (sparkle:version="1.1")
        let elementPattern = #"<sparkle:version>([^<]+)</sparkle:version>"#
        let attributePattern = #"sparkle:version="([^"]+)""#

        var versionString: String?

        if let regex = try? NSRegularExpression(pattern: elementPattern),
           let match = regex.firstMatch(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString)),
           let range = Range(match.range(at: 1), in: xmlString) {
            versionString = String(xmlString[range])
        } else if let regex = try? NSRegularExpression(pattern: attributePattern),
                  let match = regex.firstMatch(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString)),
                  let range = Range(match.range(at: 1), in: xmlString) {
            versionString = String(xmlString[range])
        }

        guard let foundVersion = versionString else {
            updateError = "Kan versie niet vinden in appcast"
            return
        }
        
        let latestVersionString = foundVersion
        latestVersion = latestVersionString
        
        // Vergelijk versies
        updateAvailable = isVersion(latestVersionString, newerThan: currentVersion)
        
        if updateAvailable {
            print("UpdateManager: Nieuwe versie beschikbaar: \(latestVersionString)")
            
            // Toon notificatie als automatische updates aan staan
            if automaticUpdatesEnabled {
                showUpdateNotification(newVersion: latestVersionString)
            }
        } else {
            print("UpdateManager: App is up-to-date (versie \(currentVersion))")
        }
    }
    
    /// Toon een macOS notificatie dat er een update beschikbaar is
    private func showUpdateNotification(newVersion: String) {
        let center = UNUserNotificationCenter.current()
        
        // Vraag eerst toestemming
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted else {
                print("UpdateManager: Notificatie toestemming geweigerd")
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = "FileFlower Update Beschikbaar"
            content.body = "Versie \(newVersion) is nu beschikbaar. Open de app om te updaten."
            content.sound = .default
            
            // Maak een trigger (direct tonen)
            let request = UNNotificationRequest(
                identifier: "updateAvailable",
                content: content,
                trigger: nil
            )
            
            center.add(request) { error in
                if let error = error {
                    print("UpdateManager: Fout bij tonen notificatie: \(error)")
                } else {
                    print("UpdateManager: Update notificatie getoond voor versie \(newVersion)")
                }
            }
        }
    }
    
    /// Vergelijk twee versie strings
    private func isVersion(_ version1: String, newerThan version2: String) -> Bool {
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
    
    // MARK: - Plugin Update Info
    
    /// Geeft informatie over beschikbare plugin updates
    var pluginUpdateInfo: PluginUpdateInfo {
        let setupManager = SetupManager.shared
        
        return PluginUpdateInfo(
            premierePluginUpdateAvailable: setupManager.isPremierePluginUpdateAvailable,
            chromeExtensionUpdateAvailable: setupManager.isChromeExtensionUpdateAvailable,
            bundledPremiereVersion: setupManager.bundledPremierePluginVersion,
            installedPremiereVersion: setupManager.currentlyInstalledPremierePluginVersion,
            bundledChromeVersion: setupManager.bundledChromeExtensionVersion,
            installedChromeVersion: setupManager.installedChromeExtensionVersion
        )
    }
    
    /// Update de Premiere plugin naar de gebundelde versie
    func updatePremierePlugin() -> Result<Void, SetupError> {
        return SetupManager.shared.installPremierePlugin()
    }
}

// MARK: - Supporting Types

struct PluginUpdateInfo {
    let premierePluginUpdateAvailable: Bool
    let chromeExtensionUpdateAvailable: Bool
    let bundledPremiereVersion: String?
    let installedPremiereVersion: String?
    let bundledChromeVersion: String?
    let installedChromeVersion: String?
}

// MARK: - Appcast Generator

/// Helper om een appcast.xml te genereren voor Sparkle updates
struct AppcastGenerator {
    
    /// Genereer een appcast entry voor een nieuwe versie
    static func generateEntry(
        version: String,
        buildNumber: String,
        downloadURL: String,
        releaseNotes: String,
        minimumSystemVersion: String = "13.0",
        edSignature: String,
        length: Int
    ) -> String {
        return """
        <item>
            <title>Versie \(version)</title>
            <sparkle:version>\(buildNumber)</sparkle:version>
            <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>\(minimumSystemVersion)</sparkle:minimumSystemVersion>
            <description><![CDATA[
                \(releaseNotes)
            ]]></description>
            <pubDate>\(ISO8601DateFormatter().string(from: Date()))</pubDate>
            <enclosure
                url="\(downloadURL)"
                sparkle:edSignature="\(edSignature)"
                length="\(length)"
                type="application/octet-stream"
            />
        </item>
        """
    }
    
    /// Genereer een complete appcast.xml
    static func generateAppcast(entries: [String]) -> String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
            <channel>
                <title>FileFlower Updates</title>
                <link>https://yourdomain.com/appcast.xml</link>
                <description>Updates voor FileFlower</description>
                <language>nl</language>
                \(entries.joined(separator: "\n        "))
            </channel>
        </rss>
        """
    }
}

