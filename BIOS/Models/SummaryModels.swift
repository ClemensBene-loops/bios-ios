import Foundation

// View models for the two server documents inside `/v1/summary`.
//
// Built from `JSONValue` with lenient accessors: every field is optional or has
// a default, wrong types are skipped, so nothing the server sends can crash the
// app. Shapes follow BIOS `analysis/whoop_check.py` (`evaluate`, `build`) and
// `analysis/outlook.py` (`build`, `alerts`, `allergy_status`), each plus `text`.

enum BIOSAlertSeverity: Equatable {
    case warn
    case info
    case other

    init(_ raw: String?) {
        switch raw {
        case "warn": self = .warn
        case "info": self = .info
        default: self = .other
        }
    }
}

/// Overall state of a section, drives symbol and color.
enum BIOSStatus: Equatable {
    case warn
    case info
    case ok
    case unknown
}

/// One entry of an `alerts` (or `hints`) list.
struct BIOSAlert: Identifiable, Equatable {
    let id: Int
    let kind: String
    let severity: BIOSAlertSeverity
    let text: String
    /// Episode length in days (Whoop alerts only).
    let days: Int?

    static func list(_ json: JSONValue?) -> [BIOSAlert] {
        var items: [BIOSAlert] = []
        for element in json?.arrayValue ?? [] {
            guard let text = element["text"]?.stringValue, !text.isEmpty else { continue }
            items.append(BIOSAlert(
                id: items.count,
                kind: element["kind"]?.stringValue ?? "",
                severity: BIOSAlertSeverity(element["severity"]?.stringValue),
                text: text,
                days: element["days"]?.intValue
            ))
        }
        return items
    }
}

// MARK: - Whoop check

/// One local day of the Whoop check (`days[]`).
struct BIOSWhoopDay: Identifiable, Equatable {
    let date: String
    let rhr: Double?
    let hrv: Double?
    let recovery: Double?
    let sleepHours: Double?
    let respRate: Double?
    let skinTemp: Double?
    let flagged: Bool

    var id: String { date }

    init?(json: JSONValue) {
        guard let date = json["date"]?.stringValue else { return nil }
        self.date = date
        rhr = json["whoop_rhr"]?.numberValue
        hrv = json["whoop_hrv"]?.numberValue
        recovery = json["whoop_recovery"]?.numberValue
        sleepHours = json["whoop_sleep_duration"]?.numberValue
        respRate = json["whoop_resp_rate"]?.numberValue
        skinTemp = json["whoop_skin_temp"]?.numberValue
        flagged = json["flags"]?["flagged"]?.boolValue ?? false
    }
}

/// `whoop_check.json`: alerts, last days and baseline for the evaluated day.
struct BIOSWhoopCheck {
    /// Evaluated local date "YYYY-MM-DD", nil when there is no Whoop data.
    let day: String?
    let alerts: [BIOSAlert]
    let allClear: Bool
    let errors: [String]
    let days: [BIOSWhoopDay]
    /// metric (e.g. "whoop_rhr") -> baseline median
    let baselineMedian: [String: Double]
    /// Number of days in the RHR baseline.
    let baselineDays: Int?
    let text: String?
    let generatedAt: String?

    init(json: JSONValue) {
        day = json["day"]?.stringValue
        alerts = BIOSAlert.list(json["alerts"])
        allClear = json["all_clear"]?.boolValue ?? false
        errors = json.strings("errors")
        days = (json["days"]?.arrayValue ?? []).compactMap { BIOSWhoopDay(json: $0) }
        var medians: [String: Double] = [:]
        for (metric, value) in json["baseline"]?.objectValue ?? [:] {
            if let median = value["median"]?.numberValue {
                medians[metric] = median
            }
        }
        baselineMedian = medians
        baselineDays = json["baseline"]?["whoop_rhr"]?["n"]?.intValue
        text = json["text"]?.stringValue
        generatedAt = json["generated_at"]?.stringValue
    }

    /// Last evaluated day (the one the alerts refer to).
    var latest: BIOSWhoopDay? { days.last }

    var status: BIOSStatus {
        if day == nil { return .unknown }
        if alerts.contains(where: { $0.severity == .warn }) { return .warn }
        if !alerts.isEmpty { return .info }
        return .ok
    }

