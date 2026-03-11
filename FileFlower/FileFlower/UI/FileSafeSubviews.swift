import SwiftUI

// MARK: - Step Indicator

struct FileSafeStepIndicator: View {
    let currentStep: FileSafeStep
    private let visibleSteps: [FileSafeStep] = [.volumeSelect, .projectSelect, .shootWizard, .structurePreview, .copying, .report]

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
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FileSafeNavBar(title: String(localized: "filesafe.volume.title"), onBack: onBack)

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

                // Capaciteit indicator
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
    let onConfirm: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FileSafeNavBar(title: String(localized: "filesafe.project.title"), onBack: onBack)

            ScrollView {
                VStack(spacing: 12) {
                    // Toggle
                    Picker("", selection: $isNewProject) {
                        Text(String(localized: "filesafe.project.new")).tag(true)
                        Text(String(localized: "filesafe.project.existing")).tag(false)
                    }
                    .pickerStyle(.segmented)

                    if isNewProject {
                        newProjectContent
                    } else {
                        existingProjectContent
                    }
                }
                .padding(12)
            }

            // Confirm knop
            if canConfirm {
                Button(action: onConfirm) {
                    Text(String(localized: "filesafe.project.confirm"))
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .padding(12)
            }
        }
    }

    private var canConfirm: Bool {
        if isNewProject {
            return !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty && selectedProjectPath != nil
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
                    Button(action: { selectedProjectPath = root }) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 12))
                            Text(URL(fileURLWithPath: root).lastPathComponent)
                                .font(.system(size: 12))
                            Spacer()
                            if selectedProjectPath == root {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedProjectPath == root ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: pickFolder) {
                Label(String(localized: "filesafe.project.browse"), systemImage: "folder.badge.plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var existingProjectContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.config.projectRoots.isEmpty {
                Text(String(localized: "filesafe.project.no_roots"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                ForEach(appState.config.projectRoots, id: \.self) { root in
                    let subfolders = listSubfolders(at: root)
                    if !subfolders.isEmpty {
                        Text(URL(fileURLWithPath: root).lastPathComponent)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        ForEach(subfolders, id: \.self) { folder in
                            Button(action: { selectedProjectPath = folder }) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.accentColor)
                                    Text(URL(fileURLWithPath: folder).lastPathComponent)
                                        .font(.system(size: 12))
                                    Spacer()
                                    if selectedProjectPath == folder {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11))
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedProjectPath == folder ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button(action: pickFolder) {
                Label(String(localized: "filesafe.project.browse"), systemImage: "folder.badge.plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func pickFolder() {
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

// MARK: - Shoot Wizard

struct FileSafeShootWizardView: View {
    @Binding var config: FileSafeShootConfig
    let scanResult: FileSafeScanResult
    let onPreview: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FileSafeNavBar(title: String(localized: "filesafe.wizard.title"), onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Algemeen
                    generalSection

                    // Video
                    if scanResult.hasVideo {
                        videoSection
                    }

                    // Audio
                    if scanResult.hasAudio {
                        audioSection
                    }

                    // Foto
                    if scanResult.hasPhoto {
                        photoSection
                    }
                }
                .padding(12)
            }

            // Preview knop
            Button(action: onPreview) {
                Text(String(localized: "filesafe.wizard.preview"))
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(12)
        }
    }

    // MARK: - Secties

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: String(localized: "filesafe.wizard.general"), icon: "calendar")

            // Aantal filmdagen
            HStack {
                Text(String(localized: "filesafe.wizard.days"))
                    .font(.system(size: 12))
                Spacer()
                Stepper(
                    "\(config.shootDays.count)",
                    onIncrement: {
                        let newDay = FileSafeShootDay(dayNumber: config.shootDays.count + 1)
                        config.shootDays.append(newDay)
                    },
                    onDecrement: {
                        if config.shootDays.count > 1 {
                            config.shootDays.removeLast()
                        }
                    }
                )
                .font(.system(size: 12))
            }

            // Optionele locatie
            HStack {
                Text(String(localized: "filesafe.wizard.location"))
                    .font(.system(size: 12))
                Spacer()
                TextField(String(localized: "filesafe.wizard.location.placeholder"), text: Binding(
                    get: { config.location ?? "" },
                    set: { config.location = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(maxWidth: 150)
            }
        }
    }

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: String(localized: "filesafe.wizard.video"),
                icon: "film",
                badge: "\(scanResult.videoCount)"
            )

            TagInputView(
                title: String(localized: "filesafe.wizard.cameras"),
                placeholder: String(localized: "filesafe.wizard.cameras.placeholder"),
                tags: $config.cameraAngles
            )

            Toggle(String(localized: "filesafe.wizard.timestamp"), isOn: $config.useTimestampAssignment)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: String(localized: "filesafe.wizard.audio"),
                icon: "waveform",
                badge: "\(scanResult.audioCount)"
            )

            TagInputView(
                title: String(localized: "filesafe.wizard.persons"),
                placeholder: String(localized: "filesafe.wizard.persons.placeholder"),
                tags: $config.audioPersons
            )

            Toggle(String(localized: "filesafe.wizard.wildtrack"), isOn: $config.hasWildtrack)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)

            if config.shootDays.count > 1 {
                Toggle(String(localized: "filesafe.wizard.audio_per_day"), isOn: $config.linkAudioToDayStructure)
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: String(localized: "filesafe.wizard.photos"),
                icon: "photo",
                badge: "\(scanResult.photoCount)"
            )

            TagInputView(
                title: String(localized: "filesafe.wizard.categories"),
                placeholder: String(localized: "filesafe.wizard.categories.placeholder"),
                tags: $config.photoCategories
            )

            Toggle(String(localized: "filesafe.wizard.split_raw"), isOn: $config.splitRawJpeg)
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    var badge: String? = nil

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
        }
    }
}

