import Foundation

class FileSafeStructureBuilder {
    static let shared = FileSafeStructureBuilder()

    // MARK: - Bouw structuur op basis van project + card config

    func buildStructure(
        projectPath: String,
        scanResult: FileSafeScanResult,
        projectConfig: FileSafeProjectConfig,
        cardConfig: FileSafeCardConfig,
        folderPreset: FolderStructurePreset,
        customTemplate: CustomFolderTemplate?
    ) -> (tree: FileSafeTargetFolder, mappings: [FileSafeFileMapping]) {

        // Bepaal basispaden voor video/audio/foto op basis van template
        let basePaths = resolveBasePaths(preset: folderPreset, customTemplate: customTemplate, existingProjectPath: projectPath)

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
            rootChildren.append(videoTree)
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
            rootChildren.append(audioTree)
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
            rootChildren.append(photoTree)
            mappings.append(contentsOf: photoMappings)
        }

        let rootTree = FileSafeTargetFolder(
            relativePath: projectPath,
            displayName: projectConfig.projectName,
            children: rootChildren
        )

        return (rootTree, mappings)
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
            fileSubfolderMap: [:],
            useDateSubfolder: false
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
        guard let footage = footagePath else { return nil }

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

        // Single-day zonder date subfolder → bestanden direct in basePath
        let skipDayFolder = !projectConfig.isMultiDayShoot && !cardConfig.useDateSubfolder
        let isMultiDay = projectConfig.isMultiDayShoot

        for day in cardConfig.shootDays {
            let dayFiles = filesByDay[day.id] ?? []
            let dayDisplayName = day.displayName(isMultiDay: isMultiDay)
            let dayPath = skipDayFolder ? basePath : "\(basePath)/\(dayDisplayName)"

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
                        totalSize: binFiles.reduce(0) { $0 + $1.fileSize }
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
                    totalSize: dayFiles.reduce(0) { $0 + $1.fileSize }
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
                        targetFolderName: skipDayFolder ? URL(fileURLWithPath: basePath).lastPathComponent : dayDisplayName
                    ))
                }

                if !skipDayFolder {
                    dayChildren.append(FileSafeTargetFolder(
                        relativePath: dayPath,
                        displayName: dayDisplayName,
                        fileCount: dayFiles.count,
                        totalSize: dayFiles.reduce(0) { $0 + $1.fileSize }
                    ))
                }
            }
        }

        let videoTree = FileSafeTargetFolder(
            relativePath: basePath,
            displayName: URL(fileURLWithPath: basePath).lastPathComponent,
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

        if projectConfig.linkAudioToDayStructure && cardConfig.shootDays.count > 1 {
            let filesByDay = assignFilesToDays(
                files: files,
                shootDays: cardConfig.shootDays,
                useTimestamp: projectConfig.useTimestampAssignment
            )

            let isMultiDay = projectConfig.isMultiDayShoot
            for day in cardConfig.shootDays {
                let dayFiles = filesByDay[day.id] ?? []
                let dayDisplayName = day.displayName(isMultiDay: isMultiDay)
                var personChildren: [FileSafeTargetFolder] = []

                if projectConfig.audioPersons.isEmpty {
                    let dayPath = "\(basePath)/\(dayDisplayName)"
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
                        let personPath = "\(basePath)/\(dayDisplayName)/\(person)"
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
                            totalSize: personFiles.reduce(0) { $0 + $1.fileSize }
                        ))
                    }

                    if projectConfig.hasWildtrack {
                        let wildtrackPath = "\(basePath)/\(dayDisplayName)/Wildtrack"
                        personChildren.append(FileSafeTargetFolder(
                            relativePath: wildtrackPath,
                            displayName: "Wildtrack",
                            fileCount: 0,
                            totalSize: 0
                        ))
                    }
                }

                children.append(FileSafeTargetFolder(
                    relativePath: "\(basePath)/\(dayDisplayName)",
                    displayName: dayDisplayName,
                    children: personChildren
                ))
            }
        } else {
            if projectConfig.audioPersons.isEmpty {
                let fullPath = "\(projectPath)/\(basePath)"
                for file in files {
                    mappings.append(FileSafeFileMapping(
                        source: file,
                        destinationPath: "\(fullPath)/\(file.fileName)",
                        targetFolderName: URL(fileURLWithPath: basePath).lastPathComponent
                    ))
                }
            } else {
                let filesPerPerson = distributeFilesOverLabels(files: files, labels: projectConfig.audioPersons)
                for person in projectConfig.audioPersons {
                    let personFiles = filesPerPerson[person] ?? []
                    let personPath = "\(basePath)/\(person)"
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
                        totalSize: personFiles.reduce(0) { $0 + $1.fileSize }
                    ))
                }

                if projectConfig.hasWildtrack {
                    children.append(FileSafeTargetFolder(
                        relativePath: "\(basePath)/Wildtrack",
                        displayName: "Wildtrack",
                        fileCount: 0,
                        totalSize: 0
                    ))
                }
            }
        }

        let audioTree = FileSafeTargetFolder(
            relativePath: basePath,
            displayName: URL(fileURLWithPath: basePath).lastPathComponent,
            fileCount: projectConfig.audioPersons.isEmpty ? files.count : 0,
            totalSize: projectConfig.audioPersons.isEmpty ? files.reduce(0) { $0 + $1.fileSize } : 0,
            children: children
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
                let dayBasePath = "\(basePath)/\(day.displayName(isMultiDay: true))"
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
                relativePath: basePath,
                displayName: URL(fileURLWithPath: basePath).lastPathComponent,
                children: dayChildren
            )
            return (photoTree, mappings)
        }

        // Single-day: bestaande logica
        return buildSingleDayPhotoStructure(
            basePath: basePath,
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
                                fileCount: rawFiles.count, totalSize: rawFiles.reduce(0) { $0 + $1.fileSize }
                            ),
                            FileSafeTargetFolder(
                                relativePath: "\(binPath)/JPEG", displayName: "JPEG",
                                fileCount: jpegFiles.count, totalSize: jpegFiles.reduce(0) { $0 + $1.fileSize }
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
                        totalSize: binFiles.reduce(0) { $0 + $1.fileSize }
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
                            fileCount: rawFiles.count, totalSize: rawFiles.reduce(0) { $0 + $1.fileSize }
                        ))
                    }
                    if !jpegFiles.isEmpty {
                        children.append(FileSafeTargetFolder(
                            relativePath: "\(basePath)/JPEG", displayName: "JPEG",
                            fileCount: jpegFiles.count, totalSize: jpegFiles.reduce(0) { $0 + $1.fileSize }
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
                        fileCount: rawFiles.count, totalSize: rawFiles.reduce(0) { $0 + $1.fileSize }
                    ),
                    FileSafeTargetFolder(
                        relativePath: jpegPath, displayName: "JPEG",
                        fileCount: jpegFiles.count, totalSize: jpegFiles.reduce(0) { $0 + $1.fileSize }
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
                        totalSize: files.reduce(0) { $0 + $1.fileSize }
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
        let photoTree = FileSafeTargetFolder(
            relativePath: basePath,
            displayName: URL(fileURLWithPath: basePath).lastPathComponent,
            fileCount: noBins && !hasSubfolders && !projectConfig.splitRawJpeg ? files.count : 0,
            totalSize: noBins && !hasSubfolders && !projectConfig.splitRawJpeg ? files.reduce(0) { $0 + $1.fileSize } : 0,
            children: children
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
