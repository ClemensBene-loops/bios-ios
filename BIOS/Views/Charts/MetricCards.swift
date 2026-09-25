import SwiftUI

/// Loads one series (memory, disk cache, server) and hands its entry to `content`.
struct SeriesReader<Content: View>: View {
    @EnvironmentObject var series: SeriesStore
    let request: SeriesStore.Request
    @ViewBuilder let content: (SeriesStore.Entry?) -> Content

    var body: some View {
        content(series.entry(request))
            .task(id: request) {
                await series.load(request)
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
        }
    }

    var unit: String {
        switch self {
        case .rhr: return "bpm"
        case .hrv: return "ms"
        case .skinTemp: return "°C"
        case .respRate: return "/min"
        case .recovery, .tir: return "%"
        case .sleep: return "h"
        case .glucoseDaily: return "mg/dL"
        case .tdd, .per10g, .insAuto: return "U"
        }
    }

    /// Digits of the header value.
    var digits: Int {
        switch self {
        case .skinTemp, .respRate, .sleep, .tdd, .insAuto: return 1
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

    /// Flags mean "infection pattern" (Whoop) or "elevated, context only" (glucose/insulin).
    var flagIsContext: Bool {
        switch self {
        case .glucoseDaily, .tdd, .per10g: return true
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

    // MARK: Header texts

    func value(_ model: SeriesModel) -> String? {
        if self == .tir {
            guard let tir = model.points.last(where: { $0.tir != nil || $0.value != nil }) else { return nil }
            return BIOSFormat.number(tir.tir ?? tir.value, digits: 0)
        }
        guard let latest = model.latest?.value else { return nil }
        if self == .skinTemp, isDeviation(model) {
            return BIOSFormat.signed(latest, digits: 1)
        }
        return BIOSFormat.number(latest, digits: digits)
    }

    func sub(_ model: SeriesModel) -> String? {
        let latestPoint: SeriesPoint? = self == .tir
            ? model.points.last(where: { $0.tir != nil || $0.value != nil })
            : model.latest
        let dayPrefix = latestPoint.map { BIOSFormat.relativeDayOf($0.date) } ?? ""
        switch self {
        case .recovery:
            return "Zone \(BIOSZone(key: nil, value: model.latest?.value).word)"
        case .tir:
            return [dayPrefix, "70 bis 180 mg/dL"].filter { !$0.isEmpty }.joined(separator: ", ")
        case .insAuto:
            return "nur Zusatzinfo"
        case .skinTemp where isDeviation(model):
            return "Abweichung zur Baseline"
        default:
            break
        }
        guard let median = model.baseline?.median else {
            return isWholeDays ? dayPrefix : nil
        }
        var parts: [String] = []
        if isWholeDays, !dayPrefix.isEmpty { parts.append(dayPrefix) }
        let baselineDigits = self == .per10g ? 2 : digits
        let unitSuffix = self == .sleep ? " h" : ""
        parts.append("Baseline \(BIOSFormat.number(median, digits: baselineDigits))\(unitSuffix)")
        if let latest = model.latest?.value {
            switch self {
            case .hrv, .tdd, .per10g:
                if median > 0 {
                    parts.append(BIOSFormat.signed((latest / median - 1) * 100) + " %")
                }
            case .sleep:
                break
            default:
                parts.append(BIOSFormat.signed(latest - median, digits: digits))
            }
        }
        return parts.joined(separator: " · ")
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
                bars.append(ChartBarPoint(id: bars.count, date: point.date, value: tbr, color: BIOSTheme.bad))
                bars.append(ChartBarPoint(id: bars.count, date: point.date, value: tir, color: BIOSTheme.good))
                bars.append(ChartBarPoint(id: bars.count, date: point.date, value: tar, color: BIOSTheme.mid))
            }
            spec.bars = bars
            spec.yMin = 0
            spec.yMax = 100
            spec.refs = [ChartRef(id: 0, value: 70, label: "Ziel 70 %")]
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
            spec.flagColor = flagIsContext ? BIOSTheme.context : BIOSTheme.bad
            spec.yDigits = (self == .skinTemp || self == .respRate || self == .per10g) ? 1 : 0
            if self == .sleep {
                spec.ySuffix = " h"
                spec.yMin = 0
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
            ]
        default:
            var items: [LegendItem] = []
            if model.baseline?.band != nil {
                items.append(LegendItem(color: color, text: "Baseline-Band", mark: .box, opacity: 0.35))
            }
            if !model.flagDates.isEmpty {
                items.append(flagIsContext
                    ? LegendItem(color: BIOSTheme.context, text: "erhöht (Kontext)", mark: .dot)
                    : LegendItem(color: BIOSTheme.bad, text: "Tag mit Infektmuster", mark: .dot))
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
                sub: model.flatMap { kind.sub($0) },
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
