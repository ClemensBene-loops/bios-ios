import Charts
import SwiftUI

// Device marker "Blutzucker (Fingerstich)" (`kind: "messgeraet"`, id
// `bg_fingerstick`): every fingerstick entered as a calibration in the Dexcom
// app. No lab, no reference range, no goal: the detail shows the readings over
// time (with time of day), their origin, and the comparison with the last CGM
// value before each fingerstick (`links[]` kind `cgm_vergleich`). Observation only.

/// Detail content of a device marker (inside the marker detail's stack).
struct LabDeviceDetailContent: View {
    let detail: LabMarkerDetail
    let region: String?
    let openRegion: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headerLine)
                .font(.footnote)
                .foregroundStyle(BIOSTheme.text2)
            Text(detail.marker.name)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)

        if let latest = detail.latest {
            LabDeviceValueCard(marker: detail.marker, point: latest, count: detail.history.count)
        } else {
            NotEvaluableBox(title: "Noch kein Wert",
                            text: "Sobald du in der Dexcom-App einen Fingerstich als Kalibrierung einträgst, erscheint er hier.")
        }

        if detail.history.contains(where: { $0.value != nil && $0.when != nil }) {
            LabDeviceChartCard(detail: detail)
        }

        if let comparison = detail.cgmComparison {
            LabCGMComparisonCard(comparison: comparison)
        }

        if region != nil {
            LabContextCard(detail: detail, region: region, openRegion: openRegion)
        }

        if !detail.history.isEmpty {
            LabDeviceReadingsCard(detail: detail)
        }

        Text(detail.disclaimer ?? "Anzeige und Entscheidungshilfe, keine Diagnose.")
            .font(.footnote)
            .foregroundStyle(BIOSTheme.text2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var headerLine: String {
        var parts: [String] = []
        if let group = detail.marker.groupLabel { parts.append(group) }
        parts.append("Messgerät")
        return parts.joined(separator: " · ")
    }
}

/// Big latest value with its time and origin; no reference bar.
struct LabDeviceValueCard: View {
    let marker: LabMarkerInfo
    let point: LabPoint
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.title3)
                    .foregroundStyle(BIOSTheme.text2)
                Spacer(minLength: 6)
                LabTag(text: "Messgerät", style: .grey, symbol: "drop")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(marker.name) \(value) \(unit), \(when), ohne Referenzbereich")

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

    private var value: String {
        LabFormat.value(point.value, decimals: marker.decimals, comparator: point.comparator, text: point.valueText)
    }

    private var unit: String {
        point.unit ?? marker.unit ?? "mg/dL"
    }

    private var when: String {
        if let measured = point.measuredAt { return "gemessen " + BIOSFormat.timestamp(measured) }
        if let date = point.date { return "gemessen am " + LabFormat.fullDate(date) }
        return "ohne Zeitangabe"
    }

    private var lines: [String] {
        var result: [String] = []
        var first = when.prefix(1).uppercased() + String(when.dropFirst())
        if let origin = point.originLabel ?? marker.sourceLabel { first += " · " + origin }
        result.append(first)
        result.append("Fingerstich vom Messgerät, als Kalibrierung in der Dexcom-App eingetragen. Kein Laborwert, daher ohne Referenzbereich und ohne Ziel.")
        if count > 1 {
            result.append("\(count) Fingerstiche insgesamt.")
        }
        return result
    }
}

/// Readings over time (x = date and time of day). Hold and drag shows one reading
/// (same scrubbing as the other charts of the app).
struct LabDeviceChartCard: View {
    let detail: LabMarkerDetail
    var note = "Jeder Punkt ist ein Fingerstich, mit Datum und Uhrzeit. Gedrückt halten und ziehen zeigt den Wert."
    /// Snapped time under the finger while scrubbing (nil = not scrubbing).
    @State private var selected: Date?

