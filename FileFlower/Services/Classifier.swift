import Foundation
import UniformTypeIdentifiers
import AVFoundation
import ImageIO
import CoreGraphics
import CoreMedia

// Protocol for classification strategies - allows for future Core ML integration
protocol ClassificationStrategy {
    func classify(url: URL, uti: String?, metadata: DownloadMetadata?, originUrl: String?) async -> AssetType
}

// MARK: - DirectClassifier
// Snelle, synchrone classificatie zonder Python - voor instant resultaten

struct DirectClassificationResult {
    let assetType: AssetType?
    let confidence: DirectClassificationConfidence
    let reason: String
    
    var shouldSkipMLX: Bool {
        return assetType != nil && confidence == .high
    }
}

enum DirectClassificationConfidence {
    case high    // 100% zeker - skip MLX
    case medium  // Redelijk zeker - kan MLX overslaan maar genre/mood mist
    case low     // Onzeker - gebruik MLX
}

class DirectClassifier {
    static let shared = DirectClassifier()
    
    // Audio extensies
    private let audioExtensions = Set(["wav", "aiff", "aif", "mp3", "m4a", "aac", "flac", "ogg"])
    
    // Video extensies
    private let videoExtensions = Set(["mp4", "mov", "avi", "mxf", "mkv", "webm", "m4v", "prores"])
    
    // Image extensies
    private let imageExtensions = Set(["png", "jpg", "jpeg", "svg", "psd", "gif", "webp", "tiff", "tif"])
    
    // Motion graphic extensies
    private let motionGraphicExtensions = Set(["mogrt", "aep", "aet"])
    
    // STEMS keywords - altijd Music
    private let stemsKeywords = ["stems", "stem", "bass", "drums", "instruments", "melody", "vocals", "vocal"]
    
    // SFX keywords
    private let sfxKeywords = [
        "sfx", "sound-effect", "sound effect", "effect", "impact", "whoosh", "swoosh",
        "hit", "crash", "bang", "explosion", "ambience", "ambient", "foley",
        "transition", "riser", "downer", "swoosh", "swish", "click", "beep",
        "notification", "ui", "button", "interface", "glitch", "noise",
        "wind", "rain", "thunder", "water", "fire", "wave",
        "organic", "nature", "bird", "animal", "door",
        "footstep", "buzz", "alarm", "siren", "horn", "bell", "knock", "creak",
        "rumble", "static", "hum", "drone", "texture", "stinger", "sweep"
    ]
    
    // VO keywords
    private let voKeywords = [
        "vo", "voice", "narration", "dialogue", "dialog", "speech", "spoken",
        "vocal", "narrator", "announcer", "commentary", "voiceover", "voice-over",
        "elevenlabs", "text-to-speech", "tts"
    ]
    
    // Music keywords
    private let musicKeywords = [
        "music", "track", "song", "beat", "melody", "score", "soundtrack", "theme",
        "remix", "mix", "album", "single", "instrumental"
    ]
    
    // Stock footage keywords/patterns
    private let stockFootageKeywords = [
        "stock", "footage", "b-roll", "broll", "clip", "scene", "shot",
        "_hd", "_4k", "_uhd", "_1080", "_720", "artgrid", "artlist"
    ]
    
    // Motion graphic keywords
    private let motionGraphicKeywords = [
        "mogrt", "motion", "graphic", "title", "lower third", "lower-third",
        "bumper", "intro", "outro", "transition", "overlay", "template",
        "promo", "opener", "end screen", "subscribe"
    ]
    
    // Stock footage platforms (in URL)
    private let stockFootagePlatforms = [
        "artgrid", "artlist.io", "shutterstock", "gettyimages", "pond5",
        "storyblocks", "videoblocks", "envato", "videohive", "adobe.com/stock",
        "istockphoto", "depositphotos", "pexels", "pixabay"
    ]
    
    private init() {}
    
    /// Snelle classificatie zonder Python
    /// Retourneert een resultaat met confidence level
    func classify(filename: String, metadata: DownloadMetadata?, originUrl: String?) -> DirectClassificationResult {
        let lower = filename.lowercased()
        let ext = (filename as NSString).pathExtension.lowercased()
        
        // ============================================
        // VIDEO BESTANDEN
        // ============================================
        if videoExtensions.contains(ext) {
            return classifyVideo(filename: filename, lower: lower, metadata: metadata, originUrl: originUrl)
        }
        
        // ============================================
        // AUDIO BESTANDEN
        // ============================================
        if audioExtensions.contains(ext) {
            return classifyAudio(filename: filename, lower: lower, metadata: metadata, originUrl: originUrl)
        }
        
        // ============================================
        // IMAGE BESTANDEN
        // ============================================
        if imageExtensions.contains(ext) {
            print("DirectClassifier: Image bestand gedetecteerd - Graphic")
            return DirectClassificationResult(assetType: .graphic, confidence: .high, reason: "Image file extension")
        }
        
        // ============================================
        // MOTION GRAPHIC BESTANDEN
        // ============================================
        if motionGraphicExtensions.contains(ext) {
            print("DirectClassifier: Motion graphic bestand gedetecteerd")
            return DirectClassificationResult(assetType: .motionGraphic, confidence: .high, reason: "Motion graphic file extension")
        }
        
        // Onbekend bestandstype
        return DirectClassificationResult(assetType: nil, confidence: .low, reason: "Unknown file type")
    }
    
    // MARK: - Video Classification
    
