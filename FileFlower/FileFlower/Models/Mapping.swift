import Foundation

struct Mapping: Codable {
    let projectPath: String
    let finderPath: String
    let premiereBinPath: String
    let createdAt: TimeInterval
    
    init(projectPath: String, finderPath: String, premiereBinPath: String, createdAt: TimeInterval = Date().timeIntervalSince1970) {
        self.projectPath = projectPath
        self.finderPath = finderPath
        self.premiereBinPath = premiereBinPath
        self.createdAt = createdAt
    }
}

