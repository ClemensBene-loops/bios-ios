import Charts
import SwiftUI

// Building blocks of the Labor tab: tags, the lab reference bar with the value
// dot (and the therapy goal tick), a mini sparkline. Colors always come with a
// word (tag) or the number itself; out of range is calm yellow, never alarm red:
// lab values are an observation, not a diagnosis.

extension LabValueStatus {
    /// Dot and tag color.
    var tint: Color {
        switch self {
        case .normal: return BIOSTheme.good
        case .hoch, .niedrig, .auffaellig: return BIOSTheme.mid
        case .keineReferenz, .unknown: return BIOSTheme.text3
        }
    }
}

/// Small rounded tag ("hoch", "zu prüfen", "seit 3 Wochen").
struct LabTag: View {
    enum Style {
        case good
        case mid
        case bad
        case context
        case grey
    }

    let text: String
    var style: Style = .grey
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
            }
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(background))
    }

    static func style(for status: LabValueStatus) -> Style {
        switch status {
        case .normal: return .good
        case .hoch, .niedrig, .auffaellig: return .mid
        default: return .grey
        }
    }

    private var foreground: Color {
        switch style {
        case .good: return Color(hex: 0x8BEBA6)
        case .mid: return BIOSTheme.midText
        case .bad: return BIOSTheme.badText
        case .context: return BIOSTheme.contextText
        case .grey: return BIOSTheme.text2
        }
    }

    private var background: Color {
        switch style {
        case .good: return BIOSTheme.good.opacity(0.14)
        case .mid: return BIOSTheme.mid.opacity(0.14)
        case .bad: return BIOSTheme.bad.opacity(0.15)
        case .context: return BIOSTheme.context.opacity(0.15)
        case .grey: return Color.white.opacity(0.08)
        }
    }
}

/// Colors of the bands, three clearly separated levels on the dark card:
/// - lab range ("Laborbereich"): subtle, low-opacity green with a faint outline
///   (luminance about 0.05, like a track),
/// - target band ("Zielbereich"): vivid saturated green, drawn taller on top
///   (contrast about 7:1 against the lab band, 10:1 against the empty track),
/// - HbA1c best range: pale mint inside the target, with a thin dark ring.
/// Outside the target but inside the lab range is a calm lavender ring, never red.
/// The history charts use the same colors, translucent (`chart*` opacities).
enum LabTargetStyle {
    static let band = Color(hex: 0x39F27A)
    static let best = Color(hex: 0xCFFFE0)
    static let outside = BIOSTheme.context
    static let referenceBase = BIOSTheme.good
    static let reference = BIOSTheme.good.opacity(0.18)
    static let referenceEdge = BIOSTheme.good.opacity(0.45)
    /// Opacities of the bands behind the points of the history charts.
    static let chartReference = 0.15
    static let chartBand = 0.30
    static let chartHint = 0.14
    static let chartBest = 0.55
    /// Opacities of the chart legend boxes (a bit stronger than the chart, so a
    /// 10 pt box stays readable).
    static let legendReference = 0.35
    static let legendBand = 0.65
    static let legendHint = 0.35
    static let legendBest = 0.9
}

/// One band on the bar; a nil side runs to the bar's edge.
struct LabBarBand: Equatable {
    let low: Double?
    let high: Double?
    /// Evidence "hinweis": hatched and lighter.
    var hint = false
}

/// Scale for the reference bar: domain (covers the lab's range, the target band and
/// the value), reference band, target band, best band, value, goal tick.
struct LabBarScale: Equatable {
    let lower: Double
    let upper: Double
    let bandLow: Double?
    let bandHigh: Double?
    /// The lab printed a range (else no light band).
    let hasReference: Bool
    let value: Double?
    /// Goal tick, only when no target band is drawn (`adds_over_reference` false).
    let tick: Double?
    /// Target band (vivid green, on top).
    let target: LabBarBand?
    /// HbA1c: best possible range inside the target (pale mint).
    let best: LabBarBand?