    private func classifyVideo(filename: String, lower: String, metadata: DownloadMetadata?, originUrl: String?) -> DirectClassificationResult {
        
        // 1. Check origin URL voor stock footage platforms
        if let origin = originUrl?.lowercased() {
            for platform in stockFootagePlatforms {
                if origin.contains(platform) {
                    print("DirectClassifier: Stock footage platform in URL - \(platform)")
                    return DirectClassificationResult(assetType: .stockFootage, confidence: .high, reason: "Stock footage platform in origin URL")
                }
            }
        }
        
        // 2. Check bestandsnaam voor stock footage patterns
        // Pattern: nummer_beschrijving_By_Maker_Platform_HD.mp4
        // Voorbeeld: 6586265_Emotional Blue Eyes Sadness Man_By_KAI_TAKEDA_Artlist_HD.mp4
        let stockFootagePattern = lower.contains("_by_") || 
                                  lower.contains("artlist") || 
                                  lower.contains("artgrid") ||
                                  lower.contains("shutterstock") ||
                                  lower.contains("gettyimages") ||
                                  lower.contains("pond5") ||
                                  lower.contains("storyblocks")
        
        if stockFootagePattern {
            print("DirectClassifier: Stock footage pattern in bestandsnaam")
            return DirectClassificationResult(assetType: .stockFootage, confidence: .high, reason: "Stock footage pattern in filename")
        }
        
        // 3. Check voor stock footage keywords
        if stockFootageKeywords.contains(where: { lower.contains($0) }) {
            print("DirectClassifier: Stock footage keyword gevonden")
            return DirectClassificationResult(assetType: .stockFootage, confidence: .high, reason: "Stock footage keyword in filename")
        }
        
        // 4. Check voor motion graphic keywords
        if motionGraphicKeywords.contains(where: { lower.contains($0) }) {
            print("DirectClassifier: Motion graphic keyword gevonden")
            return DirectClassificationResult(assetType: .motionGraphic, confidence: .high, reason: "Motion graphic keyword in filename")
        }
        
        // 5. Check voor numeriek ID prefix (typisch voor stock footage)
        // Pattern: begint met nummer gevolgd door underscore
        let hasNumericPrefix = lower.first?.isNumber == true && lower.contains("_")
        if hasNumericPrefix {
            print("DirectClassifier: Numeriek prefix gevonden (stock footage pattern)")
            return DirectClassificationResult(assetType: .stockFootage, confidence: .medium, reason: "Numeric ID prefix (stock footage pattern)")
        }
        
        // 6. Duration-based heuristics voor video
        if let meta = metadata, let duration = meta.duration {
            if duration < 30 {
                // Korte video's zijn vaak motion graphics
                print("DirectClassifier: Korte video (<30s) - Motion Graphic (medium confidence)")
                return DirectClassificationResult(assetType: .motionGraphic, confidence: .medium, reason: "Short video duration")
            }
        }
        
        // 7. Default voor video: Stock Footage (meest voorkomend)
        print("DirectClassifier: Default classificatie voor video - Stock Footage")
        return DirectClassificationResult(assetType: .stockFootage, confidence: .medium, reason: "Default for video files")
    }
    
    // MARK: - Audio Classification
    
    private func classifyAudio(filename: String, lower: String, metadata: DownloadMetadata?, originUrl: String?) -> DirectClassificationResult {
        
        // 1. STEMS check - hoogste prioriteit, altijd Music
        if stemsKeywords.contains(where: { lower.contains($0) }) {
            print("DirectClassifier: STEMS keyword gevonden - Music")
            return DirectClassificationResult(assetType: .music, confidence: .high, reason: "STEMS keyword in filename")
        }
        
        // 2. VO check - specifieke VO indicators
        if voKeywords.contains(where: { lower.contains($0) }) {
            print("DirectClassifier: VO keyword gevonden")
            return DirectClassificationResult(assetType: .vo, confidence: .high, reason: "VO keyword in filename")
        }
        
        // 3. Origin URL check voor bekende platforms
        if let origin = originUrl?.lowercased() {
            if origin.contains("elevenlabs") || origin.contains("murf.ai") || origin.contains("play.ht") {
                print("DirectClassifier: VO platform gedetecteerd")
                return DirectClassificationResult(assetType: .vo, confidence: .high, reason: "VO platform in origin URL")
            }
            if origin.contains("freesound") || origin.contains("zapsplat") || origin.contains("soundsnap") {
                print("DirectClassifier: SFX platform gedetecteerd")
                return DirectClassificationResult(assetType: .sfx, confidence: .high, reason: "SFX platform in origin URL")
            }
        }
        
        // 4. SFX check - specifieke SFX indicators (alleen als geen music keywords)
        let hasSfxKeyword = sfxKeywords.contains(where: { lower.contains($0) })
        let hasMusicKeyword = musicKeywords.contains(where: { lower.contains($0) })
        
        if hasSfxKeyword && !hasMusicKeyword {
            print("DirectClassifier: SFX keyword gevonden (geen music keywords)")
            return DirectClassificationResult(assetType: .sfx, confidence: .high, reason: "SFX keyword in filename")
        }
        
        // 5. Artist pattern check: "Song Title - Artist Name" of "Artist - Song"
        // Negeer " - " als het deel is van een platform suffix (bijv. "- Epidemic Sound")
        let platformSuffixes = ["epidemic sound", "artlist", "freesound", "pond5", "shutterstock"]
        let hasPlatformSuffix = platformSuffixes.contains(where: { lower.contains("- \($0)") })
        let hasArtistPattern = lower.contains(" - ") && !hasSfxKeyword && !hasPlatformSuffix
        if hasArtistPattern || hasMusicKeyword {
            print("DirectClassifier: Music pattern gevonden (artist of music keyword)")
            return DirectClassificationResult(assetType: .music, confidence: .high, reason: "Music pattern in filename")
        }
        
        // 6. Metadata-based classification
        if let meta = metadata {
            // BPM of key = definitief muziek
            if meta.bpm != nil || meta.key != nil {
                print("DirectClassifier: BPM/Key in metadata - Music")
                return DirectClassificationResult(assetType: .music, confidence: .high, reason: "BPM or Key in metadata")
            }
            
            // Artist in metadata = muziek
            if meta.artist != nil && !meta.artist!.isEmpty {
                print("DirectClassifier: Artist in metadata - Music")
                return DirectClassificationResult(assetType: .music, confidence: .high, reason: "Artist in metadata")
            }
            
            // Duration-based heuristics
            if let duration = meta.duration {
                if duration < 10 {
                    print("DirectClassifier: Korte audio (<10s) - SFX")
                    return DirectClassificationResult(assetType: .sfx, confidence: .medium, reason: "Duration < 10 seconds")
                }
                if duration >= 30 {
                    print("DirectClassifier: Lange audio (>=30s) - Music")
                    return DirectClassificationResult(assetType: .music, confidence: .medium, reason: "Duration >= 30 seconds")
                }
            }
        }
        
        // 7. Default voor audio zonder duidelijke indicators: Music (meest voorkomend)
        print("DirectClassifier: Default classificatie voor audio - Music (medium confidence)")
        return DirectClassificationResult(assetType: .music, confidence: .medium, reason: "Default for audio files")
    }
}

