import CoreGraphics
import Foundation

// View models for `GET /v1/bodymap` and the dashboard block `bodymap`.
// Lenient like the dashboard: unknown status -> keine_daten, missing fields
// get defaults, unknown detail links are dropped, region geometry falls back
// to the bundled layout (BodyMapShapes.swift). Observation only.

/// Status of a region or metric.
enum BodyMapStatus: String, CaseIterable, Hashable {
    case ok
    case beobachten
    case auffaellig
    case keineDaten = "keine_daten"

    /// Server key; anything unknown (or missing) is `.keineDaten`.
    init(key: String?) {
        let value = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: " ", with: "_")
        self = BodyMapStatus(rawValue: value) ?? .keineDaten
    }

    /// Sort order of the region list: auffällig first, keine Daten last.
    var rank: Int {
        switch self {
        case .auffaellig: return 0
        case .beobachten: return 1
        case .ok: return 2
        case .keineDaten: return 3
        }
    }
}

/// One value in the region sheet.
struct BodyMapMetric: Identifiable {
    let id: String
    let key: String
    let label: String
    let value: Double?
    let unit: String?
    let delta: Double?
    let deltaUnit: String?
    let display: String?
    let status: BodyMapStatus

    init?(json: JSONValue, index: Int) {
        guard json.objectValue != nil else { return nil }
        key = json.str("key") ?? "metric"
        id = "\(index)_\(key)"
        label = json.str("label") ?? key
        value = json.double("value")
        unit = json.str("unit")
        delta = json.double("delta")
        deltaUnit = json.str("delta_unit")
        display = json.str("display")
        status = BodyMapStatus(key: json.str("status"))
    }

    private static func digits(_ number: Double) -> Int {
        (number * 10).rounded() == (number.rounded() * 10) ? 0 : 1
    }

    /// "16,4 /min", "82 %", nil without a value.
    var valueText: String? {
        guard let value else { return nil }
        let number = BIOSFormat.number(value, digits: Self.digits(value))
        guard let unit else { return number }
        return number + " " + unit
    }

    /// Second line: the server's ready text, else the delta ("+1,4 /min").
    var detailText: String? {
        if let display, display != valueText { return display }
        if display == nil, let delta {
            let text = BIOSFormat.signed(delta, digits: Self.digits(delta))
            return deltaUnit.map { text + " " + $0 } ?? text
        }
        return nil
    }

    var spokenLabel: String {
        var parts = [label]
        if let valueText { parts.append(valueText) }
        if let detailText { parts.append(detailText) }
        parts.append(status.spoken)
        return parts.joined(separator: ", ")
    }
}

/// Button in the sheet to an existing detail screen.
struct BodyMapLink: Identifiable {
    let id: String
    let route: DetailRoute
    let label: String

    init?(json: JSONValue, index: Int) {
        guard let detail = json.str("detail"), let route = DetailRoute(pushValue: detail) else { return nil }
        self.route = route
        id = "\(index)_\(route.rawValue)"
        label = json.str("label") ?? route.title
    }
}

struct BodyMapRegion: Identifiable {
    let id: String
    let label: String
    let side: BodyMapSide
    let status: BodyMapStatus
    let statusLabel: String
    let reason: String
    let neutral: Bool
    /// Badge position (normalized), nil = no badge.
    let badge: CGPoint?
    let shapes: [BodyMapEllipse]
    let metrics: [BodyMapMetric]
    let links: [BodyMapLink]

    init?(json: JSONValue) {
        guard let id = json.str("id") else { return nil }
        let layout = BodyMapLayout.region(id)
        self.id = id
        label = json.str("label") ?? BodyMapStyle.regionLabel(id)
        side = json.str("view").map { BodyMapSide(key: $0) } ?? layout?.side ?? .front
        status = BodyMapStatus(key: json.str("status"))
        // The server label belongs to the server status; for an unknown status the app word.
        statusLabel = BodyMapStatus(rawValue: json.str("status") ?? "") != nil
            ? (json.str("status_label") ?? status.label) : status.label
        reason = json.str("reason") ?? BodyMapStyle.noReason
        neutral = json.flag("neutral")
        let serverShapes = json.list("shapes").compactMap(Self.ellipse)
        shapes = serverShapes.isEmpty ? (layout?.shapes ?? []) : serverShapes
        badge = json.obj("anchor").flatMap(Self.point) ?? layout?.badge
        metrics = json.list("metrics").enumerated().compactMap { BodyMapMetric(json: $0.element, index: $0.offset) }
        links = json.list("links").enumerated().compactMap { BodyMapLink(json: $0.element, index: $0.offset) }
    }

