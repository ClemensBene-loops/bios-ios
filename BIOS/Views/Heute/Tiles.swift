import SwiftUI

/// Common tile frame: colored header with icon and chevron, body, footer.
/// The whole tile is a NavigationLink to its detail.
struct TileView<Body_: View>: View {
    let route: DetailRoute
    let title: String
    let icon: String
    let color: Color
    let footer: String
    let accessibilityText: String
    @ViewBuilder let content: () -> Body_

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BIOSTheme.text3)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)

                VStack(alignment: .leading, spacing: 5) {
                    content()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Text(footer)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(BIOSTheme.text3)
                    .lineLimit(2)
            }
            .foregroundStyle(BIOSTheme.text1)
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
            .background(BIOSTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(CardButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Öffnet die Details")
        .accessibilityAddTraits(.isButton)
    }
}

/// Big number with a small unit ("78 %").
struct BigValue: View {
    let value: String
    var unit: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.title.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let unit {
                Text(unit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BIOSTheme.text2)
            }
        }
    }
}

struct CaptionText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(BIOSTheme.text2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Ø **142** mg/dL" style line: grey text with bold white values.
struct KeyValueLine: View {
    let text: Text

    var body: some View {
        text
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(BIOSTheme.text2)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }
}

extension Text {
    /// Bold white value inside a grey line.
    static func value(_ string: String) -> Text {
        Text(string).fontWeight(.semibold).foregroundColor(BIOSTheme.text1)
    }
}

struct NoDataTileContent: View {
    let reason: String?

    var body: some View {
        PillView(kind: .notEvaluable, text: "keine Daten")
        if let reason {
            CaptionText(text: reason)
        }
    }
}

// MARK: - Tiles

struct VirusTile: View {
    let region: VirusRegionModel?

    var body: some View {
        TileView(
            route: .viren,
            title: "Viren \(region?.region ?? "Wien")",
            icon: "microbe",
            color: BIOSTheme.viren,
            footer: region.map { "Abwasser, \($0.sampleText)" } ?? "Abwasser",
            accessibilityText: accessibilityText
        ) {
            if let region, !region.viruses.isEmpty {
                ForEach(region.viruses) { virus in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(virus.virus)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        VirusLevelTrend(virus: virus, compact: true)
                    }
                    .frame(minHeight: 30)
                }
            } else {
                NoDataTileContent(reason: region?.reason ?? "Keine Abwasserdaten")
            }
        }
    }

    private var accessibilityText: String {
        guard let region, !region.viruses.isEmpty else { return "Viren im Abwasser, keine Daten" }
        let rows = region.viruses.map { "\($0.virus), \(VirusLevelTrend.spoken($0))" }
        return "Viren \(region.region): " + rows.joined(separator: "; ") + ". \(region.sampleText)"
    }
}

struct PollenTile: View {
    let pollen: PollenModel?
    let outlookAt: Date?

    var body: some View {
        TileView(
            route: .pollen,
            title: "Pollen",
            icon: "camera.macro",
            color: BIOSTheme.pollen,
            footer: footer,
            accessibilityText: accessibilityText
        ) {
            if let pollen, !pollen.allergens.isEmpty {
                ForEach(pollen.allergens) { allergen in
                    HStack(spacing: 6) {
                        Text(allergen.name)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 2)
                        ForEach(allergen.forecast.prefix(4)) { day in
                            PollenDot(rank: day.levelRank)
                        }
                    }
                    .frame(minHeight: 24)
                }
                HStack(spacing: 6) {
                    Spacer(minLength: 2)
                    ForEach(Array(pollen.forecastDates.prefix(4).enumerated()), id: \.offset) { entry in
                        Text(entry.element.map { BIOSFormat.weekdayShort($0) } ?? "")
                            .frame(width: 15)
                    }
                }
                .font(.caption2)
                .foregroundStyle(BIOSTheme.text3)
                if let allergy = pollen.allergy {
                    CaptionText(text: allergy.active ? "Allergie aktiv" : "Allergie nicht aktiv")
                }
            } else {
                NoDataTileContent(reason: pollen?.reason ?? "Keine Pollenvorhersage")
            }
        }
    }

    private var footer: String {
        let place = pollen?.place ?? "Heimatort"
        if let at = pollen?.generatedAt ?? outlookAt {
            return "\(place) · Vorhersage \(BIOSFormat.time(at))"
        }
        return place
    }

    private var accessibilityText: String {
        guard let pollen, !pollen.allergens.isEmpty else { return "Pollen, keine Daten" }
        let rows = pollen.allergens.map { allergen -> String in
            let days = allergen.forecast.prefix(4).map { day -> String in
                let name = day.date.map { BIOSFormat.weekdayShort($0) } ?? ""
                return "\(name) \(day.level)"
            }
            return "\(allergen.name) \(days.joined(separator: ", "))"
        }
        var text = "Pollen \(pollen.place), nächste 4 Tage: " + rows.joined(separator: "; ")
        if let allergy = pollen.allergy {
            text += allergy.active ? ". Allergie aktiv" : ". Allergie nicht aktiv"
        }
        return text
    }
}

