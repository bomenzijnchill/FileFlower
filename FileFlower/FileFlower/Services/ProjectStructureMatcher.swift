import Foundation

/// Bepaalt per asset-type de juiste projectmap op basis van **mapnamen**.
///
/// Dit is bewust de PRIMAIRE bron voor de mapping. In een normaal ingerichte
/// projectmap zegt de structuur letterlijk waar alles hoort:
///
///     02_Materiaal/01_Ruw          → footage
///     02_Materiaal/02_Downloaded   → stock footage
///     03_Audio/01_Music            → music
///     03_Audio/02_SFX              → sfx
///     03_Audio/03_VO               → voice over
///     04_Graphics/01_Vormgeving    → graphic
///     04_Graphics/02_VFX           → motion graphic
///
/// Bestandsclassificatie (de backwards-scan) is daar hooguit een verfijning van:
/// bestandsnamen zijn onbetrouwbaar (een VO-opname heet "REC_0231 PROC.wav",
/// een muziektrack heet "Ooyy - Wind of Change.mp3"), mapnamen zijn dat niet.
enum ProjectStructureMatcher {

    /// Ondubbelzinnige mapnaam-trefwoorden per asset-type.
    /// LET OP: "audio"/"sound" staan bewust NIET bij .music — dat is de naam van de
    /// OUDER-map (03_Audio) die music/sfx/vo bevat, niet van de muziekmap zelf.
    static let folderKeywords: [AssetType: [String]] = [
        .footage: ["footage", "materiaal", "ruw", "raw", "rushes", "beeldmateriaal", "clips"],
        // GEEN platformnamen (artlist/artgrid): die leveren óók muziek, dus een map
        // "RUBEN ARTLIST" onder 01_Music is een muziek-collectie, geen stockmap.
        .stockFootage: ["stock", "stockfootage", "downloaded", "broll", "b-roll"],
        .music: ["music", "muziek", "songs", "tracks", "soundtrack"],
        .sfx: ["sfx", "soundfx", "geluidseffecten", "sound effects", "foley", "effecten"],
        .vo: ["vo", "voiceover", "voice over", "voice-over", "spraak", "narration", "dialoog", "voices"],
        .graphic: ["graphics", "vormgeving", "design", "stills", "photos", "fotos", "afbeeldingen", "grafisch"],
        .motionGraphic: ["vfx", "motion", "motiongraphics", "mogrt", "animatie", "animation", "templates"],
    ]

    /// Eén map die op naam bij een asset-type past.
    struct Match {
        let assetType: AssetType
        let relativePath: String
        let depth: Int
    }

    /// Doorzoek de projectmap en bepaal per type de best passende map.
    /// - Parameters:
    ///   - projectRoot: hoofdmap van het project
    ///   - maxDepth: hoe diep we mapnamen inspecteren (3 dekt `04_Graphics/02_VFX/…`)
    static func match(projectRoot: URL, maxDepth: Int = 3) -> [AssetType: Match] {
        var folders: [(path: String, name: String, depth: Int)] = []
        collect(projectRoot, root: projectRoot, depth: 1, maxDepth: maxDepth, into: &folders)

        // Welke types claimt elke map op naam?
        var typesByPath: [String: Set<AssetType>] = [:]
        for folder in folders {
            var claimed: Set<AssetType> = []
            for (type, keywords) in folderKeywords
            where PlacementEngine.matchesAny(folder.name, keywords: keywords) {
                claimed.insert(type)
            }
            if !claimed.isEmpty {
                typesByPath[folder.path] = claimed
            }
        }

        // Kandidaten per type, ondiepste eerst (deterministisch bij gelijke diepte)
        var result: [AssetType: Match] = [:]
        for (type, _) in folderKeywords {
            let candidates = folders
                .filter { typesByPath[$0.path]?.contains(type) == true }
                .sorted { a, b in
                    a.depth != b.depth ? a.depth < b.depth : a.path < b.path
                }
            guard var chosen = candidates.first else { continue }

            // Is de gekozen map een CATEGORIE-CONTAINER? Dat wil zeggen: hij splitst
            // zich op in submappen die verschillende types claimen (bv. 02_Materiaal
            // met 01_Ruw + 02_Downloaded, of 04_Graphics met 01_Vormgeving + 02_VFX).
            // Dan hoort het type in de specifieke submap, niet in de container.
            // Een map met maar één type-claimende submap (01_Music met MUZIEK AA)
            // is géén container — daar blijven we op het bovenste niveau.
            while true {
                let children = folders.filter {
                    $0.depth == chosen.depth + 1 &&
                    $0.path.hasPrefix(chosen.path + "/") &&
                    !$0.path.dropFirst(chosen.path.count + 1).contains("/")
                }
                // Mappen met een "_"-prefix (_STILLS, _OLD, _TEMP) zijn conventioneel
                // hulp-/afgeleide mappen. Ze mogen een map niet als categorie-container
                // laten ogen — anders daalt "02_VFX" af naar "VFX ASSETS LONGFORM"
                // alleen omdat er toevallig een "_STILLS" naast staat.
                let childTypes = Set(
                    children
                        .filter { !$0.name.hasPrefix("_") }
                        .compactMap { typesByPath[$0.path] }
                        .flatMap { $0 }
                )
                guard childTypes.count >= 2,
                      let deeper = children
                        .filter({ typesByPath[$0.path]?.contains(type) == true })
                        .sorted(by: { $0.path < $1.path })
                        .first
                else { break }
                chosen = deeper
            }

            result[type] = Match(assetType: type, relativePath: chosen.path, depth: chosen.depth)
        }

        return result
    }

    // MARK: - Private

    private static func collect(
        _ directory: URL,
        root: URL,
        depth: Int,
        maxDepth: Int,
        into folders: inout [(path: String, name: String, depth: Int)]
    ) {
        guard depth <= maxDepth else { return }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in contents {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            let name = item.lastPathComponent
            // Cache-/NLE-mappen tellen nooit mee als assetmap
            if PathSafetyPolicy.isBlockedFolderName(name) { continue }

            let relative = PlacementEngine.relative(item, to: root)
            guard !relative.isEmpty else { continue }
            folders.append((relative, name, depth))

            collect(item, root: root, depth: depth + 1, maxDepth: maxDepth, into: &folders)
        }
    }
}
