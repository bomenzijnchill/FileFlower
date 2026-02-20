import Foundation

/// Service voor het slim matchen van bestaande mappen/bins op basis van asset type keywords.
/// Wordt gebruikt om bestaande Finder-mappen en Premiere-bins te vinden voor bestanden.
class BinMatcher {
    static let shared = BinMatcher()

    /// Keywords per asset type (in meerdere talen)
    let categoryKeywords: [AssetType: [String]] = [
        .music: ["muziek", "music", "audio", "sound", "soundtrack", "score", "tracks", "songs", "musik", "musique", "música"],
        .sfx: ["sfx", "soundfx", "sound effects", "geluidseffecten", "foley", "effects", "effecten", "geluiden", "effekte", "effets"],
        .vo: ["vo", "voice", "voiceover", "voice-over", "voice over", "ingesproken", "ingesproken tekst", "narration", "dialogue", "spraak", "sprecher", "voix"],
        .graphic: ["graphics", "graphic", "vormgeving", "design", "stills", "afbeeldingen", "images", "fotos", "photos", "bilder", "grafik"],
        .motionGraphic: ["motion", "motion graphics", "motiongraphics", "animatie", "animation", "mogrt", "templates", "bewegend"],
        .stockFootage: ["footage", "stock", "stockfootage", "stock footage", "beeldmateriaal", "b-roll", "broll", "shots", "visuals", "video", "clips"]
    ]

    private init() {}

    /// Normaliseer een mapnaam: strip nummer-prefix (03_) en lowercase
    func normalizeName(_ name: String) -> String {
        var normalized = name.trimmingCharacters(in: .whitespaces).lowercased()
        // Verwijder nummer-prefix patroon zoals "03_" of "01_"
        if let range = normalized.range(of: #"^\d+_"#, options: .regularExpression) {
            normalized.removeSubrange(range)
        }
        return normalized
    }

    /// Zoek een bestaande Finder-map die matcht met het gegeven asset type
    /// Returns de naam van de gematchte map, of nil als er geen match is
    func findMatchingFolder(for assetType: AssetType, in projectRoot: URL) -> String? {
        guard let keywords = categoryKeywords[assetType] else { return nil }

        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let folders = contents.filter { url in
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }

        // Zoek een map die matcht op keywords
        for folder in folders {
            let folderName = folder.lastPathComponent
            let normalized = normalizeName(folderName)

            // Exact match met genormaliseerde naam
            for keyword in keywords {
                if normalized == keyword || normalized.contains(keyword) || keyword.contains(normalized) {
                    return folderName
                }
            }
        }

        return nil
    }

    /// Zoek recursief in submappen voor een match (bijv. binnen 03_Audio zoeken naar VO)
    func findMatchingSubfolder(for assetType: AssetType, in parentFolder: URL) -> String? {
        guard let keywords = categoryKeywords[assetType] else { return nil }

        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: parentFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let folders = contents.filter { url in
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }

        for folder in folders {
            let folderName = folder.lastPathComponent
            let normalized = normalizeName(folderName)

            for keyword in keywords {
                if normalized == keyword || normalized.contains(keyword) || keyword.contains(normalized) {
                    return folderName
                }
            }
        }

        return nil
    }

    /// Geeft de keywords terug voor een bepaald asset type (als JavaScript-compatible array string)
    func keywordsForType(_ assetType: AssetType) -> [String] {
        return categoryKeywords[assetType] ?? []
    }
}
