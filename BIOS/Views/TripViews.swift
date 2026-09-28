import SwiftUI

/// Umwelt > "Reiseziele" (`environment.trips`): detection state, one row per
/// destination with its ready line, tap opens the sheet with wastewater per
/// virus and the pollen days. Destinations never raise alarms or pushes.
struct TripsSection: View {
    let trips: TripsModel
    @State private var selected: TripItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Reiseziele")
            if !trips.enabled && trips.items.isEmpty {
                NotEvaluableBox(title: "Reiseziel-Erkennung aus",
                                text: trips.reason ?? "Der Server liest gerade keinen Kalender.")
            } else if trips.items.isEmpty {
                TripsEmptyCard(reason: trips.reason, checkedAt: trips.checkedAt)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(trips.items.enumerated()), id: \.element.id) { entry in
                        Button {
                            selected = entry.element
                        } label: {
                            TripRow(trip: entry.element)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Öffnet Abwasser und Pollen für das Reiseziel")
                        .overlay(alignment: .top) {
                            if entry.offset > 0 {
                                Rectangle().fill(BIOSTheme.separator).frame(height: 0.5)
                            }
                        }
                    }
                    if let reason = trips.reason {
                        // Calendar error: the destinations of the last good run are shown.
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(BIOSTheme.text3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                }
                .foregroundStyle(BIOSTheme.text1)
                .biosCard()
            }
        }
        .sheet(item: $selected) { trip in
            TripDetailSheet(trip: trip)
                .environment(\.locale, BIOSFormat.locale)
        }
    }
}

/// "Keine Reisen in den nächsten 14 Tagen" (+ calendar hint, last check).
private struct TripsEmptyCard: View {
    let reason: String?
    let checkedAt: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(BIOSTheme.text2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Keine Reisen in den nächsten 14 Tagen")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let reason {
                    CaptionText(text: reason)
                }
                if let checkedAt {
                    Text("Kalender geprüft \(BIOSFormat.relative(checkedAt))")
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text3)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
        .accessibilityElement(children: .combine)
    }
}

/// One destination: kind symbol, city, dates, the server's line.
struct TripRow: View {
    let trip: TripItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: trip.kind.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(BIOSTheme.accent)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(trip.city)
                        .font(.headline)
                    Spacer(minLength: 8)
                    if let dates = trip.dateText {
                        Text(dates)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(BIOSTheme.text3)
                    }
                }
                if let line = trip.line {
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BIOSTheme.text3)
                .padding(.top, 5)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trip.accessibilityText)
    }
}

/// Sheet of one destination: wastewater per virus (like the Vienna tile) with
/// plant, distance, note and source, then the pollen days of the trip.
struct TripDetailSheet: View {
    let trip: TripItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: trip.kind.symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BIOSTheme.accent)
                        .accessibilityLabel(trip.kind.word)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.city)
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)
                            .fixedSize(horizontal: false, vertical: true)
                        if let dates = trip.dateText {
                            Text(dates)
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(BIOSTheme.text2)
                        }
                    }
                    Spacer(minLength: 8)
                    Button("Fertig") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(BIOSTheme.text1)
                }

                if let line = trip.line {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(BIOSTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                sectionLabel("Viren im Abwasser")
                if let wastewater = trip.wastewater {
                    TripWastewaterCard(wastewater: wastewater)
                } else {
                    NotEvaluableBox(title: "Keine Abwasserdaten", text: nil)
                }

                sectionLabel("Pollen an den Reisetagen")
                if let pollen = trip.pollen {
                    TripPollenCard(pollen: pollen)
                } else {
                    NotEvaluableBox(title: "Keine Pollenvorhersage", text: nil)
                }

                Text("Nur zur Orientierung: Reiseziele lösen keine Warnungen aus. Pollen sind Modellwerte (CAMS), keine Fallenzählung.")
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(BIOSTheme.text1)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 30)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Wastewater of a destination: plant or region, sample date, one row per
/// virus with level and fine trend, then scope, note and source.
struct TripWastewaterCard: View {
    let wastewater: TripWastewater

    var body: some View {
        let region = wastewater.region
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(wastewater.label ?? "Abwasser")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(region.sampleText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text3)
            }
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            if region.viruses.isEmpty {
                Text(region.reason ?? "Keine Abwasserdaten für dieses Ziel")
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            }
            ForEach(region.viruses) { virus in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(virus.virus)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 62, alignment: .leading)
                    Spacer(minLength: 4)
                    VirusLevelTrend(virus: virus)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .top) {
                    Rectangle().fill(BIOSTheme.separator).frame(height: 0.5)
                }
                .accessibilityElement(children: .combine)
            }
            let facts = [wastewater.scopeText, wastewater.note, region.unitText.map { "Einheit \($0)" }].compactMap { $0 }
            if !facts.isEmpty || wastewater.attribution != nil {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(facts, id: \.self) { fact in
                        CaptionText(text: fact)
                    }
                    if let attribution = wastewater.attribution {
                        Text("Quelle: \(attribution)")
                            .font(.caption)
                            .foregroundStyle(BIOSTheme.text3)
                    }
                }
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
    }
}

/// Pollen of the trip days per allergen (dot, weekday, level), or the note
/// when the trip lies beyond the 4-day forecast.
struct TripPollenCard: View {
    let pollen: TripPollen

    var body: some View {
        let allergens = pollen.allergensWithDays
        VStack(alignment: .leading, spacing: 0) {
            if allergens.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(BIOSTheme.text2)
                        .accessibilityHidden(true)
                    Text(pollen.emptyText)
                        .font(.subheadline)
                        .foregroundStyle(BIOSTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(Array(allergens.enumerated()), id: \.element.id) { entry in
                let allergen = entry.element
                HStack(alignment: .center, spacing: 8) {
                    Text(allergen.name)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 62, alignment: .leading)
                    ForEach(allergen.forecast.prefix(4)) { day in
                        VStack(spacing: 3) {
                            PollenDot(rank: day.levelRank)
                            Text(dayText(day))
                                .font(.caption2)
                                .foregroundStyle(BIOSTheme.text2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 10)
                .overlay(alignment: .top) {
                    if entry.offset > 0 {
                        Rectangle().fill(BIOSTheme.separator).frame(height: 0.5)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(allergen.name + ": " + allergen.forecast.prefix(4).map { dayText($0) }.joined(separator: ", "))
            }
            if !allergens.isEmpty, let note = pollen.note {
                CaptionText(text: note)
                    .padding(.top, 8)
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .biosCard()
    }

    private func dayText(_ day: PollenDay) -> String {
        let name = day.date.map { BIOSFormat.weekdayShort($0) } ?? ""
        return "\(name) · \(day.level)"
    }
}
