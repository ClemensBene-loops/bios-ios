import Foundation

// View models for `GET /v1/dashboard`.
//
// Built from `JSONValue` with lenient accessors: every tile and field is
// optional or has a default, wrong types are skipped, so a missing tile or a
// new server field never breaks the app. The server computes all levels,
// colors (as keys), texts and deltas; the app only formats and draws.

/// Status key of a card: drives symbol + color (never color alone).
enum BIOSStatus: String, Equatable {
    case ok
    case info
    case warn
    case unknown

    init(key: String?) {
        self = BIOSStatus(rawValue: (key ?? "").lowercased()) ?? .unknown
    }
}

/// Recovery zone key (Whoop colors).
enum BIOSZone: String, Equatable {
    case green
    case yellow
    case red
    case none

    /// Server key first; if missing, derived from the value (67 / 34 like Whoop).
    init(key: String?, value: Double?) {
        if let key, let zone = BIOSZone(rawValue: key.lowercased()) {
            self = zone
            return
        }
        guard let value else {
            self = .none
            return
        }
        if value >= 67 {
            self = .green
        } else if value >= 34 {
            self = .yellow
        } else {
            self = .red
        }
    }

    var word: String {
        switch self {
        case .green: return "hoch"
        case .yellow: return "mittel"
        case .red: return "niedrig"
        case .none: return "keine Daten"
        }
    }
}

/// One entry of an `alerts` or `hints` list.
struct BIOSAlert: Identifiable, Equatable {
    let id: Int
    let kind: String
    let severity: String
    let text: String
    let icon: String?
    let days: Int?

    static func list(_ values: [JSONValue]) -> [BIOSAlert] {
        var items: [BIOSAlert] = []
        for element in values {
            // Plain strings are accepted as well.
            if let text = element.stringValue, !text.isEmpty {
                items.append(BIOSAlert(id: items.count, kind: "", severity: "info", text: text, icon: nil, days: nil))
                continue
            }
            guard let text = element.str("text") else { continue }
            items.append(BIOSAlert(
                id: items.count,
                kind: element.str("kind") ?? "",
                severity: element.str("severity") ?? "info",
                text: text,
                icon: element.str("icon"),
                days: element.int("days")
            ))
        }
        return items
    }
}

// MARK: - Dashboard

struct DashboardModel {
    let schemaVersion: Int?
    let generatedAt: Date?
    let freshness: [FreshnessItem]
    let infection: InfectionModel?
    let outlook: OutlookCardModel?
    let virusesWien: VirusRegionModel?
    let pollen: PollenModel?
    let glucose: GlucoseTileModel?
    let recovery: RecoveryTileModel?
    let insulin: InsulinTileModel?
    let loop: LoopTileModel?
    let environment: EnvironmentModel?
    let push: ServerPushModel?
    /// Server-side problems ("whoop_check.json fehlt"), shown in Mehr.
    let errors: [String]
    /// Context events (alcohol), additive field of Phase 2c.
    let events: DashboardEventsModel?
    /// Blood pressure tile (Build 4, optional; nil hides the tile).
    let bloodPressure: BloodPressureTileModel?
    /// Supplements / medications status (Build 4, optional).
    let intake: DashboardIntakeModel?

    /// Major schema version this app understands.
    static let supportedSchema = 1

