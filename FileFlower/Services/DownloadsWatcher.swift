import Foundation
import CoreServices
import AppKit

class DownloadsWatcher {
    static let shared = DownloadsWatcher()
    
    var onNewFile: ((URL, String?) -> Void)?
    
    private var stream: FSEventStreamRef?
    private var youtube4KStream: FSEventStreamRef?  // Stream voor 4K Video Downloader map
    private var downloadsURL: URL
    private var youtube4KURL: URL?  // 4K Video Downloader map
    private var knownFiles: Set<String> = []
    private var processingFiles: Set<String> = []
    private var quarantineRetryCount: [String: Int] = [:]
    // Track which ZIP files we're currently extracting (to match folder names)
    private var extractingZips: Set<String> = []
    // Serial queue for thread-safe access to Sets
    private let accessQueue = DispatchQueue(label: "com.dltopremiere.downloadswatcher.access", attributes: .concurrent)
    
    // MARK: - Toegestane bestandsformaten
    // Alleen deze extensies worden verwerkt door de app
    private let allowedExtensions: Set<String> = [
        // Audio formats (muziek, SFX, VO)
        "wav", "mp3", "aiff", "aif", "flac", "ogg", "m4a", "aac",
        // Video formats (footage, stockshots, motion graphics)
        "mp4", "mov", "m4v", "mxf",
        // Image formats (stock images, thumbnails, design assets)
        "jpg", "jpeg", "png", "webp", "tiff", "tif", "gif",
        // Motion graphics / templates
        "mogrt", "aep", "prproj", "drp", "fcpxml", "motion",
        // 3D / Animation / VFX assets
        "fbx", "obj", "glb", "gltf", "blend", "c4d",
        // LUTs / kleurprofielen
        "cube", "3dl",
        // Fonts
        "otf", "ttf",
        // Compressed packs (worden uitgepakt en inhoud wordt gecontroleerd)
        "zip", "rar", "7z"
    ]
    
    private init() {
        // Gebruik standaard Downloads folder bij init
        // Custom folder wordt later geladen wanneer AppState klaar is
        downloadsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        loadKnownFiles()
    }
    
    func updateDownloadsFolder(_ url: URL) {
        // Stop huidige stream
        stop()
        
        // Update URL
        downloadsURL = url
        
        // Herstart stream
        start()
    }
    
    func loadCustomFolderIfNeeded(config: Config) {
        // Deze functie wordt aangeroepen nadat AppState is geïnitialiseerd
        // Config wordt doorgegeven om circulaire init te voorkomen
        if let customFolder = config.customDownloadsFolder {
            let customURL = URL(fileURLWithPath: customFolder)
            if customURL != downloadsURL {
                updateDownloadsFolder(customURL)
            }
        }
        
        // Start ook de 4K Video Downloader watcher als geconfigureerd
        if let youtube4KFolder = config.youtube4KDownloaderFolder {
            let youtube4KURL = URL(fileURLWithPath: youtube4KFolder)
            startYoutube4KWatcher(url: youtube4KURL)
        }
    }
    
