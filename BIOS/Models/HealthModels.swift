import SwiftUI

// View models for the dashboard blocks `health` (Gesundheits-Score, six ring
// pillars plus Labor in the background) and `vitals` (last temperature /
// blood pressure entered in the app).
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
    /// Parts of the pillar (`parts`, Kreislauf since 26.09., Routine since
    /// formula 3), empty when absent.
    let parts: [HealthPillarPart]
    /// Labor only (formula 3): score per lab group and the values below 100.
    let labGroups: [HealthLabGroup]
    let labFlagged: [HealthLabFlag]
    let labMarkerCount: Int?
    let labLastDate: Date?

    var id: String { key }

    /// Background pillar (Labor): grid and detail, no ring segment.
    var isBackground: Bool { HealthPillarPalette.isBackground(key, label: label) }

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
        parts = json.list("parts").compactMap { HealthPillarPart(json: $0) }
        labGroups = json.list("groups").compactMap { HealthLabGroup(json: $0) }
        labFlagged = json.list("flagged").enumerated().compactMap { HealthLabFlag(json: $0.element, index: $0.offset) }
        labMarkerCount = json.int("n_markers")
        labLastDate = BIOSDate.day(json.str("last_date"))
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
    /// Palette, order and key mapping live in Shared/HealthRing.swift
    /// (HealthPillarPalette), shared with the Live Activity.
    static func color(key: String, label: String, hex: String?) -> Color {
        if let hex, let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16), hex.count >= 6 {
            return Color(hex: value)
        }
        return HealthPillarPalette.color(key, label: label) ?? BIOSTheme.text2
    }

    /// Order of the grid and the detail: Schlaf, Erholung, Stoffwechsel,
    /// Kreislauf, Abwehr, Routine (the ring), then Labor (background).
    static var order: [String] { HealthPillarPalette.displayOrder }

    static func canonical(_ key: String, _ label: String) -> String {
        HealthPillarPalette.canonical(key, label: label)
    }

    static func defaultLabel(_ key: String) -> String {
        HealthPillarPalette.defaultLabel(key)
    }
}

struct HealthModel {
    let score: Double?
    let level: String?
    let deltaWeek: Double?
    let pillars: [HealthPillar]
    /// Pillars left out (no data), as text.
    let dropped: [String]
    /// The same without background pillars (Heute card: Labor missing is normal).
    let droppedRing: [String]
    /// `settings.strength_goal_per_week` (formula 3), nil when absent.
    let strengthGoal: Int?
    let headline: String?
    let subline: String?
    let generatedAt: Date?
    /// Formula 2 cap (`cap`, additive since 26.09.2026); nil when absent or not applied.
    let cap: HealthCap?
    /// Weakest-link deduction text (`penalty.reason`, "Abzug 6: Schlaf 24 unter 40").
    let penaltyReason: String?
    let formulaVersion: Int?

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
        // `dropped_info` ([{key, label, reason}]) wins over `dropped` (keys or objects).
        let info = json.list("dropped_info")
        let rawDropped = info.isEmpty ? json.list("dropped") : info
        let items: [(key: String, text: String)] = rawDropped.compactMap { (element: JSONValue) -> (key: String, text: String)? in
            if let key = element.stringValue {
                return (key, HealthPillar.defaultLabel(key))
            }
            let key = element.str("key") ?? element.str("label") ?? ""
            guard let label = element.str("label") ?? (key.isEmpty ? nil : HealthPillar.defaultLabel(key)) else {
                return nil
            }
            return (key, element.str("reason").map { "\(label) (\($0))" } ?? label)
        }
        dropped = items.map(\.text)
        droppedRing = items.filter { !HealthPillarPalette.isBackground($0.key) }.map(\.text)
        strengthGoal = json.obj("settings")?.int("strength_goal_per_week")
        headline = json.str("headline")
        subline = json.str("subline") ?? json.str("text")
        generatedAt = BIOSDate.parse(json.str("generated_at"))
        cap = json.obj("cap").flatMap { HealthCap(json: $0) }
        penaltyReason = json.obj("penalty")?.str("reason")
        formulaVersion = json.int("formula_version")
        if score == nil, pillars.isEmpty { return nil }
    }

    /// "Gedeckelt: Infektmuster Tag 4 · ohne Deckel 65" for the Heute card.
    var capLine: String? {
        guard let cap else { return nil }
        return [cap.reason, cap.uncappedText].compactMap { $0 }.joined(separator: " · ")
    }

    /// Detail: the cap reason unless the subline already says it.
    var capReasonForDetail: String? {
        guard let reason = cap?.reason else { return nil }
        if let second = secondText, second.localizedCaseInsensitiveContains(reason) { return nil }
        return reason
    }

    /// Level word ("gut") and its color: server word, else from the score
    /// with the server's thresholds (80 sehr gut, 65 gut, 50 mittel).
    var levelWord: String {
        if let level { return level }
        guard let score else { return "n. b." }
        if score >= 80 { return "sehr gut" }
        if score >= 65 { return "gut" }
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

    /// Heute card: ring pillars only (a missing Labor pillar is no gap).
    var freshnessText: String {
        droppedRing.isEmpty ? "Alle Daten aktuell" : "Ohne: " + droppedRing.joined(separator: ", ")
    }

    /// A background pillar (Labor) is in the list.
    var hasBackgroundPillar: Bool { pillars.contains { $0.isBackground } }

    /// Heute card headline.
    var cardHeadline: String {
        hasBackgroundPillar ? "Sechs Säulen plus Labor.\nEin Gesamtbild." : "Sechs Säulen.\nEin Gesamtbild."
    }
}

