import Foundation

// View model for `GET /v1/therapy`: the Loop settings (Nightscout profile),
// delivered basal per hour and the optional basal assistant (`suggestions`).
// Decoded leniently with alternative keys; anything missing is hidden.

/// One entry of a daily schedule (start minute of the day + value(s)).
struct TherapyScheduleEntry: Identifiable, Equatable {
    let id: Int
    /// Minutes after midnight.
    let minute: Int
    let value: Double?
    /// Target ranges: low/high (value = nil).
    var low: Double? = nil
    var high: Double? = nil

    var timeText: String {
        "\(BIOSFormat.twoDigits(minute / 60)):\(BIOSFormat.twoDigits(minute % 60))"
    }

    /// "08:30", "8:30", 30600 (seconds), 510 (minutes) -> minutes.
    static func minute(_ json: JSONValue) -> Int? {
        for key in ["time", "start", "start_time", "from"] {
            if let text = json.str(key) {
                let parts = text.split(separator: ":").compactMap { Int($0) }
                if let hour = parts.first { return hour * 60 + (parts.count > 1 ? parts[1] : 0) }
            }
        }
        if let seconds = json.double("timeAsSeconds") ?? json.double("seconds") ?? json.double("offset_s") {
            return Int(seconds / 60)
        }
        if let minutes = json.double("minute") ?? json.double("start_min") ?? json.double("offset_min") {
            return Int(minutes)
        }
        if let hour = json.int("hour") { return hour * 60 }
        return nil
    }

    static func list(_ values: [JSONValue], valueKeys: [String]) -> [TherapyScheduleEntry] {
        var entries: [TherapyScheduleEntry] = []
        for element in values {
            guard let minute = minute(element) else { continue }
            let value = valueKeys.lazy.compactMap { element.double($0) }.first
            var entry = TherapyScheduleEntry(id: entries.count, minute: minute, value: value)
            entry.low = element.double("low") ?? element.double("min") ?? element.double("target_low")
            entry.high = element.double("high") ?? element.double("max") ?? element.double("target_high")
            if value == nil, entry.low == nil, entry.high == nil { continue }
            entries.append(entry)
        }
        return entries.sorted { $0.minute < $1.minute }
    }

    /// Value of a schedule at a minute of the day (last entry at or before it).
    static func value(_ entries: [TherapyScheduleEntry], at minute: Int) -> Double? {
        (entries.last { $0.minute <= minute } ?? entries.last)?.value
    }

    /// Sum of rate x duration over the day (U per day of a basal schedule).
    static func dailyTotal(_ entries: [TherapyScheduleEntry]) -> Double? {
        guard !entries.isEmpty else { return nil }
        var total = 0.0
        for (index, entry) in entries.enumerated() {
            let end = index + 1 < entries.count ? entries[index + 1].minute : 24 * 60
            total += (entry.value ?? 0) * Double(max(0, end - entry.minute)) / 60
        }
        return total
    }
}

struct TherapyOverride: Identifiable {
    let id: Int
    let name: String
    let symbol: String?
    let low: Double?
    let high: Double?
    /// Insulin needs factor (1.5 = 150 %), nil = unchanged.
    let factor: Double?
    /// Minutes; nil = unbegrenzt.
    let durationMin: Double?
    let indefinite: Bool

    /// `{name, symbol, factor, target: [low, high] | null, duration: min | null, indefinite}`.
    init?(json element: JSONValue, id: Int) {
        guard let name = element.str("name") ?? element.str("title") else { return nil }
        self.id = id
        self.name = name
        symbol = element.str("symbol")
        let targetList = element.list("target").compactMap(\.finiteNumber)
        let targetObject = element.obj("target")
        low = targetList.first ?? targetObject?.double("low") ?? element.double("target_low")
        high = (targetList.count > 1 ? targetList[1] : targetList.first)
            ?? targetObject?.double("high") ?? element.double("target_high")
        let pct = element.double("insulin_needs_pct") ?? element.double("percentage")
        factor = element.double("factor") ?? element.double("insulin_needs") ?? element.double("scale")
            ?? pct.map { $0 / 100 }
        let minutes = element.double("duration") ?? element.double("duration_min")
        durationMin = minutes
        indefinite = element.flag("indefinite") || minutes == nil
    }

