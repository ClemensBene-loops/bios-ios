import SwiftUI

/// Tab "Umwelt": viruses in wastewater (Wien, Deutschland), pollen, allergy
/// block, season hints.
struct UmweltView: View {
    @EnvironmentObject var dashboardStore: DashboardStore
    @EnvironmentObject var seriesStore: SeriesStore

    var body: some View {
        let dashboard = dashboardStore.dashboard
        let regions = UmweltData.regions(dashboard)
        let places = UmweltData.pollenPlaces(dashboard)
        let allergy = dashboard?.environment?.allergy ?? dashboard?.pollen?.allergy
        let hints = dashboard?.environment?.hints ?? []
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                StoreStatusBanner()

                SectionHeader(title: "Viren im Abwasser", route: .viren)
                if regions.isEmpty {
                    NotEvaluableBox(title: "Keine Abwasserdaten", text: nil)
                }
                ForEach(regions) { region in
                    NavigationLink(value: DetailRoute.viren) {
                        VirusRegionCard(region: region, detailed: false)
                    }
                    .buttonStyle(CardButtonStyle())
                }

                SectionHeader(title: "Pollen", route: .pollen)
                if places.isEmpty {
                    NotEvaluableBox(title: "Keine Pollenvorhersage", text: nil)
                }
                ForEach(places) { place in
                    NavigationLink(value: DetailRoute.pollen) {
                        PollenForecastCard(pollen: place)
                    }
                    .buttonStyle(CardButtonStyle())
                }

                SectionHeader(title: "Allergie")
                AllergyCard(allergy: allergy, names: UmweltData.allergenNames(dashboard))

                if !hints.isEmpty {
                    SectionHeader(title: "Saisonhinweise")
                    HintsCard(hints: hints)
                }

                NoteText(text: noteText(dashboard))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
        .navigationTitle("Umwelt")
        .refreshable {
            await dashboardStore.refresh(force: true)
            await seriesStore.refreshLoaded()
        }
    }

    private func noteText(_ dashboard: DashboardModel?) -> String {
        var parts: [String] = []
        if let season = dashboard?.environment?.season {
            parts.append("Saison \(season)")
        }
        if let at = dashboard?.outlook?.generatedAt {
            parts.append("Ausblick \(BIOSFormat.relative(at))")
        }
        parts.append("Pollen sind Modellwerte, keine Fallenzählung.")
        return parts.joined(separator: " · ")
    }
}

/// Merges tile and environment blocks (Wien first, then the others).
enum UmweltData {
    static func regions(_ dashboard: DashboardModel?) -> [VirusRegionModel] {
        guard let dashboard else { return [] }
        var regions = dashboard.environment?.viruses ?? []
        if !regions.contains(where: { $0.key == "abwasser_wien" }), let wien = dashboard.virusesWien {
            regions.insert(wien, at: 0)
        }
        return regions
    }

    static func pollenPlaces(_ dashboard: DashboardModel?) -> [PollenModel] {
        guard let dashboard else { return [] }
        let places = dashboard.environment?.pollen ?? []
        if !places.isEmpty { return places }
        return dashboard.pollen.map { [$0] } ?? []
    }

    /// Profile allergens as display names ("birch" -> "Birke").
    static func allergenNames(_ dashboard: DashboardModel?) -> [String] {
        let known = pollenPlaces(dashboard).first?.allergens ?? []
        let keys = dashboard?.environment?.allergy?.allergens ?? dashboard?.pollen?.allergy?.allergens ?? []
        if keys.isEmpty { return known.map(\.name) }
        return keys.map { key in
            known.first { $0.allergen == key }?.name ?? key
        }
    }
}

