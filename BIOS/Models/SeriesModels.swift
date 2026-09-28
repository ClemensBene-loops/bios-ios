import Foundation

// View model for `GET /v1/series?metric=...&days=...`.
//
// Points are `{t, v}` (plus `tbr`/`tir`/`tar` for the `tir` series); `v` may
// be null (gap). Two-region series (viruses) may come as
// `series: {wien: [...], de: [...]}` instead of `points`.

struct SeriesPoint: Identifiable {
    let id: Int
    let date: Date
    let value: Double?
    let tbr: Double?
    let tir: Double?
    let tar: Double?
    /// Measurement setting ("home" / "clinic"), blood pressure only.
    var setting: String? = nil
    /// Measuring method of a single reading ("infrarot", "oral"), body temperature only.
    var method: String? = nil
    /// Display class of a temperature ("normal", "erhoeht", "fieber"), body temperature only.
    var level: String? = nil
    /// Count of readings behind a daily aggregate (`daily[].n`).
    var count: Int? = nil
    /// Time of the day's maximum (`daily[].max_at`).
    var maxAt: Date? = nil

    static func list(_ values: [JSONValue]) -> [SeriesPoint] {
        var points: [SeriesPoint] = []
        for element in values {
            guard let point = SeriesPoint(json: element, id: points.count) else { continue }
            points.append(point)
        }
        return points.sorted { $0.date < $1.date }
    }

    init(id: Int, date: Date, value: Double?, tbr: Double?, tir: Double?, tar: Double?,
         setting: String? = nil, method: String? = nil, level: String? = nil) {
        self.id = id
        self.date = date
        self.value = value
        self.tbr = tbr
        self.tir = tir
        self.tar = tar
        self.setting = setting
        self.method = method
        self.level = level
    }

    /// One `{t, v, ...}` object; nil without a parseable `t`.
    init?(json element: JSONValue, id: Int) {
        guard let date = BIOSDate.parse(element.str("t")) else { return nil }
        self.init(
            id: id,
            date: date,
            value: element.double("v"),
            tbr: element.double("tbr"),
            tir: element.double("tir"),
            tar: element.double("tar"),
            setting: element.str("setting") ?? element.str("context") ?? element.str("place"),
            method: element.str("method"),
            level: element.str("level")
        )
        count = element.int("n")
        maxAt = BIOSDate.parse(element.str("max_at"))
    }
}

struct SeriesBaseline {
    let median: Double?
    let sigma: Double?
    let lo: Double?
    let hi: Double?
    let n: Int?
    let z: Double?

    init(json: JSONValue) {
        median = json.double("median")
        sigma = json.double("sigma")
        z = json.double("z")
        n = json.int("n")
        if let lo = json.double("lo"), let hi = json.double("hi") {
            self.lo = lo
            self.hi = hi
        } else if let median, let sigma {
            let width = (z ?? 1.5) * sigma
            self.lo = median - width
            self.hi = median + width
        } else {
            self.lo = nil
            self.hi = nil
        }
    }

    var band: (lo: Double, hi: Double)? {
        guard let lo, let hi, hi >= lo else { return nil }
        return (lo, hi)
    }
}

struct SeriesModel {
    let metric: String
    let label: String?
    let unit: String?
    let resolution: String
    let days: Int?
    let points: [SeriesPoint]
    /// Named sub-series ("wien", "de") when the server sends `series: {...}`.
    let regions: [String: [SeriesPoint]]
    let baseline: SeriesBaseline?
    /// Episode days (infection check alarm `infekt`), all daily series.
    let flagDates: [Date]
    /// Context days (glu_up / ins_up, rule A: never an alarm), glucose/insulin only.
    let contextFlagDates: [Date]
    let generatedAt: Date?
    /// Fixed reference lines from the server (`refs: [{v, label}]`).
    let refs: [ChartRef]
    /// `body_temp`: one point per local day with readings (`v` = day max, `count`, `maxAt`).
    let daily: [SeriesPoint]
    /// `body_temp`: newest reading overall (also when older than the range).
    let lastReading: SeriesPoint?
    /// `body_temp`: related series with its own axis (`companion.metric`, e.g. "whoop_skin_temp").
    let companionMetric: String?
    let companionLabel: String?

    init(json: JSONValue) {
        metric = json.str("metric") ?? ""
        label = json.str("label")
        unit = json.str("unit")
        resolution = (json.str("resolution") ?? "day").lowercased()
        days = json.int("days")
        points = SeriesPoint.list(json.list("points"))
        var regions: [String: [SeriesPoint]] = [:]
        for (key, value) in json.obj("series")?.objectValue ?? [:] {
            let parsed: [SeriesPoint]
            if value.objectValue != nil {
                parsed = SeriesPoint.list(value.list("points"))
            } else {
                parsed = SeriesPoint.list(value.arrayValue)
            }
            if !parsed.isEmpty {
                regions[key] = parsed
            }
        }
        self.regions = regions
        baseline = json.obj("baseline").map { SeriesBaseline(json: $0) }
        flagDates = json.strings("flags").compactMap { BIOSDate.parse($0) }
        contextFlagDates = json.strings("context_flags").compactMap { BIOSDate.parse($0) }
        generatedAt = BIOSDate.parse(json.str("generated_at"))
        var refs: [ChartRef] = []
        for (index, element) in json.list("refs").enumerated() {
            guard let value = element.double("v") else { continue }
            refs.append(ChartRef(id: index, value: value, label: element.str("label") ?? "", trailing: index % 2 == 1))
        }
        self.refs = refs
        daily = SeriesPoint.list(json.list("daily"))
        lastReading = json.obj("last").flatMap { SeriesPoint(json: $0, id: 0) }
        companionMetric = json.obj("companion")?.str("metric")
        companionLabel = json.obj("companion")?.str("label")
    }

    /// Last point with a value.
    var latest: SeriesPoint? {
        points.last { $0.value != nil }
    }

    var hasValues: Bool {
        points.contains { $0.value != nil || $0.tir != nil } || !regions.isEmpty
    }
}
