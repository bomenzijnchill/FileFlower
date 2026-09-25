import SwiftUI

struct AISuggestionChip: View {
    let typeName: String
    let subfolder: String?
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                let parts = [typeName, subfolder].compactMap { $0 }
                Text("\(String(localized: "queue.suggestion_prefix"))\(parts.joined(separator: " > "))")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.aiChipBg)
            .foregroundColor(.aiChipInk)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 24)
        .accessibilityLabel("\(String(localized: "queue.ai_suggestion"))\(typeName), \(subfolder ?? "")")
    }

    static func fromItem(_ item: DownloadItem, onTap: (() -> Void)? = nil) -> AISuggestionChip {
        let subfolder = item.targetSubfolder ?? item.predictedMood ?? item.predictedGenre ?? item.predictedSfxCategory
        return AISuggestionChip(typeName: item.predictedType.displayName, subfolder: subfolder, onTap: onTap)
    }
}
