import SwiftUI

/// Detail "Glukose": last 24 h summary (TIR bar, statistics), hourly curve,
/// daily mean and TIR over 7/28 days.
struct GlukoseDetailView: View {
    @EnvironmentObject var dashboardStore: DashboardStore
    @AppStorage(RangeSetting.key) private var days = 7

    var body: some View {
        let glucose = dashboardStore.dashboard?.glucose
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                StoreStatusBanner()
                GlucoseSummaryCard(glucose: glucose)
                ChartCard(
                    label: "Verlauf 24 h",
                    icon: "drop",
                    color: BIOSTheme.glucose,
                    sub: "stündliche Mittel\nkein Echtzeitwert",
                    legend: [LegendItem(color: BIOSTheme.good, text: "Zielbereich 70 bis 180", opacity: 0.35)]
                ) {
                    let spec = GlukoseDetailView.spec24h(glucose)
                    if spec.isEmpty {
                        ChartPlaceholder(isLoading: false, message: "Keine Werte der letzten 24 Stunden")
                    } else {
                        BIOSChart(spec: spec)
                            .accessibilityLabel("Glukose letzte 24 Stunden, stündliche Mittel")
                    }
                }
                RangePicker(days: $days)
                MetricChartCard(kind: .glucoseDaily, days: days)
                MetricChartCard(kind: .tir, days: days)
                NoteText(text: "Import stündlich um :17 aus Dexcom Share und Loop, Apple Health füllt Lücken. Tageswerte gelten für ganze Tage bis gestern.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
    }

    /// Hourly means of the tile (`spark_24h`, oldest first, from `spark_start`).
    static func spec24h(_ glucose: GlucoseTileModel?) -> ChartSpec {
        var spec = ChartSpec()
        spec.unit = .hour
        spec.rangeDays = 1
        spec.yMin = 40
        spec.yMax = 300
        spec.height = 150
        spec.valueUnit = "mg/dL"
        guard let glucose else { return spec }
        let calendar = Calendar.current
        let start: Date
        if let sparkStart = glucose.sparkStart {
            start = sparkStart
        } else {
            let hourStart = calendar.dateInterval(of: .hour, for: Date())?.start ?? Date()
            start = hourStart.addingTimeInterval(-Double(max(0, glucose.spark.count - 1)) * 3_600)
        }
        var points: [SeriesPoint] = []
        for (index, value) in glucose.spark.enumerated() {
            let date = start.addingTimeInterval(Double(index) * 3_600)
            points.append(SeriesPoint(id: index, date: date, value: value, tbr: nil, tir: nil, tar: nil))
        }
        let line = ChartSpec.linePoints(points, series: "glucose", color: BIOSTheme.glucose)
        spec.lines = line
        spec.area = line
        spec.areaColor = BIOSTheme.glucose
        spec.band = ChartBand(lo: glucose.targetLow, hi: glucose.targetHigh, mid: nil, color: BIOSTheme.good)
        return spec
    }
}

struct GlucoseSummaryCard: View {
    let glucose: GlucoseTileModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let glucose, glucose.evaluable {
                HStack {
                    EyebrowText(text: "Letzte 24 Stunden")
                    Spacer()
                    if let last = glucose.lastTs {
                        Text("Stand \(BIOSFormat.time(last))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(BIOSTheme.text3)
                    }
                }
                TIRBar(tbr: glucose.tbr ?? 0, tir: glucose.tir ?? 0, tar: glucose.tar ?? 0)
                HStack {
                    TIRLegendItem(value: glucose.tbr, text: "unter 70", alignment: .leading)
                    TIRLegendItem(value: glucose.tir, text: "70 bis 180", alignment: .center)
                    TIRLegendItem(value: glucose.tar, text: "über 180", alignment: .trailing)
                }
                StatGrid(columns: 3) {
                    StatItem(label: "Ø", value: BIOSFormat.number(glucose.mean), unit: "mg/dL")
                    StatItem(label: "Variabilität (CV)", value: BIOSFormat.number(glucose.cv), unit: "%")
                    StatItem(label: "GMI", value: BIOSFormat.number(glucose.gmi, digits: 1), unit: "%")
                    StatItem(
                        label: "Nacht-Ø heute",
                        value: nightText(glucose.nightMean),
                        unit: glucose.nightMean == nil ? nil : "mg/dL"
                    )
                    StatItem(label: "Abdeckung", value: BIOSFormat.number(glucose.coverage24h), unit: "%")
                    StatItem(label: "Quelle", value: glucose.sourcesText)
                }
                .padding(.top, 4)
                if glucose.up {
                    ContextLine(
                        symbol: "arrow.up",
                        title: "Glukose/Insulinbedarf erhöht",
                        detail: "Teil des Infekt-Checks als Kontext, kein eigener Alarm",
                        style: .context
                    )
                }
            } else if let glucose {
                NotEvaluableBox(title: "Nicht bewertbar", text: notEvaluableText(glucose))
            } else {
                NotEvaluableBox(title: "Keine Glukosedaten", text: "Der Server liefert noch keine Glukose-Kachel.")
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
    }

    /// The night window is 00:00 to 06:00: before 06:00 it is still running.
    private func nightText(_ value: Double?) -> String {
        if let value { return BIOSFormat.number(value) }
        return Calendar.current.component(.hour, from: Date()) < 6 ? "läuft" : "n. v."
    }

    private func notEvaluableText(_ glucose: GlucoseTileModel) -> String {
        var text = glucose.reason ?? "Zu wenige Werte"
        if let coverage = glucose.coverage24h {
            text += ". Abdeckung 24 h \(BIOSFormat.number(coverage)) %, nötig sind 70 %"
        }
        return text + ". Nach dem Warm-up (ca. 30 min) und dem nächsten stündlichen Import erscheinen wieder Werte."
    }
}

/// Horizontal time-in-range bar (below / in / above target).
struct TIRBar: View {
    let tbr: Double
    let tir: Double
    let tar: Double

