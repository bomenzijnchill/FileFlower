import Foundation

class FileSafeStructureBuilder {
    static let shared = FileSafeStructureBuilder()

    /// Gecachte AI analyse resultaten per project pad
    var aiAnalysisCache: [String: FolderStructureAnalyzer.AnalysisResult] = [:]

    // MARK: - Bouw structuur op basis van project + card config

    func buildStructure(
        projectPath: String,
        scanResult: FileSafeScanResult,
        projectConfig: FileSafeProjectConfig,
        cardConfig: FileSafeCardConfig,
        folderPreset: FolderStructurePreset,
        customTemplate: CustomFolderTemplate?,
        activeTemplate: FolderStructureTemplate? = nil,
        activeTemplateValues: [String: String] = [:]
    ) -> (tree: FileSafeTargetFolder, mappings: [FileSafeFileMapping]) {

        // Bepaal basispaden voor video/audio/foto.
        // Als er een active template is, gebruik die (placeholder-resolve met opgegeven waarden).
        let basePaths: BasePaths
        if let template = activeTemplate {
            basePaths = resolveBasePaths(
                template: template,
                values: activeTemplateValues,
                existingProjectPath: projectPath
            )
        } else {
            basePaths = resolveBasePaths(
                preset: folderPreset,
                customTemplate: customTemplate,
                existingProjectPath: projectPath
            )
        }

        // Als foto's in de footage-map staan EN er zijn zowel video als foto:
        // maak "Video" en "Photo" subfolders om ze gescheiden te houden
        let videoBasePath: String
        let photoBasePath: String

        if basePaths.photosInFootage && scanResult.hasVideo && scanResult.hasPhoto {
            videoBasePath = "\(basePaths.footagePath)/Video"
            photoBasePath = "\(basePaths.footagePath)/Photo"
        } else {
            videoBasePath = basePaths.footagePath
            photoBasePath = basePaths.photoPath
        }

        var mappings: [FileSafeFileMapping] = []
        var rootChildren: [FileSafeTargetFolder] = []

        // Video structuur
        if scanResult.hasVideo {
            let (videoTree, videoMappings) = buildVideoStructure(
                basePath: videoBasePath,
                projectPath: projectPath,
                files: scanResult.videoFiles,
                projectConfig: projectConfig,
                cardConfig: cardConfig
            )
            attachToTree(rootChildren: &rootChildren, leaf: videoTree, projectPath: projectPath)
            mappings.append(contentsOf: videoMappings)
        }

        // Audio structuur
        if scanResult.hasAudio {
            let (audioTree, audioMappings) = buildAudioStructure(
                basePath: basePaths.audioPath,
                projectPath: projectPath,
                files: scanResult.audioFiles,
                projectConfig: projectConfig,
                cardConfig: cardConfig
            )
            attachToTree(rootChildren: &rootChildren, leaf: audioTree, projectPath: projectPath)
            mappings.append(contentsOf: audioMappings)
        }

        // Foto structuur
        if scanResult.hasPhoto {
            let (photoTree, photoMappings) = buildPhotoStructure(
                basePath: photoBasePath,
                projectPath: projectPath,
                files: scanResult.photoFiles,
                projectConfig: projectConfig,
                cardConfig: cardConfig
            )
            attachToTree(rootChildren: &rootChildren, leaf: photoTree, projectPath: projectPath)
            mappings.append(contentsOf: photoMappings)
        }

        let rootTree = FileSafeTargetFolder(
            relativePath: projectPath,
            displayName: projectConfig.projectName,
            children: rootChildren
        )

        return (rootTree, mappings)
    }

    // MARK: - Tree nesting helper

    /// Plaatst een leaf-tree (bv. .../02_Footage/Video) op de juiste plek in `rootChildren`,
    /// waarbij ontbrekende intermediate parents (bv. 02_Footage) automatisch worden
    /// aangemaakt of hergebruikt zodat sibling-categorieën (Video + Photo) onder dezelfde
    /// parent terechtkomen.
    private func attachToTree(
        rootChildren: inout [FileSafeTargetFolder],
        leaf: FileSafeTargetFolder,
        projectPath: String
    ) {
        // Strip projectPath prefix om het pad relatief te krijgen
        let prefix = projectPath.hasSuffix("/") ? projectPath : projectPath + "/"
        var rel = leaf.relativePath
        if rel.hasPrefix(prefix) {
            rel = String(rel.dropFirst(prefix.count))
        } else if rel == projectPath {
            rel = ""
        }

        let components = rel.split(separator: "/").map(String.init)

        // Geen relatieve componenten → leaf is de root zelf
        guard !components.isEmpty else {
            rootChildren.append(leaf)
            return
        }

        insertIntoChildren(
            children: &rootChildren,
            leaf: leaf,
            components: ArraySlice(components),
            currentAbsolutePath: projectPath
        )
    }

    private func insertIntoChildren(
        children: inout [FileSafeTargetFolder],
        leaf: FileSafeTargetFolder,
        components: ArraySlice<String>,
        currentAbsolutePath: String
    ) {
        guard let firstComp = components.first else { return }
        let newAbsolutePath = "\(currentAbsolutePath)/\(firstComp)"
        let remaining = components.dropFirst()

        if remaining.isEmpty {
            // Leaf-niveau bereikt
            if let existingIdx = children.firstIndex(where: { $0.displayName == firstComp }) {
                // Een bestaande node met dezelfde naam — merge content
                var existing = children[existingIdx]
                existing.children.append(contentsOf: leaf.children)
                existing.files.append(contentsOf: leaf.files)
                existing.fileCount += leaf.fileCount
                existing.totalSize += leaf.totalSize
                existing.isAffected = true
                children[existingIdx] = existing
            } else {
                children.append(leaf)
            }
        } else {
            // Intermediate parent
            if let existingIdx = children.firstIndex(where: { $0.displayName == firstComp }) {
                var existing = children[existingIdx]
                existing.isAffected = true
                insertIntoChildren(
                    children: &existing.children,
                    leaf: leaf,
                    components: remaining,
                    currentAbsolutePath: newAbsolutePath
                )
                children[existingIdx] = existing
            } else {
                var newParent = FileSafeTargetFolder(
                    relativePath: newAbsolutePath,
                    displayName: firstComp
                )
                insertIntoChildren(
                    children: &newParent.children,
                    leaf: leaf,
                    components: remaining,
                    currentAbsolutePath: newAbsolutePath
                )
                children.append(newParent)
            }
        }
    }

    // MARK: - Merge bestaande projectboom in preview

