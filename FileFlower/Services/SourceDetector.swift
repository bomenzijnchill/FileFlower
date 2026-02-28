import Foundation

/// Resultaat van bron-detectie
struct SourceDetectionResult {
    var source: DetectedSource
    var assetType: AssetType?
    var confidence: DetectionConfidence
    
    // Gescrapete genre/mood van de website (optioneel)
    var scrapedGenre: String?
    var scrapedMood: String?
    var originUrl: String?
    var sfxCategory: String?  // SFX categorie (bijv. "Swooshes", "Impacts")
    
    /// Of de detectie succesvol was en we kunnen skippen naar MLX
    var shouldSkipMLX: Bool {
        return assetType != nil && confidence == .high
    }
    
    init(source: DetectedSource, assetType: AssetType?, confidence: DetectionConfidence,
         scrapedGenre: String? = nil, scrapedMood: String? = nil, originUrl: String? = nil, sfxCategory: String? = nil) {
        self.source = source
        self.assetType = assetType
        self.confidence = confidence
        self.scrapedGenre = scrapedGenre
        self.scrapedMood = scrapedMood
        self.originUrl = originUrl
        self.sfxCategory = sfxCategory
    }
}

/// Gedetecteerde bron van het bestand
enum DetectedSource: String, Codable {
    case epidemicSound = "Epidemic Sound"
    case artlist = "Artlist"
    case freesound = "Freesound"
    case adobeStock = "Adobe Stock"
    case shutterstock = "Shutterstock"
    case iStock = "iStock"
    case gettyImages = "Getty Images"
    case pond5 = "Pond5"
    case depositphotos = "Depositphotos"
    case youtube4K = "YouTube 4K"
    case unknown = "Unknown"
}

/// Zekerheid van de detectie
enum DetectionConfidence {
    case high    // 100% zeker - harde regels (prefix/pattern match)
    case medium  // Redelijk zeker - soft heuristiek
    case low     // Onzeker
}

/// Service voor het detecteren van de bron van gedownloade bestanden
/// Dit gebeurt VOOR de MLX classificatie om snel te kunnen classificeren zonder AI
class SourceDetector {
    static let shared = SourceDetector()
    
    private init() {}
    
    /// Detecteer de bron en mogelijk type van een bestand
    /// - Parameters:
    ///   - url: URL van het bestand
    ///   - metadata: Eventuele metadata van het bestand
    /// - Returns: SourceDetectionResult met bron, type en zekerheid
    func detect(url: URL, metadata: DownloadMetadata? = nil) -> SourceDetectionResult {
        let filename = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        
        // 0. Check 4K Video Downloader (pad-gebaseerde detectie - hoogste prioriteit)
        if let result = detectYoutube4K(url: url, ext: ext) {
            return result
        }
        
        // 1. Check Epidemic Sound (hoogste prioriteit - zeer betrouwbaar)
        if let result = detectEpidemicSound(filename: filename, ext: ext) {
            return result
        }
        
        // 2. Check Freesound (100% betrouwbaar pattern)
        if let result = detectFreesound(filename: filename, ext: ext) {
            return result
        }
        
        // 3. Check stock platforms met harde prefix-IDs
        if let result = detectStockPlatform(filename: filename, ext: ext) {
            return result
        }
        
        // 4. Check Artlist via metadata (extended attributes)
        if let result = detectArtlist(url: url, filename: filename, ext: ext) {
            return result
        }
        
        // 5. Check metadata tags voor provider hints (bijv. "Licensed for video by Artlist.io")
        if let result = detectFromMetadataTags(metadata: metadata, filename: filename, ext: ext) {
            return result
        }
        
        // Geen bron gedetecteerd
        return SourceDetectionResult(source: .unknown, assetType: nil, confidence: .low)
    }
    
    // MARK: - YouTube 4K Video Downloader Detection
    