    init(json: JSONValue) {
        schemaVersion = json.int("schema_version")
        generatedAt = BIOSDate.parse(json.str("generated_at"))
        freshness = json.list("freshness").enumerated().compactMap { FreshnessItem(json: $0.element, index: $0.offset) }
        infection = json.obj("infection").map { InfectionModel(json: $0) }
        outlook = json.obj("outlook").map { OutlookCardModel(json: $0) }
        environment = json.obj("environment").map { EnvironmentModel(json: $0) }
        push = json.obj("push").map { ServerPushModel(json: $0) }
        errors = json.strings("errors")
        events = json.obj("events").map { DashboardEventsModel(json: $0) }
        intake = json.obj("intake").map { DashboardIntakeModel(json: $0) }

        let tiles = json.obj("tiles")
        if let wien = tiles?.obj("viruses_wien") {
            virusesWien = VirusRegionModel(json: wien, key: "abwasser_wien")
        } else {
            virusesWien = environment?.viruses.first { $0.key == "abwasser_wien" }
        }
        if let pollenTile = tiles?.obj("pollen") {
            pollen = PollenModel(json: pollenTile)
        } else {
            pollen = environment?.pollen.first
        }
        glucose = tiles?.obj("glucose").map { GlucoseTileModel(json: $0) }
        recovery = tiles?.obj("recovery").map { RecoveryTileModel(json: $0) }
        insulin = tiles?.obj("insulin").map { InsulinTileModel(json: $0) }
        loop = tiles?.obj("loop").map { LoopTileModel(json: $0) }
        bloodPressure = (tiles?.obj("blood_pressure") ?? json.obj("blood_pressure")).map { BloodPressureTileModel(json: $0) }
    }

    var isNewerSchema: Bool {
        (schemaVersion ?? Self.supportedSchema) > Self.supportedSchema
    }
}

/// Mehr > Datenfrische.
struct FreshnessItem: Identifiable {
    let id: String
    let source: String
    let label: String
    let lastRaw: String?
    let last: Date?
    let ageMinutes: Int?
    let status: String
    let cadence: String?
    let note: String?

    init?(json: JSONValue, index: Int) {
        guard json.objectValue != nil else { return nil }
        source = json.str("source") ?? "quelle-\(index)"
        id = "\(index)-\(source)"
        label = json.str("label") ?? source
        lastRaw = json.str("last")
        last = BIOSDate.parse(lastRaw)
        ageMinutes = json.int("age_min")
        status = (json.str("status") ?? "missing").lowercased()
        cadence = json.str("cadence")
        note = json.str("note")
    }

    /// "heute 13:17" for timestamps, "Probe 23.09." for day-only values.
    var lastText: String {
        guard let lastRaw else { return "keine Daten" }
        if lastRaw.count == 10 {
            guard let day = BIOSDate.day(lastRaw) else { return lastRaw }
            return source.hasPrefix("abwasser") ? "Probe \(BIOSFormat.shortDate(day))" : BIOSFormat.shortDate(day)
        }
        if let last {
            return BIOSFormat.relative(last)
        }
        return lastRaw
    }
}

// MARK: - Hero: infection

struct InfectionChip: Identifiable {
    enum Role: String {
        case main
        case support
        case context
    }

    let id: Int
    let key: String
    let label: String
    let value: Double?
    let delta: Double?
    let deltaUnit: String?
    let display: String
    let role: Role
    /// "up", "down", "flat" or "" (no delta).
    let direction: String
    let flagged: Bool
    let evaluable: Bool
    let reason: String?

    init?(json: JSONValue, index: Int) {
        guard let label = json.str("label") ?? json.str("key") else { return nil }
        id = index
        key = json.str("key") ?? label
        self.label = label
        value = json.double("value")
        delta = json.double("delta")
        deltaUnit = json.str("delta_unit")
        role = Role(rawValue: (json.str("role") ?? "").lowercased()) ?? .support
        direction = (json.str("direction") ?? "").lowercased()
        flagged = json.flag("flagged")
        evaluable = json.flag("evaluable", fallback: true)
        reason = json.str("reason")
        if let display = json.str("display") {
            self.display = display
        } else if !evaluable {
            self.display = "n. b."
        } else if let delta {
            let unit = deltaUnit.map { $0 == "%" ? " %" : "" } ?? ""
            self.display = BIOSFormat.signed(delta, digits: abs(delta) < 10 && delta.rounded() != delta ? 1 : 0) + unit
        } else {
            self.display = "n. v."
        }
    }
}

struct GlucoseSignal {
    let evaluable: Bool
    let reason: String?
    let nightDelta: Double?
    let dayDelta: Double?
    let tarDelta: Double?
    let zNight: Double?
    let zDay: Double?
    let up: Bool

