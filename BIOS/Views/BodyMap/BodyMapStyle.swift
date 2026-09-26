import SwiftUI

// Körperkarte: colors, symbols and texts in one place, so changes after the
// morning review stay small. Status texts and symbols mirror the server legend
// (`statuses[]` of GET /v1/bodymap); a status is always shown with symbol and
// word, never by color alone. Observation, no diagnosis wording.

enum BodyMapStyle {
    // MARK: Figure

    /// Thin cream outline (Whoop style) on the dark card.
    static let line = Color(hex: 0xFDF9EF)
    static let outlineOpacity = 0.55
    static let outlineFillOpacity = 0.025
    static let detailOpacity = 0.2
    /// Soft light behind the large figure.
    static let stageGlowOpacity = 0.045
    /// Region fill and stroke (with data).
    static let regionFillOpacity = 0.16
    static let regionStrokeOpacity = 0.45
    /// Region without data: grey, dashed.
    static let noDataFill = Color(hex: 0x8A93A0, opacity: 0.06)
    static let noDataStrokeOpacity = 0.75
    static let noDataDash: [CGFloat] = [2.5, 2.5]
    /// Glow: ellipses enlarged by this factor, blurred.
    static let glowScale: CGFloat = 1.6
    /// Badge on the large figure (fixed points, not scaled with the figure).
    static let badgeDiameter: CGFloat = 19
    static let badgeFill = Color(hex: 0x0B0E12, opacity: 0.92)
    static let badgeLineWidth: CGFloat = 1.6
    static let badgeSelectedLineWidth: CGFloat = 2.6
    /// Figure heights (width = height * aspect).
    static let largeHeight: CGFloat = 380
    static let miniHeight: CGFloat = 96

    // MARK: Texts

    static let title = "Körperkarte"
    static let note = "Beobachtung, keine Diagnose"
    static let listTitle = "Regionen"
    static let valuesTitle = "Werte"
    static let detailsTitle = "Details"
    static let doneButton = "Fertig"
    static let openHint = "Öffnet Werte und Details"
    static let todayHint = "Öffnet den Tab Körper"
    static let loading = "Körperkarte wird geladen ..."
    static let unavailableTitle = "Körperkarte noch nicht verfügbar"
    static let unavailableText = "Der Server liefert die Körperkarte noch nicht. Sie erscheint nach dem Server-Update von selbst."
    static let noDataTitle = "Körperkarte: keine Daten"
    static let neutralText = "Für diese Region gibt es noch keine Messwerte. Sie bleibt neutral, bis Laborwerte oder DEXA vorliegen."
    static let noMetricsText = "Für diese Region liegen gerade keine Werte vor."
    static let noReason = "Keine Daten"
    static let allOk = "Alles im Rahmen"
    static let partialErrors = "Nicht berechnet"

    static func sideTitle(_ side: BodyMapSide) -> String {
        side == .front ? "Vorne" : "Hinten"
    }

    static func sideSpoken(_ side: BodyMapSide) -> String {
        side == .front ? "Vorderansicht" : "Rückansicht"
    }

    /// Hint under the large figure: where the other regions are.
    static func sideNote(_ side: BodyMapSide) -> String {
        side == .front ? "Niere und Knochen: Ansicht Hinten" : "Übrige Regionen: Ansicht Vorne"
    }

    /// Fallback labels when the server sends none.
    static func regionLabel(_ id: String) -> String {
        switch id {
        case "kopf_schlaf": return "Kopf und Schlaf"
        case "abwehr": return "Abwehr und Hals"
        case "lunge": return "Lunge"
        case "herz": return "Herz und Kreislauf"
        case "leber": return "Leber"
        case "stoffwechsel": return "Stoffwechsel"
        case "niere": return "Niere"
        case "muskeln": return "Muskeln"
        case "knochen": return "Knochen"
        default: return id.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

extension BodyMapStatus {
    var color: Color {
        switch self {
        case .ok: return BIOSTheme.good
        case .beobachten: return BIOSTheme.mid
        case .auffaellig: return BIOSTheme.bad
        case .keineDaten: return BIOSTheme.text3
        }
    }

    /// Text color on a tinted background (sheet status box).
    var textColor: Color {
        switch self {
        case .ok: return Color(hex: 0x6CE58F)
        case .beobachten: return BIOSTheme.midText
        case .auffaellig: return BIOSTheme.badText
        case .keineDaten: return BIOSTheme.text2
        }
    }

    /// Tinted background of status badges and the sheet box (nil = outline only).
    var background: Color? {
        switch self {
        case .ok: return BIOSTheme.good.opacity(0.14)
        case .beobachten: return BIOSTheme.mid.opacity(0.14)
        case .auffaellig: return BIOSTheme.bad.opacity(0.15)
        case .keineDaten: return nil
        }
    }

    /// Center opacity of the glow (nil = no glow).
    var glowOpacity: Double? {
        switch self {
        case .ok: return 0.55
        case .beobachten: return 0.8
        case .auffaellig: return 0.95
        case .keineDaten: return nil
        }
    }

    /// Legend word, same as the server `statuses[].label`.
    var label: String {
        switch self {
        case .ok: return "Im Rahmen"
        case .beobachten: return "Beobachten"
        case .auffaellig: return "Auffällig"
        case .keineDaten: return "Keine Daten"
        }
    }

    /// Word inside VoiceOver sentences ("Lunge, beobachten: ...").
    var spoken: String {
        switch self {
        case .ok: return "im Rahmen"
        case .beobachten: return "beobachten"
        case .auffaellig: return "auffällig"
        case .keineDaten: return "keine Daten"
        }
    }

    /// SF Symbol standing alone (legend, metric rows), same as the server `symbol`.
    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle"
        case .beobachten: return "eye"
        case .auffaellig: return "exclamationmark.triangle"
        case .keineDaten: return "minus.circle"
        }
    }

    /// SF Symbol inside a round badge.
    var badgeSymbol: String {
        switch self {
        case .ok: return "checkmark"
        case .beobachten: return "eye"
        case .auffaellig: return "exclamationmark"
        case .keineDaten: return "minus"
        }
    }
}
