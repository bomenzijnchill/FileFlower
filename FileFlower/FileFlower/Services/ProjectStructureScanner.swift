import Foundation

/// Scant een bestaand project om te leren welke bestanden waar staan.
/// Gebruikt DirectClassifier om bestanden te classificeren en leidt padregels af.
class ProjectStructureScanner {
    static let shared = ProjectStructureScanner()

    private let classifier = DirectClassifier.shared
    private let maxDepth = 4

    // Cache/systeem-mappen worden centraal via PathSafetyPolicy geblokkeerd (substring-match,
    // dus ook "Adobe Premiere Pro Audio Previews" e.d.). Hier alleen aanvullende exacte namen.
    private let ignoredFolders: Set<String> = [
        ".Spotlight-V100",
        ".Trashes",
        ".DS_Store"
    ]

    private let supportedExtensions: Set<String> = [
        "wav", "mp3", "aiff", "flac", "m4a", "aac", "ogg",
        "mp4", "mov", "mxf", "avi", "mkv", "webm",
        "png", "jpg", "jpeg", "psd", "svg", "gif", "tiff",
        "mogrt", "aep", "aet"
    ]

    private init() {}

    /// Eén plek waar bestanden van een bepaald type staan, MET het aantal bestanden.
    /// De detector heeft dit aantal nodig om het dominante cluster te kiezen; de
    /// oude aanpak telde alleen mappen en koos daarna het kortste pad.
    struct ScannedLocation {
        let assetType: AssetType
        let relativePath: String
        let fileCount: Int
    }

    /// Mappen die per definitie GEEN bronlocatie voor assets zijn. Een gerenderde .wav
    /// in "99_Export" mag nooit tot de conclusie leiden "hier hoort muziek".
    private static let nonSourceFolderKeywords = [
        "export", "exports", "render", "renders", "output", "deliver", "deliverables",
        "final", "documenten", "documents", "docs", "backup", "archief", "archive",
        "proxy", "proxies", "adobe", "premiere", "resolve", "davinci"
    ]

    static func isNonSourceFolder(_ name: String) -> Bool {
        PlacementEngine.matchesAny(name, keywords: nonSourceFolderKeywords)
    }

    /// Trefwoorden die een map ondubbelzinnig aan één asset-type binden.
    private static let folderTypeKeywords: [AssetType: [String]] = [
        .music: ["music", "muziek", "muziek aa", "songs", "tracks"],
        .sfx: ["sfx", "soundfx", "geluidseffecten", "sound effects", "foley"],
        .vo: ["vo", "voiceover", "voice over", "voice-over", "spraak", "narration", "dialoog"],
        .graphic: ["graphics", "vormgeving", "stills", "photos", "fotos"],
        .footage: ["footage", "materiaal", "ruw", "raw", "rushes"],
    ]

