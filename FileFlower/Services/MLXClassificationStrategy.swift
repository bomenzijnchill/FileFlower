import Foundation

struct ClassificationResult: Sendable {
    let assetType: String
    let genre: String?
    let mood: String?
    let error: String?
    let processingTimeMs: Int?
    
    /// Parse van JSON data (nonisolated voor gebruik in Task.detached)
    nonisolated static func from(data: Data) -> ClassificationResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return ClassificationResult(
            assetType: json["assetType"] as? String ?? "Unknown",
            genre: json["genre"] as? String,
            mood: json["mood"] as? String,
            error: json["error"] as? String,
            processingTimeMs: json["processing_time_ms"] as? Int
        )
    }
}

/// MLX Daemon status
struct DaemonStatus {
    var isRunning: Bool
    var modelLoaded: Bool
    var modelLoading: Bool
    var error: String?
}

class MLXClassificationStrategy: ClassificationStrategy {
    private let modelManager = ModelManager.shared
    private let thermalManager = ThermalManager.shared
    private var modelPath: String?
    private var isModelLoaded: Bool = false
    
    // Daemon configuratie
    private let daemonHost = "127.0.0.1"
    private let daemonPort = 17891
    private var daemonBaseURL: URL {
        URL(string: "http://\(daemonHost):\(daemonPort)")!
    }
    
    // Cache voor daemon status (voorkom te veel health checks)
    private var lastDaemonCheck: Date?
    private var cachedDaemonRunning: Bool = false
    private let daemonCheckInterval: TimeInterval = 5.0  // 5 seconden cache
    
    init(modelName: String? = nil) {
        // Model wordt lazy geladen bij eerste gebruik
        if let name = modelName {
            let path = modelManager.getModelPath(modelName: name)
            if modelManager.validateModelPath(path.path) {
                self.modelPath = path.path
            }
        }
    }
    
    func classify(url: URL, uti: String?, metadata: DownloadMetadata?, originUrl: String?) async -> AssetType {
        print("MLXClassificationStrategy: Starting classification for \(url.lastPathComponent)")
        
        // Check thermal status
        guard await thermalManager.waitUntilCanProcess() else {
            print("MLXClassificationStrategy: Thermal throttling active, skipping MLX")
            return .unknown
        }
        
        // Probeer eerst via daemon (snel)
        if await isDaemonRunning() {
            let result = await classifyViaDaemon(
                filename: url.lastPathComponent,
                metadata: metadata,
                originUrl: originUrl
            )
            
            if result.error == nil {
                if let assetType = parseAssetType(result.assetType) {
                    let timeStr = result.processingTimeMs.map { "\($0)ms" } ?? "N/A"
                    print("MLXClassificationStrategy: Daemon result - \(assetType) in \(timeStr)")
                    return assetType
                }
            } else {
                print("MLXClassificationStrategy: Daemon error - \(result.error ?? "unknown")")
            }
        }
        
        // Fallback: gebruik script (traag)
        print("MLXClassificationStrategy: Falling back to script-based classification")
        
        guard await ensureModelLoaded() else {
            print("MLXClassificationStrategy: Model not available")
            return .unknown
        }
        
        guard let modelPath = modelPath else {
            print("MLXClassificationStrategy: No model path available")
            return .unknown
        }
        
        let result = await classifyWithScript(
            filename: url.lastPathComponent,
            metadata: metadata,
            originUrl: originUrl,
            modelPath: modelPath
        )
        
        if let assetType = parseAssetType(result.assetType) {
            return assetType
        }
        
        return .unknown
    }
    
