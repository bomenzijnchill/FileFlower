import SwiftUI

/// Peach-tinted Toggle wrapper. Replaces SwiftUI's iOS-blue default.
struct BrandToggle: View {
    @Binding var isOn: Bool
    var accessibilityLabel: String? = nil

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(.brandBurntPeach)
            .accessibilityLabel(accessibilityLabel ?? "")
            .accessibilityValue(isOn ? "aan" : "uit")
    }
}
