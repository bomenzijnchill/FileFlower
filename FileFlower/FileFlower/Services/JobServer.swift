import Foundation
import NIO
import NIOHTTP1
import Combine

/// Lifecycle-status van een queued job — gebruikt door UI-polling (FileSafe report screen).
enum JobState {
    case pending       // Ligt nog in de queue, plugin heeft 'm niet opgehaald
    case inProgress    // Opgehaald door plugin, wacht op completion
    case completed(JobResult)
    case unknown       // Onbekende id (ook state na uitwerking door completeJob + GC)
}

class JobServer {
    static let shared = JobServer()

    private var group: EventLoopGroup?
    private var channel: Channel?
    // Premiere Pro job state (bestaand)
    private var pendingJobs: [UUID: JobRequest] = [:]
    private var completedJobs: [UUID: JobResult] = [:]
    private var sentJobs: [UUID: JobRequest] = [:] // Jobs die naar de plugin zijn gestuurd (voor hash tracking)

    // DaVinci Resolve job state
    private var resolvePendingJobs: [UUID: JobRequest] = [:]
    private var resolveCompletedJobs: [UUID: JobResult] = [:]
    private var resolveSentJobs: [UUID: JobRequest] = [:]

    // Begrens de completed-dicts zodat ze niet onbeperkt blijven groeien (memory leak):
    // bewaar alleen de laatste N resultaten in invoeg-volgorde.
    private var completedJobOrder: [UUID] = []
    private var resolveCompletedJobOrder: [UUID] = []
    private let maxCompletedJobs = 100

    // Job-dicts worden zowel op NIO event loop (getNextJob, completeJob)
    // als vanuit de UI (polling via jobState) geraadpleegd. Lock beschermt
    // concurrente lezen/schrijven.
    private let jobsLock = NSLock()

    private var isRunning = false
    private let serverQueue = DispatchQueue(label: "com.fileflower.jobserver", qos: .userInitiated)

    private let port: Int = 17890

    // Actief project vanuit Premiere Pro (gerapporteerd door CEP plugin)
    @Published private(set) var activeProjectPath: String?

    // Actief project vanuit DaVinci Resolve (gerapporteerd door Python bridge)
    @Published private(set) var resolveActiveProjectPath: String?

    // Media root gedetecteerd door Python bridge (gemeenschappelijk pad van alle clips)
    @Published private(set) var resolveMediaRoot: String?

    // Thread-safe kopie voor gebruik vanuit NIO event loop (getNextJob)
    private var lockedActiveProjectPath: String?
    private var lockedLastActiveProjectUpdate: Date?
    private var lockedResolveActiveProjectPath: String?
    private var lockedLastResolveActiveProjectUpdate: Date?
    private var lockedResolveMediaRoot: String?
    private let activeProjectLock = NSLock()

    private init() {}

    /// Update het actieve project pad (aangeroepen vanuit HTTP handler)
    func updateActiveProject(path: String?) {
        // Thread-safe update voor NIO event loop
        activeProjectLock.lock()
        lockedActiveProjectPath = path
        lockedLastActiveProjectUpdate = Date()
        activeProjectLock.unlock()

        // Publiceer naar main thread voor @Published (SwiftUI observers)
        DispatchQueue.main.async {
            self.activeProjectPath = path
        }
    }

    /// Aantal wachtende import-jobs (diagnostiek via /status)
    var pendingJobCount: Int {
        jobsLock.lock()
        defer { jobsLock.unlock() }
        return pendingJobs.count
    }

    /// Check of het actieve project nog vers is (binnen 10 seconden) — thread-safe
    var isActiveProjectFresh: Bool {
        activeProjectLock.lock()
        defer { activeProjectLock.unlock() }
        guard let lastUpdate = lockedLastActiveProjectUpdate else { return false }
        return Date().timeIntervalSince(lastUpdate) < 10
    }

    /// Thread-safe lezing van actief project path
    /// Niet-private: ook de /status-handler draait op de NIO event-loop en mag de
    /// @Published-property daarom niet rechtstreeks lezen.
    var threadSafeActiveProjectPath: String? {
        activeProjectLock.lock()
        defer { activeProjectLock.unlock() }
        return lockedActiveProjectPath
    }
    
    var isServerRunning: Bool {
        return isRunning && channel != nil
    }
    
    func start() throws {
        // Prevent multiple starts
        guard !isRunning else {
            #if DEBUG
            print("JobServer is already running")
            #endif
            return
        }
        
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group
        
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(server: self))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
        
