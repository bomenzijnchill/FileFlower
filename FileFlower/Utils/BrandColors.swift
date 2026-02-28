import SwiftUI

extension Color {
    // MARK: - FileFlower Brand Colors

    // Primary Colors
    static let brandBurntPeach = Color(hex: "DE6B48")
    static let brandSandyClay = Color(hex: "E5B181")
    static let brandPowderBlush = Color(hex: "F4B9B2")
    static let brandTeaGreen = Color(hex: "DAEDBD")
    static let brandSkyBlue = Color(hex: "7DBBC3")

    // Petal Animation Colors
    static let petalLavender = Color(hex: "C8A2C8")
    static let petalRosePink = Color(hex: "E8A0BF")

    // Darker Variants
    static let brandBurntPeachDark = Color(hex: "A44B2F")
    static let brandSandyClayDark = Color(hex: "A67C57")
    static let brandSkyBlueDark = Color(hex: "5C898F")

    // Text
    static let brandTextDark = Color(hex: "3D2B1F")

    // MARK: - Hex Color Initializer

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}