    /// Short verdict, same priority as the server's push title.
    var headline: String {
        if day == nil { return "Keine Whoop-Daten" }
        let byKind = Dictionary(alerts.map { ($0.kind, $0) }, uniquingKeysWith: { first, _ in first })
        if let alert = byKind["infekt"] {
            if let days = alert.days { return "Infektmuster seit \(days) Tagen" }
            return "Infektmuster"
        }
        if byKind["infekt_frueh"] != nil { return "Frühzeichen: Ruhepuls hoch, HRV tief" }
        if let alert = byKind["recovery_rot"] {
            if let days = alert.days { return "Recovery seit \(days) Tagen rot" }
            return "Recovery rot"
        }
        if byKind["schlaf"] != nil { return "Schlafdefizit" }
        if byKind["schlaf_woche"] != nil { return "Wenig Schlaf im Wochenschnitt" }
        if !alerts.isEmpty { return "Hinweis" }
        return "Alles im Rahmen"
    }
}

// MARK: - Outlook

struct BIOSVirus: Identifiable {
    let id: String
    let name: String
    let level: String
    let trend: String
    let latestDate: String?
    let stale: Bool
    let vsUsual: Double?
    let onsetKW: Int?
}

struct BIOSVirusRegion: Identifiable {
    let id: String
    let region: String
    let viruses: [BIOSVirus]
}

struct BIOSPollenAllergen: Identifiable {
    let id: String
    let name: String
    /// Highest level over the forecast days.
    let level: String
    let peakDate: String?
    let peakMean: Double?
}

struct BIOSPollenPlace: Identifiable {
    let id: String
    let place: String
    let allergens: [BIOSPollenAllergen]
}

struct BIOSAllergyStatus {
    let active: Bool
    let place: String?
    let reasons: [String]
}

/// `outlook.json`: viruses in wastewater, pollen forecast, allergy block, hints.
struct BIOSOutlook {
    let today: String?
    let season: String?
    let alerts: [BIOSAlert]
    let regions: [BIOSVirusRegion]
    let pollen: [BIOSPollenPlace]
    let allergy: BIOSAllergyStatus?
    /// Hints with severity "info" (the "warn" ones are already in `alerts`).
    let infoHints: [BIOSAlert]
    let errors: [String]
    let text: String?
    let generatedAt: String?

    static let pollenLevelOrder = ["keine", "niedrig", "mittel", "hoch"]

    init(json: JSONValue) {
        today = json["today"]?.stringValue
        season = json["season"]?.stringValue
        alerts = BIOSAlert.list(json["alerts"])
        infoHints = BIOSAlert.list(json["hints"]).filter { $0.severity == .info }
        errors = json.strings("errors")
        text = json["text"]?.stringValue
        generatedAt = json["generated_at"]?.stringValue

        // viruses: {source: {region, unit, viruses: [...]}}; Wien first.
        let sources = json["viruses"]?.objectValue ?? [:]
        let keys = sources.keys.sorted { lhs, rhs in
            let l = lhs == "abwasser_wien" ? 0 : 1
            let r = rhs == "abwasser_wien" ? 0 : 1
            return l == r ? lhs < rhs : l < r
        }
        var regions: [BIOSVirusRegion] = []
        for key in keys {
            guard let source = sources[key] else { continue }
            var items: [BIOSVirus] = []
            for virus in source["viruses"]?.arrayValue ?? [] {
                guard let name = virus["virus"]?.stringValue else { continue }
                items.append(BIOSVirus(
                    id: virus["metric"]?.stringValue ?? name,
                    name: name,
                    level: virus["level"]?.stringValue ?? "",
                    trend: virus["trend"]?.stringValue ?? "",
                    latestDate: virus["latest_date"]?.stringValue,
                    stale: virus["stale"]?.boolValue ?? false,
                    vsUsual: virus["vs_usual_this_week"]?.numberValue,
                    onsetKW: virus["typical_onset_kw"]?.intValue
                ))
            }
            if !items.isEmpty {
                regions.append(BIOSVirusRegion(
                    id: key,
                    region: source["region"]?.stringValue ?? key,
                    viruses: items
                ))
            }
        }
        self.regions = regions

        // pollen: [{place, days: [{date, allergen, name, mean, max, level}]}]
        var places: [BIOSPollenPlace] = []
        for (index, entry) in (json["pollen"]?.arrayValue ?? []).enumerated() {
            let place = entry["place"]?.stringValue ?? "Ort \(index + 1)"
            var order: [String] = []
            var worst: [String: BIOSPollenAllergen] = [:]
            for day in entry["days"]?.arrayValue ?? [] {
                let key = day["allergen"]?.stringValue ?? day["name"]?.stringValue ?? ""
                if key.isEmpty { continue }
                let level = day["level"]?.stringValue ?? "keine"
                let candidate = BIOSPollenAllergen(
                    id: key,
                    name: day["name"]?.stringValue ?? key,
                    level: level,
                    peakDate: day["date"]?.stringValue,
                    peakMean: day["mean"]?.numberValue
                )
                if let current = worst[key] {
                    if BIOSOutlook.rank(level) > BIOSOutlook.rank(current.level) {
                        worst[key] = candidate
                    }
                } else {
                    order.append(key)
                    worst[key] = candidate
                }
            }
            places.append(BIOSPollenPlace(
                id: "\(index)-\(place)",
                place: place,
                allergens: order.compactMap { worst[$0] }
            ))
        }
        pollen = places

        if let allergy = json["allergy"], allergy.objectValue != nil {
            self.allergy = BIOSAllergyStatus(
                active: allergy["active"]?.boolValue ?? false,
                place: allergy["place"]?.stringValue,
                reasons: allergy.strings("reasons")
            )
        } else {
            self.allergy = nil
        }
    }

