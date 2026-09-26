import SwiftUI

// Gesundheits-Score, design A ("Säulen"): six-segment ring in the pillar
// colors, number + level word, week delta pill, pillar grid (Heute) and the
// pillar list with bars, trends and reasons (detail). Observation only.

/// Ring input in the shared ring order (HealthPillarPalette): score per slot
/// (nil = pillar missing, dashed grey) and color per slot.
enum HealthRing {
    static func values(_ health: HealthModel) -> [Double?] {
        HealthPillar.order.map { key in pillar(health, key)?.score }
    }

    static func colors(_ health: HealthModel) -> [Color] {
        HealthPillarPalette.pillars.map { entry in pillar(health, entry.key)?.color ?? entry.color }
    }

    private static func pillar(_ health: HealthModel, _ key: String) -> HealthPillar? {
        health.pillars.first { HealthPillar.canonical($0.key, $0.label) == key }
    }
}

/// Ring with number and level word. Geometry: Shared/HealthRing.swift; the
/// stroke's outer edge touches the frame (center line radius (size - lineWidth) / 2).
struct HealthRingView: View {
    let health: HealthModel
    var size: CGFloat = 150
    var lineWidth: CGFloat = 11

    var body: some View {
        ZStack {
            HealthSegmentRing(values: HealthRing.values(health), colors: HealthRing.colors(health),
                              radius: (size - lineWidth) / 2, lineWidth: lineWidth, track: .neutral)
            VStack(spacing: 0) {
                Text(BIOSFormat.number(health.score))
                    .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(BIOSTheme.text1)
                Text(health.levelWord)
                    .font(.system(size: size * 0.11, weight: .semibold))
                    .foregroundStyle(health.levelColor)
            }
            .frame(width: size * 0.62)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gesundheits-Score \(BIOSFormat.number(health.score)) von 100, \(health.levelWord)")
    }
}

/// "↗ +4 zur Vorwoche"
struct HealthDeltaPill: View {
    let health: HealthModel