        do {
            let channel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
            self.channel = channel
            self.isRunning = true
            
            #if DEBUG
            print("JobServer started successfully on http://127.0.0.1:\(port)")
            #endif
        } catch {
            self.group = nil
            throw error
        }
    }
    
    func wait() throws {
        // Keep the server running - wait for the channel to close
        guard let channel = channel else {
            throw NSError(domain: "JobServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server not started"])
        }
        try channel.closeFuture.wait()
    }
    
    func stop() {
        guard isRunning else {
            return
        }
        
        isRunning = false
        
        do {
            try channel?.close().wait()
        } catch {
            #if DEBUG
            print("Error closing channel: \(error)")
            #endif
        }

        do {
            try group?.syncShutdownGracefully()
        } catch {
            #if DEBUG
            print("Error shutting down event loop group: \(error)")
            #endif
        }

        channel = nil
        group = nil

        #if DEBUG
        print("JobServer stopped")
        #endif
    }
    
    func addJob(_ job: JobRequest) {
        jobsLock.lock()
        switch job.nleType {
        case .premiere:
            pendingJobs[job.id] = job
            #if DEBUG
            let pendingCount = pendingJobs.count
            #endif
            jobsLock.unlock()
            #if DEBUG
            print("JobServer: Premiere job toegevoegd - id: \(job.id)")
            print("JobServer: Pending Premiere jobs: \(pendingCount)")
            #endif
        case .resolve:
            resolvePendingJobs[job.id] = job
            #if DEBUG
            let pendingCount = resolvePendingJobs.count
            #endif
            jobsLock.unlock()
            #if DEBUG
            print("JobServer: Resolve job toegevoegd - id: \(job.id)")
            print("JobServer: Pending Resolve jobs: \(pendingCount)")
            #endif
        }
        #if DEBUG
        print("JobServer: Project: \(job.projectPath)")
        print("JobServer: Bin/folder path: \(job.premiereBinPath)")
        print("JobServer: Files: \(job.files)")
        #endif
    }
    
    func getNextJob() -> JobRequest? {
        jobsLock.lock()
        defer { jobsLock.unlock() }

        guard let activePath = threadSafeActiveProjectPath else {
            if !pendingJobs.isEmpty {
                #if DEBUG
                print("JobServer: getNextJob - geen actief project gerapporteerd, \(pendingJobs.count) jobs wachten")
                #endif
            }
            return nil
        }
        guard isActiveProjectFresh else {
            if !pendingJobs.isEmpty {
                #if DEBUG
                print("JobServer: getNextJob - actief project niet vers (>10s), \(pendingJobs.count) jobs wachten")
                #endif
            }
            return nil
        }

        // Zoek een job die matcht met het actieve project
        let normalizedActive = normalizePath(activePath)
        for (id, job) in pendingJobs {
            if Self.projectPathsMatch(job.projectPath, normalizedActive) {
                pendingJobs.removeValue(forKey: id)
                // Bewaar job zodat we pendingHashes kunnen opslaan bij completion
                sentJobs[id] = job
                #if DEBUG
                print("JobServer: Job opgehaald door CEP plugin - id: \(id)")
                print("JobServer: Remaining pending jobs: \(pendingJobs.count)")
                #endif
                return job
            }
        }
        #if DEBUG
        if !pendingJobs.isEmpty {
            print("JobServer: getNextJob - geen pad-match. normalized active: \(normalizedActive)")
            for (_, job) in pendingJobs {
                print("  pending: \(normalizePath(job.projectPath))")
            }
        }
        #endif
        return nil
    }

    /// Normaliseer pad voor vergelijking (verwijder trailing slash, resolv symlinks)
    private func normalizePath(_ path: String) -> String {
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// Verwijzen twee paden naar HETZELFDE project?
    ///
    /// Eén gedeelde regel voor zowel "mag er een import-job komen?" (QueueView) als
    /// "mag de plugin deze job ophalen?" (getNextJob). Die gebruikten voorheen
    /// verschillende regels: de queue accepteerde een projectMAP waarin het .prproj
    /// staat, maar getNextJob eiste exacte gelijkheid — de job werd dan wél aangemaakt
    /// maar nooit opgehaald, en het bestand belandde zonder import in de map.
    static func projectPathsMatch(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        let na = URL(fileURLWithPath: a).standardizedFileURL.path
        let nb = URL(fileURLWithPath: b).standardizedFileURL.path
        if na == nb { return true }
        // Het ene pad is het projectBESTAND, het andere de projectMAP eromheen
        if na.hasPrefix(nb + "/") || nb.hasPrefix(na + "/") { return true }
        // Of: map van het projectbestand is gelijk aan het andere pad
        let dirA = URL(fileURLWithPath: na).deletingLastPathComponent().path
        let dirB = URL(fileURLWithPath: nb).deletingLastPathComponent().path
        return dirA == nb || dirB == na
    }
    
    /// Voeg een resultaat toe en evict de oudste als de cap overschreden wordt.
    /// Caller MOET `jobsLock` vasthouden.
    private func storeCompleted(_ result: JobResult, into dict: inout [UUID: JobResult], order: inout [UUID]) {
        if dict[result.jobId] == nil {
            order.append(result.jobId)
        }
        dict[result.jobId] = result
        while order.count > maxCompletedJobs {
            let oldest = order.removeFirst()
            dict.removeValue(forKey: oldest)
        }
    }

    func completeJob(_ result: JobResult) {
        jobsLock.lock()
        storeCompleted(result, into: &completedJobs, order: &completedJobOrder)
        let originalJob = sentJobs.removeValue(forKey: result.jobId)
        jobsLock.unlock()

        // Haal de originele job op voor syncId en pendingHashes
        guard let originalJob = originalJob,
              let syncId = originalJob.syncId,
              !originalJob.pendingHashes.isEmpty else {
            return
        }

        // Bouw een mapping van filePath -> hash
        var pathToHash: [String: String] = [:]
        for (index, filePath) in originalJob.files.enumerated() {
            if index < originalJob.pendingHashes.count {
                pathToHash[filePath] = originalJob.pendingHashes[index]
            }
        }

        // Verzamel hashes voor bestanden die succesvol geïmporteerd zijn OF al in Premiere stonden
        var hashesToStore: Set<String> = []
        for filePath in result.importedFiles {
            if let hash = pathToHash[filePath] {
                hashesToStore.insert(hash)
            }
        }
        if let alreadyImported = result.alreadyImported {
            for filePath in alreadyImported {
                if let hash = pathToHash[filePath] {
                    hashesToStore.insert(hash)
                }
            }
        }

        if !hashesToStore.isEmpty {
            #if DEBUG
            print("JobServer: Opslaan van \(hashesToStore.count) hashes voor sync \(syncId)")
            #endif
            DispatchQueue.main.async {
                if let index = AppState.shared.config.folderSyncs.firstIndex(where: { $0.id == syncId }) {
                    for hash in hashesToStore {
                        AppState.shared.config.folderSyncs[index].syncedFileHashes.insert(hash)
                    }
                    AppState.shared.config.folderSyncs[index].lastSyncDate = Date()
                    AppState.shared.saveConfig()
                }
            }
        }

        // Log gefaalde bestanden
        if !result.failedFiles.isEmpty {
            #if DEBUG
            print("JobServer: \(result.failedFiles.count) bestanden gefaald, hashes NIET opgeslagen")
            #endif
        }
    }

    // MARK: - DaVinci Resolve Methods

    /// Update het actieve Resolve project pad en optionele media root (aangeroepen vanuit HTTP handler)
    func updateResolveActiveProject(path: String?, mediaRoot: String? = nil) {
        activeProjectLock.lock()
        lockedResolveActiveProjectPath = path
        lockedLastResolveActiveProjectUpdate = Date()
        lockedResolveMediaRoot = mediaRoot
        activeProjectLock.unlock()

        DispatchQueue.main.async {
            self.resolveActiveProjectPath = path
            self.resolveMediaRoot = mediaRoot
        }
    }

    /// Check of het actieve Resolve project nog vers is (binnen 10 seconden) — thread-safe
    var isResolveActiveProjectFresh: Bool {
        activeProjectLock.lock()
        defer { activeProjectLock.unlock() }
        guard let lastUpdate = lockedLastResolveActiveProjectUpdate else { return false }
        return Date().timeIntervalSince(lastUpdate) < 10
    }

    /// Thread-safe lezing van actief Resolve project path
    private var threadSafeResolveActiveProjectPath: String? {
        activeProjectLock.lock()
        defer { activeProjectLock.unlock() }
        return lockedResolveActiveProjectPath
    }

    /// Haal de volgende Resolve job op die matcht met het actieve Resolve project
    func getNextResolveJob() -> JobRequest? {
        jobsLock.lock()
        defer { jobsLock.unlock() }

        guard let activePath = threadSafeResolveActiveProjectPath else {
            if !resolvePendingJobs.isEmpty {
                #if DEBUG
                print("JobServer: getNextResolveJob - geen actief Resolve project, \(resolvePendingJobs.count) jobs wachten")
                #endif
            }
            return nil
        }
        guard isResolveActiveProjectFresh else {
            if !resolvePendingJobs.isEmpty {
                #if DEBUG
                print("JobServer: getNextResolveJob - actief Resolve project niet vers (>10s), \(resolvePendingJobs.count) jobs wachten")
                #endif
            }
            return nil
        }

        let normalizedActive = normalizePath(activePath)
        for (id, job) in resolvePendingJobs {
            if Self.projectPathsMatch(job.projectPath, normalizedActive) {
                resolvePendingJobs.removeValue(forKey: id)
                resolveSentJobs[id] = job
                #if DEBUG
                print("JobServer: Resolve job opgehaald door Python bridge - id: \(id)")
                print("JobServer: Remaining pending Resolve jobs: \(resolvePendingJobs.count)")
                #endif
                return job
            }
        }
        #if DEBUG
        if !resolvePendingJobs.isEmpty {
            print("JobServer: getNextResolveJob - geen pad-match. normalized active: \(normalizedActive)")
            for (_, job) in resolvePendingJobs {
                print("  pending: \(normalizePath(job.projectPath))")
            }
        }
        #endif
        return nil
    }

    // MARK: - Job state lookup (voor UI polling)

    /// Geef de huidige status van een job terug (Premiere OF Resolve, eerste match).
    /// Gebruikt door FileSafe import-polling om de wachtstatus naar de gebruiker te surface'n.
    func jobState(id: UUID) -> JobState {
        jobsLock.lock()
        defer { jobsLock.unlock() }

        if let result = completedJobs[id] ?? resolveCompletedJobs[id] {
            return .completed(result)
        }
        if sentJobs[id] != nil || resolveSentJobs[id] != nil {
            return .inProgress
        }
        if pendingJobs[id] != nil || resolvePendingJobs[id] != nil {
            return .pending
        }
        return .unknown
    }

    /// Verwerk het resultaat van een Resolve job
    func completeResolveJob(_ result: JobResult) {
        jobsLock.lock()
        storeCompleted(result, into: &resolveCompletedJobs, order: &resolveCompletedJobOrder)
        let originalJob = resolveSentJobs.removeValue(forKey: result.jobId)
        jobsLock.unlock()

        guard let originalJob = originalJob,
              let syncId = originalJob.syncId,
              !originalJob.pendingHashes.isEmpty else {
            return
        }

        // Zelfde hash-opslag logica als Premiere
        var pathToHash: [String: String] = [:]
        for (index, filePath) in originalJob.files.enumerated() {
            if index < originalJob.pendingHashes.count {
                pathToHash[filePath] = originalJob.pendingHashes[index]
            }
        }

        var hashesToStore: Set<String> = []
        for filePath in result.importedFiles {
            if let hash = pathToHash[filePath] {
                hashesToStore.insert(hash)
            }
        }
        if let alreadyImported = result.alreadyImported {
            for filePath in alreadyImported {
                if let hash = pathToHash[filePath] {
                    hashesToStore.insert(hash)
                }
            }
        }

        if !hashesToStore.isEmpty {
            #if DEBUG
            print("JobServer: Resolve - Opslaan van \(hashesToStore.count) hashes voor sync \(syncId)")
            #endif
            DispatchQueue.main.async {
                if let index = AppState.shared.config.folderSyncs.firstIndex(where: { $0.id == syncId }) {
                    for hash in hashesToStore {
                        AppState.shared.config.folderSyncs[index].syncedFileHashes.insert(hash)
                    }
                    AppState.shared.config.folderSyncs[index].lastSyncDate = Date()
                    AppState.shared.saveConfig()
                }
            }
        }

        if !result.failedFiles.isEmpty {
            #if DEBUG
            print("JobServer: Resolve - \(result.failedFiles.count) bestanden gefaald, hashes NIET opgeslagen")
            #endif
        }
    }
}

