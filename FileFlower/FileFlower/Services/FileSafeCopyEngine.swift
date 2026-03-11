import Foundation
import Combine
import CryptoKit

class FileSafeCopyEngine: ObservableObject {
    // MARK: - Published state

    @Published var progress: Double = 0
    @Published var currentFile: String = ""
    @Published var copiedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var copySpeed: String = ""
    @Published var estimatedTimeRemaining: String = ""
    @Published var isRunning: Bool = false
    @Published var currentPhase: FileSafeVerificationPhase = .copying

    // Per-bestand verificatiestatus (voor UI)
    @Published var currentFileSizeOK: Bool = false
    @Published var currentFileChecksumOK: Bool = false
    @Published var currentFileBytesOK: Bool = false

    // MARK: - Config

    private let maxRetries = 3
    private let tempExtension = ".filesafe-tmp"
    private let chunkSize = 1_048_576 // 1MB chunks voor hashing en vergelijking

    private var copyTask: Task<Void, Never>?

    // MARK: - Kopieer starten

    func startCopy(
        mappings: [FileSafeFileMapping],
        projectName: String,
        volumeName: String,
        onFileComplete: @escaping (FileSafeCopyResult) -> Void,
        onComplete: @escaping (FileSafeCopyReport) -> Void
    ) {
        guard !isRunning else { return }

        isRunning = true
        totalCount = mappings.count
        copiedCount = 0
        progress = 0

        copyTask = Task { [weak self] in
            guard let self = self else { return }

            let startTime = Date()
            var results: [FileSafeCopyResult] = []
            var totalBytesCopied: Int64 = 0
            let speedTracker = SpeedTracker()

            for (index, mapping) in mappings.enumerated() {
                guard !Task.isCancelled else { break }

                await MainActor.run {
                    self.currentFile = mapping.source.fileName
                    self.copiedCount = index
                    self.progress = Double(index) / Double(self.totalCount)
                    self.currentFileSizeOK = false
                    self.currentFileChecksumOK = false
                    self.currentFileBytesOK = false
                    self.currentPhase = .copying
                }

                let result = await self.copyFileWithFullVerification(
                    mapping: mapping,
                    speedTracker: speedTracker
                )

                results.append(result)
                totalBytesCopied += mapping.source.fileSize

                await MainActor.run {
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

                onFileComplete(result)
            }

            let endTime = Date()
            let report = FileSafeCopyReport(
                id: UUID(),
                projectName: projectName,
                volumeName: volumeName,
                startTime: startTime,
                endTime: endTime,
                totalFiles: mappings.count,
                totalSize: totalBytesCopied,
                results: results
            )

            await MainActor.run {
                self.isRunning = false
                self.currentPhase = .complete
                self.progress = 1.0
            }

            onComplete(report)
        }
    }

    func cancelCopy() {
        copyTask?.cancel()
        copyTask = nil

        Task { @MainActor in
            isRunning = false
        }
    }

    // MARK: - Kopieer + Verificeer (per bestand)

    private func copyFileWithFullVerification(
        mapping: FileSafeFileMapping,
        speedTracker: SpeedTracker
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

            // Stap 1: Kopieer bestand naar temp locatie
            do {
                // Maak doelmap aan
                try FileManager.default.createDirectory(
                    at: destURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                // Verwijder eventueel oud temp bestand
                try? FileManager.default.removeItem(at: tempURL)

                // Kopieer
                try FileManager.default.copyItem(at: sourceURL, to: tempURL)
            } catch {
                lastError = "Copy failed: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: tempURL)
                continue
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

            let bytesMatch = await compareFilesbyteByByte(file1: sourceURL, file2: tempURL)

            await MainActor.run {
                self.currentFileBytesOK = bytesMatch
            }

            if !bytesMatch {
                lastError = "Byte comparison mismatch"
                try? FileManager.default.removeItem(at: tempURL)
                continue
            }

            // Alle checks geslaagd — hernoem temp naar definitief
            do {
                try? FileManager.default.removeItem(at: destURL) // Verwijder eventueel bestaand
                try FileManager.default.moveItem(at: tempURL, to: destURL)
            } catch {
                lastError = "Rename failed: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: tempURL)
                continue
            }

            await MainActor.run {
                self.currentPhase = .complete
            }

            // Succes
            return FileSafeCopyResult(
                id: UUID(),
                sourceFile: mapping.source,
                destinationPath: mapping.destinationPath,
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

    // MARK: - SHA-256 Checksum (chunked)

    private func calculateSHA256(at url: URL) async -> String {
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
                return "" // Leesfout
            }

            // Yield om UI responsive te houden
            await Task.yield()
        }

        let digest = hasher.finalize()
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Byte-voor-byte vergelijking

    private func compareFilesbyteByByte(file1: URL, file2: URL) async -> Bool {
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

            // Aantal gelezen bytes moet gelijk zijn
            if bytesRead1 != bytesRead2 { return false }

            // Leesfout
            if bytesRead1 < 0 || bytesRead2 < 0 { return false }

            // Einde van beide streams
            if bytesRead1 == 0 && bytesRead2 == 0 { break }

            // Vergelijk bytes
            if memcmp(buffer1, buffer2, bytesRead1) != 0 {
                return false
            }

            await Task.yield()
        }

        // Controleer dat beide streams uitgeput zijn
        let remaining1 = stream1.hasBytesAvailable
        let remaining2 = stream2.hasBytesAvailable
        return !remaining1 && !remaining2
    }

    // MARK: - Helpers

    private func fileSize(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return -1 }
        return size
    }

    private func makeFailedResult(mapping: FileSafeFileMapping, error: String, retries: Int) -> FileSafeCopyResult {
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

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_073_741_824 {
            return String(format: "%.1f GB/s", bytesPerSecond / 1_073_741_824)
        } else if bytesPerSecond >= 1_048_576 {
            return String(format: "%.0f MB/s", bytesPerSecond / 1_048_576)
        } else if bytesPerSecond >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1024)
        }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    private func formatTime(_ seconds: Double) -> String {
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

// MARK: - Speed Tracker

private class SpeedTracker {
    private var samples: [(time: Date, bytes: Int64)] = []
    private let windowSize: TimeInterval = 5 // 5 seconden rolling window

    func addSample(bytes: Int64) {
        let now = Date()
        samples.append((time: now, bytes: bytes))
        samples.removeAll { now.timeIntervalSince($0.time) > windowSize }
    }

    var bytesPerSecond: Double {
        guard samples.count >= 2,
              let first = samples.first,
              let last = samples.last else { return 0 }

        let elapsed = last.time.timeIntervalSince(first.time)
        guard elapsed > 0 else { return 0 }

        let totalBytes = samples.reduce(Int64(0)) { $0 + $1.bytes }
        return Double(totalBytes) / elapsed
    }
}

// MARK: - Log schrijven

extension FileSafeCopyEngine {
    static func writeLog(_ report: FileSafeCopyReport, to projectPath: String) throws {
        let logURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".filesafe-log.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(report)
        try data.write(to: logURL, options: .atomic)
    }
}
