import SwiftUI

/// macOS Settings.app-style colored icon tile used in the sidebar nav list.
/// 22×22, radius 5.5, white SF Symbol icon, gradient background per category.
struct NavTile: View {
    let icon: String
    let topColor: Color
    let bottomColor: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [topColor, bottomColor],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5.5)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .cornerRadius(5.5)
            .shadow(color: .black.opacity(0.1), radius: 1, y: 0.5)
    }
}

extension SettingsTab {
    var tileTopColor: Color {
        switch self {
        case .general: return .tileGraphiteTop
        case .library: return .tileBlueTop
        case .template: return .tileClayTop
        case .classification: return .tilePurpleTop
        case .integrations: return .tilePeachTop
        case .account: return .tileTealTop
        case .advanced: return .tileGraphiteDarkTop
        #if canImport(BridgeKit)
        case .bridge: return .tileTealTop
        #endif
        }
    }

    var tileBottomColor: Color {
        switch self {
        case .general: return .tileGraphiteBottom
        case .library: return .tileBlueBottom
        case .template: return .tileClayBottom
        case .classification: return .tilePurpleBottom
        case .integrations: return .tilePeachBottom
        case .account: return .tileTealBottom
        case .advanced: return .tileGraphiteDarkBot
        #if canImport(BridgeKit)
        case .bridge: return .tileTealBottom
        #endif
        }
    }
}
