import Foundation
import AppKit
import Combine

/// Downloadt video's en audio van een geplakte link (via het meegebundelde
/// yt-dlp) rechtstreeks naar de Downloads-watchmap, zodat het bestand
/// automatisch de normale pijplijn in gaat: DownloadsWatcher → classificatie
/// → wachtrij → projectplaatsing. De watcher negeert yt-dlp's .part/.ytdl-
/// tussenbestanden al, dus het item verschijnt pas als de download af is.
///
/// yt-dlp en ffmpeg worden als gesigneerde helpers meegeleverd in
/// Contents/Helpers/ (zie vendor/README.md voor herkomst en checksums) en
/// draaien direct vanuit de app-bundle. Er wordt bewust níéts op afstand
/// opgehaald of vervangen: de tools liften mee met app-updates.
final class LinkDownloader: ObservableObject {
    static let shared = LinkDownloader()

    enum ToolState: Equatable {
        case idle
        case ready(version: String)
        case missing
    }

    enum Format: String, CaseIterable {
        case best
        case fullHD
        case audio
    }

    @Published var toolState: ToolState = .idle
    @Published var jobs: [LinkDownloadJob] = []

    var isReady: Bool {
        if case .ready = toolState { return true }
        return false
    }

    var activeJobCount: Int { jobs.filter { $0.isRunning }.count }

    // MARK: - Tool-locaties

    /// Of de meegebundelde tools er zijn. Zonder yt-dlp verbergt het paneel
    /// zich volledig: een feature zonder motor hoort niet in beeld.
    static let toolsAvailable: Bool = toolURL("yt-dlp") != nil

    /// Zoekt de helper eerst in de app-bundle; in ontwikkelbuilds (waar de
    /// Helpers-map niet gevuld is) valt hij terug op de vendor-map in de
    /// repo, zodat de functie ook in een Debug-build te testen is.
    static func toolURL(_ name: String) -> URL? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(name)")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        #if DEBUG
        let vendored = URL(fileURLWithPath: #filePath)                 // …/FileFlower/FileFlower/Services/LinkDownloader.swift
            .deletingLastPathComponent()                               // Services
            .deletingLastPathComponent()                               // FileFlower
            .deletingLastPathComponent()                               // FileFlower (projectmap)
            .deletingLastPathComponent()                               // git-root
            .appendingPathComponent("vendor/\(name)")
        if FileManager.default.isExecutableFile(atPath: vendored.path) { return vendored }
        #endif
        return nil
    }

    /// Downloads landen in de map die DownloadsWatcher al in de gaten houdt,
    /// zodat de bestaande verwerking het bestand direct oppakt.
    static var destinationFolder: URL {
        if let custom = AppState.shared.config.customDownloadsFolder, !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    // MARK: - Gereedmaken

    private var prepareStarted = false

    /// Idempotent: controleert de helpers en leest eenmalig de yt-dlp-versie.
    func prepareIfNeeded() {
        guard !prepareStarted else { return }
        prepareStarted = true

        guard let ytdlp = LinkDownloader.toolURL("yt-dlp") else {
            toolState = .missing
            return
        }
        Task.detached(priority: .userInitiated) {
            let version = (try? LinkDownloader.runTool(ytdlp, args: ["--version"], timeout: 60))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            await MainActor.run {
                self.toolState = version.isEmpty ? .missing : .ready(version: version)
            }
        }
    }

    @discardableResult
    nonisolated static func runTool(_ tool: URL, args: [String], timeout: TimeInterval) throws -> String {
        let p = Process()
        p.executableURL = tool
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(100_000) }
        if p.isRunning { p.terminate() }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Downloads

    /// Alleen http(s)-links; al het andere wordt geweigerd vóór het yt-dlp bereikt.
    static func isValidLink(_ text: String) -> Bool {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return false }
        return true
    }

    @discardableResult
    func startDownload(link: String, format: Format) -> Bool {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isReady,
              LinkDownloader.isValidLink(trimmed),
              let ytdlp = LinkDownloader.toolURL("yt-dlp") else { return false }
        let job = LinkDownloadJob(
            link: trimmed,
            format: format,
            destination: LinkDownloader.destinationFolder,
            ytdlp: ytdlp,
            ffmpeg: LinkDownloader.toolURL("ffmpeg")
        )
        jobs.insert(job, at: 0)
        return true
    }

