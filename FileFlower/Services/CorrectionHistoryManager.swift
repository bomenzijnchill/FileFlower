import Foundation

/// Een record van een user-correctie op een classificatie
struct CorrectionRecord: Codable, Identifiable {
    let id: UUID
    let filename: String              // Originele bestandsnaam
    let fileExtension: String         // bijv. "wav", "mp4"
    let detectedSource: DetectedSource?
    let metadataSummary: String?      // Compact: "duration:45s, bpm:120"
    let originalPrediction: AssetType // Wat het systeem voorspelde
    let correctedType: AssetType      // Wat de gebruiker koos
    let correctedAt: Date
    let originUrl: String?

    init(
        id: UUID = UUID(),
        filename: String,
        fileExtension: String,
        detectedSource: DetectedSource?,
        metadataSummary: String?,
        originalPrediction: AssetType,
        correctedType: AssetType,
        correctedAt: Date = Date(),
        originUrl: String? = nil
    ) {
        self.id = id
        self.filename = filename
        self.fileExtension = fileExtension
        self.detectedSource = detectedSource
        self.metadataSummary = metadataSummary
        self.originalPrediction = originalPrediction
        self.correctedType = correctedType
        self.correctedAt = correctedAt
        self.originUrl = originUrl
    }
}

/// Manager voor opslaan en ophalen van user correcties op classificaties.
/// Wordt gebruikt voor few-shot learning in de Claude API prompt.
class CorrectionHistoryManager {
    static let shared = CorrectionHistoryManager()

    private let maxRecords = 200
    private var records: [CorrectionRecord] = []
    private let fileURL: URL

    private init() {
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let fileFlowerDir = appSupportDir.appendingPathComponent("FileFlower", isDirectory: true)

        // Zorg dat directory bestaat
        try? FileManager.default.createDirectory(at: fileFlowerDir, withIntermediateDirectories: true)

        fileURL = fileFlowerDir.appendingPathComponent("correction_history.json")
        loadFromDisk()
    }

    // MARK: - Public API

    /// Sla een correctie op wanneer de gebruiker het type wijzigt
    func recordCorrection(item: DownloadItem, originalType: AssetType, correctedType: AssetType) {
        guard originalType != correctedType else { return }

        let filename = URL(fileURLWithPath: item.path).lastPathComponent
        let ext = URL(fileURLWithPath: item.path).pathExtension.lowercased()

        let record = CorrectionRecord(
            filename: filename,
            fileExtension: ext,
            detectedSource: item.detectedSource,
            metadataSummary: buildMetadataSummary(item.metadata),
            originalPrediction: originalType,
            correctedType: correctedType,
            originUrl: item.originUrl
        )

        records.append(record)

        // Prune als we boven max zitten
        if records.count > maxRecords {
            records = Array(records.suffix(maxRecords))
        }

        saveToDisk()

        // Track analytics event
        AnalyticsService.shared.track(
            AnalyticsEvent.classificationCorrected(
                originalType: originalType.rawValue,
                correctedType: correctedType.rawValue,
                source: item.detectedSource?.rawValue ?? "Unknown"
            )
        )

        print("CorrectionHistory: Correctie opgeslagen - \(originalType.rawValue) → \(correctedType.rawValue) voor \(filename)")
    }

    /// Haal relevante voorbeelden op voor few-shot prompting
    /// Prioriteert: zelfde source + extensie > zelfde source > zelfde extensie > recent
    func relevantExamples(for filename: String, source: DetectedSource?, limit: Int = 10) -> [CorrectionRecord] {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()

        // Score elke record op relevantie
        var scored: [(record: CorrectionRecord, score: Int)] = records.map { record in
            var score = 0

            // Zelfde bron + extensie = meest relevant
            if record.detectedSource == source && record.fileExtension == ext {
                score += 4
            } else if record.detectedSource == source {
                score += 2
            } else if record.fileExtension == ext {
                score += 1
            }

            return (record, score)
        }

        // Sorteer op score (hoog → laag), dan op datum (recent → oud)
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.record.correctedAt > b.record.correctedAt
        }

        // Dedupliceer op (originalPrediction, correctedType) combinatie
        var seen: Set<String> = []
        var result: [CorrectionRecord] = []

        for item in scored {
            let key = "\(item.record.originalPrediction.rawValue)->\(item.record.correctedType.rawValue)"
            if !seen.contains(key) {
                seen.insert(key)
                result.append(item.record)
            }
            if result.count >= limit { break }
        }

        return result
    }

    /// Alle records ophalen (voor debug/UI)
    func allRecords() -> [CorrectionRecord] {
        return records
    }

    /// Aantal correcties
    var count: Int { records.count }

    // MARK: - Metadata Summary Builder

    private func buildMetadataSummary(_ metadata: DownloadMetadata?) -> String? {
        guard let meta = metadata else { return nil }

        var parts: [String] = []
        if let duration = meta.duration { parts.append("duration:\(duration)s") }
        if let bpm = meta.bpm { parts.append("bpm:\(bpm)") }
        if let key = meta.key { parts.append("key:\(key)") }
        if let artist = meta.artist, !artist.isEmpty { parts.append("artist:\(artist)") }
        if let genre = meta.genre, !genre.isEmpty { parts.append("genre:\(genre)") }
        if !meta.tags.isEmpty { parts.append("tags:\(meta.tags.prefix(3).joined(separator: ","))") }

        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            records = try JSONDecoder().decode([CorrectionRecord].self, from: data)
            print("CorrectionHistory: \(records.count) correcties geladen")
        } catch {
            print("CorrectionHistory: Fout bij laden: \(error.localizedDescription)")
            records = []
        }
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("CorrectionHistory: Fout bij opslaan: \(error.localizedDescription)")
        }
    }
}
