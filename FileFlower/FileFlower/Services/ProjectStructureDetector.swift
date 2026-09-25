import Foundation

/// Waar een voorgesteld pad vandaan komt (voor de badge in het bevestigings-paneel).
enum MappingSource: String, Codable {
    case scan      // afgeleid uit waar dit type al staat (sterkste signaal)
    case ai        // semantische AI-analyse (vult gaten)
    case keyword   // trefwoord-match op mapnaam (vangnet)
    case none      // geen voorstel — gebruiker kiest zelf
}

/// Eén voorgestelde map voor een asset-type, relatief t.o.v. de hoofd-projectmap.
struct ProposedFolderMapping: Identifiable {
    let assetType: AssetType
    var relativePath: String       // "" = direct in de projectmap
    var confidence: Double
    var source: MappingSource
    /// Aantal bestanden waarop een scan-voorstel is gebaseerd (voor de badge), indien bekend.
    var scanFileCount: Int = 0
    var id: String { assetType.rawValue }
}

/// Bouwt per project één sterke mapping (asset-type → map) door drie signalen te combineren:
/// 1) zwaar leren uit waar bestanden van dit type AL staan (backwards-scan),
/// 2) AI-folderanalyse erbovenop (alleen voor types zonder scan-resultaat),
/// 3) trefwoord-match als vangnet.
/// Voedt het eenmalige bevestigings-paneel; de gebruiker hoeft meestal alleen "Akkoord" te klikken.
final class ProjectStructureDetector {
    static let shared = ProjectStructureDetector()
    private init() {}

    /// De asset-types die we in de mapping tonen/bevestigen (zonder `.unknown`).
    static let assetTypes: [AssetType] = [.footage, .stockFootage, .music, .sfx, .vo, .graphic, .motionGraphic]

    func detect(for project: ProjectInfo) async -> [ProposedFolderMapping] {
        let mainFolder = PathResolver.shared.projectMainFolderURL(for: project)

        // 1) Backwards-scan — sterkste signaal: waar staan bestanden van dit type al?
        //    Weeg op AANTAL BESTANDEN, niet op padlengte. Voorheen viel de code bij
        //    verspreid bewijs terug op het kortste pad-STRING, waardoor 2 renders in
        //    "99_Export" wonnen van 121 muziekbestanden in "03_Audio/01_Music/*".
        let locations = await ProjectStructureScanner.shared.scanLocations(in: mainFolder)
        var locationsByType: [AssetType: [ProjectStructureScanner.ScannedLocation]] = [:]
        for loc in locations {
            locationsByType[loc.assetType, default: []].append(loc)
        }

        var scanPaths: [AssetType: (path: String, count: Int, dominant: Bool)] = [:]
        for (type, locs) in locationsByType {
            guard let best = Self.dominantLocation(locs) else { continue }
            scanPaths[type] = best
        }

        // 2) AI-analyse — alleen voor types die de scan niet dekte.
        // AI-output wordt gevalideerd: het pad moet veilig zijn (geen cache-map) en
        // daadwerkelijk op disk bestaan binnen de projectmap — anders negeren.
        var aiPaths: [AssetType: String] = [:]
        if Self.assetTypes.contains(where: { scanPaths[$0] == nil }) {
            let tree = FolderTemplateService.shared.scanFolderTree(at: mainFolder)
            let deviceId = AppState.shared.config.anonymousId
            if let mapping = try? await FolderTemplateService.shared.analyzeStructure(tree: tree, deviceId: deviceId) {
                for type in Self.assetTypes where scanPaths[type] == nil {
                    if let p = mapping.path(for: Self.aiKey(for: type)), !p.isEmpty,
                       PathSafetyPolicy.firstBlockedComponent(in: p) == nil,
                       FileManager.default.fileExists(atPath: mainFolder.appendingPathComponent(p).path) {
                        aiPaths[type] = p
                    }
                }
            }
        }

        // 3) Trefwoord-vangnet.
        var keywordPaths: [AssetType: String] = [:]
        let discovered = PathResolver.shared.discoverProjectStructure(projectRoot: mainFolder)
        for (raw, absPath) in discovered {
            guard let type = AssetType(rawValue: raw) else { continue }
            if let rel = PathResolver.shared.makeRelativeToProject(absPath, project: project), !rel.isEmpty {
                keywordPaths[type] = rel
            }
        }

        // 0) STRUCTUUR — de mapnamen zelf. Dit is het sterkste en meest betrouwbare
        //    signaal: "03_Audio/03_VO" zegt onomstotelijk waar voice-overs horen,
        //    terwijl de bestandsnamen erin ("REC_0231 PROC.wav") niets prijsgeven.
        let structural = ProjectStructureMatcher.match(projectRoot: mainFolder)

        // Merge: hoogste prioriteit wint, altijd een rij per type.
        return Self.assetTypes.map { type in
            if let match = structural[type] {
                // Bestandsbewijs mag de structuur VERFIJNEN (dieper binnen dezelfde tak),
                // maar nooit overrulen naar een heel andere tak.
                if let scan = scanPaths[type], scan.dominant,
                   scan.path.hasPrefix(match.relativePath + "/") {
                    return ProposedFolderMapping(
                        assetType: type,
                        relativePath: scan.path,
                        confidence: 0.95,
                        source: .scan,
                        scanFileCount: scan.count
                    )
                }
                let files = scanPaths[type].map { $0.path == match.relativePath || $0.path.hasPrefix(match.relativePath + "/") ? $0.count : 0 } ?? 0
                return ProposedFolderMapping(
                    assetType: type,
                    relativePath: match.relativePath,
                    confidence: 0.95,
                    source: .scan,
                    scanFileCount: files
                )
            } else if let scan = scanPaths[type] {
                // Geen mapnaam-match: val terug op bestandsbewijs.
                if !scan.dominant, let kw = keywordPaths[type], kw != scan.path {
                    return ProposedFolderMapping(assetType: type, relativePath: kw, confidence: 0.55, source: .keyword)
                }
                return ProposedFolderMapping(
                    assetType: type,
                    relativePath: scan.path,
                    confidence: scan.dominant ? 0.9 : 0.6,
                    source: .scan,
                    scanFileCount: scan.count
                )
            } else if let p = aiPaths[type] {
                return ProposedFolderMapping(assetType: type, relativePath: p, confidence: 0.7, source: .ai)
            } else if let p = keywordPaths[type] {
                return ProposedFolderMapping(assetType: type, relativePath: p, confidence: 0.4, source: .keyword)
            } else {
                return ProposedFolderMapping(assetType: type, relativePath: "", confidence: 0.0, source: .none)
            }
        }
    }

