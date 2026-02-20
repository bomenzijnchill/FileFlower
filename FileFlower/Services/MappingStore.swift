import Foundation

class MappingStore {
    static let shared = MappingStore()
    
    private let configManager = ConfigManager.shared
    
    func getMapping(projectPath: String, finderPath: String) -> String? {
        let config = AppState.shared.config
        guard let projectMapping = config.mappings[projectPath] else {
            return nil
        }
        
        // Find matching finder path
        for (finder, premiere) in projectMapping.finderToPremiere {
            if finderPath.hasPrefix(finder) || finderPath.contains(finder) {
                return premiere
            }
        }
        
        return nil
    }
    
    func setMapping(projectPath: String, finderPath: String, premiereBinPath: String) {
        var config = AppState.shared.config
        
        if config.mappings[projectPath] == nil {
            config.mappings[projectPath] = ProjectMapping()
        }
        
        config.mappings[projectPath]?.finderToPremiere[finderPath] = premiereBinPath
        AppState.shared.config = config
        AppState.shared.saveConfig()
    }
    
    func removeMapping(projectPath: String, finderPath: String) {
        var config = AppState.shared.config
        config.mappings[projectPath]?.finderToPremiere.removeValue(forKey: finderPath)
        AppState.shared.config = config
        AppState.shared.saveConfig()
    }
}

