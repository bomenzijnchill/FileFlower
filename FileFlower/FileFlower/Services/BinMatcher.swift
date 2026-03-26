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
        .footage: ["footage", "raw", "materiaal", "beeldmateriaal", "camera", "rushes", "dailies"],
        .stockFootage: ["stock", "stockfootage", "stock footage", "b-roll", "broll", "shots", "visuals", "clips"]
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

    /// Zoek een bestaande Finder-map die matcht met het gegeven asset type.
    /// Zoekt recursief door de projectstructuur (maxDepth niveaus diep).
    /// Returns de naam van de gematchte map, of nil als er geen match is.
    func findMatchingFolder(for assetType: AssetType, in projectRoot: URL, maxDepth: Int = 3) -> String? {
        guard let keywords = categoryKeywords[assetType] else { return nil }
        return findMatchingFolderRecursive(keywords: keywords, in: projectRoot, maxDepth: maxDepth)
    }

    /// Zoek recursief in submappen voor een match (bijv. binnen 03_Audio zoeken naar VO)
    func findMatchingSubfolder(for assetType: AssetType, in parentFolder: URL, maxDepth: Int = 2) -> String? {
        guard let keywords = categoryKeywords[assetType] else { return nil }
        return findMatchingFolderRecursive(keywords: keywords, in: parentFolder, maxDepth: maxDepth)
    }

    /// Interne recursieve zoekfunctie
    private func findMatchingFolderRecursive(keywords: [String], in directory: URL, maxDepth: Int) -> String? {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let folders = contents.filter { url in
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }

        // Stap 1: Zoek op huidig niveau
        for folder in folders {
            let folderName = folder.lastPathComponent
            let normalized = normalizeName(folderName)

            for keyword in keywords {
                if normalized == keyword || normalized.contains(keyword) || keyword.contains(normalized) {
                    return folderName
                }
            }
        }

        // Stap 2: Recursief zoeken (als maxDepth > 0)
        if maxDepth > 0 {
            for folder in folders {
                let name = folder.lastPathComponent.lowercased()
                // Skip NLE-specifieke en systeem mappen
                if name.contains("adobe") || name.contains("premiere") ||
                   name.contains("davinci") || name.contains("resolve") ||
                   name.contains("auto-save") || name.contains("audio previews") ||
                   name.hasPrefix("01_") || name.hasPrefix(".") {
                    continue
                }
                if let found = findMatchingFolderRecursive(keywords: keywords, in: folder, maxDepth: maxDepth - 1) {
                    return found
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
