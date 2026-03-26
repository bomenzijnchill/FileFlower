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
    
    init(selectedItemForPicker: Binding<DownloadItem?>, isShowingClearConfirmation: Binding<Bool> = .constant(false)) {
        self._selectedItemForPicker = selectedItemForPicker
        self._isShowingClearConfirmation = isShowingClearConfirmation
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Inline clear queue confirmatie (boven de toolbar)
            if isShowingClearConfirmation {
                ClearQueueConfirmation(
                    itemCount: appState.queuedItems.count,
                    onConfirm: {
                        // Eerst de confirmatie sluiten, dan pas de queue legen
                        isShowingClearConfirmation = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            clearQueue()
                        }
                    },
                    onCancel: {
                        // Direct de binding updaten zonder animatie om crashes te voorkomen
                        isShowingClearConfirmation = false
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
            
            // Toolbar
            if !appState.queuedItems.isEmpty {
                HStack(spacing: 8) {
                    Button(action: processAll) {
                        Label(String(localized: "queue.process_all"), systemImage: "play.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(appState.queuedItems.isEmpty)
                    
                    Button(action: processSelected) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(selectedItems.isEmpty)
                    .help(String(localized: "queue.process_selected"))
                    
                    Spacer()

                    Text("\(appState.queuedItems.count) items")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Button(action: { showHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(String(localized: "history.show"))
                    .popover(isPresented: $showHistory) {
                        HistoryView(
                            records: ProcessingHistoryManager.shared.todayRecords(),
                            onDismiss: { showHistory = false }
                        )
                        .frame(width: 400, height: 350)
                    }

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            handleDeleteAction()
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(selectedItems.isEmpty ? String(localized: "queue.clear_queue") : String(localized: "queue.delete_selected \(selectedItems.count)"))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 36)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            }
            
            // List - altijd scrollbaar
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.queuedItems) { item in
                        QueueItemRow(
                            item: item,
                            isSelected: selectedItems.contains(item.id),
                            onSelect: {
                                if selectedItems.contains(item.id) {
                                    selectedItems.remove(item.id)
                                } else {
                                    selectedItems.insert(item.id)
                                }
                            },
                            onChangeLocation: {
                                selectedItemForPicker = item
                            },
                            onProcess: { processItem(item) },
                            onOpenInFinder: { openInFinder(for: item) },
                            onRetry: { retryItem(item) }
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            // QuickLook voor het eerste geselecteerde item
            if let firstSelected = selectedItems.first,
               let item = appState.queuedItems.first(where: { $0.id == firstSelected }) {
                let url = URL(fileURLWithPath: item.path)
                FileSafeQuickLookCoordinator.shared.toggle(url: url)
                return .handled
            }
            return .ignored
        }
        .onAppear {
            startAutoClearTimer()
        }
        .onDisappear {
            clearTimer?.invalidate()
        }
    }
    
    private func startAutoClearTimer() {
        // Clear queue automatisch na 1 uur
        clearTimer?.invalidate()
        let state = appState
        clearTimer = Timer.scheduledTimer(withTimeInterval: 3600.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                state.clearAllItems()
            }
        }
    }
    
    private func handleDeleteAction() {
        if selectedItems.isEmpty {
            // Geen selectie: vraag bevestiging om hele queue te legen
            isShowingClearConfirmation = true
        } else {
            // Er zijn items geselecteerd: verwijder alleen die items
            deleteSelectedItems()
        }
    }
    
    private func openInFinder(for item: DownloadItem) {
        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: item.path)
        let targetURL = item.targetPath.map { URL(fileURLWithPath: $0) }
        
        let targetExists = targetURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
        let sourceExists = fileManager.fileExists(atPath: sourceURL.path)
        
        // Geef de verplaatste locatie prioriteit als die bekend is
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
    
    private func processSelected() {
        let items = appState.queuedItems.filter { selectedItems.contains($0.id) }
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
        // Blokkeer verwerking als trial verlopen en geen license
        guard LicenseManager.shared.canUseApp else {
            LicenseWindowController.show(onActivated: { }, onSkip: nil)
            return
        }

        // Sluit de popover zodra een verwerk-actie gestart wordt
        DispatchQueue.main.async {
            StatusBarController.shared.hidePopover()
        }
        
        Task {
            for item in items {
                await processSingleItem(item)
            }

            // Speel bloemblaadjes-animatie als minstens één item succesvol is
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
            // Blijf hetzelfde pad gebruiken - overschrijven
            resolvedPath = targetPath
            
        case .version:
            // Voeg versienummer toe
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
            // Skip dit item
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
        
        // Update item met resolved path
        await MainActor.run {
            if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                var updatedItem = appState.queuedItems[index]
                updatedItem.targetPath = resolvedPath
                appState.queuedItems[index] = updatedItem
                
                // Start processing met de resolved path
                appState.queuedItems[index].status = .processing
            }
        }
        
        pendingConflictItem = nil
        
        // Verwerk het item met de resolved path (skip conflict check)
        await processItemWithResolvedPath(item: item, resolvedPath: resolvedPath)
    }
    
    private func processItemWithResolvedPath(item: DownloadItem, resolvedPath: String) async {
        var processedItem = item
        processedItem.targetPath = resolvedPath
        
        // Process item zonder conflict check
        await MainActor.run {
            if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                appState.queuedItems[index] = processedItem
                appState.queuedItems[index].status = .processing
            }
        }
        
        do {
            try await FileProcessor.shared.process(processedItem)

            await MainActor.run {
                if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                    appState.queuedItems[index].status = .completed
                    ProcessingHistoryManager.shared.record(item: appState.queuedItems[index])

                    // Analytics: file imported
                    let completedItem = appState.queuedItems[index]
                    AnalyticsService.shared.track(.fileImported(
                        assetType: completedItem.predictedType.rawValue,
                        sourceWebsite: completedItem.originUrl ?? "unknown",
                        hadSubfolder: completedItem.targetSubfolder != nil,
                        targetFolderType: completedItem.targetProject?.name ?? "unknown"
                    ))
                    AnalyticsService.shared.incrementImports()

                    // First import ever?
                    if !UserDefaults.standard.bool(forKey: "firstImportCompleted") {
                        UserDefaults.standard.set(true, forKey: "firstImportCompleted")
                        AnalyticsService.shared.track(.firstImportCompleted(
                            destination: completedItem.targetProject?.name ?? "unknown"
                        ))
                    }

                    if appState.config.showPetalAnimation {
                        PetalAnimationWindow.play()
                    }

                    // Haal de actieve NLE naar voren als dit is ingeschakeld
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

                    // Analytics: import failed
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: item.path)[.size] as? Int) ?? 0
                    AnalyticsService.shared.track(.importFailed(
                        fileType: URL(fileURLWithPath: item.path).pathExtension,
                        fileSizeMB: fileSize / (1024 * 1024),
                        destination: item.targetProject?.name ?? "unknown",
                        error: error.localizedDescription
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
        // Resolve target path if not set
        var processedItem = item
        if processedItem.targetPath == nil {
            guard let project = processedItem.targetProject ?? appState.recentProjects.first else {
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
            
            // Bepaal de subfolder op basis van genre/mood/categorie detectie
            var subfolder = processedItem.targetSubfolder
            if subfolder == nil {
                switch processedItem.predictedType {
                case .music:
                    // Gebruik scraped genre/mood als submap afhankelijk van de music mode setting
                    let musicMode = appState.config.musicClassification
                    if musicMode == .mood, let mood = processedItem.predictedMood {
                        subfolder = mood
                        #if DEBUG
                        print("QueueView: Automatisch mood submap toegevoegd: \(mood)")
                        #endif
                    } else if musicMode == .genre, let genre = processedItem.predictedGenre {
                        subfolder = genre
                        #if DEBUG
                        print("QueueView: Automatisch genre submap toegevoegd: \(genre)")
                        #endif
                    }
                    
                case .sfx:
                    // Gebruik scraped SFX categorie als submap (alleen als useSfxSubfolders aan staat)
                    if appState.config.useSfxSubfolders, let sfxCategory = processedItem.predictedSfxCategory {
                        subfolder = sfxCategory
                        #if DEBUG
                        print("QueueView: Automatisch SFX categorie submap toegevoegd: \(sfxCategory)")
                        #endif
                    }
                    
                default:
                    break
                }
                processedItem.targetSubfolder = subfolder
            }
            
            do {
                let target = try PathResolver.shared.resolveTarget(
                    project: project,
                    assetType: processedItem.predictedType,
                    subfolder: subfolder,
                    musicMode: appState.config.musicClassification,
                    source: processedItem.detectedSource
                )
                
                let sourceURL = URL(fileURLWithPath: processedItem.path)
                let targetURL = target.url.appendingPathComponent(sourceURL.lastPathComponent)
                processedItem.targetPath = targetURL.path
                processedItem.targetProject = project
            } catch {
                await MainActor.run {
                    if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                        appState.queuedItems[index].status = .failed
                        appState.queuedItems[index].failureReason = String(localized: "status.failed.path_error")
                        AnalyticsService.shared.track(.errorOccurred(
                            errorType: "path_resolve_failed",
                            context: "file_processing"
                        ))
                        AnalyticsService.shared.incrementErrors()
                    }
                }
                return
            }
        }
        
        // Check of project niet in geconfigureerde roots staat — toon waarschuwing
        if !rootCheckApprovedItems.contains(processedItem.id),
           let targetProject = processedItem.targetProject,
           !appState.isProjectInConfiguredRoots(targetProject) {
            await MainActor.run {
                showUnknownRootDialog(for: processedItem)
            }
            return
        }

        // Check for conflicts
        if let targetPath = processedItem.targetPath,
           FileManager.default.fileExists(atPath: targetPath) {
            await MainActor.run {
                pendingConflictItem = processedItem
                showConflictDialog(for: processedItem)
            }
            return
        }

        // Bepaal of het geselecteerde project overeenkomt met het actieve NLE project.
        // Alleen als dat zo is maken we een NLE import job aan; anders alleen verplaatsen.
        let shouldCreateNLEJob: Bool = {
            let jobServer = JobServer.shared
            // Check Premiere Pro
            if let premierePath = jobServer.activeProjectPath, jobServer.isActiveProjectFresh {
                if let targetProject = processedItem.targetProject {
                    let premiereDir = URL(fileURLWithPath: premierePath).deletingLastPathComponent().path
                    // Match: target folder bevat het .prproj, of het is exact hetzelfde pad
                    if targetProject.projectPath == premierePath ||
                       targetProject.projectPath == premiereDir ||
                       premierePath.hasPrefix(targetProject.projectPath + "/") {
                        return true
                    }
                }
            }
            // Check DaVinci Resolve
            if let resolvePath = jobServer.resolveActiveProjectPath, jobServer.isResolveActiveProjectFresh {
                if let targetProject = processedItem.targetProject {
                    let resolveDir = URL(fileURLWithPath: resolvePath).deletingLastPathComponent().path
                    if targetProject.projectPath == resolvePath ||
                       targetProject.projectPath == resolveDir ||
                       resolvePath.hasPrefix(targetProject.projectPath + "/") {
                        return true
                    }
                }
            }
            // Geen NLE open of project matcht niet → alleen verplaatsen
            return false
        }()

        // Process item
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
                    ProcessingHistoryManager.shared.record(item: appState.queuedItems[index])

                    // Analytics: file imported
                    let completedItem = appState.queuedItems[index]
                    AnalyticsService.shared.track(.fileImported(
                        assetType: completedItem.predictedType.rawValue,
                        sourceWebsite: completedItem.originUrl ?? "unknown",
                        hadSubfolder: completedItem.targetSubfolder != nil,
                        targetFolderType: completedItem.targetProject?.name ?? "unknown"
                    ))
                    AnalyticsService.shared.incrementImports()

                    // First import ever?
                    if !UserDefaults.standard.bool(forKey: "firstImportCompleted") {
                        UserDefaults.standard.set(true, forKey: "firstImportCompleted")
                        AnalyticsService.shared.track(.firstImportCompleted(
                            destination: completedItem.targetProject?.name ?? "unknown"
                        ))
                    }

                    if shouldCreateNLEJob {
                        // NLE import job aangemaakt — breng NLE naar voren als ingeschakeld
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
                        // Geen NLE import — open de doelmap in Finder
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

                    // Analytics: import failed
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: item.path)[.size] as? Int) ?? 0
                    AnalyticsService.shared.track(.importFailed(
                        fileType: URL(fileURLWithPath: item.path).pathExtension,
                        fileSizeMB: fileSize / (1024 * 1024),
                        destination: item.targetProject?.name ?? "unknown",
                        error: error.localizedDescription
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
                rootCheckApprovedItems.insert(item.id)
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

struct QueueItemRow: View {
    let item: DownloadItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onChangeLocation: () -> Void
    let onProcess: () -> Void
    let onOpenInFinder: () -> Void
    let onRetry: () -> Void
    
    @ObservedObject private var appState = AppState.shared
    @State private var isHovered = false
    @State private var selectedManualFolder: String?
    @State private var isAddingSubfolder = false
    @State private var newSubfolderName = ""

    // Veelgebruikte SFX categorieën (gebaseerd op Epidemic Sound)
    private let sfxCategories = [
        // Impacts & Hits
        "Impacts", "Hits", "Punches", "Crashes", "Explosions",
        // Transitions
        "Risers", "Swooshes", "Whooshes", "Swishes", "Downers",
        // Designed
        "Designed", "Cinematic", "Sci-Fi", "Horror",
        // Foley
        "Foley", "Footsteps", "Cloth", "Props",
        // Ambience
        "Ambience", "Nature", "Urban", "Room Tone",
        // UI & Tech
        "UI", "Clicks", "Beeps", "Notifications", "Glitches",
        // Miscellaneous
        "Cartoon", "Comedy", "Magic", "Weapons", "Vehicles"
    ]
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection checkbox
            Button(action: onSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help(isSelected ? String(localized: "queue.deselect") : String(localized: "queue.select"))
            
            // Bestandspreview thumbnail (of SF Symbol fallback)
            ThumbnailView(
                path: item.path,
                isFolder: item.isFolder,
                assetType: item.predictedType,
                isClassifying: item.status == .classifying
            )

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Regel 1: Status badge + bestandsnaam
                HStack(spacing: 6) {
                    StatusBadge(status: item.status, failureReason: item.failureReason)

                    Text(URL(fileURLWithPath: item.path).lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    if let childFiles = item.childFiles, !childFiles.isEmpty {
                        Text(String(localized: "queue.file_count \(childFiles.count)"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                // Regel 2: Type dropdown + subcategorieën
                HStack(spacing: 8) {
                    // Type dropdown
                    Menu {
                        ForEach(AssetType.allCases.filter { $0 != .unknown }, id: \.self) { type in
                            Button(action: {
                                if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                                    let oldType = appState.queuedItems[index].predictedType
                                    appState.queuedItems[index].predictedType = type

                                    // Log correctie voor few-shot learning
                                    if oldType != type {
                                        CorrectionHistoryManager.shared.recordCorrection(
                                            item: appState.queuedItems[index],
                                            originalType: oldType,
                                            correctedType: type
                                        )
                                    }

                                    // Herbereken preview pad
                                    updatePreviewPath(at: index)
                                }
                            }) {
                                Label(type.displayName, systemImage: iconForType(type))
                            }
                        }
                    } label: {
                        if item.status == .classifying {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text(String(localized: "queue.classifying"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Label(item.predictedType.displayName, systemImage: iconForType(item.predictedType))
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(item.status == .classifying)

                    // Toon genre/mood/categorie als beschikbaar
                    if item.predictedType == .music {
                        if let genre = item.predictedGenre {
                            Text("•")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text(genre)
                                .font(.system(size: 11))
                                .foregroundColor(.purple)
                        }
                        if let mood = item.predictedMood {
                            Text("•")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text(mood)
                                .font(.system(size: 11))
                                .foregroundColor(.cyan)
                        }
                    } else if item.predictedType == .sfx {
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.5))

                        // SFX categorie dropdown
                        Menu {
                            ForEach(sfxCategories, id: \.self) { category in
                                Button(action: {
                                    if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                                        appState.queuedItems[index].predictedSfxCategory = category
                                        // Herbereken preview pad
                                        updatePreviewPath(at: index)
                                    }
                                }) {
                                    if category == item.predictedSfxCategory {
                                        Label(category, systemImage: "checkmark")
                                    } else {
                                        Text(category)
                                    }
                                }
                            }
                        } label: {
                            Text(item.predictedSfxCategory ?? String(localized: "queue.category_placeholder"))
                                .font(.system(size: 11))
                                .foregroundColor(item.predictedSfxCategory != nil ? .orange : .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    // Subfolder dropdown (bestaande mappen + eigen naam toevoegen)
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.5))

                    if isAddingSubfolder {
                        HStack(spacing: 4) {
                            TextField("Add subfolder", text: $newSubfolderName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                                .frame(width: 120)
                                .onSubmit {
                                    if !newSubfolderName.trimmingCharacters(in: .whitespaces).isEmpty {
                                        if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                                            appState.queuedItems[index].targetSubfolder = newSubfolderName.trimmingCharacters(in: .whitespaces)
                                            updatePreviewPath(at: index)
                                        }
                                    }
                                    isAddingSubfolder = false
                                    newSubfolderName = ""
                                }
                            Button(action: { isAddingSubfolder = false; newSubfolderName = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Menu {
                            Button(action: {
                                if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                                    appState.queuedItems[index].targetSubfolder = nil
                                    updatePreviewPath(at: index)
                                }
                            }) {
                                if item.targetSubfolder == nil {
                                    Label(String(localized: "queue.no_subfolder"), systemImage: "checkmark")
                                } else {
                                    Text(String(localized: "queue.no_subfolder"))
                                }
                            }

                            if let subfolders = detectExistingSubfolders(), !subfolders.isEmpty {
                                Divider()
                                ForEach(subfolders, id: \.self) { subfolder in
                                    Button(action: {
                                        if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                                            appState.queuedItems[index].targetSubfolder = subfolder
                                            updatePreviewPath(at: index)
                                        }
                                    }) {
                                        if subfolder == item.targetSubfolder {
                                            Label(subfolder, systemImage: "checkmark")
                                        } else {
                                            Text(subfolder)
                                        }
                                    }
                                }
                            }

                            Divider()
                            Button(action: { isAddingSubfolder = true }) {
                                Label("Add subfolder...", systemImage: "plus")
                            }
                        } label: {
                            Text(item.targetSubfolder ?? String(localized: "queue.subfolder"))
                                .font(.system(size: 11))
                                .foregroundColor(item.targetSubfolder != nil ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Preview pad: laat zien waar het bestand naartoe gaat (incl. project naam)
                if item.status == .queued, let preview = item.previewPath, !preview.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(preview)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                // Quick-fix acties voor mislukte items
                if item.status == .failed {
                    HStack(spacing: 6) {
                        if let reason = item.failureReason {
                            Text(reason)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        if item.targetProject == nil {
                            Button(action: {
                                onRetry()
                                onChangeLocation()
                            }) {
                                Label(String(localized: "queue.fix.select_project"), systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(.blue)
                        } else {
                            Button(action: onRetry) {
                                Label(String(localized: "queue.fix.retry"), systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }

                // Manuele classificatie prompt voor cloud downloads met onbekend type
                if item.needsManualClassification {
                    ManualFolderPicker(
                        folders: getProjectSubfolders(),
                        selectedFolder: $selectedManualFolder,
                        onConfirm: { folder in
                            handleManualFolderSelection(itemId: item.id, folder: folder)
                        },
                        onSkip: {
                            if let index = appState.queuedItems.firstIndex(where: { $0.id == item.id }) {
                                appState.queuedItems[index].status = .skipped
                            }
                        }
                    )
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 6) {
                // Open in Finder button
                Button(action: onOpenInFinder) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open in Finder")
                
                // Verwerk button (groen)
                Button(action: onProcess) {
                    if item.status == .processing {
                        Image(systemName: "hourglass")
                            .font(.system(size: 10))
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)
                .disabled(item.status == .processing || item.status == .completed || item.targetProject == nil)
                .help(item.status == .processing ? String(localized: "queue.processing") : String(localized: "queue.process"))
            }
            .frame(width: 80)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            Group {
                if isHovered {
                    Color.accentColor.opacity(0.1)
                } else if isSelected {
                    Color.accentColor.opacity(0.1)
                } else {
                    Color.clear
                }
            }
        )
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onChangeLocation()
        }
    }
    
    private func getProjectSubfolders() -> [String] {
        guard let project = item.targetProject else { return [] }
        let projectPathURL = URL(fileURLWithPath: project.projectPath)
        let projectRoot = projectPathURL.deletingLastPathComponent()

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: projectRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }
            .map { $0.lastPathComponent }
            .sorted()
    }

    private func handleManualFolderSelection(itemId: UUID, folder: String) {
        guard let index = appState.queuedItems.firstIndex(where: { $0.id == itemId }) else { return }
        var updated = appState.queuedItems[index]
        updated.targetSubfolder = folder
        updated.needsManualClassification = false

        // Recalculate target path met de geselecteerde submap
        if let project = updated.targetProject {
            let projectPathURL = URL(fileURLWithPath: project.projectPath)
            let projectRoot = projectPathURL.deletingLastPathComponent()
            let targetFolder = projectRoot.appendingPathComponent(folder)
            let filename = URL(fileURLWithPath: updated.path).lastPathComponent
            updated.targetPath = targetFolder.appendingPathComponent(filename).path
        }

        appState.queuedItems[index] = updated
    }

    /// Verwijder de projectnaam uit het preview pad (staat al in de header)
    private func previewWithoutProject(_ preview: String) -> String {
        // Preview format: "ProjectName → Audio → Music"
        // We willen: "Audio → Music"
        let parts = preview.components(separatedBy: " → ")
        if parts.count > 1 {
            return parts.dropFirst().joined(separator: " → ")
        }
        return preview
    }

    /// Detecteer bestaande submappen in de doelmap voor dit item's asset type
    private func detectExistingSubfolders() -> [String]? {
        guard let project = item.targetProject,
              item.predictedType != .unknown,
              item.predictedType != .sfx,  // SFX heeft al eigen categorie dropdown
              item.predictedType != .music else { return nil }  // Music heeft genre/mood

        // Zoek de doelmap voor dit asset type
        let rootPath = project.rootPath
        let rootURL = URL(fileURLWithPath: rootPath)

        // Gebruik BinMatcher om de juiste map te vinden
        guard let folderName = BinMatcher.shared.findMatchingFolder(
            for: item.predictedType,
            in: rootURL
        ) else { return nil }

        let targetFolderURL = rootURL.appendingPathComponent(folderName)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: targetFolderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let subfolders = contents
            .filter { url in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }
            .map { $0.lastPathComponent }
            .sorted()

        return subfolders.isEmpty ? nil : subfolders
    }

    /// Herbereken het preview-pad voor een item na type/project/categorie wijziging
    private func updatePreviewPath(at index: Int) {
        let item = appState.queuedItems[index]
        guard let project = item.targetProject, item.predictedType != .unknown else {
            appState.queuedItems[index].previewPath = nil
            return
        }
        let subfolder = item.targetSubfolder ?? item.predictedMood ?? item.predictedGenre
        appState.queuedItems[index].previewPath = PathResolver.shared.previewRelativePath(
            project: project,
            assetType: item.predictedType,
            subfolder: subfolder,
            musicMode: appState.config.musicClassification,
            sfxCategory: item.predictedSfxCategory
        )
    }

    private func iconForType(_ type: AssetType) -> String {
        switch type {
        case .music: return "music.note"
        case .sfx: return "waveform"
        case .vo: return "mic"
        case .footage: return "video.fill"
        case .motionGraphic: return "video"
        case .graphic: return "photo"
        case .stockFootage: return "film"
        case .unknown: return "questionmark"
        }
    }
}

struct StatusBadge: View {
    let status: ItemStatus
    var failureReason: String? = nil

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.2))
            .foregroundColor(status.color)
            .clipShape(Capsule())
            .help(status == .failed && failureReason != nil ? failureReason! : "")
    }
}

extension ItemStatus {
    var displayName: String {
        switch self {
        case .queued: return String(localized: "status.queued")
        case .classifying: return String(localized: "status.classifying")
        case .processing: return String(localized: "status.processing")
        case .completed: return String(localized: "status.completed")
        case .failed: return String(localized: "status.failed")
        case .skipped: return String(localized: "status.skipped")
        }
    }
    
    var color: Color {
        switch self {
        case .queued: return .blue
        case .classifying: return .purple
        case .processing: return .orange
        case .completed: return .green
        case .failed: return .red
        case .skipped: return .gray
        }
    }
}

/// Inline uitschuifbare clear queue confirmatie
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
                
                Button(String(localized: "common.cancel")) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(String(localized: "queue.clear_queue_button")) {
                    onConfirm()
                }
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

/// Inline folder picker voor cloud downloads die niet automatisch geclassificeerd konden worden
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
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(folders, id: \.self) { folder in
                            Button(action: {
                                selectedFolder = folder
                            }) {
                                Text(folder)
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(selectedFolder == folder ? Color.accentColor : Color.secondary.opacity(0.15))
                                    .foregroundColor(selectedFolder == folder ? .white : .primary)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button(String(localized: "classification.skip")) {
                    onSkip()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Spacer()

                Button(String(localized: "classification.confirm")) {
                    if let folder = selectedFolder {
                        onConfirm(folder)
                    }
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
