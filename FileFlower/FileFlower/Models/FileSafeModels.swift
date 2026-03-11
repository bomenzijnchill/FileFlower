import Foundation

// MARK: - Wizard Step

enum FileSafeStep: Int, CaseIterable {
    case emptyState = 0
    case volumeSelect = 1
    case projectSelect = 2
    case scanning = 3
    case shootWizard = 4
    case structurePreview = 5
    case copying = 6
    case report = 7
}

// MARK: - File Category

enum FileSafeFileCategory: String, Codable, CaseIterable {
    case video = "video"
    case audio = "audio"
    case photo = "photo"
    case other = "other"

    var displayName: String {
        switch self {
        case .video: return String(localized: "filesafe.category.video")
        case .audio: return String(localized: "filesafe.category.audio")
        case .photo: return String(localized: "filesafe.category.photo")
        case .other: return String(localized: "filesafe.category.other")
        }
    }

    var icon: String {
        switch self {
        case .video: return "film"
        case .audio: return "waveform"
        case .photo: return "photo"
        case .other: return "doc"
        }
    }
}

// MARK: - File Extension Sets

enum FileSafeExtensions {
    static let video: Set<String> = [
        "mp4", "mov", "mxf", "braw", "r3d", "ari", "mts", "m2ts", "avi", "mkv", "dng"
    ]

    static let audio: Set<String> = [
        "wav", "aif", "aiff", "mp3", "aac", "flac", "bwf", "rf64"
    ]

    static let photo: Set<String> = [
        "jpg", "jpeg", "png", "tiff", "tif", "cr3", "cr2", "arw", "nef", "raf", "heic"
    ]

    static let ignoredFiles: Set<String> = [
        ".DS_Store", "Thumbs.db", ".Spotlight-V100", ".fseventsd", ".Trashes"
    ]

    static let ignoredExtensions: Set<String> = [
        "xml", "idx", "cif", "thm", "lrf"
    ]

    static func category(for fileExtension: String) -> FileSafeFileCategory {
        let ext = fileExtension.lowercased()
        if video.contains(ext) { return .video }
        if audio.contains(ext) { return .audio }
        if photo.contains(ext) { return .photo }
        return .other
    }

    static func shouldIgnore(fileName: String, fileExtension: String) -> Bool {
        if ignoredFiles.contains(fileName) { return true }
        if ignoredExtensions.contains(fileExtension.lowercased()) { return true }
        if fileName.hasPrefix(".") { return true }
        return false
    }
}

// MARK: - Source File

struct FileSafeSourceFile: Codable, Identifiable, Equatable {
    let id: UUID
    let relativePath: String
    let fileName: String
    let fileExtension: String
    let category: FileSafeFileCategory
    let fileSize: Int64
    let creationDate: Date?
    let modificationDate: Date?

    var fullPath: String {
        relativePath
    }

    static func == (lhs: FileSafeSourceFile, rhs: FileSafeSourceFile) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Scan Result

struct FileSafeScanResult: Codable {
    let volumeName: String
    let volumePath: String
    let files: [FileSafeSourceFile]
    let totalSize: Int64
    let scanDate: Date

    var videoFiles: [FileSafeSourceFile] { files.filter { $0.category == .video } }
    var audioFiles: [FileSafeSourceFile] { files.filter { $0.category == .audio } }
    var photoFiles: [FileSafeSourceFile] { files.filter { $0.category == .photo } }
    var otherFiles: [FileSafeSourceFile] { files.filter { $0.category == .other } }

    var videoCount: Int { videoFiles.count }
    var audioCount: Int { audioFiles.count }
    var photoCount: Int { photoFiles.count }

    var hasVideo: Bool { videoCount > 0 }
    var hasAudio: Bool { audioCount > 0 }
    var hasPhoto: Bool { photoCount > 0 }
}

// MARK: - Shoot Day

struct FileSafeShootDay: Codable, Identifiable, Equatable {
    let id: UUID
    var dayNumber: Int
    var date: Date?
    var label: String?

    var displayName: String {
        if let label = label, !label.isEmpty {
            return label
        }
        if let date = date {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return "Day_\(String(format: "%02d", dayNumber))_\(formatter.string(from: date))"
        }
        return "Day_\(String(format: "%02d", dayNumber))"
    }

