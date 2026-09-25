import Foundation

/// Centrale veiligheidsgrens voor bestandsplaatsing.
///
/// Eén canonieke definitie van NLE-cache/systeem-mappen waarin NOOIT assets geplaatst,
/// gematcht of geleerd mogen worden. Elke laag van het plaatsingssysteem gebruikt deze
/// policy: mapnaam-matching (PathResolver), evidence-scanning (PlacementEngine),
/// structure-learning (ProjectStructureScanner), AI-input/output (FolderTemplateService)
/// én de laatste guard vóór iedere fysieke schrijfactie (FileProcessor).
enum PathSafetyPolicy {

    /// Substring-patronen op de genormaliseerde (lowercase) mapnaam.
    /// "Adobe Premiere Pro Audio Previews", "Premiere Auto-Save" etc. matchen hierop.
    static let blockedNamePatterns: [String] = [
        // Adobe Premiere Pro caches (staan naast het .prproj bestand)
        "adobe premiere pro",
        "premiere auto-save",
        "premiere pro auto-save",
        "audio previews",
        "video previews",
        "preview files",
        "media cache",
        "peak files",
        "motion graphics template media",
        "auto-save",
        "autosave",
        // After Effects
        "adobe after effects",
        "disk cache",
        // DaVinci Resolve
        "cacheclip",
        "gallery stills",
        "capture scratch",
        // Systeem / development
        "node_modules",
        ".git",
        ".trash",
    ]

    /// Check of een mapnaam een geblokkeerde cache/systeem-map is.
    static func isBlockedFolderName(_ name: String) -> Bool {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        if normalized.hasPrefix(".") { return true }
        for pattern in blockedNamePatterns {
            if normalized.contains(pattern) {
                return true
            }
        }
        return false
    }

    /// Vind de eerste geblokkeerde component in een pad, of nil als het pad veilig is.
    static func firstBlockedComponent(in path: String) -> String? {
        for component in path.split(separator: "/") {
            if isBlockedFolderName(String(component)) {
                return String(component)
            }
        }
        return nil
    }

    /// Valideer een schrijfdoel (map waarin een bestand geplaatst of aangemaakt gaat worden).
    /// - Parameters:
    ///   - directory: De doelmap.
    ///   - projectMainFolder: Optioneel — als bekend, moet het doel hierbinnen liggen.
    /// - Throws: `PathSafetyError` wanneer het doel in een cache-map ligt of buiten het project valt.
    static func validateWriteTarget(_ directory: URL, projectMainFolder: URL?) throws {
        if let blocked = firstBlockedComponent(in: directory.path) {
            throw PathSafetyError.blockedComponent(blocked)
        }

        if let root = projectMainFolder {
            let rootPath = root.standardizedFileURL.path
            let targetPath = directory.standardizedFileURL.path
            if targetPath != rootPath && !targetPath.hasPrefix(rootPath + "/") {
                throw PathSafetyError.outsideProject(rootPath)
            }
        }
    }
}

enum PathSafetyError: LocalizedError, Equatable {
    /// Doelpad bevat een NLE-cache of systeem-map.
    case blockedComponent(String)
    /// Doelpad ligt buiten de projectmap.
    case outsideProject(String)

    var errorDescription: String? {
        switch self {
        case .blockedComponent(let name):
            return "Doelmap ligt in een cache-map (\"\(name)\") — plaatsing geblokkeerd"
        case .outsideProject(let root):
            return "Doelmap ligt buiten de projectmap (\(root)) — plaatsing geblokkeerd"
        }
    }
}