    /// From a point (z-score scale for spirometry) and an optional target.
    init?(point: LabPoint?, target: LabTarget?) {
        guard let point else { return nil }
        if point.usesZScore, let z = point.zScore {
            self.init(value: z, refLow: -1.645, refHigh: nil, tick: nil, zScale: true)
        } else {
            let usable = target.flatMap { $0.matches(unit: point.unit) ? $0 : nil }
            let band = usable.flatMap { $0.drawsBand ? LabBarBand(low: $0.low, high: $0.high, hint: $0.isHint) : nil }
            var best: LabBarBand?
            if band != nil, let raw = usable?.best, raw.low != nil || raw.high != nil {
                best = LabBarBand(low: raw.low, high: raw.high)
            }
            self.init(value: point.value, refLow: point.refLow, refHigh: point.refHigh,
                      tick: band == nil ? usable?.tick : nil, target: band, best: best, zScale: false)
        }
    }

    init?(value: Double?, refLow: Double?, refHigh: Double?, tick: Double?, target: LabBarBand? = nil,
          best: LabBarBand? = nil, zScale: Bool = false) {
        if zScale {
            lower = -4
            upper = 3
            bandLow = refLow ?? -1.645
            bandHigh = nil
            hasReference = true
            self.value = value.map { min(3, max(-4, $0)) }
            self.tick = nil
            self.target = nil
            self.best = nil
            return
        }
        let bounds = [value, refLow, refHigh, tick, target?.low, target?.high, best?.low, best?.high]
        let numbers = bounds.compactMap { $0 }.filter { $0.isFinite }
        guard let minimum = numbers.min(), let maximum = numbers.max(),
              refLow != nil || refHigh != nil || target != nil else {
            return nil
        }
        var span = maximum - minimum
        if span <= 0 {
            span = max(abs(maximum) * 0.5, 1)
        }
        var low = minimum - span * 0.35
        let high = maximum + span * 0.35
        // Concentrations are never negative: start the scale at 0 then.
        if minimum >= 0 && low < 0 {
            low = 0
        }
        lower = low
        upper = high
        bandLow = refLow
        bandHigh = refHigh
        hasReference = refLow != nil || refHigh != nil
        self.value = value
        self.tick = tick
        self.target = target
        self.best = best
    }

    func fraction(_ x: Double) -> CGFloat {
        guard upper > lower else { return 0.5 }
        return CGFloat(min(1, max(0, (x - lower) / (upper - lower))))
    }

    /// Finite bounds of the target band (for ticks and labels under the bar).
    var targetBounds: [Double] {
        guard let target else { return [] }
        return [target.low, target.high].compactMap { $0 }.filter { $0.isFinite }
    }
}

/// Reference bar: subtle band = the lab's range, vivid taller capsule on top = the
/// target band (hatched for a hint), pale mint inner band = HbA1c best range, dot =
/// the value (status color, lavender ring when outside the target but not flagged),
/// white tick = goal without a band. No band at all = "ohne Referenz" (dashed).
/// `boundaryTicks` adds small ticks under the target's finite bounds (detail bar,
/// labelled by `LabBarAxis`).
struct LabRangeBar: View {
    let scale: LabBarScale?
    let status: LabValueStatus
    var height: CGFloat = 6
    var dotSize: CGFloat = 10
    /// Inside the lab's range but outside the target: calm ring, never red.
    var outsideTarget = false
    var boundaryTicks = false

