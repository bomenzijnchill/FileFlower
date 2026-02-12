import Foundation

/// Leest recent geopende Premiere Pro projecten op deze Mac via Spotlight
class PremiereRecentProjectsReader {

    /// Haal paden op van .prproj bestanden die recent geopend zijn op deze Mac
    /// Gebruikt Spotlight (mdfind) om bestanden te vinden met kMDItemLastUsedDate
    static func getRecentProjectPaths(maxAge: TimeInterval = 90 * 24 * 3600) -> Set<String> {
        var paths = Set<String>()

        // Gebruik mdfind om .prproj bestanden te vinden die recent geopend zijn
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemFSName == '*.prproj' && kMDItemLastUsedDate >= $time.today(-90)"]

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
                    if trimmed.contains("Auto-Save") { continue }
                    paths.insert(trimmed)
                }
            }
        } catch {
            print("PremiereRecentProjectsReader: mdfind fout: \(error)")
        }

        return paths
    }

    /// Check of een pad op een netwerkvolume staat
    static func isNetworkPath(_ path: String) -> Bool {
        return path.hasPrefix("/Volumes/")
    }
}