    private struct Reading: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let origin: String?
        /// Lab value of the merged "Blutzucker" (drawn as a square).
        let lab: Bool
        /// Measured with a time of day (fingerstick, capillary); lab values carry only the day.
        let timed: Bool
        let comparator: String?
        let status: LabValueStatus
        let inTarget: Bool?
    }

    var body: some View {
        let readings = makeReadings()
        let focusID = selected == nil ? readings.last?.id : nil
        let target = chartTarget
        let yRange = yScale(readings, target: target)
        let xRange = xScale(readings)
        let targetBand = target.flatMap { $0.drawsBand ? $0.band(in: yRange) : nil }
        VStack(alignment: .leading, spacing: 10) {
            Text(readings.count > 1 ? "Verlauf" : "Bisher ein Wert")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Chart {
                LabTargetBandMarks(xStart: xRange.lowerBound, xEnd: xRange.upperBound,
                                   bandLow: targetBand?.low, bandHigh: targetBand?.high,
                                   hint: target?.isHint == true, opacity: 0.34)
                ForEach(readings) { reading in
                    LineMark(
                        x: .value("Zeit", reading.date),
                        y: .value("Wert", reading.value)
                    )
                    .foregroundStyle(BIOSTheme.text3)
                    .lineStyle(StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                    .accessibilityHidden(true)
                    PointMark(
                        x: .value("Zeit", reading.date),
                        y: .value("Wert", reading.value)
                    )
                    .foregroundStyle(isHighlighted(reading, focusID: focusID) ? BIOSTheme.accent : BIOSTheme.text1)
                    .symbol(reading.lab ? BasicChartSymbolShape.square : BasicChartSymbolShape.circle)
                    .symbolSize(isHighlighted(reading, focusID: focusID) ? 70 : 30)
                    .accessibilityLabel(spokenWhen(reading))
                    .accessibilityValue(spokenValue(reading))
                }
                if let selected {
                    LabSelectionRule(date: selected, lines: selectionLines(selected, in: readings))
                }
            }
            .chartYScale(domain: yRange)
            .chartXScale(domain: xRange)
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
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
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(BIOSFormat.shortDate(date))
                                .font(.caption2)
                                .foregroundStyle(BIOSTheme.text3)
                        }
                    }
                }
            }
            .labChartScrub(selected: $selected, dates: readings.map(\.date))
            .frame(height: 190)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Verlauf \(detail.marker.name)")

            if let target, targetBand != nil {
                LegendView(items: [LegendItem(color: LabTargetStyle.band,
                                              text: "dunkel: " + target.displayLabel(decimals: detail.marker.decimals),
                                              mark: .box, opacity: target.isHint ? 0.45 : 0.8)])
            }

            Text(note)
                .font(.caption)
                .foregroundStyle(BIOSTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .biosCard()
    }

    private var unit: String {
        detail.latest?.unit ?? detail.marker.unit ?? "mg/dL"
    }

    /// The target band of the merged "Blutzucker" (the fingerstick marker has none).
    private var chartTarget: LabTarget? {
        guard let target = detail.target, target.matches(unit: unit) else { return nil }
        return target
    }

    private func makeReadings() -> [Reading] {
        detail.history.compactMap { point in
            guard let date = point.when, let value = point.value else { return nil }
            return Reading(id: point.id, date: date, value: value, origin: point.originText, lab: point.isLabOrigin,
                           timed: point.measuredAt != nil, comparator: point.comparator, status: point.status,
                           inTarget: point.inTarget)
        }
    }

    /// The selected reading while scrubbing, else the newest one.
    private func isHighlighted(_ reading: Reading, focusID: String?) -> Bool {
        if let selected { return reading.date == selected }
        return reading.id == focusID
    }

    private func valueText(_ reading: Reading) -> String {
        "\(LabFormat.value(reading.value, decimals: detail.marker.decimals, comparator: reading.comparator)) \(unit)"
    }

    /// Scrub bubble: date (with time for capillary points) and origin, then value, unit
    /// and the lab status (only lab values have a range).
    private func selectionLines(_ date: Date, in readings: [Reading]) -> [String] {
        let atDate = readings.filter { $0.date == date }
        guard let first = atDate.first else { return [] }
        let title = LabChartText.when(date, timed: first.timed)
        if atDate.count == 1 {
            return [title + (first.origin.map { " · \($0)" } ?? ""), valueLine(first)]
        }
        return [title] + atDate.map { reading in
            valueLine(reading) + (reading.origin.map { " · \($0)" } ?? "")
        }
    }

    private func valueLine(_ reading: Reading) -> String {
        valueText(reading) + (reading.lab ? LabChartText.statusSuffix(reading.status) : "")
            + (detail.target == nil ? "" : LabChartText.targetSuffix(reading.inTarget, hint: detail.target?.isHint == true))
    }

    private func spokenWhen(_ reading: Reading) -> String {
        reading.timed
            ? "\(LabFormat.fullDate(reading.date)), \(BIOSFormat.time(reading.date)) Uhr"
            : LabFormat.fullDate(reading.date)
    }

    private func spokenValue(_ reading: Reading) -> String {
        var parts = [valueText(reading)]
        if let origin = reading.origin { parts.append(origin) }
        if reading.lab, !reading.status.spoken.isEmpty { parts.append(reading.status.spoken) }
        if let judgement = detail.target?.judgement(inTarget: reading.inTarget, value: reading.value) {
            parts.append(judgement)
        }
        return parts.joined(separator: ", ")
    }

    private func yScale(_ readings: [Reading], target: LabTarget?) -> ClosedRange<Double> {
        let values = readings.map(\.value) + (target?.scaleBounds ?? [])
        guard let low = values.min(), let high = values.max() else { return 0...200 }
        let span = max(high - low, 20)
        return max(0, low - span * 0.2)...(high + span * 0.2)
    }

    private func xScale(_ readings: [Reading]) -> ClosedRange<Date> {
        guard let first = readings.first?.date, let last = readings.last?.date else {
            let now = Date()
            return now.addingTimeInterval(-86_400 * 7)...now
        }
        let pad: TimeInterval = first == last ? 86_400 : max(3_600 * 3, last.timeIntervalSince(first) * 0.04)
        return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
    }
}

