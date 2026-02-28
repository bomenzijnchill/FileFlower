import SwiftUI
import AppKit

struct MenuBarView: View {
    @StateObject private var appState = AppState.shared
    @State private var showingSettings = false
    @State private var selectedItemForPicker: DownloadItem?
    @State private var isShowingFolderSyncForm = false
    @State private var isShowingClearConfirmation = false
    
    // Bereken dynamische breedte op basis van content
    private var calculatedWidth: CGFloat {
        if showingSettings {
            return 700 // Breedte voor settings
        } else {
            return 520 // Standaard breedte (iets breder voor tabs)
        }
    }
    
    // Bereken dynamische hoogte op basis van content
    private var calculatedHeight: CGFloat {
        let headerHeight: CGFloat = 56
        let footerHeight: CGFloat = 56
        let tabBarHeight: CGFloat = 56 // Tab bar hoogte
        let toolbarHeight: CGFloat = 52 // 36 + padding
        let itemHeight: CGFloat = 80
        let formHeight: CGFloat = 380 // Hoogte voor add/edit formulier
        let confirmationHeight: CGFloat = 100 // Hoogte voor clear queue confirmatie
        let minContentHeight: CGFloat = 200 // Minimale hoogte voor content area (300px totaal minimum)
        
        if showingSettings {
            return 700 // Hoogte voor settings
        } else if selectedItemForPicker != nil {
            return 600 // Vaste hoogte voor picker
        } else if isShowingFolderSyncForm {
            // Extra hoogte voor het folder sync formulier
            return headerHeight + tabBarHeight + formHeight + footerHeight
        } else {
            // Bereken op basis van queue items of folder syncs
            let queueItemCount = min(appState.queuedItems.count, 5)
            let folderSyncCount = min(appState.config.folderSyncs.count, 5)
            let maxItems = max(queueItemCount, folderSyncCount, 0)
            
            // Extra hoogte als clear confirmatie wordt getoond
            let extraConfirmationHeight = isShowingClearConfirmation ? confirmationHeight : 0
            
            if maxItems == 0 || (appState.queuedItems.isEmpty && appState.config.folderSyncs.isEmpty) {
                // Empty state - minimaal 300px totale hoogte
                return headerHeight + tabBarHeight + minContentHeight + footerHeight
            } else {
                // Met items - bereken op basis van aantal, maar minimaal minContentHeight
                let listHeight = max(toolbarHeight + (CGFloat(maxItems) * itemHeight), minContentHeight)
                return headerHeight + tabBarHeight + listHeight + footerHeight + extraConfirmationHeight + 10
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header - vast, altijd zichtbaar
            HStack(spacing: 8) {
                Image("FileFlowerTitle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 22)
                    .fixedSize()
                
                // Pauze indicator
                if appState.isPaused {
                    Text(String(localized: "menu.paused"))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.3))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .fixedSize()
                }
                
                Spacer()
                
                // Pauze knop
                Button(action: {
                    appState.togglePause()
                }) {
                    Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .help(appState.isPaused ? String(localized: "menu.resume") : String(localized: "menu.pause"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(height: 56)
            .background(Color.brandBurntPeach)

            // Content area met tabs of settings/picker
            Group {
                if !LicenseManager.shared.canUseApp {
                    // Locked state — trial verlopen
                    Divider()
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "lock.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(String(localized: "license.trial_expired"))
                            .font(.system(size: 14, weight: .medium))
                        Text(String(localized: "license.activate_subtitle"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button(String(localized: "license.activate")) {
                            LicenseWindowController.show(onActivated: { }, onSkip: nil)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Spacer()
                    }
                    .padding(.horizontal, 32)
                } else if showingSettings {
                    Divider()
                    SettingsView(onDismiss: {
                        withAnimation {
                            showingSettings = false
                        }
                    })
                    .transition(.move(edge: .trailing))
                } else if let item = selectedItemForPicker {
                    Divider()
                    ProjectPickerView(item: item, onDismiss: {
                        selectedItemForPicker = nil
                    })
                    .transition(.move(edge: .trailing))
                } else {
                    // Main tab view met DownloadSync en FolderSync tabs
                    MainTabView(
                        showingSettings: $showingSettings,
                        selectedItemForPicker: $selectedItemForPicker,
                        isShowingFolderSyncForm: $isShowingFolderSyncForm,
                        isShowingClearConfirmation: $isShowingClearConfirmation
                    )
                    .transition(.move(edge: .leading))
                }
            }
            .layoutPriority(0)
            
            Divider()
            
            // Actions - vast, altijd zichtbaar
            HStack {
                Button(action: {
                    withAnimation {
                        if showingSettings {
                            showingSettings = false
                        } else {
                            selectedItemForPicker = nil
                            showingSettings = true
                        }
                    }
                }) {
                    Text(String(localized: "common.settings"))
                }
                .buttonStyle(.plain)
                .fixedSize()

                Spacer()

                Button(String(localized: "common.close")) {
                    StatusBarController.shared.hidePopover()
                }
                .buttonStyle(.plain)
                .fixedSize()

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 8)

                Button(String(localized: "menu.quit")) {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(height: 56)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
        .frame(width: calculatedWidth, height: calculatedHeight)
        // Taal wordt bepaald door UserDefaults "AppleLanguages" (herstart nodig)
        .onChange(of: appState.shouldOpenWindow) { _, shouldOpen in
            if shouldOpen {
                // Open de popover bij nieuwe downloads
                StatusBarController.shared.showPopover()
                appState.shouldOpenWindow = false
            }
        }
    }
}

