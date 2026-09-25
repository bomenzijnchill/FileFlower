import SwiftUI

/// v2 SettingsCard — title + optional description + optional kicker badge top-right.
/// No leading icon (replaced by editorial typography).
struct SettingsCard<Content: View>: View {
    let title: String
    var desc: String? = nil
    var kicker: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.ink)
                    if let desc = desc {
                        Text(desc)
                            .font(.system(size: 12))
                            .foregroundColor(.ink3)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if let kicker = kicker {
                    KickerBadge(text: kicker)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.line, lineWidth: 1)
        )
        .cornerRadius(12)
        .padding(.bottom, 14)
    }
}
