import AppKit
import QuickLookThumbnailing

/// Async thumbnail service voor bestanden in de download queue.
/// Gebruikt macOS QLThumbnailGenerator met NSCache voor geheugenefficiëntie.
actor ThumbnailService {
    static let shared = ThumbnailService()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    private init() {
        cache.countLimit = 100
    }

    /// Haal een thumbnail op voor het opgegeven pad.
    func thumbnail(for path: String, size: CGSize = CGSize(width: 80, height: 80)) async -> NSImage? {
        let key = path as NSString

        // Check cache
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Dedupliceer concurrent requests
        if let existing = inFlight[path] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            let url = URL(fileURLWithPath: path)
            let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }

            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: size,
                scale: scale,
                representationTypes: .thumbnail
            )

            do {
                let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                return representation.nsImage
            } catch {
                return nil
            }
        }

        inFlight[path] = task
        let result = await task.value
        inFlight.removeValue(forKey: path)

        if let image = result {
            cache.setObject(image, forKey: key)
        }

        return result
    }
}