    /// Region from the bundled layout only (Heute mini figure without a loaded map).
    init(layout: BodyMapLayout.Region, status: BodyMapStatus, reason: String? = nil) {
        id = layout.id
        label = BodyMapStyle.regionLabel(layout.id)
        side = layout.side
        self.status = status
        statusLabel = status.label
        self.reason = reason ?? BodyMapStyle.noReason
        neutral = false
        badge = layout.badge
        shapes = layout.shapes
        metrics = []
        links = []
    }

    /// "Lunge, beobachten: Atemfrequenz erhöht (+1,4 /min)."
    var spokenLabel: String {
        "\(label), \(status.spoken): \(reason)"
    }

    private static func unit(_ value: Double?) -> CGFloat? {
        guard let value, value >= 0, value <= 1 else { return nil }
        return CGFloat(value)
    }

    private static func ellipse(_ json: JSONValue) -> BodyMapEllipse? {
        guard let cx = unit(json.double("cx")), let cy = unit(json.double("cy")),
              let rx = unit(json.double("rx")), let ry = unit(json.double("ry")),
              rx > 0, ry > 0 else { return nil }
        return BodyMapEllipse(cx: cx, cy: cy, rx: rx, ry: ry)
    }

    private static func point(_ json: JSONValue) -> CGPoint? {
        guard let x = unit(json.double("x")), let y = unit(json.double("y")) else { return nil }
        return CGPoint(x: x, y: y)
    }
}

/// Counts per status (neutral regions count as keine_daten).
struct BodyMapCounts: Equatable {
    var ok = 0
    var beobachten = 0
    var auffaellig = 0
    var keineDaten = 0

    init(ok: Int = 0, beobachten: Int = 0, auffaellig: Int = 0, keineDaten: Int = 0) {
        self.ok = ok
        self.beobachten = beobachten
        self.auffaellig = auffaellig
        self.keineDaten = keineDaten
    }

    init(json: JSONValue?) {
        ok = max(0, json?.int("ok") ?? 0)
        beobachten = max(0, json?.int("beobachten") ?? 0)
        auffaellig = max(0, json?.int("auffaellig") ?? 0)
        keineDaten = max(0, json?.int("keine_daten") ?? 0)
    }

    init(regions: [BodyMapRegion]) {
        for region in regions {
            switch region.status {
            case .ok: ok += 1
            case .beobachten: beobachten += 1
            case .auffaellig: auffaellig += 1
            case .keineDaten: keineDaten += 1
            }
        }
    }

    var attention: Int { beobachten + auffaellig }

    /// "2 beobachten, 1 auffällig", "alles im Rahmen", "3 Regionen ohne Daten".
    var spoken: String {
        if attention == 0 {
            return ok > 0 ? BodyMapStyle.allOk.lowercased() : "\(keineDaten) Regionen ohne Daten"
        }
        var parts: [String] = []
        if beobachten > 0 { parts.append("\(beobachten) beobachten") }
        if auffaellig > 0 { parts.append("\(auffaellig) auffällig") }
        return parts.joined(separator: ", ")
    }
}

/// Dashboard block `bodymap` (Heute card) and `summary` of the map.
struct BodyMapSummaryModel {
    struct Top {
        let id: String
        let label: String
        let status: BodyMapStatus
        let reason: String?
    }

    let counts: BodyMapCounts
    let text: String
    let top: Top?
    let generatedAt: Date?

    init(json: JSONValue) {
        counts = BodyMapCounts(json: json.obj("counts"))
        text = json.str("text") ?? counts.spoken
        top = json.obj("top").flatMap { top -> Top? in
            guard let id = top.str("id") else { return nil }
            return Top(
                id: id,
                label: top.str("label") ?? BodyMapStyle.regionLabel(id),
                status: BodyMapStatus(key: top.str("status")),
                reason: top.str("reason")
            )
        }
        generatedAt = BIOSDate.parse(json.str("generated_at"))
    }
}

/// `GET /v1/bodymap`.
struct BodyMapModel {
    let schemaVersion: Int?
    let generatedAt: Date?
    let note: String
    let regions: [BodyMapRegion]
    let summary: BodyMapSummaryModel?
    let errors: [String]

    init(json: JSONValue) {
        schemaVersion = json.int("schema_version")
        generatedAt = BIOSDate.parse(json.str("generated_at"))
        note = json.str("note") ?? BodyMapStyle.note
        var seen = Set<String>()
        regions = json.list("regions").compactMap { BodyMapRegion(json: $0) }.filter { seen.insert($0.id).inserted }
        summary = json.obj("summary").map { BodyMapSummaryModel(json: $0) }
        errors = json.strings("errors")
    }

    /// Region list order: auffällig, beobachten, ok, keine Daten; server order within a status.
    var sortedRegions: [BodyMapRegion] {
        regions.enumerated()
            .sorted { ($0.element.status.rank, $0.offset) < ($1.element.status.rank, $1.offset) }
            .map(\.element)
    }
}