// Current heuristic-based classification strategy
class HeuristicClassificationStrategy: ClassificationStrategy {
    func classify(url: URL, uti: String?, metadata: DownloadMetadata?, originUrl: String?) async -> AssetType {
        return await classifyType(url: url, uti: uti, metadata: metadata, originUrl: originUrl)
    }
    
    // This will be moved from Classifier to here
    private func classifyType(url: URL, uti: String?, metadata: DownloadMetadata?, originUrl: String?) async -> AssetType {
        let ext = url.pathExtension.lowercased()
        let filename = url.lastPathComponent.lowercased()
        
        // Check origin URL for hints (highest priority)
        if let origin = originUrl?.lowercased() {
            if origin.contains("epidemicsound") || origin.contains("artlist") || origin.contains("audiojungle") {
                // Likely music
                if filename.contains("sfx") || filename.contains("sound-effect") {
                    return .sfx
                }
                if filename.contains("vo") || filename.contains("voice") || filename.contains("narration") {
                    return .vo
                }
                return .music
            }
            if origin.contains("envato") || origin.contains("videohive") {
                return .motionGraphic
            }
            if origin.contains("freesound") {
                return .sfx
            }
            if origin.contains("elevenlabs") {
                return .vo
            }
        }
        
        // Classify by extension and metadata
        switch ext {
        case "wav", "aiff", "mp3", "m4a", "aac":
            // Audio - classify Music vs SFX vs VO using metadata and filename
            return classifyAudioType(filename: filename, metadata: metadata)
            
        case "zip":
            // Inspect zip contents to determine type
            return await inspectZipContents(url: url)
            
        case "mogrt", "aep":
            return .motionGraphic
            
        case "png", "jpg", "jpeg", "svg", "psd", "gif", "webp", "tiff", "tif":
            return .graphic
            
        case "mp4", "mov", "avi", "mxf", "mkv", "webm", "m4v":
            // Video - classify Stock Footage vs Motion Graphic using metadata
            return classifyVideoType(filename: filename, metadata: metadata)
            
        default:
            return .unknown
        }
    }
    
    private func classifyAudioType(filename: String, metadata: DownloadMetadata?) -> AssetType {
        // Check filename patterns first (most reliable)
        let sfxKeywords = ["sfx", "sound-effect", "effect", "impact", "whoosh", "swoosh", "hit", "crash", "bang", "explosion", "ambience", "ambient",
                          "wind", "rain", "thunder", "water", "fire", "wave", "organic", "nature", "bird", "animal", "door",
                          "footstep", "click", "beep", "buzz", "alarm", "siren", "horn", "bell", "knock", "creak",
                          "rumble", "static", "hum", "drone", "texture", "riser", "downer", "stinger", "sweep"]
        let voKeywords = ["vo", "voice", "narration", "dialogue", "dialog", "speech", "spoken", "vocal", "narrator", "announcer", "commentary"]
        let musicKeywords = ["music", "track", "song", "beat", "melody", "score", "soundtrack", "theme"]
        
        let lowerFilename = filename.lowercased()
        
        // Check for SFX keywords
        for keyword in sfxKeywords {
            if lowerFilename.contains(keyword) {
                return .sfx
            }
        }
        
        // Check for VO keywords
        for keyword in voKeywords {
            if lowerFilename.contains(keyword) {
                return .vo
            }
        }
        
        // Use metadata if available
        if let meta = metadata {
            // Check genre for hints
            if let genre = meta.genre?.lowercased() {
                if genre.contains("sound effect") || genre.contains("sfx") || genre.contains("ambient") {
                    return .sfx
                }
                if genre.contains("voice") || genre.contains("narration") || genre.contains("spoken") {
                    return .vo
                }
            }
            
            // Check tags
            for tag in meta.tags {
                let lowerTag = tag.lowercased()
                if sfxKeywords.contains(where: { lowerTag.contains($0) }) {
                    return .sfx
                }
                if voKeywords.contains(where: { lowerTag.contains($0) }) {
                    return .vo
                }
            }
            
            // Use duration as heuristic
            // SFX: typically < 10 seconds
            // VO: typically 10-300 seconds (variable)
            // Music: typically > 30 seconds
            if let duration = meta.duration {
                if duration < 10 {
                    // Very short, likely SFX
                    return .sfx
                } else if duration >= 10 && duration <= 300 {
                    // Medium length - could be VO or short music
                    // Check if it has music-related metadata
                    if meta.bpm != nil || meta.key != nil || musicKeywords.contains(where: { lowerFilename.contains($0) }) {
                        return .music
                    }
                    // Otherwise likely VO
                    return .vo
                } else {
                    // Long duration, likely music
                    return .music
                }
            }
            
            // If we have BPM or key, it's likely music
            if meta.bpm != nil || meta.key != nil {
                return .music
            }
        }
        
        // Default to music for audio files if no other indicators
        return .music
    }
    
