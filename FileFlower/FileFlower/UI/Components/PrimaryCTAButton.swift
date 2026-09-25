import SwiftUI

struct PrimaryCTAButton: View {
    let title: String
    let shortcutHint: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))

                Text(shortcutHint)
                    .font(.brandMono(size: 10, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.brandBurntPeach)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel("\(title), \(shortcutHint)")
    }
}