    /// The target capsule is taller than the track and the lab band, so both of its
    /// edges stay visible where it overlaps the lab band or reaches beyond it.
    private var targetThickness: CGFloat { height + 4 }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let midY = proxy.size.height / 2
            ZStack(alignment: .topLeading) {
                if let scale {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: width, height: height)
                        .position(x: width / 2, y: midY)
                    if scale.hasReference {
                        segment(scale, low: scale.bandLow, high: scale.bandHigh, width: width, midY: midY,
                                thickness: height) {
                            LabReferenceBandFill()
                        }
                    }
                    if let band = scale.target {
                        segment(scale, low: band.low, high: band.high, width: width, midY: midY,
                                thickness: targetThickness) {
                            LabTargetBandFill(hint: band.hint)
                        }
                        if boundaryTicks {
                            let top = midY + targetThickness / 2
                            let length = max(3, proxy.size.height - top)
                            ForEach(Array(scale.targetBounds.enumerated()), id: \.offset) { _, bound in
                                Rectangle()
                                    .fill(LabTargetStyle.band)
                                    .frame(width: 1.5, height: length)
                                    .position(x: scale.fraction(bound) * width, y: top + length / 2)
                            }
                        }
                    }
                    if let best = scale.best {
                        segment(scale, low: best.low, high: best.high, width: width, midY: midY,
                                thickness: height) {
                            LabTargetBandFill(best: true)
                        }
                    }
                    if let tick = scale.tick {
                        Rectangle()
                            .fill(BIOSTheme.text1)
                            .frame(width: 2, height: height + 8)
                            .position(x: scale.fraction(tick) * width, y: midY)
                    }
                    if let value = scale.value {
                        Circle()
                            .fill(status.tint)
                            .overlay(Circle().stroke(BIOSTheme.card, lineWidth: 2))
                            .overlay {
                                if outsideTarget {
                                    Circle()
                                        .stroke(LabTargetStyle.outside, lineWidth: 1.5)
                                        .padding(-2.5)
                                }
                            }
                            .frame(width: dotSize, height: dotSize)
                            .position(x: min(width - dotSize / 2, max(dotSize / 2, scale.fraction(value) * width)), y: midY)
                    }
                } else {
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: width, height: height)
                        .position(x: width / 2, y: midY)
                }
            }
        }
        .frame(height: max(height + 8, dotSize + 5) + (boundaryTicks ? 4 : 0))
        .accessibilityHidden(true)
    }

    /// One band between `low` and `high` (nil = edge of the bar).
    private func segment<Fill: View>(_ scale: LabBarScale, low: Double?, high: Double?, width: CGFloat, midY: CGFloat,
                                     thickness: CGFloat, @ViewBuilder fill: () -> Fill) -> some View {
        let start = scale.fraction(low ?? scale.lower) * width
        let end = scale.fraction(high ?? scale.upper) * width
        let length = max(2, end - start)
        return fill()
            .frame(width: length, height: thickness)
            .position(x: start + length / 2, y: midY)
    }
}

/// Fill of the lab's range: subtle low-opacity green with a faint outline.
struct LabReferenceBandFill: View {
    var body: some View {
        Capsule()
            .fill(LabTargetStyle.reference)
            .overlay(Capsule().strokeBorder(LabTargetStyle.referenceEdge, lineWidth: 1))
    }
}

/// Fill of a target band: solid vivid green; pale mint with a thin dark ring for the
/// HbA1c best range; hatched with a vivid outline for a hint (evidence "hinweis").
struct LabTargetBandFill: View {
    var hint = false
    var best = false

    var body: some View {
        if hint {
            Capsule()
                .fill(LabTargetStyle.band.opacity(0.16))
                .overlay(LabHatch().stroke(LabTargetStyle.band.opacity(0.9), lineWidth: 1).clipShape(Capsule()))
                .overlay(Capsule().strokeBorder(LabTargetStyle.band, lineWidth: 1))
        } else if best {
            Capsule()
                .fill(LabTargetStyle.best)
                .overlay(Capsule().strokeBorder(BIOSTheme.card, lineWidth: 1))
        } else {
            Capsule()
                .fill(LabTargetStyle.band)
        }
    }
}

/// Legend swatch drawn exactly like the band on the bar.
struct LabBandSwatch: View {
    enum Kind {
        case reference
        case target
        case hint
        /// Best range: mint inside a piece of the target band, as on the bar.
        case best
    }

    let kind: Kind