    /// Detecteer bestanden uit de 4K Video Downloader map
    /// Dit is pad-gebaseerde detectie - geen origin URL nodig
    private func detectYoutube4K(url: URL, ext: String) -> SourceDetectionResult? {
        let config = AppState.shared.config
        
        // Haal de 4K downloader folder uit config
        guard let youtube4KFolder = config.youtube4KDownloaderFolder else { return nil }
        
        // Check of het bestand in de 4K Video Downloader map staat
        let filePath = url.path
        guard filePath.hasPrefix(youtube4KFolder) else { return nil }
        
        #if DEBUG
        print("SourceDetector: YouTube 4K gedetecteerd (pad: \(youtube4KFolder))")
        #endif
        
        // Bepaal asset type op basis van extensie
        let videoExts = ["mp4", "mov", "avi", "mkv", "webm", "m4v"]
        let audioExts = ["mp3", "m4a", "wav", "aac", "ogg", "flac"]
        
        var assetType: AssetType = .stockFootage  // Default voor video
        if audioExts.contains(ext) {
            assetType = .music  // Audio van YouTube is vaak muziek
        } else if !videoExts.contains(ext) {
            assetType = .unknown
        }
        
        return SourceDetectionResult(
            source: .youtube4K,
            assetType: assetType,
            confidence: .high
        )
    }
    
    // MARK: - Metadata Tags Detection
    
    /// Detecteer provider via metadata tags (bijv. "Licensed for video by Artlist.io")
    private func detectFromMetadataTags(metadata: DownloadMetadata?, filename: String, ext: String) -> SourceDetectionResult? {
        guard let meta = metadata else { return nil }
        
        // Check tags array
        for tag in meta.tags {
            let lower = tag.lowercased()
            
            // Artlist
            if lower.contains("artlist.io") || lower.contains("artlist") {
                #if DEBUG
                print("SourceDetector: Artlist gedetecteerd via metadata tags")
                #endif
                return SourceDetectionResult(
                    source: .artlist,
                    assetType: classifyArtlistType(filename: filename, ext: ext),
                    confidence: .high
                )
            }
            
            // Epidemic Sound
            if lower.contains("epidemicsound") || lower.contains("epidemic sound") {
                #if DEBUG
                print("SourceDetector: Epidemic Sound gedetecteerd via metadata tags")
                #endif
                let (esType, esConfidence) = classifyEpidemicSoundType(filename: filename, ext: ext)
                return SourceDetectionResult(
                    source: .epidemicSound,
                    assetType: esType,
                    confidence: esConfidence
                )
            }
        }
        
        // Check ook genre veld voor hints
        if let genre = meta.genre?.lowercased() {
            if genre.contains("artlist") {
                #if DEBUG
                print("SourceDetector: Artlist gedetecteerd via genre metadata")
                #endif
                return SourceDetectionResult(
                    source: .artlist,
                    assetType: classifyArtlistType(filename: filename, ext: ext),
                    confidence: .high
                )
            }
        }
        
        return nil
    }
    
    // MARK: - Epidemic Sound Detection
    
    /// Detecteer Epidemic Sound bestanden
    /// Patronen:
    /// - Prefix: ES_
    /// - Suffix: - Epidemic Sound (vóór extensie)
    private func detectEpidemicSound(filename: String, ext: String) -> SourceDetectionResult? {
        let nameWithoutExt = (filename as NSString).deletingPathExtension

        // Check ES_ prefix (meest voorkomend)
        if filename.hasPrefix("ES_") {
            #if DEBUG
            print("SourceDetector: Epidemic Sound gedetecteerd (ES_ prefix)")
            #endif
            let (assetType, confidence) = classifyEpidemicSoundType(filename: nameWithoutExt, ext: ext)
            return SourceDetectionResult(
                source: .epidemicSound,
                assetType: assetType,
                confidence: confidence
            )
        }

        // Check "- Epidemic Sound" suffix
        if nameWithoutExt.hasSuffix("- Epidemic Sound") {
            #if DEBUG
            print("SourceDetector: Epidemic Sound gedetecteerd (- Epidemic Sound suffix)")
            #endif
            let (assetType, confidence) = classifyEpidemicSoundType(filename: nameWithoutExt, ext: ext)
            return SourceDetectionResult(
                source: .epidemicSound,
                assetType: assetType,
                confidence: confidence
            )
        }

        return nil
    }

