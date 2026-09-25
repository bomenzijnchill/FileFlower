import SwiftUI

/// 2-column grid card for selecting a folder structure preset.
struct PresetCard: View {
    let name: String
    let meta: String
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ink)
                Text(meta)
                    .font(.system(size: 11))
                    .foregroundColor(.ink3)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isActive ? Color.brandBurntPeach.opacity(0.06) : Color.black.opacity(0.02))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(isActive ? Color.brandBurntPeach : Color.line, lineWidth: isActive ? 2 : 1)
            )
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
    }
}
