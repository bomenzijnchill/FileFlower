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

    init(
        id: UUID = UUID(),
        projectPath: String,
        finderTargetDir: String,
        premiereBinPath: String,
        files: [String],
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        syncId: UUID? = nil,
        pendingHashes: [String] = [],
        assetType: String? = nil
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

