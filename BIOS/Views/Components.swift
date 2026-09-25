import SwiftUI
import UIKit

/// Recovery ring (Whoop colors). The number is always shown next to it.
struct RecoveryRing: View {
    let value: Double?
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        let fraction = max(0, min(100, value ?? 0)) / 100
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(
                    LinearGradient(colors: [color.opacity(0.55), color], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

/// Wrapping row layout for chips and legends.
struct FlowLayout: Layout {
    var spacing: CGFloat = 7
    var lineSpacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(size.width, maxWidth)
            if x > 0, x + width > maxWidth {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            x += width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        let width = proposal.width ?? widest
        return CGSize(width: width.isFinite ? width : widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let width = min(size.width, bounds.width)
            if x > bounds.minX, x + width > bounds.maxX {
                y += rowHeight + lineSpacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: size.height)
            )
            x += width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Deviation chip of the infection check: flagged = color + arrow,
/// context role = indigo, not evaluable = dashed border + sensor symbol.
struct ChipView: View {
    let chip: InfectionChip
    let status: BIOSStatus

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
            }
            Text(chip.label)
            Text(chip.display)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
        }
        .font(.footnote)
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(labelColor)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .frame(minHeight: 30)
        .background(Capsule().fill(background))
        .overlay(border)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private enum Style {
        case plain
        case bad
        case mid
        case context
        case notEvaluable
    }

    private var style: Style {
        if !chip.evaluable { return .notEvaluable }
        if !chip.flagged { return .plain }
        if chip.role == .context { return .context }
        return status == .warn ? .bad : .mid
    }

    private var symbol: String? {
        switch style {
        case .notEvaluable: return "circle.dashed"
        case .plain: return nil
        default:
            switch chip.direction {
            case "down": return "arrow.down"
            case "flat": return "arrow.right"
            default: return "arrow.up"
            }
        }
    }

    private var background: Color {
        switch style {
        case .plain: return BIOSTheme.card2
        case .bad: return BIOSTheme.bad.opacity(0.15)
        case .mid: return BIOSTheme.mid.opacity(0.14)
        case .context: return BIOSTheme.context.opacity(0.15)
        case .notEvaluable: return Color.clear
        }
    }

    private var labelColor: Color {
        switch style {
        case .plain: return BIOSTheme.text2
        case .bad: return BIOSTheme.badText
        case .mid: return BIOSTheme.midText
        case .context: return BIOSTheme.contextText
        case .notEvaluable: return BIOSTheme.text3
        }
    }

    private var valueColor: Color {
        switch style {
        case .plain: return BIOSTheme.text1
        case .notEvaluable: return BIOSTheme.text2
        default: return labelColor
        }
    }

    @ViewBuilder
    private var border: some View {
        switch style {
        case .plain:
            EmptyView()
        case .notEvaluable:
            Capsule().strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        case .bad:
            Capsule().strokeBorder(BIOSTheme.bad.opacity(0.42), lineWidth: 1)
        case .mid:
            Capsule().strokeBorder(BIOSTheme.mid.opacity(0.42), lineWidth: 1)
        case .context:
            Capsule().strokeBorder(BIOSTheme.context.opacity(0.42), lineWidth: 1)
        }
    }

    private var accessibilityText: String {
        var text = "\(chip.label) \(chip.display)"
        switch style {
        case .notEvaluable:
            text += ", nicht bewertbar" + (chip.reason.map { ": \($0)" } ?? "")
        case .context:
            text += ", erhöht, nur Kontext"
        case .bad, .mid:
            text += ", auffällig"
        case .plain:
            break
        }
        return text
    }
}

/// Small capsule label ("erhöht, Kontext", "nicht bewertbar", "CGM vor 2 h").
struct PillView: View {
    enum Kind {
        case context
        case warn
        case notEvaluable
    }

    let kind: Kind
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol ?? defaultSymbol)
                .font(.caption2.weight(.bold))
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(background))
        .overlay {
            if kind == .notEvaluable {
                Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            }
        }
    }

