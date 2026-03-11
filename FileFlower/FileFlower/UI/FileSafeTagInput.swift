import SwiftUI

struct TagInputView: View {
    let title: String
    let placeholder: String
    @Binding var tags: [String]
    @State private var inputText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            // Bestaande tags
            if !tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        TagChip(text: tag) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                tags.removeAll { $0 == tag }
                            }
                        }
                    }
                }
            }

            // Invoerveld
            HStack(spacing: 6) {
                TextField(placeholder, text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        addTag()
                    }
                    .onChange(of: inputText) { _, newValue in
                        // Voeg tag toe bij komma
                        if newValue.contains(",") {
                            let parts = newValue.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                            for part in parts where !part.isEmpty && !tags.contains(part) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    tags.append(part)
                                }
                            }
                            inputText = ""
                        }
                    }

                if !inputText.isEmpty {
                    Button(action: addTag) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.controlBackgroundColor))
            )
        }
    }

    private func addTag() {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else {
            inputText = ""
            return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            tags.append(trimmed)
        }
        inputText = ""
    }
}

// MARK: - Tag Chip

struct TagChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Text(text)
                .font(.system(size: 11, weight: .medium))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.15))
        )
        .foregroundColor(.accentColor)
    }
}

// MARK: - Flow Layout (horizontale wrap)

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = calculateLayout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = calculateLayout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subviews[index].sizeThatFits(.unspecified))
            )
        }
    }

    private func calculateLayout(in maxWidth: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
