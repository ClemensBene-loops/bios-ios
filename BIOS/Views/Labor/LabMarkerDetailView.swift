import Charts
import SwiftUI

/// Marker detail: big value with the lab's reference bar (and the goal tick),
/// history chart (HbA1c with the GMI of the 90 days before each lab date as a
/// dashed line), daily data next to it, a neutral link to the body map region
/// and the table of measurements with their source document.
struct LabMarkerDetailView: View {
    let markerID: String
    @ObservedObject private var store = LabStore.shared
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let detail = store.marker(markerID) {
                    content(detail)
                } else if let error = store.markerErrors[markerID] {
                    NotEvaluableBox(title: "Nicht geladen", text: error)
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Verlauf wird geladen")
                            .font(.subheadline)
                            .foregroundStyle(BIOSTheme.text2)
                    }
                    .biosCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.loadMarker(markerID)
        }
        .task {
            store.primeMarker(markerID)
            await store.loadMarker(markerID)
        }
    }

    private var title: String {
        store.marker(markerID)?.marker.name
            ?? store.overview?.allMarkers.first { $0.id == markerID }?.name
            ?? "Laborwert"
    }

    @ViewBuilder
    private func content(_ detail: LabMarkerDetail) -> some View {
        if detail.isCombined {
            LabCombinedDetailContent(detail: detail, region: store.overview?.region(forGroup: detail.marker.group)) { region in
                router.showBodyMapRegion(region)
            }
        } else if detail.marker.hidden {
            VStack(alignment: .leading, spacing: 12) {
                Text(detail.marker.name)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                NotEvaluableBox(title: "Nur im Befund",
                                text: detail.marker.hiddenReason
                                    ?? "In der Praxis gemessen, nur im jeweiligen Befund sichtbar. Deine eigenen Messungen stehen unter Werte > Eigene Messungen.")
            }
        } else if detail.isDevice {
            LabDeviceDetailContent(detail: detail, region: store.overview?.region(forGroup: detail.marker.group)) { region in
                router.showBodyMapRegion(region)
            }
        } else {
            labContent(detail)
        }
    }

    @ViewBuilder
    private func labContent(_ detail: LabMarkerDetail) -> some View {
        let marker = detail.marker
        let latest = detail.latest

        VStack(alignment: .leading, spacing: 2) {
            Text(headerLine(detail))
                .font(.footnote)
                .foregroundStyle(BIOSTheme.text2)
            Text(marker.name)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)

        if let latest {
            LabValueCard(marker: marker, point: latest, target: detail.target)
        } else {
            NotEvaluableBox(title: "Noch kein Wert", text: "Für diesen Marker gibt es noch keinen bestätigten Wert.")
        }

        if detail.history.contains(where: { $0.value != nil && $0.date != nil }) {
            LabHistoryChartCard(detail: detail)
        }

        LabContextCard(detail: detail, region: store.overview?.region(forGroup: marker.group)) { region in
            router.showBodyMapRegion(region)
        }

        if !detail.history.isEmpty {
            measurements(detail)
        }

        if detail.refs.count > 1 {
            refsCard(detail)
        }

        Text(detail.disclaimer ?? "Anzeige und Entscheidungshilfe, keine Diagnose.")
            .font(.footnote)
            .foregroundStyle(BIOSTheme.text2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private func headerLine(_ detail: LabMarkerDetail) -> String {
        var parts: [String] = []
        if let group = detail.marker.groupLabel { parts.append(group) }
        if let date = detail.latest?.date { parts.append(LabFormat.fullDate(date)) }
        if detail.marker.custom { parts.append("eigener Marker") }
        return parts.joined(separator: " · ")
    }

    private func measurements(_ detail: LabMarkerDetail) -> some View {
        let marker = detail.marker
        let points = Array(detail.history.reversed())
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Messungen")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let due = nextDue {
                    Text(due)
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text3)
                }
            }
            ForEach(points) { point in
                let row = HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(point.date.map { LabFormat.fullDate($0) } ?? (point.dateRaw ?? "ohne Datum"))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(BIOSTheme.text1)
                        Text(source(point))
                            .font(.caption)
                            .foregroundStyle(BIOSTheme.text2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(valueWithUnit(point, marker: marker))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(BIOSTheme.text1)
                    if let tag = point.status.tag, point.status.isFlagged {
                        LabTag(text: tag, style: LabTag.style(for: point.status))
                    }
                    if point.documentID != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BIOSTheme.text3)
                    }
                }
                .contentShape(Rectangle())
                if let documentID = point.documentID {
                    NavigationLink(value: LabRoute.document(documentID)) {
                        row
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Öffnet das Dokument")
                } else {
                    row
                }
            }
        }
        .biosCard()
    }

    private func refsCard(_ detail: LabMarkerDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Referenzbereiche der Labore")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(detail.refs) { ref in
                HStack {
                    Text(LabFormat.refRange(low: ref.refLow, high: ref.refHigh, decimals: detail.marker.decimals,
                                            unit: ref.unit) ?? (ref.refText ?? "ohne Angabe"))
                        .font(.subheadline)
                        .foregroundStyle(BIOSTheme.text1)
                    Spacer(minLength: 6)
                    Text(refPeriod(ref))
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text2)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .biosCard()
    }

    private func refPeriod(_ ref: LabRefSpan) -> String {
        let from = BIOSDate.day(ref.from).map { BIOSFormat.shortDate($0) }
        let to = BIOSDate.day(ref.to).map { LabFormat.fullDate($0) }
        var text = [from, to].compactMap { $0 }.joined(separator: " bis ")
        if let n = ref.n { text += text.isEmpty ? "\(n) Werte" : " · \(n) Werte" }
        return text
    }

    private func source(_ point: LabPoint) -> String {
        guard let documentID = point.documentID else { return "ohne Dokument" }
        guard let document = store.listEntry(documentID) else { return "Befund" }
        if let issuer = document.issuer {
            return "\(document.displayTitle) · \(issuer)"
        }
        return document.displayTitle
    }

    private func valueWithUnit(_ point: LabPoint, marker: LabMarkerInfo) -> String {
        let value = LabFormat.value(point.value, decimals: marker.decimals, comparator: point.comparator, text: point.valueText)
        guard let unit = point.unit ?? marker.unit, !unit.isEmpty else { return value }
        return "\(value) \(unit)"
    }

    /// "nächste fällig 15.12.2026" from the due list.
    private var nextDue: String? {
        guard let item = store.overview?.due.first(where: { $0.id == markerID || $0.markers.contains(markerID) }),
              let due = BIOSDate.day(item.dueOn) else { return nil }
        return "nächste fällig \(LabFormat.fullDate(due))"
    }
}

