import SwiftUI

/// Editorial page header used at the top of every tab content.
/// Eyebrow (mono uppercase) → Title (Instrument Serif italic) → Lede (regular).
struct PageHead: View {
    let eyebrow: String
    let title: String
    let lede: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.brandMono(size: 10.5, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.ink3)

            Text(title)
                .font(.brandSerifItalic(size: 32))
                .foregroundColor(.ink)

            Text(lede)
                .font(.system(size: 14))
                .foregroundColor(.ink2)
        }
        .padding(.bottom, 18)
    }
}
