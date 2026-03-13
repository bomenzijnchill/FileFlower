import Foundation

class FileSafeScanner {
    static let shared = FileSafeScanner()

    struct ScanProgress {
        let filesFound: Int
        let currentDirectory: String
        let videoCount: Int
        let audioCount: Int
        let photoCount: Int
    }

    func scanVolume(
        _ volumeURL: URL,
        volumeName: String,
        onProgress: @escaping (ScanProgress) -> Void
    ) async throws -> FileSafeScanResult {
        let fileManager = FileManager.default

        let resourceKeys: [URLResourceKey] = [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .isDirectoryKey,
            .nameKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: volumeURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw FileSafeScanError.cannotAccessVolume
        }

        var files: [FileSafeSourceFile] = []
        var totalSize: Int64 = 0
        var videoCount = 0
        var audioCount = 0
        var photoCount = 0
        var lastProgressDir = ""
        var allPaths: [String] = []
        var allExtensions: Set<String> = []

        for case let fileURL as URL in enumerator {
            // Check cancellation
            try Task.checkCancellation()

            guard let resources = try? fileURL.resourceValues(forKeys: Set(resourceKeys)) else {
                continue
            }

            // Skip mappen — inclusief camera thumbnail/systeem mappen
            if resources.isDirectory == true {
                let dirName = fileURL.lastPathComponent

                // Skip bekende camera thumbnail/systeem mappen
                if FileSafeExtensions.shouldIgnoreFolder(name: dirName) {
                    enumerator.skipDescendants()
                    continue
                }

                // Rapporteer voortgang bij directorywissel
                if dirName != lastProgressDir {
                    lastProgressDir = dirName
                    allPaths.append(fileURL.path)
                    await MainActor.run {
                        onProgress(ScanProgress(
                            filesFound: files.count,
                            currentDirectory: dirName,
                            videoCount: videoCount,
                            audioCount: audioCount,
                            photoCount: photoCount
                        ))
                    }
                }
                continue
            }

            let fileName = fileURL.lastPathComponent
            let fileExtension = fileURL.pathExtension

            // Skip systeem- en indexbestanden
            if FileSafeExtensions.shouldIgnore(fileName: fileName, fileExtension: fileExtension) {
                continue
            }

            let category = FileSafeExtensions.category(for: fileExtension)
            let fileSize = Int64(resources.fileSize ?? 0)
            let relativePath = fileURL.path

            allPaths.append(relativePath)
            allExtensions.insert(fileExtension.lowercased())

            let sourceFile = FileSafeSourceFile(
                id: UUID(),
                relativePath: relativePath,
                fileName: fileName,
                fileExtension: fileExtension,
                category: category,
                fileSize: fileSize,
                creationDate: resources.creationDate,
                modificationDate: resources.contentModificationDate
            )

            files.append(sourceFile)
            totalSize += fileSize

            switch category {
            case .video: videoCount += 1
            case .audio: audioCount += 1
            case .photo: photoCount += 1
            case .other: break
            }

            // Rapporteer voortgang periodiek
            if files.count % 50 == 0 {
                await MainActor.run {
                    onProgress(ScanProgress(
                        filesFound: files.count,
                        currentDirectory: lastProgressDir,
                        videoCount: videoCount,
                        audioCount: audioCount,
                        photoCount: photoCount
                    ))
                }
            }
        }

        // Sorteer bestanden op aanmaakdatum voor timestamp-toewijzing
        files.sort { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }

        // Detecteer camera merk
        let detectedBrand = detectCameraBrand(paths: allPaths, extensions: allExtensions)

        // Analyseer datums
        let dateAnalysis = analyzeDates(from: files)

        return FileSafeScanResult(
            volumeName: volumeName,
            volumePath: volumeURL.path,
            files: files,
            totalSize: totalSize,
            scanDate: Date(),
            detectedBrand: detectedBrand,
            uniqueCalendarDays: dateAnalysis.uniqueDays,
            earliestDate: dateAnalysis.earliest,
            latestDate: dateAnalysis.latest
        )
    }

    // MARK: - Camera Merk Detectie

    private func detectCameraBrand(paths: [String], extensions: Set<String>) -> FileSafeCameraBrand {
        let upperPaths = paths.map { $0.uppercased() }
        let joinedPaths = upperPaths.joined(separator: "\n")

        // Folder-gebaseerde detectie
        if joinedPaths.contains("/PRIVATE/M4ROOT/") { return .sony }
        if joinedPaths.contains("/CLIPS001/") || joinedPaths.contains("/CANONMSC/") { return .canon }
        if joinedPaths.contains("/DCIM/100MEDIA/") { return .dji }
        if joinedPaths.contains("/DCIM/100GOPRO/") { return .gopro }

        // Extensie-gebaseerde detectie
        if extensions.contains("braw") { return .blackmagic }
        if extensions.contains("r3d") { return .red }
        if extensions.contains("ari") { return .arri }

        // Panasonic detectie
        if joinedPaths.contains("/PRIVATE/AVCHD/") || joinedPaths.contains("/PRIVATE/PANA_GRP/") { return .panasonic }

        return .unknown
    }

    // MARK: - Datum Analyse

    private func analyzeDates(from files: [FileSafeSourceFile]) -> (uniqueDays: [Date], earliest: Date?, latest: Date?) {
        let calendar = Calendar.current
        var daySet = Set<DateComponents>()
        var uniqueDays: [Date] = []
        var earliest: Date?
        var latest: Date?

        for file in files {
            guard let date = file.creationDate ?? file.modificationDate else { continue }

            // Track vroegste/laatste
            if earliest == nil || date < earliest! { earliest = date }
            if latest == nil || date > latest! { latest = date }

            // Unieke kalenderdagen
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            if daySet.insert(components).inserted {
                if let calendarDate = calendar.date(from: components) {
                    uniqueDays.append(calendarDate)
                }
            }
        }

        uniqueDays.sort()
        return (uniqueDays, earliest, latest)
    }
}

enum FileSafeScanError: LocalizedError {
    case cannotAccessVolume
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cannotAccessVolume:
            return "Cannot access the selected volume"
        case .cancelled:
            return "Scan was cancelled"
        }
    }
}
