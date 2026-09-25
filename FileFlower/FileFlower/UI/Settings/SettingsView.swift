import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable {
    case general
    case library
    case template
    case classification
    case integrations
    case account
    case advanced
    #if canImport(BridgeKit)
    case bridge
    #endif

    var icon: String {
        switch self {
        case .general: return "gear"
        case .library: return "folder.badge.gearshape"
        case .template: return "tray.full"
        case .classification: return "waveform"
        case .integrations: return "puzzlepiece.extension"
        case .account: return "person.crop.circle"
        case .advanced: return "slider.horizontal.3"
        #if canImport(BridgeKit)
        case .bridge: return "arrow.left.arrow.right.circle"
        #endif
        }
    }

    var localizedName: String {
        switch self {
        case .general: return String(localized: "settings.tab.general")
        case .library: return String(localized: "settings.tab.library")
        case .template: return String(localized: "settings.tab.template")
        case .classification: return String(localized: "settings.tab.classification")
        case .integrations: return String(localized: "settings.tab.integrations")
        case .account: return String(localized: "settings.tab.account")
        case .advanced: return String(localized: "settings.tab.advanced")
        #if canImport(BridgeKit)
        case .bridge: return String(localized: "settings.tab.bridge", defaultValue: "Bridge")
        #endif
        }
    }

    var pageEyebrow: String { localizedName }

    var pageTitle: String { localizedName }

    var pageLede: String {
        switch self {
        case .general:        return String(localized: "settings.lede.general")
        case .library:        return String(localized: "settings.lede.library")
        case .template:       return String(localized: "settings.lede.template")
        case .classification: return String(localized: "settings.lede.classification")
        case .integrations:   return String(localized: "settings.lede.integrations")
        case .account:        return String(localized: "settings.lede.account")
        case .advanced:       return String(localized: "settings.lede.advanced")
        #if canImport(BridgeKit)
        case .bridge:         return String(localized: "settings.lede.bridge", defaultValue: "Deel mappen met je andere machines en beheer wat er lokaal bewaard blijft.")
        #endif
        }
    }
}

enum ClaudeConnectionStatus {
    case unknown
    case testing
    case connected
    case failed(String)
}

struct SettingsView: View {
    @StateObject private var appState = AppState.shared
    @State private var projectRoots: [String] = []
    @State private var newRoot: String = ""
    @State private var musicMode: MusicMode = .mood
    @State private var customStockWebsites: [String] = []
    @State private var blacklistedWebsites: [String] = []
    @State private var newStockWebsite: String = ""
    @State private var newBlacklistedWebsite: String = ""
    @State private var downloadsFolder: String = ""
    @State private var showPopupAfterDownload: Bool = true
    @State private var bringPremiereToFront: Bool = true
    @State private var bringResolveToFront: Bool = true
    @State private var resolveAutoImport: Bool = true
    @State private var showPetalAnimation: Bool = true
    @State private var autoOpenBridgePanel: Bool = true
    @State private var startAtLogin: Bool = false
    @State private var useClaudeClassification: Bool = false
    @State private var claudeAPIKey: String = ""
    @State private var claudeConnectionStatus: ClaudeConnectionStatus = .unknown
    @State private var useWebScraping: Bool = true
    @State private var useGenreMoodDetection: Bool = true
    @State private var useSfxSubfolders: Bool = true
    @State private var appLanguage: String = "en"
    @State private var analyticsEnabled: Bool = false
    @State private var filterServerProjectsToLocal: Bool = true
    @State private var autoAddActiveProjectRoot: Bool = true
    @State private var folderStructurePreset: FolderStructurePreset = .standard
    @State private var selectedTab: SettingsTab = .general
    @State private var showLanguageChangeAlert = false
    @State private var pendingLanguage: String? = nil
    @State private var lastSaveTime: Date? = nil
    @State private var searchQuery: String = ""
    @FocusState private var searchFocused: Bool

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var licenseTier: String {
        if LicenseManager.shared.isLicensed { return "pro" }
        if LicenseManager.shared.isInTrial { return "trial" }
        return "free"
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 232)
                .background(Color.paper1)

            Divider().background(Color.line)

