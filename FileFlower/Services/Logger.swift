import Foundation

struct LogEntry: Codable {
    let id: UUID
    let from: String
    let to: String
    let time: TimeInterval
    let itemId: UUID
    
    init(id: UUID = UUID(), from: String, to: String, time: TimeInterval = Date().timeIntervalSince1970, itemId: UUID) {
        self.id = id
        self.from = from
        self.to = to
        self.time = time
        self.itemId = itemId
    }
}

class Logger {
    static let shared = Logger()
    
    private let logURL: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("FileFlower", isDirectory: true)
        logURL = appDir.appendingPathComponent("actions.log")
    }
    
    func logMove(from: String, to: String, itemId: UUID) {
        let entry = LogEntry(from: from, to: to, itemId: itemId)
        
        guard let data = try? JSONEncoder().encode(entry),
              let json = String(data: data, encoding: .utf8) else {
            return
        }
        
        let line = json + "\n"
        
        if let fileHandle = try? FileHandle(forWritingTo: logURL) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(line.data(using: .utf8)!)
            fileHandle.closeFile()
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
    
    func getRecentMoves(limit: Int = 50) -> [LogEntry] {
        guard let data = try? Data(contentsOf: logURL),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        var entries: [LogEntry] = []
        
        for line in lines.suffix(limit) {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(LogEntry.self, from: lineData) else {
                continue
            }
            entries.append(entry)
        }
        
        return entries.reversed() // Most recent first
    }
    
    func undoLastMove() -> (from: String, to: String)? {
        let entries = getRecentMoves(limit: 1)
        guard let last = entries.first else {
            return nil
        }
        
        // Move file back
        let fileManager = FileManager.default
        let fromURL = URL(fileURLWithPath: last.to)
        let toURL = URL(fileURLWithPath: last.from)
        
        // Check if destination exists
        if fileManager.fileExists(atPath: toURL.path) {
            return nil // Can't undo, destination exists
        }
        
        do {
            try fileManager.moveItem(at: fromURL, to: toURL)
            return (from: last.to, to: last.from)
        } catch {
            return nil
        }
    }
}

