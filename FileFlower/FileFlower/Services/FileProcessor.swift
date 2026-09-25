import Foundation

class FileProcessor {
    static let shared = FileProcessor()
    
    private init() {}
    
    /// Verwerk een download item: verplaats het bestand en maak optioneel een NLE import job aan.
    /// - Parameters:
    ///   - item: Het te verwerken download item
    ///   - createNLEJob: Als `false`, wordt het bestand alleen verplaatst zonder NLE import job.
    ///     Gebruik dit wanneer het geselecteerde project niet overeenkomt met het actieve NLE project.
    ///   - allowOverwrite: Als `true` (gebruiker koos expliciet "Overschrijven" in de conflict-dialog)
    ///     wordt een bestaand doelbestand vervangen i.p.v. stilletjes als `_2` geversioneerd.
    func process(_ item: DownloadItem, createNLEJob: Bool = true, allowOverwrite: Bool = false) async throws {
        guard let project = item.targetProject,
              let targetPath = item.targetPath else {
            throw FileProcessorError.missingTarget
        }
        
        let sourceURL = URL(fileURLWithPath: item.path)
        let targetURL = URL(fileURLWithPath: targetPath)

        // HARDE GUARD (laatste verdedigingslinie): nooit schrijven in een NLE-cache map,
        // en — tenzij de gebruiker het pad zelf handmatig koos — nooit buiten de projectmap.
        let targetDir = targetURL.deletingLastPathComponent()
        let isManualChoice = item.manualTargetPath != nil
        let mainFolder = isManualChoice ? nil : findProjectMainFolder(
            from: targetDir,
            projectPath: project.projectPath,
            configuredRootHint: project.rootPath
        )
        try PathSafetyPolicy.validateWriteTarget(targetDir, projectMainFolder: mainFolder)

        // Ensure target directory exists
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
            // Move the entire directory (uniek pad zodat een bestaande map niet wordt geraakt,
            // tenzij de gebruiker expliciet voor overschrijven koos)
            let finalTargetURL: URL
            if allowOverwrite {
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                finalTargetURL = targetURL
            } else {
                finalTargetURL = uniqueDestination(targetURL)
            }
            try fileManager.moveItem(at: sourceURL, to: finalTargetURL)

            // Remove quarantine from all files in the directory
            if let enumerator = fileManager.enumerator(
                at: finalTargetURL,
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
            filesToImport = [finalTargetURL.path]

            // Log move
            Logger.shared.logMove(
                from: item.path,
                to: finalTargetURL.path,
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
            // Move file (uniek pad zodat een bestaand bestand niet wordt overschreven of hard faalt,
            // tenzij de gebruiker expliciet voor overschrijven koos in de conflict-dialog)
            let finalTargetURL: URL
            if allowOverwrite {
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                finalTargetURL = targetURL
            } else {
                finalTargetURL = uniqueDestination(targetURL)
            }
            try FileManager.default.moveItem(at: sourceURL, to: finalTargetURL)

            // Remove quarantine
            try Quarantine.removeQuarantineAttribute(from: finalTargetURL)

            filesToImport = [finalTargetURL.path]

            // Log move
            Logger.shared.logMove(
                from: item.path,
                to: finalTargetURL.path,
                itemId: item.id
            )
        }
        
        // NLE import job alleen aanmaken als gewenst (project matcht met actieve NLE)
        if createNLEJob {
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
                let projectMainFolder = findProjectMainFolder(
                    from: targetDir,
                    projectPath: project.projectPath,
                    configuredRootHint: project.rootPath
                )

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

                let components = relativePath.split(separator: "/").filter { !$0.isEmpty }.map { String($0) }

                // GEEN "smart matching" meer op het eerste padsegment.
                // Dat zocht met findMatchingFolder tot 3 niveaus diep naar een map die bij
                // het assettype paste en plakte die KALE NAAM over component[0]. Voor een
                // bestand in "03_Audio/02_SFX/Meme" vond het de geneste map "02_SFX" en
                // maakte er "02_SFX/02_SFX/Meme" van — een dubbele bin op projectniveau,
                // terwijl er al een SFX-bin onder AUDIO bestond.
                //
                // Het relatieve schijfpad ÍS het juiste bin-pad: de plugin normaliseert
                // mapnamen (strip "03_"/"01_"), dus "03_Audio/02_SFX" vindt netjes de
                // bestaande bin "03_AUDIO/01_SFX".
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
        } else {
            #if DEBUG
            print("FileProcessor: Bestand alleen verplaatst (geen NLE import) naar \(targetDir.path)")
            #endif
        }
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
    
    /// Vindt de project main folder (waar 03_Audio, 02_Footage etc. horen).
    /// Forwardt naar `ProjectRootResolver` — dezelfde gezaghebbende bron als de queue-plaatsing,
    /// zodat de berekende Premiere-bin-naam altijd consistent is met waar het bestand op disk belandt.
    private func findProjectMainFolder(from targetDir: URL, projectPath: String, configuredRootHint: String? = nil) -> URL {
        // Virtueel Resolve-pad: targetDir is al een echte directory; gebruik die.
        if projectPath.hasPrefix("/resolve-project/") {
            return targetDir
        }
        return ProjectRootResolver.shared.mainFolder(forProjectPath: projectPath, configuredRootHint: configuredRootHint)
    }

    /// Geef een uniek doelpad: voegt `_2`, `_3`, … toe als er al iets op `target` staat,
    /// zodat een verplaatsing nooit een bestaand bestand/map overschrijft of hard faalt.
    private func uniqueDestination(_ target: URL) -> URL {
        guard FileManager.default.fileExists(atPath: target.path) else { return target }
        let dir = target.deletingLastPathComponent()
        let name = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        var candidate = target
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(name)_\(counter)" : "\(name)_\(counter).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }

    /// Verplaats een bestaand (eerder verwerkt) bestand naar een nieuw project/type.
    /// Maakt de nieuwe doelmap aan, verplaatst het bestand, logt de move,
    /// en maakt een NLE import job aan.
    func moveExistingFile(
        record: HistoryItem,
        to project: ProjectInfo,
        assetType: AssetType,
        subfolder: String? = nil,
        musicMode: MusicMode? = nil,
        sfxCategory: String? = nil
    ) throws -> String {
        let effectiveMusicMode = musicMode ?? .mood
        guard let currentPath = record.destinationPath else {
            throw FileProcessorError.missingTarget
        }

        let sourceURL = URL(fileURLWithPath: currentPath)
        guard FileManager.default.fileExists(atPath: currentPath) else {
            throw FileProcessorError.missingTarget
        }

        // De queue blokkeert verwerken tot de mapindeling van het project bevestigd is
        // (QueueView.processItems). Deze route — verplaatsen vanuit de geschiedenis — kende
        // die eis niet, terwijl het projectlijstje daar automatisch gevuld wordt met gescande
        // en via Spotlight gevonden projecten. Zonder bevestiging mag de structuurlaag hier
        // geen bestemming verzinnen.
        let mappingConfirmed = AppState.shared.config.mappings[project.projectPath]?
            .discoveredStructure?.confirmed == true
        if !mappingConfirmed, AppState.shared.config.folderStructurePreset == .standard {
            throw FileProcessorError.uncertainDestination(
                String(localized: "error.mapping_not_confirmed",
                       defaultValue: "De mapindeling van dit project is nog niet bevestigd. Kies het project één keer in de wachtrij en bevestig de mappen.")
            )
        }

        // Bereken nieuw pad via het volledige lagen-systeem (geleerde regels → evidence → structuur)
        // zodat verplaatsen-vanuit-history dezelfde kwaliteit heeft als queue-verwerking.
        let resolution = PathResolver.shared.resolveTargetWithConfidence(
            project: project,
            assetType: assetType,
            subfolder: subfolder ?? sfxCategory,
            musicMode: effectiveMusicMode,
            fileName: sourceURL.lastPathComponent
        )
        guard resolution.confidence >= PathResolver.shared.confidenceThreshold else {
            throw FileProcessorError.uncertainDestination(resolution.reason)
        }
        let targetDir = resolution.targetFolder.url

        // HARDE GUARD: nooit schrijven in een NLE-cache map of buiten de projectmap
        let mainFolder = findProjectMainFolder(
            from: targetDir,
            projectPath: project.projectPath,
            configuredRootHint: project.rootPath
        )
        try PathSafetyPolicy.validateWriteTarget(targetDir, projectMainFolder: mainFolder)

        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let filename = sourceURL.lastPathComponent
        let targetURL = targetDir.appendingPathComponent(filename)

        // Conflict handling: voeg suffix toe als bestand al bestaat
        let finalTarget = uniqueDestination(targetURL)

        // Verplaats
        try FileManager.default.moveItem(at: sourceURL, to: finalTarget)
        try? Quarantine.removeQuarantineAttribute(from: finalTarget)

        // Log
        Logger.shared.logMove(from: currentPath, to: finalTarget.path, itemId: record.id)

        // NLE job aanmaken
        let nleType = NLEType.from(projectPath: project.projectPath) ?? .premiere
        let premiereBinPath: String
        if let mapping = getPremiereBinMapping(project: project, finderPath: targetDir.path) {
            premiereBinPath = mapping
        } else {
            let projectMainFolder = findProjectMainFolder(from: targetDir, projectPath: project.projectPath)
            let relativePath: String
            if targetDir.path == projectMainFolder.path {
                relativePath = targetDir.lastPathComponent
            } else {
                var path = targetDir.path.replacingOccurrences(of: projectMainFolder.path, with: "")
                if path.hasPrefix("/") { path.removeFirst() }
                relativePath = path
            }
            // Zie process(): geen "smart matching" op component[0] — dat maakte van
            // "03_Audio/02_SFX/Meme" het pad "02_SFX/02_SFX/Meme".
            let components = relativePath.split(separator: "/").filter { !$0.isEmpty }.map { String($0) }
            premiereBinPath = components.isEmpty ? targetDir.lastPathComponent : components.joined(separator: "/")
        }

        let job = JobRequest(
            projectPath: project.projectPath,
            finderTargetDir: targetDir.path,
            premiereBinPath: premiereBinPath,
            files: [finalTarget.path],
            assetType: assetType.rawValue,
            nleType: nleType
        )
        JobServer.shared.addJob(job)

        // Update history record
        ProcessingHistoryManager.shared.updateRecord(
            record.id,
            newDestinationPath: finalTarget.path,
            newTargetProject: project.name,
            newAssetType: assetType
        )

        #if DEBUG
        print("FileProcessor: Bestand verplaatst van \(currentPath) naar \(finalTarget.path)")
        #endif

        return finalTarget.path
    }
}

enum FileProcessorError: LocalizedError {
    case missingTarget
    case moveFailed
    case uncertainDestination(String)

    var errorDescription: String? {
        switch self {
        case .missingTarget:
            return String(localized: "status.failed.missing_target")
        case .moveFailed:
            return String(localized: "status.failed.move_failed")
        case .uncertainDestination(let reason):
            return reason
        }
    }
}

