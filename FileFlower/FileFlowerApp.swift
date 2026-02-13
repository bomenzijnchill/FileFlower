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

        // Stap 1: Check of dit de eerste launch is
        if !SetupManager.shared.hasCompletedOnboarding {
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
            print("AppDelegate: Onboarding voltooid")
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
        LicenseWindowController.show(
            onActivated: { [weak self] in
                self?.startApp()
            },
            onSkip: nil // Geen skip optie als trial verlopen is
        )
    }
    
    private func startApp() {
        // Voer startup checks uit (plugin updates etc.)
        SetupManager.shared.performStartupChecks()
        print("AppDelegate: App gestart, license status: \(LicenseManager.shared.isLicensed ? "licensed" : "trial")")
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
        // Stel de taal in via UserDefaults zodat String(localized:) de juiste bundle locale gebruikt
        UserDefaults.standard.set([config.appLanguage], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        setupWatchers()
        startJobServer()
        syncLaunchAgent()
        setupActiveProjectListener()
        setupFolderSyncWatcher()
        
        // Laad custom downloads folder NA init is voltooid
        // Dit moet na alle andere initialisatie gebeuren
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.downloadsWatcher.loadCustomFolderIfNeeded(config: self.config)
            self.startAllFolderSyncs()
            
            // Start MLX daemon als MLX classificatie is ingeschakeld
            if self.config.useMLXClassification {
                self.startMLXDaemon()
            }
        }
        
        // Setup app termination handler
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                self.stopMLXDaemon()
                // Eindig analytics sessie bij afsluiten
                AnalyticsService.shared.endSession()
            }
        }
    }
    
    /// Luister naar wijzigingen in het actieve project vanuit de CEP plugin
    private func setupActiveProjectListener() {
        activeProjectCancellable = jobServer.$activeProjectPath
            .receive(on: DispatchQueue.main)
            .sink { [weak self] activeProjectPath in
                guard let self = self, let path = activeProjectPath else { return }
                self.handleActiveProjectChange(path: path)
            }
    }
    
    /// Verwerk een wijziging in het actieve project
    private func handleActiveProjectChange(path: String) {
        let projectURL = URL(fileURLWithPath: path)
        let projectName = projectURL.deletingPathExtension().lastPathComponent

        // Auto-add project root als het niet in geconfigureerde roots staat
        if config.autoAddActiveProjectRoot {
            let projectDir = projectURL.deletingLastPathComponent().path
            let alreadyInRoots = config.projectRoots.contains { root in
                projectDir.hasPrefix(root) || path.hasPrefix(root)
            }

            if !alreadyInRoots {
                // Voeg de parent directory van het project toe als root
                let newRoot = projectURL.deletingLastPathComponent().deletingLastPathComponent().path
                config.projectRoots.append(newRoot)
                saveConfig()
                print("AppState: Project root \(newRoot) automatisch toegevoegd voor \(projectName)")
            }
        }

        // Invalideer Spotlight cache zodat preferredProject verse data gebruikt
        cachedSpotlightProjects = nil

        // Controleer of dit project al in recentProjects zit
        if let existingIndex = recentProjects.firstIndex(where: { $0.projectPath == path }) {
            // Verplaats naar het begin van de lijst (hoogste prioriteit)
            let project = recentProjects.remove(at: existingIndex)
            recentProjects.insert(project, at: 0)
            print("AppState: Actief project \(project.name) naar voren verplaatst")
        } else {
            // Voeg het actieve project toe aan het begin van de lijst
            let rootPath = projectURL.deletingLastPathComponent().deletingLastPathComponent().path

            let newProject = ProjectInfo(
                name: projectName,
                rootPath: rootPath,
                projectPath: path,
                lastModified: Date().timeIntervalSince1970
            )

            recentProjects.insert(newProject, at: 0)
            print("AppState: Actief project \(projectName) toegevoegd als eerste project")
        }
    }
    
    /// Geeft het beste project terug: 1) actief CEP project, 2) eerste recente project, 3) Spotlight fallback
    var preferredProject: ProjectInfo? {
        // Prioriteit 1: Actief project via CEP plugin (indien vers)
        if let activeProjectPath = jobServer.activeProjectPath,
           jobServer.isActiveProjectFresh,
           let activeProject = recentProjects.first(where: { $0.projectPath == activeProjectPath }) {
            return activeProject
        }
        // Prioriteit 2: Eerste recente project (bevat nu ook Spotlight resultaten)
        if let firstRecent = recentProjects.first {
            return firstRecent
        }
        // Prioriteit 3: Directe Spotlight query (gecached, fallback als refreshRecentProjects nog niet klaar is)
        return spotlightProjects.first
    }

    /// Spotlight-ontdekte projecten, gecached voor 30 seconden
    private var spotlightProjects: [ProjectInfo] {
        if let cached = cachedSpotlightProjects,
           let cacheTime = spotlightProjectsCacheTime,
           Date().timeIntervalSince(cacheTime) < 30 {
            return cached
        }
        let projects = PremiereRecentProjectsReader.getRecentProjects(limit: 5)
        cachedSpotlightProjects = projects
        spotlightProjectsCacheTime = Date()
        return projects
    }

    /// Controleer of een project onder een geconfigureerde project root valt
    func isProjectInConfiguredRoots(_ project: ProjectInfo) -> Bool {
        return config.projectRoots.contains { root in
            project.projectPath.hasPrefix(root)
        }
    }

    private func syncLaunchAgent() {
        // Synchroniseer LaunchAgent met config
        let shouldBeEnabled = config.startAtLogin
        let isCurrentlyEnabled = LaunchAgentManager.shared.isStartAtLoginEnabled()
        
        if shouldBeEnabled && !isCurrentlyEnabled {
            // Config zegt enabled maar LaunchAgent is niet actief
            do {
                try LaunchAgentManager.shared.enableStartAtLogin()
            } catch {
                print("Fout bij inschakelen LaunchAgent bij opstarten: \(error)")
            }
        } else if !shouldBeEnabled && isCurrentlyEnabled {
            // Config zegt disabled maar LaunchAgent is actief
            do {
                try LaunchAgentManager.shared.disableStartAtLogin()
            } catch {
                print("Fout bij uitschakelen LaunchAgent bij opstarten: \(error)")
            }
        }
    }
    
    private func startJobServer() {
        Task {
            do {
                try JobServer.shared.start()
            } catch {
                print("Failed to start JobServer: \(error)")
            }
        }
    }
    
    private func loadConfig() {
        if let loaded = configManager.load() {
            config = loaded
        }
    }

    private func setupWatchers() {
        downloadsWatcher.onNewFile = { [weak self] url, originURL in
            Task { @MainActor in
                await self?.handleNewDownload(url: url, originURL: originURL)
            }
        }
        downloadsWatcher.start()
        
        Task {
            await refreshRecentProjects()
        }
    }
    
    func refreshRecentProjects() async {
        // Stap 1: Scan geconfigureerde roots (bestaand gedrag)
        var projects = await projectScanner.scanRecentProjects(
            roots: config.projectRoots,
            filterToLocal: config.filterServerProjectsToLocal
        )

        // Stap 2: Voeg Spotlight-ontdekte projecten toe die nog niet in de lijst staan
        var spotlightProjects = PremiereRecentProjectsReader.getRecentProjects(limit: 5)
        if config.filterServerProjectsToLocal {
            spotlightProjects = spotlightProjects.filter { !PremiereRecentProjectsReader.isNetworkPath($0.projectPath) }
        }
        for spotlightProject in spotlightProjects {
            if !projects.contains(where: { $0.projectPath == spotlightProject.projectPath }) {
                projects.append(spotlightProject)
            }
        }

        // Sorteer op lastModified aflopend na samenvoegen
        projects.sort { $0.lastModified > $1.lastModified }

        // Invalideer Spotlight cache
        cachedSpotlightProjects = nil

        recentProjects = Array(projects.prefix(config.recentProjectsCacheSize))
    }
    
    private func handleNewDownload(url: URL, originURL: String?) async {
        // Haal file size op (werkt ook voor mappen)
        let fileManager = FileManager.default
        let size: Int64 = fileManager.fileSize(at: url) ?? 0
        
        // Maak eerst een item met "classifying" status zodat de UI direct kan openen
        let tempItem = DownloadItem(
            path: url.path,
            size: size,
            predictedType: .unknown,
            status: .classifying
        )
        
        await MainActor.run {
            // Automatisch het voorkeurs project kiezen (actief project heeft prioriteit)
            var newItem = tempItem
            if let project = preferredProject {
                newItem.targetProject = project
                print("AppState: Nieuw item gekoppeld aan project \(project.name)")
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
                        predictedSfxCategory: classifiedItem.predictedSfxCategory
                    )
                    self.queuedItems[index] = updatedItem
                }
            }
        }
    }
    
    func clearCompletedItems() {
        queuedItems.removeAll { $0.status == .completed }
    }
    
    func clearAllItems() {
        queuedItems.removeAll()
    }
    
    func saveConfig() {
        let previousMLXEnabled = configManager.load()?.useMLXClassification ?? false
        let previousModelName = configManager.load()?.mlxModelName ?? ""

        // Invalideer Spotlight cache zodat nieuwe roots meegenomen worden
        cachedSpotlightProjects = nil

        configManager.save(config)
        // Update classifier strategy wanneer config verandert
        Classifier.shared.updateStrategy()
        
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
    
    func togglePause() {
        isPaused.toggle()
        if isPaused {
            downloadsWatcher.stop()
            print("AppState: Downloads watcher gepauzeerd")
        } else {
            downloadsWatcher.start()
            print("AppState: Downloads watcher hervat")
        }
    }
    
    // MARK: - MLX Daemon Methods
    
    /// Start de MLX daemon voor snelle classificatie
    func startMLXDaemon() {
        guard config.useMLXClassification else {
            print("AppState: MLX classificatie is uitgeschakeld, daemon niet gestart")
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
                        print("AppState: MLX daemon draait al")
                    }
                    startDaemonHealthCheck()
                    return
                }
                
                // Start de daemon
                try await modelManager.startDaemon(modelName: config.mlxModelName)
                
                await MainActor.run {
                    self.isDaemonRunning = true
                    self.isDaemonLoading = false
                    print("AppState: MLX daemon gestart")
                }
                
                startDaemonHealthCheck()
                
            } catch {
                await MainActor.run {
                    self.isDaemonRunning = false
                    self.isDaemonLoading = false
                    print("AppState: Kon MLX daemon niet starten: \(error)")
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
        print("AppState: MLX daemon gestopt")
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
                            print("AppState: MLX daemon is gestopt (health check)")
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
    
    /// Start alle geconfigureerde folder syncs
    private func startAllFolderSyncs() {
        for sync in config.folderSyncs where sync.isEnabled {
            folderSyncWatcher.startWatching(sync: sync)
            folderSyncStatuses[sync.id] = .idle
        }
        print("AppState: \(config.folderSyncs.filter { $0.isEnabled }.count) folder syncs gestart")
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
        
        print("AppState: Nieuwe folder sync toegevoegd: \(folderPath) -> \(projectPath)")
    }
    
    /// Verwijder een folder sync
    func removeFolderSync(syncId: UUID) {
        // Stop monitoring
        folderSyncWatcher.stopWatching(syncId: syncId)
        folderSyncStatuses.removeValue(forKey: syncId)
        
        // Verwijder uit config
        config.folderSyncs.removeAll { $0.id == syncId }
        saveConfig()
        
        print("AppState: Folder sync verwijderd: \(syncId)")
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
            print("AppState: Folder sync ingeschakeld: \(sync.folderName)")
        } else {
            folderSyncWatcher.stopWatching(syncId: syncId)
            folderSyncStatuses.removeValue(forKey: syncId)
            print("AppState: Folder sync uitgeschakeld: \(sync.folderName)")
        }
    }
    
    /// Update de Premiere bin root voor een folder sync
    func updateFolderSyncBinRoot(syncId: UUID, binRoot: String) {
        guard let index = config.folderSyncs.firstIndex(where: { $0.id == syncId }) else { return }
        
        config.folderSyncs[index].premiereBinRoot = binRoot
        saveConfig()
        
        print("AppState: Folder sync bin root bijgewerkt: \(binRoot)")
    }
    
    /// Forceer een volledige sync voor een map
    func forceFolderSync(syncId: UUID) {
        guard let sync = config.folderSyncs.first(where: { $0.id == syncId }) else { return }
        
        Task {
            await folderSyncWatcher.forceFullSync(sync: sync)
        }
    }
}

