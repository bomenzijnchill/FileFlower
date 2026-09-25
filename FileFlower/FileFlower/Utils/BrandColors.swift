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

    // MARK: - v2 Settings Tokens (editorial palette)
    // Adaptive — light/dark variants resolved automatically.

    // Peach scale
    static let peach2 = Color(hex: "C75836")
    static let peach3 = Color(hex: "A24327")

    // Paper / surfaces (adaptive)
    static let paper0 = Color(light: "FBF7F0", dark: "221A11")
    static let paper1 = Color(light: "F6EFE3", dark: "1B140C")
    static let paper2 = Color(light: "EFE5D2", dark: "2A2014")
    static let cardBg = Color(light: "FFFFFF", dark: "2A2014")

    // Ink (text) — adaptive
    static let ink   = Color(light: "2A1C12", dark: "F4E9D8")
    static let ink2  = Color(light: "5C4736", darkRGBA: (244, 233, 216, 0.74))
    static let ink3  = Color(light: "8E7A66", darkRGBA: (244, 233, 216, 0.5))
    static let ink4  = Color(light: "B6A48E", darkRGBA: (244, 233, 216, 0.36))

    // Lines — adaptive
    static let line  = Color(lightRGBA: (42, 28, 18, 0.08), darkRGBA: (255, 255, 255, 0.07))
    static let line2 = Color(lightRGBA: (42, 28, 18, 0.14), darkRGBA: (255, 255, 255, 0.14))

    // Status
    static let statusOk   = Color(hex: "4FB155")
    static let statusWarn = Color(hex: "E08B3D")
    static let statusBad  = Color(hex: "C24A3F")

    // Sidebar nav-tile gradient stops
    static let tileGraphiteTop      = Color(hex: "9CA3AF")
    static let tileGraphiteBottom   = Color(hex: "6B7280")
    static let tileBlueTop          = Color(hex: "6FA9E5")
    static let tileBlueBottom       = Color(hex: "3D7DC5")
    static let tileClayTop          = Color(hex: "E5B181")
    static let tileClayBottom       = Color(hex: "C2895A")
    static let tilePurpleTop        = Color(hex: "B387D2")
    static let tilePurpleBottom     = Color(hex: "8556B5")
    static let tilePeachTop         = Color(hex: "DE6B48")
    static let tilePeachBottom      = Color(hex: "B14E2E")
    static let tileTealTop          = Color(hex: "7DBBC3")
    static let tileTealBottom       = Color(hex: "4F8E96")
    static let tileGraphiteDarkTop  = Color(hex: "4D5360")
    static let tileGraphiteDarkBot  = Color(hex: "2D323D")

    // Integration tile colors
    static let prGradientTop  = Color(hex: "5A36AB")
    static let prGradientBot  = Color(hex: "261758")
    static let prTextColor    = Color(hex: "EAA8FF")
    static let dvGradientTop  = Color(hex: "FF7062")
    static let dvGradientBot  = Color(hex: "C73E1D")

    // Tea preview highlight
    static let teaHighlightBg = Color(red: 218/255, green: 237/255, blue: 189/255, opacity: 0.5)
    static let teaHighlightFg = Color(hex: "4A6D29")

    // MARK: - v3 Popover Tokens

    // Header cocoa gradient (dark header)
    static let headerTop    = Color(light: "2A1C12", dark: "1A1210")
    static let headerBottom = Color(light: "3A2818", dark: "251A10")
    static let headerInk    = Color(light: "FBF6EC", dark: "FBF6EC")
    static let headerGlass  = Color(lightRGBA: (255, 255, 255, 0.08), darkRGBA: (255, 255, 255, 0.06))

    // Popover surfaces
    static let popSurface     = Color(light: "FBF7F0", dark: "1E1610")
    static let popSurfaceAlt  = Color(light: "F4ECDB", dark: "2A2014")
    static let popAttentionBg = Color(light: "FFEEDF", dark: "3A2518")

    // Destination chip (green — "tea")
    static let destChipBg  = Color(light: "DAEDBD", dark: "1B3A1B")
    static let destChipInk = Color(light: "4A6D29", dark: "81C784")

    // AI suggestion chip (sky)
    static let aiChipBg  = Color(lightRGBA: (125, 187, 195, 0.20), darkRGBA: (125, 187, 195, 0.15))
    static let aiChipInk = Color(light: "2D7E89", dark: "7DBBC3")

    // MARK: - Path Editor Tokens

    // Existing folder chip (sky-blue)
    static let pathExistBg          = Color(lightRGBA: (125,187,195, 0.14), darkRGBA: (125,187,195, 0.22))
    static let pathExistBorder      = Color(lightRGBA: (125,187,195, 0.32), darkRGBA: (125,187,195, 0.45))
    static let pathExistFg          = Color(light: "5C898F", dark: "93C8CF")
    static let pathExistHoverBg     = Color(lightRGBA: (125,187,195, 0.22), darkRGBA: (125,187,195, 0.30))
    static let pathExistHoverBorder = Color(lightRGBA: (125,187,195, 0.55), darkRGBA: (125,187,195, 0.65))
    static let pathExistUnderline   = Color(lightRGBA: (125,187,195, 0.55), darkRGBA: (125,187,195, 0.60))

    // New folder chip (burnt-peach, dashed)
    static let pathNewBg       = Color(lightRGBA: (222,107,72, 0.10), darkRGBA: (222,107,72, 0.18))
    static let pathNewBorder   = Color(lightRGBA: (222,107,72, 0.50), darkRGBA: (222,107,72, 0.50))
    static let pathNewFg       = Color(light: "A44B2F", dark: "E08060")
    static let pathNewHoverBg  = Color(lightRGBA: (222,107,72, 0.16), darkRGBA: (222,107,72, 0.24))
    static let pathNewHandle   = Color(lightRGBA: (164,75,47, 0.40), darkRGBA: (222,107,72, 0.45))

    // Token chip (tea-green)
    static let pathTokenBgFrom  = Color(lightRGBA: (218,237,189, 0.55), darkRGBA: (218,237,189, 0.22))
    static let pathTokenBgTo    = Color(lightRGBA: (218,237,189, 0.30), darkRGBA: (218,237,189, 0.14))
    static let pathTokenBorder  = Color(lightRGBA: (91,135,40, 0.30), darkRGBA: (91,135,40, 0.35))
    static let pathTokenFg      = Color(light: "3A5A1F", dark: "B8D49A")

    // Project chip (green tint)
    static let pathProjectBg     = Color(lightRGBA: (91,135,40, 0.10), darkRGBA: (91,135,40, 0.18))
    static let pathProjectBorder = Color(lightRGBA: (91,135,40, 0.22), darkRGBA: (91,135,40, 0.30))
    static let pathProjectFg     = Color(light: "3A5A1F", dark: "B8D49A")

    // Row container
    static let pathRowBg       = Color(light: "FFFFFF", dark: "2A2014")
    static let pathRowHeaderBg = Color(light: "FAF5EE", dark: "302418")

    // Category dots
    static let pathDotVideo = Color(hex: "7DBBC3")
    static let pathDotAudio = Color(hex: "E5B181")
    static let pathDotPhoto = Color(hex: "F4B9B2")

    // Insert button
    static let pathInsertBorder = Color(lightRGBA: (42,28,18, 0.20), darkRGBA: (255,255,255, 0.15))

    // MARK: - FileSafe Wizard Tokens

    // Surfaces
    static let fsBg          = Color(light: "F7F2EC", darkRGBA: (24, 18, 12, 1.0))
    static let fsBgAlt       = Color(light: "FBF7F1", darkRGBA: (32, 24, 16, 1.0))
    static let fsCardBg      = Color(light: "FFFFFF", dark: "2A2014")
    static let fsSurface2    = Color(light: "FAF5EE", dark: "302418")

    // Banner-soft (info, warn, ok, bad)
    static let fsBannerOk        = Color(lightRGBA: (91,135,40, 0.10),  darkRGBA: (91,135,40, 0.25))
    static let fsBannerOkBorder  = Color(lightRGBA: (91,135,40, 0.25),  darkRGBA: (91,135,40, 0.40))
    static let fsBannerOkInk     = Color(light: "1F5A25", dark: "9CC889")

    static let fsBannerWarn       = Color(lightRGBA: (224,139,61, 0.12), darkRGBA: (224,139,61, 0.22))
    static let fsBannerWarnBorder = Color(lightRGBA: (180,130,40, 0.30), darkRGBA: (224,139,61, 0.45))
    static let fsBannerWarnInk    = Color(light: "7A4F10", dark: "F4B97A")

    static let fsBannerBad        = Color(lightRGBA: (194,74,63, 0.10),  darkRGBA: (194,74,63, 0.22))
    static let fsBannerBadBorder  = Color(lightRGBA: (194,74,63, 0.30),  darkRGBA: (194,74,63, 0.45))
    static let fsBannerBadInk     = Color(light: "8A2A20", dark: "F08070")

    static let fsBannerInfo       = Color(lightRGBA: (125,187,195, 0.14), darkRGBA: (125,187,195, 0.22))
    static let fsBannerInfoBorder = Color(lightRGBA: (125,187,195, 0.28), darkRGBA: (125,187,195, 0.45))
    static let fsBannerInfoInk    = Color(light: "2D7E89", dark: "9DCED5")

    // Step indicator
    static let fsStepDoneBg     = Color(hex: "DAEDBD")  // teaGreen
    static let fsStepDoneInk    = Color(light: "3A5A1F", dark: "B8D49A")
    static let fsStepActiveBg   = Color(hex: "DE6B48")  // burntPeach
    static let fsStepActiveInk  = Color(light: "FFFFFF", dark: "FFFFFF")
    static let fsStepIdleBg     = Color(light: "FFFFFF", dark: "302418")
    static let fsStepIdleInk    = Color(light: "8A786A", dark: "B6A48E")

    // Diff glyphs
    static let fsDiffNew    = Color(light: "1F5A25", dark: "9CC889")
    static let fsDiffDup    = Color(light: "B47828", dark: "F4B97A")
    static let fsDiffSame   = Color(light: "8A786A", dark: "B6A48E")

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

    /// Adaptive color from two hex strings.
    init(light: String, dark: String) {
        #if canImport(AppKit)
        let lightNS = NSColor.fromHex(light)
        let darkNS = NSColor.fromHex(dark)
        let dynamic = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            return isDark ? darkNS : lightNS
        }
        self.init(nsColor: dynamic)
        #else
        self.init(hex: light)
        #endif
    }

    /// Adaptive color from RGBA tuples (0-255 with alpha 0-1).
    init(lightRGBA: (Int, Int, Int, Double), darkRGBA: (Int, Int, Int, Double)) {
        #if canImport(AppKit)
        let lightNS = NSColor(red: CGFloat(lightRGBA.0)/255,
                              green: CGFloat(lightRGBA.1)/255,
                              blue: CGFloat(lightRGBA.2)/255,
                              alpha: CGFloat(lightRGBA.3))
        let darkNS = NSColor(red: CGFloat(darkRGBA.0)/255,
                             green: CGFloat(darkRGBA.1)/255,
                             blue: CGFloat(darkRGBA.2)/255,
                             alpha: CGFloat(darkRGBA.3))
        let dynamic = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            return isDark ? darkNS : lightNS
        }
        self.init(nsColor: dynamic)
        #else
        self.init(.sRGB,
                  red: Double(lightRGBA.0)/255,
                  green: Double(lightRGBA.1)/255,
                  blue: Double(lightRGBA.2)/255,
                  opacity: lightRGBA.3)
        #endif
    }

    /// Adaptive color: hex for light, RGBA for dark.
    init(light: String, darkRGBA: (Int, Int, Int, Double)) {
        #if canImport(AppKit)
        let lightNS = NSColor.fromHex(light)
        let darkNS = NSColor(red: CGFloat(darkRGBA.0)/255,
                             green: CGFloat(darkRGBA.1)/255,
                             blue: CGFloat(darkRGBA.2)/255,
                             alpha: CGFloat(darkRGBA.3))
        let dynamic = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            return isDark ? darkNS : lightNS
        }
        self.init(nsColor: dynamic)
        #else
        self.init(hex: light)
        #endif
    }
}

#if canImport(AppKit)
import AppKit

extension NSColor {
    fileprivate static func fromHex(_ hex: String) -> NSColor {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        return NSColor(red: r, green: g, blue: b, alpha: 1)
    }
}
#endif

// MARK: - Brand Typography (v2)

extension Font {
    /// Instrument Serif italic for editorial page titles.
    static func brandSerifItalic(size: CGFloat) -> Font {
        Font.custom("InstrumentSerif-Italic", size: size)
    }

    /// JetBrains Mono for paths and badges.
    static func brandMono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold: name = "JetBrainsMono-SemiBold"
        case .medium: name = "JetBrainsMono-Medium"
        default: name = "JetBrainsMono-Regular"
        }
        return Font.custom(name, size: size)
    }
}