    /// Classificeer en retourneer volledig resultaat (inclusief genre/mood)
    func classifyWithDetails(url: URL, uti: String?, metadata: DownloadMetadata?, originUrl: String?) async -> (assetType: AssetType, genre: String?, mood: String?) {
        // Check thermal status
        guard await thermalManager.waitUntilCanProcess() else {
            return (.unknown, nil, nil)
        }
        
        // Probeer eerst via daemon (snel)
        if await isDaemonRunning() {
            let result = await classifyViaDaemon(
                filename: url.lastPathComponent,
                metadata: metadata,
                originUrl: originUrl
            )
            
            if result.error == nil {
                let assetType = parseAssetType(result.assetType) ?? .unknown
                let timeStr = result.processingTimeMs.map { "\($0)ms" } ?? "N/A"
                print("MLXClassificationStrategy: Daemon result - \(assetType), genre: \(result.genre ?? "nil"), mood: \(result.mood ?? "nil") in \(timeStr)")
                return (assetType, result.genre, result.mood)
            }
        }
        
        // Fallback: gebruik script
        guard await ensureModelLoaded() else {
            return (.unknown, nil, nil)
        }
        
        guard let modelPath = modelPath else {
            return (.unknown, nil, nil)
        }
        
        let result = await classifyWithScript(
            filename: url.lastPathComponent,
            metadata: metadata,
            originUrl: originUrl,
            modelPath: modelPath
        )
        
        let assetType = parseAssetType(result.assetType) ?? .unknown
        return (assetType, result.genre, result.mood)
    }
    
    // MARK: - Daemon Communication
    
    /// Check of de daemon draait (met caching)
    func isDaemonRunning() async -> Bool {
        // Check cache
        if let lastCheck = lastDaemonCheck,
           Date().timeIntervalSince(lastCheck) < daemonCheckInterval {
            return cachedDaemonRunning
        }
        
        // Doe health check
        let status = await checkDaemonHealth()
        
        lastDaemonCheck = Date()
        cachedDaemonRunning = status.isRunning
        
        return status.isRunning
    }
    
    /// Check daemon health status
    func checkDaemonHealth() async -> DaemonStatus {
        let url = daemonBaseURL.appendingPathComponent("health")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0  // Korte timeout voor health check
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return DaemonStatus(isRunning: false, modelLoaded: false, modelLoading: false, error: "Bad response")
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return DaemonStatus(
                    isRunning: true,
                    modelLoaded: json["model_loaded"] as? Bool ?? false,
                    modelLoading: json["model_loading"] as? Bool ?? false,
                    error: json["error"] as? String
                )
            }
            
