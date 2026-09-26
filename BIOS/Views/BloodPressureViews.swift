import SwiftUI

/// Heute tile "Blutdruck": last home value, mean of readings 2 + 3,
/// classification against 135/85 (home) and 130/80 (target), date.
/// Only shown when the dashboard has a `blood_pressure` tile.
struct BloodPressureTile: View {
    let pressure: BloodPressureTileModel

    var body: some View {
        let status = pressure.effectiveStatus
        TileView(
            route: .blutdruck,
            title: "Blutdruck",
            icon: "heart.text.square",
            color: BIOSTheme.rhr,
            footer: footer,
            accessibilityText: accessibilityText
        ) {
            if let pair = pressure.last.pairText {
                BigValue(value: pair, unit: "mmHg")
                if let mean = pressure.meanText {
                    KeyValueLine(text: Text("Ø Messung 2+3 ") + Text.value(mean))
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: status.symbol)
                        .foregroundStyle(status.tint)
                    Text(pressure.classificationText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(BIOSTheme.text2)
                if let pulse = pressure.last.pulse {
                    KeyValueLine(text: Text("Puls ") + Text.value(BIOSFormat.number(pulse)))
                }
            } else {
                NoDataTileContent(reason: pressure.reason ?? "Keine Blutdruckwerte")
            }
        }
    }

    private var footer: String {
        let setting = pressure.last.isClinic ? "Praxis" : "zu Hause"
        let when = pressure.last.whenText
        return when.isEmpty ? setting : "\(when) · \(setting)"
    }

    private var accessibilityText: String {
        guard let pair = pressure.last.pairText else { return "Blutdruck, keine Daten" }
        var text = "Blutdruck \(pair) mmHg, \(footer)"
        if let mean = pressure.meanText { text += ", Mittel der Messungen 2 und 3 \(mean)" }
        return text + ". " + pressure.classificationText
    }
}

/// Detail "Blutdruck": summary, sys/dia chart with 135/85 (home) and 130/80
/// (target) reference lines, clinic values as squares, list of readings.
struct BloodPressureDetailView: View {
    @EnvironmentObject var dashboardStore: DashboardStore
    @State private var days = 90

    var body: some View {
        let pressure = dashboardStore.dashboard?.bloodPressure
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                StoreStatusBanner()
                if let pressure {
                    BloodPressureSummaryCard(pressure: pressure)
                } else {
                    NotEvaluableBox(title: "Keine Blutdruckdaten", text: "Der Server liefert noch keine Blutdruck-Kachel.")
                }
                Picker("Zeitraum", selection: $days) {
                    Text("30 Tage").tag(30)
                    Text("90 Tage").tag(90)
                    Text("1 Jahr").tag(365)
                }
                .pickerStyle(.segmented)

                SeriesReader(request: SeriesStore.Request(metric: "bp_sys", days: days, source: nil)) { sysEntry in
                    SeriesReader(request: SeriesStore.Request(metric: "bp_dia", days: days, source: nil)) { diaEntry in
                        SeriesReader(request: SeriesStore.Request(metric: "bp_pulse", days: days, source: nil)) { pulseEntry in
                            BloodPressureSeriesSection(
                                sys: sysEntry,
                                dia: diaEntry,
                                pulse: pulseEntry,
                                pressure: pressure,
                                days: days
                            )
                        }
                    }
                }

                NoteText(text: "Grenze für Messungen zu Hause 135/85 mmHg, Ziel 130/80 mmHg. Je Messreihe zählt das Mittel aus Messung 2 und 3. Praxiswerte sind als Quadrate markiert. Nur Beobachtung, keine Therapiehinweise.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
    }
}

struct BloodPressureSummaryCard: View {
    let pressure: BloodPressureTileModel

    var body: some View {
        let status = pressure.effectiveStatus
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EyebrowText(text: "Letzte Messung")
                Spacer()
                Text(pressure.last.whenText + (pressure.last.isClinic ? " · Praxis" : " · zu Hause"))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text3)
            }
            StatGrid(columns: 3) {
                StatItem(label: "Letzter Wert", value: pressure.last.pairText ?? "n. v.", unit: "mmHg")
                StatItem(label: "Ø Messung 2+3", value: pressure.meanText ?? "n. v.", unit: "mmHg")
                StatItem(label: "Puls", value: BIOSFormat.number(pressure.last.pulse), unit: "/min")
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: status.symbol)
                    .foregroundStyle(status.tint)
                Text(pressure.classificationText)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if !pressure.evaluable, let reason = pressure.reason {
                CaptionText(text: reason)
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
    }
}

struct BloodPressureSeriesSection: View {
    let sys: SeriesStore.Entry?
    let dia: SeriesStore.Entry?
    let pulse: SeriesStore.Entry?
    let pressure: BloodPressureTileModel?
    let days: Int

