import SwiftUI
#if canImport(BridgeKit)
import BridgeKit
#endif

/// Hoofdview met tabs voor DownloadSync en FolderSync
struct MainTabView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var volumeDetector = VolumeDetector.shared
    @Binding var selectedItemForPicker: DownloadItem?
    @Binding var isShowingFolderSyncForm: Bool
    @Binding var isShowingClearConfirmation: Bool

    enum Tab: String, CaseIterable {
        case downloadSync = "DownloadSync"
        case folderSync = "FolderSync"
        case loadFolder = "LoadFolder"
        case fileSafe = "FileSafe"
        #if canImport(BridgeKit)
        case bridge = "Bridge"
        #endif

        var icon: String {
            switch self {
            case .downloadSync: return "arrow.down.circle"
            case .folderSync: return "arrow.triangle.2.circlepath"
            case .loadFolder: return "folder.badge.plus"
            case .fileSafe: return "externaldrive.badge.checkmark"
            #if canImport(BridgeKit)
            case .bridge: return "arrow.left.arrow.right.circle"
            #endif
            }
        }

        var displayTitle: String {
            switch self {
            case .downloadSync: return String(localized: "tab.downloads")
            case .folderSync: return String(localized: "tab.folder_sync")
            case .loadFolder: return String(localized: "tab.quick_load")
            case .fileSafe: return String(localized: "tab.filesafe")
            #if canImport(BridgeKit)
            case .bridge: return String(localized: "tab.bridge", defaultValue: "Bridge")
            #endif
            }
        }
    }

    @State private var selectedTab: Tab = .downloadSync

    /// Tabs die zichtbaar zijn — FileSafe alleen als er externe schijven zijn
    private var visibleTabs: [Tab] {
        var tabs: [Tab] = [.downloadSync, .folderSync, .loadFolder]
        if !volumeDetector.externalVolumes.isEmpty {
            tabs.append(.fileSafe)
        }
        #if canImport(BridgeKit)
        tabs.append(.bridge)
        #endif
        return tabs
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(visibleTabs, id: \.self) { tab in
                    TabButton(
                        title: tab.displayTitle,
                        icon: tab.icon,
                        isSelected: selectedTab == tab,
                        badgeCount: badgeCount(for: tab)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Divider()
                .padding(.top, 8)

            // Content
            Group {
                switch selectedTab {
                case .downloadSync:
                    DownloadSyncContent(
                        selectedItemForPicker: $selectedItemForPicker,
                        isShowingClearConfirmation: $isShowingClearConfirmation
                    )
                case .folderSync:
                    FolderSyncView(isShowingForm: $isShowingFolderSyncForm)
                case .loadFolder:
                    LoadFolderView()
                case .fileSafe:
                    FileSafeLauncherView()
                #if canImport(BridgeKit)
                case .bridge:
                    BridgePopoverView {
                        BridgeExplorerWindowController.show()
                    }
                #endif
                }
            }
            .transition(.opacity)

            // Per-tab footer
            tabFooter
        }
        .onAppear {
            volumeDetector.startMonitoring()
        }
        .onChange(of: volumeDetector.externalVolumes) { _, newVolumes in
            // Als FileSafe tab verdwijnt terwijl die geselecteerd is, ga terug naar DownloadSync
            if newVolumes.isEmpty && selectedTab == .fileSafe {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = .downloadSync
                }
            }
        }
        .onChange(of: appState.shouldSwitchToFileSafeTab) { _, shouldSwitch in
            if shouldSwitch && !volumeDetector.externalVolumes.isEmpty {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = .fileSafe
                }
                appState.shouldSwitchToFileSafeTab = false
            }
        }
    }

    @ViewBuilder
    private var tabFooter: some View {
        switch selectedTab {
        case .downloadSync:
            // De teller moet de WERKELIJKE actie weerspiegelen: bij een actieve selectie
            // verwerkt de knop alleen die selectie (voorheen stond er "Verwerk (5)"
            // terwijl er maar 1 geselecteerd item verwerkt werd).
            let selection = appState.selectedQueueItemCount
            let count = selection > 0 ? selection : appState.readyToProcessCount
            let total = appState.queuedItems.count
            PopoverFooter(
                leftText: total > 0 ? "\(total) \(String(localized: "common.items"))" : "",
                ctaTitle: String(localized: "footer.process"),
                ctaCount: count,
                ctaEnabled: count > 0,
                ctaAction: {
                    NotificationCenter.default.post(name: .processAllFromFooter, object: nil)
                },
                secondaryIcon: total > 0 ? "trash" : nil,
                secondaryHelp: String(localized: "queue.clear_queue"),
                secondaryAction: {
                    // Nogmaals klikken sluit de bevestiging weer; het echte legen
                    // gebeurt pas na bevestiging in ClearQueueConfirmation.
                    isShowingClearConfirmation.toggle()
                }
            ) {
                footerMenuItems
            }
        case .folderSync:
            let enabledCount = appState.config.folderSyncs.filter(\.isEnabled).count
            PopoverFooter(leftText: enabledCount > 0 ? String(localized: "footer.sync_active") : "") {
                footerMenuItems
            }
        case .loadFolder:
            PopoverFooter(leftText: String(localized: "footer.load_hint")) {
                footerMenuItems
            }
        case .fileSafe:
            PopoverFooter(leftText: String(localized: "footer.connect_drive")) {
                footerMenuItems
            }
        #if canImport(BridgeKit)
        case .bridge:
            // Zelfde patroon als FolderSync en LoadFolder: een vaste hint links, en de
            // acties staan in de weergave zelf. Bewust geen live status hier — de footer
            // observeert de client niet, dus die zou pas bijwerken als er toevallig iets
            // anders hertekent. De echte status staat bovenin het tabblad.
            PopoverFooter(leftText: String(localized: "footer.bridge_hint",
                                           defaultValue: "Deel mappen met je andere machines")) {
                footerMenuItems
            }
        #endif
        }
    }

    @ViewBuilder
    private var footerMenuItems: some View {
        Button(action: { SettingsWindowController.show() }) {
            Label(String(localized: "common.settings"), systemImage: "gear")
        }
        Button(action: { StatusBarController.shared.hidePopover() }) {
            Label(String(localized: "common.close"), systemImage: "xmark")
        }
        Divider()
        Button(role: .destructive, action: { NSApp.terminate(nil) }) {
            Label(String(localized: "menu.quit"), systemImage: "power")
        }
    }

    private func badgeCount(for tab: Tab) -> Int {
        switch tab {
        case .downloadSync:
            return appState.queuedItems.count
        case .folderSync:
            return appState.config.folderSyncs.filter { $0.isEnabled }.count
        case .loadFolder:
            return appState.config.loadFolderPresets.count
        case .fileSafe:
            return volumeDetector.externalVolumes.count
        #if canImport(BridgeKit)
        case .bridge:
            return 0
        #endif
        }
    }
}

