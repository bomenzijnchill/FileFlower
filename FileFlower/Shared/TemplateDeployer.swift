import Foundation

/// Service voor het deployen van mappenstructuren naar een target directory.
/// Gebruikt door zowel de hoofdapp als de Finder Sync Extension.
class TemplateDeployer {

    /// Standaard mappenstructuur voor video editing projecten
    static let standardTemplate: [(name: String, children: [String])] = [
        ("03_Audio", ["01_Music", "02_VO"]),
        ("04_SFX", []),
        ("04_Visuals", ["01_Graphics", "02_MotionGraphics", "03_Stills"]),
        ("05_VFX", [])
    ]

    enum DeployError: LocalizedError {
        case noConfigAvailable
        case invalidTargetDirectory
        case folderCreationFailed(String)

        var errorDescription: String? {
            switch self {
            case .noConfigAvailable:
                return "No folder template configuration available"
            case .invalidTargetDirectory:
                return "Target directory is not valid or does not exist"
            case .folderCreationFailed(let path):
                return "Failed to create folder: \(path)"
            }
        }
    }

    /// Deploy de mappenstructuur in de opgegeven directory.
    /// - Parameters:
    ///   - targetDirectory: De map waarin de structuur aangemaakt wordt
    ///   - config: DeployConfig met de actieve preset en optionele custom template
    /// - Returns: Aantal nieuw aangemaakte mappen
    static func deploy(to targetDirectory: URL, config: DeployConfig) throws -> Int {
        let fileManager = FileManager.default

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: targetDirectory.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw DeployError.invalidTargetDirectory
        }

        switch config.folderStructurePreset {
        case .standard:
            return try deployStandardTemplate(to: targetDirectory)
        case .custom:
            if let template = config.customFolderTemplate {
                return try deployCustomTemplate(to: targetDirectory, template: template)
            } else {
                // Geen custom template opgeslagen, val terug op standaard
                return try deployStandardTemplate(to: targetDirectory)
            }
        case .flat:
            // Flat preset: geen mappen nodig
            return 0
        }
    }

    // MARK: - Standard Template

    private static func deployStandardTemplate(to directory: URL) throws -> Int {
        let fileManager = FileManager.default
        var count = 0

        for folder in standardTemplate {
            let folderURL = directory.appendingPathComponent(folder.name, isDirectory: true)
            if !fileManager.fileExists(atPath: folderURL.path) {
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                count += 1
            }

            for child in folder.children {
                let childURL = folderURL.appendingPathComponent(child, isDirectory: true)
                if !fileManager.fileExists(atPath: childURL.path) {
                    try fileManager.createDirectory(at: childURL, withIntermediateDirectories: true)
                    count += 1
                }
            }
        }

        return count
    }

    // MARK: - Custom Template

    private static func deployCustomTemplate(to directory: URL, template: CustomFolderTemplate) throws -> Int {
        let fileManager = FileManager.default
        var count = 0

        // De folderTree root node is de source-map naam.
        // We maken alleen de children aan, niet de root zelf.
        func createTree(_ node: FolderNode, in parent: URL) throws {
            for child in node.children {
                let childURL = parent.appendingPathComponent(child.name, isDirectory: true)
                if !fileManager.fileExists(atPath: childURL.path) {
                    try fileManager.createDirectory(at: childURL, withIntermediateDirectories: true)
                    count += 1
                }
                try createTree(child, in: childURL)
            }
        }

        try createTree(template.folderTree, in: directory)
        return count
    }
}
