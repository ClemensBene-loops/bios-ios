import Foundation

// Körper (`GET/PATCH /v1/body`, since 2026-09-28): height and weight of the user.
// The own height always wins (clinic measurements are ignored); weight = the newest
// entry, own or Whoop. Lenient like every model: missing fields are nil.

/// One weight of the history (own entry or a Whoop value).
struct BodyWeightEntry: Identifiable, Equatable {
    let id: String
    /// Server id of an own entry (nil for Whoop values).
    let serverID: String?
    let date: Date?
    let seenOn: Date?
    let kg: Double
    /// "manuell" or "whoop".
    let source: String
    /// Whoop's first value: when it was set is unknown.
    let undated: Bool
    let removable: Bool

    init?(json: JSONValue, index: Int) {
        guard let kg = json.double("kg") else { return nil }
        self.kg = kg
        serverID = json.str("id")
        date = BIOSDate.day(json.str("date"))
        seenOn = BIOSDate.day(json.str("seen_on"))
        source = json.str("source") ?? "manuell"
        undated = json.flag("undated")
        removable = json.flag("removable")
        id = serverID ?? "\(source)-\(json.str("seen_on") ?? json.str("date") ?? "")-\(index)"
    }

    var sourceLabel: String {
        source == "whoop" ? "Whoop" : "eigene Eingabe"
    }

    /// "28.09.2026" / "Whoop, seit 28.09.2026 gesehen".
    var whenText: String {
        if let date { return LabFormat.fullDate(date) }
        if let seenOn { return "undatiert, gesehen \(LabFormat.fullDate(seenOn))" }
        return "ohne Datum"
    }
}

/// `GET /v1/body`.
struct BodyProfile: Equatable {
    let heightCm: Double?
    let heightSource: String?
    let whoopHeightCm: Double?
    let weightKg: Double?
    let weightDate: Date?
    let weightSourceLabel: String?
    let bmi: Double?
    let weights: [BodyWeightEntry]
    let whoopWeightKg: Double?
    let whoopMaxHR: Int?
    let heightRange: ClosedRange<Double>
    let weightRange: ClosedRange<Double>
    let note: String?

    init(json: JSONValue) {
        let height = json.obj("height")
        heightCm = height?.double("cm")
        heightSource = height?.str("source")
        whoopHeightCm = height?.double("whoop_cm")
        let weight = json.obj("weight")
        weightKg = weight?.double("kg")
        weightDate = BIOSDate.day(weight?.str("date"))
        weightSourceLabel = weight?.str("source_label")
        bmi = json.double("bmi")
        weights = json.list("weights").enumerated().compactMap { BodyWeightEntry(json: $0.element, index: $0.offset) }
        let whoop = json.obj("whoop")
        whoopWeightKg = whoop?.double("weight_kg")
        whoopMaxHR = whoop?.int("max_hr")
        heightRange = Self.range(json.obj("ranges"), "height_cm", fallback: 100...250)
        weightRange = Self.range(json.obj("ranges"), "weight_kg", fallback: 30...300)
        note = json.str("note")
    }

    private static func range(_ json: JSONValue?, _ key: String, fallback: ClosedRange<Double>) -> ClosedRange<Double> {
        let values = (json?.list(key) ?? []).compactMap { $0.finiteNumber }
        guard values.count == 2, values[0] < values[1] else { return fallback }
        return values[0]...values[1]
    }
}
