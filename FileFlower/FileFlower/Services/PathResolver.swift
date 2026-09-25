import Foundation

class PathResolver {
    static let shared = PathResolver()
    
    private let languageMapping: [String: [String]] = [
        "Audio": ["03_Audio", "Audio"],
        "Music": ["01_Music", "Muziek"],
        "SFX": ["04_SFX", "02_SFX", "SFX", "Geluidseffecten"],
        "VO": ["03_VO", "VoiceOver"],
        "Visuals": ["04_Visuals", "Visuals"],
        "Graphics": ["01_Graphics", "Graphics"],
        "MotionGraphics": ["02_MotionGraphics", "MotionGraphics"],
        "Stills": ["03_Stills", "Stills"],
        "Grade": ["04_Grade", "Grade"],
        "VFX": ["05_VFX", "VFX"]
    ]
    
    // Subfolder naam voor YouTube 4K downloads
    private let youtube4KSubfolderName = "4KYoutube downloader"
    
    private init() {}
    
    /// Resolve target folder met optionele source parameter voor speciale routing
    func resolveTarget(
        project: ProjectInfo,
        assetType: AssetType,
        subfolder: String?,
        musicMode: MusicMode,
        source: DetectedSource? = nil
    ) throws -> TargetFolder {
        let config = AppState.shared.config

        // Custom template pad: gebruik AI-gegenereerde mapping
        if config.folderStructurePreset == .custom,
           let template = config.customFolderTemplate {
            return try resolveTargetWithCustomTemplate(
                project: project,
                assetType: assetType,
                subfolder: subfolder,
                musicMode: musicMode,
                source: source,
                template: template
            )
        }

        // Flat preset: alles direct in project root
        if config.folderStructurePreset == .flat {
            let projectPathURL = URL(fileURLWithPath: project.projectPath)
            let projectRoot = findProjectMainFolder(
                prprojPath: projectPathURL,
                configuredRootPath: project.rootPath
            )
            return TargetFolder(url: projectRoot, relativePath: "")
        }

        // Standard preset: bestaande logica
        // Find the project's main folder (where the .prproj file is located)
        // This is the folder that contains the project structure (03_Muziek, 04_SFX, etc.)
        let projectPathURL = URL(fileURLWithPath: project.projectPath)
        let projectRoot = findProjectMainFolder(
            prprojPath: projectPathURL,
            configuredRootPath: project.rootPath
        )
        
        #if DEBUG
        print("PathResolver: Using project root: \(projectRoot.path)")
        #endif
        
        // For audio/music files, first try to find existing audio/music folder in project
        // Then fall back to creating standard structure
        let baseFolder: URL
        switch assetType {
        case .music, .vo:
            // First, try to find existing audio/music folder
            if let existingAudioFolder = findExistingAudioFolder(in: projectRoot) {
                #if DEBUG
                print("PathResolver: Found existing audio folder: \(existingAudioFolder.path)")
                #endif
                baseFolder = existingAudioFolder
            } else {
                // Create standard audio folder structure
                baseFolder = planFolder(
                    in: projectRoot,
                    names: languageMapping["Audio"] ?? ["Audio"]
                )
            }
        case .sfx:
            // SFX files go directly to project root in 04_SFX folder (not in 03_Muziek)
            baseFolder = projectRoot
        case .motionGraphic, .graphic:
            baseFolder = planFolder(
                in: projectRoot,
                names: languageMapping["Visuals"] ?? ["Visuals"]
            )
        case .footage:
            // Footage gaat naar de footage/raw map
            baseFolder = planFolder(
                in: projectRoot,
                names: languageMapping["Footage"] ?? ["Footage", "Raw", "Materiaal"]
            )
        case .stockFootage:
            baseFolder = planFolder(
                in: projectRoot,
                names: languageMapping["Visuals"] ?? ["Visuals"]
            )
        case .unknown:
            throw PathResolverError.unknownAssetType
        }
        
        // Handle subfolder based on asset type
        var targetFolder = baseFolder
        
        switch assetType {
        case .music:
            // Music mode: Mood or Genre - only create if subfolder is selected
            if let subfolder = subfolder, !subfolder.isEmpty {
                // Only create Mood/Genre folder if there's a subfolder to put in it
                let modeFolder = musicMode == .mood ? "Mood" : "Genre"
                let modeFolderURL = planFolder(in: baseFolder, names: [modeFolder])
                targetFolder = planFolder(in: modeFolderURL, names: [subfolder])
            } else {
                // No subfolder selected, place directly in base folder
                targetFolder = baseFolder
            }
            
        case .sfx:
            // SFX files go directly to 04_SFX in project root
            let sfxFolder = planFolder(
                in: projectRoot,
                names: languageMapping["SFX"] ?? ["04_SFX", "SFX"]
            )
            if let subfolder = subfolder, !subfolder.isEmpty {
                targetFolder = planFolder(in: sfxFolder, names: [subfolder])
            } else {
                targetFolder = sfxFolder
            }
            
        case .vo:
            let voFolder = planFolder(
                in: baseFolder,
                names: languageMapping["VO"] ?? ["VO"]
            )
            targetFolder = voFolder
            
        case .motionGraphic, .graphic:
            let graphicsFolder = planFolder(
                in: baseFolder,
                names: languageMapping["Graphics"] ?? ["Graphics"]
            )
            targetFolder = graphicsFolder
            
        case .footage:
            // Footage gaat direct in de base footage map (of subfolder als opgegeven)
            targetFolder = baseFolder

        case .stockFootage:
            // Speciale routing voor YouTube 4K downloads
            if source == .youtube4K {
                let youtube4KFolder = planFolder(in: baseFolder, names: [youtube4KSubfolderName])
                targetFolder = youtube4KFolder
            } else {
                let footageFolder = planFolder(in: baseFolder, names: ["StockFootage"])
                targetFolder = footageFolder
            }

        case .unknown:
            break
        }

        return TargetFolder(url: targetFolder, relativePath: relativeFolderPath(of: targetFolder, under: projectRoot))
    }