    init(dayNumber: Int, date: Date? = nil, label: String? = nil) {
        self.id = UUID()
        self.dayNumber = dayNumber
        self.date = date
        self.label = label
    }
}

// MARK: - Shoot Config

struct FileSafeShootConfig: Codable {
    var projectName: String
    var shootDays: [FileSafeShootDay]
    var location: String?

    // Video
    var cameraAngles: [String]
    var cameraModels: [String]
    var useTimestampAssignment: Bool

    // Audio
    var audioPersons: [String]
    var hasWildtrack: Bool
    var linkAudioToDayStructure: Bool

    // Photo
    var photoCategories: [String]
    var splitRawJpeg: Bool

    static let `default` = FileSafeShootConfig(
        projectName: "",
        shootDays: [FileSafeShootDay(dayNumber: 1)],
        location: nil,
        cameraAngles: [],
        cameraModels: [],
        useTimestampAssignment: true,
        audioPersons: [],
        hasWildtrack: false,
        linkAudioToDayStructure: true,
        photoCategories: [],
        splitRawJpeg: false
    )
}

// MARK: - Verification Status

enum FileSafeVerificationPhase: String, Codable {
    case copying = "copying"
    case checksum = "checksum"
    case byteCompare = "byteCompare"
    case complete = "complete"

    var displayName: String {
        switch self {
        case .copying: return String(localized: "filesafe.verify.copying")
        case .checksum: return String(localized: "filesafe.verify.checksum")
        case .byteCompare: return String(localized: "filesafe.verify.bytecompare")
        case .complete: return String(localized: "filesafe.verify.complete")
        }
    }

    var icon: String {
        switch self {
        case .copying: return "doc.on.doc"
        case .checksum: return "number.circle"
        case .byteCompare: return "01.square"
        case .complete: return "checkmark.shield.fill"
        }
    }
}

// MARK: - Copy Result (per file)

struct FileSafeCopyResult: Codable, Identifiable {
    let id: UUID
    let sourceFile: FileSafeSourceFile
    let destinationPath: String
    let sourceChecksum: String
    let destinationChecksum: String
    let sizesMatch: Bool
    let checksumsMatch: Bool
    let bytesMatch: Bool
    let retryCount: Int
    let error: String?
    let copyDuration: TimeInterval

    var isFullyVerified: Bool {
        sizesMatch && checksumsMatch && bytesMatch && error == nil
    }

    var verifiedCheckCount: Int {
        var count = 0
        if sizesMatch { count += 1 }
        if checksumsMatch { count += 1 }
        if bytesMatch { count += 1 }
        return count
    }
}

// MARK: - Copy Report

struct FileSafeCopyReport: Codable, Identifiable {
    let id: UUID
    let projectName: String
    let volumeName: String
    let startTime: Date
    let endTime: Date
    let totalFiles: Int
    let totalSize: Int64
    let results: [FileSafeCopyResult]

    var successCount: Int { results.filter { $0.isFullyVerified }.count }
    var failCount: Int { results.filter { !$0.isFullyVerified }.count }
    var warningCount: Int { results.filter { $0.retryCount > 0 && $0.isFullyVerified }.count }

    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - Target Folder (for structure preview)

struct FileSafeTargetFolder: Identifiable {
    let id: UUID
    let relativePath: String
    let displayName: String
    var fileCount: Int
    var totalSize: Int64
    var children: [FileSafeTargetFolder]

    init(relativePath: String, displayName: String, fileCount: Int = 0, totalSize: Int64 = 0, children: [FileSafeTargetFolder] = []) {
        self.id = UUID()
        self.relativePath = relativePath
        self.displayName = displayName
        self.fileCount = fileCount
        self.totalSize = totalSize
        self.children = children
    }

    var totalFileCount: Int {
        fileCount + children.reduce(0) { $0 + $1.totalFileCount }
    }

    var totalTotalSize: Int64 {
        totalSize + children.reduce(0) { $0 + $1.totalTotalSize }
    }
}

// MARK: - File Mapping (source → destination)

struct FileSafeFileMapping {
    let source: FileSafeSourceFile
    let destinationPath: String
    let targetFolderName: String
}