/// Big value, tag, reference bar with the goal tick, printed value if converted.
struct LabValueCard: View {
    let marker: LabMarkerInfo
    let point: LabPoint
    let target: LabTarget?

    var body: some View {
        let scale = LabBarScale(point: point, target: target)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(LabFormat.value(point.value, decimals: marker.decimals, comparator: point.comparator, text: point.valueText))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit = point.unit ?? marker.unit {
                    Text(unit)
                        .font(.title3)
                        .foregroundStyle(BIOSTheme.text2)
                }
                Spacer(minLength: 6)
                if let tag = point.status.tag {
                    LabTag(text: tagText(tag), style: LabTag.style(for: point.status))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenValue)

            if scale != nil {
                VStack(spacing: 4) {
                    LabRangeBar(scale: scale, status: point.status, height: 8, dotSize: 14)
                    if let scale {
                        HStack {
                            Text(LabFormat.value(scale.lower, decimals: point.usesZScore ? 0 : marker.decimals))
                            Spacer()
                            Text(LabFormat.value(scale.upper, decimals: point.usesZScore ? 0 : marker.decimals))
                        }
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(BIOSTheme.text3)
                        .accessibilityHidden(true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .biosCard()
    }

    private func tagText(_ tag: String) -> String {
        switch point.status {
        case .hoch: return "über Referenz"
        case .niedrig: return "unter Referenz"
        default: return tag
        }
    }

    private var spokenValue: String {
        let value = LabFormat.value(point.value, decimals: marker.decimals, comparator: point.comparator, text: point.valueText)
        var text = "\(marker.name) \(value) \(point.unit ?? marker.unit ?? "")"
        if !point.status.spoken.isEmpty { text += ", \(point.status.spoken)" }
        return text
    }

    private var lines: [String] {
        var result: [String] = []
        if point.usesZScore, let z = point.zScore {
            var text = "z-Wert \(BIOSFormat.signed(z, digits: 2)), Grenze (LLN) \(BIOSFormat.signed(-1.645, digits: 2))"
            if let pct = point.pctPredicted { text += ", \(BIOSFormat.number(pct)) % vom Sollwert" }
            result.append(text)
        } else if let ref = LabFormat.refRange(low: point.refLow, high: point.refHigh, decimals: marker.decimals,
                                               unit: point.unit ?? marker.unit) {
            result.append("Labor-Referenz \(ref) (grünes Band).")
        } else {
            result.append("Das Labor gibt keinen Referenzbereich an.")
        }
        if let target {
            let goal = LabFormat.refRange(low: target.low, high: target.high, decimals: marker.decimals,
                                          unit: target.unit ?? point.unit ?? marker.unit) ?? ""
            var text = "Dein Therapieziel \(goal) (weißer Strich)"
            if let status = target.statusText { text += ": \(status)" }
            result.append(text + ".")
        }
        if point.converted, let raw = point.valueRaw, let unitRaw = point.unitRaw, unitRaw != point.unit {
            var text = "Im Befund: \(LabFormat.plain(raw)) \(unitRaw)"
            if let refText = point.refText { text += ", Referenz \(refText)" }
            result.append(text + ", umgerechnet.")
        }
        if let flag = point.labFlag, point.status == .auffaellig {
            result.append("Vom Labor markiert (\(flag)).")
        }
        return result
    }
}

/// History chart (Swift Charts): lab values, GMI dashed, reference band, goal line.
struct LabHistoryChartCard: View {
    let detail: LabMarkerDetail
    /// Snapped lab date under the finger while scrubbing (nil = not scrubbing).
    @State private var selected: Date?

    private struct ChartPoint: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let isLast: Bool
        var comparator: String? = nil
        var status: LabValueStatus = .unknown
    }

    var body: some View {
        let labPoints = makeLabPoints()
        let gmiPoints = makeGMIPoints()
        let tick = detail.target?.tick
        let yRange = yScale(lab: labPoints, gmi: gmiPoints, tick: tick)
        let band = referenceBand(in: yRange)
        let xRange = xScale(labPoints + gmiPoints)
        let status = detail.latest?.status ?? .unknown
        VStack(alignment: .leading, spacing: 10) {
            Text(labPoints.count > 1 ? "Verlauf" : "Bisher ein Wert")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Chart {
                if let band {
                    RectangleMark(
                        xStart: .value("Von", xRange.lowerBound),
                        xEnd: .value("Bis", xRange.upperBound),
                        yStart: .value("Referenz unten", band.low),
                        yEnd: .value("Referenz oben", band.high)
                    )
                    .foregroundStyle(BIOSTheme.good.opacity(0.13))
                    .accessibilityHidden(true)
                }
                if let tick {
                    RuleMark(y: .value("Ziel", tick))
                        .foregroundStyle(BIOSTheme.mid.opacity(0.75))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .accessibilityHidden(true)
                }
                ForEach(gmiPoints) { point in
                    LineMark(
                        x: .value("Datum", point.date),
                        y: .value("Wert", point.value),
                        series: .value("Reihe", "GMI")
                    )
                    .foregroundStyle(BIOSTheme.glucose)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [4, 3]))
                    .accessibilityHidden(true)
                    PointMark(
                        x: .value("Datum", point.date),
                        y: .value("Wert", point.value)
                    )
                    .foregroundStyle(BIOSTheme.glucose)
                    .symbolSize(22)
                    .accessibilityLabel("GMI, 90 Tage vor \(LabFormat.fullDate(point.date))")
                    .accessibilityValue("\(LabFormat.value(point.value, decimals: detail.marker.decimals)) \(gmiUnit)")
                }
                ForEach(labPoints) { point in
                    LineMark(
                        x: .value("Datum", point.date),
                        y: .value("Wert", point.value),
                        series: .value("Reihe", "Labor")
                    )
                    .foregroundStyle(BIOSTheme.text1)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .accessibilityHidden(true)
                    PointMark(
                        x: .value("Datum", point.date),
                        y: .value("Wert", point.value)
                    )
                    .foregroundStyle(point.isLast ? status.tint : BIOSTheme.text1)
                    .symbolSize(point.isLast || point.date == selected ? 70 : 34)
                    .accessibilityLabel("Labor, \(LabFormat.fullDate(point.date))")
                    .accessibilityValue(spokenValue(point))
                }
                if let selected {
                    LabSelectionRule(date: selected, lines: selectionLines(selected, lab: labPoints, gmi: gmiPoints))
                }
            }
            .chartYScale(domain: yRange)
            .chartXScale(domain: xRange)
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.10))
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(LabFormat.plain(number))
                                .font(.caption2)
                                .foregroundStyle(BIOSTheme.text3)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text("\(BIOSFormat.monthShort(date)) \(String(Calendar.current.component(.year, from: date) % 100))")
                                .font(.caption2)
                                .foregroundStyle(BIOSTheme.text3)
                        }
                    }
                }
            }
            .labChartScrub(selected: $selected, dates: labPoints.map(\.date) + gmiPoints.map(\.date))
            .frame(height: 200)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Verlauf \(detail.marker.name)")

            LegendView(items: legend(hasGMI: !gmiPoints.isEmpty, hasBand: band != nil, hasTick: tick != nil))
        }
        .biosCard()
    }

    private func makeLabPoints() -> [ChartPoint] {
        let usable = detail.history.filter { $0.value != nil && $0.date != nil }
        return usable.enumerated().compactMap { index, point in
            guard let date = point.date, let value = point.value else { return nil }
            return ChartPoint(id: "lab-\(point.id)", date: date, value: value, isLast: index == usable.count - 1,
                              comparator: point.comparator, status: point.status)
        }
    }

    private func makeGMIPoints() -> [ChartPoint] {
        detail.history.compactMap { point in
            guard let date = point.date, let gmi = point.gmi, gmi.evaluable, let value = gmi.value else { return nil }
            return ChartPoint(id: "gmi-\(point.id)", date: date, value: value, isLast: false)
        }
    }

    /// The lab's newest reference, clipped to the visible scale (an open side
    /// runs to the edge of the chart).
    private func referenceBand(in range: ClosedRange<Double>) -> (low: Double, high: Double)? {
        guard let latest = detail.latest, !latest.usesZScore else { return nil }
        let low = latest.refLow ?? detail.refs.last?.refLow
        let high = latest.refHigh ?? detail.refs.last?.refHigh
        guard low != nil || high != nil else { return nil }
        let clippedLow = max(range.lowerBound, low ?? range.lowerBound)
        let clippedHigh = min(range.upperBound, high ?? range.upperBound)
        guard clippedHigh > clippedLow else { return nil }
        return (clippedLow, clippedHigh)
    }

    /// Values, GMI and goal; the reference bounds widen the scale only when
    /// they lie close to the values (a far bound would squash the line).
    private func yScale(lab: [ChartPoint], gmi: [ChartPoint], tick: Double?) -> ClosedRange<Double> {
        var values = lab.map(\.value) + gmi.map(\.value)
        if let tick { values.append(tick) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let span = max(high - low, abs(high) * 0.2, 0.5)
        var lower = low - span * 0.25
        var upper = high + span * 0.25
        if let latest = detail.latest, !latest.usesZScore {
            if let refLow = latest.refLow, refLow < lower, refLow >= low - span * 1.5 { lower = refLow - span * 0.1 }
            if let refHigh = latest.refHigh, refHigh > upper, refHigh <= high + span * 1.5 { upper = refHigh + span * 0.1 }
        }
        if low >= 0 && lower < 0 { lower = 0 }
        return lower...upper
    }

    private func xScale(_ points: [ChartPoint]) -> ClosedRange<Date> {
        let dates = points.map(\.date)
        guard let first = dates.min(), let last = dates.max() else {
            let now = Date()
            return now.addingTimeInterval(-86_400 * 30)...now
        }
        let pad: TimeInterval = first == last ? 86_400 * 45 : max(86_400 * 10, last.timeIntervalSince(first) * 0.06)
        return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
    }

    private func legend(hasGMI: Bool, hasBand: Bool, hasTick: Bool) -> [LegendItem] {
        var items = [LegendItem(color: BIOSTheme.text1, text: "Labor", mark: .line)]
        if hasGMI {
            items.append(LegendItem(color: BIOSTheme.glucose, text: "GMI aus CGM, 90 Tage davor", mark: .dashed))
        }
        if hasBand {
            items.append(LegendItem(color: BIOSTheme.good, text: "Labor-Referenz", mark: .box, opacity: 0.35))
        }
        if hasTick {
            items.append(LegendItem(color: BIOSTheme.mid, text: "Ziel", mark: .dashed))
        }
        return items
    }

    private var unit: String {
        detail.latest?.unit ?? detail.marker.unit ?? ""
    }

    private var gmiUnit: String {
        detail.history.lazy.compactMap { $0.gmi?.unit }.first ?? "%"
    }

    private func valueText(_ point: ChartPoint) -> String {
        let value = LabFormat.value(point.value, decimals: detail.marker.decimals, comparator: point.comparator)
        return unit.isEmpty ? value : "\(value) \(unit)"
    }

    /// Scrub bubble: lab date, the lab value(s) with unit and status, the GMI of that date.
    private func selectionLines(_ date: Date, lab: [ChartPoint], gmi: [ChartPoint]) -> [String] {
        var lines = [LabFormat.fullDate(date)]
        let labAtDate = lab.filter { $0.date == date }
        let gmiAtDate = gmi.filter { $0.date == date }
        let named = !gmiAtDate.isEmpty
        for point in labAtDate {
            lines.append((named ? "Labor " : "") + valueText(point) + LabChartText.statusSuffix(point.status))
        }
        for point in gmiAtDate {
            lines.append("GMI \(LabFormat.value(point.value, decimals: detail.marker.decimals)) \(gmiUnit)")
        }
        return lines
    }

    private func spokenValue(_ point: ChartPoint) -> String {
        var text = valueText(point)
        if !point.status.spoken.isEmpty { text += ", " + point.status.spoken }
        return text
    }
}

