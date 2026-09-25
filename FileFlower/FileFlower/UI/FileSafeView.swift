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
    @State private var scanIsActive: Bool = false
    @State private var scanIsDone: Bool = false
    /// Foutmelding van de laatste scan (nil = geen fout). Zonder dit bleef de wizard
    /// eeuwig op "wachten op scan" hangen als de scan faalde.
    @State private var scanError: String?
    @State private var scanStatusBarHidden: Bool = false

    // Dashboard state
    @State private var selectedTransferId: UUID?

    // Tracks the just-completed transfer for the Done step
    @State private var lastCompletedTransferId: UUID?
    @State private var copyCompletionWatcher: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator — altijd zichtbaar (behalve empty state en dashboard)
            if currentStep != .emptyState && currentStep != .dashboard {
                FileSafeStepIndicator(
                    currentStep: currentStep,
                    onTap: { stage in goBackToStage(stage) }
                )
            }

            // Async scan-statusbar (op stappen 1-3 totdat scan + 1.5s done-fade)
            if showScanStatusBar {
                FileSafeScanStatusBar(
                    isActive: scanIsActive,
                    isDone: scanIsDone && !scanStatusBarHidden,
                    filesFound: scanResult?.files.count ?? scanProgress?.filesFound ?? 0,
                    currentDirectory: scanProgress?.currentDirectory ?? "",
                    onCancel: scanIsActive ? { cancelScan() } : nil
                )
            }

            // Onleesbare bestanden tijdens de scan: prominent melden. Een "geslaagde"
            // scan die stilzwijgend bestanden miste is precies wat FileSafe moet voorkomen.
            if let unreadable = scanResult?.unreadablePaths, !unreadable.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "filesafe.unreadable_files \(unreadable.count)"))
                            .font(.system(size: 12, weight: .semibold))
                        Text(String(localized: "filesafe.unreadable_files_description"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.10))
            }

            // Scanfout: zichtbaar met retry, zodat de wizard nooit stil vastloopt
            if let scanError = scanError, !scanIsActive {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(scanError)
                        .font(.system(size: 12))
                        .lineLimit(2)
                    Spacer()
                    Button(String(localized: "filesafe.rescan")) { startScan() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.10))
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
                            startScan()  // scan async — gebruiker gaat direct door
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
                        scanIsDone: scanIsDone,
                        onConfirm: {
                            confirmProject()
                            // Scan loopt al — direct door naar layout (cardConfig combineert oude project+card)
                            if let result = scanResult, cardConfig == nil {
                                cardConfig = FileSafeCardConfig.defaultFor(
                                    scanResult: result,
                                    projectConfig: projectConfig
                                )
                            }
                            withAnimation { currentStep = .cardConfig }
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
                    // Behouden voor compat — niet meer gerendered (overgeslagen)
                    Color.clear.onAppear {
                        withAnimation { currentStep = .projectSelect }
                    }

                case .projectConfig:
                    // Compat — route naar gecombineerde layout view
                    Color.clear.onAppear {
                        if let result = scanResult, cardConfig == nil {
                            cardConfig = FileSafeCardConfig.defaultFor(
                                scanResult: result,
                                projectConfig: projectConfig
                            )
                        }
                        withAnimation { currentStep = .cardConfig }
                    }

                case .cardConfig:
                    if let binding = Binding($cardConfig), let result = scanResult {
                        FileSafeLayoutView(
                            projectConfig: $projectConfig,
                            cardConfig: binding,
                            scanResult: result,
                            folderPreset: appState.config.folderStructurePreset,
                            customTemplate: appState.config.customFolderTemplate,
                            projectPath: selectedProjectPath,
                            onContinue: { buildPreview() },
                            onBack: { withAnimation { currentStep = .projectSelect } }
                        )
                    } else {
                        // Wachten op scan-result
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(String(localized: "filesafe.layout.waiting_scan"))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                case .structurePreview:
                    if let tree = structurePreview, let cc = Binding($cardConfig) {
                        FileSafeConfirmView(
                            tree: tree,
                            fileMappings: fileMappings,
                            skipDuplicates: $skipDuplicates,
                            verifyAfterCopy: cc.verifyAfterCopy,
                            destinationPath: selectedProjectPath,
                            onStartCopy: { startCopy() },
                            onBack: { withAnimation { currentStep = .cardConfig } }
                        )
                    }

                case .copying:
                    // Korte tussentoestand tijdens copy-start; dashboard toont voortgang.
                    if transferManager.hasTransfers {
                        FileSafeDashboardView(
                            transferManager: transferManager,
                            selectedTransferId: $selectedTransferId,
                            onNewImport: {
                                resetWizardForNewImport()
                                withAnimation { currentStep = .volumeSelect }
                            }
                        )
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                case .report:
                    FileSafeDoneView(
                        completedTransferId: lastCompletedTransferId,
                        transferManager: transferManager,
                        verifyEnabled: cardConfig?.verifyAfterCopy ?? true,
                        onShowFinder: { revealCompletedTransferInFinder() },
                        onCopyLog: { copyTransferLogToPasteboard() },
                        onEject: { ejectSourceVolume() },
                        onNextImport: {
                            resetWizardForNewImport(keepProject: true)
                            withAnimation { currentStep = .volumeSelect }
                        },
                        onClose: {
                            withAnimation { currentStep = .dashboard }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(currentStep == .emptyState || currentStep == .dashboard ? Color.clear : Color.fsCardBg)
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
                // Pre-geselecteerde volume vanuit drive-cards (popup) — start scan direct
                selectedVolume = volume
                if !scanIsActive && !scanIsDone {
                    startScan()
                }
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
        // Vorige scan altijd afbreken: anders kan een tragere scan van het VORIGE volume
        // later klaar zijn en het resultaat van het huidige volume overschrijven.
        scanTask?.cancel()
        scanProgress = nil
        scanIsActive = true
        scanIsDone = false
        scanError = nil
        scanStatusBarHidden = false
        scanResult = nil

        // Onthoud voor welk volume deze scan draait, zodat een laat resultaat
        // van een ander volume herkend en genegeerd wordt.
        let scanningVolumeURL = volume.url

        scanTask = Task {
            do {
                let result = try await FileSafeScanner.shared.scanVolume(
                    volume.url,
                    volumeName: volume.name
                ) { progress in
                    self.scanProgress = progress
                }
                await MainActor.run {
                    // Resultaat hoort bij een inmiddels verlaten volume → weggooien
                    guard self.selectedVolume?.url == scanningVolumeURL else { return }
                    self.scanResult = result

                    if !self.hasExistingProjectConfig {
                        if result.uniqueCalendarDays.count > 1 {
                            projectConfig.isMultiDayShoot = true
                        } else if result.isSingleDay {
                            projectConfig.isMultiDayShoot = false
                        }
                    }

                    withAnimation(.easeOut(duration: 0.2)) {
                        self.scanIsActive = false
                        self.scanIsDone = true
                    }

                    // Hide statusbar 1.5s after done
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        if self.scanIsDone {
                            withAnimation(.easeOut(duration: 0.4)) {
                                self.scanStatusBarHidden = true
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    guard self.selectedVolume?.url == scanningVolumeURL else { return }
                    // Fout zichtbaar maken i.p.v. stil blijven hangen op "wachten op scan"
                    if !(error is CancellationError) {
                        self.scanError = error.localizedDescription
                    }
                    withAnimation { self.scanIsActive = false; self.scanIsDone = false }
                }
            }
        }
    }

    private func cancelScan() {
        scanTask?.cancel()
        scanIsActive = false
        scanIsDone = false
        scanError = String(localized: "filesafe.scan_cancelled")
    }

    /// Show statusbar tijdens stap 1-3 zolang scan nog draait of net klaar is
    private var showScanStatusBar: Bool {
        let stage = WizardStage.stage(for: currentStep)
        let onEarlyStage = stage == .source || stage == .destination || stage == .layout
        return onEarlyStage && (scanIsActive || (scanIsDone && !scanStatusBarHidden))
    }

    private func goBackToStage(_ stage: WizardStage) {
        let target: FileSafeStep
        switch stage {
        case .source:      target = .volumeSelect
        case .destination: target = .projectSelect
        case .layout:      target = .cardConfig
        case .confirm:     target = .structurePreview
        case .done:        target = .report
        }
        withAnimation { currentStep = target }
    }

    // MARK: - Structuur preview

    private func buildPreview() {
        guard let scanResult = scanResult,
              let projectPath = selectedProjectPath,
              let cardConfig = cardConfig else { return }

        // Als er een active template is, gebruik die (met default parameter-waarden +
        // projectnaam als "Project Name" parameter bestaat).
        let activeTemplate = TemplateDeployFlow.activeTemplate(for: appState.config)
        let activeTemplateValues = activeTemplate.map { template -> [String: String] in
            var values = TemplateDeployFlow.defaultValues(for: template)
            let projectNameKey = template.parameters.first { param in
                let lower = param.title.lowercased()
                return lower == "project name" || lower == "projectname" || lower == "project"
            }?.title
            if let key = projectNameKey, !projectConfig.projectName.isEmpty {
                values[key] = projectConfig.projectName
            }
            return values
        } ?? [:]

        // NB: deze structuur-opbouw doet recursieve schijf-scans synchroon. Het off-main
        // halen (Task.detached) liet de Swift 6.2-compiler crashen in de SIL-pass
        // "ClosureLifetimeFixup" — uitgesteld tot een nieuwere toolchain of een andere opzet.
        // Het gebeurt eenmalig op de "Volgende"-actie (niet per toetsaanslag).
        let (tree, mappings) = FileSafeStructureBuilder.shared.buildStructure(
            projectPath: projectPath,
            scanResult: scanResult,
            projectConfig: projectConfig,
            cardConfig: cardConfig,
            folderPreset: appState.config.folderStructurePreset,
            customTemplate: appState.config.customFolderTemplate,
            activeTemplate: activeTemplate,
            activeTemplateValues: activeTemplateValues
        )

        // Bestaande project → merge bestaande mappen in zodat de preview de
        // volledige projectboom laat zien (grijs voor non-affected folders).
        // Bij nieuwe projecten is er nog niks op disk, dus merge overslaan.
        let merged: FileSafeTargetFolder
        if !isNewProject {
            merged = FileSafeStructureBuilder.shared.mergeExistingProjectTree(
                targetTree: tree,
                existingProjectPath: projectPath
            )
        } else {
            merged = tree
        }

        structurePreview = merged
        fileMappings = mappings

        // Detecteer duplicaten (bestanden die al in het project staan)
        // Gebruik existingProjectPath zodat bestaande mappen (bijv. "FOOTAGE") herkend worden
        let footagePath: String
        if let template = activeTemplate {
            footagePath = FileSafeStructureBuilder.shared.resolveBasePaths(
                template: template,
                values: activeTemplateValues,
                existingProjectPath: projectPath
            ).footagePath
        } else {
            footagePath = FileSafeStructureBuilder.shared.resolveBasePaths(
                preset: appState.config.folderStructurePreset,
                customTemplate: appState.config.customFolderTemplate,
                existingProjectPath: projectPath
            ).footagePath
        }
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

            // Nieuwe flow: active template met parameter-prompt
            if let template = TemplateDeployFlow.activeTemplate(for: appState.config) {
                if TemplateDeployFlow.needsPrompt(for: template) {
                    // Toon parameter-sheet — deploy gebeurt in completion
                    let controller = ParameterValueWindowController(
                        templateName: template.name,
                        parameters: template.parameters,
                        onResult: { [self] values in
                            if let values = values {
                                _ = try? TemplateDeployer.deploy(
                                    to: URL(fileURLWithPath: projectPath),
                                    template: template,
                                    values: values
                                )
                                continueStartCopy(projectPath: projectPath)
                            }
                            // Annulering → niks doen, user blijft op scherm
                        }
                    )
                    controller.show()
                    return
                } else {
                    _ = try? TemplateDeployer.deploy(
                        to: URL(fileURLWithPath: projectPath),
                        template: template,
                        values: TemplateDeployFlow.defaultValues(for: template)
                    )
                }
            } else {
                // Legacy preset-flow
                let deployConfig = DeployConfig(
                    folderStructurePreset: appState.config.folderStructurePreset,
                    customFolderTemplate: appState.config.customFolderTemplate
                )
                _ = try? TemplateDeployer.deploy(
                    to: URL(fileURLWithPath: projectPath),
                    config: deployConfig
                )
            }
        }

        continueStartCopy(projectPath: projectPath)
    }

    /// Tweede deel van startCopy — wordt uitgevoerd na (synchrone of async) template-deploy.
    private func continueStartCopy(projectPath: String) {
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

        // Bepaal footage path voor rapport — MET existingProjectPath, exact zoals
        // buildPreview dat doet. Zonder die parameter viel dit terug op de preset-default
        // ("01_Footage") en maakte writeTxtReport een spookmap naast de bestaande
        // footage-map van het project.
        let existingPathForResolve: String? = isNewProject ? nil : projectPath
        let footagePath: String
        if let template = TemplateDeployFlow.activeTemplate(for: appState.config) {
            var values = TemplateDeployFlow.defaultValues(for: template)
            let projectNameKey = template.parameters.first { param in
                let lower = param.title.lowercased()
                return lower == "project name" || lower == "projectname" || lower == "project"
            }?.title
            if let key = projectNameKey, !projectConfig.projectName.isEmpty {
                values[key] = projectConfig.projectName
            }
            footagePath = FileSafeStructureBuilder.shared.resolveBasePaths(
                template: template,
                values: values,
                existingProjectPath: existingPathForResolve
            ).footagePath
        } else {
            footagePath = FileSafeStructureBuilder.shared.resolveBasePaths(
                preset: appState.config.folderStructurePreset,
                customTemplate: appState.config.customFolderTemplate,
                existingProjectPath: existingPathForResolve
            ).footagePath
        }

        // Start transfer via manager (overleeft window close)
        let transferId = transferManager.startTransfer(
            mappings: mappingsToTransfer,
            projectName: projectConfig.projectName,
            volumeName: selectedVolume?.name ?? "",
            volumeURL: selectedVolume?.url,
            projectPath: projectPath,
            footagePath: footagePath,
            projectConfig: projectConfig,
            skippedCount: skippedCount,
            isNewProject: isNewProject
        )

        selectedTransferId = transferId
        lastCompletedTransferId = transferId
        withAnimation { currentStep = .copying }

        // Watch for completion → transition to .report (Done step)
        copyCompletionWatcher?.cancel()
        copyCompletionWatcher = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let transfer = transferManager.transfers.first(where: { $0.id == transferId }),
                   transfer.isCompleted {
                    await MainActor.run {
                        withAnimation { currentStep = .report }
                    }
                    return
                }
            }
        }
    }

    // MARK: - Acties

    private func resetWizardForNewImport(keepProject: Bool = false) {
        selectedVolume = nil
        scanResult = nil
        if !keepProject {
            selectedProjectPath = nil
            selectedProjectRootPath = nil
            isNewProject = true
            newProjectName = ""
            projectConfig = .default
            hasExistingProjectConfig = false
        }
        cardConfig = nil
        structurePreview = nil
        fileMappings = []
        skipDuplicates = true
        scanProgress = nil
        scanIsActive = false
        scanIsDone = false
        scanStatusBarHidden = false
        copyCompletionWatcher?.cancel()
        copyCompletionWatcher = nil
    }

    // MARK: - Done step acties

    private func revealCompletedTransferInFinder() {
        guard let id = lastCompletedTransferId,
              let transfer = transferManager.transfers.first(where: { $0.id == id }) else { return }
        let url = URL(fileURLWithPath: transfer.projectPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyTransferLogToPasteboard() {
        guard let id = lastCompletedTransferId,
              let transfer = transferManager.transfers.first(where: { $0.id == id }),
              let report = transfer.report else { return }
        let lines = [
            "FileFlower copy report",
            "Project: \(report.projectName)",
            "Volume: \(report.volumeName)",
            "Files: \(report.totalFiles)  Verified: \(report.successCount)  Failed: \(report.failCount)  Skipped: \(report.skippedCount)",
            "Duration: \(report.formattedDuration)"
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func ejectSourceVolume() {
        guard let volume = selectedVolume else { return }
        try? NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
    }
}