    init(json: JSONValue) {
        evaluable = json.flag("evaluable", fallback: true)
        reason = json.str("reason")
        nightDelta = json.double("night_delta")
        dayDelta = json.double("day_delta")
        tarDelta = json.double("tar_delta")
        zNight = json.double("z_night")
        zDay = json.double("z_day")
        up = json.flag("glu_up")
    }
}

struct InsulinSignal {
    let evaluable: Bool
    let reason: String?
    let tddDeltaPct: Double?
    let per10gDeltaPct: Double?
    let insAutoDelta: Double?
    let zTdd: Double?
    let zPer10g: Double?
    let up: Bool

    init(json: JSONValue) {
        evaluable = json.flag("evaluable", fallback: true)
        reason = json.str("reason")
        tddDeltaPct = json.double("tdd_delta_pct")
        per10gDeltaPct = json.double("p10_delta_pct")
        insAutoDelta = json.double("ins_auto_delta")
        zTdd = json.double("z_tdd")
        zPer10g = json.double("z_p10")
        up = json.flag("ins_up")
    }
}

struct InfectionBaseline {
    let days: Int?
    let rhr: Double?
    let hrv: Double?
    let skinTemp: Double?
    let respRate: Double?

    init(json: JSONValue) {
        days = json.int("days")
        rhr = json.double("rhr")
        hrv = json.double("hrv")
        skinTemp = json.double("skin_temp")
        respRate = json.double("resp_rate")
    }

    /// "Baseline 28 Tage · Ruhepuls 56 · HRV 68 ms"
    var footer: String? {
        var parts: [String] = []
        if let days { parts.append("Baseline \(days) Tage") } else { parts.append("Baseline") }
        if let rhr { parts.append("Ruhepuls \(BIOSFormat.number(rhr))") }
        if let hrv { parts.append("HRV \(BIOSFormat.number(hrv)) ms") }
        return parts.count > 1 ? parts.joined(separator: " · ") : nil
    }
}

struct InfectionDay: Identifiable {
    let date: String
    let rhr: Double?
    let hrv: Double?
    let recovery: Double?
    let flagged: Bool

    var id: String { date }

    init?(json: JSONValue) {
        guard let date = json.str("date") else { return nil }
        self.date = date
        rhr = json.double("rhr")
        hrv = json.double("hrv")
        recovery = json.double("recovery")
        flagged = json.flag("flagged")
    }
}

struct InfectionModel {
    let day: String?
    let checkedAt: Date?
    let evaluable: Bool
    let reason: String?
    let status: BIOSStatus
    let kind: String
    let headline: String
    let subline: String?
    let episodeDay: Int?
    let since: String?
    let alerts: [BIOSAlert]
    let recovery: Double?
    let recoveryZone: BIOSZone
    let chips: [InfectionChip]
    let resistUp: Bool
    let contextText: String?
    let glucose: GlucoseSignal?
    let insulin: InsulinSignal?
    let baseline: InfectionBaseline?
    let days: [InfectionDay]
    /// "Erholung gedrückt, vermutlich Alkohol/Training" (Phase 2c, optional).
    let confounderNote: String?
    /// Infekt-Score 0...100 (Build 4, optional); nil = hero shows Recovery.
    let score: Double?
    let scoreLevelKey: String?
    let scoreLevel: ScoreLevel
    let scoreParts: [ScorePart]
    /// "Passt zeitlich zu: COVID im Wiener Abwasser stark steigend".
    let envContext: String?
    /// "37,8 °C gemessen heute 07:40" (temperature entered in the app, only context).
    let temperatureContext: String?

