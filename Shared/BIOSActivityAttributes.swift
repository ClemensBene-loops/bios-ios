import ActivityKit
import Foundation
import SwiftUI

// Shared between the app (starts the activity, uploads the push tokens) and
// the widget extension BIOSWidgets (draws lock screen banner and Dynamic
// Island). Compiled into both targets from Shared/ (project.yml).
//
// The server starts (push-to-start, iOS 17.2+), updates and ends the
// activity via APNs with `attributes-type: "BIOSActivityAttributes"` and
// `attributes: {}`; `content-state` is the ContentState of docs/API_v1.md
// ("Live Activity", BIOS repo), keys exactly as below. Every field is
// optional and decoded leniently: an unknown, missing or mistyped field must
// never make ActivityKit drop a push. No `Date` fields (ActivityKit's decoder
// would read them as seconds since 2001): times stay ISO strings.

/// Static part of the BIOS Live Activity. Deliberately empty: push-to-start
/// sends `"attributes": {}` and everything that changes lives in ContentState.
struct BIOSActivityAttributes: ActivityAttributes {
    typealias ContentState = BIOSActivityState
}

/// What the banner shows right now (`mode`).
enum BIOSActivityMode: String, Codable, Hashable, Sendable {
    /// Next intake (medication + time).
    case normal
    /// Whoop alarm infekt / infekt_frueh: "Infekt · Tag n", infection score, next intake.
    case infection
    /// >= 37.5 °C within 12 h: value, measurement time, "Erhöht", next intake.
    case temperature

    init(raw: String?) {
        switch (raw ?? "").lowercased() {
        case "infection", "infekt": self = .infection
        case "temperature", "temperatur", "fever", "fieber": self = .temperature
        default: self = .normal
        }
    }
}

/// `content-state` of the BIOS Live Activity (server contract, snake_case).
struct BIOSActivityState: Codable, Hashable, Sendable {
    /// `next_medication`: first open plan time today.
    struct NextMedication: Codable, Hashable, Sendable {
        var name: String?
        /// "HH:MM"
        var time: String?
        var overdue: Bool?
        /// App only: plan item id for "Genommen" (the server sends the name).
        var id: String?
        /// App only: moved with "Später".
        var later: Bool?

        init(name: String?, time: String?, overdue: Bool? = nil, id: String? = nil, later: Bool? = nil) {
            self.name = name
            self.time = time
            self.overdue = overdue
            self.id = id
            self.later = later
        }

        enum CodingKeys: String, CodingKey {
            case name, time, overdue, id, later
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = LenientDecoding.string(c, .name)
            time = LenientDecoding.string(c, .time)
            overdue = LenientDecoding.bool(c, .overdue)
            id = LenientDecoding.string(c, .id) ?? LenientDecoding.int(c, .id).map(String.init)
            later = LenientDecoding.bool(c, .later)
        }
    }

    /// `supplements`: today's ticks.
    struct Supplements: Codable, Hashable, Sendable {
        var taken: Int?
        var total: Int?

        init(taken: Int?, total: Int?) {
            self.taken = taken
            self.total = total
        }

        enum CodingKeys: String, CodingKey {
            case taken, total
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            taken = LenientDecoding.int(c, .taken)
            total = LenientDecoding.int(c, .total)
        }
    }

    var healthScore: Int?
    var healthLevel: String?
    /// Six pillar scores 0...100 in ring order Schlaf, Erholung, Stoffwechsel,
    /// Kreislauf, Abwehr, Routine (null = no data, empty slot).
    var pillarsMini: [Double?]?
    var mode: BIOSActivityMode = .normal
    var infectionScore: Int?
    var infectionDay: Int?
    /// "infekt" or "infekt_frueh".
    var infectionKind: String?
    /// °C, time of the measurement (ISO), >= 37.5 within 12 h.
    var temperature: Double?
    var temperatureAt: String?
    var temperatureHigh: Bool?
    var nextMedication: NextMedication?
    var supplements: Supplements?
    /// ISO time of the data.
    var updatedAt: String?

    init() {}

