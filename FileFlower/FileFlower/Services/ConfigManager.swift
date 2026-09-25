import Foundation

class ConfigManager {
    static let shared = ConfigManager()
    
    private let configURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        let appDir = appSupport.appendingPathComponent("FileFlower", isDirectory: true)
        let oldAppDir = appSupport.appendingPathComponent("DLtoPremiere", isDirectory: true)

        // Migratie: neem config.json over uit de oude DLtoPremiere-map.
        // Conditie op het BESTAND, niet op de map: andere services (o.a. AnalyticsService)
        // maken de FileFlower-map al aan vóórdat ConfigManager draait, waardoor de oude
        // map-conditie nooit meer waar werd en de migratie in de praktijk dood was.
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)

        let newConfigURL = appDir.appendingPathComponent("config.json")
        let oldConfigURL = oldAppDir.appendingPathComponent("config.json")
        if !fileManager.fileExists(atPath: newConfigURL.path),
           fileManager.fileExists(atPath: oldConfigURL.path) {
            do {
                // Kopiëren (niet verplaatsen): de oude map blijft als vangnet staan
                try fileManager.copyItem(at: oldConfigURL, to: newConfigURL)
                #if DEBUG
                print("ConfigManager: Config gemigreerd van DLtoPremiere naar FileFlower")
                #endif
            } catch {
                #if DEBUG
                print("ConfigManager: Migratie gefaald: \(error)")
                #endif
            }
        }

        configURL = newConfigURL
    }
    
    func load() -> Config? {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: configURL) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            // Corrupte config NOOIT stil weggooien: de eerstvolgende save zou hem anders
            // permanent overschrijven met defaults (alle instellingen + geleerde regels kwijt).
            // Bewaar een backup zodat de data te herstellen is.
            let backupURL = configURL.deletingLastPathComponent()
                .appendingPathComponent("config.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: configURL, to: backupURL)
            #if DEBUG
            print("ConfigManager: Config corrupt (\(error)) — backup: \(backupURL.lastPathComponent)")
            #endif
            return nil
        }
    }
    
    func save(_ config: Config) {
        guard let data = try? JSONEncoder().encode(config) else {
            return
        }

        // Atomair schrijven (temp-bestand + rename) zodat een crash of
        // gelijktijdige schrijfactie de config nooit half/leeg achterlaat.
        do {
            try data.write(to: configURL, options: .atomic)
        } catch {
            #if DEBUG
            print("ConfigManager: Config schrijven gefaald: \(error)")
            #endif
        }
    }
}