    var body: some View {
        let spec = BloodPressureSeriesSection.spec(sys: sys?.model, dia: dia?.model, pressure: pressure)
        let rows = BloodPressureSeriesSection.rows(sys: sys?.model, dia: dia?.model, pulse: pulse?.model)
        ChartCard(
            label: "Blutdruck",
            icon: "heart.text.square",
            color: BIOSTheme.rhr,
            value: meanText(rows),
            unit: meanText(rows) == nil ? nil : "mmHg",
            sub: rows.isEmpty ? nil : "Ø \(days) Tage, zu Hause\n\(rows.count) Messungen",
            legend: [
                LegendItem(color: BIOSTheme.rhr, text: "systolisch", mark: .line),
                LegendItem(color: BIOSTheme.glucose, text: "diastolisch", mark: .line),
                LegendItem(color: BIOSTheme.text1, text: "Praxis", mark: .box),
            ]
        ) {
            if spec.isEmpty {
                ChartPlaceholder(
                    isLoading: sys?.isLoading != false || dia?.isLoading != false,
                    message: sys?.error ?? dia?.error ?? "Keine Blutdruckwerte in diesem Zeitraum",
                    height: 170
                )
            } else {
                BIOSChart(spec: spec)
                    .accessibilityLabel("Blutdruck systolisch und diastolisch, letzte \(days) Tage")
            }
        }

        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Messungen")
                    .font(.headline)
                    .padding(.bottom, 6)
                ForEach(rows.prefix(60)) { row in
                    HStack(spacing: 10) {
                        Image(systemName: row.isClinic ? "cross.case" : "house")
                            .foregroundStyle(BIOSTheme.text2)
                            .frame(width: 22)
                        Text(BIOSFormat.relative(row.date))
                            .font(.footnote)
                            .foregroundStyle(BIOSTheme.text2)
                        Spacer(minLength: 8)
                        Text(row.pairText)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        if let pulse = row.pulse {
                            Text("Puls \(BIOSFormat.number(pulse))")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(BIOSTheme.text3)
                        }
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) {
                        Rectangle().fill(BIOSTheme.separator).frame(height: 0.5)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(BIOSFormat.relative(row.date)), \(row.pairText) mmHg\(row.isClinic ? ", Praxis" : ", zu Hause")")
                }
            }
            .foregroundStyle(BIOSTheme.text1)
            .biosCard()
        }
    }

    private func meanText(_ rows: [Row]) -> String? {
        let home = rows.filter { !$0.isClinic }
        guard !home.isEmpty else { return nil }
        let sys = home.map(\.sys).reduce(0, +) / Double(home.count)
        let dia = home.map(\.dia).reduce(0, +) / Double(home.count)
        return "\(BIOSFormat.number(sys))/\(BIOSFormat.number(dia))"
    }

    struct Row: Identifiable {
        let id: Int
        let date: Date
        let sys: Double
        let dia: Double
        let pulse: Double?
        let isClinic: Bool

        var pairText: String {
            "\(BIOSFormat.number(sys))/\(BIOSFormat.number(dia))"
        }
    }

    /// Joins sys/dia/pulse by timestamp, newest first.
    static func rows(sys: SeriesModel?, dia: SeriesModel?, pulse: SeriesModel?) -> [Row] {
        var diaByDate: [Date: Double] = [:]
        for point in dia?.points ?? [] {
            if let value = point.value { diaByDate[point.date] = value }
        }
        var pulseByDate: [Date: Double] = [:]
        for point in pulse?.points ?? [] {
            if let value = point.value { pulseByDate[point.date] = value }
        }
        var rows: [Row] = []
        for point in sys?.points ?? [] {
            guard let value = point.value, let diastolic = diaByDate[point.date] else { continue }
            rows.append(Row(
                id: rows.count,
                date: point.date,
                sys: value,
                dia: diastolic,
                pulse: pulseByDate[point.date],
                isClinic: BloodPressureReading.isClinic(point.setting)
            ))
        }
        return rows.sorted { $0.date > $1.date }
    }

    static func spec(sys: SeriesModel?, dia: SeriesModel?, pressure: BloodPressureTileModel?) -> ChartSpec {
        var spec = ChartSpec()
        spec.unit = ChartXUnit.from(resolution: sys?.resolution ?? "day")
        spec.height = 170
        spec.valueUnit = "mmHg"
        spec.seriesLabels = ["sys": "Sys", "dia": "Dia", "praxissys": "Praxis sys", "praxisdia": "Praxis dia"]
        let homeSys = (sys?.points ?? []).filter { !BloodPressureReading.isClinic($0.setting) }
        let homeDia = (dia?.points ?? []).filter { !BloodPressureReading.isClinic($0.setting) }
        let sysLine = ChartSpec.linePoints(homeSys, series: "sys", color: BIOSTheme.rhr)
        let diaLine = ChartSpec.linePoints(homeDia, series: "dia", color: BIOSTheme.glucose, idOffset: sysLine.count)
        spec.lines = sysLine + diaLine
        var extra: [ChartLinePoint] = []
        for point in sys?.points ?? [] where BloodPressureReading.isClinic(point.setting) {
            if let value = point.value {
                extra.append(ChartLinePoint(id: 100_000 + extra.count, series: "praxissys-0", date: point.date,
                                            value: value, color: BIOSTheme.rhr, square: true))
            }
        }
        for point in dia?.points ?? [] where BloodPressureReading.isClinic(point.setting) {
            if let value = point.value {
                extra.append(ChartLinePoint(id: 100_000 + extra.count, series: "praxisdia-0", date: point.date,
                                            value: value, color: BIOSTheme.glucose, square: true))
            }
        }
        spec.extraPoints = extra
        let homeS = pressure?.homeSys ?? 135
        let homeD = pressure?.homeDia ?? 85
        let targetS = pressure?.targetSys ?? 130
        let targetD = pressure?.targetDia ?? 80
        spec.refs = [
            ChartRef(id: 0, value: homeS, label: "\(BIOSFormat.number(homeS)) zu Hause"),
            ChartRef(id: 1, value: homeD, label: "\(BIOSFormat.number(homeD)) zu Hause"),
            ChartRef(id: 2, value: targetS, label: "Ziel \(BIOSFormat.number(targetS))", trailing: true),
            ChartRef(id: 3, value: targetD, label: "Ziel \(BIOSFormat.number(targetD))", trailing: true),
        ]
        // Always include the reference lines in the visible range.
        let values = spec.lines.map(\.value) + extra.map(\.value)
        spec.yMin = Swift.min((values.min() ?? targetD) - 8, targetD - 8)
        spec.yMax = Swift.max((values.max() ?? homeS) + 8, homeS + 8)
        return spec
    }
}
