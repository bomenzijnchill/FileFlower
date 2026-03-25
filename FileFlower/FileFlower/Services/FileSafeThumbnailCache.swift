import AppKit
import QuickLookThumbnailing

/// Async thumbnail cache voor FileSafe bestanden (foto's en video's).
/// Gebruikt macOS `QLThumbnailGenerator` voor native thumbnail generatie.
actor FileSafeThumbnailCache {
    static let shared = FileSafeThumbnailCache()

    /// Maximale resolutie voor cache (slider max 80pt × @2x)
    private static let maxPixelSize: CGFloat = 160

    private var cache: [String: NSImage] = [:]
    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    /// Haal een thumbnail op voor het opgegeven pad. Genereert async als niet gecached.
    func thumbnail(for path: String) async -> NSImage? {
        // Check cache
        if let cached = cache[path] { return cached }

        // Dedupliceer concurrent requests voor hetzelfde bestand
        if let existing = inFlight[path] { return await existing.value }

        let task = Task<NSImage?, Never> {
            let url = URL(fileURLWithPath: path)
            let size = CGSize(width: Self.maxPixelSize, height: Self.maxPixelSize)
            let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2.0 }

            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: size,
                scale: scale,
                representationTypes: .thumbnail
            )

            do {
                let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                let image = representation.nsImage
                return image
            } catch {
                return nil
            }
        }

        inFlight[path] = task
        let result = await task.value
        inFlight.removeValue(forKey: path)

        if let image = result {
            cache[path] = image
        }

        return result
    }

    /// Wis de volledige cache (bijv. bij volume-wissel)
    func clearCache() {
        cache.removeAll()
    }
}