    var body: some View {
        GeometryReader { proxy in
            let total = max(1, tbr + tir + tar)
            let usable = max(0, proxy.size.width - 4)
            HStack(spacing: 2) {
                Rectangle().fill(BIOSTheme.bad).frame(width: usable * CGFloat(max(tbr, 0.5) / total))
                Rectangle().fill(BIOSTheme.good).frame(width: usable * CGFloat(tir / total))
                Rectangle().fill(BIOSTheme.mid).frame(width: usable * CGFloat(tar / total))
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

struct TIRLegendItem: View {
    let value: Double?
    let text: String
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 1) {
            Text("\(BIOSFormat.number(value)) %")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BIOSTheme.text1)
            Text(text)
                .font(.caption)
                .foregroundStyle(BIOSTheme.text2)
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .accessibilityElement(children: .combine)
    }
}

/// Detail "Recovery und Schlaf".
struct RecoveryDetailView: View {
    @EnvironmentObject var dashboardStore: DashboardStore
    @AppStorage(RangeSetting.key) private var days = 7

    var body: some View {
        let recovery = dashboardStore.dashboard?.recovery
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                StoreStatusBanner()
                HStack(spacing: 16) {
                    ZStack {
                        RecoveryRing(value: recovery?.recovery, color: (recovery?.zone ?? .none).color, lineWidth: 10)
                            .frame(width: 96, height: 96)
                        VStack(spacing: 1) {
                            HStack(alignment: .firstTextBaseline, spacing: 1) {
                                Text(BIOSFormat.number(recovery?.recovery))
                                    .font(.title2.bold())
                                    .monospacedDigit()
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                Text("%")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BIOSTheme.text2)
                            }
                            Text((recovery?.zone ?? .none).word)
                                .font(.caption2)
                                .foregroundStyle(BIOSTheme.text2)
                        }
                        .frame(width: 76)
                    }
                    .accessibilityElement(children: .combine)
                    StatGrid(columns: 2) {
                        StatItem(label: recovery?.sleep?.hasNaps == true ? "Schlaf (Haupt)" : "Schlaf",
                                 value: BIOSFormat.number(recovery?.mainSleepHours, digits: 1), unit: "h")
                        StatItem(label: "HRV", value: BIOSFormat.number(recovery?.hrv), unit: "ms")
                        StatItem(label: "Ruhepuls", value: BIOSFormat.number(recovery?.rhr), unit: "bpm")
                        StatItem(label: "Atmung", value: BIOSFormat.number(recovery?.respRate, digits: 1), unit: "/min")
                    }
                }
                .foregroundStyle(BIOSTheme.text1)
                .biosCard()

                if let sleep = recovery?.sleep {
                    SleepBreakdownCard(sleep: sleep)
                }

                RangePicker(days: $days)
                MetricChartCard(kind: .recovery, days: days)
                SleepChartCard(days: days)
                MetricChartCard(kind: .hrv, days: days)
                MetricChartCard(kind: .rhr, days: days)
                NoteText(text: "Recovery gehört zur Aufwach-Zeit (\(recovery?.nightText ?? "letzte Nacht")). Whoop bewertet einen Schlaf neu, wenn er verlängert wird, die letzte Bewertung gilt.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
    }
}

/// Detail "Insulin": yesterday's totals, TDD, insulin per 10 g carbs, auto bolus.
struct InsulinDetailView: View {
    @EnvironmentObject var dashboardStore: DashboardStore
    @AppStorage(RangeSetting.key) private var days = 7

    var body: some View {
        let insulin = dashboardStore.dashboard?.insulin
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                StoreStatusBanner()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        EyebrowText(text: insulin?.dayText ?? "Vortag")
                        Spacer()
                        if let insulin, !insulin.evaluable {
                            PillView(kind: .notEvaluable, text: "nicht bewertbar")
                        } else if insulin?.up == true {
                            PillView(kind: .context, text: "erhöht, Kontext")
                        } else {
                            Text("im Rahmen")
                                .font(.caption)
                                .foregroundStyle(BIOSTheme.text3)
                        }
                    }
                    if let insulin {
                        if !insulin.evaluable, let reason = insulin.reason {
                            CaptionText(text: reason)
                        }
                        StatGrid(columns: 3) {
                            StatItem(label: "Gesamt (TDD)", value: BIOSFormat.number(insulin.tdd, digits: 1), unit: "U")
                            StatItem(label: "zur Baseline", value: BIOSFormat.signed(insulin.tddDeltaPct), unit: "%")
                            StatItem(label: "Baseline", value: BIOSFormat.number(insulin.tddBaseline, digits: 1), unit: "U")
                            StatItem(label: "pro 10 g KH", value: BIOSFormat.number(insulin.per10g, digits: 2), unit: "U")
                            StatItem(label: "Kohlenhydrate", value: BIOSFormat.number(insulin.carbs), unit: "g")
                            StatItem(label: "Auto-Bolus", value: BIOSFormat.number(insulin.insAuto, digits: 1), unit: "U")
                        }
                    } else {
                        NotEvaluableBox(title: "Keine Insulindaten", text: "Der Server liefert noch keine Insulin-Kachel.")
                    }
                }
                .foregroundStyle(BIOSTheme.text1)
                .biosCard()

                NavigationLink {
                    TherapyView()
                } label: {
                    TherapyLinkRow()
                }
                .buttonStyle(CardButtonStyle())

                RangePicker(days: $days)
                MetricChartCard(kind: .tdd, days: days)
                MetricChartCard(kind: .per10g, days: days)
                MetricChartCard(kind: .insAuto, days: days)
                NoteText(text: (insulin?.basalNote ?? "Basal rekonstruiert aus Loop-Profil und Temp-Basals.") + " Insulin/10 g KH = Bolus je 10 g Kohlenhydrate. Nur Beobachtung, keine Dosierungshinweise.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
    }
}

/// Detail "Loop": last Nightscout values and IOB over 24 h.
struct LoopDetailView: View {
    @EnvironmentObject var dashboardStore: DashboardStore

