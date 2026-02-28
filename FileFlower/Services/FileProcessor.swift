import Foundation

class FileProcessor {
    static let shared = FileProcessor()
    
    private init() {}
    
    func process(_ item: DownloadItem) async throws {
        guard let project = item.targetProject,
              let targetPath = item.targetPath else {
            throw FileProcessorError.missingTarget
        }
        
        let sourceURL = URL(fileURLWithPath: item.path)
        let targetURL = URL(fileURLWithPath: targetPath)
        
        // Ensure target directory exists
        let targetDir = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        
        var filesToImport: [String] = []
        let fileManager = FileManager.default
        
        // Check if source is a directory
        var isDirectory: ObjCBool = false
        let sourceExists = fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
        
        if !sourceExists {
            throw FileProcessorError.missingTarget
        }
        
        if isDirectory.boolValue {
            // Handle directory (e.g., extracted music folder from ZIP)
            // Move the entire directory
            try fileManager.moveItem(at: sourceURL, to: targetURL)
            
            // Remove quarantine from all files in the directory
            if let enumerator = fileManager.enumerator(
                at: targetURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                let allFiles = enumerator.allObjects.compactMap { $0 as? URL }
                for fileURL in allFiles {
                    var isFile: ObjCBool = false
                    if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isFile),
                       !isFile.boolValue {
                        try? Quarantine.removeQuarantineAttribute(from: fileURL)
                    }
                }
            }
            
            // Import the folder as a whole (Premiere will import all contents)
            filesToImport = [targetURL.path]
            
            // Log move
            Logger.shared.logMove(
                from: item.path,
                to: targetPath,
                itemId: item.id
            )
        } else if sourceURL.pathExtension.lowercased() == "zip" {
            // Handle zip files
            let extracted = try Unzipper.unzip(sourceURL, to: targetDir)
            filesToImport = extracted.map { $0.path }
            // Log each extracted file
            for extractedURL in extracted {
                Logger.shared.logMove(
                    from: sourceURL.path,
                    to: extractedURL.path,
                    itemId: item.id
                )
                // Remove quarantine from extracted files
                try? Quarantine.removeQuarantineAttribute(from: extractedURL)
            }
        } else {
            // Move file
            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            
            // Remove quarantine
            try Quarantine.removeQuarantineAttribute(from: targetURL)
            
            filesToImport = [targetPath]
            
            // Log move
            Logger.shared.logMove(
                from: item.path,
                to: targetPath,
                itemId: item.id
            )
        }
        
        // Detecteer NLE type op basis van project extensie
        let nleType = NLEType.from(projectPath: project.projectPath) ?? .premiere

        // Create job request for NLE import
        let premiereBinPath: String
        if let mapping = getPremiereBinMapping(project: project, finderPath: targetDir.path) {
            premiereBinPath = mapping
            #if DEBUG
            print("FileProcessor: Using mapped bin path: \(mapping)")
            #endif
        } else {
            // Default: create bin path from folder structure relative to project main folder
            let projectMainFolder = findProjectMainFolder(from: targetDir, projectPath: project.projectPath)

            // Bepaal relative path; voorkom lege string als targetDir gelijk is aan projectMainFolder
            let relativePath: String
            if targetDir.path == projectMainFolder.path {
                relativePath = targetDir.lastPathComponent
            } else {
                var path = targetDir.path.replacingOccurrences(of: projectMainFolder.path, with: "")
                if path.hasPrefix("/") {
                    path.removeFirst()
                }
                relativePath = path
            }

            var components = relativePath.split(separator: "/").filter { !$0.isEmpty }.map { String($0) }

            // Smart matching: check of er al een bestaande Finder-map is die beter matcht
            if !components.isEmpty {
                if let matchedFolder = BinMatcher.shared.findMatchingFolder(
                    for: item.predictedType,
                    in: projectMainFolder
                ) {
                    let normalizedFirst = BinMatcher.shared.normalizeName(components[0])
                    let normalizedMatch = BinMatcher.shared.normalizeName(matchedFolder)
                    if normalizedFirst != normalizedMatch {
                        #if DEBUG
                        print("FileProcessor: Smart match - '\(components[0])' → '\(matchedFolder)' voor type \(item.predictedType.rawValue)")
                        #endif
                        components[0] = matchedFolder
                    }
                }
            }

            premiereBinPath = components.isEmpty ? targetDir.lastPathComponent : components.joined(separator: "/")
            #if DEBUG
            print("FileProcessor: Project main folder: \(projectMainFolder.path)")
            print("FileProcessor: Target dir: \(targetDir.path)")
            print("FileProcessor: Relative path: \(relativePath)")
            print("FileProcessor: Calculated bin path: \(premiereBinPath)")
            #endif
        }
        
