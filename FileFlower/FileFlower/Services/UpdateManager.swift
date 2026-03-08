import Foundation
import AppKit
import Combine
import Sparkle

/// Beheert app updates via Sparkle framework
class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    // MARK: - Sparkle

    let updaterController: SPUStandardUpdaterController

    // MARK: - Published Properties

    @Published var currentVersion: String
    @Published var buildNumber: String

    // MARK: - Initialization

    private init() {
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"

        // Sparkle updater initialiseren
        // startingUpdater: true = automatisch checken op basis van gebruikersinstellingen
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    // MARK: - Public Methods

    /// Check handmatig voor updates (opent Sparkle's native update dialoog)
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Of Sparkle automatisch voor updates checkt
    var automaticUpdatesEnabled: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Of de "Check for Updates" knop ingeschakeld moet zijn
    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
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