    private var defaultSymbol: String {
        switch kind {
        case .context: return "arrow.up"
        case .warn: return "exclamationmark.triangle"
        case .notEvaluable: return "circle.dashed"
        }
    }

    private var foreground: Color {
        switch kind {
        case .context: return Color(hex: 0xC0CAFF)
        case .warn: return BIOSTheme.midText
        case .notEvaluable: return BIOSTheme.text2
        }
    }

    private var background: Color {
        switch kind {
        case .context: return BIOSTheme.context.opacity(0.15)
        case .warn: return BIOSTheme.mid.opacity(0.14)
        case .notEvaluable: return Color.clear
        }
    }
}

/// "Offline, Stand gestern 21:40" banner above cached content.
struct OfflineBanner: View {
    let isOffline: Bool
    let error: String?
    let stand: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.icloud")
                .font(.title3)
                .foregroundStyle(BIOSTheme.mid)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(BIOSTheme.text2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(hex: 0x1F1A0E), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(BIOSTheme.mid.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        let standText = stand.map { ", Stand \(BIOSFormat.relative($0))" } ?? ""
        return (isOffline ? "Offline" : "Nicht aktualisiert") + standText
    }

    private var detail: String {
        if isOffline {
            return "Gespeicherte Daten. BIOS aktualisiert, sobald wieder Netz da ist."
        }
        return (error ?? "Server nicht erreichbar") + ". Gespeicherte Daten."
    }
}

/// Box for "nicht bewertbar" / "keine Daten" with the reason.
struct NotEvaluableBox: View {
    let title: String
    let text: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.dashed")
                .font(.body)
                .foregroundStyle(BIOSTheme.text1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BIOSTheme.text1)
                if let text, !text.isEmpty {
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(BIOSTheme.text2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Section title with an optional "Details" link to a detail screen.
struct SectionHeader: View {
    let title: String
    var route: DetailRoute?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let route {
                NavigationLink(value: route) {
                    Text("Details")
                        .font(.body)
                }
                .accessibilityLabel("\(title), Details")
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 14)
    }
}

/// Small grey uppercase label ("INFEKT-CHECK").
struct EyebrowText: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.7)
            .foregroundStyle(BIOSTheme.text2)
    }
}

/// Explanation paragraph under a section.
struct NoteText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(BIOSTheme.text3)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One statistic: small label over a number with unit.
struct StatItem: View {
    let label: String
    let value: String
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(BIOSTheme.text2)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// 3-column (or 2-column) grid of StatItems.
struct StatGrid<Content: View>: View {
    var columns: Int = 3
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: columns),
            alignment: .leading,
            spacing: 12
        ) {
            content()
        }
    }
}

/// Pollen level dot: size AND color encode the level (0 keine ... 3 hoch).
struct PollenDot: View {
    let rank: Int

    var body: some View {
        let color = BIOSLevel.pollenColor(rank)
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(rank >= 3 ? 0 : 0.2), lineWidth: 1.5)
            Circle()
                .fill(color)
                .frame(width: innerSize, height: innerSize)
        }
        .frame(width: 15, height: 15)
        .accessibilityHidden(true)
    }

    private var innerSize: CGFloat {
        switch rank {
        case 1: return 5
        case 2: return 9
        case 3...: return 15
        default: return 0
        }
    }
}

/// Virus trend arrow (direction carries the information).
struct TrendArrow: View {
    let fine: String

    var body: some View {
        Image(systemName: BIOSLevel.trendSymbol(fine))
            .font(.footnote.weight(BIOSLevel.isStrong(fine) ? .heavy : .semibold))
            .foregroundStyle(BIOSLevel.isStrong(fine) ? BIOSTheme.strongTrend : BIOSTheme.text2)
            .accessibilityHidden(true)
    }
}

