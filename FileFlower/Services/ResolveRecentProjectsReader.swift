import Foundation

/// Leest recent geopende DaVinci Resolve projecten op deze Mac via Spotlight
class ResolveRecentProjectsReader {

    /// Haal paden op van .drp bestanden die recent geopend zijn op deze Mac
    /// Gebruikt Spotlight (mdfind) om bestanden te vinden met kMDItemLastUsedDate
    static func getRecentProjectPaths(maxAge: TimeInterval = 90 * 24 * 3600) -> Set<String> {
        var paths = Set<String>()

        // Gebruik mdfind om .drp bestanden te vinden die recent geopend zijn
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemFSName == '*.drp' && kMDItemLastUsedDate >= $time.today(-90)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: "\n")
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    // Filter auto-save bestanden uit
                    if trimmed.contains("Auto-Save") || trimmed.contains("Backup") { continue }
                    paths.insert(trimmed)
                }
            }
        } catch {
            #if DEBUG
            print("ResolveRecentProjectsReader: mdfind fout: \(error)")
            #endif
        }

        return paths
    }

    /// Converteer Spotlight-gevonden paden naar ProjectInfo objecten
    /// Leidt rootPath af als grandparent van het .drp bestand (zelfde conventie als Premiere projecten)
    static func getRecentProjects(limit: Int = 5) -> [ProjectInfo] {
        let paths = getRecentProjectPaths()
        let fileManager = FileManager.default

        var projects: [ProjectInfo] = []
        for path in paths {
            let url = URL(fileURLWithPath: path)

            // Sla over als bestand niet meer bestaat (verouderde Spotlight index)
            guard fileManager.fileExists(atPath: path) else { continue }

            let name = url.deletingPathExtension().lastPathComponent
            // rootPath = grandparent directory (zelfde als handleActiveProjectChange)
            let rootPath = url.deletingLastPathComponent().deletingLastPathComponent().path

            let lastModified: TimeInterval
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date {
                lastModified = modDate.timeIntervalSince1970
            } else {
                lastModified = Date().timeIntervalSince1970
            }

            let project = ProjectInfo(
                name: name,
                rootPath: rootPath,
                projectPath: path,
                lastModified: lastModified
            )
            projects.append(project)
        }

        // Sorteer op lastModified aflopend
        projects.sort { $0.lastModified > $1.lastModified }
        return Array(projects.prefix(limit))
    }

    /// Check of een pad op een netwerkvolume staat
    static func isNetworkPath(_ path: String) -> Bool {
        return path.hasPrefix("/Volumes/")
    }
}
