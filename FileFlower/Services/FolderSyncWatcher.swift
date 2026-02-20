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
    
    /// Check of een sync actief gemonitord wordt
    func isWatching(syncId: UUID) -> Bool {
        return streams[syncId] != nil
    }

    /// Start monitoring voor een folder sync
    func startWatching(sync: FolderSync) {
        guard sync.isEnabled else {
            print("FolderSyncWatcher: Sync \(sync.id) is uitgeschakeld, niet starten")
            return
        }

        // Stop bestaande stream als die er is
        stopWatching(syncId: sync.id)

        print("FolderSyncWatcher: Start monitoring voor map: \(sync.folderPath)")

        // Initialiseer processed files set met bestaande hashes — NIET overschrijven als er al
        // in-flight hashes zijn (voorkomt dubbele syncs bij race condition)
        accessQueue.async(flags: .barrier) {
            if self.processedFiles[sync.id] == nil {
                self.processedFiles[sync.id] = sync.syncedFileHashes
            }
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
    
    /// Verwerk een batch van bestanden (geen kopiëren — bestanden staan al in de projectmap)
    private func processBatch(files: [URL], sync: FolderSync) async {
        var batchedFiles: [(sourceURL: URL, fileHash: String)] = []
        var syncedCount = 0

        // Bereken Premiere bin path (één keer, geldt voor hele batch)
        let premiereBinPath: String = sync.premiereBinRoot.isEmpty ? sync.folderName : sync.premiereBinRoot

        for fileURL in files {
            let fileHash = calculateFileHash(url: fileURL)

            var alreadyProcessed = false
            accessQueue.sync {
                alreadyProcessed = processedFiles[sync.id]?.contains(fileHash) ?? false
            }

            if alreadyProcessed {
                continue
            }

            // Markeer als in-flight zodat duplicaten binnen dezelfde sessie worden overgeslagen
            accessQueue.async(flags: .barrier) {
                self.processedFiles[sync.id]?.insert(fileHash)
            }

            batchedFiles.append((sourceURL: fileURL, fileHash: fileHash))
            syncedCount += 1
        }

        guard !batchedFiles.isEmpty else { return }

        await MainActor.run {
            onStatusChange?(sync.id, .syncing(progress: 0.5, currentFile: "Importeren \(syncedCount) bestanden..."))
        }

        // Maak job met pendingHashes — hashes worden pas opgeslagen na succesvolle import
        let job = JobRequest(
            projectPath: sync.projectPath,
            finderTargetDir: sync.folderPath,
            premiereBinPath: premiereBinPath,
            files: batchedFiles.map { $0.sourceURL.path },
            syncId: sync.id,
            pendingHashes: batchedFiles.map { $0.fileHash }
        )

        JobServer.shared.addJob(job)
        print("FolderSyncWatcher: Batch job voor '\(premiereBinPath)' met \(batchedFiles.count) bestanden")

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

    /// Voer initiële sync uit voor alle bestaande bestanden in de map (geen kopiëren)
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

        let extensions = allowedExtensions
        let filesToSync: [URL] = collectFiles(from: enumerator, allowedExtensions: extensions)

        print("FolderSyncWatcher: Gevonden \(filesToSync.count) bestanden voor initiële sync")

        if filesToSync.isEmpty {
            await MainActor.run {
                onStatusChange?(sync.id, .completed(fileCount: 0))
            }
            return
        }

        // Premiere bin path (één keer, geldt voor alle bestanden)
        let premiereBinPath: String = sync.premiereBinRoot.isEmpty ? sync.folderName : sync.premiereBinRoot

        var filePaths: [String] = []
        var fileHashes: [String] = []
        var syncedCount = 0

        for (index, fileURL) in filesToSync.enumerated() {
            let progress = Double(index + 1) / Double(filesToSync.count) * 0.8

            await MainActor.run {
                onStatusChange?(sync.id, .syncing(progress: progress, currentFile: fileURL.lastPathComponent))
            }

            let fileHash = calculateFileHash(url: fileURL)

            var alreadyProcessed = false
            accessQueue.sync {
                alreadyProcessed = processedFiles[sync.id]?.contains(fileHash) ?? false
            }

            if alreadyProcessed {
                print("FolderSyncWatcher: Skip \(fileURL.lastPathComponent) - al gesynchroniseerd")
                continue
            }

            // Markeer als in-flight
            accessQueue.async(flags: .barrier) {
                self.processedFiles[sync.id]?.insert(fileHash)
            }

            filePaths.append(fileURL.path)
            fileHashes.append(fileHash)
            syncedCount += 1
        }

        // Maak één job met alle bestanden en pendingHashes
        if !filePaths.isEmpty {
            await MainActor.run {
                onStatusChange?(sync.id, .syncing(progress: 0.9, currentFile: "Importeren naar \(premiereBinPath) (\(syncedCount) bestanden)"))
            }

            let job = JobRequest(
                projectPath: sync.projectPath,
                finderTargetDir: sync.folderPath,
                premiereBinPath: premiereBinPath,
                files: filePaths,
                syncId: sync.id,
                pendingHashes: fileHashes
            )

            JobServer.shared.addJob(job)
            print("FolderSyncWatcher: Job aangemaakt voor bin '\(premiereBinPath)' met \(syncedCount) bestanden")
        }

        await MainActor.run {
            onStatusChange?(sync.id, .completed(fileCount: syncedCount))
        }

        print("FolderSyncWatcher: Initiële sync voltooid - \(syncedCount) bestanden")
    }
    
    /// Verwerk een enkel bestand (geen kopiëren — gebruik origineel pad)
    @discardableResult
    private func processFile(url: URL, sync: FolderSync) async -> Bool {
        let fileHash = calculateFileHash(url: url)

        var alreadyProcessed = false
        accessQueue.sync {
            alreadyProcessed = processedFiles[sync.id]?.contains(fileHash) ?? false
        }

        if alreadyProcessed {
            print("FolderSyncWatcher: Skip \(url.lastPathComponent) - al gesynchroniseerd")
            return false
        }

        // Markeer als in-flight
        accessQueue.async(flags: .barrier) {
            self.processedFiles[sync.id]?.insert(fileHash)
        }

        // Premiere bin path
        let premiereBinPath: String = sync.premiereBinRoot.isEmpty ? sync.folderName : sync.premiereBinRoot

        // Maak job voor Premiere met pendingHashes
        let job = JobRequest(
            projectPath: sync.projectPath,
            finderTargetDir: sync.folderPath,
            premiereBinPath: premiereBinPath,
            files: [url.path],
            syncId: sync.id,
            pendingHashes: [fileHash]
        )

        JobServer.shared.addJob(job)
        return true
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