    private func classifyVideoType(filename: String, metadata: DownloadMetadata?) -> AssetType {
        let lowerFilename = filename.lowercased()
        
        // Check filename patterns
        let motionGraphicKeywords = ["mogrt", "motion", "graphic", "title", "lower third", "bumper", "intro", "outro", "transition", "overlay", "template"]
        let stockFootageKeywords = ["stock", "footage", "b-roll", "broll", "clip", "scene", "shot"]
        
        for keyword in motionGraphicKeywords {
            if lowerFilename.contains(keyword) {
                return .motionGraphic
            }
        }
        
        for keyword in stockFootageKeywords {
            if lowerFilename.contains(keyword) {
                return .stockFootage
            }
        }
        
        // Use metadata to distinguish
        if let meta = metadata {
            // Motion graphics are typically shorter (< 60 seconds) and often have specific resolutions
            // Stock footage is typically longer and can be any resolution
            if let duration = meta.duration {
                if duration < 60 {
                    // Short video - check resolution
                    // Motion graphics often have standard resolutions like 1920x1080, 1280x720
                    // But this is not definitive, so we'll use duration as primary indicator
                    if let width = meta.width, let height = meta.height {
                        // Common motion graphic resolutions
                        let isCommonResolution = (width == 1920 && height == 1080) ||
                                                (width == 1280 && height == 720) ||
                                                (width == 3840 && height == 2160) ||
                                                (width == 1080 && height == 1920) // Vertical
                        
                        if isCommonResolution && duration < 30 {
                            return .motionGraphic
                        }
                    }
                }
            }
            
            // Check frame rate - motion graphics often have specific frame rates
            // Motion graphics often use 30fps or 60fps, but this is not definitive
            // We'll use this as a secondary indicator if needed in the future
            _ = meta.frameRate
        }
        
        // Default to stock footage for video files
        return .stockFootage
    }
    
    private func inspectZipContents(url: URL) async -> AssetType {
        // Use command line unzip to list contents without extracting
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-l", url.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // Suppress errors
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return .unknown
            }
            
            // Parse the file list from unzip output
            let lines = output.components(separatedBy: .newlines)
            var fileExtensions: [String] = []
            
            // Skip header lines and parse file entries
            // Format: "  Length      Date    Time    Name"
            // Then: "  --------  ---------- -----   ----"
            // Then: " 12345678  01-01-2024 12:00   filename.ext"
            var skipHeader = true
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    continue
                }
                
                if skipHeader {
                    if trimmed.contains("Name") || trimmed.contains("----") {
                        skipHeader = false
                        continue
                    }
                    continue
                }
                
                // Extract filename from the line
                // The filename is typically at the end after the date/time
                let components = trimmed.components(separatedBy: .whitespaces)
                if let filename = components.last, !filename.isEmpty {
                    let ext = (filename as NSString).pathExtension.lowercased()
                    if !ext.isEmpty {
                        fileExtensions.append(ext)
                    }
                }
            }
            
            // Classify based on file extensions found in zip
            return classifyZipContents(extensions: fileExtensions, filename: url.lastPathComponent.lowercased())
            
        } catch {
            // If we can't inspect, return unknown
            return .unknown
        }
    }
    
    private func classifyZipContents(extensions: [String], filename: String) -> AssetType {
        // Count occurrences of each file type
        var audioCount = 0
        var videoCount = 0
        var imageCount = 0
        var motionGraphicCount = 0
        
        let audioExts = ["wav", "aiff", "mp3", "m4a", "aac", "flac", "ogg"]
        let videoExts = ["mp4", "mov", "avi", "mxf", "mkv", "webm", "m4v"]
        let imageExts = ["png", "jpg", "jpeg", "svg", "psd", "gif", "webp", "tiff", "tif"]
        let motionGraphicExts = ["mogrt", "aep", "aet"]
        
        for ext in extensions {
            if audioExts.contains(ext) {
                audioCount += 1
            } else if videoExts.contains(ext) {
                videoCount += 1
            } else if imageExts.contains(ext) {
                imageCount += 1
            } else if motionGraphicExts.contains(ext) {
                motionGraphicCount += 1
            }
        }
        
        // Determine type based on contents
        if motionGraphicCount > 0 {
            return .motionGraphic
        }
        
        if videoCount > 0 {
            // If mostly videos, it's likely stock footage
            // But check filename for motion graphic hints
            if filename.contains("motion") || filename.contains("graphic") || filename.contains("template") {
                return .motionGraphic
            }
            return .stockFootage
        }
        
        if imageCount > 0 && audioCount == 0 && videoCount == 0 {
            return .graphic
        }
        
        if audioCount > 0 {
            // For audio files in zip, we can't easily determine Music vs SFX vs VO
            // without extracting and analyzing. Default to music.
            return .music
        }
        
        // If we can't determine, return unknown
        return .unknown
    }
}

class Classifier {
    static let shared = Classifier()
    