    var body: some View {
        if let text = health.deltaText {
            HStack(spacing: 5) {
                Image(systemName: health.deltaSymbol)
                    .font(.caption.weight(.semibold))
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(BIOSTheme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(BIOSTheme.accent.opacity(0.14), in: Capsule())
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Heute card

struct HealthScoreCard: View {
    let health: HealthModel

    var body: some View {
        NavigationLink(value: DetailRoute.gesundheit) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Gesundheits-Score")
                        .font(.title3.bold())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BIOSTheme.text3)
                }
                HStack(alignment: .center, spacing: 16) {
                    HealthRingView(health: health, size: 138, lineWidth: 11)
                    VStack(alignment: .leading, spacing: 10) {
                        HealthDeltaPill(health: health)
                        Text("Sechs Säulen.\nEin Gesamtbild.")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(health.freshnessText)
                            .font(.caption)
                            .foregroundStyle(BIOSTheme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 3),
                          alignment: .leading, spacing: 12) {
                    ForEach(health.pillars) { pillar in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Circle().fill(pillar.color).frame(width: 7, height: 7)
                                Text(pillar.label)
                                    .font(.caption)
                                    .foregroundStyle(BIOSTheme.text2)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            Text(BIOSFormat.number(pillar.score))
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                                .padding(.leading, 12)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .foregroundStyle(BIOSTheme.text1)
            .biosCard()
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityHint("Öffnet die sechs Säulen")
    }
}

// MARK: - Heute: compact Infekt-Check

/// Infekt-Check in design A: score / 100 · Tag n, status pill, 7-day
/// sparkline of the score, temperature line. Tap opens the full detail.
struct InfektCheckCompactCard: View {
    let infection: InfectionModel?
    let vitals: DashboardVitalsModel?

    var body: some View {
        let tone = infection?.tone ?? .unknown
        NavigationLink(value: DetailRoute.infekt) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Infekt-Check")
                        .font(.title3.bold())
                    Spacer()
                    StatusPill(tone: tone, text: pillText(infection))
                }
                HStack(alignment: .center, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(infection?.score.map { BIOSFormat.number($0) } ?? BIOSFormat.number(infection?.recovery))
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(scoreSuffix(infection))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(BIOSTheme.text2)
                    }
                    Spacer(minLength: 8)
                    SeriesReader(request: SeriesStore.Request(metric: MetricKind.infectionScore.metric, days: 14, source: nil)) { entry in
                        let values = (entry?.model?.points ?? []).map(\.value)
                        if values.compactMap({ $0 }).count >= 2 {
                            ScoreSparkline(values: values, color: tone == .warn || tone == .info ? tone.tint : BIOSTheme.text2)
                                .frame(width: 140, height: 34)
                                .accessibilityHidden(true)
                        }
                    }
                }
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(BIOSTheme.text1)
            .biosCard()
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öffnet den Infekt-Check")
    }

    private func pillText(_ infection: InfectionModel?) -> String {
        guard let infection else { return "keine Daten" }
        switch infection.tone {
        case .warn: return "Auffällig"
        case .info: return infection.status == .warn ? "Auffällig" : "Hinweis"
        case .ok: return "Im Rahmen"
        case .unknown: return "nicht bewertbar"
        }
    }

    private func scoreSuffix(_ infection: InfectionModel?) -> String {
        guard let infection else { return "" }
        if infection.score == nil {
            return infection.recovery == nil ? "" : "% Recovery"
        }
        if let day = infection.episodeDay { return "/ 100 · Tag \(day)" }
        return "/ 100"
    }

    /// Temperature first ("Temperatur 37,2 °C"), then the headline and context.
    private var lines: [String] {
        var lines: [String] = []
        if let context = infection?.temperatureContext {
            lines.append("Temperatur: " + context)
        } else if let value = vitals?.temperature, let at = vitals?.temperatureAt,
                  Date().timeIntervalSince(at) < 36 * 3_600 {
            lines.append("Temperatur \(BIOSFormat.number(value, digits: 1)) °C · \(BIOSFormat.relative(at))")
        }
        if let infection {
            lines.append(infection.headline + (infection.subline.map { ". \($0)" } ?? ""))
            if let env = infection.envContext { lines.append(env) }
            if let note = infection.confounderNote { lines.append(note) }
        }
        return Array(lines.prefix(3))
    }
}

/// Status pill of the Infekt-Check. `tone` is `InfectionModel.tone` (one
/// color mapping for card, hero and detail): red / yellow / green / grey.
struct StatusPill: View {
    let tone: BIOSStatus
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tone == .warn || tone == .info ? "exclamationmark" : tone.symbol)
                .font(.caption.weight(.bold))
            Text(text)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(tone.tint.opacity(0.16), in: Capsule())
    }

    private var textColor: Color {
        switch tone {
        case .warn: return BIOSTheme.badText
        case .info: return BIOSTheme.midText
        case .ok, .unknown: return tone.tint
        }
    }
}

/// Small line of the last days (gaps stay gaps), no axes.
struct ScoreSparkline: View {
    let values: [Double?]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let numbers = values.compactMap { $0 }
            let low = (numbers.min() ?? 0) - 2
            let high = Swift.max((numbers.max() ?? 1) + 2, low + 1)
            let count = Swift.max(values.count, 2)
            Path { path in
                var penDown = false
                for (index, value) in values.enumerated() {
                    guard let value else {
                        penDown = false
                        continue
                    }
                    let x = proxy.size.width * CGFloat(index) / CGFloat(count - 1)
                    let y = proxy.size.height * (1 - CGFloat((value - low) / (high - low)))
                    if penDown {
                        path.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        path.move(to: CGPoint(x: x, y: y))
                        penDown = true
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Heute: Deine Routine

/// "Deine Routine": supplements x von y with a segmented bar (tap opens the
/// quick log), alcohol today/yesterday, medications.
struct RoutineCard: View {
    @EnvironmentObject var events: EventStore
    @EnvironmentObject var supplements: SupplementStore
    @EnvironmentObject var medications: MedicationStore
    @EnvironmentObject var plan: MedicationPlanStore
    let open: (QuickLogTarget) -> Void

    var body: some View {
        let now = Date()
        let today = EventStore.dayString(now)
        let yesterday = EventStore.dayString(Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now)
        let count = supplementCount(today)
        VStack(alignment: .leading, spacing: 12) {
            Text("Deine Routine")
                .font(.title3.bold())

            Button {
                open(.supplements)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Supplements")
                            .foregroundStyle(BIOSTheme.text2)
                        Spacer()
                        Text(count.total > 0 ? "\(count.taken) von \(count.total)" : "eintragen")
                            .font(.headline)
                            .monospacedDigit()
                    }
                    if count.total > 0 {
                        SegmentedProgress(done: count.taken, total: count.total, color: BIOSTheme.good)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Supplements, \(count.taken) von \(count.total)")

            Divider().overlay(BIOSTheme.separator)

            HStack(spacing: 8) {
                Label("Alkohol", systemImage: "wineglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BIOSTheme.context)
                Spacer(minLength: 4)
                SlimToggle(title: "Heute", on: events.isMarked(today)) { events.toggle(today) }
                SlimToggle(title: "Gestern", on: events.isMarked(yesterday)) { events.toggle(yesterday) }
                NavigationLink(value: DetailRoute.alkohol) {
                    Image(systemName: "calendar")
                        .foregroundStyle(BIOSTheme.accent)
                }
                .accessibilityLabel("Alkohol-Kalender")
            }

            Divider().overlay(BIOSTheme.separator)

            Button {
                open(.medications)
            } label: {
                HStack(spacing: 8) {
                    Label("Medikamente", systemImage: "cross.case")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BIOSTheme.insulin)
                    Spacer(minLength: 4)
                    Text(medicationText(today))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(BIOSTheme.text2)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BIOSTheme.text3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(BIOSTheme.text1)
        .biosCard()
    }

    private func supplementCount(_ today: String) -> (taken: Int, total: Int) {
        let count = supplements.takenCount(on: today)
        if count.total > 0 { return count }
        if let intake = supplements.dashboardIntake, let taken = intake.taken, let total = intake.total {
            return (taken, total)
        }
        return (0, 0)
    }

    private func medicationText(_ today: String) -> String {
        let progress = plan.progress(on: today)
        if progress.total > 0 { return "heute \(progress.taken)/\(progress.total)" }
        let count = Swift.max(medications.count(on: today), supplements.dashboardIntake?.medicationsToday ?? 0)
        return count == 0 ? "heute keine" : "heute \(count)"
    }
}

/// Row of equal segments, the first `done` filled.
struct SegmentedProgress: View {
    let done: Int
    let total: Int
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<Swift.max(1, Swift.min(total, 20)), id: \.self) { index in
                Capsule()
                    .fill(index < done ? color : Color.white.opacity(0.14))
                    .frame(height: 5)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Detail

struct HealthDetailView: View {
    @EnvironmentObject var dashboardStore: DashboardStore
    @AppStorage(RangeSetting.key) private var days = 7

    var body: some View {
        let health = dashboardStore.dashboard?.health
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                StoreStatusBanner()
                Text("Deine sechs Säulen")
                    .font(.title3)
                    .foregroundStyle(BIOSTheme.text2)
                    .padding(.horizontal, 4)
                if let health {
                    HStack(alignment: .center, spacing: 18) {
                        HealthRingView(health: health, size: 130, lineWidth: 10)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(health.titleText)
                                .font(.title2.bold())
                                .fixedSize(horizontal: false, vertical: true)
                            if let second = health.secondText {
                                Text(second)
                                    .font(.title3)
                                    .foregroundStyle(BIOSTheme.text2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            HealthDeltaPill(health: health)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(BIOSTheme.text1)
                    .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(health.pillars.enumerated()), id: \.element.id) { entry in
                            PillarRow(pillar: entry.element)
                                .overlay(alignment: .top) {
                                    if entry.offset > 0 {
                                        Rectangle().fill(BIOSTheme.separator).frame(height: 0.5)
                                    }
                                }
                        }
                    }
                    .biosCard()

                    if !health.dropped.isEmpty {
                        NoteText(text: "Ohne Wertung: " + health.dropped.joined(separator: ", ") + ". Die übrigen Säulen zählen anteilig.")
                    }
                } else {
                    NotEvaluableBox(title: "Noch kein Gesundheits-Score", text: "Der Server liefert den Score noch nicht.")
                }

                RangePicker(days: $days)
                MetricChartCard(kind: .healthScore, days: days)

                NoteText(text: "Beobachtung, keine Diagnose. Der Score fasst sechs Säulen gegen deine eigene Baseline zusammen; eine Warnung einzelner Checks bleibt davon unberührt.")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
    }
}

struct PillarRow: View {
    let pillar: HealthPillar

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(pillar.color).frame(width: 8, height: 8)
                Text(pillar.label)
                    .font(.title3.weight(.semibold))
                Spacer()
                if let symbol = pillar.trendSymbol {
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(pillar.color)
                }
                Text(pillar.score == nil ? "keine Daten" : BIOSFormat.number(pillar.score))
                    .font(pillar.score == nil ? Font.subheadline : Font.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(pillar.score == nil ? BIOSTheme.text2 : pillar.color)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(pillar.color)
                        .frame(width: proxy.size.width * CGFloat(Swift.max(0, Swift.min(1, (pillar.score ?? 0) / 100))))
                }
            }
            .frame(height: 5)
            if let reason = pillar.reason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(BIOSTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pillar.score == nil
            ? "\(pillar.label), keine Daten. \(pillar.reason ?? "")"
            : "\(pillar.label) \(BIOSFormat.number(pillar.score)) von 100, \(pillar.trendWord). \(pillar.reason ?? "")")
    }
}
