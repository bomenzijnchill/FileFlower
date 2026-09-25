import SwiftUI

/// Visual centerpiece for the Account tab: peach gradient + serif italic name + glass action buttons.
/// Background uses 3 layered gradients matching the mockup:
/// - Teal radial glow top-right (25% opacity)
/// - Tea-green radial glow bottom-left (35% opacity)
/// - Peach diagonal base (135°)
struct AccountHero: View {
    let role: String
    let name: String
    let meta: String
    let primaryAction: (title: String, action: () -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Layer 1: peach diagonal base
            LinearGradient(
                colors: [.brandBurntPeach, Color(hex: "C2522F")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Layer 2: tea-green radial glow bottom-left
            RadialGradient(
                colors: [Color(hex: "DAEDBD").opacity(0.35), Color(hex: "DAEDBD").opacity(0)],
                center: UnitPoint(x: 0.0, y: 1.0),
                startRadius: 0,
                endRadius: 320
            )

            // Layer 3: teal radial glow top-right
            RadialGradient(
                colors: [Color(hex: "7DBBC3").opacity(0.30), Color(hex: "7DBBC3").opacity(0)],
                center: UnitPoint(x: 0.8, y: 0.2),
                startRadius: 0,
                endRadius: 260
            )

            // Decorative flower mark top-right
            GeometryReader { geo in
                Image("FileFlowerLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 220, height: 220)
                    .opacity(0.22)
                    .blendMode(.plusLighter)
                    .position(x: geo.size.width - 60, y: 50)
            }
            .allowsHitTesting(false)

            // Content
            VStack(alignment: .leading, spacing: 8) {
                Text(role.uppercased())
                    .font(.brandMono(size: 11, weight: .semibold))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.85))

                Text(name)
                    .font(.brandSerifItalic(size: 28))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.top, 2)

                Text(meta)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360, alignment: .leading)

                if let primary = primaryAction {
                    HStack(spacing: 8) {
                        GlassButton(title: primary.title, action: primary.action)
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.brandBurntPeach.opacity(0.18), radius: 14, x: 0, y: 4)
        .padding(.bottom, 14)
    }
}

private struct GlassButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    ZStack {
                        Color.white.opacity(isHovered ? 0.24 : 0.16)
                        Rectangle()
                            .fill(.ultraThinMaterial.opacity(0.4))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                )
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
