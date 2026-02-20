import Foundation

enum CloudZipGroupStatus {
    case waitingForMore(baseName: String, received: Int, expected: Int)
    case allPartsReceived(baseName: String)
}

class CloudZipMerger {
    static let shared = CloudZipMerger()

    private var pendingGroups: [String: CloudZipGroup] = [:]
    private let queue = DispatchQueue(label: "com.fileflower.cloudzipmerger", attributes: .concurrent)
    private var timeoutTimer: Timer?

    /// Callback wanneer een groep klaar is om te mergen (door timeout of alle delen binnen)
    var onGroupReady: ((String, String?) -> Void)?  // (baseName, originURL)

    private let timeoutSeconds: TimeInterval = 30.0

    private init() {
        startTimeoutChecker()
    }

    // MARK: - Public API

    /// Check of een ZIP bestand een Google Drive multi-part ZIP is
    func isGoogleDriveMultiPart(_ url: URL) -> Bool {
        return CloudZipGroup.parse(filename: url.lastPathComponent) != nil
    }

    /// Voeg een Google Drive ZIP deel toe aan de merger
    func addPart(_ url: URL, originURL: String?) -> CloudZipGroupStatus {
        guard let parsed = CloudZipGroup.parse(filename: url.lastPathComponent) else {
            return .waitingForMore(baseName: "", received: 0, expected: 0)
        }

        var result: CloudZipGroupStatus = .waitingForMore(
            baseName: parsed.baseName,
            received: 1,
            expected: parsed.totalParts
        )

        queue.sync(flags: .barrier) {
            if var group = pendingGroups[parsed.baseName] {
                // Voeg toe aan bestaande groep
                let part = CloudZipPart(
                    id: UUID(),
                    url: url,
                    partNumber: parsed.partNumber
                )
                group.receivedParts.append(part)
                group.lastPartReceivedAt = Date()
                pendingGroups[parsed.baseName] = group

                print("CloudZipMerger: Deel \(parsed.partNumber)/\(parsed.totalParts) toegevoegd aan groep '\(parsed.folderName)'")

                if group.isComplete {
                    result = .allPartsReceived(baseName: parsed.baseName)
                } else {
                    result = .waitingForMore(
                        baseName: parsed.baseName,
                        received: group.receivedParts.count,
                        expected: parsed.totalParts
                    )
                }
            } else {
                // Maak nieuwe groep aan
                let part = CloudZipPart(
                    id: UUID(),
                    url: url,
                    partNumber: parsed.partNumber
                )

                let group = CloudZipGroup(
                    id: UUID(),
                    baseName: parsed.baseName,
                    expectedPartCount: parsed.totalParts,
                    receivedParts: [part],
                    firstDetectedAt: Date(),
                    lastPartReceivedAt: Date(),
                    originURL: originURL
                )

                pendingGroups[parsed.baseName] = group
                print("CloudZipMerger: Nieuwe groep '\(parsed.folderName)' (verwacht \(parsed.totalParts) delen)")

                if group.isComplete {
                    result = .allPartsReceived(baseName: parsed.baseName)
                }
            }
        }

        return result
    }

    /// Pak alle delen uit en voeg samen tot één map
    /// Retourneert de URLs van alle uitgepakte bestanden
    func mergeGroup(baseName: String) throws -> [URL] {
        var group: CloudZipGroup?
        queue.sync {
            group = pendingGroups[baseName]
        }

        guard let group = group else {
            throw CloudZipMergerError.groupNotFound(baseName)
        }

        print("CloudZipMerger: Start merge voor '\(baseName)' (\(group.receivedParts.count)/\(group.expectedPartCount) delen)")

        let fileManager = FileManager.default
        let downloadsDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

        // Gebruik de originele mapnaam (zonder timestamp en deelnummers) als merge folder
        let folderName: String
        if let parsed = CloudZipGroup.parse(filename: group.receivedParts.first?.url.lastPathComponent ?? "") {
            folderName = parsed.folderName
        } else {
            folderName = baseName
        }

        let mergedFolder = downloadsDir.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: mergedFolder, withIntermediateDirectories: true)

        var allExtractedFiles: [URL] = []
        let sortedParts = group.receivedParts.sorted { $0.partNumber < $1.partNumber }

