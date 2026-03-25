import SwiftUI

/// Thumbnail preview voor bestanden in de download queue.
/// Toont een QuickLook thumbnail of een SF Symbol fallback.
struct ThumbnailView: View {
    let path: String
    let isFolder: Bool
    let assetType: AssetType
    let isClassifying: Bool

    @State private var thumbnail: NSImage?

    private var fallbackIcon: String {
        if isFolder { return "folder.fill" }
        switch assetType {
        case .music: return "music.note"
        case .sfx: return "waveform"
        case .vo: return "mic.fill"
        case .motionGraphic: return "film"
        case .graphic: return "photo"
        case .stockFootage: return "film"
        case .unknown: return "doc"
        }
    }

    var body: some View {
        ZStack {
            if isFolder {
                // Folders tonen altijd het folder icoon
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.controlBackgroundColor))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "folder.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    )
            } else if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipped()
                    .cornerRadius(6)
            } else {
                // Placeholder met SF Symbol
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.controlBackgroundColor))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: fallbackIcon)
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    )
            }

            // Classifying spinner overlay
            if isClassifying {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 40, height: 40)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.6)
                    )
            }
        }
        .task(id: path) {
            guard !isFolder else { return }
            thumbnail = await ThumbnailService.shared.thumbnail(for: path)
        }
    }
}
