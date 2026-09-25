import SwiftUI

/// "Ausblick" (verdict, alerts, allergy, hints) plus one section per virus
/// region and one for pollen.
struct OutlookSections: View {
    let outlook: BIOSOutlook?
    let isHighlighted: Bool

    var body: some View {
        Section {
            SectionStatusRow(
                status: outlook?.status ?? .unknown,
                title: outlook?.headline ?? "Noch keine Daten",
                subtitle: subtitle
            )
            .id(SectionID.outlook)
            .listRowBackground(HighlightBackground(isOn: isHighlighted))

            if let outlook {
                ForEach(outlook.alerts) { alert in
                    AlertRow(alert: alert)
                }
                if let allergy = outlook.allergy {
                    AllergyRow(allergy: allergy)
                }
                ForEach(outlook.infoHints) { hint in
                    Label {
                        Text(hint.text)
                            .font(.subheadline)
                    } icon: {
                        Image(systemName: "lightbulb")
                            .foregroundStyle(Color.yellow)
                    }
                }
                ForEach(Array(outlook.errors.enumerated()), id: \.offset) { entry in
                    ErrorRow(text: entry.element)
                }
                if let text = outlook.text, !text.isEmpty {
                    FullTextDisclosure(text: text)
                }
            }
        } header: {
            Text("Ausblick")
        }

        if let outlook {
            ForEach(outlook.regions) { region in
                Section {
                    ForEach(region.viruses) { virus in
                        VirusRow(virus: virus)
                    }
                } header: {
                    Text("Viren im Abwasser, \(region.region)")
                }
            }

            if !outlook.pollen.isEmpty {
                Section {
                    ForEach(outlook.pollen) { place in
                        PollenRow(place: place)
                    }
                } header: {
                    Text("Pollen, nächste Tage")
                } footer: {
                    Text("Höchste Stufe der Vorhersage (Modellwerte, keine Fallenzählung).")
                }
            }
        }
    }

    private var subtitle: String {
        guard let outlook else { return "Wird vom Server geladen" }
        var parts: [String] = []
        if let today = outlook.today {
            parts.append("Stand \(BIOSFormat.day(today))")
        }
        if let season = outlook.season {
            parts.append("Saison \(season)")
        }
        return parts.joined(separator: " · ")
    }
}

struct AllergyRow: View {
    let allergy: BIOSAllergyStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(title)
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: "allergens")
                    .foregroundStyle(allergy.active ? Color.orange : Color.green)
            }
            ForEach(Array(allergy.reasons.enumerated()), id: \.offset) { entry in
                Text(entry.element)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        let place = allergy.place.map { " (\($0))" } ?? ""
        return allergy.active
            ? "Allergie-Saison aktiv\(place)"
            : "Keine Allergie-Belastung\(place)"
    }
}

struct VirusRow: View {
    let virus: BIOSVirus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: trendSymbol)
                .foregroundStyle(BIOSLevelColor.virus(virus.level))
                .accessibilityLabel(virus.trend)
            VStack(alignment: .leading, spacing: 2) {
                Text(virus.name)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(virus.level)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BIOSLevelColor.virus(virus.level))
        }
    }

    private var trendSymbol: String {
        switch virus.trend {
        case "steigend": return "arrow.up.right"
        case "fallend": return "arrow.down.right"
        default: return "arrow.right"
        }
    }

    private var detail: String {
        var parts: [String] = []
        if !virus.trend.isEmpty {
            parts.append(virus.trend)
        }
        if let ratio = virus.vsUsual, ratio > 0 {
            if ratio >= 1 {
                parts.append("\(BIOSFormat.number(ratio, digits: 1))x so viel wie sonst")
            } else {
                parts.append("\(BIOSFormat.number(1 / ratio, digits: 1))x weniger als sonst")
            }
        }
        if let kw = virus.onsetKW {
            parts.append("Welle typisch ab KW \(kw)")
        }
        if let date = virus.latestDate {
            parts.append("Stand \(BIOSFormat.shortDay(date))" + (virus.stale ? " (Daten alt)" : ""))
        }
        return parts.joined(separator: " · ")
    }
}

struct PollenRow: View {
    let place: BIOSPollenPlace

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(place.place)
                .font(.subheadline.weight(.semibold))
            if place.allergens.isEmpty {
                Text("Keine Daten")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(place.allergens) { allergen in
                HStack(spacing: 8) {
                    Circle()
                        .fill(BIOSLevelColor.pollen(allergen.level))
                        .frame(width: 8, height: 8)
                    Text(allergen.name)
                    Spacer(minLength: 8)
                    Text(levelText(allergen))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
    }

    private func levelText(_ allergen: BIOSPollenAllergen) -> String {
        guard BIOSOutlook.rank(allergen.level) >= 2, let date = allergen.peakDate else {
            return allergen.level
        }
        return "\(allergen.level) am \(BIOSFormat.day(date))"
    }
}
