import SwiftUI

struct FileSafeView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var volumeDetector = VolumeDetector.shared
    @ObservedObject private var transferManager = FileSafeTransferManager.shared

    /// Optioneel: pre-geselecteerde volume (vanuit drive-cards in de tab)
    var initialVolume: ExternalVolume? = nil

    // Wizard state
    @State private var currentStep: FileSafeStep = .emptyState
    @State private var selectedVolume: ExternalVolume?
    @State private var scanResult: FileSafeScanResult?
    @State private var selectedProjectPath: String?
    @State private var selectedProjectRootPath: String? // Root map voor nieuw project (voorkomt dubbele map)
    @State private var isNewProject: Bool = true
    @State private var newProjectName: String = ""

    // Project + Card config (nieuw)
    @State private var projectConfig: FileSafeProjectConfig = .default
    @State private var cardConfig: FileSafeCardConfig?
    @State private var hasExistingProjectConfig: Bool = false

    // Structure preview
    @State private var structurePreview: FileSafeTargetFolder?
    @State private var fileMappings: [FileSafeFileMapping] = []
    @State private var skipDuplicates: Bool = true

    // Scan state
    @State private var scanProgress: FileSafeScanner.ScanProgress?
    @State private var scanTask: Task<Void, Never>?

    // Dashboard state
    @State private var selectedTransferId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator — altijd zichtbaar (behalve empty state en dashboard)
            if currentStep != .emptyState && currentStep != .dashboard {
                FileSafeStepIndicator(currentStep: currentStep)
                Divider()
            }

            // Content per stap
            Group {
                switch currentStep {
                case .dashboard:
                    FileSafeDashboardView(
                        transferManager: transferManager,
                        selectedTransferId: $selectedTransferId,
                        onNewImport: {
                            resetWizardForNewImport()
                            withAnimation { currentStep = .volumeSelect }
                        }
                    )

                case .emptyState:
                    FileSafeEmptyStateView()

                case .volumeSelect:
                    FileSafeVolumeSelectView(
                        volumeDetector: volumeDetector,
                        onSelect: { volume in
                            selectedVolume = volume
                            withAnimation { currentStep = .projectSelect }
                        }
                    )

                case .projectSelect:
                    FileSafeProjectSelectView(
                        appState: appState,
                        isNewProject: $isNewProject,
                        newProjectName: $newProjectName,
                        selectedProjectPath: $selectedProjectPath,
                        selectedProjectRootPath: $selectedProjectRootPath,
                        onConfirm: {
                            confirmProject()
                            startScan()
                        },
                        onBack: {
                            if transferManager.hasTransfers {
                                withAnimation { currentStep = .dashboard }
                            } else {
                                withAnimation { currentStep = .volumeSelect }
                            }
                        }
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

                case .projectConfig:
                    FileSafeProjectConfigView(
                        config: $projectConfig,
                        scanResult: scanResult!,
                        onContinue: {
                            // Bouw default card config op basis van scan + project config
                            if let result = scanResult {
                                cardConfig = FileSafeCardConfig.defaultFor(
                                    scanResult: result,
                                    projectConfig: projectConfig
                                )
                            }
                            withAnimation { currentStep = .cardConfig }
                        },
                        onBack: { withAnimation { currentStep = .projectSelect } }
                    )

                case .cardConfig:
                    if let binding = Binding($cardConfig) {
                        FileSafeCardConfigView(
                            cardConfig: binding,
                            projectConfig: projectConfig,
                            scanResult: scanResult!,
                            folderPreset: appState.config.folderStructurePreset,
                            customTemplate: appState.config.customFolderTemplate,
                            projectPath: selectedProjectPath,
                            onPreview: { buildPreview() },
                            onBack: { withAnimation { currentStep = .projectConfig } }
                        )
                    }

                case .structurePreview:
                    if let tree = structurePreview {
                        FileSafeStructurePreviewView(
                            tree: tree,
                            totalFiles: fileMappings.count,
                            totalSize: fileMappings.reduce(0) { $0 + $1.source.fileSize },
                            duplicateCount: fileMappings.filter { $0.isDuplicate }.count,
                            duplicateSize: fileMappings.filter { $0.isDuplicate }.reduce(0) { $0 + $1.source.fileSize },
                            skipDuplicates: $skipDuplicates,
                            onStartCopy: { startCopy() },
                            onBack: { withAnimation { currentStep = .cardConfig } }
                        )
                    }

                case .copying:
                    // Legacy — wordt niet meer direct gebruikt,
                    // transfers worden via dashboard getoond
                    if transferManager.hasTransfers {
                        FileSafeDashboardView(
                            transferManager: transferManager,
                            selectedTransferId: $selectedTransferId,
                            onNewImport: {
                                resetWizardForNewImport()
                                withAnimation { currentStep = .volumeSelect }
                            }
                        )
                    }

                case .report:
                    // Legacy — rapporten worden via dashboard getoond
                    if transferManager.hasTransfers {
                        FileSafeDashboardView(
                            transferManager: transferManager,
                            selectedTransferId: $selectedTransferId,
                            onNewImport: {
                                resetWizardForNewImport()
                                withAnimation { currentStep = .volumeSelect }
                            }
                        )
                    }
                }
            }
            .transition(.opacity)

            // Persistent transfer status bar — altijd zichtbaar als er transfers zijn
            // behalve op het dashboard (daar staan ze al)
            if transferManager.hasTransfers && currentStep != .dashboard {
                FileSafeTransferStatusBar(transferManager: transferManager) { transferId in
                    selectedTransferId = transferId
                    withAnimation { currentStep = .dashboard }
                }
            }
        }
        .onAppear {
            volumeDetector.startMonitoring()

            // Als er actieve/recente transfers zijn, toon dashboard
            if transferManager.hasTransfers {
                withAnimation { currentStep = .dashboard }
            } else if let volume = initialVolume {
                // Pre-geselecteerde volume vanuit drive-cards
                selectedVolume = volume
                withAnimation { currentStep = .projectSelect }
            }
        }
        .onChange(of: volumeDetector.externalVolumes) { _, newVolumes in
            // Automatisch naar volume selectie als er een drive aangesloten wordt
            if currentStep == .emptyState && !newVolumes.isEmpty {
                withAnimation { currentStep = .volumeSelect }
            }
            // Terug naar empty state als alle drives verwijderd zijn (alleen als geen transfers actief)
            if currentStep == .volumeSelect && newVolumes.isEmpty && !transferManager.hasTransfers {
                withAnimation { currentStep = .emptyState }
            }
        }
    }

    // MARK: - Project bevestigen

    private func confirmProject() {
        if isNewProject {
            let projectName = newProjectName.trimmingCharacters(in: .whitespaces)
            projectConfig.projectName = projectName

            // Bereken projectpad maar maak map NOG NIET aan (dat gebeurt pas bij startCopy)
            if let rootPath = selectedProjectRootPath {
                let projectPath = URL(fileURLWithPath: rootPath)
                    .appendingPathComponent(projectName)
                    .path
                selectedProjectPath = projectPath
            }
        } else {
            // Bestaand project
            if let path = selectedProjectPath {
                projectConfig.projectName = URL(fileURLWithPath: path).lastPathComponent
            }
        }

        // Laad bestaande project config als die bestaat (alleen voor bestaande projecten)
        if !isNewProject,
           let path = selectedProjectPath,
           let existing = FileSafeProjectConfig.load(from: path) {
            projectConfig = existing
            hasExistingProjectConfig = true
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

                    // Auto-detectie: als alle materiaal van 1 dag is EN er is nog geen config
                    if result.isSingleDay && !self.hasExistingProjectConfig {
                        projectConfig.isMultiDayShoot = false
                    }

                    // Altijd projectConfig stap tonen (pre-filled met opgeslagen config)
                    withAnimation { self.currentStep = .projectConfig }
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
        guard let scanResult = scanResult,
              let projectPath = selectedProjectPath,
              let cardConfig = cardConfig else { return }

        let (tree, mappings) = FileSafeStructureBuilder.shared.buildStructure(
            projectPath: projectPath,
            scanResult: scanResult,
            projectConfig: projectConfig,
            cardConfig: cardConfig,
            folderPreset: appState.config.folderStructurePreset,
            customTemplate: appState.config.customFolderTemplate
        )

        structurePreview = tree
        fileMappings = mappings

        // Detecteer duplicaten (bestanden die al in het project staan)
        // Gebruik existingProjectPath zodat bestaande mappen (bijv. "FOOTAGE") herkend worden
        let footagePath = FileSafeStructureBuilder.shared.resolveBasePaths(
            preset: appState.config.folderStructurePreset,
            customTemplate: appState.config.customFolderTemplate,
            existingProjectPath: projectPath
        ).footagePath
        FileSafeStructureBuilder.shared.detectDuplicates(
            in: &fileMappings,
            projectPath: projectPath,
            footagePath: footagePath
        )

        withAnimation { currentStep = .structurePreview }
    }

    // MARK: - Kopiëren starten via TransferManager

    private func startCopy() {
        guard let projectPath = selectedProjectPath else { return }

        // Bij nieuw project: maak map + deploy template pas nu aan
        if isNewProject {
            try? FileManager.default.createDirectory(
                atPath: projectPath,
                withIntermediateDirectories: true
            )

            let deployConfig = DeployConfig(
                folderStructurePreset: appState.config.folderStructurePreset,
                customFolderTemplate: appState.config.customFolderTemplate
            )
            _ = try? TemplateDeployer.deploy(
                to: URL(fileURLWithPath: projectPath),
                config: deployConfig
            )
        }

        // Sla project config direct op (niet wachten tot kopie klaar is)
        projectConfig.lastUpdated = Date()
        try? projectConfig.save(to: projectPath)

        // Filter duplicaten als skipDuplicates aan staat
        let mappingsToTransfer = skipDuplicates
            ? fileMappings.filter { !$0.isDuplicate }
            : fileMappings
        let skippedCount = fileMappings.count - mappingsToTransfer.count

        // Maak mapstructuur aan
        try? FileSafeStructureBuilder.shared.createFolderStructure(
            projectPath: projectPath,
            mappings: mappingsToTransfer
        )

        // Bepaal footage path voor rapport
        let footagePath = FileSafeStructureBuilder.shared.resolveBasePaths(
            preset: appState.config.folderStructurePreset,
            customTemplate: appState.config.customFolderTemplate
        ).footagePath

        // Start transfer via manager (overleeft window close)
        let transferId = transferManager.startTransfer(
            mappings: mappingsToTransfer,
            projectName: projectConfig.projectName,
            volumeName: selectedVolume?.name ?? "",
            projectPath: projectPath,
            footagePath: footagePath,
            projectConfig: projectConfig,
            skippedCount: skippedCount
        )

        selectedTransferId = transferId
        withAnimation { currentStep = .dashboard }
    }

    // MARK: - Acties

    private func resetWizardForNewImport() {
        selectedVolume = nil
        scanResult = nil
        selectedProjectPath = nil
        selectedProjectRootPath = nil
        isNewProject = true
        newProjectName = ""
        projectConfig = .default
        cardConfig = nil
        hasExistingProjectConfig = false
        structurePreview = nil
        fileMappings = []
        skipDuplicates = true
        scanProgress = nil
    }
}