struct GlucoseTile: View {
    let glucose: GlucoseTileModel?

    var body: some View {
        TileView(
            route: .glukose,
            title: "Glukose",
            icon: "drop",
            color: BIOSTheme.glucose,
            footer: footer,
            accessibilityText: accessibilityText
        ) {
            if let glucose {
                if glucose.evaluable {
                    BigValue(value: BIOSFormat.number(glucose.tir), unit: "%")
                    CaptionText(text: "im Zielbereich, 24 h")
                    KeyValueLine(text: Text("Ø ") + Text.value(BIOSFormat.number(glucose.mean)) + Text(" mg/dL"))
                    Sparkline(values: glucose.spark, color: BIOSTheme.glucose,
                              targetLow: glucose.targetLow, targetHigh: glucose.targetHigh)
                    if glucose.up {
                        PillView(kind: .context, text: "erhöht, Kontext")
                    }
                } else {
                    PillView(kind: .notEvaluable, text: "nicht bewertbar")
                    if let reason = glucose.reason {
                        CaptionText(text: reason)
                    }
                    Sparkline(values: glucose.spark, color: BIOSTheme.glucose,
                              targetLow: glucose.targetLow, targetHigh: glucose.targetHigh)
                }
            } else {
                NoDataTileContent(reason: "Keine Glukosedaten")
            }
        }
    }

    private var footer: String {
        guard let last = glucose?.lastTs else { return "stündlich" }
        return "Stand \(BIOSFormat.time(last)) · stündlich"
    }

    private var accessibilityText: String {
        guard let glucose else { return "Glukose, keine Daten" }
        if !glucose.evaluable {
            return "Glukose nicht bewertbar" + (glucose.reason.map { ": \($0)" } ?? "")
        }
        var text = "Glukose: \(BIOSFormat.number(glucose.tir)) Prozent im Zielbereich in 24 Stunden, Durchschnitt \(BIOSFormat.number(glucose.mean)) mg/dL"
        if glucose.up { text += ", erhöht, nur Kontext" }
        if let last = glucose.lastTs { text += ", Stand \(BIOSFormat.time(last))" }
        return text
    }
}

struct RecoveryTile: View {
    let recovery: RecoveryTileModel?

    var body: some View {
        TileView(
            route: .recovery,
            title: "Recovery",
            icon: "heart",
            color: BIOSTheme.recovery,
            footer: "\(recovery?.nightText ?? "letzte Nacht") · Whoop",
            accessibilityText: accessibilityText
        ) {
            if let recovery, !recovery.evaluable, recovery.recovery == nil {
                NoDataTileContent(reason: recovery.reason ?? "Keine Whoop-Daten")
            } else if let recovery {
                HStack(spacing: 8) {
                    RecoveryRing(value: recovery.recovery, color: recovery.zone.color, lineWidth: 5)
                        .frame(width: 30, height: 30)
                    BigValue(value: BIOSFormat.number(recovery.recovery), unit: "%")
                }
                CaptionText(text: "Recovery \(recovery.zone.word)")
                KeyValueLine(text: sleepLine(recovery))
                if let afterWake = recovery.sleep?.afterWakeText {
                    CaptionText(text: afterWake)
                }
                KeyValueLine(text: hrvLine(recovery))
            } else {
                NoDataTileContent(reason: "Keine Whoop-Daten")
            }
        }
    }

    private func sleepLine(_ recovery: RecoveryTileModel) -> Text {
        var text = Text(Image(systemName: "moon"))
        text = text + Text(" Schlaf ")
        text = text + Text.value("\(BIOSFormat.number(recovery.mainSleepHours, digits: 1)) h")
        if let sleep = recovery.sleep, sleep.hasNaps, let naps = sleep.napsH {
            text = text + Text(" + Nap ") + Text.value(SleepBreakdown.duration(naps))
        }
        return text
    }

    private func hrvLine(_ recovery: RecoveryTileModel) -> Text {
        var text = Text("HRV ")
        text = text + Text.value(BIOSFormat.number(recovery.hrv))
        text = text + Text(" ms · RP ")
        text = text + Text.value(BIOSFormat.number(recovery.rhr))
        return text
    }