    init(json: JSONValue) {
        day = json.str("day")
        checkedAt = BIOSDate.parse(json.str("checked_at"))
        evaluable = json.flag("evaluable", fallback: true)
        reason = json.str("reason")
        status = BIOSStatus(key: json.str("status"))
        kind = json.str("kind") ?? "none"
        subline = json.str("subline") ?? json.str("reason")
        episodeDay = json.int("episode_day")
        since = json.str("since")
        alerts = BIOSAlert.list(json.list("alerts"))
        recovery = json.double("recovery")
        recoveryZone = BIOSZone(key: json.str("recovery_zone"), value: recovery)
        chips = json.list("chips").enumerated().compactMap { InfectionChip(json: $0.element, index: $0.offset) }
        resistUp = json.flag("resist_up")
        contextText = json.str("context_text") ?? (json.flag("resist_up") ? "dazu Glukose/Insulinbedarf erhöht" : nil)
        glucose = json.obj("glucose_signal").map { GlucoseSignal(json: $0) }
        insulin = json.obj("insulin_signal").map { InsulinSignal(json: $0) }
        baseline = json.obj("baseline").map { InfectionBaseline(json: $0) }
        days = json.list("days").compactMap { InfectionDay(json: $0) }
        confounderNote = json.str("confounder_note")
            ?? json.obj("confounder")?.str("text")
            ?? json.str("confounder")
        let scoreValue = json.double("score") ?? json.obj("score")?.double("value")
        score = scoreValue.map { Swift.max(0, Swift.min(100, $0)) }
        scoreLevelKey = json.str("score_level") ?? json.obj("score")?.str("level")
        scoreLevel = ScoreLevel(key: scoreLevelKey, score: scoreValue)
        scoreParts = ScorePart.list(json["score_parts"] ?? json.obj("score")?["parts"])
        envContext = json.str("env_context") ?? json.obj("env_context")?.str("text")
        temperatureContext = json.str("temperature_context") ?? json.obj("temperature_context")?.str("text")
        if let headline = json.str("headline") {
            self.headline = headline
        } else {
            switch status {
            case .ok: self.headline = "Alles im Rahmen"
            case .info: self.headline = "Hinweis"
            case .warn: self.headline = "Auffällig"
            case .unknown: self.headline = "Keine Whoop-Daten"
            }
        }
    }
}

// MARK: - Outlook card

struct OutlookCardModel {
    let status: BIOSStatus
    let lines: [String]
    let generatedAt: Date?

    init(json: JSONValue) {
        status = BIOSStatus(key: json.str("status"))
        lines = json.strings("lines").filter { !$0.isEmpty }
        generatedAt = BIOSDate.parse(json.str("generated_at"))
    }
}

// MARK: - Viruses

struct VirusModel: Identifiable {
    let id: String
    let virus: String
    let metric: String
    let trend: String
    let trendFine: String
    let trendRatio: Double?
    /// 2 ... -2 matching `trend_fine` (arrow angle).
    let trendRank: Int?
    let level: String
    let levelRank: Int?
    let pctOfTypicalPeak: Double?
    let vsUsual: Double?
    let onsetKW: Int?
    let weeksUntilOnset: Int?

    init?(json: JSONValue) {
        guard let name = json.str("virus") else { return nil }
        virus = name
        metric = json.str("metric") ?? name
        id = metric
        trend = json.str("trend") ?? ""
        trendFine = json.str("trend_fine")
            ?? VirusModel.fineFromRank(json.int("trend_rank"))
            ?? VirusModel.fallbackFine(json.str("trend"))
        trendRatio = json.double("trend_ratio")
        trendRank = json.int("trend_rank")
        level = json.str("level") ?? "keine Daten"
        levelRank = json.int("level_rank")
        pctOfTypicalPeak = json.double("pct_of_typical_peak")
        vsUsual = json.double("vs_usual_this_week")
        onsetKW = json.int("typical_onset_kw")
        weeksUntilOnset = json.int("weeks_until_typical_onset")
    }

    private static func fineFromRank(_ rank: Int?) -> String? {
        guard let rank else { return nil }
        switch rank {
        case 2...: return "stark steigend"
        case 1: return "leicht steigend"
        case 0: return "gleich"
        case -1: return "leicht fallend"
        default: return "fallend"
        }
    }

    /// Older server without `trend_fine`: map the coarse trend.
    private static func fallbackFine(_ trend: String?) -> String {
        switch (trend ?? "").lowercased() {
        case "steigend": return "leicht steigend"
        case "fallend": return "leicht fallend"
        case "": return ""
        default: return "gleich"
        }
    }