            VStack(spacing: 0) {
                contentArea
                SaveStatusBar(
                    lastSaveTime: lastSaveTime,
                    onClose: { SettingsWindowController.close() },
                    onExportConfig: nil
                )
            }
            .frame(maxWidth: .infinity)
            .background(Color.paper0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper0)
        .onAppear {
            loadSettings()
        }
        .background(
            // Hidden button to register ⌘F as a global shortcut within the window
            Button(action: { searchFocused = true }) { EmptyView() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        )
        .modifier(SettingsChangeHandlersA(
            projectRoots: $projectRoots,
            musicMode: $musicMode,
            customStockWebsites: $customStockWebsites,
            blacklistedWebsites: $blacklistedWebsites,
            showPopupAfterDownload: $showPopupAfterDownload,
            bringPremiereToFront: $bringPremiereToFront,
            bringResolveToFront: $bringResolveToFront,
            resolveAutoImport: $resolveAutoImport,
            showPetalAnimation: $showPetalAnimation,
            autoOpenBridgePanel: $autoOpenBridgePanel,
            startAtLogin: $startAtLogin,
            saveConfig: saveConfig,
            handleStartAtLoginChange: handleStartAtLoginChange
        ))
        .modifier(SettingsChangeHandlersB(
            useClaudeClassification: $useClaudeClassification,
            useWebScraping: $useWebScraping,
            useGenreMoodDetection: $useGenreMoodDetection,
            useSfxSubfolders: $useSfxSubfolders,
            filterServerProjectsToLocal: $filterServerProjectsToLocal,
            autoAddActiveProjectRoot: $autoAddActiveProjectRoot,
            analyticsEnabled: $analyticsEnabled,
            appLanguage: $appLanguage,
            showLanguageChangeAlert: $showLanguageChangeAlert,
            pendingLanguage: $pendingLanguage,
            saveConfig: saveConfig,
            relaunchApp: relaunchApp,
            appState: appState
        ))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            SidebarBrandBlock(appVersion: appVersion, licenseTier: licenseTier)

            // Search field
            SettingsSearchField(searchQuery: $searchQuery, isFocused: $searchFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            // Section label
            Text(String(localized: "settings.sidebar.label").uppercased())
                .font(.brandMono(size: 10, weight: .semibold))
                .tracking(1.0)
                .foregroundColor(.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 6)

            // Nav list
            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    NavItem(
                        tab: tab,
                        isActive: selectedTab == tab,
                        badge: badgeCount(for: tab),
                        action: {
                            selectedTab = tab
                            searchQuery = ""
                        }
                    )
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            SidebarStatusRibbon()
        }
    }

    private func badgeCount(for tab: SettingsTab) -> Int? {
        // Plugin / extension updates → integrations badge
        if tab == .integrations {
            let info = UpdateManager.shared.pluginUpdateInfo
            var count = 0
            if info.premierePluginUpdateAvailable { count += 1 }
            if info.chromeExtensionUpdateAvailable { count += 1 }
            return count > 0 ? count : nil
        }
        return nil
    }

    // MARK: - Content area

    @ViewBuilder
    private var contentArea: some View {
        let results = SettingsSearchIndex.match(searchQuery)

        ZStack(alignment: .top) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    PageHead(
                        eyebrow: selectedTab.pageEyebrow,
                        title: selectedTab.pageTitle,
                        lede: selectedTab.pageLede
                    )

                    selectedTabContent
                }
                .padding(.horizontal, 40)
                .padding(.top, 36)
                .padding(.bottom, 40)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Search overlay (positioned at top, slightly inset)
            if !results.isEmpty {
                SearchOverlay(results: results) { result in
                    selectedTab = result.tab
                    searchQuery = ""
                    searchFocused = false
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .frame(maxWidth: 800)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .general:
            GeneralTabView(
                appLanguage: $appLanguage,
                showPopupAfterDownload: $showPopupAfterDownload,
                showPetalAnimation: $showPetalAnimation,
                autoOpenBridgePanel: $autoOpenBridgePanel,
                startAtLogin: $startAtLogin,
                filterServerProjectsToLocal: $filterServerProjectsToLocal,
                autoAddActiveProjectRoot: $autoAddActiveProjectRoot,
                analyticsEnabled: $analyticsEnabled,
                onSave: saveConfig
            )

        case .library:
            LibraryTabView(
                projectRoots: $projectRoots,
                newRoot: $newRoot,
                downloadsFolder: $downloadsFolder,
                onSave: saveConfig
            )

        case .template:
            TemplateTabView(
                appState: appState,
                folderStructurePreset: $folderStructurePreset,
                onSave: saveConfig
            )

        case .classification:
            ClassificationTabView(
                musicMode: $musicMode,
                useSfxSubfolders: $useSfxSubfolders,
                useClaudeClassification: $useClaudeClassification,
                claudeAPIKey: $claudeAPIKey,
                claudeConnectionStatus: $claudeConnectionStatus,
                useGenreMoodDetection: $useGenreMoodDetection,
                useWebScraping: $useWebScraping
            )

        case .integrations:
            IntegrationsTabView(
                bringPremiereToFront: $bringPremiereToFront,
                bringResolveToFront: $bringResolveToFront,
                resolveAutoImport: $resolveAutoImport,
                customStockWebsites: $customStockWebsites,
                newStockWebsite: $newStockWebsite,
                blacklistedWebsites: $blacklistedWebsites,
                newBlacklistedWebsite: $newBlacklistedWebsite,
                onSave: saveConfig
            )

        case .account:
            AccountTabView()

        case .advanced:
            AdvancedTabView()

        #if canImport(BridgeKit)
        case .bridge:
            BridgeTabView()
        #endif
        }
    }

