import SwiftUI

/// Loads one series (memory, disk cache, server) and hands its entry to `content`.
/// Observes only the slot of its own request.
struct SeriesReader<Content: View>: View {
    @EnvironmentObject var series: SeriesStore
    let request: SeriesStore.Request
    @ViewBuilder let content: (SeriesStore.Entry?) -> Content

    var body: some View {
        SeriesSlotReader(slot: series.slot(request), store: series, request: request, content: content)
    }
}

private struct SeriesSlotReader<Content: View>: View {
    @ObservedObject var slot: SeriesSlot
    let store: SeriesStore
    let request: SeriesStore.Request
    let content: (SeriesStore.Entry?) -> Content

    var body: some View {
        content(slot.entry)
            .task(id: request) {
                await store.load(request)
            }
    }
}

/// The daily metric charts of Körper and the detail screens.
enum MetricKind {
    case rhr
    case hrv
    case skinTemp
    case respRate
    case recovery
    case sleep
    case glucoseDaily
    case tir
    case tdd
    case per10g
    case insAuto
    case infectionScore
    /// Body temperature readings entered in the app (`body_temp`, one point per reading).
    case bodyTemp

    var metric: String {
        switch self {
        case .rhr: return "whoop_rhr"
        case .hrv: return "whoop_hrv"
        case .skinTemp: return "whoop_skin_temp"
        case .respRate: return "whoop_resp_rate"
        case .recovery: return "whoop_recovery"
        case .sleep: return "whoop_sleep_duration"
        case .glucoseDaily: return "glucose_daily"
        case .tir: return "tir"
        case .tdd: return "tdd"
        case .per10g: return "ins_per_10g"
        case .insAuto: return "ins_auto"
        case .infectionScore: return "infection_score"
        case .bodyTemp: return "body_temp"
        }
    }

    var label: String {
        switch self {
        case .rhr: return "Ruhepuls"
        case .hrv: return "HRV"
        case .skinTemp: return "Hauttemperatur"
        case .respRate: return "Atemfrequenz"
        case .recovery: return "Recovery"
        case .sleep: return "Schlaf"
        case .glucoseDaily: return "Tages-Ø Glukose"
        case .tir: return "Zeit im Zielbereich"
        case .tdd: return "Gesamtinsulin (TDD)"
        case .per10g: return "Insulin/10 g KH"
        case .insAuto: return "Auto-Bolus (Loop-Korrekturen)"
        case .infectionScore: return "Infekt-Score"
        case .bodyTemp: return "Körpertemperatur"
        }
    }

    var icon: String? {
        switch self {
        case .rhr: return "heart"
        case .hrv: return "waveform.path.ecg"
        case .skinTemp: return "thermometer.medium"
        case .respRate: return "lungs"
        case .recovery: return "heart"
        case .sleep: return "moon"
        case .glucoseDaily, .tir: return "drop"
        case .tdd, .per10g: return "syringe"
        case .insAuto: return nil
        case .infectionScore: return "thermometer.medium"
        case .bodyTemp: return "thermometer"
        }
    }

    var color: Color {
        switch self {
        case .rhr: return BIOSTheme.rhr
        case .hrv: return BIOSTheme.hrv
        case .skinTemp: return BIOSTheme.skin
        case .respRate: return BIOSTheme.resp
        case .recovery: return BIOSTheme.recovery
        case .sleep: return BIOSTheme.sleep
        case .glucoseDaily: return BIOSTheme.glucose
        case .tir: return BIOSTheme.good
        case .tdd: return BIOSTheme.insulin
        case .per10g: return BIOSTheme.per10g
        case .insAuto: return BIOSTheme.auto
        case .infectionScore: return BIOSTheme.skin
        case .bodyTemp: return BIOSTheme.skin
        }
    }

    var unit: String {
        switch self {
        case .rhr: return "bpm"
        case .hrv: return "ms"
        case .skinTemp, .bodyTemp: return "°C"
        case .respRate: return "/min"
        case .recovery, .tir: return "%"
        case .sleep: return "h"
        case .glucoseDaily: return "mg/dL"
        case .tdd, .per10g, .insAuto: return "U"
        case .infectionScore: return "von 100"
        }
    }

    /// Digits of the header value.
    var digits: Int {
        switch self {
        case .skinTemp, .respRate, .sleep, .tdd, .insAuto, .bodyTemp: return 1
        case .per10g: return 2
        default: return 0
        }
    }

    var isBar: Bool {
        switch self {
        case .recovery, .sleep, .tdd, .insAuto, .tir: return true
        default: return false
        }
    }