    /// "1,4x so viel wie sonst um diese Zeit"
    var usualText: String? {
        guard let ratio = vsUsual, ratio > 0 else { return nil }
        if ratio >= 1 {
            return "\(BIOSFormat.number(ratio, digits: 1))x so viel wie sonst um diese Zeit"
        }
        return "\(BIOSFormat.number(1 / ratio, digits: 1))x weniger als sonst um diese Zeit"
    }
}

struct VirusRegionModel: Identifiable {
    let key: String
    let source: String
    let region: String
    let latestDate: String?
    let stale: Bool
    let unit: String?
    let viruses: [VirusModel]
    let evaluable: Bool
    let reason: String?

    var id: String { key }

    /// "gc/day" -> "Genkopien/Tag".
    var unitText: String? {
        guard let unit else { return nil }
        switch unit.lowercased() {
        case "gc/day", "gc/tag": return "Genkopien/Tag"
        case "gc/l": return "Genkopien/L"
        default: return unit
        }
    }

    init(json: JSONValue, key: String) {
        self.key = key
        source = json.str("source") ?? key
        region = json.str("region") ?? (key == "abwasser_wien" ? "Wien" : key == "abwasser_de" ? "Deutschland" : key)
        unit = json.str("unit")
        viruses = json.list("viruses").compactMap { VirusModel(json: $0) }
        stale = json.flag("stale")
        evaluable = json.flag("evaluable", fallback: true)
        reason = json.str("reason")
        // Region-level date, or the newest per-virus date (outlook.json shape).
        if let date = json.str("latest_date") {
            latestDate = date
        } else {
            latestDate = json.list("viruses").compactMap { $0.str("latest_date") }.max()
        }
    }

    var sampleText: String {
        guard let latestDate, let date = BIOSDate.day(latestDate) else { return "keine Probe" }
        return "Probe \(BIOSFormat.shortDate(date))" + (stale ? " (alt)" : "")
    }
}

// MARK: - Pollen

struct PollenDay: Identifiable {
    let id: String
    let date: Date?
    let mean: Double?
    let max: Double?
    let level: String
    let levelRank: Int

    init(json: JSONValue, index: Int) {
        let raw = json.str("date")
        id = raw ?? "tag-\(index)"
        date = BIOSDate.day(raw)
        mean = json.double("mean")
        max = json.double("max")
        let level = json.str("level") ?? "keine"
        self.level = level
        levelRank = json.int("level_rank") ?? PollenDay.rank(level)
    }

    static func rank(_ level: String) -> Int {
        switch level.lowercased() {
        case "niedrig": return 1
        case "mittel": return 2
        case "hoch", "sehr hoch": return 3
        default: return 0
        }
    }
}

struct PollenAllergen: Identifiable {
    let id: String
    let allergen: String
    let name: String
    let thresholdMittel: Double?
    let thresholdHoch: Double?
    let forecast: [PollenDay]
    let seasonStart: String?
    let seasonEnd: String?
    let inSeason: Bool
    let maxLevel: String?
    let maxLevelRank: Int?

    init?(json: JSONValue) {
        guard let allergen = json.str("allergen") ?? json.str("name") else { return nil }
        self.allergen = allergen
        id = allergen
        name = json.str("name") ?? allergen
        let thresholds = json.obj("thresholds")
        thresholdMittel = thresholds?.double("mittel")
        thresholdHoch = thresholds?.double("hoch")
        forecast = json.list("forecast").enumerated().map { PollenDay(json: $0.element, index: $0.offset) }
        let season = json.obj("season")
        seasonStart = season?.str("start")
        seasonEnd = season?.str("end")
        inSeason = json.flag("in_season")
        maxLevel = json.str("max_level")
        maxLevelRank = json.int("max_level_rank")
    }

    /// Highest forecast level as word (server `max_level`, else from the days).
    var maxLevelText: String {
        maxLevel ?? worstForecast?.level ?? "n. v."
    }

