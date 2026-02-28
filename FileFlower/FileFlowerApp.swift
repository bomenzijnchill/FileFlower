import SwiftUI
import AppKit
import Combine

@main
struct FileFlowerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(onDismiss: {})
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - app draait alleen in de menubalk
        NSApplication.shared.setActivationPolicy(.accessory)

        // Locale wordt nu via SwiftUI .environment(\.locale) ingesteld
        // Geen UserDefaults override meer nodig

        // Initialiseer het menubar icoon met popover
        _ = StatusBarController.shared

        // Start analytics sessie
        AnalyticsService.shared.startSession()

        // Registreer FinderSync extensie direct bij launch, zodat deze al zichtbaar is
        // in Systeeminstellingen tijdens de onboarding wizard
        SetupManager.shared.registerFinderExtension()

        // Stap 1: Check of dit de eerste launch is, of een update met nieuwe onboarding stappen
        if !SetupManager.shared.hasCompletedOnboarding || SetupManager.shared.shouldShowOnboardingForUpdate {
            showOnboarding()
        } else {
            // Stap 2: Check license
            checkLicenseAndContinue()
        }
    }
    
    /// BELANGRIJK: Voorkom dat de app sluit als alle vensters gesloten worden
    /// Dit is essentieel voor menu bar apps die geen dock icon hebben
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    private func showOnboarding() {
        // Toon onboarding wizard
        OnboardingWindowController.show { [weak self] in
            // Na onboarding, check license
            self?.checkLicenseAndContinue()
            #if DEBUG
            print("AppDelegate: Onboarding voltooid")
            #endif
        }
    }
    
    private func checkLicenseAndContinue() {
        let licenseManager = LicenseManager.shared
        
        // Revalideer opgeslagen license op achtergrond
        Task {
            await licenseManager.revalidateStoredLicense()
            
            await MainActor.run {
                if licenseManager.canUseApp {
                    // Licensed of in trial - start normaal
                    self.startApp()
                } else {
                    // Geen license en trial verlopen - toon activeringsscherm
                    self.showLicenseActivation()
                }
            }
        }
    }
    
    private func showLicenseActivation() {
        // Stop downloads watcher zodat de app echt stil staat
        AppState.shared.stopDownloadsWatcher()

        LicenseWindowController.show(
            onActivated: { [weak self] in
                // Herstart downloads watcher na activering
                AppState.shared.restartDownloadsWatcher()
                self?.startApp()
            },
            onSkip: nil // Geen skip optie als trial verlopen is
        )
    }
    
    private func startApp() {
        #if DEBUG
        print("AppDelegate: startApp() aangeroepen")
        #endif

        // Voer startup checks uit (plugin updates etc.)
        SetupManager.shared.performStartupChecks()

        #if DEBUG
        print("AppDelegate: App gestart, license status: \(LicenseManager.shared.isLicensed ? "licensed" : "trial")")
        #endif
    }
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var queuedItems: [DownloadItem] = []
    @Published var config: Config = Config.default
    @Published var recentProjects: [ProjectInfo] = []
    @Published var shouldOpenWindow = false
    @Published var isPaused = false
    
    // FolderSync state
    @Published var folderSyncStatuses: [UUID: FolderSyncStatus] = [:]
    
    // MLX Daemon state
    @Published var isDaemonRunning = false
    @Published var isDaemonLoading = false
    
    private let configManager = ConfigManager.shared
    private let downloadsWatcher = DownloadsWatcher.shared
    private let folderSyncWatcher = FolderSyncWatcher.shared
    private let projectScanner = ProjectScanner.shared
    private let jobServer = JobServer.shared
    private let modelManager = ModelManager.shared
    private var activeProjectCancellable: AnyCancellable?
    private var daemonHealthCheckTimer: Timer?
    private var cachedSpotlightProjects: [ProjectInfo]?
    private var spotlightProjectsCacheTime: Date?
    
    private init() {
        loadConfig()
        migrateHashesIfNeeded()
        // Stel de taal in via UserDefaults zodat String(localized:) de juiste bundle locale gebruikt
        UserDefaults.standard.set([config.appLanguage], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        setupWatchers()
        startJobServer()
        syncLaunchAgent()
        setupActiveProjectListener()
        setupFolderSyncWatcher()
        setupDeployTemplateListener()
        
        // Laad custom downloads folder NA init is voltooid
        // Dit moet na alle andere initialisatie gebeuren
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.downloadsWatcher.loadCustomFolderIfNeeded(config: self.config)
            self.startAllFolderSyncs()

            // Start Resolve bridge monitoring zodat het actieve project beschikbaar is
            // voordat de eerste download binnenkomt (niet gated achter license check)
            ResolveScriptManager.shared.startMonitoring()

            // Start MLX daemon als MLX classificatie is ingeschakeld
            if self.config.useMLXClassification {
                self.startMLXDaemon()
            }
        }
        
        // Dagelijkse cleanup van verwerkingsgeschiedenis bij launch
        ProcessingHistoryManager.shared.cleanupOldRecords()

        // Setup app termination handler
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                // Clear afgeronde items bij afsluiten
                self.clearFinishedItems()
                self.stopMLXDaemon()
                // Eindig analytics sessie bij afsluiten
                AnalyticsService.shared.endSession()
            }
        }
    }
    
    /// Luister naar deploy template verzoeken van de Finder Sync Extension
    private func setupDeployTemplateListener() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.fileflower.deployTemplate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let targetPath = notification.object as? String else {
                #if DEBUG
                print("AppState: Deploy notification ontvangen maar geen pad")
                #endif
                return
            }

            #if DEBUG
            print("AppState: Deploy template verzoek ontvangen voor: \(targetPath)")
            #endif

            let targetURL = URL(fileURLWithPath: targetPath)
            let deployConfig = DeployConfig(
                folderStructurePreset: self.config.folderStructurePreset,
                customFolderTemplate: self.config.customFolderTemplate
            )

            do {
                let count = try TemplateDeployer.deploy(to: targetURL, config: deployConfig)
                #if DEBUG
                print("AppState: \(count) mappen aangemaakt in \(targetPath)")
                #endif
            } catch {
                #if DEBUG
                print("AppState: Deploy error: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private var resolveActiveProjectCancellable: AnyCancellable?

    /// Luister naar wijzigingen in het actieve project vanuit de CEP plugin en Python bridge
    private func setupActiveProjectListener() {
        // Premiere Pro (CEP plugin)
        activeProjectCancellable = jobServer.$activeProjectPath
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activeProjectPath in
                guard let self = self, let path = activeProjectPath else { return }
                self.handleActiveProjectChange(path: path)
            }

        // DaVinci Resolve (Python bridge) — reageer op zowel projectPath als mediaRoot wijzigingen
        resolveActiveProjectCancellable = Publishers.CombineLatest(
            jobServer.$resolveActiveProjectPath,
            jobServer.$resolveMediaRoot
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] (resolveActiveProjectPath, _) in
            guard let self = self, let path = resolveActiveProjectPath else { return }
            self.handleActiveProjectChange(path: path)
        }
    }
    
    /// Verwerk een wijziging in het actieve project
    private func handleActiveProjectChange(path: String) {
        let projectURL = URL(fileURLWithPath: path)
        let projectName = projectURL.deletingPathExtension().lastPathComponent

        // Virtuele Resolve paden (database-backed projecten) hebben geen echte locatie op disk
        let isVirtualResolvePath = path.hasPrefix("/resolve-project/")
        let isResolveProject = isVirtualResolvePath || NLEType.from(projectPath: path) == .resolve

        // Lees de media root gerapporteerd door de Python bridge (indien beschikbaar)
        let mediaRoot = jobServer.resolveMediaRoot

        // Ruim eventuele foutief toegevoegde virtuele roots op (van eerdere versies)
        if config.projectRoots.contains("/resolve-project") {
            config.projectRoots.removeAll { $0 == "/resolve-project" }
            saveConfig()
            #if DEBUG
            print("AppState: Virtuele /resolve-project root verwijderd uit configuratie")
            #endif
        }

        // Auto-add project root als het niet in geconfigureerde roots staat
        // Skip voor virtuele Resolve paden (geen echte directories)
        if config.autoAddActiveProjectRoot && !isVirtualResolvePath {
            let projectDir = projectURL.deletingLastPathComponent().path
            let alreadyInRoots = config.projectRoots.contains { root in
                projectDir.hasPrefix(root) || path.hasPrefix(root)
            }

            if !alreadyInRoots {
                // Voeg de parent directory van het project toe als root
                let newRoot = projectURL.deletingLastPathComponent().deletingLastPathComponent().path
                config.projectRoots.append(newRoot)
                saveConfig()
                #if DEBUG
                print("AppState: Project root \(newRoot) automatisch toegevoegd voor \(projectName)")
                #endif
            }
        }

        // Invalideer Spotlight cache zodat preferredProject verse data gebruikt
        cachedSpotlightProjects = nil

        // Controleer of dit project al in recentProjects zit
        if let existingIndex = recentProjects.firstIndex(where: { $0.projectPath == path }) {
            var project = recentProjects.remove(at: existingIndex)

            // Update rootPath met de beste beschikbare bron
            if isResolveProject {
                if let mediaRoot = mediaRoot, FileManager.default.fileExists(atPath: mediaRoot) {
                    // Prioriteit 1: mediaRoot van de bridge (automatisch gedetecteerd uit clips)
                    let projectRoot = findProjectRootFromMediaRoot(mediaRoot)
                    if project.rootPath != projectRoot {
                        project.rootPath = projectRoot
                        #if DEBUG
                        print("AppState: Resolve project rootPath bijgewerkt via mediaRoot: \(projectRoot)")
                        #endif
                    }
                } else if isVirtualResolvePath && (project.rootPath == "/resolve-project" || !FileManager.default.fileExists(atPath: project.rootPath)) {
                    // Prioriteit 2: naam-matching in project roots (fallback)
                    if let realFolder = findRealProjectFolder(name: projectName) {
                        project.rootPath = realFolder
                        #if DEBUG
                        print("AppState: Resolve project rootPath bijgewerkt via naam-matching: \(realFolder)")
                        #endif
                    }
                }
            }

            recentProjects.insert(project, at: 0)
            if existingIndex != 0 {
                #if DEBUG
                print("AppState: Actief project \(project.name) naar voren verplaatst")
                #endif
            }
        } else {
            // Nieuw project: bepaal rootPath met prioriteitsketen
            let rootPath: String
            if isResolveProject {
                if let mediaRoot = mediaRoot, FileManager.default.fileExists(atPath: mediaRoot) {
                    // Prioriteit 1: mediaRoot van de bridge (automatisch gedetecteerd uit clips)
                    rootPath = findProjectRootFromMediaRoot(mediaRoot)
                    #if DEBUG
                    print("AppState: Resolve project '\(projectName)' rootPath via mediaRoot: \(rootPath) (mediaRoot was: \(mediaRoot))")
                    #endif
                } else if isVirtualResolvePath {
                    // Prioriteit 2: naam-matching in geconfigureerde project roots
                    if let realFolder = findRealProjectFolder(name: projectName) {
                        rootPath = realFolder
                        #if DEBUG
                        print("AppState: Resolve project '\(projectName)' gekoppeld via naam-matching: \(realFolder)")
                        #endif
                    } else {
                        // Prioriteit 3: virtueel pad (kan geen bestanden organiseren)
                        rootPath = "/resolve-project"
                        #if DEBUG
                        print("AppState: Resolve project '\(projectName)' heeft geen overeenkomstige map — wacht op mediaRoot van bridge")
                        #endif
                    }
                } else {
                    // Resolve project met .drp op disk
                    rootPath = projectURL.deletingLastPathComponent().deletingLastPathComponent().path
                }
            } else {
                // Premiere project
                rootPath = projectURL.deletingLastPathComponent().deletingLastPathComponent().path
            }

            // Auto-add project root voor virtuele Resolve projecten met echte rootPath
            if config.autoAddActiveProjectRoot && isVirtualResolvePath && rootPath != "/resolve-project" {
                let alreadyInRoots = config.projectRoots.contains { root in
                    rootPath.hasPrefix(root) || root.hasPrefix(rootPath)
                }
                if !alreadyInRoots {
                    let parentRoot = URL(fileURLWithPath: rootPath).deletingLastPathComponent().path
                    config.projectRoots.append(parentRoot)
                    saveConfig()
                    #if DEBUG
                    print("AppState: Project root \(parentRoot) automatisch toegevoegd voor virtueel Resolve project \(projectName)")
                    #endif
                }
            }

            let newProject = ProjectInfo(
                name: projectName,
                rootPath: rootPath,
                projectPath: path,
                lastModified: Date().timeIntervalSince1970
            )

            recentProjects.insert(newProject, at: 0)
            #if DEBUG
            print("AppState: Actief project \(projectName) toegevoegd als eerste project")
            #endif
        }
    }
    
    /// Zoek een echte projectmap in geconfigureerde project roots die overeenkomt met de projectnaam
    /// Wordt gebruikt voor database-backed DaVinci Resolve projecten die geen .drp op disk hebben
    private func findRealProjectFolder(name: String) -> String? {
        let fileManager = FileManager.default
        let normalizedName = name.lowercased()

        for root in config.projectRoots {
            // Skip virtuele paden
            if root.hasPrefix("/resolve-project") { continue }

            let rootURL = URL(fileURLWithPath: root)
            guard let contents = try? fileManager.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in contents {
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: item.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }

                if item.lastPathComponent.lowercased() == normalizedName {
                    return item.path
                }
            }
        }

        return nil
    }

    /// Zoek de project root vanuit een mediaRoot pad.
    /// Als mediaRoot een genummerde submap is (bijv. 02_Footage), geeft de parent terug.
    private func findProjectRootFromMediaRoot(_ mediaRoot: String) -> String {
        let url = URL(fileURLWithPath: mediaRoot)
        let folderName = url.lastPathComponent
        let fileManager = FileManager.default

        // Check of mediaRoot zelf een genummerde projectsubmap is (bijv. 02_Footage, 03_Audio)
        if folderName.range(of: #"^\d+[_\-]"#, options: .regularExpression) != nil {
            let parent = url.deletingLastPathComponent()
            if fileManager.fileExists(atPath: parent.path) {
                return parent.path
            }
        }

        // Alternatief: check of de parent van mediaRoot genummerde project folders bevat
        let parent = url.deletingLastPathComponent()
        if let contents = try? fileManager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            let hasProjectStructure = contents.contains { item in
                let name = item.lastPathComponent
                return name.hasPrefix("02_") || name.hasPrefix("03_") ||
                       name.hasPrefix("04_") || name.hasPrefix("05_")
            }
            if hasProjectStructure {
                return parent.path
            }
        }

        return mediaRoot
    }

    /// Geeft het beste project terug: 1) actief NLE project, 2) eerste recente project, 3) Spotlight fallback
    var preferredProject: ProjectInfo? {
        // Prioriteit 1a: Actief Premiere project via CEP plugin (indien vers)
        if let activeProjectPath = jobServer.activeProjectPath,
           jobServer.isActiveProjectFresh,
           let activeProject = recentProjects.first(where: { $0.projectPath == activeProjectPath }) {
            return activeProject
        }
        // Prioriteit 1b: Actief Resolve project via Python bridge (indien vers)
        if let resolveProjectPath = jobServer.resolveActiveProjectPath,
           jobServer.isResolveActiveProjectFresh,
           let resolveProject = recentProjects.first(where: { $0.projectPath == resolveProjectPath }) {
            return resolveProject
        }
        // Prioriteit 2: Eerste recente project (bevat nu ook Spotlight resultaten)
        if let firstRecent = recentProjects.first {
            return firstRecent
        }
        // Prioriteit 3: Directe Spotlight query (gecached, fallback als refreshRecentProjects nog niet klaar is)
        return spotlightProjects.first
    }

    /// Spotlight-ontdekte projecten (Premiere + Resolve), gecached voor 30 seconden
    private var spotlightProjects: [ProjectInfo] {
        if let cached = cachedSpotlightProjects,
           let cacheTime = spotlightProjectsCacheTime,
           Date().timeIntervalSince(cacheTime) < 30 {
            return cached
        }
        var projects = PremiereRecentProjectsReader.getRecentProjects(limit: 5)
        projects.append(contentsOf: ResolveRecentProjectsReader.getRecentProjects(limit: 5))
        projects.sort { $0.lastModified > $1.lastModified }
        cachedSpotlightProjects = projects
        spotlightProjectsCacheTime = Date()
        return projects
    }

    /// Controleer of een project onder een geconfigureerde project root valt
    func isProjectInConfiguredRoots(_ project: ProjectInfo) -> Bool {
        // Voor virtuele Resolve paden: check of rootPath onder een geconfigureerde root valt
        let isVirtualResolve = project.projectPath.hasPrefix("/resolve-project/")
        return config.projectRoots.contains { root in
            if isVirtualResolve {
                // Check of de echte rootPath (bijv. /Volumes/SSD/Projects/MyProject)
                // onder een geconfigureerde root valt, of dat rootPath zelf een root is
                return project.rootPath.hasPrefix(root) || root.hasPrefix(project.rootPath)
            }
            return project.projectPath.hasPrefix(root)
        }
    }

    private func syncLaunchAgent() {
        // Synchroniseer login item status met config
        let shouldBeEnabled = config.startAtLogin
        let isCurrentlyEnabled = LaunchAgentManager.shared.isStartAtLoginEnabled()

        if shouldBeEnabled && !isCurrentlyEnabled {
            do {
                try LaunchAgentManager.shared.enableStartAtLogin()
            } catch {
                #if DEBUG
                print("Fout bij inschakelen login item bij opstarten: \(error)")
                #endif
            }
        } else if !shouldBeEnabled && isCurrentlyEnabled {
            // Gebruiker heeft het via Systeeminstellingen aangezet — sync config
            config.startAtLogin = true
            configManager.save(config)
        }
    }
    
    private func startJobServer() {
        Task {
            do {
                try JobServer.shared.start()
            } catch {
                #if DEBUG
                print("Failed to start JobServer: \(error)")
                #endif
            }
        }
    }
    
    private func loadConfig() {
        if let loaded = configManager.load() {
            config = loaded
        }
        // Sync deploy config naar shared container voor Finder Sync Extension
        syncDeployConfigToSharedContainer()
    }

    /// Eenmalige migratie: wis oude syncedFileHashes die onbetrouwbaar zijn
    /// (van vóór de fix waarbij hashes pas na succesvolle Premiere import worden opgeslagen)
    private func migrateHashesIfNeeded() {
        let migrationKey = "didMigrateFolderSyncHashes_v2"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        var didChange = false
        for index in config.folderSyncs.indices {
            if !config.folderSyncs[index].syncedFileHashes.isEmpty {
                config.folderSyncs[index].syncedFileHashes.removeAll()
                didChange = true
            }
        }

        if didChange {
            configManager.save(config)
            #if DEBUG
            print("AppState: Migratie - oude syncedFileHashes gewist voor alle folder syncs")
            #endif
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private func setupWatchers() {
        downloadsWatcher.onNewFile = { [weak self] url, originURL in
            Task { @MainActor in
                await self?.handleNewDownload(url: url, originURL: originURL)
            }
        }
        downloadsWatcher.setupCloudZipMergerCallback()
        downloadsWatcher.start()
        
        Task {
            await refreshRecentProjects()
        }
    }
    
    func refreshRecentProjects() async {
        // Stap 1: Scan geconfigureerde roots (bestaand gedrag)
        var projects = await projectScanner.scanRecentProjects(
            roots: config.projectRoots,
            limit: config.recentProjectsCacheSize,
            filterToLocal: config.filterServerProjectsToLocal
        )

        // Stap 2: Voeg Spotlight-ontdekte projecten toe die nog niet in de lijst staan
        // Zoek zowel Premiere (.prproj) als DaVinci Resolve (.drp) projecten
        var spotlightProjects = PremiereRecentProjectsReader.getRecentProjects(limit: 5)
        spotlightProjects.append(contentsOf: ResolveRecentProjectsReader.getRecentProjects(limit: 5))
        if config.filterServerProjectsToLocal {
            spotlightProjects = spotlightProjects.filter { !PremiereRecentProjectsReader.isNetworkPath($0.projectPath) }
        }
        for spotlightProject in spotlightProjects {
            if !projects.contains(where: { $0.projectPath == spotlightProject.projectPath }) {
                projects.append(spotlightProject)
            }
        }

        // Stap 3: Zorg dat het actieve CEP project altijd in de lijst zit
        if let activeProjectPath = jobServer.activeProjectPath,
           !projects.contains(where: { $0.projectPath == activeProjectPath }) {
            let url = URL(fileURLWithPath: activeProjectPath)
            let name = url.deletingPathExtension().lastPathComponent
            let rootPath = url.deletingLastPathComponent().deletingLastPathComponent().path
            let lastModified: TimeInterval
            if let attrs = try? FileManager.default.attributesOfItem(atPath: activeProjectPath),
               let modDate = attrs[.modificationDate] as? Date {
                lastModified = modDate.timeIntervalSince1970
            } else {
                lastModified = Date().timeIntervalSince1970
            }
            let activeProject = ProjectInfo(
                name: name,
                rootPath: rootPath,
                projectPath: activeProjectPath,
                lastModified: lastModified
            )
            projects.insert(activeProject, at: 0)
        }

        // Sorteer op lastModified aflopend na samenvoegen
        projects.sort { $0.lastModified > $1.lastModified }

        // Invalideer Spotlight cache
        cachedSpotlightProjects = nil

        recentProjects = Array(projects.prefix(config.recentProjectsCacheSize))
    }
    
    private func handleNewDownload(url: URL, originURL: String?) async {
        // Blokkeer verwerking als trial verlopen en geen license
        guard LicenseManager.shared.canUseApp else {
            #if DEBUG
            print("AppState: Download genegeerd — license vereist")
            #endif
            await MainActor.run {
                LicenseWindowController.show(onActivated: { }, onSkip: nil)
            }
            return
        }

        // Haal file size op (werkt ook voor mappen)
        let fileManager = FileManager.default
        let size: Int64 = fileManager.fileSize(at: url) ?? 0

        // Detecteer of dit een cloud storage download is
        let isCloud = isCloudStorageDownload(originURL: originURL)

        // Detecteer of dit een map is (bijv. uitgepakte ZIP) en enumerate child files
        var isDir: ObjCBool = false
        let isFolder = fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        var childFiles: [String]? = nil
        if isFolder {
            if let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                childFiles = contents.map { $0.lastPathComponent }.sorted()
            }
        }

        // Maak eerst een item met "classifying" status zodat de UI direct kan openen
        let tempItem = DownloadItem(
            path: url.path,
            size: size,
            predictedType: .unknown,
            status: .classifying,
            isCloudDownload: isCloud,
            childFiles: childFiles
        )
        
        await MainActor.run {
            // Automatisch het voorkeurs project kiezen (actief project heeft prioriteit)
            var newItem = tempItem
            if let project = preferredProject {
                newItem.targetProject = project
                #if DEBUG
                print("AppState: Nieuw item gekoppeld aan project \(project.name)")
                #endif
            }
            queuedItems.append(newItem)
            
            // Open de popover alleen als de instelling aan staat
            if config.showPopupAfterDownload {
                shouldOpenWindow = true
            }
        }
        
        // Classificeer asynchroon op de achtergrond (niet op main thread)
        // Gebruik Task.detached om zeker te zijn dat het niet op main actor draait
        Task.detached(priority: .userInitiated) {
            let classifiedItem = await Classifier.shared.classify(url: url, originURL: originURL)
            
            await MainActor.run {
                // Update het item in de queue
                if let index = self.queuedItems.firstIndex(where: { $0.id == tempItem.id }) {
                    // Bij cloud downloads met onbekend type: vraag gebruiker om map te kiezen
                    let needsManual = isCloud && classifiedItem.predictedType == .unknown

                    // Maak een nieuw item met dezelfde ID maar met de geclassificeerde data
                    let updatedItem = DownloadItem(
                        id: tempItem.id, // Behoud dezelfde ID
                        path: classifiedItem.path,
                        uti: classifiedItem.uti,
                        size: classifiedItem.size,
                        originUrl: classifiedItem.originUrl,
                        createdAt: classifiedItem.createdAt,
                        metadata: classifiedItem.metadata,
                        predictedType: classifiedItem.predictedType,
                        status: .queued, // Zet status terug naar queued na classificatie
                        targetProject: self.preferredProject ?? tempItem.targetProject,
                        targetSubfolder: classifiedItem.targetSubfolder,
                        targetPath: classifiedItem.targetPath,
                        predictedGenre: classifiedItem.predictedGenre,
                        predictedMood: classifiedItem.predictedMood,
                        predictedSfxCategory: classifiedItem.predictedSfxCategory,
                        isCloudDownload: isCloud,
                        needsManualClassification: needsManual
                    )
                    self.queuedItems[index] = updatedItem
                }
            }
        }
    }
    
    private func isCloudStorageDownload(originURL: String?) -> Bool {
        guard let origin = originURL?.lowercased() else { return false }
        return config.cloudStorageWebsites.contains { origin.contains($0.lowercased()) }
    }

    func clearCompletedItems() {
        queuedItems.removeAll { $0.status == .completed }
    }

    func clearAllItems() {
        queuedItems.removeAll()
    }

    /// Verwijder afgeronde en overgeslagen items uit de queue
    func clearFinishedItems() {
        queuedItems.removeAll { $0.status == .completed || $0.status == .skipped }
    }
    
    func saveConfig() {
        let previousMLXEnabled = configManager.load()?.useMLXClassification ?? false
        let previousModelName = configManager.load()?.mlxModelName ?? ""

        // Invalideer Spotlight cache zodat nieuwe roots meegenomen worden
        cachedSpotlightProjects = nil

        configManager.save(config)
        // Update classifier strategy wanneer config verandert
        Classifier.shared.updateStrategy()

        // Sync deploy config naar shared container voor Finder Sync Extension
        syncDeployConfigToSharedContainer()

        // Daemon management bij config wijzigingen
        if config.useMLXClassification != previousMLXEnabled {
            if config.useMLXClassification {
                // MLX is nu ingeschakeld - start daemon
                startMLXDaemon()
            } else {
                // MLX is nu uitgeschakeld - stop daemon
                stopMLXDaemon()
            }
        } else if config.useMLXClassification && config.mlxModelName != previousModelName {
            // Model is gewijzigd - herstart daemon met nieuw model
            restartMLXDaemon()
        }
    }
    
    /// Sync de actieve folder preset en template naar de App Group shared container,
    /// zodat de Finder Sync Extension hier bij kan.
    private func syncDeployConfigToSharedContainer() {
        let deployConfig = DeployConfig(
            folderStructurePreset: config.folderStructurePreset,
            customFolderTemplate: config.customFolderTemplate
        )
        SharedConfigReader.saveDeployConfig(deployConfig)
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            downloadsWatcher.stop()
            #if DEBUG
            print("AppState: Downloads watcher gepauzeerd")
            #endif
        } else {
            downloadsWatcher.start()
            #if DEBUG
            print("AppState: Downloads watcher hervat")
            #endif
        }
    }

    /// Stop de downloads watcher (gebruikt bij trial lockdown)
    func stopDownloadsWatcher() {
        downloadsWatcher.stop()
        #if DEBUG
        print("AppState: Downloads watcher gestopt (license vereist)")
        #endif
    }

    /// Herstart de downloads watcher (na license activering)
    func restartDownloadsWatcher() {
        downloadsWatcher.start()
        isPaused = false
        #if DEBUG
        print("AppState: Downloads watcher herstart (license geactiveerd)")
        #endif
    }
    
    // MARK: - MLX Daemon Methods
    
    /// Start de MLX daemon voor snelle classificatie
    func startMLXDaemon() {
        guard config.useMLXClassification else {
            #if DEBUG
            print("AppState: MLX classificatie is uitgeschakeld, daemon niet gestart")
            #endif
            return
        }
        
        isDaemonLoading = true
        
        Task {
            do {
                // Check eerst of daemon al draait
                if await modelManager.isDaemonRunning() {
                    await MainActor.run {
                        self.isDaemonRunning = true
                        self.isDaemonLoading = false
                        #if DEBUG
                        print("AppState: MLX daemon draait al")
                        #endif
                    }
                    startDaemonHealthCheck()
                    return
                }
                
                // Start de daemon
                try await modelManager.startDaemon(modelName: config.mlxModelName)
                
                await MainActor.run {
                    self.isDaemonRunning = true
                    self.isDaemonLoading = false
                    #if DEBUG
                    print("AppState: MLX daemon gestart")
                    #endif
                }
                
                startDaemonHealthCheck()
                
            } catch {
                await MainActor.run {
                    self.isDaemonRunning = false
                    self.isDaemonLoading = false
                    #if DEBUG
                    print("AppState: Kon MLX daemon niet starten: \(error)")
                    #endif
                }
            }
        }
    }
    
    /// Stop de MLX daemon
    func stopMLXDaemon() {
        daemonHealthCheckTimer?.invalidate()
        daemonHealthCheckTimer = nil
        
        modelManager.stopDaemon()
        isDaemonRunning = false
        #if DEBUG
        print("AppState: MLX daemon gestopt")
        #endif
    }
    
    /// Herstart de MLX daemon
    func restartMLXDaemon() {
        stopMLXDaemon()
        
        // Wacht even voordat we opnieuw starten
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startMLXDaemon()
        }
    }
    
    /// Start periodic health check voor de daemon
    private func startDaemonHealthCheck() {
        daemonHealthCheckTimer?.invalidate()
        
        daemonHealthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                guard let self = self else { return }
                
                let running = await self.modelManager.isDaemonRunning()
                
                await MainActor.run {
                    if self.isDaemonRunning != running {
                        self.isDaemonRunning = running
                        if !running {
                            #if DEBUG
                            print("AppState: MLX daemon is gestopt (health check)")
                            #endif
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - FolderSync Methods
    
    /// Setup de FolderSyncWatcher callback
    private func setupFolderSyncWatcher() {
        folderSyncWatcher.onStatusChange = { [weak self] syncId, status in
            DispatchQueue.main.async {
                self?.folderSyncStatuses[syncId] = status
            }
        }
    }
    
    /// Start alle geconfigureerde folder syncs (skip syncs die al actief zijn)
    private func startAllFolderSyncs() {
        var startedCount = 0
        for sync in config.folderSyncs where sync.isEnabled {
            if !folderSyncWatcher.isWatching(syncId: sync.id) {
                folderSyncWatcher.startWatching(sync: sync)
                startedCount += 1
            }
            folderSyncStatuses[sync.id] = .idle
        }
        #if DEBUG
        print("AppState: \(startedCount) folder syncs gestart (van \(config.folderSyncs.filter { $0.isEnabled }.count) enabled)")
        #endif
    }
    
    /// Voeg een nieuwe folder sync toe
    func addFolderSync(folderPath: String, projectPath: String, premiereBinRoot: String = "") {
        let newSync = FolderSync(
            folderPath: folderPath,
            projectPath: projectPath,
            premiereBinRoot: premiereBinRoot,
            isEnabled: true
        )
        
        config.folderSyncs.append(newSync)
        saveConfig()
        
        // Start monitoring
        folderSyncWatcher.startWatching(sync: newSync)
        folderSyncStatuses[newSync.id] = .idle
        
        #if DEBUG
        print("AppState: Nieuwe folder sync toegevoegd: \(folderPath) -> \(projectPath)")
        #endif
    }
    
    /// Verwijder een folder sync
    func removeFolderSync(syncId: UUID) {
        // Stop monitoring
        folderSyncWatcher.stopWatching(syncId: syncId)
        folderSyncStatuses.removeValue(forKey: syncId)
        
        // Verwijder uit config
        config.folderSyncs.removeAll { $0.id == syncId }
        saveConfig()
        
        #if DEBUG
        print("AppState: Folder sync verwijderd: \(syncId)")
        #endif
    }
    
    /// Toggle een folder sync aan/uit
    func toggleFolderSync(syncId: UUID) {
        guard let index = config.folderSyncs.firstIndex(where: { $0.id == syncId }) else { return }
        
        config.folderSyncs[index].isEnabled.toggle()
        let sync = config.folderSyncs[index]
        saveConfig()
        
        if sync.isEnabled {
            folderSyncWatcher.startWatching(sync: sync)
            folderSyncStatuses[sync.id] = .idle
            #if DEBUG
            print("AppState: Folder sync ingeschakeld: \(sync.folderName)")
            #endif
        } else {
            folderSyncWatcher.stopWatching(syncId: syncId)
            folderSyncStatuses.removeValue(forKey: syncId)
            #if DEBUG
            print("AppState: Folder sync uitgeschakeld: \(sync.folderName)")
            #endif
        }
    }
    
    /// Update de Premiere bin root voor een folder sync
    func updateFolderSyncBinRoot(syncId: UUID, binRoot: String) {
        guard let index = config.folderSyncs.firstIndex(where: { $0.id == syncId }) else { return }
        
        config.folderSyncs[index].premiereBinRoot = binRoot
        saveConfig()
        
        #if DEBUG
        print("AppState: Folder sync bin root bijgewerkt: \(binRoot)")
        #endif
    }
    
    /// Forceer een volledige sync voor een map
    func forceFolderSync(syncId: UUID) {
        guard let sync = config.folderSyncs.first(where: { $0.id == syncId }) else { return }

        Task {
            await folderSyncWatcher.forceFullSync(sync: sync)
        }
    }

    // MARK: - LoadFolder Preset Methods

    /// Voeg een nieuwe LoadFolder preset toe
    func addLoadFolderPreset(folderPath: String, displayName: String, premiereBinPath: String? = nil) {
        let preset = LoadFolderPreset(
            folderPath: folderPath,
            displayName: displayName,
            premiereBinPath: premiereBinPath
        )
        config.loadFolderPresets.append(preset)
        saveConfig()
        #if DEBUG
        print("AppState: LoadFolder preset toegevoegd: \(displayName)")
        #endif
    }

    /// Verwijder een LoadFolder preset
    func removeLoadFolderPreset(presetId: UUID) {
        config.loadFolderPresets.removeAll { $0.id == presetId }
        saveConfig()
        #if DEBUG
        print("AppState: LoadFolder preset verwijderd: \(presetId)")
        #endif
    }

    /// Update een LoadFolder preset
    func updateLoadFolderPreset(presetId: UUID, displayName: String, premiereBinPath: String? = nil) {
        guard let index = config.loadFolderPresets.firstIndex(where: { $0.id == presetId }) else { return }
        config.loadFolderPresets[index].displayName = displayName
        config.loadFolderPresets[index].premiereBinPath = premiereBinPath
        saveConfig()
        #if DEBUG
        print("AppState: LoadFolder preset bijgewerkt: \(displayName)")
        #endif
    }

    /// Laad een map in het actieve Premiere project
    func loadFolderIntoProject(preset: LoadFolderPreset) async {
        guard preset.folderExists else {
            #if DEBUG
            print("AppState: LoadFolder map bestaat niet: \(preset.folderPath)")
            #endif
            return
        }

        guard let project = preferredProject else {
            #if DEBUG
            print("AppState: Geen actief project beschikbaar voor LoadFolder")
            #endif
            return
        }

        let folderURL = URL(fileURLWithPath: preset.folderPath)
        let fileManager = FileManager.default

        // Enumerate alle bestanden in de map (recursief)
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            #if DEBUG
            print("AppState: Kon map niet enumereren: \(preset.folderPath)")
            #endif
            return
        }

        let files = enumerator.allObjects.compactMap { $0 as? URL }.filter { url in
            var isFile: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isFile) && !isFile.boolValue
        }

        guard !files.isEmpty else {
            #if DEBUG
            print("AppState: LoadFolder map is leeg: \(preset.folderPath)")
            #endif
            return
        }

        // Bepaal het bin pad
        let binPath = preset.premiereBinPath ?? preset.folderName

        let job = JobRequest(
            projectPath: project.projectPath,
            finderTargetDir: preset.folderPath,
            premiereBinPath: binPath,
            files: files.map { $0.path }
        )

        JobServer.shared.addJob(job)
        #if DEBUG
        print("AppState: LoadFolder job aangemaakt - \(files.count) bestanden naar bin '\(binPath)'")
        #endif
    }
}

