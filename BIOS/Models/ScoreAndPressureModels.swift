import Foundation

// Additive server fields of Build 4 (infection score, blood pressure). Read
// leniently with several candidate names until docs/API_v1.md fixes them; a
// missing block simply hides the UI and falls back to the previous view.

/// Level of the infection score: server word first, else derived from the score.
enum ScoreLevel: Equatable {
    case low
    case medium
    case high

    init(key: String?, score: Double?) {
        let text = (key ?? "").lowercased()
        if ["niedrig", "gering", "low", "ok", "green", "keine", "none"].contains(where: { text.contains($0) }) {
            self = .low
        } else if ["hoch", "high", "warn", "red", "stark"].contains(where: { text.contains($0) }) {
            self = .high
        } else if ["mittel", "moderate", "medium", "info", "yellow", "erhöht", "leicht"].contains(where: { text.contains($0) }) {
            self = .medium
        } else if let score {
            self = score >= 67 ? .high : (score >= 34 ? .medium : .low)
        } else {
            self = .low
        }
    }

    var fallbackWord: String {
        switch self {
        case .low: return "niedrig"
        case .medium: return "mittel"
        case .high: return "hoch"
        }
    }
}

/// One contribution to the infection score ("Ruhepuls +18").
struct ScorePart: Identifiable {
    let id: Int
    let key: String
    let label: String
    let points: Double?
    let max: Double?
    let text: String?

    init?(json: JSONValue, index: Int, fallbackKey: String? = nil) {
        guard let label = json.str("label") ?? json.str("name") ?? json.str("key") ?? fallbackKey else { return nil }
        id = index
        key = json.str("key") ?? fallbackKey ?? label
        self.label = label
        points = json.double("points") ?? json.double("score") ?? json.double("value") ?? json.double("contribution")
        max = json.double("max") ?? json.double("max_points") ?? json.double("weight")
        text = json.str("text") ?? json.str("display") ?? json.str("detail") ?? json.str("reason")
    }

    init(id: Int, key: String, points: Double) {
        self.id = id
        self.key = key
        self.label = ScorePart.labelFor(key)
        self.points = points
        self.max = nil
        self.text = nil
    }

    /// `score_parts` as a list of objects or as an object {key: points | {...}}.
    static func list(_ json: JSONValue?) -> [ScorePart] {
        guard let json else { return [] }
        if case .array(let items) = json {
            return items.enumerated().compactMap { ScorePart(json: $0.element, index: $0.offset) }
        }
        guard let object = json.objectValue else { return [] }
        var parts: [ScorePart] = []
        for key in object.keys.sorted() {
            guard let value = object[key] else { continue }
            if let number = value.finiteNumber {
                parts.append(ScorePart(id: parts.count, key: key, points: number))
            } else if value.objectValue != nil,
                      let part = ScorePart(json: value, index: parts.count, fallbackKey: ScorePart.labelFor(key)) {
                parts.append(part)
            }
        }
        return parts.sorted { ($0.points ?? 0) > ($1.points ?? 0) }
    }

    static func labelFor(_ key: String) -> String {
        switch key.lowercased() {
        case "rhr": return "Ruhepuls"
        case "hrv": return "HRV"
        case "skin_temp": return "Hauttemperatur"
        case "resp_rate": return "Atemfrequenz"
        case "spo2": return "SpO2"
        case "recovery": return "Recovery"
        case "sleep": return "Schlaf"
        case "glucose": return "Glukose"
        case "insulin": return "Insulin"
        case "env", "environment", "viruses": return "Umfeld (Viren)"
        default: return key
        }
    }
}

// MARK: - Blood pressure

struct BloodPressureReading {
    let sys: Double?
    let dia: Double?
    let pulse: Double?
    let date: Date?
    let rawDate: String?
    /// "home" or "clinic" (also "praxis", "ambulanz").
    let setting: String?

    init(json: JSONValue) {
        sys = json.double("sys") ?? json.double("systolic") ?? json.double("bp_sys")
        dia = json.double("dia") ?? json.double("diastolic") ?? json.double("bp_dia")
        pulse = json.double("pulse") ?? json.double("bp_pulse") ?? json.double("hr")
        rawDate = json.str("ts") ?? json.str("t") ?? json.str("measured_at") ?? json.str("last_ts") ?? json.str("date")
        date = BIOSDate.parse(rawDate)
        setting = json.str("setting") ?? json.str("context") ?? json.str("place") ?? json.str("location")
    }

