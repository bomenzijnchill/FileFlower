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
    var onTap: ((WizardStage) -> Void)? = nil

    private var currentStage: WizardStage? { WizardStage.stage(for: currentStep) }

    private enum StepState { case done, active, upcoming }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(WizardStage.allCases.enumerated()), id: \.element.id) { idx, stage in
                stepView(stage)
                if idx < WizardStage.allCases.count - 1 {
                    Text("›")
                        .font(.brandMono(size: 11))
                        .foregroundColor(Color(.tertiaryLabelColor))
                        .padding(.horizontal, 10)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fsSurface2)
        .overlay(alignment: .bottom) { Color.line.frame(height: 1) }
    }

    @ViewBuilder
    private func stepView(_ stage: WizardStage) -> some View {
        let state = stateFor(stage)
        Button(action: { if state == .done { onTap?(stage) } }) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(bg(state)).frame(width: 20, height: 20)
                    Group {
                        if state == .done {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.fsStepDoneInk)
                        } else {
                            Text("\(stage.rawValue)")
                                .font(.brandMono(size: 10.5, weight: .medium))
                                .foregroundColor(ink(state))
                        }
                    }
                }
                Text(stage.localizedLabel)
                    .font(.system(size: 12, weight: state == .active ? .semibold : .regular))
                    .foregroundColor(textColor(state))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(state == .done ? Color(.controlBackgroundColor).opacity(0.001) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state != .done)
    }

    private func stateFor(_ stage: WizardStage) -> StepState {
        guard let curr = currentStage else { return .upcoming }
        if stage.rawValue < curr.rawValue { return .done }
        if stage.rawValue == curr.rawValue { return .active }
        return .upcoming
    }

    private func bg(_ s: StepState) -> Color {
        switch s {
        case .done:     return .fsStepDoneBg
        case .active:   return .fsStepActiveBg
        case .upcoming: return .fsStepIdleBg
        }
    }

    private func ink(_ s: StepState) -> Color {
        switch s {
        case .done:     return .fsStepDoneInk
        case .active:   return .fsStepActiveInk
        case .upcoming: return .fsStepIdleInk
        }
    }

    private func textColor(_ s: StepState) -> Color {
        switch s {
        case .done:     return .ink2
        case .active:   return .ink
        case .upcoming: return Color(.tertiaryLabelColor)
        }
    }
}

// MARK: - Scan Status Bar

struct FileSafeScanStatusBar: View {
    let isActive: Bool
    let isDone: Bool
    let filesFound: Int
    let currentDirectory: String
    var onCancel: (() -> Void)? = nil

    @State private var pulse = false

    var body: some View {
        if !isActive && !isDone {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                Circle()
                    .fill(isDone ? Color.statusOk : Color.brandSkyBlue)
                    .frame(width: 8, height: 8)
                    .opacity(pulse && !isDone ? 0.4 : 1.0)

                Text(isDone
                     ? String(format: String(localized: "filesafe.scan.completed"), filesFound)
                     : (filesFound > 0
                        ? String(format: String(localized: "filesafe.scan.scanning_count"), filesFound)
                        : String(localized: "filesafe.scan.scanning")))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.ink)

                if !isDone && !currentDirectory.isEmpty {
                    Text(currentDirectory)
                        .font(.brandMono(size: 11))
                        .foregroundColor(.ink3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 200, alignment: .leading)
                }

                Spacer()

                if isDone {
                    ProgressView(value: 1.0)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 160)
                        .tint(.statusOk)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 160)
                        .tint(.brandSkyBlue)
                }

                if isActive, let cancel = onCancel {
                    Button(action: cancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.ink3)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "filesafe.scan.cancel"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [Color.fsBannerInfo, Color.brandTeaGreen.opacity(0.20)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .overlay(alignment: .bottom) { Color.line.frame(height: 1) }
            .onAppear {
                if !isDone {
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
            }
            .transition(.opacity)
        }
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
            FileSafeNavBar(title: String(localized: "filesafe.source.title"))

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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "filesafe.source.subtitle"))
                            .font(.system(size: 13))
                            .foregroundColor(.ink2)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 4)

                        ForEach(volumeDetector.externalVolumes) { volume in
                            VolumeRow(volume: volume) {
                                onSelect(volume)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct VolumeRow: View {
    let volume: ExternalVolume
    let onTap: () -> Void

    @State private var isHovered = false

    private var volumeIconName: String {
        switch volume.kind {
        case .sdCard: return "sdcard.fill"
        case .networkVolume: return "externaldrive.connected.to.line.below.fill"
        case .externalDrive, .unknown: return "externaldrive.fill"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Icon — gradient sandyClay → powderBlush
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [.brandSandyClay, .brandPowderBlush],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                    Image(systemName: volumeIconName)
                        .font(.system(size: 18))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(volume.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(.ink)
                        // "What the cable" — interface/soort-badge
                        if let transport = volume.transport, !transport.isEmpty {
                            Text(transport)
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(volume.kind == .sdCard ? Color.brandSkyBlue.opacity(0.18) : Color.line2.opacity(0.6))
                                .foregroundColor(.ink3)
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(volume.formattedTotalSize) · \(volume.formattedFreeSpace) \(String(localized: "filesafe.volume.free_suffix"))")
                        .font(.brandMono(size: 11))
                        .foregroundColor(.ink3)
                }

                Spacer()

                // Capacity bar + percentage
                HStack(spacing: 10) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.line2).frame(width: 64, height: 5)
                        Capsule()
                            .fill(volume.usedPercentage > 0.9 ? Color.statusWarn : Color.brandSkyBlue)
                            .frame(width: CGFloat(64 * volume.usedPercentage), height: 5)
                    }
                    Text("\(Int(volume.usedPercentage * 100))%")
                        .font(.brandMono(size: 11))
                        .foregroundColor(.ink3)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.fsCardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovered ? Color.line2 : Color.line, lineWidth: 1)
            )
            .shadow(color: isHovered ? Color.black.opacity(0.06) : Color.clear, radius: 4, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

// MARK: - Project Select

struct FileSafeProjectSelectView: View {
    @ObservedObject var appState: AppState
    @Binding var isNewProject: Bool
    @Binding var newProjectName: String
    @Binding var selectedProjectPath: String?
    @Binding var selectedProjectRootPath: String?
    var scanIsDone: Bool = true
    let onConfirm: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FileSafeNavBar(title: String(localized: "filesafe.destination.title"), onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(String(localized: "filesafe.destination.subtitle"))
                        .font(.system(size: 13))
                        .foregroundColor(.ink2)
                        .padding(.horizontal, 4)

                    // Segmented control — bestaand / nieuw
                    fsSegmented

                    if isNewProject {
                        newProjectContent
                    } else {
                        existingProjectContent
                    }
                }
                .padding(16)
            }

            // Confirm button + scan-status hint
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Text("‹ \(String(localized: "filesafe.action.back"))")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundColor(.ink2)

                Spacer()

                if !scanIsDone {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "filesafe.destination.waiting_scan"))
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }
                }
                Button(action: onConfirm) {
                    Text(String(localized: "filesafe.destination.next"))
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!canConfirm || !scanIsDone)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.fsSurface2)
            .overlay(alignment: .top) { Color.line.frame(height: 1) }
        }
        .task(id: appState.config.projectRoots) {
            let roots = appState.config.projectRoots
            loadedProjects = await Task.detached(priority: .userInitiated) {
                Self.scanProjects(roots: roots)
            }.value
        }
    }

    private var fsSegmented: some View {
        HStack(spacing: 2) {
            segmentedButton(
                title: String(localized: "filesafe.destination.tab.existing"),
                isActive: !isNewProject
            ) { isNewProject = false }
            segmentedButton(
                title: String(localized: "filesafe.destination.tab.new"),
                isActive: isNewProject
            ) { isNewProject = true }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.line.opacity(0.6))
        )
        .frame(maxWidth: 320)
    }

    @ViewBuilder
    private func segmentedButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                .foregroundColor(isActive ? .ink : .ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.fsCardBg : Color.clear)
                        .shadow(color: isActive ? Color.black.opacity(0.05) : .clear, radius: 1, y: 1)
                )
        }
        .buttonStyle(.plain)
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
    // Eénmalig van schijf geladen projecten; filteren/sorteren gebeurt goedkoop per render.
    @State private var loadedProjects: [ProjectListItem] = []

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

                // Gefilterde en gesorteerde projectlijst (goedkoop, uit de cache)
                let projects = filterAndSort(loadedProjects)
                if projects.isEmpty {
                    Text(String(localized: "filesafe.project.no_results"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    // NLE project altijd bovenaan tonen
                    if let nlePath = activeNLEProjectFolder {
                        let nleName = URL(fileURLWithPath: nlePath).lastPathComponent
                        // Path normaliseren om symlink- en trailing-slash-verschillen te ontwijken
                        // (mirrors JobServer.normalizePath semantics).
                        let normalizedNLE = URL(fileURLWithPath: nlePath).standardizedFileURL.path
                        let isExternal = !projects.contains(where: {
                            URL(fileURLWithPath: $0.path).standardizedFileURL.path == normalizedNLE
                        })
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
                                    Text(displayPath(nlePath))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    if isExternal {
                                        Text(String(localized: "filesafe.project.external"))
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
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

                    // Overige projecten (exclusief NLE project) — normalized om duplicaten te voorkomen
                    let normalizedActiveNLE = activeNLEProjectFolder.map {
                        URL(fileURLWithPath: $0).standardizedFileURL.path
                    }
                    ForEach(projects.filter {
                        URL(fileURLWithPath: $0.path).standardizedFileURL.path != normalizedActiveNLE
                    }) { project in
                        let isNLEActive = false // al bovenaan getoond
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

                                    Text(displayPath(project.path))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

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
        // Primair: project root anchoring
        for root in appState.config.projectRoots where !root.isEmpty {
            let rootPath = root.hasSuffix("/") ? root : root + "/"
            if nleFilePath.hasPrefix(rootPath) {
                let relativePath = String(nleFilePath.dropFirst(rootPath.count))
                if let projectName = relativePath.components(separatedBy: "/").first, !projectName.isEmpty {
                    return rootPath + projectName
                }
            }
        }

        // Fallback: klim omhoog door template-mappen
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
        // Primair: vers NLE project
        if let premierePath = JobServer.shared.activeProjectPath, JobServer.shared.isActiveProjectFresh {
            let resolved = resolveNLEProjectRoot(from: premierePath)
            #if DEBUG
            print("FileSafe: Premiere path (fresh): \(premierePath) → resolved: \(resolved)")
            #endif
            return resolved
        }
        if let resolvePath = JobServer.shared.resolveActiveProjectPath, JobServer.shared.isResolveActiveProjectFresh {
            return resolveNLEProjectRoot(from: resolvePath)
        }
        // Secondair: niet-vers maar wel bekend NLE project (heartbeat kan vertraagd zijn)
        if let premierePath = JobServer.shared.activeProjectPath {
            let resolved = resolveNLEProjectRoot(from: premierePath)
            #if DEBUG
            print("FileSafe: Premiere path (stale): \(premierePath) → resolved: \(resolved)")
            #endif
            return resolved
        }
        if let resolvePath = JobServer.shared.resolveActiveProjectPath {
            return resolveNLEProjectRoot(from: resolvePath)
        }
        // Fallback: AppState's activeProject
        if let active = appState.activeProject {
            return active.projectPath
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

    /// Schijf-scan van de project-roots. Zwaar werk (directory-listing + mtime per map),
    /// dus pure/static zodat het veilig off-main via `Task.detached` kan draaien.
    /// Bevat geen star-status — die wordt goedkoop in `filterAndSort` afgeleid zodat
    /// sterren live updaten zonder herscan.
    private static func scanProjects(roots: [String]) -> [ProjectListItem] {
        var result: [ProjectListItem] = []
        let fm = FileManager.default
        for root in roots {
            guard let contents = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents {
                let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                guard rv?.isDirectory == true else { continue }

                let name = url.lastPathComponent
                // Filter template/subfolder mappen (01_Adobe, FOOTAGE, etc.)
                let normalized = name.lowercased()
                    .replacingOccurrences(of: #"^\d+_"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if templateFolderBlocklist.contains(normalized) { continue }

                result.append(ProjectListItem(
                    id: url.path,
                    path: url.path,
                    name: name,
                    modificationDate: rv?.contentModificationDate,
                    isStarred: false
                ))
            }
        }
        return result
    }

    /// Goedkoop: filter + sorteer de gecachte lijst en leid star-status live af.
    /// Geen disk-I/O, dus veilig om bij elke render (bv. per toetsaanslag) aan te roepen.
    private func filterAndSort(_ projects: [ProjectListItem]) -> [ProjectListItem] {
        let starredSet = Set(appState.config.starredProjects)
        let withStars = projects.map { item in
            ProjectListItem(
                id: item.id,
                path: item.path,
                name: item.name,
                modificationDate: item.modificationDate,
                isStarred: starredSet.contains(item.path)
            )
        }

        // Filter
        let filtered: [ProjectListItem]
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            filtered = withStars
        } else {
            filtered = withStars.filter { $0.name.lowercased().contains(query) }
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

    /// Kort home-pad af tot `~/...` voor compacte weergave onder projectnamen.
    private func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
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
                title: {
                    switch category {
                    case .video: return String(localized: "filesafe.cardconfig.video_subfolders")
                    case .audio: return String(localized: "filesafe.cardconfig.audio_subfolders")
                    case .photo: return String(localized: "filesafe.cardconfig.photo_subfolders")
                    case .other: return ""
                    }
                }(),
                icon: {
                    switch category {
                    case .video: return "video"
                    case .audio: return "waveform"
                    case .photo: return "photo"
                    case .other: return "doc"
                    }
                }(),
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
                        Image(systemName: {
                            switch category {
                            case .video: return "film"
                            case .audio: return "waveform"
                            case .photo: return "photo"
                            case .other: return "doc"
                            }
                        }())
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

// MARK: - Interactive Path Segment

struct FileSafeInteractivePathSegment: View {
    let segment: PathSegment
    let projectPath: String?
    let parentRelativePath: String?
    let onValueChange: (String) -> Void
    var onDelete: (() -> Void)? = nil
    var dragPayload: String? = nil
    var onDropSegment: ((String) -> Void)? = nil
    var isRowHovered: Bool = false

    @State private var editingName = ""
    @State private var isEditing = false
    @State private var isDropTarget = false
    @State private var isChipHovered = false

    private var alternatives: [String] {
        guard let projectPath = projectPath,
              let parentRelative = parentRelativePath else { return [] }
        let parentURL = URL(fileURLWithPath: projectPath).appendingPathComponent(parentRelative)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.lastPathComponent }
            .sorted()
    }

    private var dropdownBasePath: String? {
        guard let projectPath = projectPath else { return nil }
        let parent = parentRelativePath ?? ""
        if parent.isEmpty { return projectPath }
        return (projectPath as NSString).appendingPathComponent(parent)
    }

    var body: some View {
        if segment.type == .token {
            // Token chip — {date}, {camera}, etc.
            tokenChip

        } else if segment.hasAlternatives {
            // Existing folder — sky-blue with dropdown
            existingFolderChip

        } else if segment.isNameEditable {
            // New folder — burnt-peach, dashed
            if isEditing {
                editingChip
            } else {
                newFolderChip
                    .modifier(SegmentDragDropModifier(
                        dragPayload: dragPayload,
                        onDropPayload: onDropSegment,
                        isDropTarget: $isDropTarget
                    ))
            }

        } else if segment.type == .projectName {
            projectChip

        } else if segment.type == .fileName {
            fileNameChip

        } else {
            // Fallback for non-editable category/subfolder segments
            staticChip
        }
    }

    // MARK: - Project Chip (green tint)

    private var projectChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 10))
                .opacity(0.55)
            Text(segment.value)
                .font(.brandMono(size: 12, weight: .semibold))
        }
        .foregroundColor(.pathProjectFg)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.pathProjectBg))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.pathProjectBorder, lineWidth: 1))
    }

    // MARK: - Existing Folder Chip (sky-blue)

    private var existingFolderChip: some View {
        HStack(spacing: 0) {
            PathSegmentDropdown(
                value: segment.value,
                alternatives: alternatives,
                basePath: dropdownBasePath,
                onValueChange: onValueChange
            )
        }
        .padding(.leading, 5)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isChipHovered ? Color.pathExistHoverBg : Color.pathExistBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isChipHovered ? Color.pathExistHoverBorder : Color.pathExistBorder, lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.pathExistUnderline)
                .frame(height: 2)
                .padding(.horizontal, 7)
                .offset(y: 3)
                .opacity(isChipHovered ? 1 : 0)
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isChipHovered = hovering }
        }
        .help(String(localized: "filesafe.pathviewer.click_for_alternatives"))
    }

    // MARK: - New Folder Chip (burnt-peach, dashed)

    private var newFolderChip: some View {
        HStack(spacing: 4) {
            Text("⋮⋮")
                .font(.system(size: 9))
                .foregroundColor(.pathNewHandle)
                .opacity(isRowHovered ? 1 : 0)
                .frame(width: isRowHovered ? 10 : 0)
                .clipped()

            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundColor(.pathNewFg)
                .opacity(0.85)

            Text(segment.value)
                .font(.brandMono(size: 12, weight: .medium))
                .foregroundColor(.pathNewFg)

            Button(action: {
                editingName = segment.value
                isEditing = true
            }) {
                Image(systemName: "pencil")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.pathNewFg.opacity(0.70))
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.clear))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .onHover { h in
                // Handled via cursor
            }

            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.pathNewFg.opacity(0.70))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(String(localized: "filesafe.pathviewer.remove_folder"))
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isDropTarget ? Color.accentColor.opacity(0.25)
                      : isChipHovered ? Color.pathNewHoverBg : Color.pathNewBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    isDropTarget ? Color.accentColor
                    : isChipHovered ? Color.pathNewBorder : Color.pathNewBorder,
                    style: StrokeStyle(
                        lineWidth: isDropTarget ? 1.5 : 1,
                        dash: isChipHovered ? [] : [4, 3]
                    )
                )
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isChipHovered = hovering }
        }
        .animation(.easeOut(duration: 0.15), value: isRowHovered)
    }

    // MARK: - Editing State

    private var editingChip: some View {
        TextField(segment.value, text: $editingName)
            .textFieldStyle(.plain)
            .font(.brandMono(size: 12, weight: .medium))
            .frame(minWidth: 60, maxWidth: 160)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(.textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.brandBurntPeach, lineWidth: 1))
            .shadow(color: Color.brandBurntPeach.opacity(0.15), radius: 3, x: 0, y: 0)
            .onSubmit {
                if !editingName.trimmingCharacters(in: .whitespaces).isEmpty {
                    onValueChange(editingName.trimmingCharacters(in: .whitespaces))
                }
                isEditing = false
            }
            .onAppear { editingName = segment.value }
    }

    // MARK: - Token Chip (tea-green, italic)

    private var tokenChip: some View {
        HStack(spacing: 2) {
            Text("⟨").opacity(0.55)
            Text(segment.value)
                .italic()
            Text("⟩").opacity(0.55)
        }
        .font(.brandMono(size: 12, weight: .medium))
        .foregroundColor(.pathTokenFg)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(
                    LinearGradient(
                        colors: [.pathTokenBgFrom, .pathTokenBgTo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.pathTokenBorder, lineWidth: 1))
        .help(String(localized: "filesafe.pathviewer.token_hint"))
    }

    // MARK: - Filename Chip

    private var fileNameChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.fill")
                .font(.system(size: 10))
                .opacity(0.45)
            Text(segment.value)
                .font(.brandMono(size: 12))
        }
        .foregroundColor(Color(.secondaryLabelColor))
        .padding(.horizontal, 9)
        .frame(height: 26)
    }

    // MARK: - Static Chip (fallback for non-editable segments)

    private var staticChip: some View {
        Text(segment.value)
            .font(.brandMono(size: 12, weight: .medium))
            .foregroundColor(Color(.secondaryLabelColor))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(.controlBackgroundColor).opacity(0.5)))
    }
}

