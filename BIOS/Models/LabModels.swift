import Foundation

// Labor (`/v1/labs`, Phase V4). Lenient like every other model: each field is
// optional, unknown fields are ignored, wrong types fall back to nil/defaults,
// so a newer server never breaks the tab. Contract: docs/API_v1.md (BIOS repo),
// section "Labor"; examples docs/fixtures/labs_*.json (invented values).
// Lab values are shown as observation only; they never color the body map.

// MARK: - Status words

/// `status` of a value or point: position against the lab's own reference.
enum LabValueStatus: String {
    case normal
    case hoch
    case niedrig
    case auffaellig
    case keineReferenz = "keine_referenz"
    case unknown

    init(raw: String?) {
        self = LabValueStatus(rawValue: (raw ?? "").lowercased()) ?? .unknown
    }

    /// Outside the lab's reference (or flagged by the lab).
    var isFlagged: Bool {
        self == .hoch || self == .niedrig || self == .auffaellig
    }

    /// Tag text next to the value ("hoch"), nil when nothing needs saying.
    var tag: String? {
        switch self {
        case .hoch: return "hoch"
        case .niedrig: return "niedrig"
        case .auffaellig: return "auffällig"
        case .keineReferenz: return "ohne Referenz"
        case .normal, .unknown: return nil
        }
    }

    /// Spoken form for VoiceOver.
    var spoken: String {
        switch self {
        case .normal: return "im Referenzbereich"
        case .hoch: return "über dem Referenzbereich"
        case .niedrig: return "unter dem Referenzbereich"
        case .auffaellig: return "vom Labor markiert"
        case .keineReferenz: return "ohne Referenzbereich"
        case .unknown: return ""
        }
    }
}

/// Document `status`.
enum LabDocumentStatus: String {
    case waiting = "wartet_auf_extraktion"
    case review = "zu_pruefen"
    case confirmed = "bestaetigt"
    case discarded = "verworfen"
    case failed = "fehler"
    /// A later confirmed document holds the same values (file and values kept, hidden
    /// from overview and history; undo with `restore`).
    case superseded = "ersetzt"
    case unknown

    init(raw: String?) {
        self = LabDocumentStatus(rawValue: (raw ?? "").lowercased()) ?? .unknown
    }

    var label: String {
        switch self {
        case .waiting: return "wird ausgewertet"
        case .review: return "zu prüfen"
        case .confirmed: return "bestätigt"
        case .discarded: return "verworfen"
        case .failed: return "Fehler"
        case .superseded: return "ersetzt"
        case .unknown: return "unbekannt"
        }
    }
}

/// Document kinds with German labels and symbols (fallback when the server
/// sends no `kind_label`).
struct LabKindOption: Identifiable, Equatable {
    let id: String
    let label: String
}

enum LabKind {
    static let all: [LabKindOption] = [
        LabKindOption(id: "blut", label: "Labor"),
        LabKindOption(id: "spiro", label: "Spirometrie"),
        LabKindOption(id: "dexa", label: "DEXA"),
        LabKindOption(id: "schlaf", label: "Schlafmessung"),
        LabKindOption(id: "brief", label: "Arztbrief"),
        LabKindOption(id: "sonstiges", label: "Sonstiges"),
    ]

    static func label(_ id: String?) -> String? {
        guard let id else { return nil }
        return all.first { $0.id == id }?.label
    }

    static func symbol(_ id: String?) -> String {
        switch id ?? "" {
        case "blut": return "drop"
        case "spiro": return "lungs"
        case "dexa": return "figure.stand"
        case "schlaf": return "moon.zzz"
        case "brief": return "doc.text"
        default: return "doc"
        }
    }
}

/// Review reasons of an extracted value (yellow in the review screen).
enum LabReviewReason {
    static func text(_ raw: String) -> String {
        switch raw {
        case "nicht_zugeordnet": return "keinem Marker zugeordnet"
        case "einheit_unbekannt": return "Einheit unbekannt"
        case "kein_wert": return "kein Zahlenwert erkannt"
        case "unsicher": return "unsicher erkannt"
        default: return raw.replacingOccurrences(of: "_", with: " ")
        }
    }
}

// MARK: - Points and markers

/// GMI from the CGM, 90 days up to a lab date (`history[].gmi`, `links[]`).
struct LabGMI: Equatable {
    let kind: String?
    let label: String?
    let days: Int?
    let from: String?
    let to: String?
    let unit: String?
    let value: Double?
    let tirPct: Double?
    let coveragePct: Double?
    let evaluable: Bool
    let reason: String?

    init?(json: JSONValue?) {
        guard let json, json.objectValue != nil else { return nil }
        kind = json.str("kind")
        label = json.str("label")
        days = json.int("days")
        from = json.str("from")
        to = json.str("to")
        unit = json.str("unit")
        value = json.double("value")
        tirPct = json.double("tir_pct")
        coveragePct = json.double("coverage_pct")
        evaluable = json.flag("evaluable", fallback: json.double("value") != nil)
        reason = json.str("reason")
    }
}

/// One measurement of a marker (`Point`): canonical unit where convertible.
struct LabPoint: Identifiable, Equatable {
    let id: String
    let dateRaw: String?
    let date: Date?
    let value: Double?
    let unit: String?
    let converted: Bool
    let comparator: String?
    let valueText: String?
    let valueRaw: Double?
    let unitRaw: String?
    let status: LabValueStatus
    let statusBasis: String?
    let refLow: Double?
    let refHigh: Double?
    let refText: String?
    let labFlag: String?
    let zScore: Double?
    let pctPredicted: Double?
    let documentID: String?
    let resultID: String?
    let gmi: LabGMI?
    /// Device markers (fingerstick): local time of the measurement (several per day).
    let measuredAt: Date?
    /// Device markers: "dexcom_kalibrierung", "dexcom_ereignis", "loop_kalibrierung".
    let origin: String?
    /// "aus Dexcom-Kalibrierung" etc.
    let originLabel: String?
    /// Merged "Blutzucker": "labor", "fingerstich" or "ambulanz".
    let originGroup: String?
    /// "Labor", "Fingerstich (Kalibrierung)", "Ambulanz".
    let originGroupLabel: String?
    /// Capillary value (fingerstick or letter "BZ"): never a lab reference.
    let capillary: Bool
    /// Inside the target band (true), outside (false), undecidable or no band (nil).
    let inTarget: Bool?

