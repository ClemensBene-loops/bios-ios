import ActivityKit
import Foundation
import SwiftUI

// Shared between the app (starts the activity, uploads the push tokens) and
// the widget extension BIOSWidgets (draws lock screen banner and Dynamic
// Island). Compiled into both targets from Shared/ (project.yml).
//
// The server starts (push-to-start, iOS 17.2+) and updates the activity via
// APNs with `attributes-type: "BIOSActivityAttributes"`; the JSON of
// `content-state` is decoded with `ContentState.init(from:)` below. Every
// field is optional and decoded leniently: an unknown or missing field must
// never make ActivityKit drop a push. Times are strings ("12:30") and epoch
// seconds, never `Date` (ActivityKit decodes Date as seconds since 2001).

/// Static part of the BIOS Live Activity. Deliberately empty: push-to-start
/// sends `"attributes": {}` and everything that changes lives in ContentState.
struct BIOSActivityAttributes: ActivityAttributes {
    typealias ContentState = BIOSActivityState
}

/// What the banner shows right now.
enum BIOSActivityMode: String, Codable, Hashable, Sendable {
    /// Next intake (medication + time).
    case normal
    /// Infection episode: "Infekt · Tag n", infection score, next intake.
    case infection
    /// Elevated temperature: value, measurement time, "Erhöht", next intake.
    case temperature

    init(raw: String?) {
        switch (raw ?? "").lowercased() {
        case "infection", "infekt": self = .infection
        case "temperature", "temperatur", "fever", "fieber": self = .temperature
        default: self = .normal
        }
    }
}

/// `content-state` of the BIOS Live Activity (JSON keys in snake_case).
struct BIOSActivityState: Codable, Hashable, Sendable {
    var mode: BIOSActivityMode = .normal
    /// Gesundheits-Score 0...100 and its level word ("gut").
    var healthScore: Int?
    var healthLevel: String?
    /// Pillar scores 0...100 by key: sleep, recovery, metabolism,
    /// circulation, immune, routine (ring segments, missing = empty slot).
    var pillars: [String: Double]?
    /// Overall attention level for the status dot: "ok", "info", "warn".
    var status: String?
    var infectionScore: Int?
    var infectionDay: Int?
    /// Body temperature in °C, time of the measurement ("08:05"), label ("Erhöht").
    var temperature: Double?
    var temperatureTime: String?
    var temperatureLabel: String?
    /// Next planned intake: plan item id (for "Genommen"), name, time "HH:MM".
    var nextMedicationID: String?
    var nextMedication: String?
    var nextTime: String?
    /// Label above the intake ("Nächste Einnahme", "Später").
    var nextLabel: String?
    var supplementsTaken: Int?
    var supplementsTotal: Int?
    /// Unix seconds of the data this state was built from.
    var updatedAt: Double?

    init() {}

    enum CodingKeys: String, CodingKey {
        case mode
        case healthScore = "health_score"
        case healthLevel = "health_level"
        case pillars
        case status
        case infectionScore = "infection_score"
        case infectionDay = "infection_day"
        case temperature
        case temperatureTime = "temperature_time"
        case temperatureLabel = "temperature_label"
        case nextMedicationID = "next_medication_id"
        case nextMedication = "next_medication"
        case nextTime = "next_time"
        case nextLabel = "next_label"
        case supplementsTaken = "supplements_taken"
        case supplementsTotal = "supplements_total"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = BIOSActivityMode(raw: Self.string(c, .mode))
        healthScore = Self.int(c, .healthScore)
        healthLevel = Self.string(c, .healthLevel)
        pillars = (try? c.decodeIfPresent([String: Double].self, forKey: .pillars)) ?? nil
        status = Self.string(c, .status)
        infectionScore = Self.int(c, .infectionScore)
        infectionDay = Self.int(c, .infectionDay)
        temperature = Self.double(c, .temperature)
        temperatureTime = Self.string(c, .temperatureTime)
        temperatureLabel = Self.string(c, .temperatureLabel)
        // Plan ids may arrive as number or string.
        nextMedicationID = Self.string(c, .nextMedicationID) ?? Self.int(c, .nextMedicationID).map(String.init)
        nextMedication = Self.string(c, .nextMedication)
        nextTime = Self.string(c, .nextTime)
        nextLabel = Self.string(c, .nextLabel)
        supplementsTaken = Self.int(c, .supplementsTaken)
        supplementsTotal = Self.int(c, .supplementsTotal)
        updatedAt = Self.double(c, .updatedAt)
    }

    private static func string(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        guard let value = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func double(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        guard let value = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil, value.isFinite else { return nil }
        return value
    }

    private static func int(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        double(c, key).map { Int($0.rounded()) }
    }
}

// MARK: - Display helpers (German, used by the widget and the app preview)

extension BIOSActivityState {
    /// "3/4 · 1 offen", "4/4 · erledigt", nil without a supplement plan.
    var supplementsText: String? {
        guard let total = supplementsTotal, total > 0 else { return nil }
        let taken = min(max(supplementsTaken ?? 0, 0), total)
        let open = total - taken
        return "\(taken)/\(total) · " + (open == 0 ? "erledigt" : "\(open) offen")
    }