    var body: some View {
        let loop = dashboardStore.dashboard?.loop
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                StoreStatusBanner()
                VStack(spacing: 0) {
                    InfoRow(
                        icon: "clock",
                        color: loop?.cgmStale == true ? BIOSTheme.mid : BIOSTheme.good,
                        title: "Letzter CGM-Wert",
                        sub: cgmText(loop),
                        value: (loop?.lastCgmTs ?? loop?.lastTs).map { BIOSFormat.age(since: $0) },
                        status: loop?.cgmStale == true ? "veraltet" : nil
                    )
                    InfoRow(icon: "syringe", color: BIOSTheme.insulin, title: "Aktives Insulin (IOB)",
                            value: "\(BIOSFormat.number(loop?.iob, digits: 2)) U")
                    InfoRow(icon: "drop", color: BIOSTheme.glucose, title: "Aktive Kohlenhydrate (COB)",
                            value: "\(BIOSFormat.number(loop?.cob)) g")
                    InfoRow(icon: "arrow.triangle.2.circlepath", color: BIOSTheme.text2, title: "Temp-Basal",
                            value: "\(BIOSFormat.number(loop?.tempBasalRate, digits: 2)) U/h")
                    InfoRow(icon: "sensor.tag.radiowaves.forward", color: BIOSTheme.text2, title: "Letzter Sensorwechsel",
                            value: loop?.lastSensorChange.map { BIOSFormat.relative($0) } ?? "n. v.")
                }
                .background(BIOSTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                NavigationLink {
                    TherapyView()
                } label: {
                    TherapyLinkRow()
                }
                .buttonStyle(CardButtonStyle())

                SeriesReader(request: SeriesStore.Request(metric: "iob", days: 1, source: nil)) { entry in
                    ChartCard(
                        label: "IOB 24 h",
                        icon: "syringe",
                        color: BIOSTheme.insulin,
                        sub: "stündlich aus Nightscout"
                    ) {
                        if let model = entry?.model, model.hasValues {
                            BIOSChart(spec: LoopDetailView.iobSpec(model))
                                .accessibilityLabel("Aktives Insulin letzte 24 Stunden")
                        } else {
                            ChartPlaceholder(
                                isLoading: entry == nil || entry?.isLoading == true,
                                message: entry?.error ?? "Keine IOB-Werte",
                                height: 140
                            )
                        }
                    }
                }

                NoteText(text: "Werte aus Nightscout (Loop), stündlicher Import. Kein Echtzeitwert, für Live-Daten die Loop-App öffnen.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
    }

    private func cgmText(_ loop: LoopTileModel?) -> String {
        guard let loop else { return "keine Daten" }
        guard let glucose = loop.lastGlucose else {
            if let last = loop.lastCgmTs { return "seit \(BIOSFormat.time(last)) kein Wert" }
            return "kein Wert"
        }
        let time = (loop.lastCgmTs ?? loop.lastTs).map { " um \(BIOSFormat.time($0))" } ?? ""
        return "\(BIOSFormat.number(glucose)) mg/dL\(time)"
    }

    static func iobSpec(_ model: SeriesModel) -> ChartSpec {
        var spec = ChartSpec()
        spec.unit = .hour
        spec.rangeDays = 1
        spec.yMin = 0
        spec.height = 140
        spec.yDigits = 1
        spec.valueUnit = "U"
        spec.valueDigits = 2
        let line = ChartSpec.linePoints(model.points, series: "iob", color: BIOSTheme.insulin)
        spec.lines = line
        spec.area = line
        spec.areaColor = BIOSTheme.insulin
        return spec
    }
}

/// Row inside a card list (icon, title, optional sub line, value on the right).
struct InfoRow: View {
    let icon: String
    let color: Color
    let title: String
    var sub: String?
    var value: String?
    var status: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let sub {
                    Text(sub)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                if let value {
                    Text(value)
                        .foregroundStyle(BIOSTheme.text2)
                        .monospacedDigit()
                }
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.midText)
                }
            }
        }
        .foregroundStyle(BIOSTheme.text1)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(minHeight: 50)
        .overlay(alignment: .top) {
            Rectangle().fill(BIOSTheme.separator).frame(height: 0.5).padding(.leading, 50)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Card row that opens "Loop-Einstellungen" (with the assistant status if loaded).
struct TherapyLinkRow: View {
    @ObservedObject private var store = TherapyStore.shared

    var body: some View {
        let suggestions = store.model?.suggestions
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(BIOSTheme.insulin)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text("Loop-Einstellungen")
                    .font(.body.weight(.semibold))
                Text(subtitle(suggestions))
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BIOSTheme.text3)
        }
        .foregroundStyle(BIOSTheme.text1)
        .padding(14)
        .background(BIOSTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ suggestions: TherapySuggestions?) -> String {
        guard let suggestions else { return "Basal, KH-Verhältnis, Empfindlichkeit, Ziel, abgegeben Ø" }
        return "Basal-Vorschlag: " + (suggestions.recommended ? "zur Übernahme empfohlen" : "nicht zur Übernahme empfohlen")
    }
}