    var isClinic: Bool {
        BloodPressureReading.isClinic(setting)
    }

    static func isClinic(_ setting: String?) -> Bool {
        let value = (setting ?? "").lowercased()
        return ["clinic", "praxis", "ambulanz", "arzt", "office", "klinik"].contains { value.contains($0) }
    }

    var pairText: String? {
        guard let sys, let dia else { return nil }
        return "\(BIOSFormat.number(sys))/\(BIOSFormat.number(dia))"
    }

    var whenText: String {
        guard let date else { return rawDate ?? "" }
        if let rawDate, rawDate.count == 10 { return BIOSFormat.relativeDayOf(date) }
        return BIOSFormat.relative(date)
    }
}

struct BloodPressureTileModel {
    let evaluable: Bool
    let reason: String?
    let last: BloodPressureReading
    /// Mean of readings 2 and 3 of the last series (home protocol).
    let meanSys: Double?
    let meanDia: Double?
    let status: BIOSStatus
    let classification: String?
    let homeSys: Double
    let homeDia: Double
    let targetSys: Double
    let targetDia: Double

    init(json: JSONValue) {
        evaluable = json.flag("evaluable", fallback: true)
        reason = json.str("reason")
        last = BloodPressureReading(json: json.obj("last") ?? json.obj("latest") ?? json)
        let mean = json.obj("mean_2_3") ?? json.obj("mean") ?? json.obj("avg")
        meanSys = mean?.double("sys") ?? json.double("mean_sys") ?? json.double("mean_2_3_sys")
        meanDia = mean?.double("dia") ?? json.double("mean_dia") ?? json.double("mean_2_3_dia")
        status = BIOSStatus(key: json.str("status"))
        classification = json.str("classification_text") ?? json.str("classification") ?? json.str("class_text")
            ?? json.str("text") ?? json.str("assessment")
        let home = json.list("home_threshold").compactMap { $0.finiteNumber }
        let target = json.list("target").compactMap { $0.finiteNumber }
        homeSys = home.count == 2 ? home[0] : (json.obj("thresholds")?.obj("home")?.double("sys") ?? 135)
        homeDia = home.count == 2 ? home[1] : (json.obj("thresholds")?.obj("home")?.double("dia") ?? 85)
        targetSys = target.count == 2 ? target[0] : (json.obj("thresholds")?.obj("target")?.double("sys") ?? 130)
        targetDia = target.count == 2 ? target[1] : (json.obj("thresholds")?.obj("target")?.double("dia") ?? 80)
    }

    var meanText: String? {
        guard let meanSys, let meanDia else { return nil }
        return "\(BIOSFormat.number(meanSys))/\(BIOSFormat.number(meanDia))"
    }

    /// Server text first; else a plain comparison with the home limit and the target.
    var classificationText: String {
        if let classification { return classification }
        guard let sys = meanSys ?? last.sys, let dia = meanDia ?? last.dia else { return "keine Bewertung" }
        if sys >= homeSys || dia >= homeDia {
            return "über der Grenze für zu Hause (\(BIOSFormat.number(homeSys))/\(BIOSFormat.number(homeDia)))"
        }
        if sys >= targetSys || dia >= targetDia {
            return "unter \(BIOSFormat.number(homeSys))/\(BIOSFormat.number(homeDia)), über dem Ziel \(BIOSFormat.number(targetSys))/\(BIOSFormat.number(targetDia))"
        }
        return "im Ziel (unter \(BIOSFormat.number(targetSys))/\(BIOSFormat.number(targetDia)))"
    }

    /// Status for symbol + color: server key, else from the comparison.
    var effectiveStatus: BIOSStatus {
        if status != .unknown { return status }
        guard let sys = meanSys ?? last.sys, let dia = meanDia ?? last.dia else { return .unknown }
        if sys >= homeSys || dia >= homeDia { return .warn }
        if sys >= targetSys || dia >= targetDia { return .info }
        return .ok
    }
}
