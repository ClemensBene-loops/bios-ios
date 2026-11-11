import SwiftUI

// View models for the dashboard blocks `health` (Gesundheits-Score) and
// `vitals` (last temperature / blood pressure entered in the app).
// Formula 4 servers send `ring` (six segments Schlaf, Erholung, Zucker,
// Bewegung, Routine (key `therapie`), Labor, `HealthSegment`); old servers only `pillars`
// (six legacy ring pillars plus Labor in the background, `HealthPillar`).
// Lenient like the rest: a missing block hides its card.

/// "up"/"down"/"flat" (or a number) -> 1 / -1 / 0; nil when unknown or
/// `trend_known: false`.
enum HealthTrend {
    static func parse(_ json: JSONValue) -> Int? {
        if json["trend_known"]?.boolValue == false { return nil }
        if let number = json.double("trend") {
            return number > 0.5 ? 1 : (number < -0.5 ? -1 : 0)
        }
        switch (json.str("trend") ?? "").lowercased() {
        case "up", "steigend", "rising", "besser": return 1
        case "down", "fallend", "falling", "schlechter": return -1
        case "flat", "stabil", "gleich", "same": return 0
        default: return nil
        }
    }

    static func symbol(_ trend: Int?) -> String? {
        switch trend {
        case 1: return "arrow.up.right"
        case -1: return "arrow.down.right"
        case 0: return "arrow.right"
        default: return nil
        }
    }

    static func word(_ trend: Int?) -> String {
        switch trend {
        case 1: return "steigend"
        case -1: return "fallend"
        case 0: return "stabil"
        default: return "ohne Trend"
        }
    }