private class HTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    private let server: JobServer
    private var requestBuffer: ByteBuffer?
    
    init(server: JobServer) {
        self.server = server
    }

    /// Escape een string voor veilig gebruik in JSON values
    private func jsonEscape(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "\\", with: "\\\\")
        result = result.replacingOccurrences(of: "\"", with: "\\\"")
        result = result.replacingOccurrences(of: "\n", with: "\\n")
        result = result.replacingOccurrences(of: "\r", with: "\\r")
        result = result.replacingOccurrences(of: "\t", with: "\\t")
        return result
    }

    private var currentRequest: (head: HTTPRequestHead, body: ByteBuffer)?
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        
        switch part {
        case .head(let head):
            let bodyBuffer = context.channel.allocator.buffer(capacity: 0)
            currentRequest = (head, bodyBuffer)
            
            // If GET request, handle immediately
            if head.method == .GET {
                sendResponse(context: context, head: head, body: nil)
            }
            
        case .body(let buffer):
            if let (head, bodyBuffer) = currentRequest {
                var mutableBuffer = bodyBuffer
                var mutableInputBuffer = buffer
                mutableBuffer.writeBuffer(&mutableInputBuffer)
                currentRequest = (head, mutableBuffer)
            }
            
        case .end:
            if let (head, bodyBuffer) = currentRequest {
                sendResponse(context: context, head: head, body: bodyBuffer.readableBytes > 0 ? bodyBuffer : nil)
            }
            currentRequest = nil
        }
    }
    
    /// True als de Host-header naar loopback wijst (127.0.0.1 / localhost / ::1) of ontbreekt.
    /// Blokkeert DNS-rebinding: een kwaadaardige pagina die zijn domein naar 127.0.0.1 laat
    /// wijzen stuurt nog steeds zijn eigen domein als Host-header en wordt zo geweigerd.
    private static func isLoopbackHost(_ host: String?) -> Bool {
        guard let host = host, !host.isEmpty else { return true } // HTTP zonder Host-header toestaan
        var name = host
        if name.hasPrefix("[") {
            // IPv6 literal: [::1]:poort
            if let close = name.firstIndex(of: "]") {
                name = String(name[name.index(after: name.startIndex)..<close])
            }
        } else if let colon = name.lastIndex(of: ":") {
            name = String(name[..<colon]) // strip :poort
        }
        let lower = name.lowercased()
        return lower == "127.0.0.1" || lower == "localhost" || lower == "::1"
    }

    /// True als de Origin-header van een gewone webpagina komt.
    ///
    /// Legitieme clients zijn: de browser-extensies (`chrome-extension://`,
    /// `safari-web-extension://`, `moz-extension://`) en native clients zoals de CEP-plugin
    /// en de Python-bridge (die sturen géén Origin). Een willekeurige webpagina die
    /// `fetch('http://127.0.0.1:17890/deploy-template')` doet stuurt wél een http(s)-Origin —
    /// die weigeren we voor alles wat state muteert (CSRF-bescherming).
    private static func isDisallowedWebOrigin(_ origin: String?) -> Bool {
        guard let origin = origin, !origin.isEmpty, origin != "null" else { return false }
        let lower = origin.lowercased()
        if lower.hasPrefix("chrome-extension://")
            || lower.hasPrefix("safari-web-extension://")
            || lower.hasPrefix("moz-extension://") {
            return false
        }
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    private func sendResponse(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
        // Weiger state-muterende requests vanaf een gewone webpagina (CSRF).
        let isMutating = head.method != .GET && head.method != .OPTIONS && head.method != .HEAD
        if isMutating, Self.isDisallowedWebOrigin(head.headers.first(name: "Origin")) {
            var denyBody = context.channel.allocator.buffer(capacity: 48)
            denyBody.writeString("{\"error\":\"forbidden origin\"}")
            var denyHeaders = HTTPHeaders()
            denyHeaders.add(name: "Content-Type", value: "application/json")
            denyHeaders.add(name: "Content-Length", value: String(denyBody.readableBytes))
            var denyHead = HTTPResponseHead(version: .http1_1, status: .forbidden)
            denyHead.headers = denyHeaders
            context.write(wrapOutboundOut(.head(denyHead)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(denyBody))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            currentRequest = nil
            return
        }

        // Weiger requests met een niet-loopback Host (DNS-rebinding-bescherming).
        guard Self.isLoopbackHost(head.headers.first(name: "Host")) else {
            var denyBody = context.channel.allocator.buffer(capacity: 40)
            denyBody.writeString("{\"error\":\"forbidden host\"}")
            var denyHeaders = HTTPHeaders()
            denyHeaders.add(name: "Content-Type", value: "application/json")
            denyHeaders.add(name: "Content-Length", value: String(denyBody.readableBytes))
            var denyHead = HTTPResponseHead(version: .http1_1, status: .forbidden)
            denyHead.headers = denyHeaders
            context.write(wrapOutboundOut(.head(denyHead)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(denyBody))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            currentRequest = nil
            return
        }

        let response: (head: HTTPResponseHead, body: ByteBuffer?)

        switch (head.method, head.uri) {
        // ============================================================================
        // CORS PREFLIGHT - voor Chrome extensie
        // ============================================================================
        case (.OPTIONS, _):
            var corsBody = context.channel.allocator.buffer(capacity: 2)
            corsBody.writeString("")
            response = (
                head: HTTPResponseHead(version: .http1_1, status: .noContent),
                body: corsBody
            )
            
        // ============================================================================
        // HEALTH CHECK - voor Chrome extensie popup status
        // ============================================================================
        case (.GET, "/health"):
            var healthBody = context.channel.allocator.buffer(capacity: 100)
            healthBody.writeString("{\"status\":\"ok\",\"server\":\"FileFlower\",\"version\":\"1.0\"}")
            response = (
                head: HTTPResponseHead(version: .http1_1, status: .ok),
                body: healthBody
            )
            
        // ============================================================================
        // STATUS - voor CEP panel status check
        // ============================================================================
        case (.GET, "/status"):
            // Diagnostisch: laat zien of de NLE-plugin zich meldt en of er jobs klaarstaan.
            // Zonder dit is "bestand verplaatst maar niet geïmporteerd" niet te herleiden.
            // Via de lock-gespiegelde kopie: deze handler draait op de NIO event-loop,
            // terwijl de hoofdthread activeProjectPath schrijft.
            let activePath = server.threadSafeActiveProjectPath ?? ""
            let fresh = server.isActiveProjectFresh
            let pending = server.pendingJobCount
            let escaped = activePath
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let json = """
            {"status":"ok","server":"FileFlower","version":"1.0",\
            "activeProjectPath":"\(escaped)","activeProjectFresh":\(fresh),\
            "pendingJobs":\(pending)}
            """
            var statusBody = context.channel.allocator.buffer(capacity: json.utf8.count)
            statusBody.writeString(json)
            response = (
                head: HTTPResponseHead(version: .http1_1, status: .ok),
                body: statusBody
            )
            
        // ============================================================================
        // STOCK METADATA - ontvang metadata van Chrome extensie
        // ============================================================================
        case (.POST, "/stock-metadata"):
            if let body = body, body.readableBytes > 0 {
                var mutableBody = body
                if let bytes = mutableBody.readBytes(length: body.readableBytes) {
                    let data = Data(bytes)
                    
                    #if DEBUG
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("JobServer: Received stock metadata: \(jsonString.prefix(500))...")
                    }
                    #endif
                    
                    // Decode metadata
                    do {
                        let metadata = try JSONDecoder().decode(StockMetadata.self, from: data)
                        
                        // Add to cache (async)
                        Task {
                            await StockMetadataCache.shared.add(metadata)
                        }
                        
                        var okBody = context.channel.allocator.buffer(capacity: 100)
                        okBody.writeString("{\"status\":\"received\",\"title\":\"\(jsonEscape(metadata.title ?? "unknown"))\"}")
                        response = (
                            head: HTTPResponseHead(version: .http1_1, status: .ok),
                            body: okBody
                        )
                    } catch {
                        #if DEBUG
                        print("JobServer: Error decoding stock metadata: \(error)")
                        #endif
                        var errorBody = context.channel.allocator.buffer(capacity: 100)
                        errorBody.writeString("{\"status\":\"error\",\"message\":\"Invalid JSON format\"}")
                        response = (
                            head: HTTPResponseHead(version: .http1_1, status: .badRequest),
                            body: errorBody
                        )
                    }
                } else {
                    var errorBody = context.channel.allocator.buffer(capacity: 50)
                    errorBody.writeString("{\"status\":\"error\",\"message\":\"Empty body\"}")
                    response = (
                        head: HTTPResponseHead(version: .http1_1, status: .badRequest),
                        body: errorBody
                    )
                }
            } else {
                var errorBody = context.channel.allocator.buffer(capacity: 50)
                errorBody.writeString("{\"status\":\"error\",\"message\":\"No body\"}")
                response = (
                    head: HTTPResponseHead(version: .http1_1, status: .badRequest),
                    body: errorBody
                )
            }
            
        // ============================================================================
        // ACTIVE PROJECT - ontvang actief project van CEP plugin
        // ============================================================================
        case (.POST, "/active-project"):
            if let body = body, body.readableBytes > 0 {
                var mutableBody = body
                if let bytes = mutableBody.readBytes(length: body.readableBytes) {
                    let data = Data(bytes)
                    
                    // Log raw JSON for debugging
                    #if DEBUG
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("JobServer: Received active project: \(jsonString)")
                    }
                    #endif
                    
                    // Decode project path
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let projectPath = json["projectPath"] as? String {
                            server.updateActiveProject(path: projectPath)
                            
                            var okBody = context.channel.allocator.buffer(capacity: 100)
                            okBody.writeString("{\"status\":\"received\",\"projectPath\":\"\(jsonEscape(projectPath))\"}")
                            response = (
                                head: HTTPResponseHead(version: .http1_1, status: .ok),
                                body: okBody
                            )
                        } else {
                            // Geen project open (null of leeg)
                            server.updateActiveProject(path: nil)
                            var okBody = context.channel.allocator.buffer(capacity: 50)
                            okBody.writeString("{\"status\":\"received\",\"projectPath\":null}")
                            response = (
                                head: HTTPResponseHead(version: .http1_1, status: .ok),
                                body: okBody
                            )
                        }
                    } catch {
                        #if DEBUG
                        print("JobServer: Error decoding active project: \(error)")
                        #endif
                        var errorBody = context.channel.allocator.buffer(capacity: 100)
                        errorBody.writeString("{\"status\":\"error\",\"message\":\"Invalid JSON format\"}")
                        response = (
                            head: HTTPResponseHead(version: .http1_1, status: .badRequest),
                            body: errorBody
                        )
                    }
                } else {
                    var errorBody = context.channel.allocator.buffer(capacity: 50)
                    errorBody.writeString("{\"status\":\"error\",\"message\":\"Empty body\"}")
                    response = (
                        head: HTTPResponseHead(version: .http1_1, status: .badRequest),
                        body: errorBody
                    )
                }
            } else {
                var errorBody = context.channel.allocator.buffer(capacity: 50)
                errorBody.writeString("{\"status\":\"error\",\"message\":\"No body\"}")
                response = (
                    head: HTTPResponseHead(version: .http1_1, status: .badRequest),
                    body: errorBody
                )
            }
            
        // ============================================================================
        // JOBS API - bestaande job endpoints
        // ============================================================================
        case (.GET, "/jobs/next"):
            if let job = server.getNextJob() {
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(job),
                   let json = String(data: data, encoding: .utf8) {
                    var responseBody = context.channel.allocator.buffer(capacity: json.utf8.count)
                    responseBody.writeString(json)
                    response = (
                        head: HTTPResponseHead(version: .http1_1, status: .ok),
                        body: responseBody
                    )
                } else {
                    var errorBody = context.channel.allocator.buffer(capacity: 50)
                    errorBody.writeString("{\"error\":\"encoding failed\"}")
                    response = (
                        head: HTTPResponseHead(version: .http1_1, status: .internalServerError),
                        body: errorBody
                    )
                }
            } else {
                var emptyBody = context.channel.allocator.buffer(capacity: 2)
                emptyBody.writeString("{}")
                response = (
                    head: HTTPResponseHead(version: .http1_1, status: .ok),
                    body: emptyBody
                )
            }
            
        case (.POST, "/jobs"):
            // Handle job in body
            if let body = body, body.readableBytes > 0 {
                var mutableBody = body
                if let bytes = mutableBody.readBytes(length: body.readableBytes) {
                    let data = Data(bytes)
                    if let job = try? JSONDecoder().decode(JobRequest.self, from: data) {
                        server.addJob(job)
                    }
                }
            }
            var acceptedBody = context.channel.allocator.buffer(capacity: 30)
            acceptedBody.writeString("{\"status\":\"accepted\"}")
            response = (
                head: HTTPResponseHead(version: .http1_1, status: .accepted),
                body: acceptedBody
            )
            
        case (.POST, let uri) where uri.hasPrefix("/jobs/") && uri.hasSuffix("/result"):
            // Handle result in body
            if let body = body, body.readableBytes > 0 {
                var mutableBody = body
                if let bytes = mutableBody.readBytes(length: body.readableBytes) {
                    let data = Data(bytes)
                    if let result = try? JSONDecoder().decode(JobResult.self, from: data) {
                        server.completeJob(result)
                    }
                }
            }
            var okBody = context.channel.allocator.buffer(capacity: 30)
            okBody.writeString("{\"status\":\"received\"}")
            response = (
                head: HTTPResponseHead(version: .http1_1, status: .ok),
                body: okBody
            )
            
        // ============================================================================
        // DEPLOY TEMPLATE - Finder Sync Extension stuurt deploy verzoek
        // ============================================================================
        case (.POST, "/deploy-template"):
            if let body = body, body.readableBytes > 0 {
                var mutableBody = body
                if let bytes = mutableBody.readBytes(length: body.readableBytes) {
                    let data = Data(bytes)

                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let targetPath = json["targetPath"] as? String {
                            let targetURL = URL(fileURLWithPath: targetPath)

                            #if DEBUG
                            print("JobServer: Deploy template request voor: \(targetPath)")
                            #endif

                            let appConfig = AppState.shared.config
                            let count: Int

                            // Nieuwe flow: active template met parameters
                            if let template = TemplateDeployFlow.activeTemplate(for: appConfig) {
                                // Parse parameter values uit body (optioneel)
                                var values = TemplateDeployFlow.defaultValues(for: template)
                                if let rawValues = json["parameterValues"] as? [String: String] {
                                    for (k, v) in rawValues { values[k] = v }
                                }

                                // Valideer vereiste parameters
                                let missing = template.parameters.first { param in
                                    param.cannotBeEmpty &&
                                    (values[param.title]?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
                                }
                                if let missing = missing {
                                    var errorBody = context.channel.allocator.buffer(capacity: 200)
                                    errorBody.writeString(
                                        "{\"status\":\"error\",\"message\":\"Missing required parameter: \(jsonEscape(missing.title))\"}"
                                    )
                                    response = (
                                        head: HTTPResponseHead(version: .http1_1, status: .badRequest),
                                        body: errorBody
                                    )
                                    break
                                }

                                count = try TemplateDeployer.deploy(
                                    to: targetURL,
                                    template: template,
                                    values: values
                                )
                            } else {
                                // Legacy preset-flow
                                let config = DeployConfig(
                                    folderStructurePreset: appConfig.folderStructurePreset,
                                    customFolderTemplate: appConfig.customFolderTemplate
                                )
                                count = try TemplateDeployer.deploy(to: targetURL, config: config)
                            }

                            #if DEBUG
                            print("JobServer: \(count) mappen aangemaakt in \(targetPath)")
                            #endif

                            var okBody = context.channel.allocator.buffer(capacity: 100)
                            okBody.writeString("{\"status\":\"ok\",\"created\":\(count)}")
                            response = (
                                head: HTTPResponseHead(version: .http1_1, status: .ok),
                                body: okBody
                            )
                        } else {
                            var errorBody = context.channel.allocator.buffer(capacity: 100)
                            errorBody.writeString("{\"status\":\"error\",\"message\":\"Missing targetPath\"}")
                            response = (
                                head: HTTPResponseHead(version: .http1_1, status: .badRequest),
                                body: errorBody
                            )
                        }
                    } catch {
                        #if DEBUG
                        print("JobServer: Deploy error: \(error.localizedDescription)")
                        #endif
                        var errorBody = context.channel.allocator.buffer(capacity: 200)
                        errorBody.writeString("{\"status\":\"error\",\"message\":\"\(jsonEscape(error.localizedDescription))\"}")
                        response = (
                            head: HTTPResponseHead(version: .http1_1, status: .internalServerError),
                            body: errorBody
                        )
                    }
                } else {
                    var errorBody = context.channel.allocator.buffer(capacity: 50)
                    errorBody.writeString("{\"status\":\"error\",\"message\":\"Empty body\"}")
                    response = (
                        head: HTTPResponseHead(version: .http1_1, status: .badRequest),
                        body: errorBody
                    )
                }
            } else {
                var errorBody = context.channel.allocator.buffer(capacity: 50)
                errorBody.writeString("{\"status\":\"error\",\"message\":\"No body\"}")
                response = (
                    head: HTTPResponseHead(version: .http1_1, status: .badRequest),
                    body: errorBody
                )
            }

        // ============================================================================
        // RESOLVE ACTIVE PROJECT - ontvang actief project van Python bridge
        // ============================================================================
        case (.POST, "/resolve/active-project"):
            if let body = body, body.readableBytes > 0 {
                var mutableBody = body
                if let bytes = mutableBody.readBytes(length: body.readableBytes) {
                    let data = Data(bytes)

                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let projectPath = json["projectPath"] as? String {
                            // Parse optionele mediaRoot (gemeenschappelijk pad van clips in Media Pool)
                            let mediaRoot = json["mediaRoot"] as? String
                            server.updateResolveActiveProject(path: projectPath, mediaRoot: mediaRoot)

                            var okBody = context.channel.allocator.buffer(capacity: 150)
                            let mediaRootStr = mediaRoot != nil ? "\"\(jsonEscape(mediaRoot!))\"" : "null"
                            okBody.writeString("{\"status\":\"received\",\"projectPath\":\"\(jsonEscape(projectPath))\",\"mediaRoot\":\(mediaRootStr)}")
                            response = (
                                head: HTTPResponseHead(version: .http1_1, status: .ok),
                                body: okBody
                            )
                        } else {
                            server.updateResolveActiveProject(path: nil, mediaRoot: nil)
                            var okBody = context.channel.allocator.buffer(capacity: 50)
                            okBody.writeString("{\"status\":\"received\",\"projectPath\":null}")
                            response = (
                                head: HTTPResponseHead(version: .http1_1, status: .ok),
                                body: okBody
                            )
                        }
                    } catch {
                        #if DEBUG
                        print("JobServer: Error decoding Resolve active project: \(error)")
                        #endif
                        var errorBody = context.channel.allocator.buffer(capacity: 100)
                        errorBody.writeString("{\"status\":\"error\",\"message\":\"Invalid JSON format\"}")
                        response = (
                            head: HTTPResponseHead(version: .http1_1, status: .badRequest),
                            body: errorBody
                        )
                    }
                } else {
                    var errorBody = context.channel.allocator.buffer(capacity: 50)
                    errorBody.writeString("{\"status\":\"error\",\"message\":\"Empty body\"}")
                    response = (
                        head: HTTPResponseHead(version: .http1_1, status: .badRequest),
                        body: errorBody
                    )
                }
            } else {
                var errorBody = context.channel.allocator.buffer(capacity: 50)
                errorBody.writeString("{\"status\":\"error\",\"message\":\"No body\"}")
                response = (
                    head: HTTPResponseHead(version: .http1_1, status: .badRequest),
                    body: errorBody
                )
            }

        // ============================================================================
        // RESOLVE JOBS - endpoints voor Python bridge
        // ============================================================================
        case (.GET, "/resolve/jobs/next"):
            if let job = server.getNextResolveJob() {
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(job),
                   let json = String(data: data, encoding: .utf8) {
                    var responseBody = context.channel.allocator.buffer(capacity: json.utf8.count)
                    responseBody.writeString(json)
                    response = (
                        head: HTTPResponseHead(version: .http1_1, status: .ok),
                        body: responseBody
                    )
                } else {
                    var errorBody = context.channel.allocator.buffer(capacity: 50)
                    errorBody.writeString("{\"error\":\"encoding failed\"}")
                    response = (
                        head: HTTPResponseHead(version: .http1_1, status: .internalServerError),
                        body: errorBody
                    )
                }
            } else {
                var emptyBody = context.channel.allocator.buffer(capacity: 2)
                emptyBody.writeString("{}")
                response = (
                    head: HTTPResponseHead(version: .http1_1, status: .ok),
                    body: emptyBody
                )
            }

        case (.POST, let uri) where uri.hasPrefix("/resolve/jobs/") && uri.hasSuffix("/result"):
            if let body = body, body.readableBytes > 0 {
                var mutableBody = body
                if let bytes = mutableBody.readBytes(length: body.readableBytes) {
                    let data = Data(bytes)
                    if let result = try? JSONDecoder().decode(JobResult.self, from: data) {
                        server.completeResolveJob(result)
                        #if DEBUG
                        print("JobServer: Resolve job result ontvangen - id: \(result.jobId), success: \(result.success)")
                        #endif
                    } else {
                        #if DEBUG
                        let rawString = String(data: data, encoding: .utf8) ?? "unreadable"
                        print("JobServer: ERROR - Kan Resolve job result niet decoderen: \(rawString.prefix(200))")
                        #endif
                    }
                }
            }
            var okBody = context.channel.allocator.buffer(capacity: 30)
            okBody.writeString("{\"status\":\"received\"}")
            response = (
                head: HTTPResponseHead(version: .http1_1, status: .ok),
                body: okBody
            )

        default:
            var notFoundBody = context.channel.allocator.buffer(capacity: 30)
            notFoundBody.writeString("{\"error\":\"not found\"}")
            response = (
                head: HTTPResponseHead(version: .http1_1, status: .notFound),
                body: notFoundBody
            )
        }
        
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        // CORS headers — alleen voor Chrome extensie origins en lokale processen
        let origin = head.headers.first(name: "Origin") ?? ""
        if origin.hasPrefix("chrome-extension://") {
            headers.add(name: "Access-Control-Allow-Origin", value: origin)
            headers.add(name: "Access-Control-Allow-Methods", value: "GET, POST, OPTIONS")
            headers.add(name: "Access-Control-Allow-Headers", value: "Content-Type")
        }
        if let body = response.body {
            headers.add(name: "Content-Length", value: String(body.readableBytes))
        }
        
        var responseHead = response.head
        responseHead.headers = headers
        
        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        if let body = response.body {
            context.write(wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
        }
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        
        currentRequest = nil
    }
    
    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
}