    /// Voegt alle bestaande mappen uit `existingProjectPath` samen met `targetTree`:
    /// - Mappen die ook in targetTree voorkomen krijgen `isExisting = true`
    /// - Mappen die niet in targetTree zitten worden toegevoegd met
    ///   `isExisting = true, isAffected = false` zodat de UI ze grijs toont
    ///
    /// Alleen mappen worden meegenomen — losse bestanden blijven buiten de preview
    /// om de performance op grote projecten (TB's aan footage) binnen de perken te houden.
    func mergeExistingProjectTree(
        targetTree: FileSafeTargetFolder,
        existingProjectPath: String
    ) -> FileSafeTargetFolder {
        let fm = FileManager.default
        let projectURL = URL(fileURLWithPath: existingProjectPath)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: existingProjectPath, isDirectory: &isDir), isDir.boolValue else {
            return targetTree
        }

        // Verzamel alle bestaande submappen relatief aan de project root
        var folderEntries: [[String]] = []
        let skipNames: Set<String> = [".DS_Store", ".Trashes", ".Spotlight-V100", ".fseventsd"]

        guard let enumerator = fm.enumerator(
            at: projectURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return targetTree
        }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if skipNames.contains(name) { continue }
            if name.first == "." { continue }

            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard isFolder else { continue }

            // Pad relatief aan project root
            let absolutePath = url.path
            guard absolutePath.hasPrefix(existingProjectPath) else { continue }
            var relative = String(absolutePath.dropFirst(existingProjectPath.count))
            if relative.hasPrefix("/") { relative.removeFirst() }
            let components = relative.split(separator: "/").map(String.init)
            if components.isEmpty { continue }

