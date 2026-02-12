import Foundation

struct JobRequest: Codable {
    let id: UUID
    let projectPath: String
    let finderTargetDir: String
    let premiereBinPath: String
    let files: [String]
    let createdAt: TimeInterval
    
    init(
        id: UUID = UUID(),
        projectPath: String,
        finderTargetDir: String,
        premiereBinPath: String,
        files: [String],
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.projectPath = projectPath
        self.finderTargetDir = finderTargetDir
        self.premiereBinPath = premiereBinPath
        self.files = files
        self.createdAt = createdAt
    }
}

struct JobResult: Codable {
    let jobId: UUID
    let success: Bool
    let importedFiles: [String]
    let failedFiles: [String]
    let error: String?
}

