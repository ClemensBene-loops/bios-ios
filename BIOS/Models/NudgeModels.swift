import Foundation

// Bewegungs-Stupser (`GET /v1/nudge`, `PATCH /v1/nudge/settings`). Lenient like
// every other model: each field is optional, unknown fields are ignored, wrong
// types fall back to defaults, so a newer server never breaks the section.

/// Settings of the nudges (server profile, changed via PATCH).
struct NudgeSettings: Equatable {
    var enabled: Bool
    /// "freundlich" or "frech".
    var tone: String
    /// Time window "HH:MM".
    var start: String
    var end: String
    var maxPerDay: Int
    /// Safety margin `guard` ("streng", "mittel", "locker"); nil while the server
    /// does not send it (older server).
    var safety: String?

    static let standard = NudgeSettings(enabled: false, tone: "freundlich", start: "08:00", end: "20:00", maxPerDay: 2)

    init(enabled: Bool, tone: String, start: String, end: String, maxPerDay: Int, safety: String? = nil) {
        self.enabled = enabled
        self.tone = tone
        self.start = start
        self.end = end
        self.maxPerDay = maxPerDay
        self.safety = safety
    }

    init(json: JSONValue?) {
        let fallback = Self.standard
        enabled = json?.flag("enabled", fallback: fallback.enabled) ?? fallback.enabled
        tone = json?.str("tone")?.lowercased() ?? fallback.tone
        let hours = json?.obj("hours")
        start = NudgeClock.valid(hours?.str("start")) ?? fallback.start
        end = NudgeClock.valid(hours?.str("end")) ?? fallback.end
        maxPerDay = json?.int("max_per_day") ?? fallback.maxPerDay
        safety = json?.str("guard")?.lowercased()
    }
}

/// One level of the safety margin (`options` of `GET /v1/nudge`).
struct NudgeGuardOption: Identifiable, Equatable {
    let id: String
    let label: String
    let description: String?

    /// Title for an id without server label ("streng" -> "Streng").
    static func title(_ id: String) -> String {
        id.prefix(1).uppercased() + id.dropFirst()
    }

    /// Reads the guard levels from `options`, whatever shape the server picks:
    /// key `guards`, `guard`, `guard_levels` or `guard_options`; a list of ids,
    /// a list of objects (`id`/`value`, `label`/`title`, `description`/`text`),
    /// an object id -> description or id -> {label, description}, or an object
    /// with such a list under `values`/`options`/`levels`. Separate texts under
    /// `guard_descriptions`/`guards_descriptions` are merged in. Empty = the
    /// server has no safety margin yet (the picker stays hidden).
    static func parse(options json: JSONValue?) -> [NudgeGuardOption] {
        guard let json else { return [] }
        var extra: [String: String] = [:]
        for key in ["guard_descriptions", "guards_descriptions", "guard_texts"] {
            for (id, value) in json[key]?.objectValue ?? [:] {
                if let text = value.stringValue { extra[id.lowercased()] = text }
            }
        }
        for key in ["guards", "guard", "guard_levels", "guard_options"] {
            guard let raw = json[key] else { continue }
            let parsed = parse(raw, extra: extra)
            if !parsed.isEmpty { return parsed }
        }
        return []
    }

    private static let order = ["streng", "mittel", "locker"]

    private static func parse(_ raw: JSONValue, extra: [String: String]) -> [NudgeGuardOption] {
        if case .array(let items) = raw {
            var seen = Set<String>()
            return items.compactMap { item -> NudgeGuardOption? in
                let option: NudgeGuardOption?
                if let id = item.stringValue?.lowercased(), !id.isEmpty {
                    option = NudgeGuardOption(id: id, label: title(id), description: extra[id])
                } else if item.objectValue != nil,
                          let id = (item.str("id") ?? item.str("value") ?? item.str("key") ?? item.str("name"))?.lowercased() {
                    option = NudgeGuardOption(
                        id: id,
                        label: item.str("label") ?? item.str("title") ?? title(id),
                        description: item.str("description") ?? item.str("text") ?? item.str("detail")
                            ?? item.str("hint") ?? extra[id]
                    )
                } else {
                    option = nil
                }
                guard let option, seen.insert(option.id).inserted else { return nil }
                return option
            }
        }
        guard let object = raw.objectValue else { return [] }
        for key in ["values", "options", "levels", "choices"] {
            if let nested = object[key], case .array = nested {
                return parse(nested, extra: extra)
            }
        }
        let meta: Set<String> = ["default", "label", "title", "description", "text"]
        let options = object.compactMap { entry -> NudgeGuardOption? in
            let id = entry.key.lowercased()
            if meta.contains(id) { return nil }
            if let text = entry.value.stringValue {
                return NudgeGuardOption(id: id, label: title(id), description: text)
            }
            guard entry.value.objectValue != nil else { return nil }
            return NudgeGuardOption(
                id: id,
                label: entry.value.str("label") ?? entry.value.str("title") ?? title(id),
                description: entry.value.str("description") ?? entry.value.str("text") ?? extra[id]
            )
        }
        // An object has no order: known levels first, the rest by name.
        return options.sorted { lhs, rhs in
            let left = order.firstIndex(of: lhs.id) ?? order.count
            let right = order.firstIndex(of: rhs.id) ?? order.count
            return left == right ? lhs.id < rhs.id : left < right
        }
    }
}