    init?(json: JSONValue?, index: Int = 0) {
        guard let json, json.objectValue != nil else { return nil }
        dateRaw = json.str("date")
        date = BIOSDate.day(dateRaw)
        value = json.double("value")
        unit = json.str("unit")
        converted = json.flag("converted")
        comparator = json.str("comparator")
        valueText = json.str("value_text")
        valueRaw = json.double("value_raw")
        unitRaw = json.str("unit_raw")
        status = LabValueStatus(raw: json.str("status"))
        statusBasis = json.str("status_basis")
        refLow = json.double("ref_low")
        refHigh = json.double("ref_high")
        refText = json.str("ref_text")
        labFlag = json.str("lab_flag")
        zScore = json.double("z_score")
        pctPredicted = json.double("pct_predicted")
        documentID = json.str("document_id")
        resultID = json.str("result_id")
        gmi = LabGMI(json: json.obj("gmi"))
        let measuredRaw = json.str("measured_at")
        // A bare day would land at noon and pretend a time of day.
        measuredAt = (measuredRaw?.count ?? 0) > 10 ? BIOSDate.parse(measuredRaw) : nil
        origin = json.str("origin")
        originLabel = json.str("origin_label")
        originGroup = json.str("origin_group")
        originGroupLabel = json.str("origin_group_label")
        capillary = json.flag("capillary")
        inTarget = json["in_target"]?.boolValue
        id = resultID ?? "\(measuredRaw ?? dateRaw ?? "punkt")-\(index)"
    }

    /// Point of the merged marker measured by a lab (has the lab's range).
    var isLabOrigin: Bool { originGroup == "labor" }

    /// "Fingerstich (Kalibrierung)" / "Labor" / origin label, for rows and captions.
    var originText: String? { originGroupLabel ?? originLabel }

    /// Time of the measurement, else the day (noon).
    var when: Date? { measuredAt ?? date }

    /// Spirometry and similar: judged by the z-score (LLN -1,645).
    var usesZScore: Bool {
        statusBasis == "z" && zScore != nil
    }
}

/// `target` of a marker: the evidence-based target band ("Zielbereich", since
/// 2026-09-28, from guidelines or the lab profile), e.g. LDL "Ziel unter 70 mg/dL".
/// Older servers send only `{low, high, unit, status}`; every other field is optional.
/// Independent of the lab's own reference status.
struct LabTarget: Equatable {
    /// HbA1c: the best possible range inside the target ("bestmöglich 6,0 bis 6,5 %").
    struct Best: Equatable {
        let low: Double?
        let high: Double?
        let label: String?
    }

    let low: Double?
    let high: Double?
    let unit: String?
    /// "im_ziel", "ueber_ziel", "unter_ziel" or nil (against the newest value).
    let status: String?
    /// "Ziel unter 70 mg/dL", "Hinweis: ab 0,85 mmol/L".
    let label: String?
    let source: String?
    let url: URL?
    /// "leitlinie", "konsens", "hinweis".
    let evidence: String?
    let evidenceLabel: String?
    let why: String?
    /// "moderat", "hoch", "sehr_hoch" (ESC/EAS, LDL, non-HDL, ApoB only).
    let tier: String?
    let tierLabel: String?
    let note: String?
    /// "evidenz" or "profil".
    let origin: String?
    let lowInclusive: Bool
    let highInclusive: Bool
    /// true = narrower than usual lab ranges, false = mostly the same (the band is
    /// skipped, a tick stays), nil = depends on the lab (drawn).
    let addsOverReference: Bool?
    /// Glucose, HbA1c in type 1: the target lies partly outside the lab range.
    let extendsBeyondReference: Bool
    let best: Best?

    init?(json: JSONValue?) {
        guard let json, json.objectValue != nil else { return nil }
        low = json.double("low")
        high = json.double("high")
        unit = json.str("unit")
        status = json.str("status")
        label = json.str("label")
        source = json.str("source")
        url = json.str("url").flatMap { raw -> URL? in
            guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else { return nil }
            return url
        }
        evidence = json.str("evidence")?.lowercased()
        evidenceLabel = json.str("evidence_label")
        why = json.str("why")
        tier = json.str("tier")
        tierLabel = json.str("tier_label")
        note = json.str("note")
        origin = json.str("origin")
        lowInclusive = json.flag("low_inclusive", fallback: true)
        highInclusive = json.flag("high_inclusive", fallback: false)
        addsOverReference = json["adds_over_reference"]?.boolValue
        extendsBeyondReference = json.flag("extends_beyond_reference")
        if let raw = json.obj("best"), raw.double("low") != nil || raw.double("high") != nil {
            best = Best(low: raw.double("low"), high: raw.double("high"), label: raw.str("label"))
        } else {
            best = nil
        }
        if low == nil && high == nil { return nil }
    }

    /// The tick on the reference bar (upper goal first), used when no band is drawn.
    var tick: Double? { high ?? low }

    /// Observational data only (magnesium): drawn hatched and lighter, never called a goal.
    var isHint: Bool { evidence == "hinweis" }

    /// Draw the target band: skipped only when the server says it matches the lab range.
    var drawsBand: Bool { addsOverReference != false }

    /// Bounds that widen a chart scale (target and best band).
    var scaleBounds: [Double] {
        [low, high, best?.low, best?.high].compactMap { $0 }.filter(\.isFinite)
    }

    /// Target band clipped to a visible scale (an open side runs to the edge).
    func band(in range: ClosedRange<Double>) -> (low: Double, high: Double)? {
        Self.clip(low: low, high: high, to: range)
    }

    /// HbA1c best band clipped to a visible scale.
    func bestBand(in range: ClosedRange<Double>) -> (low: Double, high: Double)? {
        guard let best, best.low != nil || best.high != nil else { return nil }
        return Self.clip(low: best.low, high: best.high, to: range)
    }

    static func clip(low: Double?, high: Double?, to range: ClosedRange<Double>) -> (low: Double, high: Double)? {
        let clippedLow = max(range.lowerBound, low ?? range.lowerBound)
        let clippedHigh = min(range.upperBound, high ?? range.upperBound)
        return clippedHigh > clippedLow ? (clippedLow, clippedHigh) : nil
    }

    /// In target from `status` (older servers without `Point.in_target`; newest value only).
    var statusInTarget: Bool? {
        switch status ?? "" {
        case "im_ziel": return true
        case "ueber_ziel", "unter_ziel": return false
        default: return nil
        }
    }

    /// "im Ziel" / "außerhalb Ziel" / "knapp außerhalb" for a point, nil when undecidable.
    func judgement(inTarget: Bool?, value: Double?) -> String? {
        guard let inTarget else { return nil }
        if inTarget { return isHint ? "im Hinweisbereich" : "im Ziel" }
        if let value, isClose(value) { return "knapp außerhalb" }
        return isHint ? "außerhalb Hinweisbereich" : "außerhalb Ziel"
    }