    /// AssetType → de sleutel die `FolderTypeMapping.path(for:)` gebruikt.
    /// Alleen `.footage` wijkt af (AI noemt dit "RawFootage").
    static func aiKey(for type: AssetType) -> String {
        type == .footage ? "RawFootage" : type.rawValue
    }

    /// Kies de bestemming voor één asset-type op basis van WAAR DE MEESTE BESTANDEN staan.
    ///
    /// Werkwijze: groepeer de locaties op hun eerste twee pad-componenten (bv.
    /// "03_Audio/01_Music"), tel per groep het aantal bestanden, en neem de zwaarste groep.
    /// Binnen die groep is de gemeenschappelijke bovenliggende map het voorstel.
    /// `dominant` is false als de zwaarste groep geen duidelijke meerderheid heeft (<60%) —
    /// dan is het bewijs te verspreid om er 0.9 zekerheid aan te hangen.
    static func dominantLocation(
        _ locations: [ProjectStructureScanner.ScannedLocation]
    ) -> (path: String, count: Int, dominant: Bool)? {
        let usable = locations.filter { !$0.relativePath.isEmpty }
        guard !usable.isEmpty else { return nil }

        let totalFiles = usable.reduce(0) { $0 + $1.fileCount }
        guard totalFiles > 0 else { return nil }

        // Groepeer op de eerste twee componenten: dat vangt "03_Audio/01_Music/<track>"
        // samen zonder losse projecten in verschillende takken te mengen.
        var groups: [String: [ProjectStructureScanner.ScannedLocation]] = [:]
        for loc in usable {
            let comps = loc.relativePath.split(separator: "/").map(String.init)
            let key = comps.prefix(2).joined(separator: "/")
            groups[key, default: []].append(loc)
        }

        // Zwaarste groep op bestandsaantal (bij gelijkspel: het ondiepste pad)
        let ranked = groups.map { key, locs -> (key: String, locs: [ProjectStructureScanner.ScannedLocation], files: Int) in
            (key, locs, locs.reduce(0) { $0 + $1.fileCount })
        }.sorted {
            $0.files != $1.files
                ? $0.files > $1.files
                : $0.key.split(separator: "/").count < $1.key.split(separator: "/").count
        }

        guard let winner = ranked.first else { return nil }

        // Binnen de winnende groep: gemeenschappelijke bovenliggende map
        let paths = winner.locs.map(\.relativePath)
        let common = commonAncestorPath(paths) ?? ""
        let chosen = common.isEmpty ? winner.key : common
        guard !chosen.isEmpty else { return nil }

        let share = Double(winner.files) / Double(totalFiles)
        return (chosen, winner.files, share >= 0.6)
    }

    /// Langste gemeenschappelijke pad-prefix (op mapcomponent-niveau) van een set relatieve paden.
    static func commonAncestorPath(_ paths: [String]) -> String? {
        guard let first = paths.first else { return nil }
        var prefix = first.split(separator: "/").map(String.init)
        for p in paths.dropFirst() {
            let comps = p.split(separator: "/").map(String.init)
            var i = 0
            while i < prefix.count, i < comps.count, prefix[i] == comps[i] { i += 1 }
            prefix = Array(prefix.prefix(i))
            if prefix.isEmpty { break }
        }
        return prefix.joined(separator: "/")
    }
}
