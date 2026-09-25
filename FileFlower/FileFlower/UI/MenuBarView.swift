import SwiftUI
import AppKit

struct MenuBarView: View {
    @StateObject private var appState = AppState.shared
    @State private var selectedItemForPicker: DownloadItem?
    @State private var isShowingFolderSyncForm = false
    @State private var isShowingClearConfirmation = false
    /// Project waarvoor de mapindeling-editor open staat (via de headerknop).
    @State private var mappingEditorProject: ProjectInfo?
    @AppStorage("userPopoverHeight") private var userPopoverHeight: Double = 0
    @State private var isDragging = false
    @State private var dragStartHeight: CGFloat = 0

    // Standaard popover-breedte
    private var calculatedWidth: CGFloat {
        return 520
    }

    // Bereken dynamische hoogte op basis van content
    private var calculatedHeight: CGFloat {
        let headerHeight: CGFloat = 56
        let tabBarHeight: CGFloat = 56
        let footerHeight: CGFloat = 56
        let sectionHeaderHeight: CGFloat = 28
        let attentionRowHeight: CGFloat = 90
        let readyRowHeight: CGFloat = 70
        let formHeight: CGFloat = 380
        let confirmationHeight: CGFloat = 100
        let minContentHeight: CGFloat = 200

        if selectedItemForPicker != nil {
            return 600
        } else if isShowingFolderSyncForm {
            return headerHeight + tabBarHeight + formHeight + footerHeight
        } else {
            let grouped = appState.groupedQueueItems
            let attentionCount = min(grouped.attention.count, 3)
            let readyCount = min(grouped.ready.count, 4)
            let folderSyncCount = min(appState.config.folderSyncs.count, 5)
            let resizeHandleHeight: CGFloat = 20
            let extraConfirmationHeight = isShowingClearConfirmation ? confirmationHeight : 0

            let contentBasedHeight: CGFloat
            if appState.queuedItems.isEmpty && appState.config.folderSyncs.isEmpty {
                contentBasedHeight = headerHeight + tabBarHeight + minContentHeight + footerHeight
            } else {
                let attentionSectionHeight = attentionCount > 0 ? sectionHeaderHeight + CGFloat(attentionCount) * attentionRowHeight : 0
                let readySectionHeight = readyCount > 0 ? sectionHeaderHeight + CGFloat(readyCount) * readyRowHeight : 0
                let folderSyncHeight = CGFloat(folderSyncCount) * 72
                let listHeight = max(attentionSectionHeight + readySectionHeight, folderSyncHeight, minContentHeight)
                contentBasedHeight = headerHeight + tabBarHeight + listHeight + footerHeight + extraConfirmationHeight + 10
            }

            if userPopoverHeight > 0 {
                return max(CGFloat(userPopoverHeight), contentBasedHeight) + resizeHandleHeight
            } else {
                return contentBasedHeight + resizeHandleHeight
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header — dark cocoa gradient
            HStack(spacing: 10) {
                // Brand block
                HStack(spacing: 8) {
                    Image("FileFlowerLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    Text("FileFlower")
                        .font(.brandSerifItalic(size: 18))
                        .foregroundColor(.headerInk)
                }

                // Project selector
                ProjectSelectorView(appState: appState)

                // Mapindeling van het actieve project aanpassen
                if let project = appState.activeProject {
                    Button(action: { mappingEditorProject = project }) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 13))
                            .foregroundColor(.headerInk)
                            .frame(width: 28, height: 28)
                            .background(Color.headerGlass)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "mapping.edit_button"))
                }

                if appState.isPaused {
                    Text(String(localized: "menu.paused"))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.15))
                        .foregroundColor(.headerInk)
                        .clipShape(Capsule())
                        .fixedSize()
                }

                // Pause/play button
                Button(action: { appState.togglePause() }) {
                    Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.headerInk)
                        .frame(width: 28, height: 28)
                        .background(Color.headerGlass)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(appState.isPaused ? String(localized: "menu.resume") : String(localized: "menu.pause"))
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [.headerTop, .headerBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

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
                } else if let item = selectedItemForPicker {
                    Divider()
                    ProjectPickerView(item: item, onDismiss: {
                        selectedItemForPicker = nil
                    })
                    .transition(.move(edge: .trailing))
                } else {
                    // Main tab view met DownloadSync en FolderSync tabs
                    MainTabView(
                        selectedItemForPicker: $selectedItemForPicker,
                        isShowingFolderSyncForm: $isShowingFolderSyncForm,
                        isShowingClearConfirmation: $isShowingClearConfirmation
                    )
                    .transition(.move(edge: .leading))
                }
            }
            .layoutPriority(0)
            
            // Footer is now per-tab inside MainTabView

            // Resize handle — alleen in normale modus
            if selectedItemForPicker == nil && LicenseManager.shared.canUseApp {
                ResizeHandleView(
                    onDrag: { translation in
                        let newHeight = dragStartHeight + translation
                        userPopoverHeight = Double(min(max(newHeight, 300), 900))
                    },
                    onDragStart: {
                        isDragging = true
                        dragStartHeight = CGFloat(userPopoverHeight > 0 ? userPopoverHeight : Double(calculatedHeight))
                        StatusBarController.shared.setPopoverBehavior(.applicationDefined)
                    },
                    onDragEnd: {
                        isDragging = false
                        StatusBarController.shared.setPopoverBehavior(.transient)
                    }
                )
            }
        }
        .frame(width: calculatedWidth, height: calculatedHeight)
        .sheet(item: $mappingEditorProject) { project in
            ProjectMappingConfirmationSheet(
                project: project,
                onConfirm: {
                    // Herbereken de queue zodat previews de nieuwe mapping volgen.
                    appState.reresolveQueuedItems(for: project)
                    mappingEditorProject = nil
                },
                onCancel: { mappingEditorProject = nil }
            )
        }
        // Taal wordt bepaald door UserDefaults "AppleLanguages" (herstart nodig)
        .onChange(of: appState.shouldOpenWindow) { _, shouldOpen in
            if shouldOpen {
                // Open de popover bij nieuwe downloads
                StatusBarController.shared.showPopover()
                appState.shouldOpenWindow = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidClose)) { _ in
            // Reset navigatie zodat de popover bij heropenen op het hoofdscherm start
            selectedItemForPicker = nil
        }
        .onReceive(VolumeDetector.shared.newVolumeDidMount) { volume in
            // Auto-popup bij aansluiten van een kaart/externe schijf. Netwerk/server-shares
            // poppen bewust NIET automatisch op (geen nag bij elke server-mount).
            guard volume.kind != .networkVolume else { return }
            if !StatusBarController.shared.isShown {
                StatusBarController.shared.showPopover()
            }
            appState.shouldSwitchToFileSafeTab = true
        }
    }
}

// MARK: - Resize Handle

/// Sleepbare handle onderaan het popover venster voor verticaal resizen.
struct ResizeHandleView: View {
    let onDrag: (CGFloat) -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void

    @State private var isHovered = false
    @State private var dragStarted = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(isHovered ? 0.8 : 0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 16)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovered = hovering
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if !dragStarted {
                                dragStarted = true
                                onDragStart()
                            }
                            onDrag(value.translation.height)
                        }
                        .onEnded { _ in
                            dragStarted = false
                            onDragEnd()
                        }
                )
        }
    }
}