/// One part of a pillar (`pillars[].parts`): Kreislauf `ruhepuls_niveau`,
/// `aktivitaet`, `blutdruck`; Routine `krafttraining`, `einnahmen`. Unknown
/// parts render generically (label, score, reason).
struct HealthPillarPart: Identifiable {
    let key: String
    let label: String
    /// nil = part missing (`reason` says why).
    let score: Double?
    let weight: Double?
    /// Share in % after renormalizing.
    let weightUsed: Double?
    let reason: String?
    /// `krafttraining`: strength days in the window and the weekly goal.
    let sessions: Int?
    let goal: Int?
    let windowDays: Int?

    var id: String { key }

    init?(json: JSONValue) {
        guard let key = json.str("key") ?? json.str("label") else { return nil }
        self.key = key
        label = json.str("label") ?? HealthPillarPart.defaultLabel(key)
        score = json.double("score").map { Swift.max(0, Swift.min(100, $0)) }
        weight = json.double("weight")
        weightUsed = json.double("weight_used")
        reason = json.str("reason")
        sessions = json.int("sessions")
        goal = json.int("goal")
        windowDays = json.int("window_days")
    }

    static func defaultLabel(_ key: String) -> String {
        switch key {
        case "krafttraining": return "Krafttraining"
        case "einnahmen": return "Einnahmen"
        case "ruhepuls_niveau": return "Ruhepuls-Niveau"
        case "aktivitaet": return "Aktivität"
        case "blutdruck": return "Blutdruck"
        default: return key
        }
    }

    /// "Anteil 40 %"
    var shareText: String? {
        (weightUsed ?? weight).map { "Anteil \(BIOSFormat.number($0)) %" }
    }

    /// Strength progress (sessions of goal) when both are known and the goal is on.
    var progress: (done: Int, total: Int)? {
        guard let sessions, let goal, goal > 0 else { return nil }
        return (Swift.min(sessions, goal), goal)
    }

    var accessibilityText: String {
        var parts = [label]
        parts.append(score.map { "\(BIOSFormat.number($0)) von 100" } ?? "keine Wertung")
        if let reason { parts.append(reason) }
        if let shareText { parts.append(shareText) }
        return parts.joined(separator: ", ")
    }
}

/// `labor.groups[]`: score per lab group.
struct HealthLabGroup: Identifiable {
    let key: String
    let label: String
    let score: Double?
    let weightUsed: Double?
    let markerCount: Int?

    var id: String { key }

    init?(json: JSONValue) {
        guard let key = json.str("key") ?? json.str("id") ?? json.str("label") else { return nil }
        self.key = key
        label = json.str("label") ?? key
        score = json.double("score").map { Swift.max(0, Swift.min(100, $0)) }
        weightUsed = json.double("weight_used")
        markerCount = json.int("n_markers")
    }

    /// "3 Werte"
    var countText: String? {
        markerCount.map { $0 == 1 ? "1 Wert" : "\($0) Werte" }
    }
}

/// `labor.flagged[]`: a lab value below 100 points (worst first).
struct HealthLabFlag: Identifiable {
    let id: String
    /// Catalog marker id (opens the marker detail in the Labor tab).
    let marker: String?
    let name: String
    let group: String?
    /// "hoch", "niedrig", "auffällig", "über Ziel", "unter Ziel".
    let status: String?
    let date: Date?
    let value: Double?
    let valueText: String?
    let unit: String?
    let score: Double?

    init?(json: JSONValue, index: Int) {
        let marker = json.str("marker")
        guard let name = json.str("name") ?? marker else { return nil }
        self.marker = marker
        self.name = name
        id = (marker ?? name) + "-\(index)"
        group = json.str("group")
        status = json.str("status")
        date = BIOSDate.day(json.str("date"))
        value = json.double("value")
        valueText = json.str("value")
        unit = json.str("unit")
        score = json.double("score").map { Swift.max(0, Swift.min(100, $0)) }
    }

    /// "7,4 %" (decimals as the server sent them, max 2).
    var valueLine: String? {
        let number: String?
        if let value {
            let digits = value == value.rounded() ? 0 : (abs(value * 10 - (value * 10).rounded()) < 0.0001 ? 1 : 2)
            number = BIOSFormat.number(value, digits: digits)
        } else {
            number = valueText
        }
        guard let number else { return nil }
        return unit.map { "\(number) \($0)" } ?? number
    }

    /// "hoch · 01.09."
    var metaLine: String {
        [status, date.map { BIOSFormat.shortDate($0) }].compactMap { $0 }.joined(separator: " · ")
    }
}

/// `health.cap` when it lowered the score (`applied`). Lenient: without
/// `applied: true` there is nothing to show.
struct HealthCap {
    /// "Gedeckelt: Infektmuster Tag 4" (server text, else built from `cause`/`max`).
    let reason: String?
    /// Score before the cap.
    let uncapped: Double?
    let max: Double?
    let kind: String?

    init?(json: JSONValue) {
        guard json.flag("applied") else { return nil }
        uncapped = json.double("uncapped").map { Swift.max(0, Swift.min(100, $0)) }
        max = json.double("max")
        kind = json.str("kind")
        if let reason = json.str("reason") {
            self.reason = reason
        } else if let cause = json.str("cause") {
            self.reason = "Gedeckelt: \(cause)"
        } else if let max {
            self.reason = "Gedeckelt auf \(BIOSFormat.number(max))"
        } else {
            self.reason = "Gedeckelt"
        }
    }

    /// "ohne Deckel 65"
    var uncappedText: String? {
        uncapped.map { "ohne Deckel \(BIOSFormat.number($0))" }
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
