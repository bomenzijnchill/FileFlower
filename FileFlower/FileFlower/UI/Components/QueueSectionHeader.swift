import SwiftUI

enum SectionStyle {
    case attention
    case ready
}

struct QueueSectionHeader: View {
    let title: String
    let count: Int
    var style: SectionStyle = .ready
    /// Optionele actieknop rechts in de header (bijv. "Selecteer alles").
    var trailingButtonTitle: String? = nil
    var trailingButtonAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if style == .attention {
                Circle()
                    .fill(Color.brandBurntPeach)
                    .frame(width: 6, height: 6)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.ink3)
            }

            Text(title.uppercased())
                .font(.brandMono(size: 10, weight: .semibold))
                .tracking(1.0)
                .foregroundColor(style == .attention ? .brandBurntPeach : .ink3)

            Text("\(count) \(count == 1 ? String(localized: "common.item") : String(localized: "common.items"))")
                .font(.brandMono(size: 10))
                .foregroundColor(.ink3)

            Spacer()

            if let buttonTitle = trailingButtonTitle, let buttonAction = trailingButtonAction {
                Button(action: buttonAction) {
                    Text(buttonTitle)
                        .font(.brandMono(size: 10, weight: .semibold))
                        .foregroundColor(.brandBurntPeach)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.popSurfaceAlt.opacity(0.5))
    }
}