/// Tab button component
struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let badgeCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))

                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .fixedSize()

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.brandBurntPeach : Color.ink4.opacity(0.3))
                        .foregroundColor(isSelected ? .white : .ink3)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.brandBurntPeach.opacity(0.12) : Color.clear)
            )
            .foregroundColor(isSelected ? .brandBurntPeach : .ink3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? String(localized: "queue.selected") : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Content view voor DownloadSync tab (hergebruikt bestaande QueueView logica)
struct DownloadSyncContent: View {
    @StateObject private var appState = AppState.shared
    @Binding var selectedItemForPicker: DownloadItem?
    @Binding var isShowingClearConfirmation: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            if appState.queuedItems.isEmpty {
                // Empty state - neemt beschikbare ruimte in zonder te groeien
                EmptyDownloadSyncView()
                    .onAppear {
                        // Reset confirmatie wanneer queue leeg is
                        if isShowingClearConfirmation {
                            isShowingClearConfirmation = false
                        }
                    }
            } else {
                QueueView(
                    selectedItemForPicker: $selectedItemForPicker,
                    isShowingClearConfirmation: $isShowingClearConfirmation
                )
            }
        }
    }
}

/// Empty state view voor DownloadSync
struct EmptyDownloadSyncView: View {
    @State private var showHistory = false
    @State private var todayCount: Int = 0
    private let isFirstRun = !UserDefaults.standard.bool(forKey: "firstImportCompleted")

