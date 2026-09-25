import Foundation

/// Identificeert een geanimeerde demo. Elke case heeft precies één view,
/// gekoppeld in `GuideDemoView` (GuideDemos/GuideDemoRegistry.swift).
enum GuideDemoID: String, CaseIterable {
    case petals
    case menuBarPopover
    case downloadLoop
    case pathEvidence
    case templateTree
    case integrationFlow
    case syncLanding
    case filesafeVerify
    case privacyCards
}

/// Eén uitlegbare feature.
///
/// Dit is de spil van het hele systeem: een topic verschijnt automatisch in het
/// juiste gids-hoofdstuk. Een feature toevoegen = hier één entry toevoegen.
///
/// De spotlight ("Nieuw in X") bestaat nog niet; `introducedIn` wordt op dit
/// moment nergens uitgelezen. De waarde wordt wél al bijgehouden, zodat de eerste
/// versie mét spotlight geen historie hoeft te reconstrueren.
struct GuideTopic: Identifiable, Hashable {
    /// Stabiele slug. Nooit hergebruiken of hernoemen — de spotlight onthoudt hem.
    let id: String
    let chapter: GuideChapter
    /// MARKETING_VERSION waarin deze feature uitkomt, bijv. "2.2.0".
    let introducedIn: String
    /// Optionele eigen demo. `nil` betekent: gebruik die van het hoofdstuk.
    let demo: GuideDemoID?

    /// Zie de opmerking in `GuideChapter.key(_:)`: interpolatie in een
    /// `LocalizationValue` maakt er een format-sleutel van, dus expliciet literal.
    var titleKey: String.LocalizationValue {
        String.LocalizationValue(stringLiteral: "guide.topic.\(id).title")
    }
    var leadKey: String.LocalizationValue {
        String.LocalizationValue(stringLiteral: "guide.topic.\(id).lead")
    }

    init(_ id: String, chapter: GuideChapter, introducedIn: String = GuideTopic.baselineVersion, demo: GuideDemoID? = nil) {
        self.id = id
        self.chapter = chapter
        self.introducedIn = introducedIn
        self.demo = demo
    }

    /// De versie waarin de gids zelf uitkomt. Alles wat al bestond krijgt deze
    /// waarde, zodat niemand bij de eerste update een spotlight met de hele app krijgt.
    static let baselineVersion = "2.2.0"
}

// MARK: - De inhoud

extension GuideTopic {
    /// Alle topics, in leesvolgorde binnen hun hoofdstuk.
    static let all: [GuideTopic] = [
        // MARK: Welkom
        GuideTopic("scope.new-downloads-only", chapter: .welcome),
        GuideTopic("scope.local-only",         chapter: .welcome),
        GuideTopic("scope.nle-optional",       chapter: .welcome),

        // MARK: DownloadSync
        GuideTopic("queue.type-override",   chapter: .downloadSync),
        GuideTopic("queue.sfx-categories",  chapter: .downloadSync),
        GuideTopic("queue.conflicts",       chapter: .downloadSync),
        GuideTopic("queue.archives",        chapter: .downloadSync),
        GuideTopic("queue.quicklook",       chapter: .downloadSync),
        GuideTopic("queue.history",         chapter: .downloadSync),

        // MARK: Padresolutie
        GuideTopic("path.evidence-layers",  chapter: .pathResolution),
        GuideTopic("path.blocked-folders",  chapter: .pathResolution),
        GuideTopic("path.learned-rules",    chapter: .pathResolution),
        GuideTopic("path.unknown-root",     chapter: .pathResolution)
    ]

    static func topics(for chapter: GuideChapter) -> [GuideTopic] {
        all.filter { $0.chapter == chapter }
    }
}