    /// Bepaal type voor Epidemic Sound bestand
    /// Geeft (assetType, confidence) terug — high als er een duidelijke keyword match is,
    /// medium als het een gok is zodat DirectClassifier ook kan meebeslissen
    private func classifyEpidemicSoundType(filename: String, ext: String) -> (AssetType?, DetectionConfidence) {
        let lower = filename.lowercased()

        // Audio extensies
        let audioExts = ["wav", "aiff", "mp3", "m4a", "aac", "flac", "ogg"]
        guard audioExts.contains(ext) else { return (nil, .low) }

        // SFX keywords in bestandsnaam
        let sfxKeywords = ["sfx", "sound effect", "effect", "impact", "whoosh",
                          "swoosh", "hit", "crash", "bang", "explosion",
                          "ambience", "ambient", "foley", "transition",
                          "wind", "rain", "thunder", "water", "fire", "wave",
                          "organic", "nature", "bird", "animal", "door",
                          "footstep", "click", "beep", "buzz", "alarm",
                          "siren", "horn", "bell", "knock", "creak",
                          "rumble", "static", "hum", "drone", "texture",
                          "riser", "downer", "stinger", "sweep"]

        for keyword in sfxKeywords {
            if lower.contains(keyword) {
                #if DEBUG
                print("SourceDetector: SFX keyword gevonden in bestandsnaam: \(keyword)")
                #endif
                return (.sfx, .high)
            }
        }

        // Geen duidelijke SFX indicator — gebruik medium confidence zodat
        // DirectClassifier metadata (duration, BPM, etc.) kan checken
        return (.music, .medium)
    }
    
    // MARK: - Freesound Detection
    
    /// Detecteer Freesound bestanden
    /// Pattern: <ID>__<username>__<soundname>.wav
    /// Voorbeeld: 123456__user__impact.wav
    private func detectFreesound(filename: String, ext: String) -> SourceDetectionResult? {
        let nameWithoutExt = (filename as NSString).deletingPathExtension
        
        // Freesound pattern: nummer__username__naam
        let components = nameWithoutExt.components(separatedBy: "__")
        
        // Moet exact 3 delen hebben
        guard components.count >= 3 else { return nil }
        
        // Eerste deel moet een nummer zijn (Freesound ID)
        let firstPart = components[0]
        guard !firstPart.isEmpty, firstPart.allSatisfy({ $0.isNumber }) else { return nil }
        
        #if DEBUG
        print("SourceDetector: Freesound gedetecteerd (ID: \(firstPart))")
        #endif
        
        // Freesound is altijd SFX
        return SourceDetectionResult(
            source: .freesound,
            assetType: .sfx,
            confidence: .high
        )
    }
    
    // MARK: - Stock Platform Detection
    
    /// Detecteer stock platforms met harde prefix-IDs
    private func detectStockPlatform(filename: String, ext: String) -> SourceDetectionResult? {
        let lower = filename.lowercased()
        
        // Adobe Stock: AdobeStock_123456789
        if lower.hasPrefix("adobestock_") {
            #if DEBUG
            print("SourceDetector: Adobe Stock gedetecteerd")
            #endif
            return SourceDetectionResult(
                source: .adobeStock,
                assetType: classifyStockType(ext: ext),
                confidence: .high
            )
        }
        
        // Shutterstock: shutterstock_12345678
        if lower.hasPrefix("shutterstock_") {
            #if DEBUG
            print("SourceDetector: Shutterstock gedetecteerd")
            #endif
            return SourceDetectionResult(
                source: .shutterstock,
                assetType: classifyStockType(ext: ext),
                confidence: .high
            )
        }
        
        // iStock: istockphoto-12345678-*
        if lower.hasPrefix("istockphoto-") {
            #if DEBUG
            print("SourceDetector: iStock gedetecteerd")
            #endif
            return SourceDetectionResult(
                source: .iStock,
                assetType: classifyStockType(ext: ext),
                confidence: .high
            )
        }
        
        // Getty Images: gettyimages-12345678-*
        if lower.hasPrefix("gettyimages-") {
            #if DEBUG
            print("SourceDetector: Getty Images gedetecteerd")
            #endif
            return SourceDetectionResult(
                source: .gettyImages,
                assetType: classifyStockType(ext: ext),
                confidence: .high
            )
        }
        
        // Pond5: Pond5-12345678-name of pond5_12345678
        if lower.hasPrefix("pond5-") || lower.hasPrefix("pond5_") {
            #if DEBUG
            print("SourceDetector: Pond5 gedetecteerd")
            #endif
            return SourceDetectionResult(
                source: .pond5,
                assetType: classifyStockType(ext: ext),
                confidence: .high
            )
        }
        
        // Depositphotos: depositphotos_1234567-stock...
        if lower.hasPrefix("depositphotos_") {
            #if DEBUG
            print("SourceDetector: Depositphotos gedetecteerd")
            #endif
            return SourceDetectionResult(
                source: .depositphotos,
                assetType: classifyStockType(ext: ext),
                confidence: .high
            )
        }
        
        return nil
    }
    
