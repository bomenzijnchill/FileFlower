import Foundation

class FileSafeStructureBuilder {
    static let shared = FileSafeStructureBuilder()

    // MARK: - Bouw structuur op basis van shoot config

    func buildStructure(
        projectPath: String,
        scanResult: FileSafeScanResult,
        shootConfig: FileSafeShootConfig,
        folderPreset: FolderStructurePreset,
        customTemplate: CustomFolderTemplate?
    ) -> (tree: FileSafeTargetFolder, mappings: [FileSafeFileMapping]) {

        // Bepaal basispaden voor video/audio/foto op basis van template
        let basePaths = resolveBasePaths(preset: folderPreset, customTemplate: customTemplate)

        var mappings: [FileSafeFileMapping] = []
        var rootChildren: [FileSafeTargetFolder] = []

        // Video structuur
        if scanResult.hasVideo {
            let (videoTree, videoMappings) = buildVideoStructure(
                basePath: basePaths.footagePath,
                projectPath: projectPath,
                files: scanResult.videoFiles,
                config: shootConfig
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
                config: shootConfig
            )
            rootChildren.append(audioTree)
            mappings.append(contentsOf: audioMappings)
        }

        // Foto structuur
        if scanResult.hasPhoto {
            let (photoTree, photoMappings) = buildPhotoStructure(
                basePath: basePaths.photoPath,
                projectPath: projectPath,
                files: scanResult.photoFiles,
                config: shootConfig
            )
            rootChildren.append(photoTree)
            mappings.append(contentsOf: photoMappings)
        }

        let rootTree = FileSafeTargetFolder(
            relativePath: projectPath,
            displayName: shootConfig.projectName,
            children: rootChildren
        )

        return (rootTree, mappings)
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
    }

    private func resolveBasePaths(preset: FolderStructurePreset, customTemplate: CustomFolderTemplate?) -> BasePaths {
        switch preset {
        case .custom:
            if let template = customTemplate {
                // Gebruik mapping om paden te vinden
                let footagePath = template.mapping.stockFootagePath ?? "Footage"
                let audioPath = findAudioPath(in: template) ?? "Audio"
                let photoPath = findPhotoPath(in: template) ?? "Photos"
                return BasePaths(footagePath: footagePath, audioPath: audioPath, photoPath: photoPath)
            }
            return BasePaths(footagePath: "01_Footage", audioPath: "02_Production_Audio", photoPath: "06_Photos")

        case .standard:
            // Standard template heeft geen footage map, maak sensible defaults
            return BasePaths(footagePath: "01_Footage", audioPath: "02_Production_Audio", photoPath: "06_Photos")

        case .flat:
            return BasePaths(footagePath: "Footage", audioPath: "Audio", photoPath: "Photos")
        }
    }

    private func findAudioPath(in template: CustomFolderTemplate) -> String? {
        // Zoek naar een map die "audio" bevat in de template boom
        return findPath(in: template.folderTree, matching: ["audio", "sound", "geluid"])
    }

