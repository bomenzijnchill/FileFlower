import SwiftUI

/// Hoofdview met tabs voor DownloadSync en FolderSync
struct MainTabView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var volumeDetector = VolumeDetector.shared
    @Binding var showingSettings: Bool
    @Binding var selectedItemForPicker: DownloadItem?
    @Binding var isShowingFolderSyncForm: Bool
    @Binding var isShowingClearConfirmation: Bool

    enum Tab: String, CaseIterable {
        case downloadSync = "DownloadSync"
        case folderSync = "FolderSync"
        case loadFolder = "LoadFolder"
        case fileSafe = "FileSafe"

        var icon: String {
            switch self {
            case .downloadSync: return "arrow.down.circle"
            case .folderSync: return "arrow.triangle.2.circlepath"
            case .loadFolder: return "folder.badge.plus"
            case .fileSafe: return "externaldrive.badge.checkmark"
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
        return tabs
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(visibleTabs, id: \.self) { tab in
                    TabButton(
                        title: tab.rawValue,
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
                }
            }
            .transition(.opacity)
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
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                
                // Gebruik overlay om stabiele breedte te behouden ongeacht font weight
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(isSelected ? 1 : 0)
                    .overlay(alignment: .center) {
                        Text(title)
                            .font(.system(size: 12, weight: .regular))
                            .opacity(isSelected ? 0 : 1)
                    }
                
                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                        .foregroundColor(isSelected ? .white : .secondary)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .foregroundColor(isSelected ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
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

            let todayCount = ProcessingHistoryManager.shared.todayRecords().count
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
        ScrollView {
            VStack(spacing: 0) {
                ForEach(volumeDetector.externalVolumes) { volume in
                    Button(action: { openFileSafeWindow(volume: volume) }) {
                        HStack(spacing: 12) {
                            Image(systemName: "externaldrive.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.accentColor)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(volume.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text("\(volume.formattedTotalSize) \u{2022} \(volume.formattedFreeSpace) free")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.controlBackgroundColor))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
            }
            .padding(.bottom, 8)
        }
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
        showingSettings: .constant(false),
        selectedItemForPicker: .constant(nil),
        isShowingFolderSyncForm: .constant(false),
        isShowingClearConfirmation: .constant(false)
    )
    .frame(width: 500, height: 400)
}



