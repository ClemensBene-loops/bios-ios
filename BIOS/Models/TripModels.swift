import Foundation

// `environment.trips` (Reiseziele of the next 14 days, additive since
// 28.09.2026): destinations from the calendar (city and dates only) plus
// manual ones, each with wastewater in the shape of the Vienna tile and the
// pollen forecast of the trip days. Lenient: unknown kinds, missing blocks
// and wrong types fall back to calm defaults.

struct TripsModel {
    /// Detection from the calendar is on.
    let enabled: Bool
    let source: String?
    /// Why detection is off, or a hint after a calendar error.
    let reason: String?
    let checkedAt: Date?
    let items: [TripItem]

    init(json: JSONValue) {
        enabled = json.flag("enabled")
        source = json.str("source")
        reason = json.str("reason")
        checkedAt = BIOSDate.parse(json.str("checked_at"))
        items = json.list("items").enumerated().compactMap { TripItem(json: $0.element, index: $0.offset) }
    }
}

struct TripItem: Identifiable {
    enum Kind: String {
        case flight
        case travel
        case place
        case manual
        case other

        var symbol: String {
            switch self {
            case .flight: return "airplane"
            case .travel: return "car"
            case .place: return "mappin"
            case .manual: return "pencil"
            case .other: return "suitcase"
            }
        }

        /// Spoken kind for VoiceOver.
        var word: String {
            switch self {
            case .flight: return "Flug"
            case .travel: return "Reise mit Auto oder Zug"
            case .place: return "Termin am Ort"
            case .manual: return "von Hand eingetragen"
            case .other: return "Reise"
            }
        }
    }

    let id: String
    let city: String
    let country: String?
    let from: Date?
    let to: Date?
    let kind: Kind
    /// Ready line from the server ("Frankfurt 05. bis 07.10.: Abwasser: ...").
    let line: String?
    let wastewater: TripWastewater?
    let pollen: TripPollen?

    init?(json: JSONValue, index: Int) {
        guard json.objectValue != nil, let city = json.str("city") ?? json.str("place") else { return nil }
        self.city = city
        country = json.str("country")
        let fromRaw = json.str("from")
        let fromDay = BIOSDate.day(fromRaw)
        from = fromDay
        to = BIOSDate.day(json.str("to")) ?? fromDay
        kind = Kind(rawValue: (json.str("kind") ?? "").lowercased()) ?? .other
        line = json.str("line")
        id = "\(city)-\(fromRaw ?? "\(index)")-\(index)"
        wastewater = json.obj("wastewater").map { TripWastewater(json: $0, key: "trip-\(index)") }
        pollen = json.obj("pollen").map { TripPollen(json: $0) }
    }

    /// "Mo 05.10. bis Mi 07.10." or one day "Mo 05.10.".
    var dateText: String? {
        guard let from else { return nil }
        guard let to, !Calendar.current.isDate(from, inSameDayAs: to) else {
            return BIOSFormat.dayLabel(from)
        }
        return "\(BIOSFormat.dayLabel(from)) bis \(BIOSFormat.dayLabel(to))"
    }

    var accessibilityText: String {
        [city, dateText, kind.word, line].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Wastewater of a destination: `virus_view` shape (as the Vienna tile) plus
/// `scope`, `label`, `distance_km`, `note`.
struct TripWastewater {
    let region: VirusRegionModel
    /// `standort`, `bundesland`, `national`.
    let scope: String?
    let source: String?
    let label: String?
    let distanceKm: Double?
    let note: String?
    /// Server attribution if it sends one, else from the source.
    let attribution: String?

    init(json: JSONValue, key: String) {
        region = VirusRegionModel(json: json, key: key)
        scope = json.str("scope")
        let sourceKey = json.str("source")
        source = sourceKey
        label = json.str("label") ?? json.str("region")
        distanceKm = json.double("distance_km")
        note = json.str("note")
        if let given = json.str("attribution") ?? json.str("source_label") {
            attribution = given
        } else if let sourceKey, sourceKey.hasPrefix("abwasser_de") {
            attribution = "Robert Koch-Institut (AMELAG)"
        } else if sourceKey == "abwasser_wien" {
            attribution = "Stadt Wien"
        } else {
            attribution = nil
        }
    }

    /// "Klärwerk 4 km entfernt", "Mittel des Bundeslandes", "Landesweit".
    var scopeText: String? {
        switch scope {
        case "standort":
            if let distanceKm {
                let digits = distanceKm < 10 && distanceKm != distanceKm.rounded() ? 1 : 0
                return "Nächstes Klärwerk, \(BIOSFormat.number(distanceKm, digits: digits)) km entfernt"
            }
            return "Nächstes Klärwerk"
        case "bundesland": return "Mittel über die Klärwerke des Bundeslandes"
        case "national": return "Landesweiter Wert"
        default: return nil
        }
    }
}

/// Pollen of a destination: `pollen_view` shape cut to the trip days, plus `note`.
struct TripPollen {
    let model: PollenModel
    let note: String?

    init(json: JSONValue) {
        model = PollenModel(json: json)
        note = json.str("note")
    }

    /// Allergens with at least one forecast day.
    var allergensWithDays: [PollenAllergen] {
        model.allergens.filter { !$0.forecast.isEmpty }
    }

    /// Calm text when there are no days (note, else reason).
    var emptyText: String {
        note ?? model.reason ?? "Keine Pollenvorhersage für die Reisetage"
    }
}