    private var factorText: String? {
        guard let factor, abs(factor - 1) > 0.001 else { return nil }
        let digits = (factor * 10).rounded() == factor * 10 ? 1 : 2
        return "x\(BIOSFormat.number(factor, digits: digits))"
    }

    var durationText: String {
        guard !indefinite, let durationMin, durationMin > 0 else { return "unbegrenzt" }
        if durationMin >= 60 {
            let hours = durationMin / 60
            return "\(BIOSFormat.number(hours, digits: hours.rounded() == hours ? 0 : 1)) h"
        }
        return "\(BIOSFormat.number(durationMin)) min"
    }

    /// "x1,5 · 120 bis 140 mg/dL · unbegrenzt"
    var detailText: String {
        var parts: [String] = []
        if let factorText { parts.append(factorText) }
        if let low, let high {
            parts.append(low == high
                ? "\(BIOSFormat.number(low)) mg/dL"
                : "\(BIOSFormat.number(low)) bis \(BIOSFormat.number(high)) mg/dL")
        }
        parts.append(durationText)
        return parts.joined(separator: " · ")
    }

    /// "Krank x1,5, unbegrenzt"
    var bannerText: String {
        var text = [symbol, name].compactMap { $0 }.joined(separator: " ")
        if let factorText { text += " " + factorText }
        return text + ", " + durationText
    }
}

/// Delivered basal of one hour: mean over n days.
struct DeliveredHour: Equatable {
    let hour: Int
    let mean: Double
    let n: Int?
    var scheduled: Double? = nil
}

/// Basal assistant: per hour proposal plus the overall verdict.
struct TherapySuggestions {
    struct Hour: Identifiable {
        var id: Int { hour }
        let hour: Int
        let scheduled: Double?
        let deliveredMean: Double?
        let proposed: Double?
        let change: Double?
        let consistency: Double?
        let consistencyText: String?
        let nDays: Int?
        let fastingSlope: Double?
        let hypo: Bool
        let note: String?

        var hasChange: Bool {
            if let change { return abs(change) >= 0.005 }
            if let proposed, let scheduled { return abs(proposed - scheduled) >= 0.005 }
            return false
        }

        var isLowConsistency: Bool {
            if let consistency { return consistency < (consistency > 1 ? 70 : 0.7) }
            if let text = consistencyText?.lowercased() { return text.contains("niedrig") || text.contains("low") }
            return false
        }
    }

    struct ExcludedDay: Identifiable {
        var id: String { date }
        let date: String
        let reasons: [String]
    }

    let recommended: Bool
    /// "Keine Änderung nötig": gate open, no robust change (neutral, not a warning).
    let noChangeNeeded: Bool
    let statusText: String
    let reasons: [String]
    let disclaimer: String?
    let windowStart: String?
    let windowEnd: String?
    let windowDays: Int
    let cleanDays: Int?
    let excluded: [ExcludedDay]
    let hours: [Hour]
    let blocks: [TherapyScheduleEntry]
    let totalOld: Double?
    let totalNew: Double?
    let totalChangePct: Double?

