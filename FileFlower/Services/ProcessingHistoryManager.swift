import Foundation

/// Een record van een verwerkt item (download die is verplaatst/geïmporteerd)
struct HistoryItem: Codable, Identifiable {
    let id: UUID
    let filename: String
    let assetType: AssetType
    let sourcePath: String
    let destinationPath: String?
    let targetProject: String?
    let timestamp: Date
    let status: ItemStatus
    let isFolder: Bool
    let fileCount: Int

    init(
        id: UUID = UUID(),
        filename: String,
        assetType: AssetType,
        sourcePath: String,
        destinationPath: String? = nil,
        targetProject: String? = nil,
        timestamp: Date = Date(),
        status: ItemStatus,
        isFolder: Bool = false,
        fileCount: Int = 1
    ) {
        self.id = id
        self.filename = filename
        self.assetType = assetType
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.targetProject = targetProject
        self.timestamp = timestamp
        self.status = status
        self.isFolder = isFolder
        self.fileCount = fileCount
    }
}

/// Manager voor opslaan en ophalen van verwerkingsgeschiedenis.
/// Slaat verwerkte items op als JSON, wordt dagelijks geleegd.
class ProcessingHistoryManager {
    static let shared = ProcessingHistoryManager()

    private let maxRecords = 500
    private var records: [HistoryItem] = []
    private let fileURL: URL

    private init() {
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let fileFlowerDir = appSupportDir.appendingPathComponent("FileFlower", isDirectory: true)

        // Zorg dat directory bestaat
        try? FileManager.default.createDirectory(at: fileFlowerDir, withIntermediateDirectories: true)

        fileURL = fileFlowerDir.appendingPathComponent("processing_history.json")
        loadFromDisk()
        cleanupOldRecords()
    }

    // MARK: - Public API

    /// Sla een verwerkt item op in de geschiedenis
    func record(item: DownloadItem) {
        let filename = URL(fileURLWithPath: item.path).lastPathComponent

        // Bepaal of het een map is
        var isDir: ObjCBool = false
        let isFolder = FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) && isDir.boolValue

        // Tel bestanden in map
        var fileCount = 1
        if isFolder {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: item.path) {
                fileCount = contents.count
            }
        }

        let historyItem = HistoryItem(
            filename: filename,
            assetType: item.predictedType,
            sourcePath: item.path,
            destinationPath: item.targetPath,
            targetProject: item.targetProject?.name,
            status: item.status,
            isFolder: isFolder,
            fileCount: fileCount
        )

        records.append(historyItem)

        // Prune als we boven max zitten
        if records.count > maxRecords {
            records = Array(records.suffix(maxRecords))
        }

        saveToDisk()

        print("ProcessingHistory: Item opgeslagen - \(filename) (\(item.status.rawValue))")
    }

    /// Haal alle records van vandaag op
    func todayRecords() -> [HistoryItem] {
        let calendar = Calendar.current
        return records.filter { calendar.isDateInToday($0.timestamp) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Verwijder records ouder dan vandaag
    func cleanupOldRecords() {
        let calendar = Calendar.current
        let before = records.count
        records = records.filter { calendar.isDateInToday($0.timestamp) }
        let removed = before - records.count

        if removed > 0 {
            saveToDisk()
            print("ProcessingHistory: \(removed) oude records verwijderd")
        }
    }

    /// Alle records ophalen
    func allRecords() -> [HistoryItem] {
        return records
    }

    /// Aantal records
    var count: Int { records.count }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            records = try JSONDecoder().decode([HistoryItem].self, from: data)
            print("ProcessingHistory: \(records.count) records geladen")
        } catch {
            print("ProcessingHistory: Fout bij laden: \(error.localizedDescription)")
            records = []
        }
    }

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("ProcessingHistory: Fout bij opslaan: \(error.localizedDescription)")
        }
    }
}
