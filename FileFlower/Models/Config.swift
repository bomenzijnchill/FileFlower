import Foundation

struct Config: Codable {
    var projectRoots: [String]
    var musicClassification: MusicMode
    var language: [String]              // Legacy - gebruik appLanguage
    var appLanguage: String             // Actieve UI taal (en, nl, de, fr, es)
    var recentProjectsCacheSize: Int
    var mappings: [String: ProjectMapping]
    var network: NetworkConfig
    var stockWebsites: [String]
    var blacklistedWebsites: [String]
    var customDownloadsFolder: String?
    var showPopupAfterDownload: Bool
    var bringPremiereToFront: Bool
    var autoOpenBridgePanel: Bool
    var startAtLogin: Bool
    var useMLXClassification: Bool
    var mlxModelPath: String?
    var mlxModelName: String
    var useWebScraping: Bool
    var useGenreMoodDetection: Bool     // Of genre/mood detectie ingeschakeld is
    var useSfxSubfolders: Bool          // Of SFX in subcategorie submappen gesorteerd wordt
    var folderSyncs: [FolderSync]       // Folder sync configuraties
    var youtube4KDownloaderFolder: String?  // Map waar 4K Video Downloader bestanden opslaat
    var analyticsEnabled: Bool          // Of anonieme analytics data verstuurd wordt (opt-in)
    var anonymousId: String             // Anonieme device identifier voor analytics
    var termsAcceptedVersion: String?   // Welke versie van de voorwaarden geaccepteerd is
    var termsAcceptedDate: Date?        // Wanneer de voorwaarden geaccepteerd zijn
    var filterServerProjectsToLocal: Bool  // Filter server-projecten tot alleen op deze Mac geopende
    var autoAddActiveProjectRoot: Bool     // Voeg automatisch de root toe van een open Premiere project
    var savesFilesNextToProject: Bool      // Of gebruiker bestanden naast project opslaat
    var useClaudeClassification: Bool        // Of Claude API classificatie ingeschakeld is
    var userWorkflowType: WorkflowType     // Type werk dat de gebruiker doet
    var folderStructurePreset: FolderStructurePreset  // Voorkeursindeling van mappen
    var customFolderTemplate: CustomFolderTemplate?   // Template mappenstructuur voor .custom preset
    var cloudStorageWebsites: [String]              // Cloud storage websites (Dropbox, Google Drive)
    var loadFolderPresets: [LoadFolderPreset]        // Veelgebruikte mappen voor snelle import
    var bringResolveToFront: Bool              // Breng DaVinci Resolve naar voren na import
    var resolveAutoImport: Bool                // Automatisch importeren in Resolve Media Pool

    static let defaultCloudStorageWebsites = [
        "drive.google.com", "googleusercontent.com",
        "dropbox.com", "dl.dropboxusercontent.com"
    ]

    static let defaultStockWebsites = [
        "artlist.io", "artgrid.io", "motionarray.com", "elements.envato.com",
        "epidemicsound.com", "soundstripe.com", "storyblocks.com", "adobe.com/stock",
        "shutterstock.com", "pond5.com", "premiumbeat.com", "audiojungle.net",
        "videohive.net", "motionvfx.com", "rocketstock.com", "filmstro.com",
        "musicbed.com", "soundsnap.com", "freesound.org", "bmgproductionmusic.com",
        "apmmusic.com", "universalproductionmusic.com", "audionetwork.com", "boomlibrary.com",
        "sonniss.com", "zapsplat.com", "mixkit.co", "pixabay.com", "pexels.com",
        "unsplash.com", "freepik.com", "videoblocks.com", "fxhome.com", "productioncrate.com",
        "footagecrate.com", "cinepacks.com", "lensdistortions.com", "motionbro.com",
        "aejuice.com", "filmbilder.com", "frame.io", "bbc.co.uk/sounds", "youtube.com/audiolibrary",
        "orangesounds.com", "elevenlabs.io", "respeecher.com", "wondercraft.ai", "murf.ai",
        "play.ht", "lalal.ai", "jinglepunks.com", "epidemicfoley.com", "krotos.com",
        "rode.com", "bigfilmdesign.com", "nitroplug.com", "lottiefiles.com", "iconscout.com",
        "motionelements.com", "vatoelements.com", "dissolve.com", "clipstill.com",
        "depositphotos.com", "canstockphoto.com", "storyhunter.com", "wirestock.com",
        "gettyimages.com", "istockphoto.com", "dreamstime.com", "megatrax.com",
        "musicrevolution.com", "bensound.com", "incompetech.com", "filmsupply.com",
        "artlist.io/sfx", "soundly.com", "prosoundeffects.com", "gramoscopemusic.com",
        "marmosetmusic.com", "tunetank.com", "mixamo.com", "turbosquid.com",
        "cgtrader.com", "sketchfab.com"
    ]
    
