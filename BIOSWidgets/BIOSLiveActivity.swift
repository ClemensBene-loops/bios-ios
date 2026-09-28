import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// BIOS Live Activity, design A revision 2 (lock screen banner 365 x 122 pt,
// left the Gesundheits-Score ring with the six pillar colors, right the
// current information per mode, bottom the supplement status). Loop keeps its
// own activity, so the minimal island presentation is the one seen most.

struct BIOSLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BIOSActivityAttributes.self) { context in
            BIOSLockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(BIOSActivityColors.banner.opacity(0.92))
                .activitySystemActionForegroundColor(BIOSActivityColors.cream)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HealthRingView(state: state, diameter: 44, lineWidth: 3.5, numberSize: 17, showsLevel: false)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(state.nextTime ?? "–")
                            .font(.system(size: 22, weight: .semibold))
                            .monospacedDigit()
                        Text(state.hasNextMedication ? "Nächste" : "Einnahmen")
                            .font(.system(size: 10))
                            .foregroundStyle(BIOSActivityColors.text2)
                    }
                    .foregroundStyle(BIOSActivityColors.cream)
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedHeadline(state: state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedActions(state: state)
                }
            } compactLeading: {
                MarkTile(size: 22)
            } compactTrailing: {
                CompactTrailing(state: state)
            } minimal: {
                MinimalMark(attention: state.attention)
            }
            .keylineTint(state.attention.color)
        }
    }
}

// MARK: - Lock screen banner

struct BIOSLockScreenView: View {
    let state: BIOSActivityState
    var isStale = false

    var body: some View {
        HStack(spacing: 0) {
            ScoreColumn(state: state)
                .frame(width: 110)
            Rectangle()
                .fill(BIOSActivityColors.cream.opacity(0.18))
                .frame(width: 0.55, height: 91)
            InfoColumn(state: state, isStale: isStale)
                .padding(.leading, 16)
                .padding(.trailing, 5)
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 98)
        .foregroundStyle(BIOSActivityColors.cream)
    }
}

private struct ScoreColumn: View {
    let state: BIOSActivityState

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                MarkTile(size: 17)
                Text("BIOS")
                    .font(.system(size: 11, weight: .semibold))
            }
            HealthRingView(state: state, diameter: 56, lineWidth: 4.5, numberSize: 27, showsLevel: true)
                .frame(width: 62, height: 62)
            Text("Gesundheit")
                .font(.system(size: 10))
                .foregroundStyle(BIOSActivityColors.text2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gesundheit \(state.healthScoreText), \(state.healthLevelText)")
    }
}

private struct InfoColumn: View {
    let state: BIOSActivityState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch state.mode {
            case .normal:
                contextLine(state.nextLabel, color: state.nextMedication?.overdue == true ? BIOSActivityColors.attention : BIOSActivityColors.text2)
                Text(state.medicationText)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let time = state.nextTime, state.hasNextMedication {
                    Text(time)
                        .font(.system(size: 26, weight: .semibold))
                        .monospacedDigit()
                }
            case .infection:
                contextLine(infectionContext, color: BIOSActivityColors.attention, weight: .semibold)
                Text("Infekt-Score \(state.infectionScore.map(String.init) ?? "–")")
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                medicationRow
            case .temperature:
                contextLine(temperatureContext, color: BIOSActivityColors.text2)
                HStack(alignment: .firstTextBaseline) {
                    Text(state.temperatureText ?? "–")
                        .font(.system(size: 26, weight: .semibold))
                        .monospacedDigit()
                    Spacer(minLength: 4)
                    Text("! " + state.temperatureLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BIOSActivityColors.attention)
                }
                medicationRow
            }
            Spacer(minLength: 0)
            if let supplements = state.supplementsText {
                HStack {
                    Text("Supplements")
                        .font(.system(size: 12))
                        .foregroundStyle(BIOSActivityColors.text2)
                    Spacer(minLength: 4)
                    Text(supplements)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isStale ? 0.7 : 1)
    }

    private var infectionContext: String {
        "! Infekt" + (state.infectionDay.map { " · Tag \($0)" } ?? "")
    }

    private var temperatureContext: String {
        "Temperatur" + (state.temperatureTime.map { " · \($0)" } ?? "")
    }

    private var medicationRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(state.medicationText)
                .font(.system(size: 12))
                .foregroundStyle(BIOSActivityColors.text2)
                .lineLimit(1)
            Spacer(minLength: 4)
            if state.hasNextMedication, let time = state.nextTime {
                Text(time)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(state.nextMedication?.overdue == true ? BIOSActivityColors.attention : BIOSActivityColors.cream)
            }
        }
    }

    private func contextLine(_ text: String, color: Color, weight: Font.Weight = .regular) -> some View {
        Text(text)
            .font(.system(size: 11, weight: weight))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

// MARK: - Health ring (six pillar segments)

/// Mini ring: the shared six-arc ring (Shared/HealthRing.swift) with
/// pillar-tinted tracks, the score and the level word in the middle.
/// `diameter` is the center line circle of the stroke.
struct HealthRingView: View {
    let state: BIOSActivityState
    let diameter: CGFloat
    let lineWidth: CGFloat
    let numberSize: CGFloat
    let showsLevel: Bool

    var body: some View {
        ZStack {
            HealthSegmentRing(values: state.pillarsMini ?? [], radius: diameter / 2, lineWidth: lineWidth, track: .tinted)

            VStack(spacing: -3) {
                Text(state.healthScoreText)
                    .font(.system(size: numberSize, weight: .semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if showsLevel {
                    Text(state.healthLevelText)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(state.healthLevelColor)
                }
            }
            .foregroundStyle(BIOSActivityColors.cream)
            .frame(width: diameter - lineWidth * 2 - 2)
        }
    }
}

// MARK: - Dynamic Island parts

/// Round tile with the cream "b" on forest green.
struct MarkTile: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(BIOSActivityColors.forest)
            .frame(width: size, height: size)
            .overlay {
                Image("BIOSMark")
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: size * 0.62)
            }
            .accessibilityHidden(true)
    }
}

