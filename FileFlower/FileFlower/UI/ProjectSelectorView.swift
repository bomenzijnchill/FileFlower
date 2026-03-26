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

    private var visibleProjects: [ProjectInfo] {
        if showAllProjects {
            return nonNLEProjects
        }
        return Array(nonNLEProjects.prefix(10))
    }

    private var hasMoreProjects: Bool {
        nonNLEProjects.count > 10
    }

    // MARK: - Body

    var body: some View {
        Button {
            showAllProjects = false
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
        .popover(isPresented: $showingProjectList) {
            projectListPopover
        }
        .popover(isPresented: $showingNewProject) {
            newProjectPopover
        }
        .onReceive(refreshTimer) { _ in
            Task { await appState.refreshRecentProjects() }
        }
    }

    // MARK: - Project List Popover

    private var projectListPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // NLE-actieve projecten (bovenaan)
            if !appState.nleActiveProjects.isEmpty {
                ForEach(appState.nleActiveProjects) { project in
                    projectRow(project, icon: "film")
                }

                Divider()
                    .padding(.vertical, 4)
            }

            // Folder-projecten
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if visibleProjects.isEmpty && appState.nleActiveProjects.isEmpty {
                        Text(String(localized: "project.no_projects"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(visibleProjects) { project in
                            projectRow(project, icon: "folder")
                        }
                    }

                    // Show more
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
                showingProjectList = false
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
        .frame(width: 260)
        .padding(.vertical, 6)
    }

    // MARK: - Project Row

    private func projectRow(_ project: ProjectInfo, icon: String) -> some View {
        Button {
            appState.activeProject = project
            showingProjectList = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 16)

                Text(project.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if appState.activeProject?.id == project.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - New Project Popover

    private var newProjectPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "project.new"))
                .font(.system(size: 13, weight: .semibold))

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
        } catch {
            createError = error.localizedDescription
        }
    }
}
