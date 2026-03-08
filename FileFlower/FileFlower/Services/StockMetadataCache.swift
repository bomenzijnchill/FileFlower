import Foundation

/// Metadata ontvangen van de Chrome extensie
struct StockMetadata: Codable, Sendable {
    // Download info
    let downloadId: Int?
    let downloadUrl: String?
    let finalUrl: String?
    let filename: String?
    let fileSize: Int64?
    let startTime: String?
    
    // Track metadata
    let provider: String?
    let pageUrl: String?
    let title: String?
    let artists: [String]?
    let genres: [String]?
    let moods: [String]?
    let instruments: [String]?
    let videoThemes: [String]?
    let tags: [String]?
    let bpm: Int?
    let duration: Int?
    let album: String?
    let energy: String?
    
    // Meta
    let hasRichMetadata: Bool?
    let scrapedAt: String?
    let sentAt: String?
    
    /// Eerste genre (primair)
    nonisolated var primaryGenre: String? {
        genres?.first
    }
    
    /// Eerste mood (primair)
    nonisolated var primaryMood: String? {
        moods?.first
    }
    
    /// Eerste artist
    nonisolated var primaryArtist: String? {
        artists?.first
    }
    
    /// Geformatteerde bestandsnaam suggestie
    nonisolated var suggestedFilename: String? {
        guard let title = title else { return nil }
        
        if let artist = primaryArtist, !artist.isEmpty {
            return "\(artist) - \(title)"
        }
        return title
    }
}