    // MARK: - Methods

    private func handleStartAtLoginChange(_ enabled: Bool) {
        do {
            if enabled {
                try LaunchAgentManager.shared.enableStartAtLogin()
            } else {
                try LaunchAgentManager.shared.disableStartAtLogin()
            }
            saveConfig()
        } catch {
            #if DEBUG
            print("Fout bij wijzigen startAtLogin: \(error)")
            #endif
            DispatchQueue.main.async {
                startAtLogin = !enabled
            }
        }
    }

    private func loadSettings() {
        projectRoots = appState.config.projectRoots
        musicMode = appState.config.musicClassification
        customStockWebsites = appState.config.customStockWebsites
        blacklistedWebsites = appState.config.blacklistedWebsites
        downloadsFolder = appState.config.customDownloadsFolder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
        showPopupAfterDownload = appState.config.showPopupAfterDownload
        bringPremiereToFront = appState.config.bringPremiereToFront
        bringResolveToFront = appState.config.bringResolveToFront
        resolveAutoImport = appState.config.resolveAutoImport
        showPetalAnimation = appState.config.showPetalAnimation
        autoOpenBridgePanel = appState.config.autoOpenBridgePanel
        startAtLogin = appState.config.startAtLogin
        useClaudeClassification = appState.config.useClaudeClassification
        claudeAPIKey = ClaudeClassificationStrategy.loadAPIKey() ?? ""
        useWebScraping = appState.config.useWebScraping
        useGenreMoodDetection = appState.config.useGenreMoodDetection
        useSfxSubfolders = appState.config.useSfxSubfolders
        appLanguage = appState.config.appLanguage
        analyticsEnabled = appState.config.analyticsEnabled
        filterServerProjectsToLocal = appState.config.filterServerProjectsToLocal
        autoAddActiveProjectRoot = appState.config.autoAddActiveProjectRoot
        folderStructurePreset = appState.config.folderStructurePreset
    }

    private func relaunchApp() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        NSApplication.shared.terminate(nil)
    }

    private func saveConfig() {
        appState.config.projectRoots = projectRoots
        appState.config.musicClassification = musicMode

        var allStockWebsites = Config.defaultStockWebsites
        for custom in customStockWebsites {
            if !allStockWebsites.contains(custom) {
                allStockWebsites.append(custom)
            }
        }
        appState.config.stockWebsites = allStockWebsites

        appState.config.blacklistedWebsites = blacklistedWebsites

        if downloadsFolder == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path {
            appState.config.customDownloadsFolder = nil
        } else {
            appState.config.customDownloadsFolder = downloadsFolder
        }

        appState.config.showPopupAfterDownload = showPopupAfterDownload
        appState.config.bringPremiereToFront = bringPremiereToFront
        appState.config.bringResolveToFront = bringResolveToFront
        appState.config.resolveAutoImport = resolveAutoImport
        appState.config.showPetalAnimation = showPetalAnimation
        appState.config.autoOpenBridgePanel = autoOpenBridgePanel
        appState.config.startAtLogin = startAtLogin
        appState.config.useClaudeClassification = useClaudeClassification
        ClaudeClassificationStrategy.saveAPIKey(claudeAPIKey)
        appState.config.useWebScraping = useWebScraping
        appState.config.useGenreMoodDetection = useGenreMoodDetection
        appState.config.useSfxSubfolders = useSfxSubfolders
        appState.config.appLanguage = appLanguage
        appState.config.analyticsEnabled = analyticsEnabled
        appState.config.filterServerProjectsToLocal = filterServerProjectsToLocal
        appState.config.autoAddActiveProjectRoot = autoAddActiveProjectRoot
        appState.config.folderStructurePreset = folderStructurePreset

        appState.saveConfig()
        lastSaveTime = Date()
    }
}

// MARK: - Sidebar nav item

private struct NavItem: View {
    let tab: SettingsTab
    let isActive: Bool
    let badge: Int?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                NavTile(icon: tab.icon, topColor: tab.tileTopColor, bottomColor: tab.tileBottomColor)

                Text(tab.localizedName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isActive ? .white : .ink)

                Spacer()

