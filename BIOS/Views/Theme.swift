import SwiftUI

extension Color {
    /// sRGB color from 0xRRGGBB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Colors of the approved v2 mockup (dark first). Semantic colors are always
/// paired with a symbol or a word in the UI, never used alone.
enum BIOSTheme {
    static let background = Color(hex: 0x06080B)
    static let card = Color(hex: 0x13161B)
    static let card2 = Color(hex: 0x1C2027)
    static let text1 = Color(hex: 0xF3F5F8)
    static let text2 = Color(hex: 0xA7AEBA)
    static let text3 = Color(hex: 0x8A93A0)
    static let accent = Color(hex: 0x5AA7FF)
    static let separator = Color.white.opacity(0.09)

    static let good = Color(hex: 0x34D662)
    static let mid = Color(hex: 0xFFD23F)
    static let bad = Color(hex: 0xFF5A5F)
    static let context = Color(hex: 0x93A5FF)

    static let viren = Color(hex: 0xB89CFF)
    static let pollen = Color(hex: 0x46D9C3)
    static let glucose = Color(hex: 0x5DB8FF)
    static let insulin = Color(hex: 0xFFA24C)
    static let loop = Color(hex: 0xB7C0CE)
    static let recovery = Color(hex: 0xF3F5F8)
    static let rhr = Color(hex: 0xFF7A8A)
    static let hrv = Color(hex: 0xA48BFF)
    static let sleep = Color(hex: 0x7F95FF)
    static let skin = Color(hex: 0xFF9F6B)
    static let resp = Color(hex: 0x5ED3C4)
    static let per10g = Color(hex: 0xFFC27A)
    static let auto = Color(hex: 0xFFD9A8)
    static let germany = Color(hex: 0x9AA3B2)
    static let strongTrend = Color(hex: 0xFFB072)

    // Text colors on tinted chip backgrounds (mockup).
    static let badText = Color(hex: 0xFF9A9D)
    static let midText = Color(hex: 0xFFE07A)
    static let contextText = Color(hex: 0xB7C3FF)
}

extension BIOSStatus {
    var symbol: String {
        switch self {
        case .warn: return "thermometer.medium"
        case .info: return "eye"
        case .ok: return "checkmark.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .warn: return BIOSTheme.bad
        case .info: return BIOSTheme.mid
        case .ok: return BIOSTheme.good
        case .unknown: return BIOSTheme.text3
        }
    }

    /// Glow of the hero card gradient.
    var glow: Color {
        switch self {
        case .warn: return BIOSTheme.bad.opacity(0.30)
        case .info: return BIOSTheme.mid.opacity(0.24)
        case .ok: return BIOSTheme.good.opacity(0.20)
        case .unknown: return Color.white.opacity(0.06)
        }
    }

    var word: String {
        switch self {
        case .warn: return "Warnung"
        case .info: return "Hinweis"
        case .ok: return "in Ordnung"
        case .unknown: return "unbekannt"
        }
    }
}

extension BIOSZone {
    var color: Color {
        switch self {
        case .green: return BIOSTheme.good
        case .yellow: return BIOSTheme.mid
        case .red: return BIOSTheme.bad
        case .none: return BIOSTheme.text3
        }
    }
}

enum BIOSLevel {
    /// Wastewater level word -> text color (the word itself is always shown).
    static func virusColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "mittel": return Color(hex: 0xFFD86A)
        case "hoch", "sehr hoch": return BIOSTheme.badText
        default: return BIOSTheme.text2
        }
    }

    /// Fine trend -> SF Symbol (direction is the information, color only adds emphasis).
    static func trendSymbol(_ fine: String) -> String {
        switch fine.lowercased() {
        case "stark steigend": return "arrow.up"
        case "leicht steigend", "steigend": return "arrow.up.right"
        case "leicht fallend": return "arrow.down.right"
        case "fallend", "stark fallend": return "arrow.down"
        default: return "arrow.right"
        }
    }

    static func isStrong(_ fine: String) -> Bool {
        fine.lowercased() == "stark steigend"
    }

    /// Pollen level rank 0...3 -> color of the dot (dot size encodes the level too).
    static func pollenColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return BIOSTheme.good
        case 2: return BIOSTheme.mid
        case 3...: return BIOSTheme.bad
        default: return BIOSTheme.text3
        }
    }
}

/// Card background of the mockup: dark, 22 pt continuous corners.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BIOSTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

extension View {
    func biosCard(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }

    /// Dark page background behind scroll content.
    func biosPageBackground() -> some View {
        background(BIOSTheme.background.ignoresSafeArea())
    }
}
