import SwiftUI

// Körpertemperatur (readings entered in the app, `GET /v1/series?metric=body_temp`):
// Körper card with the shared 7/28 range, detail "Temperatur" with 24 h to 1 year,
// one dot per reading (colored normal / erhöht / Fieber), daily maximum as line on
// the long ranges, reference lines 37,5 "erhöht" and 38 "Fieber" (context only,
// never an alarm), scrub bubble with time, value and method. Whoop skin temperature
// is shown as its own chart (absolute skin temperature, different scale).

/// Range of the temperature charts. `days` is what the server is asked for.
enum TemperatureRange: Int, CaseIterable, Identifiable {
    case day = 1
    case week = 7
    case month = 28
    case quarter = 90
    case year = 365

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .day: return "24 h"
        case .week: return "7 T"
        case .month: return "28 T"
        case .quarter: return "90 T"
        case .year: return "1 J"
        }
    }

    var longTitle: String {
        switch self {
        case .day: return "24 Stunden"
        case .week: return "7 Tage"
        case .month: return "28 Tage"
        case .quarter: return "90 Tage"
        case .year: return "1 Jahr"
        }
    }

    /// Local days requested from the server (24 h spans today and yesterday).
    var requestDays: Int { self == .day ? 2 : rawValue }

    /// Long ranges draw the daily maximum as line, single readings as dots.
    var usesDailyMax: Bool { rawValue > 28 }

    static func from(days: Int) -> TemperatureRange {
        TemperatureRange(rawValue: days) ?? (days <= 7 ? .week : .month)
    }
}

enum TemperatureLevel {
    case normal
    case erhoeht
    case fieber

    static let elevated = 37.5
    static let fever = 38.0

    /// Server `level` first, else the fixed lines.
    init(level: String?, value: Double?) {
        switch level {
        case "fieber": self = .fieber
        case "erhoeht": self = .erhoeht
        case "normal": self = .normal
        default:
            let v = value ?? 0
            self = v >= TemperatureLevel.fever ? .fieber : (v >= TemperatureLevel.elevated ? .erhoeht : .normal)
        }
    }

    var color: Color {
        switch self {
        case .normal: return BIOSTheme.skin
        case .erhoeht: return BIOSTheme.mid
        case .fieber: return BIOSTheme.bad
        }
    }

    var word: String? {
        switch self {
        case .normal: return nil
        case .erhoeht: return "erhöht"
        case .fieber: return "Fieber"
        }
    }

    var symbol: String {
        switch self {
        case .normal: return "checkmark.circle"
        case .erhoeht: return "eye"
        case .fieber: return "exclamationmark.triangle"
        }
    }
}

extension SeriesPoint {
    var temperatureLevel: TemperatureLevel { TemperatureLevel(level: level, value: value) }
}

enum TemperatureChart {
    /// Readings shown for a range (24 h: the last 24 hours only).
    static func shownReadings(_ model: SeriesModel, range: TemperatureRange, now: Date = Date()) -> [SeriesPoint] {
        let points = model.points.filter { $0.value != nil }
        guard range == .day else { return points }
        let start = now.addingTimeInterval(-86_400)
        return points.filter { $0.date >= start }
    }

    /// Daily maxima: the server's `daily`, else computed from the readings.
    static func dailyMax(_ model: SeriesModel, readings: [SeriesPoint]) -> [(date: Date, value: Double)] {
        if !model.daily.isEmpty {
            return model.daily.compactMap { day -> (date: Date, value: Double)? in
                guard let value = day.value else { return nil }
                // The line runs through the reading that was the maximum.
                let at = day.maxAt ?? readings.last(where: {
                    Calendar.current.isDate($0.date, inSameDayAs: day.date) && $0.value == value
                })?.date ?? day.date
                return (date: at, value: value)
            }
        }
        var best: [Date: SeriesPoint] = [:]
        for point in readings {
            guard let value = point.value else { continue }
            let day = Calendar.current.startOfDay(for: point.date)
            if let current = best[day], (current.value ?? 0) >= value { continue }
            best[day] = point
        }
        return best.values.sorted { $0.date < $1.date }.compactMap { point -> (date: Date, value: Double)? in
            guard let value = point.value else { return nil }
            return (date: point.date, value: value)
        }
    }

