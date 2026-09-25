import Charts
import SwiftUI

// Generic chart for all BIOS series: bars (also stacked, e.g. TIR), lines
// (gaps split into segments), one gradient area, a baseline band, reference
// lines, flag dots under the axis and one vertical marker. Everything is
// prepared as plain arrays, the Chart body only iterates them (no `if` in the
// chart builder, which keeps the type checker fast and the API surface small).

struct ChartBarPoint: Identifiable {
    let id: Int
    let date: Date
    let value: Double
    let color: Color
    var opacity: Double = 1
}

struct ChartLinePoint: Identifiable {
    let id: Int
    let series: String
    let date: Date
    let value: Double
    let color: Color
    var dashed: Bool = false
}

struct ChartBand: Identifiable {
    let id = 0
    let lo: Double
    let hi: Double
    let mid: Double?
    let color: Color
}

struct ChartRef: Identifiable {
    let id: Int
    let value: Double
    let label: String
}

struct ChartMarker: Identifiable {
    let id: Int
    let date: Date
    let label: String
}

struct ChartFlag: Identifiable {
    let id: Int
    let date: Date
}

enum ChartXUnit {
    case hour
    case day
    case week

    var component: Calendar.Component {
        switch self {
        case .hour: return .hour
        case .day: return .day
        case .week: return .weekOfYear
        }
    }

    static func from(resolution: String) -> ChartXUnit {
        switch resolution {
        case "hour": return .hour
        case "week": return .week
        default: return .day
        }
    }
}

struct ChartSpec {
    var bars: [ChartBarPoint] = []
    var lines: [ChartLinePoint] = []
    /// Points of the one series that gets a gradient area underneath.
    var area: [ChartLinePoint] = []
    var areaColor: Color = .clear
    var band: ChartBand?
    var refs: [ChartRef] = []
    var flags: [Date] = []
    var flagColor: Color = BIOSTheme.bad
    var marker: ChartMarker?
    var unit: ChartXUnit = .day
    /// Requested range in days (label density: 7 -> weekdays, more -> dates).
    var rangeDays: Int = 7
    var yMin: Double?
    var yMax: Double?
    var yDigits: Int = 0
    var ySuffix: String = ""
    var height: CGFloat = 150
    /// Dots on every line point (short series).
    var showDots: Bool = false

    var isEmpty: Bool {
        bars.isEmpty && lines.isEmpty
    }

    // MARK: Builders

    /// Splits a series at gaps into line segments ("<name>-<segment>").
    static func linePoints(_ points: [SeriesPoint], series: String, color: Color, dashed: Bool = false,
                           idOffset: Int = 0) -> [ChartLinePoint] {
        var result: [ChartLinePoint] = []
        var segment = 0
        var previousWasGap = false
        for point in points {
            guard let value = point.value else {
                if !result.isEmpty { previousWasGap = true }
                continue
            }
            if previousWasGap {
                segment += 1
                previousWasGap = false
            }
            result.append(ChartLinePoint(
                id: idOffset + result.count,
                series: "\(series)-\(segment)",
                date: point.date,
                value: value,
                color: color,
                dashed: dashed
            ))
        }
        return result
    }

    static func barPoints(_ points: [SeriesPoint], idOffset: Int = 0,
                          color: (Double) -> Color) -> [ChartBarPoint] {
        var result: [ChartBarPoint] = []
        for point in points {
            guard let value = point.value else { continue }
            result.append(ChartBarPoint(id: idOffset + result.count, date: point.date, value: value, color: color(value)))
        }
        return result
    }
}

struct BIOSChart: View {
    let spec: ChartSpec

