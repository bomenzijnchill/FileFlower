import SwiftUI

/// Hoofdstukken van de FileFlower Gids.
///
/// De raw value is een stabiele slug — géén Int — zodat er later hoofdstukken
/// tussengevoegd kunnen worden zonder dat opgeslagen voortgang verschuift.
enum GuideChapter: String, CaseIterable, Identifiable {
    case welcome          = "welcome"
    case menuBar          = "menu-bar"
    case downloadSync     = "download-sync"
    case pathResolution   = "path-resolution"
    case folderStructure  = "folder-structure"
    case integrations     = "integrations"
    case syncAndLoad      = "sync-and-load"
    case fileSafe         = "filesafe"
    case settingsPrivacy  = "settings-privacy"
    case getStarted       = "get-started"

    var id: String { rawValue }

    /// Hoofdstukken die daadwerkelijk inhoud hebben en in de zijbalk verschijnen.
    ///
    /// Fase 0 (prototype) toont er drie. Zodra de overige demo's er zijn wordt dit
    /// `allCases` — dat is de enige regel die dan hoeft te wijzigen.
    static let enabled: [GuideChapter] = [.welcome, .downloadSync, .pathResolution]

    /// Positie binnen `enabled`, voor "Hoofdstuk 2 / 3" en de voortgangsbalk.
    var index: Int { GuideChapter.enabled.firstIndex(of: self) ?? 0 }

    // MARK: - Inhoud

    /// Let op: `String.LocalizationValue` mag je NIET met interpolatie samenstellen —
    /// `"guide.\(rawValue).title"` levert de sleutel `guide.%@.title` op in plaats van
    /// een letterlijke sleutel. Daarom expliciet via `stringLiteral:`.
    private func key(_ suffix: String) -> String.LocalizationValue {
        String.LocalizationValue(stringLiteral: "guide.\(rawValue).\(suffix)")
    }

    var titleKey: String.LocalizationValue { key("title") }
    var leadKey:  String.LocalizationValue { key("lead") }
    var whyKey:   String.LocalizationValue { key("why") }

    /// Korte naam voor de zijbalk.
    var navKey: String.LocalizationValue { key("nav") }

    /// Onderschrift onder het demo-podium, beschrijft wat je ziet.
    var demoCaptionKey: String.LocalizationValue { key("demo_caption") }

    var icon: String {
        switch self {
        case .welcome:         return "hand.wave.fill"
        case .menuBar:         return "menubar.arrow.down.rectangle"
        case .downloadSync:    return "arrow.down.circle.fill"
        case .pathResolution:  return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .folderStructure: return "folder.badge.gearshape"
        case .integrations:    return "app.connected.to.app.below.fill"
        case .syncAndLoad:     return "arrow.triangle.2.circlepath"
        case .fileSafe:        return "externaldrive.badge.checkmark"
        case .settingsPrivacy: return "lock.shield.fill"
        case .getStarted:      return "checkmark.circle.fill"
        }
    }

    /// Accentkleur per hoofdstuk, uit de merkpalet-tokens.
    var accent: Color {
        switch self {
        case .welcome:         return .petalRosePink
        case .menuBar:         return .ink3
        case .downloadSync:    return .brandBurntPeach
        case .pathResolution:  return .brandSkyBlue
        case .folderStructure: return .tileClayBottom
        case .integrations:    return .petalLavender
        case .syncAndLoad:     return .brandSandyClay
        case .fileSafe:        return .statusBad
        case .settingsPrivacy: return .brandSkyBlue
        case .getStarted:      return .brandBurntPeach
        }
    }

    /// De geanimeerde demo die bij dit hoofdstuk hoort.
    var demo: GuideDemoID? {
        switch self {
        case .welcome:         return .petals
        case .downloadSync:    return .downloadLoop
        case .pathResolution:  return .pathEvidence
        default:               return nil
        }
    }
}