    private func findPhotoPath(in template: CustomFolderTemplate) -> String? {
        // Zoek naar een map die "photo" of "stills" bevat
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
        config: FileSafeShootConfig
    ) -> (tree: FileSafeTargetFolder, mappings: [FileSafeFileMapping]) {

        var mappings: [FileSafeFileMapping] = []
        var dayChildren: [FileSafeTargetFolder] = []

        let filesByDay = assignFilesToDays(files: files, shootDays: config.shootDays, useTimestamp: config.useTimestampAssignment)

        for day in config.shootDays {
            let dayFiles = filesByDay[day.id] ?? []
            var cameraChildren: [FileSafeTargetFolder] = []

            if config.cameraAngles.isEmpty {
                // Geen camera-hoeken: alle bestanden direct in dag-map
                let dayFolderPath = "\(basePath)/\(day.displayName)"
                let fullPath = "\(projectPath)/\(dayFolderPath)"

                for file in dayFiles {
                    mappings.append(FileSafeFileMapping(
                        source: file,
                        destinationPath: "\(fullPath)/\(file.fileName)",
                        targetFolderName: day.displayName
                    ))
                }

                cameraChildren = []
                dayChildren.append(FileSafeTargetFolder(
                    relativePath: dayFolderPath,
                    displayName: day.displayName,
                    fileCount: dayFiles.count,
                    totalSize: dayFiles.reduce(0) { $0 + $1.fileSize },
                    children: cameraChildren
                ))
            } else {
                // Verdeel bestanden over camera-hoeken
                let filesPerAngle = distributeFilesOverAngles(files: dayFiles, angles: config.cameraAngles)

                for angle in config.cameraAngles {
                    let angleFiles = filesPerAngle[angle] ?? []
                    let angleFolderPath = "\(basePath)/\(day.displayName)/\(angle)"
                    let fullPath = "\(projectPath)/\(angleFolderPath)"

                    for file in angleFiles {
                        mappings.append(FileSafeFileMapping(
                            source: file,
                            destinationPath: "\(fullPath)/\(file.fileName)",
                            targetFolderName: angle
                        ))
                    }

                    cameraChildren.append(FileSafeTargetFolder(
                        relativePath: angleFolderPath,
                        displayName: angle,
                        fileCount: angleFiles.count,
                        totalSize: angleFiles.reduce(0) { $0 + $1.fileSize }
                    ))
                }

                dayChildren.append(FileSafeTargetFolder(
                    relativePath: "\(basePath)/\(day.displayName)",
                    displayName: day.displayName,
                    children: cameraChildren
                ))
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
        config: FileSafeShootConfig
    ) -> (tree: FileSafeTargetFolder, mappings: [FileSafeFileMapping]) {

        var mappings: [FileSafeFileMapping] = []
        var children: [FileSafeTargetFolder] = []

        if config.linkAudioToDayStructure && config.shootDays.count > 1 {
            // Audio per dag
            let filesByDay = assignFilesToDays(files: files, shootDays: config.shootDays, useTimestamp: config.useTimestampAssignment)

            for day in config.shootDays {
                let dayFiles = filesByDay[day.id] ?? []
                var personChildren: [FileSafeTargetFolder] = []

                if config.audioPersons.isEmpty {
                    let dayPath = "\(basePath)/\(day.displayName)"
                    let fullPath = "\(projectPath)/\(dayPath)"

                    for file in dayFiles {
                        mappings.append(FileSafeFileMapping(
                            source: file,
                            destinationPath: "\(fullPath)/\(file.fileName)",
                            targetFolderName: day.displayName
                        ))
                    }
                } else {
                    let filesPerPerson = distributeFilesOverAngles(files: dayFiles, angles: config.audioPersons)
                    for person in config.audioPersons {
                        let personFiles = filesPerPerson[person] ?? []
                        let personPath = "\(basePath)/\(day.displayName)/\(person)"
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

                    // Wildtrack map
                    if config.hasWildtrack {
                        let wildtrackPath = "\(basePath)/\(day.displayName)/Wildtrack"
                        personChildren.append(FileSafeTargetFolder(
                            relativePath: wildtrackPath,
                            displayName: "Wildtrack",
                            fileCount: 0,
                            totalSize: 0
                        ))
                    }
                }

                children.append(FileSafeTargetFolder(
                    relativePath: "\(basePath)/\(day.displayName)",
                    displayName: day.displayName,
                    children: personChildren
                ))
            }
        } else {
            // Audio zonder dag-structuur
            if config.audioPersons.isEmpty {
                let fullPath = "\(projectPath)/\(basePath)"
                for file in files {
                    mappings.append(FileSafeFileMapping(
                        source: file,
                        destinationPath: "\(fullPath)/\(file.fileName)",
                        targetFolderName: URL(fileURLWithPath: basePath).lastPathComponent
                    ))
                }
            } else {
                let filesPerPerson = distributeFilesOverAngles(files: files, angles: config.audioPersons)
                for person in config.audioPersons {
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

                if config.hasWildtrack {
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
            fileCount: config.audioPersons.isEmpty ? files.count : 0,
            totalSize: config.audioPersons.isEmpty ? files.reduce(0) { $0 + $1.fileSize } : 0,
            children: children
        )

        return (audioTree, mappings)
    }

    // MARK: - Foto structuur

    private func buildPhotoStructure(
        basePath: String,
        projectPath: String,
        files: [FileSafeSourceFile],
        config: FileSafeShootConfig
    ) -> (tree: FileSafeTargetFolder, mappings: [FileSafeFileMapping]) {

        var mappings: [FileSafeFileMapping] = []
        var children: [FileSafeTargetFolder] = []

        let rawExtensions: Set<String> = ["cr3", "cr2", "arw", "nef", "raf", "dng"]

        if config.photoCategories.isEmpty {
            // Geen categorieën
            if config.splitRawJpeg {
                let rawFiles = files.filter { rawExtensions.contains($0.fileExtension.lowercased()) }
                let jpegFiles = files.filter { !rawExtensions.contains($0.fileExtension.lowercased()) }

                let rawPath = "\(basePath)/RAW"
                let jpegPath = "\(basePath)/JPEG"

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

                children.append(FileSafeTargetFolder(
                    relativePath: rawPath, displayName: "RAW",
                    fileCount: rawFiles.count, totalSize: rawFiles.reduce(0) { $0 + $1.fileSize }
                ))
                children.append(FileSafeTargetFolder(
                    relativePath: jpegPath, displayName: "JPEG",
                    fileCount: jpegFiles.count, totalSize: jpegFiles.reduce(0) { $0 + $1.fileSize }
                ))
            } else {
                let fullPath = "\(projectPath)/\(basePath)"
                for file in files {
                    mappings.append(FileSafeFileMapping(
                        source: file,
                        destinationPath: "\(fullPath)/\(file.fileName)",
                        targetFolderName: URL(fileURLWithPath: basePath).lastPathComponent
                    ))
                }
            }
        } else {
            // Met categorieën
            let filesPerCategory = distributeFilesOverAngles(files: files, angles: config.photoCategories)

            for category in config.photoCategories {
                let catFiles = filesPerCategory[category] ?? []

                if config.splitRawJpeg {
                    let rawFiles = catFiles.filter { rawExtensions.contains($0.fileExtension.lowercased()) }
                    let jpegFiles = catFiles.filter { !rawExtensions.contains($0.fileExtension.lowercased()) }

                    let rawPath = "\(basePath)/\(category)/RAW"
                    let jpegPath = "\(basePath)/\(category)/JPEG"

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

                    var catChildren: [FileSafeTargetFolder] = []
                    catChildren.append(FileSafeTargetFolder(
                        relativePath: rawPath, displayName: "RAW",
                        fileCount: rawFiles.count, totalSize: rawFiles.reduce(0) { $0 + $1.fileSize }
                    ))
                    catChildren.append(FileSafeTargetFolder(
                        relativePath: jpegPath, displayName: "JPEG",
                        fileCount: jpegFiles.count, totalSize: jpegFiles.reduce(0) { $0 + $1.fileSize }
                    ))

                    children.append(FileSafeTargetFolder(
                        relativePath: "\(basePath)/\(category)",
                        displayName: category,
                        children: catChildren
                    ))
                } else {
                    let catPath = "\(basePath)/\(category)"
                    for file in catFiles {
                        mappings.append(FileSafeFileMapping(
                            source: file,
                            destinationPath: "\(projectPath)/\(catPath)/\(file.fileName)",
                            targetFolderName: category
                        ))
                    }
                    children.append(FileSafeTargetFolder(
                        relativePath: catPath,
                        displayName: category,
                        fileCount: catFiles.count,
                        totalSize: catFiles.reduce(0) { $0 + $1.fileSize }
                    ))
                }
            }
        }

        let photoTree = FileSafeTargetFolder(
            relativePath: basePath,
            displayName: URL(fileURLWithPath: basePath).lastPathComponent,
            fileCount: config.photoCategories.isEmpty && !config.splitRawJpeg ? files.count : 0,
            totalSize: config.photoCategories.isEmpty && !config.splitRawJpeg ? files.reduce(0) { $0 + $1.fileSize } : 0,
            children: children
        )

        return (photoTree, mappings)
    }

    // MARK: - Helpers

    private func assignFilesToDays(
        files: [FileSafeSourceFile],
        shootDays: [FileSafeShootDay],
        useTimestamp: Bool
    ) -> [UUID: [FileSafeSourceFile]] {
        guard !shootDays.isEmpty else { return [:] }

        // Als er maar 1 dag is, alles in die dag
        if shootDays.count == 1 {
            return [shootDays[0].id: files]
        }

        // Als timestamps niet gebruikt worden of geen datums beschikbaar, verdeel evenredig
        if !useTimestamp || shootDays.allSatisfy({ $0.date == nil }) {
            return distributeFilesEvenlyOverDays(files: files, days: shootDays)
        }

        // Timestamp-based toewijzing
        let calendar = Calendar.current
        var dayFiles: [UUID: [FileSafeSourceFile]] = [:]

        for file in files {
            guard let fileDate = file.creationDate ?? file.modificationDate else {
                // Geen datum: toewijzen aan eerste dag
                dayFiles[shootDays[0].id, default: []].append(file)
                continue
            }

            let matched = shootDays.first { day in
                guard let dayDate = day.date else { return false }
                return calendar.isDate(fileDate, inSameDayAs: dayDate)
            }

            let targetDay = matched ?? shootDays.last!
            dayFiles[targetDay.id, default: []].append(file)
        }

        return dayFiles
    }

    private func distributeFilesEvenlyOverDays(
        files: [FileSafeSourceFile],
        days: [FileSafeShootDay]
    ) -> [UUID: [FileSafeSourceFile]] {
        var result: [UUID: [FileSafeSourceFile]] = [:]
        let filesPerDay = max(1, files.count / days.count)

        for (index, file) in files.enumerated() {
            let dayIndex = min(index / filesPerDay, days.count - 1)
            result[days[dayIndex].id, default: []].append(file)
        }

        return result
    }

    /// Verdeel bestanden over hoeken/personen.
    /// Zonder verdere metadata worden bestanden gelijkmatig verdeeld.
    private func distributeFilesOverAngles(
        files: [FileSafeSourceFile],
        angles: [String]
    ) -> [String: [FileSafeSourceFile]] {
        guard !angles.isEmpty else { return [:] }

        if angles.count == 1 {
            return [angles[0]: files]
        }

        var result: [String: [FileSafeSourceFile]] = [:]
        let filesPerAngle = max(1, files.count / angles.count)

        for (index, file) in files.enumerated() {
            let angleIndex = min(index / filesPerAngle, angles.count - 1)
            result[angles[angleIndex], default: []].append(file)
        }

        return result
    }
}
