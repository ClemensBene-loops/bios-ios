import SwiftUI

// Gesundheits-Score, design A: segment ring in the server colors, number +
// level word, week delta pill, cap and chips, the grid of the six Bereiche
// (Heute) and the list with bars, trends and reasons (detail). Formula 4
// (`health.ring`): six segments, arc length = weight, status styles. Old
// servers without `ring` keep the legacy display (six equal pillar arcs,
// Labor in the background). Observation only.

/// Ring input per slot: value, color, arc weight and style. Formula 4 from
/// `health.ring` in server order; old servers the six legacy pillars in
/// equal arcs (Labor has no segment there).
enum HealthRing {
    struct Input {
        let values: [Double?]
        let colors: [Color]
        let arcs: [Double]?
        let styles: [HealthRingSlotStyle]?
    }

    static func input(_ health: HealthModel) -> Input {
        if health.usesRing {
            return Input(values: health.ring.map(\.fill), colors: health.ring.map(\.color),
                         arcs: health.ring.map(\.arc), styles: health.ring.map(\.ringStyle))
        }
        let values = HealthPillarPalette.legacyOrder.map { key in legacyPillar(health, key)?.score }
        let colors = HealthPillarPalette.legacyPillars.map { entry in legacyPillar(health, entry.key)?.color ?? entry.color }
        return Input(values: values, colors: colors, arcs: nil, styles: nil)
    }

