import Foundation

/// Onthoudt wat er van de gids gezien is.
///
/// Bewust gescheiden van `SetupManager`: de gids raakt de configuratie nooit aan,
/// dus opnieuw bekijken is gratis. `SetupManager.resetOnboarding()` wist wél setup-status
/// en moet daar los van blijven.
final class GuideManager {
    static let shared = GuideManager()

    private let hasSeenGuideKey     = "hasSeenGuide"
    private let lastChapterKey      = "guideLastChapter"
    private let seenChaptersKey     = "guideSeenChapters"

    private init() {}

    // MARK: - Status

    /// Of de gids ooit helemaal geopend is geweest. Bepaalt of iemand bij een update
    /// de volle gids krijgt of alleen een spotlight met wat er nieuw is.
    var hasSeenGuide: Bool {
        get { UserDefaults.standard.bool(forKey: hasSeenGuideKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasSeenGuideKey) }
    }

    /// Hoofdstukken die de gebruiker geopend heeft, als slugs.
    var seenChapters: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: seenChaptersKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: seenChaptersKey) }
    }

    /// Waar de gebruiker het laatst was, zodat heropenen daar verdergaat.
    var lastChapter: GuideChapter {
        get {
            guard let slug = UserDefaults.standard.string(forKey: lastChapterKey),
                  let chapter = GuideChapter(rawValue: slug),
                  GuideChapter.enabled.contains(chapter) else {
                return GuideChapter.enabled.first ?? .welcome
            }
            return chapter
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lastChapterKey) }
    }

    // MARK: - Bijhouden

    func markSeen(_ chapter: GuideChapter) {
        var seen = seenChapters
        seen.insert(chapter.rawValue)
        seenChapters = seen
        lastChapter = chapter

        // Zodra alle hoofdstukken bekeken zijn telt de gids als gezien.
        if seen.isSuperset(of: GuideChapter.enabled.map(\.rawValue)) {
            hasSeenGuide = true
        }
    }

    func hasSeen(_ chapter: GuideChapter) -> Bool {
        seenChapters.contains(chapter.rawValue)
    }

    /// Aandeel bekeken hoofdstukken, voor de voortgangsbalk in de zijbalk.
    var progress: Double {
        let total = GuideChapter.enabled.count
        guard total > 0 else { return 0 }
        let seen = GuideChapter.enabled.filter { hasSeen($0) }.count
        return Double(seen) / Double(total)
    }

    /// Markeert de gids als afgerond, ook als niet elk hoofdstuk geopend is.
    /// Wordt aangeroepen als het venster via de laatste knop gesloten wordt.
    func markGuideFinished() {
        hasSeenGuide = true
    }

    /// Reset — alleen voor testen. Raakt de app-configuratie niet aan.
    func reset() {
        UserDefaults.standard.removeObject(forKey: hasSeenGuideKey)
        UserDefaults.standard.removeObject(forKey: lastChapterKey)
        UserDefaults.standard.removeObject(forKey: seenChaptersKey)
    }
}
