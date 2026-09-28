import SwiftUI

/// Detail "Viren im Abwasser": virus picker, 6/12 months chart (Wien area,
/// Deutschland dashed, both in % of a typical season peak), region rows.
struct VirenDetailView: View {
    @EnvironmentObject var dashboardStore: DashboardStore
    @State private var virus = "COVID"
    @State private var weeks = 26

    var body: some View {
        let dashboard = dashboardStore.dashboard
        let regions = UmweltData.regions(dashboard)
        let names = virusNames(regions)
        let selected = names.contains(virus) ? virus : (names.first ?? virus)
        let wien = regions.first { $0.key == "abwasser_wien" } ?? regions.first
        let wienVirus = wien?.viruses.first { $0.virus == selected }
        let metric = wienVirus?.metric
            ?? regions.flatMap(\.viruses).first { $0.virus == selected }?.metric
            ?? VirenDetailView.fallbackMetric(selected)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                StoreStatusBanner()
                Picker("Virus", selection: $virus) {
                    ForEach(names, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.segmented)

                // One region per /v1/series response (`source`), two requests for the comparison.
                SeriesReader(request: SeriesStore.Request(metric: metric, days: weeks == 26 ? 182 : 365, source: "abwasser_wien")) { wienEntry in
                    SeriesReader(request: SeriesStore.Request(metric: metric, days: weeks == 26 ? 182 : 365, source: "abwasser_de")) { germanyEntry in
                        ChartCard(
                            label: "\(selected) im Abwasser",
                            icon: "microbe",
                            color: BIOSTheme.viren,
                            value: wienVirus?.pctOfTypicalPeak.map { BIOSFormat.number($0) },
                            unit: wienVirus?.pctOfTypicalPeak == nil ? nil : "% \(wien?.region ?? "Wien")",
                            sub: VirenDetailView.subText(wienVirus, wien: wienEntry?.model, weeks: weeks),
                            legend: [
                                LegendItem(color: BIOSTheme.viren, text: "Wien", mark: .line),
                                LegendItem(color: BIOSTheme.germany, text: "Deutschland", mark: .dashed),
                            ]
                        ) {
                            let spec = VirenDetailView.spec(wien: wienEntry?.model, germany: germanyEntry?.model,
                                                           days: weeks == 26 ? 182 : 365)
                            if spec.isEmpty {
                                ChartPlaceholder(
                                    isLoading: wienEntry?.isLoading != false || germanyEntry?.isLoading != false,
                                    message: wienEntry?.error ?? germanyEntry?.error ?? "Keine Verlaufsdaten",
                                    height: 170
                                )
                            } else {
                                BIOSChart(spec: spec)
                                    .accessibilityLabel("\(selected) im Abwasser, Wien und Deutschland, in Prozent eines typischen Saisonhöhepunkts")
                            }
                        }
                    }
                }

                Picker("Zeitraum", selection: $weeks) {
                    Text("6 Monate").tag(26)
                    Text("12 Monate").tag(52)
                }
                .pickerStyle(.segmented)

                ForEach(regions) { region in
                    VirusRegionCard(region: region, detailed: true)
                }

                NoteText(text: "Wien misst Genkopien pro Tag, das RKI (AMELAG) Genkopien pro Liter. Die Skalen sind nicht vergleichbar, darum zeigt das Diagramm beide in % eines typischen Saisonhöhepunkts. Trend: Mittel der letzten 2 Proben gegen die 2 davor, ab 1,5x stark steigend, ab 1,15x leicht steigend.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
    }

    private func virusNames(_ regions: [VirusRegionModel]) -> [String] {
        var names: [String] = []
        for region in regions {
            for virus in region.viruses where !names.contains(virus.virus) {
                names.append(virus.virus)
            }
        }
        return names.isEmpty ? ["COVID", "Grippe", "RSV"] : names
    }

    /// Fine trend + level, plus the mean of the selected range (Wien).
    static func subText(_ virus: VirusModel?, wien: SeriesModel?, weeks: Int) -> String? {
        var lines: [String] = []
        if let virus {
            lines.append("Niveau: \(virus.level)")
            lines.append("Trend: \(VirusLevelTrend.trendWord(virus))")
        }
        let values = (wien?.points ?? []).compactMap { $0.value }
        if !values.isEmpty {
            let mean = values.reduce(0, +) / Double(values.count)
            lines.append("Ø \(weeks == 26 ? "6" : "12") Monate \(BIOSFormat.number(mean)) %")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    static func fallbackMetric(_ virus: String) -> String {
        switch virus.lowercased() {
        case "grippe", "influenza": return "ww_influenza"
        case "rsv": return "ww_rsv"
        default: return "ww_sars_cov2"
        }
    }

    static func spec(wien wienModel: SeriesModel?, germany germanyModel: SeriesModel?, days: Int = 182) -> ChartSpec {
        var spec = ChartSpec()
        let resolution = wienModel?.resolution ?? germanyModel?.resolution ?? "week"
        spec.unit = resolution == "day" ? .day : .week
        spec.rangeDays = wienModel?.days ?? germanyModel?.days ?? days
        // Axis follows the 6/12 months picker, also when a region has fewer samples.
        let now = Date()
        spec.xStart = now.addingTimeInterval(-Double(spec.rangeDays) * 86_400)
        spec.xEnd = now.addingTimeInterval(3.5 * 86_400)
        spec.height = 170
        spec.yMin = 0
        spec.yMax = 100
        spec.ySuffix = " %"
        spec.valueUnit = "%"
        spec.seriesLabels = ["wien": "Wien", "de": "Deutschland"]
        // Both regions always in the bubble; different sample days show the
        // nearest earlier sample with its date.
        spec.seriesOrder = ["wien", "de"]
        spec.refs = [
            ChartRef(id: 0, value: 15, label: "mittel"),
            ChartRef(id: 1, value: 40, label: "hoch"),
            ChartRef(id: 2, value: 75, label: "sehr hoch"),
        ]
        var wien: [SeriesPoint] = wienModel?.points ?? []
        var germany: [SeriesPoint] = germanyModel?.points ?? []
        // Tolerates a combined answer `series: {wien: [...], de: [...]}` as well.
        for (key, points) in wienModel?.regions ?? [:] {
            let name = key.lowercased()
            if name.contains("wien") || name == "at" {
                wien = points
            } else if germany.isEmpty {
                germany = points
            }
        }
        let germanyLine = ChartSpec.linePoints(germany, series: "de", color: BIOSTheme.germany, dashed: true)
        let wienLine = ChartSpec.linePoints(wien, series: "wien", color: BIOSTheme.viren, idOffset: germanyLine.count)
        spec.lines = germanyLine + wienLine
        spec.area = wienLine
        spec.areaColor = BIOSTheme.viren
        spec.showDots = false
        return spec
    }
}

/// Detail "Pollen": forecast cards, per allergen 7 measured days plus the
/// 4 forecast days as lighter bars, thresholds as reference lines, allergy.
struct PollenDetailView: View {
    @EnvironmentObject var dashboardStore: DashboardStore

    var body: some View {
        let dashboard = dashboardStore.dashboard
        let places = UmweltData.pollenPlaces(dashboard)
        let home = places.first
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                StoreStatusBanner()
                if places.isEmpty {
                    NotEvaluableBox(title: "Keine Pollenvorhersage", text: nil)
                }
                ForEach(places) { place in
                    PollenForecastCard(pollen: place)
                }
                if let home {
                    ForEach(home.allergens) { allergen in
                        PollenAllergenChart(allergen: allergen)
                    }
                }
                AllergyCard(
                    allergy: dashboard?.environment?.allergy ?? dashboard?.pollen?.allergy,
                    names: UmweltData.allergenNames(dashboard)
                )
                NoteText(text: "Pollen aus dem CAMS-Modell (Open-Meteo). Gespeichert werden nur abgeschlossene Tage, die Vorhersage kommt live dazu.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
    }
}

struct PollenAllergenChart: View {
    let allergen: PollenAllergen

    var body: some View {
        SeriesReader(request: SeriesStore.Request(metric: "pollen_\(allergen.allergen)", days: 7, source: nil)) { entry in
            let spec = PollenAllergenChart.spec(allergen: allergen, measured: entry?.model)
            ChartCard(
                label: allergen.name,
                icon: "camera.macro",
                color: BIOSTheme.pollen,
                value: allergen.maxLevelText,
                sub: "höchste Stufe\nnächste 4 Tage",
                legend: [
                    LegendItem(color: BIOSTheme.pollen, text: "gemessen"),
                    LegendItem(color: BIOSTheme.pollen, text: "Vorhersage", opacity: 0.5),
                ],
                foot: footText
            ) {
                if spec.isEmpty {
                    ChartPlaceholder(
                        isLoading: entry == nil || entry?.isLoading == true,
                        message: entry?.error ?? "Keine Pollendaten",
                        height: 140
                    )
                } else {
                    BIOSChart(spec: spec)
                        .accessibilityLabel("\(allergen.name)pollen, 7 Tage gemessen und 4 Tage Vorhersage, Körner pro Kubikmeter")
                }
            }
        }
    }

    private var footText: String {
        var text = "Tagesmittel in Körnern/m³."
        if let season = allergen.seasonText {
            text += " Saison typisch \(season)."
        }
        return text
    }

    static func spec(allergen: PollenAllergen, measured: SeriesModel?) -> ChartSpec {
        var spec = ChartSpec()
        spec.unit = .day
        spec.rangeDays = 11
        spec.height = 140
        spec.yMin = 0
        spec.valueUnit = "Körner/m³"
        let calendar = Calendar.current
        let measuredPoints = measured?.points ?? []
        var bars = ChartSpec.barPoints(measuredPoints) { _ in BIOSTheme.pollen }
        let lastMeasured = measuredPoints.filter { $0.value != nil }.map(\.date).max()
        var firstForecast: Date?
        for day in allergen.forecast {
            guard let date = day.date, let mean = day.mean else { continue }
            if let lastMeasured, calendar.startOfDay(for: date) <= calendar.startOfDay(for: lastMeasured) {
                continue
            }
            if firstForecast == nil { firstForecast = date }
            bars.append(ChartBarPoint(id: 1000 + bars.count, date: date, value: mean, color: BIOSTheme.pollen, opacity: 0.5,
                                      label: "Vorhersage"))
        }
        spec.bars = bars
        if let firstForecast {
            spec.marker = ChartMarker(id: 0, date: calendar.startOfDay(for: firstForecast), label: "Vorhersage")
        }
        var refs: [ChartRef] = []
        if let mittel = allergen.thresholdMittel {
            refs.append(ChartRef(id: 0, value: mittel, label: "mittel ab \(BIOSFormat.number(mittel))"))
        }
        if let hoch = allergen.thresholdHoch {
            refs.append(ChartRef(id: 1, value: hoch, label: "hoch ab \(BIOSFormat.number(hoch))"))
        }
        spec.refs = refs
        let maxValue = bars.map(\.value).max() ?? 0
        spec.yMax = max((allergen.thresholdMittel ?? 10) * 1.25, maxValue * 1.15, 1)
        return spec
    }
}