    // Classification strategy - can be swapped for Core ML in the future
    private var classificationStrategy: ClassificationStrategy
    private var mlxStrategy: MLXClassificationStrategy?
    private var claudeStrategy: ClaudeClassificationStrategy?
    
    // Source detector for fast pre-classification
    private let sourceDetector = SourceDetector.shared
    
    // Direct classifier for instant classification without Python
    private let directClassifier = DirectClassifier.shared
    
    private init() {
        // Use heuristic strategy by default
        classificationStrategy = HeuristicClassificationStrategy()

        // Initialize Claude strategy if enabled (primary AI)
        if AppState.shared.config.useClaudeClassification {
            claudeStrategy = ClaudeClassificationStrategy()
        }

        // Initialize MLX strategy if enabled (secondary/legacy AI)
        if AppState.shared.config.useMLXClassification {
            mlxStrategy = MLXClassificationStrategy(modelName: AppState.shared.config.mlxModelName)
        }
    }

    /// Update classification strategy based on config
    func updateStrategy() {
        let config = AppState.shared.config

        // Claude API (primary AI)
        if config.useClaudeClassification {
            if claudeStrategy == nil {
                claudeStrategy = ClaudeClassificationStrategy()
            }
        } else {
            claudeStrategy = nil
        }

        // MLX (secondary/legacy AI)
        if config.useMLXClassification {
            if mlxStrategy == nil {
                mlxStrategy = MLXClassificationStrategy(modelName: config.mlxModelName)
            }
        } else {
            mlxStrategy = nil
        }
    }
    
    /// Raad genre en mood op basis van bestandsnaam en bron
    private func guessGenreMoodFromFilename(_ filename: String, source: DetectedSource) -> (genre: String?, mood: String?) {
        let lower = filename.lowercased()
        var genre: String? = nil
        var mood: String? = nil
        
        // Genre keywords mapping
        let genreKeywords: [(keywords: [String], genre: String)] = [
            // Electronic genres
            (["edm", "electronic", "electro", "synth"], "Electronic"),
            (["house", "deep house", "tech house"], "House"),
            (["techno", "minimal"], "Techno"),
            (["trance", "psy"], "Trance"),
            (["dubstep", "bass"], "Dubstep"),
            (["dnb", "drum and bass", "drum & bass", "jungle"], "DnB"),
            
            // Traditional genres
            (["hip hop", "hiphop", "hip-hop", "rap", "trap"], "Hip Hop"),
            (["rock", "guitar", "punk", "grunge", "metal"], "Rock"),
            (["pop", "mainstream"], "Pop"),
            (["jazz", "swing", "bebop"], "Jazz"),
            (["blues", "bluesy"], "Blues"),
            (["country", "western", "americana"], "Country"),
            (["folk", "acoustic", "singer"], "Folk"),
            (["reggae", "ska", "dub"], "Reggae"),
            (["latin", "salsa", "bossa", "samba"], "Latin"),
            (["world", "ethnic", "tribal", "african", "asian"], "World"),
            
            // Cinematic
            (["cinematic", "epic", "trailer", "film", "movie", "orchestral", "orchestra", "score", "soundtrack"], "Cinematic"),
            (["ambient", "atmospheric", "drone", "texture"], "Ambient"),
        ]
        
        // Mood keywords mapping
        let moodKeywords: [(keywords: [String], mood: String)] = [
            // Energetic moods
            (["happy", "joy", "cheerful", "upbeat", "fun", "playful", "bright"], "Happy"),
            (["epic", "heroic", "powerful", "grand", "triumphant", "majestic"], "Epic"),
            (["energetic", "uplifting", "positive", "inspiring"], "Happy"),
            (["angry", "aggressive", "intense", "fierce", "rage"], "Angry"),
            (["action", "chase", "pursuit", "driving", "urgent"], "Chasing"),
            (["busy", "frantic", "hectic", "fast", "rush"], "Busy & Frantic"),
            
            // Calm moods
            (["relaxing", "relaxed", "calm", "soothing", "peaceful", "serene", "gentle", "soft"], "Relaxing"),
            (["dreamy", "ethereal", "floating", "hazy"], "Dreamy"),
            (["smooth", "silky", "elegant", "sophisticated"], "Smooth"),
            (["chill", "chilled", "laid back", "laid-back", "lounge", "groovy", "cool"], "Laid Back"),
            
            // Emotional moods
            (["sad", "melancholic", "melancholy", "emotional", "somber"], "Sad"),
            (["romantic", "love", "loving", "tender", "intimate"], "Romantic"),
            (["sentimental", "nostalgic", "heartfelt", "touching"], "Sentimental"),
            
            // Dark moods
            (["dark", "ominous", "sinister", "menacing", "gloomy"], "Dark"),
            (["mysterious", "mystery", "enigmatic", "intriguing"], "Mysterious"),
            (["scary", "horror", "creepy", "spooky", "eerie"], "Scary"),
            (["suspense", "suspenseful", "tense", "tension", "thriller"], "Suspense"),
            
            // Quirky
            (["quirky", "whimsical", "funny", "comedy", "humorous", "weird", "strange"], "Quirky"),
        ]
        
        // Zoek naar genre keywords
        for (keywords, genreValue) in genreKeywords {
            for keyword in keywords {
                if lower.contains(keyword) {
                    genre = genreValue
                    break
                }
            }
            if genre != nil { break }
        }
        
        // Zoek naar mood keywords
        for (keywords, moodValue) in moodKeywords {
            for keyword in keywords {
                if lower.contains(keyword) {
                    mood = moodValue
                    break
                }
            }
            if mood != nil { break }
        }
        
        // Geen default suggestie - alleen invullen als we het echt weten
        if genre == nil && mood == nil {
            print("Classifier: Geen keywords gevonden in bestandsnaam, geen genre/mood suggestie")
        }
        
        return (genre, mood)
    }
    