    /// "37,8 °C"
    var temperatureText: String? {
        guard let temperature else { return nil }
        return BIOSActivityFormat.decimal(temperature) + " °C"
    }

    /// "37,8°" (compact island).
    var temperatureShortText: String? {
        guard let temperature else { return nil }
        return BIOSActivityFormat.decimal(temperature) + "°"
    }

    var healthScoreText: String {
        healthScore.map { String(min(max($0, 0), 100)) } ?? "–"
    }

    /// Level word: server word, else from the score.
    var healthLevelText: String {
        if let healthLevel { return healthLevel }
        guard let healthScore else { return "n. b." }
        if healthScore >= 70 { return "gut" }
        if healthScore >= 50 { return "mittel" }
        return "niedrig"
    }

    var healthLevelColor: Color {
        switch healthLevelText.lowercased() {
        case "sehr gut", "gut", "hoch", "good": return BIOSActivityColors.positive
        case "mittel", "ok", "medium": return BIOSActivityColors.attention
        case "niedrig", "schlecht", "low": return BIOSActivityColors.warning
        default: return BIOSActivityColors.text2
        }
    }

    /// Attention level of the status dot: server `status`, else from the mode.
    var attention: BIOSActivityAttention {
        switch (status ?? "").lowercased() {
        case "warn", "red", "hoch", "high": return .warn
        case "info", "yellow", "mittel", "attention": return .info
        case "ok", "green", "gut": return .ok
        default:
            return mode == .normal ? .ok : .info
        }
    }

    /// Next intake line without a plan item: "Heute erledigt".
    var medicationText: String {
        nextMedication ?? "Heute erledigt"
    }

    /// Example state for previews and the local fallback before data arrives.
    /// Illustrative values only, no real data.
    static var preview: BIOSActivityState {
        var state = BIOSActivityState()
        state.healthScore = 78
        state.healthLevel = "gut"
        state.pillars = ["sleep": 82, "recovery": 74, "metabolism": 80, "circulation": 77, "immune": 60, "routine": 85]
        state.nextMedication = "Beispielmedikament"
        state.nextMedicationID = "example"
        state.nextTime = "12:30"
        state.supplementsTaken = 3
        state.supplementsTotal = 4
        return state
    }
}

enum BIOSActivityAttention: Sendable {
    case ok
    case info
    case warn

    var color: Color {
        switch self {
        case .ok: return BIOSActivityColors.positive
        case .info: return BIOSActivityColors.attention
        case .warn: return BIOSActivityColors.warning
        }
    }
}

enum BIOSActivityFormat {
    /// One decimal with a German comma: 37.8 -> "37,8".
    static func decimal(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Brand colors (design A, Live Activity revision 2)

enum BIOSActivityColors {
    static let forest = Color(activityHex: 0x133D21)
    static let cream = Color(activityHex: 0xFDF9EF)
    static let accent = Color(activityHex: 0x5AA7FF)
    static let positive = Color(activityHex: 0x34D662)
    static let attention = Color(activityHex: 0xFFD23F)
    static let warning = Color(activityHex: 0xFF5A5F)
    static let text2 = Color(activityHex: 0xA7AEBA)
    /// Banner background (dark, slightly green like the mockup).
    static let banner = Color(activityHex: 0x1A2420)

    /// Ring order clockwise from the top: key and color.
    static let pillars: [(key: String, color: Color)] = [
        ("sleep", Color(activityHex: 0xB39DFA)),
        ("recovery", Color(activityHex: 0x68D8CB)),
        ("metabolism", Color(activityHex: 0x5AA7FF)),
        ("circulation", Color(activityHex: 0x8EC7A4)),
        ("immune", Color(activityHex: 0xFFD23F)),
        ("routine", Color(activityHex: 0xD6C28C)),
    ]

    /// Ring key for a server pillar key or German label ("Schlaf" -> "sleep").
    static func pillarKey(_ key: String, label: String? = nil) -> String {
        let text = (key + " " + (label ?? "")).lowercased()
        if text.contains("sleep") || text.contains("schlaf") { return "sleep" }
        if text.contains("recover") || text.contains("erholung") { return "recovery" }
        if text.contains("metab") || text.contains("stoffwechsel") || text.contains("glucose") { return "metabolism" }
        if text.contains("circ") || text.contains("kreislauf") || text.contains("cardio") { return "circulation" }
        if text.contains("immun") || text.contains("abwehr") || text.contains("infect") { return "immune" }
        if text.contains("routine") || text.contains("habit") { return "routine" }
        return key
    }
}

extension Color {
    /// sRGB color from 0xRRGGBB (own initializer name: the app target has
    /// `Color(hex:)` in Theme.swift, the widget does not).
    init(activityHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