    /// Highest forecast level (by rank).
    var worstForecast: PollenDay? {
        forecast.max { $0.levelRank < $1.levelRank }
    }

    /// "15.05. bis 31.07." from "05-15" / "07-31".
    var seasonText: String? {
        guard let seasonStart, let seasonEnd else { return nil }
        return "\(Self.monthDay(seasonStart)) bis \(Self.monthDay(seasonEnd))"
    }

    private static func monthDay(_ raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 2 else { return raw }
        return "\(parts[1]).\(parts[0])."
    }
}

struct AllergyModel {
    let active: Bool
    let place: String?
    let allergens: [String]
    let reasons: [String]

    init(json: JSONValue) {
        active = json.flag("active")
        place = json.str("place")
        var names = json.strings("allergens")
        if names.isEmpty {
            names = json.list("allergens").compactMap { $0.str("name") ?? $0.str("allergen") }
        }
        allergens = names
        reasons = json.strings("reasons")
    }
}

struct PollenModel: Identifiable {
    let place: String
    let allergens: [PollenAllergen]
    let allergy: AllergyModel?
    let generatedAt: Date?
    let evaluable: Bool
    let reason: String?

    var id: String { place }

    init(json: JSONValue) {
        place = json.str("place") ?? "Heimatort"
        allergens = json.list("allergens").compactMap { PollenAllergen(json: $0) }
        allergy = json.obj("allergy").map { AllergyModel(json: $0) }
        generatedAt = BIOSDate.parse(json.str("generated_at"))
        evaluable = json.flag("evaluable", fallback: true)
        reason = json.str("reason")
    }

    /// Forecast dates of the first allergen (column headers).
    var forecastDates: [Date?] {
        allergens.first?.forecast.map { $0.date } ?? []
    }
}

// MARK: - Tiles

struct GlucoseTileModel {
    let evaluable: Bool
    let reason: String?
    let lastTs: Date?
    let coverage24h: Double?
    let tir: Double?
    let tbr: Double?
    let tar: Double?
    let mean: Double?
    let cv: Double?
    let gmi: Double?
    let nightMean: Double?
    let spark: [Double?]
    let sparkStart: Date?
    let targetLow: Double
    let targetHigh: Double
    let up: Bool
    let sources: [String]

    init(json: JSONValue) {
        evaluable = json.flag("evaluable", fallback: true)
        reason = json.str("reason")
        lastTs = BIOSDate.parse(json.str("last_ts"))
        coverage24h = json.double("coverage_24h")
        tir = json.double("tir_24h")
        tbr = json.double("tbr_24h")
        tar = json.double("tar_24h")
        mean = json.double("mean_24h")
        cv = json.double("cv_24h")
        gmi = json.double("gmi_24h")
        nightMean = json.double("night_mean")
        spark = json.optionalNumbers("spark_24h")
        sparkStart = BIOSDate.parse(json.str("spark_start"))
        let target = json.list("target").compactMap { $0.finiteNumber }
        targetLow = target.count == 2 ? target[0] : 70
        targetHigh = target.count == 2 ? target[1] : 180
        up = json.flag("up")
        sources = json.strings("sources")
    }

    var sourcesText: String {
        let names = sources.map { source -> String in
            switch source {
            case "dexcom_share": return "Dexcom"
            case "loop": return "Loop"
            case "apple_health": return "Apple Health"
            default: return source
            }
        }
        return names.isEmpty ? "n. v." : names.joined(separator: ", ")
    }
}

struct RecoveryTileModel {
    let date: String?
    let evaluable: Bool
    let reason: String?
    let recovery: Double?
    let zone: BIOSZone
    let sleepHours: Double?
    let hrv: Double?
    let rhr: Double?
    let respRate: Double?
    /// Main sleep + naps (additive `sleep` block), nil on older servers.
    let sleep: SleepBreakdown?