    func classify(url: URL, originURL: String? = nil) async -> DownloadItem {
        let fileManager = FileManager.default
        
        // Get file size (works for both files and directories)
        let size = fileManager.fileSize(at: url) ?? 0
        
        // Check if it's a directory
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        
        guard exists else {
            return DownloadItem(
                path: url.path,
                size: 0,
                predictedType: .unknown,
                status: .queued,
                predictedGenre: nil,
                predictedMood: nil
            )
        }
        
        // Get UTI (for directories, this will be nil, which is fine)
        let uti = isDirectory.boolValue ? nil : getUTI(for: url)
        
        // Use provided origin URL or try to get it from extended attributes
        let originUrl = originURL ?? getOriginURL(for: url)
        
        // Get metadata (for directories, we'll classify based on contents)
        let metadata = isDirectory.boolValue ? nil : await extractMetadata(url: url, uti: uti)
        
        // Classify type using MLX if available, otherwise use heuristic strategy
        var assetType: AssetType
        var predictedGenre: String? = nil
        var predictedMood: String? = nil
        var predictedSfxCategory: String? = nil
        var detectedSource: DetectedSource = .unknown
        
        if isDirectory.boolValue {
            // For directories, classify based on contents
            assetType = await classifyDirectory(url: url, originUrl: originUrl)
        } else {
            // STAP 1: Probeer eerst source detection met web scraping voor genre/mood
            let config = AppState.shared.config
            let enableScraping = config.useWebScraping && config.useGenreMoodDetection
            let sourceResult = await sourceDetector.detectWithScraping(url: url, metadata: metadata, enableScraping: enableScraping)
            
            // Sla de gedetecteerde bron op
            detectedSource = sourceResult.source
            
            // Gebruik scraped genre/mood/sfxCategory als beschikbaar en detectie is ingeschakeld
            if config.useGenreMoodDetection {
                if let scrapedGenre = sourceResult.scrapedGenre {
                    predictedGenre = scrapedGenre
                    print("Classifier: Scraped genre van website: \(scrapedGenre)")
                }
                if let scrapedMood = sourceResult.scrapedMood {
                    predictedMood = scrapedMood
                    print("Classifier: Scraped mood van website: \(scrapedMood)")
                }
                if let sfxCategory = sourceResult.sfxCategory {
                    predictedSfxCategory = sfxCategory
                    print("Classifier: Scraped SFX categorie: \(sfxCategory)")
                }
            }
            
            if sourceResult.shouldSkipMLX, let detectedType = sourceResult.assetType {
                // Bron gedetecteerd met hoge zekerheid - skip MLX
                print("Classifier: \(sourceResult.source.rawValue) gedetecteerd - type: \(detectedType.displayName) (MLX overgeslagen)")
                assetType = detectedType
            } else {
                // STAP 2: Probeer DirectClassifier (instant, geen Python)
                let directResult = directClassifier.classify(
                    filename: url.lastPathComponent,
                    metadata: metadata,
                    originUrl: originUrl
                )
                
                if directResult.shouldSkipMLX, let directType = directResult.assetType {
                    // DirectClassifier heeft hoge zekerheid - skip MLX
                    print("Classifier: DirectClassifier - \(directType.displayName) (\(directResult.reason))")
                    assetType = directType
                } else if directResult.confidence == .medium, let directType = directResult.assetType {
                    // DirectClassifier heeft medium zekerheid - gebruik type maar probeer Claude/MLX voor genre/mood
                    print("Classifier: DirectClassifier medium confidence - \(directType.displayName)")
                    assetType = directType

                    // Probeer Claude API voor genre/mood (primair)
                    if let claude = claudeStrategy, config.useClaudeClassification,
                       config.useGenreMoodDetection,
                       predictedGenre == nil || predictedMood == nil {
                        print("Classifier: Claude API voor genre/mood detectie (type al bekend)")
                        let result = await claude.classifyWithDetails(url: url, uti: uti, metadata: metadata, originUrl: originUrl)
                        if predictedGenre == nil { predictedGenre = result.genre }
                        if predictedMood == nil { predictedMood = result.mood }
                        if predictedSfxCategory == nil { predictedSfxCategory = result.sfxCategory }
                    }
                    // Fallback naar MLX voor genre/mood
                    else if config.useMLXClassification && config.useGenreMoodDetection,
                            predictedGenre == nil || predictedMood == nil,
                            let mlx = mlxStrategy {
                        print("Classifier: MLX voor genre/mood detectie (type al bekend)")
                        let result = await mlx.classifyWithDetails(url: url, uti: uti, metadata: metadata, originUrl: originUrl)
                        if predictedGenre == nil { predictedGenre = result.genre }
                        if predictedMood == nil { predictedMood = result.mood }
                    }
                } else if let claude = claudeStrategy, config.useClaudeClassification {
                    // STAP 3: Claude API classificatie (primaire AI)
                    print("Classifier: Using Claude API classification (DirectClassifier had low confidence)")
                    let result = await claude.classifyWithDetails(url: url, uti: uti, metadata: metadata, originUrl: originUrl)
                    assetType = result.assetType
                    if predictedGenre == nil { predictedGenre = result.genre }
                    if predictedMood == nil { predictedMood = result.mood }
                    if predictedSfxCategory == nil { predictedSfxCategory = result.sfxCategory }

                    // Fallback to heuristic if Claude returns unknown
                    if assetType == .unknown {
                        print("Classifier: Claude returned unknown, falling back to heuristic")
                        assetType = await classificationStrategy.classify(url: url, uti: uti, metadata: metadata, originUrl: originUrl)
                    }
                } else if let mlx = mlxStrategy, config.useMLXClassification {
                    // STAP 3b: MLX classificatie (secundaire/legacy AI)
                    print("Classifier: Using MLX classification (DirectClassifier had low confidence)")
                    let result = await mlx.classifyWithDetails(url: url, uti: uti, metadata: metadata, originUrl: originUrl)
                    assetType = result.assetType
                    if predictedGenre == nil { predictedGenre = result.genre }
                    if predictedMood == nil { predictedMood = result.mood }

                    // Fallback to heuristic if MLX returns unknown
                    if assetType == .unknown {
                        print("Classifier: MLX returned unknown, falling back to heuristic")
                        assetType = await classificationStrategy.classify(url: url, uti: uti, metadata: metadata, originUrl: originUrl)
                    }
                } else {
                    // STAP 4: Fallback naar heuristic
                    print("Classifier: Using heuristic classification (AI disabled or not available)")
                    assetType = await classificationStrategy.classify(url: url, uti: uti, metadata: metadata, originUrl: originUrl)
                }
            }
            
            // STAP 5: Als we nog geen genre/mood hebben en het is muziek, probeer te raden op basis van bestandsnaam
            // Alleen als genre/mood detectie is ingeschakeld
            if config.useGenreMoodDetection && assetType == .music && (predictedGenre == nil || predictedMood == nil) {
                let guessed = guessGenreMoodFromFilename(url.lastPathComponent, source: sourceResult.source)
                
                if predictedGenre == nil, let genre = guessed.genre {
                    predictedGenre = genre
                    print("Classifier: Geraden genre van bestandsnaam: \(genre)")
                }
                if predictedMood == nil, let mood = guessed.mood {
                    predictedMood = mood
                    print("Classifier: Geraden mood van bestandsnaam: \(mood)")
                }
            }
        }
        
        return DownloadItem(
            path: url.path,
            uti: uti,
            size: size,
            originUrl: originUrl,
            createdAt: Date().timeIntervalSince1970,
            metadata: metadata,
            predictedType: assetType,
            detectedSource: detectedSource,
            status: .queued,
            predictedGenre: predictedGenre,
            predictedMood: predictedMood,
            predictedSfxCategory: predictedSfxCategory,
            originalPrediction: assetType
        )
    }

