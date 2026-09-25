import SwiftUI

/// Mono code-block showing a folder tree preview.
/// New entries (added since last render) get the tea-green highlight.
struct TreePreview: View {
    let rootName: String
    let entries: [String]
    /// Indices in `entries` that should be highlighted as "new".
    var highlightedIndices: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.ink3)
                Text("\(rootName)/")
                    .font(.brandMono(size: 11.5, weight: .medium))
                    .foregroundColor(.ink2)
            }

            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                HStack(spacing: 0) {
                    Text("  └ ")
                        .font(.brandMono(size: 11.5))
                        .foregroundColor(.ink3)
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundColor(highlightedIndices.contains(index) ? .teaHighlightFg : .ink3)
                        Text("\(entry)/")
                            .font(.brandMono(size: 11.5))
                            .foregroundColor(highlightedIndices.contains(index) ? .teaHighlightFg : .ink2)
                    }
                    .padding(.horizontal, highlightedIndices.contains(index) ? 4 : 0)
                    .padding(.vertical, highlightedIndices.contains(index) ? 1 : 0)
                    .background(highlightedIndices.contains(index) ? Color.teaHighlightBg : .clear)
                    .cornerRadius(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.025))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.line, lineWidth: 1)
        )
        .cornerRadius(8)
    }
}
