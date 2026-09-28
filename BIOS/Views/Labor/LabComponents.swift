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

/// Scale for the reference bar: domain, reference band, value, goal tick.
struct LabBarScale: Equatable {
    let lower: Double
    let upper: Double
    let bandLow: Double?
    let bandHigh: Double?
    let value: Double?
    let tick: Double?

    /// From a point (z-score scale for spirometry) and an optional goal.
    init?(point: LabPoint?, target: LabTarget?) {
        guard let point else { return nil }
        if point.usesZScore, let z = point.zScore {
            self.init(value: z, refLow: -1.645, refHigh: nil, tick: nil, zScale: true)
        } else {
            self.init(value: point.value, refLow: point.refLow, refHigh: point.refHigh, tick: target?.tick, zScale: false)
        }
    }

    init?(value: Double?, refLow: Double?, refHigh: Double?, tick: Double?, zScale: Bool = false) {
        if zScale {
            lower = -4
            upper = 3
            bandLow = refLow ?? -1.645
            bandHigh = nil
            self.value = value.map { min(3, max(-4, $0)) }
            self.tick = nil
            return
        }
        let numbers = [value, refLow, refHigh, tick].compactMap { $0 }.filter { $0.isFinite }
        guard let minimum = numbers.min(), let maximum = numbers.max(), refLow != nil || refHigh != nil else {
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
        self.value = value
        self.tick = tick
    }

    func fraction(_ x: Double) -> CGFloat {
        guard upper > lower else { return 0.5 }
        return CGFloat(min(1, max(0, (x - lower) / (upper - lower))))
    }
}

/// Reference bar: light band = the lab's range, dot = the value (status color),
/// optional white tick = therapy goal. No band at all = "ohne Referenz" (dashed).
struct LabRangeBar: View {
    let scale: LabBarScale?
    let status: LabValueStatus
    var height: CGFloat = 6
    var dotSize: CGFloat = 10

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
                    let start = scale.fraction(scale.bandLow ?? scale.lower) * width
                    let end = scale.fraction(scale.bandHigh ?? scale.upper) * width
                    Capsule()
                        .fill(BIOSTheme.good.opacity(0.30))
                        .frame(width: max(2, end - start), height: height)
                        .position(x: start + max(2, end - start) / 2, y: midY)
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
        .frame(height: max(height + 8, dotSize))
        .accessibilityHidden(true)
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
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}