    private func classifyDirectory(url: URL, originUrl: String?) async -> AssetType {
        // Check contents of directory to determine type
        let fileManager = FileManager.default
        var audioCount = 0
        var videoCount = 0
        var imageCount = 0
        var hasStems = false
        var stemKeywords: Set<String> = []
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .unknown
        }
        
        // Verzamel alle URLs synchroon om async iterator issues te vermijden
        let allFiles = enumerator.allObjects.compactMap { $0 as? URL }
        
        for fileURL in allFiles {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                let ext = fileURL.pathExtension.lowercased()
                let fileName = fileURL.lastPathComponent.lowercased()
                
                // Check for STEMS keywords in filename
                if fileName.contains("stems") || fileName.contains("stem") {
                    hasStems = true
                    // Extract stem type if present
                    if fileName.contains("bass") {
                        stemKeywords.insert("bass")
                    }
                    if fileName.contains("drums") || fileName.contains("drum") {
                        stemKeywords.insert("drums")
                    }
                    if fileName.contains("instruments") || fileName.contains("instrument") {
                        stemKeywords.insert("instruments")
                    }
                    if fileName.contains("melody") {
                        stemKeywords.insert("melody")
                    }
                    if fileName.contains("vocals") || fileName.contains("vocal") {
                        stemKeywords.insert("vocals")
                    }
                }
                
                if ["wav", "aiff", "mp3", "m4a", "aac", "flac", "ogg"].contains(ext) {
                    audioCount += 1
                } else if ["mp4", "mov", "avi", "mxf", "mkv", "webm", "m4v"].contains(ext) {
                    videoCount += 1
                } else if ["png", "jpg", "jpeg", "svg", "psd", "gif", "webp", "tiff", "tif"].contains(ext) {
                    imageCount += 1
                }
            }
        }
        
        // If directory contains STEMS (DRUMS, BASS, INSTRUMENTS, MELODY), it's definitely music
        if hasStems && stemKeywords.count >= 2 {
            print("Classifier: Directory contains STEMS (\(stemKeywords.joined(separator: ", "))) - classifying as Music")
            return .music
        }
        
        // If directory contains only audio files, it's likely music (stems)
        if audioCount > 0 && videoCount == 0 && imageCount == 0 {
            // Check if filenames share common base name (indicating stems)
            // This is a heuristic: if multiple audio files share a common prefix, they're likely stems
            return .music
        }
        
        // Otherwise, use heuristic classification based on filename
        return await classificationStrategy.classify(url: url, uti: nil, metadata: nil, originUrl: originUrl)
    }
    
    private func getUTI(for url: URL) -> String? {
        guard let uti = UTType(filenameExtension: url.pathExtension) else {
            return nil
        }
        return uti.identifier
    }
    
    private func getOriginURL(for url: URL) -> String? {
        // Skip slow xattr/NSMetadataQuery calls that block the main thread
        // We'll rely on filename and other heuristics for classification
        // This prevents the app from freezing when processing downloads
        return nil
    }
    
    private func getOriginURLFromMetadata(url: URL) -> String? {
        // Skip this slow synchronous query - it blocks the main thread
        // We'll rely on filename and other heuristics instead
        return nil
    }
    
    private func extractMetadata(url: URL, uti: String?) async -> DownloadMetadata? {
        guard let uti = uti else { return nil }
        
        // Extract metadata based on file type
        if uti.contains("audio") {
            return await extractAudioMetadata(url: url)
        } else if uti.contains("video") || uti.contains("movie") {
            return await extractVideoMetadata(url: url)
        } else if uti.contains("image") {
            return await extractImageMetadata(url: url)
        }
        
        return nil
    }
    
    private func extractAudioMetadata(url: URL) async -> DownloadMetadata? {
        let asset = AVURLAsset(url: url)
        
        // Load duration asynchronously
        let duration: Int?
        do {
            let durationValue = try await asset.load(.duration)
            if durationValue.isValid && !durationValue.isIndefinite {
                duration = Int(CMTimeGetSeconds(durationValue))
            } else {
                duration = nil
            }
        } catch {
            duration = nil
        }
        
        // Load metadata asynchronously
        let metadata = (try? await asset.load(.metadata)) ?? []
        
        var artist: String?
        var title: String?
        var genre: String?
        var bpm: Int?
        var keySignature: String?
        var bitrate: Int?
        var sampleRate: Int?
        var tags: [String] = []
        
        // Extract common metadata keys
        for item in metadata {
            guard let metadataKey = item.commonKey?.rawValue,
                  let value = try? await item.load(.value) else {
                continue
            }
            
            switch metadataKey {
            case "title":
                title = value as? String
            case "artist", "artistName":
                artist = value as? String
            case "type", "genre":
                genre = value as? String
            case "bpm":
                if let bpmValue = value as? NSNumber {
                    bpm = bpmValue.intValue
                }
            case "keySignature":
                if let keyValue = value as? String {
                    keySignature = keyValue
                }
            case "bitRate":
                if let bitrateValue = value as? NSNumber {
                    bitrate = bitrateValue.intValue / 1000 // Convert to kbps
                }
            case "sampleRate":
                if let sampleRateValue = value as? NSNumber {
                    sampleRate = sampleRateValue.intValue
                }
            default:
                // Try to extract as tag if it's a string
                if let tagValue = value as? String, !tagValue.isEmpty {
                    tags.append(tagValue)
                }
            }
        }
        
        // Also try to extract format-specific metadata from audio tracks
        // Note: Sample rate is already extracted from metadata above, so this is optional
        // If we need more detailed format info in the future, we can add it here
        // For now, we rely on metadata which is more reliable
        
        // Only return metadata if we found something useful
        if duration != nil || artist != nil || title != nil || genre != nil || bpm != nil || bitrate != nil || sampleRate != nil {
            return DownloadMetadata(
                artist: artist,
                title: title,
                duration: duration,
                bpm: bpm,
                key: keySignature,
                tags: tags,
                genre: genre,
                bitrate: bitrate,
                sampleRate: sampleRate
            )
        }
        
        return nil
    }
    
    private func extractVideoMetadata(url: URL) async -> DownloadMetadata? {
        let asset = AVURLAsset(url: url)
        
        // Load duration
        let duration: Int?
        do {
            let durationValue = try await asset.load(.duration)
            if durationValue.isValid && !durationValue.isIndefinite {
                duration = Int(CMTimeGetSeconds(durationValue))
            } else {
                duration = nil
            }
        } catch {
            duration = nil
        }
        
        // Load video tracks
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return duration != nil ? DownloadMetadata(duration: duration) : nil
        }
        
        // Load natural size
        let naturalSize = try? await videoTrack.load(.naturalSize)
        let width = naturalSize.map { Int($0.width) }
        let height = naturalSize.map { Int($0.height) }
        
        // Load frame rate asynchronously
        let frameRate: Double?
        do {
            let frameRateValue = try await videoTrack.load(.nominalFrameRate)
            frameRate = frameRateValue > 0 ? Double(frameRateValue) : nil
        } catch {
            frameRate = nil
        }
        
        // Try to extract codec from format description
        var codec: String?
        do {
            let formatDescriptions = try await videoTrack.load(.formatDescriptions)
            if let formatDescription = formatDescriptions.first {
                let codecType = CMFormatDescriptionGetMediaSubType(formatDescription)
                codec = codecTypeToString(codecType)
            }
        } catch {
            // Ignore errors
        }
        
        return DownloadMetadata(
            duration: duration,
            width: width,
            height: height,
            frameRate: frameRate,
            codec: codec
        )
    }
    
    private func extractImageMetadata(url: URL) async -> DownloadMetadata? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] else {
            return nil
        }
        
        var width: Int?
        var height: Int?
        var colorSpace: String?
        
        // Extract dimensions
        if let pixelWidth = imageProperties[kCGImagePropertyPixelWidth as String] as? Int {
            width = pixelWidth
        }
        if let pixelHeight = imageProperties[kCGImagePropertyPixelHeight as String] as? Int {
            height = pixelHeight
        }
        
        // Extract color space
        if let colorModel = imageProperties[kCGImagePropertyColorModel as String] as? String {
            colorSpace = colorModel
        }
        
        if width != nil || height != nil || colorSpace != nil {
            return DownloadMetadata(
                width: width,
                height: height,
                colorSpace: colorSpace
            )
        }
        
        return nil
    }
    
    private func codecTypeToString(_ codecType: FourCharCode) -> String {
        let bytes = [
            UInt8((codecType >> 24) & 0xFF),
            UInt8((codecType >> 16) & 0xFF),
            UInt8((codecType >> 8) & 0xFF),
            UInt8(codecType & 0xFF)
        ]
        
        if let string = String(bytes: bytes, encoding: .macOSRoman) {
            return string.trimmingCharacters(in: CharacterSet.whitespaces)
        }
        
        return String(format: "0x%08X", codecType)
    }
    
}

