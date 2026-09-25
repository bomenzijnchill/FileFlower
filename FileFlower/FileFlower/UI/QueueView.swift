import SwiftUI
import AppKit
import Quartz

struct QueueView: View {
    @StateObject private var appState = AppState.shared
    @Binding var selectedItemForPicker: DownloadItem?
    @Binding var isShowingClearConfirmation: Bool
    @State private var selectedItems: Set<UUID> = []
    @State private var clearTimer: Timer?
    @State private var pendingConflictItem: DownloadItem?
    @State private var rootCheckApprovedItems: Set<UUID> = []
    @State private var showHistory = false
    @State private var editingItemId: UUID? = nil
    @State private var showBulkSubfolderSheet = false
    @State private var bulkSubfolderName = ""
    @State private var showBulkTypeSheet = false
    @State private var bulkType: AssetType = .footage
    @State private var pathAltsItem: DownloadItem?
    /// Items waarvan de verwerking onderbroken werd door de mapping-bevestigingsgate,
    /// zodat we die na bevestiging alsnog kunnen verwerken.
    @State private var pendingProcessItems: Set<UUID>?

    init(selectedItemForPicker: Binding<DownloadItem?>, isShowingClearConfirmation: Binding<Bool> = .constant(false)) {
        self._selectedItemForPicker = selectedItemForPicker
        self._isShowingClearConfirmation = isShowingClearConfirmation
    }