            return DaemonStatus(isRunning: true, modelLoaded: false, modelLoading: false, error: nil)
            
        } catch {
            return DaemonStatus(isRunning: false, modelLoaded: false, modelLoading: false, error: error.localizedDescription)
        }
    }
    
    /// Classificeer via de daemon
    private func classifyViaDaemon(
        filename: String,
        metadata: DownloadMetadata?,
        originUrl: String?
    ) async -> ClassificationResult {
        let url = daemonBaseURL.appendingPathComponent("classify")
        
        // Bouw request body
        var body: [String: Any] = [
            "filename": filename,
            "max_tokens": 150
        ]
        
        // Voeg metadata toe
        var metadataDict: [String: Any] = [:]
        if let meta = metadata {
            if let title = meta.title { metadataDict["title"] = title }
            if let artist = meta.artist { metadataDict["artist"] = artist }
            if let genre = meta.genre { metadataDict["genre"] = genre }
            if !meta.tags.isEmpty { metadataDict["tags"] = meta.tags }
            if let duration = meta.duration { metadataDict["duration"] = duration }
            if let bpm = meta.bpm { metadataDict["bpm"] = bpm }
            if let key = meta.key { metadataDict["key"] = key }
        }
        if let origin = originUrl { metadataDict["originUrl"] = origin }
        
        if !metadataDict.isEmpty {
            body["metadata"] = metadataDict
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0  // 30 seconden timeout voor classificatie
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return ClassificationResult(assetType: "Unknown", genre: nil, mood: nil, error: "JSON encoding failed", processingTimeMs: nil)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return ClassificationResult(assetType: "Unknown", genre: nil, mood: nil, error: "Invalid response", processingTimeMs: nil)
            }
            
            if httpResponse.statusCode != 200 {
                return ClassificationResult(assetType: "Unknown", genre: nil, mood: nil, error: "HTTP \(httpResponse.statusCode)", processingTimeMs: nil)
            }
            
            if let result = ClassificationResult.from(data: data) {
                return result
            }
            
            return ClassificationResult(assetType: "Unknown", genre: nil, mood: nil, error: "Parse error", processingTimeMs: nil)
            
        } catch {
            // Markeer daemon als niet-draaiend bij connectie errors
            cachedDaemonRunning = false
            lastDaemonCheck = nil
            
            return ClassificationResult(assetType: "Unknown", genre: nil, mood: nil, error: error.localizedDescription, processingTimeMs: nil)
        }
    }
    
    // MARK: - Script-based Classification (Fallback)
    
    private func ensureModelLoaded() async -> Bool {
        if isModelLoaded && modelPath != nil {
            return true
        }
        
        print("MLXClassificationStrategy: Ensuring model is loaded...")
        
        // Zorg eerst dat MLX geïnstalleerd is
        do {
            let mlxInstalled = try await modelManager.installMLX()
            if !mlxInstalled {
                print("MLXClassificationStrategy: Failed to install MLX")
                return false
            }
        } catch {
            print("MLXClassificationStrategy: Error installing MLX: \(error)")
            return false
        }
        
        // Probeer model te laden uit config
        let config = AppState.shared.config
        let modelName = config.mlxModelName
        
        print("MLXClassificationStrategy: Checking for model \(modelName)...")
        
        // Check of model bestaat
        if modelManager.modelExists(modelName: modelName) {
            let path = modelManager.getModelPath(modelName: modelName)
            if modelManager.validateModelPath(path.path) {
                print("MLXClassificationStrategy: Model found at \(path.path)")
                self.modelPath = path.path
                self.isModelLoaded = true
                return true
            }
        }
        
        // Probeer model te downloaden als het niet bestaat
        print("MLXClassificationStrategy: Model not found, downloading...")
        do {
            try await modelManager.downloadModel(modelName: modelName)
            let path = modelManager.getModelPath(modelName: modelName)
            if modelManager.validateModelPath(path.path) {
                print("MLXClassificationStrategy: Model downloaded successfully to \(path.path)")
                self.modelPath = path.path
                self.isModelLoaded = true
                return true
            } else {
                print("MLXClassificationStrategy: Model download completed but validation failed")
                return false
            }
        } catch {
            print("MLXClassificationStrategy: Kon model niet downloaden: \(error)")
            return false
        }
    }
    
    private func classifyWithScript(
        filename: String,
        metadata: DownloadMetadata?,
        originUrl: String?,
        modelPath: String
    ) async -> ClassificationResult {
        // Maak metadata dictionary
        var metadataDict: [String: Any] = [:]
        if let meta = metadata {
            if let title = meta.title { metadataDict["title"] = title }
            if let artist = meta.artist { metadataDict["artist"] = artist }
            if let genre = meta.genre { metadataDict["genre"] = genre }
            if !meta.tags.isEmpty { metadataDict["tags"] = meta.tags }
            if let duration = meta.duration { metadataDict["duration"] = duration }
            if let bpm = meta.bpm { metadataDict["bpm"] = bpm }
            if let key = meta.key { metadataDict["key"] = key }
        }
        if let origin = originUrl { metadataDict["originUrl"] = origin }
        
        // Converteer naar JSON
        let metadataJSON: String
        if let jsonData = try? JSONSerialization.data(withJSONObject: metadataDict),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            metadataJSON = jsonString
        } else {
            metadataJSON = "{}"
        }
        
        // Run Python classifier script
        let scriptPath = modelManager.getClassifierScriptPath()
        
        guard FileManager.default.fileExists(atPath: scriptPath.path) else {
            print("MLXClassificationStrategy: Classifier script not found at \(scriptPath.path)")
            return ClassificationResult(assetType: "Unknown", genre: nil, mood: nil, error: "Classifier script not found", processingTimeMs: nil)
        }
        
        // Find Python with MLX installed
        guard let pythonPath = modelManager.findPythonWithMLX() else {
            print("MLXClassificationStrategy: No Python with MLX found")
            return ClassificationResult(assetType: "Unknown", genre: nil, mood: nil, error: "Python with MLX not found", processingTimeMs: nil)
        }
        
        print("MLXClassificationStrategy: Using Python at \(pythonPath)")
        
        // Run het Python script op een background thread om UI niet te blokkeren
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = [
                scriptPath.path,
                "--model-path", modelPath,
                "--filename", filename,
                "--metadata", metadataJSON,
                "--max-tokens", "150"
            ]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            let errorPipe = Pipe()
            process.standardError = errorPipe
            
            do {
                print("MLXClassificationStrategy: Running classifier script...")
                
                try process.run()
                
                // Wacht asynchroon op proces completion
                await withCheckedContinuation { continuation in
                    process.terminationHandler = { _ in
                        continuation.resume()
                    }
                }
                
                let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                let outputString = String(data: outputData, encoding: .utf8) ?? ""
                let errorString = String(data: errorData, encoding: .utf8) ?? ""
                
                if process.terminationStatus != 0 {
                    print("MLXClassificationStrategy: Script failed: \(errorString)")
                    return ClassificationResult(assetType: "Unknown", genre: nil, mood: nil, error: errorString.isEmpty ? "Script failed" : errorString, processingTimeMs: nil)
                }
                
                guard !outputString.isEmpty else {
                    return ClassificationResult(assetType: "Unknown", genre: nil, mood: nil, error: "No output from script", processingTimeMs: nil)
                }
                
                // Parse JSON response
                var jsonString = outputString.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Verwijder markdown code blocks
                if jsonString.contains("```json") {
                    if let startRange = jsonString.range(of: "```json"),
                       let endRange = jsonString.range(of: "```", range: startRange.upperBound..<jsonString.endIndex) {
                        jsonString = String(jsonString[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } else if jsonString.contains("```") {
                    if let startRange = jsonString.range(of: "```"),
                       let endRange = jsonString.range(of: "```", range: startRange.upperBound..<jsonString.endIndex) {
                        jsonString = String(jsonString[startRange.upperBound..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                
                // Zoek naar JSON object
                if let startIdx = jsonString.firstIndex(of: "{"),
                   let endIdx = jsonString.lastIndex(of: "}") {
                    jsonString = String(jsonString[startIdx...endIdx])
                }
                
                guard let jsonData = jsonString.data(using: .utf8) else {
                    return ClassificationResult(assetType: "Unknown", genre: nil, mood: nil, error: "Invalid output encoding", processingTimeMs: nil)
                }
                
                if let result = ClassificationResult.from(data: jsonData) {
                    return result
                }
                
                return ClassificationResult(assetType: "Unknown", genre: nil, mood: nil, error: "Parse error", processingTimeMs: nil)
                
            } catch {
                print("MLXClassificationStrategy: Exception: \(error)")
                return ClassificationResult(assetType: "Unknown", genre: nil, mood: nil, error: error.localizedDescription, processingTimeMs: nil)
            }
        }.value
    }
    
    private func parseAssetType(_ typeString: String) -> AssetType? {
        let lowercased = typeString.lowercased()
        switch lowercased {
        case "music":
            return .music
        case "sfx":
            return .sfx
        case "vo", "voice", "voiceover":
            return .vo
        case "motiongraphic", "motion graphic", "motion-graphic":
            return .motionGraphic
        case "graphic":
            return .graphic
        case "stockfootage", "stock footage", "stock-footage":
            return .stockFootage
        case "unknown":
            return .unknown
        default:
            return nil
        }
    }
}