/// "HH:MM" helpers for the time window pickers.
enum NudgeClock {
    /// "8:00" -> nil, "08:00" -> "08:00" (only well formed values).
    static func valid(_ raw: String?) -> String? {
        guard let raw, minutes(raw) != nil else { return nil }
        return raw
    }

    static func minutes(_ raw: String) -> Int? {
        let parts = raw.split(separator: ":")
        guard raw.count == 5, parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...24).contains(hour), (0..<60).contains(minute) else {
            return nil
        }
        return hour * 60 + minute
    }

    static func string(_ minutes: Int) -> String {
        "\(BIOSFormat.twoDigits(minutes / 60)):\(BIOSFormat.twoDigits(minutes % 60))"
    }

    /// Half-hour steps from `lower` to `upper`, plus `extra` values not on the grid.
    static func options(lower: String, upper: String, including extra: [String]) -> [String] {
        let low = minutes(lower) ?? 7 * 60
        let high = minutes(upper) ?? 21 * 60
        var values = Set<String>()
        if low <= high {
            for value in stride(from: low, through: high, by: 30) {
                values.insert(string(value))
            }
        }
        for value in extra where minutes(value) != nil {
            values.insert(value)
        }
        return values.sorted()
    }
}

/// `today`: budget of the local day.
struct NudgeToday: Equatable {
    let date: String?
    let sent: Int
    let maxPerDay: Int?
    let remaining: Int?
    let offToday: Bool
    let lastSentAt: Date?
    let cooldownUntil: Date?

    init(json: JSONValue) {
        date = json.str("date")
        sent = json.int("sent") ?? 0
        maxPerDay = json.int("max_per_day")
        remaining = json.int("remaining")
        offToday = json.flag("off_today")
        lastSentAt = BIOSDate.parse(json.str("last_sent_at"))
        cooldownUntil = BIOSDate.parse(json.str("cooldown_until"))
    }
}

/// `last_check`: the newest cron run with a decision (only while enabled).
struct NudgeCheck: Equatable {
    let at: Date?
    let send: Bool
    let kind: String?
    let reason: String?
    let status: String?

    init(json: JSONValue) {
        at = BIOSDate.parse(json.str("at"))
        send = json.flag("send")
        kind = json.str("kind")
        reason = json.str("reason")
        status = json.str("status")
    }
}

/// One sent nudge with its outcome (`g30`/`g60` are filled in later).
struct NudgeEntry: Identifiable, Equatable {
    let id: String
    let kind: String?
    let label: String?
    let sentAt: Date?
    let title: String?
    let body: String?
    let followupOf: String?
    let glucose: Double?
    let g30: Double?
    let g60: Double?
    let delta30: Double?
    let delta60: Double?
    let action: String?
    let actionAt: Date?

    init?(json: JSONValue, index: Int) {
        guard json.objectValue != nil else { return nil }
        id = json.str("id") ?? "nudge-\(index)"
        kind = json.str("kind")
        label = json.str("label")
        sentAt = BIOSDate.parse(json.str("sent_at"))
        title = json.str("title")
        body = json.str("body")
        followupOf = json.str("followup_of")
        glucose = json.double("glucose")
        g30 = json.double("g30")
        g60 = json.double("g60")
        delta30 = json.double("delta30") ?? Self.difference(g30, glucose)
        delta60 = json.double("delta60") ?? Self.difference(g60, glucose)
        action = json.str("action")
        actionAt = BIOSDate.parse(json.str("action_at"))
    }

    private static func difference(_ later: Double?, _ start: Double?) -> Double? {
        guard let later, let start else { return nil }
        return later - start
    }

    /// "Spitze abfangen", "Insulin wirkt zäh" (server label, else from `kind`).
    var displayLabel: String {
        if let label { return label }
        switch kind ?? "" {
        case "spitze": return "Spitze abfangen"
        case "zaeh": return "Insulin wirkt zäh"
        default: return "Stupser"
        }
    }

    /// "Erledigt", "Später", "Heute nicht", "keine Antwort".
    var actionText: String {
        switch action ?? "" {
        case "done": return "Erledigt"
        case "snooze": return "Später"
        case "off_today": return "Heute nicht"
        case "": return "keine Antwort"
        default: return action ?? "keine Antwort"
        }
    }