    var body: some View {
        switch kind {
        case .reference:
            LabReferenceBandFill().frame(width: 16, height: 6)
        case .target:
            LabTargetBandFill().frame(width: 16, height: 10)
        case .hint:
            LabTargetBandFill(hint: true).frame(width: 16, height: 10)
        case .best:
            LabTargetBandFill()
                .frame(width: 18, height: 10)
                .overlay(LabTargetBandFill(best: true).frame(width: 10, height: 6))
        }
    }
}

/// Axis under the big reference bar: the scale's min and max at the edges (grey)
/// and the target's finite bounds in green under their ticks. An edge label that
/// would collide with a target label is dropped; two close bounds share one label.
struct LabBarAxis: View {
    let scale: LabBarScale
    let decimals: Int?

    private struct Mark: Identifiable {
        let id: Int
        let fraction: CGFloat
        let text: String
        let target: Bool
    }

    var body: some View {
        LabAxisLayout {
            ForEach(marks) { mark in
                Text(mark.text)
                    .font(mark.target ? Font.caption2.weight(.semibold) : Font.caption2)
                    .monospacedDigit()
                    .foregroundStyle(mark.target ? LabTargetStyle.band : BIOSTheme.text3)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutValue(key: LabAxisFraction.self, value: mark.fraction)
            }
        }
        .accessibilityHidden(true)
    }

    private var marks: [Mark] {
        let bounds = scale.targetBounds.sorted()
        let targets: [Mark]
        if bounds.count == 2, scale.fraction(bounds[1]) - scale.fraction(bounds[0]) < 0.14 {
            let middle = (scale.fraction(bounds[0]) + scale.fraction(bounds[1])) / 2
            targets = [Mark(id: 2, fraction: middle,
                            text: "\(format(bounds[0])) bis \(format(bounds[1]))", target: true)]
        } else {
            targets = bounds.enumerated().map { index, bound in
                Mark(id: 2 + index, fraction: scale.fraction(bound), text: format(bound), target: true)
            }
        }
        var result: [Mark] = []
        if !targets.contains(where: { $0.fraction < 0.14 }) {
            result.append(Mark(id: 0, fraction: 0, text: format(scale.lower), target: false))
        }
        if !targets.contains(where: { $0.fraction > 0.86 }) {
            result.append(Mark(id: 1, fraction: 1, text: format(scale.upper), target: false))
        }
        return result + targets
    }

    private func format(_ number: Double) -> String {
        LabFormat.value(number, decimals: decimals)
    }
}

private struct LabAxisFraction: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

/// Places each label centered at its fraction of the width, clamped inside the row.
private struct LabAxisLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let center = bounds.minX + subview[LabAxisFraction.self] * bounds.width
            let x = min(bounds.maxX - size.width, max(bounds.minX, center - size.width / 2))
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(size))
        }
    }
}

