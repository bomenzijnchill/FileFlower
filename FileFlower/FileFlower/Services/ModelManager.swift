import Foundation

enum ModelManagerError: Error {
    case modelNotFound
    case invalidModelPath
    case downloadFailed
    case pythonNotAvailable
    case scriptNotFound
    case daemonStartFailed
}

@MainActor
class ModelManager {
    static let shared = ModelManager()
    
    // MARK: - Python Path Caching
    
    /// Cached Python path (voorkomt herhaalde lookups)
    private var cachedPythonPath: String?
    private var pythonPathChecked: Bool = false
    
    /// Niet-MainActor versie van findPythonWithMLX voor gebruik in background tasks
    nonisolated func findPythonWithMLXSync() -> String? {
        return findPythonWithMLXInternal()
    }
    
    /// Interne Python lookup (kan vanuit elke context worden aangeroepen)
    private nonisolated func findPythonWithMLXInternal() -> String? {
        // Probeer verschillende Python paden
        let pythonPaths = [
            "/opt/homebrew/bin/python3",  // Homebrew op Apple Silicon (meest voorkomend)
            "/usr/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
            "/usr/local/opt/python@3.13/bin/python3",
            "/usr/local/opt/python@3.12/bin/python3",
            "/usr/bin/python3"  // System Python (laatste optie)
        ]
        
        for pythonPath in pythonPaths {
            if FileManager.default.fileExists(atPath: pythonPath) {
                // Check of MLX geïnstalleerd is in deze Python
                let process = Process()
                process.executableURL = URL(fileURLWithPath: pythonPath)
                process.arguments = ["-c", "import mlx_lm; print('OK')"]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        return pythonPath
                    }
                } catch {
                    continue
                }
            }
        }
        
        // Fallback: probeer via which python3
        return findPythonViaWhich()
    }
    
    private nonisolated func findPythonViaWhich() -> String? {
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["python3"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = Pipe()
        
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty,
               FileManager.default.fileExists(atPath: path) {
                // Check MLX
                let checkProcess = Process()
                checkProcess.executableURL = URL(fileURLWithPath: path)
                checkProcess.arguments = ["-c", "import mlx_lm; print('OK')"]
                checkProcess.standardOutput = Pipe()
                checkProcess.standardError = Pipe()
                try checkProcess.run()
                checkProcess.waitUntilExit()
                if checkProcess.terminationStatus == 0 {
                    return path
                }
            }
        } catch {
            // Ignore
        }
        
        return nil
    }
    
    // MARK: - Properties
    
    private let modelsDirectory: URL
    private let downloadScriptPath: URL
    private let classifierScriptPath: URL
    private let daemonScriptPath: URL
    
    // Daemon process reference
    private var daemonProcess: Process?
    private let daemonPort = 17891
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FileFlower", isDirectory: true)
        modelsDirectory = appDir.appendingPathComponent("Models", isDirectory: true)
        
        // Script paths - probeer verschillende locaties
        var foundDownloadScript: URL?
        var foundClassifierScript: URL?
        var foundDaemonScript: URL?
        
        // 1. Probeer in app bundle Resources
        if let bundlePath = Bundle.main.resourcePath {
            let scriptsDir = URL(fileURLWithPath: bundlePath).appendingPathComponent("scripts")
            let downloadPath = scriptsDir.appendingPathComponent("download_mlx_model.py")
            let classifierPath = scriptsDir.appendingPathComponent("mlx_classifier.py")
            let daemonPath = scriptsDir.appendingPathComponent("mlx_daemon.py")
            if FileManager.default.fileExists(atPath: downloadPath.path) {
                foundDownloadScript = downloadPath
            }
            if FileManager.default.fileExists(atPath: classifierPath.path) {
                foundClassifierScript = classifierPath
            }
            if FileManager.default.fileExists(atPath: daemonPath.path) {
                foundDaemonScript = daemonPath
            }
        }
        
        // 2. Fallback: probeer relatief ten opzichte van executable
        if foundDownloadScript == nil || foundClassifierScript == nil || foundDaemonScript == nil {
            let executablePath = Bundle.main.executablePath ?? ""
            let executableURL = URL(fileURLWithPath: executablePath)
            let appBundle = executableURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let scriptsDir = appBundle.appendingPathComponent("scripts")
            let downloadPath = scriptsDir.appendingPathComponent("download_mlx_model.py")
            let classifierPath = scriptsDir.appendingPathComponent("mlx_classifier.py")
            let daemonPath = scriptsDir.appendingPathComponent("mlx_daemon.py")
            if foundDownloadScript == nil && FileManager.default.fileExists(atPath: downloadPath.path) {
                foundDownloadScript = downloadPath
            }
            if foundClassifierScript == nil && FileManager.default.fileExists(atPath: classifierPath.path) {
                foundClassifierScript = classifierPath
            }
            if foundDaemonScript == nil && FileManager.default.fileExists(atPath: daemonPath.path) {
                foundDaemonScript = daemonPath
            }
        }
        
        // 3. Fallback voor development: relatief ten opzichte van source file
        if foundDownloadScript == nil || foundClassifierScript == nil || foundDaemonScript == nil {
            let projectRoot = URL(fileURLWithPath: #file)
                .deletingLastPathComponent() // Services
                .deletingLastPathComponent() // FileFlower
                .deletingLastPathComponent() // FileFlower
                .deletingLastPathComponent() // FileFlower
            let scriptsDir = projectRoot.appendingPathComponent("scripts")
            let downloadPath = scriptsDir.appendingPathComponent("download_mlx_model.py")
            let classifierPath = scriptsDir.appendingPathComponent("mlx_classifier.py")
            let daemonPath = scriptsDir.appendingPathComponent("mlx_daemon.py")
            if foundDownloadScript == nil {
                foundDownloadScript = downloadPath
            }
            if foundClassifierScript == nil {
                foundClassifierScript = classifierPath
            }
            if foundDaemonScript == nil {
                foundDaemonScript = daemonPath
            }
        }
        
        downloadScriptPath = foundDownloadScript ?? URL(fileURLWithPath: "/tmp/download_mlx_model.py")
        classifierScriptPath = foundClassifierScript ?? URL(fileURLWithPath: "/tmp/mlx_classifier.py")
        daemonScriptPath = foundDaemonScript ?? URL(fileURLWithPath: "/tmp/mlx_daemon.py")
        
        // Zorg dat models directory bestaat
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Model Management
    
    /// Haal het pad naar een model op basis van model naam
    func getModelPath(modelName: String) -> URL {
        // Normaliseer model naam voor directory naam
        // Bijv: "TinyLlama/TinyLlama-1.1B-Chat-v1.0" -> "TinyLlama_TinyLlama-1.1B-Chat-v1.0"
        let normalizedName = modelName.replacingOccurrences(of: "/", with: "_")
        return modelsDirectory.appendingPathComponent(normalizedName, isDirectory: true)
    }
    
    /// Check of een model bestaat
    func modelExists(modelName: String) -> Bool {
        let modelPath = getModelPath(modelName: modelName)
        // Check of de directory bestaat en niet leeg is
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: modelPath.path),
              !contents.isEmpty else {
            return false
        }
        // Check voor belangrijke bestanden (config.json en weights)
        let hasConfig = contents.contains { $0 == "config.json" }
        return hasConfig
    }
    
    /// Download een model als het nog niet bestaat
    func downloadModel(modelName: String) async throws {
        if modelExists(modelName: modelName) {
            #if DEBUG
            print("ModelManager: Model \(modelName) already exists")
            #endif
            return // Model bestaat al
        }
        
        let modelPath = getModelPath(modelName: modelName)
        
        // Zorg dat MLX geïnstalleerd is
        do {
            let mlxInstalled = try await installMLX()
            guard mlxInstalled else {
                throw ModelManagerError.downloadFailed
            }
        } catch {
            #if DEBUG
            print("ModelManager: Failed to install MLX: \(error)")
            #endif
            throw ModelManagerError.downloadFailed
        }

        // Vind Python met MLX
        guard let pythonPath = findPythonWithMLX() else {
            #if DEBUG
            print("ModelManager: No Python with MLX found")
            #endif
            throw ModelManagerError.pythonNotAvailable
        }

        // Check of download script bestaat
        guard FileManager.default.fileExists(atPath: downloadScriptPath.path) else {
            #if DEBUG
            print("ModelManager: Download script not found at \(downloadScriptPath.path)")
            #endif
            throw ModelManagerError.scriptNotFound
        }

        #if DEBUG
        print("ModelManager: Downloading model \(modelName) to \(modelPath.path)...")
        #endif
        
        // Run download script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            downloadScriptPath.path,
            "--model", modelName,
            "--output", modelPath.path
        ]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            #if DEBUG
            print("ModelManager: Model download failed: \(output)")
            #endif
            throw ModelManagerError.downloadFailed
        }
        
        // Verify model werd gedownload
        guard modelExists(modelName: modelName) else {
            #if DEBUG
            print("ModelManager: Model download completed but validation failed")
            #endif
            throw ModelManagerError.downloadFailed
        }

        #if DEBUG
        print("ModelManager: Model \(modelName) downloaded successfully")
        #endif
    }
    
    // MARK: - Python Management
    
    /// Vind Python executable waar MLX geïnstalleerd is (met caching)
    func findPythonWithMLX() -> String? {
        // Return cached path als beschikbaar
        if pythonPathChecked, let cached = cachedPythonPath {
            return cached
        }
        
        // Zoek Python path
        let path = findPythonWithMLXInternal()
        
        // Cache het resultaat
        pythonPathChecked = true
        cachedPythonPath = path
        
        #if DEBUG
        if let path = path {
            print("ModelManager: Found Python with MLX at \(path) (cached)")
        }
        #endif
        
        return path
    }
    
    /// Forceer een nieuwe Python lookup (clear cache)
    func refreshPythonPath() {
        pythonPathChecked = false
        cachedPythonPath = nil
    }
    
    /// Async Python lookup voor background gebruik
    func findPythonWithMLXAsync() async -> String? {
        return await Task.detached {
            return self.findPythonWithMLXInternal()
        }.value
    }
    
    /// Installeer MLX automatisch
    func installMLX() async throws -> Bool {
        // Probeer eerst cached Python
        if let pythonPath = cachedPythonPath {
            // Check of MLX al werkt
            let checkProcess = Process()
            checkProcess.executableURL = URL(fileURLWithPath: pythonPath)
            checkProcess.arguments = ["-c", "import mlx_lm; print('OK')"]
            checkProcess.standardOutput = Pipe()
            checkProcess.standardError = Pipe()
            
            do {
                try checkProcess.run()
                checkProcess.waitUntilExit()
                if checkProcess.terminationStatus == 0 {
                    #if DEBUG
                    print("ModelManager: MLX already installed")
                    #endif
                    return true
                }
            } catch {
                // Continue to find Python
            }
        }
        
        // Zoek Python met MLX
        if let pythonPath = findPythonWithMLX() {
            // MLX is al geïnstalleerd
            #if DEBUG
            print("ModelManager: MLX already installed at \(pythonPath)")
            #endif
            return true
        }
        
        // Probeer MLX te installeren in Homebrew Python
        let homebrewPython = "/opt/homebrew/bin/python3"
        if FileManager.default.fileExists(atPath: homebrewPython) {
            return try installMLXInPython(homebrewPython)
        }
        
        // Fallback naar system Python
        return try installMLXInPython("/usr/bin/python3")
    }
    
    private func installMLXInPython(_ pythonPath: String) throws -> Bool {
        #if DEBUG
        print("ModelManager: Installing MLX in \(pythonPath)...")
        #endif
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-m", "pip", "install", "mlx", "mlx-lm", "--quiet"]
        let pipe = Pipe()
        process.standardOutput = pipe
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus == 0 {
            #if DEBUG
            print("ModelManager: MLX installed successfully")
            #endif
            // Update cache
            refreshPythonPath()
            _ = findPythonWithMLX()
            return true
        } else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            #if DEBUG
            print("ModelManager: Failed to install MLX: \(errorString)")
            #endif
            throw ModelManagerError.downloadFailed
        }
    }
    
    // MARK: - Daemon Management
    
    /// Start de MLX daemon
    func startDaemon(modelName: String) async throws {
        // Check of daemon al draait
        if await isDaemonRunning() {
            #if DEBUG
            print("ModelManager: Daemon already running")
            #endif
            return
        }

        // Check of daemon script bestaat
        guard FileManager.default.fileExists(atPath: daemonScriptPath.path) else {
            #if DEBUG
            print("ModelManager: Daemon script not found at \(daemonScriptPath.path)")
            #endif
            throw ModelManagerError.scriptNotFound
        }

        // Vind Python
        guard let pythonPath = findPythonWithMLX() else {
            #if DEBUG
            print("ModelManager: No Python with MLX found for daemon")
            #endif
            throw ModelManagerError.pythonNotAvailable
        }

        // Haal model path op
        let modelPath = getModelPath(modelName: modelName)
        guard validateModelPath(modelPath.path) else {
            #if DEBUG
            print("ModelManager: Model not found at \(modelPath.path)")
            #endif
            throw ModelManagerError.modelNotFound
        }

        #if DEBUG
        print("ModelManager: Starting MLX daemon...")
        #endif
        
        // Start daemon process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [
            daemonScriptPath.path,
            "--model-path", modelPath.path,
            "--port", String(daemonPort)
        ]
        
        // Redirect output naar /dev/null voor clean background running
        // (in development kunnen we dit veranderen voor debugging)
        let nullDevice = FileHandle.nullDevice
        process.standardOutput = nullDevice
        process.standardError = nullDevice
        
        do {
            try process.run()
            daemonProcess = process
            
            // Wacht kort om te zien of de daemon gestart is
            try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconde
            
            if process.isRunning {
                #if DEBUG
                print("ModelManager: Daemon started successfully on port \(daemonPort)")
                #endif
            } else {
                #if DEBUG
                print("ModelManager: Daemon failed to start")
                #endif
                throw ModelManagerError.daemonStartFailed
            }
        } catch {
            #if DEBUG
            print("ModelManager: Failed to start daemon: \(error)")
            #endif
            throw ModelManagerError.daemonStartFailed
        }
    }
    
    /// Stop de MLX daemon
    func stopDaemon() {
        if let process = daemonProcess, process.isRunning {
            #if DEBUG
            print("ModelManager: Stopping daemon...")
            #endif
            process.terminate()
            daemonProcess = nil
        }
        
        // Ook shutdown via HTTP proberen (voor daemon die buiten deze app gestart is)
        Task {
            await sendDaemonShutdown()
        }
    }
    
    /// Check of de daemon draait
    func isDaemonRunning() async -> Bool {
        // Check proces
        if let process = daemonProcess, process.isRunning {
            return true
        }
        
        // Check via HTTP health endpoint
        let url = URL(string: "http://127.0.0.1:\(daemonPort)/health")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            // Daemon niet bereikbaar
        }
        
        return false
    }
    
    /// Stuur shutdown commando naar daemon
    private func sendDaemonShutdown() async {
        let url = URL(string: "http://127.0.0.1:\(daemonPort)/shutdown")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 2.0
        
        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            // Ignore - daemon was waarschijnlijk al gestopt
        }
    }
    
    // MARK: - Validation
    
    /// Valideer dat een model pad geldig is
    func validateModelPath(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        // Check voor config.json
        let configPath = url.appendingPathComponent("config.json")
        return FileManager.default.fileExists(atPath: configPath.path)
    }
    
    /// Haal het classifier script pad op
    func getClassifierScriptPath() -> URL {
        return classifierScriptPath
    }
    
    /// Haal het daemon script pad op
    func getDaemonScriptPath() -> URL {
        return daemonScriptPath
    }
}
