import Foundation

/// Beheert het Python bridge script voor DaVinci Resolve als subprocess.
/// Start automatisch wanneer Resolve draait, stopt wanneer Resolve sluit.
class ResolveScriptManager {
    static let shared = ResolveScriptManager()

    private var process: Process?
    private var monitorTimer: Timer?
    private var isMonitoring = false
    private var restartCount = 0
    private let maxRestarts = 5

    /// Pad naar de DaVinci Resolve Scripting Modules
    private let resolveScriptingModulesPath =
        "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"

    private init() {
        #if DEBUG
        print("ResolveScriptManager: Singleton geïnitialiseerd")
        #endif
    }

    // MARK: - Public API

    /// Start de monitoring timer die automatisch het bridge script start/stopt
    /// op basis van of DaVinci Resolve draait
    func startMonitoring() {
        #if DEBUG
        print("ResolveScriptManager: startMonitoring() aangeroepen (isMonitoring=\(isMonitoring), isMainThread=\(Thread.isMainThread))")
        #endif

        guard !isMonitoring else {
            #if DEBUG
            print("ResolveScriptManager: Monitoring was al actief, skip")
            #endif
            return
        }
        isMonitoring = true

        #if DEBUG
        print("ResolveScriptManager: Monitoring gestart, timer wordt aangemaakt...")
        #endif

        // Zorg ervoor dat de Timer op de main thread RunLoop staat
        if Thread.isMainThread {
            setupTimer()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.setupTimer()
            }
        }
    }

    private func setupTimer() {
        // Check elke 5 seconden of Resolve draait
        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkAndManageBridge()
        }
        // Voeg toe aan common modes zodat de timer ook tijdens UI interactie vurt
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
        #if DEBUG
        print("ResolveScriptManager: Timer aangemaakt en toegevoegd aan RunLoop.main (.common)")
        #endif

        // Direct eerste check
        checkAndManageBridge()
    }

    /// Stop de monitoring timer en het bridge script
    func stopMonitoring() {
        isMonitoring = false
        monitorTimer?.invalidate()
        monitorTimer = nil
        stop()
        #if DEBUG
        print("ResolveScriptManager: Monitoring gestopt")
        #endif
    }

    /// Is het Python bridge script actief?
    var isRunning: Bool {
        return process?.isRunning == true
    }

    // MARK: - Private Methods

    /// Check of Resolve draait en start/stop het bridge script dienovereenkomstig
    private func checkAndManageBridge() {
        let resolveRunning = NLEChecker.shared.isRunning(.resolve)

        if resolveRunning && !isRunning {
            #if DEBUG
            print("ResolveScriptManager: Resolve draait, bridge wordt gestart...")
            #endif
            start()
        } else if !resolveRunning && isRunning {
            #if DEBUG
            print("ResolveScriptManager: Resolve is gestopt, bridge wordt gestopt")
            #endif
            stop()
            restartCount = 0
        }
        // Stille check: als Resolve niet draait en bridge ook niet, niets doen
    }

    /// Start het Python bridge script als subprocess
    private func start() {
        guard !isRunning else {
            #if DEBUG
            print("ResolveScriptManager: Bridge draait al, skip start()")
            #endif
            return
        }

        guard let pythonPath = findPython3() else {
            #if DEBUG
            print("ResolveScriptManager: Python 3 niet gevonden op het systeem")
            #endif
            return
        }
        #if DEBUG
        print("ResolveScriptManager: Python gevonden: \(pythonPath)")
        #endif

        guard let scriptPath = findBridgeScript() else {
            #if DEBUG
            print("ResolveScriptManager: Bridge script niet gevonden")
            #endif
            return
        }
        #if DEBUG
        print("ResolveScriptManager: Script gevonden: \(scriptPath)")
        #endif

        // Verify scripting modules exist
        if !FileManager.default.fileExists(atPath: resolveScriptingModulesPath) {
            #if DEBUG
            print("ResolveScriptManager: Resolve scripting modules niet gevonden op: \(resolveScriptingModulesPath)")
            #endif
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = [scriptPath]

        // Set PYTHONPATH zodat het script DaVinciResolveScript kan importeren
        var env = ProcessInfo.processInfo.environment
        let existingPythonPath = env["PYTHONPATH"] ?? ""
        if existingPythonPath.isEmpty {
            env["PYTHONPATH"] = resolveScriptingModulesPath
        } else {
            env["PYTHONPATH"] = "\(resolveScriptingModulesPath):\(existingPythonPath)"
        }
        // Resolve scripting API vereist ook RESOLVE_SCRIPT_API en RESOLVE_SCRIPT_LIB
        env["RESOLVE_SCRIPT_API"] = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting"
        env["RESOLVE_SCRIPT_LIB"] = "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so"
        proc.environment = env

        // Capture stdout/stderr for logging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe

        // Log output van het script
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8), !str.isEmpty {
                for line in str.split(separator: "\n") {
                    #if DEBUG
                    print("ResolveScript: \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
                    #endif
                }
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let str = String(data: data, encoding: .utf8), !str.isEmpty {
                for line in str.split(separator: "\n") {
                    #if DEBUG
                    print("ResolveScript ERROR: \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
                    #endif
                }
            }
        }

        // Termination handler voor crash detection
        proc.terminationHandler = { [weak self] process in
            guard let self = self else { return }
            let status = process.terminationStatus
            let reason = process.terminationReason

            // Stop pipe handlers
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            if status != 0 && self.isMonitoring {
                #if DEBUG
                print("ResolveScriptManager: Bridge script gestopt met status \(status), reason: \(reason == .exit ? "exit" : "uncaughtSignal")")
                #endif
                if self.restartCount < self.maxRestarts && NLEChecker.shared.isRunning(.resolve) {
                    self.restartCount += 1
                    #if DEBUG
                    print("ResolveScriptManager: Herstart poging \(self.restartCount)/\(self.maxRestarts)...")
                    #endif
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        self.start()
                    }
                } else if self.restartCount >= self.maxRestarts {
                    #if DEBUG
                    print("ResolveScriptManager: Maximum herstart pogingen bereikt, gestopt")
                    #endif
                }
            } else {
                #if DEBUG
                print("ResolveScriptManager: Bridge script normaal gestopt (status=\(status))")
                #endif
            }
        }

        do {
            try proc.run()
            process = proc
            restartCount = 0
            #if DEBUG
            print("ResolveScriptManager: Bridge script gestart (PID: \(proc.processIdentifier))")
            #endif
        } catch {
            #if DEBUG
            print("ResolveScriptManager: Kon bridge script niet starten: \(error)")
            #endif
        }
    }

    /// Stop het Python bridge script
    private func stop() {
        guard let proc = process, proc.isRunning else {
            process = nil
            return
        }

        proc.terminate()

        // Wacht max 3 seconden op graceful shutdown
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(3.0)
            while proc.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if proc.isRunning {
                #if DEBUG
                print("ResolveScriptManager: Force kill bridge script")
                #endif
                proc.interrupt() // SIGINT
            }
        }

        process = nil
        #if DEBUG
        print("ResolveScriptManager: Bridge script gestopt")
        #endif
    }

    // MARK: - Path Discovery

    /// Zoek Python 3 op het systeem
    private func findPython3() -> String? {
        let candidates = [
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3"
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Probeer via which
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["python3"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = FileHandle.nullDevice

        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {}

        return nil
    }

    /// Zoek het bridge script in de app bundle of development directory
    private func findBridgeScript() -> String? {
        // 1. In app bundle (Resources/ResolvePlugin/) — voor release/DMG builds
        if let bundlePath = Bundle.main.path(
            forResource: "fileflower_resolve_bridge",
            ofType: "py",
            inDirectory: "ResolvePlugin"
        ) {
            #if DEBUG
            print("ResolveScriptManager: Script gevonden in app bundle: \(bundlePath)")
            #endif
            return bundlePath
        }

        // 2. Development fallback: gebruik #filePath om de source root te vinden
        //    Dit werkt altijd in debug builds, ongeacht waar DerivedData staat
        let sourceFile = #filePath
        // sourceFile = .../FileFlower/FileFlower/FileFlower/Services/ResolveScriptManager.swift
        // We gaan 4 niveaus omhoog naar de repo root
        var sourceRoot = URL(fileURLWithPath: sourceFile)
        for _ in 0..<4 {
            sourceRoot = sourceRoot.deletingLastPathComponent()
        }
        let devPath = sourceRoot.appendingPathComponent("ResolvePlugin/fileflower_resolve_bridge.py")
        #if DEBUG
        print("ResolveScriptManager: Development pad gecontroleerd: \(devPath.path)")
        #endif
        if FileManager.default.fileExists(atPath: devPath.path) {
            #if DEBUG
            print("ResolveScriptManager: Script gevonden via #filePath fallback")
            #endif
            return devPath.path
        }

        #if DEBUG
        print("ResolveScriptManager: Script niet gevonden in bundle of development directory")
        #endif
        return nil
    }
}