    /// "205 mg/dL, nach 30 min −16, nach 60 min −35" (missing outcomes: "wird nachgetragen").
    var effectText: String {
        var parts: [String] = []
        if let glucose { parts.append("\(BIOSFormat.number(glucose)) mg/dL") }
        if let delta30 {
            parts.append("nach 30 min \(BIOSFormat.signed(delta30))")
        }
        if let delta60 {
            parts.append("nach 60 min \(BIOSFormat.signed(delta60))")
        }
        if delta30 == nil && delta60 == nil {
            parts.append("Wirkung wird nachgetragen")
        }
        return parts.joined(separator: ", ")
    }
}

/// `week`: descriptive 7-day summary.
struct NudgeWeek: Equatable {
    let count: Int?
    let text: String?
    let delta30Mean: Double?
    let n30: Int?
    let delta60Mean: Double?
    let n60: Int?

    init(json: JSONValue) {
        count = json.int("count")
        text = json.str("text")
        delta30Mean = json.double("delta30_mean")
        n30 = json.int("n30")
        delta60Mean = json.double("delta60_mean")
        n60 = json.int("n60")
    }

    /// Server text, else a short line from the numbers, nil without anything.
    var displayText: String? {
        if let text { return text }
        guard let count else { return nil }
        var line = count == 1 ? "1 Stupser in 7 Tagen." : "\(count) Stupser in 7 Tagen."
        if let mean = delta30Mean, let n = n30, n > 0 {
            line += " Nach dem Stupser im Schnitt \(BIOSFormat.signed(mean)) mg/dL in 30 min (n = \(n))."
        }
        return line
    }
}

/// `options`: allowed values for the settings controls.
struct NudgeOptions: Equatable {
    let tones: [String]
    let hoursLower: String
    let hoursUpper: String
    let maxRange: ClosedRange<Int>
    /// Levels of the safety margin; empty on a server without `guard`.
    let guards: [NudgeGuardOption]

    init(json: JSONValue?) {
        guards = NudgeGuardOption.parse(options: json)
        let tones = json?.strings("tones") ?? []
        self.tones = tones.isEmpty ? ["freundlich", "frech"] : tones
        let bounds = json?.strings("hours_bounds") ?? []
        hoursLower = bounds.count == 2 ? (NudgeClock.valid(bounds[0]) ?? "07:00") : "07:00"
        hoursUpper = bounds.count == 2 ? (NudgeClock.valid(bounds[1]) ?? "21:00") : "21:00"
        let range = json?["max_per_day_range"]?.arrayValue.compactMap { $0.intValue } ?? []
        if range.count == 2, range[0] >= 1, range[0] <= range[1] {
            maxRange = range[0]...range[1]
        } else {
            maxRange = 1...4
        }
    }
}

/// The whole `GET /v1/nudge` answer.
struct NudgeModel: Equatable {
    let settings: NudgeSettings
    let today: NudgeToday?
    let lastCheck: NudgeCheck?
    let nudges: [NudgeEntry]
    let week: NudgeWeek?
    let options: NudgeOptions
    let generatedAt: Date?

    init(json: JSONValue) {
        settings = NudgeSettings(json: json.obj("settings"))
        today = json.obj("today").map { NudgeToday(json: $0) }
        lastCheck = json.obj("last_check").map { NudgeCheck(json: $0) }
        nudges = json.list("nudges").enumerated().compactMap { NudgeEntry(json: $0.element, index: $0.offset) }
        week = json.obj("week").map { NudgeWeek(json: $0) }
        options = NudgeOptions(json: json.obj("options"))
        generatedAt = BIOSDate.parse(json.str("generated_at"))
    }

    /// Example text per tone for the settings (same wording as the server).
    static func example(tone: String) -> String {
        tone == "frech"
            ? "Hoch mit dir: 15 Kniebeugen, dann darf das Insulin wieder arbeiten."
            : "Kurz bewegen? Ein kurzer Spaziergang jetzt kann die Spitze flacher halten."
    }

    static func toneTitle(_ tone: String) -> String {
        switch tone {
        case "freundlich": return "Freundlich"
        case "frech": return "Frech"
        default: return tone.prefix(1).uppercased() + tone.dropFirst()
        }
    }
}

/// `training.strength` of `/v1/dashboard` (V3c, additive): last strength session.
struct StrengthModel: Equatable {
    let lastAt: Date?
    let daysSince: Int?
    let note: String?

    init?(json: JSONValue?) {
        guard let json, json.objectValue != nil else { return nil }
        lastAt = BIOSDate.parse(json.str("last_at"))
        daysSince = json.int("days_since")
        note = json.str("note")
        if lastAt == nil && daysSince == nil && note == nil { return nil }
    }

    /// "Letztes Krafttraining vor 3 Tagen" / "heute" / "gestern".
    var headline: String? {
        var days = daysSince
        if days == nil, let lastAt {
            let calendar = Calendar.current
            days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastAt),
                                           to: calendar.startOfDay(for: Date())).day
        }
        guard let days else { return nil }
        switch days {
        case ..<1: return "Letztes Krafttraining heute"
        case 1: return "Letztes Krafttraining gestern"
        default: return "Letztes Krafttraining vor \(days) Tagen"
        }
    }
}