/// One wastewater region: virus, trend arrow + fine trend, level
/// (`detailed` adds ratio, % of a typical peak, seasonal comparison, onset).
struct VirusRegionCard: View {
    let region: VirusRegionModel
    let detailed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(region.region)
                    .font(.headline)
                Spacer()
                Text(detailed && region.unitText != nil ? "\(region.sampleText) · \(region.unitText ?? "")" : region.sampleText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text3)
            }
            .padding(.bottom, 4)
            if region.viruses.isEmpty {
                Text(region.reason ?? "Keine Abwasserdaten")
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                    .padding(.vertical, 8)
            }
            ForEach(region.viruses) { virus in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(virus.virus)
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: 62, alignment: .leading)
                        Spacer(minLength: 4)
                        VirusLevelTrend(virus: virus)
                    }
                    if detailed, let detail = detailText(virus) {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(BIOSTheme.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 10)
                .overlay(alignment: .top) {
                    Rectangle().fill(BIOSTheme.separator).frame(height: 0.5)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
    }

    private func detailText(_ virus: VirusModel) -> String? {
        var parts: [String] = []
        if let ratio = virus.trendRatio {
            parts.append("\(BIOSFormat.number(ratio, digits: 2))x in 2 Wochen")
        }
        if let pct = virus.pctOfTypicalPeak {
            parts.append("\(BIOSFormat.number(pct)) % eines typischen Höhepunkts")
        }
        if let usual = virus.usualText {
            parts.append(usual)
        }
        if let kw = virus.onsetKW {
            var onset = "Welle typisch ab KW \(kw)"
            if let weeks = virus.weeksUntilOnset, weeks > 0 {
                onset += " (in ca. \(weeks) Wochen)"
            }
            parts.append(onset)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Forecast card: per allergen four level dots with weekday and level word.
struct PollenForecastCard: View {
    let pollen: PollenModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(pollen.place), nächste 4 Tage")
                    .font(.headline)
                Spacer()
                Text("Modell CAMS")
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
            }
            .padding(.bottom, 4)
            if pollen.allergens.isEmpty {
                Text(pollen.reason ?? "Keine Allergene im Profil")
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                    .padding(.vertical, 8)
            }
            ForEach(pollen.allergens) { allergen in
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
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(dayText(day))
                    }
                }
                .padding(.vertical, 10)
                .overlay(alignment: .top) {
                    Rectangle().fill(BIOSTheme.separator).frame(height: 0.5)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
    }

    private func dayText(_ day: PollenDay) -> String {
        let name = day.date.map { BIOSFormat.weekdayShort($0) } ?? ""
        return "\(name) · \(day.level)"
    }
}

/// Allergy block from outlook.json (`active`, `place`, `allergens`, `reasons`).
struct AllergyCard: View {
    let allergy: AllergyModel?
    let names: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Allergie")
                    .font(.headline)
                Spacer()
                if let place = allergy?.place {
                    Text("Heimatort \(place)")
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text3)
                }
            }
            if let allergy {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: allergy.active ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(allergy.active ? BIOSTheme.mid : BIOSTheme.good)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(allergy.active ? "Aktiv" : "Nicht aktiv")
                            .font(.subheadline.weight(.semibold))
                        ForEach(Array(reasons(allergy).enumerated()), id: \.offset) { entry in
                            CaptionText(text: entry.element)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "pills")
                        .foregroundStyle(BIOSTheme.text2)
                    CaptionText(text: allergy.active
                        ? "Die Rezeptbestellung bekommt das Allergiemittel dazu."
                        : "Wird aktiv, sobald ein Allergen mittel erreicht. Dann erscheint hier der Grund, und die Rezeptbestellung bekommt das Allergiemittel dazu.")
                }
            } else {
                CaptionText(text: "Kein Allergie-Status vom Server.")
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
    }

    private func reasons(_ allergy: AllergyModel) -> [String] {
        if !allergy.reasons.isEmpty { return allergy.reasons }
        if allergy.active { return [] }
        let list = names.isEmpty ? "deine Allergene" : names.joined(separator: ", ")
        return ["Keine Belastung ab mittel (\(list)), weder gemessen (7 Tage) noch vorhergesagt."]
    }
}

/// Season hints (flu vaccine, typical wave onset, pollen season).
struct HintsCard: View {
    let hints: [BIOSAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(hints) { hint in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol(hint))
                        .foregroundStyle(color(hint))
                        .frame(width: 22)
                    Text(hint.text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
    }

    private func symbol(_ hint: BIOSAlert) -> String {
        if hint.severity == "warn" { return "exclamationmark.triangle" }
        // API v1: `icon` is an SF Symbol name ("syringe", "allergens", "info.circle").
        if let icon = hint.icon, icon.contains(".") || ["syringe", "allergens", "calendar", "microbe", "pills", "leaf"].contains(icon) {
            return icon
        }
        switch (hint.icon ?? hint.kind).lowercased() {
        case "calendar", "flu_vaccine", "vaccine": return "calendar"
        case "virus", "wave", "season": return "microbe"
        case "flower", "pollen", "allergy": return "camera.macro"
        case "pill", "pills", "meds": return "pills"
        default: return "info.circle"
        }
    }

    private func color(_ hint: BIOSAlert) -> Color {
        if hint.severity == "warn" { return BIOSTheme.bad }
        switch symbol(hint) {
        case "calendar", "syringe": return BIOSTheme.mid
        case "microbe": return BIOSTheme.viren
        case "camera.macro", "allergens", "leaf": return BIOSTheme.pollen
        default: return BIOSTheme.text2
        }
    }
}
