import SwiftUI

struct DestinationChip: View {
    let icon: String
    let label: String
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                Text(label)
                    .font(.brandMono(size: 10, weight: .medium))
                    .tracking(0.4)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.destChipBg)
            .foregroundColor(.destChipInk)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 24)
        .accessibilityLabel("\(String(localized: "edit.target_path")): \(label)")
    }

    static func fromItem(_ item: DownloadItem, onTap: (() -> Void)? = nil) -> DestinationChip {
        let icon = iconForType(item.predictedType)
        let subfolder = item.targetSubfolder ?? item.predictedMood ?? item.predictedGenre ?? item.predictedSfxCategory
        let parts = [item.predictedType.displayName, subfolder].compactMap { $0 }
        let label = parts.joined(separator: " > ")
        return DestinationChip(icon: icon, label: label, onTap: onTap)
    }
}

func iconForType(_ type: AssetType) -> String {
    switch type {
    case .music: return "music.note"
    case .sfx: return "waveform"
    case .vo: return "mic"
    case .footage: return "video.fill"
    case .motionGraphic: return "video"
    case .graphic: return "photo"
    case .stockFootage: return "film"
    case .unknown: return "questionmark"
    }
}
