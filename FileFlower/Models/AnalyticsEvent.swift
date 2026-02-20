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
