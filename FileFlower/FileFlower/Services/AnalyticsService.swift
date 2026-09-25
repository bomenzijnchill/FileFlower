import Foundation

/// Service voor het tracken van anonieme analytics events
/// Events worden lokaal gebufferd en periodiek naar Supabase verstuurd
class AnalyticsService {
    static let shared = AnalyticsService()

    private let supabaseClient = SupabaseClient()
    private var eventQueue: [AnalyticsEvent] = []
    private let queue = DispatchQueue(label: "com.fileflower.analytics", qos: .utility)
    private var flushTimer: Timer?
    private let maxBatchSize = 20
    private let flushInterval: TimeInterval = 300 // 5 minuten
    /// Bovengrens op de lokale buffer bij langdurige verzendproblemen
    private let maxQueuedEvents = 500

    // Session tracking
    private var sessionStart: Date?
    private var sessionDownloadsCount = 0
    private var sessionImportsCount = 0
    private var sessionErrorsCount = 0

    /// Gecachte config-waarden. AppState is @MainActor terwijl flush()/track() vanaf
    /// achtergrond-queues draaien — AppState.shared.config daar lezen was een data race.
    private let settingsLock = NSLock()
    private var cachedEnabled: Bool = false
    private var cachedAnonymousId: String = ""

    private var isEnabled: Bool {
        settingsLock.lock(); defer { settingsLock.unlock() }
        return cachedEnabled
    }

    private var anonymousId: String {
        settingsLock.lock(); defer { settingsLock.unlock() }
        return cachedAnonymousId
    }

    /// Werk de gecachte instellingen bij (aanroepen vanaf de MainActor bij config-wijziging).
    func refreshSettings(enabled: Bool, anonymousId: String) {
        settingsLock.lock()
        cachedEnabled = enabled
        cachedAnonymousId = anonymousId
        settingsLock.unlock()
    }

    private init() {
        loadQueueFromDisk()
        startFlushTimer()
    }

    // MARK: - Public API

    /// Verwijder persoonlijke info uit strings die naar analytics gaan: het home-pad
    /// (incl. macOS-gebruikersnaam) wordt "~", en resterende /Users/<naam>-paden worden
    /// geredigeerd. Voorkomt het lekken van bestandspaden en gebruikersnaam in error-events.
    static func redactPII(_ string: String) -> String {
        var s = string
        let home = NSHomeDirectory()
        if !home.isEmpty {
            s = s.replacingOccurrences(of: home, with: "~")
        }
        s = s.replacingOccurrences(
            of: #"/Users/[^/\s]+"#,
            with: "/Users/<redacted>",
            options: .regularExpression
        )
        return s
    }

    /// Track een analytics event
    func track(_ event: AnalyticsEvent) {
        guard isEnabled else { return }

        queue.async { [weak self] in
            self?.eventQueue.append(event)
            self?.saveQueueToDisk()

            // Auto-flush als batch size bereikt is
            if let count = self?.eventQueue.count, count >= self?.maxBatchSize ?? 20 {
                self?.flush()
            }
        }
    }

    /// Stuur alle gebufferde events
    func flush() {
        queue.async { [weak self] in
            guard let self = self, !self.eventQueue.isEmpty else { return }

            let eventsToSend = self.eventQueue
            self.eventQueue.removeAll()
            self.saveQueueToDisk()

            self.supabaseClient.sendEvents(eventsToSend, anonymousId: self.anonymousId) { success in
                if !success {
                    // Events terug in de queue als ze niet verstuurd konden worden
                    self.queue.async {
                        self.eventQueue.insert(contentsOf: eventsToSend, at: 0)
                        // Cap de queue: bij een langdurige storing groeit hij anders
                        // onbegrensd (elke 5 min een nieuwe batch erbij).
                        if self.eventQueue.count > self.maxQueuedEvents {
                            self.eventQueue = Array(self.eventQueue.suffix(self.maxQueuedEvents))
                        }
                        self.saveQueueToDisk()
                        #if DEBUG
                        print("AnalyticsService: Events terug in queue na fout (\(eventsToSend.count) events)")
                        #endif
                    }
                } else {
                    #if DEBUG
                    print("AnalyticsService: \(eventsToSend.count) events succesvol verstuurd")
                    #endif
                }
            }
        }
    }

    /// Start een nieuwe sessie
    func startSession() {
        sessionStart = Date()
        sessionDownloadsCount = 0
        sessionImportsCount = 0
        sessionErrorsCount = 0

        // Settings snapshot per sessie (ook de cache vullen vóór het eerste event)
        let config = AppState.shared.config
        refreshSettings(enabled: config.analyticsEnabled, anonymousId: config.anonymousId)

        track(.appLaunched())

        track(.settingsSnapshot(
            selectedNLEs: config.selectedNLEs.joined(separator: ","),
            folderPreset: config.folderStructurePreset.rawValue,
            musicClassify: config.useGenreMoodDetection,
            sfxSubfolders: config.useSfxSubfolders,
            autoStart: config.startAtLogin
        ))
    }

