import SwiftUI

// View models for the dashboard blocks `health` (Gesundheits-Score, six
// pillars) and `vitals` (last temperature / blood pressure entered in the app).
// Lenient like the rest: a missing block hides its card.

struct HealthPillar: Identifiable {
    let key: String
    let label: String
    let score: Double?
    let weight: Double?
    /// -1 falling, 0 flat, 1 rising (from "up"/"down"/"flat" or a number).
    let trend: Int?
    let reason: String?
    let color: Color

    var id: String { key }

    init?(json: JSONValue) {
        guard let key = json.str("key") ?? json.str("id") else { return nil }
        self.key = key
        label = json.str("label") ?? HealthPillar.defaultLabel(key)
        score = json.double("score") ?? json.double("value")
        weight = json.double("weight")
        if let number = json.double("trend") {
            trend = number > 0.5 ? 1 : (number < -0.5 ? -1 : 0)
        } else {
            switch (json.str("trend") ?? "").lowercased() {
            case "up", "steigend", "rising", "besser": trend = 1
            case "down", "fallend", "falling", "schlechter": trend = -1
            case "flat", "stabil", "gleich", "same": trend = 0
            default: trend = nil
            }
        }
        reason = json.str("reason") ?? json.str("text")
        color = HealthPillar.color(key: key, label: label, hex: json.str("color"))
    }

    var trendSymbol: String? {
        switch trend {
        case 1: return "arrow.up.right"
        case -1: return "arrow.down.right"
        case 0: return "arrow.right"
        default: return nil
        }
    }

    var trendWord: String {
        switch trend {
        case 1: return "steigend"
        case -1: return "fallend"
        case 0: return "stabil"
        default: return "ohne Trend"
        }
    }

    /// Design A colors per pillar (server `color` wins when it is a hex value).
    static func color(key: String, label: String, hex: String?) -> Color {
        if let hex, let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16), hex.count >= 6 {
            return Color(hex: value)
        }
        switch canonical(key, label) {
        case "sleep": return Color(hex: 0xB39DFA)
        case "recovery": return Color(hex: 0x68D8CB)
        case "metabolism": return Color(hex: 0x5AA7FF)
        case "circulation": return Color(hex: 0x8EC7A4)
        case "immune": return Color(hex: 0xFFD23F)
        case "routine": return Color(hex: 0xD6C28C)
        default: return BIOSTheme.text2
        }
    }

    /// Order of the ring and grid: Schlaf, Erholung, Stoffwechsel, Kreislauf, Abwehr, Routine.
    static let order = ["sleep", "recovery", "metabolism", "circulation", "immune", "routine"]

    static func canonical(_ key: String, _ label: String) -> String {
        let text = (key + " " + label).lowercased()
        if text.contains("sleep") || text.contains("schlaf") { return "sleep" }
        if text.contains("recover") || text.contains("erholung") { return "recovery" }
        if text.contains("metab") || text.contains("stoffwechsel") || text.contains("glucose") { return "metabolism" }
        if text.contains("circ") || text.contains("kreislauf") || text.contains("cardio") { return "circulation" }
        if text.contains("immun") || text.contains("abwehr") || text.contains("infect") { return "immune" }
        if text.contains("routine") || text.contains("habit") { return "routine" }
        return key
    }

    static func defaultLabel(_ key: String) -> String {
        switch canonical(key, "") {
        case "sleep": return "Schlaf"
        case "recovery": return "Erholung"
        case "metabolism": return "Stoffwechsel"
        case "circulation": return "Kreislauf"
        case "immune": return "Abwehr"
        case "routine": return "Routine"
        default: return key
        }
    }
}

struct HealthModel {
    let score: Double?
    let level: String?
    let deltaWeek: Double?
    let pillars: [HealthPillar]
    /// Pillars left out (no data), as text.
    let dropped: [String]
    let headline: String?
    let subline: String?
    let generatedAt: Date?

    init?(json: JSONValue?) {
        guard let json, json.objectValue != nil else { return nil }
        score = (json.double("score") ?? json.double("value")).map { Swift.max(0, Swift.min(100, $0)) }
        level = json.str("level") ?? json.str("level_text")
        deltaWeek = json.double("delta_week") ?? json.double("delta")
        let parsed = json.list("pillars").compactMap { HealthPillar(json: $0) }
        pillars = parsed.sorted { lhs, rhs in
            let left = HealthPillar.order.firstIndex(of: HealthPillar.canonical(lhs.key, lhs.label)) ?? 99
            let right = HealthPillar.order.firstIndex(of: HealthPillar.canonical(rhs.key, rhs.label)) ?? 99
            return left < right
        }
        dropped = json.list("dropped").compactMap { element in
            element.stringValue ?? element.str("label").map { label in
                element.str("reason").map { "\(label) (\($0))" } ?? label
            } ?? element.str("key")
        }
        headline = json.str("headline")
        subline = json.str("subline") ?? json.str("text")
        generatedAt = BIOSDate.parse(json.str("generated_at"))
        if score == nil, pillars.isEmpty { return nil }
    }

    /// Level word ("gut") and its color: server word, else from the score.
    var levelWord: String {
        if let level { return level }
        guard let score else { return "n. b." }
        if score >= 70 { return "gut" }
        if score >= 50 { return "mittel" }
        return "niedrig"
    }

    var levelColor: Color {
        switch levelWord.lowercased() {
        case "sehr gut", "gut", "hoch", "good": return BIOSTheme.good
        case "mittel", "ok", "medium": return BIOSTheme.mid
        case "niedrig", "schlecht", "low": return BIOSTheme.bad
        default: return BIOSTheme.text2
        }
    }

    /// "+4 zur Vorwoche"
    var deltaText: String? {
        guard let deltaWeek else { return nil }
        let rounded = deltaWeek.rounded()
        if rounded == 0 { return "wie Vorwoche" }
        return "\(BIOSFormat.signed(rounded)) zur Vorwoche"
    }

    var deltaSymbol: String {
        guard let deltaWeek, deltaWeek.rounded() != 0 else { return "arrow.right" }
        return deltaWeek > 0 ? "arrow.up.right" : "arrow.down.right"
    }

    /// Detail headline: server text, else from the level and the weakest pillar.
    var titleText: String {
        if let headline { return headline }
        switch levelWord.lowercased() {
        case "sehr gut", "gut": return "Ausgewogen."
        case "mittel": return "Gemischt."
        default: return "Unter deinem Schnitt."
        }
    }

    var secondText: String? {
        if let subline { return subline }
        guard let weakest = pillars.filter({ $0.score != nil }).min(by: { ($0.score ?? 0) < ($1.score ?? 0) }) else {
            return nil
        }
        return "Mit Luft für \(weakest.label)."
    }

    var freshnessText: String {
        dropped.isEmpty ? "Alle Daten aktuell" : "Ohne: " + dropped.joined(separator: ", ")
    }
}

/// Dashboard `vitals`: last app-entered temperature and blood pressure.
struct DashboardVitalsModel {
    let temperature: Double?
    let temperatureAt: Date?
    let temperatureTodayMax: Double?

    init(json: JSONValue) {
        let last = json.obj("temperature_last")
        temperature = last?.double("value")
        let raw = last?.str("measured_at")
        temperatureAt = raw.flatMap { BIOSDate.parse($0.count == 16 ? $0 + ":00" : $0) }
        temperatureTodayMax = json.double("temperature_today_max")
    }
}