    func start() {
        guard stream == nil else {
            print("DownloadsWatcher: Stream already started")
            return
        }
        
        print("DownloadsWatcher: Starting FSEvents stream for: \(downloadsURL.path)")
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let paths = [downloadsURL.path] as CFArray
        let latency: CFTimeInterval = 1.0
        
        stream = FSEventStreamCreate(
            nil,
            { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                guard let info = clientCallBackInfo else { return }
                let watcher = Unmanaged<DownloadsWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handleEvents(
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
        )
        
        guard let stream = stream else {
            print("DownloadsWatcher: ERROR - Failed to create FSEventStream")
            return
        }
        
        if #available(macOS 13.0, *) {
            let queue = DispatchQueue(label: "com.dltopremiere.fsevents", qos: .utility)
            FSEventStreamSetDispatchQueue(stream, queue)
        } else {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        
        let success = FSEventStreamStart(stream)
        if success {
            print("DownloadsWatcher: FSEventStream started successfully")
        } else {
            print("DownloadsWatcher: ERROR - Failed to start FSEventStream")
        }
    }
    
    func stop() {
        // Stop hoofdstream
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        
        // Stop 4K Video Downloader stream
        stopYoutube4KWatcher()
    }
    
    // MARK: - 4K Video Downloader Watcher
    
    /// Start de watcher voor de 4K Video Downloader map
    private func startYoutube4KWatcher(url: URL) {
        // Stop bestaande stream eerst
        stopYoutube4KWatcher()
        
        // Check of de map bestaat
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            print("DownloadsWatcher: 4K Video Downloader map bestaat niet: \(url.path)")
            return
        }
        
        self.youtube4KURL = url
        
        print("DownloadsWatcher: Starting FSEvents stream for 4K Video Downloader: \(url.path)")
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let paths = [url.path] as CFArray
        let latency: CFTimeInterval = 1.0
        
        youtube4KStream = FSEventStreamCreate(
            nil,
            { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                guard let info = clientCallBackInfo else { return }
                let watcher = Unmanaged<DownloadsWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handleYoutube4KEvents(
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
        )
        
        guard let youtube4KStream = youtube4KStream else {
            print("DownloadsWatcher: ERROR - Failed to create FSEventStream for 4K Video Downloader")
            return
        }
        
        if #available(macOS 13.0, *) {
            let queue = DispatchQueue(label: "com.dltopremiere.fsevents.youtube4k", qos: .utility)
            FSEventStreamSetDispatchQueue(youtube4KStream, queue)
        } else {
            FSEventStreamScheduleWithRunLoop(youtube4KStream, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        }
        
        let success = FSEventStreamStart(youtube4KStream)
        if success {
            print("DownloadsWatcher: 4K Video Downloader FSEventStream started successfully")
        } else {
            print("DownloadsWatcher: ERROR - Failed to start 4K Video Downloader FSEventStream")
        }
    }
    
    /// Stop de 4K Video Downloader watcher
    private func stopYoutube4KWatcher() {
        guard let stream = youtube4KStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.youtube4KStream = nil
        self.youtube4KURL = nil
    }
    
    /// Handle events van de 4K Video Downloader map
    private func handleYoutube4KEvents(
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
            print("DownloadsWatcher: ERROR - Failed to cast 4K event paths")
            return
        }
        
        print("DownloadsWatcher: Received \(numEvents) 4K Video Downloader events")
        
        for (index, path) in paths.enumerated() {
            let flags = eventFlags[index]
            
            if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 ||
               flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                print("DownloadsWatcher: 4K event for path: \(path)")
                checkYoutube4KFile(path: path)
            }
        }
    }
    
    /// Check een bestand uit de 4K Video Downloader map
    private func checkYoutube4KFile(path: String) {
        let url = URL(fileURLWithPath: path)
        
        // Skip hidden files and temp files
        if url.lastPathComponent.hasPrefix(".") || url.pathExtension == "download" {
            return
        }
        
        // Skip incomplete downloads
        let ext = url.pathExtension.lowercased()
        if ext == "part" || ext == "ytdl" || ext == "crdownload" {
            return
        }
        
        // Check if file exists and is not a directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return }
        
        // Skip directories
        if isDirectory.boolValue { return }
        
        // Check if file extension is allowed
        if !ext.isEmpty && !allowedExtensions.contains(ext) {
            print("DownloadsWatcher: Skipping 4K file \(url.lastPathComponent) - file type '\(ext)' not supported")
            return
        }
        
        // Thread-safe check if already known or currently processing
        var shouldSkip = false
        accessQueue.sync {
            if knownFiles.contains(path) || processingFiles.contains(path) {
                shouldSkip = true
            }
        }
        
        if shouldSkip {
            print("DownloadsWatcher: Skipping 4K file \(url.lastPathComponent) - already known or processing")
            return
        }
        
        print("DownloadsWatcher: Detected new 4K Video Downloader file: \(url.lastPathComponent)")
        
        // Thread-safe mark as processing
        accessQueue.async(flags: .barrier) {
            self.processingFiles.insert(path)
        }
        
        // Wait a bit for file to stabilize - run off main thread
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
            self.verifyAndProcessYoutube4KFile(url: url)
        }
    }
    
