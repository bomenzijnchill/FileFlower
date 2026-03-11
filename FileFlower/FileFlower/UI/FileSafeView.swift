import SwiftUI

struct FileSafeView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var volumeDetector = VolumeDetector.shared
    @StateObject private var copyEngine = FileSafeCopyEngine()

    // Wizard state
    @State private var currentStep: FileSafeStep = .emptyState
    @State private var selectedVolume: ExternalVolume?
    @State private var scanResult: FileSafeScanResult?
    @State private var selectedProjectPath: String?
    @State private var isNewProject: Bool = true
    @State private var newProjectName: String = ""
    @State private var shootConfig: FileSafeShootConfig = .default
    @State private var structurePreview: FileSafeTargetFolder?
    @State private var fileMappings: [FileSafeFileMapping] = []
    @State private var copyReport: FileSafeCopyReport?

    // Scan state
    @State private var scanProgress: FileSafeScanner.ScanProgress?
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if currentStep != .emptyState {
                FileSafeStepIndicator(currentStep: currentStep)
                Divider()
            }

            // Content per stap
            Group {
                switch currentStep {
                case .emptyState:
                    FileSafeEmptyStateView()

                case .volumeSelect:
                    FileSafeVolumeSelectView(
                        volumeDetector: volumeDetector,
                        onSelect: { volume in
                            selectedVolume = volume
                            withAnimation { currentStep = .projectSelect }
                        },
                        onBack: { withAnimation { currentStep = .emptyState } }
                    )

                case .projectSelect:
                    FileSafeProjectSelectView(
                        appState: appState,
                        isNewProject: $isNewProject,
                        newProjectName: $newProjectName,
                        selectedProjectPath: $selectedProjectPath,
                        onConfirm: {
                            confirmProject()
                            startScan()
                        },
                        onBack: { withAnimation { currentStep = .volumeSelect } }
                    )

                case .scanning:
                    FileSafeScanningView(
                        volumeName: selectedVolume?.name ?? "",
                        progress: scanProgress,
                        onCancel: {
                            scanTask?.cancel()
                            withAnimation { currentStep = .projectSelect }
                        }
                    )

                case .shootWizard:
                    FileSafeShootWizardView(
                        config: $shootConfig,
                        scanResult: scanResult!,
                        onPreview: { buildPreview() },
                        onBack: { withAnimation { currentStep = .projectSelect } }
                    )

                case .structurePreview:
                    if let tree = structurePreview {
                        FileSafeStructurePreviewView(
                            tree: tree,
                            totalFiles: fileMappings.count,
                            totalSize: fileMappings.reduce(0) { $0 + $1.source.fileSize },
                            onStartCopy: { startCopy() },
                            onBack: { withAnimation { currentStep = .shootWizard } }
                        )
                    }

                case .copying:
                    FileSafeCopyingView(
                        copyEngine: copyEngine,
                        onCancel: {
                            copyEngine.cancelCopy()
                            withAnimation { currentStep = .structurePreview }
                        }
                    )

                case .report:
                    if let report = copyReport {
                        FileSafeReportView(
                            report: report,
                            onEject: { ejectVolume() },
                            onOpenFinder: { openInFinder() },
                            onDone: { resetWizard() }
                        )
                    }
                }
            }
            .transition(.opacity)
        }
        .onAppear {
            volumeDetector.startMonitoring()
        }
        .onChange(of: volumeDetector.externalVolumes) { _, newVolumes in
            // Automatisch naar volume selectie als er een drive aangesloten wordt
            if currentStep == .emptyState && !newVolumes.isEmpty {
                withAnimation { currentStep = .volumeSelect }
            }
            // Terug naar empty state als alle drives verwijderd zijn
            if currentStep == .volumeSelect && newVolumes.isEmpty {
                withAnimation { currentStep = .emptyState }
            }
        }
    }

    // MARK: - Project bevestigen

    private func confirmProject() {
        if isNewProject {
            let projectName = newProjectName.trimmingCharacters(in: .whitespaces)
            shootConfig.projectName = projectName

            // Maak projectmap aan
            if let rootPath = selectedProjectPath {
                let projectPath = URL(fileURLWithPath: rootPath)
                    .appendingPathComponent(projectName)
                    .path

                try? FileManager.default.createDirectory(
                    atPath: projectPath,
                    withIntermediateDirectories: true
                )

                // Deploy template
                let deployConfig = DeployConfig(
                    folderStructurePreset: appState.config.folderStructurePreset,
                    customFolderTemplate: appState.config.customFolderTemplate
                )
                _ = try? TemplateDeployer.deploy(
                    to: URL(fileURLWithPath: projectPath),
                    config: deployConfig
                )

                selectedProjectPath = projectPath
            }
        } else {
            // Bestaand project
            if let path = selectedProjectPath {
                shootConfig.projectName = URL(fileURLWithPath: path).lastPathComponent
            }

            // Laad eventueel opgeslagen config
            if let path = selectedProjectPath,
               let savedConfig = appState.config.fileSafeConfigs[path] {
                shootConfig = savedConfig
                // Behoud projectnaam
                shootConfig.projectName = URL(fileURLWithPath: path).lastPathComponent
            }
        }
    }

    // MARK: - Scan starten

    private func startScan() {
        guard let volume = selectedVolume else { return }
        withAnimation { currentStep = .scanning }
        scanProgress = nil

        scanTask = Task {
            do {
                let result = try await FileSafeScanner.shared.scanVolume(
                    volume.url,
                    volumeName: volume.name
                ) { progress in
                    self.scanProgress = progress
                }
                await MainActor.run {
                    self.scanResult = result
                    withAnimation { self.currentStep = .shootWizard }
                }
            } catch {
                await MainActor.run {
                    withAnimation { self.currentStep = .projectSelect }
                }
            }
        }
    }

    // MARK: - Structuur preview

    private func buildPreview() {
        guard let scanResult = scanResult, let projectPath = selectedProjectPath else { return }

        let (tree, mappings) = FileSafeStructureBuilder.shared.buildStructure(
            projectPath: projectPath,
            scanResult: scanResult,
            shootConfig: shootConfig,
            folderPreset: appState.config.folderStructurePreset,
            customTemplate: appState.config.customFolderTemplate
        )

        structurePreview = tree
        fileMappings = mappings
        withAnimation { currentStep = .structurePreview }
    }

    // MARK: - Kopiëren starten

    private func startCopy() {
        guard let projectPath = selectedProjectPath else { return }

        withAnimation { currentStep = .copying }

        // Maak mapstructuur aan
        try? FileSafeStructureBuilder.shared.createFolderStructure(
            projectPath: projectPath,
            mappings: fileMappings
        )

        copyEngine.startCopy(
            mappings: fileMappings,
            projectName: shootConfig.projectName,
            volumeName: selectedVolume?.name ?? ""
        ) { _ in
            // Per bestand callback — kan later gebruikt worden voor live log
        } onComplete: { report in
            Task { @MainActor in
                self.copyReport = report
                withAnimation { self.currentStep = .report }

                // Sla verificatielog op
                if let path = self.selectedProjectPath {
                    try? FileSafeCopyEngine.writeLog(report, to: path)
                }

                // Sla shoot config op voor hergebruik
                if let path = self.selectedProjectPath {
                    self.appState.config.fileSafeConfigs[path] = self.shootConfig
                    self.appState.saveConfig()
                }
            }
        }
    }

    // MARK: - Acties

    private func ejectVolume() {
        if let volume = selectedVolume {
            volumeDetector.ejectVolume(volume)
        }
    }

    private func openInFinder() {
        if let path = selectedProjectPath {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        }
    }

    private func resetWizard() {
        withAnimation {
            currentStep = volumeDetector.externalVolumes.isEmpty ? .emptyState : .volumeSelect
            selectedVolume = nil
            scanResult = nil
            selectedProjectPath = nil
            isNewProject = true
            newProjectName = ""
            shootConfig = .default
            structurePreview = nil
            fileMappings = []
            copyReport = nil
            scanProgress = nil
        }
    }
}