    var body: some View {
        VStack(spacing: 0) {
            if isShowingClearConfirmation {
                ClearQueueConfirmation(
                    itemCount: appState.queuedItems.count,
                    onConfirm: {
                        isShowingClearConfirmation = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            clearQueue()
                        }
                    },
                    onCancel: {
                        isShowingClearConfirmation = false
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }

            // Contextual selection bar (zichtbaar bij 2+ geselecteerd)
            if selectedItems.count >= 2 {
                BulkSelectionBar(
                    count: selectedItems.count,
                    onClear: { selectedItems.removeAll() },
                    onSharedSubfolder: {
                        bulkSubfolderName = ""
                        showBulkSubfolderSheet = true
                    },
                    onEditType: {
                        // Start vanuit het type van het eerste geselecteerde item
                        if let first = selectedItems.first,
                           let item = appState.queuedItems.first(where: { $0.id == first }) {
                            bulkType = item.predictedType
                        }
                        showBulkTypeSheet = true
                    },
                    onDelete: {
                        appState.queuedItems.removeAll { selectedItems.contains($0.id) }
                        selectedItems.removeAll()
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Grouped queue sections
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    let grouped = appState.groupedQueueItems

                    // Section: Attention (needs confirmation)
                    if !grouped.attention.isEmpty {
                        Section(header: QueueSectionHeader(
                            title: String(localized: "queue.needs_confirmation"),
                            count: grouped.attention.count,
                            style: .attention
                        )) {
                            ForEach(grouped.attention) { item in
                                AttentionQueueRow(
                                    item: item,
                                    onConfirm: { acceptSuggestedPath(for: item) },
                                    onChooseAlternate: {
                                        // Toon eerst de mappen die FileFlower al kent; geen bekende
                                        // mappen → direct de bladeren-panel.
                                        if knownFolders(for: item).isEmpty {
                                            showPathPicker(for: item)
                                        } else {
                                            pathAltsItem = item
                                        }
                                    },
                                    onEdit: { editingItemId = item.id }
                                )
                            }
                        }
                    }

                    // Section: Ready to process
                    if !grouped.ready.isEmpty {
                        Section(header: QueueSectionHeader(
                            title: String(localized: "queue.ready_to_process"),
                            count: grouped.ready.count,
                            style: .ready,
                            trailingButtonTitle: allReadySelected
                                ? String(localized: "queue.deselect_all")
                                : String(localized: "queue.select_all"),
                            trailingButtonAction: { toggleSelectAll() }
                        )) {
                            ForEach(grouped.ready) { item in
                                ReadyQueueRow(
                                    item: item,
                                    isSelected: selectedItems.contains(item.id),
                                    onSelect: {
                                        if selectedItems.contains(item.id) {
                                            selectedItems.remove(item.id)
                                        } else {
                                            selectedItems.insert(item.id)
                                        }
                                    },
                                    onEdit: { editingItemId = item.id },
                                    onProcess: { processItem(item) },
                                    onSkip: {
                                        if let idx = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                                            appState.queuedItems[idx].status = .skipped
                                        }
                                    },
                                    onReveal: { openInFinder(for: item) },
                                    onRetry: { retryItem(item) },
                                    bulkSubfolderAvailable: selectedItems.contains(item.id) && selectedItems.count >= 2,
                                    onBulkSubfolder: {
                                        bulkSubfolderName = ""
                                        showBulkSubfolderSheet = true
                                    },
                                    onDelete: {
                                        appState.queuedItems.removeAll { $0.id == item.id }
                                        selectedItems.remove(item.id)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            if let firstSelected = selectedItems.first,
               let item = appState.queuedItems.first(where: { $0.id == firstSelected }) {
                let url = URL(fileURLWithPath: item.path)
                FileSafeQuickLookCoordinator.shared.toggle(url: url)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.delete) {
            // Backspace/Delete verwijdert de selectie uit de wachtrij (alleen queue-entries,
            // geen bestanden op schijf). Niets geselecteerd → laat de toets met rust.
            if !selectedItems.isEmpty {
                deleteSelectedItems()
                return .handled
            }
            return .ignored
        }
        .background {
            Button("") {
                // Alleen de zichtbare, selecteerbare rijen. Attention-items tonen geen
                // checkbox; die stilzwijgend mee-selecteren maakte bulk-delete/-type
                // onbedoeld destructief.
                selectedItems = Set(appState.groupedQueueItems.ready.map(\.id))
            }
            .keyboardShortcut("a", modifiers: .command)
            .hidden()
        }
        .onChange(of: selectedItems) { _, newValue in
            appState.selectedQueueItemCount = newValue.count
        }
        .onAppear {
            startAutoClearTimer()
        }
        .onDisappear {
            clearTimer?.invalidate()
            appState.selectedQueueItemCount = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .processAllFromFooter)) { _ in
            if selectedItems.isEmpty {
                processAll()
            } else {
                processSelected()
            }
        }
        .sheet(isPresented: Binding(
            get: { editingItemId != nil },
            set: { if !$0 { editingItemId = nil } }
        )) {
            if let id = editingItemId {
                RowEditSheet(itemId: id, onDismiss: { editingItemId = nil })
            }
        }
        .sheet(isPresented: $showBulkSubfolderSheet) {
            let repItem = appState.queuedItems.first { selectedItems.contains($0.id) }
            BulkSubfolderSheet(
                count: selectedItems.count,
                project: repItem?.targetProject,
                assetType: repItem?.predictedType ?? .footage,
                musicMode: appState.config.musicClassification,
                subfolderName: $bulkSubfolderName,
                onCancel: { showBulkSubfolderSheet = false },
                onConfirm: {
                    let trimmed = bulkSubfolderName.trimmingCharacters(in: .whitespaces)
                    showBulkSubfolderSheet = false
                    guard !trimmed.isEmpty else { return }
                    applySharedSubfolder(trimmed)
                }
            )
        }
        .sheet(isPresented: $showBulkTypeSheet) {
            BulkTypeSheet(
                count: selectedItems.count,
                type: $bulkType,
                onCancel: { showBulkTypeSheet = false },
                onConfirm: {
                    let chosen = bulkType
                    showBulkTypeSheet = false
                    applyBulkType(chosen)
                }
            )
        }
        .sheet(item: $pathAltsItem) { item in
            PathAlternativesSheet(
                filename: URL(fileURLWithPath: item.path).lastPathComponent,
                alternatives: knownFolders(for: item).map { abs in
                    let display = item.targetProject.flatMap {
                        PathResolver.shared.makeRelativeToProject(abs, project: $0)
                    } ?? abs
                    return PathAlternative(absolute: abs, display: display)
                },
                onPick: { abs in
                    pathAltsItem = nil
                    applyChosenFolder(item, absolutePath: abs)
                },
                onBrowse: {
                    pathAltsItem = nil
                    showPathPicker(for: item)
                },
                onCancel: { pathAltsItem = nil }
            )
        }
        .sheet(item: Binding(
            get: { appState.pendingMappingProject },
            set: { appState.pendingMappingProject = $0 }
        )) { project in
            ProjectMappingConfirmationSheet(
                project: project,
                onConfirm: {
                    // Bevestigd → herbereken de queue naar de bevestigde mapping (confidence 1.0)
                    // en hervat de verwerking die door de gate werd onderbroken.
                    appState.reresolveQueuedItems(for: project)
                    appState.pendingMappingProject = nil
                    if let pending = pendingProcessItems {
                        pendingProcessItems = nil
                        let refreshed = appState.queuedItems.filter { item in
                            pending.contains(item.id)
                        }
                        if !refreshed.isEmpty {
                            processItems(refreshed)
                        }
                    }
                },
                onCancel: {
                    appState.pendingMappingProject = nil
                    pendingProcessItems = nil
                }
            )
        }
    }

    // MARK: - Bulk Subfolder

    private func applySharedSubfolder(_ name: String) {
        for id in selectedItems {
            guard let index = appState.queuedItems.firstIndex(where: { $0.id == id }) else { continue }
            appState.queuedItems[index].targetSubfolder = name

            // Herbereken preview pad
            if let project = appState.queuedItems[index].targetProject {
                let item = appState.queuedItems[index]
                appState.queuedItems[index].previewPath = PathResolver.shared.previewRelativePath(
                    project: project,
                    assetType: item.predictedType,
                    subfolder: name,
                    musicMode: appState.config.musicClassification,
                    sfxCategory: item.predictedSfxCategory
                )
            }
        }
    }

    // MARK: - Bulk Type

    /// Wijzig het type van alle geselecteerde items in bulk. Type-specifieke velden
    /// (mood/genre/sfx-categorie/submap) worden gewist omdat ze bij het nieuwe type niet meer kloppen.
    private func applyBulkType(_ type: AssetType) {
        for id in selectedItems {
            guard let index = appState.queuedItems.firstIndex(where: { $0.id == id }) else { continue }

            // Type ONGEWIJZIGD → mood/genre/categorie/submap behouden. Voorheen wiste
            // "Toepassen" zonder wijziging de moods van alle geselecteerde items.
            guard appState.queuedItems[index].predictedType != type else { continue }

            appState.queuedItems[index].predictedType = type
            appState.queuedItems[index].predictedMood = nil
            appState.queuedItems[index].predictedGenre = nil
            appState.queuedItems[index].predictedSfxCategory = nil
            appState.queuedItems[index].targetSubfolder = nil

            if let project = appState.queuedItems[index].targetProject {
                appState.queuedItems[index].previewPath = PathResolver.shared.previewRelativePath(
                    project: project,
                    assetType: type,
                    subfolder: nil,
                    musicMode: appState.config.musicClassification,
                    sfxCategory: nil
                )
            }
        }
    }

    // MARK: - Path Confirmation Actions

    /// De effectieve submap voor learning: expliciete keuze > mood/genre/sfx-categorie
    /// (zelfde afleiding als bij resolutie, zodat regels niet met een verouderde nil
    /// worden opgeslagen en per ongeluk generiek worden).
    private func effectiveSubfolder(for item: DownloadItem) -> String? {
        if let explicit = item.targetSubfolder, !explicit.isEmpty { return explicit }
        switch item.predictedType {
        case .music:
            return appState.config.musicClassification == .mood ? item.predictedMood : item.predictedGenre
        case .sfx:
            return appState.config.useSfxSubfolders ? item.predictedSfxCategory : nil
        default:
            return nil
        }
    }

    private func acceptSuggestedPath(for item: DownloadItem) {
        guard let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) else { return }
        // Heeft de gebruiker al handmatig een map gekozen, dan is er geen suggestie
        // meer om te bevestigen — de handmatige keuze is leidend en de (verworpen)
        // suggestie mag zeker niet als regel geleerd worden.
        guard item.manualTargetPath == nil else {
            appState.queuedItems[index].needsPathConfirmation = false
            return
        }
        appState.queuedItems[index].needsPathConfirmation = false

        if let project = item.targetProject, let targetPath = item.targetPath {
            let folder = URL(fileURLWithPath: targetPath).deletingLastPathComponent().path
            let ext = URL(fileURLWithPath: item.path).pathExtension.lowercased()
            if let relative = PathResolver.shared.makeRelativeToProject(folder, project: project) {
                PathLearningManager.shared.recordPathDecision(
                    projectPath: project.projectPath,
                    assetType: item.predictedType,
                    subfolder: effectiveSubfolder(for: item),
                    chosenPath: relative,
                    fileExtension: ext,
                    source: item.detectedSource
                )

                // Preview toont het GEACCEPTEERDE pad, niet het cosmetische standaard-label
                appState.queuedItems[index].previewPath = relative.isEmpty
                    ? project.name
                    : "\(project.name) → \(relative)"
            }
        }
    }

    private func showPathPicker(for item: DownloadItem) {
        // Voorkom dat de transient popover sluit terwijl de folder picker open is
        StatusBarController.shared.setPopoverBehavior(.applicationDefined)
        defer { StatusBarController.shared.setPopoverBehavior(.transient) }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "edit.choose_target_message")
        panel.prompt = String(localized: "edit.choose")
        panel.directoryURL = preferredPickerStartDirectory(for: item)

        if panel.runModal() == .OK, let url = panel.url {
            guard let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) else { return }
            appState.queuedItems[index].manualTargetPath = url.path
            appState.queuedItems[index].needsPathConfirmation = false
            // Wis de (verworpen) suggestie en markeer als zeker: handmatige keuze is leidend
            appState.queuedItems[index].targetPath = nil
            appState.queuedItems[index].pathConfidence = 1.0
            appState.queuedItems[index].previewPath = url.lastPathComponent

            if let project = item.targetProject {
                let ext = URL(fileURLWithPath: item.path).pathExtension.lowercased()
                if let relative = PathResolver.shared.makeRelativeToProject(url.path, project: project) {
                    PathLearningManager.shared.recordPathDecision(
                        projectPath: project.projectPath,
                        assetType: item.predictedType,
                        subfolder: effectiveSubfolder(for: item),
                        chosenPath: relative,
                        fileExtension: ext,
                        source: item.detectedSource
                    )
                }
            }
        }
    }

    /// Verzamel mappen die FileFlower al kent voor dit project + type (geleerd + gescand),
    /// als absolute paden — voor de snelkeuze in de "kies andere map"-flow.
    private func knownFolders(for item: DownloadItem) -> [String] {
        guard let project = item.targetProject else { return [] }
        let structure = appState.config.mappings[project.projectPath]?.discoveredStructure
        let mainFolder = PathResolver.shared.projectMainFolderURL(for: project)
        var result: [String] = []

        // Geleerde regels voor dit type (relatieve paden → absoluut)
        if let rules = structure?.learnedRules {
            for rule in rules where rule.assetType == item.predictedType.rawValue && !rule.resolvedPath.hasPrefix("/") {
                result.append(mainFolder.appendingPathComponent(rule.resolvedPath).path)
            }
        }
        // Gescand pad voor dit type (al absoluut)
        if let discovered = structure?.discoveredPaths[item.predictedType.rawValue] {
            result.append(discovered)
        }

        // Dedupe met behoud van volgorde
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    /// Pas een gekozen (bekende) map toe op een item en leer ervan.
    private func applyChosenFolder(_ item: DownloadItem, absolutePath: String) {
        guard let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) else { return }
        appState.queuedItems[index].manualTargetPath = absolutePath
        appState.queuedItems[index].needsPathConfirmation = false
        // Wis de (verworpen) suggestie en markeer als zeker: handmatige keuze is leidend
        appState.queuedItems[index].targetPath = nil
        appState.queuedItems[index].pathConfidence = 1.0
        appState.queuedItems[index].previewPath = URL(fileURLWithPath: absolutePath).lastPathComponent

        if let project = item.targetProject {
            let ext = URL(fileURLWithPath: item.path).pathExtension.lowercased()
            if let relative = PathResolver.shared.makeRelativeToProject(absolutePath, project: project) {
                PathLearningManager.shared.recordPathDecision(
                    projectPath: project.projectPath,
                    assetType: item.predictedType,
                    subfolder: effectiveSubfolder(for: item),
                    chosenPath: relative,
                    fileExtension: ext,
                    source: item.detectedSource
                )
            }
        }
    }

    /// Bepaal de slimste startmap voor de folder picker:
    /// 1. Bestaande targetPath als die binnen het project valt
    /// 2. Anders project main folder (bv. /Volumes/.../PROJECT_B)
    /// 3. Anders system default (nil)
    private func preferredPickerStartDirectory(for item: DownloadItem) -> URL? {
        let project = item.targetProject

        if let path = item.targetPath ?? item.manualTargetPath {
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
            if let project = project {
                let projectRoot = PathResolver.shared.projectMainFolderURL(for: project).path
                if parent.path.hasPrefix(projectRoot) {
                    return parent
                }
            } else {
                return parent
            }
        }

        if let project = project {
            return PathResolver.shared.projectMainFolderURL(for: project)
        }

        return nil
    }

    // MARK: - Timer & Cleanup

    private func startAutoClearTimer() {
        clearTimer?.invalidate()
        let state = appState
        clearTimer = Timer.scheduledTimer(withTimeInterval: 3600.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                // Alleen AFGERONDE items opruimen. clearAllItems() wiste ook items die
                // nog op bevestiging wachtten of handmatig ingestelde paden hadden —
                // die verdwenen dan zonder waarschuwing na een uur open staan.
                state.clearFinishedItems()
            }
        }
    }

    /// Alle zichtbare, selecteerbare rijen geselecteerd? Attention-items tellen niet mee
    /// (die tonen geen checkbox, zie de Cmd+A-shortcut).
    private var allReadySelected: Bool {
        let ready = appState.groupedQueueItems.ready
        return !ready.isEmpty && ready.allSatisfy { selectedItems.contains($0.id) }
    }

    private func toggleSelectAll() {
        if allReadySelected {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(appState.groupedQueueItems.ready.map(\.id))
        }
    }

    private func openInFinder(for item: DownloadItem) {
        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: item.path)
        let targetURL = item.targetPath.map { URL(fileURLWithPath: $0) }

        let targetExists = targetURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
        let sourceExists = fileManager.fileExists(atPath: sourceURL.path)

        let destinationURL: URL
        if targetExists {
            destinationURL = targetURL!
        } else if let targetURL = targetURL, item.status == .completed {
            destinationURL = targetURL
        } else if sourceExists {
            destinationURL = sourceURL
        } else if let targetURL = targetURL {
            destinationURL = targetURL
        } else {
            destinationURL = sourceURL
        }

        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    private func deleteSelectedItems() {
        appState.queuedItems.removeAll { selectedItems.contains($0.id) }
        selectedItems.removeAll()
    }

    private func clearQueue() {
        appState.clearAllItems()
        selectedItems.removeAll()
    }

    // MARK: - Processing

    private func processSelected() {
        let items = appState.queuedItems.filter {
            selectedItems.contains($0.id) && !$0.needsPathConfirmation
        }
        processItems(items)
    }

    private func processAll() {
        processItems(appState.queuedItems)
    }

    private func retryItem(_ item: DownloadItem) {
        if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
            appState.queuedItems[index].status = .queued
            appState.queuedItems[index].failureReason = nil
            appState.queuedItems[index].targetPath = nil
            AnalyticsService.shared.track(.queueItemRetried())
        }
    }

    private func processItem(_ item: DownloadItem) {
        processItems([item])
    }

    private func processItems(_ items: [DownloadItem]) {
        guard LicenseManager.shared.canUseApp else {
            LicenseWindowController.show(onActivated: { }, onSkip: nil)
            return
        }

        // Gate: is de mapindeling van het doelproject nog niet bevestigd, toon dan eerst
        // het bevestigings-paneel (ook als het project via de Premiere-plugin actief werd).
        // Zo belanden bestanden nooit ongecontroleerd in de verkeerde map. Items met een
        // handmatig gekozen pad (manualTargetPath) worden niet geblokkeerd.
        // Flat preset: alles gaat expliciet naar de projectroot — niets te bevestigen.
        if appState.config.folderStructurePreset != .flat,
           let unconfirmed = items.first(where: { item in
            guard item.manualTargetPath == nil, let project = item.targetProject else { return false }
            return appState.config.mappings[project.projectPath]?.discoveredStructure?.confirmed != true
        })?.targetProject {
            // Onthoud wat er verwerkt moest worden, zodat we dat na bevestiging hervatten
            pendingProcessItems = Set(items.map(\.id))
            appState.pendingMappingProject = unconfirmed
            return
        }

        DispatchQueue.main.async {
            StatusBarController.shared.hidePopover()
        }

        Task {
            for item in items {
                await processSingleItem(item)
            }

            await MainActor.run {
                let anyCompleted = items.contains { item in
                    appState.queuedItems.first(where: { $0.id == item.id })?.status == .completed
                }
                if anyCompleted && appState.config.showPetalAnimation {
                    PetalAnimationWindow.play()
                }
            }
        }
    }

    private func showConflictDialog(for item: DownloadItem) {
        let windowController = ConflictDialogWindowController(item: item) { resolution in
            Task {
                await self.handleConflictResolution(item: item, resolution: resolution)
            }
        }
        windowController.show()
    }

    private func handleConflictResolution(item: DownloadItem, resolution: ConflictDialog.ConflictResolution) async {
        guard let targetPath = item.targetPath else { return }

        var resolvedPath = targetPath

        switch resolution {
        case .overwrite:
            resolvedPath = targetPath

        case .version:
            let url = URL(fileURLWithPath: targetPath)
            let directory = url.deletingLastPathComponent()
            let filename = url.deletingPathExtension().lastPathComponent
            let extension_ = url.pathExtension

            var version = 2
            var newPath: String
            repeat {
                let versionedFilename = "\(filename)_v\(version).\(extension_)"
                newPath = directory.appendingPathComponent(versionedFilename).path
                version += 1
            } while FileManager.default.fileExists(atPath: newPath)

            resolvedPath = newPath

        case .skip:
            await MainActor.run {
                if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                    appState.queuedItems[index].status = .skipped
                    ProcessingHistoryManager.shared.record(item: appState.queuedItems[index])
                    AnalyticsService.shared.track(.fileSkipped(
                        assetType: appState.queuedItems[index].predictedType.rawValue,
                        reason: "conflict_skip"
                    ))
                }
            }
            pendingConflictItem = nil
            return
        }

        await MainActor.run {
            if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                var updatedItem = appState.queuedItems[index]
                updatedItem.targetPath = resolvedPath
                appState.queuedItems[index] = updatedItem
                appState.queuedItems[index].status = .processing
            }
        }

        pendingConflictItem = nil
        // Bij "Overschrijven" moet FileProcessor het bestaande bestand écht vervangen —
        // anders zou uniqueDestination er stilletjes een _2-versie naast zetten.
        await processItemWithResolvedPath(
            item: item,
            resolvedPath: resolvedPath,
            allowOverwrite: resolution == .overwrite
        )
    }

    private func processItemWithResolvedPath(item: DownloadItem, resolvedPath: String, allowOverwrite: Bool = false) async {
        var processedItem = item
        processedItem.targetPath = resolvedPath

        await MainActor.run {
            if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                appState.queuedItems[index] = processedItem
                appState.queuedItems[index].status = .processing
            }
        }

        do {
            try await FileProcessor.shared.process(processedItem, allowOverwrite: allowOverwrite)

            await MainActor.run {
                if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                    appState.queuedItems[index].status = .completed
                    ProcessingHistoryManager.shared.record(item: appState.queuedItems[index])

                    let completedItem = appState.queuedItems[index]
                    AnalyticsService.shared.track(.fileImported(
                        assetType: completedItem.predictedType.rawValue,
                        sourceWebsite: completedItem.originUrl ?? "unknown",
                        hadSubfolder: completedItem.targetSubfolder != nil,
                        targetFolderType: completedItem.targetProject?.name ?? "unknown"
                    ))
                    AnalyticsService.shared.incrementImports()

                    if !UserDefaults.standard.bool(forKey: "firstImportCompleted") {
                        UserDefaults.standard.set(true, forKey: "firstImportCompleted")
                        AnalyticsService.shared.track(.firstImportCompleted(
                            destination: completedItem.targetProject?.name ?? "unknown"
                        ))
                    }

                    if appState.config.showPetalAnimation {
                        PetalAnimationWindow.play()
                    }

                    if appState.config.bringPremiereToFront {
                        if let nleType = NLEType.from(projectPath: item.targetProject?.projectPath ?? "") {
                            NLEChecker.shared.bringToFront(nleType)
                        } else if NLEChecker.shared.isRunning(.premiere) {
                            NLEChecker.shared.bringToFront(.premiere)
                        } else if NLEChecker.shared.isRunning(.resolve) {
                            NLEChecker.shared.bringToFront(.resolve)
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                    appState.queuedItems[index].status = .failed
                    appState.queuedItems[index].failureReason = error.localizedDescription
                    ProcessingHistoryManager.shared.record(item: appState.queuedItems[index])

                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: item.path)[.size] as? Int) ?? 0
                    AnalyticsService.shared.track(.importFailed(
                        fileType: URL(fileURLWithPath: item.path).pathExtension,
                        fileSizeMB: fileSize / (1024 * 1024),
                        destination: item.targetProject?.name ?? "unknown",
                        error: AnalyticsService.redactPII(error.localizedDescription)
                    ))
                    AnalyticsService.shared.track(.errorOccurred(
                        errorType: String(describing: type(of: error)),
                        context: "file_processing_resolved"
                    ))
                    AnalyticsService.shared.incrementErrors()
                }
            }
        }
    }

    private func processSingleItem(_ item: DownloadItem) async {
        if item.needsPathConfirmation { return }

        var processedItem = item

        if let manualPath = processedItem.manualTargetPath {
            let sourceURL = URL(fileURLWithPath: processedItem.path)
            let targetURL = URL(fileURLWithPath: manualPath).appendingPathComponent(sourceURL.lastPathComponent)
            processedItem.targetPath = targetURL.path
        } else {
            // Altijd her-resolven op verwerk-moment: een eerder (eager) gezet targetPath kan
            // verouderd zijn, en een stille fallback naar "eerste recente project" mag NOOIT —
            // zonder expliciet gekozen project faalt het item met een duidelijke reden.
            guard let project = processedItem.targetProject else {
                await MainActor.run {
                    if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                        appState.queuedItems[index].status = .failed
                        appState.queuedItems[index].failureReason = String(localized: "status.failed.no_project")
                        AnalyticsService.shared.track(.errorOccurred(errorType: "no_project", context: "file_processing"))
                        AnalyticsService.shared.incrementErrors()
                    }
                }
                return
            }

            var subfolder = processedItem.targetSubfolder
            if subfolder == nil {
                switch processedItem.predictedType {
                case .music:
                    let musicMode = appState.config.musicClassification
                    if musicMode == .mood, let mood = processedItem.predictedMood {
                        subfolder = mood
                    } else if musicMode == .genre, let genre = processedItem.predictedGenre {
                        subfolder = genre
                    }
                case .sfx:
                    if appState.config.useSfxSubfolders, let sfxCategory = processedItem.predictedSfxCategory {
                        subfolder = sfxCategory
                    }
                default:
                    break
                }
                processedItem.targetSubfolder = subfolder
            }

            let resolution = PathResolver.shared.resolveTargetWithConfidence(
                project: project,
                assetType: processedItem.predictedType,
                subfolder: subfolder,
                musicMode: appState.config.musicClassification,
                source: processedItem.detectedSource,
                fileName: URL(fileURLWithPath: processedItem.path).lastPathComponent
            )

            if resolution.confidence < PathResolver.shared.confidenceThreshold {
                await MainActor.run {
                    if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                        appState.queuedItems[index].needsPathConfirmation = true
                        appState.queuedItems[index].pathConfidence = resolution.confidence
                        // Persisteer de afgeleide submap zodat bevestigen/leren dezelfde
                        // submap ziet als de resolutie gebruikte
                        appState.queuedItems[index].targetSubfolder = subfolder
                        if resolution.confidence > 0 {
                            let sourceURL = URL(fileURLWithPath: processedItem.path)
                            let targetURL = resolution.targetFolder.url.appendingPathComponent(sourceURL.lastPathComponent)
                            appState.queuedItems[index].targetPath = targetURL.path
                            // Toon het ECHTE voorgestelde pad + de reden — nooit alleen een reden-string
                            let rel = resolution.targetFolder.relativePath
                            appState.queuedItems[index].previewPath = rel.isEmpty
                                ? resolution.reason
                                : "\(project.name) → \(rel)  •  \(resolution.reason)"
                        } else {
                            appState.queuedItems[index].targetPath = nil
                            appState.queuedItems[index].previewPath = resolution.reason
                        }
                    }
                }
                return
            }

            let sourceURL = URL(fileURLWithPath: processedItem.path)
            let targetURL = resolution.targetFolder.url.appendingPathComponent(sourceURL.lastPathComponent)
            processedItem.targetPath = targetURL.path
            processedItem.targetProject = project
            // Preview = het echte doel (wat er werkelijk gebeurt), niet het cosmetische label
            let rel = resolution.targetFolder.relativePath
            processedItem.previewPath = rel.isEmpty ? project.name : "\(project.name) → \(rel)"
        }

        if !rootCheckApprovedItems.contains(processedItem.id),
           let targetProject = processedItem.targetProject,
           !appState.isProjectInConfiguredRoots(targetProject) {
            await MainActor.run {
                showUnknownRootDialog(for: processedItem)
            }
            return
        }

        if let targetPath = processedItem.targetPath,
           FileManager.default.fileExists(atPath: targetPath) {
            await MainActor.run {
                pendingConflictItem = processedItem
                showConflictDialog(for: processedItem)
            }
            return
        }

        // Waarom er (g)een NLE-import komt — ook nodig om de gebruiker te kunnen
        // vertellen waarom een bestand alleen verplaatst is.
        let nleDecision: (createJob: Bool, reason: String?) = {
            let jobServer = JobServer.shared
            guard let targetProject = processedItem.targetProject else {
                return (false, String(localized: "queue.no_import.no_project",
                                      defaultValue: "verplaatst — geen project gekozen"))
            }
            // Dezelfde matching-regel als JobServer.getNextJob gebruikt, zodat een job
            // die we aanmaken ook daadwerkelijk opgehaald kan worden.
            if let premierePath = jobServer.activeProjectPath, !premierePath.isEmpty,
               jobServer.isActiveProjectFresh,
               JobServer.projectPathsMatch(targetProject.projectPath, premierePath) {
                return (true, nil)
            }
            if let resolvePath = jobServer.resolveActiveProjectPath, !resolvePath.isEmpty,
               jobServer.isResolveActiveProjectFresh,
               JobServer.projectPathsMatch(targetProject.projectPath, resolvePath) {
                return (true, nil)
            }

            // Geen match — leg uit waarom
            let premiereOpen = jobServer.activeProjectPath?.isEmpty == false && jobServer.isActiveProjectFresh
            let resolveOpen = jobServer.resolveActiveProjectPath?.isEmpty == false && jobServer.isResolveActiveProjectFresh
            if premiereOpen || resolveOpen {
                return (false, String(localized: "queue.no_import.other_project",
                                      defaultValue: "verplaatst — ander project open in de NLE"))
            }
            return (false, String(localized: "queue.no_import.nle_closed",
                                  defaultValue: "verplaatst — geen project open in Premiere/Resolve"))
        }()
        let shouldCreateNLEJob = nleDecision.createJob

        await MainActor.run {
            if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                appState.queuedItems[index] = processedItem
                appState.queuedItems[index].status = .processing
            }
        }

        do {
            try await FileProcessor.shared.process(processedItem, createNLEJob: shouldCreateNLEJob)

            await MainActor.run {
                if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                    appState.queuedItems[index].status = .completed
                    // Alleen verplaatst zonder NLE-import? Vertel WAAROM — voorheen
                    // gebeurde dat volledig stil en leek de import onverklaarbaar mislukt.
                    if let reason = nleDecision.reason {
                        appState.queuedItems[index].failureReason = reason
                    }
                    ProcessingHistoryManager.shared.record(item: appState.queuedItems[index])

                    let completedItem = appState.queuedItems[index]
                    AnalyticsService.shared.track(.fileImported(
                        assetType: completedItem.predictedType.rawValue,
                        sourceWebsite: completedItem.originUrl ?? "unknown",
                        hadSubfolder: completedItem.targetSubfolder != nil,
                        targetFolderType: completedItem.targetProject?.name ?? "unknown"
                    ))
                    AnalyticsService.shared.incrementImports()

                    if !UserDefaults.standard.bool(forKey: "firstImportCompleted") {
                        UserDefaults.standard.set(true, forKey: "firstImportCompleted")
                        AnalyticsService.shared.track(.firstImportCompleted(
                            destination: completedItem.targetProject?.name ?? "unknown"
                        ))
                    }

                    // BEWUST GEEN auto-learning van automatische plaatsingen: één foute
                    // plaatsing zou zichzelf anders als "geleerde regel" gaan herhalen.
                    // Er wordt alleen geleerd van keuzes die de gebruiker expliciet maakte
                    // (handmatige map-keuze, accepteren van een suggestie, bevestigingspaneel).

                    if shouldCreateNLEJob {
                        if appState.config.bringPremiereToFront {
                            if let nleType = NLEType.from(projectPath: item.targetProject?.projectPath ?? "") {
                                NLEChecker.shared.bringToFront(nleType)
                            } else if NLEChecker.shared.isRunning(.premiere) {
                                NLEChecker.shared.bringToFront(.premiere)
                            } else if NLEChecker.shared.isRunning(.resolve) {
                                NLEChecker.shared.bringToFront(.resolve)
                            }
                        }
                    } else {
                        if let targetPath = appState.queuedItems[index].targetPath {
                            let targetURL = URL(fileURLWithPath: targetPath)
                            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
                        }
                    }
                }
            }
        } catch {
            await MainActor.run {
                if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                    appState.queuedItems[index].status = .failed
                    appState.queuedItems[index].failureReason = error.localizedDescription
                    ProcessingHistoryManager.shared.record(item: appState.queuedItems[index])

                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: item.path)[.size] as? Int) ?? 0
                    AnalyticsService.shared.track(.importFailed(
                        fileType: URL(fileURLWithPath: item.path).pathExtension,
                        fileSizeMB: fileSize / (1024 * 1024),
                        destination: item.targetProject?.name ?? "unknown",
                        error: AnalyticsService.redactPII(error.localizedDescription)
                    ))
                    AnalyticsService.shared.track(.errorOccurred(
                        errorType: String(describing: type(of: error)),
                        context: "file_processing"
                    ))
                    AnalyticsService.shared.incrementErrors()
                }
            }
        }
    }

    private func showUnknownRootDialog(for item: DownloadItem) {
        guard let targetProject = item.targetProject else { return }
        // Root-goedkeuring geldt per PROJECT: bij een batch uit hetzelfde project
        // niet 5 vensters stapelen. Het item blijft in de wachtrij en wordt na
        // goedkeuring gewoon opnieuw verwerkt.
        guard !UnknownRootDialogWindowController.isShowing(for: targetProject) else { return }
        let windowController = UnknownRootDialogWindowController(project: targetProject) { [self] resolution in
            Task {
                await handleUnknownRootResolution(item: item, resolution: resolution)
            }
        }
        windowController.show()
    }

    private func handleUnknownRootResolution(
        item: DownloadItem,
        resolution: UnknownRootDialog.UnknownRootResolution
    ) async {
        switch resolution {
        case .proceedAndAddRoot(let rootPath):
            await MainActor.run {
                if !appState.config.projectRoots.contains(rootPath) {
                    appState.config.projectRoots.append(rootPath)
                    appState.saveConfig()
                }
                rootCheckApprovedItems.insert(item.id)
            }
            await processSingleItem(item)
            await MainActor.run {
                if appState.queuedItems.first(where: { $0.id == item.id })?.status == .completed,
                   appState.config.showPetalAnimation {
                    PetalAnimationWindow.play()
                }
            }

        case .proceedWithout:
            await MainActor.run {
                _ = rootCheckApprovedItems.insert(item.id)
            }
            await processSingleItem(item)
            await MainActor.run {
                if appState.queuedItems.first(where: { $0.id == item.id })?.status == .completed,
                   appState.config.showPetalAnimation {
                    PetalAnimationWindow.play()
                }
            }

        case .cancel:
            await MainActor.run {
                if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                    appState.queuedItems[index].status = .skipped
                    ProcessingHistoryManager.shared.record(item: appState.queuedItems[index])
                    AnalyticsService.shared.track(.fileSkipped(
                        assetType: appState.queuedItems[index].predictedType.rawValue,
                        reason: "unknown_root_cancel"
                    ))
                }
            }
        }
    }
}