/// Diagonal hatching for hint bands.
struct LabHatch: Shape {
    var spacing: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

/// Legend line with the same swatches as the bar: "blass: Laborbereich, kräftig
/// grün: Zielbereich (Leitlinie)".
struct LabBandLegend: View {
    var body: some View {
        FlowLayout(spacing: 14, lineSpacing: 4) {
            HStack(spacing: 6) {
                LabBandSwatch(kind: .reference)
                Text("blass: Laborbereich")
            }
            HStack(spacing: 6) {
                LabBandSwatch(kind: .target)
                Text("kräftig grün: Zielbereich (Leitlinie)")
            }
        }
        .font(.caption)
        .foregroundStyle(BIOSTheme.text2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Legende: blasses Band Laborbereich, kräftig grünes Band Zielbereich nach Leitlinie")
    }
}

/// Target block of the marker detail: label with the judgement of the value, HbA1c
/// best range, why, risk tier and note (LDL, non-HDL, ApoB), evidence and source link.
struct LabTargetInfo: View {
    let target: LabTarget
    let decimals: Int
    /// `in_target` of the shown point.
    let inTarget: Bool?
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                LabBandSwatch(kind: target.isHint ? .hint : .target)
                    .accessibilityHidden(true)
                Text(target.displayLabel(decimals: decimals))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BIOSTheme.text1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if let judgement = target.judgement(inTarget: inTarget, value: value) {
                    LabTag(text: judgement, style: inTarget == true ? .good : .context)
                }
            }
            .accessibilityElement(children: .combine)
            if let label = target.best?.label {
                HStack(spacing: 8) {
                    LabBandSwatch(kind: .best)
                        .accessibilityHidden(true)
                    Text(label.prefix(1).uppercased() + String(label.dropFirst()))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(BIOSTheme.text1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            if let why = target.why {
                Text(why)
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let tier = target.tierLabel {
                Text("Risikostufe: \(tier)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(BIOSTheme.text1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = target.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if target.evidenceText != nil || target.source != nil {
                HStack(alignment: .center, spacing: 8) {
                    if let evidence = target.evidenceText {
                        LabTag(text: evidence, style: target.isHint ? .grey : .context)
                    }
                    source
                    Spacer(minLength: 0)
                }
            }
            if target.origin == "profil" {
                Text("Ziel aus deinem Laborprofil.")
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
            }
        }
    }

    @ViewBuilder
    private var source: some View {
        if let url = target.url {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Text(target.source ?? "Quelle")
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2.weight(.semibold))
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(BIOSTheme.accent)
            }
            .accessibilityLabel("Quelle: \(target.source ?? "Leitlinie")")
            .accessibilityHint("Öffnet die Quelle im Browser")
        } else if let name = target.source {
            Text("Quelle: \(name)")
                .font(.caption)
                .foregroundStyle(BIOSTheme.text2)
                .lineLimit(2)
        }
    }
}

/// Mini trend of the last measurements (grey line, last dot in status color).
struct LabSparkline: View {
    let values: [Double]
    let status: LabValueStatus

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            if values.count >= 2, let minimum = values.min(), let maximum = values.max() {
                let range = maximum - minimum > 0 ? maximum - minimum : 1
                let lowValue = maximum - minimum > 0 ? minimum : minimum - 0.5
                let points: [CGPoint] = values.enumerated().map { index, value in
                    CGPoint(
                        x: 3 + (width - 6) * CGFloat(index) / CGFloat(values.count - 1),
                        y: height - 3 - (height - 6) * CGFloat((value - lowValue) / range)
                    )
                }
                Path { path in
                    path.addLines(points)
                }
                .stroke(BIOSTheme.text3, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                if let last = points.last {
                    Circle()
                        .fill(status.tint)
                        .frame(width: 5, height: 5)
                        .position(last)
                }
            }
        }
        .frame(width: 46, height: 18)
        .accessibilityHidden(true)
    }
}

/// Round icon of a document kind.
struct LabKindIcon: View {
    let kind: String?
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: LabKind.symbol(kind))
            .font(.body)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch kind ?? "" {
        case "blut": return BIOSTheme.rhr
        case "spiro": return BIOSTheme.resp
        case "schlaf": return BIOSTheme.sleep
        case "dexa": return BIOSTheme.loop
        default: return BIOSTheme.text2
        }
    }
}

/// Section label in capitals with an optional trailing note.
struct LabSectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(BIOSTheme.text2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text3)
                    .accessibilityLabel(trailing.replacingOccurrences(of: "/", with: " von "))
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

// MARK: - Scrubbing

/// Scrubbing on the Labor charts, the same interaction as `BIOSChartBody`: hold
/// (0.25 s) and drag, the UIKit `ScrubGesture` never fights the scroll view, the
/// selection snaps to the nearest point in time, selection haptics on each step.
struct LabChartScrub: ViewModifier {
    @Binding var selected: Date?
    /// Snap targets (any order, duplicates allowed).
    let dates: [Date]