    /// Outside, but within 5 % of the nearest bound (70 against "unter 70").
    func isClose(_ value: Double) -> Bool {
        let bounds = [low, high].compactMap { $0 }
        guard let nearest = bounds.min(by: { abs($0 - value) < abs($1 - value) }) else { return false }
        return abs(value - nearest) <= max(abs(nearest) * 0.05, 1e-9)
    }

    /// Label with a fallback for older servers ("Ziel 4,0 bis 6,0 %").
    func displayLabel(decimals: Int?) -> String {
        if let label { return label }
        let range = LabFormat.refRange(low: low, high: high, decimals: decimals, unit: unit) ?? ""
        return (isHint ? "Hinweis: " : "Ziel ") + range
    }

    /// VoiceOver: "Ziel unter 70 mg/dL, Wert 70, knapp außerhalb".
    func spokenLine(decimals: Int?, value: Double?, valueText: String, inTarget: Bool?) -> String {
        var text = "\(displayLabel(decimals: decimals)), Wert \(valueText)"
        if let judgement = judgement(inTarget: inTarget, value: value) { text += ", \(judgement)" }
        return text
    }

    /// "Leitlinie", "Konsens", "Hinweis (nur Beobachtungsdaten)".
    var evidenceText: String? {
        if let evidenceLabel { return evidenceLabel }
        switch evidence ?? "" {
        case "leitlinie": return "Leitlinie"
        case "konsens": return "Konsens"
        case "hinweis": return "Hinweis (nur Beobachtungsdaten)"
        default: return nil
        }
    }

    var statusText: String? {
        switch status ?? "" {
        case "im_ziel": return "im Ziel"
        case "ueber_ziel": return "über Ziel"
        case "unter_ziel": return "unter Ziel"
        default: return nil
        }
    }

    /// Target and point unit agree (or one is unknown): band and value share a scale.
    func matches(unit pointUnit: String?) -> Bool {
        guard let unit, let pointUnit else { return true }
        return unit.lowercased() == pointUnit.lowercased()
    }
}

/// `targets` of the overview: counts for the chip "7 von 9 im Zielbereich".
struct LabTargetSummary: Equatable {
    let nTarget: Int
    let nInTarget: Int
    let nOutside: Int
    let label: String?
    let riskTier: String?
    let riskTierLabel: String?
    let diabetesSince: Int?
    let note: String?

    init?(json: JSONValue?) {
        guard let json, json.objectValue != nil else { return nil }
        nTarget = json.int("n_target") ?? 0
        nInTarget = json.int("n_in_target") ?? 0
        nOutside = json.int("n_outside") ?? max(0, nTarget - nInTarget)
        label = json.str("label")
        riskTier = json.str("risk_tier")
        riskTierLabel = json.str("risk_tier_label")
        diabetesSince = json.int("diabetes_since")
        note = json.str("note")
    }

    /// Counted in the app (server without the `targets` block).
    init(nTarget: Int, nInTarget: Int) {
        self.nTarget = nTarget
        self.nInTarget = nInTarget
        nOutside = max(0, nTarget - nInTarget)
        label = nil
        riskTier = nil
        riskTierLabel = nil
        diabetesSince = nil
        note = nil
    }

    /// "16 von 18 im Zielbereich", nil without any decidable marker.
    var chipText: String? {
        if let label { return label }
        guard nTarget > 0 else { return nil }
        return "\(nInTarget) von \(nTarget) im Zielbereich"
    }
}

struct LabSparkPoint: Equatable {
    let date: Date?
    let value: Double
    /// Device markers only: time of the measurement.
    var measuredAt: Date? = nil
}

/// `kind` of a marker: lab value (default) or a device reading.
enum LabMarkerKind {
    /// "messgeraet": fingerstick from the meter, no lab, no reference range.
    static let device = "messgeraet"
    /// "kombiniert": the merged "Blutzucker" (lab glucose, fingersticks, letter values).
    static let combined = "kombiniert"

    static func isDevice(_ kind: String?) -> Bool {
        (kind ?? "").lowercased() == device
    }

    static func isCombined(_ kind: String?) -> Bool {
        (kind ?? "").lowercased() == combined
    }
}

/// `parts[]` of the merged marker: how many values per origin.
struct LabMergedPart: Identifiable, Equatable {
    let id: String
    let label: String
    let nValues: Int
    let lastDate: String?

    init?(json: JSONValue) {
        guard let id = json.str("origin_group") else { return nil }
        self.id = id
        label = json.str("label") ?? id
        nValues = json.int("n_values") ?? 0
        lastDate = json.str("last_date")
    }
}

/// `MarkerEntry` of the overview.
struct LabMarkerEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let unit: String?
    let decimals: Int
    let custom: Bool
    let latest: LabPoint?
    let previous: LabPoint?
    let sparkline: [LabSparkPoint]
    let nValues: Int
    let target: LabTarget?
    /// `kind` ("messgeraet" for the fingerstick), nil for lab markers.
    let kind: String?
    /// "aus Dexcom-Kalibrierung": shown instead of the reference bar.
    let sourceLabel: String?
    /// Merged "Blutzucker": newest lab point (with the lab's range), nil otherwise.
    let latestLab: LabPoint?
    /// Merged "Blutzucker": values per origin.
    let parts: [LabMergedPart]

    init?(json: JSONValue) {
        guard let id = json.str("id") else { return nil }
        self.id = id
        name = json.str("name") ?? id
        unit = json.str("unit")
        decimals = max(0, min(4, json.int("decimals") ?? 1))
        custom = json.flag("custom")
        latest = LabPoint(json: json.obj("latest"))
        previous = LabPoint(json: json.obj("previous"))
        latestLab = LabPoint(json: json.obj("latest_lab"))
        parts = json.list("parts").compactMap { LabMergedPart(json: $0) }
        sparkline = json.list("sparkline").compactMap { point in
            guard let value = point.double("value") else { return nil }
            let measured = point.str("measured_at")
            return LabSparkPoint(date: BIOSDate.day(point.str("date")), value: value,
                                 measuredAt: (measured?.count ?? 0) > 10 ? BIOSDate.parse(measured) : nil)
        }
        nValues = json.int("n_values") ?? sparkline.count
        target = LabTarget(json: json.obj("target"))
        kind = json.str("kind")
        sourceLabel = json.str("source_label") ?? latest?.originLabel
    }

    /// A device reading (fingerstick): no reference, never flagged.
    var isDevice: Bool { LabMarkerKind.isDevice(kind) }

    /// The merged "Blutzucker" (lab, fingerstick and clinic values in one series).
    var isCombined: Bool { LabMarkerKind.isCombined(kind) }

    /// The point that stands for this marker's lab status (merged: the newest lab point).
    var statusPoint: LabPoint? { isCombined ? latestLab : latest }
}