    /// Server hex color ("#5B6CFF"), nil when absent or malformed.
    static func color(hex: String?) -> Color? {
        guard let hex else { return nil }
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return Color(hex: value)
    }
}

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

    /// Formula 3 background pillar (Labor, old servers): grid and detail, no ring segment.
    var isBackground: Bool { HealthPillarPalette.isLegacyBackground(key, label: label) }

    init?(json: JSONValue) {
        guard let key = json.str("key") ?? json.str("id") else { return nil }
        self.key = key
        label = json.str("label") ?? HealthPillar.defaultLabel(key)
        score = json.double("score") ?? json.double("value")
        weight = json.double("weight")
        trend = HealthTrend.parse(json)
        reason = json.str("reason") ?? json.str("text")
        color = HealthPillar.color(key: key, label: label, hex: json.str("color"))
        parts = json.list("parts").compactMap { HealthPillarPart(json: $0) }
        labGroups = json.list("groups").compactMap { HealthLabGroup(json: $0) }
        labFlagged = json.list("flagged").enumerated().compactMap { HealthLabFlag(json: $0.element, index: $0.offset) }
        labMarkerCount = json.int("n_markers")
        labLastDate = BIOSDate.day(json.str("last_date"))
    }

    var trendSymbol: String? { HealthTrend.symbol(trend) }

    var trendWord: String { HealthTrend.word(trend) }

    /// Server `color` wins when it is a hex value, else the legacy palette
    /// (old servers), else the formula 4 palette. Palette, order and key
    /// mapping live in Shared/HealthRing.swift (HealthPillarPalette), shared
    /// with the Live Activity.
    static func color(key: String, label: String, hex: String?) -> Color {
        if let color = HealthTrend.color(hex: hex) { return color }
        let canonicalKey = HealthPillarPalette.canonical(key, label: label)
        let legacy = (HealthPillarPalette.legacyPillars + HealthPillarPalette.legacyBackground)
            .first { $0.key == canonicalKey }
        return legacy?.color ?? HealthPillarPalette.color(key, label: label) ?? BIOSTheme.text2
    }

    /// Order of the legacy grid and detail: Schlaf, Erholung, Stoffwechsel,
    /// Kreislauf, Abwehr, Routine (the old ring), then Labor (background).
    static var order: [String] { HealthPillarPalette.legacyDisplayOrder }

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
    /// Formula 4 ring (`ring`, six segments in server order); empty on old
    /// servers, which keep the legacy pillar display.
    let ring: [HealthSegment]
    /// Pillars left out (no data), as text.
    let dropped: [String]
    /// The same without background pillars (Heute card: Labor missing is normal).
    let droppedRing: [String]
    /// `settings.strength_goal_per_week` (formula 3), nil when absent.
    let strengthGoal: Int?
    let headline: String?
    let subline: String?
    let generatedAt: Date?
    /// Cap (`cap`, additive since 26.09.2026); nil when absent or not applied.
    let cap: HealthCap?
    /// Weakest-link deduction text (`penalty.reason`, "Abzug 4: Erholung 15 unter 25").
    let penaltyReason: String?
    let formulaVersion: Int?
    /// Formula 4: chips below the score (`abzug`, `stand`, `alkohol`), the
    /// penalty reason added as `abzug` when the server did not send one.
    let chips: [HealthChip]
    /// Formula 4 level thresholds (`levels`), highest first.
    let levels: [HealthLevel]
    /// Formula 4: today is a partial day.
    let partial: Bool
    /// Formula 4: why there is no total ("Keine Whoop-Nacht, kein Gesamtwert.").
    let scoreReason: String?

    init?(json: JSONValue?) {
        guard let json, json.objectValue != nil else { return nil }
        score = (json.double("score") ?? json.double("value")).map { Swift.max(0, Swift.min(100, $0)) }
        level = json.str("level") ?? json.str("level_text")
        deltaWeek = json.double("delta_week") ?? json.double("delta")
        let rawPillars = json.list("pillars")
        let parsed = rawPillars.compactMap { HealthPillar(json: $0) }
        pillars = parsed.sorted { lhs, rhs in
            let left = HealthPillar.order.firstIndex(of: HealthPillar.canonical(lhs.key, lhs.label)) ?? 99
            let right = HealthPillar.order.firstIndex(of: HealthPillar.canonical(rhs.key, rhs.label)) ?? 99
            return left < right
        }
        // Formula 4 pillars carry the segment extras (parts, Labor groups,
        // HbA1c, ...) under the legacy key; `segment` names the ring key.
        var extras: [String: JSONValue] = [:]
        for raw in rawPillars {
            guard let key = raw.str("key") ?? raw.str("id") else { continue }
            if let segment = raw.str("segment") ?? HealthPillarPalette.segmentKey(key, label: raw.str("label")),
               extras[segment] == nil {
                extras[segment] = raw
            }
        }
        ring = json.list("ring").compactMap { (entry: JSONValue) -> HealthSegment? in
            guard let key = entry.str("key") else { return nil }
            return HealthSegment(json: entry, extra: extras[HealthPillarPalette.canonical(key, label: entry.str("label"))])
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
        droppedRing = items.filter { !HealthPillarPalette.isLegacyBackground($0.key) }.map(\.text)
        strengthGoal = json.obj("settings")?.int("strength_goal_per_week")
        headline = json.str("headline")
        subline = json.str("subline") ?? json.str("text")
        generatedAt = BIOSDate.parse(json.str("generated_at"))
        cap = json.obj("cap").flatMap { HealthCap(json: $0) }
        let penalty = json.obj("penalty")?.str("reason")
        penaltyReason = penalty
        formulaVersion = json.int("formula_version")
        var chips = json.list("chips").enumerated().compactMap { HealthChip(json: $0.element, index: $0.offset) }
        if let penalty, !json.list("ring").isEmpty, !chips.contains(where: { $0.kind == "abzug" }) {
            chips.insert(HealthChip(kind: "abzug", text: penalty, index: -1), at: 0)
        }
        self.chips = chips
        levels = json.list("levels").compactMap { HealthLevel(json: $0) }.sorted { $0.min > $1.min }
        partial = json.flag("partial")
        scoreReason = json.str("score_reason")
        if score == nil, pillars.isEmpty, ring.isEmpty { return nil }
    }

    /// Formula 4 display (the server sends `ring`).
    var usesRing: Bool { !ring.isEmpty }

    /// "Gedeckelt: Infektmuster Tag 4 · ohne Deckel 65" for the Heute card
    /// (formula 4: `cap.text`, "Gedeckelt auf 49: Infektmuster Tag 4 (ohne Deckel 56).").
    var capLine: String? {
        guard let cap else { return nil }
        if let text = cap.text { return text }
        return [cap.reason, cap.uncappedText].compactMap { $0 }.joined(separator: " · ")
    }

    /// Formula 4: when the cap goes away (`cap.lift`), only while it applies.
    var capLift: String? { cap?.lift }

    /// Detail: the cap reason unless the subline already says it.
    var capReasonForDetail: String? {
        guard let reason = cap?.reason else { return nil }
        if let second = secondText, second.localizedCaseInsensitiveContains(reason) { return nil }
        return reason
    }

    /// Formula 4 detail: `cap.text` unless the subline already is that text.
    var capTextForDetail: String? {
        guard let text = capLine else { return nil }
        if let second = secondText, second.localizedCaseInsensitiveContains(text) { return nil }
        return text
    }

    /// Level word ("gut") and its color: server word, else from the score
    /// with the server's thresholds (`levels`; formula 4 85/70/50, before
    /// 80/65/50).
    var levelWord: String {
        if let level { return level }
        guard let score else { return "n. b." }
        if !levels.isEmpty {
            return levels.first(where: { score >= $0.min })?.label ?? levels[levels.count - 1].label
        }
        let formula4 = (formulaVersion ?? 0) >= 4 || usesRing
        if score >= (formula4 ? 85 : 80) { return "sehr gut" }
        if score >= (formula4 ? 70 : 65) { return "gut" }
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

    /// "Stufen: ab 85 sehr gut, ab 70 gut, ab 50 mittel, darunter niedrig."
    var levelsText: String? {
        guard !levels.isEmpty else { return nil }
        let steps = levels.filter { $0.min > 0 }.map { "ab \(BIOSFormat.number($0.min)) \($0.label)" }
        guard !steps.isEmpty else { return nil }
        var text = "Stufen: " + steps.joined(separator: ", ")
        if let lowest = levels.last, lowest.min <= 0 { text += ", darunter \(lowest.label)" }
        return text + "."
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
        if score == nil, scoreReason != nil { return "Kein Gesamtwert." }
        switch levelWord.lowercased() {
        case "sehr gut", "gut": return "Ausgewogen."
        case "mittel": return "Gemischt."
        default: return "Unter deinem Schnitt."
        }
    }

    var secondText: String? {
        if let subline { return subline }
        if usesRing {
            let candidates = ring.filter { $0.fill != nil && $0.key != "labor" }
            guard let weakest = candidates.min(by: { ($0.fill ?? 0) < ($1.fill ?? 0) }) else { return scoreReason }
            return (weakest.fill ?? 0) < 75 ? "Mit Luft für \(weakest.label)." : "Alles im grünen Bereich."
        }
        guard let weakest = pillars.filter({ $0.score != nil }).min(by: { ($0.score ?? 0) < ($1.score ?? 0) }) else {
            return nil
        }
        return "Mit Luft für \(weakest.label)."
    }

    /// Formula 4: segments without a value ("Bewegung (Pause wegen Infekt)").
    var segmentsWithoutValue: [String] {
        ring.filter { $0.fill == nil }.map { segment in
            segment.statusText.map { "\(segment.label) (\($0))" } ?? segment.label
        }
    }

    /// Heute card: ring pillars only (a missing legacy Labor pillar is no gap).
    var freshnessText: String {
        if usesRing {
            let missing = segmentsWithoutValue
            return missing.isEmpty ? "Alle Daten aktuell" : "Ohne Wert: " + missing.joined(separator: ", ")
        }
        return droppedRing.isEmpty ? "Alle Daten aktuell" : "Ohne: " + droppedRing.joined(separator: ", ")
    }

    /// A legacy background pillar (Labor, formula 3) is in the list.
    var hasBackgroundPillar: Bool { !usesRing && pillars.contains { $0.isBackground } }

    /// Heute card headline.
    var cardHeadline: String { "Sechs Bereiche.\nEin Gesamtbild." }

    /// VoiceOver: "Gesundheits-Score 49 von 100, niedrig, gedeckelt".
    var scoreAccessibilityText: String {
        guard let score else {
            return "Gesundheits-Score ohne Gesamtwert" + (scoreReason.map { ". \($0)" } ?? "")
        }
        var text = "Gesundheits-Score \(BIOSFormat.number(score)) von 100, \(levelWord)"
        if cap != nil { text += ", gedeckelt" }
        return text
    }
}

/// One formula 4 ring segment (`health.ring[]`), with the extras of the
/// matching pillar (`pillars[]` with `segment` = key): parts, Labor groups
/// and flagged values, HbA1c, strength sessions.
struct HealthSegment: Identifiable {
    enum Status: String {
        case ok
        case keineDaten = "keine_daten"
        case pause
        case nichtErfasst = "nicht_erfasst"
        case verblasst
    }

    let key: String
    let label: String
    /// Arc length = nominal weight (20, 20, 25, 15, 10, 10).
    let arc: Double
    /// 0...100, nil = no value (`status` says why).
    let fill: Double?
    let status: Status
    /// Share of the total in % after renormalizing (0 without value).
    let weightUsed: Double?
    let reason: String?
    let color: Color
    /// -1 / 0 / 1, nil when unknown.
    let trend: Int?
    let deltaWeek: Double?
    /// Labor only: newest finding, "Stand 01.09.", weight factor 0...1, hints.
    let stand: Date?
    let standLabel: String?
    let weightFactor: Double?
    let hints: [String]
    // Extras from the matching pillar.
    let parts: [HealthPillarPart]
    let labGroups: [HealthLabGroup]
    let labFlagged: [HealthLabFlag]
    let labMarkerCount: Int?
    let hba1c: HealthHbA1c?
    /// Bewegung: strength days in 14 days and the goal (shrunk by sick days).
    let sessions: Int?
    let sessionGoal: Double?

    var id: String { key }

    init?(json: JSONValue, extra: JSONValue?) {
        guard let rawKey = json.str("key") else { return nil }
        let key = HealthPillarPalette.canonical(rawKey, label: json.str("label"))
        self.key = key
        label = json.str("label") ?? HealthPillarPalette.defaultLabel(key)
        arc = json.double("arc") ?? HealthPillarPalette.pillars.first(where: { $0.key == key })?.arc ?? 10
        fill = json.double("fill").map { Swift.max(0, Swift.min(100, $0)) }
        let raw = Status(rawValue: (json.str("status") ?? "").lowercased())
        if let raw, !(raw == .ok && fill == nil) {
            status = raw
        } else {
            status = fill == nil ? .keineDaten : .ok
        }
        weightUsed = json.double("weight_used")
        reason = json.str("reason") ?? extra?.str("reason")
        color = HealthTrend.color(hex: json.str("color"))
            ?? HealthPillarPalette.pillars.first(where: { $0.key == key })?.color
            ?? BIOSTheme.text2
        trend = HealthTrend.parse(json)
        deltaWeek = json.double("delta_week")
        stand = BIOSDate.day(json.str("stand"))
        standLabel = json.str("stand_label") ?? BIOSDate.day(json.str("stand")).map { "Stand \(BIOSFormat.shortDate($0))" }
        weightFactor = json.double("weight_factor")
        let ownHints = json.strings("hints")
        hints = ownHints.isEmpty ? (extra?.strings("hints") ?? []) : ownHints
        parts = (extra?.list("parts") ?? []).compactMap { HealthPillarPart(json: $0) }
        labGroups = (extra?.list("groups") ?? []).compactMap { HealthLabGroup(json: $0) }
        labFlagged = (extra?.list("flagged") ?? []).enumerated().compactMap { HealthLabFlag(json: $0.element, index: $0.offset) }
        labMarkerCount = extra?.int("n_markers")
        hba1c = extra?.obj("hba1c").flatMap { HealthHbA1c(json: $0) }
        sessions = extra?.int("sessions_14d")
        sessionGoal = extra?.double("goal")
    }

    var isLabor: Bool { key == "labor" }

    /// How the ring draws the segment.
    var ringStyle: HealthRingSlotStyle {
        switch status {
        case .ok: return fill == nil ? .missing : .normal
        case .keineDaten: return .missing
        case .pause, .nichtErfasst: return .inactive
        case .verblasst: return fill == nil ? .missing : .faded
        }
    }

    /// Dot and bar color: grey for inactive and missing segments, paler when faded.
    var displayColor: Color {
        switch ringStyle {
        case .normal: return color
        case .faded: return color.opacity(0.5)
        case .missing, .inactive: return BIOSTheme.text3
        }
    }

    /// Status in words, nil for `ok`.
    var statusText: String? {
        switch status {
        case .ok: return nil
        case .keineDaten: return "keine Daten"
        case .pause: return "Pause wegen Infekt"
        case .nichtErfasst: return "nicht erfasst"
        case .verblasst: return standLabel.map { "verblasst, \($0)" } ?? "verblasst"
        }
    }

    /// Grid value: number, else a short status.
    var shortValue: String {
        if let fill { return BIOSFormat.number(fill) }
        switch status {
        case .pause: return "Pause"
        case .nichtErfasst: return "nicht erfasst"
        default: return "keine Daten"
        }
    }

    var trendSymbol: String? { HealthTrend.symbol(trend) }

    var trendWord: String { HealthTrend.word(trend) }

    /// "Anteil 20 % · −6 zur Vorwoche · zählt zu 60 %"
    var metaLine: String? {
        var parts: [String] = []
        if let weightUsed, fill != nil { parts.append("Anteil \(BIOSFormat.number(weightUsed)) %") }
        if let deltaWeek, trend != nil {
            parts.append(deltaWeek.rounded() == 0 ? "wie Vorwoche" : "\(BIOSFormat.signed(deltaWeek.rounded())) zur Vorwoche")
        }
        if isLabor, let weightFactor, weightFactor < 1 {
            parts.append("Gewicht \(BIOSFormat.number(weightFactor * 100)) %")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Bewegung: strength days of the goal as segments (goal rounded up).
    var sessionProgress: (done: Int, total: Int)? {
        guard let sessions, let sessionGoal, sessionGoal > 0 else { return nil }
        let total = Int(sessionGoal.rounded(.up))
        return (Swift.min(sessions, total), total)
    }

    /// VoiceOver for the grid cell and the detail row.
    var accessibilityText: String {
        var parts = [label]
        if let fill {
            parts.append("\(BIOSFormat.number(fill)) von 100")
            if trend != nil { parts.append(trendWord) }
        }
        if let statusText { parts.append(statusText) }
        if isLabor, status != .verblasst, let standLabel { parts.append(standLabel) }
        return parts.joined(separator: ", ")
    }
}

/// Labor segment: the HbA1c behind the points (`pillars[labor].hba1c`).
struct HealthHbA1c {
    let value: Double?
    let estimated: Bool
    let points: Double?
    let band: [Double]
    let max: Double?
    let date: Date?
    let dateCount: Int?

    init?(json: JSONValue) {
        value = json.double("value")
        estimated = json.flag("estimated")
        points = json.double("points")
        band = json.optionalNumbers("band").compactMap { $0 }
        max = json.double("max")
        date = BIOSDate.day(json.str("date"))
        dateCount = json.int("n_dates")
        if value == nil, points == nil { return nil }
    }

    /// "HbA1c 7,0 %" / "HbA1c 7,2 % (geschätzt)"
    var valueLine: String {
        var text = "HbA1c " + (value.map { BIOSFormat.number($0, digits: 1) + " %" } ?? "n. v.")
        if estimated { text += " (geschätzt)" }
        return text
    }

    /// "Ziel unter 7 %, bestmöglich 6,0 bis 6,5 %"
    var goalText: String? {
        guard let max else { return nil }
        let maxText = BIOSFormat.number(max, digits: max == max.rounded() ? 0 : 1)
        var text = "Ziel unter \(maxText) %"
        if band.count == 2 {
            text += ", bestmöglich \(BIOSFormat.number(band[0], digits: 1)) bis \(BIOSFormat.number(band[1], digits: 1)) %"
        }
        return text
    }

    /// "vom 01.09., Mittel aus 2 Messungen"
    var metaLine: String? {
        var parts: [String] = []
        if let date { parts.append("vom \(BIOSFormat.shortDate(date))") }
        if let dateCount, dateCount > 1 { parts.append("Mittel aus \(dateCount) Messungen") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Formula 4 chip below the score (`chips[]`).
struct HealthChip: Identifiable {
    let id: String
    /// `abzug`, `stand`, `alkohol` (unknown kinds render plainly).
    let kind: String
    let text: String

    init(kind: String, text: String, index: Int) {
        self.kind = kind
        self.text = text
        id = "\(kind)-\(index)"
    }

    init?(json: JSONValue, index: Int) {
        guard let text = json.str("text") else { return nil }
        self.init(kind: json.str("kind") ?? "", text: text, index: index)
    }

    var symbol: String {
        switch kind {
        case "abzug": return "minus.circle"
        case "stand": return "clock"
        case "alkohol": return "wineglass"
        default: return "info.circle"
        }
    }
}

/// Formula 4 level threshold (`levels[]`): `min` and word.
struct HealthLevel {
    let min: Double
    let label: String

    init?(json: JSONValue) {
        guard let min = json.double("min"), let label = json.str("label") else { return nil }
        self.min = min
        self.label = label
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
    /// Formula 4: "Gedeckelt auf 49: Infektmuster Tag 4 (ohne Deckel 56)."
    let text: String?
    /// Formula 4: when the cap goes away by itself.
    let lift: String?

    init?(json: JSONValue) {
        guard json.flag("applied") else { return nil }
        uncapped = json.double("uncapped").map { Swift.max(0, Swift.min(100, $0)) }
        max = json.double("max")
        kind = json.str("kind")
        text = json.str("text")
        lift = json.str("lift")
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
