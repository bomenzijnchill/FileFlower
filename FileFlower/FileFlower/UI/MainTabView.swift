import SwiftUI

/// Hoofdview met tabs voor DownloadSync en FolderSync
struct MainTabView: View {
    @StateObject private var appState = AppState.shared
    @Binding var showingSettings: Bool
    @Binding var selectedItemForPicker: DownloadItem?
    @Binding var isShowingFolderSyncForm: Bool
    @Binding var isShowingClearConfirmation: Bool
    
    enum Tab: String, CaseIterable {
        case downloadSync = "DownloadSync"
        case folderSync = "FolderSync"
        case loadFolder = "LoadFolder"

        var icon: String {
            switch self {
            case .downloadSync: return "arrow.down.circle"
            case .folderSync: return "folder.badge.gearshape"
            case .loadFolder: return "folder.badge.plus"
            }
        }
    }
    
    @State private var selectedTab: Tab = .downloadSync
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
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
                }
            }
            .transition(.opacity)
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
            .padding(.horizontal, 12)
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

    var body: some View {
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

#Preview {
    MainTabView(
        showingSettings: .constant(false),
        selectedItemForPicker: .constant(nil),
        isShowingFolderSyncForm: .constant(false),
        isShowingClearConfirmation: .constant(false)
    )
    .frame(width: 500, height: 400)
}