/// A group of the overview ("Stoffwechsel", "Blutfette", ...).
struct LabGroup: Identifiable, Equatable {
    let id: String
    let label: String
    /// Body map region id for a neutral link (never a color).
    let region: String?
    let nMarkers: Int
    let nFlagged: Int
    /// Markers with a decidable `latest.in_target`, and how many of them are inside.
    let nTarget: Int
    let nInTarget: Int
    let markers: [LabMarkerEntry]

    init?(json: JSONValue) {
        guard let id = json.str("id") else { return nil }
        self.id = id
        label = json.str("label") ?? id
        region = json.str("region")
        markers = json.list("markers").compactMap { LabMarkerEntry(json: $0) }
        nMarkers = json.int("n_markers") ?? markers.count
        nFlagged = json.int("n_flagged") ?? markers.filter { $0.latest?.status.isFlagged == true }.count
        let decidable = markers.filter { !$0.isDevice && $0.latest?.inTarget != nil }
        nTarget = json.int("n_target") ?? decidable.count
        nInTarget = min(nTarget, json.int("n_in_target") ?? decidable.filter { $0.latest?.inTarget == true }.count)
    }
}

/// One entry of the "Fällig" list.
struct LabDue: Identifiable, Equatable {
    let id: String
    let label: String
    /// Marker ids covered by this entry ("niere" -> creatinine, egfr).
    let markers: [String]
    let months: Int?
    let lastOn: String?
    let dueOn: String?
    let daysUntil: Int?
    /// "faellig", "unbekannt", "bald", "ok".
    let status: String

    init?(json: JSONValue) {
        guard let id = json.str("id") else { return nil }
        self.id = id
        label = json.str("label") ?? id
        markers = json.strings("markers")
        months = json.int("months")
        lastOn = json.str("last_on")
        dueOn = json.str("due_on")
        daysUntil = json.int("days_until")
        status = json.str("status")?.lowercased() ?? "ok"
    }

    /// Needs attention: due now or soon, or never measured.
    var isOpen: Bool {
        status == "faellig" || status == "bald" || status == "unbekannt"
    }

    /// "alle 3 Monate · zuletzt 15.09.2026" / "jährlich · noch kein Wert".
    var subline: String {
        var parts: [String] = []
        if let months, months > 0 {
            parts.append(months == 12 ? "jährlich" : (months == 1 ? "monatlich" : "alle \(months) Monate"))
        }
        if let last = BIOSDate.day(lastOn) {
            parts.append("zuletzt \(LabFormat.fullDate(last))")
        } else {
            parts.append("noch kein Wert")
        }
        return parts.joined(separator: " · ")
    }

    /// Tag on the right: "seit 3 Wochen", "heute", "in 12 Tagen", "15.12.", "noch nie".
    var tagText: String {
        switch status {
        case "unbekannt":
            return "noch nie"
        case "faellig":
            guard let days = daysUntil else { return "fällig" }
            if days >= 0 { return "fällig" }
            return "seit " + LabFormat.span(days: -days)
        case "bald":
            guard let days = daysUntil else { return "bald" }
            if days <= 0 { return "fällig" }
            return "in " + LabFormat.span(days: days)
        default:
            if let due = BIOSDate.day(dueOn) {
                return BIOSFormat.shortDate(due)
            }
            return "ok"
        }
    }
}

/// `review` of overview and document list.
struct LabReviewSummary: Equatable {
    let documents: Int
    let values: Int
    let flaggedValues: Int
    let waiting: Int
    let waitingReason: String?
    let errors: Int

    static let empty = LabReviewSummary(json: nil)

    init(json: JSONValue?) {
        documents = json?.int("documents") ?? 0
        values = json?.int("values") ?? 0
        flaggedValues = json?.int("flagged_values") ?? 0
        waiting = json?.int("waiting") ?? 0
        waitingReason = json?.str("waiting_reason")
        errors = json?.int("errors") ?? 0
    }
}

/// `GET /v1/labs`: segment "Werte".
struct LabOverview: Equatable {
    let schemaVersion: Int?
    let generatedAt: Date?
    let disclaimer: String?
    let due: [LabDue]
    let groups: [LabGroup]
    let review: LabReviewSummary
    /// Body map region id -> group ids (for the neutral link from a region).
    let regions: [String: [String]]
    let nValues: Int
    let lastValueOn: String?
    /// Number of fingerstick readings (device marker), additive.
    let nDeviceValues: Int
    let ownMeasurements: LabOwnMeasurements?
    /// Chip "7 von 9 im Zielbereich" (`targets`, additive since 2026-09-28; counted
    /// from the groups when the block is missing, nil without any decidable marker).
    let targets: LabTargetSummary?

    init(json: JSONValue) {
        schemaVersion = json.int("schema_version")
        generatedAt = BIOSDate.parse(json.str("generated_at"))
        disclaimer = json.str("disclaimer")
        due = json.list("due").compactMap { LabDue(json: $0) }
        groups = json.list("groups").compactMap { LabGroup(json: $0) }.filter { !$0.markers.isEmpty }
        review = LabReviewSummary(json: json.obj("review"))
        var regions: [String: [String]] = [:]
        for (key, value) in json.obj("regions")?.objectValue ?? [:] {
            let ids = value.arrayValue.compactMap { $0.stringValue }
            if !ids.isEmpty { regions[key] = ids }
        }
        self.regions = regions
        nValues = json.int("n_values") ?? groups.reduce(0) { $0 + $1.markers.count }
        lastValueOn = json.str("last_value_on")
        nDeviceValues = json.int("n_device_values") ?? 0
        ownMeasurements = LabOwnMeasurements(json: json.obj("own"))
        if let summary = LabTargetSummary(json: json.obj("targets")) {
            targets = summary
        } else {
            let total = groups.reduce(0) { $0 + $1.nTarget }
            let inside = groups.reduce(0) { $0 + $1.nInTarget }
            targets = total > 0 ? LabTargetSummary(nTarget: total, nInTarget: inside) : nil
        }
    }

    var allMarkers: [LabMarkerEntry] {
        groups.flatMap(\.markers)
    }

    /// Lab markers only (device readings have no reference and no lab status).
    var labMarkers: [LabMarkerEntry] {
        allMarkers.filter { !$0.isDevice }
    }

    /// Card "Eigene Messungen" (`own`, additive since 2026-09-28).
    var own: LabOwnMeasurements? {
        ownMeasurements
    }

    var hasValues: Bool {
        !groups.isEmpty
    }

    /// Body map region of a group (the group's own `region`, else the `regions` map).
    func region(forGroup groupID: String?) -> String? {
        guard let groupID else { return nil }
        if let region = groups.first(where: { $0.id == groupID })?.region {
            return region
        }
        return regions.first { $0.value.contains(groupID) }?.key
    }