    init?(json: JSONValue?) {
        guard let json, json.objectValue != nil else { return nil }
        let status = (json.str("status") ?? "").lowercased()
        recommended = status == "recommended" || status == "empfohlen"
        let text = json.str("status_text") ?? (recommended ? "Zur Übernahme empfohlen" : "Nicht zur Übernahme empfohlen")
        statusText = text
        noChangeNeeded = !recommended && text.lowercased().contains("keine änderung")
        reasons = TherapySuggestions.texts(json.list("reasons"))
        disclaimer = json.str("disclaimer")
        let window = json.obj("window")
        windowStart = window?.str("start") ?? window?.str("from") ?? json.str("window_start")
        windowEnd = window?.str("end") ?? window?.str("to") ?? json.str("window_end")
        var excluded: [ExcludedDay] = []
        for element in json.list("excluded_days") {
            if let date = element.stringValue {
                excluded.append(ExcludedDay(date: date, reasons: []))
            } else if let date = element.str("date") ?? element.str("day") {
                var reasons = TherapySuggestions.texts(element.list("reasons"))
                if reasons.isEmpty, let reason = element.str("reason") { reasons = [reason] }
                excluded.append(ExcludedDay(date: date, reasons: reasons))
            }
        }
        self.excluded = excluded
        let clean = json.int("clean_days") ?? (json["clean_days"]?.arrayValue).map { $0.count }
        cleanDays = clean
        if let days = json.int("window_days") ?? window?.int("days") {
            windowDays = days
        } else if let start = BIOSDate.day(windowStart), let end = BIOSDate.day(windowEnd) {
            windowDays = (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 13) + 1
        } else {
            windowDays = (clean ?? 0) + excluded.count > 0 ? (clean ?? 0) + excluded.count : 14
        }
        var hours: [Hour] = []
        let hourList = json.list("hours").isEmpty ? (json.list("per_hour").isEmpty ? json.list("hourly") : json.list("per_hour")) : json.list("hours")
        for element in hourList {
            guard let hour = element.int("hour") ?? TherapyScheduleEntry.minute(element).map({ $0 / 60 }) else { continue }
            hours.append(Hour(
                hour: hour,
                scheduled: element.double("scheduled") ?? element.double("current"),
                deliveredMean: element.double("delivered_mean") ?? element.double("delivered"),
                proposed: element.double("proposed") ?? element.double("suggested"),
                change: element.double("change"),
                consistency: element.double("consistency"),
                consistencyText: element.str("consistency"),
                nDays: element.int("n_days") ?? element.int("n"),
                fastingSlope: element.double("fasting_slope"),
                hypo: element.flag("hypo_flag") || element.flag("hypo"),
                note: element.str("note")
            ))
        }
        self.hours = hours.sorted { $0.hour < $1.hour }
        blocks = TherapyScheduleEntry.list(
            json.list("blocks").isEmpty ? json.list("proposed_blocks") : json.list("blocks"),
            valueKeys: ["rate", "proposed", "value"]
        )
        let totals = json.obj("totals")
        totalOld = totals?.double("old") ?? totals?.double("current") ?? json.double("total_old")
        totalNew = totals?.double("new") ?? totals?.double("proposed") ?? json.double("total_new")
        totalChangePct = totals?.double("change_pct")
    }

    func hour(_ hour: Int) -> Hour? {
        hours.first { $0.hour == hour }
    }

    var windowText: String? {
        guard let windowStart, let windowEnd else { return nil }
        let start = BIOSDate.day(windowStart).map { BIOSFormat.shortDate($0) } ?? windowStart
        let end = BIOSDate.day(windowEnd).map { BIOSFormat.shortDate($0) } ?? windowEnd
        return "\(start) bis \(end)"
    }

    var cleanText: String? {
        guard let cleanDays else { return nil }
        return "\(cleanDays) von \(windowDays) Tagen sauber"
    }

    static func texts(_ values: [JSONValue]) -> [String] {
        values.compactMap { $0.stringValue ?? $0.str("text") ?? $0.str("reason") }.filter { !$0.isEmpty }
    }
}

struct TherapyModel {
    let basal: [TherapyScheduleEntry]
    let carbRatio: [TherapyScheduleEntry]
    let sensitivity: [TherapyScheduleEntry]
    let targets: [TherapyScheduleEntry]
    let maxBasal: Double?
    let maxBolus: Double?
    let overrides: [TherapyOverride]
    /// Running override (banner).
    let activeOverride: TherapyOverride?
    /// Planned U/h per hour (minute weighted, 24 values).
    let basalHourly: [Double?]
    let note: String?
    let errors: [String]
    let delivered: [DeliveredHour]
    let deliveredDays: Int?
    let basalTotal: Double?
    let deliveredTotal: Double?
    let profileName: String?
    /// "nightscout" or "db" (then without ratio, ISF, targets, limits).
    let profileSource: String?
    let updatedAt: Date?
    let generatedAt: Date?
    let suggestions: TherapySuggestions?

