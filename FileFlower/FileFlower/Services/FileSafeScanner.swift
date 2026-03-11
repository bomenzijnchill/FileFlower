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

        for case let fileURL as URL in enumerator {
            // Check cancellation
            try Task.checkCancellation()

            guard let resources = try? fileURL.resourceValues(forKeys: Set(resourceKeys)) else {
                continue
            }

            // Skip mappen
            if resources.isDirectory == true {
                let dirName = fileURL.lastPathComponent
                // Rapporteer voortgang bij directorywissel
                if dirName != lastProgressDir {
                    lastProgressDir = dirName
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

        return FileSafeScanResult(
            volumeName: volumeName,
            volumePath: volumeURL.path,
            files: files,
            totalSize: totalSize,
            scanDate: Date()
        )
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