/// 24 h glucose sparkline with the 70 to 180 target band; gaps stay gaps.
struct Sparkline: View {
    let values: [Double?]
    let color: Color
    var low: Double = 40
    var high: Double = 280
    var targetLow: Double = 70
    var targetHigh: Double = 180

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let count = max(values.count, 2)
            let xFor: (Int) -> CGFloat = { index in
                2 + (width - 6) * CGFloat(index) / CGFloat(count - 1)
            }
            let yFor: (Double) -> CGFloat = { value in
                let clamped = min(high, max(low, value))
                return height - 3 - CGFloat((clamped - low) / (high - low)) * (height - 6)
            }
            ZStack(alignment: .topLeading) {
                Path { path in
                    let top = yFor(targetHigh)
                    let bottom = yFor(targetLow)
                    path.addRoundedRect(
                        in: CGRect(x: 0, y: top, width: width, height: max(0, bottom - top)),
                        cornerSize: CGSize(width: 3, height: 3)
                    )
                }
                .fill(Color.white.opacity(0.06))

                Path { path in
                    var penDown = false
                    for (index, value) in values.enumerated() {
                        guard let value else {
                            penDown = false
                            continue
                        }
                        let point = CGPoint(x: xFor(index), y: yFor(value))
                        if penDown {
                            path.addLine(to: point)
                        } else {
                            path.move(to: point)
                            penDown = true
                        }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let lastIndex = values.lastIndex(where: { $0 != nil }), let last = values[lastIndex] {
                    Circle()
                        .fill(color)
                        .overlay(Circle().stroke(BIOSTheme.card, lineWidth: 2))
                        .frame(width: 7, height: 7)
                        .position(x: xFor(lastIndex), y: yFor(last))
                }
            }
        }
        .frame(height: 40)
        .accessibilityHidden(true)
    }
}

/// Seven small bars (last one highlighted) with a dashed baseline.
struct MiniBars: View {
    let values: [Double?]
    let baseline: Double?
    let color: Color

    var body: some View {
        let top = max(1, (values.compactMap { $0 } + [baseline ?? 0]).max() ?? 1) * 1.1
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(values.enumerated()), id: \.offset) { entry in
                        let value = entry.element ?? 0
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color.opacity(entry.offset == values.count - 1 ? 1 : 0.55))
                            .frame(height: max(entry.element == nil ? 0 : 2, proxy.size.height * CGFloat(value / top)))
                            .frame(maxWidth: .infinity)
                    }
                }
                if let baseline {
                    Path { path in
                        let y = proxy.size.height * (1 - CGFloat(baseline / top))
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                    .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
        }
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}

/// Segmented 7/28 days picker (shared by Körper and the detail screens).
struct RangePicker: View {
    @Binding var days: Int

    var body: some View {
        Picker("Zeitraum", selection: $days) {
            Text("7 Tage").tag(7)
            Text("28 Tage").tag(28)
        }
        .pickerStyle(.segmented)
    }
}

/// Row of legend swatches.
struct LegendItem: Identifiable {
    enum Mark {
        case line
        case dashed
        case box
        case dot
        case diamond
    }

    let id = UUID()
    let color: Color
    let text: String
    var mark: Mark = .box
    var opacity: Double = 1
}

struct LegendView: View {
    let items: [LegendItem]

    var body: some View {
        FlowLayout(spacing: 14, lineSpacing: 4) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    swatch(item)
                    Text(item.text)
                }
                .font(.caption)
                .foregroundStyle(BIOSTheme.text2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func swatch(_ item: LegendItem) -> some View {
        switch item.mark {
        case .line:
            Capsule().fill(item.color).frame(width: 14, height: 3)
        case .dashed:
            Capsule()
                .stroke(item.color, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .frame(width: 14, height: 2)
        case .box:
            RoundedRectangle(cornerRadius: 3).fill(item.color.opacity(item.opacity)).frame(width: 10, height: 10)
        case .dot:
            Circle().fill(item.color).frame(width: 7, height: 7)
        case .diamond:
            Rectangle().fill(item.color).frame(width: 6, height: 6).rotationEffect(.degrees(45))
        }
    }
}

/// Opens the iOS notification settings of BIOS.
enum SystemSettings {
    static var notificationsURL: URL? {
        URL(string: UIApplication.openNotificationSettingsURLString)
    }
}