            folderEntries.append(components)
        }

        // Sorteer op diepte zodat we altijd de parent verwerken vóór de child
        folderEntries.sort { $0.count < $1.count }

        var merged = targetTree
        for components in folderEntries {
            insertOrMarkExistingFolder(in: &merged, pathComponents: components, projectPath: existingProjectPath)
        }

        return merged
    }

    /// Navigeert recursief via `pathComponents`. Matcht op `displayName`; markt
    /// bestaande matches als `isExisting`, voegt ontbrekende mappen toe als
    /// non-affected existing nodes.
    private func insertOrMarkExistingFolder(
        in tree: inout FileSafeTargetFolder,
        pathComponents: [String],
        projectPath: String
    ) {
        guard let head = pathComponents.first else { return }
        let rest = Array(pathComponents.dropFirst())

        if let idx = tree.children.firstIndex(where: { $0.displayName == head }) {
            tree.children[idx].isExisting = true
            if !rest.isEmpty {
                insertOrMarkExistingFolder(
                    in: &tree.children[idx],
                    pathComponents: rest,
                    projectPath: projectPath
                )
            }
        } else {
            let fullPath = "\(projectPath)/\(pathComponents.joined(separator: "/"))"
            var newChild = FileSafeTargetFolder(
                relativePath: fullPath,
                displayName: head,
                isExisting: true,
                isAffected: false
            )
            if !rest.isEmpty {
                // Maak tussenliggende parents van de child leaf (alleen de head is de directe child)
                insertOrMarkExistingFolder(
                    in: &newChild,
                    pathComponents: rest,
                    projectPath: projectPath
                )
            }
            tree.children.append(newChild)
        }
    }

    // MARK: - Backward compatibility overload

    func buildStructure(
        projectPath: String,
        scanResult: FileSafeScanResult,
        shootConfig: FileSafeShootConfig,
        folderPreset: FolderStructurePreset,
        customTemplate: CustomFolderTemplate?
    ) -> (tree: FileSafeTargetFolder, mappings: [FileSafeFileMapping]) {
        // Converteer legacy config naar nieuwe structuur
        let projectConfig = FileSafeProjectConfig(
            projectName: shootConfig.projectName,
            isMultiDayShoot: shootConfig.shootDays.count > 1,
            location: shootConfig.location,
            hasMultipleCameras: !shootConfig.cameraAngles.isEmpty,
            cameraSplitMode: shootConfig.cameraAngles.isEmpty ? .none : .byAngle,
            cameraLabels: shootConfig.cameraAngles,
            audioPersons: shootConfig.audioPersons,
            hasWildtrack: shootConfig.hasWildtrack,
            linkAudioToDayStructure: shootConfig.linkAudioToDayStructure,
            photoCategories: shootConfig.photoCategories,
            splitRawJpeg: shootConfig.splitRawJpeg,
            useTimestampAssignment: shootConfig.useTimestampAssignment,
            dateSource: .materialDate,
            lastUpdated: Date()
        )

        let cardConfig = FileSafeCardConfig(
            shootDays: shootConfig.shootDays,
            dateOverride: nil,
            volumePath: scanResult.volumePath,
            volumeName: scanResult.volumeName,
            videoSubfolders: [],
            photoSubfolders: [],
            videoBins: [],
            photoBins: [],
            audioBins: [],
            fileSubfolderMap: [:],
            useDateSubfolder: false,
            insertedSubfolders: [:],
            footageFolderOverride: nil,
            audioFolderOverride: nil,
            photoFolderOverride: nil,
            customPathOverride: [:],
            postDaySubfolders: [:]
        )

        return buildStructure(
            projectPath: projectPath,
            scanResult: scanResult,
            projectConfig: projectConfig,
            cardConfig: cardConfig,
            folderPreset: folderPreset,
            customTemplate: customTemplate
        )
    }

    // MARK: - Mappen aanmaken op schijf

    func createFolderStructure(projectPath: String, mappings: [FileSafeFileMapping]) throws {
        let fileManager = FileManager.default

        // Verzamel unieke doelmappen
        let uniqueDirs = Set(mappings.map { URL(fileURLWithPath: $0.destinationPath).deletingLastPathComponent().path })

        for dir in uniqueDirs {
            try fileManager.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    // MARK: - Template integratie

    struct BasePaths {
        let footagePath: String
        let audioPath: String
        let photoPath: String
        let photosInFootage: Bool  // true = foto's delen de footage-map (geen aparte foto-map in template)
    }

    /// Resolve base paths, checking existing project folder structure first
    func resolveBasePaths(preset: FolderStructurePreset, customTemplate: CustomFolderTemplate?, existingProjectPath: String? = nil) -> BasePaths {
        // Als er een bestaand project is, zoek eerst naar bestaande mappen
        if let projectPath = existingProjectPath {
            if let existing = resolveFromExistingProject(at: projectPath) {
                return existing
            }
        }
        return resolveBasePathsFromPreset(preset: preset, customTemplate: customTemplate)
    }

    /// Overload: resolve base paths vanuit een FolderStructureTemplate.
    /// De template boom wordt geresolved met de opgegeven parameter-waarden voordat de paden
    /// worden bepaald — placeholders zoals `[Project Name]` verdwijnen dus uit de mapnamen.
    func resolveBasePaths(
        template: FolderStructureTemplate,
        values: [String: String],
        existingProjectPath: String? = nil
    ) -> BasePaths {
        if let projectPath = existingProjectPath {
            if let existing = resolveFromExistingProject(at: projectPath) {
                return existing
            }
        }

        let resolvedTree = TemplatePlaceholderResolver.resolve(
            tree: template.folderTree,
            parameters: template.parameters,
            values: values
        )

        // Footage: gebruik AI rawFootagePath → keyword search → fallback
        let footagePath = template.mapping.rawFootagePath
            ?? findPath(in: resolvedTree, matching: ["raw"])
            ?? findPath(in: resolvedTree, matching: ["footage", "video", "beeldmateriaal"])
            ?? template.mapping.stockFootagePath
            ?? "Footage"
        let audioPath = findPath(in: resolvedTree, matching: ["audio", "sound", "geluid"]) ?? "Audio"

        // Foto's: gebruik AI photoPath → keyword search → geen match = in footage
        let aiPhotoPath = template.mapping.photoPath
            ?? findPath(in: resolvedTree, matching: ["photo", "stills", "foto", "pictures", "images"])

        if let photoPath = aiPhotoPath {
            return BasePaths(footagePath: footagePath, audioPath: audioPath, photoPath: photoPath, photosInFootage: false)
        } else {
            return BasePaths(footagePath: footagePath, audioPath: audioPath, photoPath: footagePath, photosInFootage: true)
        }
    }

    /// Zoek bestaande footage/audio/photo mappen in een project directory
    private func resolveFromExistingProject(at projectPath: String) -> BasePaths? {
        let projectURL = URL(fileURLWithPath: projectPath)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: projectURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let folders = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        let footageKeywords = ["footage", "raw", "materiaal", "beeldmateriaal", "video"]
        let audioKeywords = ["audio", "sound", "geluid", "production_audio"]
        let photoKeywords = ["photo", "photos", "stills", "foto", "pictures", "images"]

        func findFolder(matching keywords: [String]) -> String? {
            for folder in folders {
                let name = folder.lastPathComponent
                let normalized = name.lowercased()
                    .replacingOccurrences(of: #"^\d+_"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                for keyword in keywords {
                    if normalized == keyword || normalized.contains(keyword) || keyword.contains(normalized) {
                        return name
                    }
                }
            }
            return nil
        }

        let footagePath = findFolder(matching: footageKeywords)

        // Als keyword-scan niets vindt, probeer AI analyse (als gecachet)
        if footagePath == nil {
            if let aiResult = aiAnalysisCache[projectPath] {
                let footage = aiResult.rawFootagePath ?? "Footage"
                let audio = aiResult.audioPath ?? "Audio"
                let photo = aiResult.photoPath

                if let p = photo {
                    return BasePaths(footagePath: footage, audioPath: audio, photoPath: p, photosInFootage: false)
                } else {
                    return BasePaths(footagePath: footage, audioPath: audio, photoPath: footage, photosInFootage: true)
                }
            }
            return nil
        }

        let footage = footagePath!
        let audioPath = findFolder(matching: audioKeywords) ?? "Audio"
        let photoPath = findFolder(matching: photoKeywords)

        if let photo = photoPath {
            return BasePaths(footagePath: footage, audioPath: audioPath, photoPath: photo, photosInFootage: false)
        } else {
            return BasePaths(footagePath: footage, audioPath: audioPath, photoPath: footage, photosInFootage: true)
        }
    }

    private func resolveBasePathsFromPreset(preset: FolderStructurePreset, customTemplate: CustomFolderTemplate?) -> BasePaths {
        switch preset {
        case .custom:
            if let template = customTemplate {
                // Footage: gebruik AI rawFootagePath → keyword search → fallback
                let footagePath = template.mapping.rawFootagePath
                    ?? findFootagePath(in: template)
                    ?? template.mapping.stockFootagePath
                    ?? "Footage"
                let audioPath = findAudioPath(in: template) ?? "Audio"

                // Foto's: gebruik AI photoPath → keyword search → geen match = in footage
                let aiPhotoPath = template.mapping.photoPath ?? findPhotoPath(in: template)

                if let photoPath = aiPhotoPath {
                    // Template heeft een aparte foto-map
                    return BasePaths(footagePath: footagePath, audioPath: audioPath, photoPath: photoPath, photosInFootage: false)
                } else {
                    // Geen foto-map → foto's gaan in de footage-map
                    return BasePaths(footagePath: footagePath, audioPath: audioPath, photoPath: footagePath, photosInFootage: true)
                }
            }
            return BasePaths(footagePath: "01_Footage", audioPath: "02_Production_Audio", photoPath: "06_Photos", photosInFootage: false)

        case .standard:
            return BasePaths(footagePath: "01_Footage", audioPath: "02_Production_Audio", photoPath: "06_Photos", photosInFootage: false)

        case .flat:
            return BasePaths(footagePath: "Footage", audioPath: "Audio", photoPath: "Photos", photosInFootage: false)
        }
    }

    private func findFootagePath(in template: CustomFolderTemplate) -> String? {
        // Zoek eerst een "raw" submap (bijv. "02_Footage/01_Raw") — diepste match
        if let rawPath = findPath(in: template.folderTree, matching: ["raw"]) {
            return rawPath
        }
        // Fallback: zoek een footage-map op naam
        return findPath(in: template.folderTree, matching: ["footage", "video", "beeldmateriaal"])
    }

    private func findAudioPath(in template: CustomFolderTemplate) -> String? {
        return findPath(in: template.folderTree, matching: ["audio", "sound", "geluid"])
    }

    private func findPhotoPath(in template: CustomFolderTemplate) -> String? {
        return findPath(in: template.folderTree, matching: ["photo", "stills", "foto", "pictures", "images"])
    }

    private func findPath(in node: FolderNode, matching keywords: [String]) -> String? {
        let lowName = node.name.lowercased()
        for keyword in keywords {
            if lowName.contains(keyword) {
                return node.relativePath
            }
        }
        for child in node.children {
            if let found = findPath(in: child, matching: keywords) {
                return found
            }
        }
        return nil
    }


    // MARK: - Path override helpers (Path Editor integratie)

    /// Geeft het user-gekozen base pad terug als `customPathOverride[category]` is gezet,
    /// anders het default pad uit `basePaths`. `category` matcht `FileSafeFileCategory.rawValue`.
    private func effectiveBasePath(
        defaultBase: String,
        category: String,
        cardConfig: FileSafeCardConfig
    ) -> String {
        guard let segments = cardConfig.customPathOverride[category],
              !segments.isEmpty else { return defaultBase }
        return segments.joined(separator: "/")
    }

    /// Geeft het post-day pad-suffix terug (met leading slash) of "" als er geen
    /// postDaySubfolders gezet zijn voor deze categorie.
    private func postDayPathSuffix(
        category: String,
        cardConfig: FileSafeCardConfig
    ) -> String {
        let segs = cardConfig.postDaySubfolders[category] ?? []
        return segs.isEmpty ? "" : "/" + segs.joined(separator: "/")
    }

    // MARK: - Video structuur

    private func buildVideoStructure(
        basePath: String,
        projectPath: String,
        files: [FileSafeSourceFile],
        projectConfig: FileSafeProjectConfig,
        cardConfig: FileSafeCardConfig
    ) -> (tree: FileSafeTargetFolder, mappings: [FileSafeFileMapping]) {

        var mappings: [FileSafeFileMapping] = []
        var dayChildren: [FileSafeTargetFolder] = []

        let filesByDay = assignFilesToDays(
            files: files,
            shootDays: cardConfig.shootDays,
            useTimestamp: projectConfig.useTimestampAssignment
        )

        let videoBins = cardConfig.videoBins.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let videoSubs = cardConfig.effectiveVideoSubfolders

        // Path Editor overrides: pre-day en post-day segmenten uit cardConfig
        let effectiveBase = effectiveBasePath(defaultBase: basePath, category: "video", cardConfig: cardConfig)
        let postDay = postDayPathSuffix(category: "video", cardConfig: cardConfig)

        // Single-day zonder date subfolder → bestanden direct in effectiveBase
        let skipDayFolder = !projectConfig.isMultiDayShoot && !cardConfig.useDateSubfolder
        let isMultiDay = projectConfig.isMultiDayShoot

        for day in cardConfig.shootDays {
            let dayFiles = filesByDay[day.id] ?? []
            let dayDisplayName = day.displayName(isMultiDay: isMultiDay)
            // dayPath = effectiveBase + (day?) + postDay
            let dayPathNoPost = skipDayFolder ? effectiveBase : "\(effectiveBase)/\(dayDisplayName)"
            let dayPath = "\(dayPathNoPost)\(postDay)"

            if !videoBins.isEmpty {
                // NIEUW: bin-gebaseerde routing
                var binChildren: [FileSafeTargetFolder] = []

                for bin in videoBins {
                    let binName = bin.name.trimmingCharacters(in: .whitespaces)
                    let binFiles = dayFiles.filter { cardConfig.fileSubfolderMap[$0.id] == binName }
                    let binPath = "\(dayPath)/\(binName)"
                    let fullBinPath = "\(projectPath)/\(binPath)"

                    for file in binFiles {
                        mappings.append(FileSafeFileMapping(
                            source: file,
                            destinationPath: "\(fullBinPath)/\(file.fileName)",
                            targetFolderName: binName
                        ))
                    }

                    binChildren.append(FileSafeTargetFolder(
                        relativePath: binPath,
                        displayName: binName,
                        fileCount: binFiles.count,
                        totalSize: binFiles.reduce(0) { $0 + $1.fileSize },
                        files: binFiles
                    ))
                }

                // Unassigned bestanden → direct in dag-map
                let assignedBinNames = Set(videoBins.map { $0.name.trimmingCharacters(in: .whitespaces) })
                let unassigned = dayFiles.filter {
                    guard let assignment = cardConfig.fileSubfolderMap[$0.id] else { return true }
                    return !assignedBinNames.contains(assignment)
                }
                let fullDayPath = "\(projectPath)/\(dayPath)"
                for file in unassigned {
                    mappings.append(FileSafeFileMapping(
                        source: file,
                        destinationPath: "\(fullDayPath)/\(file.fileName)",
                        targetFolderName: dayDisplayName
                    ))
                }

                if skipDayFolder {
                    dayChildren.append(contentsOf: binChildren)
                } else {
                    dayChildren.append(FileSafeTargetFolder(
                        relativePath: dayPath,
                        displayName: dayDisplayName,
                        fileCount: unassigned.count,
                        totalSize: unassigned.reduce(0) { $0 + $1.fileSize },
                        children: binChildren
                    ))
                }

            } else if !videoSubs.isEmpty {
                // Legacy modus: geneste submappen
                var targetPath = dayPath
                for sub in videoSubs {
                    targetPath += "/\(sub)"
                }
                let fullPath = "\(projectPath)/\(targetPath)"
                let leafName = videoSubs.last!

                for file in dayFiles {
                    mappings.append(FileSafeFileMapping(
                        source: file,
                        destinationPath: "\(fullPath)/\(file.fileName)",
                        targetFolderName: leafName
                    ))
                }

                // Bouw geneste kinderen van binnen naar buiten
                var innerChild = FileSafeTargetFolder(
                    relativePath: targetPath,
                    displayName: videoSubs.last!,
                    fileCount: dayFiles.count,
                    totalSize: dayFiles.reduce(0) { $0 + $1.fileSize },
                    files: dayFiles
                )
                if videoSubs.count > 1 {
                    var currentPath = dayPath
                    var pathComponents: [(path: String, name: String)] = []
                    for sub in videoSubs.dropLast() {
                        currentPath += "/\(sub)"
                        pathComponents.append((currentPath, sub))
                    }
                    for component in pathComponents.reversed() {
                        innerChild = FileSafeTargetFolder(
                            relativePath: component.path,
                            displayName: component.name,
                            children: [innerChild]
                        )
                    }
                }

                if skipDayFolder {
                    dayChildren.append(innerChild)
                } else {
                    dayChildren.append(FileSafeTargetFolder(
                        relativePath: dayPath,
                        displayName: dayDisplayName,
                        children: [innerChild]
                    ))
                }

            } else {
                // Geen bins, geen legacy subfolders → alles direct in dag-map
                let fullPath = "\(projectPath)/\(dayPath)"
                for file in dayFiles {
                    mappings.append(FileSafeFileMapping(
                        source: file,
                        destinationPath: "\(fullPath)/\(file.fileName)",
                        targetFolderName: skipDayFolder ? URL(fileURLWithPath: effectiveBase).lastPathComponent : dayDisplayName
                    ))
                }

                if !skipDayFolder {
                    dayChildren.append(FileSafeTargetFolder(
                        relativePath: dayPath,
                        displayName: dayDisplayName,
                        fileCount: dayFiles.count,
                        totalSize: dayFiles.reduce(0) { $0 + $1.fileSize },
                        files: dayFiles
                    ))
                }
            }
        }

        let videoTree = FileSafeTargetFolder(
            relativePath: effectiveBase,
            displayName: URL(fileURLWithPath: effectiveBase).lastPathComponent,
            children: dayChildren
        )

        return (videoTree, mappings)
    }

    // MARK: - Audio structuur

    private func buildAudioStructure(
        basePath: String,
        projectPath: String,
        files: [FileSafeSourceFile],
        projectConfig: FileSafeProjectConfig,
        cardConfig: FileSafeCardConfig
    ) -> (tree: FileSafeTargetFolder, mappings: [FileSafeFileMapping]) {

        var mappings: [FileSafeFileMapping] = []
        var children: [FileSafeTargetFolder] = []

        // Path Editor overrides
        let effectiveBase = effectiveBasePath(defaultBase: basePath, category: "audio", cardConfig: cardConfig)
        let postDay = postDayPathSuffix(category: "audio", cardConfig: cardConfig)

        // Dag-gate: gelijkgetrokken met video — gebruik `useDateSubfolder` i.p.v. legacy
        // `linkAudioToDayStructure`. Single-day met date-subfolder → dagmap; anders geen.
        // Multi-day → altijd dagmap.
        let skipDayFolder = !projectConfig.isMultiDayShoot && !cardConfig.useDateSubfolder
        let useDay = !skipDayFolder
        let isMultiDay = projectConfig.isMultiDayShoot

        // NIEUW: bin-gebaseerde routing als er audioBins zijn (vergelijkbaar met video)
        let audioBins = cardConfig.audioBins.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        if !audioBins.isEmpty {
            if useDay {
                let filesByDay = assignFilesToDays(
                    files: files,
                    shootDays: cardConfig.shootDays,
                    useTimestamp: projectConfig.useTimestampAssignment
                )
                for day in cardConfig.shootDays {
                    let dayFiles = filesByDay[day.id] ?? []
                    let dayDisplayName = day.displayName(isMultiDay: isMultiDay)
                    let dayPath = "\(effectiveBase)/\(dayDisplayName)\(postDay)"
                    var binChildren: [FileSafeTargetFolder] = []

                    for bin in audioBins {
                        let binName = bin.name.trimmingCharacters(in: .whitespaces)
                        let binFiles = dayFiles.filter { cardConfig.fileSubfolderMap[$0.id] == binName }
                        let binPath = "\(dayPath)/\(binName)"
                        let fullBinPath = "\(projectPath)/\(binPath)"

                        for file in binFiles {
                            mappings.append(FileSafeFileMapping(
                                source: file,
                                destinationPath: "\(fullBinPath)/\(file.fileName)",
                                targetFolderName: binName
                            ))
                        }

                        binChildren.append(FileSafeTargetFolder(
                            relativePath: binPath,
                            displayName: binName,
                            fileCount: binFiles.count,
                            totalSize: binFiles.reduce(0) { $0 + $1.fileSize },
                            files: binFiles
                        ))
                    }

                    let assignedBinNames = Set(audioBins.map { $0.name.trimmingCharacters(in: .whitespaces) })
                    let unassigned = dayFiles.filter {
                        guard let assignment = cardConfig.fileSubfolderMap[$0.id] else { return true }
                        return !assignedBinNames.contains(assignment)
                    }
                    let fullDayPath = "\(projectPath)/\(dayPath)"
                    for file in unassigned {
                        mappings.append(FileSafeFileMapping(
                            source: file,
                            destinationPath: "\(fullDayPath)/\(file.fileName)",
                            targetFolderName: dayDisplayName
                        ))
                    }

                    children.append(FileSafeTargetFolder(
                        relativePath: dayPath,
                        displayName: dayDisplayName,
                        fileCount: unassigned.count,
                        totalSize: unassigned.reduce(0) { $0 + $1.fileSize },
                        children: binChildren
                    ))
                }
            } else {
                // Geen dag → bins direct onder effectiveBase (+ postDay)
                let basePlusPost = "\(effectiveBase)\(postDay)"
                for bin in audioBins {
                    let binName = bin.name.trimmingCharacters(in: .whitespaces)
                    let binFiles = files.filter { cardConfig.fileSubfolderMap[$0.id] == binName }
                    let binPath = "\(basePlusPost)/\(binName)"
                    let fullBinPath = "\(projectPath)/\(binPath)"

                    for file in binFiles {
                        mappings.append(FileSafeFileMapping(
                            source: file,
                            destinationPath: "\(fullBinPath)/\(file.fileName)",
                            targetFolderName: binName
                        ))
                    }

                    children.append(FileSafeTargetFolder(
                        relativePath: binPath,
                        displayName: binName,
                        fileCount: binFiles.count,
                        totalSize: binFiles.reduce(0) { $0 + $1.fileSize },
                        files: binFiles
                    ))
                }

                let assignedBinNames = Set(audioBins.map { $0.name.trimmingCharacters(in: .whitespaces) })
                let unassigned = files.filter {
                    guard let assignment = cardConfig.fileSubfolderMap[$0.id] else { return true }
                    return !assignedBinNames.contains(assignment)
                }
                let fullBasePath = "\(projectPath)/\(basePlusPost)"
                for file in unassigned {
                    mappings.append(FileSafeFileMapping(
                        source: file,
                        destinationPath: "\(fullBasePath)/\(file.fileName)",
                        targetFolderName: URL(fileURLWithPath: effectiveBase).lastPathComponent
                    ))
                }
            }

            let audioTree = FileSafeTargetFolder(
                relativePath: effectiveBase,
                displayName: URL(fileURLWithPath: effectiveBase).lastPathComponent,
                children: children
            )
            return (audioTree, mappings)
        }

        // Legacy audio path (zonder bins) — persons + optionele wildtrack
        if useDay {
            let filesByDay = assignFilesToDays(
                files: files,
                shootDays: cardConfig.shootDays,
                useTimestamp: projectConfig.useTimestampAssignment
            )

            for day in cardConfig.shootDays {
                let dayFiles = filesByDay[day.id] ?? []
                let dayDisplayName = day.displayName(isMultiDay: isMultiDay)
                let dayPath = "\(effectiveBase)/\(dayDisplayName)\(postDay)"
                var personChildren: [FileSafeTargetFolder] = []

                if projectConfig.audioPersons.isEmpty {
                    let fullPath = "\(projectPath)/\(dayPath)"

                    for file in dayFiles {
                        mappings.append(FileSafeFileMapping(
                            source: file,
                            destinationPath: "\(fullPath)/\(file.fileName)",
                            targetFolderName: dayDisplayName
                        ))
                    }
                } else {
                    let filesPerPerson = distributeFilesOverLabels(files: dayFiles, labels: projectConfig.audioPersons)
                    for person in projectConfig.audioPersons {
                        let personFiles = filesPerPerson[person] ?? []
                        let personPath = "\(dayPath)/\(person)"
                        let fullPath = "\(projectPath)/\(personPath)"

                        for file in personFiles {
                            mappings.append(FileSafeFileMapping(
                                source: file,
                                destinationPath: "\(fullPath)/\(file.fileName)",
                                targetFolderName: person
                            ))
                        }

                        personChildren.append(FileSafeTargetFolder(
                            relativePath: personPath,
                            displayName: person,
                            fileCount: personFiles.count,
                            totalSize: personFiles.reduce(0) { $0 + $1.fileSize },
                            files: personFiles
                        ))
                    }

                    if projectConfig.hasWildtrack {
                        let wildtrackPath = "\(dayPath)/Wildtrack"
                        personChildren.append(FileSafeTargetFolder(
                            relativePath: wildtrackPath,
                            displayName: "Wildtrack",
                            fileCount: 0,
                            totalSize: 0
                        ))
                    }
                }

                children.append(FileSafeTargetFolder(
                    relativePath: dayPath,
                    displayName: dayDisplayName,
                    children: personChildren
                ))
            }
        } else {
            let basePlusPost = "\(effectiveBase)\(postDay)"
            if projectConfig.audioPersons.isEmpty {
                let fullPath = "\(projectPath)/\(basePlusPost)"
                for file in files {
                    mappings.append(FileSafeFileMapping(
                        source: file,
                        destinationPath: "\(fullPath)/\(file.fileName)",
                        targetFolderName: URL(fileURLWithPath: effectiveBase).lastPathComponent
                    ))
                }
            } else {
                let filesPerPerson = distributeFilesOverLabels(files: files, labels: projectConfig.audioPersons)
                for person in projectConfig.audioPersons {
                    let personFiles = filesPerPerson[person] ?? []
                    let personPath = "\(basePlusPost)/\(person)"
                    let fullPath = "\(projectPath)/\(personPath)"

                    for file in personFiles {
                        mappings.append(FileSafeFileMapping(
                            source: file,
                            destinationPath: "\(fullPath)/\(file.fileName)",
                            targetFolderName: person
                        ))
                    }

                    children.append(FileSafeTargetFolder(
                        relativePath: personPath,
                        displayName: person,
                        fileCount: personFiles.count,
                        totalSize: personFiles.reduce(0) { $0 + $1.fileSize },
                        files: personFiles
                    ))
                }

                if projectConfig.hasWildtrack {
                    children.append(FileSafeTargetFolder(
                        relativePath: "\(basePlusPost)/Wildtrack",
                        displayName: "Wildtrack",
                        fileCount: 0,
                        totalSize: 0
                    ))
                }
            }
        }

        let audioTree = FileSafeTargetFolder(
            relativePath: effectiveBase,
            displayName: URL(fileURLWithPath: effectiveBase).lastPathComponent,
            fileCount: projectConfig.audioPersons.isEmpty ? files.count : 0,
            totalSize: projectConfig.audioPersons.isEmpty ? files.reduce(0) { $0 + $1.fileSize } : 0,
            children: children,
            files: projectConfig.audioPersons.isEmpty ? files : []
        )

        return (audioTree, mappings)
    }

    // MARK: - Foto structuur

    private func buildPhotoStructure(
        basePath: String,
        projectPath: String,
        files: [FileSafeSourceFile],
        projectConfig: FileSafeProjectConfig,
        cardConfig: FileSafeCardConfig
    ) -> (tree: FileSafeTargetFolder, mappings: [FileSafeFileMapping]) {

        // Path Editor overrides voor foto
        let effectiveBase = effectiveBasePath(defaultBase: basePath, category: "photo", cardConfig: cardConfig)
        let postDay = postDayPathSuffix(category: "photo", cardConfig: cardConfig)

        // Multi-day: wrap foto's in dag-submappen (ook als er maar 1 dag in deze import zit,
        // want toekomstige imports voor hetzelfde project voegen meer dagen toe)
        if projectConfig.isMultiDayShoot {
            var mappings: [FileSafeFileMapping] = []
            var dayChildren: [FileSafeTargetFolder] = []

            let filesByDay = assignFilesToDays(
                files: files,
                shootDays: cardConfig.shootDays,
                useTimestamp: projectConfig.useTimestampAssignment
            )

            for day in cardConfig.shootDays {
                let dayFiles = filesByDay[day.id] ?? []
                // day komt NA effectiveBase, postDay komt NA day (tussen day en bin)
                let dayBasePath = "\(effectiveBase)/\(day.displayName(isMultiDay: true))\(postDay)"
                let (dayTree, dayMappings) = buildSingleDayPhotoStructure(
                    basePath: dayBasePath,
                    projectPath: projectPath,
                    files: dayFiles,
                    projectConfig: projectConfig,
                    cardConfig: cardConfig
                )
                dayChildren.append(dayTree)
                mappings.append(contentsOf: dayMappings)
            }

            let photoTree = FileSafeTargetFolder(
                relativePath: effectiveBase,
                displayName: URL(fileURLWithPath: effectiveBase).lastPathComponent,
                children: dayChildren
            )
            return (photoTree, mappings)
        }

        // Single-day: geen dag-map; postDay zit direct na effectiveBase
        return buildSingleDayPhotoStructure(
            basePath: "\(effectiveBase)\(postDay)",
            projectPath: projectPath,
            files: files,
            projectConfig: projectConfig,
            cardConfig: cardConfig
        )
    }

    /// Bouw foto-structuur voor één dag (of flat als single-day)
    private func buildSingleDayPhotoStructure(
        basePath: String,
        projectPath: String,
        files: [FileSafeSourceFile],
        projectConfig: FileSafeProjectConfig,
        cardConfig: FileSafeCardConfig
    ) -> (tree: FileSafeTargetFolder, mappings: [FileSafeFileMapping]) {

        var mappings: [FileSafeFileMapping] = []
        var children: [FileSafeTargetFolder] = []

        let rawExtensions: Set<String> = ["cr3", "cr2", "arw", "nef", "raf", "dng"]
        let photoBins = cardConfig.photoBins.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let photoSubs = cardConfig.effectivePhotoSubfolders
        let hasSubfolders = !photoSubs.isEmpty
        let hasBins = !photoBins.isEmpty

        if hasBins {
            // NIEUW: bin-gebaseerde routing met optionele RAW/JPEG split per bin
            let assignedBinNames = Set(photoBins.map { $0.name.trimmingCharacters(in: .whitespaces) })

            for bin in photoBins {
                let binName = bin.name.trimmingCharacters(in: .whitespaces)
                let binFiles = files.filter { cardConfig.fileSubfolderMap[$0.id] == binName }
                let binPath = "\(basePath)/\(binName)"

                if projectConfig.splitRawJpeg {
                    let rawFiles = binFiles.filter { rawExtensions.contains($0.fileExtension.lowercased()) }
                    let jpegFiles = binFiles.filter { !rawExtensions.contains($0.fileExtension.lowercased()) }

                    for file in rawFiles {
                        mappings.append(FileSafeFileMapping(
                            source: file,
                            destinationPath: "\(projectPath)/\(binPath)/RAW/\(file.fileName)",
                            targetFolderName: "RAW"
                        ))
                    }
                    for file in jpegFiles {
                        mappings.append(FileSafeFileMapping(
                            source: file,
                            destinationPath: "\(projectPath)/\(binPath)/JPEG/\(file.fileName)",
                            targetFolderName: "JPEG"
                        ))
                    }

                    children.append(FileSafeTargetFolder(
                        relativePath: binPath,
                        displayName: binName,
                        children: [
                            FileSafeTargetFolder(
                                relativePath: "\(binPath)/RAW", displayName: "RAW",
                                fileCount: rawFiles.count, totalSize: rawFiles.reduce(0) { $0 + $1.fileSize },
                                files: rawFiles
                            ),
                            FileSafeTargetFolder(
                                relativePath: "\(binPath)/JPEG", displayName: "JPEG",
                                fileCount: jpegFiles.count, totalSize: jpegFiles.reduce(0) { $0 + $1.fileSize },
                                files: jpegFiles
                            )
                        ]
                    ))
                } else {
                    let fullBinPath = "\(projectPath)/\(binPath)"
                    for file in binFiles {
                        mappings.append(FileSafeFileMapping(
                            source: file,
                            destinationPath: "\(fullBinPath)/\(file.fileName)",
                            targetFolderName: binName
                        ))
                    }

                    children.append(FileSafeTargetFolder(
                        relativePath: binPath,
                        displayName: binName,
                        fileCount: binFiles.count,
                        totalSize: binFiles.reduce(0) { $0 + $1.fileSize },
                        files: binFiles
                    ))
                }
            }

            // Unassigned bestanden → direct in basePath (met optionele RAW/JPEG split)
            let unassigned = files.filter {
                guard let assignment = cardConfig.fileSubfolderMap[$0.id] else { return true }
                return !assignedBinNames.contains(assignment)
            }

            if !unassigned.isEmpty {
                if projectConfig.splitRawJpeg {
                    let rawFiles = unassigned.filter { rawExtensions.contains($0.fileExtension.lowercased()) }
                    let jpegFiles = unassigned.filter { !rawExtensions.contains($0.fileExtension.lowercased()) }

                    for file in rawFiles {
                        mappings.append(FileSafeFileMapping(
                            source: file,
                            destinationPath: "\(projectPath)/\(basePath)/RAW/\(file.fileName)",
                            targetFolderName: "RAW"
                        ))
                    }
                    for file in jpegFiles {
                        mappings.append(FileSafeFileMapping(
                            source: file,
                            destinationPath: "\(projectPath)/\(basePath)/JPEG/\(file.fileName)",
                            targetFolderName: "JPEG"
                        ))
                    }

                    // RAW/JPEG nodes direct onder basePath (naast bins)
                    if !rawFiles.isEmpty {
                        children.append(FileSafeTargetFolder(
                            relativePath: "\(basePath)/RAW", displayName: "RAW",
                            fileCount: rawFiles.count, totalSize: rawFiles.reduce(0) { $0 + $1.fileSize },
                            files: rawFiles
                        ))
                    }
                    if !jpegFiles.isEmpty {
                        children.append(FileSafeTargetFolder(
                            relativePath: "\(basePath)/JPEG", displayName: "JPEG",
                            fileCount: jpegFiles.count, totalSize: jpegFiles.reduce(0) { $0 + $1.fileSize },
                            files: jpegFiles
                        ))
                    }
                } else {
                    let fullPath = "\(projectPath)/\(basePath)"
                    for file in unassigned {
                        mappings.append(FileSafeFileMapping(
                            source: file,
                            destinationPath: "\(fullPath)/\(file.fileName)",
                            targetFolderName: URL(fileURLWithPath: basePath).lastPathComponent
                        ))
                    }
                }
            }

        } else {
            // Legacy modus: geneste submappen
            var effectiveBase = basePath
            for sub in photoSubs {
                effectiveBase += "/\(sub)"
            }

            if projectConfig.splitRawJpeg {
                let rawFiles = files.filter { rawExtensions.contains($0.fileExtension.lowercased()) }
                let jpegFiles = files.filter { !rawExtensions.contains($0.fileExtension.lowercased()) }

                let rawPath = "\(effectiveBase)/RAW"
                let jpegPath = "\(effectiveBase)/JPEG"

                for file in rawFiles {
                    mappings.append(FileSafeFileMapping(
                        source: file,
                        destinationPath: "\(projectPath)/\(rawPath)/\(file.fileName)",
                        targetFolderName: "RAW"
                    ))
                }
                for file in jpegFiles {
                    mappings.append(FileSafeFileMapping(
                        source: file,
                        destinationPath: "\(projectPath)/\(jpegPath)/\(file.fileName)",
                        targetFolderName: "JPEG"
                    ))
                }

                let splitChildren = [
                    FileSafeTargetFolder(
                        relativePath: rawPath, displayName: "RAW",
                        fileCount: rawFiles.count, totalSize: rawFiles.reduce(0) { $0 + $1.fileSize },
                        files: rawFiles
                    ),
                    FileSafeTargetFolder(
                        relativePath: jpegPath, displayName: "JPEG",
                        fileCount: jpegFiles.count, totalSize: jpegFiles.reduce(0) { $0 + $1.fileSize },
                        files: jpegFiles
                    )
                ]

                if hasSubfolders {
                    var innerNode = FileSafeTargetFolder(
                        relativePath: effectiveBase,
                        displayName: photoSubs.last!,
                        children: splitChildren
                    )
                    if photoSubs.count > 1 {
                        var currentPath = basePath
                        var pathComponents: [(path: String, name: String)] = []
                        for sub in photoSubs.dropLast() {
                            currentPath += "/\(sub)"
                            pathComponents.append((currentPath, sub))
                        }
                        for component in pathComponents.reversed() {
                            innerNode = FileSafeTargetFolder(
                                relativePath: component.path,
                                displayName: component.name,
                                children: [innerNode]
                            )
                        }
                    }
                    children.append(innerNode)
                } else {
                    children.append(contentsOf: splitChildren)
                }
            } else {
                let fullPath = "\(projectPath)/\(effectiveBase)"
                let leafName = photoSubs.last ?? URL(fileURLWithPath: basePath).lastPathComponent

                for file in files {
                    mappings.append(FileSafeFileMapping(
                        source: file,
                        destinationPath: "\(fullPath)/\(file.fileName)",
                        targetFolderName: leafName
                    ))
                }

                if hasSubfolders {
                    var innerNode = FileSafeTargetFolder(
                        relativePath: effectiveBase,
                        displayName: photoSubs.last!,
                        fileCount: files.count,
                        totalSize: files.reduce(0) { $0 + $1.fileSize },
                        files: files
                    )
                    if photoSubs.count > 1 {
                        var currentPath = basePath
                        var pathComponents: [(path: String, name: String)] = []
                        for sub in photoSubs.dropLast() {
                            currentPath += "/\(sub)"
                            pathComponents.append((currentPath, sub))
                        }
                        for component in pathComponents.reversed() {
                            innerNode = FileSafeTargetFolder(
                                relativePath: component.path,
                                displayName: component.name,
                                children: [innerNode]
                            )
                        }
                    }
                    children.append(innerNode)
                }
            }
        }

        let noBins = !hasBins
        let isLeaf = noBins && !hasSubfolders && !projectConfig.splitRawJpeg
        let photoTree = FileSafeTargetFolder(
            relativePath: basePath,
            displayName: URL(fileURLWithPath: basePath).lastPathComponent,
            fileCount: isLeaf ? files.count : 0,
            totalSize: isLeaf ? files.reduce(0) { $0 + $1.fileSize } : 0,
            children: children,
            files: isLeaf ? files : []
        )

        return (photoTree, mappings)
    }

    // MARK: - Helpers

    /// Wijs bestanden toe aan dagen op basis van werkelijke kalenderdatum
    func assignFilesToDays(
        files: [FileSafeSourceFile],
        shootDays: [FileSafeShootDay],
        useTimestamp: Bool
    ) -> [UUID: [FileSafeSourceFile]] {
        guard !shootDays.isEmpty else { return [:] }

        // Als er maar 1 dag is, alles in die dag
        if shootDays.count == 1 {
            return [shootDays[0].id: files]
        }

        // Groepeer bestanden per werkelijke kalenderdatum
        let calendar = Calendar.current
        var filesByCalendarDay: [DateComponents: [FileSafeSourceFile]] = [:]
        var filesWithoutDate: [FileSafeSourceFile] = []

        for file in files {
            if let date = file.creationDate ?? file.modificationDate {
                let key = calendar.dateComponents([.year, .month, .day], from: date)
                filesByCalendarDay[key, default: []].append(file)
            } else {
                filesWithoutDate.append(file)
            }
        }

        // Match kalenderdatums met geconfigureerde shootdagen
        var result: [UUID: [FileSafeSourceFile]] = [:]

        if useTimestamp {
            for day in shootDays {
                guard let dayDate = day.date else { continue }
                let dayComponents = calendar.dateComponents([.year, .month, .day], from: dayDate)
                if let matchedFiles = filesByCalendarDay[dayComponents] {
                    result[day.id, default: []].append(contentsOf: matchedFiles)
                    filesByCalendarDay.removeValue(forKey: dayComponents)
                }
            }
        }

        // Ongematchte bestanden en bestanden zonder datum → eerste dag
        let remainingFiles = filesByCalendarDay.values.flatMap { $0 } + filesWithoutDate
        if !remainingFiles.isEmpty {
            result[shootDays[0].id, default: []].append(contentsOf: remainingFiles)
        }

        return result
    }

    /// Verdeel bestanden over labels (camera's, personen, categorieën).
    private func distributeFilesOverLabels(
        files: [FileSafeSourceFile],
        labels: [String]
    ) -> [String: [FileSafeSourceFile]] {
        guard !labels.isEmpty else { return [:] }

        if labels.count == 1 {
            return [labels[0]: files]
        }

        var result: [String: [FileSafeSourceFile]] = [:]
        let filesPerLabel = max(1, files.count / labels.count)

        for (index, file) in files.enumerated() {
            let labelIndex = min(index / filesPerLabel, labels.count - 1)
            result[labels[labelIndex], default: []].append(file)
        }

        return result
    }

    // MARK: - Duplicate Detection

    /// Scant de footage-map van het project en markeert mappings waarvan het bestand
    /// al in het project aanwezig is (op basis van bestandsnaam + bestandsgrootte).
    func detectDuplicates(
        in mappings: inout [FileSafeFileMapping],
        projectPath: String,
        footagePath: String?
    ) {
        // Bepaal zoekpad: footage-map binnen project, of hele project
        let searchRoot: String
        if let fp = footagePath, !fp.isEmpty {
            searchRoot = (projectPath as NSString).appendingPathComponent(fp)
        } else {
            searchRoot = projectPath
        }

        let searchURL = URL(fileURLWithPath: searchRoot)

        // Controleer of de map bestaat
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: searchRoot, isDirectory: &isDir),
              isDir.boolValue else {
            // Project/footage map bestaat nog niet → geen duplicaten
            return
        }

        // Bouw lookup dictionary: [bestandsnaam (lowercase): Set<bestandsgrootte>]
        var existingFiles: [String: Set<Int64>] = [:]

        if let enumerator = FileManager.default.enumerator(
            at: searchURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                      resourceValues.isRegularFile == true,
                      let fileSize = resourceValues.fileSize else {
                    continue
                }

                let fileName = fileURL.lastPathComponent.lowercased()
                existingFiles[fileName, default: []].insert(Int64(fileSize))
            }
        }

        // Markeer mappings waarvan bestand al bestaat
        for i in mappings.indices {
            let fileName = mappings[i].source.fileName.lowercased()
            let fileSize = mappings[i].source.fileSize
            if let sizes = existingFiles[fileName], sizes.contains(fileSize) {
                mappings[i].isDuplicate = true
            }
        }
    }
}
