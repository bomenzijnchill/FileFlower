import SwiftUI
import Combine

/// Project selector dropdown in de header bar.
/// Toont NLE-actieve projecten bovenaan (met divider), folder-projecten gesorteerd op laatst gewijzigd.
struct ProjectSelectorView: View {
    @ObservedObject var appState: AppState

    @State private var showingProjectList = false
    @State private var showingNewProject = false
    @State private var showAllProjects = false
    @State private var newProjectName = ""
    @State private var selectedRoot = ""
    @State private var createError: String?

    // Search
    @State private var searchText: String = ""

    // Open-project state per rij
    @State private var projectFilesByID: [UUID: [URL]] = [:]
    @State private var scanningProjectID: UUID? = nil
    @State private var expandedProjectID: UUID? = nil

    /// Auto-refresh timer
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // MARK: - Computed

    /// Template-mapnamen die geen echte projecten zijn
    private static let templateFolderBlocklist: Set<String> = [
        "adobe", "footage", "audio", "graphics", "subs", "documents",
        "exports", "vfx", "sfx", "visuals", "music", "materiaal",
        "vormgeving", "muziek", "subtitles", "export", "photos",
        "stills", "production_audio", "foto", "video"
    ]

    /// Folder-projecten zonder NLE-actieve en zonder template-mappen
    private var nonNLEProjects: [ProjectInfo] {
        let nleIDs = Set(appState.nleActiveProjects.map(\.id))
        return appState.allFolderProjects
            .filter { !nleIDs.contains($0.id) }
            .filter { project in
                let normalized = project.name.lowercased()
                    .replacingOccurrences(of: #"^\d+_"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                return !Self.templateFolderBlocklist.contains(normalized)
            }
            .sorted { $0.lastModified > $1.lastModified }
    }

    /// Trim + check of we aan het zoeken zijn
    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespaces)
    }

    private var isSearching: Bool {
        !trimmedSearch.isEmpty
    }

    /// NLE-actieve projecten, gefilterd op zoekterm
    private var filteredNLEProjects: [ProjectInfo] {
        let projects = appState.nleActiveProjects
        guard isSearching else { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearch) }
    }

    /// Folder-projecten gefilterd op zoekterm
    private var filteredNonNLEProjects: [ProjectInfo] {
        guard isSearching else { return nonNLEProjects }
        return nonNLEProjects.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearch) }
    }

    private var visibleProjects: [ProjectInfo] {
        // Bij zoeken negeren we de top-10 cap
        if isSearching || showAllProjects {
            return filteredNonNLEProjects
        }
        return Array(filteredNonNLEProjects.prefix(10))
    }

    private var hasMoreProjects: Bool {
        !isSearching && filteredNonNLEProjects.count > 10
    }

    // MARK: - Body

    var body: some View {
        Button {
            showAllProjects = false
            showingNewProject = false
            showingProjectList.toggle()
        } label: {
            HStack(spacing: 0) {
                Text(appState.activeProject?.name ?? String(localized: "project.none_selected"))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingProjectList, arrowEdge: .bottom) {
            if showingNewProject {
                newProjectPopover
            } else {
                projectListPopover
            }
        }
        .onReceive(refreshTimer) { _ in
            Task { await appState.refreshRecentProjects() }
        }
    }

    // MARK: - Project List Popover

    private var projectListPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Zoekveld
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField(String(localized: "project.search_placeholder"), text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // NLE-actieve projecten (bovenaan)
            if !filteredNLEProjects.isEmpty {
                ForEach(filteredNLEProjects) { project in
                    projectRow(project, icon: "film")
                }

                if !visibleProjects.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                }
            }

            // Folder-projecten
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if visibleProjects.isEmpty && filteredNLEProjects.isEmpty {
                        Text(isSearching
                             ? String(format: String(localized: "project.no_search_results"), trimmedSearch)
                             : String(localized: "project.no_projects"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(visibleProjects) { project in
                            projectRow(project, icon: "folder")
                        }
                    }

                    // Show more (alleen wanneer niet aan het zoeken)
                    if hasMoreProjects && !showAllProjects {
                        Button {
                            withAnimation { showAllProjects = true }
                        } label: {
                            HStack {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 11))
                                Text(String(localized: "project.show_more"))
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 300)

            Divider()

            // Nieuw project aanmaken
            Button {
                newProjectName = ""
                createError = nil
                if let firstRoot = appState.config.projectRoots.first {
                    selectedRoot = firstRoot
                }
                showingNewProject = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                    Text(String(localized: "project.new"))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 340)
        .padding(.vertical, 6)
    }

    // MARK: - Project Row

    private func projectRow(_ project: ProjectInfo, icon: String) -> some View {
        HStack(spacing: 4) {
            // Naam-knop: klik om actief project te wisselen
            Button {
                appState.activeProject = project
                showingProjectList = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(project.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(displayPath(for: project))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(project.rootPath)

            // Open folder
            Button {
                openFolder(for: project)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "project.open_folder"))

            // Open project
            Button {
                handleOpenProject(project)
            } label: {
                Image(systemName: scanningProjectID == project.id ? "hourglass" : "play.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "project.open_project"))
            .popover(isPresented: Binding(
                get: { expandedProjectID == project.id },
                set: { if !$0 { expandedProjectID = nil } }
            ), arrowEdge: .trailing) {
                projectFilesPopover(for: project)
            }

            // Checkmark placeholder voor uitlijning
            Group {
                if appState.activeProject?.id == project.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                } else {
                    Color.clear
                }
            }
            .frame(width: 16)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    /// Abbreviate home directory in project path for compact display
    private func displayPath(for project: ProjectInfo) -> String {
        let path = project.rootPath
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Project Files Popover (voor "Open project" met meerdere bestanden)

    private func projectFilesPopover(for project: ProjectInfo) -> some View {
        NLEProjectFilesPopover(
            files: projectFilesByID[project.id] ?? [],
            emptyMessage: String(localized: "project.no_project_file"),
            onPick: { url in
                openProjectFile(url)
                expandedProjectID = nil
                showingProjectList = false
            }
        )
    }

    // MARK: - Actions: Open Folder / Open Project

    private func openFolder(for project: ProjectInfo) {
        let fileManager = FileManager.default
        // Primair: rootPath (de projectmap zelf)
        if fileManager.fileExists(atPath: project.rootPath) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.rootPath)
            return
        }
        // Fallback: parent van projectPath
        let fallback = URL(fileURLWithPath: project.projectPath).deletingLastPathComponent().path
        if fileManager.fileExists(atPath: fallback) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: fallback)
        }
    }

    private func openProjectFile(_ url: URL) {
        NSWorkspace.shared.open(url)
        // Extra zekerheid: breng NLE naar voren wanneer al draaiend
        if let nle = NLEType.from(projectPath: url.path) {
            NLEChecker.shared.bringToFront(nle)
        }
    }

    private func handleOpenProject(_ project: ProjectInfo) {
        scanningProjectID = project.id
        let projectID = project.id
        let rootPath = project.rootPath
        Task {
            let files = await ProjectScanner.shared.findProjectFiles(in: rootPath)
            await MainActor.run {
                projectFilesByID[projectID] = files
                // Enkel onze eigen spinner uitzetten
                if scanningProjectID == projectID {
                    scanningProjectID = nil
                }

                if files.count == 1 {
                    openProjectFile(files[0])
                    showingProjectList = false
                } else {
                    // 0 of >1: toon popover (leeg = "no project file", meer = kies)
                    expandedProjectID = projectID
                }
            }
        }
    }

    // MARK: - New Project Popover

    private var newProjectPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header met back-button
            HStack(spacing: 6) {
                Button {
                    showingNewProject = false
                    createError = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Text(String(localized: "project.new"))
                    .font(.system(size: 13, weight: .semibold))
            }

            // Root selector (als er meerdere roots zijn)
            if appState.config.projectRoots.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "project.select_root"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Picker("", selection: $selectedRoot) {
                        ForEach(appState.config.projectRoots, id: \.self) { root in
                            Text(URL(fileURLWithPath: root).lastPathComponent)
                                .tag(root)
                        }
                    }
                    .labelsHidden()
                }
            }

            // Project naam
            TextField(String(localized: "project.name_placeholder"), text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit { createProject() }

            if let error = createError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button(String(localized: "project.create")) {
                    createProject()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 260)
    }

    // MARK: - Actions

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let root = selectedRoot.isEmpty
            ? (appState.config.projectRoots.first ?? "")
            : selectedRoot

        guard !root.isEmpty else {
            createError = "No project root configured"
            return
        }

        do {
            let _ = try appState.createNewProject(name: name, inRoot: root)
            showingNewProject = false
            showingProjectList = false
        } catch {
            createError = error.localizedDescription
        }
    }
}
