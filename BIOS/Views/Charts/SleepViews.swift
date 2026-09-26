import SwiftUI

/// "Schlaf inkl. Naps": stacked bars main sleep + naps per day
/// (`whoop_sleep_duration`, `whoop_nap_duration`), baseline band of the
/// total (`whoop_sleep_total`, else of the main sleep). Without nap series
/// (older server) it shows the main sleep alone.
struct SleepChartCard: View {
    let days: Int
    var compact: Bool = false

    static let napColor = Color(hex: 0xB9C4FF)

    var body: some View {
        SeriesReader(request: SeriesStore.Request(metric: "whoop_sleep_duration", days: days, source: nil)) { mainEntry in
            SeriesReader(request: SeriesStore.Request(metric: "whoop_nap_duration", days: days, source: nil)) { napEntry in
                SeriesReader(request: SeriesStore.Request(metric: "whoop_sleep_total", days: days, source: nil)) { totalEntry in
                    card(main: mainEntry, nap: napEntry, total: totalEntry)
                }
            }
        }
    }

    @ViewBuilder
    private func card(main: SeriesStore.Entry?, nap: SeriesStore.Entry?, total: SeriesStore.Entry?) -> some View {
        let data = SleepChartData(main: main?.model, nap: nap?.model, total: total?.model)
        ChartCard(
            label: data.hasNaps ? "Schlaf inkl. Naps" : "Schlaf",
            icon: "moon",
            color: BIOSTheme.sleep,
            value: data.meanTotal.map { BIOSFormat.number($0, digits: 1) },
            unit: data.meanTotal == nil ? nil : "h",
            sub: data.subText(days: main?.model?.days ?? days),
            legend: data.legend
        ) {
            if data.spec(days: days, compact: compact).isEmpty {
                ChartPlaceholder(
                    isLoading: main == nil || main?.isLoading == true,
                    message: main?.error ?? "Keine Daten für diesen Zeitraum",
                    height: compact ? 124 : 150
                )
            } else {
                BIOSChart(spec: data.spec(days: days, compact: compact))
                    .accessibilityLabel("Schlaf pro Tag, Hauptschlaf und Naps, letzte \(days) Tage")
            }
        }
    }
}

struct SleepChartData {
    let main: [Date: Double]
    let nap: [Date: Double]
    let dates: [Date]
    let baseline: SeriesBaseline?
    let flags: [Date]

    init(main mainModel: SeriesModel?, nap napModel: SeriesModel?, total totalModel: SeriesModel?) {
        var main: [Date: Double] = [:]
        for point in mainModel?.points ?? [] {
            if let value = point.value { main[point.date] = value }
        }
        var nap: [Date: Double] = [:]
        for point in napModel?.points ?? [] {
            if let value = point.value, value > 0 { nap[point.date] = value }
        }
        self.main = main
        self.nap = nap
        dates = Array(Set(main.keys).union(nap.keys)).sorted()
        baseline = totalModel?.baseline?.band != nil ? totalModel?.baseline : mainModel?.baseline
        flags = mainModel?.flagDates ?? []
    }

    var hasNaps: Bool { !nap.isEmpty }

    private var totals: [Double] {
        dates.map { (main[$0] ?? 0) + (nap[$0] ?? 0) }
    }

    var meanTotal: Double? {
        guard !dates.isEmpty else { return nil }
        return totals.reduce(0, +) / Double(dates.count)
    }

    func subText(days: Int) -> String? {
        guard !dates.isEmpty else { return nil }
        var first = "Ø \(days) Tage"
        if hasNaps { first += " gesamt" }
        var second: [String] = []
        if !main.isEmpty {
            second.append("Haupt \(BIOSFormat.number(main.values.reduce(0, +) / Double(main.count), digits: 1)) h")
        }
        if hasNaps {
            second.append("\(nap.count) Tage mit Nap")
        }
        if let median = baseline?.median {
            second.append("Baseline \(BIOSFormat.number(median, digits: 1)) h")
        }
        return second.isEmpty ? first : first + "\n" + second.joined(separator: " · ")
    }

    var legend: [LegendItem] {
        var items = [LegendItem(color: BIOSTheme.sleep, text: "Hauptschlaf")]
        if hasNaps {
            items.append(LegendItem(color: SleepChartCard.napColor, text: "Nap"))
        }
        if baseline?.band != nil {
            items.append(LegendItem(color: BIOSTheme.sleep, text: hasNaps ? "Baseline gesamt" : "Baseline-Band", mark: .box, opacity: 0.35))
        }
        if !flags.isEmpty {
            items.append(LegendItem(color: BIOSTheme.bad, text: "Tag mit Infektmuster", mark: .dot))
        }
        return items
    }

    func spec(days: Int, compact: Bool) -> ChartSpec {
        var spec = ChartSpec()
        spec.unit = .day
        spec.rangeDays = days
        spec.setDayRange(days: days)
        spec.height = compact ? 124 : 150
        spec.valueUnit = "h"
        spec.valueDigits = 1
        spec.ySuffix = " h"
        spec.yMin = 0
        var bars: [ChartBarPoint] = []
        var totalsOnly: [ChartLinePoint] = []
        for date in dates {
            let mainValue = main[date] ?? 0
            let napValue = nap[date] ?? 0
            bars.append(ChartBarPoint(id: bars.count, date: date, value: mainValue, color: BIOSTheme.sleep, label: "Haupt"))
            if napValue > 0 {
                bars.append(ChartBarPoint(id: bars.count, date: date, value: napValue, color: SleepChartCard.napColor, label: "Nap"))
                totalsOnly.append(ChartLinePoint(id: totalsOnly.count, series: "gesamt-0", date: date,
                                                 value: mainValue + napValue, color: BIOSTheme.text2))
            }
        }
        spec.bars = bars
        // Bubble: "Gesamt" only on days with a nap (else it equals the main sleep).
        spec.bubbleOnly = totalsOnly
        spec.seriesLabels = ["gesamt": "Gesamt"]
        spec.exactOnlySeries = ["gesamt"]
        if let band = baseline?.band {
            spec.band = ChartBand(lo: band.lo, hi: band.hi, mid: baseline?.median, color: BIOSTheme.sleep)
        }
        spec.flags = flags
        return spec
    }
}

/// Recovery detail: main sleep, naps and total of the last Whoop day.
struct SleepBreakdownCard: View {
    let sleep: SleepBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            EyebrowText(text: "Schlaf inkl. Naps")
            StatGrid(columns: 3) {
                StatItem(label: "Hauptschlaf", value: BIOSFormat.number(sleep.mainH, digits: 1), unit: "h")
                StatItem(label: "Naps", value: sleep.hasNaps ? BIOSFormat.number(sleep.napsH, digits: 1) : "keine",
                         unit: sleep.hasNaps ? "h" : nil)
                StatItem(label: "Gesamt", value: BIOSFormat.number(sleep.totalH, digits: 1), unit: "h")
            }
            ForEach(sleep.naps) { nap in
                Label(nap.text.isEmpty ? "Nap" : "Nap \(nap.text)", systemImage: "powersleep")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text2)
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
    }
}