    /// Whether a body map region has confirmed lab values (for its neutral link).
    func hasValues(inRegion regionID: String) -> Bool {
        let groupIDs = Set(regions[regionID] ?? [])
        return groups.contains { group in
            group.region == regionID || groupIDs.contains(group.id)
        }
    }
}

// MARK: - Marker detail

struct LabMarkerInfo: Equatable {
    let id: String
    let name: String
    let group: String?
    let groupLabel: String?
    let unit: String?
    let decimals: Int
    let kind: String?
    let custom: Bool
    /// Device markers: "aus Dexcom-Kalibrierung".
    let sourceLabel: String?
    /// Visit vitals from letters (`kind` "vital_visite"): no history, only in the document.
    let hidden: Bool
    let hiddenReason: String?
    /// Merged "Blutzucker": values per origin.
    let parts: [LabMergedPart]

    init(json: JSONValue?, fallbackID: String) {
        id = json?.str("id") ?? fallbackID
        name = json?.str("name") ?? fallbackID
        group = json?.str("group")
        groupLabel = json?.str("group_label")
        unit = json?.str("unit")
        decimals = max(0, min(4, json?.int("decimals") ?? 1))
        kind = json?.str("kind")
        custom = json?.flag("custom") ?? false
        sourceLabel = json?.str("source_label")
        hidden = json?.flag("hidden") ?? false
        hiddenReason = json?.str("hidden_reason")
        parts = (json?.list("parts") ?? []).compactMap { LabMergedPart(json: $0) }
    }

    var isDevice: Bool { LabMarkerKind.isDevice(kind) }
    var isCombined: Bool { LabMarkerKind.isCombined(kind) }
}

/// One fingerstick with the last CGM value before it (`links[].pairs[]`).
struct LabCGMPair: Identifiable, Equatable {
    let id: String
    let measuredAt: Date?
    let dateRaw: String?
    let finger: Double
    let cgm: Double
    let cgmAt: Date?
    /// CGM minus finger in mg/dL.
    let diff: Double
    /// Relative to the finger value, in %.
    let diffPct: Double?

    init?(json: JSONValue, index: Int) {
        guard json.objectValue != nil, let finger = json.double("finger"), let cgm = json.double("cgm") else {
            return nil
        }
        let measured = json.str("measured_at")
        measuredAt = BIOSDate.parse(measured)
        dateRaw = json.str("date")
        self.finger = finger
        self.cgm = cgm
        cgmAt = BIOSDate.parse(json.str("cgm_at"))
        diff = json.double("diff") ?? (cgm - finger)
        diffPct = json.double("diff_pct") ?? (finger != 0 ? (cgm - finger) / finger * 100 : nil)
        id = "\(measured ?? dateRaw ?? "paar")-\(index)"
    }

    var when: Date? { measuredAt ?? BIOSDate.day(dateRaw) }
}

/// `links[]` entry `cgm_vergleich` of the fingerstick marker: sensor vs finger.
struct LabCGMComparison: Equatable {
    let label: String?
    let unit: String
    let nValues: Int?
    let nPairs: Int
    let windowMin: Int?
    /// Mean of |diff_pct| (MARD-like, no study MARD); only from 5 pairs.
    let mardPct: Double?
    /// Mean of diff in mg/dL (positive = sensor higher).
    let biasMgDl: Double?
    let evaluable: Bool
    let reason: String?
    /// Chronological.
    let pairs: [LabCGMPair]

    init?(json: JSONValue?) {
        guard let json, json.objectValue != nil, (json.str("kind") ?? "") == "cgm_vergleich" else { return nil }
        label = json.str("label")
        unit = json.str("unit") ?? "mg/dL"
        nValues = json.int("n_values")
        windowMin = json.int("window_min")
        let parsed = json.list("pairs").enumerated().compactMap { LabCGMPair(json: $0.element, index: $0.offset) }
        pairs = parsed.sorted { ($0.when ?? .distantPast) < ($1.when ?? .distantPast) }
        nPairs = json.int("n_pairs") ?? pairs.count
        mardPct = json.double("mard_pct")
        biasMgDl = json.double("bias_mg_dl")
        evaluable = json.flag("evaluable", fallback: mardPct != nil)
        reason = json.str("reason")
    }

    /// Summary only when the server judged it evaluable (>= 5 pairs).
    var hasSummary: Bool {
        evaluable && (mardPct != nil || biasMgDl != nil)
    }
}

/// A reference range that applied over a period (`refs[]`).
struct LabRefSpan: Identifiable, Equatable {
    let id: Int
    let refLow: Double?
    let refHigh: Double?
    let refText: String?
    let unit: String?
    let from: String?
    let to: String?
    let n: Int?

    init?(json: JSONValue, index: Int) {
        guard json.objectValue != nil else { return nil }
        id = index
        refLow = json.double("ref_low")
        refHigh = json.double("ref_high")
        refText = json.str("ref_text")
        unit = json.str("unit")
        from = json.str("from")
        to = json.str("to")
        n = json.int("n")
    }
}

/// `GET /v1/labs/markers/{id}`.
struct LabMarkerDetail: Equatable {
    let marker: LabMarkerInfo
    /// Chronological.
    let history: [LabPoint]
    let refs: [LabRefSpan]
    let target: LabTarget?
    let links: [LabGMI]
    /// Fingerstick marker: sensor vs finger (`links[]` kind `cgm_vergleich`).
    let cgmComparison: LabCGMComparison?
    let disclaimer: String?
    let generatedAt: Date?

    init(json: JSONValue, id: String) {
        marker = LabMarkerInfo(json: json.obj("marker"), fallbackID: id)
        let points = json.list("history").enumerated().compactMap { LabPoint(json: $0.element, index: $0.offset) }
        // Chronological by the server; device readings sorted by their time to be safe.
        if points.contains(where: { $0.measuredAt != nil }) {
            history = points.sorted { ($0.when ?? .distantPast) < ($1.when ?? .distantPast) }
        } else {
            history = points
        }
        refs = json.list("refs").enumerated().compactMap { LabRefSpan(json: $0.element, index: $0.offset) }
        target = LabTarget(json: json.obj("target"))
        links = json.list("links").compactMap { LabGMI(json: $0) }
        cgmComparison = json.list("links").lazy.compactMap { LabCGMComparison(json: $0) }.first
        disclaimer = json.str("disclaimer")
        generatedAt = BIOSDate.parse(json.str("generated_at"))
    }

    var latest: LabPoint? { history.last }