        #if DEBUG
        print("FileProcessor: Creating job for project: \(project.projectPath)")
        print("FileProcessor: Files to import: \(filesToImport)")
        print("FileProcessor: Premiere bin path: \(premiereBinPath)")
        #endif
        
        let job = JobRequest(
            projectPath: project.projectPath,
            finderTargetDir: targetDir.path,
            premiereBinPath: premiereBinPath,
            files: filesToImport,
            assetType: item.predictedType.rawValue,
            nleType: nleType
        )
        
        JobServer.shared.addJob(job)
    }
    
    private func getPremiereBinMapping(project: ProjectInfo, finderPath: String) -> String? {
        // Get mapping from config
        let config = AppState.shared.config
        guard let projectMapping = config.mappings[project.projectPath] else {
            return nil
        }
        
        // Find matching finder path in mappings
        for (finder, premiere) in projectMapping.finderToPremiere {
            if finderPath.contains(finder) {
                return premiere
            }
        }
        
        return nil
    }
    
    /// Vindt de project main folder (waar 03_Muziek, 04_SFX etc. staan)
    /// door omhoog te navigeren vanaf de target directory
    private func findProjectMainFolder(from targetDir: URL, projectPath: String) -> URL {
        let fileManager = FileManager.default
        let projectURL = URL(fileURLWithPath: projectPath)
        let prprojParent = projectURL.deletingLastPathComponent()

        // Virtueel Resolve pad: gebruik targetDir als startpunt (is al een echte directory)
        // De fallback-logica hieronder zou anders een virtueel pad teruggeven
        let isVirtualResolvePath = projectPath.hasPrefix("/resolve-project/")

        // Walk up from target directory to find the project structure folder
        var current = targetDir
        
        while current.path != "/" {
            // Check if this folder has project structure markers
            if let contents = try? fileManager.contentsOfDirectory(
                at: current,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                let folderNames = contents.compactMap { url -> String? in
                    var isDir: ObjCBool = false
                    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir),
                          isDir.boolValue else { return nil }
                    return url.lastPathComponent
                }
                
                // Look for numbered folders (03_, 04_, 05_, etc.) that indicate project structure
                let hasProjectStructure = folderNames.contains { name in
                    name.hasPrefix("02_") || name.hasPrefix("03_") ||
                    name.hasPrefix("04_") || name.hasPrefix("05_") ||
                    name.hasPrefix("06_")
                }
                
                if hasProjectStructure {
                    return current
                }
            }
            
            // Also check if we're at the parent of the .prproj file
            // (the project main folder often contains the Adobe folder with the .prproj)
            if current.path == prprojParent.deletingLastPathComponent().path {
                return current
            }
            
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        
        // Fallback: go up two levels from .prproj (from 01_Adobe/project.prproj to project root)
        // Voor virtuele Resolve paden: gebruik targetDir zelf als fallback (is een echte directory)
        if isVirtualResolvePath {
            return targetDir
        }
        return prprojParent.deletingLastPathComponent()
    }
}

enum FileProcessorError: Error {
    case missingTarget
    case moveFailed
}