/// Sensor vs finger: the last CGM value before each fingerstick, difference in
/// mg/dL and %, plus a MARD-like mean and the bias from 5 pairs on.
struct LabCGMComparisonCard: View {
    let comparison: LabCGMComparison
    @State private var showAll = false
    /// Snapped fingerstick time under the finger while scrubbing (nil = not scrubbing).
    @State private var selected: Date?

    private let collapsedCount = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(comparison.label ?? "Sensor vs. Fingerstich")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            Text(explanation)
                .font(.footnote)
                .foregroundStyle(BIOSTheme.text2)
                .fixedSize(horizontal: false, vertical: true)

            if comparison.hasSummary {
                summary
            } else {
                LabInfoLine(symbol: "circle.dashed",
                            text: "Noch keine Zusammenfassung",
                            detail: comparison.reason ?? pairsHint)
            }

            if comparison.pairs.count >= 2 {
                chart
            }

            if !comparison.pairs.isEmpty {
                table
            }
        }
        .biosCard()
    }

    private var explanation: String {
        var text = "Wie weit der Sensor vor dem Fingerstich vom Finger-Wert entfernt war."
        if let window = comparison.windowMin {
            text += " Verglichen wird der letzte Sensorwert bis zu \(window) Minuten davor."
        }
        return text
    }

    private var pairsHint: String {
        let n = comparison.nPairs
        return "Mittlere Abweichung und Bias ab 5 Paaren, bisher \(n == 1 ? "1 Paar" : "\(n) Paare")."
    }

    // MARK: Summary

    private var summary: some View {
        HStack(spacing: 10) {
            if let mard = comparison.mardPct {
                tile(title: "Mittlere Abweichung",
                     value: "\(BIOSFormat.number(mard, digits: mard < 10 ? 1 : 0)) %",
                     sub: "MARD-ähnlich, \(comparison.nPairs) Paare",
                     spoken: "Mittlere Abweichung \(BIOSFormat.number(mard, digits: mard < 10 ? 1 : 0)) Prozent, MARD-ähnlich, aus \(comparison.nPairs) Paaren")
            }
            if let bias = comparison.biasMgDl {
                tile(title: "Bias",
                     value: "\(BIOSFormat.signed(bias, digits: abs(bias) < 10 ? 1 : 0)) \(comparison.unit)",
                     sub: biasText(bias),
                     spoken: "Bias \(BIOSFormat.signed(bias, digits: abs(bias) < 10 ? 1 : 0)) \(comparison.unit), \(biasText(bias))")
            }
        }
    }

    private func biasText(_ bias: Double) -> String {
        if abs(bias) < 3 { return "Sensor im Mittel etwa gleich" }
        return bias > 0 ? "Sensor im Mittel höher" : "Sensor im Mittel niedriger"
    }

    private func tile(title: String, value: String, sub: String, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(BIOSTheme.text2)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(BIOSTheme.text1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.caption2)
                .foregroundStyle(BIOSTheme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BIOSTheme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    // MARK: Chart

    private struct ChartValue: Identifiable {
        let id: String
        let date: Date
        let value: Double
        let series: String
    }

    private var chart: some View {
        let values: [ChartValue] = comparison.pairs.flatMap { pair -> [ChartValue] in
            guard let date = pair.when else { return [] }
            return [
                ChartValue(id: pair.id + "-f", date: date, value: pair.finger, series: "Finger"),
                ChartValue(id: pair.id + "-s", date: date, value: pair.cgm, series: "Sensor"),
            ]
        }
        let numbers = values.map(\.value)
        let low = numbers.min() ?? 0
        let high = numbers.max() ?? 200
        let span = max(high - low, 20)
        let yRange = max(0, low - span * 0.15)...(high + span * 0.15)
        return VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(comparison.pairs) { pair in
                    if let date = pair.when {
                        RuleMark(
                            x: .value("Zeit", date),
                            yStart: .value("Finger", pair.finger),
                            yEnd: .value("Sensor", pair.cgm)
                        )
                        .foregroundStyle(Color.white.opacity(date == selected ? 0.4 : 0.18))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        // One VoiceOver element per pair: finger, sensor, difference.
                        .accessibilityLabel(pairWhen(date))
                        .accessibilityValue(spokenPairValues(pair))
                    }
                }
                ForEach(values) { item in
                    PointMark(
                        x: .value("Zeit", item.date),
                        y: .value("Wert", item.value)
                    )
                    .foregroundStyle(item.series == "Finger" ? BIOSTheme.text1 : BIOSTheme.glucose)
                    .symbol(item.series == "Finger" ? BasicChartSymbolShape.circle : BasicChartSymbolShape.diamond)
                    .symbolSize(item.date == selected ? 60 : 30)
                    .accessibilityHidden(true)
                }
                if let selected {
                    LabSelectionRule(date: selected, lines: selectionLines(selected))
                }
            }
            .chartYScale(domain: yRange)
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
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
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(BIOSFormat.shortDate(date))
                                .font(.caption2)
                                .foregroundStyle(BIOSTheme.text3)
                        }
                    }
                }
            }
            .labChartScrub(selected: $selected, dates: comparison.pairs.compactMap(\.when))
            .frame(height: 170)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Finger und Sensor im Vergleich, \(comparison.pairs.count) Paare")

            LegendView(items: [
                LegendItem(color: BIOSTheme.text1, text: "Finger", mark: .dot),
                LegendItem(color: BIOSTheme.glucose, text: "Sensor davor", mark: .diamond),
                LegendItem(color: Color.white, text: "Abstand", mark: .line, opacity: 0.3),
            ])
        }
    }

    /// Scrub bubble: time of the fingerstick, finger and sensor value, difference.
    private func selectionLines(_ date: Date) -> [String] {
        guard let pair = comparison.pairs.first(where: { $0.when == date }) else { return [] }
        let unit = comparison.unit
        var difference = "Differenz \(BIOSFormat.signed(pair.diff, digits: 0)) \(unit)"
        if let pct = pair.diffPct { difference += " · \(BIOSFormat.signed(pct, digits: 1)) %" }
        return [
            LabChartText.when(date, timed: true),
            "Finger \(LabFormat.value(pair.finger, decimals: 0)) \(unit)",
            "Sensor \(LabFormat.value(pair.cgm, decimals: 0)) \(unit)",
            difference,
        ]
    }

    private func pairWhen(_ date: Date) -> String {
        "\(LabFormat.fullDate(date)), \(BIOSFormat.time(date)) Uhr"
    }

    /// Finger, sensor and difference of one pair (the time is the element's label).
    private func spokenPairValues(_ pair: LabCGMPair) -> String {
        var text = "Finger \(LabFormat.value(pair.finger, decimals: 0)), Sensor \(LabFormat.value(pair.cgm, decimals: 0)) \(comparison.unit)"
        let direction = pair.diff > 0 ? "Sensor höher" : (pair.diff < 0 ? "Sensor niedriger" : "gleich")
        text += ", Differenz \(BIOSFormat.number(abs(pair.diff), digits: 0)) \(comparison.unit)"
        if let pct = pair.diffPct {
            text += ", \(BIOSFormat.number(abs(pct), digits: 1)) Prozent"
        }
        return text + ", \(direction)"
    }

    // MARK: Table

    private var table: some View {
        let newestFirst = Array(comparison.pairs.reversed())
        let shown = showAll ? newestFirst : Array(newestFirst.prefix(collapsedCount))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Zeit").frame(maxWidth: .infinity, alignment: .leading)
                Text("Finger").frame(width: 50, alignment: .trailing)
                Text("Sensor").frame(width: 52, alignment: .trailing)
                Text("Differenz").frame(width: 92, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(BIOSTheme.text3)
            .padding(.bottom, 6)
            .accessibilityHidden(true)

            ForEach(shown) { pair in
                Rectangle()
                    .fill(BIOSTheme.separator)
                    .frame(height: 0.5)
                row(pair)
                    .padding(.vertical, 7)
            }

            if comparison.pairs.count > collapsedCount {
                Button(showAll ? "Weniger zeigen" : "Alle \(comparison.pairs.count) Paare zeigen") {
                    withAnimation { showAll.toggle() }
                }
                .font(.footnote.weight(.semibold))
                .padding(.top, 8)
            }
        }
    }

    private func row(_ pair: LabCGMPair) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                if let when = pair.when {
                    Text(BIOSFormat.dayLabel(when))
                    Text(BIOSFormat.time(when))
                        .foregroundStyle(BIOSTheme.text2)
                } else {
                    Text(pair.dateRaw ?? "ohne Datum")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(LabFormat.value(pair.finger, decimals: 0))
                .frame(width: 50, alignment: .trailing)
            Text(LabFormat.value(pair.cgm, decimals: 0))
                .foregroundStyle(BIOSTheme.glucose)
                .frame(width: 52, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 0) {
                Text(BIOSFormat.signed(pair.diff, digits: 0))
                if let pct = pair.diffPct {
                    Text("\(BIOSFormat.signed(pct, digits: 1)) %")
                        .foregroundStyle(BIOSTheme.text2)
                }
            }
            .frame(width: 92, alignment: .trailing)
        }
        .font(.footnote)
        .monospacedDigit()
        .foregroundStyle(BIOSTheme.text1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(pair))
    }

    private func spoken(_ pair: LabCGMPair) -> String {
        var text = ""
        if let when = pair.when {
            text = "\(BIOSFormat.dayLabel(when)), \(BIOSFormat.time(when)) Uhr: "
        }
        text += "Finger \(LabFormat.value(pair.finger, decimals: 0)), Sensor \(LabFormat.value(pair.cgm, decimals: 0)) \(comparison.unit)"
        let direction = pair.diff > 0 ? "Sensor höher" : (pair.diff < 0 ? "Sensor niedriger" : "gleich")
        text += ", Differenz \(BIOSFormat.number(abs(pair.diff), digits: 0)) \(comparison.unit)"
        if let pct = pair.diffPct {
            text += ", \(BIOSFormat.number(abs(pct), digits: 1)) Prozent"
        }
        return text + ", \(direction)"
    }
}