    func remove(_ job: LinkDownloadJob) {
        if job.isRunning { job.cancel() }
        jobs.removeAll { $0.id == job.id }
    }

    func clearFinished() {
        jobs.removeAll { !$0.isRunning }
    }
}

/// Eén lopende of afgeronde link-download, met voortgang uit yt-dlp's
/// `--newline`-uitvoer.
final class LinkDownloadJob: ObservableObject, Identifiable {
    let id = UUID()
    @Published var title: String
    @Published var progress: Double = 0
    @Published var statusKind: StatusKind = .starting
    @Published var statusDetail: String = ""
    @Published var state: JobState = .running

    enum JobState { case running, done, failed, cancelled }
    enum StatusKind { case starting, downloading, merging, extracting, done, failed, cancelled }

    var isRunning: Bool { state == .running }

    private var process: Process?
    private var stderrTail = ""
    private var wasCancelled = false

    init(link: String, format: LinkDownloader.Format, destination: URL, ytdlp: URL, ffmpeg: URL?) {
        self.title = link

        // Argumenten als array — er komt geen shell aan te pas en de link is
        // een los argument, dus niets om te escapen of te injecteren.
        var args = ["--newline", "--no-playlist",
                    "-o", "%(title)s.%(ext)s", "-P", destination.path]
        if let ffmpeg {
            args += ["--ffmpeg-location", ffmpeg.path]
        }
        switch format {
        case .best:
            args += ffmpeg != nil
                ? ["-f", "bv*+ba/b", "--merge-output-format", "mp4", "-S", "res:2160"]
                : ["-f", "b", "-S", "res:2160"]
        case .fullHD:
            args += ffmpeg != nil
                ? ["-f", "bv*+ba/b", "--merge-output-format", "mp4", "-S", "res:1080"]
                : ["-f", "b", "-S", "res:1080"]
        case .audio:
            args += ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        }
        args.append(link)

        let p = Process()
        p.executableURL = ytdlp
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = String(data: handle.availableData, encoding: .utf8) ?? ""
            guard !chunk.isEmpty else { return }
            DispatchQueue.main.async { self?.parse(chunk) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = String(data: handle.availableData, encoding: .utf8) ?? ""
            guard !chunk.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.stderrTail = String((self.stderrTail + chunk).suffix(600))
            }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                guard let self else { return }
                if proc.terminationStatus == 0 {
                    self.progress = 1
                    self.state = .done
                    self.statusKind = .done
                } else if self.wasCancelled {
                    self.state = .cancelled
                    self.statusKind = .cancelled
                } else {
                    self.state = .failed
                    self.statusKind = .failed
                    let tail = self.stderrTail
                        .split(separator: "\n")
                        .last(where: { $0.contains("ERROR") })
                    self.statusDetail = tail.map(String.init) ?? ""
                }
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            state = .failed
            statusKind = .failed
        }
    }

    func cancel() {
        wasCancelled = true
        process?.terminate()
    }

    private func parse(_ chunk: String) {
        for line in chunk.split(separator: "\n") {
            let s = String(line)
            if let r = s.range(of: #"\[download\]\s+([\d.]+)%"#, options: .regularExpression) {
                let pct = s[r].replacingOccurrences(of: "[download]", with: "")
                    .replacingOccurrences(of: "%", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if let v = Double(pct) { progress = v / 100 }
                statusKind = .downloading
                statusDetail = s.replacingOccurrences(of: "[download] ", with: "")
                    .trimmingCharacters(in: .whitespaces)
            } else if s.contains("Destination:") {
                if let r = s.range(of: "Destination: ") {
                    let path = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                    if !name.isEmpty { title = name }
                }
            } else if s.contains("[Merger]") || s.contains("Merging") {
                statusKind = .merging
            } else if s.contains("[ExtractAudio]") {
                statusKind = .extracting
            }
        }
    }
}