    /// True als het gedetecteerde type in tegenspraak is met de mapnaam waarin het staat.
    /// Bv. een VO-classificatie in een map die "MUZIEK" heet.
    static func contradictsFolderName(assetType: AssetType, relativePath: String) -> Bool {
        guard let ownKeywords = folderTypeKeywords[assetType] else { return false }
        let components = relativePath.split(separator: "/").map(String.init)
        guard let deepest = components.last else { return false }

        // Past de mapnaam bij het eigen type? Dan is er geen conflict.
        if PlacementEngine.matchesAny(deepest, keywords: ownKeywords) { return false }

        // Claimt de map (of een ouder ervan) een ANDER audio/asset-type? Dan wel.
        for (otherType, keywords) in folderTypeKeywords where otherType != assetType {
            for component in components.reversed() {
                if PlacementEngine.matchesAny(component, keywords: keywords) {
                    // Alleen conflicteren binnen dezelfde "familie" (audio-types onderling,
                    // beeld-types onderling) — anders zou footage in 03_Audio/... ook sneuvelen
                    // terwijl dat een legitieme (zij het ongewone) keuze kan zijn.
                    let audioTypes: Set<AssetType> = [.music, .sfx, .vo]
                    if audioTypes.contains(assetType) && audioTypes.contains(otherType) {
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Scan een projectmap en geef per (type, map) het aantal bestanden terug.
    func scanLocations(in projectRoot: URL) async -> [ScannedLocation] {
        var frequencyMap: [String: FrequencyEntry] = [:]
        await scanDirectory(projectRoot, relativeTo: projectRoot, depth: 0, frequencyMap: &frequencyMap)

        return frequencyMap.values.compactMap { entry in
            guard let type = AssetType(rawValue: entry.assetType) else { return nil }
            return ScannedLocation(
                assetType: type,
                relativePath: entry.relativePath,
                fileCount: entry.count
            )
        }
    }

    /// Scan een projectmap en genereer geleerde regels op basis van bestaande bestandsplaatsing.
    func scanExistingFiles(in projectRoot: URL) async -> [LearnedPathRule] {
        var frequencyMap: [String: FrequencyEntry] = [:]

        await scanDirectory(projectRoot, relativeTo: projectRoot, depth: 0, frequencyMap: &frequencyMap)

        // Genereer regels waar count >= 2
        var rules: [LearnedPathRule] = []
        for (_, entry) in frequencyMap where entry.count >= 2 {
            let rule = LearnedPathRule(
                assetType: entry.assetType,
                subfolder: entry.subfolder,
                resolvedPath: entry.relativePath,
                fileExtensions: Array(entry.extensions),
                source: nil,
                learnedAt: Date(),
                usageCount: 0,
                isScanned: true
            )
            rules.append(rule)
        }

        #if DEBUG
        print("ProjectStructureScanner: \(rules.count) regels afgeleid uit \(projectRoot.lastPathComponent)")
        #endif

        return rules
    }

    private struct FrequencyEntry {
        let assetType: String
        let subfolder: String?
        let relativePath: String
        var extensions: Set<String>
        var count: Int
    }

    private func scanDirectory(
        _ url: URL,
        relativeTo root: URL,
        depth: Int,
        frequencyMap: inout [String: FrequencyEntry]
    ) async {
        guard depth <= maxDepth else { return }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            let name = item.lastPathComponent

            if ignoredFolders.contains(name) { continue }
            // KRITIEK: nooit leren uit NLE-cache mappen (substring-match, dus ook
            // "Adobe Premiere Pro Audio Previews") — anders vergiftigt een eerder
            // misplaatst bestand de geleerde regels.
            if PathSafetyPolicy.isBlockedFolderName(name) { continue }

            var isDir: ObjCBool = false
            fm.fileExists(atPath: item.path, isDirectory: &isDir)

            if isDir.boolValue {
                // Export/render/documenten/projectbestand-mappen zijn geen BRON van assets.
                // Een gerenderde .wav in 99_Export bewees anders "hier hoort muziek".
                if Self.isNonSourceFolder(name) { continue }
                await scanDirectory(item, relativeTo: root, depth: depth + 1, frequencyMap: &frequencyMap)
            } else {
                let ext = item.pathExtension.lowercased()
                guard supportedExtensions.contains(ext) else { continue }

                let result = classifier.classify(filename: name, metadata: nil, originUrl: nil)
                guard let assetType = result.assetType,
                      result.confidence != .low else { continue }

                let parentPath = item.deletingLastPathComponent()
                let relativePath = parentPath.path.replacingOccurrences(of: root.path, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

                guard !relativePath.isEmpty else { continue }

                // Mapnaam wint van bestandsnaam bij tegenspraak: een als VO geclassificeerd
                // bestand in ".../01_Music/MUZIEK AA" is geen bewijs dat VO daar hoort
                // (het is bijna zeker een muziekbestand dat verkeerd geclassificeerd werd).
                if Self.contradictsFolderName(assetType: assetType, relativePath: relativePath) {
                    continue
                }

                // Detecteer subfolder hint uit mapnaam
                let subfolder = detectSubfolderHint(
                    from: parentPath.lastPathComponent,
                    assetType: assetType
                )

                let key = "\(assetType.rawValue)|\(subfolder ?? "")|\(relativePath)"

                if var existing = frequencyMap[key] {
                    existing.count += 1
                    existing.extensions.insert(ext)
                    frequencyMap[key] = existing
                } else {
                    frequencyMap[key] = FrequencyEntry(
                        assetType: assetType.rawValue,
                        subfolder: subfolder,
                        relativePath: relativePath,
                        extensions: [ext],
                        count: 1
                    )
                }
            }
        }
    }

    /// Detecteer mood/genre/category hints uit mapnamen.
    private func detectSubfolderHint(from folderName: String, assetType: AssetType) -> String? {
        let normalized = folderName
            .replacingOccurrences(of: #"^\d+_"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        switch assetType {
        case .music:
            let moods = ["chill", "energetic", "dark", "happy", "sad", "epic", "ambient",
                         "upbeat", "dramatic", "relaxed", "intense", "melancholic"]
            let genres = ["electronic", "hiphop", "rock", "jazz", "classical", "pop",
                          "ambient", "cinematic", "folk", "indie", "lofi"]
            let lower = normalized.lowercased()
            if moods.contains(lower) || genres.contains(lower) {
                return normalized
            }
        case .sfx:
            let categories = ["swooshes", "impacts", "risers", "transitions", "foley",
                              "ambience", "ui", "explosions", "nature", "mechanical"]
            let lower = normalized.lowercased()
            if categories.contains(lower) {
                return normalized
            }
        default:
            break
        }

        return nil
    }
}
