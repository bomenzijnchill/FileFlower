import SwiftUI
import Quartz
import QuickLookThumbnailing

// MARK: - QuickLook Coordinator (macOS QLPreviewPanel)

class FileSafeQuickLookCoordinator: NSObject, QLPreviewPanelDataSource {
    static let shared = FileSafeQuickLookCoordinator()

    private var currentURL: URL?

    /// Toggle QuickLook panel: open als dicht, sluit als open (of wissel bestand)
    func toggle(url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }

        if panel.isVisible {
            if currentURL == url {
                panel.orderOut(nil)
                return
            }
            // Ander bestand → update
            currentURL = url
            panel.reloadData()
        } else {
            currentURL = url
            panel.dataSource = self
            panel.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        currentURL != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        currentURL as? QLPreviewItem
    }
}

// MARK: - Step Indicator

struct FileSafeStepIndicator: View {
    let currentStep: FileSafeStep
    private let visibleSteps: [FileSafeStep] = [.volumeSelect, .projectSelect, .projectConfig, .cardConfig, .structurePreview, .copying, .report]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(visibleSteps, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Empty State

struct FileSafeEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text(String(localized: "filesafe.empty.title"))
                .font(.system(size: 15, weight: .semibold))

            Text(String(localized: "filesafe.empty.subtitle"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Volume Select

struct FileSafeVolumeSelectView: View {
    @ObservedObject var volumeDetector: VolumeDetector
    let onSelect: (ExternalVolume) -> Void

    var body: some View {
        VStack(spacing: 0) {
            FileSafeNavBar(title: String(localized: "filesafe.volume.title"))

            if volumeDetector.externalVolumes.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(String(localized: "filesafe.volume.waiting"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(volumeDetector.externalVolumes) { volume in
                            VolumeRow(volume: volume) {
                                onSelect(volume)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
}

struct VolumeRow: View {
    let volume: ExternalVolume
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(volume.name)
                        .font(.system(size: 13, weight: .medium))

                    Text("\(volume.formattedTotalSize) \u{2022} \(volume.formattedFreeSpace) free")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Capacity indicator
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 40, height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(volume.usedPercentage > 0.9 ? Color.red : Color.accentColor)
                        .frame(width: CGFloat(40 * volume.usedPercentage), height: 4)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Project Select

struct FileSafeProjectSelectView: View {
    @ObservedObject var appState: AppState
    @Binding var isNewProject: Bool
    @Binding var newProjectName: String
    @Binding var selectedProjectPath: String?
    @Binding var selectedProjectRootPath: String?
    let onConfirm: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FileSafeNavBar(title: String(localized: "filesafe.project.title"), onBack: onBack)

            ScrollView {
                VStack(spacing: 12) {
                    // New / Existing selection
                    HStack(spacing: 10) {
                        FileSafeSelectButton(
                            title: String(localized: "filesafe.project.new"),
                            icon: "folder.badge.plus",
                            isSelected: isNewProject
                        ) {
                            isNewProject = true
                        }
                        FileSafeSelectButton(
                            title: String(localized: "filesafe.project.existing"),
                            icon: "folder",
                            isSelected: !isNewProject
                        ) {
                            isNewProject = false
                        }
                    }

                    if isNewProject {
                        newProjectContent
                    } else {
                        existingProjectContent
                    }
                }
                .padding(12)
            }

            // Confirm button
            Button(action: onConfirm) {
                Text(String(localized: "filesafe.project.confirm"))
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(!canConfirm)
            .padding(12)
        }
    }

    private var canConfirm: Bool {
        if isNewProject {
            return !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty && selectedProjectRootPath != nil
        } else {
            return selectedProjectPath != nil
        }
    }

    private var newProjectContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "filesafe.project.name"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            TextField(String(localized: "filesafe.project.name.placeholder"), text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            if !appState.config.projectRoots.isEmpty {
                Text(String(localized: "filesafe.project.location"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)

                ForEach(appState.config.projectRoots, id: \.self) { root in
                    Button(action: { selectedProjectRootPath = root }) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 12))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(URL(fileURLWithPath: root).lastPathComponent)
                                    .font(.system(size: 12))
                                Text(root)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            if selectedProjectRootPath == root {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedProjectRootPath == root ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: pickNewProjectFolder) {
                Label(String(localized: "filesafe.project.browse"), systemImage: "folder.badge.plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @State private var searchText: String = ""
    @State private var sortMode: ProjectSortMode = .dateNewest

    private var existingProjectContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.config.projectRoots.isEmpty {
                Text(String(localized: "filesafe.project.no_roots"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                // Zoek + sorteer toolbar
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        TextField(String(localized: "filesafe.project.search.placeholder"), text: $searchText)
                            .font(.system(size: 12))
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(.controlBackgroundColor))
                    )

                    Menu {
                        ForEach(ProjectSortMode.allCases, id: \.self) { mode in
                            Button(action: { sortMode = mode }) {
                                Label(mode.displayName, systemImage: sortMode == mode ? "checkmark" : mode.icon)
                            }
                        }
                    } label: {
                        Label(sortMode.displayName, systemImage: "arrow.up.arrow.down")
                            .font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                // Gefilterde en gesorteerde projectlijst
                let projects = loadAndFilterProjects()
                if projects.isEmpty {
                    Text(String(localized: "filesafe.project.no_results"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    // NLE project bovenaan als het niet in de lijst staat
                    if let nlePath = activeNLEProjectFolder,
                       !projects.contains(where: { $0.path == nlePath }) {
                        let nleName = URL(fileURLWithPath: nlePath).lastPathComponent
                        Button(action: { selectedProjectPath = nlePath }) {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(nleName)
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                        Text("Premiere")
                                            .font(.system(size: 9, weight: .medium))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.green.opacity(0.2))
                                            .clipShape(Capsule())
                                            .foregroundColor(.green)
                                    }
                                    Text(String(localized: "filesafe.project.external"))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedProjectPath == nlePath {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedProjectPath == nlePath ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.green.opacity(0.5), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.vertical, 4)
                    }

                    ForEach(projects) { project in
                        let isNLEActive = activeNLEProjectFolder == project.path
                        Button(action: { selectedProjectPath = project.path }) {
                            HStack(spacing: 8) {
                                // Star toggle
                                Button(action: { toggleStar(for: project.path) }) {
                                    Image(systemName: project.isStarred ? "star.fill" : "star")
                                        .font(.system(size: 11))
                                        .foregroundColor(project.isStarred ? .yellow : .secondary.opacity(0.4))
                                }
                                .buttonStyle(.plain)

                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(isNLEActive ? .green : .accentColor)

                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(project.name)
                                            .font(.system(size: 12))
                                            .lineLimit(1)
                                        if isNLEActive {
                                            Text("Premiere")
                                                .font(.system(size: 9, weight: .medium))
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.green.opacity(0.2))
                                                .clipShape(Capsule())
                                                .foregroundColor(.green)
                                        }
                                    }

                                    if let date = project.modificationDate {
                                        Text(date, style: .relative)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                if selectedProjectPath == project.path {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedProjectPath == project.path ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
                            )
                            .overlay(
                                isNLEActive ?
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.green.opacity(0.5), lineWidth: 1.5)
                                    : nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button(action: pickExistingProjectFolder) {
                Label(String(localized: "filesafe.project.browse"), systemImage: "folder.badge.plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Project List Helpers

    struct ProjectListItem: Identifiable {
        let id: String
        let path: String
        let name: String
        let modificationDate: Date?
        let isStarred: Bool
    }

    /// Active NLE project folder path (Premiere/Resolve)
    /// Resolve het echte project-pad door template-submappen heen te kijken
    private func resolveNLEProjectRoot(from nleFilePath: String) -> String {
        var dir = URL(fileURLWithPath: nleFilePath).deletingLastPathComponent()
        for _ in 0..<3 {
            let normalized = dir.lastPathComponent.lowercased()
                .replacingOccurrences(of: #"^\d+_"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if Self.templateFolderBlocklist.contains(normalized) {
                dir = dir.deletingLastPathComponent()
            } else {
                break
            }
        }
        return dir.path
    }

    private var activeNLEProjectFolder: String? {
        if let premierePath = JobServer.shared.activeProjectPath, JobServer.shared.isActiveProjectFresh {
            return resolveNLEProjectRoot(from: premierePath)
        }
        if let resolvePath = JobServer.shared.resolveActiveProjectPath, JobServer.shared.isResolveActiveProjectFresh {
            return resolveNLEProjectRoot(from: resolvePath)
        }
        return nil
    }

    /// Template folder names die geen projecten zijn
    private static let templateFolderBlocklist: Set<String> = {
        // From TemplateDeployer.standardTemplate + common names
        var names: Set<String> = ["adobe", "footage", "audio", "graphics", "subs", "documents",
                                   "exports", "vfx", "sfx", "visuals", "music", "materiaal",
                                   "vormgeving", "muziek", "subtitles", "export", "photos",
                                   "stills", "production_audio", "foto", "video"]
        // Add standardTemplate names (normalized)
        for item in TemplateDeployer.standardTemplate {
            let normalized = item.name.lowercased()
                .replacingOccurrences(of: #"^\d+_"#, with: "", options: .regularExpression)
            names.insert(normalized)
        }
        return names
    }()

    private func loadAndFilterProjects() -> [ProjectListItem] {
        var allProjects: [ProjectListItem] = []

        for root in appState.config.projectRoots {
            let subfolders = listSubfolders(at: root)
            for folder in subfolders {
                let name = URL(fileURLWithPath: folder).lastPathComponent
                // Filter template/subfolder mappen (01_Adobe, FOOTAGE, etc.)
                let normalized = name.lowercased()
                    .replacingOccurrences(of: #"^\d+_"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if Self.templateFolderBlocklist.contains(normalized) { continue }

                let modDate = modificationDate(for: folder)
                let isStarred = appState.config.starredProjects.contains(folder)
                allProjects.append(ProjectListItem(
                    id: folder,
                    path: folder,
                    name: name,
                    modificationDate: modDate,
                    isStarred: isStarred
                ))
            }
        }

        // Filter
        let filtered: [ProjectListItem]
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            filtered = allProjects
        } else {
            let query = searchText.lowercased()
            filtered = allProjects.filter { $0.name.lowercased().contains(query) }
        }

        // Splits starred/unstarred
        let starred = filtered.filter { $0.isStarred }
        let unstarred = filtered.filter { !$0.isStarred }

        // Sorteer
        let sortFn: (ProjectListItem, ProjectListItem) -> Bool
        switch sortMode {
        case .name:
            sortFn = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .dateNewest:
            sortFn = { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        case .dateOldest:
            sortFn = { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }
        }

        return starred.sorted(by: sortFn) + unstarred.sorted(by: sortFn)
    }

    private func modificationDate(for path: String) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else { return nil }
        return date
    }

    private func toggleStar(for path: String) {
        if let index = appState.config.starredProjects.firstIndex(of: path) {
            appState.config.starredProjects.remove(at: index)
        } else {
            appState.config.starredProjects.append(path)
        }
        AppState.shared.saveConfig()
    }

    private func pickNewProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            selectedProjectRootPath = url.path
        }
    }

    private func pickExistingProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            selectedProjectPath = url.path
        }
    }

    private func listSubfolders(at path: String) -> [String] {
        let url = URL(fileURLWithPath: path)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.path }
            .sorted()
    }
}

// MARK: - Scanning View

struct FileSafeScanningView: View {
    let volumeName: String
    let progress: FileSafeScanner.ScanProgress?
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text(String(localized: "filesafe.scan.title"))
                .font(.system(size: 15, weight: .semibold))

            Text(volumeName)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if let progress = progress {
                VStack(spacing: 8) {
                    Text(String(localized: "filesafe.scan.found \(progress.filesFound)"))
                        .font(.system(size: 12, weight: .medium))

                    HStack(spacing: 16) {
                        ScanCountBadge(icon: "film", count: progress.videoCount, label: "Video")
                        ScanCountBadge(icon: "waveform", count: progress.audioCount, label: "Audio")
                        ScanCountBadge(icon: "photo", count: progress.photoCount, label: "Photo")
                    }

                    if !progress.currentDirectory.isEmpty {
                        Text(progress.currentDirectory)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Button(action: onCancel) {
                Text(String(localized: "filesafe.cancel"))
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanCountBadge: View {
    let icon: String
    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.accentColor)
            Text("\(count)")
                .font(.system(size: 12, weight: .medium))
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Project Config View

struct FileSafeProjectConfigView: View {
    @Binding var config: FileSafeProjectConfig
    let scanResult: FileSafeScanResult
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FileSafeNavBar(title: String(localized: "filesafe.projectconfig.title"), onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Detected camera brand badge
                    if scanResult.detectedBrand != .unknown {
                        HStack(spacing: 6) {
                            Image(systemName: scanResult.detectedBrand.icon)
                                .font(.system(size: 11))
                            Text(scanResult.detectedBrand.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.15))
                        )
                        .foregroundColor(.accentColor)
                    }

                    // General section
                    generalSection

                    // Video section
                    if scanResult.hasVideo {
                        videoSection
                    }

                    // Audio section
                    if scanResult.hasAudio {
                        audioSection
                    }

                    // Photo section
                    if scanResult.hasPhoto {
                        photoSection
                    }
                }
                .padding(12)
            }

            // Continue button
            Button(action: onContinue) {
                Text(String(localized: "filesafe.projectconfig.continue"))
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(12)
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: String(localized: "filesafe.projectconfig.general"), icon: "gearshape")

            // Multi-day toggle
            Toggle(String(localized: "filesafe.projectconfig.multiday"), isOn: $config.isMultiDayShoot)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)

            // Date source picker (alleen bij multi-day)
            if config.isMultiDayShoot {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "filesafe.projectconfig.datesource"))
                        .font(.system(size: 12))
                    Picker("", selection: $config.dateSource) {
                        ForEach(FileSafeDateSource.allCases, id: \.rawValue) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

        }
    }

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: String(localized: "filesafe.projectconfig.video"),
                icon: "film",
                badge: "\(scanResult.videoCount)"
            )

            // Multiple cameras toggle
            Toggle(String(localized: "filesafe.projectconfig.multicam"), isOn: $config.hasMultipleCameras)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)

            if !config.hasMultipleCameras {
                Text(String(localized: "filesafe.projectconfig.multicam.hint"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if config.hasMultipleCameras {
                // Camera split mode picker
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "filesafe.projectconfig.splitmode"))
                        .font(.system(size: 12))
                    Picker("", selection: $config.cameraSplitMode) {
                        Text(FileSafeCameraSplitMode.byType.displayName).tag(FileSafeCameraSplitMode.byType)
                        Text(FileSafeCameraSplitMode.byAngle.displayName).tag(FileSafeCameraSplitMode.byAngle)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Camera labels
                Text(config.cameraSplitMode == .byAngle
                    ? String(localized: "filesafe.projectconfig.camera_angles.placeholder")
                    : String(localized: "filesafe.projectconfig.camera_names.placeholder"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: String(localized: "filesafe.projectconfig.audio"),
                icon: "waveform",
                badge: "\(scanResult.audioCount)"
            )

            TagInputView(
                title: String(localized: "filesafe.projectconfig.persons"),
                placeholder: String(localized: "filesafe.projectconfig.persons.placeholder"),
                tags: $config.audioPersons
            )

            Toggle(String(localized: "filesafe.projectconfig.wildtrack"), isOn: $config.hasWildtrack)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)

            Toggle(String(localized: "filesafe.projectconfig.audio_per_day"), isOn: $config.linkAudioToDayStructure)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: String(localized: "filesafe.projectconfig.photos"),
                icon: "photo",
                badge: "\(scanResult.photoCount)"
            )

            TagInputView(
                title: String(localized: "filesafe.projectconfig.categories"),
                placeholder: String(localized: "filesafe.projectconfig.categories.placeholder"),
                tags: $config.photoCategories
            )

            Toggle(String(localized: "filesafe.projectconfig.split_raw"), isOn: $config.splitRawJpeg)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

// MARK: - Card Config View

struct FileSafeCardConfigView: View {
    @Binding var cardConfig: FileSafeCardConfig
    let projectConfig: FileSafeProjectConfig
    let scanResult: FileSafeScanResult
    let folderPreset: FolderStructurePreset
    let customTemplate: CustomFolderTemplate?
    var projectPath: String? = nil
    let onPreview: () -> Void
    let onBack: () -> Void

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "dd-MM-yyyy"
        return f
    }

    /// Detecteer bestaande footage map + duplicaten met bestanden op de kaart
    @State private var duplicateFileNames: Set<String> = []
    @State private var footageFolderInfo: (found: Bool, folderName: String, fileCount: Int) = (false, "", 0)

    private func scanForExistingFootage() {
        guard let path = projectPath else {
            footageFolderInfo = (false, "", 0)
            duplicateFileNames = []
            return
        }

        let projectURL = URL(fileURLWithPath: path)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: projectURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return }

        let footageKeywords = ["footage", "raw", "materiaal", "beeldmateriaal", "video"]
        var foundFolder: URL?

        for folder in contents {
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let normalized = folder.lastPathComponent.lowercased()
                .replacingOccurrences(of: #"^\d+_"#, with: "", options: .regularExpression)
            if footageKeywords.contains(where: { normalized.contains($0) }) {
                foundFolder = folder
                break
            }
        }

        guard let footageURL = foundFolder else {
            footageFolderInfo = (false, "", 0)
            duplicateFileNames = []
            return
        }

        // Scan recursief alle bestanden in de footage map
        var existingFiles: [String: Set<Int64>] = [:]
        var totalCount = 0
        if let enumerator = FileManager.default.enumerator(
            at: footageURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                guard let rv = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                      rv.isRegularFile == true, let size = rv.fileSize else { continue }
                existingFiles[fileURL.lastPathComponent.lowercased(), default: []].insert(Int64(size))
                totalCount += 1
            }
        }

        footageFolderInfo = (true, footageURL.lastPathComponent, totalCount)

        // Vergelijk met bestanden op de kaart
        var dupes: Set<String> = []
        for file in scanResult.files {
            let key = file.fileName.lowercased()
            if let sizes = existingFiles[key], sizes.contains(file.fileSize) {
                dupes.insert(file.fileName)
            }
        }
        duplicateFileNames = dupes
    }

    var body: some View {
        VStack(spacing: 0) {
            FileSafeNavBar(title: String(localized: "filesafe.cardconfig.title"), onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Detected info banner
                    detectedInfoBanner

                    // Bestaande footage waarschuwing
                    if footageFolderInfo.found {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(localized: "filesafe.cardconfig.existing_footage_title"))
                                        .font(.system(size: 12, weight: .medium))
                                    Text(String(localized: "filesafe.cardconfig.existing_footage_detail \(footageFolderInfo.folderName) \(footageFolderInfo.fileCount)"))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }

                            // Duplicaten melding
                            if !duplicateFileNames.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.on.doc.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.orange)
                                    Text(String(localized: "filesafe.cardconfig.duplicates_found \(duplicateFileNames.count)"))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.orange)
                                }
                                .padding(.leading, 28)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(duplicateFileNames.isEmpty ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                        )
                    }

                    // Day configuration (read-only)
                    if projectConfig.isMultiDayShoot {
                        multiDaySection
                    } else {
                        singleDaySection
                    }

                    // Video bins + bestandsbrowser
                    if scanResult.hasVideo {
                        FileSafeCategoryBinEditor(
                            category: .video,
                            files: scanResult.videoFiles,
                            shootDays: cardConfig.shootDays,
                            isMultiDay: projectConfig.isMultiDayShoot,
                            useTimestamp: projectConfig.useTimestampAssignment,
                            bins: $cardConfig.videoBins,
                            fileSubfolderMap: $cardConfig.fileSubfolderMap
                        )
                    }

                    // Foto bins + bestandsbrowser
                    if scanResult.hasPhoto {
                        FileSafeCategoryBinEditor(
                            category: .photo,
                            files: scanResult.photoFiles,
                            shootDays: cardConfig.shootDays,
                            isMultiDay: projectConfig.isMultiDayShoot,
                            useTimestamp: projectConfig.useTimestampAssignment,
                            bins: $cardConfig.photoBins,
                            fileSubfolderMap: $cardConfig.fileSubfolderMap
                        )
                    }

                    // Live path preview
                    FileSafePathPreview(
                        projectConfig: projectConfig,
                        cardConfig: cardConfig,
                        scanResult: scanResult,
                        folderPreset: folderPreset,
                        customTemplate: customTemplate,
                        projectPath: projectPath
                    )
                }
                .padding(16)
            }

            // Preview button
            Button(action: onPreview) {
                Text(String(localized: "filesafe.cardconfig.preview"))
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(16)
        }
        .onAppear {
            scanForExistingFootage()
        }
    }

    private var detectedInfoBanner: some View {
        HStack(spacing: 8) {
            if scanResult.detectedBrand != .unknown {
                HStack(spacing: 4) {
                    Image(systemName: scanResult.detectedBrand.icon)
                        .font(.system(size: 11))
                    Text(scanResult.detectedBrand.rawValue)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.accentColor)
            }

            if let earliest = scanResult.earliestDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text(String(localized: "filesafe.cardconfig.material_from \(dateFormatter.string(from: earliest))"))
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        )
    }

    private var multiDaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: String(localized: "filesafe.cardconfig.days"), icon: "calendar")

            ForEach(cardConfig.shootDays.indices, id: \.self) { index in
                HStack {
                    Text(String(localized: "filesafe.cardconfig.day \(index + 1)"))
                        .font(.system(size: 12))
                    Spacer()
                    DatePicker("", selection: Binding(
                        get: { cardConfig.shootDays[index].date ?? Date() },
                        set: { cardConfig.shootDays[index].date = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }
            }
        }
    }

    private var singleDaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: String(localized: "filesafe.cardconfig.date"), icon: "calendar")

            if !cardConfig.shootDays.isEmpty {
                HStack {
                    Text(String(localized: "filesafe.cardconfig.detected_date"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    DatePicker("", selection: Binding(
                        get: { cardConfig.shootDays.first?.date ?? Date() },
                        set: { newDate in
                            if !cardConfig.shootDays.isEmpty {
                                cardConfig.shootDays[0].date = newDate
                            }
                        }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }

                Toggle(isOn: $cardConfig.useDateSubfolder) {
                    Text(String(localized: "filesafe.cardconfig.use_date_subfolder"))
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private var videoSubfoldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if projectConfig.hasMultipleCameras {
                SectionHeader(
                    title: projectConfig.cameraSplitMode == .byAngle
                        ? String(localized: "filesafe.projectconfig.camera_angles")
                        : String(localized: "filesafe.projectconfig.camera_names"),
                    icon: "video",
                    badge: "\(scanResult.videoCount)"
                )

                SubfolderListEditor(
                    subfolders: $cardConfig.videoSubfolders,
                    placeholder: projectConfig.cameraSplitMode == .byAngle
                        ? String(localized: "filesafe.cardconfig.camera_angle.placeholder")
                        : String(localized: "filesafe.cardconfig.camera_label.placeholder"),
                    minCount: 1
                )
            } else {
                SectionHeader(
                    title: String(localized: "filesafe.cardconfig.video_subfolders"),
                    icon: "video",
                    badge: "\(scanResult.videoCount)"
                )

                SubfolderListEditor(
                    subfolders: $cardConfig.videoSubfolders,
                    placeholder: String(localized: "filesafe.cardconfig.video_subfolder.placeholder")
                )
            }
        }
    }

    private var photoSubfoldersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: String(localized: "filesafe.cardconfig.photo_subfolders"),
                icon: "photo",
                badge: "\(scanResult.photoCount)"
            )

            SubfolderListEditor(
                subfolders: $cardConfig.photoSubfolders,
                placeholder: String(localized: "filesafe.cardconfig.photo_subfolder.placeholder")
            )
        }
    }
}

// MARK: - Path Preview

// MARK: - Subfolder List Editor

struct SubfolderListEditor: View {
    @Binding var subfolders: [String]
    let placeholder: String
    var minCount: Int = 0  // Minimum aantal velden (bijv. 1 voor camera label)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(subfolders.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 6) {
                    if subfolders.count > 1 {
                        Text("\(index + 1).")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                    }

                    TextField(placeholder, text: safeBinding(at: index))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))

                    if subfolders.count > minCount {
                        Button(action: { removeItem(at: index) }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button(action: {
                withAnimation { subfolders.append("") }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                    Text(String(localized: "filesafe.cardconfig.add_subfolder"))
                        .font(.system(size: 11))
                }
                .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    private func safeBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { index < subfolders.count ? subfolders[index] : "" },
            set: { newValue in if index < subfolders.count { subfolders[index] = newValue } }
        )
    }

    private func removeItem(at index: Int) {
        guard index < subfolders.count, subfolders.count > minCount else { return }
        withAnimation { let _ = subfolders.remove(at: index) }
    }
}

// MARK: - Category Bin Editor (vervangt SubfolderListEditor in Card Config)

struct FileSafeCategoryBinEditor: View {
    let category: FileSafeFileCategory
    let files: [FileSafeSourceFile]
    let shootDays: [FileSafeShootDay]
    let isMultiDay: Bool
    let useTimestamp: Bool
    @Binding var bins: [FileSafeSubfolderBin]
    @Binding var fileSubfolderMap: [UUID: String]

    @State private var newBinName: String = ""
    @State private var selectedFileIDs: Set<UUID> = []
    @State private var lastClickedFileID: UUID?
    @State private var isFileBrowserExpanded: Bool = false
    @State private var thumbnailSize: CGFloat = 24

    private var filesByDay: [UUID: [FileSafeSourceFile]] {
        FileSafeStructureBuilder.shared.assignFilesToDays(
            files: files,
            shootDays: shootDays,
            useTimestamp: useTimestamp
        )
    }

    /// Flat ordered list of all files (for shift-select range calculation)
    private var allFilesFlat: [FileSafeSourceFile] {
        if isMultiDay && shootDays.count > 1 {
            return shootDays.flatMap { day in filesByDay[day.id] ?? [] }
        } else {
            return files
        }
    }

    private var binNames: [String] {
        bins.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var totalSize: Int64 {
        files.reduce(0) { $0 + $1.fileSize }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            SectionHeader(
                title: category == .video
                    ? String(localized: "filesafe.cardconfig.video_subfolders")
                    : String(localized: "filesafe.cardconfig.photo_subfolders"),
                icon: category == .video ? "video" : "photo",
                badge: "\(files.count)",
                helpText: String(localized: "filesafe.help.bins")
            )

            // Bins lijst
            if !bins.isEmpty {
                VStack(spacing: 4) {
                    ForEach(bins) { bin in
                        FileSafeBinRow(
                            bin: bindingForBin(bin.id),
                            fileCount: fileSubfolderMap.values.filter { $0 == bin.name }.count,
                            onRemove: { removeBin(bin) }
                        )
                    }
                }
            }

            // Nieuwe bin toevoegen
            HStack(spacing: 6) {
                TextField(String(localized: "filesafe.cardconfig.bins.name_placeholder"), text: $newBinName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { addBin() }

                Button(action: addBin) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(newBinName.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newBinName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            // Uitklapbare bestandslijst
            DisclosureGroup(
                isExpanded: $isFileBrowserExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 4) {
                        // Thumbnail grootte slider
                        HStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "photo")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Slider(value: $thumbnailSize, in: 24...80, step: 8)
                                .frame(width: 100)
                            Image(systemName: "photo")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .padding(.bottom, 2)

                        if isMultiDay && shootDays.count > 1 {
                            // Multi-day: per dag
                            ForEach(shootDays) { day in
                                let dayFiles = filesByDay[day.id] ?? []
                                if !dayFiles.isEmpty {
                                    FileSafeDayFileSection(
                                        day: day,
                                        files: dayFiles,
                                        binNames: binNames,
                                        fileSubfolderMap: $fileSubfolderMap,
                                        selectedFileIDs: $selectedFileIDs,
                                        thumbnailSize: thumbnailSize,
                                        onFileClick: { file, modifiers in
                                            handleFileClick(file: file, modifiers: modifiers)
                                        },
                                        onBinChange: { binName in
                                            batchAssign(to: binName)
                                        }
                                    )
                                }
                            }
                        } else {
                            // Single-day: bestanden direct
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(files) { file in
                                    FileSafeFileRow(
                                        file: file,
                                        binNames: binNames,
                                        fileSubfolderMap: $fileSubfolderMap,
                                        isSelected: selectedFileIDs.contains(file.id),
                                        thumbnailSize: thumbnailSize,
                                        onFileClick: { modifiers in
                                            handleFileClick(file: file, modifiers: modifiers)
                                        },
                                        onBinChange: { binName in
                                            batchAssign(to: binName)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                },
                label: {
                    HStack(spacing: 6) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(String(localized: "filesafe.cardconfig.files_on_card"))
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(files.count)")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                            .foregroundColor(.secondary)
                        Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            )
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.space) {
                openQuickLook()
                return .handled
            }

            // Batch action bar (alleen zichtbaar als bestanden geselecteerd)
            if !selectedFileIDs.isEmpty && !binNames.isEmpty {
                HStack(spacing: 8) {
                    Text(String(localized: "filesafe.cardconfig.selected_count \(selectedFileIDs.count)"))
                        .font(.system(size: 11, weight: .medium))

                    Spacer()

                    Text(String(localized: "filesafe.cardconfig.assign_to"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Menu {
                        Button(String(localized: "filesafe.cardconfig.unassigned")) {
                            batchAssign(to: nil)
                        }
                        Divider()
                        ForEach(binNames, id: \.self) { name in
                            Button(name) {
                                batchAssign(to: name)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(String(localized: "filesafe.cardconfig.assign_to"))
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor))
                        .foregroundColor(.white)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.1))
                )
            }
        }
    }

    // MARK: - File Selection (Finder-style)

    private func handleFileClick(file: FileSafeSourceFile, modifiers: EventModifiers) {
        let flatFiles = allFilesFlat

        if modifiers.contains(.shift), let lastID = lastClickedFileID {
            // Shift+click: range selectie
            guard let lastIndex = flatFiles.firstIndex(where: { $0.id == lastID }),
                  let currentIndex = flatFiles.firstIndex(where: { $0.id == file.id }) else {
                selectedFileIDs = [file.id]
                lastClickedFileID = file.id
                return
            }
            let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
            let rangeIDs = Set(flatFiles[range].map(\.id))
            if modifiers.contains(.command) {
                // Shift+Cmd: voeg range toe aan bestaande selectie
                selectedFileIDs.formUnion(rangeIDs)
            } else {
                // Shift alleen: vervang selectie met range
                selectedFileIDs = rangeIDs
            }
        } else if modifiers.contains(.command) {
            // Cmd+click: toggle individueel bestand
            if selectedFileIDs.contains(file.id) {
                selectedFileIDs.remove(file.id)
            } else {
                selectedFileIDs.insert(file.id)
            }
            lastClickedFileID = file.id
        } else {
            // Gewone click: selecteer alleen dit bestand
            selectedFileIDs = [file.id]
            lastClickedFileID = file.id
        }
    }

    // MARK: - QuickLook

    private func openQuickLook() {
        // Preview het laatst geklikte bestand (of het eerste geselecteerde)
        let targetID = lastClickedFileID ?? selectedFileIDs.first
        guard let fileID = targetID,
              let file = allFilesFlat.first(where: { $0.id == fileID }) else { return }
        let url = URL(fileURLWithPath: file.relativePath)
        FileSafeQuickLookCoordinator.shared.toggle(url: url)
    }

    // MARK: - Bin Actions

    private func addBin() {
        let name = newBinName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard !bins.contains(where: { $0.name == name }) else { return }
        withAnimation { bins.append(FileSafeSubfolderBin(name: name)) }
        newBinName = ""
    }

    private func removeBin(_ bin: FileSafeSubfolderBin) {
        withAnimation {
            fileSubfolderMap = fileSubfolderMap.filter { $0.value != bin.name }
            bins.removeAll { $0.id == bin.id }
        }
    }

    private func batchAssign(to binName: String?) {
        withAnimation {
            for id in selectedFileIDs {
                if let name = binName {
                    fileSubfolderMap[id] = name
                } else {
                    fileSubfolderMap.removeValue(forKey: id)
                }
            }
            selectedFileIDs.removeAll()
        }
    }

    private func bindingForBin(_ binId: UUID) -> Binding<FileSafeSubfolderBin> {
        Binding(
            get: { bins.first(where: { $0.id == binId }) ?? FileSafeSubfolderBin(name: "") },
            set: { newValue in
                if let index = bins.firstIndex(where: { $0.id == binId }) {
                    let oldName = bins[index].name
                    bins[index] = newValue
                    if oldName != newValue.name && !oldName.isEmpty {
                        for (key, value) in fileSubfolderMap where value == oldName {
                            fileSubfolderMap[key] = newValue.name
                        }
                    }
                }
            }
        )
    }
}

// MARK: - Bin Row

struct FileSafeBinRow: View {
    @Binding var bin: FileSafeSubfolderBin
    let fileCount: Int
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundColor(.accentColor)

            TextField("", text: $bin.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            Text(String(localized: "filesafe.cardconfig.bins.files_count \(fileCount)"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(minWidth: 50)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Day File Section (per dag)

struct FileSafeDayFileSection: View {
    let day: FileSafeShootDay
    let files: [FileSafeSourceFile]
    let binNames: [String]
    @Binding var fileSubfolderMap: [UUID: String]
    @Binding var selectedFileIDs: Set<UUID>
    var thumbnailSize: CGFloat = 24
    var onFileClick: (FileSafeSourceFile, EventModifiers) -> Void
    var onBinChange: ((String?) -> Void)?

    @State private var isExpanded: Bool = false

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "dd-MM-yyyy"
        return f
    }

    var body: some View {
        DisclosureGroup(
            isExpanded: $isExpanded,
            content: {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(files) { file in
                        FileSafeFileRow(
                            file: file,
                            binNames: binNames,
                            fileSubfolderMap: $fileSubfolderMap,
                            isSelected: selectedFileIDs.contains(file.id),
                            thumbnailSize: thumbnailSize,
                            onFileClick: { modifiers in
                                onFileClick(file, modifiers)
                            },
                            onBinChange: onBinChange
                        )
                    }
                }
            },
            label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(day.displayName)
                        .font(.system(size: 11, weight: .medium))
                    if let date = day.date {
                        Text(dateFormatter.string(from: date))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(files.count)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        )
    }
}

// MARK: - Thumbnail View

struct FileSafeThumbnailView: View {
    let filePath: String
    let category: FileSafeFileCategory
    let size: CGFloat

    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
                    .cornerRadius(3)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.controlBackgroundColor))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: category == .video ? "film" : "photo")
                            .font(.system(size: size * 0.4))
                            .foregroundColor(.secondary.opacity(0.5))
                    )
            }
        }
        .task(id: filePath) {
            guard category == .photo || category == .video else { return }
            thumbnail = await FileSafeThumbnailCache.shared.thumbnail(for: filePath)
        }
    }
}

// MARK: - File Row

struct FileSafeFileRow: View {
    let file: FileSafeSourceFile
    let binNames: [String]
    @Binding var fileSubfolderMap: [UUID: String]
    let isSelected: Bool
    var thumbnailSize: CGFloat = 24
    var onFileClick: (EventModifiers) -> Void
    var onBinChange: ((String?) -> Void)?

    private var currentAssignment: String? {
        fileSubfolderMap[file.id]
    }

    /// Detecteer modifier keys via NSApp.currentEvent
    private func currentModifiers() -> EventModifiers {
        guard let flags = NSApp.currentEvent?.modifierFlags else { return [] }
        var mods: EventModifiers = []
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.command) { mods.insert(.command) }
        return mods
    }

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox
            Button(action: {
                onFileClick(currentModifiers())
            }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)

            // Thumbnail
            FileSafeThumbnailView(
                filePath: file.relativePath,
                category: file.category,
                size: thumbnailSize
            )

            // Filename
            Text(file.fileName)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // File size
            Text(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(minWidth: 55, alignment: .trailing)

            // Bin picker
            if !binNames.isEmpty {
                Menu {
                    Button {
                        if isSelected, let cb = onBinChange {
                            cb(nil)
                        } else {
                            fileSubfolderMap.removeValue(forKey: file.id)
                        }
                    } label: {
                        HStack {
                            Text("—")
                            if currentAssignment == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Divider()
                    ForEach(binNames, id: \.self) { name in
                        Button {
                            if isSelected, let cb = onBinChange {
                                cb(name)
                            } else {
                                fileSubfolderMap[file.id] = name
                            }
                        } label: {
                            HStack {
                                Text(name)
                                if currentAssignment == name {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(currentAssignment ?? "—")
                            .font(.system(size: 10, weight: currentAssignment != nil ? .medium : .regular))
                            .foregroundColor(currentAssignment != nil ? .accentColor : .secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(currentAssignment != nil ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
                    )
                }
                .frame(minWidth: 80)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onFileClick(currentModifiers())
        }
    }
}

// MARK: - Path Preview

struct FileSafePathPreview: View {
    let projectConfig: FileSafeProjectConfig
    let cardConfig: FileSafeCardConfig
    let scanResult: FileSafeScanResult
    let folderPreset: FolderStructurePreset
    let customTemplate: CustomFolderTemplate?
    var projectPath: String? = nil

    @State private var isExpanded: Bool = true

    private var examplePaths: [String] {
        var paths: [String] = []
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "ddMMyyyy"

        // Bij single-day zonder useDateSubfolder → geen dagmap in pad
        let skipDayInPath = !projectConfig.isMultiDayShoot && !cardConfig.useDateSubfolder
        let dayLabel: String
        if skipDayInPath {
            dayLabel = ""
        } else if let firstDay = cardConfig.shootDays.first, let date = firstDay.date {
            if projectConfig.isMultiDayShoot {
                let localizedDay = String(localized: "filesafe.cardconfig.day \(1)")
                dayLabel = "\(localizedDay)_\(dayFormatter.string(from: date))"
            } else {
                // Single-day met useDateSubfolder: alleen datum, geen "Day 1"
                dayLabel = dayFormatter.string(from: date)
            }
        } else {
            dayLabel = dayFormatter.string(from: Date())
        }

        // Resolve dynamische basispaden uit template (met bestaande map herkenning)
        let basePaths = FileSafeStructureBuilder.shared.resolveBasePaths(
            preset: folderPreset,
            customTemplate: customTemplate,
            existingProjectPath: projectPath
        )

        // Bepaal video/foto base paths (zelfde logica als buildStructure)
        let videoBase: String
        let photoBase: String
        if basePaths.photosInFootage && scanResult.hasVideo && scanResult.hasPhoto {
            videoBase = "\(basePaths.footagePath)/Video"
            photoBase = "\(basePaths.footagePath)/Photo"
        } else {
            videoBase = basePaths.footagePath
            photoBase = basePaths.photoPath
        }

        // Helper: voeg dayLabel toe aan pad als die niet leeg is
        func withDay(_ base: String) -> String {
            dayLabel.isEmpty ? base : "\(base)/\(dayLabel)"
        }

        // Video example paths
        if scanResult.hasVideo {
            let videoBinNames = cardConfig.effectiveVideoBinNames
            if !videoBinNames.isEmpty {
                for binName in videoBinNames.prefix(2) {
                    if let sampleFile = scanResult.videoFiles.first(where: {
                        cardConfig.fileSubfolderMap[$0.id] == binName
                    }) ?? scanResult.videoFiles.first {
                        paths.append("\(withDay(videoBase))/\(binName)/\(sampleFile.fileName)")
                    }
                }
                let assignedBins = Set(videoBinNames)
                if let unassigned = scanResult.videoFiles.first(where: {
                    guard let assignment = cardConfig.fileSubfolderMap[$0.id] else { return true }
                    return !assignedBins.contains(assignment)
                }) {
                    paths.append("\(withDay(videoBase))/\(unassigned.fileName)")
                }
            } else if let sampleFile = scanResult.videoFiles.first {
                var videoPath = withDay(videoBase)
                for subfolder in cardConfig.effectiveVideoSubfolders {
                    videoPath += "/\(subfolder)"
                }
                paths.append("\(videoPath)/\(sampleFile.fileName)")
            }
        }

        // Audio example paths
        if scanResult.hasAudio {
            let audioBase = basePaths.audioPath
            if let sampleFile = scanResult.audioFiles.first {
                if !projectConfig.audioPersons.isEmpty {
                    let person = projectConfig.audioPersons.first ?? "Person"
                    if projectConfig.linkAudioToDayStructure && projectConfig.isMultiDayShoot {
                        paths.append("\(audioBase)/\(dayLabel)/\(person)/\(sampleFile.fileName)")
                    } else {
                        paths.append("\(audioBase)/\(person)/\(sampleFile.fileName)")
                    }
                } else {
                    paths.append("\(audioBase)/\(sampleFile.fileName)")
                }
            }
        }

        // Photo example paths
        if scanResult.hasPhoto {
            let photoBinNames = cardConfig.effectivePhotoBinNames

            if !photoBinNames.isEmpty {
                // Bin-gebaseerd: toon 1 voorbeeld per bin
                for binName in photoBinNames.prefix(2) {
                    if let sampleFile = scanResult.photoFiles.first(where: {
                        cardConfig.fileSubfolderMap[$0.id] == binName
                    }) ?? scanResult.photoFiles.first {
                        let isRaw = ["cr3", "cr2", "arw", "nef", "raf", "dng"].contains(sampleFile.fileExtension.lowercased())
                        var photoPath = photoBase
                        if projectConfig.isMultiDayShoot { photoPath += "/\(dayLabel)" }
                        photoPath += "/\(binName)"
                        if projectConfig.splitRawJpeg {
                            photoPath += "/\(isRaw ? "RAW" : "JPEG")"
                        }
                        paths.append("\(photoPath)/\(sampleFile.fileName)")
                    }
                }
            } else if let sampleFile = scanResult.photoFiles.first {
                let isRaw = ["cr3", "cr2", "arw", "nef", "raf", "dng"].contains(sampleFile.fileExtension.lowercased())

                // Legacy: bouw foto-pad op
                var photoPath = photoBase
                if projectConfig.isMultiDayShoot { photoPath += "/\(dayLabel)" }
                for subfolder in cardConfig.effectivePhotoSubfolders {
                    photoPath += "/\(subfolder)"
                }
                if projectConfig.splitRawJpeg {
                    photoPath += "/\(isRaw ? "RAW" : "JPEG")"
                }
                paths.append("\(photoPath)/\(sampleFile.fileName)")
            }
        }

        // Wildtrack example
        if projectConfig.hasWildtrack && scanResult.hasAudio {
            let audioBase = basePaths.audioPath
            if projectConfig.isMultiDayShoot && projectConfig.linkAudioToDayStructure {
                paths.append("\(audioBase)/\(dayLabel)/Wildtrack/")
            } else {
                paths.append("\(audioBase)/Wildtrack/")
            }
        }

        // Prepend project name to all paths
        let projectPrefix = projectConfig.projectName
        return paths.map { projectPrefix + "/" + $0 }
    }

    var body: some View {
        DisclosureGroup(
            isExpanded: $isExpanded,
            content: {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(examplePaths, id: \.self) { path in
                        HStack(spacing: 6) {
                            Image(systemName: path.hasSuffix("/") ? "folder.fill" : "doc.fill")
                                .font(.system(size: 10))
                                .foregroundColor(path.hasSuffix("/") ? .accentColor : .secondary)
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    if examplePaths.isEmpty {
                        Text(String(localized: "filesafe.cardconfig.no_preview"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            },
            label: {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    Text(String(localized: "filesafe.cardconfig.path_preview"))
                        .font(.system(size: 12, weight: .medium))
                }
            }
        )
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        )
    }
}

// MARK: - Structure Preview

struct FileSafeStructurePreviewView: View {
    let tree: FileSafeTargetFolder
    let totalFiles: Int
    let totalSize: Int64
    let duplicateCount: Int
    let duplicateSize: Int64
    @Binding var skipDuplicates: Bool
    let onStartCopy: () -> Void
    let onBack: () -> Void

    private var filesToCopy: Int {
        skipDuplicates ? totalFiles - duplicateCount : totalFiles
    }

    private var sizeToCopy: Int64 {
        skipDuplicates ? totalSize - duplicateSize : totalSize
    }

    var body: some View {
        VStack(spacing: 0) {
            FileSafeNavBar(title: String(localized: "filesafe.preview.title"), onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // Summary
                    HStack {
                        Text(String(localized: "filesafe.preview.summary \(totalFiles)"))
                            .font(.system(size: 12))
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)

                    // Duplicate info blok
                    if duplicateCount > 0 {
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)

                                Text(String(localized: "filesafe.preview.duplicates \(duplicateCount)"))
                                    .font(.system(size: 12))

                                Spacer()

                                Text(ByteCountFormatter.string(fromByteCount: duplicateSize, countStyle: .file))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Toggle(isOn: $skipDuplicates) {
                                Text(String(localized: "filesafe.preview.skip_duplicates"))
                                    .font(.system(size: 12))
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)

                            if skipDuplicates {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Text(String(localized: "filesafe.preview.files_to_copy \(filesToCopy)"))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: sizeToCopy, countStyle: .file))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.08))
                        )
                        .padding(.bottom, 8)
                    }

                    // Folder structure tree (start bij project root)
                    FolderTreeRow(folder: tree, depth: 0)
                }
                .padding(12)
            }

            // Start copy
            Button(action: onStartCopy) {
                HStack {
                    Image(systemName: "doc.on.doc.fill")
                    if duplicateCount > 0 && skipDuplicates {
                        Text(String(localized: "filesafe.preview.files_to_copy \(filesToCopy)"))
                    } else {
                        Text(String(localized: "filesafe.preview.start_copy"))
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(12)
            .disabled(filesToCopy == 0)
        }
    }
}

struct FolderTreeRow: View {
    let folder: FileSafeTargetFolder
    let depth: Int
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                // Indentation
                if depth > 0 {
                    ForEach(0..<depth, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(width: 1)
                            .padding(.horizontal, 6)
                    }
                }

                // Expand/collapse
                if !folder.children.isEmpty {
                    Button(action: { withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                        .frame(width: 12)
                }

                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)

                Text(folder.displayName)
                    .font(.system(size: 12, weight: .medium))

                Spacer()

                if folder.totalFileCount > 0 {
                    Text("\(folder.totalFileCount)")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 22)

            if isExpanded {
                ForEach(folder.children) { child in
                    FolderTreeRow(folder: child, depth: depth + 1)
                }
            }
        }
    }
}

// MARK: - Copying View

struct FileSafeCopyingView: View {
    @ObservedObject var transfer: FileSafeTransfer
    let onPauseResume: () -> Void
    let onCancel: () -> Void
    var onBack: (() -> Void)? = nil
    var onNewImport: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let onBack = onBack {
                FileSafeNavBar(title: String(localized: "filesafe.copy.title"), onBack: onBack)
                Divider()
            }

            ScrollView {
                VStack(spacing: 16) {
                    if onBack == nil {
                        // Title alleen als er geen nav bar is
                        Text(String(localized: "filesafe.copy.title"))
                            .font(.system(size: 15, weight: .semibold))
                    }

                    // Overall progress bar
                    ProgressView(value: transfer.progress)
                        .progressViewStyle(.linear)

                    // File counter
                    Text("\(transfer.copiedCount) / \(transfer.totalCount)")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))

                    // Current file name
                    if !transfer.currentFile.isEmpty {
                        VStack(spacing: 2) {
                            Text(transfer.currentFile)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if !transfer.currentDestinationPath.isEmpty {
                                Text(transfer.currentDestinationPath)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }

                    // Speed and ETA
                    HStack(spacing: 16) {
                        if !transfer.copySpeed.isEmpty {
                            Label(transfer.copySpeed, systemImage: "gauge.with.dots.needle.33percent")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        if !transfer.estimatedTimeRemaining.isEmpty {
                            Label(transfer.estimatedTimeRemaining, systemImage: "clock")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    // Three verification step indicators
                    VStack(spacing: 6) {
                        Text(String(localized: "filesafe.copy.verification"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        VerificationStepRow(
                            label: String(localized: "filesafe.copy.step.size"),
                            icon: "doc.on.doc",
                            isComplete: transfer.currentFileSizeOK,
                            isActive: transfer.currentPhase == .copying
                        )

                        VerificationStepRow(
                            label: String(localized: "filesafe.copy.step.checksum"),
                            icon: "number.circle",
                            isComplete: transfer.currentFileChecksumOK,
                            isActive: transfer.currentPhase == .checksum
                        )

                        VerificationStepRow(
                            label: String(localized: "filesafe.copy.step.bytes"),
                            icon: "01.square",
                            isComplete: transfer.currentFileBytesOK,
                            isActive: transfer.currentPhase == .byteCompare
                        )
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                    )
                }
                .padding(12)
            }

            // Bottom bar with Pause/Resume and Cancel buttons
            VStack(spacing: 8) {
                Divider()

                HStack(spacing: 8) {
                    Button(action: onCancel) {
                        Label(String(localized: "filesafe.copy.cancel"), systemImage: "xmark.circle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)

                    Spacer()

                    if let onNewImport = onNewImport {
                        Button(action: onNewImport) {
                            Label(String(localized: "filesafe.dashboard.new_import"), systemImage: "plus.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button(action: onPauseResume) {
                        Label(
                            transfer.isPaused
                                ? String(localized: "filesafe.copy.resume")
                                : String(localized: "filesafe.copy.pause"),
                            systemImage: transfer.isPaused ? "play.fill" : "pause.fill"
                        )
                        .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }
}

struct VerificationStepRow: View {
    let label: String
    let icon: String
    let isComplete: Bool
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if isActive {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }
            .font(.system(size: 14))
            .frame(width: 18, height: 18)

            Text(label)
                .font(.system(size: 12))
                .foregroundColor(isComplete ? .primary : (isActive ? .primary : .secondary))

            Spacer()

            if isComplete {
                Text("OK")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
            }
        }
    }
}

// MARK: - Report View

struct FileSafeReportView: View {
    let report: FileSafeCopyReport
    let projectPath: String
    let onEject: () -> Void
    let onOpenFinder: () -> Void
    let onOpenReport: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Shield icon
                    Image(systemName: report.failCount == 0 ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 44))
                        .foregroundColor(report.failCount == 0 ? .green : .orange)

                    // Title
                    Text(String(localized: "filesafe.report.title"))
                        .font(.system(size: 15, weight: .semibold))

                    // Stats
                    VStack(spacing: 8) {
                        ReportStatRow(
                            icon: "checkmark.circle.fill",
                            color: .green,
                            label: String(localized: "filesafe.report.verified"),
                            value: "\(report.successCount)",
                            detail: "3/3 checks"
                        )

                        if report.warningCount > 0 {
                            ReportStatRow(
                                icon: "exclamationmark.triangle.fill",
                                color: .orange,
                                label: String(localized: "filesafe.report.warnings"),
                                value: "\(report.warningCount)",
                                detail: String(localized: "filesafe.report.retried")
                            )
                        }

                        if report.failCount > 0 {
                            ReportStatRow(
                                icon: "xmark.circle.fill",
                                color: .red,
                                label: String(localized: "filesafe.report.failed"),
                                value: "\(report.failCount)",
                                detail: ""
                            )
                        }

                        if report.skippedCount > 0 {
                            ReportStatRow(
                                icon: "arrow.triangle.2.circlepath",
                                color: .blue,
                                label: String(localized: "filesafe.report.skipped"),
                                value: "\(report.skippedCount)",
                                detail: ""
                            )
                        }

                        Divider()

                        HStack {
                            Text(String(localized: "filesafe.report.duration"))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(report.formattedDuration)
                                .font(.system(size: 12, weight: .medium))
                        }

                        HStack {
                            Text(String(localized: "filesafe.report.total_size"))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: report.totalSize, countStyle: .file))
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                    )

                    // Per-file results with three check marks
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "filesafe.report.file_results"))
                            .font(.system(size: 12, weight: .medium))

                        ForEach(report.results) { result in
                            HStack(spacing: 6) {
                                Image(systemName: result.isFullyVerified ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(result.isFullyVerified ? .green : .red)

                                Text(result.sourceFile.fileName)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                // Three verification check marks
                                HStack(spacing: 4) {
                                    VerificationCheckMark(label: String(localized: "filesafe.report.check.size"), passed: result.sizesMatch)
                                    VerificationCheckMark(label: "SHA-256", passed: result.checksumsMatch)
                                    VerificationCheckMark(label: "Bytes", passed: result.bytesMatch)
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                    )

                    // Failed files section
                    if report.failCount > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "filesafe.report.failed_files"))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)

                            ForEach(report.results.filter { !$0.isFullyVerified }) { result in
                                HStack {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 10))
                                        .foregroundColor(.red)
                                    Text(result.sourceFile.fileName)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(result.error ?? "Unknown")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red.opacity(0.05))
                        )
                    }
                }
                .padding(12)
            }

            // Action buttons
            VStack(spacing: 8) {
                Divider()

                HStack(spacing: 8) {
                    Button(action: onEject) {
                        Label(String(localized: "filesafe.report.eject"), systemImage: "eject.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: onOpenFinder) {
                        Label(String(localized: "filesafe.report.open_finder"), systemImage: "folder")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: onOpenReport) {
                        Label(String(localized: "filesafe.report.open_report"), systemImage: "doc.text")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    Button(action: onDone) {
                        Text(String(localized: "filesafe.report.done"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Verification Check Mark (for report per-file results)

struct VerificationCheckMark: View {
    let label: String
    let passed: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: passed ? "checkmark" : "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(passed ? .green : .red)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }
}

struct ReportStatRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 14))

            Text(label)
                .font(.system(size: 12))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))

            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Dashboard View

struct FileSafeDashboardView: View {
    @ObservedObject var transferManager: FileSafeTransferManager
    @Binding var selectedTransferId: UUID?
    let onNewImport: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Als een transfer geselecteerd is, toon detail view
            if let selectedId = selectedTransferId,
               let transfer = transferManager.transfers.first(where: { $0.id == selectedId }) {
                if transfer.isCompleted, let report = transfer.report {
                    // Rapport view
                    FileSafeReportView(
                        report: report,
                        projectPath: transfer.projectPath,
                        onEject: {},
                        onOpenFinder: {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: transfer.projectPath)
                        },
                        onOpenReport: {
                            let reportPath = FileSafeCopyEngine.txtReportPath(
                                projectName: transfer.projectName,
                                projectPath: transfer.projectPath,
                                footagePath: transfer.footagePath
                            )
                            NSWorkspace.shared.open(URL(fileURLWithPath: reportPath))
                        },
                        onDone: {
                            transferManager.removeTransfer(id: selectedId)
                            selectedTransferId = nil
                        }
                    )
                } else {
                    // Actieve copy view
                    FileSafeCopyingView(
                        transfer: transfer,
                        onPauseResume: {
                            if transfer.isPaused {
                                transferManager.resumeTransfer(id: selectedId)
                            } else {
                                transferManager.pauseTransfer(id: selectedId)
                            }
                        },
                        onCancel: {
                            transferManager.cancelTransfer(id: selectedId)
                            transferManager.removeTransfer(id: selectedId)
                            selectedTransferId = nil
                        },
                        onBack: { selectedTransferId = nil },
                        onNewImport: onNewImport
                    )
                }
            } else {
                // Transfer overzicht
                dashboardList
            }
        }
    }

    private var dashboardList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(String(localized: "filesafe.dashboard.title"))
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Button(action: onNewImport) {
                    Label(String(localized: "filesafe.dashboard.new_import"), systemImage: "plus.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if transferManager.transfers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(String(localized: "filesafe.dashboard.empty"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(transferManager.transfers) { transfer in
                            FileSafeTransferRow(transfer: transfer) {
                                withAnimation { selectedTransferId = transfer.id }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
}

// MARK: - Transfer Row

struct FileSafeTransferRow: View {
    @ObservedObject var transfer: FileSafeTransfer
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                // Top row: volume → project
                HStack(spacing: 6) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(transfer.volumeName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    Text(transfer.projectName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)

                    Spacer()

                    // Status indicator
                    if transfer.isCompleted {
                        Image(systemName: transfer.isFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(transfer.isFailed ? .orange : .green)
                    } else if transfer.isPaused {
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                }

                // Progress bar
                if transfer.isRunning {
                    ProgressView(value: transfer.progress)
                        .progressViewStyle(.linear)

                    // Stats row
                    HStack(spacing: 12) {
                        Text("\(transfer.copiedCount)/\(transfer.totalCount)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))

                        if !transfer.copySpeed.isEmpty {
                            Text(transfer.copySpeed)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        if !transfer.estimatedTimeRemaining.isEmpty {
                            Text(transfer.estimatedTimeRemaining)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if transfer.isPaused {
                            Text(String(localized: "filesafe.transfer.paused"))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.orange)
                        }
                    }
                } else if transfer.isCompleted {
                    HStack {
                        Text(String(localized: "filesafe.transfer.completed"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.green)

                        Text("\(transfer.totalCount) files")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(String(localized: "filesafe.transfer.view_report"))
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Transfer Status Bar (persistent bottom bar)

struct FileSafeTransferStatusBar: View {
    @ObservedObject var transferManager: FileSafeTransferManager
    let onTapTransfer: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(transferManager.transfers) { transfer in
                        FileSafeTransferStatusChip(transfer: transfer) {
                            onTapTransfer(transfer.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(Color(.windowBackgroundColor))
        }
    }
}

struct FileSafeTransferStatusChip: View {
    @ObservedObject var transfer: FileSafeTransfer
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Status icon
                if transfer.isCompleted {
                    Image(systemName: transfer.isFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(transfer.isFailed ? .orange : .green)
                } else if transfer.isPaused {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                } else {
                    // Mini spinner for active transfer
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }

                // Project name
                Text(transfer.projectName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)

                // Progress or status
                if transfer.isRunning && !transfer.isPaused {
                    Text("\(Int(transfer.progress * 100))%")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(.separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Help Button

struct FileSafeHelpButton: View {
    let text: String

    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented) {
            Text(text)
                .font(.system(size: 12))
                .padding(12)
                .frame(maxWidth: 250)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Project Sort Mode

enum ProjectSortMode: String, CaseIterable {
    case name
    case dateNewest
    case dateOldest

    var displayName: String {
        switch self {
        case .name: return String(localized: "filesafe.project.sort.name")
        case .dateNewest: return String(localized: "filesafe.project.sort.newest")
        case .dateOldest: return String(localized: "filesafe.project.sort.oldest")
        }
    }

    var icon: String {
        switch self {
        case .name: return "textformat.abc"
        case .dateNewest: return "calendar.badge.clock"
        case .dateOldest: return "calendar"
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String
    var badge: String? = nil
    var helpText: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let badge = badge {
                Text(badge)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())
            }
            if let helpText = helpText {
                FileSafeHelpButton(text: helpText)
            }
        }
    }
}

// MARK: - Nav Bar

struct FileSafeNavBar: View {
    let title: String
    var onBack: (() -> Void)? = nil

    var body: some View {
        HStack {
            if let onBack = onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
            }

            Text(title)
                .font(.system(size: 14, weight: .semibold))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Select Button

struct FileSafeSelectButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