// MARK: - Segment Drag/Drop Modifier

/// Past `.draggable` + `.dropDestination` conditioneel toe — alleen als er een
/// payload en drop callback zijn meegegeven. Gebruikt door editable path-segments
/// voor reordering binnen dezelfde categorie + positie (pre-day / post-day).
struct SegmentDragDropModifier: ViewModifier {
    let dragPayload: String?
    let onDropPayload: ((String) -> Void)?
    @Binding var isDropTarget: Bool

    func body(content: Content) -> some View {
        if let payload = dragPayload, let onDrop = onDropPayload {
            content
                .draggable(payload)
                .dropDestination(for: String.self) { items, _ in
                    guard let item = items.first else { return false }
                    onDrop(item)
                    return true
                } isTargeted: { targeted in
                    isDropTarget = targeted
                }
        } else {
            content
        }
    }
}

// MARK: - Path Insert Button (standalone, geen ForEach popover problemen)

/// Betrouwbare segment dropdown die AppKit NSMenu toont voor map-alternatieven
struct PathSegmentDropdown: NSViewRepresentable {
    let value: String
    let alternatives: [String]
    /// Absoluut pad van de map waar de alternatieven leven (parent-folder van dit segment).
    /// Nodig voor lazy drill-down submenus naar diepere niveaus.
    let basePath: String?
    /// Wordt aangeroepen met de nieuwe waarde — kan multi-segment zijn ("01_Raw/02_Reels")
    /// na drill-down. handleSegmentChange splitst en flattent multi-segment values.
    let onValueChange: (String) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .inline
        button.title = value + " ▾"
        button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.title = value + " ▾"
        context.coordinator.value = value
        context.coordinator.alternatives = alternatives
        context.coordinator.basePath = basePath
        context.coordinator.onValueChange = onValueChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: value, alternatives: alternatives, basePath: basePath, onValueChange: onValueChange)
    }

    class Coordinator: NSObject, NSMenuDelegate {
        var value: String
        var alternatives: [String]
        var basePath: String?
        var onValueChange: (String) -> Void

        /// Cache van disk children per absoluut pad (vermijd herhaalde I/O bij hover)
        private var childrenCache: [String: [String]] = [:]
        /// Map: submenu → (absoluut pad, relatief pad t.o.v. dit segment-niveau)
        private var menuPathMap: [ObjectIdentifier: (abs: String, rel: String)] = [:]
        /// Submenus die al gevuld zijn (vermijd dubbele populatie bij re-open)
        private var populatedMenus: Set<ObjectIdentifier> = []

        init(value: String, alternatives: [String], basePath: String?, onValueChange: @escaping (String) -> Void) {
            self.value = value
            self.alternatives = alternatives
            self.basePath = basePath
            self.onValueChange = onValueChange
        }

        @objc func showMenu(_ sender: NSButton) {
            // Reset state per menu-open — folders kunnen op disk gewijzigd zijn
            childrenCache.removeAll()
            menuPathMap.removeAll()
            populatedMenus.removeAll()

            let menu = NSMenu()
            menu.delegate = self

            // Top-level acties: Rename + New folder
            let renameItem = NSMenuItem(
                title: String(localized: "filesafe.pathviewer.rename_action"),
                action: #selector(renameTapped(_:)),
                keyEquivalent: ""
            )
            renameItem.target = self
            renameItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
            menu.addItem(renameItem)

            let newItem = NSMenuItem(
                title: String(localized: "filesafe.pathviewer.new_folder_action"),
                action: #selector(newFolderTapped(_:)),
                keyEquivalent: ""
            )
            newItem.target = self
            newItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
            menu.addItem(newItem)

            menu.addItem(.separator())

            // Sibling alternatieven met lazy drill-down submenus
            for alt in alternatives {
                let item = NSMenuItem(title: alt, action: #selector(itemSelected(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = alt
                item.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
                if alt == value {
                    item.state = .on
                }

                // Hang een leeg submenu op als deze map kinderen heeft (drill-down)
                if let basePath = basePath {
                    let childAbsPath = (basePath as NSString).appendingPathComponent(alt)
                    if hasSubfolders(at: childAbsPath) {
                        let submenu = NSMenu()
                        submenu.delegate = self
                        item.submenu = submenu
                        menuPathMap[ObjectIdentifier(submenu)] = (abs: childAbsPath, rel: alt)
                    }
                }

                menu.addItem(item)
            }

            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
        }

        // MARK: - NSMenuDelegate (lazy drill-down)

        func menuNeedsUpdate(_ menu: NSMenu) {
            let key = ObjectIdentifier(menu)
            guard let (absPath, relPath) = menuPathMap[key] else { return }
            // Vermijd dubbele populatie als gebruiker submenu opnieuw opent
            if populatedMenus.contains(key) { return }
            populatedMenus.insert(key)
            menu.removeAllItems()

            let children = childrenAt(absPath: absPath)
            if children.isEmpty {
                let emptyItem = NSMenuItem(
                    title: String(localized: "filesafe.pathviewer.empty_folder"),
                    action: nil,
                    keyEquivalent: ""
                )
                emptyItem.isEnabled = false
                menu.addItem(emptyItem)
                return
            }

            // Limiteer aantal kinderen om UI snappy te houden
            let limited = Array(children.prefix(500))
            for child in limited {
                let item = NSMenuItem(title: child, action: #selector(itemSelected(_:)), keyEquivalent: "")
                item.target = self
                let childRelPath = (relPath as NSString).appendingPathComponent(child)
                item.representedObject = childRelPath
                item.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)

                let childAbsPath = (absPath as NSString).appendingPathComponent(child)
                if hasSubfolders(at: childAbsPath) {
                    let submenu = NSMenu()
                    submenu.delegate = self
                    item.submenu = submenu
                    menuPathMap[ObjectIdentifier(submenu)] = (abs: childAbsPath, rel: childRelPath)
                }
                menu.addItem(item)
            }

            if children.count > limited.count {
                let truncated = NSMenuItem(
                    title: "…",
                    action: nil,
                    keyEquivalent: ""
                )
                truncated.isEnabled = false
                menu.addItem(truncated)
            }
        }

        private func childrenAt(absPath: String) -> [String] {
            if let cached = childrenCache[absPath] { return cached }
            let url = URL(fileURLWithPath: absPath)
            let result: [String]
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                result = contents
                    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                    .map { $0.lastPathComponent }
                    .sorted()
            } else {
                result = []
            }
            childrenCache[absPath] = result
            return result
        }

        private func hasSubfolders(at absPath: String) -> Bool {
            !childrenAt(absPath: absPath).isEmpty
        }

        // MARK: - Acties

        @objc func itemSelected(_ sender: NSMenuItem) {
            if let folder = sender.representedObject as? String {
                DispatchQueue.main.async {
                    self.onValueChange(folder)
                }
            }
        }

        @objc func renameTapped(_ sender: NSMenuItem) {
            let alert = NSAlert()
            alert.messageText = String(localized: "filesafe.pathviewer.rename_alert.title")
            alert.informativeText = String(localized: "filesafe.pathviewer.rename_alert.message")
            alert.addButton(withTitle: String(localized: "filesafe.pathviewer.rename_alert.confirm"))
            alert.addButton(withTitle: String(localized: "filesafe.pathviewer.day_remove_confirm.cancel"))

            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            textField.stringValue = value
            alert.accessoryView = textField

            // Schedule async — anders blokkeert het menu-tracking de modal
            let currentValue = value
            let callback = onValueChange
            DispatchQueue.main.async {
                if alert.runModal() == .alertFirstButtonReturn {
                    let name = textField.stringValue.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty && name != currentValue {
                        callback(name)
                    }
                }
            }
        }

        @objc func newFolderTapped(_ sender: NSMenuItem) {
            let alert = NSAlert()
            alert.messageText = String(localized: "filesafe.pathviewer.new_folder_alert.title")
            alert.informativeText = String(localized: "filesafe.pathviewer.new_folder_alert.message")
            alert.addButton(withTitle: String(localized: "filesafe.pathviewer.new_folder_alert.add"))
            alert.addButton(withTitle: String(localized: "filesafe.pathviewer.day_remove_confirm.cancel"))

            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            textField.placeholderString = String(localized: "filesafe.pathviewer.folder_name.placeholder")
            alert.accessoryView = textField

            let callback = onValueChange
            DispatchQueue.main.async {
                if alert.runModal() == .alertFirstButtonReturn {
                    let name = textField.stringValue.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        callback(name)
                    }
                }
            }
        }
    }
}