/// Cache voor stock metadata van de Chrome extensie
/// Koppelt download URLs aan metadata zodat we bestanden kunnen organiseren
actor StockMetadataCache {
    static let shared = StockMetadataCache()
    
    /// Cache entry met timestamp
    private struct CacheEntry {
        let metadata: StockMetadata
        let receivedAt: Date
    }
    
    /// Cache op basis van download URL
    private var urlCache: [String: CacheEntry] = [:]
    
    /// Cache op basis van filename patterns
    private var filenameCache: [String: CacheEntry] = [:]
    
    /// Recente metadata (laatste 10 minuten)
    private var recentMetadata: [CacheEntry] = []
    
    /// Callbacks voor nieuwe metadata
    private var onMetadataReceivedCallbacks: [(StockMetadata) -> Void] = []
    
    private init() {}
    
    // MARK: - Public API
    
    /// Voeg metadata toe aan de cache (aangeroepen vanuit JobServer)
    func add(_ metadata: StockMetadata) {
        let entry = CacheEntry(metadata: metadata, receivedAt: Date())
        
        // Cache op URL
        if let url = metadata.downloadUrl {
            urlCache[normalizeUrl(url)] = entry
        }
        if let url = metadata.finalUrl {
            urlCache[normalizeUrl(url)] = entry
        }
        
        // Cache op filename
        if let filename = metadata.filename {
            let key = normalizeFilename(filename)
            filenameCache[key] = entry
        }
        
        // Voeg toe aan recente lijst
        recentMetadata.append(entry)
        
        // Log
        #if DEBUG
        print("StockMetadataCache: Metadata ontvangen voor '\(metadata.title ?? "unknown")' van \(metadata.provider ?? "unknown")")
        if let genres = metadata.genres, !genres.isEmpty {
            print("  Genres: \(genres.joined(separator: ", "))")
        }
        if let moods = metadata.moods, !moods.isEmpty {
            print("  Moods: \(moods.joined(separator: ", "))")
        }
        #endif
        
        // Notify callbacks
        for callback in onMetadataReceivedCallbacks {
            callback(metadata)
        }
        
        // Cleanup oude entries
        cleanupOldEntries()
    }
    
    /// Zoek metadata voor een download URL
    func findByUrl(_ url: String) -> StockMetadata? {
        let key = normalizeUrl(url)
        return urlCache[key]?.metadata
    }
    
    /// Zoek metadata voor een bestandsnaam
    func findByFilename(_ filename: String) -> StockMetadata? {
        let key = normalizeFilename(filename)
        
        // Exacte match
        if let entry = filenameCache[key] {
            return entry.metadata
        }
        
        // Fuzzy match - zoek in recente metadata
        for entry in recentMetadata.reversed() {
            if matchesFilename(entry.metadata, filename: filename) {
                return entry.metadata
            }
        }
        
        return nil
    }
    
    /// Zoek metadata voor een bestand (combineert URL en filename zoeken)
    func findForFile(url: URL, originUrls: [String] = []) -> StockMetadata? {
        // Probeer eerst op origin URLs
        for originUrl in originUrls {
            if let meta = findByUrl(originUrl) {
                #if DEBUG
                print("StockMetadataCache: Match gevonden op origin URL")
                #endif
                return meta
            }
        }
        
        // Probeer op filename
        let filename = url.lastPathComponent
        if let meta = findByFilename(filename) {
            #if DEBUG
            print("StockMetadataCache: Match gevonden op filename '\(filename)'")
            #endif
            return meta
        }
        
        // Geen match, maar check recente metadata (binnen 60 seconden)
        let recentCutoff = Date().addingTimeInterval(-60)
        for entry in recentMetadata.reversed() {
            if entry.receivedAt > recentCutoff {
                // Check of provider matcht met detected source
                #if DEBUG
                print("StockMetadataCache: Gebruiken van recente metadata (binnen 60s)")
                #endif
                return entry.metadata
            }
        }
        
        return nil
    }
    
    /// Registreer callback voor nieuwe metadata
    func onMetadataReceived(_ callback: @escaping (StockMetadata) -> Void) {
        onMetadataReceivedCallbacks.append(callback)
    }
    
    /// Haal statistieken op
    func getStats() -> (urlCacheCount: Int, filenameCacheCount: Int, recentCount: Int) {
        return (urlCache.count, filenameCache.count, recentMetadata.count)
    }
    
    // MARK: - Private helpers
    
    private func normalizeUrl(_ url: String) -> String {
        // Verwijder query parameters en fragments voor matching
        if let urlObj = URL(string: url) {
            var components = URLComponents(url: urlObj, resolvingAgainstBaseURL: false)
            components?.query = nil
            components?.fragment = nil
            return components?.string ?? url
        }
        return url
    }
    
    private func normalizeFilename(_ filename: String) -> String {
        // Lowercase, verwijder extensie en (1), (2) suffixes
        var name = filename.lowercased()
        
        // Verwijder extensie
        if let dotIndex = name.lastIndex(of: ".") {
            name = String(name[..<dotIndex])
        }
        
        // Verwijder (1), (2), etc.
        name = name.replacingOccurrences(of: #"\s*\(\d+\)\s*$"#, with: "", options: .regularExpression)
        
        return name.trimmingCharacters(in: .whitespaces)
    }
    
    private func matchesFilename(_ metadata: StockMetadata, filename: String) -> Bool {
        let normalizedInput = normalizeFilename(filename)
        
        // Check op metadata filename
        if let metaFilename = metadata.filename {
            if normalizeFilename(metaFilename) == normalizedInput {
                return true
            }
        }
        
        // Check op title + artist combinatie
        if let title = metadata.title?.lowercased() {
            // "Artist - Title" formaat
            if normalizedInput.contains(title) {
                return true
            }
            
            // Check ook omgekeerd
            if title.contains(normalizedInput.replacingOccurrences(of: " - ", with: " ")) {
                return true
            }
        }
        
        // Check suggestedFilename
        if let suggested = metadata.suggestedFilename {
            if normalizeFilename(suggested) == normalizedInput {
                return true
            }
        }
        
        return false
    }
    
    private func cleanupOldEntries() {
        let maxAge: TimeInterval = 10 * 60 // 10 minuten
        let cutoff = Date().addingTimeInterval(-maxAge)
        
        // Cleanup URL cache
        urlCache = urlCache.filter { $0.value.receivedAt > cutoff }
        
        // Cleanup filename cache
        filenameCache = filenameCache.filter { $0.value.receivedAt > cutoff }
        
        // Cleanup recent list
        recentMetadata = recentMetadata.filter { $0.receivedAt > cutoff }
    }
}




