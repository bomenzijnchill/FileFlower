import Foundation
import CoreServices
import CryptoKit

/// Service die mappen monitort voor FolderSync en bestanden synchroniseert naar Premiere
class FolderSyncWatcher {
    static let shared = FolderSyncWatcher()
    
    // Callback wanneer sync status verandert
    var onStatusChange: ((UUID, FolderSyncStatus) -> Void)?
    
    // Actieve FSEvent streams per folder sync ID
    private var streams: [UUID: FSEventStreamRef] = [:]
    
    // Tracking van verwerkte bestanden per sync
    private var processedFiles: [UUID: Set<String>] = [:]
    
    // Serial queue voor thread-safe access
    private let accessQueue = DispatchQueue(label: "com.dltopremiere.foldersyncwatcher.access", attributes: .concurrent)
    
    // Batch systeem voor real-time file events
    private var pendingFiles: [UUID: [URL]] = [:]
    private var batchTimers: [UUID: DispatchWorkItem] = [:]
    private let batchDelay: TimeInterval = 2.0 // Wacht 2 seconden om bestanden te batchen
    
    // MARK: - Toegestane bestandsformaten (zelfde als DownloadsWatcher)
    private let allowedExtensions: Set<String> = [
        // Audio formats
        "wav", "mp3", "aiff", "aif", "flac", "ogg", "m4a", "aac",
        // Video formats
        "mp4", "mov", "m4v", "mxf",
        // Image formats
        "jpg", "jpeg", "png", "webp", "tiff", "tif", "gif",
        // Motion graphics / templates
        "mogrt", "aep", "prproj", "drp", "fcpxml", "motion",
        // 3D / Animation / VFX assets
        "fbx", "obj", "glb", "gltf", "blend", "c4d",
        // LUTs / kleurprofielen
        "cube", "3dl",
        // Fonts
        "otf", "ttf"
    ]
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Start monitoring voor een folder sync
    func startWatching(sync: FolderSync) {
        guard sync.isEnabled else {
            print("FolderSyncWatcher: Sync \(sync.id) is uitgeschakeld, niet starten")
            return
        }
        
        // Stop bestaande stream als die er is
        stopWatching(syncId: sync.id)
        
        print("FolderSyncWatcher: Start monitoring voor map: \(sync.folderPath)")
        
        // Initialiseer processed files set met bestaande hashes
        accessQueue.async(flags: .barrier) {
            self.processedFiles[sync.id] = sync.syncedFileHashes
        }
        
        // Start FSEvents stream
        startFSEventStream(for: sync)
        
        // Voer initiële sync uit voor bestaande bestanden
        Task {
            await performInitialSync(sync: sync)
        }
    }
    
    /// Stop monitoring voor een folder sync
    func stopWatching(syncId: UUID) {
        guard let stream = streams[syncId] else { return }
        
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streams.removeValue(forKey: syncId)
        
        print("FolderSyncWatcher: Gestopt met monitoring voor sync: \(syncId)")
    }
    
    /// Stop alle actieve watchers
    func stopAll() {
        for syncId in streams.keys {
            stopWatching(syncId: syncId)
        }
    }
    
    /// Herstart een specifieke sync
    func restartSync(sync: FolderSync) {
        stopWatching(syncId: sync.id)
        if sync.isEnabled {
            startWatching(sync: sync)
        }
    }
    
    /// Forceer een volledige sync voor een map
    func forceFullSync(sync: FolderSync) async {
        // Clear processed files voor deze sync
        accessQueue.async(flags: .barrier) {
            self.processedFiles[sync.id] = []
        }
        
        await performInitialSync(sync: sync)
    }
    
    // MARK: - Private Methods
    
    private func startFSEventStream(for sync: FolderSync) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        // Sla sync ID op in user data (via wrapper class)
        let syncInfo = SyncInfo(syncId: sync.id, folderPath: sync.folderPath)
        context.info = Unmanaged.passRetained(syncInfo).toOpaque()
        
        let paths = [sync.folderPath] as CFArray
        let latency: CFTimeInterval = 1.0
        