    init(json: JSONValue) {
        date = json.str("date")
        evaluable = json.flag("evaluable", fallback: true)
        reason = json.str("reason")
        recovery = json.double("recovery")
        zone = BIOSZone(key: json.str("zone"), value: recovery)
        sleepHours = json.double("sleep_h")
        hrv = json.double("hrv")
        rhr = json.double("rhr")
        respRate = json.double("resp_rate")
        sleep = SleepBreakdown(json: json.obj("sleep"))
    }

    /// Main sleep in hours (block first, then the older `sleep_h`).
    var mainSleepHours: Double? {
        sleep?.mainH ?? sleepHours
    }

    /// "Nacht auf Fr"
    var nightText: String {
        guard let day = BIOSDate.day(date) else { return "letzte Nacht" }
        return "Nacht auf \(BIOSFormat.weekdayShort(day))"
    }
}

/// `tiles.recovery.sleep`: main sleep, naps and total of the Whoop day.
struct SleepBreakdown {
    struct Nap: Identifiable {
        let id: Int
        let start: Date?
        let end: Date?
        let hours: Double?

        var text: String {
            var parts: [String] = []
            if let start {
                parts.append(end.map { "\(BIOSFormat.time(start)) bis \(BIOSFormat.time($0))" } ?? BIOSFormat.time(start))
            }
            if let hours { parts.append(SleepBreakdown.duration(hours)) }
            return parts.joined(separator: " · ")
        }
    }

    let mainH: Double?
    let napsH: Double?
    let totalH: Double?
    let naps: [Nap]

    init?(json: JSONValue?) {
        guard let json else { return nil }
        let main = json.double("main_h") ?? json.double("main")
        mainH = main
        var naps: [Nap] = []
        for element in json.list("naps") {
            let start = BIOSDate.parse(element.str("start"))
            let end = BIOSDate.parse(element.str("end"))
            var hours = element.double("h") ?? element.double("duration_h") ?? element.double("hours")
                ?? element.double("minutes").map { $0 / 60 }
            if hours == nil, let start, let end { hours = end.timeIntervalSince(start) / 3_600 }
            naps.append(Nap(id: naps.count, start: start, end: end, hours: hours))
        }
        self.naps = naps
        let napHours = json.double("naps_h") ?? (naps.isEmpty ? nil : naps.compactMap(\.hours).reduce(0, +))
        napsH = napHours
        let total = json.double("total_h") ?? main.map { $0 + (napHours ?? 0) }
        totalH = total
        if main == nil, total == nil { return nil }
    }

    var hasNaps: Bool {
        (napsH ?? 0) > 0.01 || !naps.isEmpty
    }

    /// "7:25 h" style is ambiguous in German; decimal hours with one digit.
    static func duration(_ hours: Double) -> String {
        hours < 1 ? "\(BIOSFormat.number(hours * 60)) min" : "\(BIOSFormat.number(hours, digits: 1)) h"
    }
}

struct InsulinTileModel {
    let date: String?
    let evaluable: Bool
    let reason: String?
    let tdd: Double?
    let tddBaseline: Double?
    let tddDeltaPct: Double?
    let per10g: Double?
    let per10gBaseline: Double?
    let per10gDeltaPct: Double?
    let insAuto: Double?
    let carbs: Double?
    let tddLast7: [Double?]
    let basalSource: String?
    let up: Bool

    init(json: JSONValue) {
        date = json.str("date")
        evaluable = json.flag("evaluable", fallback: true)
        reason = json.str("reason")
        tdd = json.double("tdd")
        tddBaseline = json.double("tdd_baseline")
        tddDeltaPct = json.double("tdd_delta_pct")
        per10g = json.double("per_10g_carbs")
        per10gBaseline = json.double("per_10g_baseline")
        per10gDeltaPct = json.double("per_10g_delta_pct")
        insAuto = json.double("ins_auto")
        carbs = json.double("carbs_g")
        tddLast7 = json.optionalNumbers("tdd_last7")
        basalSource = json.str("basal_source")
        up = json.flag("up")
    }

