import Foundation

/// Representeert een analytics event dat naar Supabase gestuurd wordt
struct AnalyticsEvent: Codable {
    let id: UUID
    let eventType: String
    let eventData: [String: AnyCodableValue]
    let appVersion: String
    let osVersion: String
    let locale: String
    let timestamp: Date

    init(
        eventType: String,
        eventData: [String: AnyCodableValue] = [:],
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        locale: String = Locale.current.identifier
    ) {
        self.id = UUID()
        self.eventType = eventType
        self.eventData = eventData
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.locale = locale
        self.timestamp = Date()
    }
}

// MARK: - Event Types

extension AnalyticsEvent {
    /// App is gestart
    static func appLaunched() -> AnalyticsEvent {
        AnalyticsEvent(eventType: "app_launched")
    }

    /// Download gedetecteerd van een stock website
    static func downloadDetected(sourceWebsite: String, assetType: String, fileExtension: String) -> AnalyticsEvent {
        AnalyticsEvent(
            eventType: "download_detected",
            eventData: [
                "source_website": .string(sourceWebsite),
                "asset_type": .string(assetType),
                "file_extension": .string(fileExtension)
            ]
        )
    }

    /// Classificatie voltooid
    static func classificationComplete(assetType: String, confidence: String, method: String, durationMs: Int) -> AnalyticsEvent {
        AnalyticsEvent(
            eventType: "classification_complete",
            eventData: [
                "asset_type": .string(assetType),
                "confidence": .string(confidence),
                "method": .string(method),
                "duration_ms": .int(durationMs)
            ]
        )
    }

    /// Bestand succesvol geimporteerd
    static func fileImported(assetType: String, sourceWebsite: String, hadSubfolder: Bool, targetFolderType: String) -> AnalyticsEvent {
        AnalyticsEvent(
            eventType: "file_imported",
            eventData: [
                "asset_type": .string(assetType),
                "source_website": .string(sourceWebsite),
                "had_subfolder": .bool(hadSubfolder),
                "target_folder_type": .string(targetFolderType)
            ]
        )
    }

    /// Feature toggle gewijzigd
    static func featureToggled(featureName: String, enabled: Bool) -> AnalyticsEvent {
        AnalyticsEvent(
            eventType: "feature_toggled",
            eventData: [
                "feature_name": .string(featureName),
                "enabled": .bool(enabled)
            ]
        )
    }

    /// Wizard voltooid
    static func wizardCompleted(languageChosen: String, musicClassify: Bool, sfxSubfolders: Bool, autoStart: Bool, analyticsOptIn: Bool) -> AnalyticsEvent {
        AnalyticsEvent(
            eventType: "wizard_completed",
            eventData: [
                "language_chosen": .string(languageChosen),
                "music_classify": .bool(musicClassify),
                "sfx_subfolders": .bool(sfxSubfolders),
                "auto_start": .bool(autoStart),
                "analytics_opt_in": .bool(analyticsOptIn)
            ]
        )
    }

    /// Sessie samenvatting bij afsluiten
    static func sessionSummary(durationMinutes: Int, downloadsCount: Int, importsCount: Int, errorsCount: Int) -> AnalyticsEvent {
        AnalyticsEvent(
            eventType: "session_summary",
            eventData: [
                "duration_minutes": .int(durationMinutes),
                "downloads_count": .int(downloadsCount),
                "imports_count": .int(importsCount),
                "errors_count": .int(errorsCount)
            ]
        )
    }

    /// Fout opgetreden
    static func errorOccurred(errorType: String, context: String) -> AnalyticsEvent {
        AnalyticsEvent(
            eventType: "error_occurred",
            eventData: [
                "error_type": .string(errorType),
                "context": .string(context)
            ]
        )
    }

    /// Premiere connectie status
    static func premiereConnection(connected: Bool, pluginVersion: String?) -> AnalyticsEvent {
        var data: [String: AnyCodableValue] = ["connected": .bool(connected)]
        if let version = pluginVersion {
            data["plugin_version"] = .string(version)
        }
        return AnalyticsEvent(eventType: "premiere_connection", eventData: data)
    }

    /// User correctie op classificatie (voor learning analytics)
    static func classificationCorrected(originalType: String, correctedType: String, source: String) -> AnalyticsEvent {
        return AnalyticsEvent(eventType: "classification_corrected", eventData: [
            "original_type": .string(originalType),
            "corrected_type": .string(correctedType),
            "source": .string(source)
        ])
    }

    // MARK: - Core Usage Events