    private static func legacyPillar(_ health: HealthModel, _ key: String) -> HealthPillar? {
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
        let input = HealthRing.input(health)
        ZStack {
            HealthSegmentRing(values: input.values, colors: input.colors, arcs: input.arcs, styles: input.styles,
                              radius: (size - lineWidth) / 2, lineWidth: lineWidth, track: .neutral)
            VStack(spacing: 0) {
                Text(health.score == nil && health.usesRing ? "–" : BIOSFormat.number(health.score))
                    .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(health.score == nil ? BIOSTheme.text3 : BIOSTheme.text1)
                Text(health.score == nil && health.usesRing ? "kein Wert" : health.levelWord)
                    .font(.system(size: size * 0.11, weight: .semibold))
                    .foregroundStyle(health.score == nil ? BIOSTheme.text3 : health.levelColor)
            }
            .frame(width: size * 0.62)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(health.scoreAccessibilityText)
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

/// Formula 4 cap below the score: `cap.text`, then `cap.lift` in a calm
/// smaller line. Nothing when the cap does not apply.
struct HealthCapBlock: View {
    let text: String?
    let lift: String?

    var body: some View {
        if text != nil || lift != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let text {
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BIOSTheme.text1)
                        .monospacedDigit()
                }
                if let lift {
                    Text(lift)
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text3)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Formula 4 chips (`abzug`, `stand`, `alkohol`) as calm grey capsules.
struct HealthChipsRow: View {
    let chips: [HealthChip]

    var body: some View {
        if !chips.isEmpty {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(chips) { chip in
                    HStack(spacing: 4) {
                        Image(systemName: chip.symbol)
                            .font(.caption2.weight(.semibold))
                        Text(chip.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text2)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(chip.text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                        Text(health.cardHeadline)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        if health.usesRing, health.score == nil, let reason = health.scoreReason {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(BIOSTheme.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(health.freshnessText)
                            .font(.caption)
                            .foregroundStyle(BIOSTheme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        if !health.usesRing, let capLine = health.capLine {
                            // Formula 2 and 3: the score is capped (Infekt, Frühzeichen, Fieber).
                            Text(capLine)
                                .font(.caption)
                                .foregroundStyle(BIOSTheme.text3)
                                .monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if health.usesRing {
                    HealthCapBlock(text: health.capLine, lift: health.capLift)
                    HealthChipsRow(chips: health.chips)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 3),
                          alignment: .leading, spacing: 12) {
                    if health.usesRing {
                        ForEach(health.ring) { segment in
                            HealthSegmentCell(segment: segment)
                        }
                    } else {
                        ForEach(health.pillars) { pillar in
                            LegacyPillarCell(pillar: pillar)
                        }
                    }
                }
            }
            .foregroundStyle(BIOSTheme.text1)
            .biosCard()
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityHint(health.hasBackgroundPillar
            ? "Öffnet die sechs Bereiche, dazu Labor im Hintergrund"
            : "Öffnet die sechs Bereiche")
    }
}

/// Grid cell of a formula 4 segment: dot, label, value or short status
/// (Pause, nicht erfasst, keine Daten); Labor with its "Stand".
struct HealthSegmentCell: View {
    let segment: HealthSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(segment.displayColor).frame(width: 7, height: 7)
                Text(segment.label)
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if segment.fill != nil {
                Text(segment.shortValue)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(segment.ringStyle == .faded ? BIOSTheme.text2 : BIOSTheme.text1)
                    .padding(.leading, 12)
            } else {
                Text(segment.shortValue)
                    .font(.subheadline)
                    .foregroundStyle(BIOSTheme.text3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.leading, 12)
                    .padding(.vertical, 4)
            }
            if segment.isLabor, let stand = segment.standLabel {
                Text(stand)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text3)
                    .padding(.leading, 12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segment.accessibilityText)
    }
}

/// Grid cell of an old server's pillar (formula 1 to 3).
struct LegacyPillarCell: View {
    let pillar: HealthPillar

    var body: some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pillar.isBackground
            ? "\(pillar.label) \(BIOSFormat.number(pillar.score)), im Hintergrund, nicht im Ring"
            : "\(pillar.label) \(BIOSFormat.number(pillar.score))")
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
                if let label = infection?.abatingLabel {
                    // Alarm pill stays; "klingt ab" beside it, or below when the row is too narrow.
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text("Infekt-Check")
                                .font(.title3.bold())
                            Spacer()
                            TrendPill(text: label)
                            StatusPill(tone: tone, text: pillText(infection))
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Infekt-Check")
                                    .font(.title3.bold())
                                Spacer()
                                StatusPill(tone: tone, text: pillText(infection))
                            }
                            TrendPill(text: label)
                        }
                    }
                } else {
                    HStack {
                        Text("Infekt-Check")
                            .font(.title3.bold())
                        Spacer()
                        StatusPill(tone: tone, text: pillText(infection))
                    }
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

/// Calm pill "klingt ab" next to the alarm pill: the alarm is still active,
/// but the newest scored day is calm (server field `trend`, display only).
struct TrendPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.right")
                .font(.caption.weight(.bold))
            Text(text)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(BIOSTheme.good)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(BIOSTheme.good.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
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
                Text(health?.hasBackgroundPillar == true
                     ? "Sechs Bereiche im Ring, dazu Labor im Hintergrund"
                     : "Deine sechs Bereiche")
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

                    if health.usesRing {
                        segmentSection(health)
                    } else {
                        legacySection(health)
                    }
                } else {
                    NotEvaluableBox(title: "Noch kein Gesundheits-Score", text: "Der Server liefert den Score noch nicht.")
                }

                RangePicker(days: $days)
                MetricChartCard(kind: .healthScore, days: days)

                NoteText(text: noteText(health))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .biosPageBackground()
    }

    /// Formula 4: cap, chips, the six segments with their details.
    @ViewBuilder
    private func segmentSection(_ health: HealthModel) -> some View {
        HealthCapBlock(text: health.capTextForDetail, lift: health.capLift)
            .padding(.horizontal, 4)
        HealthChipsRow(chips: health.chips)
            .padding(.horizontal, 4)
        if health.score == nil, let reason = health.scoreReason, reason != health.secondText {
            Text(reason)
                .font(.footnote)
                .foregroundStyle(BIOSTheme.text2)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(spacing: 0) {
            ForEach(Array(health.ring.enumerated()), id: \.element.id) { entry in
                VStack(alignment: .leading, spacing: 0) {
                    HealthSegmentRow(segment: entry.element)
                    SegmentExtras(segment: entry.element)
                }
                .overlay(alignment: .top) {
                    if entry.offset > 0 {
                        Rectangle().fill(BIOSTheme.separator).frame(height: 0.5)
                    }
                }
            }
        }
        .biosCard()

        if !health.segmentsWithoutValue.isEmpty {
            NoteText(text: "Ohne Wert: " + health.segmentsWithoutValue.joined(separator: ", ") + ". Die übrigen Bereiche zählen anteilig.")
        }
    }

    /// Old servers (formula 1 to 3): cap line, pillar list, dropped pillars.
    @ViewBuilder
    private func legacySection(_ health: HealthModel) -> some View {
        if let details = scoreDetails(health) {
            // Formula 2: cap reason, value before the cap, weakest-link deduction.
            Text(details)
                .font(.footnote)
                .foregroundStyle(BIOSTheme.text2)
                .monospacedDigit()
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(spacing: 0) {
            ForEach(Array(health.pillars.enumerated()), id: \.element.id) { entry in
                VStack(alignment: .leading, spacing: 0) {
                    PillarRow(pillar: entry.element)
                    PillarExtras(pillar: entry.element)
                }
                .overlay(alignment: .top) {
                    if entry.offset > 0 {
                        Rectangle().fill(BIOSTheme.separator).frame(height: 0.5)
                    }
                }
            }
        }
        .biosCard()

        if !health.dropped.isEmpty {
            NoteText(text: "Ohne Wertung: " + health.dropped.joined(separator: ", ") + ". Die übrigen Bereiche zählen anteilig.")
        }
    }

    private func noteText(_ health: HealthModel?) -> String {
        guard let health, health.usesRing else {
            return "Beobachtung, keine Diagnose. Der Score fasst sechs Bereiche im Ring gegen deine eigene Baseline zusammen, dazu Labor als Hintergrundfaktor (bestätigte Laborwerte der letzten 12 Monate, ohne Ring-Segment). Eine Warnung einzelner Checks bleibt davon unberührt."
        }
        let labels = health.ring.map(\.label)
        let list = labels.count > 1
            ? labels.dropLast().joined(separator: ", ") + " und " + (labels.last ?? "")
            : labels.joined()
        var text = "Beobachtung, keine Diagnose. Der Score fasst sechs Bereiche gegen deine eigene Baseline zusammen: \(list). Die Länge eines Bogens zeigt sein Gewicht, die Füllung den Wert. Ein Infekt wirkt über den Deckel, nicht über einen eigenen Bereich. Eine Warnung einzelner Checks bleibt davon unberührt."
        if let levels = health.levelsText { text += " " + levels }
        return text
    }

    /// "Gedeckelt: Infektmuster Tag 4, ohne Deckel 65. Abzug 6: Schlaf 24 unter 40."
    /// (the cap reason only when the subline does not already say it).
    private func scoreDetails(_ health: HealthModel) -> String? {
        var sentences: [String] = []
        let capParts = [health.capReasonForDetail, health.cap?.uncappedText].compactMap { $0 }
        if !capParts.isEmpty {
            sentences.append(Self.sentence(capParts.joined(separator: ", ")))
        }
        if let penalty = health.penaltyReason {
            sentences.append(Self.sentence(penalty))
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    private static func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        let capitalized = first.uppercased() + text.dropFirst()
        return capitalized.hasSuffix(".") ? capitalized : capitalized + "."
    }
}

/// Formula 4 segment in the detail: label, trend, value or status, bar,
/// status line (Pause wegen Infekt, verblasst), reason, share and week delta.
struct HealthSegmentRow: View {
    let segment: HealthSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(segment.displayColor).frame(width: 8, height: 8)
                Text(segment.label)
                    .font(.title3.weight(.semibold))
                Spacer()
                if segment.fill != nil, let symbol = segment.trendSymbol {
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(segment.displayColor)
                }
                Text(segment.shortValue)
                    .font(segment.fill == nil ? Font.subheadline : Font.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(segment.fill == nil ? BIOSTheme.text2 : segment.displayColor)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(segment.fill == nil ? 0.06 : 0.10))
                    if let fill = segment.fill {
                        Capsule()
                            .fill(segment.displayColor)
                            .frame(width: proxy.size.width * CGFloat(Swift.max(0, Swift.min(1, fill / 100))))
                    }
                }
            }
            .frame(height: 5)
            if let status = segment.statusText, status != segment.shortValue {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BIOSTheme.text3)
            }
            if let reason = segment.reason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(BIOSTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let meta = segment.metaLine {
                Text(meta)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text3)
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([segment.accessibilityText, segment.reason, segment.metaLine]
            .compactMap { $0 }
            .joined(separator: ". "))
    }
}

/// Legacy pillar in the detail (old servers).
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