    enum CodingKeys: String, CodingKey {
        case healthScore = "health_score"
        case healthLevel = "health_level"
        case pillarsMini = "pillars_mini"
        case mode
        case infectionScore = "infection_score"
        case infectionDay = "infection_day"
        case infectionKind = "infection_kind"
        case temperature
        case temperatureAt = "temperature_at"
        case temperatureHigh = "temperature_high"
        case nextMedication = "next_medication"
        case supplements
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        healthScore = LenientDecoding.int(c, .healthScore)
        healthLevel = LenientDecoding.string(c, .healthLevel)
        pillarsMini = (try? c.decodeIfPresent([Double?].self, forKey: .pillarsMini)) ?? nil
        mode = BIOSActivityMode(raw: LenientDecoding.string(c, .mode))
        infectionScore = LenientDecoding.int(c, .infectionScore)
        infectionDay = LenientDecoding.int(c, .infectionDay)
        infectionKind = LenientDecoding.string(c, .infectionKind)
        temperature = LenientDecoding.double(c, .temperature)
        temperatureAt = LenientDecoding.string(c, .temperatureAt)
        temperatureHigh = LenientDecoding.bool(c, .temperatureHigh)
        nextMedication = (try? c.decodeIfPresent(NextMedication.self, forKey: .nextMedication)) ?? nil
        supplements = (try? c.decodeIfPresent(Supplements.self, forKey: .supplements)) ?? nil
        updatedAt = LenientDecoding.string(c, .updatedAt)
    }
}

/// decodeIfPresent that turns a wrong type into nil instead of an error.
enum LenientDecoding {
    static func string<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? {
        guard let value = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func double<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
        guard let value = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil, value.isFinite else { return nil }
        return value
    }

    static func int<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
        double(c, key).map { Int($0.rounded()) }
    }

    static func bool<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Bool? {
        if let value = (try? c.decodeIfPresent(Bool.self, forKey: key)) ?? nil { return value }
        return double(c, key).map { $0 != 0 }
    }
}

// MARK: - Display helpers (German, used by the widget)

extension BIOSActivityState {
    /// "3/4 · 1 offen", "4/4 · erledigt", nil without a supplement plan.
    var supplementsText: String? {
        guard let total = supplements?.total, total > 0 else { return nil }
        let taken = min(max(supplements?.taken ?? 0, 0), total)
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

    /// "08:05" of `temperature_at`.
    var temperatureTime: String? {
        BIOSActivityFormat.clock(temperatureAt)
    }

    /// "Erhöht" (>= 37.5), "Fieber" from 38.0.
    var temperatureLabel: String {
        (temperature ?? 0) >= 38.0 ? "Fieber" : "Erhöht"
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

    /// Status dot: attention in the infection and temperature modes.
    var attention: BIOSActivityAttention {
        mode == .normal ? .ok : .info
    }

    /// Pillar score of ring slot `index` (0...5), nil = no data.
    func pillar(_ index: Int) -> Double? {
        guard let values = pillarsMini, values.indices.contains(index) else { return nil }
        return values[index]
    }

    var hasNextMedication: Bool {
        nextMedication?.name != nil
    }

    /// Next intake name, "Heute erledigt" without an open plan time.
    var medicationText: String {
        nextMedication?.name ?? "Heute erledigt"
    }

    var nextTime: String? {
        nextMedication?.time
    }

    /// Label above the intake: "Nächste Einnahme", "Überfällig", "Später".
    var nextLabel: String {
        guard hasNextMedication else { return "Einnahmen" }
        if nextMedication?.later == true { return "Später" }
        if nextMedication?.overdue == true { return "Überfällig" }
        return "Nächste Einnahme"
    }

    /// Example state for previews. Illustrative values only, no real data.
    static var preview: BIOSActivityState {
        var state = BIOSActivityState()
        state.healthScore = 78
        state.healthLevel = "gut"
        state.pillarsMini = [82, 74, 80, 77, 60, 85]
        state.nextMedication = NextMedication(name: "Beispielmedikament", time: "12:30", overdue: false)
        state.supplements = Supplements(taken: 3, total: 4)
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

    /// "HH:MM" in local time from an ISO timestamp (with offset), else the
    /// wall-clock part after "T".
    static func clock(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = formatter.date(from: iso)
        }
        if let date {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
        guard let tIndex = iso.firstIndex(of: "T") else { return nil }
        let clock = iso[iso.index(after: tIndex)...].prefix(5)
        return clock.count == 5 ? String(clock) : nil
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