    func body(content: Content) -> some View {
        content
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    ScrubGesture(
                        onChange: { x in update(x: x, proxy: proxy, geometry: geometry) },
                        onEnd: { selected = nil }
                    )
                    .accessibilityHidden(true)
                }
            }
            .sensoryFeedback(.selection, trigger: selected)
    }

    private func update(x: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geometry[plotFrame].origin
        guard let date = proxy.value(atX: x - origin.x, as: Date.self),
              let nearest = Self.nearest(to: date, in: dates) else { return }
        if nearest != selected {
            selected = nearest
        }
    }

    static func nearest(to date: Date, in dates: [Date]) -> Date? {
        dates.min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }
    }
}

extension View {
    func labChartScrub(selected: Binding<Date?>, dates: [Date]) -> some View {
        modifier(LabChartScrub(selected: selected, dates: dates))
    }
}

/// Dashed vertical rule at the selected point with the scrub bubble on top,
/// styled like the selection of `BIOSChartBody`. Drawn last, so it lies above
/// the marks; the reference band underneath stays visible.
struct LabSelectionRule: ChartContent {
    let date: Date
    let lines: [String]

    var body: some ChartContent {
        RuleMark(x: .value("Auswahl", date))
            .foregroundStyle(Color.white.opacity(0.65))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .annotation(
                position: .top,
                spacing: 0,
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
            ) {
                SelectionBubble(lines: lines)
            }
            .accessibilityHidden(true)
    }
}

/// Target band behind the points of a Labor chart: the bar's vivid green, translucent,
/// over the whole width; the HbA1c best range as pale mint inside; a hint band fainter
/// with dashed edges.
struct LabTargetBandMarks: ChartContent {
    let xStart: Date
    let xEnd: Date
    let bandLow: Double?
    let bandHigh: Double?
    var bestLow: Double? = nil
    var bestHigh: Double? = nil
    var hintEdges: [Double] = []
    var hint = false
    var opacity = LabTargetStyle.chartBand

    var body: some ChartContent {
        if let bandLow, let bandHigh {
            RectangleMark(
                xStart: .value("Von", xStart),
                xEnd: .value("Bis", xEnd),
                yStart: .value("Ziel unten", bandLow),
                yEnd: .value("Ziel oben", bandHigh)
            )
            .foregroundStyle(LabTargetStyle.band.opacity(hint ? LabTargetStyle.chartHint : opacity))
            .accessibilityHidden(true)
        }
        ForEach(hintEdges, id: \.self) { edge in
            RuleMark(y: .value("Hinweisgrenze", edge))
                .foregroundStyle(LabTargetStyle.band)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .accessibilityHidden(true)
        }
        if let bestLow, let bestHigh {
            RectangleMark(
                xStart: .value("Von", xStart),
                xEnd: .value("Bis", xEnd),
                yStart: .value("Bestmöglich unten", bestLow),
                yEnd: .value("Bestmöglich oben", bestHigh)
            )
            .foregroundStyle(LabTargetStyle.best.opacity(LabTargetStyle.chartBest))
            .accessibilityHidden(true)
        }
    }
}

enum LabChartText {
    /// "27.09.2026, 21:36" with a time of day, else "15.09.2026".
    static func when(_ date: Date, timed: Bool) -> String {
        timed ? "\(LabFormat.fullDate(date)), \(BIOSFormat.time(date))" : LabFormat.fullDate(date)
    }

    /// " · hoch" for a flagged status, else "".
    static func statusSuffix(_ status: LabValueStatus) -> String {
        guard status.isFlagged, let tag = status.tag else { return "" }
        return " · " + tag
    }

    /// " · im Ziel" / " · außerhalb Ziel" from `in_target`, "" without a decision.
    static func targetSuffix(_ inTarget: Bool?, hint: Bool = false) -> String {
        guard let inTarget else { return "" }
        if hint { return inTarget ? " · im Hinweisbereich" : " · außerhalb Hinweisbereich" }
        return inTarget ? " · im Ziel" : " · außerhalb Ziel"
    }
}