    static func rank(_ pollenLevel: String) -> Int {
        pollenLevelOrder.firstIndex(of: pollenLevel) ?? 0
    }

    var status: BIOSStatus {
        if today == nil && regions.isEmpty && pollen.isEmpty { return .unknown }
        if alerts.contains(where: { $0.severity == .warn }) { return .warn }
        if !alerts.isEmpty { return .info }
        return .ok
    }

    var headline: String {
        switch status {
        case .unknown: return "Kein Ausblick"
        case .warn: return "Achtung"
        case .info: return "Hinweis"
        case .ok: return "Nichts Besonderes"
        }
    }
}

extension SummaryResponse {
    var whoop: BIOSWhoopCheck? {
        guard let json = whoopCheck, json.objectValue != nil else { return nil }
        return BIOSWhoopCheck(json: json)
    }

    var outlookModel: BIOSOutlook? {
        guard let json = outlook, json.objectValue != nil else { return nil }
        return BIOSOutlook(json: json)
    }
}

// MARK: - Formatting (German, independent of the device language)

enum BIOSFormat {
    static let locale = Locale(identifier: "de_AT")

    /// "YYYY-MM-DD" (or an ISO timestamp starting with it) as a local date.
    static func date(fromISODay value: String?) -> Date? {
        guard let value, value.count >= 10 else { return nil }
        let parts = value.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = dayOfMonth
        components.hour = 12
        return Calendar.current.date(from: components)
    }

    /// "Mi., 24.09." or the raw string if it cannot be parsed.
    static func day(_ value: String?) -> String {
        guard let parsed = Self.date(fromISODay: value) else { return value ?? "" }
        return parsed.formatted(
            .dateTime.weekday(.abbreviated).day(.twoDigits).month(.twoDigits).locale(locale)
        )
    }

    /// "24.09." or the raw string.
    static func shortDay(_ value: String?) -> String {
        guard let parsed = Self.date(fromISODay: value) else { return value ?? "" }
        return parsed.formatted(.dateTime.day(.twoDigits).month(.twoDigits).locale(locale))
    }

    /// "25.09.2026, 11:25"
    static func timestamp(_ date: Date) -> String {
        date.formatted(
            .dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute().locale(locale)
        )
    }

    /// Decimal comma, fixed digits.
    static func number(_ value: Double, digits: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    /// "+3" / "-18", explicit sign.
    static func signed(_ value: Double, digits: Int = 0) -> String {
        let text = number(abs(value), digits: digits)
        if text == number(0, digits: digits) { return "±" + text }
        return (value < 0 ? "-" : "+") + text
    }
}
