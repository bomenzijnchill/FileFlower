import Foundation
import Combine
import CryptoKit

// MARK: - Transfer Manager (Singleton)

@MainActor
class FileSafeTransferManager: ObservableObject {
    static let shared = FileSafeTransferManager()

    @Published var transfers: [FileSafeTransfer] = []

    private init() {}

    /// Start een nieuwe transfer en retourneer het transfer ID
    func startTransfer(
        mappings: [FileSafeFileMapping],
        projectName: String,
        volumeName: String,
        volumeURL: URL? = nil,
        projectPath: String,
        footagePath: String?,
        projectConfig: FileSafeProjectConfig,
        skippedCount: Int = 0,
        isNewProject: Bool = false
    ) -> UUID {
        let transfer = FileSafeTransfer(
            projectName: projectName,
            volumeName: volumeName,
            volumeURL: volumeURL,
            projectPath: projectPath,
            footagePath: footagePath,
            totalCount: mappings.count,
            skippedCount: skippedCount,
            isNewProject: isNewProject
        )

        transfers.append(transfer)
        transfer.startCopy(mappings: mappings, projectConfig: projectConfig)
        return transfer.id
    }

    func cancelTransfer(id: UUID) {
        guard let transfer = transfers.first(where: { $0.id == id }) else { return }
        transfer.cancel()
    }

    func pauseTransfer(id: UUID) {
        guard let transfer = transfers.first(where: { $0.id == id }) else { return }
        transfer.pause()
    }

    func resumeTransfer(id: UUID) {
        guard let transfer = transfers.first(where: { $0.id == id }) else { return }
        transfer.resume()
    }

    /// Verwijder voltooide/geannuleerde transfer uit lijst
    func removeTransfer(id: UUID) {
        transfers.removeAll { $0.id == id && !$0.isRunning }
    }

    var hasActiveTransfers: Bool {
        transfers.contains { $0.isRunning }
    }

    var hasTransfers: Bool {
        !transfers.isEmpty
    }
}

// MARK: - Individual Transfer

@MainActor
class FileSafeTransfer: ObservableObject, Identifiable {
    let id: UUID
    let projectName: String
    let volumeName: String
    /// Bron-volume, nodig om na afloop te kunnen ejecten vanuit het dashboard
    let volumeURL: URL?
    let projectPath: String
    let footagePath: String?
    let startTime: Date
    let skippedCount: Int  // Aantal overgeslagen duplicaten
    let isNewProject: Bool  // True als FileSafe een nieuwe projectmap heeft aangemaakt

    // Published progress state
    @Published var progress: Double = 0
    @Published var currentFile: String = ""
    @Published var currentDestinationPath: String = ""
    @Published var copiedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var copySpeed: String = ""
    @Published var estimatedTimeRemaining: String = ""
    @Published var isRunning: Bool = false
    @Published var isPaused: Bool = false
    @Published var currentPhase: FileSafeVerificationPhase = .copying

    // Per-bestand verificatiestatus
    @Published var currentFileSizeOK: Bool = false
    @Published var currentFileChecksumOK: Bool = false
    @Published var currentFileBytesOK: Bool = false

    // Rapport na afloop
    @Published var report: FileSafeCopyReport?

    var isCompleted: Bool { report != nil }
    var isFailed: Bool { report?.failCount ?? 0 > 0 }

    // Internal
    private var copyTask: Task<Void, Never>?
    private let maxRetries = 3
    /// Uniek per transfer: twee gelijktijdige transfers naar dezelfde doelmap mogen
    /// elkaars tijdelijke bestand niet verwijderen/verifiëren.
    private nonisolated let tempExtension: String
    private let chunkSize = 1_048_576 // 1MB chunks

    init(
        projectName: String,
        volumeName: String,
        volumeURL: URL? = nil,
        projectPath: String,
        footagePath: String?,
        totalCount: Int,
        skippedCount: Int = 0,
        isNewProject: Bool = false
    ) {
        let newId = UUID()
        self.id = newId
        self.tempExtension = ".filesafe-tmp-\(newId.uuidString.prefix(8))"
        self.projectName = projectName
        self.volumeName = volumeName
        self.volumeURL = volumeURL
        self.projectPath = projectPath
        self.footagePath = footagePath
        self.startTime = Date()
        self.totalCount = totalCount
        self.skippedCount = skippedCount
        self.isNewProject = isNewProject
    }

