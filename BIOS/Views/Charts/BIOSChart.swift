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
    /// Name in the scrub bubble ("unter 70", "Vorhersage"), nil = value only.
    var label: String? = nil
}

struct ChartLinePoint: Identifiable {
    let id: Int
    let series: String
    let date: Date
    let value: Double
    let color: Color
    var dashed: Bool = false
    /// Drawn as a square (e.g. clinic blood pressure) instead of a circle.
    var square: Bool = false
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
    /// Label at the trailing end (two close lines keep their labels apart).
    var trailing: Bool = false
}

struct ChartMarker: Identifiable {
    let id: Int
    let date: Date
    let label: String
}

/// The scrubbed x position: snapped date plus the bubble text.
struct ChartSelection: Identifiable {
    let id = 0
    let date: Date
    let lines: [String]
}

struct ChartFlag: Identifiable {
    let id: Int
    let date: Date
    /// Context day (indigo diamond) instead of an episode day (red dot).
    let isContext: Bool
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
    /// Episode days: red dots under the axis.
    var flags: [Date] = []
    /// Context days: indigo diamonds under the axis (shape differs, not only color).
    var contextFlags: [Date] = []
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
    /// Unit and digits of values in the scrub bubble.
    var valueUnit: String = ""
    var valueDigits: Int = 0
    /// Display names of line series in the bubble ("wien" -> "Wien").
    var seriesLabels: [String: String] = [:]
    /// Single points without a line (drawn with the dots, e.g. clinic values).
    var extraPoints: [ChartLinePoint] = []
    /// Values that only appear in the scrub bubble (not drawn), e.g. pulse next to sys/dia.
    var bubbleOnly: [ChartLinePoint] = []
    /// Order of the series in the bubble (names without segment suffix); others follow.
    var seriesOrder: [String] = []
    /// Series shown in the bubble only with a point exactly at the selected x
    /// (e.g. clinic values); all others fall back to their nearest earlier point.
    var exactOnlySeries: Set<String> = []

