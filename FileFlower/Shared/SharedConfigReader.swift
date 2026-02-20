import Foundation

/// Leest en schrijft DeployConfig naar een gedeelde locatie op disk.
/// Gebruikt door zowel de hoofdapp (schrijven) als de Finder Sync Extension (lezen).
///
/// De hoofdapp schrijft naar TWEE locaties:
/// 1. ~/Library/Application Support/FileFlower/ (eigen locatie)
/// 2. De container van de Finder Sync Extension
///    (zodat de sandboxed extension erbij kan)
///
/// De extension leest gewoon uit z'n eigen Application Support (wat door de container
/// automatisch naar locatie 2 verwijst).
class SharedConfigReader {
    private static let deployConfigFilename = "deploy_config.json"
    private static let extensionBundleId = "com.fileflower.app.FileFlowerFinderSync"

    /// Directory in de extension container (gebruikt door de hoofdapp om te schrijven)
    private static var extensionContainerDirectory: URL {
        let home = NSHomeDirectory()
        let containerPath = "\(home)/Library/Containers/\(extensionBundleId)/Data/Library/Application Support/FileFlower"
        return URL(fileURLWithPath: containerPath)
    }

    /// Eigen Application Support directory (container-aware)
    private static var appSupportDirectory: URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return appSupport.appendingPathComponent("FileFlower", isDirectory: true)
    }

    /// Lees de DeployConfig — leest uit eigen Application Support
    /// (voor de extension wijst dit automatisch naar z'n container)
    static func loadDeployConfig() -> DeployConfig? {
        guard let directory = appSupportDirectory else {
            print("SharedConfigReader: Cannot determine app support directory")
            return nil
        }

        let configURL = directory.appendingPathComponent(deployConfigFilename)
        print("SharedConfigReader: Loading from \(configURL.path)")

        guard FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL) else {
            print("SharedConfigReader: No deploy config found at \(configURL.path)")
            return nil
        }

        do {
            let decoder = JSONDecoder()
            let config = try decoder.decode(DeployConfig.self, from: data)
            print("SharedConfigReader: Loaded deploy config (preset: \(config.folderStructurePreset.rawValue), hasTemplate: \(config.customFolderTemplate != nil))")
            return config
        } catch {
            print("SharedConfigReader: Failed to decode deploy config: \(error)")
            return nil
        }
    }

    /// Schrijf de DeployConfig — schrijft naar eigen locatie EN naar de extension container
    static func saveDeployConfig(_ config: DeployConfig) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(config) else {
            print("SharedConfigReader: Failed to encode deploy config")
            return
        }

        // 1. Schrijf naar eigen Application Support
        if let appDir = appSupportDirectory {
            writeConfig(data: data, to: appDir)
        }

        // 2. Schrijf ook naar de extension container (zodat de sandboxed extension erbij kan)
        let containerDir = extensionContainerDirectory
        writeConfig(data: data, to: containerDir)
    }

    private static func writeConfig(data: Data, to directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let configURL = directory.appendingPathComponent(deployConfigFilename)
            try data.write(to: configURL, options: .atomic)
            print("SharedConfigReader: Deploy config saved to \(configURL.path)")
        } catch {
            print("SharedConfigReader: Failed to save to \(directory.path): \(error)")
        }
    }
}
