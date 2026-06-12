import SwiftUI

// MARK: - Pool Side Brand Colors
// Source: Pool Side Color Palette — Track. Balance. Enjoy.

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Named Palette
// Colors are defined as named assets in Assets.xcassets — edit values there in Xcode.

enum PoolColor {
    /// #0C3566 — Deep, trustworthy. Primary app background.
    static let deepWater   = Color("DeepWater")

    /// #356082 — Surface color for cards, containers, nav bars.
    static let oceanBlue   = Color("OceanBlue")

    /// #328680 — Primary brand color. Clean, inviting.
    static let poolTeal    = Color("PoolTeal")

    /// #FFC857 — Primary action color. CTAs, highlights.
    static let sunshine    = Color("Sunshine")

    /// #52B201 — Success / ideal levels.
    static let palmGreen   = Color("PalmGreen")

    /// #FF7F48 — Alerts, warnings, treatment actions.
    static let coral       = Color("Coral")

    /// #F5F1EA — Warm neutral background. Light, airy.
    static let sand        = Color("Sand")

    /// #FFFFFF — Elevated surfaces and content backgrounds.
    static let cloudWhite  = Color("CloudWhite")

    // MARK: - Chemical Status Colors

    /// #52C96C — Ideal range
    static let statusIdeal        = Color("StatusIdeal")

    /// #FFC857 — Slightly low / slightly high
    static let statusSlight       = Color("StatusSlight")

    /// #FF9C00 — Low / High
    static let statusOffRange     = Color("StatusOffRange")

    /// #FF4B4B — Critical
    static let statusCritical     = Color("StatusCritical")

    /// #A8A8A8 — Testing / awaiting results
    static let statusTesting      = Color("StatusTesting")

    // MARK: - Semantic Aliases (Light Theme)

    static let appBackground      = Color(hex: "F5F7F6")  // very light teal-tinted white
    static let cardBackground     = cloudWhite             // pure white cards
    static let primaryText        = deepWater              // dark navy for headings
    static let secondaryText      = Color(hex: "6B7A8D")  // medium gray-blue
    static let divider            = Color(hex: "E8ECEA")  // subtle divider
    static let primaryBrand       = poolTeal
    static let primaryAction      = sunshine
    static let success            = palmGreen
    static let warning            = coral
    static let neutralBackground  = sand
    static let elevatedSurface    = cloudWhite
}

// MARK: - Gradient Helpers

extension LinearGradient {
    static var poolBackground: LinearGradient {
        LinearGradient(
            colors: [PoolColor.deepWater, Color(hex: "0A2E5A")],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var tealAccent: LinearGradient {
        LinearGradient(
            colors: [PoolColor.poolTeal, Color(hex: "2A7070")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var sunshineAction: LinearGradient {
        LinearGradient(
            colors: [PoolColor.sunshine, Color(hex: "FFB020")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
