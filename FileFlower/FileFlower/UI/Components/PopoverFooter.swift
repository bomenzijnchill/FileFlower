import SwiftUI

struct PopoverFooter<MenuContent: View>: View {
    let leftText: String
    var ctaTitle: String? = nil
    var ctaCount: Int = 0
    var ctaEnabled: Bool = true
    var ctaAction: (() -> Void)? = nil
    /// Optionele losse icoonknop links van het menu (bijv. wachtrij legen).
    var secondaryIcon: String? = nil
    var secondaryHelp: String? = nil
    var secondaryAction: (() -> Void)? = nil
    @ViewBuilder var menuContent: () -> MenuContent

    var body: some View {
        HStack(spacing: 8) {
            Text(leftText)
                .font(.system(size: 11))
                .foregroundColor(.ink3)
                .lineLimit(1)

            Spacer()

            if let icon = secondaryIcon, let action = secondaryAction {
                Button(action: action) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.ink3)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(secondaryHelp ?? "")
                .accessibilityLabel(secondaryHelp ?? "")
            }

            Menu {
                menuContent()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ink3)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .accessibilityLabel(String(localized: "common.more_options"))

            if let title = ctaTitle, let action = ctaAction {
                PrimaryCTAButton(
                    title: "\(title) \(ctaCount) \(ctaCount == 1 ? String(localized: "common.item") : String(localized: "common.items"))",
                    shortcutHint: "\u{2318}\u{21A9}",
                    isEnabled: ctaEnabled && ctaCount > 0,
                    action: action
                )
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color.popSurfaceAlt.opacity(0.5))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.line).frame(height: 1)
        }
    }
}
