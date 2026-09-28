import SwiftUI

// Merged marker "Blutzucker" (`kind: "kombiniert"`, id `blood_glucose`): the lab's
// serum/plasma glucose (with the lab's reference range), capillary values measured
// at a visit ("BZ (prä)" in letters, "Ambulanz") and every fingerstick entered as a
// calibration in the Dexcom app, in one series. Each point names its origin; only lab
// points have a range and a status. Plus the card "Eigene Messungen" (`own` of
// GET /v1/labs): height, weight, home blood pressure, temperature, blood glucose.
// Observation only, never a diagnosis.

/// Overview row of the merged marker: latest value of any origin with time and origin,
/// the newest lab value with its range below.
struct LabCombinedMarkerRow: View {
    let marker: LabMarkerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(marker.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BIOSTheme.text1)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BIOSTheme.text3)
                    }
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(valueText(marker.latest))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(BIOSTheme.text1)
                    Text(marker.latest?.unit ?? marker.unit ?? "mg/dL")
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text2)
                }
            }
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: marker.latestLab == nil ? "drop" : "testtube.2")
                        .font(.caption2.weight(.semibold))
                    Text(labLine)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    if let status = marker.latestLab?.status, status.isFlagged, let tag = status.tag {
                        LabTag(text: tag, style: LabTag.style(for: status))
                    }
                }
                .font(.caption)
                .foregroundStyle(BIOSTheme.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                LabSparkline(values: marker.sparkline.map(\.value), status: .keineReferenz)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityHint("Öffnet Verlauf aller Blutzuckerwerte und den Vergleich mit dem Sensor")
        .accessibilityAddTraits(.isButton)
    }

    private func valueText(_ point: LabPoint?) -> String {
        guard let point else { return "n. v." }
        return LabFormat.value(point.value, decimals: marker.decimals, comparator: point.comparator, text: point.valueText)
    }

    /// "zuletzt 27.09.2026, 21:36 · Fingerstich (Kalibrierung) · 12 Werte".
    private var meta: String {
        guard let point = marker.latest else { return "kein Wert" }
        var parts: [String] = []
        if let measured = point.measuredAt {
            parts.append("zuletzt " + BIOSFormat.timestamp(measured))
        } else if let date = point.date {
            parts.append("zuletzt " + LabFormat.fullDate(date))
        }
        if let origin = point.originText { parts.append(origin) }
        if marker.nValues > 1 { parts.append("\(marker.nValues) Werte") }
        return parts.joined(separator: " · ")
    }

    /// "Labor 15.09.2026: 92 mg/dL, Ref. 70 bis 99" or the origins without a lab value.
    private var labLine: String {
        guard let lab = marker.latestLab else {
            let labels = marker.parts.map(\.label)
            return labels.isEmpty ? (marker.sourceLabel ?? "ohne Laborwert") : labels.joined(separator: " · ") + ", ohne Laborwert"
        }
        var text = "Labor"
        if let date = lab.date { text += " " + LabFormat.fullDate(date) }
        text += ": \(valueText(lab)) \(lab.unit ?? marker.unit ?? "")"
        if let ref = LabFormat.refRange(low: lab.refLow, high: lab.refHigh, decimals: marker.decimals, unit: nil) {
            text += ", Ref. \(ref)"
        }
        return text
    }

    private var spoken: String {
        let unit = marker.latest?.unit ?? marker.unit ?? "mg/dL"
        var text = "\(marker.name): \(valueText(marker.latest)) \(unit), \(meta). \(labLine)"
        if let status = marker.latestLab?.status, !status.spoken.isEmpty {
            text += ", \(status.spoken)"
        }
        return text
    }
}

// MARK: - Eigene Messungen

/// Card "Eigene Messungen" on top of "Werte": Clemens' own values instead of the visit
/// vitals printed in letters (those stay inside their document).
struct LabOwnMeasurementsCard: View {
    let own: LabOwnMeasurements

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(own.label)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            NavigationLink {
                BodyProfileView()
            } label: {
                row(symbol: "figure.stand", title: "Größe und Gewicht", value: bodyValue, detail: bodyDetail,
                    chevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet Größe und Gewicht zum Ändern")
            if let bp = own.bloodPressure {
                row(symbol: "heart", title: "Blutdruck (zu Hause)", value: bpValue(bp), detail: bpDetail(bp),
                    tag: bpTag(bp))
            }
            if let temperature = own.temperature {
                row(symbol: "thermometer.medium", title: "Temperatur",
                    value: "\(BIOSFormat.number(temperature.value, digits: 1)) °C",
                    detail: temperatureDetail(temperature))
            }
            if let glucose = own.glucose {
                NavigationLink(value: LabRoute.marker(glucose.markerID)) {
                    row(symbol: "drop", title: "Blutzucker",
                        value: "\(LabFormat.value(glucose.value, decimals: 0)) \(glucose.unit)",
                        detail: glucoseDetail(glucose), chevron: true)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Öffnet den Verlauf aller Blutzuckerwerte")
            }
            if let note = own.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .biosCard()
    }

    private func row(symbol: String, title: String, value: String, detail: String?, tag: (String, LabTag.Style)? = nil,
                     chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(BIOSTheme.text2)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.06), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BIOSTheme.text1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text1)
                if let tag {
                    LabTag(text: tag.0, style: tag.1)
                }
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BIOSTheme.text3)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Body

