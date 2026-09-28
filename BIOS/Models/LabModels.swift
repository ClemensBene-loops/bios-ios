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
        id = resultID ?? "\(dateRaw ?? "punkt")-\(index)"
    }

    /// Spirometry and similar: judged by the z-score (LLN -1,645).
    var usesZScore: Bool {
        statusBasis == "z" && zScore != nil
    }
}

/// `target` of a marker (therapy goal from the profile, e.g. HbA1c < 7,0 %).
struct LabTarget: Equatable {
    let low: Double?
    let high: Double?
    let unit: String?
    /// "im_ziel", "ueber_ziel", "unter_ziel" or nil.
    let status: String?

    init?(json: JSONValue?) {
        guard let json, json.objectValue != nil else { return nil }
        low = json.double("low")
        high = json.double("high")
        unit = json.str("unit")
        status = json.str("status")
        if low == nil && high == nil { return nil }
    }

    /// The tick on the reference bar (upper goal first).
    var tick: Double? { high ?? low }

    var statusText: String? {
        switch status ?? "" {
        case "im_ziel": return "im Ziel"
        case "ueber_ziel": return "über Ziel"
        case "unter_ziel": return "unter Ziel"
        default: return nil
        }
    }
}

struct LabSparkPoint: Equatable {
    let date: Date?
    let value: Double
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

    init?(json: JSONValue) {
        guard let id = json.str("id") else { return nil }
        self.id = id
        name = json.str("name") ?? id
        unit = json.str("unit")
        decimals = max(0, min(4, json.int("decimals") ?? 1))
        custom = json.flag("custom")
        latest = LabPoint(json: json.obj("latest"))
        previous = LabPoint(json: json.obj("previous"))
        sparkline = json.list("sparkline").compactMap { point in
            guard let value = point.double("value") else { return nil }
            return LabSparkPoint(date: BIOSDate.day(point.str("date")), value: value)
        }
        nValues = json.int("n_values") ?? sparkline.count
        target = LabTarget(json: json.obj("target"))
    }
}

/// A group of the overview ("Stoffwechsel", "Blutfette", ...).
struct LabGroup: Identifiable, Equatable {
    let id: String
    let label: String
    /// Body map region id for a neutral link (never a color).
    let region: String?
    let nMarkers: Int
    let nFlagged: Int
    let markers: [LabMarkerEntry]

    init?(json: JSONValue) {
        guard let id = json.str("id") else { return nil }
        self.id = id
        label = json.str("label") ?? id
        region = json.str("region")
        markers = json.list("markers").compactMap { LabMarkerEntry(json: $0) }
        nMarkers = json.int("n_markers") ?? markers.count
        nFlagged = json.int("n_flagged") ?? markers.filter { $0.latest?.status.isFlagged == true }.count
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
    }

    var allMarkers: [LabMarkerEntry] {
        groups.flatMap(\.markers)
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

    init(json: JSONValue?, fallbackID: String) {
        id = json?.str("id") ?? fallbackID
        name = json?.str("name") ?? fallbackID
        group = json?.str("group")
        groupLabel = json?.str("group_label")
        unit = json?.str("unit")
        decimals = max(0, min(4, json?.int("decimals") ?? 1))
        kind = json?.str("kind")
        custom = json?.flag("custom") ?? false
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
    let disclaimer: String?
    let generatedAt: Date?

    init(json: JSONValue, id: String) {
        marker = LabMarkerInfo(json: json.obj("marker"), fallbackID: id)
        history = json.list("history").enumerated().compactMap { LabPoint(json: $0.element, index: $0.offset) }
        refs = json.list("refs").enumerated().compactMap { LabRefSpan(json: $0.element, index: $0.offset) }
        target = LabTarget(json: json.obj("target"))
        links = json.list("links").compactMap { LabGMI(json: $0) }
        disclaimer = json.str("disclaimer")
        generatedAt = BIOSDate.parse(json.str("generated_at"))
    }

    var latest: LabPoint? { history.last }

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

    init?(json: JSONValue, index: Int) {
        guard json.objectValue != nil else { return nil }
        id = json.str("id") ?? "wert-\(index)"
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
    /// nil in the list; the values of `GET /v1/labs/documents/{id}`.
    let values: [LabValue]?

    init?(json: JSONValue) {
        guard let id = json.str("id") else { return nil }
        self.id = id
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
