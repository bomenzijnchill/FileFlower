import Foundation

// MARK: - Wizard Step

enum FileSafeStep: Int, CaseIterable {
    case dashboard = -1         // Transfer overzicht (actieve/voltooide transfers)
    case emptyState = 0
    case volumeSelect = 1
    case projectSelect = 2
    case scanning = 3
    case projectConfig = 4      // Project-level instellingen (1x per project)
    case cardConfig = 5         // Kaart-level instellingen (per import)
    case structurePreview = 6
    case copying = 7
    case report = 8
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

// MARK: - Camera Brand Detection

enum FileSafeCameraBrand: String, Codable, CaseIterable {
    case sony = "Sony"
    case canon = "Canon"
    case blackmagic = "Blackmagic"
    case red = "RED"
    case arri = "ARRI"
    case dji = "DJI"
    case gopro = "GoPro"
    case panasonic = "Panasonic"
    case unknown = "Unknown"

    var icon: String {
        switch self {
        case .sony, .canon, .panasonic: return "video.fill"
        case .blackmagic, .red, .arri: return "film"
        case .dji: return "airplane"
        case .gopro: return "camera.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Camera Split Mode

enum FileSafeCameraSplitMode: String, Codable, CaseIterable {
    case none = "none"           // Geen camera-onderverdeling
    case byType = "byType"      // Onderverdelen op camera type (bijv. "Sony FX6", "Canon C70")
    case byAngle = "byAngle"    // Onderverdelen op camera angle (bijv. "A", "B", "C")

    var displayName: String {
        switch self {
        case .none: return String(localized: "filesafe.camera.split.none")
        case .byType: return String(localized: "filesafe.camera.split.type")
        case .byAngle: return String(localized: "filesafe.camera.split.angle")
        }
    }
}

// MARK: - Date Source

enum FileSafeDateSource: String, Codable, CaseIterable {
    case materialDate = "materialDate"   // Gebruik bestandsdatum van bronmateriaal
    case downloadDate = "downloadDate"   // Gebruik vandaag als datum

    var displayName: String {
        switch self {
        case .materialDate: return String(localized: "filesafe.datesource.material")
        case .downloadDate: return String(localized: "filesafe.datesource.download")
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
        "xml", "idx", "cif", "thm", "lrf",
        // Camera-specifieke proxy/systeem extensies
        "lrv",   // GoPro low-res video proxy
        "scr",   // DJI screen thumbnails
        "cpf",   // Canon Custom Picture Files
        "mif",   // Canon master index
        "bin"    // Camera systeem bestanden (STATUS.BIN etc.)
    ]

    /// Camera thumbnail/systeem mappen die overgeslagen moeten worden
    static let ignoredFolderNames: Set<String> = [
        "THMBNL",     // Sony thumbnails
        "THM",        // DJI thumbnails
        "MISC",       // DJI systeem bestanden
        "CLIPINFO",   // Canon clip metadata
        "CANONMSC"    // Canon systeem
    ]

    /// Bestandsnaam-patronen die overgeslagen moeten worden
    static let ignoredFilePatterns: [String] = [
        "JOURNAL",      // Canon transaction logs
        "STATUS.BIN"    // Camera systeem status
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
        // Check bestandsnaam-patronen
        let upperName = fileName.uppercased()
        for pattern in ignoredFilePatterns {
            if upperName.hasPrefix(pattern) { return true }
        }
        return false
    }

    static func shouldIgnoreFolder(name: String) -> Bool {
        ignoredFolderNames.contains(name.uppercased())
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

    // Detectie-informatie
    let detectedBrand: FileSafeCameraBrand
    let uniqueCalendarDays: [Date]   // Unieke kalenderdagen gevonden in materiaal
    let earliestDate: Date?
    let latestDate: Date?

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

    /// Of al het materiaal van een enkele dag is
    var isSingleDay: Bool { uniqueCalendarDays.count <= 1 }

    /// Voorgesteld aantal dagen op basis van gevonden datums
    var suggestedDayCount: Int { max(1, uniqueCalendarDays.count) }
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
            formatter.dateFormat = "ddMMyyyy"
            return "Dag \(dayNumber)_\(formatter.string(from: date))"
        }
        return "Dag \(dayNumber)"
    }

    init(dayNumber: Int, date: Date? = nil, label: String? = nil) {
        self.id = UUID()
        self.dayNumber = dayNumber
        self.date = date
        self.label = label
    }
}

// MARK: - Project Config (opgeslagen als .filesafe-project.json in projectmap)

struct FileSafeProjectConfig: Codable {
    var projectName: String
    var isMultiDayShoot: Bool
    var location: String?

    // Camera
    var hasMultipleCameras: Bool
    var cameraSplitMode: FileSafeCameraSplitMode
    var cameraLabels: [String]       // Camera namen (byType) of angle labels (byAngle)

    // Audio
    var audioPersons: [String]
    var hasWildtrack: Bool
    var linkAudioToDayStructure: Bool

    // Photo
    var photoCategories: [String]
    var splitRawJpeg: Bool

    // Instellingen
    var useTimestampAssignment: Bool
    var dateSource: FileSafeDateSource
    var lastUpdated: Date

    static let `default` = FileSafeProjectConfig(
        projectName: "",
        isMultiDayShoot: false,
        location: nil,
        hasMultipleCameras: false,
        cameraSplitMode: .none,
        cameraLabels: [],
        audioPersons: [],
        hasWildtrack: false,
        linkAudioToDayStructure: true,
        photoCategories: [],
        splitRawJpeg: false,
        useTimestampAssignment: true,
        dateSource: .materialDate,
        lastUpdated: Date()
    )
}

// MARK: - Project Config Persistence

extension FileSafeProjectConfig {
    private static let fileName = ".filesafe-project.json"

    static func load(from projectPath: String) -> FileSafeProjectConfig? {
        let url = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FileSafeProjectConfig.self, from: data)
    }

    func save(to projectPath: String) throws {
        let url = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(Self.fileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Subfolder Bin

struct FileSafeSubfolderBin: Identifiable, Equatable {
    let id: UUID
    var name: String

    init(name: String) {
        self.id = UUID()
        self.name = name
    }
}

// MARK: - Card Config (per import)

struct FileSafeCardConfig {
    var shootDays: [FileSafeShootDay]
    var dateOverride: Date?
    var volumePath: String
    var volumeName: String

    // Legacy: geneste submappen (behouden voor backward compat)
    var videoSubfolders: [String]
    var photoSubfolders: [String]

    // Bins per categorie (vervangt SubfolderListEditor in UI)
    var videoBins: [FileSafeSubfolderBin]
    var photoBins: [FileSafeSubfolderBin]

    // Per-file toewijzing: fileId → bin name (bestanden zonder entry → direct in dag-map)
    var fileSubfolderMap: [UUID: String]

    static func defaultFor(scanResult: FileSafeScanResult, projectConfig: FileSafeProjectConfig) -> FileSafeCardConfig {
        var days: [FileSafeShootDay] = []

        if projectConfig.isMultiDayShoot {
            // Maak dagen aan op basis van gedetecteerde datums
            for (index, date) in scanResult.uniqueCalendarDays.enumerated() {
                days.append(FileSafeShootDay(dayNumber: index + 1, date: date))
            }
            // Minimaal 1 dag
            if days.isEmpty {
                days.append(FileSafeShootDay(dayNumber: 1, date: Date()))
            }
        } else {
            // Enkele dag
            let date: Date
            switch projectConfig.dateSource {
            case .materialDate:
                date = scanResult.uniqueCalendarDays.first ?? Date()
            case .downloadDate:
                date = Date()
            }
            days.append(FileSafeShootDay(dayNumber: 1, date: date))
        }

        // Als er meerdere camera's zijn, maak standaard bins aan op basis van camera labels
        var videoBins: [FileSafeSubfolderBin] = []
        if projectConfig.hasMultipleCameras && !projectConfig.cameraLabels.isEmpty {
            videoBins = projectConfig.cameraLabels
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { FileSafeSubfolderBin(name: $0) }
        }

        return FileSafeCardConfig(
            shootDays: days,
            dateOverride: nil,
            volumePath: scanResult.volumePath,
            volumeName: scanResult.volumeName,
            videoSubfolders: projectConfig.hasMultipleCameras ? [""] : [],
            photoSubfolders: [],
            videoBins: videoBins,
            photoBins: [],
            fileSubfolderMap: [:]
        )
    }

    /// Gefilterde video submappen (lege strings verwijderd) — legacy
    var effectiveVideoSubfolders: [String] {
        videoSubfolders.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Gefilterde foto submappen (lege strings verwijderd) — legacy
    var effectivePhotoSubfolders: [String] {
        photoSubfolders.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Effectieve video bin namen (lege namen verwijderd)
    var effectiveVideoBinNames: [String] {
        videoBins.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Effectieve foto bin namen (lege namen verwijderd)
    var effectivePhotoBinNames: [String] {
        photoBins.map { $0.name.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Aantal bestanden in een specifieke bin
    func filesCountInBin(_ binName: String) -> Int {
        fileSubfolderMap.values.filter { $0 == binName }.count
    }

    /// Wijs een bestand toe aan een bin (of verwijder toewijzing met nil)
    mutating func assignFile(_ fileId: UUID, toBin binName: String?) {
        if let name = binName, !name.isEmpty {
            fileSubfolderMap[fileId] = name
        } else {
            fileSubfolderMap.removeValue(forKey: fileId)
        }
    }

    /// Wijs meerdere bestanden toe aan een bin
    mutating func assignFiles(_ fileIds: Set<UUID>, toBin binName: String?) {
        for id in fileIds {
            assignFile(id, toBin: binName)
        }
    }

    /// Verwijder alle assignments voor een specifieke bin
    mutating func removeAssignmentsForBin(_ binName: String) {
        fileSubfolderMap = fileSubfolderMap.filter { $0.value != binName }
    }
}

// MARK: - Legacy Shoot Config (backward compatibility)

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
    let skippedCount: Int  // Aantal overgeslagen duplicaten

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
    var isDuplicate: Bool = false  // Bestand bestaat al in project (naam + grootte match)
}