        for part in sortedParts {
            print("CloudZipMerger: Uitpakken deel \(part.partNumber)...")

            // Pak uit naar een tijdelijke map
            let tempFolder = downloadsDir.appendingPathComponent(
                "_fileflower_temp_part_\(part.partNumber)_\(UUID().uuidString.prefix(8))",
                isDirectory: true
            )

            do {
                let extractedFiles = try Unzipper.unzip(part.url, to: tempFolder)

                // De extractie maakt een subfolder met de zip-naam, dus we moeten de bestanden
                // uit die subfolder halen
                for fileURL in extractedFiles {
                    // Bepaal het relatieve pad binnen de extractie
                    // Unzipper maakt een subfolder met de zip-naam (zonder .zip)
                    let zipBaseName = part.url.deletingPathExtension().lastPathComponent
                    let extractSubfolder = tempFolder.appendingPathComponent(zipBaseName)

                    let relativePath: String
                    if fileURL.path.hasPrefix(extractSubfolder.path) {
                        // Pad relatief ten opzichte van de subfolder
                        relativePath = String(fileURL.path.dropFirst(extractSubfolder.path.count + 1))
                    } else if fileURL.path.hasPrefix(tempFolder.path) {
                        // Pad relatief ten opzichte van de temp folder
                        relativePath = String(fileURL.path.dropFirst(tempFolder.path.count + 1))
                    } else {
                        relativePath = fileURL.lastPathComponent
                    }

                    let destinationURL = mergedFolder.appendingPathComponent(relativePath)

                    // Maak subdirectories aan als nodig
                    let destinationDir = destinationURL.deletingLastPathComponent()
                    try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)

                    // Verplaats bestand (met duplicate handling)
                    var finalDestination = destinationURL
                    var counter = 1
                    while fileManager.fileExists(atPath: finalDestination.path) {
                        let filename = destinationURL.deletingPathExtension().lastPathComponent
                        let ext = destinationURL.pathExtension
                        let parentDir = destinationURL.deletingLastPathComponent()
                        finalDestination = parentDir.appendingPathComponent("\(filename)_\(counter).\(ext)")
                        counter += 1
                    }

                    try fileManager.moveItem(at: fileURL, to: finalDestination)
                    allExtractedFiles.append(finalDestination)
                }

                // Ruim temp map op
                try? fileManager.removeItem(at: tempFolder)
            } catch {
                print("CloudZipMerger: Fout bij uitpakken deel \(part.partNumber): \(error)")
                try? fileManager.removeItem(at: tempFolder)
            }

            // Verwijder originele ZIP
            try? fileManager.removeItem(at: part.url)
        }

        // Verwijder groep uit pending
        queue.sync(flags: .barrier) {
            pendingGroups.removeValue(forKey: baseName)
        }

        print("CloudZipMerger: Merge voltooid — \(allExtractedFiles.count) bestanden in \(mergedFolder.path)")
        return allExtractedFiles
    }

    /// Haal de originURL op voor een groep
    func originURL(for baseName: String) -> String? {
        var result: String?
        queue.sync {
            result = pendingGroups[baseName]?.originURL
        }
        return result
    }

    // MARK: - Timeout

    private func startTimeoutChecker() {
        DispatchQueue.main.async {
            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.checkTimeouts()
            }
        }
    }

    private func checkTimeouts() {
        var timedOutGroups: [(String, String?)] = []  // (baseName, originURL)

        queue.sync {
            let now = Date()
            for (baseName, group) in pendingGroups {
                let timeSinceLastPart = now.timeIntervalSince(group.lastPartReceivedAt)
                if timeSinceLastPart > timeoutSeconds && !group.receivedParts.isEmpty {
                    timedOutGroups.append((baseName, group.originURL))
                    print("CloudZipMerger: Groep '\(baseName)' timeout na \(Int(timeSinceLastPart))s — merge met \(group.receivedParts.count)/\(group.expectedPartCount) delen")
                }
            }
        }

        for (baseName, originURL) in timedOutGroups {
            onGroupReady?(baseName, originURL)
        }
    }
}

enum CloudZipMergerError: Error, LocalizedError {
    case groupNotFound(String)
    case mergeFailed(String)

    var errorDescription: String? {
        switch self {
        case .groupNotFound(let name):
            return "ZIP groep '\(name)' niet gevonden"
        case .mergeFailed(let reason):
            return "Merge mislukt: \(reason)"
        }
    }
}
