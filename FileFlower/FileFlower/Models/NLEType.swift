import Foundation

/// Ondersteunde NLE (Non-Linear Editor) applicaties
enum NLEType: String, Codable, CaseIterable {
    case premiere = "premiere"
    case resolve = "resolve"

    var displayName: String {
        switch self {
        case .premiere: return "Premiere Pro"
        case .resolve: return "DaVinci Resolve"
        }
    }

    var icon: String {
        switch self {
        case .premiere: return "film.fill"
        case .resolve: return "film.stack.fill"
        }
    }

    /// Project bestandsextensie voor deze NLE
    var projectExtension: String {
        switch self {
        case .premiere: return "prproj"
        case .resolve: return "drp"
        }
    }

    /// Terminologie: "Bin" in Premiere, "Folder" in Resolve Media Pool
    var containerTerm: String {
        switch self {
        case .premiere: return "Bin"
        case .resolve: return "Folder"
        }
    }

    /// Detecteer NLE type op basis van project bestandsextensie of virtueel pad
    static func from(projectPath: String) -> NLEType? {
        // Virtuele Resolve paden (database-backed projecten zonder .drp op disk)
        if projectPath.hasPrefix("/resolve-project/") {
            return .resolve
        }
        let ext = URL(fileURLWithPath: projectPath).pathExtension.lowercased()
        switch ext {
        case "prproj": return .premiere
        case "drp": return .resolve
        default: return nil
        }
    }
}