    /// Bepaal type voor stock platforms op basis van extensie
    private func classifyStockType(ext: String) -> AssetType {
        let videoExts = ["mp4", "mov", "avi", "mxf", "mkv", "webm", "m4v"]
        let imageExts = ["png", "jpg", "jpeg", "svg", "psd", "gif", "webp", "tiff", "tif"]
        let audioExts = ["wav", "aiff", "mp3", "m4a", "aac", "flac", "ogg"]
        
        if videoExts.contains(ext) {
            return .stockFootage
        } else if imageExts.contains(ext) {
            return .graphic
        } else if audioExts.contains(ext) {
            // Stock audio is meestal SFX of muziek
            return .music
        }
        
        return .unknown
    }
    
    // MARK: - Artlist Detection
    
    /// Detecteer Artlist via metadata (extended attributes)
    /// Artlist zet "Origin: https://artlist.io/" in de metadata
    private func detectArtlist(url: URL, filename: String, ext: String) -> SourceDetectionResult? {
        // Check extended attributes voor origin URL
        if let originUrl = getOriginFromExtendedAttributes(url: url) {
            let lower = originUrl.lowercased()
            
            if lower.contains("artlist.io") {
                #if DEBUG
                print("SourceDetector: Artlist gedetecteerd via metadata")
                #endif
                return SourceDetectionResult(
                    source: .artlist,
                    assetType: classifyArtlistType(filename: filename, ext: ext),
                    confidence: .high
                )
            }
        }
        
        return nil
    }
    