// MARK: - Attention Row (needs confirmation)

struct AttentionQueueRow: View {
    let item: DownloadItem
    let onConfirm: () -> Void
    let onChooseAlternate: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ThumbnailView(
                path: item.path,
                isFolder: item.isFolder,
                assetType: item.predictedType,
                isClassifying: item.status == .classifying
            )
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(URL(fileURLWithPath: item.path).lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    // Zonder voorgesteld pad valt er niets te bevestigen — de knop
                    // deed dan letterlijk niets (item bleef in deze sectie hangen).
                    Button(String(localized: "queue.confirm"), action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.brandBurntPeach)
                        .disabled(item.targetPath == nil)
                }

                AISuggestionChip.fromItem(item, onTap: onEdit)

                if let preview = item.previewPath, !preview.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9))
                        Text(preview)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .foregroundColor(.statusWarn)
                }

                HStack(spacing: 8) {
                    if item.targetPath != nil {
                        Button(action: onConfirm) {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                Text(String(localized: "queue.confirm_suggestion"))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.destChipBg)
                            .foregroundColor(.destChipInk)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onChooseAlternate) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 9))
                            Text(String(localized: "queue.choose_other_folder"))
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.ink3)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.leading, 9)
        .padding(.trailing, 12)
        .background(Color.popAttentionBg)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.brandBurntPeach).frame(width: 3)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.line).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(String(localized: "queue.confirmation_needed"))\(URL(fileURLWithPath: item.path).lastPathComponent)")
    }
}

