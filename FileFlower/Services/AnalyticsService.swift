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

    // Session tracking
    private var sessionStart: Date?
    private var sessionDownloadsCount = 0
    private var sessionImportsCount = 0
    private var sessionErrorsCount = 0

    private var isEnabled: Bool {
        AppState.shared.config.analyticsEnabled
    }

    private var anonymousId: String {
        AppState.shared.config.anonymousId
    }

    private init() {
        loadQueueFromDisk()
        startFlushTimer()
    }

    // MARK: - Public API

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

        track(.appLaunched())
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

        // Stuur alle events direct bij afsluiten
        flush()
    }

    /// Increment session counters
    func incrementDownloads() { sessionDownloadsCount += 1 }
    func incrementImports() { sessionImportsCount += 1 }
    func incrementErrors() { sessionErrorsCount += 1 }

    // MARK: - Opt-in/Out

    func optIn() {
        AppState.shared.config.analyticsEnabled = true
        AppState.shared.saveConfig()
        startSession()
        #if DEBUG
        print("AnalyticsService: Opt-in - analytics ingeschakeld")
        #endif
    }

    func optOut() {
        AppState.shared.config.analyticsEnabled = false
        AppState.shared.saveConfig()
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
