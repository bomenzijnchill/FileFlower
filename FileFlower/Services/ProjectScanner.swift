import Foundation

class ProjectScanner {
    static let shared = ProjectScanner()

    private init() {}

    func scanRecentProjects(roots: [String], limit: Int = 3, filterToLocal: Bool = false) async -> [ProjectInfo] {
        var projects: [ProjectInfo] = []

        for rootPath in roots {
            // Try URL(string:) first for file:// URLs, otherwise use fileURLWithPath
            let rootURL: URL
            if let url = URL(string: rootPath), url.scheme != nil {
                rootURL = url
            } else {
                rootURL = URL(fileURLWithPath: rootPath)
            }

            // Gebruik timeout per root om server-paden niet te laten hangen
            let found = await findProjectsWithTimeout(in: rootURL, timeout: 10)
            projects.append(contentsOf: found)
        }

        // Filter server-projecten tot alleen lokaal geopende (via Spotlight)
        if filterToLocal {
            let premiereRecentPaths = PremiereRecentProjectsReader.getRecentProjectPaths()
            let resolveRecentPaths = ResolveRecentProjectsReader.getRecentProjectPaths()
            let localRecentPaths = premiereRecentPaths.union(resolveRecentPaths)
            projects = projects.filter { project in
                // Lokale projecten altijd doorlaten
                if !PremiereRecentProjectsReader.isNetworkPath(project.projectPath) {
                    return true
                }
                // Server-projecten alleen als ze recent lokaal geopend zijn
                return localRecentPaths.contains(project.projectPath)
            }
        }

        // Sort by lastModified descending
        projects.sort { $0.lastModified > $1.lastModified }

        // Return top N
        return Array(projects.prefix(limit))
    }

    /// Scan met timeout — als het langer dan `timeout` seconden duurt, geef terug wat we tot nu toe hebben
    private func findProjectsWithTimeout(in root: URL, timeout: TimeInterval) async -> [ProjectInfo] {
        await withTaskGroup(of: [ProjectInfo].self) { group in
            group.addTask {
                await self.findProjects(in: root, maxDepth: 5)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return [] // Timeout sentinel
            }

            // Return whichever finishes first
            if let first = await group.next() {
                group.cancelAll()
                return first
            }
            return []
        }
    }

    /// Recursieve scan met depth limit
    private func findProjects(in root: URL, maxDepth: Int) async -> [ProjectInfo] {
        return findProjectsRecursive(in: root, rootPath: root.path, currentDepth: 0, maxDepth: maxDepth)
    }

    private func findProjectsRecursive(in directory: URL, rootPath: String, currentDepth: Int, maxDepth: Int) -> [ProjectInfo] {
        guard currentDepth < maxDepth else { return [] }

        // Check task cancellation (voor timeout support)
        guard !Task.isCancelled else { return [] }

        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var projects: [ProjectInfo] = []

        for item in contents {
            guard !Task.isCancelled else { break }

            let ext = item.pathExtension.lowercased()
            if ext == "prproj" || ext == "drp" {
                if let attrs = try? item.resourceValues(forKeys: [.contentModificationDateKey]),
                   let modDate = attrs.contentModificationDate {
                    let project = ProjectInfo(
                        name: item.deletingPathExtension().lastPathComponent,
                        rootPath: rootPath,
                        projectPath: item.path,
                        lastModified: modDate.timeIntervalSince1970
                    )
                    projects.append(project)
                }
            } else {
                // Check of het een directory is en recurse
                if let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey]),
                   resourceValues.isDirectory == true {
                    let subProjects = findProjectsRecursive(
                        in: item,
                        rootPath: rootPath,
                        currentDepth: currentDepth + 1,
                        maxDepth: maxDepth
                    )
                    projects.append(contentsOf: subProjects)
                }
            }
        }

        return projects
    }
}