// MARK: - Ready Row (confident)

struct ReadyQueueRow: View {
    let item: DownloadItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onProcess: () -> Void
    let onSkip: () -> Void
    let onReveal: () -> Void
    let onRetry: () -> Void
    let bulkSubfolderAvailable: Bool
    let onBulkSubfolder: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox
            Button(action: onSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .brandBurntPeach : .ink4)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel(isSelected ? String(localized: "queue.selected") : String(localized: "queue.not_selected"))

            ThumbnailView(
                path: item.path,
                isFolder: item.isFolder,
                assetType: item.predictedType,
                isClassifying: item.status == .classifying
            )
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(URL(fileURLWithPath: item.path).lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if item.status != .queued {
                        StatusBadge(status: item.status, failureReason: item.failureReason)
                    }
                }

                DestinationChip.fromItem(item, onTap: onEdit)

                // Een afgerond item kan tóch iets te melden hebben: verplaatst, maar niet
                // geïmporteerd in de NLE. Zichtbaar in de rij, niet alleen als tooltip —
                // anders blijft het praktisch even stil als voorheen.
                if let reason = item.failureReason, !reason.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text(reason)
                            .font(.system(size: 10))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundColor(item.status == .failed ? .statusBad : .statusWarn)
                }

                if let preview = item.previewPath, !preview.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundColor(.ink4)
                        Text(preview)
                            .font(.brandMono(size: 10))
                            .foregroundColor(.ink3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer(minLength: 0)

            // Context menu
            Menu {
                Button(action: onEdit) {
                    Label(String(localized: "queue.edit"), systemImage: "pencil")
                }
                Button(action: onProcess) {
                    Label(String(localized: "queue.process"), systemImage: "play.fill")
                }
                .disabled(item.status == .processing || item.status == .completed || item.targetProject == nil)
                Button(action: onReveal) {
                    Label(String(localized: "queue.show_in_finder"), systemImage: "folder")
                }
                if item.status == .failed {
                    Button(action: onRetry) {
                        Label(String(localized: "queue.retry"), systemImage: "arrow.counterclockwise")
                    }
                }
                if bulkSubfolderAvailable {
                    Divider()
                    Button(action: onBulkSubfolder) {
                        Label(String(localized: "queue.move_to_shared_subfolder"), systemImage: "folder.badge.plus")
                    }
                }
                Divider()
                Button(action: onSkip) {
                    Label(String(localized: "queue.skip"), systemImage: "forward.fill")
                }
                Button(role: .destructive, action: onDelete) {
                    Label(String(localized: "common.delete"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.ink3)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .accessibilityLabel(String(localized: "common.more_options"))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isHovered || isSelected ? Color.brandBurntPeach.opacity(0.06) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.line).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(URL(fileURLWithPath: item.path).lastPathComponent), \(item.predictedType.displayName)")
    }
}

// MARK: - Clear Queue Confirmation

struct ClearQueueConfirmation: View {
    let itemCount: Int
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "queue.clear_confirm_title"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(String(localized: "queue.clear_confirm_message \(itemCount)"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Spacer()
                Button(String(localized: "common.cancel")) { onCancel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(String(localized: "queue.clear_queue_button")) { onConfirm() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red.opacity(0.4), lineWidth: 1.5)
                )
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Manual Folder Picker

struct ManualFolderPicker: View {
    let folders: [String]
    @Binding var selectedFolder: String?
    let onConfirm: (String) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 14))
                Text(String(localized: "classification.manual_needed"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
            }

            if folders.isEmpty {
                Text(String(localized: "classification.no_folders"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(folders, id: \.self) { folder in
                            Button(action: { selectedFolder = folder }) {
                                Text(folder)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(selectedFolder == folder ? Color.brandBurntPeach : Color.ink4.opacity(0.15))
                                    .foregroundColor(selectedFolder == folder ? .white : .primary)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button(String(localized: "classification.skip")) { onSkip() }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                Spacer()
                Button(String(localized: "classification.confirm")) {
                    if let folder = selectedFolder { onConfirm(folder) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(selectedFolder == nil)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Bulk Selection Bar

struct BulkSelectionBar: View {
    let count: Int
    let onClear: () -> Void
    let onSharedSubfolder: () -> Void
    let onEditType: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.brandBurntPeach)

            Text(String(format: String(localized: "queue.selection_count"), count))
                .font(.system(size: 12, weight: .medium))

            Spacer()

            Button(action: onEditType) {
                Label(String(localized: "edit.type"), systemImage: "tag")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(action: onSharedSubfolder) {
                Label(String(localized: "queue.move_to_shared_subfolder"), systemImage: "folder.badge.plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help(String(localized: "common.delete"))

            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "queue.clear_selection"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.brandBurntPeach.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.line).frame(height: 1)
        }
    }
}

// MARK: - Bulk Subfolder Sheet

struct BulkSubfolderSheet: View {
    let count: Int
    var project: ProjectInfo? = nil
    var assetType: AssetType = .footage
    var musicMode: MusicMode = .mood
    @Binding var subfolderName: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @FocusState private var isInputFocused: Bool
    @State private var existingSubfolders: [String] = []

    private var trimmed: String { subfolderName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "queue.shared_subfolder_title"))
                    .font(.system(size: 14, weight: .semibold))
                Text(String(format: String(localized: "queue.shared_subfolder_subtitle"), count))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            TextField(String(localized: "queue.shared_subfolder_placeholder"), text: $subfolderName)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .onSubmit {
                    if !trimmed.isEmpty { onConfirm() }
                }

            // Bestaande submappen om uit te kiezen (indien gevonden)
            if !existingSubfolders.isEmpty {
                Text(String(localized: "queue.shared_subfolder_existing"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(existingSubfolders, id: \.self) { name in
                            Button(action: { subfolderName = name }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 10))
                                        .foregroundColor(.accentColor)
                                    Text(name).font(.system(size: 12))
                                    Spacer(minLength: 0)
                                    if trimmed == name {
                                        Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }

            // Live route-preview
            if let project = project {
                Text(PathResolver.shared.previewRelativePath(
                    project: project,
                    assetType: assetType,
                    subfolder: trimmed.isEmpty ? nil : trimmed,
                    musicMode: musicMode,
                    sfxCategory: assetType == .sfx ? (trimmed.isEmpty ? nil : trimmed) : nil
                ))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }

            Text(String(localized: "queue.shared_subfolder_hint"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            HStack {
                Spacer()
                Button(String(localized: "common.cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "common.apply"), action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { isInputFocused = true }
        .task { await loadExistingSubfolders() }
    }

    /// Laad bestaande on-disk submappen van de asset-map (juiste hoofd-projectmap), off-main.
    private func loadExistingSubfolders() async {
        guard let project = project, assetType != .unknown else { return }
        let mainPath = PathResolver.shared.projectMainFolderURL(for: project).path
        let type = assetType
        let result: [String] = await Task.detached(priority: .userInitiated) {
            let rootURL = URL(fileURLWithPath: mainPath)
            guard let folderName = await MainActor.run(body: {
                BinMatcher.shared.findMatchingFolder(for: type, in: rootURL)
            }) else { return [] }
            let target = rootURL.appendingPathComponent(folderName)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: target,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return contents.filter { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }.map { $0.lastPathComponent }.sorted()
        }.value
        existingSubfolders = result
    }
}

// MARK: - Bulk Type Sheet

struct BulkTypeSheet: View {
    let count: Int
    @Binding var type: AssetType
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "edit.type"))
                    .font(.system(size: 14, weight: .semibold))
                Text(String(format: String(localized: "queue.selection_count"), count))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Picker(String(localized: "edit.type"), selection: $type) {
                ForEach(AssetType.allCases.filter { $0 != .unknown }, id: \.self) { t in
                    Label(t.displayName, systemImage: iconForType(t)).tag(t)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            HStack {
                Spacer()
                Button(String(localized: "common.cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "common.apply"), action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

// MARK: - Path Alternatives Sheet

struct PathAlternative: Identifiable {
    let absolute: String
    let display: String
    var id: String { absolute }
}

/// Snelkeuze van mappen die FileFlower al kent (geleerd + gescand) bij "kies andere map".
struct PathAlternativesSheet: View {
    let filename: String
    let alternatives: [PathAlternative]
    let onPick: (String) -> Void
    let onBrowse: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "queue.choose_other_folder"))
                    .font(.system(size: 14, weight: .semibold))
                Text(filename)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(spacing: 4) {
                ForEach(alternatives) { alt in
                    Button(action: { onPick(alt.absolute) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundColor(.accentColor)
                            Text(alt.display)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button(String(localized: "common.cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: onBrowse) {
                    Label(String(localized: "edit.choose"), systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
