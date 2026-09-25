import SwiftUI

/// Small mono-uppercase badge displayed top-right of a card header.
/// Examples: "Anoniem", "Optioneel", "Geavanceerd", "Voorzichtig", "Apple Silicon".
struct KickerBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.brandMono(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(.peach3)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.brandBurntPeach.opacity(0.08))
            .cornerRadius(4)
    }
}