    static let `default` = Config(
        projectRoots: [],
        musicClassification: .mood,
        language: ["nl", "en"],
        appLanguage: "en",
        recentProjectsCacheSize: 50,
        mappings: [:],
        network: NetworkConfig(premiereBridgeUrl: "http://127.0.0.1:17890"),
        stockWebsites: defaultStockWebsites,
        blacklistedWebsites: [],
        customDownloadsFolder: nil,
        showPopupAfterDownload: true,
        bringPremiereToFront: true,
        autoOpenBridgePanel: true,
        startAtLogin: false,
        useMLXClassification: false,
        mlxModelPath: nil,
        mlxModelName: "TinyLlama/TinyLlama-1.1B-Chat-v1.0",
        useWebScraping: true,
        useGenreMoodDetection: true,
        useSfxSubfolders: true,
        folderSyncs: [],
        youtube4KDownloaderFolder: nil,
        analyticsEnabled: false,
        anonymousId: UUID().uuidString,
        termsAcceptedVersion: nil,
        termsAcceptedDate: nil,
        filterServerProjectsToLocal: true,
        autoAddActiveProjectRoot: true,
        savesFilesNextToProject: true,
        useClaudeClassification: false,
        userWorkflowType: .videoEditor,
        folderStructurePreset: .standard,
        customFolderTemplate: nil,
        cloudStorageWebsites: defaultCloudStorageWebsites,
        loadFolderPresets: [],
        bringResolveToFront: true,
        resolveAutoImport: true
    )

    // Default init
    init(
        projectRoots: [String],
        musicClassification: MusicMode,
        language: [String],
        appLanguage: String = "en",
        recentProjectsCacheSize: Int,
        mappings: [String: ProjectMapping],
        network: NetworkConfig,
        stockWebsites: [String],
        blacklistedWebsites: [String],
        customDownloadsFolder: String?,
        showPopupAfterDownload: Bool = true,
        bringPremiereToFront: Bool = true,
        autoOpenBridgePanel: Bool = true,
        startAtLogin: Bool = false,
        useMLXClassification: Bool = false,
        mlxModelPath: String? = nil,
        mlxModelName: String = "TinyLlama/TinyLlama-1.1B-Chat-v1.0",
        useWebScraping: Bool = true,
        useGenreMoodDetection: Bool = true,
        useSfxSubfolders: Bool = true,
        folderSyncs: [FolderSync] = [],
        youtube4KDownloaderFolder: String? = nil,
        analyticsEnabled: Bool = false,
        anonymousId: String = UUID().uuidString,
        termsAcceptedVersion: String? = nil,
        termsAcceptedDate: Date? = nil,
        filterServerProjectsToLocal: Bool = true,
        autoAddActiveProjectRoot: Bool = true,
        savesFilesNextToProject: Bool = true,
        useClaudeClassification: Bool = false,
        userWorkflowType: WorkflowType = .videoEditor,
        folderStructurePreset: FolderStructurePreset = .standard,
        customFolderTemplate: CustomFolderTemplate? = nil,
        cloudStorageWebsites: [String] = defaultCloudStorageWebsites,
        loadFolderPresets: [LoadFolderPreset] = [],
        bringResolveToFront: Bool = true,
        resolveAutoImport: Bool = true
    ) {
        self.projectRoots = projectRoots
        self.musicClassification = musicClassification
        self.language = language
        self.appLanguage = appLanguage
        self.recentProjectsCacheSize = recentProjectsCacheSize
        self.mappings = mappings
        self.network = network
        self.stockWebsites = stockWebsites
        self.blacklistedWebsites = blacklistedWebsites
        self.customDownloadsFolder = customDownloadsFolder
        self.showPopupAfterDownload = showPopupAfterDownload
        self.bringPremiereToFront = bringPremiereToFront
        self.autoOpenBridgePanel = autoOpenBridgePanel
        self.startAtLogin = startAtLogin
        self.useMLXClassification = useMLXClassification
        self.mlxModelPath = mlxModelPath
        self.mlxModelName = mlxModelName
        self.useWebScraping = useWebScraping
        self.useGenreMoodDetection = useGenreMoodDetection
        self.useSfxSubfolders = useSfxSubfolders
        self.folderSyncs = folderSyncs
        self.youtube4KDownloaderFolder = youtube4KDownloaderFolder
        self.analyticsEnabled = analyticsEnabled
        self.anonymousId = anonymousId
        self.termsAcceptedVersion = termsAcceptedVersion
        self.termsAcceptedDate = termsAcceptedDate
        self.filterServerProjectsToLocal = filterServerProjectsToLocal
        self.autoAddActiveProjectRoot = autoAddActiveProjectRoot
        self.savesFilesNextToProject = savesFilesNextToProject
        self.useClaudeClassification = useClaudeClassification
        self.userWorkflowType = userWorkflowType
        self.folderStructurePreset = folderStructurePreset
        self.customFolderTemplate = customFolderTemplate
        self.cloudStorageWebsites = cloudStorageWebsites
        self.loadFolderPresets = loadFolderPresets
        self.bringResolveToFront = bringResolveToFront
        self.resolveAutoImport = resolveAutoImport
    }