    /// A device marker (fingerstick), by `kind` or by its points' origin.
    var isDevice: Bool {
        if isCombined { return false }
        return marker.isDevice || cgmComparison != nil || (history.last?.origin != nil && history.last?.documentID == nil)
    }

    /// The merged "Blutzucker" (lab, fingerstick and clinic values), by `kind` or its points.
    var isCombined: Bool {
        marker.isCombined || history.contains { $0.originGroup != nil }
    }

    /// Merged marker: lab points only (with the lab's range), chronological.
    var labHistory: [LabPoint] {
        history.filter { $0.isLabOrigin }
    }

    /// The GMI link for today (HbA1c only).
    var gmiLink: LabGMI? {
        links.first { ($0.kind ?? "gmi") == "gmi" }
    }
}

// MARK: - Documents

/// One extracted value of a document (review screen, expanded cards).
struct LabValue: Identifiable, Equatable {
    let id: String
    let markerID: String?
    let markerName: String?
    let group: String?
    let rawName: String?
    let value: Double?
    let valueText: String?
    let comparator: String?
    let unit: String?
    let valueCanonical: Double?
    let unitCanonical: String?
    let refLow: Double?
    let refHigh: Double?
    let refText: String?
    let labFlag: String?
    let status: LabValueStatus
    let statusBasis: String?
    let zScore: Double?
    let pctPredicted: Double?
    let confidence: Double?
    let needsReview: Bool
    let reviewReasons: [String]
    let page: Int?
    let snippet: String?
    /// "zu_pruefen", "bestaetigt", "verworfen".
    let review: String
    let edited: Bool
    /// `kind` of the mapped catalog marker ("vital_visite" for height, weight, RR of letters).
    let markerKind: String?
    /// Visit vital from a letter: kept here only, never in overview or history.
    let hidden: Bool

    init?(json: JSONValue, index: Int) {
        guard json.objectValue != nil else { return nil }
        id = json.str("id") ?? "wert-\(index)"
        markerKind = json.str("marker_kind")
        hidden = json.flag("hidden")
        markerID = json.str("marker_id")
        markerName = json.str("marker_name")
        group = json.str("group")
        rawName = json.str("raw_name")
        value = json.double("value")
        valueText = json.str("value_text")
        comparator = json.str("comparator")
        unit = json.str("unit")
        valueCanonical = json.double("value_canonical")
        unitCanonical = json.str("unit_canonical")
        refLow = json.double("ref_low")
        refHigh = json.double("ref_high")
        refText = json.str("ref_text")
        labFlag = json.str("lab_flag")
        status = LabValueStatus(raw: json.str("status"))
        statusBasis = json.str("status_basis")
        zScore = json.double("z_score")
        pctPredicted = json.double("pct_predicted")
        confidence = json.double("confidence")
        reviewReasons = json.strings("review_reasons")
        needsReview = json.flag("needs_review", fallback: !json.strings("review_reasons").isEmpty)
        page = json.int("page")
        snippet = json.str("snippet")
        review = json.str("review")?.lowercased() ?? "zu_pruefen"
        edited = json.flag("edited")
    }

    var displayName: String {
        markerName ?? rawName ?? "Wert"
    }

    var isDiscarded: Bool { review == "verworfen" }

    /// Not assigned to a catalog marker (review reason, no id or a custom `x_` id).
    var isUnmapped: Bool {
        reviewReasons.contains("nicht_zugeordnet") || markerID == nil || markerID?.hasPrefix("x_") == true
    }

    /// "53 mmol/mol" as printed in the document.
    var printedText: String {
        let number = LabFormat.value(value, decimals: nil, comparator: comparator, text: valueText)
        guard let unit, !unit.isEmpty else { return number }
        return "\(number) \(unit)"
    }

    /// "Ref. 20 - 42" as printed, or from the numbers.
    var refDisplay: String? {
        if let refText { return "Ref. " + refText }
        return LabFormat.refRange(low: refLow, high: refHigh, decimals: nil, unit: nil).map { "Ref. " + $0 }
    }
}

/// `Document` (list) or `Document` + `values` (single document).
struct LabDocument: Identifiable, Equatable {
    let id: String
    let kind: String?
    let kindLabel: String?
    let title: String?
    let collectedOn: String?
    let issuer: String?
    let status: LabDocumentStatus
    let statusReason: String?
    let source: String?
    let contentType: String?
    let sizeBytes: Int?
    let uploadedAt: Date?
    let extractedAt: Date?
    let confirmedAt: Date?
    let nValues: Int
    let nReview: Int
    let summaryPoints: [String]
    /// List only: id of an earlier document with mostly the same values (photo
    /// and PDF of one report). Just a hint, nothing is merged.
    let possibleDuplicateOf: String?
    /// nil in the list; the values of `GET /v1/labs/documents/{id}`.
    let values: [LabValue]?
    /// Status `ersetzt`: the later document that holds the same values.
    let supersededBy: LabDocumentRef?
    let supersededAt: Date?
    /// Older documents this one replaced.
    let supersedes: [LabDocumentRef]

    init?(json: JSONValue) {
        guard let id = json.str("id") else { return nil }
        self.id = id
        supersededBy = LabDocumentRef(json: json.obj("superseded_by"))
        supersededAt = BIOSDate.parse(json.str("superseded_at"))
        supersedes = json.list("supersedes").compactMap { LabDocumentRef(json: $0) }
        kind = json.str("kind")
        kindLabel = json.str("kind_label") ?? LabKind.label(json.str("kind"))
        title = json.str("title")
        collectedOn = json.str("collected_on")
        issuer = json.str("issuer")
        status = LabDocumentStatus(raw: json.str("status"))
        statusReason = json.str("status_reason")
        source = json.str("source")
        contentType = json.str("content_type")
        sizeBytes = json.int("size_bytes")
        uploadedAt = BIOSDate.parse(json.str("uploaded_at"))
        extractedAt = BIOSDate.parse(json.str("extracted_at"))
        confirmedAt = BIOSDate.parse(json.str("confirmed_at"))
        summaryPoints = json.strings("summary_points")
        let duplicate = json.str("possible_duplicate_of")
        possibleDuplicateOf = duplicate == id ? nil : duplicate
        if case .array(let items)? = json["values"] {
            values = items.enumerated().compactMap { LabValue(json: $0.element, index: $0.offset) }
        } else {
            values = nil
        }
        nValues = json.int("n_values") ?? values?.filter { !$0.isDiscarded }.count ?? 0
        nReview = json.int("n_review") ?? values?.filter { $0.needsReview && !$0.isDiscarded }.count ?? 0
    }

    /// Date of the document: collection date, else the upload.
    var date: Date? {
        BIOSDate.day(collectedOn) ?? uploadedAt
    }

