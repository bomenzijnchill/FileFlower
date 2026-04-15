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
    var children: [FolderNode]

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
    var rawFootagePath: String?
    var photoPath: String?
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
        case "RawFootage": return rawFootagePath
        case "Photo": return photoPath
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

// MARK: - Post Haste-stijl template systeem

/// Type van een template-parameter — bepaalt hoe het invoerveld er bij project-creatie uitziet
enum TemplateParamType: String, Codable {
    case text
    case number
}

/// Een door de gebruiker gedefinieerde parameter binnen een template.
/// Wordt in mapnamen gebruikt als `[Title]`-placeholder.
struct TemplateParameter: Codable, Identifiable {
    let id: UUID
    var title: String            // Wat als token gebruikt wordt: "[Project Name]"
    var type: TemplateParamType
    var defaultValue: String
    var folderBreak: Bool        // Waarde "A/B" expandeert naar nested mappen A/B
    var cannotBeEmpty: Bool

    init(id: UUID = UUID(),
         title: String,
         type: TemplateParamType = .text,
         defaultValue: String = "",
         folderBreak: Bool = false,
         cannotBeEmpty: Bool = false) {
        self.id = id
        self.title = title
        self.type = type
        self.defaultValue = defaultValue
        self.folderBreak = folderBreak
        self.cannotBeEmpty = cannotBeEmpty
    }
}

/// Een benoemde folder-template met boom, AI-mapping en parameters.
/// Meerdere templates worden in Config.folderTemplates opgeslagen; één kan de default zijn.
struct FolderStructureTemplate: Codable, Identifiable {
    let id: UUID
    var name: String
    var folderTree: FolderNode           // folderNode.name mag "[Param]" tokens bevatten
    var parameters: [TemplateParameter]
    var mapping: FolderTypeMapping
    var sourcePath: String?              // Pad van originele scan (nil bij from-scratch / duplicate)
    var createdAt: Date
    var lastUpdatedAt: Date

    init(id: UUID = UUID(),
         name: String,
         folderTree: FolderNode,
         parameters: [TemplateParameter] = [],
         mapping: FolderTypeMapping = FolderTypeMapping(),
         sourcePath: String? = nil,
         createdAt: Date = Date(),
         lastUpdatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.folderTree = folderTree
        self.parameters = parameters
        self.mapping = mapping
        self.sourcePath = sourcePath
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
    }
}

/// Lichtgewicht config voor de Finder Sync Extension
struct DeployConfig: Codable {
    let folderStructurePreset: FolderStructurePreset
    let customFolderTemplate: CustomFolderTemplate?
    let activeTemplate: FolderStructureTemplate?         // Gebruikt als defaultTemplateId gezet is
    let resolvedParameters: [String: String]?            // Reeds ingevulde parameters (placeholder → value)

    init(folderStructurePreset: FolderStructurePreset,
         customFolderTemplate: CustomFolderTemplate? = nil,
         activeTemplate: FolderStructureTemplate? = nil,
         resolvedParameters: [String: String]? = nil) {
        self.folderStructurePreset = folderStructurePreset
        self.customFolderTemplate = customFolderTemplate
        self.activeTemplate = activeTemplate
        self.resolvedParameters = resolvedParameters
    }

    // Custom decoder: nieuwe velden zijn optioneel voor backwards-compat
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        folderStructurePreset = try container.decode(FolderStructurePreset.self, forKey: .folderStructurePreset)
        customFolderTemplate = try container.decodeIfPresent(CustomFolderTemplate.self, forKey: .customFolderTemplate)
        activeTemplate = try container.decodeIfPresent(FolderStructureTemplate.self, forKey: .activeTemplate)
        resolvedParameters = try container.decodeIfPresent([String: String].self, forKey: .resolvedParameters)
    }

    enum CodingKeys: String, CodingKey {
        case folderStructurePreset
        case customFolderTemplate
        case activeTemplate
        case resolvedParameters
    }
}

