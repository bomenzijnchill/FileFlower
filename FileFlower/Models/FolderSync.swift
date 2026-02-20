import Foundation

/// Representeert een folder sync configuratie die een lokale map koppelt aan een Premiere project
struct FolderSync: Codable, Identifiable, Equatable {
    var id: UUID
    var folderPath: String          // Bron map om te monitoren
    var projectPath: String         // Gekoppeld Premiere project (.prproj pad)
    var premiereBinRoot: String     // Root bin in Premiere (bijv. "05_Footage")
    var isEnabled: Bool             // Sync aan/uit
    var lastSyncDate: Date?         // Laatste sync timestamp
    var syncedFileHashes: Set<String> // Hashes van al gesyncte bestanden (voor duplicate detection)
    
    init(
        id: UUID = UUID(),
        folderPath: String,
        projectPath: String,
        premiereBinRoot: String = "",
        isEnabled: Bool = true,
        lastSyncDate: Date? = nil,
        syncedFileHashes: Set<String> = []
    ) {
        self.id = id
        self.folderPath = folderPath
        self.projectPath = projectPath
        self.premiereBinRoot = premiereBinRoot
        self.isEnabled = isEnabled
        self.lastSyncDate = lastSyncDate
        self.syncedFileHashes = syncedFileHashes
    }
    
    /// Geeft de naam van de map terug (voor display)
    var folderName: String {
        URL(fileURLWithPath: folderPath).lastPathComponent
    }
    
    /// Geeft de naam van het project terug (voor display)
    var projectName: String {
        URL(fileURLWithPath: projectPath).deletingPathExtension().lastPathComponent
    }
    
    /// Controleert of de map nog bestaat
    var folderExists: Bool {
        FileManager.default.fileExists(atPath: folderPath)
    }
    
    /// Controleert of het project nog bestaat
    var projectExists: Bool {
        FileManager.default.fileExists(atPath: projectPath)
    }
}

/// Status van een folder sync operatie
enum FolderSyncStatus: Equatable {
    case idle
    case syncing(progress: Double, currentFile: String)
    case completed(fileCount: Int)
    case error(message: String)
    
    var displayName: String {
        switch self {
        case .idle:
            return "Wachtend"
        case .syncing(_, let file):
            return "Syncing: \(file)"
        case .completed(let count):
            return "\(count) bestanden gesynct"
        case .error(let message):
            return "Fout: \(message)"
        }
    }
}



