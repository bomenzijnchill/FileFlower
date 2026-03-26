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
            return TargetFolder(url: projectRoot, relativePath: projectRoot.path)
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
                baseFolder = try findOrCreateFolder(
                    in: projectRoot,
                    names: languageMapping["Audio"] ?? ["Audio"]
                )
            }
        case .sfx:
            // SFX files go directly to project root in 04_SFX folder (not in 03_Muziek)
            baseFolder = projectRoot
        case .motionGraphic, .graphic:
            baseFolder = try findOrCreateFolder(
                in: projectRoot,
                names: languageMapping["Visuals"] ?? ["Visuals"]
            )
        case .footage:
            // Footage gaat naar de footage/raw map
            baseFolder = try findOrCreateFolder(
                in: projectRoot,
                names: languageMapping["Footage"] ?? ["Footage", "Raw", "Materiaal"]
            )
        case .stockFootage:
            baseFolder = try findOrCreateFolder(
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
                let modeFolderURL = try findOrCreateFolder(in: baseFolder, names: [modeFolder])
                targetFolder = try findOrCreateFolder(in: modeFolderURL, names: [subfolder])
            } else {
                // No subfolder selected, place directly in base folder
                targetFolder = baseFolder
            }
            
        case .sfx:
            // SFX files go directly to 04_SFX in project root
            let sfxFolder = try findOrCreateFolder(
                in: projectRoot,
                names: languageMapping["SFX"] ?? ["04_SFX", "SFX"]
            )
            if let subfolder = subfolder, !subfolder.isEmpty {
                targetFolder = try findOrCreateFolder(in: sfxFolder, names: [subfolder])
            } else {
                targetFolder = sfxFolder
            }
            
        case .vo:
            let voFolder = try findOrCreateFolder(
                in: baseFolder,
                names: languageMapping["VO"] ?? ["VO"]
            )
            targetFolder = voFolder
            
        case .motionGraphic, .graphic:
            let graphicsFolder = try findOrCreateFolder(
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
                let youtube4KFolder = try findOrCreateFolder(in: baseFolder, names: [youtube4KSubfolderName])
                targetFolder = youtube4KFolder
            } else {
                let footageFolder = try findOrCreateFolder(in: baseFolder, names: ["StockFootage"])
                targetFolder = footageFolder
            }

        case .unknown:
            break
        }
        
        return TargetFolder(url: targetFolder, relativePath: targetFolder.path)
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
            let targetFolder = try findOrCreateFolder(in: projectRoot, names: fallbackNames)
            return TargetFolder(url: targetFolder, relativePath: targetFolder.path)
        }

        // Bouw target folder op basis van het relatieve pad uit de mapping
        var targetFolder = projectRoot
        for component in path.split(separator: "/") {
            targetFolder = try findOrCreateFolder(in: targetFolder, names: [String(component)])
        }

        // Subfolder handling (mood/genre voor music, categorie voor SFX)
        if let subfolder = subfolder, !subfolder.isEmpty {
            switch assetType {
            case .music:
                let modeFolder = musicMode == .mood ? "Mood" : "Genre"
                let modeFolderURL = try findOrCreateFolder(in: targetFolder, names: [modeFolder])
                targetFolder = try findOrCreateFolder(in: modeFolderURL, names: [subfolder])
            case .sfx:
                targetFolder = try findOrCreateFolder(in: targetFolder, names: [subfolder])
            default:
                break
            }
        }

        #if DEBUG
        print("PathResolver: Custom template resolved -> \(targetFolder.path)")
        #endif
        return TargetFolder(url: targetFolder, relativePath: targetFolder.path)
    }

    // MARK: - Folder Helpers

    private func findOrCreateFolder(in parent: URL, names: [String]) throws -> URL {
        let fileManager = FileManager.default
        
        // First, check if any of the name variants already exist (case-insensitive)
        if let existing = findExistingFolder(in: parent, names: names) {
            return existing
        }
        
        // If none found, try each name variant to create
        for name in names {
            let folderURL = parent.appendingPathComponent(name, isDirectory: true)
            
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return folderURL
                }
            } else {
                // Create folder
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                return folderURL
            }
        }
        
        // If none found, use first name
        let folderURL = parent.appendingPathComponent(names.first ?? "Unknown", isDirectory: true)
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }
    
    private func findProjectMainFolder(prprojPath: URL, configuredRootPath: String) -> URL {
        let fileManager = FileManager.default
        let configuredRootURL = URL(fileURLWithPath: configuredRootPath)

        // Virtueel Resolve pad: database-backed project zonder .drp op disk
        // Gebruik het geconfigureerde rootpad als dat een echte directory is
        if prprojPath.path.hasPrefix("/resolve-project/") {
            if fileManager.fileExists(atPath: configuredRootURL.path) {
                #if DEBUG
                print("PathResolver: Virtual Resolve project, using configured root: \(configuredRootURL.path)")
                #endif
                return configuredRootURL
            }
            // Geconfigureerde root bestaat niet — dit is waarschijnlijk "/resolve-project"
            // Kan geen bestanden organiseren zonder een echte map op disk
            #if DEBUG
            print("PathResolver: Virtual Resolve project, geen echte projectmap gevonden voor: \(configuredRootPath)")
            #endif
            return configuredRootURL
        }

        // Start from the .prproj file's parent directory
        var current = prprojPath.deletingLastPathComponent()

        #if DEBUG
        print("PathResolver: Starting search from: \(current.path)")
        #endif
        
        // Walk up the directory tree until we find the project's main folder
        // This is the folder that contains folders like 03_Muziek, 04_SFX, etc.
        // NOT folders like 01_Adobe (which contains Premiere project files)
        while current.path != "/" {
            // Check if we've gone above the configured root
            if !current.path.hasPrefix(configuredRootURL.path) {
                #if DEBUG
                print("PathResolver: Gone above configured root, using parent of .prproj")
                #endif
                // We've gone too far, use the parent of .prproj
                return prprojPath.deletingLastPathComponent()
            }
            
            // Check if this folder contains audio/music folders
            if let contents = try? fileManager.contentsOfDirectory(
                at: current,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                let folderNames = contents.compactMap { url -> String? in
                    var isDir: ObjCBool = false
                    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir),
                          isDir.boolValue else {
                        return nil
                    }
                    return url.lastPathComponent
                }
                
                #if DEBUG
                print("PathResolver: Checking folder: \(current.path)")
                print("PathResolver: Found folders: \(folderNames.joined(separator: ", "))")
                #endif
                
                // First check: Are we CURRENTLY in a Premiere-specific folder? (check current folder name, not contents)
                let currentFolderName = current.lastPathComponent.lowercased()
                let isCurrentlyInNLEFolder = currentFolderName.contains("adobe") ||
                                                  currentFolderName.contains("premiere") ||
                                                  currentFolderName.contains("davinci") ||
                                                  currentFolderName.contains("resolve") ||
                                                  currentFolderName.contains("audio previews") ||
                                                  currentFolderName.contains("auto-save") ||
                                                  currentFolderName.hasPrefix("01_")
                
                // If we're currently in a Premiere folder (e.g. 01_Adobe), the parent is the project root
                if isCurrentlyInNLEFolder {
                    #if DEBUG
                    print("PathResolver: Currently in NLE folder, skipping: \(current.path)")
                    #endif
                    let parent = current.deletingLastPathComponent()
                    if parent.path != current.path && parent.path.hasPrefix(configuredRootURL.path) {
                        // De parent van een 01_Adobe/Premiere folder IS de project root
                        // ook als er nog geen 03_/04_ mappen bestaan (nieuw project)
                        #if DEBUG
                        print("PathResolver: Found project main folder (parent of Premiere folder): \(parent.path)")
                        #endif
                        return parent
                    }
                }
                
                // Check if we see project structure folders (03_, 04_, etc.)
                let hasProjectStructureFolder = folderNames.contains { name in
                    // Look for numbered folders that indicate project structure
                    return name.hasPrefix("03_") || // 03_Muziek, 03_Audio
                           name.hasPrefix("04_") || // 04_SFX, 04_Visuals
                           name.hasPrefix("05_") || // 05_VFX
                           name.hasPrefix("06_") || // 06_Vormgeving
                           name.hasPrefix("02_")    // 02_Materiaal
                }
                
                // Also check for unnumbered but clear structure folders
                let hasAudioMusicFolder = folderNames.contains { name in
                    let lowerName = name.lowercased()
                    // Look for folders that indicate audio/music content (but NOT Premiere-related)
                    return (lowerName == "muziek" || lowerName == "audio" || lowerName == "music") &&
                           !lowerName.contains("preview") &&
                           !lowerName.contains("adobe")
                }
                
                // If we find project structure folders OR audio/music folders, this is the project main folder
                if hasProjectStructureFolder || hasAudioMusicFolder {
                    #if DEBUG
                    print("PathResolver: Found project main folder at: \(current.path)")
                    #endif
                    return current
                }
            }
            
            // Move up one level
            let parent = current.deletingLastPathComponent()
            
            // If we can't go higher, use current
            if parent.path == current.path {
                break
            }
            
            current = parent
        }
        
        // Fallback: go up from .prproj until we find a folder that's not a Premiere folder
        var fallback = prprojPath.deletingLastPathComponent()
        while fallback.path != "/" {
            let folderName = fallback.lastPathComponent.lowercased()
            // If this is not an NLE folder, use it
            if !folderName.contains("adobe") &&
               !folderName.contains("premiere") &&
               !folderName.contains("davinci") &&
               !folderName.contains("resolve") &&
               !folderName.contains("audio previews") &&
               !folderName.contains("auto-save") &&
               !folderName.hasPrefix("01_") {
                #if DEBUG
                print("PathResolver: Fallback - using: \(fallback.path)")
                #endif
                return fallback
            }
            // Otherwise, go up one more level
            let parent = fallback.deletingLastPathComponent()
            if parent.path == fallback.path {
                break
            }
            fallback = parent
        }
        
        // Last resort: use parent of .prproj
        #if DEBUG
        print("PathResolver: Fallback - using parent of .prproj: \(prprojPath.deletingLastPathComponent().path)")
        #endif
        return prprojPath.deletingLastPathComponent()
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
            
            // Skip NLE-specific folders
            if itemName.contains("adobe") ||
               itemName.contains("premiere") ||
               itemName.contains("davinci") ||
               itemName.contains("resolve") ||
               itemName.contains("preview") ||
               itemName.contains("auto-save") ||
               itemName.hasPrefix("01_") {
                continue
            }
            
            // Check if this folder indicates audio/music
            if itemName == "muziek" || 
               itemName == "audio" || 
               itemName == "music" ||
               itemName.hasPrefix("03_") {
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

        // Stap 1: Zoek exacte en contains-matches op huidig niveau
        for item in folders {
            let itemName = normalizeFolderName(item.lastPathComponent)

            // Exacte match
            for normalizedName in normalizedNames {
                if itemName == normalizedName {
                    return item
                }
            }

            // Contains match (bijv. "03_Audio" bevat "audio")
            for normalizedName in normalizedNames {
                if itemName.contains(normalizedName) || normalizedName.contains(itemName) {
                    if normalizedName.count >= 3 && itemName.count >= 3 {
                        return item
                    }
                }
            }
        }

        // Stap 2: Recursief zoeken in submappen (als maxDepth > 0)
        if maxDepth > 0 {
            for item in folders {
                // Skip NLE-specifieke en systeem mappen
                let name = item.lastPathComponent.lowercased()
                if name.contains("adobe") || name.contains("premiere") ||
                   name.contains("davinci") || name.contains("resolve") ||
                   name.contains("auto-save") || name.contains("audio previews") ||
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

enum PathResolverError: Error {
    case unknownAssetType
    case invalidProjectRoot
}