    /// Eindig de huidige sessie en stuur samenvatting
    func endSession() {
        guard let start = sessionStart else { return }

        let durationMinutes = Int(Date().timeIntervalSince(start) / 60)
        track(.sessionSummary(
            durationMinutes: durationMinutes,
            downloadsCount: sessionDownloadsCount,
            importsCount: sessionImportsCount,
            errorsCount: sessionErrorsCount
        ))

        // Stuur alle events synchroon bij afsluiten (blokkeert tot netwerk klaar is)
        flushSync()
    }

    /// Synchrone flush — blokkeert de huidige thread tot events verstuurd zijn.
    /// Gebruik alleen bij app-afsluiting om te voorkomen dat events verloren gaan.
    private func flushSync() {
        // Haal events direct op (niet via async queue, want de app sluit af)
        var eventsToSend: [AnalyticsEvent] = []
        queue.sync {
            eventsToSend = self.eventQueue
            self.eventQueue.removeAll()
            self.saveQueueToDisk()
        }

        guard !eventsToSend.isEmpty else { return }

        let semaphore = DispatchSemaphore(value: 0)

        // Precies ÉÉN partij mag de events terugzetten: de completion óf de timeout.
        // Anders zetten beide ze terug → duplicaten in Supabase bij de volgende launch.
        let handledLock = NSLock()
        var handled = false
        func claimHandling() -> Bool {
            handledLock.lock(); defer { handledLock.unlock() }
            if handled { return false }
            handled = true
            return true
        }

        supabaseClient.sendEvents(eventsToSend, anonymousId: self.anonymousId) { success in
            guard claimHandling() else {
                semaphore.signal()
                return
            }
            if !success {
                // Events terug opslaan zodat ze bij volgende launch verstuurd worden
                self.queue.sync {
                    self.eventQueue.insert(contentsOf: eventsToSend, at: 0)
                    self.saveQueueToDisk()
                }
                #if DEBUG
                print("AnalyticsService: Sync flush mislukt, \(eventsToSend.count) events opgeslagen voor volgende launch")
                #endif
            } else {
                #if DEBUG
                print("AnalyticsService: Sync flush geslaagd — \(eventsToSend.count) events verstuurd")
                #endif
            }
            semaphore.signal()
        }

        // Wacht maximaal 10 seconden op het netwerk verzoek
        let result = semaphore.wait(timeout: .now() + 10)
        if result == .timedOut, claimHandling() {
            #if DEBUG
            print("AnalyticsService: Sync flush timeout — events worden bij volgende launch verstuurd")
            #endif
            // Events zijn al van disk verwijderd, zet ze terug
            queue.sync {
                self.eventQueue.insert(contentsOf: eventsToSend, at: 0)
                self.saveQueueToDisk()
            }
        }
    }

    /// Increment session counters
    func incrementDownloads() { sessionDownloadsCount += 1 }
    func incrementImports() { sessionImportsCount += 1 }
    func incrementErrors() { sessionErrorsCount += 1 }

    // MARK: - Opt-in/Out

    func optIn() {
        AppState.shared.config.analyticsEnabled = true
        AppState.shared.saveConfig()
        refreshSettings(enabled: true, anonymousId: AppState.shared.config.anonymousId)
        startSession()
        #if DEBUG
        print("AnalyticsService: Opt-in - analytics ingeschakeld")
        #endif
    }

    func optOut() {
        AppState.shared.config.analyticsEnabled = false
        AppState.shared.saveConfig()
        refreshSettings(enabled: false, anonymousId: AppState.shared.config.anonymousId)
        // Verwijder alle gebufferde events
        queue.async { [weak self] in
            self?.eventQueue.removeAll()
            self?.saveQueueToDisk()
        }
        #if DEBUG
        print("AnalyticsService: Opt-out - analytics uitgeschakeld, queue geleegd")
        #endif
    }

    // MARK: - Persistentie

    private var queueFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FileFlower", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("analytics_queue.json")
    }

    private func saveQueueToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(eventQueue) else { return }
        try? data.write(to: queueFileURL)
    }

    private func loadQueueFromDisk() {
        guard let data = try? Data(contentsOf: queueFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        eventQueue = (try? decoder.decode([AnalyticsEvent].self, from: data)) ?? []

        if !eventQueue.isEmpty {
            #if DEBUG
            print("AnalyticsService: \(eventQueue.count) events geladen uit queue")
            #endif
        }
    }

    // MARK: - Timer

    private func startFlushTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.flushTimer = Timer.scheduledTimer(withTimeInterval: self.flushInterval, repeats: true) { [weak self] _ in
                self?.flush()
            }
        }
    }

    deinit {
        flushTimer?.invalidate()
    }
}