/// Minimal presentation next to Loop: round "b" mark plus a status dot.
struct MinimalMark: View {
    let attention: BIOSActivityAttention

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(BIOSActivityColors.forest)
                .frame(width: 24, height: 24)
                .overlay {
                    Image("BIOSMark")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 14)
                }
            Circle()
                .fill(attention.color)
                .frame(width: 9, height: 9)
                .overlay {
                    if attention != .ok {
                        Text("!")
                            .font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(Color.black)
                    }
                }
                .offset(x: 2, y: -2)
        }
        .accessibilityLabel(attention == .ok ? "BIOS, alles im Rahmen" : "BIOS, Hinweis")
    }
}

/// Compact trailing: the most relevant number of the mode.
private struct CompactTrailing: View {
    let state: BIOSActivityState

    var body: some View {
        Group {
            switch state.mode {
            case .infection:
                Text("! \(state.infectionScore.map(String.init) ?? "–")")
                    .foregroundStyle(BIOSActivityColors.attention)
            case .temperature:
                Text(state.temperatureShortText ?? "–")
                    .foregroundStyle(BIOSActivityColors.attention)
            case .normal:
                if state.healthScore != nil {
                    Text(state.healthScoreText)
                        .foregroundStyle(state.healthLevelColor)
                } else {
                    Text(state.nextTime ?? "–")
                        .foregroundStyle(BIOSActivityColors.cream)
                }
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
    }
}

private struct ExpandedHeadline: View {
    let state: BIOSActivityState

    var body: some View {
        VStack(spacing: 1) {
            switch state.mode {
            case .normal:
                Text(state.nextLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(BIOSActivityColors.text2)
                Text(state.medicationText)
                    .font(.system(size: 16, weight: .semibold))
            case .infection:
                Text("! Infekt" + (state.infectionDay.map { " · Tag \($0)" } ?? ""))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BIOSActivityColors.attention)
                Text("Infekt-Score \(state.infectionScore.map(String.init) ?? "–")")
                    .font(.system(size: 16, weight: .semibold))
            case .temperature:
                Text("Temperatur" + (state.temperatureTime.map { " · \($0)" } ?? ""))
                    .font(.system(size: 11))
                    .foregroundStyle(BIOSActivityColors.text2)
                Text((state.temperatureText ?? "–") + " · " + state.temperatureLabel)
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .foregroundStyle(BIOSActivityColors.cream)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

/// Bottom row: medication with "Genommen" / "Später" (LiveActivityIntent,
/// runs in the app), supplements status.
private struct ExpandedActions: View {
    let state: BIOSActivityState

    var body: some View {
        VStack(spacing: 6) {
            if state.mode != .normal {
                HStack {
                    Text(state.medicationText)
                        .font(.system(size: 12))
                        .foregroundStyle(BIOSActivityColors.text2)
                    Spacer(minLength: 4)
                    if state.hasNextMedication, let time = state.nextTime {
                        Text(time)
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
            HStack(spacing: 8) {
                if let name = state.nextMedication?.name {
                    let id = state.nextMedication?.id
                    Button(intent: LiveActivityTakenIntent(medicationID: id, medicationName: name)) {
                        Label("Genommen", systemImage: "checkmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .tint(BIOSActivityColors.positive)
                    Button(intent: LiveActivityLaterIntent(medicationID: id, medicationName: name)) {
                        Label("Später", systemImage: "clock")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .tint(BIOSActivityColors.text2)
                }
                Spacer(minLength: 4)
                if let supplements = state.supplementsText {
                    Text("Supplements " + supplements)
                        .font(.system(size: 12))
                        .foregroundStyle(BIOSActivityColors.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .foregroundStyle(BIOSActivityColors.cream)
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 4)
    }
}

// MARK: - Previews (illustrative values only)

#Preview("Sperrbildschirm", as: .content, using: BIOSActivityAttributes()) {
    BIOSLiveActivity()
} contentStates: {
    BIOSActivityState.preview
    BIOSActivityState.previewInfection
    BIOSActivityState.previewTemperature
}

extension BIOSActivityState {
    static var previewInfection: BIOSActivityState {
        var state = BIOSActivityState.preview
        state.mode = .infection
        state.infectionScore = 69
        state.infectionDay = 4
        state.infectionKind = "infekt"
        return state
    }

    static var previewTemperature: BIOSActivityState {
        var state = BIOSActivityState.preview
        state.mode = .temperature
        state.temperature = 37.8
        state.temperatureAt = "2026-01-01T08:05:00+01:00"
        state.temperatureHigh = true
        return state
    }
}