    /// Bereken het relatieve pad van een map t.o.v. de project-hoofdmap ("" = de hoofdmap zelf).
    private func relativeFolderPath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == rootPath { return "" }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard path.hasPrefix(prefix) else { return path }
        return String(path.dropFirst(prefix.count))
    }

    // MARK: - Preview Path (read-only, geen filesystem side-effects)

    /// Berekent een leesbaar preview-pad dat laat zien waar het bestand naartoe gaat, zonder mappen aan te maken
    func previewRelativePath(
        project: ProjectInfo,
        assetType: AssetType,
        subfolder: String?,
        musicMode: MusicMode,
        sfxCategory: String? = nil
    ) -> String {
        var components: [String] = [project.name]

        switch assetType {
        case .music:
            components.append("Audio")
            components.append("Music")
            if let sub = subfolder, !sub.isEmpty {
                components.append(musicMode == .mood ? "Mood" : "Genre")
                components.append(sub)
            }
        case .sfx:
            components.append("SFX")
            if let cat = sfxCategory, !cat.isEmpty {
                components.append(cat)
            } else if let sub = subfolder, !sub.isEmpty {
                components.append(sub)
            }
        case .vo:
            components.append("Audio")
            components.append("VO")
        case .motionGraphic, .graphic:
            components.append("Visuals")
            components.append("Graphics")
        case .footage:
            components.append("Footage")
        case .stockFootage:
            components.append("Visuals")
            components.append("StockFootage")
        case .unknown:
            return ""
        }

        return components.joined(separator: " → ")
    }

    // MARK: - Confidence-Based Resolution

    let confidenceThreshold: Double = 0.6

    /// De daadwerkelijke project main folder (bv. de map die 03_Audio, 04_SFX, etc. bevat).
    /// Handig om als startpunt te gebruiken voor folder pickers.
    func projectMainFolderURL(for project: ProjectInfo) -> URL {
        let projectPathURL = URL(fileURLWithPath: project.projectPath)
        return findProjectMainFolder(
            prprojPath: projectPathURL,
            configuredRootPath: project.rootPath
        )
    }

    /// Convert een absoluut doelpad naar een relatief pad t.o.v. de project main folder.
    /// Returns nil als het pad NIET onder de project root valt — dan moet de regel niet opgeslagen worden.
    /// Een leeg pad ("") is geldig en betekent "in de project root zelf".
    func makeRelativeToProject(_ absolutePath: String, project: ProjectInfo) -> String? {
        // Als het al een relatief pad is (geen leading /), accepteer het direct
        if !absolutePath.hasPrefix("/") {
            return absolutePath
        }

        let projectPathURL = URL(fileURLWithPath: project.projectPath)
        let projectRoot = findProjectMainFolder(
            prprojPath: projectPathURL,
            configuredRootPath: project.rootPath
        )
        let rootPath = projectRoot.path

        // Normaliseer trailing slashes
        let normalizedRoot = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        let normalizedAbs = absolutePath.hasSuffix("/") ? String(absolutePath.dropLast()) : absolutePath

        if normalizedAbs == normalizedRoot {
            return ""
        }

        let prefix = normalizedRoot + "/"
        guard normalizedAbs.hasPrefix(prefix) else {
            #if DEBUG
            print("PathResolver: chosenPath \(normalizedAbs) ligt buiten project root \(normalizedRoot) — niet opslaan")
            #endif
            return nil
        }

        return String(normalizedAbs.dropFirst(prefix.count))
    }

    /// Resolve target folder met confidence score, via drie lagen:
    ///   1. Door de gebruiker bevestigde/geleerde regels (hoogste autoriteit)
    ///   2. Bewijs: waar staan vergelijkbare bestanden ál in dit project (PlacementEngine)
    ///   3. Structuur/keyword-conventie (resolveTarget — puur, maakt niets aan)
    /// Elke laag wordt gevalideerd tegen PathSafetyPolicy; een geblokkeerd resultaat
    /// valt door naar de volgende laag. Resolutie heeft GEEN filesystem side-effects,
    /// dus de confidence beschrijft het plan — niet een zojuist zelf aangemaakte map.
    /// Laag 1 als losse stap: de geleerde of bevestigde regel voor dit project.
    /// Geeft nil als er geen bruikbare regel is, of als de regel naar een geblokkeerde map wijst.
    /// `isConfirmed` onderscheidt een regel uit het bevestigings-paneel van een gescande/geleerde.
    private func learnedRuleResolution(
        project: ProjectInfo,
        assetType: AssetType,
        subfolder: String?,
        musicMode: MusicMode,
        source: DetectedSource?,
        projectRoot: URL
    ) -> (resolution: PathResolution, isConfirmed: Bool)? {
        // SKIP regels met absolute paden (legacy bug data) — die zouden tot folder-nesting leiden
        guard let learned = PathLearningManager.shared.findMatchingRule(
            projectPath: project.projectPath,
            assetType: assetType,
            subfolder: subfolder,
            source: source
        ), !learned.resolvedPath.hasPrefix("/") else { return nil }

        var url = projectRoot.appendingPathComponent(learned.resolvedPath)

        // Een generieke regel (zonder submap) is de BASIS; de gevraagde mood/genre/
        // categorie-submap hoort daar nog onder — zelfde structuur als resolveTarget.
        if learned.subfolder == nil, let sub = subfolder, !sub.isEmpty {
            switch assetType {
            case .music:
                let modeFolder = musicMode == .mood ? "Mood" : "Genre"
                url = planFolder(in: planFolder(in: url, names: [modeFolder]), names: [sub])
            case .sfx:
                url = planFolder(in: url, names: [sub])
            default:
                break
            }
        }

        // Veiligheidscheck: een regel die (uit oude data) naar een cache-map wijst is ongeldig
        guard PathSafetyPolicy.firstBlockedComponent(in: url.path) == nil else { return nil }

        let mappingConfirmed = AppState.shared.config.mappings[project.projectPath]?
            .discoveredStructure?.confirmed == true
        let isConfirmed = mappingConfirmed && !learned.isScanned

        let confidence: Double
        if isConfirmed {
            confidence = 1.0
        } else if learned.isScanned {
            confidence = 0.75
        } else if learned.usageCount >= 3 {
            confidence = 1.0
        } else {
            confidence = 0.85
        }

        let resolution = PathResolution(
            targetFolder: TargetFolder(url: url, relativePath: relativeFolderPath(of: url, under: projectRoot)),
            confidence: confidence,
            reason: isConfirmed ? "Bevestigde mapindeling" : "Geleerd uit \(learned.usageCount) eerdere keuze(s)"
        )
        return (resolution, isConfirmed)
    }

    func resolveTargetWithConfidence(
        project: ProjectInfo,
        assetType: AssetType,
        subfolder: String?,
        musicMode: MusicMode,
        source: DetectedSource? = nil,
        fileName: String? = nil
    ) -> PathResolution {
        guard assetType != .unknown else {
            return PathResolution(
                targetFolder: TargetFolder(url: URL(fileURLWithPath: "/"), relativePath: ""),
                confidence: 0.0,
                reason: "Onbekend bestandstype"
            )
        }

        let projectRoot = findProjectMainFolder(
            prprojPath: URL(fileURLWithPath: project.projectPath),
            configuredRootPath: project.rootPath
        )

        let preset = AppState.shared.config.folderStructurePreset

        // Een BEVESTIGDE mapindeling is de meest expliciete keuze die de gebruiker kan maken:
        // hij heeft per asset-type in het paneel aangewezen waar het hoort. Die gaat daarom
        // vóór het eigen sjabloon — anders bleef het bevestigings-paneel zonder effect voor
        // iedereen met een custom template. Flat blijft wél kortsluiten: daar is "alles in de
        // projectmap" per definitie het antwoord.
        if preset == .custom,
           let learned = learnedRuleResolution(
               project: project, assetType: assetType, subfolder: subfolder,
               musicMode: musicMode, source: source, projectRoot: projectRoot
           ), learned.isConfirmed {
            return learned.resolution
        }

        // Flat en custom presets zijn verder expliciete gebruikerskeuzes — evidence en
        // gescande regels mogen die niet omzeilen. Direct het structuurplan gebruiken.
        if preset == .flat || preset == .custom {
            if let plan = try? resolveTarget(
                project: project, assetType: assetType, subfolder: subfolder,
                musicMode: musicMode, source: source
            ), PathSafetyPolicy.firstBlockedComponent(in: plan.url.path) == nil {
                return PathResolution(
                    targetFolder: plan,
                    confidence: preset == .flat ? 0.95 : 0.85,
                    reason: preset == .flat ? "Flat-indeling (alles in projectmap)" : "Eigen mapindeling (template)"
                )
            }
            return PathResolution(
                targetFolder: TargetFolder(url: URL(fileURLWithPath: "/"), relativePath: ""),
                confidence: 0.0,
                reason: "Kan geen veilige bestemming bepalen"
            )
        }

        // ── Laag 1: geleerde/bevestigde regels ──────────────────────────────
        if let learned = learnedRuleResolution(
            project: project, assetType: assetType, subfolder: subfolder,
            musicMode: musicMode, source: source, projectRoot: projectRoot
        ) {
            return learned.resolution
        }

        // ── Laag 3 alvast berekenen (nodig voor kruisvalidatie met laag 2) ──
        let structurePlan: TargetFolder? = (try? resolveTarget(
            project: project,
            assetType: assetType,
            subfolder: subfolder,
            musicMode: musicMode,
            source: source
        )).flatMap { plan in
            // Geblokkeerd structuurplan (cache-map) is geen geldig plan
            PathSafetyPolicy.firstBlockedComponent(in: plan.url.path) == nil ? plan : nil
        }

        // ── Laag 2: bewijs — waar staan vergelijkbare bestanden al? ─────────
        var evidenceCandidates: [PlacementCandidate] = []
        if let query = placementQuery(for: assetType, fileName: fileName, subfolder: subfolder) {
            evidenceCandidates = PlacementEngine().findCandidates(
                snapshot: cachedSnapshot(for: projectRoot),
                query: query
            )
        }

        if let top = evidenceCandidates.first, top.score >= 30, top.peerCount >= 3,
           !top.relativePath.isEmpty {
            // Sterk bewijs. Kruisvalidatie met het structuurplan verhoogt de zekerheid.
            let agreesWithStructure = structurePlan.map { plan in
                top.directoryURL.path == plan.url.path ||
                top.directoryURL.path.hasPrefix(plan.url.path + "/") ||
                plan.url.path.hasPrefix(top.directoryURL.path + "/")
            } ?? false

            // Submap-verfijning: als de bewijs-map een BESTAANDE submap heeft die matcht op
            // de mood/genre/categorie, plaats daar. Anders plat bij de peers — we bouwen geen
            // Mood/Genre-structuur op in mappen waar de gebruiker die niet gebruikt.
            var targetURL = top.directoryURL
            if let sub = subfolder, !sub.isEmpty,
               let existingSub = findExistingFolder(in: top.directoryURL, names: [sub], maxDepth: 0) {
                targetURL = existingSub
            }

            return PathResolution(
                targetFolder: TargetFolder(url: targetURL, relativePath: relativeFolderPath(of: targetURL, under: projectRoot)),
                confidence: agreesWithStructure ? 0.9 : 0.85,
                reason: top.reason,
                alternatives: Array(evidenceCandidates.prefix(4))
            )
        }

        // ── Laag 3: structuur/keyword-conventie ─────────────────────────────
        if let plan = structurePlan {
            let folderExists = FileManager.default.fileExists(atPath: plan.url.path)
            let hasDiscoveredStructure = AppState.shared.config.mappings[project.projectPath]?.discoveredStructure != nil

            // Matig bewijs uit laag 2 dat het structuurplan tegenspreekt → bevestiging vragen
            let conflictingEvidence = evidenceCandidates.first.map { top in
                top.score >= 15 &&
                top.directoryURL.path != plan.url.path &&
                !top.directoryURL.path.hasPrefix(plan.url.path + "/") &&
                !plan.url.path.hasPrefix(top.directoryURL.path + "/")
            } ?? false

            let confidence: Double
            let reason: String
            if conflictingEvidence {
                confidence = 0.5
                reason = "Structuur wijst naar \(plan.relativePath.isEmpty ? "projectmap" : plan.relativePath), maar vergelijkbare bestanden staan ergens anders"
            } else if folderExists && hasDiscoveredStructure {
                confidence = 0.8
                reason = "Bestaande map gevonden"
            } else if folderExists {
                confidence = 0.7
                reason = "Map bestaat, structuur niet eerder gescand"
            } else if hasDiscoveredStructure {
                confidence = 0.5
                reason = "Map moet aangemaakt worden"
            } else {
                confidence = 0.3
                reason = "Geen bekende structuur, pad is een schatting"
            }

            return PathResolution(
                targetFolder: plan,
                confidence: confidence,
                reason: reason,
                alternatives: Array(evidenceCandidates.prefix(4))
            )
        }

        // ── Niets bruikbaars: expliciet onzeker, nooit gokken ────────────────
        return PathResolution(
            targetFolder: TargetFolder(url: URL(fileURLWithPath: "/"), relativePath: ""),
            confidence: 0.0,
            reason: "Kan geen veilige bestemming bepalen",
            alternatives: Array(evidenceCandidates.prefix(4))
        )
    }

    // MARK: - Evidence snapshot cache

    /// Snapshot van de projectboom per projectroot, kort gecached zodat een batch
    /// (reresolve/verwerk-ronde) maar één filesystem-walk doet — belangrijk op netwerkschijven.
    private var snapshotCache: [String: (date: Date, entries: [PlacementDirEntry])] = [:]
    private let snapshotTTL: TimeInterval = 60

    private func cachedSnapshot(for projectRoot: URL) -> [PlacementDirEntry] {
        let key = projectRoot.standardizedFileURL.path
        if let cached = snapshotCache[key], Date().timeIntervalSince(cached.date) < snapshotTTL {
            return cached.entries
        }
        let entries = PlacementEngine().snapshot(projectRoot: projectRoot)
        snapshotCache[key] = (Date(), entries)
        return entries
    }

    /// Bouw de evidence-query voor een asset type.
    private func placementQuery(for assetType: AssetType, fileName: String?, subfolder: String?) -> PlacementQuery? {
        let audioExts: Set<String> = ["wav", "mp3", "aiff", "aif", "flac", "m4a", "aac", "ogg"]
        let videoExts: Set<String> = ["mp4", "mov", "mxf", "avi", "mkv", "webm", "braw", "r3d"]
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "psd", "svg", "gif", "tiff", "webp", "ai", "eps"]
        let motionExts: Set<String> = ["mogrt", "aep", "aet"]

        switch assetType {
        case .music:
            return PlacementQuery(
                fileName: fileName ?? "",
                peerExtensions: audioExts,
                keywords: ["music", "muziek", "audio", "soundtrack"],
                avoidKeywords: ["sfx", "soundfx", "geluidseffecten", "vo", "voiceover", "voice",
                                "foley", "effects", "effecten", "sound effects"],
                subfolder: subfolder
            )
        case .sfx:
            return PlacementQuery(
                fileName: fileName ?? "",
                peerExtensions: audioExts,
                keywords: ["sfx", "soundfx", "geluidseffecten", "foley", "effecten", "sound effects"],
                avoidKeywords: ["music", "muziek", "vo", "voiceover"],
                subfolder: subfolder
            )
        case .vo:
            return PlacementQuery(
                fileName: fileName ?? "",
                peerExtensions: audioExts,
                keywords: ["vo", "voiceover", "voice", "spraak", "narration"],
                avoidKeywords: ["music", "muziek", "sfx", "geluidseffecten", "effects", "sound effects"],
                subfolder: subfolder
            )
        case .footage:
            return PlacementQuery(
                fileName: fileName ?? "",
                peerExtensions: videoExts,
                keywords: ["footage", "materiaal", "raw", "rushes", "media"],
                avoidKeywords: ["exports", "export", "final", "render", "renders", "output", "stock"],
                subfolder: subfolder
            )
        case .stockFootage:
            return PlacementQuery(
                fileName: fileName ?? "",
                peerExtensions: videoExts,
                keywords: ["stock", "stockfootage", "broll", "b-roll"],
                avoidKeywords: ["exports", "export", "final", "render", "renders", "output"],
                subfolder: subfolder
            )
        case .graphic:
            return PlacementQuery(
                fileName: fileName ?? "",
                peerExtensions: imageExts,
                keywords: ["graphics", "vormgeving", "design", "stills", "visuals"],
                avoidKeywords: ["exports", "export"],
                subfolder: subfolder
            )
        case .motionGraphic:
            return PlacementQuery(
                fileName: fileName ?? "",
                peerExtensions: motionExts,
                keywords: ["motiongraphics", "motion", "templates", "mogrt", "graphics", "visuals"],
                avoidKeywords: [],
                subfolder: subfolder
            )
        case .unknown:
            return nil
        }
    }

    /// Invalideer de gecachte structuur en scan opnieuw.
    func invalidateAndRediscover(for project: ProjectInfo) async -> DiscoveredProjectStructure? {
        let config = AppState.shared.config
        let mappingKey = project.projectPath

        // Evidence-snapshot is ook verouderd
        snapshotCache.removeAll()

        // Verwijder oude gescande regels (behoud handmatige)
        PathLearningManager.shared.clearScannedRules(for: mappingKey)

        // Scan folder structuur opnieuw
        let projectPathURL = URL(fileURLWithPath: project.projectPath)
        let projectRoot = findProjectMainFolder(
            prprojPath: projectPathURL,
            configuredRootPath: project.rootPath
        )

        let discoveredPaths = discoverProjectStructure(projectRoot: projectRoot)
        let convention = detectNamingConvention(in: projectRoot)

        // Voer backwards reasoning uit
        let scannedRules = await ProjectStructureScanner.shared.scanExistingFiles(in: projectRoot)

        // Behoud bestaande handmatige regels
        let existingManualRules = config.mappings[mappingKey]?.discoveredStructure?.learnedRules?
            .filter { !$0.isScanned } ?? []

        let structure = DiscoveredProjectStructure(
            discoveredPaths: discoveredPaths,
            namingConvention: convention.rawValue,
            lastScannedDate: Date(),
            learnedRules: existingManualRules + scannedRules
        )

        // Sla op
        var updatedConfig = AppState.shared.config
        var mapping = updatedConfig.mappings[mappingKey] ?? ProjectMapping()
        mapping.discoveredStructure = structure
        updatedConfig.mappings[mappingKey] = mapping

        AppState.shared.config = updatedConfig
        ConfigManager.shared.save(updatedConfig)

        return structure
    }

    // MARK: - Custom Template Routing

    /// Resolve target folder op basis van de custom folder template mapping
    private func resolveTargetWithCustomTemplate(
        project: ProjectInfo,
        assetType: AssetType,
        subfolder: String?,
        musicMode: MusicMode,
        source: DetectedSource?,
        template: CustomFolderTemplate
    ) throws -> TargetFolder {
        let projectPathURL = URL(fileURLWithPath: project.projectPath)
        let projectRoot = findProjectMainFolder(
            prprojPath: projectPathURL,
            configuredRootPath: project.rootPath
        )

        #if DEBUG
        print("PathResolver: Custom template routing vanuit: \(projectRoot.path)")
        #endif

        let mapping = template.mapping

        // Zoek het pad voor dit asset type uit de AI mapping
        let relativePath: String?
        switch assetType {
        case .music:
            relativePath = mapping.musicPath
        case .sfx:
            relativePath = mapping.sfxPath
        case .vo:
            relativePath = mapping.voPath
        case .graphic:
            relativePath = mapping.graphicsPath
        case .motionGraphic:
            relativePath = mapping.motionGraphicsPath
        case .footage:
            relativePath = mapping.rawFootagePath ?? mapping.stockFootagePath
        case .stockFootage:
            relativePath = mapping.stockFootagePath
        case .unknown:
            throw PathResolverError.unknownAssetType
        }

        guard let path = relativePath, !path.isEmpty else {
            #if DEBUG
            print("PathResolver: Geen custom mapping voor \(assetType), fallback naar standaard")
            #endif
            let fallbackNames: [String]
            switch assetType {
            case .music: fallbackNames = languageMapping["Music"] ?? ["Music"]
            case .sfx: fallbackNames = languageMapping["SFX"] ?? ["SFX"]
            case .vo: fallbackNames = languageMapping["VO"] ?? ["VO"]
            case .graphic: fallbackNames = languageMapping["Graphics"] ?? ["Graphics"]
            case .motionGraphic: fallbackNames = languageMapping["MotionGraphics"] ?? ["MotionGraphics"]
            case .footage: fallbackNames = languageMapping["Footage"] ?? ["Footage", "Raw", "Materiaal"]
            case .stockFootage: fallbackNames = ["StockFootage"]
            case .unknown: throw PathResolverError.unknownAssetType
            }
            let targetFolder = planFolder(in: projectRoot, names: fallbackNames)
            return TargetFolder(url: targetFolder, relativePath: relativeFolderPath(of: targetFolder, under: projectRoot))
        }

        // Bouw target folder op basis van het relatieve pad uit de mapping
        var targetFolder = projectRoot
        for component in path.split(separator: "/") {
            targetFolder = planFolder(in: targetFolder, names: [String(component)])
        }

        // Subfolder handling (mood/genre voor music, categorie voor SFX)
        if let subfolder = subfolder, !subfolder.isEmpty {
            switch assetType {
            case .music:
                let modeFolder = musicMode == .mood ? "Mood" : "Genre"
                let modeFolderURL = planFolder(in: targetFolder, names: [modeFolder])
                targetFolder = planFolder(in: modeFolderURL, names: [subfolder])
            case .sfx:
                targetFolder = planFolder(in: targetFolder, names: [subfolder])
            default:
                break
            }
        }

        #if DEBUG
        print("PathResolver: Custom template resolved -> \(targetFolder.path)")
        #endif
        return TargetFolder(url: targetFolder, relativePath: relativeFolderPath(of: targetFolder, under: projectRoot))
    }

    // MARK: - Folder Helpers

    /// Plan een map binnen `parent`: gebruik een bestaande map als die matcht, anders het
    /// BEOOGDE pad met de eerste naam-variant. Maakt NOOIT een map aan — resolutie is puur;
    /// mappen worden pas fysiek aangemaakt door FileProcessor op het moment van verplaatsen.
    private func planFolder(in parent: URL, names: [String]) -> URL {
        if let existing = findExistingFolder(in: parent, names: names) {
            return existing
        }

        // Bestaat er al een map met exact één van deze namen (zonder fuzzy match)?
        let fileManager = FileManager.default
        for name in names {
            let folderURL = parent.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return folderURL
            }
        }

        // Nog niet aanwezig: plan de map met de eerste naam-variant
        return parent.appendingPathComponent(names.first ?? "Unknown", isDirectory: true)
    }
    
    /// Forwardt naar ProjectRootResolver — de gezaghebbende bepaling van de hoofd-projectmap.
    /// (Voorheen koos dit soms de map van het .prproj-bestand zelf, bv. 01_PremierePro.)
    private func findProjectMainFolder(prprojPath: URL, configuredRootPath: String) -> URL {
        return ProjectRootResolver.shared.mainFolder(forProjectPath: prprojPath.path, configuredRootHint: configuredRootPath)
    }
    
    private func findExistingAudioFolder(in parent: URL) -> URL? {
        let fileManager = FileManager.default
        
        // Get all items in parent directory
        guard let contents = try? fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        
        // Look for folders that indicate audio/music content
        // BUT exclude Premiere-specific folders
        for item in contents {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            
            let itemName = item.lastPathComponent.lowercased()

            // Skip NLE-cache en systeem-mappen (centrale policy) + extra NLE-heuristieken
            if PathSafetyPolicy.isBlockedFolderName(itemName) ||
               itemName.contains("adobe") ||
               itemName.contains("premiere") ||
               itemName.contains("davinci") ||
               itemName.contains("resolve") ||
               itemName.contains("preview") ||
               itemName.hasPrefix("01_") {
                continue
            }
            
            // Wijst deze map op audio? Woordgrens-match, GEEN kaal "03_"-prefix.
            // Dat prefix accepteerde elke map die met 03_ begint: in een project met
            // 03_Grading en zonder muziekmap belandden muziek en VO daar — de map bestond,
            // dus confidence 0.7 en het gebeurde zonder te vragen.
            // "03_Audio" en "03_Geluid" matchen nog steeds: op het woord, niet op het cijfer.
            if PlacementEngine.matchesAny(itemName, keywords: ["audio", "muziek", "music", "geluid", "sound"]) {
                #if DEBUG
                print("PathResolver: Found audio folder: \(item.path)")
                #endif
                return item
            }
        }
        
        return nil
    }
    
    /// Zoek recursief naar een bestaande map die matcht met de gegeven namen.
    /// - Parameters:
    ///   - parent: De bovenliggende map om in te zoeken
    ///   - names: Naam-varianten om op te matchen (bijv. ["03_Audio", "Audio"])
    ///   - maxDepth: Maximale zoekdiepte (0 = alleen huidige map, 3 = standaard)
    private func findExistingFolder(in parent: URL, names: [String], maxDepth: Int = 3) -> URL? {
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let normalizedNames = names.map(normalizeFolderName)

        let folders = contents.filter { url in
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }

        // KRITIEK: cache/NLE-mappen mogen NOOIT als asset-map matchen.
        // Dit voorkomt dat bv. "Adobe Premiere Pro Audio Previews" matcht bij zoeken naar "Audio"
        // (de exacte bug die een bestand in de Premiere render-cache plaatste).
        let matchableFolders = folders.filter { !PathSafetyPolicy.isBlockedFolderName($0.lastPathComponent) }

        // Stap 1: Zoek exacte matches op huidig niveau
        for item in matchableFolders {
            let itemName = normalizeFolderName(item.lastPathComponent)
            for normalizedName in normalizedNames {
                if itemName == normalizedName {
                    return item
                }
            }
        }

        // Stap 1b: token-gebaseerde match ("Audio Files" matcht "audio"; "Audiobooks" NIET).
        // Bewust strakker dan de oude substring-match die bv. "Audiobooks" als audiomap zag.
        for item in matchableFolders {
            if PlacementEngine.matchesAny(item.lastPathComponent, keywords: normalizedNames) {
                return item
            }
        }

        // Stap 2: Recursief zoeken in submappen (als maxDepth > 0)
        if maxDepth > 0 {
            for item in matchableFolders {
                // Skip NLE-specifieke mappen bij het afdalen
                let name = item.lastPathComponent.lowercased()
                if name.contains("adobe") || name.contains("premiere") ||
                   name.contains("davinci") || name.contains("resolve") ||
                   name.hasPrefix("01_") || name.hasPrefix(".") {
                    continue
                }
                if let found = findExistingFolder(in: item, names: names, maxDepth: maxDepth - 1) {
                    return found
                }
            }
        }

        return nil
    }

    /// Normaliseer een mapnaam: strip nummer-prefix (03_) en lowercase
    private func normalizeFolderName(_ name: String) -> String {
        var normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let range = normalized.range(of: #"^\d+_"#, options: .regularExpression) {
            normalized = String(normalized[range.upperBound...])
        }
        return normalized
    }

    // MARK: - Naming Convention Detection

    /// Detecteer de naamgeving-conventie van een project op basis van bestaande mappen
    func detectNamingConvention(in projectRoot: URL) -> NamingConvention {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .unknown
        }

        let folderNames = contents.compactMap { url -> String? in
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return url.lastPathComponent
        }

        let dutchKeywords = ["muziek", "geluidseffecten", "vormgeving", "materiaal", "geluid"]
        let englishKeywords = ["audio", "music", "sfx", "graphics", "footage", "visuals"]
        var hasNumberPrefix = false
        var dutchScore = 0
        var englishScore = 0

        for name in folderNames {
            let lower = name.lowercased()
            if lower.range(of: #"^\d+_"#, options: .regularExpression) != nil {
                hasNumberPrefix = true
            }
            for keyword in dutchKeywords {
                if lower.contains(keyword) { dutchScore += 1 }
            }
            for keyword in englishKeywords {
                if lower.contains(keyword) { englishScore += 1 }
            }
        }

        if dutchScore > englishScore {
            return hasNumberPrefix ? .numberedDutch : .plainDutch
        } else if englishScore > 0 {
            return hasNumberPrefix ? .numberedEnglish : .plainEnglish
        }
        return hasNumberPrefix ? .numberedEnglish : .unknown
    }

    // MARK: - Project Structure Discovery

    /// Scan de hele projectstructuur en ontdek bestaande mappen per asset type.
    /// Resultaten worden gecached in Config.mappings voor hergebruik.
    func discoverProjectStructure(projectRoot: URL) -> [String: String] {
        var discovered: [String: String] = [:]

        for (assetType, keywords) in BinMatcher.shared.categoryKeywords {
            // Zoek recursief vanuit de project root
            if let found = findExistingFolder(in: projectRoot, names: keywords, maxDepth: 4) {
                discovered[assetType.rawValue] = found.path
            }
        }

        #if DEBUG
        print("PathResolver: Discovered \(discovered.count) asset folders in \(projectRoot.lastPathComponent)")
        for (type, path) in discovered {
            print("  \(type) → \(path)")
        }
        #endif

        return discovered
    }

    /// Haal de gecachte discovery op, of voer een scan uit als de cache verlopen is
    func getOrDiscoverStructure(for project: ProjectInfo) -> DiscoveredProjectStructure? {
        let projectKey = project.projectPath
        let config = AppState.shared.config

        // Check bestaande cache
        if let mapping = config.mappings[projectKey],
           let existing = mapping.discoveredStructure,
           existing.isValid {
            return existing
        }

        // Voer discovery scan uit
        let projectRoot = findProjectMainFolder(
            prprojPath: URL(fileURLWithPath: project.projectPath),
            configuredRootPath: project.rootPath
        )

        let discoveredPaths = discoverProjectStructure(projectRoot: projectRoot)
        guard !discoveredPaths.isEmpty else { return nil }

        let convention = detectNamingConvention(in: projectRoot)
        let structure = DiscoveredProjectStructure(
            discoveredPaths: discoveredPaths,
            namingConvention: convention.rawValue,
            lastScannedDate: Date()
        )

        // Sla op in config cache
        var updatedConfig = config
        var mapping = updatedConfig.mappings[projectKey] ?? ProjectMapping()
        mapping.discoveredStructure = structure
        updatedConfig.mappings[projectKey] = mapping
        AppState.shared.config = updatedConfig
        AppState.shared.saveConfig()

        return structure
    }
}

struct TargetFolder {
    let url: URL
    let relativePath: String
}

struct PathResolution {
    let targetFolder: TargetFolder
    let confidence: Double
    let reason: String
    /// Alternatieve bestemmingen op basis van bewijs (voor het bevestigings-UI)
    var alternatives: [PlacementCandidate] = []
}

enum PathResolverError: Error {
    case unknownAssetType
    case invalidProjectRoot
}