/// "Neben Tagesdaten": GMI and time in range for HbA1c, neutral body map link.
struct LabContextCard: View {
    let detail: LabMarkerDetail
    let region: String?
    let openRegion: (String) -> Void
    @ObservedObject private var bodyMap = BodyMapStore.shared

    var body: some View {
        let gmi = detail.gmiLink
        if gmi != nil || region != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Neben Tagesdaten")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let gmi {
                    gmiRow(gmi)
                    if let tir = gmi.tirPct, gmi.evaluable {
                        row(symbol: "clock", color: BIOSTheme.good,
                            title: "Zeit im Zielbereich",
                            subtitle: "70 bis 180 mg/dL, gleicher Zeitraum",
                            value: "\(BIOSFormat.number(tir)) %")
                    }
                }
                if let region {
                    Button {
                        openRegion(region)
                    } label: {
                        HStack(spacing: 12) {
                            icon("figure.stand", color: BIOSTheme.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Körperkarte")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(BIOSTheme.text1)
                                Text("Region \(regionLabel(region))")
                                    .font(.caption)
                                    .foregroundStyle(BIOSTheme.text2)
                            }
                            Spacer(minLength: 6)
                            Text("Öffnen")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BIOSTheme.accent)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Körperkarte, Region \(regionLabel(region)) öffnen")
                    .accessibilityHint("Laborwerte färben die Körperkarte nicht")
                }
            }
            .biosCard()
        }
    }

    @ViewBuilder
    private func gmiRow(_ gmi: LabGMI) -> some View {
        let title = gmi.label ?? "GMI aus CGM, letzte 90 Tage"
        if gmi.evaluable, let value = gmi.value {
            row(symbol: "waveform.path.ecg", color: BIOSTheme.glucose, title: title,
                subtitle: gmiSubtitle(gmi, value: value),
                value: "\(LabFormat.value(value, decimals: 1)) \(gmi.unit ?? "%")")
        } else {
            row(symbol: "circle.dashed", color: BIOSTheme.text2, title: title,
                subtitle: gmi.reason ?? "nicht bewertbar", value: "n. v.")
        }
    }

    private func gmiSubtitle(_ gmi: LabGMI, value: Double) -> String {
        var parts: [String] = []
        if let latest = detail.latest?.value, detail.marker.id == "hba1c" {
            let difference = latest - value
            parts.append("Differenz zum Labor \(BIOSFormat.signed(difference, digits: 1)) Punkte")
        }
        if let coverage = gmi.coveragePct {
            parts.append("CGM-Abdeckung \(BIOSFormat.number(coverage)) %")
        }
        return parts.isEmpty ? "aus dem Sensor, nur zum Vergleich" : parts.joined(separator: " · ")
    }

    private func row(symbol: String, color: Color, title: String, subtitle: String, value: String) -> some View {
        HStack(spacing: 12) {
            icon(symbol, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BIOSTheme.text1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(BIOSTheme.text1)
        }
        .accessibilityElement(children: .combine)
    }

    private func icon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.subheadline)
            .foregroundStyle(color)
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }

    private func regionLabel(_ id: String) -> String {
        if let label = bodyMap.model?.regions.first(where: { $0.id == id })?.label {
            return label
        }
        switch id {
        case "stoffwechsel": return "Stoffwechsel"
        case "herz": return "Herz und Gefäße"
        case "niere": return "Niere"
        case "leber": return "Leber"
        case "abwehr": return "Abwehr"
        case "lunge": return "Lunge"
        case "knochen": return "Knochen"
        case "kopf_schlaf": return "Kopf und Schlaf"
        default: return id
        }
    }
}