    /// Haal origin URL uit extended attributes (macOS)
    private func getOriginFromExtendedAttributes(url: URL) -> String? {
        // Check com.apple.metadata:kMDItemWhereFroms
        let attributeName = "com.apple.metadata:kMDItemWhereFroms"
        
        // Get size of attribute
        let size = getxattr(url.path, attributeName, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        
        // Read attribute data
        var data = [UInt8](repeating: 0, count: size)
        let result = getxattr(url.path, attributeName, &data, size, 0, 0)
        guard result > 0 else { return nil }
        
        // Parse plist data
        let nsData = Data(data)
        if let plist = try? PropertyListSerialization.propertyList(from: nsData, options: [], format: nil),
           let urls = plist as? [String] {
            // Zoek naar scrapable trackpagina URL (niet CDN/download URLs)
            // Prioriteit: trackpagina > andere URLs
            
            // Artlist trackpagina: artlist.io/royalty-free-music/song/...
            for urlString in urls {
                let lower = urlString.lowercased()
                if (lower.contains("artlist.io/royalty-free-music/song/") ||
                    lower.contains("artlist.io/song/")) &&
                   !lower.contains("cms-artifacts") {
                    #if DEBUG
                    print("SourceDetector: Gevonden Artlist trackpagina URL")
                    #endif
                    return urlString
                }
            }
            
            // Epidemic Sound trackpagina: epidemicsound.com/track/...
            for urlString in urls {
                let lower = urlString.lowercased()
                if lower.contains("epidemicsound.com/track/") {
                    #if DEBUG
                    print("SourceDetector: Gevonden Epidemic Sound trackpagina URL")
                    #endif
                    return urlString
                }
            }
            
            // Zoek naar andere provider URLs met meer specifieke paden
            for urlString in urls {
                let lower = urlString.lowercased()
                // Skip CDN/download URLs
                if lower.contains("cms-artifacts") ||
                   lower.contains("cdn.") ||
                   lower.contains("/download") ||
                   lower.contains(".wav?") ||
                   lower.contains(".mp3?") ||
                   lower.contains("?d=true") {
                    #if DEBUG
                    print("SourceDetector: Skipping CDN/download URL: \(urlString.prefix(60))...")
                    #endif
                    continue
                }
                // Skip root URLs zonder specifiek pad
                if urlString == "https://artlist.io/" || 
                   urlString == "https://artlist.io" ||
                   urlString == "https://www.artlist.io/" ||
                   urlString == "https://www.artlist.io" {
                    #if DEBUG
                    print("SourceDetector: Skipping root URL (geen trackpagina): \(urlString)")
                    #endif
                    continue
                }
                // Return URL met meer specifiek pad
                #if DEBUG
                print("SourceDetector: Gevonden provider URL: \(urlString)")
                #endif
                return urlString
            }
            
            // Geen goede URL gevonden - log waarom
            #if DEBUG
            print("SourceDetector: Geen scrapable trackpagina URL gevonden in extended attributes")
            print("SourceDetector: De browser slaat alleen de CDN download URL of homepage op, niet de trackpagina")
            #endif
            return nil
        }
        
        return nil
    }
    
    /// Haal ALLE origin URLs uit extended attributes (voor debugging)
    func getAllOriginURLs(url: URL) -> [String] {
        let attributeName = "com.apple.metadata:kMDItemWhereFroms"
        
        let size = getxattr(url.path, attributeName, nil, 0, 0, 0)
        guard size > 0 else { return [] }
        
        var data = [UInt8](repeating: 0, count: size)
        let result = getxattr(url.path, attributeName, &data, size, 0, 0)
        guard result > 0 else { return [] }
        
        let nsData = Data(data)
        if let plist = try? PropertyListSerialization.propertyList(from: nsData, options: [], format: nil),
           let urls = plist as? [String] {
            return urls
        }
        
        return []
    }
    
    /// Bepaal type voor Artlist bestand
    private func classifyArtlistType(filename: String, ext: String) -> AssetType? {
        let lower = filename.lowercased()
        let audioExts = ["wav", "aiff", "mp3", "m4a", "aac", "flac", "ogg"]
        
        guard audioExts.contains(ext) else { return nil }
        
        // Check voor SFX indicators in bestandsnaam
        let sfxKeywords = ["sfx", "sound effect", "effect", "impact", "whoosh",
                          "swoosh", "hit", "crash", "foley", "ambient"]
        
        for keyword in sfxKeywords {
            if lower.contains(keyword) {
                return .sfx
            }
        }
        
        // Default voor Artlist audio is Music
        return .music
    }
    
    // MARK: - Async Detection with Chrome Extension Metadata
    
    /// Detecteer bron en haal genre/mood uit de Chrome extensie metadata cache
    /// - Parameters:
    ///   - url: URL van het bestand
    ///   - metadata: Eventuele metadata van het bestand
    ///   - enableScraping: Of metadata lookup ingeschakeld moet worden (nu via Chrome extensie)
    /// - Returns: SourceDetectionResult met bron, type, en optioneel genre/mood
    func detectWithScraping(url: URL, metadata: DownloadMetadata? = nil, enableScraping: Bool = true) async -> SourceDetectionResult {
        // Eerst normale detectie
        var result = detect(url: url, metadata: metadata)
        
        // Check of metadata lookup is ingeschakeld
        guard enableScraping else {
            return result
        }
        
        // Haal origin URLs op
        let allUrls = getAllOriginURLs(url: url)
        #if DEBUG
        if !allUrls.isEmpty {
            print("SourceDetector: Alle origin URLs voor \(url.lastPathComponent):")
            for (index, originUrl) in allUrls.enumerated() {
                print("  [\(index)] \(originUrl)")
            }
        }
        #endif
        
        // ============================================================================
        // NIEUW: Zoek metadata in de Chrome extensie cache
        // ============================================================================
        if let stockMeta = await StockMetadataCache.shared.findForFile(url: url, originUrls: allUrls) {
            #if DEBUG
            print("SourceDetector: Chrome extensie metadata gevonden voor '\(stockMeta.title ?? "unknown")'")
            #endif

            // Haal de origin URL uit de metadata
            if let pageUrl = stockMeta.pageUrl {
                result.originUrl = pageUrl
                
                // ============================================================
                // SFX DETECTIE: Check of de URL aangeeft dat het een SFX is
                // Ondersteunde URL patterns:
                // - /sound-effects/ (Epidemic Sound, Artlist)
                // - /sound-design/ (BMG Production Music)
                // - /sfx/ (diverse platforms)
                // ============================================================
                let isSfxUrl = pageUrl.contains("/sound-effects/") || 
                               pageUrl.contains("/sound-design/") || 
                               pageUrl.contains("/sfx/")
                
                // Check ook genres voor SFX indicatoren
                let sfxGenres = ["sound-design", "sfx", "sound effect", "sound effects", "foley", "ambience", "ambient"]
                let hasSfxGenre = stockMeta.genres?.contains(where: { genre in
                    sfxGenres.contains(where: { sfxKeyword in genre.lowercased().contains(sfxKeyword) })
                }) ?? false
                
                if isSfxUrl || hasSfxGenre {
                    // Dit is een SFX, niet muziek!
                    result.assetType = .sfx
                    result.confidence = .high  // BELANGRIJK: Zorgt ervoor dat MLX geskipt wordt
                    #if DEBUG
                    print("SourceDetector: SFX gedetecteerd via \(isSfxUrl ? "pageUrl" : "genre"): \(pageUrl)")
                    #endif
                    
                    // Extraheer de SFX categorie uit de URL of genres
                    if let category = extractSfxCategory(from: pageUrl) {
                        result.sfxCategory = category
                        #if DEBUG
                        print("SourceDetector: SFX categorie uit URL: \(category)")
                        #endif
                    } else if let genres = stockMeta.genres, !genres.isEmpty {
                        // Gebruik eerste genre (niet sound-design/sfx) als categorie
                        let filteredGenres = genres.filter { !sfxGenres.contains($0.lowercased()) }
                        if let category = filteredGenres.first {
                            result.sfxCategory = category.capitalized
                            #if DEBUG
                            print("SourceDetector: SFX categorie uit genres: \(category.capitalized)")
                            #endif
                        }
                    } else if let title = stockMeta.title, !title.lowercased().contains("sound effect") {
                        // Gebruik het eerste komma-gescheiden descriptor als categorie
                        // "Crowds, Applause, Medium Audience, Short" → "Crowds"
                        let firstDescriptor = title.split(separator: ",").first
                            .map { $0.trimmingCharacters(in: .whitespaces) } ?? title
                        result.sfxCategory = firstDescriptor
                        #if DEBUG
                        print("SourceDetector: SFX categorie uit title (eerste descriptor): \(firstDescriptor)")
                        #endif
                    }
                } else {
                    // Muziek - zet assetType en confidence
                    result.assetType = .music
                    result.confidence = .high  // BELANGRIJK: Zorgt ervoor dat MLX geskipt wordt
                    
                    // Gebruik de eerste genre/mood
                    if let genre = stockMeta.primaryGenre {
                        result.scrapedGenre = genre
                        #if DEBUG
                        print("SourceDetector: Genre uit Chrome extensie: \(genre)")
                        #endif
                    } else {
                        // Fallback: probeer genre uit URL te halen
                        // URL format: /music/genres/jazz/ -> "Jazz"
                        if let genre = extractMusicGenreFromUrl(pageUrl) {
                            result.scrapedGenre = genre
                            #if DEBUG
                            print("SourceDetector: Genre uit URL (fallback): \(genre)")
                            #endif
                        }
                    }
                    
                    if let mood = stockMeta.primaryMood {
                        result.scrapedMood = mood
                        #if DEBUG
                        print("SourceDetector: Mood uit Chrome extensie: \(mood)")
                        #endif
                    } else {
                        // Fallback: probeer mood uit URL te halen
                        // URL format: /music/moods/happy/ -> "Happy"
                        if let mood = extractMusicMoodFromUrl(pageUrl) {
                            result.scrapedMood = mood
                            #if DEBUG
                            print("SourceDetector: Mood uit URL (fallback): \(mood)")
                            #endif
                        }
                    }
                }
                
                #if DEBUG
                print("SourceDetector: Chrome extensie metadata - shouldSkipMLX: \(result.shouldSkipMLX)")
                #endif
            } else {
                // Geen pageUrl - gebruik standaard genre/mood maar stel assetType nog steeds in
                result.assetType = .music  // Default voor audio zonder URL
                result.confidence = .high
                
                if let genre = stockMeta.primaryGenre {
                    result.scrapedGenre = genre
                    #if DEBUG
                    print("SourceDetector: Genre uit Chrome extensie: \(genre)")
                    #endif
                }
                if let mood = stockMeta.primaryMood {
                    result.scrapedMood = mood
                    #if DEBUG
                    print("SourceDetector: Mood uit Chrome extensie: \(mood)")
                    #endif
                }
            }

            return result
        }
        
        #if DEBUG
        print("SourceDetector: Geen Chrome extensie metadata gevonden voor \(url.lastPathComponent)")
        print("SourceDetector: Tip - Installeer de Chrome extensie voor automatische genre/mood detectie")
        #endif
        
        return result
    }
    
    // MARK: - Music Genre/Mood Extraction from URL
    
    /// Extraheer muziek genre uit een URL als fallback
    /// URL format: /music/genres/jazz/ -> "Jazz"
    private func extractMusicGenreFromUrl(_ url: String) -> String? {
        guard let urlObj = URL(string: url) else { return nil }
        
        let path = urlObj.path.lowercased()
        
        // Check of dit een genre pagina is
        guard path.contains("/genres/") else { return nil }
        
        // Extraheer de genre uit het pad
        let components = urlObj.pathComponents
        if let genreIndex = components.firstIndex(of: "genres"),
           genreIndex + 1 < components.count {
            let genre = components[genreIndex + 1]
            if !genre.isEmpty && genre != "/" {
                let prettyGenre = genre.replacingOccurrences(of: "-", with: " ").capitalized
                return prettyGenre
            }
        }
        
        return nil
    }
    
    /// Extraheer muziek mood uit een URL als fallback
    /// URL format: /music/moods/happy/ -> "Happy"
    private func extractMusicMoodFromUrl(_ url: String) -> String? {
        guard let urlObj = URL(string: url) else { return nil }
        
        let path = urlObj.path.lowercased()
        
        // Check of dit een mood pagina is
        guard path.contains("/moods/") else { return nil }
        
        // Extraheer de mood uit het pad
        let components = urlObj.pathComponents
        if let moodIndex = components.firstIndex(of: "moods"),
           moodIndex + 1 < components.count {
            let mood = components[moodIndex + 1]
            if !mood.isEmpty && mood != "/" {
                let prettyMood = mood.replacingOccurrences(of: "-", with: " ").capitalized
                return prettyMood
            }
        }
        
        return nil
    }
    
    // MARK: - SFX Category Extraction
    
    /// Extraheer SFX categorie uit een URL
    /// URL format: /sound-effects/categories/designed/riser/ -> "Riser" (meest specifieke categorie)
    /// URL format: /sound-effects/categories/swooshes/ -> "Swooshes"
    /// URL format: /sound-design/tracks?soundTerm=Drone -> "Drone" (BMG)
    private func extractSfxCategory(from url: String) -> String? {
        // Parse URL en haal pad-componenten op
        guard let urlObj = URL(string: url) else { return nil }
        
        // BMG format: /sound-design/tracks?soundTerm=Drone%20OR%20Rumble
        // Probeer eerst de soundTerm parameter te extraheren
        if let components = URLComponents(url: urlObj, resolvingAgainstBaseURL: false),
           let soundTerm = components.queryItems?.first(where: { $0.name == "soundTerm" })?.value {
            // soundTerm bevat "Drone OR Rumble" -> pak eerste term
            let terms = soundTerm.components(separatedBy: " OR ").first ?? soundTerm
            let category = terms.trimmingCharacters(in: .whitespaces).capitalized
            #if DEBUG
            print("SourceDetector: Geëxtraheerde SFX categorie '\(category)' uit soundTerm parameter")
            #endif
            return category
        }
        
        let pathComponents = urlObj.pathComponents.filter { component in
            // Filter lege strings, slashes en niet-categorie paden
            !component.isEmpty && 
            component != "/" && 
            component != "sound-effects" && 
            component != "sound-design" &&
            component != "categories" &&
            component != "tracks" &&
            component != "search"
        }
        
        // Pak de LAATSTE component (meest specifieke categorie)
        // Bijv: /categories/designed/riser/ -> ["designed", "riser"] -> "riser"
        guard let lastCategory = pathComponents.last, !lastCategory.isEmpty else {
            return nil
        }

        // Filter UUID-achtige componenten (bijv. 70bb6d68-b1aa-4788-9b08-2306803e8abc)
        // Epidemic Sound track URLs bevatten alleen een UUID als pad-component
        if lastCategory.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            #if DEBUG
            print("SourceDetector: SFX pad-component is een UUID, skip: \(lastCategory)")
            #endif
            return nil
        }

        // Filter ook taalcodes zoals "en-nl"
        if lastCategory.contains("-") && lastCategory.count <= 5 {
            return nil
        }
        
        // Maak de categorie mooi: riser -> Riser, low-frequency -> Low Frequency
        var category = lastCategory.replacingOccurrences(of: "-", with: " ")
        category = category.capitalized
        
        #if DEBUG
        print("SourceDetector: Geëxtraheerde SFX categorie '\(category)' uit URL pad: \(pathComponents.joined(separator: " > "))")
        #endif
        
        return category
    }
    
}