    /// Server key -> German note.
    var basalNote: String {
        switch (basalSource ?? "reconstructed").lowercased() {
        case "apple_health":
            return "Basal aus dem Apple-Health-Export."
        case "reconstructed", "rekonstruiert":
            return "Basal rekonstruiert aus Loop-Profil und Temp-Basals (Abweichung ca. 2 %)."
        default:
            return "Basal: \(basalSource ?? "unbekannt")."
        }
    }

    /// "Gestern, 24.09."
    var dayText: String {
        guard let day = BIOSDate.day(date) else { return "Vortag" }
        let relative = BIOSFormat.relativeDay(date)
        if relative == "gestern" { return "Gestern, \(BIOSFormat.shortDate(day))" }
        return BIOSFormat.dayLabel(day)
    }
}

struct LoopTileModel {
    let evaluable: Bool
    let reason: String?
    let lastTs: Date?
    let lastCgmTs: Date?
    let lastGlucose: Double?
    let cgmStale: Bool
    let iob: Double?
    let cob: Double?
    let tempBasalRate: Double?
    let lastSensorChange: Date?

    init(json: JSONValue) {
        evaluable = json.flag("evaluable", fallback: true)
        reason = json.str("reason")
        lastTs = BIOSDate.parse(json.str("last_ts"))
        lastCgmTs = BIOSDate.parse(json.str("last_cgm_ts"))
        lastGlucose = json.double("last_glucose")
        cgmStale = json.flag("cgm_stale")
        iob = json.double("iob")
        cob = json.double("cob")
        tempBasalRate = json.double("temp_basal_rate")
        lastSensorChange = BIOSDate.parse(json.str("last_sensor_change"))
    }
}

// MARK: - Umwelt

struct EnvironmentModel {
    let season: String?
    let viruses: [VirusRegionModel]
    let pollen: [PollenModel]
    let allergy: AllergyModel?
    let hints: [BIOSAlert]

    init(json: JSONValue) {
        season = json.str("season")
        let sources = json.obj("viruses")?.objectValue ?? [:]
        let keys = sources.keys.sorted { lhs, rhs in
            let left = lhs == "abwasser_wien" ? 0 : 1
            let right = rhs == "abwasser_wien" ? 0 : 1
            return left == right ? lhs < rhs : left < right
        }
        var regions: [VirusRegionModel] = []
        for key in keys {
            guard let value = sources[key], value.objectValue != nil else { continue }
            regions.append(VirusRegionModel(json: value, key: key))
        }
        viruses = regions
        pollen = json.list("pollen").filter { $0.objectValue != nil }.map { PollenModel(json: $0) }
        allergy = json.obj("allergy").map { AllergyModel(json: $0) }
        hints = BIOSAlert.list(json.list("hints"))
    }
}

// MARK: - Events

/// Dashboard `events` block (additive, lenient): today/yesterday marks and
/// recent alcohol days (strings or `{date}` objects).
struct DashboardEventsModel {
    let todayMarked: Bool?
    let yesterdayMarked: Bool?
    let alcoholRecent: [String]

    init(json: JSONValue) {
        todayMarked = json["today_marked"]?.boolValue
        yesterdayMarked = json["yesterday_marked"]?.boolValue
        var days: [String] = json.strings("alcohol_recent")
        if days.isEmpty {
            days = json.list("alcohol_recent").compactMap { $0.str("date") }
        }
        alcoholRecent = days.map { String($0.prefix(10)) }
    }
}

// MARK: - Mehr

struct ServerPushModel {
    struct Last {
        let title: String
        let body: String
        let sentAt: Date?
        let threadID: String?
        let tab: String?
    }

    let last: Last?
    let devices: Int?
    let testPushAvailable: Bool

    init(json: JSONValue) {
        if let last = json.obj("last") {
            self.last = Last(
                title: last.str("title") ?? "(ohne Titel)",
                body: last.str("body") ?? "",
                sentAt: BIOSDate.parse(last.str("sent_at")),
                threadID: last.str("thread_id"),
                tab: last.str("tab")
            )
        } else {
            self.last = nil
        }
        devices = json.int("devices")
        testPushAvailable = json.flag("test_push_available")
    }
}