                if let badge = badge {
                    Text("\(badge)")
                        .font(.brandMono(size: 10, weight: .semibold))
                        .foregroundColor(isActive ? .white : .peach3)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(isActive ? Color.white.opacity(0.25) : Color.brandBurntPeach.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isActive
                    ? Color.brandBurntPeach
                    : (isHovered ? Color.black.opacity(0.04) : .clear)
            )
            .cornerRadius(7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

// MARK: - Settings Change Handlers (split into two modifiers for Swift type checker)

private struct SettingsChangeHandlersA: ViewModifier {
    @Binding var projectRoots: [String]
    @Binding var musicMode: MusicMode
    @Binding var customStockWebsites: [String]
    @Binding var blacklistedWebsites: [String]
    @Binding var showPopupAfterDownload: Bool
    @Binding var bringPremiereToFront: Bool
    @Binding var bringResolveToFront: Bool
    @Binding var resolveAutoImport: Bool
    @Binding var showPetalAnimation: Bool
    @Binding var autoOpenBridgePanel: Bool
    @Binding var startAtLogin: Bool
    var saveConfig: () -> Void
    var handleStartAtLoginChange: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: projectRoots) { _, _ in saveConfig() }
            .onChange(of: musicMode) { _, _ in saveConfig() }
            .onChange(of: customStockWebsites) { _, _ in saveConfig() }
            .onChange(of: blacklistedWebsites) { _, _ in saveConfig() }
            .onChange(of: showPopupAfterDownload) { _, newValue in
                saveConfig()
                AnalyticsService.shared.track(.featureToggled(featureName: "show_popup", enabled: newValue))
            }
            .onChange(of: bringPremiereToFront) { _, _ in saveConfig() }
            .onChange(of: bringResolveToFront) { _, _ in saveConfig() }
            .onChange(of: resolveAutoImport) { _, newValue in
                saveConfig()
                AnalyticsService.shared.track(.featureToggled(featureName: "resolve_auto_import", enabled: newValue))
            }
            .onChange(of: showPetalAnimation) { _, _ in saveConfig() }
            .onChange(of: autoOpenBridgePanel) { _, _ in saveConfig() }
            .onChange(of: startAtLogin) { _, newValue in
                handleStartAtLoginChange(newValue)
                AnalyticsService.shared.track(.featureToggled(featureName: "start_at_login", enabled: newValue))
            }
    }
}

private struct SettingsChangeHandlersB: ViewModifier {
    @Binding var useClaudeClassification: Bool
    @Binding var useWebScraping: Bool
    @Binding var useGenreMoodDetection: Bool
    @Binding var useSfxSubfolders: Bool
    @Binding var filterServerProjectsToLocal: Bool
    @Binding var autoAddActiveProjectRoot: Bool
    @Binding var analyticsEnabled: Bool
    @Binding var appLanguage: String
    @Binding var showLanguageChangeAlert: Bool
    @Binding var pendingLanguage: String?
    var saveConfig: () -> Void
    var relaunchApp: () -> Void
    var appState: AppState

    func body(content: Content) -> some View {
        content
            .onChange(of: useClaudeClassification) { _, newValue in
                saveConfig()
                AnalyticsService.shared.track(.featureToggled(featureName: "claude_classification", enabled: newValue))
            }
            .onChange(of: useWebScraping) { _, newValue in
                saveConfig()
                AnalyticsService.shared.track(.featureToggled(featureName: "web_scraping", enabled: newValue))
            }
            .onChange(of: useGenreMoodDetection) { _, newValue in
                saveConfig()
                AnalyticsService.shared.track(.featureToggled(featureName: "genre_mood_detection", enabled: newValue))
            }
            .onChange(of: useSfxSubfolders) { _, newValue in
                saveConfig()
                AnalyticsService.shared.track(.featureToggled(featureName: "sfx_subfolders", enabled: newValue))
            }
            .onChange(of: filterServerProjectsToLocal) { _, _ in saveConfig() }
            .onChange(of: autoAddActiveProjectRoot) { _, _ in saveConfig() }
            .onChange(of: appLanguage) { oldValue, newValue in
                guard oldValue != newValue else { return }
                pendingLanguage = newValue
                appLanguage = oldValue
                showLanguageChangeAlert = true
            }
            .alert(
                String(localized: "settings.language.change_title"),
                isPresented: $showLanguageChangeAlert
            ) {
                Button(String(localized: "settings.language.change_confirm")) {
                    if let newLang = pendingLanguage {
                        appLanguage = newLang
                        appState.config.appLanguage = newLang
                        appState.saveConfig()
                        UserDefaults.standard.set([newLang], forKey: "AppleLanguages")
                        UserDefaults.standard.synchronize()
                        relaunchApp()
                    }
                }
                Button(String(localized: "common.cancel"), role: .cancel) {
                    pendingLanguage = nil
                }
            } message: {
                Text(String(localized: "settings.language.change_message"))
            }
            .onChange(of: analyticsEnabled) { _, newValue in
                saveConfig()
                if newValue {
                    AnalyticsService.shared.optIn()
                } else {
                    AnalyticsService.shared.optOut()
                }
            }
    }
}
