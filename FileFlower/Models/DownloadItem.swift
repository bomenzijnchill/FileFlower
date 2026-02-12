import Foundation

struct DownloadItem: Identifiable, Codable {
    let id: UUID
    var path: String
    var uti: String?
    var size: Int64
    var originUrl: String?
    var createdAt: TimeInterval
    var metadata: DownloadMetadata?
    var predictedType: AssetType
    var detectedSource: DetectedSource?  // Gedetecteerde bron (bijv. YouTube 4K, Artlist, etc.)
    var status: ItemStatus
    var targetProject: ProjectInfo?
    var targetSubfolder: String?
    var targetPath: String?
    var predictedGenre: String?
    var predictedMood: String?
    var predictedSfxCategory: String?  // SFX categorie (bijv. "Swooshes", "Impacts", etc.)
    var originalPrediction: AssetType?  // Systeem's originele classificatie vóór user correctie

    init(
        id: UUID = UUID(),
        path: String,
        uti: String? = nil,
        size: Int64,
        originUrl: String? = nil,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        metadata: DownloadMetadata? = nil,
        predictedType: AssetType,
        detectedSource: DetectedSource? = nil,
        status: ItemStatus = .queued,
        targetProject: ProjectInfo? = nil,
        targetSubfolder: String? = nil,
        targetPath: String? = nil,
        predictedGenre: String? = nil,
        predictedMood: String? = nil,
        predictedSfxCategory: String? = nil,
        originalPrediction: AssetType? = nil
    ) {
        self.id = id
        self.path = path
        self.uti = uti
        self.size = size
        self.originUrl = originUrl
        self.createdAt = createdAt
        self.metadata = metadata
        self.predictedType = predictedType
        self.detectedSource = detectedSource
        self.status = status
        self.targetProject = targetProject
        self.targetSubfolder = targetSubfolder
        self.targetPath = targetPath
        self.predictedGenre = predictedGenre
        self.predictedMood = predictedMood
        self.predictedSfxCategory = predictedSfxCategory
        self.originalPrediction = originalPrediction
    }
}

struct DownloadMetadata: Codable {
    // Audio metadata
    var artist: String?
    var title: String?
    var duration: Int? // Duration in seconds
    var bpm: Int?
    var key: String?
    var tags: [String]
    var genre: String?
    var bitrate: Int? // Audio bitrate in kbps
    var sampleRate: Int? // Sample rate in Hz
    
    // Video metadata
    var width: Int? // Video width in pixels
    var height: Int? // Video height in pixels
    var frameRate: Double? // Frame rate in fps
    var codec: String? // Video codec name
    
    // Image metadata
    var colorSpace: String? // Color space name
    
    // Web scraped metadata
    var scrapedProvider: String? // Provider van de stock website (artlist, epidemic, etc.)
    var scrapedGenres: [String]? // Ruwe genres van de website
    var scrapedMoods: [String]? // Ruwe moods van de website
    var originUrl: String? // URL waar het bestand vandaan komt
    
    init(
        artist: String? = nil,
        title: String? = nil,
        duration: Int? = nil,
        bpm: Int? = nil,
        key: String? = nil,
        tags: [String] = [],
        genre: String? = nil,
        bitrate: Int? = nil,
        sampleRate: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        frameRate: Double? = nil,
        codec: String? = nil,
        colorSpace: String? = nil,
        scrapedProvider: String? = nil,
        scrapedGenres: [String]? = nil,
        scrapedMoods: [String]? = nil,
        originUrl: String? = nil
    ) {
        self.artist = artist
        self.title = title
        self.duration = duration
        self.bpm = bpm
        self.key = key
        self.tags = tags
        self.genre = genre
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.codec = codec
        self.colorSpace = colorSpace
        self.scrapedProvider = scrapedProvider
        self.scrapedGenres = scrapedGenres
        self.scrapedMoods = scrapedMoods
        self.originUrl = originUrl
    }
}

enum AssetType: String, Codable, CaseIterable {
    case music = "Music"
    case sfx = "SFX"
    case vo = "VO"
    case motionGraphic = "MotionGraphic"
    case graphic = "Graphic"
    case stockFootage = "StockFootage"
    case unknown = "Unknown"
    
    var displayName: String {
        switch self {
        case .music: return "Music"
        case .sfx: return "SFX"
        case .vo: return "Voice Over"
        case .motionGraphic: return "Motion Graphic"
        case .graphic: return "Graphic"
        case .stockFootage: return "Stock Footage"
        case .unknown: return "Unknown"
        }
    }
}

enum ItemStatus: String, Codable {
    case queued = "queued"
    case classifying = "classifying"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
    case skipped = "skipped"
}

struct ProjectInfo: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var rootPath: String
    var projectPath: String
    var lastModified: TimeInterval
    
    init(id: UUID = UUID(), name: String, rootPath: String, projectPath: String, lastModified: TimeInterval) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.projectPath = projectPath
        self.lastModified = lastModified
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