        guard let stream = FSEventStreamCreate(
            nil,
            { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                guard let info = clientCallBackInfo else { return }
                let syncInfo = Unmanaged<SyncInfo>.fromOpaque(info).takeUnretainedValue()
                FolderSyncWatcher.shared.handleEvents(
                    syncId: syncInfo.syncId,
                    folderPath: syncInfo.folderPath,
                    numEvents: numEvents,
                    eventPaths: eventPaths,
                    eventFlags: eventFlags
                )
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            print("FolderSyncWatcher: ERROR - Failed to create FSEventStream")
            return
        }
        
        let queue = DispatchQueue(label: "com.dltopremiere.foldersync.\(sync.id)", qos: .utility)
        FSEventStreamSetDispatchQueue(stream, queue)
        
        if FSEventStreamStart(stream) {
            streams[sync.id] = stream
            print("FolderSyncWatcher: FSEventStream gestart voor: \(sync.folderPath)")
        } else {
            print("FolderSyncWatcher: ERROR - Failed to start FSEventStream")
        }
    }
    
    private func handleEvents(
        syncId: UUID,
        folderPath: String,
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
            return
        }
        
        var newFiles: [URL] = []
        
        for (index, path) in paths.enumerated() {
            let flags = eventFlags[index]
            
            // Check voor nieuwe of gewijzigde bestanden
            if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 ||
               flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 ||
               flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 {
                
                let url = URL(fileURLWithPath: path)
                
                // Skip hidden files en directories
                if url.lastPathComponent.hasPrefix(".") {
                    continue
                }
                
                // Check of het een bestand is (geen directory)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else {
                    continue
                }
                
                // Check extensie
                let ext = url.pathExtension.lowercased()
                guard !ext.isEmpty, allowedExtensions.contains(ext) else {
                    continue
                }
                
                newFiles.append(url)
            }
        }
        
        // Voeg bestanden toe aan de batch en start/reset timer
        if !newFiles.isEmpty {
            queueFilesForBatch(syncId: syncId, files: newFiles)
        }
    }
    
    /// Voeg bestanden toe aan de batch queue en start een timer
    private func queueFilesForBatch(syncId: UUID, files: [URL]) {
        accessQueue.async(flags: .barrier) {
            // Voeg bestanden toe aan pending lijst
            if self.pendingFiles[syncId] == nil {
                self.pendingFiles[syncId] = []
            }
            self.pendingFiles[syncId]?.append(contentsOf: files)
            
            // Cancel bestaande timer
            self.batchTimers[syncId]?.cancel()
            
            // Start nieuwe timer
            let workItem = DispatchWorkItem { [weak self] in
                self?.processPendingBatch(syncId: syncId)
            }
            self.batchTimers[syncId] = workItem
            
            DispatchQueue.main.asyncAfter(deadline: .now() + self.batchDelay, execute: workItem)
            
            print("FolderSyncWatcher: \(files.count) bestand(en) toegevoegd aan batch voor sync \(syncId), wachten op meer...")
        }
    }
    
    /// Verwerk alle pending bestanden voor een sync als batch
    private func processPendingBatch(syncId: UUID) {
        var filesToProcess: [URL] = []
        
        accessQueue.sync {
            filesToProcess = pendingFiles[syncId] ?? []
        }
        
        accessQueue.async(flags: .barrier) {
            self.pendingFiles[syncId] = []
            self.batchTimers[syncId] = nil
        }
        
        guard !filesToProcess.isEmpty else { return }
        
        // Haal sync configuratie op
        guard let sync = AppState.shared.config.folderSyncs.first(where: { $0.id == syncId }) else {
            print("FolderSyncWatcher: Sync niet gevonden voor batch processing")
            return
        }
        
        print("FolderSyncWatcher: Verwerken batch van \(filesToProcess.count) bestanden")
        
        Task {
            await self.processBatch(files: filesToProcess, sync: sync)
        }
    }
    
    /// Verwerk een batch van bestanden
    private func processBatch(files: [URL], sync: FolderSync) async {
        let fileManager = FileManager.default
        var batchedFiles: [String: [(sourceURL: URL, targetURL: URL, targetDir: URL, fileHash: String)]] = [:]
        var syncedCount = 0
        
        for fileURL in files {
            // Bereken file hash voor duplicate detection
            let fileHash = calculateFileHash(url: fileURL)
            
            // Check of bestand al verwerkt is
            var alreadyProcessed = false
            accessQueue.sync {
                alreadyProcessed = processedFiles[sync.id]?.contains(fileHash) ?? false
            }
            
            if alreadyProcessed {
                continue
            }
            
            // Bereken relatief pad vanaf sync folder
            let syncFolderURL = URL(fileURLWithPath: sync.folderPath)
            let relativePath = fileURL.path.replacingOccurrences(of: syncFolderURL.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            
            // Bepaal target path in project
            guard let projectInfo = findProjectInfo(for: sync.projectPath) else {
                continue
            }
            
            // Bereken target directory
            let projectRootURL = URL(fileURLWithPath: projectInfo.rootPath)
            var targetDirURL: URL
            
            if sync.premiereBinRoot.isEmpty {
                targetDirURL = projectRootURL.appendingPathComponent(sync.folderName)
            } else {
                targetDirURL = projectRootURL.appendingPathComponent(sync.premiereBinRoot)
            }
            
            let relativeDir = URL(fileURLWithPath: relativePath).deletingLastPathComponent().path
            if !relativeDir.isEmpty && relativeDir != "." {
                targetDirURL = targetDirURL.appendingPathComponent(relativeDir)
            }
            
            let targetURL = targetDirURL.appendingPathComponent(fileURL.lastPathComponent)
            
            // Maak target directory aan en kopieer
            do {
                try fileManager.createDirectory(at: targetDirURL, withIntermediateDirectories: true)
                
                if !fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.copyItem(at: fileURL, to: targetURL)
                }
                
                try? Quarantine.removeQuarantineAttribute(from: targetURL)
                
                accessQueue.async(flags: .barrier) {
                    self.processedFiles[sync.id]?.insert(fileHash)
                }
                
                // Bereken Premiere bin path
                var premiereBinPath: String
                if sync.premiereBinRoot.isEmpty {
                    premiereBinPath = sync.folderName
                } else {
                    premiereBinPath = sync.premiereBinRoot
                }
                
                if !relativeDir.isEmpty && relativeDir != "." {
                    premiereBinPath += "/" + relativeDir
                }
                
                // Groepeer per bin path
                if batchedFiles[premiereBinPath] == nil {
                    batchedFiles[premiereBinPath] = []
                }
                batchedFiles[premiereBinPath]?.append((sourceURL: fileURL, targetURL: targetURL, targetDir: targetDirURL, fileHash: fileHash))
                
                syncedCount += 1
                
            } catch {
                print("FolderSyncWatcher: Fout bij batch verwerking: \(error)")
            }
        }
        
        // Update config
        await MainActor.run {
            if let index = AppState.shared.config.folderSyncs.firstIndex(where: { $0.id == sync.id }) {
                for (_, files) in batchedFiles {
                    for file in files {
                        AppState.shared.config.folderSyncs[index].syncedFileHashes.insert(file.fileHash)
                    }
                }
                AppState.shared.config.folderSyncs[index].lastSyncDate = Date()
                AppState.shared.saveConfig()
            }
            
            onStatusChange?(sync.id, .syncing(progress: 0.5, currentFile: "Importeren \(syncedCount) bestanden..."))
        }
        
        // Maak gebatchte jobs
        for (premiereBinPath, files) in batchedFiles {
            guard let firstFile = files.first else { continue }
            
            let job = JobRequest(
                projectPath: sync.projectPath,
                finderTargetDir: firstFile.targetDir.path,
                premiereBinPath: premiereBinPath,
                files: files.map { $0.targetURL.path }
            )
            
            JobServer.shared.addJob(job)
            print("FolderSyncWatcher: Batch job voor '\(premiereBinPath)' met \(files.count) bestanden")
        }
        
        await MainActor.run {
            onStatusChange?(sync.id, .completed(fileCount: syncedCount))
        }
    }
    
    /// Verzamel bestanden uit een enumerator (synchrone helper voor Swift 6 compatibiliteit)
    private nonisolated func collectFiles(from enumerator: FileManager.DirectoryEnumerator, allowedExtensions: Set<String>) -> [URL] {
        let fileManager = FileManager.default
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                continue
            }
            let ext = fileURL.pathExtension.lowercased()
            guard !ext.isEmpty, allowedExtensions.contains(ext) else {
                continue
            }
            files.append(fileURL)
        }
        return files
    }

    /// Voer initiële sync uit voor alle bestaande bestanden in de map
    private func performInitialSync(sync: FolderSync) async {
        let folderURL = URL(fileURLWithPath: sync.folderPath)
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("FolderSyncWatcher: Kon map niet enumereren: \(sync.folderPath)")
            await MainActor.run {
                onStatusChange?(sync.id, .error(message: "Kon map niet openen"))
            }
            return
        }
        
        // Verzamel alle bestanden (in synchrone context voor Swift 6 compatibiliteit)
        let extensions = allowedExtensions
        let filesToSync: [URL] = collectFiles(from: enumerator, allowedExtensions: extensions)
        
        print("FolderSyncWatcher: Gevonden \(filesToSync.count) bestanden voor initiële sync")
        
        if filesToSync.isEmpty {
            await MainActor.run {
                onStatusChange?(sync.id, .completed(fileCount: 0))
            }
            return
        }
        
        // Batch verwerking: groepeer bestanden per Premiere bin path
        var batchedFiles: [String: [(sourceURL: URL, targetURL: URL, targetDir: URL, fileHash: String)]] = [:]
        var syncedCount = 0
        
        for (index, fileURL) in filesToSync.enumerated() {
            let progress = Double(index + 1) / Double(filesToSync.count) * 0.5 // Eerste 50% voor kopiëren
            
            await MainActor.run {
                onStatusChange?(sync.id, .syncing(progress: progress, currentFile: "Kopiëren: \(fileURL.lastPathComponent)"))
            }
            
            // Bereken file hash voor duplicate detection
            let fileHash = calculateFileHash(url: fileURL)
            
            // Check of bestand al verwerkt is
            var alreadyProcessed = false
            accessQueue.sync {
                alreadyProcessed = processedFiles[sync.id]?.contains(fileHash) ?? false
            }
            
            if alreadyProcessed {
                print("FolderSyncWatcher: Skip \(fileURL.lastPathComponent) - al gesynchroniseerd")
                continue
            }
            
            // Bereken relatief pad vanaf sync folder
            let syncFolderURL = URL(fileURLWithPath: sync.folderPath)
            let relativePath = fileURL.path.replacingOccurrences(of: syncFolderURL.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            
            // Bepaal target path in project
            guard let projectInfo = findProjectInfo(for: sync.projectPath) else {
                print("FolderSyncWatcher: Kon project niet vinden: \(sync.projectPath)")
                continue
            }
            
            // Bereken target directory (spiegel folder structuur)
            let projectRootURL = URL(fileURLWithPath: projectInfo.rootPath)
            var targetDirURL: URL
            
            if sync.premiereBinRoot.isEmpty {
                targetDirURL = projectRootURL.appendingPathComponent(sync.folderName)
            } else {
                targetDirURL = projectRootURL.appendingPathComponent(sync.premiereBinRoot)
            }
            
            // Voeg relatief pad toe (subfolder structuur)
            let relativeDir = URL(fileURLWithPath: relativePath).deletingLastPathComponent().path
            if !relativeDir.isEmpty && relativeDir != "." {
                targetDirURL = targetDirURL.appendingPathComponent(relativeDir)
            }
            
            let targetURL = targetDirURL.appendingPathComponent(fileURL.lastPathComponent)
            
            // Maak target directory aan
            do {
                try fileManager.createDirectory(at: targetDirURL, withIntermediateDirectories: true)
            } catch {
                print("FolderSyncWatcher: Kon directory niet aanmaken: \(error)")
                continue
            }
            
            // Kopieer bestand
            do {
                if fileManager.fileExists(atPath: targetURL.path) {
                    print("FolderSyncWatcher: Bestand bestaat al: \(targetURL.lastPathComponent)")
                } else {
                    try fileManager.copyItem(at: fileURL, to: targetURL)
                    print("FolderSyncWatcher: Gekopieerd: \(fileURL.lastPathComponent)")
                }
                
                try? Quarantine.removeQuarantineAttribute(from: targetURL)
                
                // Markeer als verwerkt
                accessQueue.async(flags: .barrier) {
                    self.processedFiles[sync.id]?.insert(fileHash)
                }
                
                // Bereken Premiere bin path
                var premiereBinPath: String
                if sync.premiereBinRoot.isEmpty {
                    premiereBinPath = sync.folderName
                } else {
                    premiereBinPath = sync.premiereBinRoot
                }
                
                if !relativeDir.isEmpty && relativeDir != "." {
                    premiereBinPath += "/" + relativeDir
                }
                
                // Groepeer per bin path
                if batchedFiles[premiereBinPath] == nil {
                    batchedFiles[premiereBinPath] = []
                }
                batchedFiles[premiereBinPath]?.append((sourceURL: fileURL, targetURL: targetURL, targetDir: targetDirURL, fileHash: fileHash))
                
                syncedCount += 1
                
            } catch {
                print("FolderSyncWatcher: Fout bij kopiëren: \(error)")
            }
        }
        
        // Update config met alle hashes in één keer
        await MainActor.run {
            if let index = AppState.shared.config.folderSyncs.firstIndex(where: { $0.id == sync.id }) {
                for (_, files) in batchedFiles {
                    for file in files {
                        AppState.shared.config.folderSyncs[index].syncedFileHashes.insert(file.fileHash)
                    }
                }
                AppState.shared.config.folderSyncs[index].lastSyncDate = Date()
                AppState.shared.saveConfig()
            }
        }
        
        // Maak gebatchte jobs voor Premiere (één job per bin path)
        var binIndex = 0
        let totalBins = batchedFiles.count
        
        for (premiereBinPath, files) in batchedFiles {
            binIndex += 1
            let progress = 0.5 + (Double(binIndex) / Double(totalBins)) * 0.5 // Tweede 50% voor importeren
            
            await MainActor.run {
                onStatusChange?(sync.id, .syncing(progress: progress, currentFile: "Importeren naar \(premiereBinPath) (\(files.count) bestanden)"))
            }
            
            guard let firstFile = files.first else { continue }
            
            // Maak één job met alle bestanden voor deze bin
            let job = JobRequest(
                projectPath: sync.projectPath,
                finderTargetDir: firstFile.targetDir.path,
                premiereBinPath: premiereBinPath,
                files: files.map { $0.targetURL.path }
            )
            
            JobServer.shared.addJob(job)
            print("FolderSyncWatcher: Job aangemaakt voor bin '\(premiereBinPath)' met \(files.count) bestanden")
        }
        
        await MainActor.run {
            onStatusChange?(sync.id, .completed(fileCount: syncedCount))
        }
        
        print("FolderSyncWatcher: Initiële sync voltooid - \(syncedCount) bestanden in \(batchedFiles.count) batches")
    }
    
    /// Verwerk een enkel bestand
    @discardableResult
    private func processFile(url: URL, sync: FolderSync) async -> Bool {
        // Bereken file hash voor duplicate detection
        let fileHash = calculateFileHash(url: url)
        
        // Check of bestand al verwerkt is
        var alreadyProcessed = false
        accessQueue.sync {
            alreadyProcessed = processedFiles[sync.id]?.contains(fileHash) ?? false
        }
        
        if alreadyProcessed {
            print("FolderSyncWatcher: Skip \(url.lastPathComponent) - al gesynchroniseerd")
            return false
        }
        
        // Bereken relatief pad vanaf sync folder
        let syncFolderURL = URL(fileURLWithPath: sync.folderPath)
        let relativePath = url.path.replacingOccurrences(of: syncFolderURL.path, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // Bepaal target path in project
        guard let projectInfo = findProjectInfo(for: sync.projectPath) else {
            print("FolderSyncWatcher: Kon project niet vinden: \(sync.projectPath)")
            return false
        }
        
        // Bereken target directory (spiegel folder structuur)
        let projectRootURL = URL(fileURLWithPath: projectInfo.rootPath)
        var targetDirURL: URL
        
        if sync.premiereBinRoot.isEmpty {
            // Gebruik folder naam als bin root
            targetDirURL = projectRootURL.appendingPathComponent(sync.folderName)
        } else {
            targetDirURL = projectRootURL.appendingPathComponent(sync.premiereBinRoot)
        }
        
        // Voeg relatief pad toe (subfolder structuur)
        let relativeDir = URL(fileURLWithPath: relativePath).deletingLastPathComponent().path
        if !relativeDir.isEmpty && relativeDir != "." {
            targetDirURL = targetDirURL.appendingPathComponent(relativeDir)
        }
        
        let targetURL = targetDirURL.appendingPathComponent(url.lastPathComponent)
        
        // Maak target directory aan
        do {
            try FileManager.default.createDirectory(at: targetDirURL, withIntermediateDirectories: true)
        } catch {
            print("FolderSyncWatcher: Kon directory niet aanmaken: \(error)")
            return false
        }
        
        // Kopieer bestand (niet verplaatsen!)
        do {
            // Check of bestand al bestaat
            if FileManager.default.fileExists(atPath: targetURL.path) {
                print("FolderSyncWatcher: Bestand bestaat al: \(targetURL.lastPathComponent)")
            } else {
                try FileManager.default.copyItem(at: url, to: targetURL)
                print("FolderSyncWatcher: Gekopieerd: \(url.lastPathComponent) -> \(targetURL.path)")
            }
            
            // Remove quarantine
            try? Quarantine.removeQuarantineAttribute(from: targetURL)
            
            // Markeer als verwerkt
            accessQueue.async(flags: .barrier) {
                self.processedFiles[sync.id]?.insert(fileHash)
            }
            
            // Update config met nieuwe hash
            await MainActor.run {
                if let index = AppState.shared.config.folderSyncs.firstIndex(where: { $0.id == sync.id }) {
                    AppState.shared.config.folderSyncs[index].syncedFileHashes.insert(fileHash)
                    AppState.shared.config.folderSyncs[index].lastSyncDate = Date()
                    AppState.shared.saveConfig()
                }
            }
            
            // Bereken Premiere bin path
            var premiereBinPath: String
            if sync.premiereBinRoot.isEmpty {
                premiereBinPath = sync.folderName
            } else {
                premiereBinPath = sync.premiereBinRoot
            }
            
            if !relativeDir.isEmpty && relativeDir != "." {
                premiereBinPath += "/" + relativeDir
            }
            
            // Maak job voor Premiere
            let job = JobRequest(
                projectPath: sync.projectPath,
                finderTargetDir: targetDirURL.path,
                premiereBinPath: premiereBinPath,
                files: [targetURL.path]
            )
            
            JobServer.shared.addJob(job)
            
            return true
            
        } catch {
            print("FolderSyncWatcher: Fout bij kopiëren: \(error)")
            return false
        }
    }
    
    /// Bereken een hash van het bestand voor duplicate detection
    private func calculateFileHash(url: URL) -> String {
        // Gebruik bestandsnaam + grootte + modificatiedatum als snelle hash
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              let modDate = attrs[.modificationDate] as? Date else {
            return url.path
        }
        
        let identifier = "\(url.lastPathComponent)_\(size)_\(modDate.timeIntervalSince1970)"
        
        // SHA256 hash van identifier
        let data = Data(identifier.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Vind ProjectInfo voor een project path
    private func findProjectInfo(for projectPath: String) -> ProjectInfo? {
        // Zoek in recente projecten
        if let project = AppState.shared.recentProjects.first(where: { $0.projectPath == projectPath }) {
            return project
        }
        
        // Maak een nieuwe ProjectInfo aan
        let projectURL = URL(fileURLWithPath: projectPath)
        let projectName = projectURL.deletingPathExtension().lastPathComponent
        let rootPath = projectURL.deletingLastPathComponent().deletingLastPathComponent().path
        
        return ProjectInfo(
            name: projectName,
            rootPath: rootPath,
            projectPath: projectPath,
            lastModified: Date().timeIntervalSince1970
        )
    }
}

/// Helper class om sync info door te geven aan FSEvents callback
private class SyncInfo {
    let syncId: UUID
    let folderPath: String
    
    init(syncId: UUID, folderPath: String) {
        self.syncId = syncId
        self.folderPath = folderPath
    }
}