    /// Verify en process een 4K Video Downloader bestand
    private func verifyAndProcessYoutube4KFile(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("DownloadsWatcher: 4K file no longer exists: \(url.lastPathComponent)")
            accessQueue.async(flags: .barrier) {
                self.processingFiles.remove(url.path)
            }
            return
        }
        
        // Check if file is stable (not still downloading)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            print("DownloadsWatcher: Could not get 4K file attributes for: \(url.lastPathComponent)")
            accessQueue.async(flags: .barrier) {
                self.processingFiles.remove(url.path)
            }
            return
        }
        
        print("DownloadsWatcher: Checking 4K file stability for: \(url.lastPathComponent) (size: \(size))")
        
        // Check again after a delay to ensure size is stable
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("DownloadsWatcher: 4K file disappeared during stability check: \(url.lastPathComponent)")
                self.accessQueue.async(flags: .barrier) {
                    self.processingFiles.remove(url.path)
                }
                return
            }
            
            guard let newAttrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let newSize = newAttrs[.size] as? Int64 else {
                print("DownloadsWatcher: Could not get 4K file attributes during stability check: \(url.lastPathComponent)")
                self.accessQueue.async(flags: .barrier) {
                    self.processingFiles.remove(url.path)
                }
                return
            }
            
            if newSize != size {
                print("DownloadsWatcher: 4K file still downloading: \(url.lastPathComponent) (old: \(size), new: \(newSize))")
                // File is still downloading, check again later
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
                    self.verifyAndProcessYoutube4KFile(url: url)
                }
                return
            }
            
            print("DownloadsWatcher: 4K file is stable: \(url.lastPathComponent)")
            
            // 4K Video Downloader bestanden worden ALTIJD verwerkt (geen origin URL check nodig)
            // Ze komen uit een specifieke map, dus we weten dat ze van YouTube komen
            self.processFile(url: url, originURL: nil)
        }
    }
    
    private func handleEvents(
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
            print("DownloadsWatcher: ERROR - Failed to cast event paths")
            return
        }
        
        print("DownloadsWatcher: Received \(numEvents) events")
        
        for (index, path) in paths.enumerated() {
            let flags = eventFlags[index]
            
            if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 ||
               flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 {
                print("DownloadsWatcher: Event for path: \(path)")
                checkFile(path: path)
            }
        }
    }
    
    private func checkFile(path: String) {
        let url = URL(fileURLWithPath: path)
        
        // Skip hidden files and temp files
        if url.lastPathComponent.hasPrefix(".") || url.pathExtension == "download" {
            return
        }
        
        // Skip .crdownload files (Chrome partial downloads)
        if url.pathExtension.lowercased() == "crdownload" {
            return
        }
        
        // Check if file extension is allowed (skip check for directories)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        
        if exists && !isDir.boolValue {
            let ext = url.pathExtension.lowercased()
            if !ext.isEmpty && !allowedExtensions.contains(ext) {
                print("DownloadsWatcher: Skipping \(url.lastPathComponent) - file type '\(ext)' not supported")
                return
            }
        }
        
        // Check if this is a directory first, before checking if it's known
        var isDirectory: ObjCBool = false
        let pathExists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        
        // If this is a directory, check if it matches a ZIP we're extracting
        if pathExists && isDirectory.boolValue {
            if isExtractingZipFolder(path) {
                print("DownloadsWatcher: Skipping \(url.lastPathComponent) - folder matches ZIP we're extracting")
                // Mark folder and all files inside as known immediately
                accessQueue.async(flags: .barrier) {
                    self.knownFiles.insert(path)
                    // Also mark all files in the folder as known
                    if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
                        for fileURL in contents {
                            var isFile: ObjCBool = false
                            if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isFile),
                               !isFile.boolValue {
                                self.knownFiles.insert(fileURL.path)
                                self.processingFiles.remove(fileURL.path)
                            }
                        }
                    }
                }
                return
            }
        }
        
        // Thread-safe check if already known or currently processing
        var shouldSkip = false
        var isKnownMusicFolder = false
        accessQueue.sync {
            if knownFiles.contains(path) || processingFiles.contains(path) {
                shouldSkip = true
            }
            // Also check if this path itself is a known music folder (the folder itself)
            if pathExists && isDirectory.boolValue {
                isKnownMusicFolder = knownFiles.contains(path)
            }
        }
        
        // If this is a known music folder, skip it immediately
        if isKnownMusicFolder {
            print("DownloadsWatcher: Skipping \(url.lastPathComponent) - this is a known music folder")
            return
        }
        
        if shouldSkip {
            print("DownloadsWatcher: Skipping \(url.lastPathComponent) - already known or processing")
            return
        }
        
        // Check if this file/directory is inside a known music folder (to skip individual files in music ZIPs)
        let parentDir = url.deletingLastPathComponent()
        var isInKnownMusicFolder = false
        accessQueue.sync {
            isInKnownMusicFolder = knownFiles.contains(parentDir.path)
        }
        
        if isInKnownMusicFolder {
            print("DownloadsWatcher: Skipping \(url.lastPathComponent) - inside known music folder")
            // Mark this file as known to prevent further processing
            accessQueue.async(flags: .barrier) {
                self.knownFiles.insert(path)
            }
            return
        }
        
        print("DownloadsWatcher: Detected new file: \(url.lastPathComponent)")
        
        // Thread-safe mark as processing
        accessQueue.async(flags: .barrier) {
            self.processingFiles.insert(path)
        }
        
        // Wait a bit for file to stabilize - run off main thread
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) {
            self.verifyAndProcessFile(url: url)
        }
    }
    
    private func verifyAndProcessFile(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("DownloadsWatcher: File no longer exists: \(url.lastPathComponent)")
            accessQueue.async(flags: .barrier) {
                self.processingFiles.remove(url.path)
            }
            return
        }
        
        // Check if file is stable (not still downloading)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            print("DownloadsWatcher: Could not get file attributes for: \(url.lastPathComponent)")
            accessQueue.async(flags: .barrier) {
                self.processingFiles.remove(url.path)
            }
            return
        }
        
        print("DownloadsWatcher: Checking file stability for: \(url.lastPathComponent) (size: \(size))")
        
        // Check again after a delay to ensure size is stable - run off main thread
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.0) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                print("DownloadsWatcher: File disappeared during stability check: \(url.lastPathComponent)")
                self.accessQueue.async(flags: .barrier) {
                    self.processingFiles.remove(url.path)
                }
                return
            }
            
            guard let newAttrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let newSize = newAttrs[.size] as? Int64 else {
                print("DownloadsWatcher: Could not get file attributes during stability check: \(url.lastPathComponent)")
                self.accessQueue.async(flags: .barrier) {
                    self.processingFiles.remove(url.path)
                }
                return
            }
            
            if newSize != size {
                print("DownloadsWatcher: File still downloading: \(url.lastPathComponent) (old: \(size), new: \(newSize))")
                // File is still downloading, check again later
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.0) {
                    self.verifyAndProcessFile(url: url)
                }
                return
            }
            
            print("DownloadsWatcher: File is stable: \(url.lastPathComponent)")
            
            // Double-check if file/folder is still not known (might have been marked as known during stability check)
            var shouldSkip = false
            self.accessQueue.sync {
                if self.knownFiles.contains(url.path) {
                    shouldSkip = true
                }
            }
            
            if shouldSkip {
                print("DownloadsWatcher: Skipping \(url.lastPathComponent) - marked as known during stability check")
                self.accessQueue.async(flags: .barrier) {
                    self.processingFiles.remove(url.path)
                }
                return
            }
            
            // Check quarantine attribute asynchronously
            self.checkQuarantineAndProcess(url: url)
        }
    }
    
    private func checkQuarantineAndProcess(url: URL) {
        // Final check if file/folder is already known (might have been marked as known by ZIP extraction)
        // This check MUST happen FIRST, before any other processing
        var isKnown = false
        var isDirectory: ObjCBool = false
        let pathExists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        
        // If this is a directory, check if it matches a ZIP we're extracting
        if pathExists && isDirectory.boolValue {
            if isExtractingZipFolder(url.path) {
                print("DownloadsWatcher: Skipping directory \(url.lastPathComponent) - folder matches ZIP we're extracting")
                // Mark folder and all files inside as known immediately
                accessQueue.sync(flags: .barrier) {
                    self.knownFiles.insert(url.path)
                    self.processingFiles.remove(url.path)
                    // Also mark all files in the folder as known
                    if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
                        for fileURL in contents {
                            var isFile: ObjCBool = false
                            if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isFile),
                               !isFile.boolValue {
                                self.knownFiles.insert(fileURL.path)
                                self.processingFiles.remove(fileURL.path)
                            }
                        }
                    }
                }
                return
            }
        }
        
        accessQueue.sync {
            isKnown = knownFiles.contains(url.path)
        }
        
        // If this is a directory that's already known (e.g., from ZIP extraction), skip it immediately
        if isKnown {
            if pathExists && isDirectory.boolValue {
                print("DownloadsWatcher: Skipping directory \(url.lastPathComponent) - already known (likely from ZIP extraction)")
            } else {
                print("DownloadsWatcher: Skipping \(url.lastPathComponent) - already known (likely from ZIP extraction)")
            }
            accessQueue.async(flags: .barrier) {
                self.processingFiles.remove(url.path)
            }
            return
        }
        
        // Check if this is a directory that might be from a ZIP extraction
        // If it contains only audio files with similar names, it's likely a music ZIP folder
        // Reuse the isDirectory variable that was already checked above
        if pathExists && isDirectory.boolValue {
            // Check if this directory might be from a ZIP extraction (contains only audio files)
            if let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey]),
               !contents.isEmpty {
                let audioFiles = contents.filter { fileURL in
                    var isFile: ObjCBool = false
                    if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isFile),
                       !isFile.boolValue {
                        let ext = fileURL.pathExtension.lowercased()
                        return ["wav", "aiff", "mp3", "m4a", "aac", "flac", "ogg"].contains(ext)
                    }
                    return false
                }
                
                // If directory contains only audio files, check if they have STEMS in their names
                if audioFiles.count == contents.count && audioFiles.count > 1 {
                    let hasStems = audioFiles.contains { fileURL in
                        let fileName = fileURL.lastPathComponent.lowercased()
                        return fileName.contains("stems") || fileName.contains("stem") ||
                               fileName.contains("bass") || fileName.contains("drums") ||
                               fileName.contains("instruments") || fileName.contains("melody")
                    }
                    
                    if hasStems {
                        // This is likely a music ZIP folder - mark it as known and process it as one item
                        print("DownloadsWatcher: Detected music folder with STEMS - marking as known: \(url.lastPathComponent)")
                        accessQueue.sync(flags: .barrier) {
                            self.knownFiles.insert(url.path)
                            // Mark all files in the folder as known too
                            for fileURL in audioFiles {
                                self.knownFiles.insert(fileURL.path)
                            }
                        }
                        
                        // Process the folder as a single item
                        processFile(url: url, originURL: nil)
                        return
                    }
                }
            }
        }
        
        // Read origin URL from quarantine attributes
        let originURL = getOriginURL(from: url)
        print("DownloadsWatcher: Origin URL for \(url.lastPathComponent): \(originURL ?? "none")")
        
        // Check if we should process this file
        if shouldProcessFile(url: url, originURL: originURL) {
            // Check if it's a ZIP file and needs extraction
            if url.pathExtension.lowercased() == "zip" {
                extractZipAndProcess(url: url, originURL: originURL)
            } else {
                processFile(url: url, originURL: originURL)
            }
        } else {
            print("DownloadsWatcher: Skipping \(url.lastPathComponent) - not from stock website and Premiere Pro not running")
            self.accessQueue.async(flags: .barrier) {
                self.processingFiles.remove(url.path)
            }
        }
    }
    
    private func getOriginURL(from url: URL) -> String? {
        // Read origin URL from quarantine attributes using xattr
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-p", "com.apple.quarantine", url.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let quarantineString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    // Parse quarantine string format: flags;timestamp;agent;origin
                    // Origin can be at different positions, try to find URL pattern
                    let components = quarantineString.split(separator: ";")
                    
                    // Look for URL in any component
                    for component in components {
                        let componentString = String(component)
                        // Check if component contains a URL
                        if componentString.contains("http://") || componentString.contains("https://") {
                            // Extract URL - find start and end
                            if let httpRange = componentString.range(of: "http://") ?? componentString.range(of: "https://") {
                                var urlString = String(componentString[httpRange.lowerBound...])
                                // Remove any trailing characters that aren't part of URL
                                if let endIndex = urlString.firstIndex(where: { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" }) {
                                    urlString = String(urlString[..<endIndex])
                                }
                                return urlString
                            }
                        }
                    }
                }
            }
        } catch {
            // Ignore errors - origin URL is optional
        }
        
        return nil
    }
    
    private func shouldProcessFile(url: URL, originURL: String?) -> Bool {
        let config = AppState.shared.config
        
        // Always process if Premiere Pro is running
        if PremiereChecker.shared.isPremiereProRunning() {
            print("DownloadsWatcher: Premiere Pro is running - processing all downloads")
            return true
        }
        
        // Check if origin URL matches stock websites
        guard let origin = originURL?.lowercased() else {
            print("DownloadsWatcher: No origin URL found - skipping")
            return false
        }
        
        // Check blacklist first
        for blacklisted in config.blacklistedWebsites {
            if origin.contains(blacklisted.lowercased()) {
                print("DownloadsWatcher: Origin URL is blacklisted: \(blacklisted)")
                return false
            }
        }
        
        // Check if origin matches any stock website (standaard + custom)
        let allStockWebsites = config.stockWebsites
        for stockSite in allStockWebsites {
            if origin.contains(stockSite.lowercased()) {
                print("DownloadsWatcher: Origin URL matches stock website: \(stockSite)")
                // Track download detectie
                AnalyticsService.shared.track(.downloadDetected(
                    sourceWebsite: stockSite,
                    assetType: "unknown", // Wordt later geclassificeerd
                    fileExtension: ""
                ))
                AnalyticsService.shared.incrementDownloads()
                return true
            }
        }
        
        print("DownloadsWatcher: Origin URL does not match any stock website")
        return false
    }
    
    private func extractZipAndProcess(url: URL, originURL: String?) {
        print("DownloadsWatcher: Extracting ZIP file: \(url.lastPathComponent)")
        
        // Get the folder name BEFORE extraction so we can mark it as known
        let downloadsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let extractFolder = Unzipper.getExtractFolderName(for: url, in: downloadsDir)
        
        // Mark ZIP as extracting and pre-mark the folder as known BEFORE starting extraction
        // This prevents FSEvents from detecting the folder as a new file
        accessQueue.sync(flags: .barrier) {
            self.extractingZips.insert(url.path)
            // Pre-mark the folder as known so FSEvents skips it
            self.knownFiles.insert(extractFolder.path)
        }
        
        print("DownloadsWatcher: Pre-marked folder as known: \(extractFolder.lastPathComponent)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Check if ZIP contains only music files (WAV/MP3)
                let isMusicZip = Unzipper.containsOnlyMusic(url)
                print("DownloadsWatcher: ZIP contains only music: \(isMusicZip)")
                
                // Extract to Downloads
                let extractedFiles = try Unzipper.unzip(url, to: downloadsDir)
                
                print("DownloadsWatcher: Extracted \(extractedFiles.count) files from ZIP")
                
                // Mark all extracted files as known immediately
                self.accessQueue.sync(flags: .barrier) {
                    for extractedFile in extractedFiles {
                        self.processingFiles.remove(extractedFile.path)
                        self.knownFiles.insert(extractedFile.path)
                    }
                }
                
                print("DownloadsWatcher: Marked all \(extractedFiles.count) extracted files as known")
                
                if isMusicZip {
                    // For music ZIPs, treat the entire folder as one item
                    print("DownloadsWatcher: Music ZIP detected - treating folder as single item: \(extractFolder.lastPathComponent)")
                    
                    // Process the folder as a single item (use same origin URL as ZIP)
                    DispatchQueue.main.async {
                        print("DownloadsWatcher: Calling callback for music folder: \(extractFolder.lastPathComponent)")
                        if let callback = self.onNewFile {
                            callback(extractFolder, originURL)
                        }
                    }
                } else {
                    // For non-music ZIPs, process each extracted file individually
                    // But filter out files with unsupported extensions
                    let supportedFiles = extractedFiles.filter { fileURL in
                        let ext = fileURL.pathExtension.lowercased()
                        if ext.isEmpty {
                            return false
                        }
                        if self.allowedExtensions.contains(ext) {
                            return true
                        } else {
                            print("DownloadsWatcher: Skipping extracted file \(fileURL.lastPathComponent) - file type '\(ext)' not supported")
                            return false
                        }
                    }
                    
                    if supportedFiles.isEmpty {
                        print("DownloadsWatcher: Non-music ZIP contains no supported files - skipping")
                    } else {
                        print("DownloadsWatcher: Non-music ZIP - processing \(supportedFiles.count) supported files (skipped \(extractedFiles.count - supportedFiles.count) unsupported)")
                        
                        // Process each supported extracted file (use same origin URL as ZIP)
                        for extractedFile in supportedFiles {
                            DispatchQueue.main.async {
                                if let callback = self.onNewFile {
                                    callback(extractedFile, originURL)
                                }
                            }
                        }
                    }
                }
                
                // Remove the ZIP file after extraction
                try? FileManager.default.removeItem(at: url)
                
                self.accessQueue.async(flags: .barrier) {
                    self.processingFiles.remove(url.path)
                    // Remove from extracting set after extraction is complete
                    self.extractingZips.remove(url.path)
                }
            } catch {
                print("DownloadsWatcher: Failed to extract ZIP: \(error.localizedDescription)")
                // Remove from extracting set on error
                self.accessQueue.async(flags: .barrier) {
                    self.extractingZips.remove(url.path)
                    // Also remove pre-marked folder
                    self.knownFiles.remove(extractFolder.path)
                }
                // If extraction fails, try to process the ZIP itself
                self.processFile(url: url, originURL: originURL)
            }
        }
    }
    
    /// Check if a folder name matches a ZIP we're currently extracting
    private func isExtractingZipFolder(_ folderPath: String) -> Bool {
        let folderName = URL(fileURLWithPath: folderPath).lastPathComponent
        
        var isExtracting = false
        accessQueue.sync {
            // Check if any extracting ZIP has the same name (without .zip extension)
            for zipPath in extractingZips {
                let zipName = URL(fileURLWithPath: zipPath).deletingPathExtension().lastPathComponent
                if zipName == folderName {
                    isExtracting = true
                    break
                }
            }
        }
        
        return isExtracting
    }
    
    private func processFile(url: URL, originURL: String?) {
        // Thread-safe: Mark file as known and remove from processing
        self.accessQueue.async(flags: .barrier) {
            self.knownFiles.insert(url.path)
            self.processingFiles.remove(url.path)
            self.quarantineRetryCount.removeValue(forKey: url.path)
        }
        
        print("DownloadsWatcher: File ready: \(url.lastPathComponent)")
        
        // Call callback on main thread
        DispatchQueue.main.async {
            print("DownloadsWatcher: Calling onNewFile callback for: \(url.lastPathComponent)")
            guard let callback = self.onNewFile else {
                print("DownloadsWatcher: ERROR - onNewFile callback is nil!")
                return
            }
            callback(url, originURL)
            print("DownloadsWatcher: Callback completed for: \(url.lastPathComponent)")
        }
    }
    
    private func hasQuarantineAttribute(url: URL) -> Bool {
        // Simplified quarantine check - just skip it for now to avoid blocking
        // We'll process files even if they're quarantined, macOS will handle it
        // This prevents the app from hanging on quarantine checks
        return false
    }
    
    private func loadKnownFiles() {
        // Don't mark existing files as known - we only want to track files that were
        // processed after the app started. This allows the app to detect files that
        // were already in Downloads when the app starts.
        // Only mark files that we've already processed during this session
        // This is called during init, so it's safe to set directly
        knownFiles = Set<String>()
    }
}