    static func spec(_ model: SeriesModel, range: TemperatureRange, compact: Bool, now: Date = Date()) -> ChartSpec {
        var spec = ChartSpec()
        spec.height = compact ? 124 : 170
        spec.valueUnit = "°C"
        spec.valueDigits = 1
        spec.yDigits = 1
        spec.rangeDays = range.rawValue
        if range == .day {
            spec.unit = .hour
            spec.exactTimes = true
            spec.xStart = now.addingTimeInterval(-86_400)
            spec.xEnd = now
        } else {
            spec.unit = .day
            spec.setDayRange(days: range.rawValue, now: now)
        }
        let readings = shownReadings(model, range: range, now: now)
        var notes: [Date: String] = [:]
        for point in readings {
            var parts: [String] = []
            if let method = point.method, !method.isEmpty { parts.append(method) }
            if let word = point.temperatureLevel.word { parts.append(word) }
            if !parts.isEmpty { notes[point.date] = parts.joined(separator: " · ") }
        }
        spec.bubbleNotes = notes

        if range.usesDailyMax {
            // Line through the daily maxima, every reading as a colored dot on top.
            let maxima = dailyMax(model, readings: readings)
            let maxDates = Set(maxima.map(\.date))
            spec.lines = segments(maxima, name: "max", color: BIOSTheme.skin.opacity(0.75))
            spec.extraPoints = readings.enumerated().compactMap { index, point -> ChartLinePoint? in
                guard let value = point.value else { return nil }
                let name = maxDates.contains(point.date) ? "max-x" : "mess-x"
                return ChartLinePoint(id: 100_000 + index, series: name, date: point.date, value: value,
                                      color: point.temperatureLevel.color)
            }
            spec.seriesLabels = ["max": "Tagesmax", "mess": "Messung"]
            spec.seriesOrder = ["max", "mess"]
            spec.exactOnlySeries = ["max", "mess"]
        } else {
            let values: [(date: Date, value: Double)] = readings.compactMap { point -> (date: Date, value: Double)? in
                guard let value = point.value else { return nil }
                return (date: point.date, value: value)
            }
            spec.lines = segments(values, name: "temp", color: BIOSTheme.skin.opacity(0.75))
            // Same track name as the line: the bubble shows each reading once.
            spec.extraPoints = readings.enumerated().compactMap { index, point -> ChartLinePoint? in
                guard let value = point.value else { return nil }
                return ChartLinePoint(id: 100_000 + index, series: "temp-x", date: point.date, value: value,
                                      color: point.temperatureLevel.color)
            }
            spec.exactOnlySeries = ["temp"]
        }
        spec.flags = model.flagDates
        spec.refs = model.refs.isEmpty
            ? [ChartRef(id: 0, value: TemperatureLevel.elevated, label: "37,5 erhöht"),
               ChartRef(id: 1, value: TemperatureLevel.fever, label: "38 Fieber", trailing: true)]
            : model.refs
        let values = readings.compactMap(\.value)
        spec.yMin = Swift.min(35.5, (values.min() ?? 36) - 0.3)
        spec.yMax = Swift.max(38.5, (values.max() ?? 38) + 0.3)
        return spec
    }

    /// Line segments, broken where two readings are more than 2 days apart.
    private static func segments(_ values: [(date: Date, value: Double)], name: String, color: Color) -> [ChartLinePoint] {
        var result: [ChartLinePoint] = []
        var segment = 0
        var previous: Date?
        for (date, value) in values.sorted(by: { $0.date < $1.date }) {
            if let previous, date.timeIntervalSince(previous) > 2 * 86_400 { segment += 1 }
            previous = date
            result.append(ChartLinePoint(id: result.count, series: "\(name)-\(segment)", date: date, value: value,
                                         color: color))
        }
        return result
    }

    static func legend(_ model: SeriesModel, range: TemperatureRange) -> [LegendItem] {
        var items: [LegendItem] = [LegendItem(color: BIOSTheme.skin, text: "Messung", mark: .dot)]
        if range.usesDailyMax {
            items.append(LegendItem(color: BIOSTheme.skin, text: "Tagesmaximum", mark: .line))
        }
        items.append(LegendItem(color: BIOSTheme.mid, text: "ab 37,5 erhöht", mark: .dot))
        items.append(LegendItem(color: BIOSTheme.bad, text: "ab 38 Fieber", mark: .dot))
        if !model.flagDates.isEmpty {
            items.append(LegendItem(color: BIOSTheme.bad, text: "Tag mit Infektmuster", mark: .dot))
        }
        return items
    }

    /// Newest reading: `last` of the server (any age), else the newest point.
    static func last(_ model: SeriesModel) -> SeriesPoint? {
        model.lastReading ?? model.latest
    }