    /// Bestand overgeslagen door gebruiker of systeem
    static func fileSkipped(assetType: String, reason: String) -> AnalyticsEvent {
        AnalyticsEvent(eventType: "file_skipped", eventData: [
            "asset_type": .string(assetType),
            "reason": .string(reason)
        ])
    }

    /// Monitored map toegevoegd, verwijderd of gewijzigd
    static func folderWatchedChanged(action: String, folderType: String) -> AnalyticsEvent {
        AnalyticsEvent(eventType: "folder_watched_changed", eventData: [
            "action": .string(action),
            "folder_type": .string(folderType)
        ])
    }

    // MARK: - Error Events

    /// Import mislukt met gedetailleerde info
    static func importFailed(fileType: String, fileSizeMB: Int, destination: String, error: String) -> AnalyticsEvent {
        AnalyticsEvent(eventType: "import_failed", eventData: [
            "file_type": .string(fileType),
            "file_size_mb": .int(fileSizeMB),
            "destination": .string(destination),
            "error": .string(error)
        ])
    }

    /// NLE niet gevonden bij app start of import
    static func nleNotFound(nle: String) -> AnalyticsEvent {
        AnalyticsEvent(eventType: "nle_not_found", eventData: [
            "nle": .string(nle)
        ])
    }

    // MARK: - Onboarding Events

    /// Onboarding wizard gestart
    static func onboardingStarted() -> AnalyticsEvent {
        AnalyticsEvent(eventType: "onboarding_started")
    }

    /// Onboarding stap bereikt (funnel tracking)
    static func onboardingStep(step: String, stepIndex: Int) -> AnalyticsEvent {
        AnalyticsEvent(eventType: "onboarding_step", eventData: [
            "step": .string(step),
            "step_index": .int(stepIndex)
        ])
    }

    /// Eerste succesvolle import ooit (belangrijk activatie-event)
    static func firstImportCompleted(destination: String) -> AnalyticsEvent {
        AnalyticsEvent(eventType: "first_import_completed", eventData: [
            "destination": .string(destination)
        ])
    }

    // MARK: - Business Events

    /// Trial periode gestart
    static func trialStarted() -> AnalyticsEvent {
        AnalyticsEvent(eventType: "trial_started")
    }

    /// Trial periode verlopen
    static func trialExpired(daysUsed: Int) -> AnalyticsEvent {
        AnalyticsEvent(eventType: "trial_expired", eventData: [
            "days_used": .int(daysUsed)
        ])
    }

    /// Gebruiker opende purchase pagina (conversie funnel)
    static func purchaseInitiated() -> AnalyticsEvent {
        AnalyticsEvent(eventType: "purchase_initiated")
    }

    /// License activatie poging
    static func licenseActivated(success: Bool, error: String?) -> AnalyticsEvent {
        var data: [String: AnyCodableValue] = ["success": .bool(success)]
        if let error = error {
            data["error"] = .string(error)
        }
        return AnalyticsEvent(eventType: "license_activated", eventData: data)
    }

    /// License gedeactiveerd (apparaat vrijgegeven)
    static func licenseDeactivated() -> AnalyticsEvent {
        AnalyticsEvent(eventType: "license_deactivated")
    }

    // MARK: - Extra Insight Events

    /// DaVinci Resolve connectie status
    static func resolveConnection(connected: Bool) -> AnalyticsEvent {
        AnalyticsEvent(eventType: "resolve_connection", eventData: [
            "connected": .bool(connected)
        ])
    }

    /// Gebruiker heeft een mislukt item opnieuw geprobeerd
    static func queueItemRetried() -> AnalyticsEvent {
        AnalyticsEvent(eventType: "queue_item_retried")
    }

    /// App update gedetecteerd (eerste launch na update)
    static func appUpdated(fromVersion: String, toVersion: String) -> AnalyticsEvent {
        AnalyticsEvent(eventType: "app_updated", eventData: [
            "from_version": .string(fromVersion),
            "to_version": .string(toVersion)
        ])
    }

    /// Snapshot van gebruikersinstellingen (eenmalig per sessie)
    static func settingsSnapshot(selectedNLEs: String, folderPreset: String, musicClassify: Bool, sfxSubfolders: Bool, autoStart: Bool) -> AnalyticsEvent {
        AnalyticsEvent(eventType: "settings_snapshot", eventData: [
            "selected_nles": .string(selectedNLEs),
            "folder_preset": .string(folderPreset),
            "music_classify": .bool(musicClassify),
            "sfx_subfolders": .bool(sfxSubfolders),
            "auto_start": .bool(autoStart)
        ])
    }
}

// MARK: - AnyCodableValue voor flexibele event data

enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.typeMismatch(AnyCodableValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        }
    }
}