    // MARK: - Copy starten

    func startCopy(
        mappings: [FileSafeFileMapping],
        projectConfig: FileSafeProjectConfig
    ) {
        guard !isRunning else { return }

        isRunning = true
        copiedCount = 0
        progress = 0

        copyTask = Task { [weak self] in
            guard let self = self else { return }

            let startTime = Date()
            var results: [FileSafeCopyResult] = []
            var totalBytesCopied: Int64 = 0

            for (index, mapping) in mappings.enumerated() {
                guard !Task.isCancelled else { break }

                // Pause ondersteuning
                while self.isPaused && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                guard !Task.isCancelled else { break }

                self.currentFile = mapping.source.fileName
                self.currentDestinationPath = mapping.destinationPath
                self.copiedCount = index
                self.progress = Double(index) / Double(self.totalCount)
                self.currentFileSizeOK = false
                self.currentFileChecksumOK = false
                self.currentFileBytesOK = false
                self.currentPhase = .copying

                let result = await self.copyFileWithFullVerification(mapping: mapping)

                results.append(result)
                totalBytesCopied += mapping.source.fileSize

                self.copiedCount = index + 1
                self.progress = Double(index + 1) / Double(self.totalCount)

                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > 0 {
                    let bytesPerSecond = Double(totalBytesCopied) / elapsed
                    self.copySpeed = self.formatSpeed(bytesPerSecond)

                    let remainingFiles = self.totalCount - (index + 1)
                    if remainingFiles > 0 && bytesPerSecond > 0 {
                        let remainingBytes = mappings[(index + 1)...].reduce(Int64(0)) { $0 + $1.source.fileSize }
                        let remainingSeconds = Double(remainingBytes) / bytesPerSecond
                        self.estimatedTimeRemaining = self.formatTime(remainingSeconds)
                    }
                }
            }

            let endTime = Date()
            // Bij annulering: de niet-verwerkte mappings expliciet als "niet gekopieerd"
            // opnemen. Anders meldt het rapport "Verified: 20 / Failed: 0" terwijl er
            // 30 bestanden ontbreken — precies het bewijs waarvoor FileSafe bestaat.
            let wasCancelled = Task.isCancelled || results.count < mappings.count
            if wasCancelled {
                for mapping in mappings.dropFirst(results.count) {
                    results.append(self.makeFailedResult(
                        mapping: mapping,
                        error: "Niet gekopieerd — transfer geannuleerd",
                        retries: 0
                    ))
                }
            }

            let report = FileSafeCopyReport(
                id: UUID(),
                projectName: self.projectName,
                volumeName: self.volumeName,
                startTime: startTime,
                endTime: endTime,
                totalFiles: mappings.count,
                totalSize: totalBytesCopied,
                results: results,
                skippedCount: self.skippedCount
            )

            self.isRunning = false
            self.currentPhase = .complete
            self.progress = wasCancelled ? Double(results.filter { $0.error == nil }.count) / Double(max(mappings.count, 1)) : 1.0
            self.report = report

            // I/O voor log/txt/config naar achtergrond zodat UI direct door kan transitionen.
            // Zonder deze detach zit de report-screen overgang te wachten op TXT-rendering
            // voor 25+ files op traag volume → hangt enkele seconden op 100%.
            let capturedProjectPath = self.projectPath
            let capturedFootagePath = self.footagePath
            var updatedConfig = projectConfig
            updatedConfig.lastUpdated = Date()

            Task.detached(priority: .utility) {
                try? FileSafeCopyEngine.writeLog(report, to: capturedProjectPath)
                try? FileSafeCopyEngine.writeTxtReport(report, to: capturedProjectPath, footagePath: capturedFootagePath)
                try? updatedConfig.save(to: capturedProjectPath)
            }
        }
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func cancel() {
        copyTask?.cancel()
        copyTask = nil
        isRunning = false
        isPaused = false
    }

    // MARK: - Kopieer + Verificeer (per bestand)

    private nonisolated func copyFileWithFullVerification(
        mapping: FileSafeFileMapping
    ) async -> FileSafeCopyResult {
        let sourceURL = URL(fileURLWithPath: mapping.source.relativePath)
        let destURL = URL(fileURLWithPath: mapping.destinationPath)
        let tempURL = destURL.appendingPathExtension(tempExtension.replacingOccurrences(of: ".", with: ""))

        var lastError: String?
        var retryCount = 0

        for attempt in 1...maxRetries {
            guard !Task.isCancelled else {
                return makeFailedResult(mapping: mapping, error: "Cancelled", retries: retryCount)
            }

            retryCount = attempt - 1

            // Reset UI state
            await MainActor.run {
                self.currentFileSizeOK = false
                self.currentFileChecksumOK = false
                self.currentFileBytesOK = false
                self.currentPhase = .copying
            }

            // Stap 1: Kopieer bestand naar temp locatie (op achtergrond thread)
            let copyResult: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    try FileManager.default.createDirectory(
                        at: destURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try? FileManager.default.removeItem(at: tempURL)
                    try FileManager.default.copyItem(at: sourceURL, to: tempURL)
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }.value

            switch copyResult {
            case .failure(let error):
                lastError = "Copy failed: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: tempURL)
                continue
            case .success:
                break
            }

            // Size check
            let sourceSize = mapping.source.fileSize
            let destSize = fileSize(at: tempURL)
            let sizesMatch = sourceSize == destSize

            await MainActor.run {
                self.currentFileSizeOK = sizesMatch
            }

            if !sizesMatch {
                lastError = "Size mismatch: source \(sourceSize) vs dest \(destSize)"
                try? FileManager.default.removeItem(at: tempURL)
                continue
            }

            // Stap 2: SHA-256 checksum verificatie
            await MainActor.run {
                self.currentPhase = .checksum
            }

            let sourceHash = await calculateSHA256(at: sourceURL)
            let destHash = await calculateSHA256(at: tempURL)
            let checksumsMatch = !sourceHash.isEmpty && !destHash.isEmpty && sourceHash == destHash

            await MainActor.run {
                self.currentFileChecksumOK = checksumsMatch
            }

            if !checksumsMatch {
                lastError = "Checksum mismatch"
                try? FileManager.default.removeItem(at: tempURL)
                continue
            }

            // Stap 3: Byte-voor-byte vergelijking
            await MainActor.run {
                self.currentPhase = .byteCompare
            }

            let bytesMatch = await compareFilesByteByByte(file1: sourceURL, file2: tempURL)

            await MainActor.run {
                self.currentFileBytesOK = bytesMatch
            }

            if !bytesMatch {
                lastError = "Byte comparison mismatch"
                try? FileManager.default.removeItem(at: tempURL)
                continue
            }

            // Alle checks geslaagd — hernoem temp naar definitief.
            // NOOIT stil overschrijven: twee bronbestanden met dezelfde naam (bv. IMG_0001.CR3
            // uit 100CANON én 101CANON) mogen elkaar niet vervangen. Bestaat het doel al:
            //   - identieke inhoud (checksum) → duplicaat, klaar
            //   - andere inhoud → uniek suffix (_2, _3, …)
            var finalDestURL = destURL
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    let existingHash = await calculateSHA256(at: destURL)
                    if existingHash == sourceHash {
                        // Exact duplicaat staat er al geverifieerd — temp opruimen
                        try? FileManager.default.removeItem(at: tempURL)
                    } else {
                        finalDestURL = Self.uniqueDestination(destURL)
                        try FileManager.default.moveItem(at: tempURL, to: finalDestURL)
                    }
                } else {
                    try FileManager.default.moveItem(at: tempURL, to: destURL)
                }
            } catch {
                lastError = "Rename failed: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: tempURL)
                continue
            }

            await MainActor.run {
                self.currentPhase = .complete
            }

            return FileSafeCopyResult(
                id: UUID(),
                sourceFile: mapping.source,
                destinationPath: finalDestURL.path,
                sourceChecksum: sourceHash,
                destinationChecksum: destHash,
                sizesMatch: true,
                checksumsMatch: true,
                bytesMatch: true,
                retryCount: retryCount,
                error: nil,
                copyDuration: 0
            )
        }

