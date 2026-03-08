import Foundation

struct JobRequest: Codable {
    let id: UUID
    let projectPath: String
    let finderTargetDir: String
    let premiereBinPath: String
    let files: [String]
    let createdAt: TimeInterval
    let syncId: UUID?
    let pendingHashes: [String]
    let assetType: String?
    let nleType: NLEType

    enum CodingKeys: String, CodingKey {
        case id, projectPath, finderTargetDir, premiereBinPath, files
        case createdAt, syncId, pendingHashes, assetType, nleType
    }

    init(
        id: UUID = UUID(),
        projectPath: String,
        finderTargetDir: String,
        premiereBinPath: String,
        files: [String],
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        syncId: UUID? = nil,
        pendingHashes: [String] = [],
        assetType: String? = nil,
        nleType: NLEType = .premiere
    ) {
        self.id = id
        self.projectPath = projectPath
        self.finderTargetDir = finderTargetDir
        self.premiereBinPath = premiereBinPath
        self.files = files
        self.createdAt = createdAt
        self.syncId = syncId
        self.pendingHashes = pendingHashes
        self.assetType = assetType
        self.nleType = nleType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        projectPath = try container.decode(String.self, forKey: .projectPath)
        finderTargetDir = try container.decode(String.self, forKey: .finderTargetDir)
        premiereBinPath = try container.decode(String.self, forKey: .premiereBinPath)
        files = try container.decode([String].self, forKey: .files)
        createdAt = try container.decode(TimeInterval.self, forKey: .createdAt)
        syncId = try container.decodeIfPresent(UUID.self, forKey: .syncId)
        pendingHashes = try container.decodeIfPresent([String].self, forKey: .pendingHashes) ?? []
        assetType = try container.decodeIfPresent(String.self, forKey: .assetType)
        nleType = try container.decodeIfPresent(NLEType.self, forKey: .nleType) ?? .premiere
    }
}

struct JobResult: Codable {
    let jobId: UUID
    let success: Bool
    let importedFiles: [String]
    let failedFiles: [String]
    let error: String?
    let alreadyImported: [String]?
}