    var displayTitle: String {
        title ?? kindLabel ?? (status == .waiting ? "Neues Dokument" : "Dokument")
    }

    /// A letter or report text: summary points instead of values.
    var isLetter: Bool {
        kind == "brief" || (nValues == 0 && !summaryPoints.isEmpty)
    }

    var isPDF: Bool {
        (contentType ?? "").lowercased().contains("pdf")
    }

    /// "15.09. · Labor (Beispiel) · 5 Werte".
    var subline: String {
        var parts: [String] = []
        if let date = BIOSDate.day(collectedOn) {
            parts.append(BIOSFormat.shortDate(date))
        } else if let uploadedAt {
            parts.append("hochgeladen " + BIOSFormat.relative(uploadedAt))
        }
        if let issuer { parts.append(issuer) }
        if status == .confirmed || status == .review {
            if isLetter {
                parts.append("Kurzfassung")
            } else {
                parts.append(nValues == 1 ? "1 Wert" : "\(nValues) Werte")
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// Short reference to another document (`superseded_by`, `supersedes[]`).
struct LabDocumentRef: Identifiable, Equatable {
    let id: String
    let title: String?
    let collectedOn: String?
    let kindLabel: String?

    init?(json: JSONValue?) {
        guard let json, let id = json.str("id") else { return nil }
        self.id = id
        title = json.str("title")
        collectedOn = json.str("collected_on")
        kindLabel = json.str("kind_label")
    }

    /// "Befund vom 15.09.2026" (or the title without a date).
    var shortText: String {
        if let day = BIOSDate.day(collectedOn) {
            return "Befund vom \(LabFormat.fullDate(day))"
        }
        return title ?? kindLabel ?? "neuerem Befund"
    }
}

// MARK: - Eigene Messungen (`own` of GET /v1/labs)

/// Clemens' own measurements instead of the visit vitals printed in letters: height,
/// weight, BMI (body profile or Whoop), home blood pressure, temperature, blood glucose.
struct LabOwnMeasurements: Equatable {
    struct Body: Equatable {
        let heightCm: Double?
        let heightSource: String?
        let weightKg: Double?
        let weightDate: String?
        let weightSource: String?
        let weightSourceLabel: String?
        let bmi: Double?
    }

    struct BloodPressure: Equatable {
        let days: Int
        let meanSys: Double?
        let meanDia: Double?
        let meanPulse: Double?
        let nSeries: Int
        let nReadings: Int
        /// "ok", "info", "warn".
        let status: String?
        let classificationText: String?
        let lastSys: Double?
        let lastDia: Double?
        let lastPulse: Double?
        let lastAt: Date?
    }

    struct Temperature: Equatable {
        let value: Double
        let measuredAt: Date?
        let method: String?
    }

    struct Glucose: Equatable {
        let markerID: String
        let value: Double
        let unit: String
        let date: Date?
        let measuredAt: Date?
        let originLabel: String?
        let nValues: Int
    }

    let label: String
    let note: String?
    let body: Body?
    let bloodPressure: BloodPressure?
    let temperature: Temperature?
    let glucose: Glucose?

    init?(json: JSONValue?) {
        guard let json, json.objectValue != nil else { return nil }
        label = json.str("label") ?? "Eigene Messungen"
        note = json.str("note")
        if let b = json.obj("body"), b.objectValue != nil {
            body = Body(heightCm: b.double("height_cm"), heightSource: b.str("height_source"),
                        weightKg: b.double("weight_kg"), weightDate: b.str("weight_date"),
                        weightSource: b.str("weight_source"), weightSourceLabel: b.str("weight_source_label"),
                        bmi: b.double("bmi"))
        } else {
            body = nil
        }
        if let p = json.obj("blood_pressure"), p.objectValue != nil {
            let mean = p.obj("mean")
            let last = p.obj("last")
            bloodPressure = BloodPressure(
                days: p.int("days") ?? 7, meanSys: mean?.double("sys"), meanDia: mean?.double("dia"),
                meanPulse: mean?.double("pulse"), nSeries: p.int("n_series") ?? 0, nReadings: p.int("n_readings") ?? 0,
                status: p.str("status"), classificationText: p.str("classification_text"),
                lastSys: last?.double("sys"), lastDia: last?.double("dia"), lastPulse: last?.double("pulse"),
                lastAt: BIOSDate.parse(last?.str("measured_at")))
        } else {
            bloodPressure = nil
        }
        if let t = json.obj("temperature"), let value = t.double("value") {
            temperature = Temperature(value: value, measuredAt: BIOSDate.parse(t.str("measured_at")),
                                      method: t.str("method"))
        } else {
            temperature = nil
        }
        if let g = json.obj("glucose"), let value = g.double("value") {
            let measured = g.str("measured_at")
            glucose = Glucose(markerID: g.str("marker_id") ?? "blood_glucose", value: value,
                              unit: g.str("unit") ?? "mg/dL", date: BIOSDate.day(g.str("date")),
                              measuredAt: (measured?.count ?? 0) > 10 ? BIOSDate.parse(measured) : nil,
                              originLabel: g.str("origin_group_label"), nValues: g.int("n_values") ?? 0)
        } else {
            glucose = nil
        }
    }

    var isEmpty: Bool {
        body == nil && bloodPressure == nil && temperature == nil && glucose == nil
    }
}

/// `GET /v1/labs/documents`.
struct LabDocumentsResponse: Equatable {
    let documents: [LabDocument]
    let review: LabReviewSummary
    let generatedAt: Date?

    init(json: JSONValue) {
        documents = json.list("documents").compactMap { LabDocument(json: $0) }.filter { $0.status != .discarded }
        review = LabReviewSummary(json: json.obj("review"))
        generatedAt = BIOSDate.parse(json.str("generated_at"))
    }
}

/// A marker of the catalog (for "Marker zuordnen" in the review step).
struct LabCatalogMarker: Identifiable, Equatable {
    let id: String
    let name: String
    let group: String?
    let groupLabel: String?
    /// Canonical unit.
    let unit: String?
    let decimals: Int
    let kind: String?
    /// Units the server can convert (canonical one included).
    let unitsAccepted: [String]

    init?(json: JSONValue) {
        guard let id = json.str("id") else { return nil }
        self.id = id
        name = json.str("name") ?? id
        group = json.str("group")
        groupLabel = json.str("group_label")
        unit = json.str("unit")
        decimals = max(0, min(4, json.int("decimals") ?? 1))
        kind = json.str("kind")
        unitsAccepted = json.strings("units_accepted")
    }

    /// Unit choices: canonical unit first, then the other accepted ones.
    var unitChoices: [String] {
        let candidates = (unit.map { [$0] } ?? []) + unitsAccepted
        var result: [String] = []
        for candidate in candidates where !candidate.isEmpty && !result.contains(candidate) {
            result.append(candidate)
        }
        return result
    }

    /// Search over name, id and group ("hba", "Blutfette", "ldl").
    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return [name, id, groupLabel ?? "", group ?? ""].contains { $0.range(of: needle, options: options) != nil }
    }
}

/// One group of the marker picker.
struct LabCatalogSection: Identifiable, Equatable {
    let id: String
    let label: String
    let markers: [LabCatalogMarker]
}

/// `GET /v1/labs/catalog`: kinds for the kind picker, groups and markers for
/// assigning an unmapped value.
struct LabCatalog: Equatable {
    struct GroupInfo: Identifiable, Equatable {
        let id: String
        let label: String
    }

    let kinds: [LabKindOption]
    let groups: [GroupInfo]
    let markers: [LabCatalogMarker]

    init(json: JSONValue?) {
        let parsed: [LabKindOption] = (json?.list("kinds") ?? []).compactMap { kind in
            guard let id = kind.str("id") else { return nil }
            return LabKindOption(id: id, label: kind.str("label") ?? LabKind.label(id) ?? id)
        }
        kinds = parsed.isEmpty ? LabKind.all : parsed
        groups = (json?.list("groups") ?? []).compactMap { group -> GroupInfo? in
            guard let id = group.str("id") else { return nil }
            return GroupInfo(id: id, label: group.str("label") ?? id)
        }
        markers = (json?.list("markers") ?? []).compactMap { LabCatalogMarker(json: $0) }
    }

    func marker(_ id: String?) -> LabCatalogMarker? {
        guard let id else { return nil }
        return markers.first { $0.id == id }
    }

    /// Markers matching `query`, grouped in catalog group order (groups the
    /// catalog does not list come last, in order of appearance).
    func sections(matching query: String) -> [LabCatalogSection] {
        let hits = markers.filter { $0.matches(query) }
        var order = groups.map(\.id)
        for marker in hits {
            let id = marker.group ?? "sonstiges"
            if !order.contains(id) { order.append(id) }
        }
        return order.compactMap { groupID -> LabCatalogSection? in
            let items = hits.filter { ($0.group ?? "sonstiges") == groupID }
            guard !items.isEmpty else { return nil }
            let label = groups.first { $0.id == groupID }?.label ?? items.first?.groupLabel ?? groupID
            return LabCatalogSection(id: groupID, label: label, markers: items)
        }
    }
}

// MARK: - Dashboard block

/// `labs` of `/v1/dashboard`: small card on Heute only when something is to
/// review or due.
struct DashboardLabsModel: Equatable {
    struct DueItem: Identifiable, Equatable {
        let id: String
        let label: String
        let status: String
        let dueOn: String?
    }

    let reviewDocuments: Int
    let waiting: Int
    let errors: Int
    let due: [DueItem]
    let hasValues: Bool

    init(json: JSONValue) {
        reviewDocuments = json.int("review_documents") ?? 0
        waiting = json.int("waiting") ?? 0
        errors = json.int("errors") ?? 0
        due = json.list("due").compactMap { item in
            guard let id = item.str("id") else { return nil }
            return DueItem(id: id, label: item.str("label") ?? id,
                           status: item.str("status")?.lowercased() ?? "", dueOn: item.str("due_on"))
        }
        hasValues = json.flag("has_values")
    }

    var openDue: [DueItem] {
        due.filter { $0.status == "faellig" || $0.status == "bald" }
    }

    var showsCard: Bool {
        reviewDocuments > 0 || !openDue.isEmpty
    }
}

// MARK: - Formatting

enum LabFormat {
    /// Marker value with the marker's decimals ("7,0"), comparator ("< 0,5") or
    /// the value text. `decimals` nil = as needed, at most 3.
    static func value(_ value: Double?, decimals: Int?, comparator: String? = nil, text: String? = nil) -> String {
        guard let value, value.isFinite else { return text ?? "n. v." }
        let number: String
        if let decimals {
            number = BIOSFormat.number(value, digits: decimals)
        } else {
            number = plain(value)
        }
        if let symbol = comparatorSymbol(comparator) {
            return "\(symbol) \(number)"
        }
        return number
    }

    /// Up to three decimals, trailing zeros dropped ("2,6", "53", "0,94").
    static func plain(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...3)).locale(BIOSFormat.locale).grouping(.never))
    }