    init(json root: JSONValue) {
        // Schedules may sit in `profile` (Nightscout shape) or at the top level.
        let json = root.obj("profile") ?? root.obj("settings") ?? root
        func firstList(_ keys: [String]) -> [JSONValue] {
            for key in keys {
                let list = json.list(key)
                if !list.isEmpty { return list }
                let rootList = root.list(key)
                if !rootList.isEmpty { return rootList }
                if let nested = json.obj(key) ?? root.obj(key) {
                    for inner in ["schedule", "entries", "items", "values"] where !nested.list(inner).isEmpty {
                        return nested.list(inner)
                    }
                }
            }
            return []
        }
        basal = TherapyScheduleEntry.list(firstList(["basal", "basal_schedule", "basal_rates", "basal_rate"]),
                                          valueKeys: ["rate", "value", "u_h"])
        carbRatio = TherapyScheduleEntry.list(firstList(["carb_ratio", "carb_ratios", "carbratio", "ic"]),
                                              valueKeys: ["value", "ratio", "g_per_u"])
        sensitivity = TherapyScheduleEntry.list(firstList(["sensitivity", "isf", "insulin_sensitivity", "sens"]),
                                                valueKeys: ["value", "isf", "mgdl_per_u"])
        targets = TherapyScheduleEntry.list(firstList(["target", "targets", "target_range", "correction_range"]),
                                            valueKeys: ["value", "target"])
        let limits = json.obj("limits") ?? root.obj("limits") ?? root.obj("delivery_limits")
        maxBasal = json.double("max_basal") ?? root.double("max_basal") ?? limits?.double("max_basal")
        maxBolus = json.double("max_bolus") ?? root.double("max_bolus") ?? limits?.double("max_bolus")
        var overrides: [TherapyOverride] = []
        activeOverride = root.obj("active_override").flatMap { TherapyOverride(json: $0, id: 0) }
        note = root.str("note")
        errors = root.strings("errors")
        basalHourly = root.list("basal_hourly").map(\.finiteNumber)
        for element in firstList(["overrides", "override_presets", "presets"]) {
            if let preset = TherapyOverride(json: element, id: overrides.count) { overrides.append(preset) }
        }
        self.overrides = overrides

        var delivered: [DeliveredHour] = []
        let deliveredJSON = root["delivered"] ?? root["basal_delivered"] ?? root["delivered_by_hour"]
        if let numbers = deliveredJSON?.arrayValue, numbers.first?.numberValue != nil {
            for (hour, value) in numbers.enumerated() {
                if let mean = value.finiteNumber { delivered.append(DeliveredHour(hour: hour, mean: mean, n: nil)) }
            }
        } else {
            let list = deliveredJSON?.arrayValue ?? deliveredJSON?.list("hours") ?? []
            for element in list {
                guard let hour = element.int("hour"),
                      let mean = element.double("mean") ?? element.double("delivered_mean") ?? element.double("value") else { continue }
                delivered.append(DeliveredHour(hour: hour, mean: mean, n: element.int("n") ?? element.int("n_days"),
                                               scheduled: element.double("scheduled")))
            }
        }
        self.delivered = delivered
        deliveredDays = root.int("delivered_days") ?? deliveredJSON?.int("days") ?? root.int("days")
        basalTotal = root.double("basal_total") ?? json.double("basal_total") ?? TherapyScheduleEntry.dailyTotal(basal)
        let info = root.obj("delivered_info")
        deliveredTotal = info?.double("delivered_total") ?? root.double("delivered_total")
            ?? (delivered.count == 24 ? delivered.reduce(0) { $0 + $1.mean } : nil)
        profileName = json.str("name") ?? root.str("profile_name")
        profileSource = root.obj("profile")?.str("source")
        updatedAt = BIOSDate.parse(json.str("start") ?? root.str("updated_at") ?? json.str("updated_at"))
        generatedAt = BIOSDate.parse(root.str("generated_at"))
        suggestions = TherapySuggestions(json: root["suggestions"])
    }

    var isEmpty: Bool {
        basal.isEmpty && carbRatio.isEmpty && sensitivity.isEmpty && targets.isEmpty && suggestions == nil
    }

    func scheduled(hour: Int) -> Double? {
        if hour < basalHourly.count, let value = basalHourly[hour] { return value }
        if let entry = delivered.first(where: { $0.hour == hour }), let scheduled = entry.scheduled { return scheduled }
        return TherapyScheduleEntry.value(basal, at: hour * 60)
    }

    func delivered(hour: Int) -> DeliveredHour? {
        if let entry = delivered.first(where: { $0.hour == hour }) { return entry }
        if let suggestion = suggestions?.hour(hour), let mean = suggestion.deliveredMean {
            return DeliveredHour(hour: hour, mean: mean, n: suggestion.nDays)
        }
        return nil
    }

    var hasHourly: Bool {
        !delivered.isEmpty || !(suggestions?.hours.isEmpty ?? true)
    }
}
