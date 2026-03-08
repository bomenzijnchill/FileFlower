import Foundation

class ConfigManager {
    static let shared = ConfigManager()
    
    private let configURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FileFlower", isDirectory: true)
        let oldAppDir = appSupport.appendingPathComponent("DLtoPremiere", isDirectory: true)

        // Migratie: hernoem oude DLtoPremiere map naar FileFlower
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: oldAppDir.path) && !fileManager.fileExists(atPath: appDir.path) {
            do {
                try fileManager.moveItem(at: oldAppDir, to: appDir)
                #if DEBUG
                print("ConfigManager: Config gemigreerd van DLtoPremiere naar FileFlower")
                #endif
            } catch {
                #if DEBUG
                print("ConfigManager: Migratie gefaald: \(error), nieuwe map wordt aangemaakt")
                #endif
                try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
            }
        } else {
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        }

        configURL = appDir.appendingPathComponent("config.json")
    }
    
    func load() -> Config? {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return nil
        }
        
        guard let data = try? Data(contentsOf: configURL) else {
            return nil
        }
        
        return try? JSONDecoder().decode(Config.self, from: data)
    }
    
    func save(_ config: Config) {
        guard let data = try? JSONEncoder().encode(config) else {
            return
        }
        
        try? data.write(to: configURL)
    }
}