    /// Glucose and insulin are whole days up to yesterday.
    var isWholeDays: Bool {
        switch self {
        case .glucoseDaily, .tir, .tdd, .per10g, .insAuto: return true
        default: return false
        }
    }

    // MARK: Header texts (follow the 7/28 picker)

    /// Values of the range for the header: TIR uses `tir`, all others `v`; nulls are skipped.
    func rangeValues(_ model: SeriesModel) -> [Double] {
        model.points.compactMap { point -> Double? in
            self == .tir ? (point.tir ?? point.value) : point.value
        }
    }

    private func latestPoint(_ model: SeriesModel) -> (date: Date, value: Double)? {
        for point in model.points.reversed() {
            if let value = self == .tir ? (point.tir ?? point.value) : point.value {
                return (point.date, value)
            }
        }
        return nil
    }

    private func format(_ value: Double, _ model: SeriesModel) -> String {
        if self == .skinTemp, isDeviation(model) {
            return BIOSFormat.signed(value, digits: 1)
        }
        return BIOSFormat.number(value, digits: digits)
    }

    /// Big number: mean over the selected range (temperature: the latest reading).
    func value(_ model: SeriesModel) -> String? {
        if self == .bodyTemp {
            return model.latest?.value.map { BIOSFormat.number($0, digits: 1) }
        }
        let values = rangeValues(model)
        guard !values.isEmpty else { return nil }
        return format(values.reduce(0, +) / Double(values.count), model)
    }

    /// "Ø 28 Tage · 25 von 28 Tagen" and "gestern 127 · Baseline 149".
    func sub(_ model: SeriesModel, days: Int) -> String? {
        let values = rangeValues(model)
        guard !values.isEmpty else { return nil }
        if self == .bodyTemp {
            var first = "letzte Messung"
            if let latest = model.latest {
                first += " " + BIOSFormat.relative(latest.date)
            }
            let count = values.count == 1 ? "1 Messung" : "\(values.count) Messungen"
            let high = values.max().map { " · max \(BIOSFormat.number($0, digits: 1)) °C" } ?? ""
            return first + "\n" + count + high
        }
        let total = model.points.count
        var first = "Ø \(model.days ?? days) Tage"
        if total > 0, values.count < total {
            first += " · \(values.count) von \(total) Tagen"
        }
        var second: [String] = []
        if let latest = latestPoint(model) {
            let unitSuffix = self == .tir ? " %" : (self == .sleep ? " h" : "")
            second.append("\(BIOSFormat.relativeDayOf(latest.date)) \(format(latest.value, model))\(unitSuffix)")
        }
        switch self {
        case .recovery:
            if let latest = latestPoint(model) {
                second.append("Zone \(BIOSZone(key: nil, value: latest.value).word)")
            }
        case .tir:
            second.append("Ziel ≥ 70 %")
        case .insAuto:
            second.append("nur Zusatzinfo")
        default:
            if let median = model.baseline?.median {
                let baselineDigits = self == .per10g ? 2 : digits
                let text = self == .skinTemp && isDeviation(model)
                    ? BIOSFormat.signed(median, digits: 1)
                    : BIOSFormat.number(median, digits: baselineDigits)
                second.append("Baseline \(text)" + (self == .sleep ? " h" : ""))
            }
        }
        return second.isEmpty ? first : first + "\n" + second.joined(separator: " · ")
    }

    /// Skin temperature may come as deviation (around 0) or absolute (around 34).
    private func isDeviation(_ model: SeriesModel) -> Bool {
        let values = model.points.compactMap { $0.value }
        guard let maxAbs = values.map({ abs($0) }).max() else { return true }
        return maxAbs < 10
    }

    // MARK: Chart