    static func comparatorSymbol(_ raw: String?) -> String? {
        switch raw ?? "" {
        case "<": return "<"
        case "<=": return "≤"
        case ">": return ">"
        case ">=": return "≥"
        default: return nil
        }
    }

    /// "4,0 bis 6,0 %", "< 5,0 mg/L", "> 30 ng/mL", nil without any bound.
    static func refRange(low: Double?, high: Double?, decimals: Int?, unit: String?) -> String? {
        let suffix = (unit?.isEmpty == false) ? " " + (unit ?? "") : ""
        switch (low, high) {
        case let (low?, high?):
            return "\(value(low, decimals: decimals)) bis \(value(high, decimals: decimals))\(suffix)"
        case let (nil, high?):
            return "< \(value(high, decimals: decimals))\(suffix)"
        case let (low?, nil):
            return "> \(value(low, decimals: decimals))\(suffix)"
        default:
            return nil
        }
    }

    /// "15.09.2026".
    static func fullDate(_ date: Date) -> String {
        let year = Calendar.current.component(.year, from: date)
        return "\(BIOSFormat.shortDate(date))\(year)"
    }

    /// "September 2026".
    static func month(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        let name = BIOSFormat.monthsLong[max(0, min(11, (parts.month ?? 1) - 1))]
        return "\(name) \(parts.year ?? 0)"
    }

    /// "12 Tagen", "3 Wochen", "2 Monaten" (dative, after "in"/"seit").
    static func span(days: Int) -> String {
        if days == 1 { return "1 Tag" }
        if days < 14 { return "\(days) Tagen" }
        if days < 60 { return "\(days / 7) Wochen" }
        return "\(days / 30) Monaten"
    }

    /// Parses a number typed with a decimal comma or point ("7,2" -> 7.2).
    static func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "\u{2212}", with: "-")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    /// Text field value of a number: plain, decimal comma.
    static func editText(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return plain(value)
    }

    /// "48 KB", "1,2 MB".
    static func size(_ bytes: Int?) -> String? {
        guard let bytes, bytes > 0 else { return nil }
        if bytes < 1024 * 1024 {
            return "\(max(1, bytes / 1024)) KB"
        }
        return BIOSFormat.number(Double(bytes) / 1_048_576, digits: 1) + " MB"
    }
}
