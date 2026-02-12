import Foundation
import NIO
import NIOHTTP1
import Combine

class JobServer {
    static let shared = JobServer()
    
    private var group: EventLoopGroup?
    private var channel: Channel?
    private var pendingJobs: [UUID: JobRequest] = [:]
    private var completedJobs: [UUID: JobResult] = [:]
    private var isRunning = false
    private let serverQueue = DispatchQueue(label: "com.fileflower.jobserver", qos: .userInitiated)
    
    private let port: Int = 17890
    
    // Actief project vanuit Premiere Pro (gerapporteerd door CEP plugin)
    @Published private(set) var activeProjectPath: String?
    private var lastActiveProjectUpdate: Date?
    
    private init() {}
    
    /// Update het actieve project pad (aangeroepen vanuit HTTP handler)
    func updateActiveProject(path: String?) {
        DispatchQueue.main.async {
            self.activeProjectPath = path
            self.lastActiveProjectUpdate = Date()
        }
    }
    
    /// Check of het actieve project nog vers is (binnen 10 seconden)
    var isActiveProjectFresh: Bool {
        guard let lastUpdate = lastActiveProjectUpdate else { return false }
        return Date().timeIntervalSince(lastUpdate) < 10
    }
    
    var isServerRunning: Bool {
        return isRunning && channel != nil
    }
    
    func start() throws {
        // Prevent multiple starts
        guard !isRunning else {
            print("JobServer is already running")
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
            
            print("JobServer started successfully on http://127.0.0.1:\(port)")
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
            print("Error closing channel: \(error)")
        }
        
        do {
            try group?.syncShutdownGracefully()
        } catch {
            print("Error shutting down event loop group: \(error)")
        }
        
        channel = nil
        group = nil
        
        print("JobServer stopped")
    }
    
    func addJob(_ job: JobRequest) {
        pendingJobs[job.id] = job
        print("JobServer: Job toegevoegd - id: \(job.id)")
        print("JobServer: Project: \(job.projectPath)")
        print("JobServer: Premiere bin path: \(job.premiereBinPath)")
        print("JobServer: Files: \(job.files)")
        print("JobServer: Pending jobs count: \(pendingJobs.count)")
    }
    
    func getNextJob() -> JobRequest? {
        guard let (id, job) = pendingJobs.first else {
            return nil
        }
        pendingJobs.removeValue(forKey: id)
        print("JobServer: Job opgehaald door CEP plugin - id: \(id)")
        print("JobServer: Remaining pending jobs: \(pendingJobs.count)")
        return job
    }
    
    func completeJob(_ result: JobResult) {
        completedJobs[result.jobId] = result
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
    
    private func sendResponse(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
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
            var statusBody = context.channel.allocator.buffer(capacity: 100)
            statusBody.writeString("{\"status\":\"ok\",\"server\":\"FileFlower\",\"version\":\"1.0\"}")
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
                    
                    // Log raw JSON for debugging
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("JobServer: Received stock metadata: \(jsonString.prefix(500))...")
                    }
                    
                    // Decode metadata
                    do {
                        let metadata = try JSONDecoder().decode(StockMetadata.self, from: data)
                        
                        // Add to cache (async)
                        Task {
                            await StockMetadataCache.shared.add(metadata)
                        }
                        
                        var okBody = context.channel.allocator.buffer(capacity: 100)
                        okBody.writeString("{\"status\":\"received\",\"title\":\"\(metadata.title ?? "unknown")\"}")
                        response = (
                            head: HTTPResponseHead(version: .http1_1, status: .ok),
                            body: okBody
                        )
                    } catch {
                        print("JobServer: Error decoding stock metadata: \(error)")
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
                    if let jsonString = String(data: data, encoding: .utf8) {
                        print("JobServer: Received active project: \(jsonString)")
                    }
                    
                    // Decode project path
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let projectPath = json["projectPath"] as? String {
                            server.updateActiveProject(path: projectPath)
                            
                            var okBody = context.channel.allocator.buffer(capacity: 100)
                            okBody.writeString("{\"status\":\"received\",\"projectPath\":\"\(projectPath)\"}")
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
                        print("JobServer: Error decoding active project: \(error)")
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
        // CORS headers voor Chrome extensie
        headers.add(name: "Access-Control-Allow-Origin", value: "*")
        headers.add(name: "Access-Control-Allow-Methods", value: "GET, POST, OPTIONS")
        headers.add(name: "Access-Control-Allow-Headers", value: "Content-Type")
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

