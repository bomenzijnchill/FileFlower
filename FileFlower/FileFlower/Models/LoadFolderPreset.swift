import Foundation

/// Preset voor een veelgebruikte map die snel in een Premiere project geladen kan worden
struct LoadFolderPreset: Codable, Identifiable, Equatable {
    var id: UUID
    var folderPath: String        // Pad naar de map op disk
    var displayName: String       // Weergavenaam in de UI
    var premiereBinPath: String?  // Optioneel doelbin in Premiere
    var createdAt: Date

    init(
        id: UUID = UUID(),
        folderPath: String,
        displayName: String,
        premiereBinPath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.folderPath = folderPath
        self.displayName = displayName
        self.premiereBinPath = premiereBinPath
        self.createdAt = createdAt
    }

    /// Of de map nog bestaat op disk
    var folderExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: folderPath, isDirectory: &isDir) && isDir.boolValue
    }

    /// Mapnaam van het pad
    var folderName: String {
        URL(fileURLWithPath: folderPath).lastPathComponent
    }
}