    // Custom decoder voor migratie van oude configs
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectRoots = try container.decodeIfPresent([String].self, forKey: .projectRoots) ?? []
        musicClassification = try container.decodeIfPresent(MusicMode.self, forKey: .musicClassification) ?? .mood
        language = try container.decodeIfPresent([String].self, forKey: .language) ?? ["nl", "en"]

        // Migratie: als appLanguage niet bestaat, gebruik eerste taal uit legacy language array
        if let existingAppLanguage = try container.decodeIfPresent(String.self, forKey: .appLanguage) {
            appLanguage = existingAppLanguage
        } else {
            // Migreer van oude language array naar appLanguage
            let legacyLanguages = try container.decodeIfPresent([String].self, forKey: .language) ?? ["en"]
            appLanguage = legacyLanguages.first ?? "en"
        }

        recentProjectsCacheSize = try container.decodeIfPresent(Int.self, forKey: .recentProjectsCacheSize) ?? 50
        mappings = try container.decodeIfPresent([String: ProjectMapping].self, forKey: .mappings) ?? [:]
        network = try container.decodeIfPresent(NetworkConfig.self, forKey: .network) ?? NetworkConfig(premiereBridgeUrl: "http://127.0.0.1:17890")
        stockWebsites = try container.decodeIfPresent([String].self, forKey: .stockWebsites) ?? Config.defaultStockWebsites
        blacklistedWebsites = try container.decodeIfPresent([String].self, forKey: .blacklistedWebsites) ?? []
        customDownloadsFolder = try container.decodeIfPresent(String.self, forKey: .customDownloadsFolder)
        showPopupAfterDownload = try container.decodeIfPresent(Bool.self, forKey: .showPopupAfterDownload) ?? true
        bringPremiereToFront = try container.decodeIfPresent(Bool.self, forKey: .bringPremiereToFront) ?? true
        autoOpenBridgePanel = try container.decodeIfPresent(Bool.self, forKey: .autoOpenBridgePanel) ?? true
        startAtLogin = try container.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? false
        useMLXClassification = try container.decodeIfPresent(Bool.self, forKey: .useMLXClassification) ?? false
        mlxModelPath = try container.decodeIfPresent(String.self, forKey: .mlxModelPath)
        mlxModelName = try container.decodeIfPresent(String.self, forKey: .mlxModelName) ?? "TinyLlama/TinyLlama-1.1B-Chat-v1.0"
        useWebScraping = try container.decodeIfPresent(Bool.self, forKey: .useWebScraping) ?? true
        useGenreMoodDetection = try container.decodeIfPresent(Bool.self, forKey: .useGenreMoodDetection) ?? true
        useSfxSubfolders = try container.decodeIfPresent(Bool.self, forKey: .useSfxSubfolders) ?? true
        folderSyncs = try container.decodeIfPresent([FolderSync].self, forKey: .folderSyncs) ?? []
        youtube4KDownloaderFolder = try container.decodeIfPresent(String.self, forKey: .youtube4KDownloaderFolder)
        analyticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .analyticsEnabled) ?? false
        anonymousId = try container.decodeIfPresent(String.self, forKey: .anonymousId) ?? UUID().uuidString
        termsAcceptedVersion = try container.decodeIfPresent(String.self, forKey: .termsAcceptedVersion)
        termsAcceptedDate = try container.decodeIfPresent(Date.self, forKey: .termsAcceptedDate)
        filterServerProjectsToLocal = try container.decodeIfPresent(Bool.self, forKey: .filterServerProjectsToLocal) ?? true
        autoAddActiveProjectRoot = try container.decodeIfPresent(Bool.self, forKey: .autoAddActiveProjectRoot) ?? true
        savesFilesNextToProject = try container.decodeIfPresent(Bool.self, forKey: .savesFilesNextToProject) ?? true
        useClaudeClassification = try container.decodeIfPresent(Bool.self, forKey: .useClaudeClassification) ?? false
        userWorkflowType = try container.decodeIfPresent(WorkflowType.self, forKey: .userWorkflowType) ?? .videoEditor
        folderStructurePreset = try container.decodeIfPresent(FolderStructurePreset.self, forKey: .folderStructurePreset) ?? .standard
        customFolderTemplate = try container.decodeIfPresent(CustomFolderTemplate.self, forKey: .customFolderTemplate)
        cloudStorageWebsites = try container.decodeIfPresent([String].self, forKey: .cloudStorageWebsites) ?? Config.defaultCloudStorageWebsites
        loadFolderPresets = try container.decodeIfPresent([LoadFolderPreset].self, forKey: .loadFolderPresets) ?? []
        bringResolveToFront = try container.decodeIfPresent(Bool.self, forKey: .bringResolveToFront) ?? true
        resolveAutoImport = try container.decodeIfPresent(Bool.self, forKey: .resolveAutoImport) ?? true
    }
    
    // Custom encoder
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(projectRoots, forKey: .projectRoots)
        try container.encode(musicClassification, forKey: .musicClassification)
        try container.encode(language, forKey: .language)
        try container.encode(appLanguage, forKey: .appLanguage)
        try container.encode(recentProjectsCacheSize, forKey: .recentProjectsCacheSize)
        try container.encode(mappings, forKey: .mappings)
        try container.encode(network, forKey: .network)
        try container.encode(stockWebsites, forKey: .stockWebsites)
        try container.encode(blacklistedWebsites, forKey: .blacklistedWebsites)
        try container.encodeIfPresent(customDownloadsFolder, forKey: .customDownloadsFolder)
        try container.encode(showPopupAfterDownload, forKey: .showPopupAfterDownload)
        try container.encode(bringPremiereToFront, forKey: .bringPremiereToFront)
        try container.encode(autoOpenBridgePanel, forKey: .autoOpenBridgePanel)
        try container.encode(startAtLogin, forKey: .startAtLogin)
        try container.encode(useMLXClassification, forKey: .useMLXClassification)
        try container.encodeIfPresent(mlxModelPath, forKey: .mlxModelPath)
        try container.encode(mlxModelName, forKey: .mlxModelName)
        try container.encode(useWebScraping, forKey: .useWebScraping)
        try container.encode(useGenreMoodDetection, forKey: .useGenreMoodDetection)
        try container.encode(useSfxSubfolders, forKey: .useSfxSubfolders)
        try container.encode(folderSyncs, forKey: .folderSyncs)
        try container.encodeIfPresent(youtube4KDownloaderFolder, forKey: .youtube4KDownloaderFolder)
        try container.encode(analyticsEnabled, forKey: .analyticsEnabled)
        try container.encode(anonymousId, forKey: .anonymousId)
        try container.encodeIfPresent(termsAcceptedVersion, forKey: .termsAcceptedVersion)
        try container.encodeIfPresent(termsAcceptedDate, forKey: .termsAcceptedDate)
        try container.encode(filterServerProjectsToLocal, forKey: .filterServerProjectsToLocal)
        try container.encode(autoAddActiveProjectRoot, forKey: .autoAddActiveProjectRoot)
        try container.encode(savesFilesNextToProject, forKey: .savesFilesNextToProject)
        try container.encode(useClaudeClassification, forKey: .useClaudeClassification)
        try container.encode(userWorkflowType, forKey: .userWorkflowType)
        try container.encode(folderStructurePreset, forKey: .folderStructurePreset)
        try container.encodeIfPresent(customFolderTemplate, forKey: .customFolderTemplate)
        try container.encode(cloudStorageWebsites, forKey: .cloudStorageWebsites)
        try container.encode(loadFolderPresets, forKey: .loadFolderPresets)
        try container.encode(bringResolveToFront, forKey: .bringResolveToFront)
        try container.encode(resolveAutoImport, forKey: .resolveAutoImport)
    }
    
    enum CodingKeys: String, CodingKey {
        case projectRoots
        case musicClassification
        case language
        case appLanguage
        case recentProjectsCacheSize
        case mappings
        case network
        case stockWebsites
        case blacklistedWebsites
        case customDownloadsFolder
        case showPopupAfterDownload
        case bringPremiereToFront
        case autoOpenBridgePanel
        case startAtLogin
        case useMLXClassification
        case mlxModelPath
        case mlxModelName
        case useWebScraping
        case useGenreMoodDetection
        case useSfxSubfolders
        case folderSyncs
        case youtube4KDownloaderFolder
        case analyticsEnabled
        case anonymousId
        case termsAcceptedVersion
        case termsAcceptedDate
        case filterServerProjectsToLocal
        case autoAddActiveProjectRoot
        case savesFilesNextToProject
        case useClaudeClassification
        case userWorkflowType
        case folderStructurePreset
        case customFolderTemplate
        case cloudStorageWebsites
        case loadFolderPresets
        case bringResolveToFront
        case resolveAutoImport
    }
    
    // Helper om alleen custom toegevoegde websites te krijgen (exclusief standaard)
    var customStockWebsites: [String] {
        stockWebsites.filter { !Config.defaultStockWebsites.contains($0) }
    }
}

