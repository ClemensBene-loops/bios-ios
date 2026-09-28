import SwiftUI

// Gesundheits-Score detail, below each pillar row: the pillar's parts
// (`pillars[].parts`) and for Labor (formula 3, background pillar without a
// ring segment) the groups with scores and the flagged values.

/// Below a pillar row in the detail: its parts (Routine: Krafttraining,
/// Einnahmen; Kreislauf: Ruhepuls, Aktivität, Blutdruck; unknown parts
/// generically) and for Labor the groups with scores and the values below 100
/// points (tap opens the marker in the Labor tab).
struct PillarExtras: View {
    @EnvironmentObject private var router: Router
    let pillar: HealthPillar

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(pillar.parts) { part in
                    PillarPartRow(part: part, color: pillar.color)
                }
                if !pillar.labGroups.isEmpty {
                    subheading("Gruppen")
                    ForEach(pillar.labGroups) { group in
                        LabGroupScoreRow(group: group, color: pillar.color)
                    }
                }
                if !pillar.labFlagged.isEmpty {
                    subheading("Auffällige Werte")
                    ForEach(pillar.labFlagged) { flag in
                        if let marker = flag.marker {
                            Button {
                                router.showLabor(.marker(marker))
                            } label: {
                                LabFlagScoreRow(flag: flag, showsChevron: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Öffnet den Wert im Tab Labor")
                        } else {
                            LabFlagScoreRow(flag: flag, showsChevron: false)
                        }
                    }
                }
                if pillar.isBackground {
                    Text(labNote)
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 16)
            .padding(.bottom, 12)
        }
    }

    private var hasContent: Bool {
        !pillar.parts.isEmpty || !pillar.labGroups.isEmpty || !pillar.labFlagged.isEmpty || pillar.isBackground
    }

    private func subheading(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(BIOSTheme.text3)
            .padding(.top, 2)
            .accessibilityAddTraits(.isHeader)
    }

    /// "Im Hintergrund, nicht im Ring ... 23 Werte, Stand 01.09."
    private var labNote: String {
        var text = "Im Hintergrund, nicht im Ring: zählt mit kleinem Gewicht zum Gesamtwert."
        var facts: [String] = []
        if let count = pillar.labMarkerCount {
            facts.append(count == 1 ? "1 Wert" : "\(count) Werte")
        }
        if let date = pillar.labLastDate {
            facts.append("Stand \(BIOSFormat.shortDate(date))")
        }
        if !facts.isEmpty {
            text += " " + facts.joined(separator: ", ") + "."
        }
        return text
    }
}

/// One part of a pillar: label, points (or "fehlt"), bar or strength-day
/// segments, reason and share.
struct PillarPartRow: View {
    let part: HealthPillarPart
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(part.label)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(part.score.map { BIOSFormat.number($0) } ?? "fehlt")
                    .font(part.score == nil ? Font.footnote : Font.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(part.score == nil ? BIOSTheme.text3 : color)
            }
            if let progress = part.progress {
                SegmentedProgress(done: progress.done, total: progress.total, color: color)
            } else if let score = part.score {
                PartBar(fraction: score / 100, color: color)
            }
            if let reason = part.reason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(BIOSTheme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let share = part.shareText {
                Text(share)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(part.accessibilityText)
    }
}

/// Thin bar 0...1.
private struct PartBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(color.opacity(0.8))
                    .frame(width: proxy.size.width * CGFloat(Swift.max(0, Swift.min(1, fraction))))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// Labor group with its points: "Blutfette  3 Werte    72".
struct LabGroupScoreRow: View {
    let group: HealthLabGroup
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(group.label)
                .font(.subheadline)
            if let count = group.countText {
                Text(count)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text3)
            }
            Spacer(minLength: 8)
            Text(group.score.map { BIOSFormat.number($0) } ?? "n. b.")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(scoreColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var scoreColor: Color {
        guard let score = group.score else { return BIOSTheme.text3 }
        return score < 100 ? color : BIOSTheme.text2
    }

    private var accessibilityText: String {
        var parts = [group.label]
        parts.append(group.score.map { "\(BIOSFormat.number($0)) von 100" } ?? "nicht bewertet")
        if let count = group.countText { parts.append(count) }
        return parts.joined(separator: ", ")
    }
}

/// A lab value below 100 points: name, value with unit, status and date.
struct LabFlagScoreRow: View {
    let flag: HealthLabFlag
    let showsChevron: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BIOSTheme.mid)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(flag.name)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !flag.metaLine.isEmpty {
                    Text(flag.metaLine)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(BIOSTheme.text2)
                }
            }
            Spacer(minLength: 8)
            if let value = flag.valueLine {
                Text(value)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BIOSTheme.text3)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts: [String] = [flag.name]
        if let value = flag.valueLine { parts.append(value) }
        if let status = flag.status { parts.append(status) }
        if let date = flag.date { parts.append("vom \(BIOSFormat.shortDate(date))") }
        if let score = flag.score { parts.append("\(BIOSFormat.number(score)) Punkte") }
        return parts.joined(separator: ", ")
    }

    /// Direction of the value (status word), else a neutral mark.
    private var symbol: String {
        switch (flag.status ?? "").lowercased() {
        case "hoch", "über ziel": return "arrow.up"
        case "niedrig", "unter ziel": return "arrow.down"
        default: return "exclamationmark"
        }
    }
}