        // Alle pogingen gefaald
        try? FileManager.default.removeItem(at: tempURL)
        return makeFailedResult(mapping: mapping, error: lastError ?? "Unknown error", retries: retryCount)
    }

    /// Uniek doelpad: voegt `_2`, `_3`, … toe zodat een bestaand bestand nooit wordt overschreven.
    private nonisolated static func uniqueDestination(_ target: URL) -> URL {
        guard FileManager.default.fileExists(atPath: target.path) else { return target }
        let dir = target.deletingLastPathComponent()
        let name = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        var counter = 2
        var candidate = target
        while FileManager.default.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(name)_\(counter)" : "\(name)_\(counter).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }

    // MARK: - SHA-256 Checksum (chunked)

    private nonisolated func calculateSHA256(at url: URL) async -> String {
        guard let stream = InputStream(url: url) else { return "" }
        stream.open()
        defer { stream.close() }

        var hasher = SHA256()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            if Task.isCancelled { return "" }

            let bytesRead = stream.read(buffer, maxLength: chunkSize)
            if bytesRead > 0 {
                hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: bytesRead))
            } else if bytesRead < 0 {
                return ""
            }

            await Task.yield()
        }

        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Byte-voor-byte vergelijking

    private nonisolated func compareFilesByteByByte(file1: URL, file2: URL) async -> Bool {
        guard let stream1 = InputStream(url: file1),
              let stream2 = InputStream(url: file2) else { return false }

        stream1.open()
        stream2.open()
        defer {
            stream1.close()
            stream2.close()
        }

        let buffer1 = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        let buffer2 = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer {
            buffer1.deallocate()
            buffer2.deallocate()
        }

        while stream1.hasBytesAvailable && stream2.hasBytesAvailable {
            if Task.isCancelled { return false }

            let bytesRead1 = stream1.read(buffer1, maxLength: chunkSize)
            let bytesRead2 = stream2.read(buffer2, maxLength: chunkSize)

            if bytesRead1 != bytesRead2 { return false }
            if bytesRead1 < 0 || bytesRead2 < 0 { return false }
            if bytesRead1 == 0 && bytesRead2 == 0 { break }

            if memcmp(buffer1, buffer2, bytesRead1) != 0 {
                return false
            }

            await Task.yield()
        }

        let remaining1 = stream1.hasBytesAvailable
        let remaining2 = stream2.hasBytesAvailable
        return !remaining1 && !remaining2
    }

    // MARK: - Helpers

    private nonisolated func fileSize(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return -1 }
        return size
    }

    private nonisolated func makeFailedResult(mapping: FileSafeFileMapping, error: String, retries: Int) -> FileSafeCopyResult {
        FileSafeCopyResult(
            id: UUID(),
            sourceFile: mapping.source,
            destinationPath: mapping.destinationPath,
            sourceChecksum: "",
            destinationChecksum: "",
            sizesMatch: false,
            checksumsMatch: false,
            bytesMatch: false,
            retryCount: retries,
            error: error,
            copyDuration: 0
        )
    }

    private nonisolated func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_073_741_824 {
            return String(format: "%.1f GB/s", bytesPerSecond / 1_073_741_824)
        } else if bytesPerSecond >= 1_048_576 {
            return String(format: "%.0f MB/s", bytesPerSecond / 1_048_576)
        } else if bytesPerSecond >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1024)
        }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    private nonisolated func formatTime(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        } else if seconds < 3600 {
            let min = Int(seconds) / 60
            let sec = Int(seconds) % 60
            return "\(min)m \(sec)s"
        } else {
            let hrs = Int(seconds) / 3600
            let min = (Int(seconds) % 3600) / 60
            return "\(hrs)h \(min)m"
        }
    }
}