    var body: some View {
        if isFirstRun {
            firstRunContent
        } else {
            returningUserContent
        }
    }

    private var firstRunContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)

            Text(String(localized: "empty.first_run.title"))
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                firstRunStep(number: "1", text: String(localized: "empty.first_run.step1"), icon: "globe")
                firstRunStep(number: "2", text: String(localized: "empty.first_run.step2"), icon: "arrow.down.circle")
                firstRunStep(number: "3", text: String(localized: "empty.first_run.step3"), icon: "folder.badge.plus")
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func firstRunStep(number: String, text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Text(number)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.accentColor)
            }
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    private var returningUserContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))

            Text(String(localized: "queue.no_downloads"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Text(String(localized: "queue.auto_shown"))
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)

            if todayCount > 0 {
                Button(action: { showHistory = true }) {
                    Label(String(localized: "history.show_today \(todayCount)"), systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popover(isPresented: $showHistory) {
                    HistoryView(
                        records: ProcessingHistoryManager.shared.todayRecords(),
                        onDismiss: { showHistory = false }
                    )
                    .frame(width: 400, height: 350)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await refreshTodayCount()
        }
    }

    private func refreshTodayCount() async {
        todayCount = ProcessingHistoryManager.shared.todayRecords().count
    }
}

// MARK: - FileSafe Launcher (toont drive-cards, opent apart venster bij klik)

struct FileSafeLauncherView: View {
    @StateObject private var volumeDetector = VolumeDetector.shared

    var body: some View {
        VStack(spacing: 0) {
            if volumeDetector.externalVolumes.isEmpty {
                emptyContent
            } else {
                driveList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            volumeDetector.startMonitoring()
        }
    }

    private var driveList: some View {
        VStack(spacing: 0) {
            QueueSectionHeader(
                title: String(localized: "filesafe.connected_drives"),
                count: volumeDetector.externalVolumes.count,
                style: .ready
            )

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(volumeDetector.externalVolumes) { volume in
                        HStack(spacing: 12) {
                            Image(systemName: "externaldrive.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.brandBurntPeach)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(volume.name)
                                        .font(.system(size: 13, weight: .medium))

                                    if volume.usedPercentage > 0.85 {
                                        HStack(spacing: 3) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 8))
                                            Text(String(localized: "filesafe.almost_full"))
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .foregroundColor(.statusWarn)
                                    }
                                }

                                // Capacity bar
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.ink4.opacity(0.2))
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(capacityColor(for: volume.usedPercentage))
                                            .frame(width: geo.size.width * CGFloat(volume.usedPercentage))
                                    }
                                }
                                .frame(height: 4)

                                Text("\(volume.formattedTotalSize) \u{2022} \(volume.formattedFreeSpace) vrij")
                                    .font(.system(size: 11))
                                    .foregroundColor(.ink3)
                            }

                            Spacer()

                            Button(String(localized: "filesafe.open_safe")) {
                                openFileSafeWindow(volume: volume)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.line).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func capacityColor(for percentage: Double) -> Color {
        if percentage > 0.90 { return .statusBad }
        if percentage > 0.75 { return .statusWarn }
        return .statusOk
    }

    private var emptyContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
            Text(String(localized: "filesafe.launcher.title"))
                .font(.system(size: 14, weight: .semibold))
            Text(String(localized: "filesafe.launcher.subtitle"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openFileSafeWindow(volume: ExternalVolume) {
        // Sluit bestaand venster en open nieuw met geselecteerde volume
        FileSafeWindowController.shared?.close()
        let controller = FileSafeWindowController(initialVolume: volume)
        controller.show()
    }
}

#Preview {
    MainTabView(
        selectedItemForPicker: .constant(nil),
        isShowingFolderSyncForm: .constant(false),
        isShowingClearConfirmation: .constant(false)
    )
    .frame(width: 500, height: 400)
}