enum MusicMode: String, Codable {
    case mood = "mood"
    case genre = "genre"
}

enum WorkflowType: String, Codable, CaseIterable {
    case videoEditor = "video_editor"
    case graphicDesign = "graphic_design"
    case motionGraphics = "motion_graphics"
    case soundDesign = "sound_design"
    case other = "other"

    var displayKey: String.LocalizationValue {
        switch self {
        case .videoEditor: return "workflow.type.video_editor"
        case .graphicDesign: return "workflow.type.graphic_design"
        case .motionGraphics: return "workflow.type.motion_graphics"
        case .soundDesign: return "workflow.type.sound_design"
        case .other: return "workflow.type.other"
        }
    }

    var icon: String {
        switch self {
        case .videoEditor: return "film"
        case .graphicDesign: return "paintbrush.fill"
        case .motionGraphics: return "sparkles"
        case .soundDesign: return "waveform"
        case .other: return "ellipsis.circle"
        }
    }
}

// FolderStructurePreset, FolderNode, FolderTypeMapping, CustomFolderTemplate
// zijn verplaatst naar Shared/SharedConfig.swift (gedeeld met Finder Sync Extension)

struct ProjectMapping: Codable {
    var finderToPremiere: [String: String]
    var preferences: [String: String]
    
    init(finderToPremiere: [String: String] = [:], preferences: [String: String] = [:]) {
        self.finderToPremiere = finderToPremiere
        self.preferences = preferences
    }
}

struct NetworkConfig: Codable {
    var premiereBridgeUrl: String
}