// MARK: - Structure Preview

struct FileSafeStructurePreviewView: View {
    let tree: FileSafeTargetFolder
    let totalFiles: Int
    let totalSize: Int64
    let onStartCopy: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            FileSafeNavBar(title: String(localized: "filesafe.preview.title"), onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // Samenvatting
                    HStack {
                        Text(String(localized: "filesafe.preview.summary \(totalFiles)"))
                            .font(.system(size: 12))
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)

                    // Mapstructuur boom
                    ForEach(tree.children) { child in
                        FolderTreeRow(folder: child, depth: 0)
                    }
                }
                .padding(12)
            }

            // Start kopiëren
            Button(action: onStartCopy) {
                HStack {
                    Image(systemName: "doc.on.doc.fill")
                    Text(String(localized: "filesafe.preview.start_copy"))
                }
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(12)
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
                // Inspring
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
    @ObservedObject var copyEngine: FileSafeCopyEngine
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Verificatie status van huidig bestand
            VStack(spacing: 8) {
                Text(String(localized: "filesafe.copy.title"))
                    .font(.system(size: 15, weight: .semibold))

                // Voortgangsbalk
                ProgressView(value: copyEngine.progress)
                    .progressViewStyle(.linear)

                // Teller
                Text("\(copyEngine.copiedCount) / \(copyEngine.totalCount)")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))

                // Huidig bestand
                if !copyEngine.currentFile.isEmpty {
                    Text(copyEngine.currentFile)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                // Snelheid en resterende tijd
                HStack(spacing: 16) {
                    if !copyEngine.copySpeed.isEmpty {
                        Label(copyEngine.copySpeed, systemImage: "gauge.with.dots.needle.33percent")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    if !copyEngine.estimatedTimeRemaining.isEmpty {
                        Label(copyEngine.estimatedTimeRemaining, systemImage: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Drie verificatiestappen
            VStack(spacing: 6) {
                Text(String(localized: "filesafe.copy.verification"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                VerificationStepRow(
                    label: String(localized: "filesafe.copy.step.size"),
                    icon: "doc.on.doc",
                    isComplete: copyEngine.currentFileSizeOK,
                    isActive: copyEngine.currentPhase == .copying
                )

                VerificationStepRow(
                    label: String(localized: "filesafe.copy.step.checksum"),
                    icon: "number.circle",
                    isComplete: copyEngine.currentFileChecksumOK,
                    isActive: copyEngine.currentPhase == .checksum
                )

                VerificationStepRow(
                    label: String(localized: "filesafe.copy.step.bytes"),
                    icon: "01.square",
                    isComplete: copyEngine.currentFileBytesOK,
                    isActive: copyEngine.currentPhase == .byteCompare
                )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )

            Button(action: onCancel) {
                Text(String(localized: "filesafe.cancel"))
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let onEject: () -> Void
    let onOpenFinder: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // Shield icoon
                    Image(systemName: report.failCount == 0 ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .font(.system(size: 44))
                        .foregroundColor(report.failCount == 0 ? .green : .orange)

                    // Samenvatting
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

                    // Mislukte bestanden detail
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

            // Actieknoppen
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

// MARK: - Nav Bar

struct FileSafeNavBar: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)

            Text(title)
                .font(.system(size: 13, weight: .semibold))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
