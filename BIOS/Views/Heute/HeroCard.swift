import SwiftUI

/// Hero card "Infekt-Check": recovery ring, status symbol + headline, subline,
/// deviation chips, context line (glucose/insulin, rule A: context only),
/// "not evaluable" line and the baseline footer. Tapping opens the detail.
struct HeroCard: View {
    let infection: InfectionModel?
    let glucoseTile: GlucoseTileModel?

    var body: some View {
        NavigationLink(value: DetailRoute.infekt) {
            content
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Öffnet den Infekt-Check")
    }

    @ViewBuilder
    private var content: some View {
        let status = infection?.status ?? .unknown
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                EyebrowText(text: "Infekt-Check")
                Spacer()
                if let checked = infection?.checkedAt {
                    Text(BIOSFormat.relative(checked))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(BIOSTheme.text3)
                }
            }

            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    RecoveryRing(value: infection?.recovery, color: zone.color, lineWidth: 11)
                        .frame(width: 112, height: 112)
                    VStack(spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text(infection?.recovery.map { BIOSFormat.number($0) } ?? "n. v.")
                                .font(.title.bold())
                                .monospacedDigit()
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                            if infection?.recovery != nil {
                                Text("%")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BIOSTheme.text2)
                            }
                        }
                        Text("Recovery")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(BIOSTheme.text2)
                    }
                    .frame(width: 90)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: status.symbol)
                            .foregroundStyle(status.tint)
                        Text(infection?.headline ?? "Noch keine Daten")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.title3.bold())
                    if let subline = infection?.subline {
                        Text(subline)
                            .font(.subheadline)
                            .foregroundStyle(BIOSTheme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if infection == nil {
                        Text("Wird vom Server geladen")
                            .font(.subheadline)
                            .foregroundStyle(BIOSTheme.text2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 12)

            if let chips = infection?.chips, !chips.isEmpty {
                FlowLayout(spacing: 7, lineSpacing: 7) {
                    ForEach(chips) { chip in
                        ChipView(chip: chip, status: status)
                    }
                }
                .padding(.top, 14)
            }

            if let infection, infection.resistUp {
                ContextLine(
                    symbol: "drop",
                    title: infection.contextText ?? "dazu Glukose/Insulinbedarf erhöht",
                    detail: "Kontext zum Muster, löst allein keinen Alarm aus",
                    style: .context
                )
                .padding(.top, 12)
            }

            if let note = infection?.confounderNote {
                ContextLine(
                    symbol: "wineglass",
                    title: note,
                    detail: nil,
                    style: .neutral
                )
                .padding(.top, 12)
            }

            if let reason = glucoseNotEvaluableReason {
                ContextLine(
                    symbol: "circle.dashed",
                    title: "Glukose heute nicht bewertbar",
                    detail: reason,
                    style: .neutral
                )
                .padding(.top, 12)
            }

            Rectangle()
                .fill(BIOSTheme.separator)
                .frame(height: 0.5)
                .padding(.top, 14)
            HStack {
                Text(infection?.baseline?.footer ?? "Baseline 28 Tage")
                    .lineLimit(2)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
            }
            .font(.caption)
            .foregroundStyle(BIOSTheme.text3)
            .padding(.top, 12)
        }
        .foregroundStyle(BIOSTheme.text1)
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: status.glow, location: 0),
                            .init(color: BIOSTheme.card, location: 0.55),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .background(BIOSTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var zone: BIOSZone {
        infection?.recoveryZone ?? .none
    }

    private var glucoseNotEvaluableReason: String? {
        if let signal = infection?.glucose, !signal.evaluable {
            return signal.reason ?? "Keine ausreichenden Glukosedaten"
        }
        return nil
    }

    private var accessibilityText: String {
        guard let infection else { return "Infekt-Check, noch keine Daten" }
        var parts = ["Infekt-Check: \(infection.headline)"]
        if let recovery = infection.recovery {
            parts.append("Recovery \(BIOSFormat.number(recovery)) Prozent, \(zone.word)")
        }
        if let subline = infection.subline { parts.append(subline) }
        if infection.resistUp { parts.append(infection.contextText ?? "Dazu Glukose/Insulinbedarf erhöht") }
        if let note = infection.confounderNote { parts.append(note) }
        if let reason = glucoseNotEvaluableReason { parts.append("Glukose nicht bewertbar: \(reason)") }
        return parts.joined(separator: ". ")
    }
}

/// Tinted info line inside a card (context = indigo, neutral = outlined).
struct ContextLine: View {
    enum Style {
        case context
        case neutral
    }

    let symbol: String
    let title: String
    let detail: String?
    let style: Style

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(BIOSTheme.text2)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(style == .context ? Color(hex: 0xC9D1FF) : BIOSTheme.text2)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(style == .context ? BIOSTheme.context.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(style == .neutral ? 0.14 : 0), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Press feedback for tappable cards (slight scale), no blue tint.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