    var isEmpty: Bool {
        bars.isEmpty && lines.isEmpty && extraPoints.isEmpty
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

/// Chart for one `ChartSpec`. All derived arrays (domains, ticks, dots, the
/// per-series lookup of the scrub bubble) are computed once in
/// `PreparedChart`; the inner view is Equatable on a fingerprint of the data,
/// so a parent re-render with the same data does not rebuild the Chart.
struct BIOSChart: View {
    let spec: ChartSpec

    init(spec: ChartSpec) {
        self.spec = spec
    }

    var body: some View {
        BIOSChartBody(prepared: PreparedChart(spec: spec))
            .equatable()
    }
}

/// One series in the scrub bubble: its points by date (sorted).
struct BubbleTrack {
    let name: String
    let label: String?
    let points: [(date: Date, value: Double)]
    let exactOnly: Bool
}

struct PreparedChart: Equatable {
    let spec: ChartSpec
    let fingerprint: Int
    let yDomain: ClosedRange<Double>
    let xDomain: ClosedRange<Date>
    let flags: [ChartFlag]
    let bands: [ChartBand]
    let mids: [ChartRef]
    let refs: [ChartRef]
    let markers: [ChartMarker]
    let dots: [ChartLinePoint]
    let xTicks: [Date]
    let yTicks: [Double]
    /// Distinct x positions (sorted), the snap targets of the scrub gesture.
    let dates: [Date]
    let distinctDays: Int
    let tracks: [BubbleTrack]

    static func == (lhs: PreparedChart, rhs: PreparedChart) -> Bool {
        lhs.fingerprint == rhs.fingerprint
    }

    init(spec: ChartSpec) {
        self.spec = spec
        fingerprint = PreparedChart.makeFingerprint(spec)
        let allDates = spec.bars.map(\.date) + spec.lines.map(\.date) + spec.extraPoints.map(\.date)
        let dates = Array(Set(allDates)).sorted()
        self.dates = dates
        let calendar = Calendar.current
        distinctDays = Set(dates.map { calendar.startOfDay(for: $0) }).count
        let yDomain = PreparedChart.makeYDomain(spec)
        self.yDomain = yDomain
        let xDomain = PreparedChart.makeXDomain(spec, dates: dates)
        self.xDomain = xDomain

        var flags: [ChartFlag] = []
        for date in spec.flags where xDomain.contains(date) {
            flags.append(ChartFlag(id: flags.count, date: date, isContext: false))
        }
        for date in spec.contextFlags where xDomain.contains(date) {
            flags.append(ChartFlag(id: flags.count, date: date, isContext: true))
        }
        self.flags = flags
        bands = spec.band.map { [$0] } ?? []
        mids = bands.compactMap { band in band.mid.map { ChartRef(id: 0, value: $0, label: "") } }
        refs = spec.refs.filter { yDomain.contains($0.value) }
        markers = spec.marker.map { [$0] } ?? []
        dots = PreparedChart.makeDotPoints(spec)
        xTicks = PreparedChart.makeXTicks(spec.unit, dates: dates)
        yTicks = PreparedChart.makeYTicks(yDomain)
        tracks = PreparedChart.makeTracks(spec)
    }

    // MARK: Bubble

    /// Bubble text at the snapped x: date, then every series. A series without
    /// a point there shows its nearest earlier point with its own date, or
    /// "keine Probe" (exact-only series are left out instead).
    func selectionLines(_ date: Date) -> [String] {
        var lines = [selectionTitle(date)]
        let bars = spec.bars.filter { $0.date == date }
        if bars.count > 1 {
            for bar in bars {
                lines.append("\(bar.label ?? "Wert") \(formatValue(bar.value))")
            }
        } else if let bar = bars.first {
            lines.append((bar.label.map { "\($0) " } ?? "") + formatValue(bar.value))
        }
        let named = tracks.count > 1
        for track in tracks {
            let prefix = track.label.map { "\($0) " } ?? (named ? "\(track.name) " : "")
            if let exact = track.points.last(where: { $0.date == date }) {
                lines.append(prefix + formatValue(exact.value))
                continue
            }
            if track.exactOnly { continue }
            if let earlier = track.points.last(where: { $0.date < date }) {
                lines.append(prefix + formatValue(earlier.value) + " (\(pointDate(earlier.date)))")
            } else {
                lines.append(prefix + "keine Probe")
            }
        }
        if lines.count == 1 {
            lines.append("keine Daten")
        }
        return lines
    }

    func nearestDate(to date: Date) -> Date? {
        guard !dates.isEmpty else { return nil }
        // Binary search in the sorted snap targets.
        var low = 0
        var high = dates.count - 1
        while low < high {
            let mid = (low + high) / 2
            if dates[mid] < date { low = mid + 1 } else { high = mid }
        }
        let candidate = dates[low]
        if low > 0 {
            let previous = dates[low - 1]
            if abs(previous.timeIntervalSince(date)) <= abs(candidate.timeIntervalSince(date)) {
                return previous
            }
        }
        return candidate
    }

    private func selectionTitle(_ date: Date) -> String {
        switch spec.unit {
        case .hour:
            return "\(BIOSFormat.dayLabel(date)), \(BIOSFormat.twoDigits(Calendar.current.component(.hour, from: date))):00"
        case .week:
            return "KW \(Calendar(identifier: .iso8601).component(.weekOfYear, from: date)) · \(BIOSFormat.shortDate(date))"
        case .day:
            // Single readings (blood pressure, temperature) carry a time of day.
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            if (parts.hour ?? 0) != 0 || (parts.minute ?? 0) != 0 {
                return "\(BIOSFormat.dayLabel(date)), \(BIOSFormat.time(date))"
            }
            return BIOSFormat.dayLabel(date)
        }
    }

    private func pointDate(_ date: Date) -> String {
        switch spec.unit {
        case .hour:
            return BIOSFormat.twoDigits(Calendar.current.component(.hour, from: date)) + ":00"
        case .day:
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            if (parts.hour ?? 0) != 0 || (parts.minute ?? 0) != 0 {
                return BIOSFormat.shortDate(date) + " " + BIOSFormat.time(date)
            }
            return BIOSFormat.shortDate(date)
        case .week:
            return BIOSFormat.shortDate(date)
        }
    }

    private func formatValue(_ value: Double) -> String {
        let number = BIOSFormat.number(value, digits: spec.valueDigits)
        return spec.valueUnit.isEmpty ? number : "\(number) \(spec.valueUnit)"
    }

    // MARK: Labels

    func formatX(_ date: Date) -> String {
        switch spec.unit {
        case .hour:
            return BIOSFormat.twoDigits(Calendar.current.component(.hour, from: date)) + ":00"
        case .week:
            return BIOSFormat.monthShort(date)
        case .day:
            return distinctDays <= 8 ? BIOSFormat.weekdayShort(date) : BIOSFormat.shortDate(date)
        }
    }

    func formatY(_ value: Double) -> String {
        BIOSFormat.number(value, digits: spec.yDigits) + spec.ySuffix
    }

    // MARK: Computation (once per spec)

    private static func seriesName(_ series: String) -> String {
        series.components(separatedBy: "-").first ?? series
    }

    private static func makeTracks(_ spec: ChartSpec) -> [BubbleTrack] {
        var order: [String] = []
        var points: [String: [(date: Date, value: Double)]] = [:]
        for point in spec.lines + spec.extraPoints + spec.bubbleOnly {
            let name = seriesName(point.series)
            if points[name] == nil {
                order.append(name)
            }
            points[name, default: []].append((point.date, point.value))
        }
        let ordered = spec.seriesOrder.filter { points[$0] != nil } + order.filter { !spec.seriesOrder.contains($0) }
        return ordered.map { name in
            BubbleTrack(
                name: name,
                label: spec.seriesLabels[name],
                points: (points[name] ?? []).sorted { $0.date < $1.date },
                exactOnly: spec.exactOnlySeries.contains(name)
            )
        }
    }

    private static func makeFingerprint(_ spec: ChartSpec) -> Int {
        var hasher = Hasher()
        hasher.combine(spec.bars.count)
        for bar in spec.bars {
            hasher.combine(bar.date)
            hasher.combine(bar.value)
            hasher.combine(bar.opacity)
            hasher.combine(bar.label)
        }
        hasher.combine(spec.lines.count)
        for point in spec.lines + spec.extraPoints + spec.bubbleOnly {
            hasher.combine(point.series)
            hasher.combine(point.date)
            hasher.combine(point.value)
        }
        hasher.combine(spec.area.count)
        for ref in spec.refs {
            hasher.combine(ref.value)
            hasher.combine(ref.label)
        }
        if let band = spec.band {
            hasher.combine(band.lo)
            hasher.combine(band.hi)
            hasher.combine(band.mid)
        }
        hasher.combine(spec.flags)
        hasher.combine(spec.contextFlags)
        hasher.combine(spec.marker?.date)
        hasher.combine(spec.marker?.label)
        hasher.combine(spec.rangeDays)
        hasher.combine(spec.yMin)
        hasher.combine(spec.yMax)
        hasher.combine(spec.yDigits)
        hasher.combine(spec.ySuffix)
        hasher.combine(Double(spec.height))
        hasher.combine(spec.showDots)
        hasher.combine(spec.valueUnit)
        hasher.combine(spec.valueDigits)
        hasher.combine(spec.seriesOrder)
        hasher.combine(String(describing: spec.unit))
        return hasher.finalize()
    }

    private static func makeYDomain(_ spec: ChartSpec) -> ClosedRange<Double> {
        var values = spec.bars.map(\.value) + spec.lines.map(\.value) + spec.extraPoints.map(\.value)
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

    private static func makeXDomain(_ spec: ChartSpec, dates: [Date]) -> ClosedRange<Date> {
        let calendar = Calendar.current
        guard let first = dates.first, let last = dates.last else {
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

    private static func makeYTicks(_ domain: ClosedRange<Double>) -> [Double] {
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

    private static func makeXTicks(_ unit: ChartXUnit, dates: [Date]) -> [Date] {
        guard !dates.isEmpty else { return [] }
        let calendar = Calendar.current
        switch unit {
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
            return dates.filter { calendar.component(.hour, from: $0) % 6 == 0 }
        case .week:
            // First sample of each month (every second month for long ranges).
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

    /// Endpoints of every line series, plus all points for short series.
    private static func makeDotPoints(_ spec: ChartSpec) -> [ChartLinePoint] {
        if spec.showDots || Set(spec.lines.map(\.date)).count <= 8 {
            return spec.lines + spec.extraPoints
        }
        var lastBySeries: [String: ChartLinePoint] = [:]
        for point in spec.lines {
            let name = seriesName(point.series)
            if let current = lastBySeries[name], current.date >= point.date { continue }
            lastBySeries[name] = point
        }
        return lastBySeries.values.sorted { $0.id < $1.id } + spec.extraPoints
    }
}

struct BIOSChartBody: View, Equatable {
    let prepared: PreparedChart
    /// Snapped date under the finger while scrubbing (nil = not scrubbing).
    @State private var selected: Date?

    static func == (lhs: BIOSChartBody, rhs: BIOSChartBody) -> Bool {
        lhs.prepared == rhs.prepared
    }

    var body: some View {
        let spec = prepared.spec
        let yDomain = prepared.yDomain
        let xDomain = prepared.xDomain
        let selection = selected.map { [ChartSelection(date: $0, lines: prepared.selectionLines($0))] } ?? []

        Chart {
            ForEach(prepared.bands) { band in
                RectangleMark(
                    xStart: .value("Zeit", xDomain.lowerBound),
                    xEnd: .value("Zeit", xDomain.upperBound),
                    yStart: .value("Band unten", band.lo),
                    yEnd: .value("Band oben", band.hi)
                )
                .foregroundStyle(band.color.opacity(0.12))
            }
            ForEach(prepared.mids) { mid in
                RuleMark(y: .value("Median", mid.value))
                    .foregroundStyle((spec.band?.color ?? Color.white).opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            ForEach(prepared.refs) { ref in
                RuleMark(y: .value("Referenz", ref.value))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: ref.trailing ? .trailing : .leading, spacing: 2) {
                        // Pill background: the label stays legible above bars and lines.
                        Text(ref.label)
                            .font(.caption2)
                            .foregroundStyle(BIOSTheme.text2)
                            .padding(.horizontal, ref.label.isEmpty ? 0 : 4)
                            .background(ref.label.isEmpty ? Color.clear : BIOSTheme.card.opacity(0.85), in: Capsule())
                    }
            }
            ForEach(prepared.markers) { marker in
                RuleMark(x: .value("Zeit", marker.date))
                    .foregroundStyle(Color.white.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text(marker.label)
                            .font(.caption2)
                            .foregroundStyle(BIOSTheme.text2)
                            .padding(.horizontal, 4)
                            .background(BIOSTheme.card.opacity(0.85), in: Capsule())
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
            ForEach(prepared.dots) { point in
                PointMark(
                    x: .value("Zeit", point.date),
                    y: .value("Wert", point.value)
                )
                .foregroundStyle(point.color)
                .symbol(point.square ? BasicChartSymbolShape.square : BasicChartSymbolShape.circle)
                .symbolSize(point.square ? 44 : (point.dashed ? 24 : 36))
            }
            ForEach(prepared.flags) { flag in
                PointMark(
                    x: .value("Zeit", flag.date),
                    y: .value("Markierung", yDomain.lowerBound)
                )
                .foregroundStyle(flag.isContext ? BIOSTheme.context : BIOSTheme.bad)
                .symbol(flag.isContext ? BasicChartSymbolShape.diamond : BasicChartSymbolShape.circle)
                .symbolSize(30)
            }
            ForEach(selection) { item in
                RuleMark(x: .value("Auswahl", item.date))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(
                        position: .top,
                        spacing: 0,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        SelectionBubble(lines: item.lines)
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: xDomain)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: prepared.yTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.10))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(prepared.formatY(number))
                            .font(.caption2)
                            .foregroundStyle(BIOSTheme.text3)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: prepared.xTicks) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(prepared.formatX(date))
                            .font(.caption2)
                            .foregroundStyle(BIOSTheme.text3)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                // UIKit long press (0.25 s, 10 pt slack): a vertical pan starts
                // scrolling at once and fails the press; a held finger wins
                // against the scroll view and then drags the selection.
                ScrubGesture(
                    onChange: { x in updateSelection(x: x, proxy: proxy, geometry: geometry) },
                    onEnd: { selected = nil }
                )
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
        .frame(height: spec.height)
    }

    private func updateSelection(x: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geometry[plotFrame].origin
        guard let date = proxy.value(atX: x - origin.x, as: Date.self),
              let nearest = prepared.nearestDate(to: date) else { return }
        if nearest != selected {
            selected = nearest
        }
    }
}

/// Long press, then drag, as a UIKit recognizer on a transparent view. Unlike
/// a SwiftUI gesture inside a ScrollView it never delays the scroll view's pan:
/// moving before 0.25 s fails the press (normal scrolling); once the press is
/// recognized, the pan fails and the finger scrubs.
struct ScrubGesture: UIViewRepresentable {
    var onChange: (CGFloat) -> Void
    var onEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        press.minimumPressDuration = 0.25
        press.allowableMovement = 10
        press.cancelsTouchesInView = false
        view.addGestureRecognizer(press)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ScrubGesture

        init(parent: ScrubGesture) {
            self.parent = parent
        }

        @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                parent.onChange(recognizer.location(in: recognizer.view).x)
            case .ended, .cancelled, .failed:
                parent.onEnd()
            default:
                break
            }
        }
    }
}

/// Scrub bubble: date on top, values below.
struct SelectionBubble: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { entry in
                Text(entry.element)
                    .font(entry.offset == 0 ? .caption2 : .caption.weight(.semibold))
                    .foregroundStyle(entry.offset == 0 ? BIOSTheme.text2 : BIOSTheme.text1)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(hex: 0x2C2F37), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
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