    var body: some View {
        let yDomain = computeYDomain()
        let xDomain = computeXDomain()
        let flags = flagMarks(xDomain: xDomain)
        let bands = spec.band.map { [$0] } ?? []
        let mids = bands.compactMap { band in band.mid.map { ChartRef(id: 0, value: $0, label: "") } }
        let refs = spec.refs.filter { yDomain.contains($0.value) }
        let markers = spec.marker.map { [$0] } ?? []
        let dots = dotPoints()

        Chart {
            ForEach(bands) { band in
                RectangleMark(
                    xStart: .value("Zeit", xDomain.lowerBound),
                    xEnd: .value("Zeit", xDomain.upperBound),
                    yStart: .value("Band unten", band.lo),
                    yEnd: .value("Band oben", band.hi)
                )
                .foregroundStyle(band.color.opacity(0.12))
            }
            ForEach(mids) { mid in
                RuleMark(y: .value("Median", mid.value))
                    .foregroundStyle((spec.band?.color ?? Color.white).opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            ForEach(refs) { ref in
                RuleMark(y: .value("Referenz", ref.value))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(ref.label)
                            .font(.caption2)
                            .foregroundStyle(BIOSTheme.text3)
                    }
            }
            ForEach(markers) { marker in
                RuleMark(x: .value("Zeit", marker.date))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(marker.label)
                            .font(.caption2)
                            .foregroundStyle(BIOSTheme.text3)
                    }
            }
            ForEach(spec.bars) { bar in
                BarMark(
                    x: .value("Zeit", bar.date, unit: spec.unit.component),
                    y: .value("Wert", bar.value)
                )
                .foregroundStyle(bar.color.opacity(bar.opacity))
                .cornerRadius(3)
            }
            ForEach(spec.area) { point in
                AreaMark(
                    x: .value("Zeit", point.date),
                    yStart: .value("Basis", yDomain.lowerBound),
                    yEnd: .value("Wert", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [spec.areaColor.opacity(0.30), spec.areaColor.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            ForEach(spec.lines) { point in
                LineMark(
                    x: .value("Zeit", point.date),
                    y: .value("Wert", point.value),
                    series: .value("Serie", point.series)
                )
                .foregroundStyle(point.color)
                .lineStyle(StrokeStyle(
                    lineWidth: point.dashed ? 1.8 : 2.2,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: point.dashed ? [5, 4] : []
                ))
            }
            ForEach(dots) { point in
                PointMark(
                    x: .value("Zeit", point.date),
                    y: .value("Wert", point.value)
                )
                .foregroundStyle(point.color)
                .symbolSize(point.dashed ? 24 : 36)
            }
            ForEach(flags) { flag in
                PointMark(
                    x: .value("Zeit", flag.date),
                    y: .value("Markierung", yDomain.lowerBound)
                )
                .foregroundStyle(spec.flagColor)
                .symbolSize(30)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: xDomain)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: yTicks(yDomain)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.10))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(formatY(number))
                            .font(.caption2)
                            .foregroundStyle(BIOSTheme.text3)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xTicks()) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(formatX(date))
                            .font(.caption2)
                            .foregroundStyle(BIOSTheme.text3)
                    }
                }
            }
        }
        .frame(height: spec.height)
    }

    // MARK: - Scales

    private var allDates: [Date] {
        spec.bars.map(\.date) + spec.lines.map(\.date)
    }

    private func computeYDomain() -> ClosedRange<Double> {
        var values = spec.bars.map(\.value) + spec.lines.map(\.value)
        if !spec.bars.isEmpty {
            // Stacked bars: the sum per date is the top.
            var sums: [Date: Double] = [:]
            for bar in spec.bars {
                sums[bar.date, default: 0] += bar.value
            }
            values.append(contentsOf: sums.values)
            values.append(0)
        }
        if let band = spec.band {
            values.append(band.lo)
            values.append(band.hi)
        }
        var low = values.min() ?? 0
        var high = values.max() ?? 1
        if high - low < 1e-9 {
            high += 1
            low -= 1
        }
        let pad = (high - low) * 0.14
        low = spec.yMin ?? (spec.bars.isEmpty ? low - pad : min(0, low))
        high = max(spec.yMax ?? (high + pad), low + 1e-6)
        if let yMax = spec.yMax, let dataMax = values.max(), dataMax > yMax {
            high = dataMax * 1.05
        }
        return low...high
    }

    private func computeXDomain() -> ClosedRange<Date> {
        let calendar = Calendar.current
        guard let first = allDates.min(), let last = allDates.max() else {
            let now = Date()
            return now.addingTimeInterval(-86_400)...now
        }
        switch spec.unit {
        case .day:
            let start = calendar.startOfDay(for: first)
            let endDay = calendar.startOfDay(for: last)
            let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? last.addingTimeInterval(43_200)
            return start...end
        case .hour:
            return first.addingTimeInterval(-1_800)...last.addingTimeInterval(1_800)
        case .week:
            return first.addingTimeInterval(-3.5 * 86_400)...last.addingTimeInterval(3.5 * 86_400)
        }
    }

    private func yTicks(_ domain: ClosedRange<Double>) -> [Double] {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0, span.isFinite else { return [] }
        let raw = span / 3
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let step: Double
        if normalized < 1.5 {
            step = 1 * magnitude
        } else if normalized < 3 {
            step = 2 * magnitude
        } else if normalized < 7 {
            step = 5 * magnitude
        } else {
            step = 10 * magnitude
        }
        var ticks: [Double] = []
        var tick = (domain.lowerBound / step).rounded(.up) * step
        while tick <= domain.upperBound + 1e-9, ticks.count < 8 {
            ticks.append(tick)
            tick += step
        }
        return ticks
    }

    private func xTicks() -> [Date] {
        let dates = Array(Set(allDates)).sorted()
        guard !dates.isEmpty else { return [] }
        switch spec.unit {
        case .day:
            if dates.count <= 8 { return dates }
            // Every 7th day counted back from the newest, so today is labeled.
            var ticks: [Date] = []
            var index = dates.count - 1
            while index >= 0 {
                ticks.append(dates[index])
                index -= 7
            }
            return ticks.reversed()
        case .hour:
            let calendar = Calendar.current
            return dates.filter { calendar.component(.hour, from: $0) % 6 == 0 }
        case .week:
            // First sample of each month (every second month for long ranges).
            let calendar = Calendar.current
            var ticks: [Date] = []
            var lastMonth = -1
            for date in dates {
                let month = calendar.component(.month, from: date)
                if month != lastMonth {
                    lastMonth = month
                    if dates.count <= 30 || month % 2 == 1 {
                        ticks.append(date)
                    }
                }
            }
            return ticks
        }
    }

    private func formatX(_ date: Date) -> String {
        switch spec.unit {
        case .hour:
            return BIOSFormat.twoDigits(Calendar.current.component(.hour, from: date)) + ":00"
        case .week:
            return BIOSFormat.monthShort(date)
        case .day:
            let distinctDays = Set(allDates.map { Calendar.current.startOfDay(for: $0) }).count
            return distinctDays <= 8 ? BIOSFormat.weekdayShort(date) : BIOSFormat.shortDate(date)
        }
    }

    private func formatY(_ value: Double) -> String {
        BIOSFormat.number(value, digits: spec.yDigits) + spec.ySuffix
    }

    private func flagMarks(xDomain: ClosedRange<Date>) -> [ChartFlag] {
        var result: [ChartFlag] = []
        for date in spec.flags where xDomain.contains(date) {
            result.append(ChartFlag(id: result.count, date: date))
        }
        return result
    }

    /// Endpoints of every line segment set, plus all points for short series.
    private func dotPoints() -> [ChartLinePoint] {
        if spec.showDots || Set(spec.lines.map(\.date)).count <= 8 {
            return spec.lines
        }
        var lastBySeries: [String: ChartLinePoint] = [:]
        for point in spec.lines {
            let name = point.series.components(separatedBy: "-").first ?? point.series
            if let current = lastBySeries[name], current.date >= point.date { continue }
            lastBySeries[name] = point
        }
        return Array(lastBySeries.values)
    }
}

/// Card around a chart: colored label with icon, big value, right-aligned
/// sub text, chart, legend, footnote (mockup "chartCard").
struct ChartCard<Inner: View>: View {
    let label: String
    let icon: String?
    let color: Color
    var value: String?
    var unit: String?
    var sub: String?
    var legend: [LegendItem] = []
    var foot: String?
    @ViewBuilder let chart: () -> Inner

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let icon {
                            Image(systemName: icon)
                        }
                        Text(label)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    if let value {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(value)
                                .font(.title2.bold())
                                .monospacedDigit()
                            if let unit {
                                Text(unit)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BIOSTheme.text2)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                if let sub {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text2)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
            chart()
            if !legend.isEmpty {
                LegendView(items: legend)
            }
            if let foot {
                Text(foot)
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .biosCard()
    }
}

/// Placeholder while a series loads or when it has no data.
struct ChartPlaceholder: View {
    let isLoading: Bool
    let message: String?
    var height: CGFloat = 150

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            if isLoading {
                ProgressView()
            } else {
                Label(message ?? "Keine Daten", systemImage: "circle.dashed")
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
        .frame(height: height)
    }
}
