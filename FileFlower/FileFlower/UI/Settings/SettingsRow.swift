import SwiftUI

/// v2 SettingsRow — label + optional help on left, control on right.
/// Divider is rendered ABOVE the row (not below), skipped for the first row in a card.
struct SettingsRow<Control: View>: View {
    let label: String
    var help: String? = nil
    var isFirst: Bool = false
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(spacing: 0) {
            if !isFirst {
                Divider().background(Color.line)
            }
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.ink)
                    if let help = help {
                        Text(help)
                            .font(.system(size: 11.5))
                            .foregroundColor(.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                control()
            }
            .padding(.vertical, 12)
        }
    }
}