    private var accessibilityText: String {
        guard let recovery else { return "Recovery, keine Daten" }
        return "Recovery \(BIOSFormat.number(recovery.recovery)) Prozent, \(recovery.zone.word). "
            + "Schlaf \(BIOSFormat.number(recovery.mainSleepHours, digits: 1)) Stunden, "
            + (recovery.sleep?.hasNaps == true ? "dazu Naps \(SleepBreakdown.duration(recovery.sleep?.napsH ?? 0)), " : "")
            + "HRV \(BIOSFormat.number(recovery.hrv)) ms, Ruhepuls \(BIOSFormat.number(recovery.rhr))"
    }
}

struct InsulinTile: View {
    let insulin: InsulinTileModel?

    var body: some View {
        TileView(
            route: .insulin,
            title: "Insulin",
            icon: "syringe",
            color: BIOSTheme.insulin,
            footer: insulin?.dayText ?? "Vortag",
            accessibilityText: accessibilityText
        ) {
            if let insulin {
                BigValue(value: BIOSFormat.number(insulin.tdd, digits: 1), unit: "U")
                CaptionText(text: captionText(insulin))
                if !insulin.tddLast7.isEmpty {
                    MiniBars(values: insulin.tddLast7, baseline: insulin.tddBaseline, color: BIOSTheme.insulin)
                }
                KeyValueLine(text: Text("pro 10 g KH ") + Text.value("\(BIOSFormat.number(insulin.per10g, digits: 2)) U"))
                if !insulin.evaluable {
                    PillView(kind: .notEvaluable, text: "nicht bewertbar")
                } else if insulin.up {
                    PillView(kind: .context, text: "erhöht, Kontext")
                }
            } else {
                NoDataTileContent(reason: "Keine Insulindaten")
            }
        }
    }

    private func captionText(_ insulin: InsulinTileModel) -> String {
        guard let delta = insulin.tddDeltaPct else { return "gesamt" }
        return "gesamt · \(BIOSFormat.signed(delta)) % zur Baseline"
    }

    private var accessibilityText: String {
        guard let insulin else { return "Insulin, keine Daten" }
        var text = "Insulin \(insulin.dayText): \(BIOSFormat.number(insulin.tdd, digits: 1)) Einheiten"
        if let delta = insulin.tddDeltaPct { text += ", \(BIOSFormat.signed(delta)) Prozent zur Baseline" }
        text += ", \(BIOSFormat.number(insulin.per10g, digits: 2)) Einheiten pro 10 g Kohlenhydrate"
        if insulin.up { text += ", erhöht, nur Kontext" }
        return text
    }
}

struct LoopTile: View {
    let loop: LoopTileModel?

    var body: some View {
        TileView(
            route: .loop,
            title: "Loop",
            icon: "arrow.triangle.2.circlepath",
            color: BIOSTheme.loop,
            footer: footer,
            accessibilityText: accessibilityText
        ) {
            if let loop, !loop.evaluable, loop.lastTs == nil {
                NoDataTileContent(reason: loop.reason ?? "Keine Nightscout-Daten")
            } else if let loop {
                BigValue(value: BIOSFormat.number(loop.iob, digits: 2), unit: "U")
                CaptionText(text: "aktives Insulin (IOB)")
                KeyValueLine(text: cobLine(loop))
                if loop.cgmStale {
                    PillView(kind: .warn, text: "CGM \(ageText(loop))")
                } else {
                    KeyValueLine(text: lastValueLine(loop))
                }
            } else {
                NoDataTileContent(reason: "Keine Nightscout-Daten")
            }
        }
    }

    private func cobLine(_ loop: LoopTileModel) -> Text {
        var text = Text("COB ")
        text = text + Text.value("\(BIOSFormat.number(loop.cob)) g")
        text = text + Text(" · Temp ")
        text = text + Text.value(BIOSFormat.number(loop.tempBasalRate, digits: 2))
        text = text + Text(" U/h")
        return text
    }

    private func lastValueLine(_ loop: LoopTileModel) -> Text {
        var text = Text(Image(systemName: "clock"))
        text = text + Text(" letzter Wert ")
        text = text + Text.value(ageText(loop))
        return text
    }

    private func ageText(_ loop: LoopTileModel) -> String {
        guard let last = loop.lastCgmTs ?? loop.lastTs else { return "unbekannt" }
        return BIOSFormat.age(since: last)
    }

    private var footer: String {
        guard let last = loop?.lastTs else { return "Nightscout" }
        return "Nightscout · Stand \(BIOSFormat.time(last))"
    }

    private var accessibilityText: String {
        guard let loop else { return "Loop, keine Daten" }
        var text = "Loop: aktives Insulin \(BIOSFormat.number(loop.iob, digits: 2)) Einheiten, COB \(BIOSFormat.number(loop.cob)) g"
        text += loop.cgmStale ? ", CGM veraltet, letzter Wert \(ageText(loop))" : ", letzter Wert \(ageText(loop))"
        return text
    }
}