/// All fingersticks, newest first, with time and origin.
struct LabDeviceReadingsCard: View {
    let detail: LabMarkerDetail
    @State private var showAll = false

    private let collapsedCount = 12

    var body: some View {
        let points = Array(detail.history.reversed())
        let shown = showAll ? points : Array(points.prefix(collapsedCount))
        VStack(alignment: .leading, spacing: 10) {
            Text("Fingerstiche")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(shown) { point in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(timeText(point))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(BIOSTheme.text1)
                        Text(point.originLabel ?? detail.marker.sourceLabel ?? "Messgerät")
                            .font(.caption)
                            .foregroundStyle(BIOSTheme.text2)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 6)
                    Text(valueWithUnit(point))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(BIOSTheme.text1)
                }
                .accessibilityElement(children: .combine)
            }
            if points.count > collapsedCount {
                Button(showAll ? "Weniger zeigen" : "Alle \(points.count) zeigen") {
                    withAnimation { showAll.toggle() }
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .biosCard()
    }

    private func timeText(_ point: LabPoint) -> String {
        if let measured = point.measuredAt { return BIOSFormat.timestamp(measured) }
        if let date = point.date { return LabFormat.fullDate(date) }
        return point.dateRaw ?? "ohne Datum"
    }

    private func valueWithUnit(_ point: LabPoint) -> String {
        let value = LabFormat.value(point.value, decimals: detail.marker.decimals, comparator: point.comparator,
                                    text: point.valueText)
        guard let unit = point.unit ?? detail.marker.unit, !unit.isEmpty else { return value }
        return "\(value) \(unit)"
    }
}
