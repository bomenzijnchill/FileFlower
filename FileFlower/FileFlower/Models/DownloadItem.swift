import Foundation
import CryptoKit

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
    var isCloudDownload: Bool            // Of het bestand van cloud storage komt (Dropbox, Google Drive)
    var needsManualClassification: Bool  // Of de gebruiker handmatig een map moet kiezen
    var childFiles: [String]?            // Bestanden binnen een map-item (uit ZIP extractie)
    var failureReason: String?           // Reden waarom verwerking is mislukt
    var previewPath: String?             // Leesbaar preview-pad (bijv. "Project → Audio → Music → Mood → Chill")
    var manualTargetPath: String?        // Handmatig overschreven doelpad (overschrijft PathResolver)
    var needsPathConfirmation: Bool      // PathResolver is onzeker over het pad
    var pathConfidence: Double?          // 0.0-1.0 confidence score van PathResolver

    /// Of dit item een map is (bijv. uitgepakte ZIP)
    var isFolder: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

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
        originalPrediction: AssetType? = nil,
        isCloudDownload: Bool = false,
        needsManualClassification: Bool = false,
        childFiles: [String]? = nil,
        failureReason: String? = nil,
        previewPath: String? = nil,
        manualTargetPath: String? = nil,
        needsPathConfirmation: Bool = false,
        pathConfidence: Double? = nil
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
        self.isCloudDownload = isCloudDownload
        self.needsManualClassification = needsManualClassification
        self.childFiles = childFiles
        self.failureReason = failureReason
        self.previewPath = previewPath
        self.manualTargetPath = manualTargetPath
        self.needsPathConfirmation = needsPathConfirmation
        self.pathConfidence = pathConfidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        uti = try container.decodeIfPresent(String.self, forKey: .uti)
        size = try container.decode(Int64.self, forKey: .size)
        originUrl = try container.decodeIfPresent(String.self, forKey: .originUrl)
        createdAt = try container.decode(TimeInterval.self, forKey: .createdAt)
        metadata = try container.decodeIfPresent(DownloadMetadata.self, forKey: .metadata)
        predictedType = try container.decode(AssetType.self, forKey: .predictedType)
        detectedSource = try container.decodeIfPresent(DetectedSource.self, forKey: .detectedSource)
        status = try container.decode(ItemStatus.self, forKey: .status)
        targetProject = try container.decodeIfPresent(ProjectInfo.self, forKey: .targetProject)
        targetSubfolder = try container.decodeIfPresent(String.self, forKey: .targetSubfolder)
        targetPath = try container.decodeIfPresent(String.self, forKey: .targetPath)
        predictedGenre = try container.decodeIfPresent(String.self, forKey: .predictedGenre)
        predictedMood = try container.decodeIfPresent(String.self, forKey: .predictedMood)
        predictedSfxCategory = try container.decodeIfPresent(String.self, forKey: .predictedSfxCategory)
        originalPrediction = try container.decodeIfPresent(AssetType.self, forKey: .originalPrediction)
        isCloudDownload = try container.decodeIfPresent(Bool.self, forKey: .isCloudDownload) ?? false
        needsManualClassification = try container.decodeIfPresent(Bool.self, forKey: .needsManualClassification) ?? false
        childFiles = try container.decodeIfPresent([String].self, forKey: .childFiles)
        failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
        previewPath = try container.decodeIfPresent(String.self, forKey: .previewPath)
        manualTargetPath = try container.decodeIfPresent(String.self, forKey: .manualTargetPath)
        needsPathConfirmation = try container.decodeIfPresent(Bool.self, forKey: .needsPathConfirmation) ?? false
        pathConfidence = try container.decodeIfPresent(Double.self, forKey: .pathConfidence)
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
    case footage = "Footage"
    case motionGraphic = "MotionGraphic"
    case graphic = "Graphic"
    case stockFootage = "StockFootage"
    case unknown = "Unknown"

    var displayName: String {
        switch self {
        case .music: return "Music"
        case .sfx: return "SFX"
        case .vo: return "Voice Over"
        case .footage: return "Footage"
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

    /// Standaard wordt de id DETERMINISTISCH afgeleid van het projectpad.
    /// Voorheen kreeg elke constructie een verse UUID, waardoor hetzelfde project na
    /// elke 30s-rescan een andere id had: id-gebaseerde membership-checks faalden dan
    /// en een handmatig gekozen project werd stilzwijgend teruggezet.
    init(id: UUID? = nil, name: String, rootPath: String, projectPath: String, lastModified: TimeInterval) {
        self.id = id ?? Self.stableID(for: projectPath)
        self.name = name
        self.rootPath = rootPath
        self.projectPath = projectPath
        self.lastModified = lastModified
    }

    /// Stabiele UUID afgeleid van het projectpad (zelfde pad → zelfde id).
    static func stableID(for projectPath: String) -> UUID {
        let digest = SHA256.hash(data: Data(projectPath.utf8))
        var bytes = Array(digest.prefix(16))
        // Zet UUID-versie (4) en variant-bits zodat het een geldige UUID is
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