    private var bodyValue: String {
        guard let body = own.body else { return "eintragen" }
        var parts: [String] = []
        if let height = body.heightCm { parts.append("\(BIOSFormat.number(height, digits: 0)) cm") }
        if let weight = body.weightKg { parts.append("\(BIOSFormat.number(weight, digits: 1)) kg") }
        return parts.isEmpty ? "eintragen" : parts.joined(separator: " · ")
    }

    private var bodyDetail: String? {
        guard let body = own.body else { return "Noch keine Angaben" }
        var parts: [String] = []
        if let bmi = body.bmi { parts.append("BMI \(BIOSFormat.number(bmi, digits: 1))") }
        if let day = BIOSDate.day(body.weightDate) {
            var text = "Gewicht vom \(LabFormat.fullDate(day))"
            if let source = body.weightSourceLabel { text += " (\(source))" }
            parts.append(text)
        } else if body.weightKg != nil, let source = body.weightSourceLabel {
            parts.append("Gewicht: \(source)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Blood pressure

    private func bpValue(_ bp: LabOwnMeasurements.BloodPressure) -> String {
        if let sys = bp.meanSys, let dia = bp.meanDia {
            return "Ø \(BIOSFormat.number(sys, digits: 0))/\(BIOSFormat.number(dia, digits: 0))"
        }
        if let sys = bp.lastSys, let dia = bp.lastDia {
            return "\(BIOSFormat.number(sys, digits: 0))/\(BIOSFormat.number(dia, digits: 0))"
        }
        return "n. v."
    }

    private func bpDetail(_ bp: LabOwnMeasurements.BloodPressure) -> String {
        var parts: [String] = []
        if bp.meanSys != nil {
            parts.append("Mittel \(bp.days) Tage, \(bp.nSeries == 1 ? "1 Serie" : "\(bp.nSeries) Serien")")
        } else {
            parts.append("keine Serie in den letzten \(bp.days) Tagen")
        }
        if let sys = bp.lastSys, let dia = bp.lastDia {
            var text = "zuletzt \(BIOSFormat.number(sys, digits: 0))/\(BIOSFormat.number(dia, digits: 0))"
            if let at = bp.lastAt { text += " am " + BIOSFormat.timestamp(at) }
            parts.append(text)
        }
        return parts.joined(separator: " · ")
    }

    private func bpTag(_ bp: LabOwnMeasurements.BloodPressure) -> (String, LabTag.Style)? {
        switch bp.status ?? "" {
        case "warn": return ("erhöht", .mid)
        case "info": return ("über Ziel", .context)
        case "ok": return ("im Ziel", .good)
        default: return nil
        }
    }

    // MARK: Temperature, glucose

    private func temperatureDetail(_ temperature: LabOwnMeasurements.Temperature) -> String? {
        var parts: [String] = []
        if let at = temperature.measuredAt { parts.append("zuletzt " + BIOSFormat.timestamp(at)) }
        if let method = temperature.method { parts.append(method) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func glucoseDetail(_ glucose: LabOwnMeasurements.Glucose) -> String? {
        var parts: [String] = []
        if let at = glucose.measuredAt {
            parts.append("zuletzt " + BIOSFormat.timestamp(at))
        } else if let date = glucose.date {
            parts.append("zuletzt " + LabFormat.fullDate(date))
        }
        if let origin = glucose.originLabel { parts.append(origin) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Detail

/// Detail content of the merged "Blutzucker" (inside the marker detail's stack).
struct LabCombinedDetailContent: View {
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
            LabCombinedValueCard(marker: detail.marker, point: latest, count: detail.history.count)
        } else {
            NotEvaluableBox(title: "Noch kein Wert",
                            text: "Hier erscheinen Laborwerte, Fingerstiche aus der Dexcom-App und Blutzucker aus Arztbriefen.")
        }

        if let lab = detail.labHistory.last {
            VStack(alignment: .leading, spacing: 6) {
                LabSectionLabel(title: "Letzter Laborwert")
                LabValueCard(marker: detail.marker, point: lab, target: nil)
            }
        }

        if detail.history.contains(where: { $0.value != nil && $0.when != nil }) {
            LabDeviceChartCard(detail: detail,
                               note: "Kreise: kapillär (Fingerstich, Ambulanz), Quadrate: Labor. Gedrückt halten und ziehen zeigt den Wert.")
        }

        if let comparison = detail.cgmComparison, comparison.nValues ?? comparison.nPairs > 0 {
            LabCGMComparisonCard(comparison: comparison)
        }

        if region != nil {
            LabContextCard(detail: detail, region: region, openRegion: openRegion)
        }

        if !detail.history.isEmpty {
            LabCombinedReadingsCard(detail: detail)
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
        let labels = detail.marker.parts.map(\.label)
        parts.append(labels.isEmpty ? "Labor, Fingerstich und Ambulanz" : labels.joined(separator: ", "))
        return parts.joined(separator: " · ")
    }
}

/// Big latest value of any origin, with its time and origin; the lab range only
/// in the card below (capillary values never have one).
struct LabCombinedValueCard: View {
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
                Text(point.unit ?? marker.unit ?? "mg/dL")
                    .font(.title3)
                    .foregroundStyle(BIOSTheme.text2)
                Spacer(minLength: 6)
                LabTag(text: point.originGroupLabel ?? "Wert", style: .grey,
                       symbol: point.isLabOrigin ? "testtube.2" : "drop")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(marker.name) \(value) \(point.unit ?? marker.unit ?? ""), \(when), \(point.originText ?? "")")

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

    private var when: String {
        if let measured = point.measuredAt { return "gemessen " + BIOSFormat.timestamp(measured) }
        if let date = point.date { return "gemessen am " + LabFormat.fullDate(date) }
        return "ohne Zeitangabe"
    }

    private var lines: [String] {
        var first = when.prefix(1).uppercased() + String(when.dropFirst())
        if let origin = point.originLabel { first += " · " + origin }
        var result = [first]
        result.append("Labor, Fingerstich und der Blutzucker aus Arztbriefen sind eine Reihe. Einen Referenzbereich hat nur ein Laborwert; kapilläre Werte (Fingerstich, Ambulanz) haben keinen.")
        if count > 1 { result.append("\(count) Werte insgesamt.") }
        return result
    }
}

/// Every value newest first: time, origin, value; lab values with their range and tag,
/// values from a document open it.
struct LabCombinedReadingsCard: View {
    let detail: LabMarkerDetail
    @State private var showAll = false

    private let collapsedCount = 12

    var body: some View {
        let points = Array(detail.history.reversed())
        let shown = showAll ? points : Array(points.prefix(collapsedCount))
        VStack(alignment: .leading, spacing: 10) {
            Text("Alle Werte")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(shown) { point in
                if let documentID = point.documentID {
                    NavigationLink(value: LabRoute.document(documentID)) {
                        row(point, link: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Öffnet den Befund")
                } else {
                    row(point, link: false)
                }
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

    private func row(_ point: LabPoint, link: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(timeText(point))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text1)
                Text(subline(point))
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text2)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Text(valueWithUnit(point))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(BIOSTheme.text1)
            if point.isLabOrigin, point.status.isFlagged, let tag = point.status.tag {
                LabTag(text: tag, style: LabTag.style(for: point.status))
            }
            if link {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BIOSTheme.text3)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func timeText(_ point: LabPoint) -> String {
        if let measured = point.measuredAt { return BIOSFormat.timestamp(measured) }
        if let date = point.date { return LabFormat.fullDate(date) }
        return point.dateRaw ?? "ohne Datum"
    }

    /// "Labor · Ref. 70 bis 99" / "Ambulanz (kapillär)" / "aus Dexcom-Kalibrierung".
    private func subline(_ point: LabPoint) -> String {
        var parts: [String] = []
        if let label = point.originLabel ?? point.originGroupLabel { parts.append(label) }
        if point.isLabOrigin,
           let ref = LabFormat.refRange(low: point.refLow, high: point.refHigh, decimals: detail.marker.decimals, unit: nil) {
            parts.append("Ref. \(ref)")
        }
        return parts.isEmpty ? "Wert" : parts.joined(separator: " · ")
    }

    private func valueWithUnit(_ point: LabPoint) -> String {
        let value = LabFormat.value(point.value, decimals: detail.marker.decimals, comparator: point.comparator,
                                    text: point.valueText)
        guard let unit = point.unit ?? detail.marker.unit, !unit.isEmpty else { return value }
        return "\(value) \(unit)"
    }
}
