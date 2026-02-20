import Foundation

// MARK: - Gedeelde types tussen FileFlower en FileFlowerFinderSync

enum FolderStructurePreset: String, Codable, CaseIterable {
    case standard = "standard"
    case flat = "flat"
    case custom = "custom"

    var displayKey: String.LocalizationValue {
        switch self {
        case .standard: return "workflow.folder.standard"
        case .flat: return "workflow.folder.flat"
        case .custom: return "workflow.folder.custom"
        }
    }

    var descriptionKey: String.LocalizationValue {
        switch self {
        case .standard: return "workflow.folder.standard.desc"
        case .flat: return "workflow.folder.flat.desc"
        case .custom: return "workflow.folder.custom.desc"
        }
    }
}

/// Een map-node in de gescande template boom
struct FolderNode: Codable, Identifiable {
    let id: UUID
    let name: String               // bijv. "03_Audio"
    let relativePath: String       // bijv. "03_Audio/01_Music"
    let children: [FolderNode]

    init(id: UUID = UUID(), name: String, relativePath: String, children: [FolderNode] = []) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.children = children
    }
}

/// AI-gegenereerde mapping van AssetType naar relatief pad
struct FolderTypeMapping: Codable {
    var musicPath: String?
    var sfxPath: String?
    var voPath: String?
    var graphicsPath: String?
    var motionGraphicsPath: String?
    var stockFootagePath: String?
    var description: String?
    var analyzedAt: Date?

    /// Geeft het pad voor een AssetType, of nil als niet gevonden
    func path(for assetType: String) -> String? {
        switch assetType {
        case "Music": return musicPath
        case "SFX": return sfxPath
        case "VO": return voPath
        case "Graphic": return graphicsPath
        case "MotionGraphic": return motionGraphicsPath
        case "StockFootage": return stockFootagePath
        default: return nil
        }
    }
}

/// Volledige custom folder template met boom + AI mapping
struct CustomFolderTemplate: Codable {
    var sourcePath: String
    var folderTree: FolderNode
    var mapping: FolderTypeMapping
    var createdAt: Date
    var lastUpdatedAt: Date
}

/// Lichtgewicht config voor de Finder Sync Extension
struct DeployConfig: Codable {
    let folderStructurePreset: FolderStructurePreset
    let customFolderTemplate: CustomFolderTemplate?
}
