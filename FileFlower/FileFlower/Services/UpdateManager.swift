import Foundation
import AppKit
import Combine
import Sparkle
import UserNotifications

/// Beheert app updates via Sparkle framework
class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    // MARK: - Sparkle

    let updaterController: SPUStandardUpdaterController
    private let sparkleDelegate = SparkleUpdateDelegate()

    // MARK: - Published Properties

    @Published var currentVersion: String
    @Published var buildNumber: String

    // MARK: - Initialization

    private init() {
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"

        // Sparkle updater initialiseren met delegate voor update-notificaties
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: sparkleDelegate,
            userDriverDelegate: nil
        )

        // Notification permissie aanvragen
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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

// MARK: - Sparkle Update Delegate

/// Stuurt een push-notificatie wanneer Sparkle een nieuwe update vindt
private class SparkleUpdateDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let content = UNMutableNotificationContent()
        content.title = "FileFlower Update"
        content.body = "Versie \(item.displayVersionString) is beschikbaar. Open FileFlower om te updaten."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "app-update-\(item.displayVersionString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
