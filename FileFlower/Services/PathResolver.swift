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
        // Find the project's main folder (where the .prproj file is located)
        // This is the folder that contains the project structure (03_Muziek, 04_SFX, etc.)
        let projectPathURL = URL(fileURLWithPath: project.projectPath)
        let projectRoot = findProjectMainFolder(
            prprojPath: projectPathURL,
            configuredRootPath: project.rootPath
        )
        
        print("PathResolver: Using project root: \(projectRoot.path)")
        
        // For audio/music files, first try to find existing audio/music folder in project
        // Then fall back to creating standard structure
        let baseFolder: URL
        switch assetType {
        case .music, .vo:
            // First, try to find existing audio/music folder
            if let existingAudioFolder = findExistingAudioFolder(in: projectRoot) {
                print("PathResolver: Found existing audio folder: \(existingAudioFolder.path)")
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
            
        case .stockFootage:
            // Speciale routing voor YouTube 4K downloads
            if source == .youtube4K {
                // YouTube 4K bestanden gaan naar Visuals/4KYoutube downloader/
                let youtube4KFolder = try findOrCreateFolder(in: baseFolder, names: [youtube4KSubfolderName])
                targetFolder = youtube4KFolder
                print("PathResolver: YouTube 4K bestand -> \(targetFolder.path)")
            } else {
                let footageFolder = try findOrCreateFolder(in: baseFolder, names: ["StockFootage"])
                targetFolder = footageFolder
            }
            
        case .unknown:
            break
        }
        
        return TargetFolder(url: targetFolder, relativePath: targetFolder.path)
    }
    
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
        
        // Start from the .prproj file's parent directory
        var current = prprojPath.deletingLastPathComponent()
        
        print("PathResolver: Starting search from: \(current.path)")
        
        // Walk up the directory tree until we find the project's main folder
        // This is the folder that contains folders like 03_Muziek, 04_SFX, etc.
        // NOT folders like 01_Adobe (which contains Premiere project files)
        while current.path != "/" {
            // Check if we've gone above the configured root
            if !current.path.hasPrefix(configuredRootURL.path) {
                print("PathResolver: Gone above configured root, using parent of .prproj")
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
                
                print("PathResolver: Checking folder: \(current.path)")
                print("PathResolver: Found folders: \(folderNames.joined(separator: ", "))")
                
                // First check: Are we CURRENTLY in a Premiere-specific folder? (check current folder name, not contents)
                let currentFolderName = current.lastPathComponent.lowercased()
                let isCurrentlyInPremiereFolder = currentFolderName.contains("adobe") ||
                                                  currentFolderName.contains("premiere") ||
                                                  currentFolderName.contains("audio previews") ||
                                                  currentFolderName.contains("auto-save") ||
                                                  currentFolderName.hasPrefix("01_")
                
                // If we're currently in a Premiere folder (e.g. 01_Adobe), the parent is the project root
                if isCurrentlyInPremiereFolder {
                    print("PathResolver: Currently in Premiere folder, skipping: \(current.path)")
                    let parent = current.deletingLastPathComponent()
                    if parent.path != current.path && parent.path.hasPrefix(configuredRootURL.path) {
                        // De parent van een 01_Adobe/Premiere folder IS de project root
                        // ook als er nog geen 03_/04_ mappen bestaan (nieuw project)
                        print("PathResolver: Found project main folder (parent of Premiere folder): \(parent.path)")
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
                    print("PathResolver: Found project main folder at: \(current.path)")
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
            // If this is not a Premiere folder, use it
            if !folderName.contains("adobe") &&
               !folderName.contains("premiere") &&
               !folderName.contains("audio previews") &&
               !folderName.contains("auto-save") &&
               !folderName.hasPrefix("01_") {
                print("PathResolver: Fallback - using: \(fallback.path)")
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
        print("PathResolver: Fallback - using parent of .prproj: \(prprojPath.deletingLastPathComponent().path)")
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
            
            // Skip Premiere-specific folders
            if itemName.contains("adobe") ||
               itemName.contains("premiere") ||
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
                print("PathResolver: Found audio folder: \(item.path)")
                return item
            }
        }
        
        return nil
    }
    
    private func findExistingFolder(in parent: URL, names: [String]) -> URL? {
        let fileManager = FileManager.default
        
        // Get all items in parent directory
        guard let contents = try? fileManager.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        
        // Normalize names for comparison
        // Remove number prefixes (03_, 04_, etc.) and normalize
        let normalizeName: (String) -> String = { name in
            var normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
            // Remove number prefix pattern like "03_" or "01_"
            if let range = normalized.range(of: #"^\d+_"#, options: .regularExpression) {
                normalized = String(normalized[range.upperBound...])
            }
            return normalized
        }
        
        let normalizedNames = names.map(normalizeName)
        
        // Check each existing folder
        for item in contents {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                continue
            }
            
            let itemName = normalizeName(item.lastPathComponent)
            
            // Check if this folder matches any of our name variants
            for normalizedName in normalizedNames {
                if itemName == normalizedName {
                    return item
                }
            }
            
            // Also check if the folder name contains any of our search terms
            // (e.g., "03_Audio" contains "audio")
            for normalizedName in normalizedNames {
                if itemName.contains(normalizedName) || normalizedName.contains(itemName) {
                    // Make sure it's a reasonable match (not too short)
                    if normalizedName.count >= 3 && itemName.count >= 3 {
                        return item
                    }
                }
            }
        }
        
        return nil
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

