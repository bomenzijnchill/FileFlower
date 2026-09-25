import SwiftUI

enum BrandButtonVariant {
    case primary
    case secondary
    case ghost
    case danger
}

enum BrandButtonSize {
    case tiny
    case regular
}

struct BrandButton: View {
    let title: String
    var icon: String? = nil
    var variant: BrandButtonVariant = .secondary
    var size: BrandButtonSize = .regular
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: fontSize - 1, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: fontSize, weight: .medium))
            }
            .padding(.horizontal, paddingH)
            .padding(.vertical, paddingV)
            .background(background)
            .foregroundColor(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    // MARK: - Style derivations

    private var fontSize: CGFloat { size == .tiny ? 11 : 12.5 }
    private var paddingH: CGFloat { size == .tiny ? 7 : 12 }
    private var paddingV: CGFloat { size == .tiny ? 3 : 6 }

    private var background: Color {
        switch variant {
        case .primary:
            return isHovered ? .peach2 : .brandBurntPeach
        case .secondary:
            return isHovered ? .paper2 : .cardBg
        case .ghost:
            return isHovered ? .peach3.opacity(0.08) : .clear
        case .danger:
            return isHovered ? .statusBad.opacity(0.08) : .clear
        }
    }

    private var foreground: Color {
        switch variant {
        case .primary: return .white
        case .secondary: return .ink
        case .ghost: return .peach3
        case .danger: return .statusBad
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary: return .peach2
        case .secondary: return .line2
        case .ghost: return .clear
        case .danger: return .statusBad.opacity(0.3)
        }
    }

    private var borderWidth: CGFloat {
        variant == .ghost ? 0 : 1
    }

    private var shadowColor: Color {
        variant == .primary ? Color.brandBurntPeach.opacity(0.3) : .clear
    }

    private var shadowRadius: CGFloat { variant == .primary ? 2 : 0 }
    private var shadowY: CGFloat { variant == .primary ? 1 : 0 }
}