    func spec(_ model: SeriesModel, days: Int, compact: Bool) -> ChartSpec {
        var spec = ChartSpec()
        spec.unit = ChartXUnit.from(resolution: model.resolution)
        spec.rangeDays = days
        spec.height = compact ? 124 : 150
        spec.valueUnit = unit
        spec.valueDigits = digits
        let color = self.color
        switch self {
        case .recovery:
            spec.bars = ChartSpec.barPoints(model.points) { BIOSZone(key: nil, value: $0).color }
            spec.yMin = 0
            spec.yMax = 100
            spec.refs = [ChartRef(id: 0, value: 67, label: ""), ChartRef(id: 1, value: 34, label: "")]
            spec.ySuffix = " %"
        case .tir:
            var bars: [ChartBarPoint] = []
            for point in model.points {
                guard let tir = point.tir ?? point.value else { continue }
                let tbr = point.tbr ?? 0
                let tar = point.tar ?? max(0, 100 - tir - tbr)
                bars.append(ChartBarPoint(id: bars.count, date: point.date, value: tbr, color: BIOSTheme.bad, label: "unter 70"))
                bars.append(ChartBarPoint(id: bars.count, date: point.date, value: tir, color: BIOSTheme.good, label: "70 bis 180"))
                bars.append(ChartBarPoint(id: bars.count, date: point.date, value: tar, color: BIOSTheme.mid, label: "über 180"))
            }
            spec.bars = bars
            spec.yMin = 0
            spec.yMax = 100
            // Unlabeled line; "Ziel 70 %" sits in the legend, outside the bars.
            spec.refs = [ChartRef(id: 0, value: 70, label: "")]
            spec.ySuffix = " %"
            spec.height = compact ? 118 : 130
        default:
            if isBar {
                spec.bars = ChartSpec.barPoints(model.points) { _ in color }
            } else {
                let line = ChartSpec.linePoints(model.points, series: metric, color: color)
                spec.lines = line
                spec.area = line
                spec.areaColor = color
            }
            if let band = model.baseline?.band {
                spec.band = ChartBand(lo: band.lo, hi: band.hi, mid: model.baseline?.median, color: color)
            }
            spec.flags = model.flagDates
            spec.contextFlags = model.contextFlagDates
            spec.yDigits = (self == .skinTemp || self == .respRate || self == .per10g) ? 1 : 0
            if self == .infectionScore {
                spec.yMin = 0
                spec.yMax = 100
                spec.valueUnit = ""
            }
            if self == .sleep {
                spec.ySuffix = " h"
                spec.yMin = 0
            }
            if self == .bodyTemp {
                // Single readings: dots on every point, no area, fever lines 37,5 / 38.
                spec.area = []
                spec.showDots = true
                spec.yMin = 35.5
                spec.yMax = 38.5
                spec.refs = model.refs.isEmpty
                    ? [ChartRef(id: 0, value: 37.5, label: "37,5"), ChartRef(id: 1, value: 38, label: "38", trailing: true)]
                    : model.refs
            }
        }
        return spec
    }

    func legend(_ model: SeriesModel) -> [LegendItem] {
        switch self {
        case .recovery:
            return [
                LegendItem(color: BIOSTheme.good, text: "hoch ab 67"),
                LegendItem(color: BIOSTheme.mid, text: "mittel 34 bis 66"),
                LegendItem(color: BIOSTheme.bad, text: "niedrig unter 34"),
            ]
        case .tir:
            return [
                LegendItem(color: BIOSTheme.bad, text: "unter 70"),
                LegendItem(color: BIOSTheme.good, text: "70 bis 180"),
                LegendItem(color: BIOSTheme.mid, text: "über 180"),
                LegendItem(color: Color.white.opacity(0.7), text: "Ziel 70 %", mark: .dashed),
            ]
        default:
            var items: [LegendItem] = []
            if model.baseline?.band != nil {
                items.append(LegendItem(color: color, text: "Baseline-Band", mark: .box, opacity: 0.35))
            }
            if !model.flagDates.isEmpty {
                items.append(LegendItem(color: BIOSTheme.bad, text: "Tag mit Infektmuster", mark: .dot))
            }
            if !model.contextFlagDates.isEmpty {
                items.append(LegendItem(color: BIOSTheme.context, text: "erhöht (Kontext)", mark: .diamond))
            }
            return items
        }
    }
}

extension BIOSFormat {
    /// "heute", "gestern" or "Mi 23.09." for a date.
    static func relativeDayOf(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "heute" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "gestern"
        }
        return dayLabel(date)
    }
}

/// Chart card for one `MetricKind` over 7 or 28 days.
struct MetricChartCard: View {
    let kind: MetricKind
    let days: Int
    var compact: Bool = false

    var body: some View {
        SeriesReader(request: SeriesStore.Request(metric: kind.metric, days: days, source: nil)) { entry in
            let model = entry?.model
            ChartCard(
                label: kind.label,
                icon: kind.icon,
                color: kind.color,
                value: model.flatMap { kind.value($0) },
                unit: model.flatMap { kind.value($0) } == nil ? nil : kind.unit,
                sub: model.flatMap { kind.sub($0, days: days) },
                legend: model.map { kind.legend($0) } ?? []
            ) {
                if let model, model.hasValues {
                    BIOSChart(spec: kind.spec(model, days: days, compact: compact))
                        .accessibilityLabel("\(kind.label), letzte \(days) Tage")
                } else {
                    ChartPlaceholder(
                        isLoading: entry == nil || entry?.isLoading == true,
                        message: entry?.error ?? "Keine Daten für diesen Zeitraum",
                        height: compact ? 124 : 150
                    )
                }
            }
        }
    }
}
