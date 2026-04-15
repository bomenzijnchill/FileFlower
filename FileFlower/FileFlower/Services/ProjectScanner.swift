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
                // Filter autosave bestanden
                if isAutosaveFile(item) { continue }

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
                    let dirName = item.lastPathComponent
                    // Skip autosave en backup mappen
                    if dirName.localizedCaseInsensitiveContains("Auto-Save") ||
                       dirName.localizedCaseInsensitiveContains("Backup") {
                        continue
                    }

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

    // MARK: - Project File Discovery

    /// Zoek alle .prproj/.drp bestanden onder een projectmap.
    /// Gebruikt dezelfde recursieve scan als scanRecentProjects, inclusief autosave-filter en
    /// Auto-Save/Backup map-skip. Gesorteerd op lastModified aflopend.
    func findProjectFiles(in projectRoot: String) async -> [URL] {
        let rootURL: URL
        if let url = URL(string: projectRoot), url.scheme != nil {
            rootURL = url
        } else {
            rootURL = URL(fileURLWithPath: projectRoot)
        }

        let projects = await findProjectsWithTimeout(in: rootURL, timeout: 10)
        return projects.map { URL(fileURLWithPath: $0.projectPath) }
    }

    // MARK: - Folder-based Project Scanning

    /// Scan alle top-level mappen in de projectroots als projecten, ongeacht of ze .prproj/.drp bevatten.
    /// Sorteert op meest recente wijzigingsdatum van de map.
    func scanAllFolderProjects(roots: [String], limit: Int = 50) async -> [ProjectInfo] {
        var projects: [ProjectInfo] = []

        for rootPath in roots {
            let rootURL: URL
            if let url = URL(string: rootPath), url.scheme != nil {
                rootURL = url
            } else {
                rootURL = URL(fileURLWithPath: rootPath)
            }

            let found = await scanTopLevelFoldersWithTimeout(in: rootURL, timeout: 10)
            projects.append(contentsOf: found)
        }

        // Dedupliceer op projectPath
        var seen = Set<String>()
        projects = projects.filter { project in
            if seen.contains(project.projectPath) { return false }
            seen.insert(project.projectPath)
            return true
        }

        // Sorteer op lastModified aflopend
        projects.sort { $0.lastModified > $1.lastModified }

        return Array(projects.prefix(limit))
    }

    private func scanTopLevelFoldersWithTimeout(in root: URL, timeout: TimeInterval) async -> [ProjectInfo] {
        await withTaskGroup(of: [ProjectInfo].self) { group in
            group.addTask {
                self.scanTopLevelFolders(in: root)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return []
            }
            if let first = await group.next() {
                group.cancelAll()
                return first
            }
            return []
        }
    }

    /// Lijst alle directe subdirectories in een root op, met hun wijzigingsdatum.
    private func scanTopLevelFolders(in root: URL) -> [ProjectInfo] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var projects: [ProjectInfo] = []
        let skipNames: Set<String> = ["Auto-Save", "Backup", ".Trash", "Adobe Premiere Pro Auto-Save"]

        for item in contents {
            guard !Task.isCancelled else { break }

            guard let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey]),
                  resourceValues.isDirectory == true else {
                continue
            }

            let dirName = item.lastPathComponent
            // Skip system/autosave mappen
            if skipNames.contains(dirName) ||
               dirName.localizedCaseInsensitiveContains("Auto-Save") ||
               dirName.localizedCaseInsensitiveContains("Backup") ||
               dirName.hasPrefix(".") {
                continue
            }

            // Gebruik de meest recente wijzigingsdatum: ofwel de map zelf, ofwel het nieuwste bestand erin
            let modDate = mostRecentModificationDate(in: item) ?? resourceValues.contentModificationDate ?? Date.distantPast

            let project = ProjectInfo(
                name: dirName,
                rootPath: root.path,
                projectPath: item.path,
                lastModified: modDate.timeIntervalSince1970
            )
            projects.append(project)
        }

        return projects
    }

    /// Zoek de meest recente wijzigingsdatum in een map (1 niveau diep, voor performance).
    private func mostRecentModificationDate(in directory: URL) -> Date? {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var latestDate: Date?
        for item in contents {
            if let attrs = try? item.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = attrs.contentModificationDate {
                if latestDate == nil || modDate > latestDate! {
                    latestDate = modDate
                }
            }
        }
        return latestDate
    }

    /// Check of een projectbestand een autosave is
    private func isAutosaveFile(_ url: URL) -> Bool {
        // Check parent directory naam
        let parentName = url.deletingLastPathComponent().lastPathComponent
        if parentName.localizedCaseInsensitiveContains("Auto-Save") ||
           parentName.localizedCaseInsensitiveContains("Backup") {
            return true
        }

        // Check bestandsnaam voor Premiere autosave UUID-timestamp pattern:
        // ProjectName--hex8-hex4-hex4-hex4-hex12-yyyy-mm-dd.prproj
        let filename = url.deletingPathExtension().lastPathComponent
        let pattern = #"--[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-\d{4}-\d{2}-\d{2}"#
        return filename.range(of: pattern, options: .regularExpression) != nil
    }
}