    /// "heute 07:40 · infrarot · erhöht"
    static func lastLine(_ point: SeriesPoint) -> String {
        var parts = [BIOSFormat.relative(point.date)]
        if let method = point.method, !method.isEmpty { parts.append(method) }
        if let word = point.temperatureLevel.word { parts.append(word) }
        return parts.joined(separator: " · ")
    }

    /// "5 Messungen · max 38,2 °C" for the range.
    static func rangeLine(_ readings: [SeriesPoint]) -> String? {
        let values = readings.compactMap(\.value)
        guard let high = values.max() else { return nil }
        let count = values.count == 1 ? "1 Messung" : "\(values.count) Messungen"
        return count + " · max \(BIOSFormat.number(high, digits: 1)) °C"
    }
}

/// Chart card of the body temperature for one range (Körper: compact).
struct TemperatureChartCard: View {
    let range: TemperatureRange
    var compact: Bool = false

    var body: some View {
        SeriesReader(request: SeriesStore.Request(metric: "body_temp", days: range.requestDays, source: nil)) { entry in
            if let model = entry?.model {
                content(model, entry: entry)
            } else if let error = entry?.error {
                // Server without the series (or offline without cache): last value from the dashboard.
                TemperatureFallbackCard(message: error)
            } else {
                ChartCard(label: "Körpertemperatur", icon: "thermometer", color: BIOSTheme.skin) {
                    ChartPlaceholder(isLoading: true, message: nil, height: compact ? 124 : 170)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ model: SeriesModel, entry: SeriesStore.Entry?) -> some View {
        let readings = TemperatureChart.shownReadings(model, range: range)
        let last = TemperatureChart.last(model)
        let sub = [last.map { TemperatureChart.lastLine($0) }, TemperatureChart.rangeLine(readings)]
            .compactMap { $0 }.joined(separator: "\n")
        ChartCard(
            label: "Körpertemperatur",
            icon: "thermometer",
            color: BIOSTheme.skin,
            value: last?.value.map { BIOSFormat.number($0, digits: 1) },
            unit: last?.value == nil ? nil : "°C",
            sub: sub.isEmpty ? nil : sub,
            legend: readings.isEmpty ? [] : TemperatureChart.legend(model, range: range)
        ) {
            if readings.isEmpty {
                ChartPlaceholder(
                    isLoading: entry?.isLoading == true,
                    message: last == nil ? "Noch keine Messung eingetragen" : "Keine Messung in \(range.longTitle)",
                    height: compact ? 124 : 170
                )
            } else {
                BIOSChart(spec: TemperatureChart.spec(model, range: range, compact: compact))
                    .accessibilityLabel("Körpertemperatur, \(range.longTitle), \(readings.count) Messungen")
            }
        }
    }
}

/// Fallback without the `body_temp` series: last reading and today's maximum from `/v1/dashboard`.
struct TemperatureFallbackCard: View {
    @EnvironmentObject var dashboardStore: DashboardStore
    let message: String

    var body: some View {
        let vitals = dashboardStore.dashboard?.vitals
        ChartCard(
            label: "Körpertemperatur",
            icon: "thermometer",
            color: BIOSTheme.skin,
            value: vitals?.temperature.map { BIOSFormat.number($0, digits: 1) },
            unit: vitals?.temperature == nil ? nil : "°C",
            sub: fallbackSub(vitals)
        ) {
            ChartPlaceholder(isLoading: false, message: "Verlauf nicht verfügbar: \(message)", height: 90)
        }
    }

    private func fallbackSub(_ vitals: DashboardVitalsModel?) -> String? {
        var lines: [String] = []
        if let at = vitals?.temperatureAt { lines.append("letzte Messung " + BIOSFormat.relative(at)) }
        if let max = vitals?.temperatureTodayMax { lines.append("heute max \(BIOSFormat.number(max, digits: 1)) °C") }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// "Temperatur eintragen" button, opens the quick log sheet (same view as the "+" on Heute).
struct TemperatureLogButton: View {
    @State private var showLog = false

    var body: some View {
        Button {
            showLog = true
        } label: {
            Label("Temperatur eintragen", systemImage: "plus.circle")
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityHint("Öffnet die Eingabe für eine neue Messung")
        .sheet(isPresented: $showLog) {
            QuickLogSheet(start: .temperature)
                .environmentObject(EventStore.shared)
                .environmentObject(SupplementStore.shared)
                .environmentObject(MedicationStore.shared)
                .environmentObject(MedicationPlanStore.shared)
                .environmentObject(VitalsStore.shared)
                .environmentObject(DashboardStore.shared)
                .environmentObject(SeriesStore.shared)
                .environment(\.locale, BIOSFormat.locale)
        }
    }
}

/// Körper section "Temperatur": header with "Details", card over the shared 7/28 range,
/// entry button. Always shown (also before the first reading, so the entry is findable).
struct BodyTemperatureSection: View {
    let days: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Temperatur", route: .temperatur)
            TemperatureChartCard(range: TemperatureRange.from(days: days), compact: true)
            TemperatureLogButton()
                .padding(.horizontal, 4)
        }
    }
}

/// Detail "Temperatur": last reading, range picker 24 h to 1 year, chart, readings list,
/// Whoop skin temperature as a separate chart.
struct TemperatureDetailView: View {
    @AppStorage(RangeSetting.key) private var sharedDays = 7
    @State private var range: TemperatureRange?

    var body: some View {
        let current = range ?? TemperatureRange.from(days: sharedDays)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                StoreStatusBanner()
                SeriesReader(request: SeriesStore.Request(metric: "body_temp", days: current.requestDays, source: nil)) { entry in
                    if let model = entry?.model, let last = TemperatureChart.last(model) {
                        TemperatureSummaryCard(last: last, model: model)
                    }
                }
                Picker("Zeitraum", selection: Binding(get: { current }, set: { range = $0 })) {
                    ForEach(TemperatureRange.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                TemperatureChartCard(range: current)
                TemperatureLogButton()
                    .padding(.horizontal, 4)

                SeriesReader(request: SeriesStore.Request(metric: "body_temp", days: current.requestDays, source: nil)) { entry in
                    if let model = entry?.model {
                        TemperatureReadingsList(readings: TemperatureChart.shownReadings(model, range: current))
                    }
                }

                SectionHeader(title: "Zum Vergleich")
                MetricChartCard(kind: .skinTemp, days: current == .day ? 7 : current.rawValue)
                NoteText(text: "Whoop misst die Hauttemperatur im Schlaf, eine eigene Größe mit eigener Achse (keine Körpertemperatur). Grenzen 37,5 °C erhöht und 38 °C Fieber sind nur Kontext zum Infekt-Check und ändern keinen Alarm. Punkte: jede eingetragene Messung, bei 90 Tagen und 1 Jahr verbindet die Linie das Tagesmaximum.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
    }
}

/// Last reading, big: value, time, method, level.
struct TemperatureSummaryCard: View {
    let last: SeriesPoint
    let model: SeriesModel

    var body: some View {
        let level = last.temperatureLevel
        let today = model.points.filter { Calendar.current.isDateInToday($0.date) }.compactMap(\.value)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EyebrowText(text: "Letzte Messung")
                Spacer()
                Text(BIOSFormat.relative(last.date))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text3)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(BIOSFormat.number(last.value, digits: 1))
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                Text("°C")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BIOSTheme.text2)
                Spacer()
                Label(level.word ?? "unter 37,5", systemImage: level.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(level == .normal ? BIOSTheme.text2 : level.color)
            }
            StatGrid(columns: 3) {
                StatItem(label: "Methode", value: last.method ?? "n. v.")
                StatItem(label: "Heute max", value: BIOSFormat.number(today.max(), digits: 1), unit: "°C")
                StatItem(label: "Heute", value: today.count == 1 ? "1 Messung" : "\(today.count) Messungen")
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .accessibilityElement(children: .combine)
        .biosCard()
    }
}

/// Readings of the range, newest first.
struct TemperatureReadingsList: View {
    let readings: [SeriesPoint]

    var body: some View {
        if !readings.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Messungen")
                    .font(.headline)
                    .padding(.bottom, 6)
                ForEach(Array(readings.reversed().prefix(80))) { point in
                    let level = point.temperatureLevel
                    HStack(spacing: 10) {
                        Image(systemName: level == .normal ? "thermometer.medium" : level.symbol)
                            .foregroundStyle(level.color)
                            .frame(width: 22)
                        Text(BIOSFormat.relative(point.date))
                            .font(.footnote)
                            .foregroundStyle(BIOSTheme.text2)
                        if let method = point.method {
                            Text(method)
                                .font(.caption)
                                .foregroundStyle(BIOSTheme.text3)
                        }
                        Spacer(minLength: 8)
                        Text("\(BIOSFormat.number(point.value, digits: 1)) °C")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) {
                        Rectangle().fill(BIOSTheme.separator).frame(height: 0.5)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(BIOSFormat.relative(point.date)), \(BIOSFormat.number(point.value, digits: 1)) Grad\(point.method.map { ", \($0)" } ?? "")\(level.word.map { ", \($0)" } ?? "")")
                }
            }
            .foregroundStyle(BIOSTheme.text1)
            .biosCard()
        }
    }
}
