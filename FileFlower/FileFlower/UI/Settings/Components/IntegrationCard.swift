import SwiftUI

enum IntegrationLogo {
    case premiere   // Pr — purple gradient
    case resolve    // DV — red gradient
    case browser    // Chrome conic
    case fileFlower // serif italic F on peach
}

enum IntegrationStatusKind {
    case ok, warn, bad

    var dotColor: Color {
        switch self {
        case .ok: return .statusOk
        case .warn: return .statusWarn
        case .bad: return .statusBad
        }
    }

    var pillBg: Color {
        switch self {
        case .ok: return Color(red: 79/255, green: 177/255, blue: 85/255, opacity: 0.10)
        case .warn: return Color(red: 224/255, green: 139/255, blue: 61/255, opacity: 0.13)
        case .bad: return Color(red: 194/255, green: 74/255, blue: 63/255, opacity: 0.12)
        }
    }

    var pillFg: Color {
        switch self {
        case .ok: return Color(hex: "2D7E33")
        case .warn: return Color(hex: "8E5825")
        case .bad: return Color(hex: "8E342B")
        }
    }
}

/// v2 IntegrationCard — 44×44 logo tile, name + sub, status pill, and arbitrary body content.
struct IntegrationCard<Body: View>: View {
    let logo: IntegrationLogo
    let name: String
    let sub: String
    let status: String
    let statusKind: IntegrationStatusKind
    @ViewBuilder let bodyContent: () -> Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center, spacing: 12) {
                AppLogoTile(logo: logo)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.ink)
                    Text(sub)
                        .font(.brandMono(size: 11.5))
                        .foregroundColor(.ink3)
                }

                Spacer()

                StatusPill(text: status, kind: statusKind)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            // Body
            VStack(spacing: 0) {
                bodyContent()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.015))
            .overlay(
                Rectangle()
                    .fill(Color.line)
                    .frame(height: 1),
                alignment: .top
            )
        }
        .background(Color.cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.line, lineWidth: 1)
        )
        .cornerRadius(12)
        .padding(.bottom, 14)
    }
}

private struct AppLogoTile: View {
    let logo: IntegrationLogo

    var body: some View {
        Group {
            switch logo {
            case .premiere:
                ZStack {
                    LinearGradient(colors: [.prGradientTop, .prGradientBot],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text("Pr")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.prTextColor)
                }
            case .resolve:
                ZStack {
                    LinearGradient(colors: [.dvGradientTop, .dvGradientBot],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text("DV")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }
            case .browser:
                ZStack {
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(hex: "DC4E41"),
                            Color(hex: "FFCD40"),
                            Color(hex: "0F9D58"),
                            Color(hex: "4285F4"),
                            Color(hex: "DC4E41")
                        ]),
                        center: .center
                    )
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(Color(hex: "4285F4"))
                        .frame(width: 8, height: 8)
                }
            case .fileFlower:
                ZStack {
                    LinearGradient(colors: [.brandBurntPeach, .peach2],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text("F")
                        .font(.brandSerifItalic(size: 22))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: 44, height: 44)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
    }
}

private struct StatusPill: View {
    let text: String
    let kind: IntegrationStatusKind

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(kind.dotColor)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(kind.pillFg)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(kind.pillBg)
        .clipShape(Capsule())
    }
}