/// Betrouwbare insert-knop die een AppKit NSMenu toont (werkt altijd, ook in custom layouts)
struct PathInsertButton: NSViewRepresentable {
    let folders: [String]
    let onSelectFolder: (String) -> Void
    let onNewFolder: (String) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .inline
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "Insert folder")
        button.contentTintColor = .orange
        button.imageScaling = .scaleProportionallyUpOrDown
        // 13x13 past visueel bij 12pt monospaced "/" tekst (~14px cap height)
        button.setFrameSize(NSSize(width: 13, height: 13))
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.folders = folders
        context.coordinator.onSelectFolder = onSelectFolder
        context.coordinator.onNewFolder = onNewFolder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(folders: folders, onSelectFolder: onSelectFolder, onNewFolder: onNewFolder)
    }

    class Coordinator: NSObject {
        var folders: [String]
        var onSelectFolder: (String) -> Void
        var onNewFolder: (String) -> Void

        init(folders: [String], onSelectFolder: @escaping (String) -> Void, onNewFolder: @escaping (String) -> Void) {
            self.folders = folders
            self.onSelectFolder = onSelectFolder
            self.onNewFolder = onNewFolder
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()

            for folder in folders {
                let item = NSMenuItem(title: folder, action: #selector(folderSelected(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = folder
                item.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
                menu.addItem(item)
            }

            if !folders.isEmpty {
                menu.addItem(.separator())
            }

            let newItem = NSMenuItem(title: "New folder...", action: #selector(newFolderSelected(_:)), keyEquivalent: "")
            newItem.target = self
            newItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
            menu.addItem(newItem)

            // Positioneer het menu direct onder de knop
            let point = NSPoint(x: 0, y: sender.bounds.height + 4)
            menu.popUp(positioning: nil, at: point, in: sender)
        }

        @objc func folderSelected(_ sender: NSMenuItem) {
            if let folder = sender.representedObject as? String {
                DispatchQueue.main.async {
                    self.onSelectFolder(folder)
                }
            }
        }

        @objc func newFolderSelected(_ sender: NSMenuItem) {
            // Toon een alert met een tekstveld voor de nieuwe mapnaam
            let alert = NSAlert()
            alert.messageText = "Insert folder"
            alert.informativeText = "Enter a name for the new folder:"
            alert.addButton(withTitle: "Add")
            alert.addButton(withTitle: "Cancel")

            let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            textField.placeholderString = "Folder name..."
            alert.accessoryView = textField

            if let window = NSApp.keyWindow {
                alert.beginSheetModal(for: window) { response in
                    if response == .alertFirstButtonReturn {
                        let name = textField.stringValue.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            DispatchQueue.main.async {
                                self.onNewFolder(name)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Interactive Path

struct FileSafeInteractivePath: View {
    let segments: [PathSegment]
    let projectPath: String?
    let onSegmentChange: (PathSegment, String) -> Void
    var onInsertSegment: ((Int, String) -> Void)?
    var onSegmentDelete: ((PathSegment) -> Void)?
    var onSegmentReorder: ((String, PathSegment) -> Void)?
    var trailingBadge: String? = nil
    var isRowHovered: Bool = false

    private func subfoldersAt(relativePath: String) -> [String] {
        guard let projectPath = projectPath else { return [] }
        let url: URL
        if relativePath.isEmpty {
            url = URL(fileURLWithPath: projectPath)
        } else {
            url = URL(fileURLWithPath: projectPath).appendingPathComponent(relativePath)
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.lastPathComponent }
            .sorted()
    }

    private func shouldShowInsertButton(beforeIndex index: Int) -> Bool {
        guard index > 0, onInsertSegment != nil else { return false }
        let curr = segments[index]
        return curr.type == .dayFolder || curr.type == .fileName || curr.type == .binName
    }

    private func dragPayload(for segment: PathSegment, at index: Int) -> String? {
        guard segment.isNameEditable, let category = segment.category else { return nil }
        let dayIdx = segments.firstIndex(where: { $0.type == .dayFolder })
        let position: String
        if let dayIdx = dayIdx, index > dayIdx {
            position = "post"
        } else {
            position = "pre"
        }
        return "FS_SEG|\(category.rawValue)|\(position)|\(segment.value)"
    }

    var body: some View {
        FlowLayout(spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                if index > 0 {
                    if shouldShowInsertButton(beforeIndex: index) {
                        pathSeparator

                        PathInsertButton(
                            folders: subfoldersAt(relativePath: parentPath(for: index) ?? ""),
                            onSelectFolder: { folder in
                                onInsertSegment?(index, folder)
                            },
                            onNewFolder: { name in
                                onInsertSegment?(index, name)
                            }
                        )
                        .frame(width: 18, height: 18)
                        .opacity(isRowHovered ? 0.6 : 0)
                        .scaleEffect(isRowHovered ? 1 : 0.8)
                        .animation(.easeOut(duration: 0.15), value: isRowHovered)

                        pathSeparator
                    } else {
                        pathSeparator
                    }
                }

                FileSafeInteractivePathSegment(
                    segment: segment,
                    projectPath: projectPath,
                    parentRelativePath: parentPath(for: index),
                    onValueChange: { newValue in
                        onSegmentChange(segment, newValue)
                    },
                    onDelete: onSegmentDelete.map { callback in
                        { callback(segment) }
                    },
                    dragPayload: dragPayload(for: segment, at: index),
                    onDropSegment: onSegmentReorder.map { reorder in
                        { payload in reorder(payload, segment) }
                    },
                    isRowHovered: isRowHovered
                )
            }

            if let badge = trailingBadge, !badge.isEmpty {
                Text(badge)
                    .font(.brandMono(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    private var pathSeparator: some View {
        Text("/")
            .font(.brandMono(size: 12))
            .foregroundColor(Color(.secondaryLabelColor).opacity(0.45))
            .padding(.horizontal, 2)
    }

    private func parentPath(for index: Int) -> String? {
        guard index > 0 else { return nil }
        let parentSegments = segments.prefix(index).filter { $0.type != .projectName }
        if parentSegments.isEmpty { return "" }
        return parentSegments.map(\.value).joined(separator: "/")
    }
}

// MARK: - Path Preview

struct FileSafePathPreview: View {
    let projectConfig: FileSafeProjectConfig
    @Binding var cardConfig: FileSafeCardConfig
    let scanResult: FileSafeScanResult
    let folderPreset: FolderStructurePreset
    let customTemplate: CustomFolderTemplate?
    var projectPath: String? = nil

    @State private var isExpanded: Bool = true

    /// Segmented paths for interactive editing — builds PathSegment arrays for the path preview/editor
    private var segmentedPaths: [(segments: [PathSegment], isFolder: Bool, fileCount: Int)] {
        var result: [(segments: [PathSegment], isFolder: Bool, fileCount: Int)] = []
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "ddMMyyyy"

        let skipDayInPath = !projectConfig.isMultiDayShoot && !cardConfig.useDateSubfolder
        let dayLabel: String
        if skipDayInPath {
            dayLabel = ""
        } else if let firstDay = cardConfig.shootDays.first, let date = firstDay.date {
            if projectConfig.isMultiDayShoot {
                let localizedDay = String(localized: "filesafe.cardconfig.day \(1)")
                dayLabel = "\(localizedDay)_\(dayFormatter.string(from: date))"
            } else {
                dayLabel = dayFormatter.string(from: date)
            }
        } else {
            dayLabel = dayFormatter.string(from: Date())
        }

        // Zelfde resolutie-ingang als de daadwerkelijke plaatsing (incl. actieve template),
        // zodat de preview nooit een ander pad toont dan waar bestanden heen gaan.
        let basePaths = FileSafeStructureBuilder.shared.resolveBasePathsForDisplay(
            config: AppState.shared.config,
            projectName: projectConfig.projectName,
            existingProjectPath: projectPath
        )

        let videoBase: String
        let photoBase: String
        if basePaths.photosInFootage && scanResult.hasVideo && scanResult.hasPhoto {
            videoBase = "\(basePaths.footagePath)/Video"
            photoBase = "\(basePaths.footagePath)/Photo"
        } else {
            videoBase = basePaths.footagePath
            photoBase = basePaths.photoPath
        }

        // Helper: split een base path in segmenten, check of elke map op disk bestaat
        func baseSegments(_ base: String, category: FileSafeFileCategory) -> [PathSegment] {
            let parts = base.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            var currentPath = projectPath ?? ""
            return parts.map { part in
                currentPath = (currentPath as NSString).appendingPathComponent(part)
                let exists = FileManager.default.fileExists(atPath: currentPath)
                return PathSegment(type: .categoryFolder, value: part, category: category, existsOnDisk: exists)
            }
        }

        // Helper: bouw category segmenten op, inclusief eventuele customPathOverride
        func buildCategorySegments(_ defaultBase: [PathSegment], category: FileSafeFileCategory) -> [PathSegment] {
            let key = category.rawValue

            // Als er een custom path override is, gebruik die in plaats van de default base
            if let customPath = cardConfig.customPathOverride[key], !customPath.isEmpty {
                var currentPath = projectPath ?? ""
                return customPath.map { folder in
                    currentPath = (currentPath as NSString).appendingPathComponent(folder)
                    let exists = FileManager.default.fileExists(atPath: currentPath)
                    return PathSegment(type: .categoryFolder, value: folder, category: category, existsOnDisk: exists)
                }
            }

            // Geen override — gebruik default + eventuele insertedSubfolders
            var result = defaultBase
            if let inserted = cardConfig.insertedSubfolders[key] {
                for folder in inserted {
                    var checkPath = projectPath ?? ""
                    for seg in result where seg.type != .projectName {
                        checkPath = (checkPath as NSString).appendingPathComponent(seg.value)
                    }
                    checkPath = (checkPath as NSString).appendingPathComponent(folder)
                    let exists = FileManager.default.fileExists(atPath: checkPath)
                    result.append(PathSegment(type: .subfolder, value: folder, category: category, existsOnDisk: exists))
                }
            }
            return result
        }

        // Helper: voeg dag-segment toe
        func withDaySegment(_ base: [PathSegment]) -> [PathSegment] {
            guard !dayLabel.isEmpty else { return base }
            return base + [PathSegment(type: .dayFolder, value: dayLabel, existsOnDisk: false)]
        }

        // Helper: voeg postDaySubfolders toe ná de dagmap voor een specifieke categorie
        func appendPostDayFolders(_ base: [PathSegment], category: FileSafeFileCategory) -> [PathSegment] {
            let key = category.rawValue
            guard let postDay = cardConfig.postDaySubfolders[key], !postDay.isEmpty else {
                return base
            }
            // Bouw pad op voor existsOnDisk-check
            var checkPath = projectPath ?? ""
            for seg in base where seg.type != .projectName {
                checkPath = (checkPath as NSString).appendingPathComponent(seg.value)
            }
            var result = base
            for folder in postDay {
                checkPath = (checkPath as NSString).appendingPathComponent(folder)
                let exists = FileManager.default.fileExists(atPath: checkPath)
                result.append(PathSegment(type: .subfolder, value: folder, category: category, existsOnDisk: exists))
            }
            return result
        }

        // Helper: combineer dag + postDay in één pas (gebruikt door video/photo/audio paths)
        func withDayAndPostDay(_ base: [PathSegment], category: FileSafeFileCategory) -> [PathSegment] {
            return appendPostDayFolders(withDaySegment(base), category: category)
        }

        let projectSegment = PathSegment(type: .projectName, value: projectConfig.projectName, existsOnDisk: true)

        // Video segmented paths
        if scanResult.hasVideo {
            let videoBinNames = cardConfig.effectiveVideoBinNames

            // Rebuild: use override if set
            let effectiveVideoBase: String
            if let override = cardConfig.footageFolderOverride {
                let parentParts = videoBase.split(separator: "/", omittingEmptySubsequences: true).dropLast()
                if parentParts.isEmpty {
                    effectiveVideoBase = override
                } else {
                    effectiveVideoBase = parentParts.joined(separator: "/") + "/" + override
                }
            } else {
                effectiveVideoBase = videoBase
            }
            let vBaseSegs = baseSegments(effectiveVideoBase, category: .video)

            if !videoBinNames.isEmpty {
                for binName in videoBinNames.prefix(2) {
                    if let sampleFile = scanResult.videoFiles.first(where: {
                        cardConfig.fileSubfolderMap[$0.id] == binName
                    }) ?? scanResult.videoFiles.first {
                        var segs: [PathSegment] = [projectSegment] + withDayAndPostDay(buildCategorySegments(vBaseSegs, category: .video), category: .video)
                        segs.append(PathSegment(type: .binName, value: binName, category: .video))
                        segs.append(PathSegment(type: .fileName, value: sampleFile.fileName))
                        let cnt = scanResult.videoFiles.filter { cardConfig.fileSubfolderMap[$0.id] == binName }.count
                        result.append((segments: segs, isFolder: false, fileCount: cnt))
                    }
                }
                let assignedBins = Set(videoBinNames)
                let unassignedFiles = scanResult.videoFiles.filter {
                    guard let assignment = cardConfig.fileSubfolderMap[$0.id] else { return true }
                    return !assignedBins.contains(assignment)
                }
                if let unassigned = unassignedFiles.first {
                    var segs: [PathSegment] = [projectSegment] + withDayAndPostDay(buildCategorySegments(vBaseSegs, category: .video), category: .video)
                    segs.append(PathSegment(type: .fileName, value: unassigned.fileName))
                    result.append((segments: segs, isFolder: false, fileCount: unassignedFiles.count))
                }
            } else if let sampleFile = scanResult.videoFiles.first {
                var segs: [PathSegment] = [projectSegment] + withDayAndPostDay(buildCategorySegments(vBaseSegs, category: .video), category: .video)
                for subfolder in cardConfig.effectiveVideoSubfolders {
                    segs.append(PathSegment(type: .subfolder, value: subfolder))
                }
                segs.append(PathSegment(type: .fileName, value: sampleFile.fileName))
                result.append((segments: segs, isFolder: false, fileCount: scanResult.videoFiles.count))
            }
        }

        // Audio segmented paths
        if scanResult.hasAudio {
            let audioBase = cardConfig.audioFolderOverride ?? basePaths.audioPath
            let aBaseSegs = baseSegments(audioBase, category: .audio)
            let audioBinNames = cardConfig.effectiveAudioBinNames
            let useDayForAudio = projectConfig.linkAudioToDayStructure && projectConfig.isMultiDayShoot

            // Helper: bouw audio-base met of zonder dag-segment
            func audioBaseWithDay() -> [PathSegment] {
                let category = FileSafeFileCategory.audio
                if useDayForAudio {
                    return appendPostDayFolders(buildCategorySegments(aBaseSegs, category: category) + [PathSegment(type: .dayFolder, value: dayLabel)], category: category)
                } else {
                    // Geen dag voor audio — wel postDaySubfolders direct na base toepassen
                    return appendPostDayFolders(buildCategorySegments(aBaseSegs, category: category), category: category)
                }
            }

            if !audioBinNames.isEmpty {
                for binName in audioBinNames.prefix(2) {
                    if let sampleFile = scanResult.audioFiles.first(where: {
                        cardConfig.fileSubfolderMap[$0.id] == binName
                    }) ?? scanResult.audioFiles.first {
                        var segs: [PathSegment] = [projectSegment] + audioBaseWithDay()
                        segs.append(PathSegment(type: .binName, value: binName, category: .audio))
                        segs.append(PathSegment(type: .fileName, value: sampleFile.fileName))
                        let cnt = scanResult.audioFiles.filter { cardConfig.fileSubfolderMap[$0.id] == binName }.count
                        result.append((segments: segs, isFolder: false, fileCount: cnt))
                    }
                }
                let assignedBins = Set(audioBinNames)
                let unassignedFiles = scanResult.audioFiles.filter {
                    guard let assignment = cardConfig.fileSubfolderMap[$0.id] else { return true }
                    return !assignedBins.contains(assignment)
                }
                if let unassigned = unassignedFiles.first {
                    var segs: [PathSegment] = [projectSegment] + audioBaseWithDay()
                    segs.append(PathSegment(type: .fileName, value: unassigned.fileName))
                    result.append((segments: segs, isFolder: false, fileCount: unassignedFiles.count))
                }
            } else if let sampleFile = scanResult.audioFiles.first {
                if !projectConfig.audioPersons.isEmpty {
                    let person = projectConfig.audioPersons.first ?? "Person"
                    var segs: [PathSegment] = [projectSegment] + audioBaseWithDay()
                    segs.append(PathSegment(type: .subfolder, value: person))
                    segs.append(PathSegment(type: .fileName, value: sampleFile.fileName))
                    result.append((segments: segs, isFolder: false, fileCount: scanResult.audioFiles.count))
                } else {
                    var segs: [PathSegment] = [projectSegment] + audioBaseWithDay()
                    segs.append(PathSegment(type: .fileName, value: sampleFile.fileName))
                    result.append((segments: segs, isFolder: false, fileCount: scanResult.audioFiles.count))
                }
            }
        }

        // Photo segmented paths
        if scanResult.hasPhoto {
            let effectivePhotoBase = cardConfig.photoFolderOverride ?? photoBase
            let pBaseSegs = baseSegments(effectivePhotoBase, category: .photo)
            let photoBinNames = cardConfig.effectivePhotoBinNames

            // Helper: bouw photo-base met of zonder dag-segment via gemeenschappelijke pipeline
            func photoBaseWithDay() -> [PathSegment] {
                let category = FileSafeFileCategory.photo
                let withCustom = buildCategorySegments(pBaseSegs, category: category)
                if projectConfig.isMultiDayShoot {
                    return appendPostDayFolders(withCustom + [PathSegment(type: .dayFolder, value: dayLabel)], category: category)
                } else {
                    return appendPostDayFolders(withCustom, category: category)
                }
            }

            if !photoBinNames.isEmpty {
                for binName in photoBinNames.prefix(2) {
                    if let sampleFile = scanResult.photoFiles.first(where: {
                        cardConfig.fileSubfolderMap[$0.id] == binName
                    }) ?? scanResult.photoFiles.first {
                        let isRaw = ["cr3", "cr2", "arw", "nef", "raf", "dng"].contains(sampleFile.fileExtension.lowercased())
                        var segs: [PathSegment] = [projectSegment] + photoBaseWithDay()
                        segs.append(PathSegment(type: .binName, value: binName, category: .photo))
                        if projectConfig.splitRawJpeg {
                            segs.append(PathSegment(type: .subfolder, value: isRaw ? "RAW" : "JPEG"))
                        }
                        segs.append(PathSegment(type: .fileName, value: sampleFile.fileName))
                        let cnt = scanResult.photoFiles.filter { cardConfig.fileSubfolderMap[$0.id] == binName }.count
                        result.append((segments: segs, isFolder: false, fileCount: cnt))
                    }
                }
            } else if let sampleFile = scanResult.photoFiles.first {
                let isRaw = ["cr3", "cr2", "arw", "nef", "raf", "dng"].contains(sampleFile.fileExtension.lowercased())
                var segs: [PathSegment] = [projectSegment] + photoBaseWithDay()
                for subfolder in cardConfig.effectivePhotoSubfolders {
                    segs.append(PathSegment(type: .subfolder, value: subfolder))
                }
                if projectConfig.splitRawJpeg {
                    segs.append(PathSegment(type: .subfolder, value: isRaw ? "RAW" : "JPEG"))
                }
                segs.append(PathSegment(type: .fileName, value: sampleFile.fileName))
                result.append((segments: segs, isFolder: false, fileCount: scanResult.photoFiles.count))
            }
        }

        // Wildtrack
        if projectConfig.hasWildtrack && scanResult.hasAudio {
            let audioBase = cardConfig.audioFolderOverride ?? basePaths.audioPath
            let aBaseSegs = baseSegments(audioBase, category: .audio)
            let aSegsWithCustom = buildCategorySegments(aBaseSegs, category: .audio)
            if projectConfig.isMultiDayShoot && projectConfig.linkAudioToDayStructure {
                var segs: [PathSegment] = [projectSegment] + aSegsWithCustom
                segs.append(PathSegment(type: .dayFolder, value: dayLabel))
                segs.append(PathSegment(type: .subfolder, value: "Wildtrack"))
                result.append((segments: segs, isFolder: true, fileCount: 0))
            } else {
                var segs: [PathSegment] = [projectSegment] + aSegsWithCustom
                segs.append(PathSegment(type: .subfolder, value: "Wildtrack"))
                result.append((segments: segs, isFolder: true, fileCount: 0))
            }
        }

        return result
    }

    private func handleSegmentInsert(pathIndex: Int, segmentIndex: Int, folderName: String) {
        // Bepaal de categorie van het pad
        let paths = segmentedPaths
        guard pathIndex < paths.count else { return }
        let segments = paths[pathIndex].segments
        let category = segments.first(where: { $0.category != nil })?.category
        let key = category?.rawValue ?? "video"

        // Bepaal waar de gebruiker op "+" heeft geklikt.
        // segmentIndex verwijst naar de segment NÁ de +-knop.
        // Als die (of een segment ervoor) al voorbij de dagmap is, dan moet de
        // nieuwe map na de dagmap komen (in postDaySubfolders).
        guard segmentIndex > 0, segmentIndex <= segments.count else { return }

        // Vind eventuele dag-positie in het pad
        let dayIndex = segments.firstIndex(where: { $0.type == .dayFolder })
        let isAfterDay: Bool = {
            guard let dayIdx = dayIndex else { return false }
            // Insert komt NA de day als de +-positie (segmentIndex) > dayIdx
            return segmentIndex > dayIdx
        }()

        if isAfterDay {
            // Tussen dag en bin/file → postDaySubfolders
            // Positie binnen postDaySubfolders: tel hoeveel subfolders ná de dag al vóór
            // de insert-positie staan.
            let postDayExisting = segments[(dayIndex ?? -1) + 1 ..< segmentIndex]
                .filter { $0.type == .subfolder }
                .map(\.value)
            var currentPostDay = cardConfig.postDaySubfolders[key] ?? []
            // Vind index van de laatste "al bestaande post-day folder" in de lijst
            // en voeg ná die in. Als geen match → aan het eind toevoegen.
            if let lastExisting = postDayExisting.last,
               let idx = currentPostDay.firstIndex(of: lastExisting) {
                currentPostDay.insert(folderName, at: idx + 1)
            } else {
                currentPostDay.append(folderName)
            }
            cardConfig.postDaySubfolders[key] = currentPostDay
        } else {
            // Vóór dag (of geen dag aanwezig) → customPathOverride (pre-day keten)
            // Bouw de keten tot aan de +-positie op
            let preDaySegments = segments[..<segmentIndex]
                .filter { $0.type == .categoryFolder || $0.type == .subfolder }
                .map(\.value)
            // Huidige volledige keten (inclusief alles ná de insert-positie) zodat we
            // niet per ongeluk folders achter het +-punt verliezen
            let fullChain = segments
                .filter { $0.type == .categoryFolder || $0.type == .subfolder }
                .map(\.value)
            // Insert op positie = preDaySegments.count
            var newChain = fullChain
            newChain.insert(folderName, at: min(preDaySegments.count, newChain.count))
            cardConfig.customPathOverride[key] = newChain
        }
    }

    private func handleSegmentChange(_ segment: PathSegment, newValue: String) {
        switch segment.type {
        case .categoryFolder, .subfolder:
            // Bij wijziging van een map-segment: bouw het volledige customPathOverride op.
            // Match op category i.p.v. UUID: PathSegment.id wordt per render opnieuw
            // gegenereerd, dus een UUID-match faalt altijd.
            let key = segment.category?.rawValue ?? "video"

            // Vind een pad met dezelfde category als het gewijzigde segment
            let paths = segmentedPaths
            guard let entry = paths.first(where: { entry in
                entry.segments.first(where: { $0.category != nil })?.category == segment.category
            }) else { return }

            // Bepaal of dit segment in pre-day of post-day gebied staat
            let dayIndex = entry.segments.firstIndex(where: { $0.type == .dayFolder })
            let segmentIndex = entry.segments.firstIndex(where: {
                $0.type == segment.type && $0.value == segment.value && $0.category == segment.category
            })
            let isPostDay: Bool = {
                guard let segIdx = segmentIndex, let dayIdx = dayIndex else { return false }
                return segIdx > dayIdx
            }()

            // Split multi-segment newValue (bv. "01_Raw/02_Reels" via drill-down)
            // zodat elk segment een eigen entry in de chain wordt.
            let splitValues = newValue
                .split(separator: "/")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if isPostDay {
                // Pas postDaySubfolders aan
                var postDay = cardConfig.postDaySubfolders[key] ?? []
                if let idx = postDay.firstIndex(of: segment.value) {
                    postDay.replaceSubrange(idx...idx, with: splitValues)
                    cardConfig.postDaySubfolders[key] = postDay
                }
            } else {
                // Pas customPathOverride aan (volledige pre-day keten)
                var chain = entry.segments
                    .prefix(while: { $0.type != .dayFolder })
                    .filter { $0.type == .categoryFolder || $0.type == .subfolder }
                    .map(\.value)
                if let idx = chain.firstIndex(of: segment.value) {
                    chain.replaceSubrange(idx...idx, with: splitValues)
                }
                cardConfig.customPathOverride[key] = chain
            }

        case .binName:
            if segment.category == .video {
                if let idx = cardConfig.videoBins.firstIndex(where: { $0.name == segment.value }) {
                    cardConfig.videoBins[idx].name = newValue
                }
            } else if segment.category == .photo {
                if let idx = cardConfig.photoBins.firstIndex(where: { $0.name == segment.value }) {
                    cardConfig.photoBins[idx].name = newValue
                }
            }

        case .dayFolder:
            // Dag label wijzigen
            if let dayIndex = cardConfig.shootDays.firstIndex(where: {
                $0.displayName == segment.value || $0.displayName(isMultiDay: true) == segment.value
            }) {
                cardConfig.shootDays[dayIndex].label = newValue
            }

        default:
            break
        }
    }

    /// Verwijder een door FF aangemaakte folder uit pre-day of post-day list
    private func handleSegmentDelete(_ segment: PathSegment) {
        // Day-folder segment: single-day flipt useDateSubfolder=false direct.
        // Multi-day toont confirm-dialog (verlies van dag-distinctie is destructief).
        if segment.type == .dayFolder {
            if !projectConfig.isMultiDayShoot {
                cardConfig.useDateSubfolder = false
            } else {
                let alert = NSAlert()
                alert.messageText = String(localized: "filesafe.pathviewer.day_remove_confirm.title")
                alert.informativeText = String(localized: "filesafe.pathviewer.day_remove_confirm.message")
                alert.alertStyle = .warning
                alert.addButton(withTitle: String(localized: "filesafe.pathviewer.day_remove_confirm.confirm"))
                alert.addButton(withTitle: String(localized: "filesafe.pathviewer.day_remove_confirm.cancel"))
                if alert.runModal() == .alertFirstButtonReturn {
                    cardConfig.useDateSubfolder = false
                }
            }
            return
        }

        guard let category = segment.category else { return }
        let key = category.rawValue

        // Verwijder uit postDaySubfolders als het daar in staat
        if var postDay = cardConfig.postDaySubfolders[key],
           let idx = postDay.firstIndex(of: segment.value) {
            postDay.remove(at: idx)
            cardConfig.postDaySubfolders[key] = postDay.isEmpty ? nil : postDay
            return
        }

        // Anders uit customPathOverride verwijderen
        if var chain = cardConfig.customPathOverride[key],
           let idx = chain.firstIndex(of: segment.value) {
            chain.remove(at: idx)
            cardConfig.customPathOverride[key] = chain.isEmpty ? nil : chain
            return
        }

        // Fallback: insertedSubfolders (oudere toevoegmethode)
        if var inserted = cardConfig.insertedSubfolders[key],
           let idx = inserted.firstIndex(of: segment.value) {
            inserted.remove(at: idx)
            cardConfig.insertedSubfolders[key] = inserted.isEmpty ? nil : inserted
        }
    }

    /// Herorder een segment binnen dezelfde categorie + positie (pre-day / post-day).
    /// Cross-category of cross-position drops worden genegeerd.
    private func handleSegmentReorder(payload: String, target: PathSegment) {
        // Payload parse: "FS_SEG|{category}|{position}|{value}"
        let parts = payload.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "FS_SEG" else { return }
        let srcCategory = String(parts[1])
        let srcPosition = String(parts[2])
        let srcValue = String(parts[3])

        // Doel moet een category hebben en editable zijn
        guard let targetCategory = target.category?.rawValue,
              target.isNameEditable else { return }

        // Vind target segment in segmentedPaths om zijn positie te bepalen
        let paths = segmentedPaths
        guard let entry = paths.first(where: { entry in
            entry.segments.first(where: { $0.category != nil })?.category?.rawValue == targetCategory
        }) else { return }

        let dayIdx = entry.segments.firstIndex(where: { $0.type == .dayFolder })
        let targetIdx = entry.segments.firstIndex(where: {
            $0.type == target.type && $0.value == target.value && $0.category == target.category
        })
        let targetPosition: String
        if let targetIdx = targetIdx, let dayIdx = dayIdx, targetIdx > dayIdx {
            targetPosition = "post"
        } else {
            targetPosition = "pre"
        }

        // Beperking: alleen binnen dezelfde categorie + positie
        guard srcCategory == targetCategory, srcPosition == targetPosition else { return }
        guard srcValue != target.value else { return } // drop op zichzelf → no-op

        // Pas de juiste lijst aan.
        // Na remove op fromIdx schuiven items ná die index één plek op; insert op
        // targets originele toIdx plaatst het gesleepte item dus op de positie van
        // het target — target zelf schuift naar rechts (bij forward drag) of
        // behoudt zijn relatieve volgorde (bij backward drag).
        if srcPosition == "post" {
            var list = cardConfig.postDaySubfolders[srcCategory] ?? []
            guard let fromIdx = list.firstIndex(of: srcValue),
                  let toIdx = list.firstIndex(of: target.value),
                  fromIdx != toIdx else { return }
            let moved = list.remove(at: fromIdx)
            list.insert(moved, at: min(toIdx, list.count))
            cardConfig.postDaySubfolders[srcCategory] = list
        } else {
            var list = cardConfig.customPathOverride[srcCategory] ?? []
            guard let fromIdx = list.firstIndex(of: srcValue),
                  let toIdx = list.firstIndex(of: target.value),
                  fromIdx != toIdx else { return }
            let moved = list.remove(at: fromIdx)
            list.insert(moved, at: min(toIdx, list.count))
            cardConfig.customPathOverride[srcCategory] = list
        }
    }

    // MARK: - Category Grouping

    private struct CategoryGroup: Identifiable {
        let id: String
        let category: FileSafeFileCategory
        var paths: [(index: Int, segments: [PathSegment], isFolder: Bool, fileCount: Int)]
    }

    private var groupedCategories: [CategoryGroup] {
        let paths = segmentedPaths
        var groups: [String: CategoryGroup] = [:]
        var order: [String] = []

        for (index, entry) in paths.enumerated() {
            let cat = entry.segments.first(where: { $0.category != nil })?.category ?? .other
            let key = cat.rawValue
            if groups[key] == nil {
                groups[key] = CategoryGroup(id: key, category: cat, paths: [])
                order.append(key)
            }
            groups[key]?.paths.append((index: index, segments: entry.segments, isFolder: entry.isFolder, fileCount: entry.fileCount))
        }
        return order.compactMap { groups[$0] }
    }

    private func categoryFileCount(_ category: FileSafeFileCategory) -> Int {
        switch category {
        case .video: return scanResult.videoCount
        case .audio: return scanResult.audioCount
        case .photo: return scanResult.photoCount
        case .other: return scanResult.otherFiles.count
        }
    }

    private func categoryFileSize(_ category: FileSafeFileCategory) -> String {
        let bytes: Int64
        switch category {
        case .video: bytes = scanResult.videoFiles.reduce(0) { $0 + $1.fileSize }
        case .audio: bytes = scanResult.audioFiles.reduce(0) { $0 + $1.fileSize }
        case .photo: bytes = scanResult.photoFiles.reduce(0) { $0 + $1.fileSize }
        case .other: bytes = scanResult.otherFiles.reduce(0) { $0 + $1.fileSize }
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func categoryDotColor(_ category: FileSafeFileCategory) -> Color {
        switch category {
        case .video: return .pathDotVideo
        case .audio: return .pathDotAudio
        case .photo: return .pathDotPhoto
        case .other: return Color(.secondaryLabelColor)
        }
    }

    var body: some View {
        DisclosureGroup(
            isExpanded: $isExpanded,
            content: {
                VStack(alignment: .leading, spacing: 14) {
                    // Legend
                    PathEditorLegend(totalFiles: scanResult.files.count)

                    if groupedCategories.isEmpty {
                        Text(String(localized: "filesafe.cardconfig.no_preview"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(groupedCategories) { group in
                            PathEditorCategoryRow(
                                category: group.category,
                                dotColor: categoryDotColor(group.category),
                                fileCount: categoryFileCount(group.category),
                                fileSize: categoryFileSize(group.category),
                                paths: group.paths,
                                projectPath: projectPath,
                                onSegmentChange: handleSegmentChange,
                                onSegmentInsert: handleSegmentInsert,
                                onSegmentDelete: handleSegmentDelete,
                                onSegmentReorder: handleSegmentReorder
                            )
                        }
                    }

                    // Token dock
                    PathEditorTokenDock()
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

// MARK: - Path Editor Legend

private struct PathEditorLegend: View {
    let totalFiles: Int

    var body: some View {
        HStack(spacing: 14) {
            legendItem(color: .pathExistBg, border: .pathExistBorder, dashed: false, label: String(localized: "filesafe.legend.exists"))
            legendItem(color: .pathNewBg, border: .pathNewBorder, dashed: true, label: String(localized: "filesafe.legend.created"))
            legendItem(color: .pathTokenBgFrom, border: .pathTokenBorder, dashed: false, label: "Token")
            legendItem(color: Color(.controlBackgroundColor).opacity(0.5), border: .line, dashed: false, label: String(localized: "filesafe.legend.file"))

            Spacer()

            Text("Live preview · \(totalFiles) \(String(localized: "filesafe.legend.files_label"))")
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
        }
        .padding(.horizontal, 2)
    }

    private func legendItem(color: Color, border: Color, dashed: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(border, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : []))
                )
                .frame(width: 12, height: 12)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
        }
    }
}

// MARK: - Path Editor Category Row

private struct PathEditorCategoryRow: View {
    let category: FileSafeFileCategory
    let dotColor: Color
    let fileCount: Int
    let fileSize: String
    let paths: [(index: Int, segments: [PathSegment], isFolder: Bool, fileCount: Int)]
    let projectPath: String?
    let onSegmentChange: (PathSegment, String) -> Void
    let onSegmentInsert: (Int, Int, String) -> Void
    let onSegmentDelete: (PathSegment) -> Void
    let onSegmentReorder: (String, PathSegment) -> Void

    @State private var isRowHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 9, height: 9)
                    Text(category.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                }

                HStack(spacing: 4) {
                    Text("\(fileCount)")
                        .font(.brandMono(size: 11, weight: .medium))
                        .foregroundColor(.ink2)
                    Text(String(localized: "filesafe.legend.files_label"))
                        .font(.system(size: 11.5))
                        .foregroundColor(Color(.secondaryLabelColor))
                    Text("·")
                        .foregroundColor(Color(.secondaryLabelColor))
                    Text(fileSize)
                        .font(.brandMono(size: 11, weight: .medium))
                        .foregroundColor(.ink2)
                }

                Spacer()

                if fileCount > 0 {
                    HStack(spacing: 4) {
                        Text("+ \(fileCount)")
                            .font(.brandMono(size: 10.5, weight: .semibold))
                            .foregroundColor(.pathProjectFg)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.pathProjectBg))
                        Text(String(localized: "filesafe.patheditor.go_here"))
                            .font(.system(size: 11))
                            .foregroundColor(Color(.secondaryLabelColor))
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Color.pathRowHeaderBg)

            Divider().opacity(0.5)

            // Path chips
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(paths.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 4) {
                        Text("⌂")
                            .font(.system(size: 13))
                            .foregroundColor(Color(.secondaryLabelColor))
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(.controlBackgroundColor).opacity(0.5)))

                        FileSafeInteractivePath(
                            segments: entry.segments,
                            projectPath: projectPath,
                            onSegmentChange: onSegmentChange,
                            onInsertSegment: { segIndex, folderName in
                                onSegmentInsert(entry.index, segIndex, folderName)
                            },
                            onSegmentDelete: onSegmentDelete,
                            onSegmentReorder: onSegmentReorder,
                            trailingBadge: entry.fileCount > 1
                                ? String(format: String(localized: "filesafe.pathviewer.files_count_suffix"), entry.fileCount - 1)
                                : nil,
                            isRowHovered: isRowHovered
                        )
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)

            Divider().opacity(0.5)

            // Footer hints
            HStack(spacing: 14) {
                hintItem(kbd: "Enter", label: String(localized: "filesafe.patheditor.hint_confirm"))
                hintItem(kbd: "⌫", label: String(localized: "filesafe.patheditor.hint_delete"))
                hintItem(kbd: "drag", label: String(localized: "filesafe.patheditor.hint_reorder"))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(Color.pathRowHeaderBg)
        }
        .background(Color.pathRowBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.line, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isRowHovered = hovering }
        }
    }

    private func hintItem(kbd: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(kbd)
                .font(.brandMono(size: 10))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.line2, lineWidth: 1))
                )
                .foregroundColor(.ink2)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(.secondaryLabelColor))
        }
    }
}

// MARK: - Path Editor Token Dock

private struct PathEditorTokenDock: View {
    private let tokens = ["date", "camera", "project", "day"]

    var body: some View {
        HStack(spacing: 8) {
            Text(String(localized: "filesafe.patheditor.token_dock_label"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.ink2)

            ForEach(tokens, id: \.self) { token in
                Text("{\(token)}")
                    .font(.brandMono(size: 11))
                    .foregroundColor(.pathTokenFg)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.pathTokenBgFrom.opacity(0.4))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.pathTokenBorder, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    )
                    .draggable("TOKEN|\(token)")
            }

            Spacer()

            Text(String(localized: "filesafe.patheditor.token_dock_hint"))
                .font(.system(size: 10.5))
                .foregroundColor(Color(.secondaryLabelColor))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.paper2)
        .overlay(alignment: .top) {
            Color.line.frame(height: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
    var footagePath: String? = nil
    var isNewProject: Bool = false
    var projectName: String = ""
    let onEject: () -> Void
    let onOpenFinder: () -> Void
    let onOpenReport: () -> Void
    let onDone: () -> Void

    @State private var importProjectFiles: [URL] = []
    @State private var isScanningForProjects: Bool = false
    @State private var showingProjectPicker: Bool = false
    @State private var showingNLEPicker: Bool = false
    @State private var importStatus: String? = nil
    @State private var importWatcherTask: Task<Void, Never>? = nil
    @State private var importStatusPollTask: Task<Void, Never>? = nil

    /// Of de gekozen projectmap een .prproj/.drp bevat. Default true bij `isNewProject == false`
    /// om text-flicker tijdens scan te vermijden (zie Item 11 in plan).
    @State private var hasExistingProjectFile: Bool = true
    @State private var isCheckingProjectFiles: Bool = false

    /// Bestanden die succesvol (3/3 checks) zijn gekopieerd en beschikbaar om te importeren.
    private var importableFiles: [String] {
        report.results
            .filter { $0.isFullyVerified }
            .map { $0.destinationPath }
    }

    private var hasImportableFiles: Bool {
        !importableFiles.isEmpty
    }

    /// "Nieuw project" indien expliciet als nieuw aangemerkt, of indien de gekozen
    /// bestaande map geen NLE-projectbestand bevat (.prproj/.drp).
    private var effectiveIsNewProject: Bool {
        isNewProject || !hasExistingProjectFile
    }

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

            // Action buttons + Import Footage
            VStack(spacing: 8) {
                Divider()

                // Import footage — alleen tonen bij succesvolle transfer
                if hasImportableFiles {
                    importFootageButton
                        .padding(.horizontal, 12)
                        .padding(.top, 4)

                    if let status = importStatus {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                            Text(status)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                            if importWatcherTask != nil {
                                Button(String(localized: "filesafe.report.import.cancel_watch")) {
                                    importWatcherTask?.cancel()
                                    importWatcherTask = nil
                                    importStatus = nil
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                }

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

                    Button(action: {
                        importWatcherTask?.cancel()
                        importWatcherTask = nil
                        onDone()
                    }) {
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
        .onDisappear {
            importWatcherTask?.cancel()
            importWatcherTask = nil
            importStatusPollTask?.cancel()
            importStatusPollTask = nil
        }
        .onAppear {
            // Item 11: detecteer of de gekozen "bestaande" map daadwerkelijk een
            // NLE-projectbestand bevat. Zo niet → behandel als nieuw project zodat
            // de gebruiker via de NLE-picker een nieuw .prproj/.drp kan aanmaken.
            guard !isNewProject else {
                hasExistingProjectFile = false
                return
            }
            isCheckingProjectFiles = true
            Task {
                let files = await ProjectScanner.shared.findProjectFiles(in: projectPath)
                await MainActor.run {
                    hasExistingProjectFile = !files.isEmpty
                    isCheckingProjectFiles = false
                }
            }
        }
    }

    // MARK: - Import Footage knop

    @ViewBuilder
    private var importFootageButton: some View {
        Button(action: handleImportTap) {
            HStack(spacing: 8) {
                if isScanningForProjects || importWatcherTask != nil {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: effectiveIsNewProject
                          ? "plus.rectangle.on.folder.fill"
                          : "square.and.arrow.down.on.square.fill")
                        .font(.system(size: 14))
                }
                Text(importButtonLabel)
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isScanningForProjects)
        .popover(isPresented: $showingProjectPicker) {
            NLEProjectFilesPopover(
                files: importProjectFiles,
                emptyMessage: String(localized: "filesafe.report.import.no_project"),
                onPick: { url in
                    showingProjectPicker = false
                    startImport(using: url)
                }
            )
        }
        .popover(isPresented: $showingNLEPicker) {
            newProjectNLEPicker
        }
    }

    private var importButtonLabel: String {
        if effectiveIsNewProject {
            return String(localized: "filesafe.report.import.create_new")
        } else {
            let name = projectName.isEmpty
                ? URL(fileURLWithPath: projectPath).lastPathComponent
                : projectName
            return String(format: String(localized: "filesafe.report.import.existing"), name)
        }
    }

    // MARK: - Nieuwe-project NLE picker

    private var newProjectNLEPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "filesafe.report.import.pick_nle"))
                .font(.system(size: 12, weight: .semibold))

            ForEach(NLEType.allCases, id: \.self) { nle in
                Button {
                    showingNLEPicker = false
                    launchNLEAndWatch(nle: nle)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: nle.icon)
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                        Text(nle.displayName)
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 220)
    }

    // MARK: - Acties

    private func handleImportTap() {
        importStatus = nil
        if effectiveIsNewProject {
            showingNLEPicker = true
        } else {
            // Scan naar NLE projectbestanden in de projectmap
            isScanningForProjects = true
            Task {
                let files = await ProjectScanner.shared.findProjectFiles(in: projectPath)
                await MainActor.run {
                    importProjectFiles = files
                    isScanningForProjects = false

                    if files.count == 1 {
                        // Direct importeren
                        startImport(using: files[0])
                    } else {
                        // 0 of >1: toon popover
                        showingProjectPicker = true
                    }
                }
            }
        }
    }

    private func startImport(using projectURL: URL) {
        let nle = NLEType.from(projectPath: projectURL.path) ?? .premiere
        let dateString = DateFormatter.localizedString(
            from: Date(),
            dateStyle: .none,
            timeStyle: .short
        )
        let binPath = "FileSafe Import \(dateString)"

        let targetDir = footagePath ?? projectPath
        let job = JobRequest(
            projectPath: projectURL.path,
            finderTargetDir: targetDir,
            premiereBinPath: binPath,
            files: importableFiles,
            assetType: "footage",
            nleType: nle
        )
        let jobId = job.id
        JobServer.shared.addJob(job)
        NLEChecker.shared.bringToFront(nle)

        importStatus = String(
            format: String(localized: "filesafe.report.import.queued"),
            importableFiles.count
        )

        // Poll JobServer zodat de gebruiker ziet of de plugin de job heeft
        // opgehaald, of dat de heartbeat nog niet matcht.
        importStatusPollTask?.cancel()
        importStatusPollTask = Task { @MainActor in
            let start = Date()
            var lastStatus: String?
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                let state = JobServer.shared.jobState(id: jobId)
                switch state {
                case .pending:
                    let elapsed = Int(Date().timeIntervalSince(start))
                    let key: String.LocalizationValue = elapsed > 30
                        ? "filesafe.report.import.waiting_long"
                        : "filesafe.report.import.waiting"
                    let status = String(format: String(localized: key), elapsed)
                    if status != lastStatus {
                        importStatus = status
                        lastStatus = status
                    }
                case .inProgress:
                    let status = String(localized: "filesafe.report.import.importing")
                    if status != lastStatus {
                        importStatus = status
                        lastStatus = status
                    }
                case .completed(let result):
                    importStatus = String(
                        format: String(localized: "filesafe.report.import.done"),
                        result.importedFiles.count
                    )
                    return
                case .unknown:
                    return
                }
            }
        }
    }

    /// Voor nieuwe projecten: open de NLE en wacht tot er een projectbestand op disk verschijnt.
    private func launchNLEAndWatch(nle: NLEType) {
        // Open de NLE applicatie
        let bundleId: String
        switch nle {
        case .premiere: bundleId = "com.adobe.PremierePro"
        case .resolve: bundleId = "com.blackmagic-design.DaVinciResolve"
        }
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)

        // Als de NLE niet geïnstalleerd én niet actief is: meld dit direct i.p.v. 10 min te wachten.
        if appURL == nil && !NLEChecker.shared.isRunning(nle) {
            importStatus = String(
                format: String(localized: "filesafe.report.import.nle_unavailable"),
                nle.displayName
            )
            return
        }

        if let appURL = appURL {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                if error != nil {
                    Task { @MainActor in
                        importStatus = String(
                            format: String(localized: "filesafe.report.import.nle_unavailable"),
                            nle.displayName
                        )
                    }
                }
            }
        } else {
            NLEChecker.shared.bringToFront(nle)
        }

        importStatus = String(
            format: String(localized: "filesafe.report.import.watching"),
            nle.displayName
        )

        // Start watcher: elke 3s scannen of er een .prproj/.drp in de projectmap verschijnt
        importWatcherTask?.cancel()
        importWatcherTask = Task {
            let maxSeconds = 600.0 // 10 minuten
            let pollInterval: UInt64 = 3_000_000_000 // 3s
            let start = Date()

            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                if elapsed > maxSeconds { break }

                let files = await ProjectScanner.shared.findProjectFiles(in: projectPath)
                if !files.isEmpty {
                    await MainActor.run {
                        importProjectFiles = files
                        importWatcherTask = nil
                        if files.count == 1 {
                            importStatus = String(
                                format: String(localized: "filesafe.report.import.found"),
                                files[0].lastPathComponent
                            )
                            startImport(using: files[0])
                        } else {
                            importStatus = String(localized: "filesafe.report.import.multiple_found")
                            showingProjectPicker = true
                        }
                    }
                    return
                }

                try? await Task.sleep(nanoseconds: pollInterval)
            }

            await MainActor.run {
                if importWatcherTask != nil {
                    importStatus = String(localized: "filesafe.report.import.timeout")
                    importWatcherTask = nil
                }
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
                        footagePath: transfer.footagePath,
                        isNewProject: transfer.isNewProject,
                        projectName: transfer.projectName,
                        onEject: {
                            // Was een lege closure: de knop deed niets terwijl de gebruiker
                            // dacht dat de kaart veilig uitgeworpen was.
                            guard let volumeURL = transfer.volumeURL else { return }
                            VolumeDetector.shared.ejectVolume(at: volumeURL)
                        },
                        onOpenFinder: {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: transfer.projectPath)
                        },
                        onOpenReport: {
                            let reportPath = FileSafeCopyEngine.txtReportPath(
                                projectName: transfer.projectName,
                                projectPath: transfer.projectPath,
                                footagePath: transfer.footagePath,
                                report: report
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

// MARK: - Wizard Component: Accordion

struct FileSafeAccordion<Content: View>: View {
    let title: String
    let meta: String?
    @Binding var isOpen: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.easeOut(duration: 0.18)) { isOpen.toggle() } }) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.ink3)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 14)
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.ink)
                    if let meta = meta {
                        Text(meta)
                            .font(.system(size: 11.5))
                            .foregroundColor(.ink3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.fsSurface2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Divider()
                content()
                    .padding(16)
            }
        }
        .background(Color.fsCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 1))
    }
}

// MARK: - Wizard Component: AutoDetect Banner

struct FileSafeAutoDetectBanner: View {
    let scanResult: FileSafeScanResult
    let isMultiDay: Bool
    var onUndoMultiDay: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("✦")
                .font(.system(size: 16))
                .foregroundColor(.fsBannerInfoInk)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                if isMultiDay && scanResult.uniqueCalendarDays.count > 1 {
                    let formatter = DateFormatter()
                    let _ = formatter.setLocalizedDateFormatFromTemplate("dMMM")
                    let datesStr = scanResult.uniqueCalendarDays.prefix(5).map { formatter.string(from: $0) }.joined(separator: ", ")
                    HStack(spacing: 4) {
                        Text(String(format: String(localized: "filesafe.layout.autodetect.multiday"), scanResult.uniqueCalendarDays.count, datesStr))
                            .font(.system(size: 12.5))
                            .foregroundColor(.fsBannerInfoInk)
                        Button(action: onUndoMultiDay) {
                            Text(String(localized: "filesafe.layout.autodetect.undo_singleday"))
                                .font(.system(size: 12, weight: .medium))
                                .underline()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.peach3)
                    }
                }
                if scanResult.detectedBrand != .unknown {
                    Text(String(format: String(localized: "filesafe.layout.autodetect.brand"), scanResult.detectedBrand.rawValue))
                        .font(.system(size: 12.5))
                        .foregroundColor(.fsBannerInfoInk)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.fsBannerInfo)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.fsBannerInfoBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Wizard Step 3: Layout (combines projectConfig + cardConfig)

struct FileSafeLayoutView: View {
    @Binding var projectConfig: FileSafeProjectConfig
    @Binding var cardConfig: FileSafeCardConfig
    let scanResult: FileSafeScanResult
    let folderPreset: FolderStructurePreset
    let customTemplate: CustomFolderTemplate?
    var projectPath: String? = nil
    let onContinue: () -> Void
    let onBack: () -> Void

    @State private var isAOpen = true
    @State private var isBOpen = true
    @State private var isCOpen = false
    @State private var bannerDismissed = false

    private var showBanner: Bool {
        !bannerDismissed && (scanResult.uniqueCalendarDays.count > 1 || scanResult.detectedBrand != .unknown)
    }

    var body: some View {
        VStack(spacing: 0) {
            FileSafeNavBar(title: String(localized: "filesafe.layout.title"), onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if showBanner {
                        FileSafeAutoDetectBanner(
                            scanResult: scanResult,
                            isMultiDay: projectConfig.isMultiDayShoot,
                            onUndoMultiDay: {
                                projectConfig.isMultiDayShoot = false
                                bannerDismissed = true
                            }
                        )
                    }

                    // Accordion A — Algemeen
                    FileSafeAccordion(
                        title: String(localized: "filesafe.layout.accordion.general"),
                        meta: String(localized: "filesafe.layout.accordion.general.meta"),
                        isOpen: $isAOpen
                    ) {
                        VStack(alignment: .leading, spacing: 0) {
                            if !scanResult.isSingleDay {
                                toggleRow(
                                    title: String(localized: "filesafe.layout.toggle.multiday.label"),
                                    desc: String(localized: "filesafe.layout.toggle.multiday.desc"),
                                    isOn: $projectConfig.isMultiDayShoot
                                )
                                Divider()
                            }
                            if scanResult.hasVideo {
                                toggleRow(
                                    title: String(localized: "filesafe.layout.toggle.multicam.label"),
                                    desc: String(localized: "filesafe.layout.toggle.multicam.desc"),
                                    isOn: $projectConfig.hasMultipleCameras
                                )
                            }
                            if scanResult.hasAudio {
                                Divider()
                                toggleRow(
                                    title: String(localized: "filesafe.layout.toggle.audio_per_day.label"),
                                    desc: String(localized: "filesafe.layout.toggle.audio_per_day.desc"),
                                    isOn: $projectConfig.linkAudioToDayStructure
                                )
                            }
                        }
                    }

                    // Accordion B — Path editor
                    FileSafeAccordion(
                        title: String(localized: "filesafe.layout.accordion.where_files"),
                        meta: String(localized: "filesafe.layout.accordion.where_files.meta"),
                        isOpen: $isBOpen
                    ) {
                        FileSafePathPreview(
                            projectConfig: projectConfig,
                            cardConfig: $cardConfig,
                            scanResult: scanResult,
                            folderPreset: folderPreset,
                            customTemplate: customTemplate,
                            projectPath: projectPath
                        )
                    }

                    // Accordion C — Bins / specifieke bestanden
                    FileSafeAccordion(
                        title: String(localized: "filesafe.layout.accordion.specific_files"),
                        meta: String(localized: "filesafe.layout.accordion.specific_files.meta"),
                        isOpen: $isCOpen
                    ) {
                        VStack(spacing: 12) {
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
                            if scanResult.hasAudio {
                                FileSafeCategoryBinEditor(
                                    category: .audio,
                                    files: scanResult.audioFiles,
                                    shootDays: cardConfig.shootDays,
                                    isMultiDay: projectConfig.isMultiDayShoot,
                                    useTimestamp: projectConfig.useTimestampAssignment,
                                    bins: $cardConfig.audioBins,
                                    fileSubfolderMap: $cardConfig.fileSubfolderMap
                                )
                            }
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
                            if !scanResult.hasVideo && !scanResult.hasAudio && !scanResult.hasPhoto {
                                Text(String(localized: "filesafe.layout.accordion.specific_files.placeholder"))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(16)
            }

            // Action bar
            HStack {
                Button(action: onBack) {
                    Text("‹ \(String(localized: "filesafe.action.back"))")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundColor(.ink2)

                Spacer()

                Button(action: onContinue) {
                    Text("\(String(localized: "filesafe.destination.next"))")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.fsSurface2)
            .overlay(alignment: .top) { Color.line.frame(height: 1) }
        }
    }

    @ViewBuilder
    private func toggleRow(title: String, desc: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(.ink)
                Text(desc).font(.system(size: 11.5)).foregroundColor(.ink3)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.brandBurntPeach)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Wizard Step 4: Confirm (diff preview + summary + space check)

struct FileSafeConfirmView: View {
    let tree: FileSafeTargetFolder
    let fileMappings: [FileSafeFileMapping]
    @Binding var skipDuplicates: Bool
    @Binding var verifyAfterCopy: Bool
    var destinationPath: String?
    let onStartCopy: () -> Void
    let onBack: () -> Void

    private var totalFiles: Int { fileMappings.count }
    private var totalSize: Int64 { fileMappings.reduce(0) { $0 + $1.source.fileSize } }
    private var duplicateCount: Int { fileMappings.filter { $0.isDuplicate }.count }
    private var duplicateSize: Int64 { fileMappings.filter { $0.isDuplicate }.reduce(0) { $0 + $1.source.fileSize } }
    private var duplicateFileIds: Set<UUID> { Set(fileMappings.filter { $0.isDuplicate }.map { $0.source.id }) }

    private var newFolderCount: Int {
        var count = 0
        func walk(_ folder: FileSafeTargetFolder) {
            let existsOnDisk = !folder.relativePath.isEmpty
                && FileManager.default.fileExists(atPath: folder.relativePath)
            if folder.isAffected && !existsOnDisk && !folder.isExisting {
                count += 1
            }
            for child in folder.children { walk(child) }
        }
        walk(tree)
        return count
    }

    private var filesToCopy: Int {
        skipDuplicates ? totalFiles - duplicateCount : totalFiles
    }
    private var sizeToCopy: Int64 {
        skipDuplicates ? totalSize - duplicateSize : totalSize
    }

    private var freeSpace: Int64 {
        guard let path = destinationPath else { return 0 }
        let url = URL(fileURLWithPath: path)
        // Walk up to find existing parent (target folder may not yet exist)
        var current = url
        while !FileManager.default.fileExists(atPath: current.path) && current.path != "/" {
            current = current.deletingLastPathComponent()
        }
        let values = try? current.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return Int64(values?.volumeAvailableCapacity ?? 0)
    }

    private var marginBytes: Int64 { freeSpace - sizeToCopy }

    private enum SpaceStatus { case ok, warn, bad }
    private var spaceStatus: SpaceStatus {
        let fiveGB: Int64 = 5 * 1024 * 1024 * 1024
        if marginBytes <= 0 { return .bad }
        if marginBytes < fiveGB { return .warn }
        return .ok
    }

    private var etaSeconds: Int {
        // Conservative ~100 MB/s estimate
        let bytesPerSec: Int64 = 100 * 1024 * 1024
        return Int(sizeToCopy / max(1, bytesPerSec))
    }

    private var etaFormatted: String {
        let mins = etaSeconds / 60
        let secs = etaSeconds % 60
        if mins == 0 { return "\(secs)s" }
        return "\(mins) min"
    }

    var body: some View {
        VStack(spacing: 0) {
            FileSafeNavBar(title: String(localized: "filesafe.confirm.title"), onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Hero subtitle
                    Text(String(localized: "filesafe.confirm.subtitle"))
                        .font(.system(size: 13))
                        .foregroundColor(.ink2)
                        .padding(.horizontal, 4)

                    // Summary grid
                    summaryGrid

                    // Space check banner
                    spaceCheckBanner

                    // Diff title + legend
                    HStack {
                        Text(String(localized: "filesafe.confirm.diff.title"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.ink)
                        Spacer()
                        HStack(spacing: 12) {
                            legendItem(glyph: "+", color: .fsDiffNew, label: String(localized: "filesafe.confirm.diff.legend.new"))
                            legendItem(glyph: "~", color: .fsDiffDup, label: String(localized: "filesafe.confirm.diff.legend.dup"))
                            legendItem(glyph: "·", color: .fsDiffSame, label: String(localized: "filesafe.confirm.diff.legend.same"))
                        }
                    }

                    // Diff preview
                    FileSafeDiffPreview(
                        tree: tree,
                        duplicateFileIds: duplicateFileIds
                    )

                    // Toggles
                    VStack(spacing: 0) {
                        confirmToggle(
                            title: String(localized: "filesafe.confirm.toggle.skip_dup.label"),
                            desc: duplicateCount > 0
                                ? String(format: String(localized: "filesafe.confirm.toggle.skip_dup.desc"), duplicateCount, ByteCountFormatter.string(fromByteCount: duplicateSize, countStyle: .file))
                                : String(localized: "filesafe.confirm.toggle.skip_dup.desc_none"),
                            isOn: $skipDuplicates
                        )
                        Divider()
                        confirmToggle(
                            title: String(localized: "filesafe.confirm.toggle.verify.label"),
                            desc: String(localized: "filesafe.confirm.toggle.verify.desc"),
                            isOn: $verifyAfterCopy
                        )
                    }
                    .background(Color.fsCardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 1))
                }
                .padding(16)
            }

            // Action bar
            HStack {
                Button(action: onBack) {
                    Text("‹ \(String(localized: "filesafe.action.back"))")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .foregroundColor(.ink2)

                Spacer()

                Button(action: onStartCopy) {
                    Text(String(format: String(localized: "filesafe.confirm.start_copy"), ByteCountFormatter.string(fromByteCount: sizeToCopy, countStyle: .file)))
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(spaceStatus == .bad || filesToCopy == 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.fsSurface2)
            .overlay(alignment: .top) { Color.line.frame(height: 1) }
        }
    }

    private var summaryGrid: some View {
        HStack(spacing: 0) {
            summaryCell(
                label: String(localized: "filesafe.confirm.summary.to_copy"),
                value: "\(filesToCopy)",
                sub: String(format: String(localized: "filesafe.confirm.summary.files"), ByteCountFormatter.string(fromByteCount: sizeToCopy, countStyle: .file)),
                color: .ink
            )
            Divider()
            summaryCell(
                label: String(localized: "filesafe.confirm.summary.new_folders"),
                value: "\(newFolderCount)",
                sub: "",
                color: .fsBannerOkInk
            )
            Divider()
            summaryCell(
                label: String(localized: "filesafe.confirm.summary.duplicates"),
                value: "\(duplicateCount)",
                sub: duplicateCount > 0 ? String(localized: "filesafe.confirm.summary.skipped") : "",
                color: duplicateCount > 0 ? .fsBannerWarnInk : .ink2
            )
            Divider()
            summaryCell(
                label: String(localized: "filesafe.confirm.summary.free_space"),
                value: ByteCountFormatter.string(fromByteCount: max(0, freeSpace), countStyle: .file),
                sub: marginBytes > 0
                    ? String(format: String(localized: "filesafe.confirm.summary.margin"), ByteCountFormatter.string(fromByteCount: marginBytes, countStyle: .file))
                    : String(localized: "filesafe.confirm.space_bad_short"),
                color: marginColor()
            )
        }
        .frame(maxWidth: .infinity)
        .background(Color.fsCardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 1))
    }

    private func marginColor() -> Color {
        switch spaceStatus {
        case .ok:   return .fsBannerOkInk
        case .warn: return .fsBannerWarnInk
        case .bad:  return .fsBannerBadInk
        }
    }

    @ViewBuilder
    private func summaryCell(label: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundColor(.ink3)
                .textCase(.uppercase)
            Text(value)
                .font(.brandSerifItalic(size: 22))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !sub.isEmpty {
                Text(sub).font(.system(size: 11)).foregroundColor(.ink3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var spaceCheckBanner: some View {
        let (icon, ink, bg, border, text): (String, Color, Color, Color, String) = {
            switch spaceStatus {
            case .ok:
                return ("checkmark.circle.fill", .fsBannerOkInk, .fsBannerOk, .fsBannerOkBorder,
                        String(format: String(localized: "filesafe.confirm.space_ok"),
                               ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file),
                               etaFormatted))
            case .warn:
                return ("exclamationmark.triangle.fill", .fsBannerWarnInk, .fsBannerWarn, .fsBannerWarnBorder,
                        String(localized: "filesafe.confirm.space_warn"))
            case .bad:
                return ("xmark.octagon.fill", .fsBannerBadInk, .fsBannerBad, .fsBannerBadBorder,
                        String(format: String(localized: "filesafe.confirm.space_bad"),
                               ByteCountFormatter.string(fromByteCount: sizeToCopy, countStyle: .file),
                               ByteCountFormatter.string(fromByteCount: max(0, freeSpace), countStyle: .file)))
            }
        }()

        return HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(ink)
            Text(text).font(.system(size: 12.5)).foregroundColor(ink)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(bg)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func legendItem(glyph: String, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Text(glyph).font(.brandMono(size: 12, weight: .semibold)).foregroundColor(color)
            Text(label).font(.system(size: 11)).foregroundColor(.ink3)
        }
    }

    @ViewBuilder
    private func confirmToggle(title: String, desc: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(.ink)
                Text(desc).font(.system(size: 11.5)).foregroundColor(.ink3)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).tint(.brandBurntPeach)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Diff Preview Component

struct FileSafeDiffPreview: View {
    let tree: FileSafeTargetFolder
    let duplicateFileIds: Set<UUID>

    private struct DiffEntry: Identifiable {
        let id = UUID()
        let path: String
        let type: DiffType
        let size: Int64?
        let depth: Int
    }

    private enum DiffType { case new, duplicate, same }

    private var entries: [DiffEntry] {
        var result: [DiffEntry] = []
        flatten(tree, parentPath: "", depth: 0, into: &result)
        return result
    }

    private func flatten(_ folder: FileSafeTargetFolder, parentPath: String, depth: Int, into result: inout [DiffEntry]) {
        let displayPath = parentPath.isEmpty
            ? folder.displayName + "/"
            : "\(parentPath)\(folder.displayName)/"

        // Live disk-check: vertrouw niet alleen op isExisting flag uit de builder.
        // relativePath in FileSafeTargetFolder is feitelijk een absoluut pad.
        let existsOnDisk = !folder.relativePath.isEmpty
            && FileManager.default.fileExists(atPath: folder.relativePath)
        let folderType: DiffType
        if existsOnDisk || folder.isExisting {
            folderType = .same
        } else if folder.isAffected {
            folderType = .new
        } else {
            folderType = .same
        }
        result.append(DiffEntry(path: displayPath, type: folderType, size: nil, depth: depth))

        for child in folder.children.sorted(by: { $0.displayName < $1.displayName }) {
            flatten(child, parentPath: displayPath, depth: depth + 1, into: &result)
        }
        for file in folder.files.sorted(by: { $0.fileName < $1.fileName }) {
            let isDup = duplicateFileIds.contains(file.id)
            let type: DiffType = isDup ? .duplicate : .new
            result.append(DiffEntry(path: "\(displayPath)\(file.fileName)", type: type, size: file.fileSize, depth: depth + 1))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(entries) { entry in
                    diffRow(entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: 280)
        .background(Color.fsSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line, lineWidth: 1))
    }

    @ViewBuilder
    private func diffRow(_ entry: DiffEntry) -> some View {
        let glyph: String = {
            switch entry.type {
            case .new: return "+"
            case .duplicate: return "~"
            case .same: return "·"
            }
        }()
        let color: Color = {
            switch entry.type {
            case .new: return .fsDiffNew
            case .duplicate: return .fsDiffDup
            case .same: return .fsDiffSame
            }
        }()
        let textColor: Color = entry.type == .same ? .fsDiffSame : .ink

        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(glyph)
                .font(.brandMono(size: 12, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 14, alignment: .leading)

            Text(String(repeating: "  ", count: entry.depth) + entry.path)
                .font(.brandMono(size: 12))
                .foregroundColor(textColor)
                .strikethrough(entry.type == .duplicate, color: .fsDiffDup.opacity(0.5))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let size = entry.size {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.brandMono(size: 10.5))
                    .foregroundColor(.ink3)
            }
            if entry.type == .duplicate {
                Text(String(localized: "filesafe.confirm.duplicate_marker"))
                    .font(.system(size: 10.5))
                    .italic()
                    .foregroundColor(.fsBannerWarnInk)
            }
        }
    }
}

// MARK: - Wizard Step 5: Done (verify + eject + next)

struct FileSafeDoneView: View {
    let completedTransferId: UUID?
    @ObservedObject var transferManager: FileSafeTransferManager
    let verifyEnabled: Bool
    let onShowFinder: () -> Void
    let onCopyLog: () -> Void
    let onEject: () -> Void
    let onNextImport: () -> Void
    let onClose: () -> Void

    private var transfer: FileSafeTransfer? {
        guard let id = completedTransferId else { return nil }
        return transferManager.transfers.first(where: { $0.id == id })
    }

    private var hasFailures: Bool {
        transfer?.isFailed ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    // Hero
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(hasFailures ? Color.fsBannerBad : Color.fsStepDoneBg)
                                .frame(width: 72, height: 72)
                            Image(systemName: hasFailures ? "exclamationmark.triangle.fill" : "checkmark")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(hasFailures ? .fsBannerBadInk : .fsStepDoneInk)
                        }

                        Text(hasFailures
                             ? String(localized: "filesafe.done.title_failed")
                             : String(localized: "filesafe.done.title"))
                            .font(.brandSerifItalic(size: 26))
                            .foregroundColor(.ink)

                        if let report = transfer?.report {
                            Text(String(format: String(localized: "filesafe.done.subtitle"),
                                        report.totalFiles,
                                        ByteCountFormatter.string(fromByteCount: report.totalSize, countStyle: .file),
                                        report.formattedDuration))
                                .font(.brandMono(size: 12))
                                .foregroundColor(.ink3)
                        }
                    }
                    .padding(.top, 30)

                    // Verify + Eject cards
                    HStack(spacing: 14) {
                        FileSafeActionCard(
                            icon: "checkmark.shield.fill",
                            tint: .brandSkyBlue,
                            background: .fsBannerInfo,
                            border: .fsBannerInfoBorder,
                            title: String(localized: "filesafe.done.verify_card.title"),
                            description: String(localized: "filesafe.done.verify_card.desc"),
                            ctaTitle: verifyEnabled
                                ? String(localized: "filesafe.done.verify_card.done")
                                : String(localized: "filesafe.done.verify_card.cta"),
                            ctaDisabled: verifyEnabled,
                            ctaCheckmark: verifyEnabled,
                            action: { /* engine already verified during copy */ }
                        )
                        FileSafeActionCard(
                            icon: "eject.fill",
                            tint: .brandTeaGreen,
                            background: .fsBannerOk,
                            border: .fsBannerOkBorder,
                            title: String(localized: "filesafe.done.eject_card.title"),
                            description: String(localized: "filesafe.done.eject_card.desc"),
                            ctaTitle: String(localized: "filesafe.done.eject_card.cta"),
                            ctaDisabled: false,
                            ctaCheckmark: false,
                            action: onEject
                        )
                    }
                    .padding(.horizontal, 20)

                    // Sub-actions
                    HStack(spacing: 18) {
                        subActionLink(icon: "folder", label: String(localized: "filesafe.done.show_finder"), action: onShowFinder)
                        subActionLink(icon: "doc.on.clipboard", label: String(localized: "filesafe.done.copy_log"), action: onCopyLog)
                        subActionLink(icon: "arrow.clockwise", label: String(localized: "filesafe.done.next_card"), action: onNextImport)
                    }
                    .padding(.top, 4)

                    Spacer()
                }
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }

            HStack {
                Spacer()
                Button(action: onClose) {
                    Text(String(localized: "filesafe.done.close"))
                        .font(.system(size: 13))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.fsSurface2)
            .overlay(alignment: .top) { Color.line.frame(height: 1) }
        }
    }

    @ViewBuilder
    private func subActionLink(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 11.5))
            }
            .foregroundColor(.peach3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action Card Component (Verify/Eject)

struct FileSafeActionCard: View {
    let icon: String
    let tint: Color
    let background: Color
    let border: Color
    let title: String
    let description: String
    let ctaTitle: String
    let ctaDisabled: Bool
    let ctaCheckmark: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.ink)
                    Text(description)
                        .font(.system(size: 11.5))
                        .foregroundColor(.ink2)
                        .lineLimit(2)
                }
            }
            HStack {
                Spacer()
                if ctaDisabled {
                    Button(action: action) {
                        HStack(spacing: 4) {
                            if ctaCheckmark {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                            }
                            Text(ctaTitle).font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(true)
                } else {
                    Button(action: action) {
                        HStack(spacing: 4) {
                            if ctaCheckmark {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                            }
                            Text(ctaTitle).font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
