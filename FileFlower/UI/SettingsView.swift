import SwiftUI
import AppKit

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
    
    let onDismiss: () -> Void
    
    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case classification = "Classification"
        case websites = "Websites"
        case updates = "Updates"
        case feedback = "Feedback"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .classification: return "waveform"
            case .websites: return "globe"
            case .updates: return "arrow.triangle.2.circlepath"
            case .feedback: return "bubble.left.and.text.bubble.right"
            }
        }

        var localizedName: String {
            switch self {
            case .general: return String(localized: "settings.tab.general")
            case .classification: return String(localized: "settings.tab.classification")
            case .websites: return String(localized: "settings.tab.websites")
            case .updates: return String(localized: "settings.tab.updates")
            case .feedback: return String(localized: "settings.tab.feedback")
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header met terug knop
            settingsHeader

            Divider()

            // Tab picker
            tabPicker

            Divider()

            // Content gebaseerd op geselecteerde tab
            tabContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadSettings()
        }
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
    
    // MARK: - Header
    
    private var settingsHeader: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text(String(localized: "common.back"))
                        .font(.system(size: 13))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            Spacer()

            Text(String(localized: "common.settings"))
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            // Invisible spacer voor balans
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                Text(String(localized: "common.back"))
                    .font(.system(size: 13))
            }
            .opacity(0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Tab Picker
    
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11))
                        Text(tab.localizedName)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Tab Content
    
    @ViewBuilder
    private var tabContent: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 12) {
                switch selectedTab {
                case .general:
                    generalTabContent
                case .classification:
                    classificationTabContent
                case .websites:
                    websitesTabContent
                case .updates:
                    updatesTabContent
                case .feedback:
                    feedbackTabContent
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var generalTabContent: some View {
        VStack(spacing: 12) {
            // Taalkeuze
            LanguageSection(appLanguage: $appLanguage, onSave: saveConfig)

            ProjectRootsSection(
                projectRoots: $projectRoots,
                newRoot: $newRoot,
                onSave: saveConfig
            )

            DownloadsFolderSection(
                downloadsFolder: $downloadsFolder,
                onSave: saveConfig
            )

            WindowBehaviorSection(
                showPopupAfterDownload: $showPopupAfterDownload,
                bringPremiereToFront: $bringPremiereToFront,
                bringResolveToFront: $bringResolveToFront,
                resolveAutoImport: $resolveAutoImport,
                showPetalAnimation: $showPetalAnimation,
                autoOpenBridgePanel: $autoOpenBridgePanel,
                startAtLogin: $startAtLogin
            )

            ProjectBehaviorSection(
                filterServerProjectsToLocal: $filterServerProjectsToLocal,
                autoAddActiveProjectRoot: $autoAddActiveProjectRoot
            )

            FolderStructureSection(
                folderStructurePreset: $folderStructurePreset,
                onSave: saveConfig
            )

            // Analytics
            AnalyticsSection(analyticsEnabled: $analyticsEnabled)
        }
    }
    
    private var classificationTabContent: some View {
        VStack(spacing: 12) {
            MusicClassificationSection(musicMode: $musicMode)

            SfxSubfoldersSection(useSfxSubfolders: $useSfxSubfolders)

            ClaudeClassificationSection(
                useClaudeClassification: $useClaudeClassification,
                claudeAPIKey: $claudeAPIKey,
                connectionStatus: $claudeConnectionStatus
            )

            GenreMoodDetectionSection(
                useGenreMoodDetection: $useGenreMoodDetection,
                useWebScraping: $useWebScraping
            )
        }
    }
    
    private var websitesTabContent: some View {
        VStack(spacing: 12) {
            StockWebsitesSection(
                customStockWebsites: $customStockWebsites,
                newStockWebsite: $newStockWebsite,
                onSave: saveConfig
            )
            
            BlacklistWebsitesSection(
                blacklistedWebsites: $blacklistedWebsites,
                newBlacklistedWebsite: $newBlacklistedWebsite,
                onSave: saveConfig
            )
        }
    }
    
    private var updatesTabContent: some View {
        VStack(spacing: 12) {
            LicenseSection()
            AppUpdateSection()
            PluginUpdateSection()
            SetupSection()
        }
    }

    private var feedbackTabContent: some View {
        VStack(spacing: 12) {
            FeedbackTabView()
        }
    }
    
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
        
        // Combineer standaard websites met custom websites
        var allStockWebsites = Config.defaultStockWebsites
        for custom in customStockWebsites {
            if !allStockWebsites.contains(custom) {
                allStockWebsites.append(custom)
            }
        }
        appState.config.stockWebsites = allStockWebsites
        
        appState.config.blacklistedWebsites = blacklistedWebsites
        
        // Sla downloads folder op (of nil als het de standaard is)
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
            .onChange(of: showPopupAfterDownload) { _, _ in saveConfig() }
            .onChange(of: bringPremiereToFront) { _, _ in saveConfig() }
            .onChange(of: bringResolveToFront) { _, _ in saveConfig() }
            .onChange(of: resolveAutoImport) { _, _ in saveConfig() }
            .onChange(of: showPetalAnimation) { _, _ in saveConfig() }
            .onChange(of: autoOpenBridgePanel) { _, _ in saveConfig() }
            .onChange(of: startAtLogin) { _, newValue in handleStartAtLoginChange(newValue) }
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
            .onChange(of: useClaudeClassification) { _, _ in saveConfig() }
            .onChange(of: useWebScraping) { _, _ in saveConfig() }
            .onChange(of: useGenreMoodDetection) { _, _ in saveConfig() }
            .onChange(of: useSfxSubfolders) { _, _ in saveConfig() }
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

// MARK: - Sub Views

// MARK: - Language Section

struct LanguageSection: View {
    @Binding var appLanguage: String
    let onSave: () -> Void

    private let languages: [(code: String, name: String, flag: String)] = [
        ("en", "English", "🇬🇧"),
        ("nl", "Nederlands", "🇳🇱"),
        ("de", "Deutsch", "🇩🇪"),
        ("fr", "Français", "🇫🇷"),
        ("es", "Español", "🇪🇸")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.language"))
                .font(.system(size: 13, weight: .semibold))

            HStack {
                Picker("", selection: $appLanguage) {
                    ForEach(languages, id: \.code) { lang in
                        Text("\(lang.flag) \(lang.name)").tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)

                Spacer()
            }

            Text(String(localized: "settings.language.restart_needed"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - SFX Subfolders Section

struct SfxSubfoldersSection: View {
    @Binding var useSfxSubfolders: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(String(localized: "settings.sfx_subfolders"), isOn: $useSfxSubfolders)
                .font(.system(size: 13))

            Text("Impacts, Swooshes, Foley, Ambience, UI, ...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Analytics Section

// MARK: - Folder Structure Section

struct FolderStructureSection: View {
    @StateObject private var appState = AppState.shared
    @Binding var folderStructurePreset: FolderStructurePreset
    let onSave: () -> Void

    @State private var templateFolderPath: String = ""
    @State private var scannedFolderTree: FolderNode?
    @State private var isScanningTemplate = false
    @State private var isAnalyzingTemplate = false
    @State private var templateMapping: FolderTypeMapping?
    @State private var templateError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.folder_structure"))
                .font(.system(size: 13, weight: .semibold))

            // Preset picker
            Picker(String(localized: "settings.folder_preset"), selection: $folderStructurePreset) {
                ForEach(FolderStructurePreset.allCases, id: \.self) { preset in
                    Text(String(localized: preset.displayKey)).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: folderStructurePreset) { _, _ in onSave() }

            // Custom template management
            if folderStructurePreset == .custom {
                if let template = appState.config.customFolderTemplate {
                    existingTemplateView(template)
                } else {
                    noTemplateView
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func existingTemplateView(_ template: CustomFolderTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                Text(URL(fileURLWithPath: template.sourcePath).lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button(String(localized: "settings.template.change")) {
                    selectTemplateFolder()
                }
                .controlSize(.small)
            }

            if let desc = template.mapping.description {
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .italic()
            }

            if let date = template.mapping.analyzedAt {
                Text("\(String(localized: "settings.template.analyzed_at")) \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            // Mapping overzicht
            VStack(alignment: .leading, spacing: 2) {
                settingsMappingRow("Music", path: template.mapping.musicPath)
                settingsMappingRow("SFX", path: template.mapping.sfxPath)
                settingsMappingRow("Voice Over", path: template.mapping.voPath)
                settingsMappingRow("Graphics", path: template.mapping.graphicsPath)
                settingsMappingRow("Motion Graphics", path: template.mapping.motionGraphicsPath)
                settingsMappingRow("Stock Footage", path: template.mapping.stockFootagePath)
            }
            .padding(6)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(4)

            Button(String(localized: "settings.template.reanalyze")) {
                reanalyzeTemplate(template)
            }
            .controlSize(.small)
            .disabled(isAnalyzingTemplate)

            if isAnalyzingTemplate {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: "onboarding.template.analyzing"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            if let error = templateError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
        .padding(.top, 4)
    }

    private var noTemplateView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "settings.template.none"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Button(String(localized: "onboarding.template.select_folder")) {
                selectTemplateFolder()
            }
            .controlSize(.small)

            if isScanningTemplate || isAnalyzingTemplate {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(String(localized: isScanningTemplate
                                ? "onboarding.template.scanning"
                                : "onboarding.template.analyzing"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            if let error = templateError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
            }
        }
        .padding(.top, 4)
    }

    private func settingsMappingRow(_ label: String, path: String?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 90, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
            Text(path ?? "-")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(path != nil ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func selectTemplateFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "onboarding.template.panel_message")

        if panel.runModal() == .OK, let url = panel.url {
            templateFolderPath = url.path
            templateError = nil
            isScanningTemplate = true

            Task {
                let tree = FolderTemplateService.shared.scanFolderTree(at: url)
                await MainActor.run {
                    scannedFolderTree = tree
                    isScanningTemplate = false
                    isAnalyzingTemplate = true
                }

                do {
                    let mapping = try await FolderTemplateService.shared.analyzeStructure(
                        tree: tree,
                        deviceId: appState.config.anonymousId
                    )
                    await MainActor.run {
                        appState.config.customFolderTemplate = CustomFolderTemplate(
                            sourcePath: templateFolderPath,
                            folderTree: tree,
                            mapping: mapping,
                            createdAt: Date(),
                            lastUpdatedAt: Date()
                        )
                        appState.saveConfig()
                        isAnalyzingTemplate = false
                    }
                } catch {
                    await MainActor.run {
                        templateError = error.localizedDescription
                        isAnalyzingTemplate = false
                    }
                }
            }
        }
    }

    private func reanalyzeTemplate(_ template: CustomFolderTemplate) {
        templateError = nil
        isAnalyzingTemplate = true

        Task {
            do {
                let mapping = try await FolderTemplateService.shared.analyzeStructure(
                    tree: template.folderTree,
                    deviceId: appState.config.anonymousId
                )
                await MainActor.run {
                    appState.config.customFolderTemplate?.mapping = mapping
                    appState.config.customFolderTemplate?.lastUpdatedAt = Date()
                    appState.saveConfig()
                    isAnalyzingTemplate = false
                }
            } catch {
                await MainActor.run {
                    templateError = error.localizedDescription
                    isAnalyzingTemplate = false
                }
            }
        }
    }
}

struct AnalyticsSection: View {
    @Binding var analyticsEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(String(localized: "settings.analytics"), isOn: $analyticsEnabled)
                .font(.system(size: 13))

            Text(String(localized: "settings.analytics.description"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Project Roots Section

struct ProjectRootsSection: View {
    @Binding var projectRoots: [String]
    @Binding var newRoot: String
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.project_roots"))
                .font(.system(size: 13, weight: .semibold))
            
            if !projectRoots.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(projectRoots, id: \.self) { root in
                        HStack(spacing: 8) {
                            Text(root)
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Spacer()
                            Button(String(localized: "common.delete")) {
                                projectRoots.removeAll { $0 == root }
                                onSave()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                    }
                }
            }
            
            HStack(spacing: 6) {
                TextField(String(localized: "settings.new_root_path"), text: $newRoot)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Button(String(localized: "common.browse")) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        newRoot = url.path
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(String(localized: "common.add")) {
                    if !newRoot.isEmpty {
                        projectRoots.append(newRoot)
                        newRoot = ""
                        onSave()
                        Task {
                            await AppState.shared.refreshRecentProjects()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newRoot.isEmpty)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }
}

struct MusicClassificationSection: View {
    @Binding var musicMode: MusicMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.music_classification"))
                .font(.system(size: 13, weight: .semibold))

            Picker(String(localized: "settings.mode"), selection: $musicMode) {
                Text(String(localized: "common.mood")).tag(MusicMode.mood)
                Text(String(localized: "common.genre")).tag(MusicMode.genre)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }
}

enum ClaudeConnectionStatus {
    case unknown
    case testing
    case connected
    case failed(String)
}

struct ClaudeClassificationSection: View {
    @Binding var useClaudeClassification: Bool
    @Binding var claudeAPIKey: String
    @Binding var connectionStatus: ClaudeConnectionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(String(localized: "settings.claude_classification"))
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()

                    claudeStatusBadge
                }

                Text(String(localized: "settings.claude_description"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Toggle(String(localized: "settings.use_claude"), isOn: $useClaudeClassification)
                .font(.system(size: 11))

            if useClaudeClassification {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "settings.api_key"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    HStack {
                        SecureField(String(localized: "settings.api_key_placeholder"), text: $claudeAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)

                        Button(String(localized: "settings.test_connection")) {
                            testConnection()
                        }
                        .controlSize(.small)
                        .disabled(claudeAPIKey.isEmpty)
                    }

                    Text(String(localized: "settings.api_key_hint"))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }

    @ViewBuilder
    private var claudeStatusBadge: some View {
        switch connectionStatus {
        case .unknown:
            EmptyView()
        case .testing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text(String(localized: "settings.connection.testing"))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        case .connected:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 10))
                Text(String(localized: "settings.connection.connected"))
                    .font(.system(size: 9))
                    .foregroundColor(.green)
            }
        case .failed:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 10))
                Text(String(localized: "settings.connection.failed"))
                    .font(.system(size: 9))
                    .foregroundColor(.red)
            }
        }
    }

    private func testConnection() {
        connectionStatus = .testing
        Task {
            let success = await ClaudeClassificationStrategy.testConnection(apiKey: claudeAPIKey)
            await MainActor.run {
                connectionStatus = success ? .connected : .failed("Connection failed")
            }
        }
    }
}

struct GenreMoodDetectionSection: View {
    @Binding var useGenreMoodDetection: Bool
    @Binding var useWebScraping: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "settings.genre_mood_detection"))
                    .font(.system(size: 13, weight: .semibold))

                Text(String(localized: "settings.genre_mood_description"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Toggle(String(localized: "settings.enable_genre_mood"), isOn: $useGenreMoodDetection)
                .font(.system(size: 11))
            
            if useGenreMoodDetection {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    
                    Toggle(String(localized: "settings.web_scraping"), isOn: $useWebScraping)
                        .font(.system(size: 11))

                    Text(String(localized: "settings.web_scraping_description"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    if useWebScraping {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "settings.supported_providers"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 8) {
                                ForEach(["Artlist", "Epidemic Sound", "Envato"], id: \.self) { provider in
                                    Text(provider)
                                        .font(.system(size: 9))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    Text(String(localized: "settings.detection_methods"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 10))
                            Text(String(localized: "settings.filename_analysis"))
                                .font(.system(size: 10))
                        }
                        if useWebScraping {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 10))
                                Text(String(localized: "settings.web_scraping_available"))
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }
}

struct DownloadsFolderSection: View {
    @Binding var downloadsFolder: String
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.downloads_folder"))
                .font(.system(size: 13, weight: .semibold))
            
            HStack(spacing: 6) {
                TextField(String(localized: "settings.downloads_folder_path"), text: $downloadsFolder)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .disabled(true)
                Button(String(localized: "common.browse")) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = true
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        downloadsFolder = url.path
                        onSave()
                        DispatchQueue.main.async {
                            DownloadsWatcher.shared.updateDownloadsFolder(url)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("Reset") {
                    downloadsFolder = ""
                    onSave()
                    let defaultFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                    DispatchQueue.main.async {
                        DownloadsWatcher.shared.updateDownloadsFolder(defaultFolder)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Text(String(localized: "settings.default_downloads"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }
}

struct StockWebsitesSection: View {
    @Binding var customStockWebsites: [String]
    @Binding var newStockWebsite: String
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "settings.stock_websites"))
                    .font(.system(size: 13, weight: .semibold))

                Text(String(localized: "settings.stock_websites_description"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            if !customStockWebsites.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(customStockWebsites, id: \.self) { website in
                        HStack(spacing: 8) {
                            Text(website)
                                .font(.system(size: 11))
                            Spacer()
                            Button(String(localized: "common.delete")) {
                                customStockWebsites.removeAll { $0 == website }
                                onSave()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                    }
                }
            }
            
            HStack(spacing: 6) {
                TextField(String(localized: "settings.example_website"), text: $newStockWebsite)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Button(String(localized: "common.add")) {
                    if !newStockWebsite.isEmpty && !customStockWebsites.contains(newStockWebsite) {
                        customStockWebsites.append(newStockWebsite)
                        newStockWebsite = ""
                        onSave()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newStockWebsite.isEmpty)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }
}

struct BlacklistWebsitesSection: View {
    @Binding var blacklistedWebsites: [String]
    @Binding var newBlacklistedWebsite: String
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "settings.blacklist_websites"))
                    .font(.system(size: 13, weight: .semibold))

                Text(String(localized: "settings.blacklist_description"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            if !blacklistedWebsites.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(blacklistedWebsites, id: \.self) { website in
                        HStack(spacing: 8) {
                            Text(website)
                                .font(.system(size: 11))
                            Spacer()
                            Button(String(localized: "common.delete")) {
                                blacklistedWebsites.removeAll { $0 == website }
                                onSave()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                    }
                }
            }
            
            HStack(spacing: 6) {
                TextField(String(localized: "settings.example_website"), text: $newBlacklistedWebsite)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Button(String(localized: "common.add")) {
                    if !newBlacklistedWebsite.isEmpty && !blacklistedWebsites.contains(newBlacklistedWebsite) {
                        blacklistedWebsites.append(newBlacklistedWebsite)
                        newBlacklistedWebsite = ""
                        onSave()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newBlacklistedWebsite.isEmpty)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }
}

struct WindowBehaviorSection: View {
    @Binding var showPopupAfterDownload: Bool
    @Binding var bringPremiereToFront: Bool
    @Binding var bringResolveToFront: Bool
    @Binding var resolveAutoImport: Bool
    @Binding var showPetalAnimation: Bool
    @Binding var autoOpenBridgePanel: Bool
    @Binding var startAtLogin: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.window_behavior"))
                .font(.system(size: 13, weight: .semibold))

            Toggle(String(localized: "settings.show_popup"), isOn: $showPopupAfterDownload)
                .font(.system(size: 11))

            Toggle(String(localized: "settings.petal_animation"), isOn: $showPetalAnimation)
                .font(.system(size: 11))

            Toggle(String(localized: "settings.bring_premiere"), isOn: $bringPremiereToFront)
                .font(.system(size: 11))

            Toggle(String(localized: "settings.auto_open_bridge"), isOn: $autoOpenBridgePanel)
                .font(.system(size: 11))

            Divider()

            Text("DaVinci Resolve")
                .font(.system(size: 13, weight: .semibold))

            Toggle(String(localized: "settings.bring_resolve"), isOn: $bringResolveToFront)
                .font(.system(size: 11))

            Toggle(String(localized: "settings.resolve_auto_import"), isOn: $resolveAutoImport)
                .font(.system(size: 11))

            HStack(spacing: 6) {
                Circle()
                    .fill(ResolveScriptManager.shared.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(ResolveScriptManager.shared.isRunning
                     ? String(localized: "settings.resolve_bridge.running")
                     : String(localized: "settings.resolve_bridge.stopped"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Divider()

            Toggle(String(localized: "settings.start_at_login"), isOn: $startAtLogin)
                .font(.system(size: 11))
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }
}

// MARK: - Project Behavior Section

struct ProjectBehaviorSection: View {
    @Binding var filterServerProjectsToLocal: Bool
    @Binding var autoAddActiveProjectRoot: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.project_behavior"))
                .font(.system(size: 13, weight: .semibold))

            Toggle(String(localized: "settings.filter_server_projects"), isOn: $filterServerProjectsToLocal)
                .font(.system(size: 11))

            Text(String(localized: "settings.filter_server_projects.description"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Toggle(String(localized: "settings.auto_add_project_root"), isOn: $autoAddActiveProjectRoot)
                .font(.system(size: 11))

            Text(String(localized: "settings.auto_add_project_root.description"))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }
}

// MARK: - Update Sections

struct AppUpdateSection: View {
    @StateObject private var updateManager = UpdateManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "settings.app_updates"))
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                Text("v\(updateManager.currentVersion) (\(updateManager.buildNumber))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Spacer()

                Button(String(localized: "settings.check_updates")) {
                    updateManager.checkForUpdates()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Toggle(String(localized: "settings.auto_check_updates"), isOn: Binding(
                get: { updateManager.automaticUpdatesEnabled },
                set: { updateManager.automaticUpdatesEnabled = $0 }
            ))
            .font(.system(size: 11))
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }
}

struct PluginUpdateSection: View {
    @State private var isUpdating = false
    @State private var updateError: String?
    @State private var updateSuccess = false
    
    private var pluginInfo: PluginUpdateInfo {
        UpdateManager.shared.pluginUpdateInfo
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "settings.plugin_updates"))
                .font(.system(size: 13, weight: .semibold))
            
            // Premiere Plugin
            HStack(spacing: 8) {
                Image(systemName: "film.fill")
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Premiere Pro Plugin")
                        .font(.system(size: 12, weight: .medium))
                    
                    if let installed = pluginInfo.installedPremiereVersion {
                        Text(String(localized: "settings.installed_version \(installed)"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        Text(String(localized: "settings.not_installed"))
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                if pluginInfo.premierePluginUpdateAvailable {
                    if isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(String(localized: "settings.update_to \(pluginInfo.bundledPremiereVersion ?? "")")) {
                            updatePremierePlugin()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                } else if pluginInfo.installedPremiereVersion != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            
            // Chrome Extension
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.chrome_extension"))
                        .font(.system(size: 12, weight: .medium))

                    if let installed = pluginInfo.installedChromeVersion {
                        Text(String(localized: "settings.installed_version \(installed)"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    } else {
                        Text(String(localized: "settings.not_installed_manual"))
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                if pluginInfo.chromeExtensionUpdateAvailable {
                    Button(String(localized: "settings.instructions")) {
                        SetupManager.shared.openChromeExtensionFolder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            
            if let error = updateError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
            
            if updateSuccess {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(String(localized: "settings.plugin_updated"))
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }
    
    private func updatePremierePlugin() {
        isUpdating = true
        updateError = nil
        updateSuccess = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            let result = UpdateManager.shared.updatePremierePlugin()
            
            DispatchQueue.main.async {
                isUpdating = false
                
                switch result {
                case .success:
                    updateSuccess = true
                case .failure(let error):
                    updateError = error.localizedDescription
                }
            }
        }
    }
}

struct SetupSection: View {
    @State private var showResetConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Setup")
                .font(.system(size: 13, weight: .semibold))
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.rerun_onboarding"))
                        .font(.system(size: 12))
                    Text(String(localized: "settings.rerun_onboarding_description"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(String(localized: "settings.reset_setup")) {
                    showResetConfirmation = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Divider()
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "settings.reinstall_plugin"))
                        .font(.system(size: 12))
                    Text(String(localized: "settings.reinstall_plugin_description"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(String(localized: "settings.reinstall")) {
                    _ = SetupManager.shared.installPremierePlugin()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
        .alert(String(localized: "settings.reset_setup_title"), isPresented: $showResetConfirmation) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "settings.reset"), role: .destructive) {
                SetupManager.shared.resetOnboarding()
                // Toon onboarding
                OnboardingWindowController.show {}
            }
        } message: {
            Text(String(localized: "settings.reset_setup_message"))
        }
    }
}

// MARK: - Feedback Tab

private enum FeedbackType: String, CaseIterable {
    case featureRequest
    case bugReport
}

private enum FeedbackSendState: Equatable {
    case idle
    case sending
    case success
    case error(String)
}

private struct FeedbackTabView: View {
    @State private var selectedFeedbackType: FeedbackType = .featureRequest
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var message: String = ""
    @State private var sendState: FeedbackSendState = .idle

    private static let proxyBaseURL = "https://fileflower-proxy.fileflower.workers.dev"

    private var accentColor: Color {
        selectedFeedbackType == .featureRequest ? .brandSandyClay : .brandBurntPeach
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "settings.feedback"))
                .font(.system(size: 13, weight: .semibold))

            Text(String(localized: "settings.feedback.description"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            // Feedback type picker
            Picker("", selection: $selectedFeedbackType) {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10))
                    Text(String(localized: "settings.feedback.feature_request"))
                }
                .tag(FeedbackType.featureRequest)

                HStack(spacing: 4) {
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 10))
                    Text(String(localized: "settings.feedback.report_bug"))
                }
                .tag(FeedbackType.bugReport)
            }
            .pickerStyle(.segmented)
            .disabled(sendState == .sending)

            switch sendState {
            case .idle, .error:
                feedbackForm
            case .sending:
                sendingView
            case .success:
                successView
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }

    private var feedbackForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "settings.feedback.name"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField(String(localized: "settings.feedback.name_placeholder"), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "settings.feedback.email"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField(String(localized: "settings.feedback.email_placeholder"), text: $email)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "settings.feedback.message"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextEditor(text: $message)
                    .font(.system(size: 12))
                    .frame(minHeight: 80, maxHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
            }

            // Error banner
            if case .error(let errorMessage) = sendState {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.brandBurntPeach)
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.brandBurntPeach)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.brandBurntPeach.opacity(0.1))
                .cornerRadius(6)
            }

            // Verstuur button
            HStack {
                Spacer()
                Button(action: sendFeedback) {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                        Text(String(localized: "settings.feedback.send"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(name.isEmpty || email.isEmpty || message.isEmpty)
            }
        }
    }

    private var sendingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "settings.feedback.sending"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var successView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)
            Text(String(localized: "settings.feedback.success"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.green)
            Text(String(localized: "settings.feedback.success_description"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sendState = .idle
                    name = ""
                    email = ""
                    message = ""
                }
            }) {
                Text(String(localized: "settings.feedback.send_another"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func sendFeedback() {
        withAnimation(.easeInOut(duration: 0.2)) {
            sendState = .sending
        }

        Task {
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            let deviceId = AppState.shared.config.anonymousId

            guard let url = URL(string: "\(Self.proxyBaseURL)/api/feedback") else {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sendState = .error(String(localized: "settings.feedback.error.send_failed"))
                    }
                }
                return
            }

            let requestBody: [String: String] = [
                "type": selectedFeedbackType.rawValue,
                "name": name,
                "email": email,
                "message": message,
                "appVersion": appVersion,
                "osVersion": osVersion
            ]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
            request.timeoutInterval = 15.0

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sendState = .error(String(localized: "settings.feedback.error.send_failed"))
                        }
                    }
                    return
                }

                if httpResponse.statusCode == 200 {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sendState = .success
                        }
                    }
                } else if httpResponse.statusCode == 429 {
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sendState = .error(String(localized: "settings.feedback.error.rate_limit"))
                        }
                    }
                } else {
                    #if DEBUG
                    if let errorBody = String(data: data, encoding: .utf8) {
                        print("Feedback: HTTP \(httpResponse.statusCode) - \(errorBody.prefix(200))")
                    }
                    #endif
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sendState = .error(String(localized: "settings.feedback.error.send_failed"))
                        }
                    }
                }
            } catch {
                #if DEBUG
                print("Feedback: Network error: \(error.localizedDescription)")
                #endif
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sendState = .error(String(localized: "settings.feedback.error.network"))
                    }
                }
            }
        }
    }
}